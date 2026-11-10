import SwiftUI
import MetalKit

/// Immutable, preview-sized presentation resources. Engine/session can close
/// without invalidating them; no engine work or image readback per frame.
final class MobileDevelopmentAssets: @unchecked Sendable {
    let id = UUID()
    let device: MTLDevice
    let print: MTLTexture
    let pipeline: MTLRenderPipelineState
#if SILVERPHASE_APP
    let scan: MTLTexture
    let scanStyle: Bool
    let transform: MTLComputePipelineState
    let setup: (Data, MTLBuffer)
#endif
#if DEBUG
    private let auditLock = NSLock()
    private var submittedFrames = 0
    private var lastProgress: Float = -1
    private var presentationError = ""
    func recordFrame(_ progress: Float) { auditLock.lock(); defer { auditLock.unlock() }; submittedFrames += 1; lastProgress = progress }
    func recordError(_ error: String) { auditLock.lock(); defer { auditLock.unlock() }; presentationError = error }
    func presentationAudit() -> [String: Any] {
        auditLock.lock(); defer { auditLock.unlock() }
        return ["submittedFrames": submittedFrames, "lastProgress": lastProgress, "error": presentationError]
    }
#endif
    static let paperSeconds = 2.2
#if SILVERPHASE_APP
    static let scanSeconds = 0.35
    var duration: Double { scanStyle ? Self.scanSeconds : Self.paperSeconds }
    init(device: MTLDevice, print: MTLTexture, scan: MTLTexture, transform: MTLComputePipelineState,
         setup: (Data, MTLBuffer), scanStyle: Bool) throws {
        self.device = device; self.print = print; self.scan = scan
        self.transform = transform; self.setup = setup; self.scanStyle = scanStyle
        guard let url = Bundle.main.url(forResource: "SilverphaseUI", withExtension: "metallib", subdirectory: StockCatalog.resourceDirectory) else { throw MobileFailure.message(TDetached("The development animation shader is missing", "缺少显影动画着色器", "缺少顯影動畫著色器")) }
        let library = try device.makeLibrary(URL: url)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "mobileDevelopVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "mobileDevelopFragment")
        descriptor.colorAttachments[0].pixelFormat = .rgba16Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }
#else
    var duration: Double { 0.45 }

    init(photo: CGImage) throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let colorSpace = CGColorSpace(name: CGColorSpace.rommrgb),
              let pixels = CGContext(data: nil, width: photo.width, height: photo.height,
                                     bitsPerComponent: 8, bytesPerRow: photo.width * 4, space: colorSpace,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        else { throw MobileFailure.message(TDetached("The development preview could not be prepared", "无法准备显影预览", "無法準備顯影預覽")) }
        pixels.draw(photo, in: CGRect(x: 0, y: 0, width: photo.width, height: photo.height))
        let texture = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: photo.width,
                                                               height: photo.height, mipmapped: false)
        guard let image = device.makeTexture(descriptor: texture), let data = pixels.data else {
            throw MobileFailure.message(TDetached("The development textures could not be prepared", "无法准备显影纹理", "無法準備顯影紋理"))
        }
        image.replace(region: MTLRegionMake2D(0, 0, photo.width, photo.height), mipmapLevel: 0,
                      withBytes: data, bytesPerRow: pixels.bytesPerRow)
        self.device = device
        self.print = image
        let library = try device.makeDefaultLibrary(bundle: .main)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "mobileDevelopVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "lockedCameraDevelopFragment")
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }
#endif
    func encode(command: MTLCommandBuffer, working: MTLTexture, output: MTLTexture, progress: Float) throws {
        let descriptor = MTLRenderPassDescriptor()
#if SILVERPHASE_APP
        descriptor.colorAttachments[0].texture = working
#else
        descriptor.colorAttachments[0].texture = output
#endif
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        guard let render = command.makeRenderCommandEncoder(descriptor: descriptor) else { throw MobileFailure.message(TDetached("The development animation could not be submitted", "无法提交显影动画", "無法提交顯影動畫")) }
        render.setRenderPipelineState(pipeline)
        var t = progress
#if SILVERPHASE_APP
        render.setFragmentTexture(print, index: 0); render.setFragmentTexture(scan, index: 1)
        var style: UInt32 = scanStyle ? 1 : 0
        render.setFragmentBytes(&style, length: 4, index: 1)
#else
        render.setFragmentTexture(print, index: 0)
#endif
        render.setFragmentBytes(&t, length: 4, index: 0)
        render.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        render.endEncoding()
#if SILVERPHASE_APP
        guard let stats = device.makeBuffer(length: 16, options: .storageModeShared),
              let encoder = command.makeComputeCommandEncoder() else { throw MobileFailure.message(TDetached("The development animation colour could not be converted", "无法转换显影动画色彩", "無法轉換顯影動畫色彩")) }
        memset(stats.contents(), 0, 16)
        encoder.setComputePipelineState(transform)
        encoder.setTexture(working, index: 0); encoder.setTexture(output, index: 1)
        setup.0.withUnsafeBytes { encoder.setBytes($0.baseAddress!, length: $0.count, index: 0) }
        encoder.setBuffer(setup.1, offset: 0, index: 1); encoder.setBuffer(stats, offset: 0, index: 2)
        let width = transform.threadExecutionWidth
        encoder.dispatchThreads(MTLSize(width: output.width, height: output.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: min(8, transform.maxTotalThreadsPerThreadgroup / width), depth: 1))
        encoder.endEncoding()
#endif
    }
#if DEBUG && SILVERPHASE_APP
    func auditFrame(_ progress: Float) throws -> Data {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Unorm, width: print.width, height: print.height, mipmapped: false)
        descriptor.storageMode = .shared; descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        guard let working = device.makeTexture(descriptor: descriptor), let output = device.makeTexture(descriptor: descriptor),
              let command = device.makeCommandQueue()?.makeCommandBuffer() else { throw MobileFailure.message(TDetached("The development animation check could not allocate textures", "显影动画检查无法分配纹理", "顯影動畫檢查無法分配紋理")) }
        try encode(command: command, working: working, output: output, progress: progress)
        command.commit(); command.waitUntilCompleted()
        if let error = command.error { throw error }
        var data = Data(count: print.width * print.height * 8)
        data.withUnsafeMutableBytes { output.getBytes($0.baseAddress!, bytesPerRow: print.width * 8, from: MTLRegionMake2D(0, 0, print.width, print.height), mipmapLevel: 0) }
        return data
    }
#endif
}

struct MobileDevelopmentView: UIViewRepresentable {
    let assets: MobileDevelopmentAssets
    let running: Bool
    var playbackRate: Double = 1
    let finished: () -> Void
    func makeCoordinator() -> Coordinator {
        Coordinator(assets: assets, duration: assets.duration / playbackRate, finished: finished)
    }
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: assets.device)
        view.colorPixelFormat = .rgba16Float
#if SILVERPHASE_APP
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
#else
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
#endif
        view.framebufferOnly = false; view.isOpaque = true
        view.isUserInteractionEnabled = false // all canvas gestures belong to SwiftUI
        view.isPaused = true; view.enableSetNeedsDisplay = true
        view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator
        return view
    }
    func updateUIView(_ view: MTKView, context: Context) {
        let coordinator = context.coordinator
        coordinator.finished = finished
        if running && coordinator.start == nil { coordinator.start = CACurrentMediaTime() }
        view.enableSetNeedsDisplay = !running; view.isPaused = !running
        if !running { view.setNeedsDisplay() }
    }
    static func dismantleUIView(_ view: MTKView, coordinator: Coordinator) {
        view.isPaused = true; view.delegate = nil; coordinator.working = nil
    }
    @MainActor final class Coordinator: NSObject, MTKViewDelegate {
        let assets: MobileDevelopmentAssets
        let duration: Double
        let queue: MTLCommandQueue?
        var working: MTLTexture?
        var start: CFTimeInterval?
        var completed = false
        var finished: () -> Void
        init(assets: MobileDevelopmentAssets, duration: Double, finished: @escaping () -> Void) {
            self.assets = assets
            self.duration = duration
            self.finished = finished
            queue = assets.device.makeCommandQueue()
        }
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { working = nil }
        func draw(in view: MTKView) {
            guard !completed else { return }
            guard !UIAccessibility.isReduceMotionEnabled else { complete(view); return }
            guard let drawable = view.currentDrawable, let command = queue?.makeCommandBuffer() else {
#if DEBUG
                assets.recordError("Drawable/command unavailable")
#endif
                complete(view); return
            }
#if SILVERPHASE_APP
            let width = drawable.texture.width, height = drawable.texture.height
            if working?.width != width || working?.height != height {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Unorm, width: width, height: height, mipmapped: false)
                descriptor.storageMode = .private; descriptor.usage = [.renderTarget, .shaderRead]
                working = assets.device.makeTexture(descriptor: descriptor)
            }
            guard let working else { complete(view); return }
#else
            let working = drawable.texture
#endif
            let t = Float(start.map { min(1, max(0, (CACurrentMediaTime() - $0) / duration)) } ?? 0)
            do { try assets.encode(command: command, working: working, output: drawable.texture, progress: t) }
            catch {
#if DEBUG
                assets.recordError(error.localizedDescription)
#endif
                complete(view); return
            }
            command.present(drawable); command.commit()
#if DEBUG
            assets.recordFrame(t)
#endif
            if t >= 1 { complete(view) }
        }
        private func complete(_ view: MTKView) {
            guard !completed else { return }
            completed = true; view.isPaused = true
            // Avoid changing observable document state in a SwiftUI update/draw.
            Task { @MainActor [finished] in await Task.yield(); finished() }
        }
    }
}
