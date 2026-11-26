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

    private static func validateCapture(_ track: VideoTrack, expected: MobileMovieProfile?) throws {
        // Older Debug builds may have one pending 1080p clip. Do not apply
        // a newly saved UHD profile retroactively to that original file.
        guard let expected else { return }
        let long = max(track.size.width, track.size.height), short = min(track.size.width, track.size.height)
        guard long == CGFloat(expected.raster.width), short == CGFloat(expected.raster.height),
              track.frameRate.isFinite, abs(Double(track.frameRate) - expected.fps) <= 0.5, track.hevc else {
            let actual = "\(Int(track.size.width))×\(Int(track.size.height)) / \(track.frameRate.formatted()) fps"
            throw MobileFailure.message(TDetached("Recording did not match the selected HEVC format (\(actual)). The original was kept.",
                                                  "录像未达到所选 HEVC 规格（实测 \(actual)），已保留原片。",
                                                  "錄影未達所選 HEVC 規格（實測 \(actual)），已保留原片。"))
        }
    }

    static func checkCapture(source: URL, expected: MobileMovieProfile?) async throws {
        let asset = AVURLAsset(url: source)
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        guard let track = video.first, !audio.isEmpty else {
            throw MobileFailure.message(TDetached("The recording has no playable video or audio track.", "录像没有可播放的视频或音频轨道。", "錄影沒有可播放的影片或音訊軌道。"))
        }
        try validateCapture(await inspect(track), expected: expected)
    }

    @MainActor static func export(source: URL, destination: URL, film: String, expected: MobileMovieProfile?,
                       progress: @escaping @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        guard duration.seconds.isFinite, duration.seconds > 0, let inputTrack = video.first, !audio.isEmpty else {
            throw MobileFailure.message(TDetached("The recording has no playable video or audio track.", "录像没有可播放的视频或音频轨道。", "錄影沒有可播放的影片或音訊軌道。"))
        }
        let input = try await inspect(inputTrack)
        try validateCapture(input, expected: expected)
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
        // Keep the source's sample timing rather than forcing a synthetic 30 fps grid.
        composition.sourceTrackIDForFrameTiming = inputTrack.trackID
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
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: partial, to: destination)
    }
}

#if DEBUG
extension MobileMovieDevelopment {
#if targetEnvironment(simulator)
    @MainActor static func runPhotoSaveRegression() async {
        let directory = URL.documentsDirectory
        let report = directory.appending(path: "video-photo-save-report.json")
        let fixture = directory.appending(path: "video-check-legacy-small.mov")
        let result: [String: String]
        do {
            try await PhotoLibraryWriter.saveVideo(fixture, creationDate: .now)
            result = ["status": "saved",
                      "sourceStillExists": String(FileManager.default.fileExists(atPath: fixture.path))]
        } catch {
            result = ["status": "failed", "error": error.localizedDescription]
        }
        if let data = try? JSONEncoder().encode(result) { try? data.write(to: report, options: .atomic) }
    }
#endif

    /// Compare different selected stocks on the exact same saturated footage.
    @MainActor static func runLookRegression() async {
        let directory = URL.documentsDirectory
        let fixture = directory.appending(path: "video-check-legacy-small.mov")
        let checks = ["kodak_tri_x_400", "kodak_portra_400", "kodak_vision3_500t"]
        var result: [String: String] = [:]
        for film in checks {
            let destination = directory.appending(path: "video-look-\(film).mov")
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try await export(source: fixture, destination: destination, film: film, expected: nil) { _ in }
                result[film] = "rendered"
            } catch { result[film] = error.localizedDescription }
        }
        if let data = try? JSONEncoder().encode(result) {
            try? data.write(to: directory.appending(path: "video-look-report.json"), options: .atomic)
        }
    }

    static func runFormatRegression() {
        typealias Mode = MobileMovieProfile
        func spec(_ w: Int, _ h: Int, _ rate: Int32) -> Mode {
            Mode(raster: .init(w, h), duration: CMTime(value: 1, timescale: rate))
        }
        let uhd60 = spec(3840, 2160, 60)
        let uhd30 = spec(3840, 2160, 30)
        let large = spec(4096, 2160, 24)
        let hd120 = spec(1920, 1080, 120)
        let ntsc = Mode(raster: uhd60.raster, duration: CMTime(value: 1001, timescale: 60000))
        let tests = [
            "ranking": Mode.ranked([hd120, uhd30, large, uhd60, ntsc]) == [large, uhd60, ntsc, uhd30, hd120],
            "equivalentDuration": Mode.ranked([uhd60, Mode(raster: uhd60.raster, duration: CMTime(value: 2, timescale: 120))]) == [uhd60],
            "legacyTake": Mode.legacyUHD(60) == uhd60 && Mode.legacyUHD(24) == nil,
            "storedFormat": (try? JSONEncoder().encode(ntsc)).flatMap { try? JSONDecoder().decode(Mode.self, from: $0) } == ntsc,
            "orientation": Mode.Raster(2160, 3840) == uhd60.raster
        ]
        if let data = try? JSONEncoder().encode(tests) {
            try? data.write(to: URL.documentsDirectory.appending(path: "video-format-report.json"), options: .atomic)
        }
    }

    /// Explicit Debug-only launch check. Fixtures are injected into a test
    /// container by the developer; nothing is bundled or added to Photos.
    @MainActor static func runExportRegression() async {
        let directory = URL.documentsDirectory
        let report = directory.appending(path: "video-export-report.json")
        try? FileManager.default.removeItem(at: report)
        var results: [[String: String]] = []
        var cropMismatchRejected: Bool?
        for variant in ["uhd30-landscape", "uhd30-portrait", "uhd60-landscape", "uhd60-portrait", "legacy-small"] {
            let source = directory.appending(path: "video-check-\(variant).mov")
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let destination = directory.appending(path: "video-check-\(variant)-developed.mov")
            let rate: Int? = variant.hasPrefix("uhd30") ? 30 : (variant.hasPrefix("uhd60") ? 60 : nil)
            if variant == "uhd60-landscape" {
                let deliberatelyWrong = MobileMovieProfile(raster: .init(1920, 1080), duration: CMTime(value: 1, timescale: 60))
                do {
                    try await checkCapture(source: source, expected: deliberatelyWrong)
                    cropMismatchRejected = false
                } catch { cropMismatchRejected = true }
            }
            var passedCapture = false
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try await checkCapture(source: source, expected: rate.flatMap(MobileMovieProfile.legacyUHD))
                passedCapture = true
                try await export(source: source, destination: destination,
                                 film: MobileCameraRecipe.defaultFilmID, expected: rate.flatMap(MobileMovieProfile.legacyUHD)) { _ in }
                results.append(["fixture": variant, "status": "passed"])
            } catch {
                results.append(["fixture": variant, "status": "failed", "captureCheck": passedCapture ? "passed" : "failed", "error": error.localizedDescription])
            }
        }
        var data: [String: Any] = ["results": results, "freeMemoryBytes": Int(os_proc_available_memory())]
        if let cropMismatchRejected { data["cropMismatchRejected"] = cropMismatchRejected }
        if let encoded = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) {
            try? encoded.write(to: report, options: .atomic)
        }
    }
}
#endif

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
            guard !extent.isInfinite, !extent.isEmpty,
                  let width = Int(exactly: extent.width), let height = Int(exactly: extent.height),
                  UInt32(exactly: width) != nil, UInt32(exactly: height) != nil,
                  width > 0, height > 0, width <= device.maxBufferLength / max(height, 1) / 16 else {
                throw MobileFailure.message(TDetached("Unsupported video frame size.", "不支持的视频帧尺寸。", "不支援的影片畫面尺寸。"))
            }
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
