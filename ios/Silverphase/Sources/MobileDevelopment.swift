import SwiftUI
import MetalKit

/// Immutable, preview-sized presentation resources. Engine/session can close
/// without invalidating them; no engine work or image readback per frame.
final class MobileDevelopmentAssets: @unchecked Sendable {
    let id = UUID()
    let device: MTLDevice
    let print: MTLTexture
    let scan: MTLTexture
    let scanStyle: Bool
    let pipeline: MTLRenderPipelineState
    let transform: MTLComputePipelineState
    let setup: (Data, MTLBuffer)
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
    static let scanSeconds = 0.35
    var duration: Double { scanStyle ? Self.scanSeconds : Self.paperSeconds }
    init(device: MTLDevice, print: MTLTexture, scan: MTLTexture, transform: MTLComputePipelineState,
         setup: (Data, MTLBuffer), scanStyle: Bool) throws {
        self.device = device; self.print = print; self.scan = scan
        self.transform = transform; self.setup = setup; self.scanStyle = scanStyle
        guard let url = Bundle.main.url(forResource: "SilverphaseUI", withExtension: "metallib", subdirectory: StockCatalog.resourceDirectory) else { throw MobileFailure.message("缺少显影动画着色器") }
        let library = try device.makeLibrary(URL: url)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "mobileDevelopVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "mobileDevelopFragment")
        descriptor.colorAttachments[0].pixelFormat = .rgba16Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }
    func encode(command: MTLCommandBuffer, working: MTLTexture, output: MTLTexture, progress: Float) throws {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = working
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        guard let render = command.makeRenderCommandEncoder(descriptor: descriptor) else { throw MobileFailure.message("无法提交显影动画") }
        render.setRenderPipelineState(pipeline)
        render.setFragmentTexture(print, index: 0); render.setFragmentTexture(scan, index: 1)
        var t = progress, style: UInt32 = scanStyle ? 1 : 0
        render.setFragmentBytes(&t, length: 4, index: 0); render.setFragmentBytes(&style, length: 4, index: 1)
        render.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        render.endEncoding()
        guard let stats = device.makeBuffer(length: 16, options: .storageModeShared),
              let encoder = command.makeComputeCommandEncoder() else { throw MobileFailure.message("无法转换显影动画色彩") }
        memset(stats.contents(), 0, 16)
        encoder.setComputePipelineState(transform)
        encoder.setTexture(working, index: 0); encoder.setTexture(output, index: 1)
        setup.0.withUnsafeBytes { encoder.setBytes($0.baseAddress!, length: $0.count, index: 0) }
        encoder.setBuffer(setup.1, offset: 0, index: 1); encoder.setBuffer(stats, offset: 0, index: 2)
        let width = transform.threadExecutionWidth
        encoder.dispatchThreads(MTLSize(width: output.width, height: output.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: min(8, transform.maxTotalThreadsPerThreadgroup / width), depth: 1))
        encoder.endEncoding()
    }
#if DEBUG
    func auditFrame(_ progress: Float) throws -> Data {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Unorm, width: print.width, height: print.height, mipmapped: false)
        descriptor.storageMode = .shared; descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        guard let working = device.makeTexture(descriptor: descriptor), let output = device.makeTexture(descriptor: descriptor),
              let command = device.makeCommandQueue()?.makeCommandBuffer() else { throw MobileFailure.message("显影动画检查无法分配纹理") }
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
    let finished: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(assets: assets, finished: finished) }
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: assets.device)
        view.colorPixelFormat = .rgba16Float
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
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
        let queue: MTLCommandQueue?
        var working: MTLTexture?
        var start: CFTimeInterval?
        var completed = false
        var finished: () -> Void
        init(assets: MobileDevelopmentAssets, finished: @escaping () -> Void) {
            self.assets = assets; self.finished = finished; queue = assets.device.makeCommandQueue()
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
            let width = drawable.texture.width, height = drawable.texture.height
            if working?.width != width || working?.height != height {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Unorm, width: width, height: height, mipmapped: false)
                descriptor.storageMode = .private; descriptor.usage = [.renderTarget, .shaderRead]
                working = assets.device.makeTexture(descriptor: descriptor)
            }
            guard let working else { complete(view); return }
            let t = Float(start.map { min(1, max(0, (CACurrentMediaTime() - $0) / assets.duration)) } ?? 0)
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
