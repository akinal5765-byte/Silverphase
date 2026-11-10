#if DEBUG && SILVERPHASE_APP
import Foundation
import CoreImage
import ImageIO
import Metal

/// Development diagnostic only. Retains numerical input summaries, never an
/// extra image, location, or a guessed exposure correction. One latest report.
struct MobileCameraExposureSummary: Codable, Sendable {
    let aspect: Double
    let percentiles: [Double] // 1, 10, 25, 50, 75, 90, 99 percent
    static func make(_ values: [Double], aspect: Double) throws -> Self {
        guard !values.isEmpty, aspect.isFinite, aspect > 0,
              values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw MobileFailure.message(TDetached("The exposure diagnostic input is invalid", "曝光诊断输入无效", "曝光診斷輸入無效"))
        }
        let sorted = values.sorted()
        return Self(aspect: max(aspect, 1 / aspect), percentiles: [1, 10, 25, 50, 75, 90, 99].map { sorted[$0 * (sorted.count - 1) / 100] })
    }
    static func compare(raw: Self, video: Self) -> [String: Any] {
        guard abs(log(raw.aspect / video.aspect)) < 0.03 else { return ["status": "different_field_of_view"] }
        var ratios: [Double] = []
        for index in [2, 3, 4] {
            let a = raw.percentiles[index], b = video.percentiles[index]
            guard a > 0.0001, b > 0.0001 else { return ["status": "insufficient_midtones"] }
            ratios.append(log2(a / b))
        }
        let sorted = ratios.sorted(), spread = sorted.last! - sorted.first!
        return ["status": "statistics_only_no_correction", "rawRelativeToVideoEVAt25_50_75": ratios,
                "medianEV": sorted[1], "spreadEV": spread,
                "consistentWithUniformGain": spread <= 0.25]
    }
}

enum MobileCameraExposureProbe {
    static func summarize(_ image: CIImage, context: CIContext) throws -> MobileCameraExposureSummary {
        let extent = image.extent
        guard !extent.isEmpty, !extent.isInfinite, let linear = MobileInputColor.linearProPhoto() else {
            throw MobileFailure.message(TDetached("The exposure diagnostic frame is invalid", "曝光诊断画面无效", "曝光診斷畫面無效"))
        }
        let placed = image.transformed(by: .init(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: .init(scaleX: 64 / extent.width, y: 64 / extent.height))
        var pixels = [Float](repeating: 0, count: 64 * 64 * 4)
        pixels.withUnsafeMutableBytes { context.render(placed, toBitmap: $0.baseAddress!, rowBytes: 64 * 16,
            bounds: CGRect(x: 0, y: 0, width: 64, height: 64), format: .RGBAf, colorSpace: linear) }
        let luma = (0..<(64 * 64)).map { i in
            max(0, Double(pixels[i * 4]) * 0.2880402 + Double(pixels[i * 4 + 1]) * 0.7118741 + Double(pixels[i * 4 + 2]) * 0.0000857)
        }
        return try .make(luma, aspect: Double(extent.width / extent.height))
    }

    static func runChecks() {
        let report = URL.documentsDirectory.appendingPathComponent("camera-exposure-checks.json")
        var checks: [String] = []
        do {
            guard let device = MTLCreateSystemDefaultDevice() else { throw MobileFailure.message(TDetached("No Metal device", "没有 Metal 设备", "沒有 Metal 設備")) }
            let context = MobileInputColor.context(device: device)
            defer { context.clearCaches() }
            func image(_ value: Float, space: CGColorSpace) -> CIImage {
                let pixels = (0..<16).flatMap { _ in [value, value, value, Float(1)] }
                let data = pixels.withUnsafeBytes { Data($0) }
                return CIImage(bitmapData: data, bytesPerRow: 4 * 16, size: CGSize(width: 4, height: 4), format: .RGBAf, colorSpace: space)
            }
            let encoded = try summarize(image(0.5, space: CGColorSpace(name: CGColorSpace.sRGB)!), context: context)
            let linear = try summarize(image(0.21404114, space: CGColorSpace(name: CGColorSpace.linearSRGB)!), context: context)
            guard abs(encoded.percentiles[3] - 0.21404114) < 0.001,
                  abs((MobileCameraExposureSummary.compare(raw: linear, video: encoded)["medianEV"] as? Double) ?? 10) < 0.01 else {
                throw MobileFailure.message(TDetached("The exposure statistics disagree between the encoded and linear inputs", "编码／线性输入的曝光统计不一致", "編碼／線性輸入的曝光統計不一致"))
            }
            checks.append("sRGB encoded 0.5 and linear 0.21404114 produce the same measured scene luminance; no double gamma")
            let half = try summarize(image(0.10702057, space: CGColorSpace(name: CGColorSpace.linearSRGB)!), context: context)
            guard abs(((MobileCameraExposureSummary.compare(raw: half, video: encoded)["medianEV"] as? Double) ?? 10) + 1) < 0.01 else {
                throw MobileFailure.message(TDetached("A one-stop brightness difference reads in the wrong direction on the actual Core Image input", "实际 CI 输入的一档亮度差方向错误", "實際 CI 輸入的一檔亮度差方向錯誤"))
            }
            checks.append("actual ColorSync/CI measurement reports raw input one stop darker with the correct sign")
            try JSONSerialization.data(withJSONObject: ["passed": true, "checks": checks,
                "scope": "synthetic input representation invariance; no actual paired sensor/RAW validation"], options: [.prettyPrinted, .sortedKeys])
                .write(to: report, options: .atomic)
        } catch {
            try? JSONSerialization.data(withJSONObject: ["passed": false, "checks": checks, "error": error.localizedDescription], options: [.prettyPrinted, .sortedKeys])
                .write(to: report, options: .atomic)
        }
    }

    static func record(rawData: Data, frame: MobileCameraLookFrame, angle: CGFloat, mirrored: Bool,
                       shutterUptime: Double, recipe: MobileCameraRecipe) {
        autoreleasepool {
            let report = URL.documentsDirectory.appendingPathComponent("camera-exposure-report.json")
            var object: [String: Any] = ["version": 1, "film": recipe.filmID ?? "", "metering": recipe.metering.rawValue,
                "videoFrameAgeAtShutter": shutterUptime - frame.receivedUptime,
                "scope": "near-shutter video vs original RAW input statistics; no images/GPS, no automatic correction"]
            do {
                guard shutterUptime - frame.receivedUptime >= 0, shutterUptime - frame.receivedUptime < 0.25 else {
                    throw MobileFailure.message(TDetached("The video frame before the shutter is stale", "快门前的视频帧已过期", "快門前的影片幀已過期"))
                }
                guard let source = CGImageSourceCreateWithData(rawData as CFData, nil),
                      let raw = CIRAWFilter(imageData: rawData, identifierHint: CGImageSourceGetType(source) as String?),
                      let device = MTLCreateSystemDefaultDevice() else { throw MobileFailure.message(TDetached("The RAW input reference could not be prepared", "无法准备 RAW 输入对照", "無法準備 RAW 輸入對照")) }
                raw.scaleFactor = Float(min(1, 256 / max(raw.nativeSize.width, raw.nativeSize.height)))
                raw.isDraftModeEnabled = false; raw.isLensCorrectionEnabled = false
                MobileInputColor.prepareSceneLinearRAW(raw)
                guard let image = raw.outputImage else { throw MobileFailure.message(TDetached("The RAW input reference failed to decode", "RAW 输入对照解码失败", "RAW 輸入對照解碼失敗")) }
                let context = MobileInputColor.context(device: device)
                defer { context.clearCaches() }
                let video = try summarize(MobileCameraLookGeometry.orientedImage(frame, angle: angle, mirrored: mirrored), context: context)
                let decoded = try summarize(image, context: context)
                object["videoLinearProPhoto"] = ["aspect": video.aspect, "percentiles": video.percentiles]
                object["rawLinearProPhoto"] = ["aspect": decoded.aspect, "percentiles": decoded.percentiles]
                object["comparison"] = MobileCameraExposureSummary.compare(raw: decoded, video: video)
                object["rawBaselineExposureEV"] = raw.baselineExposure
                object["rawExposureEV"] = raw.exposure
                if let iso = frame.sensorISO { object["videoISO"] = iso }
                if let duration = frame.sensorDuration { object["videoExposureTime"] = duration }
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
                let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
                if let value = exif[kCGImagePropertyExifISOSpeedRatings as String] { object["rawISO"] = value }
                if let value = exif[kCGImagePropertyExifExposureTime as String] { object["rawExposureTime"] = value }
                object["passed"] = true
            } catch {
                object["passed"] = false; object["error"] = error.localizedDescription
            }
            if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: report, options: .atomic)
            }
        }
    }
}
#endif
