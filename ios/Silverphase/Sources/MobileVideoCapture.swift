#if SILVERPHASE_APP
@preconcurrency import AVFoundation
import AVKit
import Foundation
import Photos
import SwiftUI

enum MobileMovieProfile: Int, CaseIterable, Identifiable, Sendable {
    case uhd30 = 30
    case uhd60 = 60

    static let width = 3840
    static let height = 2160
    var id: Int { rawValue }
    var title: String { "4K \(rawValue) fps" }

    static func rearCamera() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    func format(on device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let rate = Double(rawValue)
        func matches(_ format: AVCaptureDevice.Format) -> Bool {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return Int(dimensions.width) == Self.width && Int(dimensions.height) == Self.height
                && format.supportedColorSpaces.contains(.sRGB)
                && !format.unsupportedCaptureOutputClasses.contains { $0 == AVCaptureMovieFileOutput.self }
                && format.videoSupportedFrameRateRanges.contains {
                    $0.minFrameRate <= rate && $0.maxFrameRate >= rate
                }
        }
        if matches(device.activeFormat) { return device.activeFormat }
        return device.formats.first(where: matches)
    }

    static func supports(_ profile: Self) -> Bool {
        guard let camera = rearCamera() else { return false }
        return profile.format(on: camera) != nil
    }
}

// Photo/portrait and the locked camera keep their existing session. All
// mutations of this separate session and movie output run on one serial queue.
private final class MobileMovieCapture: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.silverphase.video.capture")
    private let movie = AVCaptureMovieFileOutput()
    private var configuredProfile: MobileMovieProfile?
    private var finishing: (@Sendable (Result<URL, Error>) -> Void)?
    private var pendingStop = false

    struct Configuration: @unchecked Sendable {
        let device: AVCaptureDevice
    }

    func start(profile: MobileMovieProfile) async throws -> Configuration {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    if self.session.isRunning { self.session.stopRunning() }
                    if self.configuredProfile != profile { try self.configure(profile: profile) }
                    self.session.startRunning()
                    guard self.session.isRunning, let input = self.session.inputs.first as? AVCaptureDeviceInput,
                          let connection = self.movie.connection(with: .video),
                          self.movie.availableVideoCodecTypes.contains(.hevc),
                          self.movie.supportedOutputSettingsKeys(for: connection).contains(AVVideoCodecKey) else {
                        throw self.setupError(profile)
                    }
                    self.movie.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: connection)
                    continuation.resume(returning: Configuration(device: input.device))
                } catch {
                    if self.session.isRunning { self.session.stopRunning() }
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func configure(profile: MobileMovieProfile) throws {
        guard let camera = MobileMovieProfile.rearCamera(),
              let microphone = AVCaptureDevice.default(for: .audio) else {
            throw MobileFailure.message(TDetached("A rear camera and microphone are required.", "需要后置相机和麦克风。", "需要後置相機和麥克風。"))
        }
        guard let format = profile.format(on: camera) else { throw setupError(profile) }
        let video = try AVCaptureDeviceInput(device: camera)
        let audio = try AVCaptureDeviceInput(device: microphone)
        session.beginConfiguration()
        configuredProfile = nil
        session.outputs.forEach { session.removeOutput($0) }
        session.inputs.forEach { session.removeInput($0) }
        defer {
            if configuredProfile == nil {
                session.outputs.forEach { session.removeOutput($0) }
                session.inputs.forEach { session.removeInput($0) }
            }
            session.commitConfiguration()
        }
        guard session.canAddInput(video) else { throw setupError(profile) }
        session.addInput(video)
        guard session.canAddInput(audio) else { throw setupError(profile) }
        session.automaticallyConfiguresCaptureDeviceForWideColor = false
        session.addInput(audio)
        try camera.lockForConfiguration()
        do {
            defer { camera.unlockForConfiguration() }
            // Setting the device format selects the session’s input-priority mode.
            camera.activeFormat = format
            camera.activeColorSpace = .sRGB
            camera.automaticallyAdjustsVideoHDREnabled = false
            if camera.isVideoHDREnabled { camera.isVideoHDREnabled = false }
            let duration = CMTime(value: 1, timescale: CMTimeScale(profile.rawValue))
            camera.activeVideoMinFrameDuration = duration
            camera.activeVideoMaxFrameDuration = duration
        }
        guard session.canAddOutput(movie) else { throw setupError(profile) }
        session.addOutput(movie)
        guard let connection = movie.connection(with: .video), movie.connection(with: .audio) != nil else { throw setupError(profile) }
        if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .standard }
        // There is no product duration limit. AVFoundation ends recording if
        // the OS interrupts it or free disk space falls below this reserve.
        movie.minFreeDiskSpaceLimit = 200 * 1024 * 1024
        configuredProfile = profile
    }

    private func setupError(_ profile: MobileMovieProfile) -> MobileFailure {
        let title = profile.title
        return .message(TDetached("This camera could not configure \(title) SDR HEVC with audio.",
                                  "当前相机无法配置 \(title) SDR HEVC 有声录制。",
                                  "目前相機無法設定 \(title) SDR HEVC 有聲錄製。"))
    }

    func record(to url: URL, angle: CGFloat,
                completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        queue.async {
            guard let profile = self.configuredProfile else {
                completion(.failure(self.setupError(.uhd30))); return
            }
            guard self.session.isRunning, !self.session.isInterrupted,
                  self.finishing == nil, let connection = self.movie.connection(with: .video),
                  connection.isActive, self.movie.connection(with: .audio)?.isActive == true else {
                completion(.failure(self.setupError(profile))); return
            }
            self.finishing = completion
            self.pendingStop = false
            if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
            self.movie.startRecording(to: url, recordingDelegate: self)
        }
    }

    func stopRecording() {
        queue.async {
            guard self.finishing != nil else { return }
            if self.movie.isRecording { self.movie.stopRecording() }
            else { self.pendingStop = true }
        }
    }

    func suspend() {
        queue.async {
            if self.finishing != nil {
                if self.movie.isRecording { self.movie.stopRecording() }
                else { self.pendingStop = true }
            } else if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        queue.async {
            if self.pendingStop, self.movie.isRecording { self.movie.stopRecording() }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        queue.async {
            let completion = self.finishing
            self.finishing = nil
            self.pendingStop = false
            if self.session.isRunning { self.session.stopRunning() }
            if let error, ((error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) != true {
                completion?(.failure(error))
            } else {
                completion?(.success(outputFileURL))
            }
        }
    }
}

private struct MobileMoviePreview: UIViewRepresentable {
    let camera: MobileMovieCapture
    let device: AVCaptureDevice

    final class Surface: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        var rotation: AVCaptureDevice.RotationCoordinator?
        var observation: NSKeyValueObservation?

        func updateRotation() {
            guard let rotation, let connection = preview.connection else { return }
            let angle = rotation.videoRotationAngleForHorizonLevelPreview
            if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
        }

        override func layoutSubviews() { super.layoutSubviews(); updateRotation() }
    }

    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        view.preview.session = camera.session
        view.preview.videoGravity = .resizeAspect
        let rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: view.preview)
        view.rotation = rotation
        view.observation = rotation.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak view] _, _ in
            Task { @MainActor [weak view] in view?.updateRotation() }
        }
        return view
    }

    func updateUIView(_ view: Surface, context: Context) { view.updateRotation() }
}

private struct MobileMovieTake: Codable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    let film: String
    var profile: MobileMovieProfile.RawValue?

    static func directory() -> URL {
        URL.applicationSupportDirectory.appendingPathComponent("SilverphaseVideoTakes", isDirectory: true)
    }

    var folder: URL { Self.directory().appendingPathComponent(id.uuidString, isDirectory: true) }
    var source: URL { folder.appendingPathComponent("Silverphase-Original.mov") }
    var developed: URL { folder.appendingPathComponent("Silverphase-Film.mov") }

    func prepare() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: folder.appendingPathComponent("take.json"), options: .atomic)
    }

    static func pending() -> [Self] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory(), includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder -> Self? in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("take.json")),
                  let take = try? JSONDecoder().decode(Self.self, from: data),
                  take.folder.path == folder.path, FileManager.default.fileExists(atPath: take.source.path) else { return nil }
            return take
        }.sorted { $0.date > $1.date }
    }

    func removeAfterSave() {
        try? FileManager.default.removeItem(at: folder)
    }
}

struct MobileVideoCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var camera = MobileMovieCapture()
    @State private var device: AVCaptureDevice?
    @State private var rotation: AVCaptureDevice.RotationCoordinator?
    @State private var armed = false
    @State private var preparing = false
    @State private var runningSince: Date?
    @State private var stopping = false
    @State private var saving = false
    @State private var developing = false
    @State private var saveTask: Task<Void, Never>?
    @State private var player: AVPlayer?
    @State private var film = MobileCameraRecipe.defaultFilmID
    @State private var profile: MobileMovieProfile = .uhd30
    @State private var allows60 = false
    @State private var selected: MobileMovieTake?
    @State private var takes: [MobileMovieTake] = []
    @State private var message: String?
    @State private var notice: String?
    @State private var exportProgress = 0.0

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let player {
                    VideoPlayer(player: player)
                        .background(.black)
                        .clipShape(.rect(cornerRadius: 10))
                } else if let device {
                    MobileMoviePreview(camera: camera, device: device)
                        .background(.black)
                        .clipShape(.rect(cornerRadius: 10))
                } else {
                    Color.black.overlay { Image(systemName: "video").foregroundStyle(.white.opacity(0.7)) }
                        .clipShape(.rect(cornerRadius: 10))
                }
                if let runningSince, !stopping {
                    Text(runningSince, style: .timer).monospacedDigit().foregroundStyle(.red)
                } else if stopping || saving || preparing {
                    ProgressView(value: saving && exportProgress > 0 ? exportProgress : nil)
                    if stopping { Text(T("Finalizing recording…", "正在结束录像…", "正在結束錄影…")) }
                }
                if let notice { Text(notice).font(.footnote) }
                if let selected {
                    Text(selected.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.monospacedDigit())
                    Button(T("Develop and save video", "显影并保存视频", "顯影並儲存影片"), systemImage: "film") {
                        save(selected, developed: true)
                    }.buttonStyle(.borderedProminent).disabled(saving)
                    Button(T("Save original video", "保存视频原片", "儲存原始影片"), systemImage: "square.and.arrow.down") {
                        save(selected, developed: false)
                    }.buttonStyle(.bordered).disabled(saving)
                    Button(T("Back to camera", "返回相机", "返回相機")) { self.selected = nil }
                        .disabled(saving)
                    if developing {
                        Button(T("Cancel development", "取消显影", "取消顯影")) { saveTask?.cancel() }
                    }
                } else {
                    if !takes.isEmpty && runningSince == nil {
                        Menu(T("Recover unsaved videos", "恢复未保存的视频", "復原未儲存的影片"), systemImage: "film.stack") {
                            ForEach(takes) { take in
                                Button(take.date.formatted(date: .abbreviated, time: .standard)) {
                                    selected = take
                                    armed = false
                                    camera.suspend()
                                    device = nil
                                }
                            }
                        }.disabled(preparing)
                    }
                    Picker(T("Film", "胶片", "膠片"), selection: $film) {
                        ForEach(StockCatalog.shared.filmsForPicker) { Text($0.displayName).tag($0.id) }
                    }.disabled(runningSince != nil || stopping)
                    Picker(T("Frame rate", "帧率", "影格率"), selection: $profile) {
                        Text(MobileMovieProfile.uhd30.title).tag(MobileMovieProfile.uhd30)
                        if allows60 { Text(MobileMovieProfile.uhd60.title).tag(MobileMovieProfile.uhd60) }
                    }.disabled(runningSince != nil || preparing || stopping)
                    Text(T("UHD SDR · HEVC · Rear camera · Film applied after recording",
                           "UHD SDR · HEVC · 后置相机 · 录完后显影",
                           "UHD SDR · HEVC · 後置相機 · 錄完後顯影"))
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                        if runningSince != nil { stop() }
                        else if !armed { Task { await prepareCamera() } }
                        else { begin() }
                    } label: {
                        Label(runningSince != nil ? T("Stop", "停止", "停止") : armed
                              ? T("Record", "录制", "錄製") : T("Enable video camera", "启用视频相机", "啟用影片相機"),
                              systemImage: runningSince != nil ? "stop.fill" : "record.circle")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(preparing || stopping)
                    .accessibilityIdentifier("video.record")
                }
            }
            .padding()
            .navigationTitle(T("Video", "视频", "影片"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(T("Close", "关闭", "關閉")) { dismiss() }
                        .disabled(preparing || runningSince != nil || stopping || saving)
                }
            }
        }
        .interactiveDismissDisabled(preparing || runningSince != nil || stopping || saving)
        .task {
            takes = MobileMovieTake.pending()
            allows60 = MobileMovieProfile.supports(.uhd60)
        }
        .onChange(of: profile) { _, _ in
            camera.suspend()
            device = nil
            armed = false
        }
        .onChange(of: selected?.id) { _, _ in
            player?.pause()
            player = selected.map { AVPlayer(url: $0.source) }
        }
        .onDisappear {
            player?.pause()
            camera.suspend()
        }
        .onChange(of: scenePhase) { _, state in
            guard state == .background else { return }
            if runningSince != nil { stop() }
            else {
                camera.suspend()
                armed = false
                device = nil
            }
        }
        .alert(T("Video", "视频", "影片"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(T("OK", "好", "好")) { message = nil }
        } message: { Text(message ?? "") }
    }

    private func prepareCamera() async {
        guard !preparing else { return }
        preparing = true
        defer { preparing = false }
        for media in [AVMediaType.video, .audio] {
            let allowed: Bool
            switch AVCaptureDevice.authorizationStatus(for: media) {
            case .authorized: allowed = true
            case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: media)
            default: allowed = false
            }
            guard allowed else {
                message = T("Allow camera and microphone access in Settings to record sound.",
                            "请在系统设置里允许相机和麦克风权限，以录制有声视频。",
                            "請在系統設定允許相機和麥克風權限，以錄製有聲影片。")
                return
            }
        }
        guard scenePhase == .active else { return }
        do {
            let activeDevice = try await camera.start(profile: profile).device
            guard scenePhase == .active else { camera.suspend(); return }
            device = activeDevice
            rotation = AVCaptureDevice.RotationCoordinator(device: activeDevice, previewLayer: nil)
            armed = true
        } catch { message = error.localizedDescription }
    }

    private func begin() {
        guard armed, runningSince == nil, !stopping else { return }
        let take = MobileMovieTake(id: UUID(), date: .now, film: film, profile: profile.rawValue)
        do { try take.prepare() }
        catch { message = error.localizedDescription; return }
        notice = nil
        runningSince = .now
        camera.record(to: take.source, angle: rotation?.videoRotationAngleForHorizonLevelCapture ?? 0) { result in
            Task { @MainActor in
                runningSince = nil
                stopping = false
                armed = false
                device = nil
                takes = MobileMovieTake.pending()
                switch result {
                case .success:
                    selected = take
                    do {
                        try await MobileMovieDevelopment.checkCapture(source: take.source, frameRate: take.profile)
                    } catch {
                        notice = error.localizedDescription
                    }
                case .failure(let error): message = error.localizedDescription
                }
            }
        }
    }

    private func stop() {
        guard runningSince != nil, !stopping else { return }
        stopping = true
        camera.stopRecording()
    }

    private func save(_ take: MobileMovieTake, developed: Bool) {
        guard !saving else { return }
        saving = true
        developing = developed
        player?.pause()
        exportProgress = 0
        saveTask = Task {
            defer { saving = false; developing = false; saveTask = nil }
            do {
                try await PhotoLibraryWriter.authorize()
                let file: URL
                if developed {
                    try await MobileMovieDevelopment.export(source: take.source, destination: take.developed,
                                                            film: take.film, frameRate: take.profile) { value in
                        Task { @MainActor in exportProgress = value }
                    }
                    file = take.developed
                } else { file = take.source }
                try Task.checkCancellation()
                developing = false
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.creationDate = take.date
                    request.addResource(with: .video, fileURL: file, options: nil)
                }
#if DEBUG
                if !ProcessInfo.processInfo.arguments.contains("--video-check-keep-files") { take.removeAfterSave() }
#else
                take.removeAfterSave()
#endif
                takes = MobileMovieTake.pending()
                selected = nil
                notice = T("Saved to Photos", "已保存到照片", "已儲存到照片")
            } catch is CancellationError {
                notice = T("Development canceled. Your original was kept.", "已取消显影，原片仍保留。", "已取消顯影，原片仍保留。")
            } catch {
                message = error.localizedDescription
                // The take is still on disk. Retry development or save the original.
            }
        }
    }
}
#endif
