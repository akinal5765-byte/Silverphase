import CryptoKit
import Foundation
import ImageIO
import Metal
import XCTest

/// Selected private photographs are external fixtures, never bundled or renamed
/// as the historical Nikon/A7 III oracle. Missing opt-in skips; a wrong file,
/// checksum, timeout or render is a failure once this gate is requested.
@MainActor
final class RealPhotoValidationTests: XCTestCase {
    private struct Manifest: Decodable { var fixtures: [Fixture] }
    private struct Fixture: Decodable {
        var role: String
        var relative_path: String
        var sha256: String
        var width: Int
        var height: Int
    }
    private func digest(_ url: URL) throws -> String {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var hash = SHA256()
        while let bytes = try input.read(upToCount: 1024 * 1024), !bytes.isEmpty { hash.update(data: bytes) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private func fixture(_ role: String) throws -> (source: URL, copy: URL, record: Fixture) {
        guard let root = ProcessInfo.processInfo.environment["SILVERPHASE_VALIDATION_PHOTOS"] else {
            throw XCTSkip("Set SILVERPHASE_VALIDATION_PHOTOS to run the selected real-photo gate")
        }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let selectedManifest = ProcessInfo.processInfo.environment["SILVERPHASE_VALIDATION_MANIFEST"]
            .map { URL(fileURLWithPath: $0) } ?? repo.appending(path: "modern_UI/Spektrafilm/SpektrafilmTests/Fixtures/validation-manifest.json")
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: selectedManifest))
        let record = try XCTUnwrap(manifest.fixtures.first { $0.role == role })
        let source = URL(fileURLWithPath: root).appending(path: record.relative_path)
        XCTAssertEqual(try digest(source), record.sha256, "fixture changed; update the reviewed manifest explicitly")
        let properties = try XCTUnwrap(CGImageSourceCreateWithURL(source as CFURL, nil))
        let metadata = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(properties, 0, nil) as? [CFString: Any])
        XCTAssertEqual(metadata[kCGImagePropertyPixelWidth] as? Int, record.width)
        XCTAssertEqual(metadata[kCGImagePropertyPixelHeight] as? Int, record.height)
        let directory = FileManager.default.temporaryDirectory.appending(path: "silverphase-real-validation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let copy = directory.appending(path: source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: copy)
        print("real-photo fixture: \(role), \(record.width)x\(record.height), \(record.sha256)")
        return (source, copy, record)
    }
    private func wait(_ what: String, diagnostics: () -> String = { "" }, _ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(180)
        while !predicate() {
            guard Date() < deadline else { XCTFail("timed out: \(what) \(diagnostics())"); throw CocoaError(.coderInvalidValue) }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
    private func develop(_ role: String) async throws -> (Session, URL, URL, Fixture) {
        let (source, copy, record) = try fixture(role)
        let session = Session()
        session.renderer.reduceMotion = { true }
        session.beginBatchExport() // export owns the full render; no competing canvas job
        session.open(urls: [copy])
        try await wait("decode and engine warmup") { session.decoded != nil && session.serviceReady }
        var parameters = session.params
        parameters.grainActive = false
        parameters.glareActive = false
        session.params = parameters
        session.requestPrint()
        try await wait("first print", diagnostics: { "status=\(session.status), error=\(session.lastError ?? "none"), busy=\(session.busy), pending=\(session.scheduler.pending), session=\(session.serviceSessionIDForExport ?? "none"), live=\(session.renderer.live != nil)" }) {
            !session.busy && !session.scheduler.pending && session.frameStates[copy] == .processed && session.renderer.live != nil
        }
        XCTAssertEqual(session.renderCore, "native-metal")
        return (session, source, copy, record)
    }
    private func pixels(_ texture: MTLTexture, session: Session) throws -> [UInt16] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Unorm,
            width: texture.width, height: texture.height, mipmapped: false)
        descriptor.storageMode = .shared
        let destination = try XCTUnwrap(session.renderer.device.makeTexture(descriptor: descriptor))
        let command = try XCTUnwrap(session.renderer.queue.makeCommandBuffer())
        let blit = try XCTUnwrap(command.makeBlitCommandEncoder())
        blit.copy(from: texture, to: destination)
        blit.endEncoding(); command.commit(); command.waitUntilCompleted()
        XCTAssertEqual(command.status, .completed)
        var values = [UInt16](repeating: 0, count: texture.width * texture.height * 4)
        values.withUnsafeMutableBytes {
            destination.getBytes($0.baseAddress!, bytesPerRow: texture.width * 8,
                                 from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
        }
        return values
    }
    private func export(_ session: Session, source: URL, format: ExportFormat) async throws -> URL {
        var recipe = ExportRecipe()
        recipe.format = format
        recipe.folder = .fixed(path: source.deletingLastPathComponent().appending(path: "exports").path)
        recipe.subfolder = ""
        let size = try XCTUnwrap(session.decoded?.pixelSize)
        let context = NamingRule.Context(originalName: source.deletingPathExtension().lastPathComponent,
            filmStock: session.params.filmStock, printStock: session.params.printStock,
            pixelSize: size, counter: 1, date: Date())
        let result = try await Exporter.export(session: session, recipe: recipe, context: context,
            sessionID: try XCTUnwrap(session.serviceSessionIDForExport))
        guard case .wrote(let files, _, _) = result else { throw CocoaError(.fileWriteUnknown) }
        return try XCTUnwrap(files.first)
    }
    private func validate(_ role: String, exportFiles: Bool) async throws {
        let (session, original, copy, record) = try await develop(role)
        // The canvas owns the active print. An evictable cache may refuse it under
        // memory pressure, so cache retention is not the completion contract.
        let before = try pixels(XCTUnwrap(session.renderer.live), session: session)
        let prior = session.renderer.live
        var changed = session.params
        changed.printBrightnessStops += 0.7
        session.params = changed
        try await wait("exposure edit") { session.renderer.live !== prior && !session.busy && !session.scheduler.pending }
        let edited = try pixels(XCTUnwrap(session.renderer.live), session: session)
        XCTAssertFalse(before.elementsEqual(edited), "an exposure edit must reach the actual pixels")
        let next = session.renderer.live
        changed.printBrightnessStops -= 0.7
        session.params = changed
        try await wait("exposure reset") { session.renderer.live !== next && !session.busy && !session.scheduler.pending }
        let reset = try pixels(XCTUnwrap(session.renderer.live), session: session)
        XCTAssertTrue(before.elementsEqual(reset), "deterministic reset must recover the original render")
        if exportFiles {
            for format in [ExportFormat.tiff, .jpeg] {
                let file = try await export(session, source: copy, format: format)
                let source = try XCTUnwrap(CGImageSourceCreateWithURL(file as CFURL, nil))
                let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
                let size = try XCTUnwrap(session.decoded?.pixelSize)
                XCTAssertEqual(image.width, Int(size.width))
                XCTAssertEqual(image.height, Int(size.height))
                XCTAssertEqual(image.bitsPerComponent, format == .tiff ? 16 : 8)
                let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
                XCTAssertNotNil(properties[kCGImagePropertyProfileName], "finished RGB export must have an ICC profile")
                XCTAssertGreaterThan(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, 0)
            }
        }
        XCTAssertEqual(try digest(original), record.sha256, "validation must never edit the source photo")
    }
    func testStandardRAWReprintsAndExportsFullSizeTIFFAndJPEG() async throws {
        try await validate("raw-standard", exportFiles: true)
    }
    func testHighResolutionRAWReprintsAndResetsExactly() async throws {
        try await validate("raw-high-resolution", exportFiles: false)
    }
    func testEncodedJPEGReprintsAndResetsExactly() async throws {
        try await validate("encoded-jpeg", exportFiles: false)
    }
    func testEncodedTIFFReprintsAndResetsExactly() async throws {
        try await validate("encoded-tiff", exportFiles: false)
    }
}
