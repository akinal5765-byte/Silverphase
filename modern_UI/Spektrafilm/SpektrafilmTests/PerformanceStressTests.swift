import Foundation
import XCTest

@MainActor
final class PerformanceStressTests: XCTestCase {
    func testSingleFullResolutionTIFFExport() async throws {
        guard let path = ProcessInfo.processInfo.environment["SILVERPHASE_PERF_RAW"] else {
            throw XCTSkip("Set SILVERPHASE_PERF_RAW to run the export benchmark")
        }
        let source = URL(fileURLWithPath: path)
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "silverphase-export-stress-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = Session()
        session.open(urls: [source])
        let readyStarted = Date()
        let developedID = await session.currentServiceSession()
        let sessionID = try XCTUnwrap(developedID)
        let readyMs = Int(Date().timeIntervalSince(readyStarted) * 1000)

        var recipe = ExportRecipe()
        recipe.format = .tiff
        recipe.folder = .fixed(path: folder.path)
        recipe.subfolder = ""
        recipe.colorSpace = .displayP3
        let size = try XCTUnwrap(session.decoded?.pixelSize)
        let context = NamingRule.Context(
            originalName: source.deletingPathExtension().lastPathComponent,
            filmStock: session.params.filmStock, printStock: session.params.printStock,
            pixelSize: size, counter: 1, date: Date())
        let exportStarted = Date()
        let outcome = try await Exporter.export(session: session, recipe: recipe,
                                                context: context, sessionID: sessionID)
        let exportMs = Int(Date().timeIntervalSince(exportStarted) * 1000)
        guard case .wrote(let files, _, _) = outcome, let output = files.first else {
            return XCTFail("the full-resolution export wrote no file")
        }
        let bytes = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        XCTAssertGreaterThan(bytes, 0)
        let record = "prepare_ms\texport_ms\toutput_bytes\tphys_footprint_bytes\n"
            + "\(readyMs)\t\(exportMs)\t\(bytes)\t\(MemorySampler.footprintBytes())\n"
        if let result = ProcessInfo.processInfo.environment["SILVERPHASE_PERF_RESULTS"] {
            try record.write(toFile: result, atomically: true, encoding: .utf8)
        }
    }

    /// Run explicitly with SILVERPHASE_PERF_RAW pointing to a readable RAW.
    /// Copies have distinct identities so a cache hit cannot disguise a
    /// frame-lifetime leak. This is an in-process memory benchmark, not a
    /// display-link or visible frame-switch latency measurement.
    func testTwentyFullResolutionFrameSwitches() async throws {
        guard let path = ProcessInfo.processInfo.environment["SILVERPHASE_PERF_RAW"] else {
            throw XCTSkip("Set SILVERPHASE_PERF_RAW to run the 20-frame stress benchmark")
        }
        let source = URL(fileURLWithPath: path)
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "silverphase-frame-stress-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for index in 0..<20 {
            let copy = dir.appending(path: String(format: "frame-%02d", index))
                .appendingPathExtension(source.pathExtension)
            try FileManager.default.copyItem(at: source, to: copy)
        }

        let session = Session()
        session.open(urls: [dir])
        let urls = session.frames.map(\.id)
        XCTAssertEqual(urls.count, 20)
        var rows = ["index\tfull_render_ms\tphys_footprint_bytes"]
        for (index, url) in urls.enumerated() {
            let start = Date()
            if index > 0 { session.select(url) }
            let deadline = Date().addingTimeInterval(90)
            while session.selection == url && !session.renderer.showsFullRender
                      && Date() < deadline {
                try await Task.sleep(for: .milliseconds(25))
            }
            XCTAssertEqual(session.selection, url)
            XCTAssertTrue(session.renderer.showsFullRender,
                          "frame \(index) did not reach a full-resolution print")
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            let footprint = MemorySampler.footprintBytes()
            rows.append("\(index)\t\(elapsed)\t\(footprint)")
        }
        if let output = ProcessInfo.processInfo.environment["SILVERPHASE_PERF_RESULTS"] {
            try rows.joined(separator: "\n").write(toFile: output, atomically: true,
                                                  encoding: .utf8)
        }
    }
}
