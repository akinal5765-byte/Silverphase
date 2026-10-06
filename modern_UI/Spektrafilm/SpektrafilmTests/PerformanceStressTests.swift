import Foundation
import XCTest

@MainActor
final class PerformanceStressTests: XCTestCase {
    /// The same select -> develop -> export sequence as the export page, with
    /// distinct real files. Opt in with a directory of photographs; outputs
    /// stay in a temporary directory so the sources are untouched.
    func testRealPhotoBatchExport() async throws {
        guard let path = ProcessInfo.processInfo.environment["SILVERPHASE_PERF_BATCH_DIR"] else {
            throw XCTSkip("Set SILVERPHASE_PERF_BATCH_DIR to run the batch benchmark")
        }
        let source = URL(fileURLWithPath: path)
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "silverphase-batch-stress-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = Session()
        session.open(urls: [source])
        let count = Int(ProcessInfo.processInfo.environment["SILVERPHASE_PERF_BATCH_COUNT"] ?? "10") ?? 10
        let urls = Array(session.frames.map(\.id).prefix(count))
        XCTAssertFalse(urls.isEmpty)
        let legacy = ProcessInfo.processInfo.environment["SILVERPHASE_PERF_BATCH_LEGACY"] == "1"
        if !legacy { session.beginBatchExport() }
        defer { if !legacy { session.endBatchExport() } }
        let fullRendersBefore = Log.shared.records(category: .render).filter {
            $0.value("tier") == .string("full")
        }.count
        var recipe = ExportRecipe()
        recipe.format = ProcessInfo.processInfo.environment["SILVERPHASE_PERF_BATCH_FORMAT"] == "jpeg"
            ? .jpeg : .tiff
        recipe.folder = .fixed(path: folder.path)
        recipe.subfolder = ""
        recipe.colorSpace = .displayP3
        let batchStart = Date()
        var rows = ["index\tfile\tdevelop_ms\texport_ms\toutput_bytes\tphys_footprint_bytes"]
        for (index, url) in urls.enumerated() {
            print("batch validation: starting \(index + 1)/\(urls.count) \(url.lastPathComponent)")
            let developStart = Date()
            if session.selection != url { session.select(url) }
            let developedID = await session.ensureDeveloped()
            let sessionID = try XCTUnwrap(developedID)
            let developMs = Int(Date().timeIntervalSince(developStart) * 1000)
            let size = try XCTUnwrap(session.decoded?.pixelSize)
            let context = NamingRule.Context(
                originalName: url.deletingPathExtension().lastPathComponent,
                filmStock: session.params.filmStock, printStock: session.params.printStock,
                pixelSize: size, counter: index + 1, date: Date())
            let exportStart = Date()
            let outcome = try await Exporter.export(session: session, recipe: recipe,
                                                    context: context, sessionID: sessionID)
            let exportMs = Int(Date().timeIntervalSince(exportStart) * 1000)
            if !legacy {
                XCTAssertTrue(session.renderer.showsFullRender,
                              "the export's full print should also reach the canvas")
            }
            guard case .wrote(let files, _, _) = outcome, let output = files.first else {
                return XCTFail("frame \(index) wrote no file")
            }
            let bytes = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            XCTAssertGreaterThan(bytes, 0)
            rows.append("\(index)\t\(url.lastPathComponent)\t\(developMs)\t\(exportMs)\t\(bytes)\t\(MemorySampler.footprintBytes())")
            print("batch validation: completed \(index + 1)/\(urls.count)")
        }
        rows.append("total_ms\t\(Int(Date().timeIntervalSince(batchStart) * 1000))")
        let fullRendersAfter = Log.shared.records(category: .render).filter {
            $0.value("tier") == .string("full")
        }.count
        rows.append("full_renders\t\(fullRendersAfter - fullRendersBefore)")
        if !legacy { XCTAssertEqual(fullRendersAfter - fullRendersBefore, urls.count) }
        if let result = ProcessInfo.processInfo.environment["SILVERPHASE_PERF_RESULTS"] {
            try rows.joined(separator: "\n").write(toFile: result, atomically: true,
                                                  encoding: .utf8)
        }
    }

    func testSingleFullResolutionTIFFExport() async throws {
        guard let path = ProcessInfo.processInfo.environment["SILVERPHASE_PERF_RAW"] else {
            throw XCTSkip("Set SILVERPHASE_PERF_RAW to run the export benchmark")
        }
        let source = URL(fileURLWithPath: path)
        let keep = ProcessInfo.processInfo.environment["SILVERPHASE_PERF_KEEP_OUTPUT"]
        let folder = keep.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory
                .appending(path: "silverphase-export-stress-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { if keep == nil { try? FileManager.default.removeItem(at: folder) } }
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
