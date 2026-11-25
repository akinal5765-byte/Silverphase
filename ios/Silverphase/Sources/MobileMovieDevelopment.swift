#if SILVERPHASE_APP
@preconcurrency import AVFoundation
import CoreImage
import Foundation
import Metal

enum MobileMovieDevelopment {
    static func export(source: URL, destination: URL, film: String,
                       progress: @escaping @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        guard duration.seconds.isFinite, duration.seconds > 0, !video.isEmpty, !audio.isEmpty else {
            throw MobileFailure.message(TDetached("The recording has no playable video or audio track.", "录像没有可播放的视频或音频轨道。", "錄影沒有可播放的影片或音訊軌道。"))
        }
        if FileManager.default.fileExists(atPath: destination.path) { return }
        let renderer = try MobileMovieFrameRenderer(film: film)
        let composition = try await AVMutableVideoComposition.videoComposition(
            with: asset, applyingCIFiltersWithHandler: { request in
                do { request.finish(with: try renderer.render(request.sourceImage), context: renderer.context) }
                catch { request.finish(with: error) }
            })
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        // Highest-quality preserves the asset's portrait/landscape dimensions;
        // a fixed landscape preset can add padding or scale vertical video.
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality),
              exporter.supportedFileTypes.contains(.mov) else {
            throw MobileFailure.message(TDetached("The video exporter could not be configured.", "无法配置视频导出器。", "無法設定影片輸出器。"))
        }
        exporter.videoComposition = composition
        let partial = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".mov")
        let progressTask = Task {
            for await state in exporter.states(updateInterval: 0.5) {
                if Task.isCancelled { break }
                if case .exporting(let value) = state { progress(value.fractionCompleted) }
            }
        }
        defer {
            progressTask.cancel()
            try? FileManager.default.removeItem(at: partial)
        }
        try await exporter.export(to: partial, as: .mov)
        let output = AVURLAsset(url: partial)
        let outputDuration = try await output.load(.duration)
        let outputVideo = try await output.loadTracks(withMediaType: .video)
        let outputAudio = try await output.loadTracks(withMediaType: .audio)
        guard outputDuration.seconds.isFinite, abs(outputDuration.seconds - duration.seconds) <= 0.15,
              !outputVideo.isEmpty, !outputAudio.isEmpty else {
            throw MobileFailure.message(TDetached("The exported video lost duration or an audio/video track; the original was kept.",
                                                  "导出视频时长或音视频轨道不完整，已保留原片。",
                                                  "輸出影片時長或音視訊軌道不完整，已保留原片。"))
        }
        try FileManager.default.moveItem(at: partial, to: destination)
    }
}

// The composition can request frames concurrently. Serialize each engine
// session and use AVFoundation's source timestamps, not wall-clock preview
// cadence. Only frame-sized buffers are allocated, independent of duration.
private final class MobileMovieFrameRenderer: @unchecked Sendable {
    let context: CIContext
    private let device: MTLDevice
    private let inputSpace: CGColorSpace
    private let outputSpace: CGColorSpace
    private let engine: OpaquePointer
    private let film: String
    private let lock = NSLock()
    private var session: OpaquePointer?
    private var input: MTLBuffer?
    private var size: CGSize = .zero

    init(film: String) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let linear = MobileInputColor.linearProPhoto(),
              let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let resources = Bundle.main.url(forResource: "engine", withExtension: nil, subdirectory: StockCatalog.resourceDirectory),
              let engine = spk_engine_create(resources.path, Unmanaged.passUnretained(device as AnyObject).toOpaque()) else {
            throw MobileFailure.message(TDetached("The native film engine is unavailable.", "原生胶片引擎不可用。", "原生膠片引擎無法使用。"))
        }
        self.device = device
        context = MobileInputColor.context(device: device)
        inputSpace = linear
        outputSpace = srgb
        self.engine = engine
        self.film = film
    }

    deinit {
        if let session { spk_session_release(session) }
        spk_engine_destroy(engine)
    }

    private func recipe(aspect: Double) throws -> String {
        var values: [String: WireValue] = [:]
        // Camera AE/WB remain baked into SDR video. Re-running film metering
        // or still-photo matching on every frame would cause exposure pumping.
        try MobileDocument.applyCapturedRecipe(MobileCameraRecipe(filmID: film, metering: .custom), to: &values)
        values = try MobileProcessContract.wire(values, aspect: aspect)
        values["input_color_space"] = .string("ProPhoto RGB")
        values["input_cctf_decoding"] = .bool(false)
        values["output_color_space"] = .string("sRGB")
        values["output_cctf_encoding"] = .bool(true)
        values["auto_exposure"] = .bool(false)
        values["scene_latitude_active"] = .bool(false)
        values["extended_dynamic_range"] = .bool(false)
        values["glare_active"] = .bool(false) // The still glare field is independently randomized.
        values["overscan_active"] = .bool(false)
        values["date_imprint_active"] = .bool(false)
        values["product_defaults"] = .bool(true)
        return String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
    }

    func render(_ frame: CIImage) throws -> CIImage {
        lock.lock()
        defer { lock.unlock() }
        return try autoreleasepool {
            let extent = frame.extent
            guard !extent.isInfinite, !extent.isEmpty, extent.width <= 1920, extent.height <= 1920,
                  extent.width.rounded() == extent.width, extent.height.rounded() == extent.height else {
                throw MobileFailure.message(TDetached("Unsupported video frame size.", "不支持的视频帧尺寸。", "不支援的影片畫面尺寸。"))
            }
            let width = Int(extent.width), height = Int(extent.height)
            if extent.size != size {
                if let session { spk_session_release(session); self.session = nil }
                input = device.makeBuffer(length: width * height * 16, options: .storageModeShared)
                size = extent.size
            }
            guard let input else { throw MobileFailure.message("Could not allocate the video frame buffer.") }
            context.render(frame, toBitmap: input.contents(), rowBytes: width * 16, bounds: extent, format: .RGBAf, colorSpace: inputSpace)
            var pixels = spk_device_image(buffer: Unmanaged.passUnretained(input as AnyObject).toOpaque(),
                                          width: UInt32(width), height: UInt32(height), channels: 4)
            if let session {
                guard spk_replace_device_frame(session, &pixels) == SPK_OK else { throw failure() }
            } else {
                let json = try recipe(aspect: Double(width) / Double(height))
                guard let opened = spk_open_device(engine, &pixels, json, nil) else { throw failure() }
                session = opened
            }
            guard let session else { throw failure() }
            var result = spk_result()
            defer { spk_result_free(&result) }
            guard spk_render(session, "full", &result) == SPK_OK, let source = result.rgba16,
                  result.width == UInt32(width), result.height == UInt32(height) else { throw failure() }
            // AVFoundation may retain the frame after this callback. Copy
            // bytes before releasing the result texture, not its pointer.
            let stride = Int(result.row_stride_px) * 8
            let bytes = Data(bytes: source, count: stride * height)
            guard let provider = CGDataProvider(data: bytes as CFData),
                  let image = CGImage(width: width, height: height, bitsPerComponent: 16, bitsPerPixel: 64,
                                      bytesPerRow: stride, space: outputSpace,
                                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue).union(.byteOrder16Little),
                                      provider: provider, decode: nil, shouldInterpolate: false, intent: .relativeColorimetric)
            else { throw MobileFailure.message("Could not read the developed video frame.") }
            return CIImage(cgImage: image).transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
        }
    }

    private func failure() -> MobileFailure {
        .message(String(cString: spk_last_error(engine)))
    }
}
#endif
