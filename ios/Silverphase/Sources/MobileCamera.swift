import AVFoundation
import AVKit
import CoreImage
import CoreMotion
import ImageIO
import OSLog
import SwiftUI
import UniformTypeIdentifiers

#if SILVERPHASE_APP
struct MobileCameraDevelopment: Sendable {
    let image: CGImage
    let animation: MobileDevelopmentAssets?
}

private struct CameraPhotoBounds: PreferenceKey {
    enum Role: Hashable { case preview, thumbnail }
    static let defaultValue: [Role: Anchor<CGRect>] = [:]

    static func reduce(value: inout [Role: Anchor<CGRect>], nextValue: () -> [Role: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

#endif
struct MobileCameraView: View {
#if SILVERPHASE_APP
    let initialHingeClosed: Bool?
    let libraryThumbnail: URL?
    let mirrorsFrontCamera: Bool
    let importPhoto: (URL, Stock?, MobileCameraRecipe) async throws -> MobilePhoto
    let developPhoto: (MobilePhoto, Bool) async throws -> MobileCameraDevelopment
    let savePhoto: (MobilePhoto) async throws -> Void
    let returnToLibrary: (UUID) -> Void
#else
    let storeCapture: (Data, MobileCaptureFormat, MobileCameraRecipe) async throws -> Void
    let openLibrary: () -> Void
    let lockedHingeClosed: Bool?
    private let mirrorsFrontCamera = false
#endif

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
#if SILVERPHASE_APP
    @AppStorage("mobile.camera.film") private var filmID = ""
    @AppStorage(MobileCameraPreviewMode.key) private var previewMode = MobileCameraPreviewMode.initial()
    private var showsFilmPreview: Bool { previewMode != .system }
    @AppStorage(MobileCaptureLocation.preferenceKey) private var recordsLocation = true
    @State private var lookEngine = MobileCameraLookEngine()
    @State private var fastLookEngine = MobileCameraFastLookEngine()
    @State private var lookFrame: MobileCameraLookResult?
    @State private var lookUnavailable = false
    @AppStorage("mobile.camera.metering") private var metering = MobileMeteringMode.center_weighted
    @AppStorage("mobile.camera.diffusion") private var diffusion = MobileDiffusionFilter.off
    @AppStorage("mobile.camera.goldenGrid") private var showsGoldenGrid = true
    @AppStorage("mobile.camera.useGoldenRatio") private var usesGoldenRatio = false
    @AppStorage("mobile.camera.level") private var showsLevel = true
#else
    // The secure capture extension cannot persist UserDefaults. Keep controls
    // in session state, seeded from CameraCaptureIntent.appContext below.
    @State private var filmID = ""
    @State private var metering = MobileMeteringMode.center_weighted
    @State private var diffusion = MobileDiffusionFilter.off
    @State private var showsGoldenGrid = true
    @State private var usesGoldenRatio = false
    @State private var showsLevel = true
#endif
#if SILVERPHASE_APP
    @State private var hingeClosed: Bool?
#endif
    @State private var camera = MobileStillCamera()
    @State private var configuration: MobileCameraConfiguration?
    @State private var lens = MobileCameraLens.wide
    @State private var rearLens = MobileCameraLens.wide
    @State private var switching = false
    @State private var flash = AVCaptureDevice.FlashMode.off
    @State private var exposure: Float = 0
    @State private var focusPoint: CGPoint?
    @State private var focusLocked = false
    @State private var focusFeedbackID = 0
    @State private var draggingExposure = false
    @State private var portraitPreview = true
    @State private var portraitMode = false
    @State private var levelRoll: Double?
    @State private var deviceQuarterTurn = 0.0
    @State private var measuredCapturePose: MobileCameraCapturePose?
    // MobileCameraCanvas keeps the camera's own coordinate system portrait.
    private let interfaceQuarterTurn = 0.0
    @State private var controlRotation = 0.0
    @State private var filmLabelHeight: CGFloat = 60
#if SILVERPHASE_APP
    @State private var showingFilms = false
#endif
    @State private var capturing = false
#if SILVERPHASE_APP
    @State private var developing = false
    @State private var savingToPhotos = false
    @State private var latestPhotoID: UUID?
    @State private var latestPreview: CGImage?
    @State private var frozenShot: CGImage?
    @State private var reveal: MobileCameraDevelopment?
    @State private var shotQuarterTurn = 0.0
    @State private var revealOpacity = 0.0
    @State private var landingPhoto = false
    @State private var photoAtThumbnail = false
    @State private var holdLanding = false
#endif
    @State private var previewing = false
    @State private var changingPhysicalLens = false
    @State private var switchFrame: CGImage?
#if SILVERPHASE_APP
    @State private var frozenSwitchGeneration: UInt64 = 0
#endif
    @State private var issue: String?
    @State private var failure: String?
    @State private var retry = 0

    private var films: [Stock] { StockCatalog.shared.filmsForPicker }
    private var film: Stock? {
#if SILVERPHASE_APP
        let defaultID = MobileProcessContract.defaults["film_stock"]?.stringValue ?? MobileCameraRecipe.defaultFilmID
#else
        let defaultID = MobileCameraRecipe.defaultFilmID
#endif
        let id = filmID.isEmpty ? defaultID : filmID
        return films.first { $0.id == id } ?? films.first
    }
    private var captureRecipe: MobileCameraRecipe {
        MobileCameraRecipe(filmID: film?.id, metering: metering, diffusion: diffusion)
    }

#if SILVERPHASE_APP
    private var lookRequest: MobileCameraRecipe? {
        guard !isLayoutCheck, showsFilmPreview, canRunCamera, !shotInProgress, film != nil else { return nil }
        return captureRecipe
    }

    private var shotInProgress: Bool { capturing || developing || savingToPhotos || reveal != nil }
#else
    private var shotInProgress: Bool { capturing }
    private let showingFilms = false
#endif
    private var isLayoutCheck: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--camera-layout-check")
#else
        false
#endif
    }

    private var canRunCamera: Bool {
#if SILVERPHASE_APP
        scenePhase == .active
#else
        true
#endif
    }
    private var ready: Bool {
#if !SILVERPHASE_APP
        guard !sessionInterrupted else { return false }
#endif
        return configuration != nil && previewing && !switching && switchFrame == nil && !shotInProgress && canRunCamera
    }

#if SILVERPHASE_APP
    private var fillsPanel: Bool { (hingeClosed ?? initialHingeClosed) == true }
    private var revealRotation: Double { (interfaceQuarterTurn - shotQuarterTurn).remainder(dividingBy: 360) }
    private var revealSwapsAxes: Bool { abs(revealRotation.remainder(dividingBy: 180)) == 90 }

#else
    private var fillsPanel: Bool { lockedHingeClosed != false }
    @State private var sessionInterrupted = false
    @State private var contentionRecoveryPending = false
    @State private var attemptedContentionRecovery = false
    @State private var attemptedStartupRecovery = false
    @State private var hasShownPreview = false
    @State private var hasMountedViewfinder = false
    @State private var lockedDevelopment: MobileDevelopmentAssets?
    private var waitingForCamera: Bool { (sessionInterrupted || !previewing || configuration == nil) && issue == nil }
#endif

    private var cameraLayout: some View {
        ZStack {
            viewfinder(fillsPanel: fillsPanel)
                .ignoresSafeArea(.container, edges: fillsPanel ? .all : [])
            VStack(spacing: 8) {
                topControls
#if SILVERPHASE_APP
                previewStatus
#endif
                Spacer(minLength: 0)
                if let configuration { finderControls(configuration) }
                captureDock
            }
        }
    }

    var body: some View {
        MobileCameraCanvas { cameraBody }
    }

    private var cameraBody: some View {
        cameraLayout
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#if SILVERPHASE_APP
        .background {
            MobileCameraOrientationObserver()
                .allowsHitTesting(false)
            if #available(iOS 27.1, *), UIDevice.current.userInterfaceIdiom == .phone {
                ProcessBarGeometryProbe(hingeChanged: { hingeClosed = $0 })
                    .allowsHitTesting(false)
            }
        }
        .overlayPreferenceValue(CameraPhotoBounds.self) { anchors in
            GeometryReader { geometry in
                if let reveal, landingPhoto, let from = anchors[.preview], let to = anchors[.thumbnail] {
                    let rect = geometry[photoAtThumbnail ? to : from]
                    let swapsAxes = !photoAtThumbnail && revealSwapsAxes
                    Image(decorative: reveal.image, scale: 1).resizable().scaledToFill()
                        .frame(width: swapsAxes ? rect.height : rect.width,
                               height: swapsAxes ? rect.width : rect.height)
                        .clipShape(.rect(cornerRadius: photoAtThumbnail ? rect.width / 2 : 20))
                        .rotationEffect(.degrees(revealRotation))
                        .position(x: rect.midX, y: rect.midY)
                        .accessibilityHidden(true)
                }
            }.allowsHitTesting(false)
        }
#endif
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
#if SILVERPHASE_APP
        .interactiveDismissDisabled(capturing || developing || savingToPhotos)
        .accessibilityHidden(showingFilms)
        .overlay {
            if showingFilms {
                filmPicker
                    .ignoresSafeArea(.container, edges: fillsPanel ? .horizontal : [])
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
#endif
#if !SILVERPHASE_APP
        .task(id: waitingForCamera ? retry : nil) {
            guard waitingForCamera else { return }
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            guard waitingForCamera else { return }
            // startRunning can still be in progress or waiting on a system
            // interruption. Leave it alone unless the user explicitly retries.
            issue = T("The camera is not ready yet. Try again.", "相机尚未准备好，请重试。", "相機尚未準備好，請重試。")
        }
        .task(id: contentionRecoveryPending) {
            guard contentionRecoveryPending else { return }
            // Let AVFoundation resume after the competing client releases the
            // camera. Restart once only if the session or preview stays stuck.
            do { try await Task.sleep(for: .milliseconds(2800)) } catch { return }
            contentionRecoveryPending = false
            guard sessionInterrupted || !camera.session.isRunning || !previewing || configuration == nil else { return }
            Logger(subsystem: "com.silverphase.editor", category: "LockedCamera")
                .notice("Restarting capture after camera contention")
            retryCamera()
        }
        .task(id: previewing && !sessionInterrupted && !contentionRecoveryPending) {
            guard previewing, !sessionInterrupted, !contentionRecoveryPending else { return }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            attemptedContentionRecovery = false
        }
        .onGeometryChange(for: CGRect.self) { geometry in
            geometry.frame(in: .global)
        } action: { frame in
            Logger(subsystem: "com.silverphase.editor", category: "LockedCamera")
                .notice("Camera layout: \(String(describing: frame), privacy: .public)")
        }
        .onChange(of: deviceQuarterTurn) { _, _ in lockedDevelopment = nil }
        .onChange(of: previewing) { _, visible in
            if visible, !sessionInterrupted {
                if !hasShownPreview {
                    Logger(subsystem: "com.silverphase.editor", category: "LockedCamera")
                        .notice("First camera preview frame")
                }
                hasShownPreview = true
                issue = nil
            }
        }
#endif
#if SILVERPHASE_APP
        .task(id: canRunCamera && recordsLocation) {
            if !isLayoutCheck { MobileCameraLocation.shared.setCameraActive(canRunCamera, enabled: recordsLocation) }
        }
        .task(id: captureRecipe) {
            do { try await SilverphaseCameraCaptureIntent.updateAppContext(captureRecipe) }
            catch {
                Logger(subsystem: "com.silverphase.editor", category: "Camera")
                    .notice("Could not update lock-screen camera preferences")
            }
        }
        .task(id: MobileCameraLookTaskID(request: lookRequest, cameraRetry: retry, mode: previewMode)) {
            lookEngine.workGate.setActive(false)
            fastLookEngine.workGate.setActive(false)
            lookUnavailable = false
            guard let request = lookRequest else {
                lookFrame = nil
                await lookEngine.close()
                await fastLookEngine.close(keepingColorTables: shotInProgress && canRunCamera)
                return
            }
            if lookFrame?.recipe != request { lookFrame = nil }
            let mode = previewMode
            if mode == .approximate { await lookEngine.close(); fastLookEngine.workGate.setActive(true) }
            else { await fastLookEngine.close(); lookEngine.workGate.setActive(true) }
            var previousSerial: UInt64?
            do {
                while !Task.isCancelled, lookRequest == request {
                    guard previewing, !changingPhysicalLens,
                          let frame = camera.lookFrames.latest(), frame.serial != previousSerial else {
                        try await Task.sleep(for: .milliseconds(30))
                        continue
                    }
                    let started = ProcessInfo.processInfo.systemUptime
                    let reduced = ProcessInfo.processInfo.isLowPowerModeEnabled ||
                        ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
                    let budget = MobileCameraLookBudget(reducedPower: reduced)
                    let geometry = camera.lookGeometry()
                    let result: MobileCameraLookResult
                    if mode == .approximate {
                        result = try await fastLookEngine.render(frame, angle: geometry.angle, mirrored: geometry.mirrored,
                                                                recipe: request, longEdge: reduced ? 640 : 960)
                    } else {
                        result = try await lookEngine.render(frame, angle: geometry.angle, mirrored: geometry.mirrored,
                                                            recipe: request, longEdge: budget.longEdge)
                    }
                    try Task.checkCancellation()
                    guard lookRequest == request, previewMode == mode else { return }
                    guard result.sourceGeneration == camera.lookFrames.currentGeneration() else { continue }
                    lookFrame = result; previousSerial = frame.serial
                    let pause = max(0.001, (mode == .approximate ? (reduced ? 1.0 / 20 : 1.0 / 30) : budget.interval) - (ProcessInfo.processInfo.systemUptime - started))
                    try await Task.sleep(for: .seconds(pause))
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, lookRequest == request, previewMode == mode else { return }
                lookUnavailable = true; lookFrame = nil
                Logger(subsystem: "com.silverphase.editor", category: "CameraLook")
                    .error("Film preview unavailable: \(error.localizedDescription, privacy: .public)")
            }
        }
        .task(id: retry) { if canRunCamera && !isLayoutCheck { await startCamera() } }
#else
        .task {
            let initial = captureRecipe
            do {
                guard let saved = try await SilverphaseCameraCaptureIntent.appContext,
                      captureRecipe == initial, !shotInProgress else { return }
                // Do not overwrite a choice made while context was loading.
                if let id = saved.filmID, films.contains(where: { $0.id == id }) { filmID = id }
                metering = saved.metering; diffusion = saved.diffusion
            } catch {
                Logger(subsystem: "com.silverphase.editor", category: "LockedCamera")
                    .notice("Using default camera preferences; app context unavailable")
            }
        }
        .task(id: hasMountedViewfinder ? retry : nil) {
            if hasMountedViewfinder && !isLayoutCheck { await startCamera() }
        }
#endif
        .task(id: canRunCamera) {
            if canRunCamera && !isLayoutCheck { await trackDeviceOrientation() }
        }
        .onChange(of: interfaceQuarterTurn - deviceQuarterTurn, initial: true) { _, target in
            controlRotation += (target - controlRotation).remainder(dividingBy: 360)
        }
#if SILVERPHASE_APP
        .task(id: landingPhoto) {
            guard landingPhoto else { return }
            // Allow the flying image to appear at the preview anchor before moving it.
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
            guard !Task.isCancelled, reveal != nil else { return }
            withAnimation(.easeInOut(duration: 0.34), completionCriteria: .logicallyComplete) {
                photoAtThumbnail = true
            } completion: {
                if photoAtThumbnail { finishReveal() }
            }
        }
#endif
        .task(id: previewing && switchFrame != nil) {
            guard previewing, switchFrame != nil else { return }
            while !Task.isCancelled {
                if await camera.hasSettledPreview() {
#if SILVERPHASE_APP
                    guard MobileCameraPreviewTransition.canReveal(mode: previewMode, unavailable: lookUnavailable,
                        result: lookFrame, recipe: captureRecipe, frozenGeneration: frozenSwitchGeneration,
                        currentGeneration: camera.lookFrames.currentGeneration()) else {
                        do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                        continue
                    }
#endif
                    // Give the preview layer time to present the newly delivered frames.
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled, previewing else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { switchFrame = nil }
                    return
                }
                do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
            }
        }
#if SILVERPHASE_APP
        .onChange(of: reduceMotion) { _, reduced in if reduced { finishReveal() } }
        .onChange(of: savingToPhotos) { _, saving in
            // A held print lands as soon as the Photos write returns.
            guard !saving, holdLanding else { return }
            holdLanding = false
            landReveal()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { measuredCapturePose = nil }
            if phase == .active { retry += 1 }
            else if phase == .background {
                finishReveal()
                stopCamera()
            }
        }
#endif
        .onDisappear { stopCamera() }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.wasInterruptedNotification, object: camera.session).receive(on: DispatchQueue.main)) { notification in
#if SILVERPHASE_APP
            camera.detachPreview()
            configuration = nil
            previewing = false
            issue = T("The camera is unavailable right now", "相机暂时不可用", "相機暫時不可用")
#else
            sessionInterrupted = true
            let reason = (notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue ?? -1
            if reason == AVCaptureSession.InterruptionReason.videoDeviceInUseByAnotherClient.rawValue,
               !attemptedContentionRecovery {
                attemptedContentionRecovery = true
                contentionRecoveryPending = true
            }
            Logger(subsystem: "com.silverphase.editor", category: "LockedCamera").notice("Capture interrupted, reason: \(reason)")
#endif
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.interruptionEndedNotification, object: camera.session).receive(on: DispatchQueue.main)) { _ in
#if SILVERPHASE_APP
            if canRunCamera { retry += 1 }
#else
            sessionInterrupted = false
            issue = nil
            Logger(subsystem: "com.silverphase.editor", category: "LockedCamera")
                .notice("Capture interruption ended, running: \(camera.session.isRunning), configured: \(configuration != nil)")
            if !contentionRecoveryPending, configuration == nil || !camera.session.isRunning { retry += 1 }
#endif
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.runtimeErrorNotification, object: camera.session).receive(on: DispatchQueue.main)) { notification in
#if SILVERPHASE_APP
            camera.detachPreview()
#else
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
            Logger(subsystem: "com.silverphase.editor", category: "LockedCamera")
                .notice("Capture runtime error: \(error?.code ?? 0)")
            if error?.domain == AVFoundationErrorDomain,
               error?.code == AVError.Code.mediaServicesWereReset.rawValue,
               recoverLockedCameraOnce() { return }
#endif
            configuration = nil
            previewing = false
            issue = T("The camera stopped. Try again.", "相机运行中断，请重试", "相機執行中斷，請重試")
        }
        .alert(T("Camera", "相机", "相機"), isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button(T("OK", "好", "好")) { failure = nil }
        } message: { Text(failure ?? "") }
    }

    private var controlOrientation: CameraControlOrientation {
        CameraControlOrientation(rotation: controlRotation, animated: !reduceMotion)
    }

#if SILVERPHASE_APP
    private var previewStatus: some View {
        HStack {
            if showsFilmPreview, !shotInProgress {
                Text(lookUnavailable ? T("Raw viewfinder · preview unavailable", "原始取景 · 预览不可用", "原始取景 · 預覽不可用") : lookFrame?.snapshot(for: captureRecipe) == nil ? T("Preparing the film preview…", "正在准备胶片预览…", "正在準備膠片預覽…") : (previewMode == .approximate ? T("Approximate preview", "近似预览", "近似預覽") : T("Native engine preview", "原生引擎预览", "原生引擎預覽")))
                    .font(.caption2).lineLimit(1)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.black.opacity(0.35), in: Capsule())
                    .accessibilityIdentifier("camera.look-status")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .allowsHitTesting(false)
    }
#endif

    private var topControls: some View {
        HStack {
            Button(action: returnFromCamera) {
                Image(systemName: "chevron.left")
                    // Chrome icons stay white; the button would otherwise inherit
                    // the system blue accent inside the lock-screen host.
                    .foregroundStyle(.white)
                    .modifier(controlOrientation)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
                .accessibilityLabel(T("Back to Library", "返回图库", "返回圖庫"))
                .accessibilityIdentifier("camera.back")
                .modifier(ChromeSurface(radius: 22, interactive: true))
                .disabled(shotInProgress)
            Spacer()
            HStack(spacing: 4) {
                if let configuration {
                    Text(configuration.format.rawValue)
                        .font(.caption2.monospaced().weight(.semibold))
                        .modifier(AdjustmentNumberTransition(value: nil, label: configuration.format.rawValue))
                        .modifier(controlOrientation)
                        .padding(.leading, 10)
                }
                flashMenu
                meteringMenu
                Menu {
                    Toggle(T("Composition grid", "构图网格", "構圖網格"), isOn: $showsGoldenGrid)
                    Picker(T("Grid style", "网格样式", "網格樣式"), selection: $usesGoldenRatio) {
                        Text(T("Rule of thirds", "三分网格", "三分網格")).tag(false)
                        Text(T("Golden ratio", "黄金分割", "黃金分割")).tag(true)
                    }
                    .disabled(!showsGoldenGrid)
                    Toggle(T("Level", "水平仪", "水平儀"), isOn: $showsLevel)
#if SILVERPHASE_APP
                    Divider()
                    Picker(T("Live film preview", "实时胶片取景", "即時膠片取景"), selection: $previewMode) {
                        ForEach(MobileCameraPreviewMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
#endif
                } label: {
                    Image(systemName: "grid")
                        .foregroundStyle(showsGoldenGrid || showsLevel ? MobileStyle.accent : .white)
                        .modifier(controlOrientation)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(T("Composition aids", "构图辅助", "構圖輔助"))
                .accessibilityIdentifier("camera.options")
            }
            .padding(4)
            .modifier(ChromeSurface(radius: 24, interactive: true))
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var meteringMenu: some View {
        Menu {
            Picker(T("Metering Mode", "测光模式", "測光模式"), selection: $metering) {
                ForEach(MobileMeteringMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            if metering == .custom {
                Text(T("Keeps the input exposure; the system video viewfinder and the RAW-finished photo may differ in brightness.", "保留输入曝光；系统视频取景与 RAW 成片的亮度可能不同。", "保留輸入曝光；系統影片取景與 RAW 成片的亮度可能不同。"))
            }
        } label: {
            Image(systemName: "camera.metering.center.weighted")
                .foregroundStyle(metering == .custom ? .white : MobileStyle.accent)
                .modifier(controlOrientation)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(T("Metering Mode", "测光模式", "測光模式"))
        .accessibilityValue(metering.title)
        .accessibilityIdentifier("camera.metering")
        .disabled(shotInProgress)
    }

    private func returnFromCamera() {
#if SILVERPHASE_APP
        dismiss()
#else
        openLibrary()
#endif
    }

    private var captureDock: some View {
        HStack(spacing: 8) {
            galleryButton.frame(maxWidth: .infinity)
            shutterButton
            filmControls.frame(maxWidth: .infinity)
        }
        .padding(8)
        .frame(maxWidth: 420)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var filmControls: some View {
        HStack(alignment: .top, spacing: 4) {
#if SILVERPHASE_APP
            filmButton
#endif
            diffusionMenu
        }
        .disabled(shotInProgress)
    }

    private var diffusionMenu: some View {
        Menu {
            Picker(T("Shooting diffusion filter", "拍摄柔光镜", "拍攝柔光鏡"), selection: $diffusion) {
                ForEach(MobileDiffusionFilter.allCases, id: \.self) { filter in
                    Text(filter.title).tag(filter)
                }
            }
        } label: {
            CameraDiffusionFilterGlyph()
                .foregroundStyle(diffusion == .off ? .white : MobileStyle.accent)
                // Rotate inside the original fixed label, before its frame and
                // glass are applied. The menu keeps the original layout bounds.
                .modifier(controlOrientation)
                .frame(width: 44, height: 44)
                .modifier(ChromeSurface(radius: 22, interactive: true))
        }
        .accessibilityLabel(T("Shooting diffusion filter", "拍摄柔光镜", "拍攝柔光鏡"))
        .accessibilityValue(diffusion.title)
        .accessibilityIdentifier("camera.diffusion")
    }

    private func finderControls(_ configuration: MobileCameraConfiguration) -> some View {
        HStack(spacing: 4) {
            flipButton(configuration)
            Spacer(minLength: 0)
            lensControls(configuration)
            Spacer(minLength: 0)
            if configuration.hasPortraitCamera || portraitMode {
                Button { setPortraitMode(!portraitMode) } label: {
                    Image(systemName: "f.cursive")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(portraitMode ? MobileStyle.accent : .white)
                        .modifier(controlOrientation)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .modifier(ChromeSurface(radius: 22, interactive: true))
                .disabled(!ready)
                .accessibilityLabel(T("Portrait mode", "人像模式", "人像模式"))
                .accessibilityAddTraits(portraitMode ? .isSelected : [])
                .accessibilityIdentifier("camera.portrait")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 12)
    }

#if SILVERPHASE_APP
    private var galleryButton: some View {
        Button {
            if let latestPhotoID { returnToLibrary(latestPhotoID) }
            else { dismiss() }
        } label: { latestThumbnail }
        .buttonStyle(.plain)
        .accessibilityLabel(T("Back to Library", "返回图库", "返回圖庫"))
        .accessibilityIdentifier("camera.latest")
        .disabled(shotInProgress)
        .anchorPreference(key: CameraPhotoBounds.self, value: .bounds) { [.thumbnail: $0] }
    }

#else
    private var galleryButton: some View {
        Button(action: openLibrary) {
            Image(systemName: "photo.on.rectangle")
                .foregroundStyle(.white)
                .modifier(controlOrientation)
                .frame(width: 48, height: 48)
                .modifier(ChromeSurface(radius: 24, interactive: true))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(T("Unlock and open the library", "解锁并打开图库", "解鎖並開啟圖庫"))
        .accessibilityIdentifier("camera.latest")
        .disabled(shotInProgress)
    }
#endif
    private var shutterButton: some View {
        Button(action: takePhoto) {
            Circle().strokeBorder(.white.opacity(0.75), lineWidth: 1.5)
                .overlay { Circle().fill(.white).padding(5) }
                .overlay {
                    if capturing {
                        ProgressView().tint(.black)
                    }
                }
                .frame(width: 68, height: 68)
        }
        .buttonStyle(.plain)
        .modifier(ChromeSurface(radius: 34, interactive: true))
        .disabled(!ready)
        .opacity(ready || capturing ? 1 : 0.45)
        .accessibilityLabel(T("Take Photo", "拍照", "拍照"))
        .accessibilityIdentifier("camera.shutter")
    }

#if SILVERPHASE_APP
    private func setFilmPicker(_ visible: Bool) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) { showingFilms = visible }
    }

    private var filmPicker: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { setFilmPicker(false) }
                    .accessibilityHidden(true)
                VStack(spacing: 0) {
                    Capsule().fill(.white.opacity(0.5)).frame(width: 36, height: 4)
                        .frame(maxWidth: .infinity, minHeight: 20)
                        .contentShape(Rectangle())
                        .gesture(DragGesture().onEnded { drag in
                            if drag.translation.height > 24 { setFilmPicker(false) }
                        })
                        .accessibilityHidden(true)
                    HStack {
                        Text(T("Choose Film", "选择胶片", "選擇膠片")).font(.headline).accessibilityAddTraits(.isHeader)
                        Spacer()
                        Button(T("Done", "完成", "完成")) { setFilmPicker(false) }.tint(MobileStyle.accent)
                            .frame(minHeight: 32)
                    }
                    .padding(.horizontal, 18)
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 12) {
                            ForEach(films) { stock in
                                Button {
                                    filmID = stock.id
                                    setFilmPicker(false)
                                } label: {
                                    BrowserCard(title: stock.name, subtitle: stock.speedLabel ?? "", width: 96, selected: stock.id == film?.id) {
                                        if let artwork = stock.packagingArtworkURL ?? stock.coverURL {
                                            FilmstripThumbnail(url: artwork, fillsFrame: true)
                                        } else {
                                            Image(systemName: "film").frame(maxWidth: .infinity, maxHeight: .infinity)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(stock.name)
                                .accessibilityAddTraits(stock.id == film?.id ? .isSelected : [])
                            }
                        }
                        .padding(12)
                    }
                }
                .frame(maxWidth: 560)
                .frame(height: geometry.size.height * 0.54)
                .modifier(ChromeSurface(radius: 30, interactive: true))
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape) { setFilmPicker(false) }
            }
        }
    }

    private var filmButton: some View {
        Button { setFilmPicker(true) } label: { filmButtonLabel }
        .buttonStyle(.plain)
        .disabled(shotInProgress || films.isEmpty)
        .accessibilityLabel(T("Choose Film", "选择胶片", "選擇膠片"))
        .accessibilityValue(film?.name ?? "")
        .accessibilityIdentifier("camera.film")
    }

    private var filmButtonLabel: some View {
        ZStack(alignment: .top) {
            Color.clear.frame(width: 44, height: 44)
                .modifier(ChromeSurface(radius: 22, interactive: true))
            VStack(spacing: 3) {
                Image(systemName: "film").font(.title3)
                    .frame(width: 44, height: 44)
                let title = film?.name ?? T("Film", "胶片", "膠片")
                Text(title).font(.caption2).lineLimit(1)
                    .modifier(AdjustmentNumberTransition(value: nil, label: title))
                    .frame(maxWidth: 88)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { filmLabelHeight = $0 }
            .modifier(CameraControlOrientation(
                rotation: controlRotation, animated: !reduceMotion,
                anchor: UnitPoint(x: 0.5, y: 22 / max(44, filmLabelHeight))
            ))
        }
        .foregroundStyle(.white)
    }

    private var latestThumbnail: some View {
        Group {
            if let latestPreview {
                Image(decorative: latestPreview, scale: 1)
                    .resizable().scaledToFill()
            } else if let libraryThumbnail {
                FilmstripThumbnail(url: libraryThumbnail, fillsFrame: true)
            } else {
                Image(systemName: "photo.on.rectangle").frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.12))
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(Circle())
        .modifier(controlOrientation)
        .opacity(reveal == nil ? 1 : 0)
    }

#endif
    private var previewHardwareShutterEnabled: Bool {
#if SILVERPHASE_APP
        ready && !showingFilms
#else
        // Register on the live viewfinder, including while its first frame arrives.
        true
#endif
    }

    private func viewfinder(fillsPanel: Bool) -> some View {
        GeometryReader { proxy in
            ZStack {
#if SILVERPHASE_APP
                let previewDevice = configuration?.device
#else
                // Mount the preview layer and hardware interaction before starting the session.
                let previewDevice = configuration?.device ?? lens.physicalLens.findDevice()
#endif
                if let previewDevice {
                    let aspect = configuration?.aspect ?? 4.0 / 3.0
                    let ratio = portraitPreview ? 1 / aspect : aspect
                    let width = fillsPanel ? proxy.size.width : min(proxy.size.width, proxy.size.height * ratio)
                    let height = fillsPanel ? proxy.size.height : width / ratio
                    ZStack {
                        Color(white: 0.08)
                        if !changingPhysicalLens {
                            MobileCameraPreview(camera: camera, device: previewDevice,
                                                portrait: $portraitPreview, previewing: $previewing,
                                                mirrored: lens == .front && mirrorsFrontCamera,
                                                hardwareShutterEnabled: previewHardwareShutterEnabled, shutter: takePhoto,
                                                canAdjustExposure: ready && focusPoint != nil && !focusLocked && configuration?.exposureRange != nil,
                                                exposureRotation: controlRotation,
                                                focus: focus, adjustExposure: dragExposure)
                                .id(previewDevice.uniqueID)
#if SILVERPHASE_APP
                                .overlay {
                                    if let image = lookFrame?.snapshot(for: captureRecipe), !lookUnavailable,
                                       !shotInProgress, canRunCamera {
                                        Image(decorative: image, scale: 1).resizable().scaledToFill()
                                            .frame(width: width, height: height).clipped()
                                            .allowsHitTesting(false).accessibilityHidden(true)
                                    }
                                }
#endif
#if !SILVERPHASE_APP
                                .onAppear { hasMountedViewfinder = true }
#else
                                .opacity(previewing || switchFrame != nil ? 1 : 0)
#endif
                                .accessibilityHidden(true)
                        }
#if SILVERPHASE_APP
                        let showsLensPlaceholder = changingPhysicalLens || !previewing
#else
                        let showsLensPlaceholder = changingPhysicalLens
#endif
                        if showsLensPlaceholder && switchFrame == nil {
                            Text(lens.title).font(.headline).foregroundStyle(.secondary)
                                .modifier(AdjustmentNumberTransition(value: nil, label: lens.title))
                                .modifier(controlOrientation)
                        }
                    }
                    .frame(width: width, height: height)
                    .overlay {
                        if let switchFrame {
                            Image(decorative: switchFrame, scale: 1).resizable().scaledToFill()
                                .frame(width: width, height: height)
                                .transition(.opacity)
                                .accessibilityHidden(true)
                                .allowsHitTesting(false)
                        }
#if SILVERPHASE_APP
                        // Hold the shot on screen while it develops. This replaces
                        // the old "显影中…" spinner: the frozen frame reads as the
                        // photo the user just took, and the develop animation then
                        // plays over it.
                        if let frozenShot {
                            Image(decorative: frozenShot, scale: 1).resizable().scaledToFill()
                                .frame(width: width, height: height)
                                // Settle back once the develop animation takes the
                                // stage, so the print stays the subject.
                                .opacity(reveal == nil ? 1 : 0.45)
                                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: reveal == nil)
                                .accessibilityHidden(true)
                                .allowsHitTesting(false)
                        }
#endif
                    }
                    .clipped()
                    .overlay {
                        if previewing && !changingPhysicalLens {
                            compositionGuides
                            focusIndicator
                        }
                    }
#if !SILVERPHASE_APP
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                        Logger(subsystem: "com.silverphase.editor", category: "LockedCamera")
                            .notice("Viewfinder layout: \(String(describing: frame), privacy: .public)")
                    }
                    .overlay {
                        if let development = lockedDevelopment {
                            let scale = max(width / CGFloat(development.print.width),
                                            height / CGFloat(development.print.height))
                            MobileDevelopmentView(assets: development, running: true) {
                                if lockedDevelopment?.id == development.id { lockedDevelopment = nil }
                            }
                            .id(development.id)
                            .frame(width: CGFloat(development.print.width) * scale,
                                   height: CGFloat(development.print.height) * scale)
                            .frame(width: width, height: height)
                            .clipped()
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                        }
                    }
#endif
#if SILVERPHASE_APP
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: previewing)
#endif
                }
                if let issue {
                    VStack(spacing: 12) {
                        Text(issue).multilineTextAlignment(.center)
                        Button(T("Retry", "重试", "重試"), action: retryCamera).buttonStyle(.bordered)
                    }.padding().background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                } else if configuration == nil {
                    if !shotInProgress && !isLayoutCheck {
                        ProgressView(T("Opening the camera", "正在打开相机", "正在開啟相機")).modifier(controlOrientation)
                    }
                }
#if SILVERPHASE_APP
                // No spinner while developing: the frozen shot covers the wait and
                // the develop animation takes over from it. Keep the fallback for
                // the rare shot where no viewfinder frame could be frozen.
                if (savingToPhotos && reveal == nil) || (developing && frozenShot == nil) {
                    VStack(spacing: EditorDesign.gutter) {
                        ProgressView().tint(.primary)
                        Text(developing ? T("Developing…", "显影中…", "顯影中…") : T("Saving to Photos…", "保存到相册…", "儲存到相簿…")).font(EditorDesign.noticeTitle)
                    }
                    .modifier(controlOrientation)
                    .frame(width: 104, height: 104)
                    .modifier(ChromeSurface(radius: 20))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(developing ? "camera.developing" : "camera.saving")
                }
                if let reveal {
                    let ratio = CGFloat(reveal.image.width) / CGFloat(reveal.image.height)
                    let availableWidth = revealSwapsAxes ? proxy.size.height : proxy.size.width
                    let availableHeight = revealSwapsAxes ? proxy.size.width : proxy.size.height
                    // Folded (outer display) runs the develop edge to edge, matching
                    // the full-bleed viewfinder there; other layouts keep the print
                    // card. Either way the print keeps its aspect ratio and the
                    // overflow is clipped by the panel.
                    let width = fillsPanel ? max(availableWidth, availableHeight * ratio)
                                           : min(availableWidth, availableHeight * ratio)
                    let height = width / ratio
                    Group {
                        if landingPhoto {
                            Color.clear
                        } else if let animation = reveal.animation {
                            MobileDevelopmentView(assets: animation, running: true, playbackRate: 2, finished: landReveal)
                                .padding(-1 / max(1, displayScale))
                        } else {
                            Image(decorative: reveal.image, scale: 1).resizable()
                                .opacity(revealOpacity)
                                .background(.black)
                                .task {
                                    withAnimation(.easeOut(duration: 0.18)) { revealOpacity = 1 }
                                    do { try await Task.sleep(for: .milliseconds(380)) } catch { return }
                                    landReveal()
                                }
                        }
                    }
                    .frame(width: width, height: height)
                    .clipShape(.rect(cornerRadius: fillsPanel ? 0 : 20))
                    .rotationEffect(.degrees(revealRotation))
                    .frame(width: revealSwapsAxes ? height : width, height: revealSwapsAxes ? width : height)
                    .anchorPreference(key: CameraPhotoBounds.self, value: .bounds) { [.preview: $0] }
                    .accessibilityLabel(T("Development preview", "显影预览", "顯影預覽"))
                }
#endif
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func lensControls(_ configuration: MobileCameraConfiguration) -> some View {
        HStack(spacing: 2) {
            if portraitMode || lens == .front {
                let title = portraitMode ? T("Portrait", "人像", "人像") : T("Front", "前置", "前置")
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .modifier(AdjustmentNumberTransition(value: nil, label: title))
                    .foregroundStyle(MobileStyle.accent)
                    .modifier(controlOrientation)
                    .padding(.horizontal, 14).frame(minHeight: 44)
            } else {
                ForEach(configuration.rearLenses) { option in
                    let alternate = configuration.alternateLenses[option]
                    let usesAlternate = alternate == lens
                    let selected = option == lens || usesAlternate
                    let title = usesAlternate ? lens.title : configuration.lensTitles[option] ?? option.title
                    Button {
                        selectLens(option == lens ? alternate ?? option : option)
                    } label: {
                        VStack(spacing: 2) {
                            Text(title)
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .modifier(AdjustmentNumberTransition(
                                    value: alternate == nil ? nil : (usesAlternate ? alternate?.transitionValue : option.transitionValue),
                                    fractionDigits: 0
                                ))
                            if alternate != nil {
                                focalLengthIndicator(selected: selected, usesAlternate: usesAlternate)
                            }
                        }
                        .modifier(controlOrientation)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                        .foregroundStyle(selected ? MobileStyle.accent : .white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("camera.lens." + option.rawValue)
                }
            }
        }
        .modifier(ChromeSurface(radius: 22, interactive: true))
        .disabled(!ready)
    }

    private func focalLengthIndicator(selected: Bool, usesAlternate: Bool) -> some View {
        Capsule()
            .fill(.white.opacity(0.20))
            .frame(width: 14, height: 3)
            .overlay {
                Capsule()
                    .fill(MobileStyle.accent)
                    .frame(width: 7, height: 3)
                    .offset(x: usesAlternate ? 3.5 : -3.5)
            }
            .opacity(selected ? 1 : 0.55)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: usesAlternate)
            .accessibilityHidden(true)
    }

    private func flipButton(_ configuration: MobileCameraConfiguration) -> some View {
        Button {
            selectLens(lens == .front ? rearLens : .front)
        } label: {
            Image(systemName: "camera.rotate")
                .modifier(controlOrientation)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .modifier(ChromeSurface(radius: 22, interactive: true))
        .accessibilityLabel(lens == .front ? T("Switch to the rear camera", "切换到后置相机", "切換到後置相機") : T("Switch to the front camera", "切换到前置相机", "切換到前置相機"))
        .accessibilityIdentifier("camera.flip")
        .disabled(!ready || portraitMode || !configuration.hasFrontCamera)
    }

    private func setPortraitMode(_ enabled: Bool) {
        guard ready, portraitMode != enabled else { return }
        switchCamera(to: lens, portrait: enabled, changesInput: true)
    }

    private var compositionGuides: some View {
        ZStack {
            if showsGoldenGrid {
                Canvas { context, size in
                    var lines = Path()
                    let division = usesGoldenRatio ? (3 - sqrt(5.0)) / 2 : 1.0 / 3
                    for fraction in [division, 1 - division] {
                        let x = size.width * fraction
                        let y = size.height * fraction
                        lines.move(to: CGPoint(x: x, y: 0))
                        lines.addLine(to: CGPoint(x: x, y: size.height))
                        lines.move(to: CGPoint(x: 0, y: y))
                        lines.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(lines, with: .color(.black.opacity(0.28)), lineWidth: 2)
                    context.stroke(lines, with: .color(.white.opacity(0.35)), lineWidth: 1)
                }
            }
            if showsLevel, let levelRoll {
                let levelAngle = -levelRoll.remainder(dividingBy: 90)
                let vertical = abs(controlRotation.remainder(dividingBy: 180)) > 45
                let aligned = abs(levelAngle) < 1.5
                HStack(spacing: 4) {
                    Capsule().fill(.white.opacity(0.60)).frame(width: 18, height: 2)
                    Capsule().fill(aligned ? MobileStyle.accent : .white)
                        .frame(width: 38, height: 2)
                        .rotationEffect(.degrees(aligned ? 0 : levelAngle))
                    Capsule().fill(.white.opacity(0.60)).frame(width: 18, height: 2)
                }
                .rotationEffect(.degrees(vertical ? 90 : 0))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: vertical)
                .shadow(color: .black.opacity(0.7), radius: 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func trackDeviceOrientation() async {
        measuredCapturePose = nil
        let motion = CMMotionManager()
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates()
        defer { motion.stopDeviceMotionUpdates() }
        while !Task.isCancelled {
            if let gravity = motion.deviceMotion?.gravity, hypot(gravity.x, gravity.y) > 0.2 {
                let roll = atan2(gravity.x, -gravity.y) * 180 / .pi
                // Hysteresis keeps the controls steady near the diagonal.
                if abs((roll - deviceQuarterTurn).remainder(dividingBy: 360)) > 52 {
                    deviceQuarterTurn = (roll / 90).rounded() * 90
                }
                measuredCapturePose = MobileCameraCapturePose(quarterTurn: deviceQuarterTurn)
                if showsLevel { levelRoll = (roll * 2).rounded() / 2 }
            } else {
                levelRoll = nil
            }
            do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
        }
    }

    private var flashMenu: some View {
        Menu {
            ForEach(configuration?.flashModes ?? [], id: \.rawValue) { mode in
                Button {
                    flash = mode
                } label: {
                    if flash == mode { Label(flashTitle(mode), systemImage: "checkmark") }
                    else { Text(flashTitle(mode)) }
                }
            }
        } label: {
            Image(systemName: flash == .off ? "bolt.slash" : flash == .auto ? "bolt.badge.automatic" : "bolt.fill")
                .foregroundStyle(flash == .off ? Color.white : MobileStyle.accent)
                .modifier(controlOrientation)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(T("Flash", "闪光灯", "閃光燈"))
        .accessibilityValue(flashTitle(flash))
        .accessibilityIdentifier("camera.flash")
        .disabled(!ready || (configuration?.flashModes.count ?? 0) < 2)
    }

    private func flashTitle(_ mode: AVCaptureDevice.FlashMode) -> String {
        switch mode {
        case .off: T("Off", "关闭", "關閉")
        case .auto: T("Auto", "自动", "自動")
        case .on: T("On", "开启", "開啟")
        @unknown default: T("Flash", "闪光灯", "閃光燈")
        }
    }

    private func selectLens(_ option: MobileCameraLens) {
        guard ready, lens != option else { return }
        switchCamera(to: option, portrait: portraitMode, changesInput: lens.physicalLens != option.physicalLens)
    }

    private func switchCamera(to option: MobileCameraLens, portrait: Bool, changesInput: Bool) {
#if SILVERPHASE_APP
        // Capture the composed, processed image synchronously before switch
        // state or task cancellation can hide/replace it. Includes portrait.
        let displayedFrame = showsFilmPreview && !lookUnavailable ? lookFrame?.snapshot(for: captureRecipe) : nil
        let oldGeneration = camera.lookFrames.currentGeneration()
#endif
        switching = true
        focusPoint = nil
        focusLocked = false
        Task {
            if changesInput {
#if SILVERPHASE_APP
                let frozen: CGImage?
                if let displayedFrame { frozen = displayedFrame }
                else { frozen = await camera.freezePreview() }
#else
                let frozen = await camera.freezePreview()
#endif
                guard let frame = frozen else {
                    switching = false
                    failure = T("The viewfinder is not ready yet. Try switching lenses again.", "取景画面尚未准备好，请重试切换镜头。", "取景畫面尚未準備好，請重試切換鏡頭。")
                    return
                }
                guard canRunCamera, configuration != nil else { switching = false; return }
                switchFrame = frame
#if SILVERPHASE_APP
                frozenSwitchGeneration = oldGeneration
#endif
                // Publish the frozen image before disconnecting the live layer.
                try? await Task.sleep(for: .milliseconds(40))
                guard canRunCamera, configuration != nil else { switching = false; return }
                camera.detachPreview()
                previewing = false
                changingPhysicalLens = true
            }
            lens = option
            if option != .front { rearLens = option }
            portraitMode = portrait
            retry += 1
        }
    }

    private var focusIndicator: some View {
        let orientation = controlOrientation
        let swapsAxes = abs(controlRotation.remainder(dividingBy: 180)) == 90
        return GeometryReader { geometry in
            let size = geometry.size
            Color.clear.keyframeAnimator(initialValue: CGFloat(1), trigger: focusFeedbackID) { content, scale in
                content.overlay {
                    if let focusPoint {
                        let horizontalInset: CGFloat = swapsAxes ? 60 : 56
                        let verticalInset: CGFloat = swapsAxes ? 56 : 60
                        let insetX = min(horizontalInset, size.width / 2)
                        let insetY = min(verticalInset, size.height / 2)
                        ZStack(alignment: .top) {
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(MobileStyle.accent, lineWidth: 1.5)
                                .frame(width: 56, height: 56)
                                .overlay(alignment: .trailing) {
                                    if !focusLocked, let range = configuration?.exposureRange {
                                        let travel = exposure >= 0 ? range.upperBound : -range.lowerBound
                                        let offset = travel > 0 ? -CGFloat(exposure / travel) * 22 : 0
                                        ZStack {
                                            if draggingExposure {
                                                Capsule().fill(.white.opacity(0.5)).frame(width: 1, height: 44)
                                            }
                                            Image(systemName: "sun.max.fill")
                                                .font(.caption)
                                                .offset(y: offset)
                                        }
                                        .offset(x: 18)
                                    }
                                }
                            if focusLocked {
                                Label(T("AE/AF lock", "自动曝光／自动对焦锁定", "自動曝光／自動對焦鎖定"), systemImage: "lock.fill")
                                    .font(.caption2.weight(.semibold))
                                    .fixedSize()
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(.black.opacity(0.60), in: Capsule())
                                    .offset(y: -24)
                                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                            } else if draggingExposure {
                                Text(exposure.formatted(.number.sign(strategy: .always(includingZero: false))
                                    .precision(.fractionLength(1))) + " EV")
                                    .font(.caption2.weight(.semibold))
                                    .modifier(AdjustmentNumberTransition(value: Double(exposure), fractionDigits: 1))
                                    .fixedSize()
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(.black.opacity(0.60), in: Capsule())
                                    .offset(y: -24)
                                    .transition(.opacity)
                            }
                        }
                        .foregroundStyle(MobileStyle.accent)
                        .scaleEffect(reduceMotion ? 1 : scale)
                        .modifier(orientation)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: focusLocked)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: draggingExposure)
                        .position(x: min(max(focusPoint.x * size.width, insetX), size.width - insetX),
                                  y: min(max(focusPoint.y * size.height, insetY), size.height - insetY))
                    }
                }
            } keyframes: { _ in
                MoveKeyframe(1.28)
                SpringKeyframe(1, duration: 0.24)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func focus(at point: CGPoint, devicePoint: CGPoint, lock: Bool) {
        guard ready else { return }
        focusPoint = point
        focusLocked = lock
        focusFeedbackID += 1
        camera.focus(at: devicePoint, lens: lens, lock: lock)
    }

    private func dragExposure(_ movement: CGFloat?) {
        guard let movement else {
            draggingExposure = false
            return
        }
        guard ready, focusPoint != nil, let range = configuration?.exposureRange else { return }
        draggingExposure = true
        let value = min(max(exposure - Float(movement) / 90, range.lowerBound), range.upperBound)
        guard value != exposure else { return }
        exposure = value
        camera.updateExposure(value, lens: lens)
    }

    private func retryCamera() {
#if !SILVERPHASE_APP
        sessionInterrupted = false
        contentionRecoveryPending = false
#endif
        stopCamera()
        retry += 1
    }

#if !SILVERPHASE_APP
    private func recoverLockedCameraOnce() -> Bool {
        guard !hasShownPreview, !attemptedStartupRecovery else { return false }
        attemptedStartupRecovery = true
        retryCamera()
        return true
    }
#endif

    private func startCamera() async {
        issue = nil
        defer {
            if !Task.isCancelled {
                switching = false
                changingPhysicalLens = false
            }
        }
        let authorized: Bool
#if SILVERPHASE_APP
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: authorized = true
        case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
        default: authorized = false
        }
#else
        Logger(subsystem: "com.silverphase.editor", category: "LockedCamera")
            .notice("Starting camera, attempt \(retry)")
        authorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
#endif
        guard !Task.isCancelled, canRunCamera else { return }
        guard authorized else {
            configuration = nil
            issue = T("Allow Silverphase to use the camera in System Settings.", "请在系统设置中允许 Silverphase 使用相机。", "請在系統設定中允許 Silverphase 使用相機。")
            return
        }
        do {
            let available = try await camera.start(lens: lens, exposure: exposure, portrait: portraitMode)
            guard !Task.isCancelled, canRunCamera else { return }
            configuration = available
            exposure = available.exposure
            if !available.flashModes.contains(flash) { flash = .off }
#if !SILVERPHASE_APP
            if previewing, !sessionInterrupted { issue = nil }
            Logger(subsystem: "com.silverphase.editor", category: "LockedCamera")
                .notice("Capture configuration ready")
#endif
        } catch {
            guard !Task.isCancelled, canRunCamera else { return }
#if SILVERPHASE_APP
            switchFrame = nil
#endif
#if !SILVERPHASE_APP
            let cameraError = error as NSError
            Logger(subsystem: "com.silverphase.editor", category: "LockedCamera")
                .notice("Capture start error: \(cameraError.domain, privacy: .public) \(cameraError.code)")
            if camera.session.isInterrupted || sessionInterrupted {
                sessionInterrupted = true
                return
            }
            if !camera.session.isRunning, recoverLockedCameraOnce() { return }
#endif
            if portraitMode {
                portraitMode = false
                failure = error.localizedDescription
                retry += 1
                return
            }
            configuration = nil
            issue = error.localizedDescription
        }
    }

    private func stopCamera() {
        measuredCapturePose = nil
#if SILVERPHASE_APP
        if !isLayoutCheck { MobileCameraLocation.shared.setCameraActive(false, enabled: recordsLocation) }
        lookEngine.workGate.setActive(false)
        lookFrame = nil
        fastLookEngine.workGate.setActive(false)
        let renderer = lookEngine, fastRenderer = fastLookEngine
        Task { await renderer.close(); await fastRenderer.close() }
#endif
        focusPoint = nil
        focusLocked = false
        switchFrame = nil
#if SILVERPHASE_APP
        camera.detachPreview()
#else
        lockedDevelopment = nil
#endif
        configuration = nil
        previewing = false
        camera.stop()
    }

#if SILVERPHASE_APP
    private func landReveal() {
        guard reveal != nil, !landingPhoto else { return }
        if reduceMotion { finishReveal() }
        else if savingToPhotos {
            // The print is developed but Photos is still writing. Hold the
            // finished frame instead of dropping a save spinner over it; the
            // shot lands in the strip as soon as the save returns.
            holdLanding = true
        } else {
            landingPhoto = true
        }
    }

    /// Suspends until the app is active again. Used after backgrounding
    /// cancelled a camera save, so the retry runs in the foreground rather
    /// than submitting Metal work while backgrounded.
    private func waitForForeground() async {
        final class Once: @unchecked Sendable {
            private let lock = NSLock(); private var done = false
            func run(_ body: () -> Void) { lock.lock(); defer { lock.unlock() }; guard !done else { return }; done = true; body() }
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = Once()
            var observer: NSObjectProtocol?
            observer = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { _ in
                if let observer { NotificationCenter.default.removeObserver(observer) }
                once.run { continuation.resume() }
            }
            if UIApplication.shared.applicationState == .active {
                if let observer { NotificationCenter.default.removeObserver(observer) }
                once.run { continuation.resume() }
            }
        }
    }

    private func finishReveal() {
        reveal = nil
        landingPhoto = false
        photoAtThumbnail = false
        holdLanding = false
    }

#endif
    private func takePhoto() {
        guard ready else { return }
#if SILVERPHASE_APP
        let selectedFilm = film
        shotQuarterTurn = deviceQuarterTurn
        frozenShot = showsFilmPreview && !lookUnavailable ? lookFrame?.snapshot(for: captureRecipe) : nil
#else
        lockedDevelopment = nil
#endif
#if SILVERPHASE_APP
        let selectedLocation = MobileCameraLocation.shared.snapshot(enabled: recordsLocation)
#else
        let selectedLocation: MobileCaptureLocation? = nil
#endif
#if DEBUG && SILVERPHASE_APP
        let exposureFrame = camera.lookFrames.latest()
        let exposureGeometry = camera.lookGeometry()
        let shutterUptime = ProcessInfo.processInfo.systemUptime
#endif
        let selectedRecipe = captureRecipe
        // No motion sample (including denied/unavailable motion) must not be
        // mistaken for a measured portrait pose. Retain the native coordinator
        // fallback until a physical orientation has actually been observed.
        let selectedPose = measuredCapturePose
        let selectedFlash = flash
        let usesDepth = portraitMode
        let mirrored = lens == .front && mirrorsFrontCamera
        capturing = true
        Task {
#if !SILVERPHASE_APP
            var writingCapture = false
            let finderFrame = reduceMotion ? nil : await camera.snapshotPreview()
#else
            // Freeze the frame the user composed before capture stops delivering
            // preview frames; it stays on screen until the shot is developed and
            // saved.
            if frozenShot == nil { frozenShot = await camera.freezePreview() }
#endif
            defer {
                capturing = false
#if SILVERPHASE_APP
                developing = false
                savingToPhotos = false
                frozenShot = nil
#endif
            }
            do {
                let (data, format) = try await camera.capture(flash: selectedFlash, portrait: usesDepth,
                                                              mirrored: mirrored, pose: selectedPose, location: selectedLocation)
#if DEBUG && SILVERPHASE_APP
                if selectedRecipe.metering == .custom, selectedFlash == .off, !usesDepth,
                   format == .proRAW || format == .bayer, let exposureFrame {
                    Task.detached(priority: .utility) {
                        MobileCameraExposureProbe.record(rawData: data, frame: exposureFrame,
                            angle: exposureGeometry.angle, mirrored: exposureGeometry.mirrored,
                            shutterUptime: shutterUptime, recipe: selectedRecipe)
                    }
                }
#endif
                var warnings: [String] = []
                let portraitImage = usesDepth ? await Task.detached(priority: .userInitiated) {
                    MobilePortraitCapture.render(data, format: format)
                }.value : nil
                if usesDepth && portraitImage == nil {
                    warnings.append(T("Portrait blur could not be applied this time; the camera's original was kept.", "本次未能应用人像虚化，已保留相机原片。", "本次未能應用人像虛化，已保留相機原片。"))
                }
                let imageData = portraitImage ?? data
#if SILVERPHASE_APP
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Silverphase-" + UUID().uuidString)
                    .appendingPathExtension(format.fileExtension)
                defer { try? FileManager.default.removeItem(at: url) }
                try await Task.detached(priority: .userInitiated) { try imageData.write(to: url, options: .atomic) }.value
                developing = true
                capturing = false
                let photo = try await importPhoto(url, selectedFilm, selectedRecipe)
                latestPhotoID = photo.id
                latestPreview = nil
                do {
                    let result = try await developPhoto(photo, !reduceMotion)
                    latestPreview = result.image
                    if !reduceMotion, scenePhase == .active {
                        revealOpacity = 0
                        reveal = result
                    }
                } catch {
                    warnings.append(T("The development preview failed: \(error.localizedDescription)", "显影预览生成失败：\(error.localizedDescription)", "顯影預覽生成失敗：\(error.localizedDescription)"))
                }
                developing = false
                savingToPhotos = true
                do {
                    try await savePhoto(photo)
                } catch is CancellationError {
                    // Backgrounding cancelled the export engine. The original is
                    // already in the local library; defer the Photos save to the
                    // next foreground activation instead of losing it.
                    await waitForForeground()
                    do { try await savePhoto(photo) } catch { warnings.append(T("Could not save to Photos: \(error.localizedDescription)", "未能存到系统相册：\(error.localizedDescription)", "未能存到系統相簿：\(error.localizedDescription)")) }
                } catch {
                    warnings.append(T("Could not save to Photos: \(error.localizedDescription)", "未能存到系统相册：\(error.localizedDescription)", "未能存到系統相簿：\(error.localizedDescription)"))
                }
                if !warnings.isEmpty {
                    failure = ([T("The original is saved in Silverphase.", "原片已保存在 Silverphase。", "原片已儲存在 Silverphase。")] + warnings).joined(separator: "\n")
                }
#else
                writingCapture = true
                try await storeCapture(imageData, format, selectedRecipe)
                Logger(subsystem: "com.silverphase.editor", category: "LockedCamera")
                    .notice("Original persisted: \(imageData.count) bytes")
                if let finderFrame, !reduceMotion {
                    lockedDevelopment = await makeLockedDevelopment(finderFrame)
                }
                if !warnings.isEmpty { failure = warnings.joined(separator: "\n") }
#endif
            } catch {
#if !SILVERPHASE_APP
                let cameraError = error as NSError
                Logger(subsystem: "com.silverphase.editor", category: "LockedCamera")
                    .notice("Shot failed while writing: \(writingCapture), error: \(cameraError.domain, privacy: .public) \(cameraError.code)")
                let action = writingCapture ? T("Saving the original failed", "保存原片失败", "儲存原片失敗") : T("Capture failed", "拍摄失败", "拍攝失敗")
                failure = "\(action)：\(error.localizedDescription)"
#else
                failure = error.localizedDescription
#endif
            }
        }
    }

#if !SILVERPHASE_APP
    private func makeLockedDevelopment(_ frame: CIImage) async -> MobileDevelopmentAssets? {
        await Task.detached(priority: .userInitiated) {
            let scale = min(1, 1280 / max(frame.extent.width, frame.extent.height))
            let image = frame.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let context = CIContext(options: [.cacheIntermediates: false])
            guard let photo = context.createCGImage(image, from: image.extent) else { return nil }
            do { return try MobileDevelopmentAssets(photo: photo) }
            catch {
                let code = (error as NSError).code
                Logger(subsystem: "com.silverphase.editor", category: "LockedCamera")
                    .notice("Development presentation unavailable: \(code)")
                return nil
            }
        }.value
    }
#endif
}

// A screw-in optical filter: the outer ring surrounds the glass and its reflections.
private struct CameraDiffusionFilterGlyph: View {
    var body: some View {
        ZStack {
            Circle().strokeBorder(lineWidth: 1.5)
            Circle().strokeBorder(lineWidth: 1).padding(3)
            Path { path in
                path.move(to: CGPoint(x: 7, y: 13))
                path.addLine(to: CGPoint(x: 13, y: 7))
                path.move(to: CGPoint(x: 11, y: 16))
                path.addLine(to: CGPoint(x: 16, y: 11))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
        .frame(width: 23, height: 23)
        .accessibilityHidden(true)
    }
}

private struct CameraControlOrientation: ViewModifier {
    let rotation: Double
    let animated: Bool
    var anchor: UnitPoint = .center

    func body(content: Content) -> some View {
        content.rotationEffect(.degrees(rotation), anchor: anchor)
            .animation(animated ? .easeInOut(duration: 0.22) : nil, value: rotation)
    }
}

private enum MobilePortraitCapture {
    static func render(_ data: Data, format: MobileCaptureFormat) -> Data? {
        autoreleasepool {
            let context = CIContext()
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let input = CIImage(data: data),
                  let image = context.depthBlurEffectFilter(forImageData: data, options: nil)?.outputImage,
                  let space = input.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
                  let rendered = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: space)
            else { return nil }
            var properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
            if let orientation = image.properties[kCGImagePropertyOrientation as String] {
                properties[kCGImagePropertyOrientation as String] = orientation
            }
            properties[kCGImageDestinationLossyCompressionQuality as String] = 0.96
            let bytes = NSMutableData()
            let type = format == .heic ? UTType.heic : UTType.jpeg
            guard let destination = CGImageDestinationCreateWithData(bytes, type.identifier as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(destination, rendered, properties as CFDictionary)
            return CGImageDestinationFinalize(destination) ? bytes as Data : nil
        }
    }
}
