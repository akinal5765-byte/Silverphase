#if SILVERPHASE_APP
@preconcurrency import AVFoundation
import AVKit
import Foundation
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import CoreTransferable

struct MobileMovieProfile: Codable, Hashable, Sendable {
    struct Raster: Codable, Hashable, Sendable {
        let width: Int
        let height: Int
        var pixels: Int { width * height }
        var title: String { "\(width)×\(height)" }

        init(_ width: Int, _ height: Int) {
            self.width = max(width, height); self.height = min(width, height)
        }
    }

    let raster: Raster
    private let durationValue: Int64
    private let durationScale: Int32

    init(raster: Raster, duration: CMTime) {
        self.raster = raster
        // CMTime's arithmetic may leave equivalent values at different scales.
        var x = duration.value, y = Int64(duration.timescale)
        while y != 0 { (x, y) = (y, x % y) }
        durationValue = duration.value / x
        durationScale = Int32(Int64(duration.timescale) / x)
    }

    var duration: CMTime { CMTime(value: durationValue, timescale: durationScale) }
    var fps: Double { 1 / duration.seconds }
    var rateTitle: String { "\(fps.formatted(.number.precision(.fractionLength(0...3)))) fps" }
    var title: String { "\(raster.title) / \(rateTitle)" }

    static func ranked(_ profiles: [Self]) -> [Self] {
        Set(profiles).sorted {
            if $0.raster.pixels != $1.raster.pixels { return $0.raster.pixels > $1.raster.pixels }
            if $0.raster.width != $1.raster.width { return $0.raster.width > $1.raster.width }
            return CMTimeCompare($0.duration, $1.duration) < 0
        }
    }

    static func cameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
                                         mediaType: .video, position: .back).devices.sorted {
            if $0.deviceType == .builtInWideAngleCamera { return $1.deviceType != .builtInWideAngleCamera }
            if $1.deviceType == .builtInWideAngleCamera { return false }
            return $0.localizedName < $1.localizedName
        }
    }

    private static func raster(for format: AVCaptureDevice.Format) -> Raster? {
        let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        guard d.width > 0, d.height > 0, format.supportedColorSpaces.contains(.sRGB),
              !format.unsupportedCaptureOutputClasses.contains(where: { $0 == AVCaptureMovieFileOutput.self }) else { return nil }
        return Raster(Int(d.width), Int(d.height))
    }

    private static func contains(_ duration: CMTime, _ range: AVFrameRateRange) -> Bool {
        duration.isNumeric && duration.value > 0 &&
        CMTimeCompare(duration, range.minFrameDuration) >= 0 && CMTimeCompare(duration, range.maxFrameDuration) <= 0
    }

    static func available(on device: AVCaptureDevice) -> [Self] {
        let common: [CMTime] = [24, 25, 30, 48, 50, 60, 90, 100, 120, 200, 240].map {
            CMTime(value: 1, timescale: $0)
        } + [24000, 30000, 60000, 120000].map { CMTime(value: 1001, timescale: $0) }
        var profiles: [Self] = []
        for format in device.formats {
            guard let raster = raster(for: format) else { continue }
            for range in format.videoSupportedFrameRateRanges {
                for duration in common + [range.minFrameDuration] where contains(duration, range) {
                    profiles.append(Self(raster: raster, duration: duration))
                }
            }
        }
        return ranked(profiles)
    }

    func format(on device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let matching = device.formats.filter { format in
            Self.raster(for: format) == raster &&
            format.videoSupportedFrameRateRanges.contains { Self.contains(duration, $0) }
        }
        return matching.first(where: { !$0.isVideoBinned }) ?? matching.first
    }

    static func legacyUHD(_ rate: Int) -> Self? {
        guard rate == 30 || rate == 60 else { return nil }
        return Self(raster: Raster(3840, 2160), duration: CMTime(value: 1, timescale: Int32(rate)))
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

    func start(camera: AVCaptureDevice, profile: MobileMovieProfile) async throws -> Configuration {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    if self.session.isRunning { self.session.stopRunning() }
                    try self.configure(camera: camera, profile: profile)
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

    private func configure(camera: AVCaptureDevice, profile: MobileMovieProfile) throws {
        guard let microphone = AVCaptureDevice.default(for: .audio) else {
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
            if #available(iOS 18.0, *), format.isAutoVideoFrameRateSupported {
                camera.isAutoVideoFrameRateEnabled = false
            }
            let duration = profile.duration
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
                completion(.failure(MobileFailure.message(TDetached("Video camera not ready.", "视频相机未就绪。", "影片相機未就緒。")))); return
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
    var profile: Int? // Legacy private Debug takes used 30/60 to identify UHD.
    var captureSpec: MobileMovieProfile?
    var importedFilename: String?
    var expectedSpec: MobileMovieProfile? { captureSpec ?? profile.flatMap(MobileMovieProfile.legacyUHD) }

    static func directory() -> URL {
        URL.applicationSupportDirectory.appendingPathComponent("SilverphaseVideoTakes", isDirectory: true)
    }

    var folder: URL { Self.directory().appendingPathComponent(id.uuidString, isDirectory: true) }
    var source: URL {
        let ext = importedFilename.flatMap { Self.safeExtension(URL(fileURLWithPath: $0)) } ?? "mov"
        return folder.appendingPathComponent("Silverphase-Original.\(ext)")
    }
    private static func safeExtension(_ source: URL) -> String? {
        let ext = source.pathExtension.lowercased()
        return ["mov", "mp4", "m4v"].contains(ext) ? ext : nil
    }
    var title: String { importedFilename ?? date.formatted(date: .abbreviated, time: .standard) }

    static func importMovie(from url: URL, film: String) async throws -> Self {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard safeExtension(url) != nil else {
            throw MobileFailure.message(TDetached("Choose a MOV, MP4 or M4V video file.", "请选择 MOV、MP4 或 M4V 视频。", "請選擇 MOV、MP4 或 M4V 影片。"))
        }
        let movie = AVURLAsset(url: url)
        let duration = try await movie.load(.duration)
        let tracks = try await movie.loadTracks(withMediaType: .video)
        guard duration.seconds.isFinite, duration.seconds > 0, !tracks.isEmpty, try await movie.load(.isPlayable) else {
            throw MobileFailure.message(TDetached("This file is not a playable video.", "这个文件不是可播放的视频。", "這個檔案不是可播放的影片。"))
        }
        let take = Self(id: UUID(), date: .now, film: film, importedFilename: url.lastPathComponent)
        do {
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: take.folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: take.source)
            try Task.checkCancellation()
            try take.prepare()
            return take
        } catch {
            try? FileManager.default.removeItem(at: take.folder)
            throw error
        }
    }

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

    func removeFromLibrary() throws {
        try FileManager.default.removeItem(at: folder)
    }
}

private struct MobileVideoPickerFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(received.file.lastPathComponent)
            do { try FileManager.default.copyItem(at: received.file, to: destination) }
            catch {
                try? FileManager.default.removeItem(at: folder)
                throw error
            }
            return Self(url: destination)
        }
    }
}

private struct MobileVideoLibraryThumbnail: View {
    let source: URL
    @State private var thumbnail: CGImage?

    var body: some View {
        Group {
            if let thumbnail { Image(decorative: thumbnail, scale: 1).resizable().scaledToFill() }
            else { Rectangle().fill(.quaternary).overlay { Image(systemName: "film") } }
        }
        .frame(width: 72, height: 48)
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityHidden(true)
        .task(id: source) {
            thumbnail = nil
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: source))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 144, height: 96)
            if let generated = try? await generator.image(at: .zero), !Task.isCancelled {
                thumbnail = generated.image
            }
        }
    }
}

struct MobileVideoCaptureView: View {
    var libraryMode = false
    @State private var choosingVideos = false
    @State private var choosingFiles = false
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var importingVideo = false
    @State private var reviewFilm = MobileCameraRecipe.defaultFilmID
    @State private var deleteVideo: MobileMovieTake?
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
    @State private var cameraChoices: [AVCaptureDevice] = []
    @State private var lensID = ""
    @State private var profiles: [MobileMovieProfile] = []
    @State private var automatic = true
    @State private var manual: MobileMovieProfile?
    @State private var activeProfile: MobileMovieProfile?

    private var requestedProfile: MobileMovieProfile? { automatic ? profiles.first : manual }
    private var rasters: [MobileMovieProfile.Raster] {
        var seen: Set<MobileMovieProfile.Raster> = []
        return profiles.map(\.raster).filter { seen.insert($0).inserted }
    }
    private var controlsLocked: Bool { runningSince != nil || preparing || stopping }
    @State private var selected: MobileMovieTake?
    @State private var takes: [MobileMovieTake] = []
    @State private var message: String?
    @State private var notice: String?
    @State private var exportProgress = 0.0

    var body: some View {
        NavigationStack {
            Group {
            if libraryMode && selected == nil {
                videoLibrary
            } else {
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
                    Text(T("Original preview · no film applied", "当前预览是原片，未套用胶片", "目前預覽是原片，未套用膠片"))
                        .font(.footnote).foregroundStyle(.secondary)
                    Picker(T("Film for development", "显影胶片", "顯影膠片"), selection: $reviewFilm) {
                        ForEach(StockCatalog.shared.filmsForPicker) { Text($0.displayName).tag($0.id) }
                    }.disabled(saving)
                    Text(selected.date.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.monospacedDigit())
                    Button(T("Apply film and save", "套用胶片并保存", "套用膠片並儲存"), systemImage: "film") {
                        save(selected, developed: true)
                    }.buttonStyle(.borderedProminent).disabled(saving)
                    Button(T("Save original without film", "不套胶片，保存原片", "不套膠片，儲存原片"), systemImage: "square.and.arrow.down") {
                        save(selected, developed: false)
                    }.buttonStyle(.bordered).disabled(saving)
                    Button(libraryMode ? T("Back to videos", "返回视频图库", "返回影片圖庫")
                                      : T("Back to camera", "返回相机", "返回相機")) { self.selected = nil }
                        .disabled(saving)
                    if developing {
                        Button(T("Cancel development", "取消显影", "取消顯影")) { saveTask?.cancel() }
                    }
                } else {
                    if !takes.isEmpty && runningSince == nil {
                        Menu(T("Open recorded videos", "打开已保存到图库的视频", "開啟已儲存到圖庫的影片"), systemImage: "film.stack") {
                            ForEach(takes) { take in
                                Button(take.date.formatted(date: .abbreviated, time: .standard)) {
                                    selected = take
                                    resetPreview()
                                }
                            }
                        }.disabled(preparing)
                    }
                    Picker(T("Film", "胶片", "膠片"), selection: $film) {
                        ForEach(StockCatalog.shared.filmsForPicker) { Text($0.displayName).tag($0.id) }
                    }.disabled(runningSince != nil || stopping)
                    if cameraChoices.count > 1 {
                        Picker(T("Lens", "镜头", "鏡頭"), selection: $lensID) {
                            ForEach(cameraChoices, id: \.uniqueID) { lens in Text(lens.localizedName).tag(lens.uniqueID) }
                        }.disabled(controlsLocked)
                    }
                    Toggle(T("Automatic maximum", "自动最高规格", "自動最高規格"), isOn: $automatic)
                        .disabled(controlsLocked || profiles.isEmpty)
                    if !automatic, !profiles.isEmpty {
                        Picker(T("Resolution", "分辨率", "解析度"), selection: Binding<MobileMovieProfile.Raster?>(
                            get: { manual?.raster },
                            set: { raster in
                                if manual?.raster == raster { return }
                                manual = profiles.first { $0.raster == raster }
                                if let manual {
                                    notice = T("Selected \(manual.title). Adjust its frame rate below.",
                                               "已选 \(manual.title)，可在下方调整帧率。",
                                               "已選 \(manual.title)，可在下方調整影格率。")
                                }
                            })) {
                            if manual == nil { Text(T("Choose", "请选择", "請選擇")).tag(nil as MobileMovieProfile.Raster?) }
                            ForEach(rasters, id: \.self) { Text($0.title).tag(Optional($0)) }
                        }.disabled(controlsLocked)
                        if let raster = manual?.raster {
                            Picker(T("Frame rate", "帧率", "影格率"), selection: $manual) {
                                ForEach(profiles.filter { $0.raster == raster }, id: \.self) {
                                    Text($0.rateTitle).tag(Optional($0))
                                }
                            }.disabled(controlsLocked)
                        }
                    }
                    if let spec = activeProfile ?? requestedProfile {
                        Text("\(spec.title) · SDR HEVC")
                            .font(.subheadline.monospacedDigit())
                            .accessibilityIdentifier("video.spec")
                    } else {
                        Text(T("No recording format selected.", "未选择可用的录制规格。", "未選擇可用的錄製規格。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(T("Sound on · Film applied after recording", "有声录制 · 录完后显影", "有聲錄製 · 錄完後顯影"))
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
                    .disabled(preparing || stopping || (runningSince == nil && requestedProfile == nil))
                    .accessibilityIdentifier("video.record")
                }
            }
            .padding()
            }
            }
            .navigationTitle(libraryMode ? T("Video Library", "视频图库", "影片圖庫") : T("Video", "视频", "影片"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(T("Close", "关闭", "關閉")) { dismiss() }
                        .disabled(preparing || runningSince != nil || stopping || saving || importingVideo)
                }
            }
        }
        .interactiveDismissDisabled(preparing || runningSince != nil || stopping || saving || importingVideo)
        .task {
            takes = MobileMovieTake.pending()
            guard !libraryMode else { return }
            cameraChoices = MobileMovieProfile.cameras()
            if lensID.isEmpty, let first = cameraChoices.first {
                lensID = first.uniqueID
                refreshFormats()
            }
        }
        .onChange(of: lensID) { _, _ in refreshFormats() }
        .onChange(of: automatic) { _, enabled in
            resetPreview()
            if !enabled, manual == nil { manual = profiles.first }
            notice = nil
        }
        .onChange(of: requestedProfile) { _, _ in resetPreview() }
        .onChange(of: selected?.id) { _, _ in
            player?.pause()
            player = selected.map { AVPlayer(url: $0.source) }
            if let selected {
                reviewFilm = StockCatalog.shared.stock(selected.film) != nil ? selected.film : MobileCameraRecipe.defaultFilmID
            }
        }
        .onDisappear {
            player?.pause()
            camera.suspend()
        }
        .onChange(of: scenePhase) { _, state in
            guard state == .background else { return }
            if runningSince != nil { stop() }
            else {
                resetPreview()
            }
        }
        .photosPicker(isPresented: $choosingVideos, selection: $selectedVideoItem,
                      matching: .videos, preferredItemEncoding: .current)
        .onChange(of: selectedVideoItem) { _, item in
            guard let item, !importingVideo else { return }
            importingVideo = true
            Task {
                defer { importingVideo = false; selectedVideoItem = nil }
                do {
                    guard let transfer = try await item.loadTransferable(type: MobileVideoPickerFile.self) else {
                        throw MobileFailure.message(T("Couldn't load the selected video.", "无法读取所选视频。", "無法讀取所選影片。"))
                    }
                    defer { try? FileManager.default.removeItem(at: transfer.url.deletingLastPathComponent()) }
                    try await addMovie(transfer.url)
                } catch { message = error.localizedDescription }
            }
        }
        .fileImporter(isPresented: $choosingFiles, allowedContentTypes: [.quickTimeMovie, .mpeg4Movie, .movie]) { result in
            guard !importingVideo else { return }
            importingVideo = true
            Task {
                defer { importingVideo = false }
                do { try await addMovie(result.get()) }
                catch { message = error.localizedDescription }
            }
        }
        .confirmationDialog(T("Remove from the Video Library?", "从视频图库移除？", "從影片圖庫移除？"),
                            isPresented: Binding(get: { deleteVideo != nil }, set: { if !$0 { deleteVideo = nil } }),
                            titleVisibility: .visible, presenting: deleteVideo) { take in
            Button(T("Remove", "移除", "移除"), role: .destructive) {
                do { try take.removeFromLibrary(); takes = MobileMovieTake.pending() }
                catch { message = error.localizedDescription }
            }
            Button(T("Cancel", "取消", "取消"), role: .cancel) {}
        } message: { _ in
            Text(T("This removes only the copy in Silverphase, not your Photos or Files.", "只移除 Silverphase 保存的副本，不会删除系统相册或文件里的原件。", "只移除 Silverphase 儲存的副本，不會刪除系統相簿或檔案裡的原件。"))
        }
        .alert(T("Video", "视频", "影片"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button(T("OK", "好", "好")) { message = nil }
        } message: { Text(message ?? "") }
    }

    private var videoLibrary: some View {
        List {
            Section {
                Button(T("Import from Photos", "从照片导入视频", "從照片匯入影片"), systemImage: "photo.on.rectangle") {
                    choosingVideos = true
                }.accessibilityIdentifier("video-library.import-photos")
                Button(T("Import from Files", "从文件导入视频", "從檔案匯入影片"), systemImage: "folder") {
                    choosingFiles = true
                }.accessibilityIdentifier("video-library.import-files")
                if importingVideo { ProgressView(T("Importing video…", "正在导入视频…", "正在匯入影片…")) }
            }
            .disabled(importingVideo)
            Section(T("Videos", "视频", "影片")) {
                if takes.isEmpty {
                    Text(T("No videos yet.", "还没有视频。", "還沒有影片。")).foregroundStyle(.secondary)
                }
                ForEach(takes) { take in
                    Button {
                        notice = nil
                        selected = take
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text(take.title).lineLimit(1)
                                let details = StockCatalog.shared.stock(take.film)?.displayName ?? take.film
                                Text(take.expectedSpec.map { "\($0.title) · \(details)" } ?? details)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { MobileVideoLibraryThumbnail(source: take.source) }
                    }
                    .swipeActions(allowsFullSwipe: false) {
                        Button(role: .destructive) { deleteVideo = take } label: { Label(T("Remove", "移除", "移除"), systemImage: "trash") }
                    }
                }
            }
            .disabled(importingVideo)
        }
        .accessibilityIdentifier("video-library.list")
    }

    private func addMovie(_ source: URL) async throws {
        let take = try await MobileMovieTake.importMovie(from: source, film: film)
        takes = MobileMovieTake.pending()
        notice = nil
        selected = take
    }

#if DEBUG
    static func runVideoLibraryRegression() async {
        let fixture = URL.documentsDirectory.appending(path: "video-library-regression.mp4")
        let report = URL.documentsDirectory.appending(path: "video-library-report.json")
        let values: [String: Bool]
        do {
            let baseline = Set(MobileMovieTake.pending().map(\.id))
            let take = try await MobileMovieTake.importMovie(from: fixture, film: "kodak_tri_x_400")
            defer { try? take.removeFromLibrary() }
            let bytes = try Data(contentsOf: take.source)
            values = [
                "preservedBytes": try bytes == Data(contentsOf: fixture),
                "persisted": MobileMovieTake.pending().contains { $0.id == take.id && $0.film == "kodak_tri_x_400" },
                "keptFilenameAndType": take.importedFilename == fixture.lastPathComponent && take.source.pathExtension == "mp4",
                "keptPreviousVideos": baseline.isSubset(of: Set(MobileMovieTake.pending().map(\.id))),
                "notCaptureLocked": take.expectedSpec == nil,
            ]
        } catch { values = ["importSucceeded": false] }
        if let data = try? JSONEncoder().encode(values) { try? data.write(to: report, options: .atomic) }
    }
#endif

    private func resetPreview() {
        camera.suspend()
        armed = false
        device = nil
        rotation = nil
        activeProfile = nil
    }

    private func refreshFormats() {
        resetPreview()
        profiles = cameraChoices.first { $0.uniqueID == lensID }.map { MobileMovieProfile.available(on: $0) } ?? []
        if let manual, !profiles.contains(manual) {
            self.manual = nil
            if !automatic {
                notice = T("The previous format is unavailable on this lens. Choose a new one or enable Automatic.",
                           "当前镜头不支持原规格，请重新选择，或打开自动最高规格。",
                           "目前鏡頭不支援原規格，請重新選擇，或開啟自動最高規格。")
            }
        } else { notice = nil }
    }

    private func prepareCamera() async {
        guard !preparing, let spec = requestedProfile,
              let lens = cameraChoices.first(where: { $0.uniqueID == lensID }) else { return }
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
            let activeDevice = try await camera.start(camera: lens, profile: spec).device
            guard scenePhase == .active else { camera.suspend(); return }
            device = activeDevice
            activeProfile = spec
            rotation = AVCaptureDevice.RotationCoordinator(device: activeDevice, previewLayer: nil)
            armed = true
        } catch { message = error.localizedDescription }
    }

    private func begin() {
        guard armed, let activeProfile, runningSince == nil, !stopping else { return }
        let take = MobileMovieTake(id: UUID(), date: .now, film: film, captureSpec: activeProfile)
        do { try take.prepare() }
        catch { message = error.localizedDescription; return }
        notice = nil
        runningSince = .now
        camera.record(to: take.source, angle: rotation?.videoRotationAngleForHorizonLevelCapture ?? 0) { result in
            Task { @MainActor in
                runningSince = nil
                stopping = false
                resetPreview()
                takes = MobileMovieTake.pending()
                switch result {
                case .success:
                    selected = take
                    do {
                        try await MobileMovieDevelopment.checkCapture(source: take.source, expected: take.expectedSpec)
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
        let stockID = reviewFilm
        saveTask = Task {
            // The library keeps the original after either save. Never reuse
            // a film export from another recipe or a previous failed save.
            let output = take.folder.appendingPathComponent("export-\(UUID().uuidString).mov")
            defer {
#if DEBUG
                if !ProcessInfo.processInfo.arguments.contains("--video-check-keep-files") {
                    try? FileManager.default.removeItem(at: output)
                }
#else
                try? FileManager.default.removeItem(at: output)
#endif
            }
            defer { saving = false; developing = false; saveTask = nil }
            do {
                try await PhotoLibraryWriter.authorize()
                let file: URL
                if developed {
                    try await MobileMovieDevelopment.export(source: take.source, destination: output,
                                                            film: stockID, expected: take.expectedSpec) { value in
                        Task { @MainActor in exportProgress = value }
                    }
                    file = output
                } else { file = take.source }
                try Task.checkCancellation()
                developing = false
                try await PhotoLibraryWriter.saveVideo(file, creationDate: take.date)
                let stock = StockCatalog.shared.stock(stockID)?.displayName ?? stockID
                notice = developed
                    ? T("Saved to Photos with \(stock).", "已套用 \(stock) 并保存到相册。", "已套用 \(stock) 並儲存到相簿。")
                    : T("Original saved to Photos without film.", "原片已保存到相册，未套用胶片。", "原片已儲存到相簿，未套用膠片。")
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
