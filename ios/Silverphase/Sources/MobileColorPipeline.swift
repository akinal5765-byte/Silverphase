import Foundation
import Metal
import CoreGraphics

/// Runs the desktop outputTransform shader unchanged. No second lightness
/// shoulder and no Core Graphics clipping in place of the desktop gamut map.
final class MobileColorPipeline {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let transform: MTLComputePipelineState
    private let cineon: MTLComputePipelineState
    private var lut: MTLTexture?
    private var setups: [String: (Data, MTLBuffer)] = [:]
    init(device: MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue(),
              let url = Bundle.main.url(forResource: "SilverphaseUI", withExtension: "metallib", subdirectory: StockCatalog.resourceDirectory) else { throw MobileFailure.message("缺少输出色彩着色器") }
        self.queue = queue
        let library = try device.makeLibrary(URL: url)
        guard let output = library.makeFunction(name: "outputTransform"), let view = library.makeFunction(name: "mobileCineonView") else { throw MobileFailure.message("无法创建输出色彩着色器") }
        transform = try device.makeComputePipelineState(function: output)
        cineon = try device.makeComputePipelineState(function: view)
    }
    private func texture(_ image: CGImage) throws -> MTLTexture {
        guard image.bitsPerComponent == 16, let bytes = image.dataProvider?.data else { throw MobileFailure.message("输出输入必须为16位") }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Unorm, width: image.width, height: image.height, mipmapped: false)
        d.storageMode = .shared; d.usage = [.shaderRead, .shaderWrite]
        guard let t = device.makeTexture(descriptor: d), let p = CFDataGetBytePtr(bytes) else { throw MobileFailure.message("无法分配输出色彩纹理") }
        t.replace(region: MTLRegionMake2D(0, 0, image.width, image.height), mipmapLevel: 0, withBytes: p, bytesPerRow: image.bytesPerRow)
        return t
    }
    private func output(_ src: MTLTexture) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Unorm, width: src.width, height: src.height, mipmapped: false)
        d.storageMode = .shared; d.usage = [.shaderRead, .shaderWrite]
        guard let value = device.makeTexture(descriptor: d) else { throw MobileFailure.message("输出色彩纹理内存不足") }
        return value
    }
    private func image(_ texture: MTLTexture, space: CGColorSpace) throws -> CGImage {
        var bytes = Data(count: texture.width * texture.height * 8)
        bytes.withUnsafeMutableBytes { p in texture.getBytes(p.baseAddress!, bytesPerRow: texture.width * 8, from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0) }
        guard let provider = CGDataProvider(data: bytes as CFData),
              let image = CGImage(width: texture.width, height: texture.height, bitsPerComponent: 16, bitsPerPixel: 64, bytesPerRow: texture.width * 8, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue).union(.byteOrder16Little), provider: provider, decode: nil, shouldInterpolate: true, intent: .relativeColorimetric) else { throw MobileFailure.message("无法创建输出图像") }
        return image
    }
    private func dispatch(_ pipeline: MTLComputePipelineState, source: MTLTexture, destination: MTLTexture, encode: (MTLComputeCommandEncoder) -> Void) throws {
        guard let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else { throw MobileFailure.message("无法提交输出色彩处理") }
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(source, index: 0); encoder.setTexture(destination, index: 1)
        encode(encoder)
        let w = pipeline.threadExecutionWidth, h = min(8, pipeline.maxTotalThreadsPerThreadgroup / w)
        encoder.dispatchThreads(MTLSize(width: source.width, height: source.height, depth: 1), threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1))
        encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
        if let error = command.error { throw error }
    }
    func convert(_ source: CGImage, engine: OpaquePointer?, target: MobileOutputSpace) throws -> CGImage {
        try autoreleasepool { try convertInPool(source, engine: engine, target: target) }
    }
    private func convertInPool(_ source: CGImage, engine: OpaquePointer?, target: MobileOutputSpace) throws -> CGImage {
        if target == .prophoto { return source }
        let setup = try outputSetup(engine: engine, target: target)
        let src = try texture(source), dst = try output(src)
        guard let stats = device.makeBuffer(length: 16, options: .storageModeShared) else { throw MobileFailure.message("无法分配输出统计") }
        memset(stats.contents(), 0, 16)
        try dispatch(transform, source: src, destination: dst) { encoder in
            setup.0.withUnsafeBytes { encoder.setBytes($0.baseAddress!, length: $0.count, index: 0) }
            encoder.setBuffer(setup.1, offset: 0, index: 1); encoder.setBuffer(stats, offset: 0, index: 2)
        }
        return try image(dst, space: target.cgSpace)
    }
    private func outputSetup(engine: OpaquePointer?, target: MobileOutputSpace) throws -> (Data, MTLBuffer) {
        let setup: (Data, MTLBuffer)
        if let cached = setups[target.rawValue] { setup = cached }
        else {
            guard let engine else { throw MobileFailure.message("未准备输出色彩配置") }
            var reply: UnsafeMutablePointer<CChar>?
            var cmax: UnsafePointer<Float>?
            var count: UInt32 = 0
            guard spk_output_transform(engine, "ProPhoto RGB", target.rawValue, #"{"lightness_compression_active":false}"#, &reply, &cmax, &count) == SPK_OK,
                  let reply, let cmax else { throw MobileFailure.message(String(cString: spk_last_error(engine))) }
            defer { spk_string_free(reply) }
            let object = try JSONSerialization.jsonObject(with: Data(String(cString: reply).utf8)) as? [String: Any] ?? [:]
            let g = object["gamut_compress"] as? [String: Any] ?? [:]
            let arrays = [object["matrix"] as? [Double] ?? [], g["m_to_xyz"] as? [Double] ?? [], g["m_to_rgb"] as? [Double] ?? [], g["k"] as? [Double] ?? []]
            guard arrays.map(\.count) == [9, 9, 9, 22], let table = device.makeBuffer(bytes: cmax, length: Int(count) * 4, options: .storageModeShared) else { throw MobileFailure.message("输出色彩参数不完整") }
            let floats = arrays.flatMap { $0 }.map(Float.init)
            var packed = floats.withUnsafeBytes { Data($0) }
            let integers: [UInt32] = [UInt32(object["source_cctf_mode"] as? Int ?? 0), UInt32(object["target_cctf_mode"] as? Int ?? 0),
                                      g["algorithm"] as? String == "off" ? 0 : 1, g["lightness_compression_active"] as? Bool == true ? 1 : 0,
                                      UInt32(g["cmax_rows"] as? Int ?? 0), UInt32(g["cmax_cols"] as? Int ?? 0), 0, 0]
            integers.withUnsafeBytes { packed.append(contentsOf: $0) }
            guard packed.count == 228 else { throw MobileFailure.message("输出色彩参数布局不匹配") }
            setup = (packed, table); setups[target.rawValue] = setup
        }
        return setup
    }
    func developmentAssets(print: CGImage, scan: CGImage, engine: OpaquePointer?, scanStyle: Bool) throws -> MobileDevelopmentAssets {
        let setup = try outputSetup(engine: engine, target: .p3)
        return try MobileDevelopmentAssets(device: device, print: texture(print), scan: texture(scan),
                                           transform: transform, setup: setup, scanStyle: scanStyle)
    }
    func cineonView(_ source: CGImage) throws -> CGImage {
        try autoreleasepool { try cineonViewInPool(source) }
    }
    private func cineonViewInPool(_ source: CGImage) throws -> CGImage {
        if lut == nil {
            guard let url = Bundle.main.url(forResource: "SpektraLab DI view, Cineon to ProPhoto RGB", withExtension: "cube", subdirectory: StockCatalog.resourceDirectory + "/DI") else { throw MobileFailure.message("缺少数字中间片视图 LUT") }
            var size = 0, values: [Float] = []
            for line in try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline) {
                if line.hasPrefix("LUT_3D_SIZE ") { size = Int(line.split(separator: " ").last!) ?? 0 }
                let components = line.split(whereSeparator: \.isWhitespace)
                if components.count == 3, let r = Float(components[0]), let g = Float(components[1]), let b = Float(components[2]) { values += [r, g, b, 1] }
            }
            guard size > 1, values.count == size * size * size * 4 else { throw MobileFailure.message("数字中间片 LUT 不完整") }
            let d = MTLTextureDescriptor(); d.textureType = .type3D; d.pixelFormat = .rgba32Float; d.width = size; d.height = size; d.depth = size; d.storageMode = .shared; d.usage = .shaderRead
            guard let texture = device.makeTexture(descriptor: d) else { throw MobileFailure.message("无法分配数字中间片 LUT") }
            values.withUnsafeBytes { texture.replace(region: MTLRegionMake3D(0, 0, 0, size, size, size), mipmapLevel: 0, slice: 0, withBytes: $0.baseAddress!, bytesPerRow: size * 16, bytesPerImage: size * size * 16) }
            lut = texture
        }
        let src = try texture(source), dst = try output(src)
        try dispatch(cineon, source: src, destination: dst) { $0.setTexture(lut, index: 2) }
        return try image(dst, space: CGColorSpace(name: CGColorSpace.rommrgb)!)
    }
}
