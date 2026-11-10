import Foundation

/// Originals and edit intent are durable. GPU results and undo history are not.
struct MobileLibraryStore {
    struct Snapshot: Codable {
        var version = 1
        var photos: [MobilePhoto]
        var selection: UUID?
    }
    let directory: URL
    private var manifest: URL { directory.appendingPathComponent("library.json") }

    func load() throws -> Snapshot {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: manifest.path) else { return Snapshot(photos: []) }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: manifest))
        guard snapshot.version == 1 else { throw MobileFailure.message(TDetached("That library version is not supported; originals and records are safe.", "图库版本不受支持，原文件与记录已保留。", "圖庫版本不受支援，原檔案與記錄已保留。")) }
        try validate(snapshot)
        return snapshot
    }
    func write(_ snapshot: Snapshot) throws {
        try validate(snapshot)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: manifest, options: .atomic)
    }
    private func validate(_ snapshot: Snapshot) throws {
        guard Set(snapshot.photos.map(\.id)).count == snapshot.photos.count,
              Set(snapshot.photos.map(\.filename)).count == snapshot.photos.count,
              snapshot.photos.allSatisfy({ photo in
                  !photo.filename.isEmpty && photo.filename != "." && photo.filename != ".." &&
                  photo.filename != "library.json" && !photo.filename.contains("/") && !photo.filename.contains("\\") &&
                  photo.sourceAspect.isFinite && photo.sourceAspect > 0 &&
                  photo.sourceMegapixels.isFinite && photo.sourceMegapixels >= 0
              }) else { throw MobileFailure.message(TDetached("The library record is invalid; originals and records are safe.", "图库记录无效，原文件与记录已保留。", "圖庫記錄無效，原檔案與記錄已保留。")) }
    }
}
