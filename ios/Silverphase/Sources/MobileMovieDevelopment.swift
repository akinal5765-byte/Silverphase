#if SILVERPHASE_APP
@preconcurrency import AVFoundation
import CoreImage
import Foundation
import Metal
import Darwin

enum MobileMovieDevelopment {
    private struct VideoTrack {
        let size: CGSize
        let frameRate: Float
        let hevc: Bool
    }

    private static func inspect(_ track: AVAssetTrack) async throws -> VideoTrack {
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let bounds = CGRect(origin: .zero, size: size).applying(transform)
        let descriptions = try await track.load(.formatDescriptions)
        return VideoTrack(size: CGSize(width: abs(bounds.width).rounded(), height: abs(bounds.height).rounded()),
                          frameRate: try await track.load(.nominalFrameRate),
                          hevc: !descriptions.isEmpty &&
                              descriptions.allSatisfy { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_HEVC })
    }

    private static func validateCapture(_ track: VideoTrack, frameRate: Int?) throws {
        // Older Debug builds may have one pending 1080p clip. Do not apply
        // a newly saved UHD profile retroactively to that original file.
        guard let frameRate else { return }
        let long = max(track.size.width, track.size.height), short = min(track.size.width, track.size.height)
        guard long == CGFloat(MobileMovieProfile.width), short == CGFloat(MobileMovieProfile.height),
              track.frameRate.isFinite, abs(track.frameRate - Float(frameRate)) <= 0.5, track.hevc else {
            let actual = "\(Int(track.size.width))×\(Int(track.size.height)) / \(track.frameRate.formatted()) fps"
            throw MobileFailure.message(TDetached("Recording did not match the selected 4K HEVC profile (\(actual)). The original was kept.",
                                                  "录像未达到所选 4K HEVC 规格（实测 \(actual)），已保留原片。",
                                                  "錄影未達所選 4K HEVC 規格（實測 \(actual)），已保留原片。"))
        }
    }

    static func checkCapture(source: URL, frameRate: Int?) async throws {
        let asset = AVURLAsset(url: source)
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        guard let track = video.first, !audio.isEmpty else {
            throw MobileFailure.message(TDetached("The recording has no playable video or audio track.", "录像没有可播放的视频或音频轨道。", "錄影沒有可播放的影片或音訊軌道。"))
        }
        try validateCapture(await inspect(track), frameRate: frameRate)
    }

    static func export(source: URL, destination: URL, film: String, frameRate: Int?,
                       progress: @escaping @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        guard duration.seconds.isFinite, duration.seconds > 0, let inputTrack = video.first, !audio.isEmpty else {
            throw MobileFailure.message(TDetached("The recording has no playable video or audio track.", "录像没有可播放的视频或音频轨道。", "錄影沒有可播放的影片或音訊軌道。"))
        }
        let input = try await inspect(inputTrack)
        try validateCapture(input, frameRate: frameRate)
        if FileManager.default.fileExists(atPath: destination.path) { return }
        // Start with the still HEIF export's conservative working-set gate.
        // This estimates free headroom, not peak or a measured device budget.
        let allowance = Double(input.size.width * input.size.height) * 90 + 600_000_000
        guard Double(os_proc_available_memory()) > allowance else {
            throw MobileFailure.message(TDetached("There is not enough free memory to develop this video safely. The original was kept.",
                                                  "当前可用内存不足以安全显影这段视频，已保留原片。",
                                                  "目前可用記憶體不足以安全顯影這段影片，已保留原片。"))
        }
        let renderer = try MobileMovieFrameRenderer(film: film)
        let composition = try await AVMutableVideoComposition.videoComposition(
            with: asset, applyingCIFiltersWithHandler: { request in
                do { request.finish(with: try renderer.render(request.sourceImage), context: renderer.context) }
                catch { request.finish(with: error) }
            })
        composition.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        composition.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
        composition.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        // Don't prescribe a landscape size. Verify the actual resulting
        // orientation, raster and rate after encoding, before saving.
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHEVCHighestQuality),
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
              let outputTrack = outputVideo.first, !outputAudio.isEmpty else {
            throw MobileFailure.message(TDetached("The exported video lost duration or an audio/video track; the original was kept.",
                                                  "导出视频时长或音视频轨道不完整，已保留原片。",
                                                  "輸出影片時長或音視訊軌道不完整，已保留原片。"))
        }
        let result = try await inspect(outputTrack)
        guard result.size == input.size, result.frameRate.isFinite, result.frameRate > 0,
              abs(result.frameRate - input.frameRate) <= 0.5, result.hevc else {
            throw MobileFailure.message(TDetached("The rendered movie did not preserve the source dimensions or frame rate. The original was kept.",
                                                  "显影后的文件未保持原片画幅或帧率，已保留原片。",
                                                  "顯影後的檔案未保留原始畫幅或影格率，已保留原片。"))
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
        values["striped"] = .bool(true)
        values["strip_rows"] = .double(256)
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
            guard !extent.isInfinite, !extent.isEmpty, max(extent.width, extent.height) <= CGFloat(MobileMovieProfile.width),
                  min(extent.width, extent.height) <= CGFloat(MobileMovieProfile.height),
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
