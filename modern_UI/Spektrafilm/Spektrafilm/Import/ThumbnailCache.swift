//  ThumbnailCache.swift — embedded previews until a developed print lands;
//  the developed thumbnail then serves every navigator surface and survives
//  memory eviction/relaunch in the app's existing disk cache.

import AppKit
import ImageIO

private struct ThumbnailKey: Hashable, Sendable {
    let url: URL
    let maxPixel: Int
}

/// Lock-protected storage, separate from the asynchronous work scheduler so
/// an arena eviction can drop its reference synchronously from the callback.
private final class ThumbnailStorage: @unchecked Sendable {
    private final class Slot: @unchecked Sendable {
        var handle: MemoryArena.Handle?
    }

    private struct Entry {
        let image: CGImage
        let bytes: Int
        var value: CacheValue
        let slot: Slot
    }

    private let lock = NSRecursiveLock()
    private let arena: MemoryArena
    private let byteLimit: Int
    private var entries: [ThumbnailKey: Entry] = [:]
    /// A rendered thumbnail replaces every embedded-preview size for that URL,
    /// which is the behavior the old URL-only cache had.
    private var processed: [URL: ThumbnailKey] = [:]
    private var total = 0
    private var clock = 0.0

    init(arena: MemoryArena, byteLimit: Int) {
        self.arena = arena
        self.byteLimit = max(0, byteLimit)
    }

    func image(for key: ThumbnailKey) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        let lookup = processed[key.url] ?? key
        guard var entry = entries[lookup] else { return nil }
        entry.value.hit(at: Date().timeIntervalSinceReferenceDate)
        entries[lookup] = entry
        if let handle = entry.slot.handle { arena.touch(handle) }
        return entry.image
    }

    @discardableResult
    func put(_ image: CGImage, key: ThumbnailKey, costMs: Double,
             replacingURL: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if !replacingURL, processed[key.url] != nil { return true }
        if replacingURL {
            let old = entries.keys.filter { $0.url == key.url }
            for oldKey in old { removeLocked(oldKey, releaseArena: true) }
            processed[key.url] = nil
        } else {
            removeLocked(key, releaseArena: true)
        }

        let bytes = max(1, image.bytesPerRow * image.height)
        let slot = Slot()
        let admitted = arena.admitCache(bytes: bytes, kind: "thumbnails", costMs: costMs,
                                        evict: { [weak self] in
                                            self?.drop(key, matching: slot)
                                        })
        guard let admitted else { return false }
        slot.handle = admitted
        entries[key] = Entry(image: image, bytes: bytes,
                             value: CacheValue(costMs: costMs, bytes: bytes,
                                               lastUsed: Date().timeIntervalSinceReferenceDate),
                             slot: slot)
        total += bytes
        if replacingURL { processed[key.url] = key }
        trimLocked()
        return true
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        for entry in entries.values {
            if let handle = entry.slot.handle { arena.release(handle) }
        }
        entries.removeAll()
        processed.removeAll()
        total = 0
        clock = 0
    }

    var count: Int { lock.withLock { entries.count } }
    var bytes: Int { lock.withLock { total } }

    private func drop(_ key: ThumbnailKey, matching slot: Slot) {
        lock.lock()
        defer { lock.unlock() }
        guard entries[key]?.slot === slot else { return }
        removeLocked(key, releaseArena: false)
    }

    private func trimLocked() {
        while total > byteLimit {
            guard let key = entries.min(by: {
                let lp = $0.value.value.priority(clock: clock)
                let rp = $1.value.value.priority(clock: clock)
                return lp == rp ? $0.value.value.lastUsed < $1.value.value.lastUsed : lp < rp
            })?.key else { break }
            clock = max(clock, entries[key]!.value.priority(clock: clock))
            removeLocked(key, releaseArena: true)
        }
    }

    private func removeLocked(_ key: ThumbnailKey, releaseArena: Bool) {
        guard let entry = entries.removeValue(forKey: key) else { return }
        if releaseArena, let handle = entry.slot.handle { arena.release(handle) }
        total -= entry.bytes
        if processed[key.url] == key { processed[key.url] = nil }
    }
}

final class ThumbnailCache: @unchecked Sendable {
    typealias Decoder = @Sendable (URL, Int) async -> CGImage?

    private struct Decoded: Sendable {
        let image: CGImage
        let costMs: Double
    }

    static let shared = ThumbnailCache(arena: .shared)

    private let storage: ThumbnailStorage
    private let decode: Decoder
    private var diskCache: DiskCacheStore?
    private var diskWriteTask: Task<Void, Never>?
    private let lock = NSLock()
    private var inFlight: [ThumbnailKey: Task<Decoded?, Never>] = [:]
    private var generation = 0
    private var revision: [URL: Int] = [:]

    init(arena: MemoryArena = MemoryArena(),
         byteLimit: Int = 256_000_000,
         diskCache: DiskCacheStore? = nil,
         decoder: @escaping Decoder = ThumbnailCache.decodeEmbedded) {
        storage = ThumbnailStorage(arena: arena, byteLimit: byteLimit)
        self.diskCache = diskCache
        decode = decoder
    }

    func useDiskCache(_ cache: DiskCacheStore?) {
        lock.withLock { diskCache = cache }
    }

    func thumbnail(for url: URL, maxPixel: Int = 320) async -> CGImage? {
        let key = ThumbnailKey(url: url, maxPixel: max(1, maxPixel))
        if let cached = storage.image(for: key) { return cached }

        // Most filmstrip frames are unedited. Avoid a sidecar identity scan
        // and SQLite lookup until there is an edit record for this path.
        if FileManager.default.fileExists(atPath: Sidecar.url(for: url).path),
           let diskCache = lock.withLock({ diskCache }),
           let cacheKey = Self.cacheKey(for: url, edit: Sidecar.load(for: url)) {
            let diskRevision = lock.withLock { revision[url] ?? 0 }
            let disk = try? await diskCache.load(cacheKey)
            let image = disk.flatMap { Self.image(from: $0) }
            if let image {
                let stillCurrent = lock.withLock { (revision[url] ?? 0) == diskRevision }
                if stillCurrent {
                    storage.put(image, key: ThumbnailKey(url: url, maxPixel: max(image.width, image.height)),
                                costMs: 0, replacingURL: true)
                    return image
                }
                if let latest = storage.image(for: key) { return latest }
            }
        }

        let request: (task: Task<Decoded?, Never>, generation: Int, revision: Int) =
            lock.withLock {
                if let task = inFlight[key] {
                    return (task, generation, revision[url] ?? 0)
                }
                let generation = generation
                let revision = revision[url] ?? 0
                let decode = decode
                let task = Task<Decoded?, Never>.detached(priority: .utility) {
                    guard !Task.isCancelled else { return nil }
                    let start = Date()
                    guard let image = await decode(url, key.maxPixel) else { return nil }
                    return Decoded(image: image,
                                   costMs: Date().timeIntervalSince(start) * 1000)
                }
                inFlight[key] = task
                return (task, generation, revision)
            }

        let decoded = await request.task.value
        let accepted = lock.withLock {
            guard generation == request.generation,
                  (revision[url] ?? 0) == request.revision else { return false }
            inFlight[key] = nil
            return true
        }
        guard accepted else { return nil }
        guard let decoded else { return nil }
        storage.put(decoded.image, key: key, costMs: decoded.costMs,
                    replacingURL: false)
        return decoded.image
    }

    /// Replace the embedded preview with a rendered one. The rendered size is
    /// the key's size, and the replacement wins for every requested size for
    /// that URL until it is evicted.
    /// Reserve a generation before the GPU readback starts. If two edits land
    /// quickly, the slower *older* readback must not replace the newer one.
    func beginRenderedThumbnail(for url: URL) -> Int {
        lock.withLock {
            revision[url, default: 0] += 1
            return revision[url]!
        }
    }

    func store(_ image: CGImage, for url: URL, edit: Sidecar? = nil, ticket: Int? = nil) {
        let result: (accepted: Bool, stale: [Task<Decoded?, Never>]) = lock.withLock {
            if let ticket, ticket != revision[url, default: 0] { return (false, []) }
            revision[url, default: 0] += 1
            let keys = inFlight.keys.filter { $0.url == url }
            let tasks = keys.compactMap { inFlight.removeValue(forKey: $0) }
            return (true, tasks)
        }
        guard result.accepted else { return }
        result.stale.forEach { $0.cancel() }
        let key = ThumbnailKey(url: url, maxPixel: max(1, image.width, image.height))
        storage.put(image, key: key, costMs: 0, replacingURL: true)
        if let edit, let cacheKey = Self.cacheKey(for: url, edit: edit),
           let diskCache = lock.withLock({ diskCache }) {
            lock.withLock {
                let previous = diskWriteTask
                diskWriteTask = Task.detached(priority: .utility) {
                    await previous?.value
                    guard let data = Self.jpegData(for: image) else { return }
                    try? await diskCache.store(key: cacheKey, data: data,
                                               width: image.width, height: image.height,
                                               format: "jpeg", costMs: 50)
                }
            }
        }
    }

    /// A new folder is a new generation. Detached work from the old one may
    /// finish, but it cannot repopulate the cache or replace a newer result.
    func clear() {
        let stale = lock.withLock {
            generation &+= 1
            revision.removeAll()
            let tasks = Array(inFlight.values)
            inFlight.removeAll()
            return tasks
        }
        stale.forEach { $0.cancel() }
        storage.removeAll()
    }

    var cachedCount: Int { storage.count }
    var cachedBytes: Int { storage.bytes }

    /// Test seam: wait for writes to the shared store before making a fresh cache.
    func finishPendingDiskWrites() async {
        let task = lock.withLock { diskWriteTask }
        await task?.value
    }

    private static func decodeEmbedded(_ url: URL, _ maxPixel: Int) async -> CGImage? {
        if HalfFramePair.isPair(url) { return PairComposer.thumbnail(url, maxPixel: maxPixel) }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCache: false,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// Only pixel-affecting fields belong here. The sidecar's state, solve
    /// readout and source bookkeeping can change after the render without
    /// changing the thumbnail.
    private struct EditFingerprint: Encodable {
        let decode: DecodeSettings
        let params: FilmParams
        let adjustments: Adjustments
        let geometry: Geometry
        let masks: [EditMask]
    }

    private static func cacheKey(for url: URL, edit: Sidecar?) -> CacheKey? {
        guard let edit else { return nil }
        let state = EditFingerprint(decode: edit.decode, params: edit.params,
                                    adjustments: edit.adjustments, geometry: edit.geometry,
                                    masks: edit.masks)
        return CacheKey(kind: .thumbnail,
                        sourceIdentity: CacheKey.sourceIdentity(for: url),
                        configuration: CacheKey.encodedConfiguration(state),
                        engineVersion: "developed-thumbnail-v1")
    }

    private static func image(from payload: DiskCachePayload) -> CGImage? {
        guard payload.kind == .thumbnail, payload.format == "jpeg",
              let source = CGImageSourceCreateWithData(payload.data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == payload.width, image.height == payload.height else { return nil }
        return image
    }

    private static func jpegData(for image: CGImage) -> Data? {
        guard let bytes = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(bytes, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return bytes as Data
    }
}
