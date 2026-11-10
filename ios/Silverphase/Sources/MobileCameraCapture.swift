import AVFoundation
import AVKit
import CoreImage
import ImageIO
import OSLog
import SwiftUI

enum MobileCaptureFormat: String, Sendable {
    case proRAW = "ProRAW", bayer = "RAW", heic = "HEIC", jpeg = "JPEG"
    var fileExtension: String {
        switch self {
        case .proRAW, .bayer: "dng"
        case .heic: "heic"
        case .jpeg: "jpg"
        }
    }
}

enum MobileCameraLens: String, Identifiable, Sendable {
    case ultraWide, wide, wide35, wideCrop, wideCrop3, telephoto, telephotoCrop8, front

    var id: Self { self }
    /// `@MainActor` because two of the lens names are copy; the rest are
    /// magnifications, which do not translate.
    @MainActor var title: String {
        switch self {
        case .ultraWide: T("Ultra Wide", "超广角", "超廣角")
        case .wide: "1×"
        case .wide35: "35 mm"
        case .wideCrop: "2×"
        case .wideCrop3: "3×"
        case .telephoto: T("Telephoto", "长焦", "長焦")
        case .telephotoCrop8: "8×"
        case .front: T("Front", "前置", "前置")
        }
    }
    var transitionValue: Double? {
        switch self {
        case .wide: 1
        case .wide35: 35
        case .wideCrop: 2
        case .wideCrop3: 3
        case .telephoto: 4
        case .telephotoCrop8: 8
        default: nil
        }
    }

    var physicalLens: Self {
        switch self {
        case .wideCrop, .wideCrop3, .wide35: .wide
        case .telephotoCrop8: .telephoto
        default: self
        }
    }

    func findDevice() -> AVCaptureDevice? {
        switch self {
        case .ultraWide: AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
        case .wide, .wide35, .wideCrop, .wideCrop3: AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        case .telephoto, .telephotoCrop8: AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back)
        case .front: AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        }
    }
}

struct MobileCameraConfiguration: @unchecked Sendable {
    // The view uses device only to create the system rotation coordinator.
    let device: AVCaptureDevice
    let format: MobileCaptureFormat
    let aspect: CGFloat
    let rearLenses: [MobileCameraLens]
    let lensTitles: [MobileCameraLens: String]
    let alternateLenses: [MobileCameraLens: MobileCameraLens]
    let hasFrontCamera: Bool
    let hasPortraitCamera: Bool
    let flashModes: [AVCaptureDevice.FlashMode]
    let exposureRange: ClosedRange<Float>?
    let exposure: Float
}

// Session and output operations are serialized on queue. The main actor uses
// the session only to connect its preview layer and observe notifications.
final class MobileStillCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
#if SILVERPHASE_APP
    let lookFrames = MobileCameraLookFrames()

    @MainActor func lookGeometry() -> (angle: CGFloat, mirrored: Bool) {
        (previewLayer?.connection?.videoRotationAngle ?? 0, previewLayer?.connection?.isVideoMirrored == true)
    }
#endif
    @MainActor private var rotation: AVCaptureDevice.RotationCoordinator?
    @MainActor private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private let queue = DispatchQueue(label: "silverphase.camera")
    private var output = AVCapturePhotoOutput()
    private var previewOutput: AVCaptureVideoDataOutput?
    private var previewBuffer: CVPixelBuffer?
    private var previewBufferRotation: CGFloat = 0
    private var previewFrameCount = 0
    private lazy var previewContext = CIContext(options: [.cacheIntermediates: false])
    private var captureDelegate: StillCaptureDelegate?
    private var input: AVCaptureDeviceInput?
    private var activeLens: MobileCameraLens?
    private var focusRequest = 0
    private var portraitCapture = false
    private var supportsWideCrop = false
    private lazy var devices: [MobileCameraLens: AVCaptureDevice] = Dictionary(uniqueKeysWithValues:
        [MobileCameraLens.ultraWide, .wide, .telephoto, .front].compactMap { lens in
            lens.findDevice().map { (lens, $0) }
        }
    )

    override init() { super.init() }

    @MainActor func attachPreview(_ layer: AVCaptureVideoPreviewLayer, device: AVCaptureDevice) -> AVCaptureDevice.RotationCoordinator {
        detachPreview()
        layer.session = session
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: layer)
        previewLayer = layer
        rotation = coordinator
        return coordinator
    }

    @MainActor func detachPreview() {
        previewLayer?.session = nil
        previewLayer = nil
        rotation = nil
    }

    // Retain the frame and the viewfinder geometry together. Render it off
    // the capture queue so the first use of Core Image cannot delay the shutter.
    @MainActor func snapshotPreview() async -> CIImage? {
        let angle = previewLayer?.connection?.videoRotationAngle ?? 0
        let mirrored = previewLayer?.connection?.isVideoMirrored == true
        return await withCheckedContinuation { continuation in
            queue.async {
                guard let buffer = self.previewBuffer else {
                    continuation.resume(returning: nil)
                    return
                }
                let radians = -(angle - self.previewBufferRotation) * .pi / 180
                var image = CIImage(cvPixelBuffer: buffer).transformed(by: CGAffineTransform(rotationAngle: radians))
                image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
                if mirrored { image = image.oriented(.upMirrored) }
                continuation.resume(returning: image)
            }
        }
    }

    @MainActor func freezePreview() async -> CGImage? {
        guard let image = await snapshotPreview() else { return nil }
        return await withCheckedContinuation { continuation in
            queue.async {
                let scale = min(1, 1280 / max(image.extent.width, image.extent.height))
                let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                continuation.resume(returning: self.previewContext.createCGImage(scaled, from: scaled.extent))
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard output === previewOutput, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        previewBuffer = buffer
        previewBufferRotation = connection.videoRotationAngle
        previewFrameCount = min(previewFrameCount + 1, 3)
#if SILVERPHASE_APP
        lookFrames.store(buffer, rotation: connection.videoRotationAngle,
                         sensorISO: input.map { Double($0.device.iso) },
                         sensorDuration: input.map { CMTimeGetSeconds($0.device.exposureDuration) })
#endif
    }

    func hasSettledPreview() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.previewOutput == nil || self.previewFrameCount >= 3)
            }
        }
    }

    func start(lens: MobileCameraLens, exposure: Float, portrait: Bool) async throws -> MobileCameraConfiguration {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let rampsZoom = self.session.isRunning && !portrait && !self.portraitCapture &&
                        self.activeLens?.physicalLens == lens.physicalLens && self.activeLens != lens
                    let device = try self.configure(lens: lens, portrait: portrait)
#if SILVERPHASE_APP
                    // Same queue as the video delegate. Old physical-output
                    // callbacks are rejected by output identity; zoom frames
                    // from this configuration remain live throughout the ramp.
                    self.lookFrames.beginConfiguration()
#endif
                    if portrait && !self.output.isDepthDataDeliveryEnabled {
                        throw MobileFailure.message(TDetached("The current lens or capture configuration does not support portrait depth.", "当前镜头或拍摄配置不支持人像深度。", "目前鏡頭或拍攝設定檔不支援人像深度。"))
                    }
                    if !self.session.isRunning {
#if !SILVERPHASE_APP
                        let log = Logger(subsystem: "com.silverphase.editor", category: "LockedCamera")
                        log.notice("Capture graph configured, starting session")
#endif
                        self.session.startRunning()
#if !SILVERPHASE_APP
                        log.notice("Session start returned, running: \(self.session.isRunning)")
#endif
                    }
                    guard self.session.isRunning else { throw MobileFailure.message(TDetached("The camera could not be started", "无法启动相机", "無法啟動相機")) }
                    try self.applyControls(lens: lens, exposure: exposure, device: device, rampsZoom: rampsZoom)
                    if rampsZoom {
                        self.finishZoom(lens: lens, exposure: exposure, request: self.focusRequest,
                                        attempts: 20, continuation: continuation)
                    } else {
                        continuation.resume(returning: self.currentConfiguration(device: device, exposure: exposure))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func finishZoom(lens: MobileCameraLens, exposure: Float, request: Int, attempts: Int,
                            continuation: CheckedContinuation<MobileCameraConfiguration, any Error>) {
        queue.asyncAfter(deadline: .now() + .milliseconds(30)) {
            guard self.focusRequest == request, self.session.isRunning, let device = self.input?.device else {
                continuation.resume(throwing: CancellationError())
                return
            }
            if device.isRampingVideoZoom, attempts > 0 {
                self.finishZoom(lens: lens, exposure: exposure, request: request, attempts: attempts - 1, continuation: continuation)
                return
            }
            do {
                // Set the exact final factor before deriving the available RAW format.
                try self.applyControls(lens: lens, exposure: exposure, device: device)
                continuation.resume(returning: self.currentConfiguration(device: device, exposure: exposure))
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func stop() {
        queue.async {
            self.focusRequest += 1
            if self.session.isRunning { self.session.stopRunning() }
            self.previewBuffer = nil
#if SILVERPHASE_APP
            self.lookFrames.clear()
#endif
            self.previewFrameCount = 0
        }
    }

    private func portraitDevice(for lens: MobileCameraLens) -> AVCaptureDevice? {
        if lens == .front {
            return AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front)
        }
        for type in [AVCaptureDevice.DeviceType.builtInDualCamera, .builtInTripleCamera, .builtInDualWideCamera] {
            if let device = AVCaptureDevice.default(type, for: .video, position: .back) { return device }
        }
        return nil
    }

    private func configure(lens: MobileCameraLens, portrait: Bool) throws -> AVCaptureDevice {
        guard let device = portrait ? portraitDevice(for: lens) : lens.physicalLens.findDevice() else {
            throw MobileFailure.message(TDetached("This device has no lens of that kind", "此设备没有所选镜头", "此設備沒有所選鏡頭"))
        }
        if input?.device.uniqueID != device.uniqueID || portraitCapture != portrait {
            let next = try AVCaptureDeviceInput(device: device)
            // Rebuild the still-photo graph while stopped. RAW and flash
            // capabilities belong to the new input and its photo output.
            if session.isRunning { session.stopRunning() }
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            if session.outputs.contains(output) { session.removeOutput(output) }
            if let previewOutput { session.removeOutput(previewOutput) }
            previewOutput = nil
#if SILVERPHASE_APP
            lookFrames.clear()
#endif
            previewBuffer = nil
            previewFrameCount = 0
            if let input { session.removeInput(input) }
            input = nil
            activeLens = nil
            guard session.canAddInput(next) else {
                throw MobileFailure.message(TDetached("The lens could not be switched", "无法切换镜头", "無法切換鏡頭"))
            }
            session.addInput(next)
            if session.canSetSessionPreset(.photo) { session.sessionPreset = .photo }
            let nextOutput = AVCapturePhotoOutput()
            guard session.canAddOutput(nextOutput) else {
                session.removeInput(next)
                throw MobileFailure.message(TDetached("The photo output could not be configured", "无法配置照片输出", "無法設定檔照片輸出"))
            }
            session.addOutput(nextOutput)
            let frames = AVCaptureVideoDataOutput()
            frames.alwaysDiscardsLateVideoFrames = true
#if SILVERPHASE_APP
            frames.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            frames.automaticallyConfiguresOutputBufferDimensions = false
            frames.deliversPreviewSizedOutputBuffers = true
#endif
            if session.canAddOutput(frames) {
                session.addOutput(frames)
#if !SILVERPHASE_APP
                // The preview layer presents the first frame. This output only supplies
                // transition snapshots and can come up after the viewfinder is live.
                if #available(iOS 26, *), frames.isDeferredStartSupported {
                    frames.isDeferredStartEnabled = true
                }
#endif
                if let connection = frames.connection(with: .video), connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = false
                }
                frames.setSampleBufferDelegate(self, queue: queue)
                previewOutput = frames
            }
            if portrait {
                nextOutput.isDepthDataDeliveryEnabled = nextOutput.isDepthDataDeliverySupported
                if nextOutput.isDepthDataDeliveryEnabled && nextOutput.isPortraitEffectsMatteDeliverySupported {
                    nextOutput.isPortraitEffectsMatteDeliveryEnabled = true
                }
            } else if nextOutput.isAppleProRAWSupported {
                nextOutput.isAppleProRAWEnabled = true
            }
            output = nextOutput
            input = next
            portraitCapture = portrait
        }
        return device
    }

    private func applyControls(lens: MobileCameraLens, exposure: Float, device: AVCaptureDevice, rampsZoom: Bool = false) throws {
        focusRequest += 1
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        if !portraitCapture {
            if lens.physicalLens == .wide { supportsWideCrop = device.maxAvailableVideoZoomFactor >= 2 }
            let zoom: CGFloat?
            switch lens {
            case .wide35: zoom = zoomFor35mm(on: device)
            case .wideCrop, .telephotoCrop8: zoom = 2
            case .wideCrop3: zoom = 3
            default: zoom = 1
            }
            guard let zoom, (device.minAvailableVideoZoomFactor...device.maxAvailableVideoZoomFactor).contains(zoom) else {
                throw MobileFailure.message(TDetached("The current lens does not support that focal length", "当前镜头不支持该焦段", "目前鏡頭不支援該焦段"))
            }
            if device.isRampingVideoZoom { device.cancelVideoZoomRamp() }
            if device.videoZoomFactor != zoom {
                if rampsZoom { device.ramp(toVideoZoomFactor: zoom, withRate: 5) }
                else { device.videoZoomFactor = zoom }
            }
        }
        setExposure(exposure, on: device)
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        activeLens = lens
    }

    private func zoomFor35mm(on device: AVCaptureDevice) -> CGFloat? {
        guard #available(iOS 26, *) else { return nil }
        let focalLength = device.nominalFocalLengthIn35mmFilm
        guard focalLength > 0, focalLength < 35 else { return nil }
        let zoom = 35 / CGFloat(focalLength)
        return (device.minAvailableVideoZoomFactor...device.maxAvailableVideoZoomFactor).contains(zoom) ? zoom : nil
    }

    private func lensTitles() -> [MobileCameraLens: String] {
        guard let wide = devices[.wide] else { return [:] }
        var titles: [MobileCameraLens: String] = [:]
        for lens in [MobileCameraLens.ultraWide, .telephoto] {
            guard let device = devices[lens] else { continue }
            let ratio: Double
            if #available(iOS 26, *), wide.nominalFocalLengthIn35mmFilm > 0, device.nominalFocalLengthIn35mmFilm > 0 {
                ratio = Double(device.nominalFocalLengthIn35mmFilm) / Double(wide.nominalFocalLengthIn35mmFilm)
            } else {
                let wideAngle = Double(wide.activeFormat.videoFieldOfView)
                let angle = Double(device.activeFormat.videoFieldOfView)
                guard wideAngle > 0, angle > 0 else { continue }
                ratio = tan(wideAngle * .pi / 360) / tan(angle * .pi / 360)
            }
            titles[lens] = lens == .telephoto && abs(ratio - 4) < 0.35
                ? "4×" : ratio.formatted(.number.precision(.fractionLength(0...1))) + "×"
        }
        return titles
    }

    private func supportsSensorCrop(_ device: AVCaptureDevice?, factor: CGFloat) -> Bool {
        guard let device, device.maxAvailableVideoZoomFactor >= factor else { return false }
        return device.formats.contains { format in
            format.videoMaxZoomFactor >= factor && (
                format.secondaryNativeResolutionZoomFactors.contains { abs($0 - factor) < 0.05 } ||
                format.supportedMaxPhotoDimensions.contains { Int64($0.width) * Int64($0.height) >= 40_000_000 }
            )
        }
    }

    private func currentConfiguration(device: AVCaptureDevice, exposure: Float) -> MobileCameraConfiguration {
        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let aspect = CGFloat(max(dimensions.width, dimensions.height)) / CGFloat(min(dimensions.width, dimensions.height))
        let lenses: [MobileCameraLens] = [.ultraWide, .wide, .wideCrop, .telephoto]
        let minimum = device.minExposureTargetBias
        let maximum = device.maxExposureTargetBias
        let titles = lensTitles()
        var alternates: [MobileCameraLens: MobileCameraLens] = [:]
        if devices[.wide].flatMap(zoomFor35mm(on:)) != nil { alternates[.wide] = .wide35 }
        if supportsSensorCrop(devices[.wide], factor: 3) { alternates[.wideCrop] = .wideCrop3 }
        if titles[.telephoto] == "4×", supportsSensorCrop(devices[.telephoto], factor: 2) {
            alternates[.telephoto] = .telephotoCrop8
        }
        return MobileCameraConfiguration(device: device, format: captureFormat(), aspect: aspect,
            rearLenses: lenses.filter { $0 == .wideCrop ? supportsWideCrop : devices[$0] != nil },
            lensTitles: titles,
            alternateLenses: alternates,
            hasFrontCamera: devices[.front] != nil,
            hasPortraitCamera: activeLens.flatMap(portraitDevice(for:)) != nil,
            flashModes: device.hasFlash ? [.off, .auto, .on].filter(output.supportedFlashModes.contains) : [.off],
            exposureRange: minimum < maximum ? minimum...maximum : nil,
            exposure: min(max(exposure, minimum), maximum))
    }

    func focus(at point: CGPoint, lens: MobileCameraLens, lock: Bool) {
        queue.async {
            guard self.activeLens == lens, let device = self.input?.device else { return }
            self.focusRequest += 1
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = point
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposurePointOfInterest = point
                    device.exposureMode = .continuousAutoExposure
                }
                if lock { self.finishFocusLock(request: self.focusRequest, attempts: 10) }
            } catch {
                // The capture device can become unavailable during an interruption.
            }
        }
    }

    private func finishFocusLock(request: Int, attempts: Int) {
        queue.asyncAfter(deadline: .now() + .milliseconds(100)) {
            guard self.focusRequest == request, self.session.isRunning, let device = self.input?.device else { return }
            if attempts > 0, device.isAdjustingFocus || device.isAdjustingExposure {
                self.finishFocusLock(request: request, attempts: attempts - 1)
                return
            }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
                if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
            } catch {
                // The capture device can become unavailable during an interruption.
            }
        }
    }

    func updateExposure(_ value: Float, lens: MobileCameraLens) {
        queue.async {
            guard self.activeLens == lens, let device = self.input?.device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                self.setExposure(value, on: device)
            } catch {
                // Configuration may be unavailable during a system interruption.
            }
        }
    }

    private func setExposure(_ value: Float, on device: AVCaptureDevice) {
        let bias = min(max(value, device.minExposureTargetBias), device.maxExposureTargetBias)
        if device.exposureTargetBias != bias { device.setExposureTargetBias(bias, completionHandler: nil) }
    }

    private func captureFormat() -> MobileCaptureFormat {
        if !portraitCapture {
            let formats = output.availableRawPhotoPixelFormatTypes
            if formats.contains(where: AVCapturePhotoOutput.isAppleProRAWPixelFormat) { return .proRAW }
            if input?.device.videoZoomFactor == 1, formats.contains(where: AVCapturePhotoOutput.isBayerRAWPixelFormat) { return .bayer }
        }
        return output.availablePhotoCodecTypes.contains(.hevc) ? .heic : .jpeg
    }

    @MainActor func capture(flash: AVCaptureDevice.FlashMode, portrait: Bool,
                            mirrored: Bool, pose: MobileCameraCapturePose? = nil,
                            location: MobileCaptureLocation? = nil) async throws -> (data: Data, format: MobileCaptureFormat) {
        let angle: CGFloat?
        if #available(iOS 27, *), let pose {
            guard let rotation else { throw MobileFailure.message(TDetached("The capture orientation is not ready yet. Try again.", "相机拍摄方向尚未准备好，请重试。", "相機拍攝方向尚未準備好，請重試。")) }
            // Capture uses the physical pose latched at shutter press.
            // AVFoundation resolves the sensor's mounting; never infer capture
            // orientation from the rotating extension host or the preview layer.
            angle = rotation.videoRotationAngleRelative(toDeviceOrientation: pose.videoOrientation)
        } else {
            angle = rotation?.videoRotationAngleForHorizonLevelCapture
        }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.session.isRunning, let connection = self.output.connection(with: .video),
                      connection.isActive, self.captureDelegate == nil,
                      self.portraitCapture == portrait, !portrait || self.output.isDepthDataDeliveryEnabled else {
                    continuation.resume(throwing: MobileFailure.message(TDetached("The camera is not ready", "相机尚未准备好", "相機尚未準備好")))
                    return
                }
                // RAW availability can change after the startup or lens configuration snapshot.
                let format = self.captureFormat()
                if let angle {
                    if connection.isVideoRotationAngleSupported(angle) {
                        connection.videoRotationAngle = angle
                    } else if pose != nil {
                        continuation.resume(throwing: MobileFailure.message(TDetached("The camera does not support this capture orientation.", "当前相机不支持本次拍摄方向。", "目前相機不支援本次拍攝方向。")))
                        return
                    }
                }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = mirrored
                }
                let settings: AVCapturePhotoSettings
                switch format {
                case .proRAW, .bayer:
                    let formats = self.output.availableRawPhotoPixelFormatTypes
                    let raw = formats.first { format == .proRAW
                        ? AVCapturePhotoOutput.isAppleProRAWPixelFormat($0)
                        : AVCapturePhotoOutput.isBayerRAWPixelFormat($0)
                    }
                    guard let raw else {
                        continuation.resume(throwing: MobileFailure.message(TDetached("The camera does not support the selected RAW format", "当前相机不支持所选 RAW 格式", "目前相機不支援所選 RAW 格式")))
                        return
                    }
                    settings = AVCapturePhotoSettings(rawPixelFormatType: raw)
                case .heic, .jpeg:
                    settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: format == .heic ? AVVideoCodecType.hevc : .jpeg])
                }
                if let location {
                    settings.metadata = [kCGImagePropertyGPSDictionary as String: location.gps]
                }
                if format == .bayer { settings.photoQualityPrioritization = .speed }
                if portrait {
                    settings.isDepthDataDeliveryEnabled = true
                    settings.isPortraitEffectsMatteDeliveryEnabled = self.output.isPortraitEffectsMatteDeliveryEnabled
                }
                if flash == .on, self.input?.device.isFlashAvailable != true {
                    continuation.resume(throwing: MobileFailure.message(TDetached("The flash is unavailable. Turn it off and try again.", "闪光灯暂时不可用，请关闭闪光灯后重试", "閃光燈暫時不可用，請關閉閃光燈後重試")))
                    return
                }
                if self.output.supportedFlashModes.contains(flash) { settings.flashMode = flash }
                let delegate = StillCaptureDelegate(expectsRAW: format == .proRAW || format == .bayer) { result in
                    self.queue.async {
                        self.captureDelegate = nil
                        continuation.resume(with: result.map { (data: $0, format: format) })
                    }
                }
                self.captureDelegate = delegate
                self.output.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }
}

private extension MobileCameraCapturePose {
    var videoOrientation: AVCaptureVideoOrientation {
        switch self {
        case .portrait: .portrait
        case .landscapeLeft: .landscapeLeft
        case .portraitUpsideDown: .portraitUpsideDown
        case .landscapeRight: .landscapeRight
        }
    }
}

private final class StillCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    let expectsRAW: Bool
    let finish: @Sendable (Result<Data, Error>) -> Void
    private var data: Data?
    private var processingError: Error?

    init(expectsRAW: Bool, finish: @escaping @Sendable (Result<Data, Error>) -> Void) {
        self.expectsRAW = expectsRAW
        self.finish = finish
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard photo.isRawPhoto == expectsRAW else { return }
        processingError = error
        if error == nil { data = photo.fileDataRepresentation() }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error ?? processingError { finish(.failure(error)) }
        else if let data { finish(.success(data)) }
        else { finish(.failure(MobileFailure.message(TDetached("The camera did not return an original", "相机未返回原片", "相機未返回原片")))) }
    }
}

struct MobileCameraPreview: UIViewRepresentable {
    let camera: MobileStillCamera
    let device: AVCaptureDevice
    @Binding var portrait: Bool
    @Binding var previewing: Bool
    let mirrored: Bool
    let hardwareShutterEnabled: Bool
    let shutter: () -> Void
    let canAdjustExposure: Bool
    let exposureRotation: Double
    let focus: (CGPoint, CGPoint, Bool) -> Void
    let adjustExposure: (CGFloat?) -> Void

    func makeUIView(context: Context) -> Preview {
        let view = Preview()
        view.installGestures()
        view.shutter = shutter
        let captureInteraction = AVCaptureEventInteraction { [weak view] event in
            if event.phase == .ended { view?.shutter?() }
        }
        captureInteraction.isEnabled = hardwareShutterEnabled
        view.addInteraction(captureInteraction)
        view.captureInteraction = captureInteraction
        view.previewLayer.videoGravity = .resizeAspectFill
        let rotation = camera.attachPreview(view.previewLayer, device: device)
        view.rotation = rotation
        view.mirrored = mirrored
        view.updateConnectionOrientation()
        view.orientationChanged = { isPortrait in
            if portrait != isPortrait { portrait = isPortrait }
        }
        view.previewObservation = view.previewLayer.observe(\.isPreviewing, options: [.initial, .new]) { [weak view] _, change in
            guard let value = change.newValue else { return }
            Task { @MainActor in
                guard view?.previewLayer.session != nil else { return }
                if previewing != value { previewing = value }
            }
        }
        view.rotationObservation = rotation.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak view] _, _ in
            Task { @MainActor in view?.setNeedsLayout() }
        }
        return view
    }

    func updateUIView(_ view: Preview, context: Context) {
        view.shutter = shutter
        view.captureInteraction?.isEnabled = hardwareShutterEnabled
        view.mirrored = mirrored
        view.updateConnectionOrientation()
        view.canAdjustExposure = canAdjustExposure
        view.exposureRotation = exposureRotation
        view.focus = focus
        view.adjustExposure = adjustExposure
    }

    static func dismantleUIView(_ view: Preview, coordinator: ()) {
        view.rotationObservation?.invalidate()
        view.previewObservation?.invalidate()
        view.captureInteraction?.isEnabled = false
        view.rotation = nil
        view.previewLayer.session = nil
    }

    final class Preview: UIView, UIGestureRecognizerDelegate {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var rotationObservation: NSKeyValueObservation?
        var previewObservation: NSKeyValueObservation?
        var rotation: AVCaptureDevice.RotationCoordinator?
        var orientationChanged: ((Bool) -> Void)?
        var mirrored = false
        var captureInteraction: AVCaptureEventInteraction?
        var shutter: (() -> Void)?
        var canAdjustExposure = false
        var exposureRotation = 0.0
        private var dragRotation: Double?
        var focus: ((CGPoint, CGPoint, Bool) -> Void)?
        var adjustExposure: ((CGFloat?) -> Void)?

        func installGestures() {
            let tap = UITapGestureRecognizer(target: self, action: #selector(focusGesture(_:)))
            let press = UILongPressGestureRecognizer(target: self, action: #selector(focusGesture(_:)))
            let pan = UIPanGestureRecognizer(target: self, action: #selector(exposureGesture(_:)))
            tap.require(toFail: press)
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            addGestureRecognizer(tap)
            addGestureRecognizer(press)
            addGestureRecognizer(pan)
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: self)
            let swapsAxes = abs(exposureRotation.remainder(dividingBy: 180)) == 90
            return canAdjustExposure && (swapsAxes ? abs(velocity.x) > abs(velocity.y) : abs(velocity.y) > abs(velocity.x))
        }

        @objc private func focusGesture(_ gesture: UIGestureRecognizer) {
            let locks = gesture is UILongPressGestureRecognizer
            guard gesture.state == (locks ? .began : .ended), bounds.width > 0, bounds.height > 0 else { return }
            let point = gesture.location(in: self)
            focus?(CGPoint(x: point.x / bounds.width, y: point.y / bounds.height),
                   previewLayer.captureDevicePointConverted(fromLayerPoint: point), locks)
        }

        @objc private func exposureGesture(_ pan: UIPanGestureRecognizer) {
            if pan.state == .began { dragRotation = exposureRotation }
            switch pan.state {
            case .began, .changed:
                guard canAdjustExposure, dragRotation == exposureRotation else {
                    dragRotation = nil
                    adjustExposure?(nil)
                    return
                }
                // Project the movement onto the same down axis as the rotated EV indicator.
                let radians = exposureRotation * .pi / 180
                let translation = pan.translation(in: self)
                adjustExposure?(-sin(radians) * translation.x + cos(radians) * translation.y)
                pan.setTranslation(.zero, in: self)
            case .ended, .cancelled, .failed:
                dragRotation = nil
                adjustExposure?(nil)
            default:
                break
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            updateConnectionOrientation()
        }

        func updateConnectionOrientation() {
            guard let rotation, let connection = previewLayer.connection else { return }
            let angle = rotation.videoRotationAngleForHorizonLevelPreview
            if connection.isVideoRotationAngleSupported(angle), connection.videoRotationAngle != angle {
                connection.videoRotationAngle = angle
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                if connection.isVideoMirrored != mirrored { connection.isVideoMirrored = mirrored }
            }
            let radians = angle * .pi / 180
            let portrait = abs(sin(radians)) > abs(cos(radians))
            Task { @MainActor [weak self] in self?.orientationChanged?(portrait) }
        }
    }
}
