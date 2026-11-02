import Foundation
import CryptoKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// The filename binds a disposable preview to the exact edit that produced it.
/// A pasted/undone edit never displays another recipe's finished photograph.
enum MobileLibraryPreview {
    private static let lock = NSLock()
    private struct Key: Encodable {
        let recipe: [String: ParamValue]
        let geometry: MobileGeometry
        let cropRemapsEffects: Bool
        let diBlueCompensation: Bool
    }
    static func url(photo: MobilePhoto, cropRemapsEffects: Bool, diBlueCompensation: Bool) -> URL {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let key = Key(recipe: photo.recipe, geometry: photo.geometry, cropRemapsEffects: cropRemapsEffects, diBlueCompensation: diBlueCompensation)
        let digest = SHA256.hash(data: (try? encoder.encode(key)) ?? Data()).map { String(format: "%02x", $0) }.joined()
        return URL.cachesDirectory.appendingPathComponent("Silverphase-Previews", isDirectory: true)
            .appendingPathComponent(photo.id.uuidString + "-" + digest + ".jpg")
    }
    static func remove(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        let folder = URL.cachesDirectory.appendingPathComponent("Silverphase-Previews", isDirectory: true)
        for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            where file.lastPathComponent.hasPrefix(id.uuidString + "-") {
            try? FileManager.default.removeItem(at: file)
        }
    }
    static func write(_ image: CGImage, to url: URL, source: URL) {
        lock.lock(); defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        autoreleasepool {
            do {
                let folder = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let scale = min(1, 384.0 / Double(max(image.width, image.height)))
                let input = CIImage(cgImage: image).transformed(by: .init(scaleX: scale, y: scale))
                let context = CIContext(options: [.cacheIntermediates: false])
                defer { context.clearCaches() }
                guard let small = context.createCGImage(input, from: input.extent, format: .RGBA8, colorSpace: image.colorSpace) else { return }
                let data = NSMutableData()
                guard let writer = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return }
                CGImageDestinationAddImage(writer, small, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
                guard CGImageDestinationFinalize(writer) else { return }
                try (data as Data).write(to: url, options: .atomic)
                for old in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                    where old != url && old.lastPathComponent.hasPrefix(String(url.lastPathComponent.prefix(36)) + "-") {
                    try? FileManager.default.removeItem(at: old)
                }
            } catch { /* Disposable cache; source and recipe remain authoritative. */ }
        }
    }
}
