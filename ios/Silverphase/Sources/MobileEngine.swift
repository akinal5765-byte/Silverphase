import Foundation
import CoreImage
import ImageIO
import Metal
import UniformTypeIdentifiers
import Darwin

struct MobileRender: @unchecked Sendable {
    let image: CGImage
    let original: CGImage
    let resolved: [String: WireValue]
    let latitude: MobileLatitude?
    let negativeWasCached: Bool
}

struct MobileLatitude: Sendable {
    var bins: [Double] = []
    var shadow = 0.0
    var highlight = 0.0
    var minimumHighlight = 0.0
    var minimumShadow = 0.0
    var suggestedHighlight = 0.0
    var suggestedShadow = 0.0
    var suggestionValid = false
    var loEV = -8.0
    var hiEV = 8.0
    var rampEV: [Double] = []
    var rampY: [Double] = []
    var yWhite = 1.0
    var centres: [Double] { bins.indices.map { loEV + (Double($0) + 0.5) * (hiEV - loEV) / Double(max(1, bins.count)) } }
    var below: Double { zip(centres, bins).filter { $0.0 < shadow }.map(\.1).reduce(0, +) }
    var above: Double { zip(centres, bins).filter { $0.0 > highlight }.map(\.1).reduce(0, +) }
    var within: Double { max(0, bins.reduce(0, +) - below - above) }
    var separation: [(Double, Double)] {
        func lightness(_ y: Double) -> Double {
            let t = max(y, 0) / max(yWhite, 1e-9)
            return t > 0.008856 ? 116 * pow(t, 1 / 3.0) - 16 : 903.3 * t
        }
        let count = min(rampY.count, rampEV.count)
        guard count > 1 else { return [] }
        let slopes = (0..<(count - 1)).map { i in
            ((rampEV[i] + rampEV[i + 1]) / 2, max(0, (lightness(rampY[i + 1]) - lightness(rampY[i])) / max(1e-9, rampEV[i + 1] - rampEV[i])))
        }
        let peak = max(slopes.map(\.1).max() ?? 0, 1e-9)
        return slopes.map { ($0.0, $0.1 / peak) }
    }
}

enum MobileFilmGate {
    static func size(_ id: String) -> (Double, Double) {
        switch id {
        case "135_half": (24, 18)
        case "120_645": (56, 41.5)
        case "120_6x6": (56, 56)
        case "120_6x7": (69.5, 56)
        case "120_6x8": (76, 56)
        case "120_6x9": (84, 56)
        case "135_xpan": (65, 24)
        case "120_6x12": (112, 56)
        case "120_6x17": (168, 56)
        default: (36, 24)
        }
    }
    static func presents(_ recipe: [String: WireValue]) -> Bool {
        recipe["overscan_active"]?.boolValue == true || recipe["date_imprint_active"]?.boolValue == true
    }
}

enum MobileFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

// Serialized off the main actor. The engine session keeps the negative while
// editing; backgrounding closes it, and reopening reconstructs it from the recipe.
final class MobileWorkGate: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    private var session: OpaquePointer?
    func setActive(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        active = value
        if !value, let session { spk_cancel(session, nil) }
    }
    func register(_ session: OpaquePointer?) {
        lock.lock(); defer { lock.unlock() }
        self.session = session
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        if let session { spk_cancel(session, nil) }
    }
    func check() throws {
        lock.lock(); defer { lock.unlock() }
        if !active { throw CancellationError() }
    }
}

actor MobileEngine {
    nonisolated let workGate = MobileWorkGate()
    private var engine: OpaquePointer?
    private var session: OpaquePointer?
    private var sourceURL: URL?
    private var original: CGImage?
    private var openedMP = 0.0
    private var decodeInfo: [String: WireValue] = [:]
    private var appliedGeometry = MobileGeometry()
    private var appliedRecipe: [String: WireValue] = [:]
    private var appliedWire: [String: WireValue] = [:]
    private let device = MTLCreateSystemDefaultDevice()
    private var outputPipeline: MobileColorPipeline?
    private var progressHandler: (@Sendable (String) -> Void)?
    // Imported URLs are immutable, app-owned copies. Keep only small metadata,
    // never a RAW filter/decoded frame, across interactive parameter changes.
    private var metadataURL: URL?
    private var metadataCache: MobileImageMetadata?
    private var captureURL: URL?
    private var captureCache: [String: (date: String, data: String, aperture: Double)] = [:]
    func setProgressHandler(_ handler: (@Sendable (String) -> Void)?) { progressHandler = handler }

    private func traceExport(_ phase: String) {
        progressHandler?(phase)
        MobileExportJournal.shared.record(phase)
#if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--audit-large-jpeg") else { return }
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
        let url = URL.documentsDirectory.appendingPathComponent("large-jpeg-phases.json")
        var rows = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
        rows.append(["phase": phase, "uptime": ProcessInfo.processInfo.systemUptime, "footprint": status == KERN_SUCCESS ? info.phys_footprint : 0, "available": os_proc_available_memory(), "engine": engine.map { String(cString: spk_memory_report($0)) } ?? "closed"])
        if let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: url, options: .atomic) }
#endif
    }
    private func releaseSession() {
        workGate.register(nil)
        if let session { spk_session_release(session) }
        session = nil; sourceURL = nil; original = nil; openedMP = 0; appliedRecipe = [:]; appliedWire = [:]
    }
    func close() {
        releaseSession()
        if let engine { spk_engine_destroy(engine) }
        engine = nil
    }

    func render(url: URL, recipe: [String: WireValue], megapixels: Double = 2, geometry: MobileGeometry = MobileGeometry(), inputMetadata: MobileImageMetadata? = nil) throws -> MobileRender {
        try autoreleasepool {
            try Task.checkCancellation()
            try workGate.check()
            var suppliedMetadata = inputMetadata
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--audit-export-legacy-work") { suppliedMetadata = nil }
#endif
            let metadata: MobileImageMetadata
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--audit-export-legacy-work") {
                metadata = MobileImageMetadata.read(url)
            } else {
                metadata = suppliedMetadata ?? (metadataURL == url ? metadataCache : nil) ?? MobileImageMetadata.read(url)
            }
#else
            metadata = suppliedMetadata ?? (metadataURL == url ? metadataCache : nil) ?? MobileImageMetadata.read(url)
#endif
            metadataURL = url; metadataCache = metadata
            let aspect = sourceURL == url ? decodeInfo["_sourceAspect"]?.doubleValue ?? metadata.aspect : metadata.aspect
            var delta = try processWire(recipe, aspect: aspect, orientedAspect: metadata.aspect, geometry: geometry)
            if recipe["_interactivePreview"]?.boolValue == true { delta["preview_long_edge"] = .double(max(800, recipe["_interactiveEdge"]?.doubleValue ?? 1600)) }
            if recipe["_exporting"]?.boolValue == true {
                delta["striped"] = .bool(true)
                // Engine default 0 still means whole-plane. The mobile export
                // policy explicitly requests bounded bands; no look changes.
                delta["strip_rows"] = .double(256)
#if DEBUG
                if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--audit-strip-rows=") }),
                   let rows = Double(argument.dropFirst(19)), [256.0, 512, 1024].contains(rows) {
                    delta["strip_rows"] = .double(rows)
                }
#endif
            }
            let presentation = MobileFilmGate.presents(recipe)
            if recipe["overscan_active"]?.boolValue == true {
                delta["film_format_mm"] = .double(MobileFilmGate.size(recipe["overscan_format"]?.stringValue ?? "135").0)
            }
            if captureURL != url { captureCache = [:]; captureURL = url }
            let order = recipe["_dateOrder"]?.stringValue ?? "japan"
            let capture = captureCache[order] ?? MobileCaptureText.read(url, order: order)
            captureCache[order] = capture
            if delta["overscan_active"]?.boolValue == true {
                delta["overscan_edge_text"] = .string(StockCatalog.shared.stock(delta["film_stock"]?.stringValue ?? "")?.name ?? "")
                delta["overscan_f_number"] = .double(capture.aperture)
            }
            if recipe["date_imprint_active"]?.boolValue == true {
                let format = delta["overscan_format"]?.stringValue ?? "135"
                let face = delta["date_imprint_style"]?.stringValue ?? "lcd"
                let edge = delta["overscan_active"]?.boolValue == true
                let panoramic = ["135_xpan", "120_6x12", "120_6x17"].contains(format)
                let needsEdge = format.hasPrefix("120_") || face == "data" || delta["date_imprint_placement"]?.stringValue == "rebate"
                delta["date_imprint_active"] = .bool(!panoramic && (!needsEdge || edge))
                let custom = recipe["date_imprint_text"]?.stringValue ?? ""
                delta["date_imprint_text"] = .string(custom.isEmpty ? (face == "data" ? capture.data : capture.date) : custom)
                delta["date_imprint_data_text"] = .string(edge && face != "data" && recipe["_dateWithData"]?.boolValue == true ? capture.data : "")
                if format == "135_half", face == "data" { delta["date_imprint_size"] = .double(min(1, delta["date_imprint_size"]?.doubleValue ?? 1)) }
            }
            // Decoding is done once at the input boundary, including encoded RGB.
            delta["input_color_space"] = .string("ProPhoto RGB")
            delta["input_cctf_decoding"] = .bool(false)
            delta["output_color_space"] = .string("ProPhoto RGB")
            delta["output_cctf_encoding"] = .bool(true)
            // Removing an override (reset/undo) must restore profile defaults;
            // merely sending a smaller delta would leave the old value live.
            let removedOverride = appliedRecipe.keys.contains { !["_interactivePreview", "_interactiveEdge"].contains($0) && recipe[$0] == nil }
            let filmChanged = appliedRecipe["film_stock"] != recipe["film_stock"]
            let decodeChanged = ["_temperature", "_tint", "_lens", "overscan_active", "overscan_format", "date_imprint_active"].contains { appliedRecipe[$0] != recipe[$0] } || (decodeInfo["_draft"]?.boolValue == true && recipe["_interactivePreview"]?.boolValue != true)
            if sourceURL != url || openedMP != megapixels || session == nil || removedOverride || filmChanged || decodeChanged || (presentation && appliedGeometry != geometry) {
                let keepKernels = recipe["_interactivePreview"]?.boolValue == true && sourceURL == url && openedMP == megapixels && megapixels <= 3
                if keepKernels { releaseSession() } else { close() }
                guard let device,
                      let resources = Bundle.main.url(forResource: "engine", withExtension: nil, subdirectory: StockCatalog.resourceDirectory) else {
                    throw MobileFailure.message("缺少 Metal 设备或随包引擎资源")
                }
                if engine == nil { engine = spk_engine_create(resources.path, Unmanaged.passUnretained(device as AnyObject).toOpaque()) }
                guard let engine else { throw failure() }
                traceExport("before-decode")
                let decoded = try decode(url: url, megapixels: megapixels, device: device, recipe: recipe, geometry: geometry, metadata: metadata)
                traceExport("decoded")
                if recipe["overscan_active"]?.boolValue != true, recipe["film_format_mm"] == nil || recipe["_filmFrame"] != nil || recipe["_filmSide"] != nil {
                    delta["film_format_mm"] = try processWire(recipe, aspect: decodeInfo["_sourceAspect"]?.doubleValue ?? aspect, orientedAspect: metadata.aspect, geometry: geometry)["film_format_mm"]
                }
                var input = spk_device_image(buffer: Unmanaged.passUnretained(decoded.buffer as AnyObject).toOpaque(),
                                             width: UInt32(decoded.width), height: UInt32(decoded.height), channels: 4)
                var reply: UnsafeMutablePointer<CChar>?
                var openingDelta = delta
                openingDelta["product_defaults"] = .bool(true)
                let openingJSON = String(decoding: try JSONEncoder().encode(openingDelta), as: UTF8.self)
                session = spk_open_device(engine, &input, openingJSON, &reply)
                if let reply { spk_string_free(reply) }
                guard session != nil else { close(); throw MobileFailure.message("无法打开图像引擎会话") }
                workGate.register(session)
                sourceURL = url; openedMP = megapixels; original = decoded.original
            } else if let session {
                let changed = delta.filter { appliedWire[$0.key] != $0.value }
                if !changed.isEmpty {
                    let json = String(decoding: try JSONEncoder().encode(changed), as: UTF8.self)
                    var reply: UnsafeMutablePointer<CChar>?
                    let status = spk_set_params(session, json, &reply)
                    if let reply { spk_string_free(reply) }
                    guard status == SPK_OK else { throw failure() }
                }
            }
            guard let session, let original else { throw failure() }
            traceExport("session-ready")
            try workGate.check()
            try Task.checkCancellation()
            var latitudeFailure: String?
            var latitude: MobileLatitude?
            var latitudeReply: UnsafeMutablePointer<CChar>?
            let h = recipe["_placementHighlight"]?.doubleValue ?? 0
            let sh = recipe["_placementShadow"]?.doubleValue ?? 0
            var needsLatitude = (recipe["_exporting"]?.boolValue != true && recipe["_interactivePreview"]?.boolValue != true) || h > 0 || sh > 0
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--audit-export-legacy-work") { needsLatitude = true }
#endif
            if needsLatitude {
            let request = String(decoding: try JSONEncoder().encode(["highlight_pull_back": h, "shadow_pull_back": sh]), as: UTF8.self)
            if spk_scene_latitude(session, request, &latitudeReply) == SPK_OK, let latitudeReply {
                defer { spk_string_free(latitudeReply) }
                let object = try JSONSerialization.jsonObject(with: Data(String(cString: latitudeReply).utf8)) as? [String: Any] ?? [:]
                let medium = object["medium"] as? [String: Any] ?? [:]
                let scene = object["scene"] as? [String: Any] ?? [:]
                let histogram = scene["histogram"] as? [String: Any] ?? [:]
                let fit = object["fit"] as? [String: Any] ?? [:]
                let highlight = fit["highlight"] as? [String: Any] ?? [:]
                let shadow = fit["shadow"] as? [String: Any] ?? [:]
                let suggested = object["suggested"] as? [String: Any] ?? [:]
                latitude = MobileLatitude(bins: histogram["placed_fractions"] as? [Double] ?? histogram["fractions"] as? [Double] ?? [],
                    shadow: medium["shadow_ev"] as? Double ?? 0, highlight: medium["highlight_ev"] as? Double ?? 0,
                    minimumHighlight: highlight["minimum_pull_back"] as? Double ?? 0,
                    minimumShadow: shadow["minimum_pull_back"] as? Double ?? 0,
                    suggestedHighlight: suggested["highlight_pull_back"] as? Double ?? 0,
                    suggestedShadow: suggested["shadow_pull_back"] as? Double ?? 0,
                    suggestionValid: suggested["valid"] as? Bool ?? false,
                    loEV: histogram["lo_ev"] as? Double ?? -8, hiEV: histogram["hi_ev"] as? Double ?? 8,
                    rampEV: medium["ramp_ev"] as? [Double] ?? [], rampY: medium["ramp_y"] as? [Double] ?? [],
                    yWhite: medium["y_white"] as? Double ?? 1)
                if (h > 0 || sh > 0) && delta["digital_intermediate"]?.boolValue != true {
                    guard fit["valid"] as? Bool == true, let values = fit["params_delta"] else {
                        let issues = fit["issues"] as? [[String: Any]]
                        throw MobileFailure.message(issues?.first?["message"] as? String ?? "当前场景置位超出可用范围")
                    }
                    let fitJSON = String(decoding: try JSONSerialization.data(withJSONObject: values), as: UTF8.self)
                    guard spk_set_params(session, fitJSON, nil) == SPK_OK else { throw failure() }
                } else if recipe["_placementHighlight"] != nil || recipe["_placementShadow"] != nil || delta["digital_intermediate"]?.boolValue == true {
                    guard spk_set_params(session, "{\"scene_latitude_active\":false}", nil) == SPK_OK else { throw failure() }
                }
            } else {
                latitudeFailure = String(cString: spk_last_error(engine))
                if let latitudeReply { spk_string_free(latitudeReply) }
            }
            } else if recipe["_placementHighlight"] != nil || recipe["_placementShadow"] != nil || delta["digital_intermediate"]?.boolValue == true {
                guard spk_set_params(session, "{\"scene_latitude_active\":false}", nil) == SPK_OK else { throw failure() }
            }
            var result = spk_result()
            // set_params invalidates the negative for shoot edits. Reprint safely
            // reuses it for paper/output edits, preserving grain and avoiding
            // a forced film render on every slider commit.
            traceExport("before-render")
            let status = spk_reprint(session, recipe["_interactivePreview"]?.boolValue == true ? "live" : "full", &result)
            traceExport("rendered")
            defer { spk_result_free(&result) }
            if status == SPK_ERR_CANCELLED { throw CancellationError() }
            guard status == SPK_OK, let pixels = result.rgba16 else { throw failure() }
            var reply: UnsafeMutablePointer<CChar>?
            guard spk_get_params(session, &reply) == SPK_OK, let reply else { throw failure() }
            defer { spk_string_free(reply) }
            var resolved = try JSONDecoder().decode([String: WireValue].self, from: Data(String(cString: reply).utf8))
            if recipe["_exporting"]?.boolValue == true, recipe["_keepExportSession"]?.boolValue != true, let engine {
                let target = recipe["_exportTargetSpace"]?.stringValue.flatMap(MobileOutputSpace.init(rawValue:)) ?? .p3
                _ = try colorPipeline().convert(original, engine: engine, target: target)
                // spk_result owns the output texture independently of the
                // session/engine. Drop source/negative/pool BEFORE its host copy.
                close()
                traceExport("engine-released")
            }
            // Copy before releasing spk_result; CGImage must never borrow freed
            // engine memory. ROMM tags match the encoded ProPhoto output.
            let data = Data(bytes: pixels, count: Int(result.row_stride_px * result.height) * 8)
            traceExport("host-copy")
            guard let provider = CGDataProvider(data: data as CFData),
                  let space = CGColorSpace(name: CGColorSpace.rommrgb),
                  let image = CGImage(width: Int(result.width), height: Int(result.height),
                                      bitsPerComponent: 16, bitsPerPixel: 64,
                                      bytesPerRow: Int(result.row_stride_px) * 8, space: space,
                                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
                                        .union(.byteOrder16Little), provider: provider,
                                      decode: nil, shouldInterpolate: true, intent: .relativeColorimetric) else {
                throw MobileFailure.message("无法创建带颜色配置的图像")
            }
            if let latitudeFailure { resolved["_latitudeFailure"] = .string(latitudeFailure) }
            resolved.merge(decodeInfo) { _, new in new }
            appliedRecipe = recipe
            appliedWire = delta
            appliedGeometry = geometry
            let viewed = delta["digital_intermediate"]?.boolValue == true ? try colorPipeline().cineonView(image) : image
            return MobileRender(image: viewed, original: original, resolved: resolved, latitude: latitude, negativeWasCached: result.negative_was_cached != 0)
        }
    }

    private func processWire(_ recipe: [String: WireValue], aspect: Double, orientedAspect: Double, geometry: MobileGeometry) throws -> [String: WireValue] {
        var wire = try MobileProcessContract.wire(recipe, aspect: aspect)
        if recipe["_cropRecalc"]?.boolValue == true, !geometry.value.isIdentity, recipe["overscan_active"]?.boolValue != true {
            let source = CGSize(width: orientedAspect * 10000, height: 10000)
            let output = geometry.outputSize(for: source)
            let w = output.width, h = output.height
            let originalLong = max(source.width, source.height)
            let side = recipe["_filmSide"]?.stringValue ?? "short"
            let length = recipe["_sideLengthMM"]?.doubleValue ?? 24
            let long = side == "long" ? length : length * max(w / h, h / w)
            wire["film_format_mm"] = .double(min(200, max(4, long * originalLong / max(w, h))))
        }
        return wire
    }

    private func colorPipeline() throws -> MobileColorPipeline {
        if let outputPipeline { return outputPipeline }
        guard let device else { throw MobileFailure.message("缺少 Metal 设备") }
        let pipeline = try MobileColorPipeline(device: device)
        outputPipeline = pipeline
        return pipeline
    }

    func canvasImage(_ working: CGImage) throws -> CGImage {
        try colorPipeline().convert(working, engine: engine, target: .p3)
    }
    func developmentAssets(print: CGImage, geometry: MobileGeometry, framed: Bool, scanStyle: Bool) throws -> MobileDevelopmentAssets {
        try Task.checkCancellation()
        guard let session else { throw MobileFailure.message("未准备显影会话") }
        var result = spk_result()
        let status = spk_preview_scan(session, "live", &result)
        defer { spk_result_free(&result) }
        guard status == SPK_OK, let pixels = result.rgba16,
              let space = CGColorSpace(name: CGColorSpace.rommrgb) else { throw failure() }
        try Task.checkCancellation()
        let data = Data(bytes: pixels, count: Int(result.row_stride_px * result.height) * 8)
        guard let provider = CGDataProvider(data: data as CFData),
              let scan = CGImage(width: Int(result.width), height: Int(result.height), bitsPerComponent: 16, bitsPerPixel: 64,
                bytesPerRow: Int(result.row_stride_px) * 8, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue).union(.byteOrder16Little),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .relativeColorimetric) else { throw MobileFailure.message("无法创建胶片扫描预览") }
        return try colorPipeline().developmentAssets(print: print, scan: framed ? scan : geometry.apply(to: scan), engine: engine, scanStyle: scanStyle)
    }
    func cropCanvasImage(url: URL, recipe: [String: WireValue], megapixels: Double) throws -> CGImage {
        guard let device else { throw MobileFailure.message("缺少 Metal 设备") }
        var unframed = recipe
        unframed["overscan_active"] = .bool(false); unframed["date_imprint_active"] = .bool(false)
        let input = try decode(url: url, megapixels: megapixels, device: device, recipe: unframed, geometry: MobileGeometry())
        return try canvasImage(input.original)
    }
    /// Camera-rendered before image, using the same RAW display defaults/WB
    /// as decode(). Only materialise the visible native pixels: no film render,
    /// full float upload or second full-resolution host comparison image.
    func originalDetail(url: URL, recipe: [String: WireValue], geometry: MobileGeometry,
                        viewport: CGRect, pixelLongEdge: Double) throws -> MobileDetailTile {
        try autoreleasepool {
            try Task.checkCancellation()
            guard let device else { throw MobileFailure.message("缺少 Metal 设备") }
            let metadata = MobileImageMetadata.read(url)
            var image: CIImage
            if metadata.isRaw {
                guard let raw = CIRAWFilter(imageURL: url) else { throw MobileFailure.message("无法读取原图细节") }
                raw.scaleFactor = 1; raw.isDraftModeEnabled = false
                raw.isLensCorrectionEnabled = recipe["_lens"]?.boolValue ?? false
                if let t = recipe["_temperature"]?.doubleValue { raw.neutralTemperature = Float(t) }
                if let t = recipe["_tint"]?.doubleValue { raw.neutralTint = Float(t) }
                guard let output = raw.outputImage else { throw MobileFailure.message("原图没有输出") }
                image = output
            } else {
                guard let input = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { throw MobileFailure.message("无法读取原图") }
                image = input
            }
            image = geometry.apply(to: image)
            if recipe["overscan_active"]?.boolValue == true {
                let gate = MobileFilmGate.size(recipe["overscan_format"]?.stringValue ?? "135")
                image = crop(image, aspect: image.extent.width >= image.extent.height ? gate.0 / gate.1 : gate.1 / gate.0)
            }
            let native = image.extent.integral.size
            let scale = min(1, pixelLongEdge / max(native.width, native.height))
            image = image.transformed(by: .init(translationX: -image.extent.minX, y: -image.extent.minY))
                .transformed(by: .init(scaleX: scale, y: scale))
            let extent = image.extent.integral
            let rect = viewport.insetBy(dx: -viewport.width * 0.15, dy: -viewport.height * 0.15)
                .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            let pixels = CGRect(x: rect.minX * extent.width, y: (1 - rect.maxY) * extent.height,
                                width: rect.width * extent.width, height: rect.height * extent.height).integral.intersection(extent)
            guard !pixels.isEmpty, Double(os_proc_available_memory()) > metadata.megapixels * 28e6 + 350e6 else {
                throw MobileFailure.message("当前内存不足以读取原图细节")
            }
            let context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false,
                .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!, .workingFormat: CIFormat.RGBAh, .highQualityDownsample: true])
            defer { context.clearCaches(); close() }
            guard let working = CGColorSpace(name: CGColorSpace.rommrgb),
                  let tile = context.createCGImage(image, from: pixels, format: .RGBA16, colorSpace: working) else { throw MobileFailure.message("无法创建原图细节") }
            try Task.checkCancellation()
            if engine == nil {
                guard let resources = Bundle.main.url(forResource: "engine", withExtension: nil, subdirectory: StockCatalog.resourceDirectory) else { throw MobileFailure.message("缺少色彩资源") }
                engine = spk_engine_create(resources.path, Unmanaged.passUnretained(device as AnyObject).toOpaque())
            }
            let display = try canvasImage(tile)
            return MobileDetailTile(image: display, rect: CGRect(x: pixels.minX / extent.width, y: 1 - pixels.maxY / extent.height,
                width: pixels.width / extent.width, height: pixels.height / extent.height), nativeSize: scale >= 0.9999 ? native : nil)
        }
    }

    func neutralPoint(url: URL, point: CGPoint) throws -> (Double, Double) {
        guard let filter = CIRAWFilter(imageURL: url), let extent = filter.outputImage?.extent else { throw MobileFailure.message("当前 RAW 无法取样白平衡") }
        filter.neutralLocation = CGPoint(x: extent.minX + point.x * extent.width, y: extent.minY + (1 - point.y) * extent.height)
        return (Double(filter.neutralTemperature), Double(filter.neutralTint))
    }

    func export(url: URL, recipe: [String: WireValue], geometry: MobileGeometry,
                format: MobileExportFormat) throws -> URL {
        var options = MobileExportRecipe(); options.format = format
        return try exportFiles(url: url, recipe: recipe, geometry: geometry, options: options, stem: "Silverphase")[0]
    }

    func exportFiles(url: URL, recipe: [String: WireValue], geometry: MobileGeometry,
                     options: MobileExportRecipe, stem: String) throws -> [URL] {
        try autoreleasepool {
        defer { close() }
        traceExport("export.prepare")
        let metadata = MobileImageMetadata.read(url)
        let mp = options.megapixels(sourceMP: metadata.megapixels, aspect: metadata.aspect, geometry: geometry)
        close() // Release the preview arena before budgeting a large export.
        // Incremental working-set allowance, not total physical RAM. The
        // decoder now drains before film rendering; retaining its old peak
        // estimate would reject every later batch frame despite ample room.
        let bytesPerPixel = options.format == .jpeg ? 70.0 : options.format == .di ? 140.0 : 90.0
        let allowance = (mp * bytesPerPixel + 600) * 1_000_000
        guard Double(os_proc_available_memory()) > allowance else {
            throw MobileFailure.message("当前可用内存不足以安全导出此尺寸，请降低像素上限或输出长边。")
        }
        let folder = URL.temporaryDirectory.appendingPathComponent("Export-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            var exportRecipe = recipe
            exportRecipe["_exporting"] = .bool(true)
            exportRecipe["_keepExportSession"] = .bool(options.format == .di)
            exportRecipe["_exportTargetSpace"] = .string(options.colorSpace.rawValue)
            var rendered: MobileRender? = try render(url: url, recipe: exportRecipe, megapixels: mp, geometry: geometry, inputMetadata: metadata)
            let output = folder.appendingPathComponent(stem).appendingPathExtension(options.format.fileExtension)
            if options.format == .di {
                rendered = nil
                guard let session else { throw failure() }
                var result = spk_result()
                guard spk_render_digital_intermediate(session, &result, nil) == SPK_OK, let pixels = result.rgba16 else { throw failure() }
                var ownsResult = true
                defer { if ownsResult { spk_result_free(&result) } }
                let bytes = Data(bytes: pixels, count: Int(result.row_stride_px * result.height) * 8)
                guard let provider = CGDataProvider(data: bytes as CFData),
                      let master = CGImage(width: Int(result.width), height: Int(result.height), bitsPerComponent: 16, bitsPerPixel: 64, bytesPerRow: Int(result.row_stride_px) * 8, space: CGColorSpaceCreateDeviceRGB(),
                                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue).union(.byteOrder16Little), provider: provider, decode: nil, shouldInterpolate: true, intent: .relativeColorimetric) else { throw MobileFailure.message("无法创建数字中间片") }
                spk_result_free(&result); ownsResult = false
                let colors = try colorPipeline()
                close()
                let preview = try colors.cineonView(master)
                try writeExport(master, source: url, output: output, options: options, diPreview: preview)
                var files = [output]
                for name in ["SpektraLab DI view, Cineon to ProPhoto RGB", "SpektraLab DI view, Cineon to Rec709"] {
                    guard let lut = Bundle.main.url(forResource: name, withExtension: "cube", subdirectory: StockCatalog.resourceDirectory + "/DI") else { throw MobileFailure.message("缺少数字中间片视图 LUT") }
                    let destination = folder.appendingPathComponent(name + ".cube")
                    try FileManager.default.copyItem(at: lut, to: destination); files.append(destination)
                }
                return files
            }
            guard let renderedImage = rendered?.image else { throw MobileFailure.message("没有导出图像") }
            var cropped = try MobileFilmGate.presents(recipe) ? renderedImage : geometry.apply(to: renderedImage)
            rendered = nil
            let resize: Double
            if options.sizeMode == "longEdge" { resize = min(1, Double(options.longEdge) / Double(max(cropped.width, cropped.height))) }
            else if options.sizeMode == "megapixels" { resize = min(1, sqrt(options.maximumMegapixels * 1_000_000 / Double(cropped.width * cropped.height))) }
            else { resize = 1 }
            if resize < 1 {
                let resized = CIImage(cgImage: cropped).transformed(by: .init(scaleX: resize, y: resize))
                guard let image = CIContext(options: [.cacheIntermediates: false]).createCGImage(resized, from: resized.extent.integral, format: .RGBA16, colorSpace: cropped.colorSpace) else { throw MobileFailure.message("无法缩放输出尺寸") }
                cropped = image
            }
            let colors = try colorPipeline()
            // Fetch/copy the desktop transform's setup, then release the large
            // engine arena before allocating conversion and encoding buffers.
            if let engine, let probe = cropped.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1)) { _ = try colors.convert(probe, engine: engine, target: options.colorSpace) }
            close()
            traceExport("before-output-conversion")
            let converted = try colors.convert(cropped, engine: nil, target: options.colorSpace)
            traceExport("after-output-conversion")
            traceExport("before-jpeg-write")
            try writeExport(converted, source: url, output: output, options: options)
            traceExport("file-ready")
            return [output]
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        }
    }

    private func writeExport(_ image: CGImage, source: URL, output: URL, options: MobileExportRecipe, diPreview: CGImage? = nil) throws {
        var written = image
        let context = CIContext(options: [.cacheIntermediates: false])
        if options.format == .jpeg || options.format == .png {
            guard let eight = context.createCGImage(CIImage(cgImage: image), from: CGRect(x: 0, y: 0, width: image.width, height: image.height), format: .RGBA8, colorSpace: image.colorSpace) else { throw MobileFailure.message("无法写入8位图像") }
            written = eight
        }
        var properties: [CFString: Any] = [kCGImagePropertyOrientation: 1]
        if options.metadata, let input = CGImageSourceCreateWithURL(source as CFURL, nil), let metadata = CGImageSourceCopyPropertiesAtIndex(input, 0, nil) as? [CFString: Any] {
            for key in [kCGImagePropertyExifDictionary, kCGImagePropertyIPTCDictionary, kCGImagePropertyTIFFDictionary] { properties[key] = metadata[key] }
            if options.location { properties[kCGImagePropertyGPSDictionary] = metadata[kCGImagePropertyGPSDictionary] }
        }
        var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        exif.removeValue(forKey: kCGImagePropertyExifMakerNote)
        exif[kCGImagePropertyExifColorSpace] = image.colorSpace?.name == CGColorSpace.sRGB ? 1 : 0xFFFF
        exif[kCGImagePropertyExifPixelXDimension] = image.width; exif[kCGImagePropertyExifPixelYDimension] = image.height
        properties[kCGImagePropertyExifDictionary] = exif
        let sourceTIFF = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        var tiff: [CFString: Any] = [:]
        for key in [kCGImagePropertyTIFFMake, kCGImagePropertyTIFFModel, kCGImagePropertyTIFFArtist, kCGImagePropertyTIFFCopyright, kCGImagePropertyTIFFDateTime, kCGImagePropertyTIFFImageDescription] { tiff[key] = sourceTIFF[key] }
        tiff[kCGImagePropertyTIFFSoftware] = "Silverphase"
        tiff[kCGImagePropertyTIFFOrientation] = 1
        if options.format == .tiff || options.format == .di { tiff[kCGImagePropertyTIFFCompression] = 1 }
        properties[kCGImagePropertyTIFFDictionary] = tiff
        if options.format == .jpeg { properties[kCGImageDestinationLossyCompressionQuality] = min(1, max(0.1, options.quality)) }
        let preview = (options.format == .tiff && options.embedsPreview) || diPreview != nil
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, options.format.type.identifier as CFString, preview ? 2 : 1, nil) else { throw MobileFailure.message("无法创建导出文件") }
        CGImageDestinationAddImage(destination, written, properties as CFDictionary)
        if preview {
            let previewImage = diPreview ?? image
            let factor = min(1, 1024 / Double(max(previewImage.width, previewImage.height)))
            let small = CIImage(cgImage: previewImage).transformed(by: .init(scaleX: factor, y: factor))
            guard let page = context.createCGImage(small, from: small.extent.integral, format: .RGBA8, colorSpace: previewImage.colorSpace) else { throw MobileFailure.message("无法写入 TIFF 预览页") }
            CGImageDestinationAddImage(destination, page, nil)
        }
        guard CGImageDestinationFinalize(destination) else { throw MobileFailure.message("导出文件写入未完成") }
    }

    private func failure() -> MobileFailure {
        MobileFailure.message(String(cString: spk_last_error(engine)))
    }

    private func crop(_ image: CIImage, aspect: Double) -> CIImage {
        let size = image.extent.size
        let width = max(1, min(size.width, size.height * aspect).rounded(.down))
        let height = max(1, (width / aspect).rounded())
        let rect = CGRect(x: (image.extent.midX - width / 2).rounded(.down),
                          y: (image.extent.midY - height / 2).rounded(.down), width: width, height: height)
        return image.cropped(to: rect).transformed(by: .init(translationX: -rect.minX, y: -rect.minY))
    }
    private func captureDate(_ url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any],
              let stamp = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String else { return nil }
        let date = stamp.prefix(10).split(separator: ":")
        guard date.count == 3 else { return nil }
        return "'" + date[0].suffix(2) + " " + date[1] + " " + date[2]
    }

    private func decode(url: URL, megapixels: Double, device: MTLDevice, recipe: [String: WireValue], geometry: MobileGeometry, metadata: MobileImageMetadata? = nil) throws -> (buffer: MTLBuffer, width: Int, height: Int, original: CGImage) {
        try autoreleasepool {
        var image: CIImage
        var comparison: CIImage?
        var suppliedMetadata = metadata
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--audit-export-legacy-work") { suppliedMetadata = nil }
#endif
        let isRaw = (suppliedMetadata ?? MobileImageMetadata.read(url)).isRaw
        if isRaw {
            guard let raw = CIRAWFilter(imageURL: url), raw.nativeSize.width > 0, raw.nativeSize.height > 0 else { throw MobileFailure.message("系统无法解码这款 RAW") }
            raw.scaleFactor = Float(min(1, sqrt(megapixels * 1_000_000 / (raw.nativeSize.width * raw.nativeSize.height))))
            raw.isDraftModeEnabled = recipe["_interactivePreview"]?.boolValue == true
            decodeInfo = ["_temperature": .double(Double(raw.neutralTemperature)), "_tint": .double(Double(raw.neutralTint)),
                          "_asShotTemperature": .double(Double(raw.neutralTemperature)), "_asShotTint": .double(Double(raw.neutralTint)),
                          "_draft": .bool(recipe["_interactivePreview"]?.boolValue == true),
                          "_raw": .bool(true), "_lensSupported": .bool(raw.isLensCorrectionSupported),
                          "_sourceAspect": .double(raw.nativeSize.width / raw.nativeSize.height)]
            raw.isLensCorrectionEnabled = recipe["_lens"]?.boolValue ?? false
            if let temperature = recipe["_temperature"]?.doubleValue { raw.neutralTemperature = Float(temperature) }
            if let tint = recipe["_tint"]?.doubleValue { raw.neutralTint = Float(tint) }
            if recipe["_exporting"]?.boolValue != true && recipe["_interactivePreview"]?.boolValue != true {
            guard let display = CIRAWFilter(imageURL: url) else { throw MobileFailure.message("无法创建 RAW 原图预览") }
            display.scaleFactor = raw.scaleFactor
            display.isDraftModeEnabled = false
            display.isLensCorrectionEnabled = raw.isLensCorrectionEnabled
            if let temperature = recipe["_temperature"]?.doubleValue { display.neutralTemperature = Float(temperature) }
            if let tint = recipe["_tint"]?.doubleValue { display.neutralTint = Float(tint) }
            comparison = display.outputImage
            }
            raw.boostAmount = 0; raw.boostShadowAmount = 0
            raw.isGamutMappingEnabled = false
            raw.localToneMapAmount = 0; raw.extendedDynamicRangeAmount = 0
            guard let output = raw.outputImage else { throw MobileFailure.message("RAW 解码没有输出") }
            image = output
        } else {
            decodeInfo = ["_raw": .bool(false), "_lensSupported": .bool(false)]
            guard var input = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
                throw MobileFailure.message("无法读取图像")
            }
            let scale = min(1, sqrt(megapixels * 1_000_000 / (input.extent.width * input.extent.height)))
            image = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        func prepared(_ input: CIImage) -> CIImage {
            var output = input
            if MobileFilmGate.presents(recipe) {
                output = geometry.apply(to: output)
                if recipe["overscan_active"]?.boolValue == true {
                    let gate = MobileFilmGate.size(recipe["overscan_format"]?.stringValue ?? "135")
                    output = crop(output, aspect: output.extent.width >= output.extent.height ? gate.0 / gate.1 : gate.1 / gate.0)
                }
            }
            return output
        }
        comparison = prepared(comparison ?? image)
        image = prepared(image)
        let extent = image.extent.integral
        let width = Int(extent.width), height = Int(extent.height)
        guard width > 0, height > 0, width <= 16384, height <= 16384,
              width * height <= Int(megapixels * 1_000_000 * 1.05),
              let buffer = device.makeBuffer(length: width * height * 16, options: .storageModeShared) else {
            throw MobileFailure.message("图像尺寸超出当前移动端内存预算")
        }
        let placed = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        let context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false, .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!, .workingFormat: CIFormat.RGBAh, .highQualityDownsample: true])
        defer { context.clearCaches() }
        // Same linear ProPhoto matrix as the desktop decoder and the iOS PoC.
        var wp: [CGFloat] = [0.9642, 1, 0.8249], bp: [CGFloat] = [0, 0, 0], gamma: [CGFloat] = [1, 1, 1]
        var matrix: [CGFloat] = [0.7976749, 0.2880402, 0, 0.1351917, 0.7118741, 0, 0.0313534, 0.0000857, 0.8252100]
        let originalScale = recipe["_exporting"]?.boolValue == true || recipe["_interactivePreview"]?.boolValue == true ? min(1, 256 / Double(max(width, height))) : 1
        guard let linear = CGColorSpace(calibratedRGBWhitePoint: &wp, blackPoint: &bp, gamma: &gamma, matrix: &matrix),
              let working = CGColorSpace(name: CGColorSpace.rommrgb),
              let display = comparison,
              let original = context.createCGImage(display.transformed(by: .init(translationX: -display.extent.minX, y: -display.extent.minY)).transformed(by: .init(scaleX: originalScale, y: originalScale)), from: CGRect(x: 0, y: 0, width: Double(width) * originalScale, height: Double(height) * originalScale).integral, format: .RGBA16, colorSpace: working) else {
            throw MobileFailure.message("无法创建输入颜色空间")
        }
        context.render(placed, toBitmap: buffer.contents(), rowBytes: width * 16,
                       bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBAf, colorSpace: linear)
        return (buffer, width, height, original)
        }
    }
}

#if DEBUG
extension MobileEngine {
    func auditInput(_ url: URL) throws -> [Double] {
        guard let device else { throw MobileFailure.message("没有 Metal 设备") }
        let frame = try decode(url: url, megapixels: 2, device: device, recipe: [:], geometry: MobileGeometry())
        let pixels = frame.buffer.contents().assumingMemoryBound(to: Float.self)
        var samples: [Double] = []
        for y in 0..<24 { for x in 0..<16 {
            let sx = min(frame.width - 1, (2 * x + 1) * frame.width / 32)
            let sy = min(frame.height - 1, (2 * y + 1) * frame.height / 48)
            for c in 0..<3 { samples.append(Double(pixels[(sy * frame.width + sx) * 4 + c])) }
        } }
        return samples
    }
    func auditMemory() -> String { engine.map { String(cString: spk_memory_report($0)) } ?? "{}" }
}
#endif
