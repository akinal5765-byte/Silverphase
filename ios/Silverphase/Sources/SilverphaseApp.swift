import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ImageIO
import PhotosUI

@main struct SilverphaseMobileApp: App {
    @State private var document: MobileDocument = {
        let document = MobileDocument()
        document.editorVisible = ProcessInfo.processInfo.arguments.contains { !$0.hasPrefix("--library") && $0.hasPrefix("--") && ($0.contains("regression") || $0.contains("audit") || $0 == "--smoke-test") }
        return document
    }()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            Group {
                if document.editorVisible && ProcessInfo.processInfo.arguments.contains(where: { !$0.hasPrefix("--library") && $0.hasPrefix("--") && ($0.contains("regression") || $0.contains("audit") || $0 == "--smoke-test") }) {
                    MobileEditor(document: document)
                } else { MobileLibrary(document: document) }
            }
                .preferredColorScheme(.dark)
                .tint(.primary)
                .task {
#if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--compact-editor-ui-regression") {
                        MobileSmokeChecks.prepareCompactPhoneUI(document)
                    } else if ProcessInfo.processInfo.arguments.contains("--library-regression") {
                        MobileLibraryChecks.run()
                        await MobileLibraryChecks.exportBatch()
                    } else if ProcessInfo.processInfo.arguments.contains("--library-ui-regression") {
                        MobileLibraryChecks.prepareUI(document)
                    } else if ProcessInfo.processInfo.arguments.contains("--ipad-chrome-regression") {
                        MobileSmokeChecks.prepareIPadChromeUI(document)
                    } else if ProcessInfo.processInfo.arguments.contains("--clipboard-ui-regression") {
                        MobileSmokeChecks.prepareClipboardUI(document)
                    } else if ProcessInfo.processInfo.arguments.contains("--clipboard-regression") {
                        MobileSmokeChecks.clipboardRegression()
                    } else if ProcessInfo.processInfo.arguments.contains("--interaction-ui-regression") {
                        UIApplication.shared.isIdleTimerDisabled = true
                        document.importFiles([URL.documentsDirectory.appendingPathComponent("DeviceAuditInput.ARW")])
                    } else if ProcessInfo.processInfo.arguments.contains("--device-audit") {
                        await MobileDeviceAudit.run(document: document)
                    } else if ProcessInfo.processInfo.arguments.contains("--clear-flat-import-regression") {
                        let report = URL.documentsDirectory.appendingPathComponent("flat-import-report.json")
                        do {
                            if FileManager.default.fileExists(atPath: report.path) { try FileManager.default.removeItem(at: report) }
                        } catch { document.error = error.localizedDescription }
                    } else if ProcessInfo.processInfo.arguments.contains("--flat-import-regression") {
                        await MobileSmokeChecks.flatImportRegression()
                    } else if ProcessInfo.processInfo.arguments.contains("--raw-import-regression") {
                        await MobileSmokeChecks.rawImportRegression()
                    } else if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
                        do { document.importFiles([try await MobileSmokeChecks.run()]) }
                        catch { document.error = error.localizedDescription }
                    }
#endif
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in document.releaseMemory() }
                .onChange(of: scenePhase) { _, phase in
#if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--ipad-chrome-regression") || ProcessInfo.processInfo.arguments.contains("--compact-editor-ui-regression") { return }
#endif
                    document.setActive(phase == .active, background: phase == .background)
                }
        }
    }
}

enum MobileStyle {
    // Current desktop Theme tokens, kept explicit until Theme's AppKit types
    // can be isolated. Layout follows EditorWindow.modernLayout, not legacy rails.
    static let accent = Color(uiColor: .systemOrange)
    static let canvas = Color(white: 48.0 / 255)
    static let gutter: CGFloat = 8
    static let panel: CGFloat = 288
    static let radius: CGFloat = 16
    static let row: CGFloat = EditorDesign.hitSize
    static let surface = Color(white: 0.065)
    static let well = Color.white.opacity(0.09)
    static let rule = Color.white.opacity(0.09)
    static let muted = Color.white.opacity(0.28)
}

enum MobileStage: String, CaseIterable, Identifiable {
    case camera = "相机", film = "胶片", development = "显影", print = "印相", output = "扫描", geometry = "构图", filmEdge = "片边"
    var id: String {
        switch self {
        case .camera: "camera"
        case .film: "film"
        case .development: "development"
        case .print: "print"
        case .output: "output"
        case .geometry: "geometry"
        case .filmEdge: "filmEdge"
        }
    }
    var symbol: String {
        switch self {
        case .camera: "camera.aperture"
        case .film: "film"
        case .development: "drop.fill"
        case .print: "photo.on.rectangle.angled"
        case .output: "scanner"
        case .geometry: "aspectratio"
        case .filmEdge: "rectangle.dashed"
        }
    }
}

struct MobileEditor: View {
    @Bindable var document: MobileDocument
    var batchIDs: [UUID]? = nil
    var returnToLibrary: (@MainActor @Sendable () -> Void)? = nil
    @State private var batchCopyRequest: MobileSettingsCopyRequest?
    private var showsPhotoStrip: Bool { returnToLibrary == nil || batchIDs != nil }
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var minimumRating = 0
    @State private var flagFilter = "all"
    @State private var overlays = MobileOverlays()
    @State private var stage = MobileStage.camera
    @State private var inspector = true
    @State private var materials = false
    @State private var importing = false
    @State private var pickingPhotos = false
    @State private var exporting = false
    @State private var about = false
    @State private var settings = false
    @State private var format = MobileExportFormat.jpeg
    @State private var dockFraction = 0.42
    @State private var systemBarFrame: CGRect?
    @State private var returnButtonFrame = CGRect.zero
    @State private var iPadSafeInsets = EdgeInsets()
    @State private var panelDragStart: Double?
    @GestureState private var panelDragging = false
    @State private var phoneHingeClosed: Bool?
    @State private var phonePostureKnown = false
    @State private var phoneWindowSize = CGSize.zero
    private var compactPhoneEditor: Bool {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }
        if #available(iOS 27.1, *) {
            guard phonePostureKnown else { return false }
            if let phoneHingeClosed {
                return !phoneHingeClosed && phoneWindowSize.height > phoneWindowSize.width
            }
            return true
        }
        return true
    }

    private var verticalSystemBar: Bool {
        guard systemProcessToolbar, let frame = systemBarFrame else { return false }
        return frame.height > frame.width
    }

    private var usesIPadToolbar: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private var systemProcessToolbar: Bool {
        if #available(iOS 27.1, *) { UIDevice.current.userInterfaceIdiom == .phone }
        else { false }
    }
    var body: some View {
        NavigationStack {
            Group {
            if compactPhoneEditor { compactWorkspace }
            else {
            ProcessNavigation(document: document, stage: $stage, inspector: $inspector,
                              materials: $materials, exporting: $exporting, enabled: systemProcessToolbar) {
            GeometryReader { geometry in
                let plan = WorkspaceLayout(size: geometry.size, safe: usesIPadToolbar ? iPadSafeInsets : EdgeInsets(),
                                           exclusions: workspaceExclusions(geometry),
                                           showsMedia: materials || (showsPhotoStrip && !document.photos.isEmpty),
                                           systemBars: systemProcessToolbar,
                                           systemBarFrame: verticalSystemBar ? systemBarFrame?.offsetBy(dx: -geometry.frame(in: .global).minX, dy: -geometry.frame(in: .global).minY) : nil,
                                           showInspector: inspector && document.current != nil,
                                           materialBrowser: materials, dockFraction: dockFraction)
                let showsPanel = inspector && document.current != nil
                ZStack(alignment: .topLeading) {
                    if stage == .geometry, let source = document.cropSourceImage, let photo = document.current {
                        MobileCropCanvas(image: source, geometry: photo.geometry.value, sourceSize: document.geometrySourceSize,
                                         insets: plan.imageInsets(showInspector: showsPanel), commit: document.setGeometry)
                            .id(document.selection)
                    } else {
                    PhotoCanvas(canvas: document.canvasState, image: document.neutralPreview ?? (document.showOriginal ? document.original : document.image),
                                fitInsets: plan.imageInsets(showInspector: showsPanel),
                                detail: document.pickingNeutral ? nil : (document.showOriginal ? document.originalDetailTile : document.detailTile),
                                onViewport: document.requestDetail,
                                onOriginalViewport: document.requestOriginalDetail,
                                nativeSize: document.showOriginal ? document.originalNativeOutputSize : document.nativeOutputSize,
                                zoomRequest: document.canvasZoomRequest, wantsNative: document.canvasWantsNative,
                                comparison: document.showOriginal, onCompare: document.compareCanvas,
                                development: document.development, developmentRunning: document.developmentRunning,
                                onPrintNegative: document.printNegative, onDevelopmentFinished: document.finishDevelopment,
                                onNeutral: document.pickingNeutral ? { document.pickNeutral($0) } : nil)
                        .id(document.selection)
                    }
                    if document.current == nil {
                        emptyEditor.frame(width: geometry.size.width, height: geometry.size.height)
                    }
                    if !systemProcessToolbar {
                    editorBar(twoRows: plan.usesTwoNavigationRows, sideStages: systemProcessToolbar)
                        .padding(.leading, plan.navigationContent.minX)
                        .padding(.trailing, geometry.size.width - plan.navigationContent.maxX)
                        .frame(width: plan.navigation.width, height: plan.navigation.height)
                        .modifier(ChromeSurface(topBar: true))
                        .position(x: plan.navigation.midX, y: plan.navigation.midY)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("editor.primary-navigation")
                    }
                    if showsPanel {
                        processPanel(side: plan.usesSidebar)
                            .frame(width: plan.inspector.width, height: plan.inspector.height)
                            .modifier(ChromeSurface())
                            .auditEditorBounds("panel.inspector")
                            .position(x: plan.inspector.midX, y: plan.inspector.midY)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("editor.parameters")
                            .transition(.move(edge: plan.usesSidebar ? .trailing : .bottom).combined(with: .opacity))
                    }
                    if plan.media.height > 0 {
                        Group {
                            if materials { MaterialChooser(document: document, startsWithPaper: stage == .print) }
                            else { filmstrip }
                        }
                        .frame(width: plan.media.width, height: plan.media.height)
                        .modifier(ChromeSurface())
                        .auditEditorBounds("panel.browser")
                        .position(x: plan.media.midX, y: plan.media.midY)
                    }
                    if document.current != nil {
                        let infoLeft = plan.photoInsets.leading + EditorDesign.contentInset
                        let infoWidth = max(1, geometry.size.width - plan.imageInsets(showInspector: showsPanel).trailing - EditorDesign.contentInset - infoLeft)
                        canvasStatus
                        .frame(width: infoWidth, alignment: .leading)
                        .position(x: infoLeft + infoWidth / 2,
                                  y: statusCenterY(in: geometry, defaultY: plan.navigation.maxY + EditorDesign.canvasInfoInset))
                        .accessibilityElement(children: .combine).accessibilityIdentifier("editor.photo-info")
                        .allowsHitTesting(false)
                    }
                }
                .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: inspector)
                .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: materials)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: stage)
                .modifier(WorkspaceGlassGroup())
                .modifier(WorkspaceViewportClip(roundedHeader: usesIPadToolbar))
            }
            .background {
                if usesIPadToolbar {
                    WindowSafeAreaProbe { iPadSafeInsets = $0 }.allowsHitTesting(false)
                }
            }
            .ignoresSafeArea(.container, edges: usesIPadToolbar ? [.top, .bottom] : verticalSystemBar ? [.top, .trailing, .bottom] : [])
            .auditEditorBounds("viewport")
            .auditEditorBounds("safeViewport")
            .background(MobileStyle.canvas.ignoresSafeArea())
            }
            .modifier(ProcessToolbar(document: document, inspector: $inspector,
                                     materials: $materials, exporting: $exporting, about: $about, settings: $settings,
                                     importing: $importing, pickingPhotos: $pickingPhotos, enabled: systemProcessToolbar))
            }
            }
            .background {
                if UIDevice.current.userInterfaceIdiom == .phone {
                    ProcessBarGeometryProbe(update: { frame in
                        systemBarFrame = frame
                    }, windowSizeChanged: { size in
                        phoneWindowSize = size
                    }, hingeChanged: { closed in
                        phoneHingeClosed = closed
                        phonePostureKnown = true
                    }, returnFrameChanged: { returnButtonFrame = $0 })
                    .allowsHitTesting(false)
                }
            }
            .environment(\.returnToLibrary, returnToLibrary)
            .sheet(item: $batchCopyRequest) { request in
                MobileCopySettingsSheet(document: document, request: request, applyIDs: Set(batchIDs ?? []))
            }
            .environment(overlays)
            .overlay { ChoiceOverlay(overlays: overlays) }
            .sheet(isPresented: $pickingPhotos) {
                LibraryPhotoPicker(isPresented: $pickingPhotos,
                                   onStart: { document.beginPhotoImport(total: $0) },
                                   onProgress: { document.photoImportProgress(index: $0, total: $1, name: $2) }) { files, skipped, errors in
                    Task {
                        if !files.isEmpty {
                            let names = Dictionary(uniqueKeysWithValues: files.map { ($0.url, $0.name) })
                            await document.importFiles(files.map(\.url), displayNames: names, removeSourcesAfterImport: true, continuingPhotoSelection: true).value
                        } else { document.finishPhotoImportWithoutFiles() }
                        if skipped > 0 { document.postNotification("已跳过 \(skipped) 张不支持或无法读取的照片", style: .warning) }
                        if !errors.isEmpty { document.error = errors.joined(separator: "\n") }
                    }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .rawImage], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): document.importFiles(urls)
                case .failure(let error): document.error = error.localizedDescription
                }
            }
            .sheet(isPresented: Binding(get: { document.exported != nil }, set: { if !$0 { document.clearExport() } })) {
                if let url = document.exported { ActivitySheet(urls: document.exportedFiles.isEmpty ? [url] : document.exportedFiles) }
            }
            .sheet(isPresented: $about) { MobileAbout() }
            .sheet(isPresented: $settings) { MobileSettingsView(document: document) }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in document.schedule() }
            .onChange(of: document.preferences.values) { _, _ in document.schedule() }
            .onChange(of: stage) { _, stage in document.cropEditing = stage == .geometry }
            .onChange(of: document.selection) { _, id in if id == nil { returnToLibrary?() } }
            .onAppear {
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--show-parameters") { inspector = true }
                if ProcessInfo.processInfo.arguments.contains("--show-materials") { materials = true; inspector = true; stage = .film }
#endif
            }
        }
        .onChange(of: document.isInteractionLocked) { _, locked in
            if locked {
                overlays.choice = nil
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
        .disabled(document.isInteractionLocked)
        .accessibilityHidden(document.isInteractionLocked)
        .allowsHitTesting(!document.isInteractionLocked)
        .overlay {
            MobileNotificationCenter(notification: document.currentNotification,
                                     excludedFrame: verticalSystemBar ? systemBarFrame : nil,
                                     isCovered: document.exported != nil || pickingPhotos || importing || settings || about,
                                     dismiss: document.dismissNotification)
        }
    }

    private func statusCenterY(in geometry: GeometryProxy, defaultY: CGFloat) -> CGFloat {
        guard returnToLibrary != nil else { return defaultY }
        let reservedRowBottom = geometry.safeAreaInsets.top + EditorDesign.hitSize + 2 * EditorDesign.gutter
        let buttonBottom = returnButtonFrame.isEmpty ? reservedRowBottom : returnButtonFrame.maxY - geometry.frame(in: .global).minY
        // Reserve a complete toolbar row even before UIKit publishes its control frame.
        return max(defaultY, max(reservedRowBottom, buttonBottom) + EditorDesign.canvasInfoInset)
    }

    private var canvasStatus: some View {
        Text(canvasStatusText).font(.system(size: 11)).lineLimit(1)
            .foregroundStyle(document.busy ? MobileStyle.accent : .white.opacity(0.75))
    }
    private var canvasStatusText: String {
        if document.busy { return "处理中…" }
        if document.showOriginal && document.originalDetailBusy { return "载入原图细节…" }
        if document.showOriginal && document.originalDetailTile?.nativeSize != nil { return "原图 · 原始像素" }
        if document.development != nil { return document.developmentRunning ? "显影中…" : "轻点照片开始印相" }
        if document.detailBusy { return "载入细节…" }
        if !document.previewStatus.isEmpty { return document.previewStatus }
        if let tile = document.detailTile, !document.showOriginal, !document.pickingNeutral {
            return tile.nativeSize != nil ? "原始像素" : "细节预览"
        }
        return document.image != nil ? "适屏预览" : "等待照片"
    }

    private var compactWorkspace: some View {
        GeometryReader { geometry in
            let photos = showsPhotoStrip && document.photos.count > 1
            let plan = CompactPhoneLayout(size: geometry.size, fraction: dockFraction, showsPhotos: photos)
            ZStack(alignment: .topLeading) {
                if stage == .geometry, let source = document.cropSourceImage, let photo = document.current {
                    MobileCropCanvas(image: source, geometry: photo.geometry.value, sourceSize: document.geometrySourceSize,
                                     insets: EdgeInsets(), commit: document.setGeometry).id(document.selection)
                        .ignoresSafeArea(.container, edges: [.top, .bottom])
                } else {
                    PhotoCanvas(canvas: document.canvasState,
                                image: document.neutralPreview ?? (document.showOriginal ? document.original : document.image),
                                detail: document.pickingNeutral ? nil : (document.showOriginal ? document.originalDetailTile : document.detailTile),
                                onViewport: document.requestDetail, onOriginalViewport: document.requestOriginalDetail,
                                nativeSize: document.showOriginal ? document.originalNativeOutputSize : document.nativeOutputSize,
                                zoomRequest: document.canvasZoomRequest, wantsNative: document.canvasWantsNative,
                                comparison: document.showOriginal, onCompare: document.compareCanvas,
                                development: document.development, developmentRunning: document.developmentRunning,
                                onPrintNegative: document.printNegative, onDevelopmentFinished: document.finishDevelopment,
                                onNeutral: document.pickingNeutral ? { document.pickNeutral($0) } : nil)
                        .id(document.selection)
                        .ignoresSafeArea(.container, edges: [.top, .bottom])
                }
                if document.current == nil { emptyEditor.frame(maxWidth: .infinity, maxHeight: .infinity) }
                if document.current != nil {
                    let left = EditorDesign.contentInset
                    let width = max(1, geometry.size.width - left - EditorDesign.contentInset)
                    canvasStatus.frame(width: width, alignment: .leading)
                        .position(x: left + width / 2, y: statusCenterY(in: geometry, defaultY: EditorDesign.canvasInfoInset))
                        .accessibilityElement(children: .combine).accessibilityIdentifier("editor.photo-info")
                        .allowsHitTesting(false)
                }
                if inspector, document.current != nil {
                    processPanel(side: false, heightBasis: geometry.size.height)
                        .frame(width: plan.inspector.width, height: plan.inspector.height)
                        .modifier(ChromeSurface(radius: 24))
                        .position(x: plan.inspector.midX, y: plan.inspector.midY)
                        .accessibilityElement(children: .contain).accessibilityIdentifier("editor.parameters")
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if photos {
                    filmstrip.frame(width: plan.media.width, height: plan.media.height).modifier(ChromeSurface())
                        .position(x: plan.media.midX, y: plan.media.midY)
                }
                CompactProcessTabs(stage: stage, enabled: document.current != nil && !document.delivering) { item in
                    document.endParameterInteraction()
                    stage = item; inspector = true; exporting = false
                    materials = item == .film || item == .print
                }
                .frame(width: plan.tabs.width, height: plan.tabs.height)
                .position(x: plan.tabs.midX, y: plan.tabs.midY)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: inspector)
            .background(MobileStyle.canvas.ignoresSafeArea())
        }
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if let returnToLibrary {
                    Button("返回", systemImage: "chevron.left") { returnToLibrary() }.accessibilityIdentifier("editor.library")
                }
            }.compactHorizontalAxis()
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("导出", systemImage: "square.and.arrow.up") {
                    exporting = true; inspector = true; materials = false
                }.disabled(document.current == nil || document.delivering).accessibilityIdentifier("editor.export")
                NativeEditorMenu(document: document, inspector: $inspector, materials: $materials,
                                 exporting: $exporting, about: $about, settings: $settings,
                                 importing: $importing, pickingPhotos: $pickingPhotos)
            }.compactHorizontalAxis()
        }
    }

    private func editorBar(twoRows: Bool, sideStages: Bool) -> some View {
        Group {
            if sideStages {
                HStack(spacing: 0) { fileActions; Spacer(minLength: 8); viewActions }.frame(height: 44)
            } else if twoRows {
                VStack(spacing: 4) {
                    HStack(spacing: 0) {
                        fileActions
                        Spacer(minLength: 4)
                        viewActions
                    }.frame(height: 44)
                    ScrollView(.horizontal, showsIndicators: false) { stageNavigation(expands: false) }.frame(height: 44).clipped()
                }
            } else {
                HStack(spacing: 4) {
                    fileActions
                    Rectangle().fill(MobileStyle.rule).frame(width: 1, height: 20)
                    stageNavigation(expands: false)
                    Spacer(minLength: 0)
                    viewActions
                }
            }
        }.padding(.horizontal, 8)
    }
    private var fileActions: some View {
        HStack(spacing: 0) {
            if let returnToLibrary {
                ChromeButton(title: "返回", symbol: "chevron.left") { returnToLibrary() }.accessibilityIdentifier("editor.library")
            }
            if returnToLibrary == nil {
                ChromeButton(title: "打开照片", symbol: "plus") { openImport() }.accessibilityIdentifier("import.menu")
                    .contextMenu {
                        Button("重置当前照片", systemImage: "arrow.counterclockwise") { document.reset() }.disabled(document.current == nil)
                        Button("关于 Silverphase", systemImage: "info.circle") { about = true }
                    }
            }
            ChromeButton(title: "撤销", symbol: "arrow.uturn.backward", enabled: document.canUndo) { document.undo() }.accessibilityIdentifier("editor.undo")
            ChromeButton(title: "重做", symbol: "arrow.uturn.forward", enabled: document.canRedo) { document.redo() }.accessibilityIdentifier("editor.redo")
        }.auditEditorBounds("top.leading-actions")
    }
    private var viewActions: some View {
        HStack(spacing: 0) {
            ChromeButton(title: "原图对比", symbol: "rectangle.lefthalf.filled", selected: document.showOriginal, enabled: document.image != nil) { document.showOriginal.toggle() }
                .contextMenu {
                    Button("适合窗口") { document.zoomToFit() }.disabled(document.cropEditing)
                    Button("1:1 原始像素") { document.zoomToNative() }.disabled(document.cropEditing)
                }
            ChromeButton(title: "导出", symbol: "square.and.arrow.up", selected: exporting, enabled: document.image != nil && !document.delivering) {
                exporting.toggle(); inspector = true; materials = false
            }
            NativeEditorMenu(document: document, inspector: $inspector, materials: $materials,
                             exporting: $exporting, about: $about, settings: $settings,
                             importing: $importing, pickingPhotos: $pickingPhotos)
                .labelStyle(.iconOnly).frame(width: EditorDesign.hitSize, height: EditorDesign.hitSize)
        }.auditEditorBounds("top.trailing-actions")
    }
    private func stageNavigation(expands: Bool, vertical: Bool = false) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            ForEach(MobileStage.allCases) { item in
                Button {
                    stage = item; inspector = true; exporting = false
                    materials = document.current != nil && (item == .film || item == .print)
                } label: {
                    ToolbarGlyph(symbol: item.symbol)
                        .foregroundStyle(document.current != nil && stage == item && inspector && !exporting ? MobileStyle.accent : .white.opacity(0.75))
                        .frame(minWidth: 44, maxWidth: expands ? .infinity : nil, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(document.current == nil || document.delivering)
                .accessibilityLabel(item.rawValue).accessibilityIdentifier("stage." + item.id)
                .contextMenu {
                    Button("打开" + item.rawValue, systemImage: item.symbol) {
                        stage = item; inspector = true; exporting = false
                        materials = item == .film || item == .print
                    }
                }
            }
        }
    }
    private func openImport() {
        overlays.choice = MobileChoice(title: "导入照片", options: [
            MobileOption(id: "photos", title: "从照片导入", symbol: "photo.on.rectangle", accessibilityID: "import.photos"),
            MobileOption(id: "files", title: "从文件导入", symbol: "folder", accessibilityID: "import.files")
        ]) { id in if id == "photos" { pickingPhotos = true } else { importing = true } }
    }
    private var emptyEditor: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 27, weight: .light)).foregroundStyle(.secondary)
            Text("打开照片开始编辑").font(.system(size: 15, weight: .semibold))
            Text("胶片 · 显影 · 印相").font(.system(size: 11)).foregroundStyle(.secondary)
            SmallAction(title: "打开照片", symbol: "plus", prominent: true) { pickingPhotos = true }.frame(width: 144)
        }
    }
    private func processPanel(side: Bool, heightBasis: CGFloat? = nil) -> some View {
        VStack(spacing: 0) {
            if !side {
                Capsule().fill(Color.white.opacity(0.25)).frame(width: 28, height: 3)
                    .padding(.top, heightBasis == nil ? 6 : 0).padding(.bottom, heightBasis == nil ? 2 : 0)
                    .frame(maxWidth: .infinity).frame(height: heightBasis == nil ? nil : 44).contentShape(Rectangle())
                    .accessibilityIdentifier("editor.panel-resize")
                    .gesture(DragGesture(coordinateSpace: .global).updating($panelDragging) { _, state, _ in state = true }
                        .onChanged { value in
                            if let heightBasis {
                                if panelDragStart == nil { panelDragStart = dockFraction }
                                dockFraction = min(0.72, max(0.25, (panelDragStart ?? dockFraction) - value.translation.height / max(1, heightBasis)))
                            } else { dockFraction = min(0.65, max(0.25, dockFraction - value.translation.height / 5000)) }
                        }.onEnded { _ in panelDragStart = nil })
                    .onChange(of: panelDragging) { _, dragging in if !dragging { panelDragStart = nil } }
            }
            HStack {
                Text(exporting ? "导出成片" : compactPhoneEditor && materials ? "胶片与相纸" : stage.rawValue).font(EditorDesign.panelTitle).accessibilityIdentifier("inspector.title")
                Spacer()
                if !exporting {
                    Text(document.value("film_stock")?.stringValue.flatMap { StockCatalog.shared.stock($0)?.name.replacingOccurrences(of: "Kodak ", with: "") } ?? "")
                        .font(EditorDesign.help).foregroundStyle(.secondary).lineLimit(1)
                }
                if let batchIDs, batchIDs.count > 1, !exporting {
                    Button {
                        document.endParameterInteraction()
                        if let photo = document.current { batchCopyRequest = MobileSettingsCopyRequest(source: photo, groups: document.copyGroups) }
                    } label: { Image(systemName: "rectangle.stack.badge.plus") }
                    .frame(width: 44, height: 44).accessibilityLabel("应用编辑项到本批 \(batchIDs.count) 张")
                    .accessibilityIdentifier("editor.apply-batch")
                }
                if compactPhoneEditor && !exporting && (stage == .film || stage == .print) {
                    ChromeButton(title: materials ? "查看工艺参数" : "选择胶片与相纸",
                                 symbol: materials ? "slider.horizontal.3" : "rectangle.stack") {
                        materials.toggle()
                    }.accessibilityIdentifier("editor.material-toggle")
                }
                if !exporting {
                    Menu { Button("重置本工艺", systemImage: "arrow.counterclockwise") { document.resetStage(stage) } } label: {
                        ToolbarGlyph(symbol: "ellipsis")
                    }.tint(.primary).accessibilityLabel("工艺操作")
                }
                ChromeButton(title: "收起面板", symbol: "chevron.down") { inspector = false; exporting = false; materials = false }
                    .accessibilityIdentifier("editor.panel-collapse")
            }.padding(.leading, 16).padding(.trailing, 4).frame(height: 44)
            Rectangle().fill(MobileStyle.rule).frame(height: 1)
            if compactPhoneEditor && materials && !exporting {
                MaterialChooser(document: document, startsWithPaper: stage == .print)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            }
            else if exporting { ScrollView { exportPanel }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped() }
            else {
                ScrollView { ProcessControls(document: document, stage: stage).id(document.selection).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, EditorDesign.contentInset).padding(.vertical, 8) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                    .id(stage).transition(.opacity)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private var exportPanel: some View {
        MobileExportPanel(document: document, filteredIDs: filteredPhotos.map(\.id), fixedIDs: batchIDs ?? (returnToLibrary == nil ? nil : document.selection.map { [$0] }))
    }
    private var filteredPhotos: [MobilePhoto] {
        document.photos.filter { (batchIDs?.contains($0.id) ?? true) && $0.rating >= minimumRating && (flagFilter == "all" || $0.flag == flagFilter) }
    }
    private var filmstrip: some View {
        MobileFilmstrip(document: document, photos: filteredPhotos, minimumRating: $minimumRating, flagFilter: $flagFilter)
    }

}

@MainActor @Observable final class MobileCanvasState {
    var scale: CGFloat = 1
    var nativeMode = false
    var pixelScale: CGFloat?
    var offset = CGSize.zero
    func reset(native: Bool = false) { scale = 1; nativeMode = native; pixelScale = nil; offset = .zero }
}

struct PhotoCanvas: View {
    @Bindable var canvas: MobileCanvasState
    let image: CGImage?
    var fitInsets = EdgeInsets()
    var detail: MobileDetailTile?
    var onViewport: ((MobileViewport) -> Void)?
    var onOriginalViewport: ((MobileViewport) -> Void)?
    var nativeSize = CGSize.zero
    var zoomRequest = 0
    var wantsNative = false
    var comparison = false
    var onCompare: ((Bool) -> Void)?
    var development: MobileDevelopmentAssets?
    var developmentRunning = false
    var onPrintNegative: (() -> Void)?
    var onDevelopmentFinished: ((UUID?) -> Void)?
    @Environment(\.displayScale) private var displayScale
    var onNeutral: ((CGPoint) -> Void)? = nil
    @GestureState private var magnification: CGFloat = 1
    @GestureState private var drag = CGSize.zero
    @GestureState private var comparing = false
    private func canvasAccessibilityValue(pixelLongEdge: Double) -> String {
        let transform = "\(canvas.nativeMode ? "native" : "manual");\(canvas.scale);\(canvas.offset.width);\(canvas.offset.height)"
#if DEBUG
        if (ProcessInfo.processInfo.arguments.contains("--interaction-ui-regression") || ProcessInfo.processInfo.arguments.contains("--compact-editor-ui-regression")), let image {
            return transform + ";image:" + String(describing: ObjectIdentifier(image)) + String(format: ";pixels:%.2f", pixelLongEdge)
        }
#endif
        return transform
    }
    var body: some View {
        GeometryReader { geometry in
            if let image {
                let w = max(1, geometry.size.width - fitInsets.leading - fitInsets.trailing)
                let h = max(1, geometry.size.height - fitInsets.top - fitInsets.bottom)
                let logicalSize = onNeutral == nil && nativeSize.width > 0 && nativeSize.height > 0 ? nativeSize : CGSize(width: image.width, height: image.height)
                let factor = min(w / logicalSize.width, h / logicalSize.height)
                let iw = logicalSize.width * factor, ih = logicalSize.height * factor
                let nativeScale = CGFloat(MobilePreviewPolicy.nativeZoom(nativeLongEdge: Double(max(nativeSize.width, nativeSize.height)),
                    fitLongEdgePoints: Double(max(iw, ih)), displayScale: Double(displayScale)))
                // Native mode is a constraint, not an asynchronously copied
                // canvas.scale value. Swapping preview tiers must preserve 1:1.
                let currentScale = canvas.nativeMode ? nativeScale : canvas.pixelScale.map { $0 * nativeScale } ?? canvas.scale
                let baseScale = currentScale
                let totalScale = baseScale * magnification
                let dx = canvas.offset.width + drag.width, dy = canvas.offset.height + drag.height
                let displayed = CGRect(x: fitInsets.leading + w / 2 + dx - iw * totalScale / 2,
                                       y: fitInsets.top + h / 2 + dy - ih * totalScale / 2,
                                       width: iw * totalScale, height: ih * totalScale)
                let visible = displayed.intersection(CGRect(x: fitInsets.leading, y: fitInsets.top, width: w, height: h))
                let requested = MobileViewport(rect: visible.isNull ? .zero : CGRect(x: (visible.minX - displayed.minX) / displayed.width,
                    y: (visible.minY - displayed.minY) / displayed.height, width: visible.width / displayed.width, height: visible.height / displayed.height),
                    zoom: Double(totalScale), pixelLongEdge: Double(max(iw, ih) * totalScale * displayScale), previewLongEdge: max(image.width, image.height),
                    pixelSize: CGSize(width: iw * totalScale * displayScale, height: ih * totalScale * displayScale))
                ZStack {
                    Image(decorative: image, scale: 1).resizable().frame(width: iw, height: ih)
                    if let development, !comparison, onNeutral == nil {
                        MobileDevelopmentView(assets: development, running: developmentRunning) { onDevelopmentFinished?(development.id) }
                            .id(development.id).frame(width: iw, height: ih).allowsHitTesting(false)
                    }
                    if let detail {
                        Image(decorative: detail.image, scale: 1).resizable()
                            .frame(width: iw * detail.rect.width, height: ih * detail.rect.height)
                            .position(x: (w - iw) / 2 + iw * detail.rect.midX, y: (h - ih) / 2 + ih * detail.rect.midY)
                    }
                }
                    .frame(width: w, height: h).contentShape(Rectangle())
                    .scaleEffect(totalScale)
                    .offset(x: canvas.offset.width + drag.width, y: canvas.offset.height + drag.height)
                    .position(x: fitInsets.leading + max(1, geometry.size.width - fitInsets.leading - fitInsets.trailing) / 2,
                              y: fitInsets.top + max(1, geometry.size.height - fitInsets.top - fitInsets.bottom) / 2)
                    .gesture(MagnifyGesture().updating($magnification) { value, state, _ in state = value.magnification }
                        .onChanged { _ in if canvas.nativeMode { canvas.scale = baseScale; canvas.pixelScale = 1; canvas.nativeMode = false } }
                        .onEnded { value in
                            canvas.scale = min(max(8, nativeScale), max(min(1, nativeScale), baseScale * value.magnification))
                            canvas.pixelScale = canvas.scale / nativeScale; canvas.nativeMode = false
                            if canvas.scale <= 1 { canvas.offset = .zero; if nativeScale > 1 { canvas.pixelScale = nil } }
                        })
                    .simultaneousGesture(DragGesture().updating($drag) { value, state, _ in if baseScale > 1 { state = value.translation } }
                        .onEnded { value in if baseScale > 1 { canvas.offset.width += value.translation.width; canvas.offset.height += value.translation.height } })
                    .simultaneousGesture(LongPressGesture(minimumDuration: 0.25, maximumDistance: 8)
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .updating($comparing) { value, state, _ in
                            if case .second(true, _) = value { state = true }
                        })
                    .onChange(of: comparing) { _, held in
                        if !held || onNeutral == nil { onCompare?(held) }
                    }
                    .onDisappear { onCompare?(false) }
                    .accessibilityAction(named: comparison ? "结束原图对比" : "查看原图") { onCompare?(!comparison) }
                    .accessibilityHint("按住画布查看原图，松开恢复处理结果；双击切换适屏和原始像素")
                    .accessibilityIdentifier("editor.canvas")
                    .accessibilityValue(canvasAccessibilityValue(pixelLongEdge: requested.pixelLongEdge))
                    .accessibilityAction(named: "开始印相") { onPrintNegative?() }
                    .simultaneousGesture(SpatialTapGesture(count: 2, coordinateSpace: .named("photoCanvas"))
                        .exclusively(before: SpatialTapGesture(count: 1, coordinateSpace: .named("photoCanvas")))
                        .onEnded { event in
                        if case .first = event { canvas.reset(native: !canvas.nativeMode && baseScale <= 1.01); return }
                        guard case .second(let tap) = event else { return }
                        let point = tap.location
                        if development != nil, onNeutral == nil { onPrintNegative?(); return }
                        guard let onNeutral else { return }
                        let w = max(1, geometry.size.width - fitInsets.leading - fitInsets.trailing)
                        let h = max(1, geometry.size.height - fitInsets.top - fitInsets.bottom)
                        let factor = min(w / CGFloat(image.width), h / CGFloat(image.height))
                        let iw = CGFloat(image.width) * factor, ih = CGFloat(image.height) * factor
                        let rect = CGRect(x: fitInsets.leading + (w - iw) / 2, y: fitInsets.top + (h - ih) / 2, width: iw, height: ih)
                        guard rect.contains(point) else { return }
                        onNeutral(CGPoint(x: (point.x - rect.minX) / iw, y: (point.y - rect.minY) / ih))
                    })
                    .onChange(of: onNeutral != nil) { _, _ in canvas.reset() }
                    .onChange(of: comparison) { _, comparing in if comparing { onOriginalViewport?(requested) } }
                    .onChange(of: requested, initial: true) { _, request in
                        if comparison { onOriginalViewport?(request) } else { onViewport?(request) }
                    }
            }
        }.coordinateSpace(name: "photoCanvas").clipped()
    }
}

struct ActivitySheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        MobileExportJournal.shared.delivery("share.presenting")
        controller.completionWithItemsHandler = { _, completed, _, error in
            MobileExportJournal.shared.delivery(error != nil ? "share.failed" : completed ? "share.completed" : "share.cancelled")
        }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}

struct MobileAbout: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Silverphase") {
                    Text("基于 Hanze Qiu 的 SpektraLab 原生应用与 Andrea Volpato 的 spektrafilm 物理模型及实测配置。Silverphase 为独立衍生项目。")
                }
                Section("开源许可与署名") {
                    ForEach(licenseURLs, id: \.self) { url in
                        NavigationLink(url.lastPathComponent) { ScrollView { Text((try? String(contentsOf: url, encoding: .utf8)) ?? "无法读取许可文件")
                            .font(.caption).textSelection(.enabled).padding() }.navigationTitle(url.lastPathComponent) }
                    }
                }
            }.navigationTitle("关于 Silverphase")
        }
    }
    private var licenseURLs: [URL] {
        guard let folder = Bundle.main.url(forResource: "Licenses", withExtension: nil, subdirectory: StockCatalog.resourceDirectory) else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

private struct ThumbnailResult: @unchecked Sendable { let image: CGImage? }
struct FilmstripThumbnail: View {
    let url: URL
    var fillsFrame = false
    @State private var image: CGImage?
    var body: some View {
        Group {
            if let image { Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: fillsFrame ? .fill : .fit) }
            else { Image(systemName: "photo").foregroundStyle(.secondary) }
        }.task(id: url) {
            image = nil
            let result = await Task.detached(priority: .utility) {
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 192, kCGImageSourceCreateThumbnailWithTransform: true]
                let source = CGImageSourceCreateWithURL(url as CFURL, nil)
                return ThumbnailResult(image: source.flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, options as CFDictionary) })
            }.value
            if !Task.isCancelled { image = result.image }
        }
    }
}
