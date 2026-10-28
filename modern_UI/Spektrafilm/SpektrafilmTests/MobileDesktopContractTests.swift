import XCTest
import CoreImage
import Metal

/// Export the actual desktop defaults for the iOS audit. This is a product
/// contract, not an engine/reference baseline or a personal image fixture.
final class MobileDesktopContractTests: XCTestCase {
    @MainActor func testExportDesktopControlContract() throws {
        let p = FilmParams.default
        let wire = Dictionary(uniqueKeysWithValues: p.wire.map { ($0.name, $0.value) })
        let wireObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(wire))
        let ui: [String: Any] = [
            "grainSoftness": p.grainSoftness, "grainSoftnessRange": [FilmParams.grainSoftnessRange.lowerBound, FilmParams.grainSoftnessRange.upperBound],
            "scannerSharpeningActive": p.scannerSharpeningActive, "scannerSharpeningStrength": p.scannerSharpeningStrength,
            "scannerSharpeningRange": [FilmParams.scannerSharpeningRange.lowerBound, FilmParams.scannerSharpeningRange.upperBound],
            "scatterRange": [EffectStrengths.scatterRange.lowerBound, EffectStrengths.scatterRange.upperBound],
            "filmFrame": p.filmFrame, "filmSide": p.filmSide, "sideLengthMM": p.sideLengthMM,
            "frames": FilmFrame.all.map { ["id": $0.id, "short": $0.short, "long": $0.long] as [String: Any] },
            "dateOrder": p.dateBack.order.rawValue, "dateWithData": p.dateBack.withData,
        ]
        let body: [String: Any] = ["wire": wireObject, "ui": ui]
        try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: "/tmp/silverphase-desktop-control-contract.json"), options: .atomic)
        XCTAssertEqual(wire["print_stock"]?.stringValue, p.printStock)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let captured = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("ios/Silverphase/Resources/DesktopControlDefaults.json"))) as! [String: Any]
        let capturedWire = try JSONDecoder().decode([String: ParamValue].self, from: JSONSerialization.data(withJSONObject: captured["wire"]!))
        XCTAssertEqual(capturedWire, wire, "iOS default contract drifted from the current desktop")
    }
    @MainActor func testDesktopColorAuditReference() throws {
        let source = URL(fileURLWithPath: "/tmp/silverphase-device-color-audit.ARW")
        guard FileManager.default.fileExists(atPath: source.path) else { throw XCTSkip("Provide an explicitly authorized temporary RAW for device colour audit") }
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let raw = try ImageDecoder.rawFilter(source, look: .linear, settings: DecodeSettings()).filter
        raw.scaleFactor = Float(min(1, sqrt(2_000_000 / (raw.nativeSize.width * raw.nativeSize.height))))
        let frame = try ImageDecoder.engineFrame(from: XCTUnwrap(raw.outputImage), device: device)
        let resources = EngineClient.defaultResources()
        let engine = try XCTUnwrap(spk_engine_create(resources.path, Unmanaged.passUnretained(device as AnyObject).toOpaque()))
        defer { spk_engine_destroy(engine) }
        var params = FilmParams.default
        params.grainActive = false; params.glareActive = false
        var delta = Dictionary(uniqueKeysWithValues: params.wire.map { ($0.name, $0.value) })
        delta["product_defaults"] = .bool(true)
        delta["input_color_space"] = .string("ProPhoto RGB"); delta["input_cctf_decoding"] = .bool(false)
        delta["output_color_space"] = .string("ProPhoto RGB"); delta["output_cctf_encoding"] = .bool(true)
        let json = String(decoding: try JSONEncoder().encode(delta), as: UTF8.self)
        var image = spk_device_image(buffer: Unmanaged.passUnretained(frame.buffer as AnyObject).toOpaque(), width: UInt32(frame.width), height: UInt32(frame.height), channels: 4)
        let session = try XCTUnwrap(spk_open_device(engine, &image, json, nil))
        defer { spk_session_release(session) }
        var result = spk_result()
        XCTAssertTrue(spk_render(session, "full", &result) == SPK_OK)
        defer { spk_result_free(&result) }
        let pixels = try XCTUnwrap(result.rgba16)
        var samples: [Double] = []
        for y in 0..<24 { for x in 0..<16 {
            let sx = min(Int(result.width) - 1, (2 * x + 1) * Int(result.width) / 32)
            let sy = min(Int(result.height) - 1, (2 * y + 1) * Int(result.height) / 48)
            for c in 0..<3 { samples.append(Double(pixels[(sy * Int(result.row_stride_px) + sx) * 4 + c]) / 65535) }
        } }
        var inputSamples: [Double] = []
        let inputPixels = frame.buffer.contents().assumingMemoryBound(to: Float.self)
        for y in 0..<24 { for x in 0..<16 {
            let sx = min(frame.width - 1, (2 * x + 1) * frame.width / 32)
            let sy = min(frame.height - 1, (2 * y + 1) * frame.height / 48)
            for c in 0..<3 { inputSamples.append(Double(inputPixels[(sy * frame.width + sx) * 4 + c])) }
        } }
        var reply: UnsafeMutablePointer<CChar>?
        XCTAssertTrue(spk_get_params(session, &reply) == SPK_OK)
        let paramsObject = try reply.map { try JSONSerialization.jsonObject(with: Data(String(cString: $0).utf8)) }
        if let reply { spk_string_free(reply) }
        let body: [String: Any] = ["width": Int(result.width), "height": Int(result.height), "samples": samples,
                                 "inputSamples": inputSamples, "params": paramsObject ?? [:], "temperature": raw.neutralTemperature, "tint": raw.neutralTint,
                                 "decoderVersion": raw.decoderVersion]
        try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: "/tmp/silverphase-desktop-color-reference.json"), options: .atomic)
    }

}
