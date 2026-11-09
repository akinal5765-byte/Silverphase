#if SILVERPHASE_APP
import CoreImage
import Metal
import Foundation

enum MobileCameraPreviewMode: String, CaseIterable, Sendable {
    case system, approximate, native
    static let key = "mobile.camera.previewMode"
    static let defaultMigrationKey = "mobile.camera.approximateDefault.v1"
    var title: String {
        switch self {
        case .system: "系统取景（关闭效果）"
        case .approximate: "流畅近似预览"
        case .native: "原生引擎预览（实验）"
        }
    }
    static func initial(in defaults: UserDefaults = .standard) -> Self {
        // Promote the accepted approximate pipeline once for existing native
        // preview users. Explicit off stays off; later manual choices persist.
        if !defaults.bool(forKey: defaultMigrationKey) {
            if defaults.string(forKey: key) == Self.native.rawValue {
                defaults.set(Self.approximate.rawValue, forKey: key)
            }
            defaults.set(true, forKey: defaultMigrationKey)
        }
        if let raw = defaults.string(forKey: key), let saved = Self(rawValue: raw) { return saved }
        if defaults.object(forKey: "mobile.camera.filmPreview") != nil,
           !defaults.bool(forKey: "mobile.camera.filmPreview") { return .system }
        return .approximate
    }
}

struct MobileCameraLookTaskID: Hashable {
    let request: MobileCameraRecipe?
    let cameraRetry: Int
    let mode: MobileCameraPreviewMode
}

struct MobileCameraLookResult: @unchecked Sendable {
    let image: CGImage
    let recipe: MobileCameraRecipe
    let sourceSerial: UInt64
    var sourceGeneration: UInt64 = 0
#if DEBUG
    var exposureEV: Double? = nil
#endif

    func snapshot(for selectedRecipe: MobileCameraRecipe) -> CGImage? {
        recipe == selectedRecipe ? image : nil
    }
}

/// A frozen physical-camera transition can reveal only a processed frame
/// from the current new input. Serial numbers alone cannot identify an input.
enum MobileCameraPreviewTransition {
    static func canReveal(mode: MobileCameraPreviewMode, unavailable: Bool,
                          result: MobileCameraLookResult?, recipe: MobileCameraRecipe,
                          frozenGeneration: UInt64, currentGeneration: UInt64) -> Bool {
        if mode == .system || unavailable { return true }
        guard let result, result.snapshot(for: recipe) != nil else { return false }
        return currentGeneration > frozenGeneration && result.sourceGeneration == currentGeneration
    }
}

/// Low-power/thermal policy changes work rate and resolution, never the look.
struct MobileCameraLookBudget: Equatable {
    let longEdge: Int
    let interval: Double
    init(reducedPower: Bool) {
        longEdge = reducedPower ? 480 : 640
        interval = reducedPower ? 1.0 / 15 : 1.0 / 30
    }
}

struct MobileCameraLookFrame: @unchecked Sendable {
    let buffer: CVPixelBuffer
    let rotation: CGFloat
    let serial: UInt64
    var generation: UInt64 = 0
    var receivedUptime = ProcessInfo.processInfo.systemUptime
    var sensorISO: Double? = nil
    var sensorDuration: Double? = nil
}

/// Exactly one retained latest frame. Rendering never queues work on the
/// capture/shutter queue, and a slow display drops frames rather than backlog.
final class MobileCameraLookFrames: @unchecked Sendable {
    private let lock = NSLock()
    private var frame: MobileCameraLookFrame?
    private var serial: UInt64 = 0
    private var generation: UInt64 = 0
    @discardableResult func beginConfiguration() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1; frame = nil
        return generation
    }
    func currentGeneration() -> UInt64 { lock.lock(); defer { lock.unlock() }; return generation }
    func store(_ buffer: CVPixelBuffer, rotation: CGFloat, sensorISO: Double? = nil, sensorDuration: Double? = nil) {
        lock.lock(); defer { lock.unlock() }
        serial &+= 1
        frame = MobileCameraLookFrame(buffer: buffer, rotation: rotation, serial: serial, generation: generation, sensorISO: sensorISO, sensorDuration: sensorDuration)
    }
    func latest() -> MobileCameraLookFrame? { lock.lock(); defer { lock.unlock() }; return frame }
    func clear() { lock.lock(); defer { lock.unlock() }; frame = nil }
}

enum MobileCameraLookGeometry {
    static func orientedImage(_ frame: MobileCameraLookFrame, angle: CGFloat, mirrored: Bool) -> CIImage {
        var image = CIImage(cvPixelBuffer: frame.buffer)
            .transformed(by: CGAffineTransform(rotationAngle: -(angle - frame.rotation) * .pi / 180))
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        if mirrored { image = image.oriented(.upMirrored) }
        return image
    }
}

/// Native metering, film/paper, halation, diffusion and display transform on
/// system video. SDR input cannot justify reconstructing lost scene headroom;
/// the video policy leaves recorded highlights as supplied. Grain/glare are
/// omitted. This is not a RAW scene estimate or a final-print proof.
actor MobileCameraLookEngine {
    nonisolated let workGate = MobileWorkGate()
    private let device = MTLCreateSystemDefaultDevice()
    private var engine: OpaquePointer?
    private var session: OpaquePointer?
    private var sessionRecipe: MobileCameraRecipe?
    private var sessionSize: CGSize = .zero
    private var inputBuffer: MTLBuffer?
#if DEBUG
    private let reusesSession: Bool
    private let forcesUnusedMeter: Bool
    private let headroomForChecks: Double?
    init(reusesSession: Bool = true, forcesUnusedMeter: Bool = false, headroomForChecks: Double? = nil) {
        self.reusesSession = reusesSession; self.forcesUnusedMeter = forcesUnusedMeter
        self.headroomForChecks = headroomForChecks
    }
#endif
    private var context: CIContext?
    private var colors: MobileColorPipeline?

    private func closeSession() {
        workGate.register(nil)
        if let session { spk_session_release(session) }
        session = nil; sessionRecipe = nil; sessionSize = .zero
    }

    func close() {
        closeSession(); inputBuffer = nil
        colors = nil; context?.clearCaches(); context = nil
        if let engine { spk_engine_destroy(engine) }
        engine = nil
    }

    static func intent(_ recipe: MobileCameraRecipe) throws -> [String: WireValue] {
        var values: [String: WireValue] = [:]
        try MobileDocument.applyCapturedRecipe(recipe, to: &values)
        values["grain_active"] = .bool(false)
        values["glare_active"] = .bool(false)
        // Current video output is 8-bit BGRA SDR, already exposed/tone-mapped
        // by the ISP. Treat its highlights as recorded, rather than guessing
        // another four stops of scene energy. This is a preview input policy;
        // captured recipes and native still-file defaults remain untouched.
        values["halation_headroom_ev"] = .double(0)
        return values
    }

    func render(_ frame: MobileCameraLookFrame, angle: CGFloat, mirrored: Bool,
                recipe: MobileCameraRecipe, longEdge: Int) throws -> MobileCameraLookResult {
        try autoreleasepool {
            try Task.checkCancellation(); try workGate.check()
            guard let device else { throw MobileFailure.message("没有 Metal 设备") }
            if engine == nil {
                guard let resources = Bundle.main.url(forResource: "engine", withExtension: nil,
                                                       subdirectory: StockCatalog.resourceDirectory) else {
                    throw MobileFailure.message("缺少随包引擎资源")
                }
                engine = spk_engine_create(resources.path, Unmanaged.passUnretained(device as AnyObject).toOpaque())
            }
            guard let engine else { throw MobileFailure.message("无法准备胶片预览") }
            if context == nil { context = MobileInputColor.context(device: device) }
            if colors == nil { colors = try MobileColorPipeline(device: device) }
            guard let context, let colors, let linear = MobileInputColor.linearProPhoto() else {
                throw MobileFailure.message("无法准备输入颜色空间")
            }
            let source = MobileCameraLookGeometry.orientedImage(frame, angle: angle, mirrored: mirrored)
            // Metering sees a stable 1600px sensor frame, independently of the
            // display tier. Tiny render inputs changed both the meter statistic
            // and the resolved spatial effects when power/quality changed.
            let edge = 1600
            let renderEdge = max(256, min(1600, longEdge))
            let scale = min(1, CGFloat(edge) / max(source.extent.width, source.extent.height))
            let width = max(1, Int((source.extent.width * scale).rounded(.down)))
            let height = max(1, Int((source.extent.height * scale).rounded(.down)))
            let image = source.transformed(by: CGAffineTransform(scaleX: CGFloat(width) / source.extent.width,
                                                                 y: CGFloat(height) / source.extent.height))
            let size = CGSize(width: width, height: height)
            if inputBuffer?.length != width * height * 16 {
                inputBuffer = device.makeBuffer(length: width * height * 16, options: .storageModeShared)
            }
            guard let buffer = inputBuffer else {
                throw MobileFailure.message("胶片预览内存不足")
            }
            // The exact same ColorSync/linear ProPhoto boundary as file decode.
            context.render(image, toBitmap: buffer.contents(), rowBytes: width * 16,
                           bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBAf, colorSpace: linear)
            var input = spk_device_image(buffer: Unmanaged.passUnretained(buffer as AnyObject).toOpaque(),
                                         width: UInt32(width), height: UInt32(height), channels: 4)
            if sessionRecipe != recipe || sessionSize != size { closeSession() }
            if let session {
                guard spk_replace_device_frame(session, &input) == SPK_OK else {
                    throw MobileFailure.message(String(cString: spk_last_error(engine)))
                }
            } else {
                var wire = try MobileProcessContract.wire(Self.intent(recipe), aspect: Double(width) / Double(height))
                wire["input_color_space"] = .string("ProPhoto RGB")
                wire["input_cctf_decoding"] = .bool(false)
                wire["output_color_space"] = .string("ProPhoto RGB")
                wire["output_cctf_encoding"] = .bool(true)
                wire["product_defaults"] = .bool(true)
#if DEBUG
                if let headroomForChecks { wire["halation_headroom_ev"] = .double(headroomForChecks) }
#endif
                let json = String(decoding: try JSONEncoder().encode(wire), as: UTF8.self)
                guard let opened = spk_open_device(engine, &input, json, nil) else {
                    throw MobileFailure.message(String(cString: spk_last_error(engine)))
                }
                session = opened; sessionRecipe = recipe; sessionSize = size
            }
            guard let session else { throw MobileFailure.message("无法准备连续取景") }
            workGate.register(session)
            defer {
                workGate.register(nil)
#if DEBUG
                if !reusesSession { closeSession() }
#endif
            }
            try Task.checkCancellation(); try workGate.check()
#if DEBUG
            // Reproduce the previous unused analysis for an interleaved timing
            // control, without modifying saved exposure or the rendered pixels.
            if forcesUnusedMeter && recipe.metering == .custom {
                guard spk_solve(session, "exposure", nil) == SPK_OK else {
                    throw MobileFailure.message(String(cString: spk_last_error(engine)))
                }
            }
#endif
            var output = spk_result()
            defer { spk_result_free(&output) }
            guard spk_render_viewfinder(session, UInt32(renderEdge), &output) == SPK_OK, let pixels = output.rgba16 else {
                throw MobileFailure.message(String(cString: spk_last_error(engine)))
            }
            try Task.checkCancellation(); try workGate.check()
            // Copy before retiring native result/session: displayed and frozen
            // frames must remain immutable across later renders and shutdown.
            let data = Data(bytes: pixels, count: Int(output.row_stride_px * output.height) * 8)
            guard let provider = CGDataProvider(data: data as CFData),
                  let space = CGColorSpace(name: CGColorSpace.rommrgb),
                  let working = CGImage(width: Int(output.width), height: Int(output.height), bitsPerComponent: 16,
                    bitsPerPixel: 64, bytesPerRow: Int(output.row_stride_px) * 8, space: space,
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue).union(.byteOrder16Little),
                    provider: provider, decode: nil, shouldInterpolate: true, intent: .relativeColorimetric) else {
                throw MobileFailure.message("无法读取胶片预览")
            }
            let display = try colors.convert(working, engine: engine, target: .p3)
            try Task.checkCancellation(); try workGate.check()
            var result = MobileCameraLookResult(image: display, recipe: recipe, sourceSerial: frame.serial, sourceGeneration: frame.generation)
#if DEBUG
            var progress: UnsafeMutablePointer<CChar>?
            if spk_progress(session, nil, &progress) == SPK_OK, let progress {
                defer { spk_string_free(progress) }
                let object = try JSONSerialization.jsonObject(with: Data(String(cString: progress).utf8)) as? [String: Any]
                result.exposureEV = object?["auto_exposure_ev"] as? Double
            }
#endif
            return result
        }
    }
}
#endif
