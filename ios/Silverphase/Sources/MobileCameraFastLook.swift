#if SILVERPHASE_APP
import CoreImage
import Metal
import Foundation

/// Log-shaper allocates the table to shadows and highlights, rather than
/// clipping exposed video at SDR white before the film has seen the light.
enum MobileCameraLookDomain {
    static let dimension = 49
    static let toe: Float = 0.002
    static let maximum: Float = 16
    static let logRange = log2f(1 + maximum / toe)
    static func value(_ coordinate: Float) -> Float {
        toe * (exp2f(max(0, min(1, coordinate)) * logRange) - 1)
    }
    static func coordinate(_ linear: Float) -> Float {
        log2f(1 + max(0, min(maximum, linear)) / toe) / logRange
    }
}

/// A composition approximation: bake the film/paper colour once, then process
/// ordinary video frames with a small meter, linear-light bloom and GPU lookup.
/// This deliberately does not claim native spatial/headroom or RAW equivalence.
actor MobileCameraFastLookEngine {
    nonisolated let workGate = MobileWorkGate()
    private let device = MTLCreateSystemDefaultDevice()
    private var engine: OpaquePointer?
    private var context: CIContext?
    private var colors: MobileColorPipeline?
    private var linearSpace: CGColorSpace?
    private var queue: MTLCommandQueue?
    private var pipeline: MTLComputePipelineState?
    private var cubes: [String: MTLTexture] = [:]
    private var cubeOrder: [String] = []
#if DEBUG
    private(set) var tableBuildCount = 0
#endif
    private var input: MTLBuffer?
    private var output: MTLTexture?
    private var meter = [Float](repeating: 0, count: 64 * 64 * 4)
    private var lastRecipe: MobileCameraRecipe?
    private var smoothedEV: Double?
    private var lastMeterTime: Double?

    func close(keepingColorTables: Bool = false) {
        if !keepingColorTables { cubes.removeAll(); cubeOrder.removeAll() }
        colors = nil; linearSpace = nil; context?.clearCaches(); context = nil
        queue = nil; pipeline = nil; input = nil; output = nil
        lastRecipe = nil; smoothedEV = nil; lastMeterTime = nil
        if let engine { spk_engine_destroy(engine) }; engine = nil
    }

    private func prepare(needsBaker: Bool = true) throws {
        guard let device else { throw MobileFailure.message("没有 Metal 设备") }
        if engine == nil && needsBaker {
            guard let resources = Bundle.main.url(forResource: "engine", withExtension: nil, subdirectory: StockCatalog.resourceDirectory) else { throw MobileFailure.message("缺少胶片预览资源") }
            engine = spk_engine_create(resources.path, Unmanaged.passUnretained(device as AnyObject).toOpaque())
        }
        if needsBaker && engine == nil { throw MobileFailure.message("无法准备胶片预览") }
        if context == nil { context = MobileInputColor.context(device: device) }
        if linearSpace == nil { linearSpace = MobileInputColor.linearProPhoto() }
        if needsBaker && colors == nil { colors = try MobileColorPipeline(device: device) }
        if queue == nil { queue = device.makeCommandQueue() }
        if pipeline == nil {
            guard let url = Bundle.main.url(forResource: "SilverphaseUI", withExtension: "metallib", subdirectory: StockCatalog.resourceDirectory),
                  let function = try device.makeLibrary(URL: url).makeFunction(name: "mobileCameraFastLook") else { throw MobileFailure.message("无法准备流畅取景") }
            pipeline = try device.makeComputePipelineState(function: function)
        }
    }

    static func colorIntent(filmID: String) throws -> [String: WireValue] {
        let calibration = MobileCameraRecipe(filmID: filmID, metering: .custom, diffusion: .off)
        var intent: [String: WireValue] = [:]
        try MobileDocument.applyCapturedRecipe(calibration, to: &intent)
        intent["grain_active"] = .bool(false); intent["glare_active"] = .bool(false)
        var values = try MobileProcessContract.wire(intent, aspect: 4.0 / 3)
        values["input_color_space"] = .string("ProPhoto RGB"); values["input_cctf_decoding"] = .bool(false)
        values["output_color_space"] = .string("ProPhoto RGB"); values["output_cctf_encoding"] = .bool(true)
        values["product_defaults"] = .bool(true)
        return values
    }

    private func cube(for recipe: MobileCameraRecipe) throws -> MTLTexture {
        let id = recipe.filmID ?? MobileCameraRecipe.defaultFilmID
        if let cached = cubes[id] {
            cubeOrder.removeAll { $0 == id }; cubeOrder.append(id)
            return cached
        }
        guard let device, let engine, let colors else { throw MobileFailure.message("胶片预览未准备") }
        let n = MobileCameraLookDomain.dimension, width = n * n, height = n
        var samples = [Float](repeating: 0, count: n * n * n * 3)
        // Red varies fastest, then green, then blue, matching Metal 3D texture x/y/z.
        for b in 0..<n { for g in 0..<n { for r in 0..<n {
            let i = ((b * n + g) * n + r) * 3
            samples[i] = MobileCameraLookDomain.value(Float(r) / Float(n - 1))
            samples[i + 1] = MobileCameraLookDomain.value(Float(g) / Float(n - 1))
            samples[i + 2] = MobileCameraLookDomain.value(Float(b) / Float(n - 1))
        } } }
        // Isolate all spatial/global processing in the engine, while keeping
        // pointwise print EDR and scanner references. No fictitious film size.
        let values = try Self.colorIntent(filmID: id)
        let json = String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
        let opened = samples.withUnsafeBufferPointer { p -> OpaquePointer? in
            var image = spk_image(data: p.baseAddress, width: UInt32(width), height: UInt32(height), channels: 3)
            return spk_open(engine, &image, json, nil)
        }
        guard let session = opened else { throw MobileFailure.message(String(cString: spk_last_error(engine))) }
        workGate.register(session)
        defer { workGate.register(nil); spk_session_release(session) }
        try Task.checkCancellation(); try workGate.check()
        var result = spk_result()
        defer { spk_result_free(&result) }
        guard spk_render_color_samples(session, &result) == SPK_OK, result.width == width, result.height == height, let pixels = result.rgba16 else { throw MobileFailure.message(String(cString: spk_last_error(engine))) }
        let data = Data(bytes: pixels, count: Int(result.row_stride_px * result.height) * 8)
        guard let provider = CGDataProvider(data: data as CFData), let space = CGColorSpace(name: CGColorSpace.rommrgb),
              let image = CGImage(width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 64,
                bytesPerRow: Int(result.row_stride_px) * 8, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue).union(.byteOrder16Little),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .relativeColorimetric) else { throw MobileFailure.message("无法读取胶片颜色表") }
        let display = try colors.convert(image, engine: engine, target: .p3)
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D; descriptor.pixelFormat = .rgba32Float
        descriptor.width = n; descriptor.height = n; descriptor.depth = n
        descriptor.storageMode = .shared; descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor), let bytes = display.dataProvider?.data,
              let base = CFDataGetBytePtr(bytes) else { throw MobileFailure.message("无法创建胶片颜色表") }
        var table = [Float](repeating: 1, count: n * n * n * 4)
        for b in 0..<n { for g in 0..<n { for r in 0..<n {
            let source = base + b * display.bytesPerRow + (g * n + r) * 8
            for c in 0..<3 { table[((b * n + g) * n + r) * 4 + c] = Float(UInt16(source[c * 2]) | UInt16(source[c * 2 + 1]) << 8) / 65535 }
        } } }
        table.withUnsafeBytes { texture.replace(region: MTLRegionMake3D(0, 0, 0, n, n, n), mipmapLevel: 0, slice: 0,
            withBytes: $0.baseAddress!, bytesPerRow: n * 16, bytesPerImage: n * n * 16) }
        try Task.checkCancellation(); try workGate.check()
        while cubes.count >= 2, !cubeOrder.isEmpty { cubes.removeValue(forKey: cubeOrder.removeFirst()) }
        cubes[id] = texture; cubeOrder.append(id)
#if DEBUG
        tableBuildCount += 1
#endif
        return texture
    }

    func render(_ frame: MobileCameraLookFrame, angle: CGFloat, mirrored: Bool,
                recipe: MobileCameraRecipe, longEdge: Int) throws -> MobileCameraLookResult {
        try autoreleasepool {
            try Task.checkCancellation(); try workGate.check()
            try prepare(needsBaker: cubes[recipe.filmID ?? MobileCameraRecipe.defaultFilmID] == nil)
            let cube = try cube(for: recipe)
            guard let device, let context, let queue, let pipeline else { throw MobileFailure.message("预览未准备") }
            let source = MobileCameraLookGeometry.orientedImage(frame, angle: angle, mirrored: mirrored)
            let ev = try meteredEV(source, mode: recipe.metering, context: context)
            let now = ProcessInfo.processInfo.systemUptime
            if lastRecipe != recipe { smoothedEV = nil; lastMeterTime = nil }
            let alpha = min(1, max(0.05, (now - (lastMeterTime ?? now - 1)) / 0.18))
            let exposure = (smoothedEV ?? ev) + (ev - (smoothedEV ?? ev)) * alpha
            smoothedEV = exposure; lastRecipe = recipe; lastMeterTime = now
            let scale = min(1, CGFloat(longEdge) / max(source.extent.width, source.extent.height))
            let width = max(1, Int(source.extent.width * scale)), height = max(1, Int(source.extent.height * scale))
            var image = source.transformed(by: .init(scaleX: CGFloat(width) / source.extent.width, y: CGFloat(height) / source.extent.height))
                .applyingFilter("CIExposureAdjust", parameters: ["inputEV": exposure])
            // Explicitly approximate linear-light diffusion before the film colour.
            // It stays enabled in low-power mode; only size/update rate change.
            if recipe.diffusion != .off {
                let strength: Double
                switch recipe.diffusion {
                case .off: strength = 0
                case .glimmerglass: strength = 0.22
                case .black_pro_mist: strength = 0.38
                case .pro_mist: strength = 0.55
                case .cinebloom: strength = 0.7
                }
                image = image.clampedToExtent().applyingFilter("CIBloom", parameters: ["inputRadius": Double(max(width, height)) * 0.012,
                                                                                      "inputIntensity": strength])
                    .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
            }
            if input?.length != width * height * 16 { input = device.makeBuffer(length: width * height * 16, options: .storageModeShared) }
            if output?.width != width || output?.height != height {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Unorm, width: width, height: height, mipmapped: false)
                descriptor.storageMode = .shared; descriptor.usage = [.shaderWrite, .shaderRead]
                output = device.makeTexture(descriptor: descriptor)
            }
            guard let input, let output, let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder(),
                  let space = linearSpace else { throw MobileFailure.message("无法分配取景缓冲") }
            context.render(image, toBitmap: input.contents(), rowBytes: width * 16, bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBAf, colorSpace: space)
            encoder.setComputePipelineState(pipeline); encoder.setBuffer(input, offset: 0, index: 0)
            var domain = SIMD2<Float>(MobileCameraLookDomain.toe, MobileCameraLookDomain.logRange)
            encoder.setBytes(&domain, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)
            encoder.setTexture(output, index: 0); encoder.setTexture(cube, index: 1)
            encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 8, depth: 1))
            encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
            if let error = command.error { throw error }
            try Task.checkCancellation(); try workGate.check()
            var data = Data(count: width * height * 8)
            data.withUnsafeMutableBytes { output.getBytes($0.baseAddress!, bytesPerRow: width * 8, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0) }
            guard let provider = CGDataProvider(data: data as CFData), let p3 = CGColorSpace(name: CGColorSpace.displayP3),
                  let display = CGImage(width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 64, bytesPerRow: width * 8,
                    space: p3, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue).union(.byteOrder16Little),
                    provider: provider, decode: nil, shouldInterpolate: true, intent: .relativeColorimetric) else { throw MobileFailure.message("无法显示胶片预览") }
            return MobileCameraLookResult(image: display, recipe: recipe, sourceSerial: frame.serial, sourceGeneration: frame.generation)
        }
    }

#if DEBUG
    /// Direct engine evaluation is an independent oracle for table sampling,
    /// not a RAW/video-match oracle. The shader/table path is not used here.
    func directColorReference(_ frame: MobileCameraLookFrame, recipe: MobileCameraRecipe,
                              clampAtWhite: Bool = false) throws -> CGImage {
        try prepare()
        guard recipe.diffusion == .off, let device, let context, let linearSpace,
              let engine, let colors else { throw MobileFailure.message("Colour reference requires diffusion off") }
        let source = MobileCameraLookGeometry.orientedImage(frame, angle: 0, mirrored: false)
        let width = Int(source.extent.width), height = Int(source.extent.height)
        let exposure = try meteredEV(source, mode: recipe.metering, context: context)
        let exposed = source.applyingFilter("CIExposureAdjust", parameters: ["inputEV": exposure])
        guard let buffer = device.makeBuffer(length: width * height * 16, options: .storageModeShared) else {
            throw MobileFailure.message("Cannot allocate colour reference")
        }
        context.render(exposed, toBitmap: buffer.contents(), rowBytes: width * 16,
            bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBAf, colorSpace: linearSpace)
        if clampAtWhite {
            let pixels = buffer.contents().assumingMemoryBound(to: Float.self)
            for i in 0..<(width * height) { for c in 0..<3 { pixels[i * 4 + c] = max(0, min(1, pixels[i * 4 + c])) } }
        }
        var input = spk_device_image(buffer: Unmanaged.passUnretained(buffer as AnyObject).toOpaque(),
                                    width: UInt32(width), height: UInt32(height), channels: 4)
        let json = String(decoding: try JSONEncoder().encode(Self.colorIntent(filmID: recipe.filmID ?? MobileCameraRecipe.defaultFilmID)), as: UTF8.self)
        guard let session = spk_open_device(engine, &input, json, nil) else { throw MobileFailure.message(String(cString: spk_last_error(engine))) }
        workGate.register(session)
        defer { workGate.register(nil); spk_session_release(session) }
        var result = spk_result()
        defer { spk_result_free(&result) }
        guard spk_render_color_samples(session, &result) == SPK_OK, let pixels = result.rgba16 else {
            throw MobileFailure.message(String(cString: spk_last_error(engine)))
        }
        let data = Data(bytes: pixels, count: Int(result.row_stride_px * result.height) * 8)
        guard let provider = CGDataProvider(data: data as CFData), let space = CGColorSpace(name: CGColorSpace.rommrgb),
              let image = CGImage(width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 64,
                bytesPerRow: Int(result.row_stride_px) * 8, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue).union(.byteOrder16Little),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .relativeColorimetric) else {
            throw MobileFailure.message("Cannot read colour reference")
        }
        return try colors.convert(image, engine: engine, target: .p3)
    }
#endif

    private func meteredEV(_ source: CIImage, mode: MobileMeteringMode, context: CIContext) throws -> Double {
        if mode == .custom { return 0 }
        let edge = max(source.extent.width, source.extent.height)
        let w = max(1, Int(64 * source.extent.width / edge)), h = max(1, Int(64 * source.extent.height / edge))
        let image = source.transformed(by: .init(scaleX: CGFloat(w) / source.extent.width, y: CGFloat(h) / source.extent.height))
        guard let linearSpace else { throw MobileFailure.message("缺少测光颜色空间") }
        meter.withUnsafeMutableBytes { context.render(image, toBitmap: $0.baseAddress!, rowBytes: w * 16,
            bounds: CGRect(x: 0, y: 0, width: w, height: h), format: .RGBAf, colorSpace: linearSpace) }
        var luminance = [Double](); luminance.reserveCapacity(w * h)
        for i in 0..<(w * h) { luminance.append(max(0.184 / 4096, Double(meter[i * 4]) * 0.2880402 + Double(meter[i * 4 + 1]) * 0.7118741 + Double(meter[i * 4 + 2]) * 0.0000857)) }
        let sorted = luminance.sorted(), n = luminance.count
        func rank(_ q: Int) -> Double { sorted[q * (n - 1) / 1000] }
        let p1 = rank(10), p99 = rank(990)
        let trimmed = luminance.filter { $0 >= p1 && $0 <= p99 }
        let balanced = -log2(exp(trimmed.reduce(0) { $0 + log($1) } / Double(trimmed.count)) / 0.184)
        var weighted = 0.0, mass = 0.0
        for y in 0..<h { for x in 0..<w {
            let value = luminance[y * w + x]
            if mode == .center && (value < p1 || value > p99) { continue }
            let longEdge = Double(max(w, h))
            let dx = (Double(x) / Double(w) - 0.5) * Double(w) / longEdge
            let dy = (Double(y) / Double(h) - 0.5) * Double(h) / longEdge
            let weight = exp(-(dx * dx + dy * dy) / 0.08)
            mass += weight; weighted += (mode == .center ? log(value) : value) * weight
        } }
        let ev: Double
        switch mode {
        case .custom: ev = 0
        case .balanced: ev = balanced
        case .center: ev = -log2(exp(weighted / mass) / 0.184)
        case .center_weighted: ev = -log2(weighted / mass / 0.184)
        case .protect_highlights: ev = max(balanced - 3, min(balanced, log2(0.184 * pow(2, 2.5) / rank(995))))
        case .protect_shadows: ev = min(balanced + 2, max(balanced, log2(0.184 * pow(2, -3.5) / rank(50))))
        }
        return max(-8, min(8, ev.isFinite ? ev : 0))
    }
}
#endif
