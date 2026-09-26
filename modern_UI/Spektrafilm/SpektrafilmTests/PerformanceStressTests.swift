import Foundation
import XCTest

@MainActor
final class PerformanceStressTests: XCTestCase {
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
