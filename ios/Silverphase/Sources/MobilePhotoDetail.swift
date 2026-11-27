import SwiftUI
import ImageIO
import UIKit

/// The viewer owns browsing state, not the editor's selected image or render session.
struct MobilePhotoDetail: View {
    let document: MobileDocument
    let photoIDs: [UUID]
    let initialHingeClosed: Bool?
    let initialWindowSize: CGSize
    @Binding var photoID: UUID
    let gridBackdrop: UIImage?
    let gridTarget: CGRect?
    let entryTarget: CGRect?
    let entryPhotoID: UUID
    let backLabel: String
    let onPullDismiss: () -> Void
    let onEdit: (MobilePhoto) -> Void
    let onExport: (MobilePhoto) -> Void
    let onInfo: (MobilePhoto) -> Void
    let onCopy: (MobilePhoto) -> Void
    let onDelete: (MobilePhoto) -> Void

    @State private var renderer = MobileEngine()
    @State private var galleryDetailRenderer = MobileDetailRenderer()
    @State private var originalDetailRenderer = MobileEngine()
    @State private var originalTile: (key: URL, tile: MobileDetailTile)?
    @State private var originalUnavailable = false
    @State private var filmUnavailable = false
    @State private var nativeZoomCommand = 0
    @State private var fitZoomCommand = 0
    @State private var canvasDemand: GalleryCanvasDemand?
    @State private var galleryTile: (key: URL, tile: MobileDetailTile)?
    @State private var tileWork: Task<Void, Never>?
    @State private var tileGeneration = 0
    @State private var originalHoldID: UUID?
    @State private var originalFitWork: UUID?
    @State private var originalDetailWork: UUID?
    @State private var originalProxy: (id: UUID, image: CGImage, requestedEdge: Int)?
    @State private var memoryDrop = 0
    @State private var preview: CGImage?
    @State private var previewLoading = true
    @State private var previewID: UUID?
    @State private var developedPreview = false
    @State private var displayedFilmKey: URL?
    @State private var showingFilm = false
    @State private var hinge: HingeReading = .pending
    @State private var windowSize: CGSize = .zero
    @State private var chromeVisible = true
    @State private var pulling = false
    @State private var entryCurtain = true
    @State private var backCommand = 0
    @State private var neighbors: [Int: DetailPageNeighbor] = [:]
    @State private var stripScrubbing = false
    @State private var stripProxyID: UUID?
    @State private var pageIndexes: [UUID: Int] = [:]
    @State private var recentRenditions: [(key: URL, edge: Int, image: CGImage)] = []
    private static let stripBand: CGFloat = 58
    private static let titledFilmLabelWidth: CGFloat = 108
    private static let toolbarFilmSymbolSize: CGFloat = 22
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    private var showsControls: Bool { chromeVisible && !pulling }

    private enum HingeReading { case pending, measured(Bool?) }
    private enum Placement: Equatable { case bottom, systemSide, duoPortrait, iPad }
    private var usesSpreadPhotoActions: Bool { placement == .duoPortrait }
    private var detailWindowSize: CGSize { windowSize == .zero ? initialWindowSize : windowSize }
    private var hingeClosed: Bool? {
        switch hinge {
        case .pending: initialHingeClosed
        case .measured(let value): value
        }
    }
    private var isDuo: Bool {
        if #available(iOS 27.1, *) { return hingeClosed != nil }
        return false
    }

    private var placement: Placement {
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--gallery-duo-portrait-layout") { return .duoPortrait }
#endif
        if UIDevice.current.userInterfaceIdiom == .pad { return .iPad }
        let closed = hingeClosed
        if #available(iOS 27.1, *), let closed {
            let size = detailWindowSize
            return closed || size.width >= size.height ? .systemSide : .duoPortrait
        }
        return .bottom
    }

    private struct PreviewRequest: Equatable {
        let source: URL?
        let scrubbing: Bool
        let edge: Int?
        let zoomed: Bool
    }

    private struct TileRequest: Equatable {
        let key: URL
        let viewport: MobileViewport
        let memoryDrop: Int
        let wantsNative: Bool
    }

    private var zoomedDemand: Bool { canvasDemand?.photoID == photoID && canvasDemand?.viewport != nil }
    private var fitEdge: Int? { canvasDemand?.photoID == photoID ? canvasDemand?.fitEdge : nil }
    private var tileRequest: TileRequest? {
        guard !stripScrubbing, previewID == photoID,
              displayedFilmKey == photo.map({ document.libraryPreviewURL($0) }),
              let photo, let demand = canvasDemand, demand.photoID == photo.id,
              let viewport = demand.viewport, (demand.nativeZoom || viewport.needsDetail) else { return nil }
        return TileRequest(key: document.libraryPreviewURL(photo), viewport: viewport, memoryDrop: memoryDrop,
                           wantsNative: demand.nativeZoom)
    }

    private var originalTileRequest: TileRequest? {
        guard !stripScrubbing, let photo, originalHoldID == photo.id,
              originalProxy?.id == photo.id, let demand = canvasDemand, demand.photoID == photo.id,
              let viewport = demand.originalViewport, (demand.nativeZoom || viewport.needsDetail) else { return nil }
        return TileRequest(key: document.libraryPreviewURL(photo), viewport: viewport, memoryDrop: memoryDrop,
                           wantsNative: demand.nativeZoom)
    }

    private var photo: MobilePhoto? { document.libraryPhoto(withID: photoID) }
    var body: some View {
        NavigationStack {
            if let photo {
                content(photo)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { navigationItems(photo) }
                    .toolbar(showsControls ? .visible : .hidden, for: .navigationBar)
                    .toolbar(showsControls ? .visible : .hidden, for: .bottomBar)
                    .toolbarBackground(.hidden, for: .navigationBar, .bottomBar)
                    .modifier(DetailNoScrollMask())
                    .modifier(DetailToolbarAxis(usesTop: placement == .iPad || usesSpreadPhotoActions))
            } else {
                Button(backLabel, action: onPullDismiss)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .tint(.primary)
        .overlay {
            if entryCurtain, !reduceMotion, entryTarget != nil, let gridBackdrop {
                GeometryReader { geometry in
                    Image(uiImage: gridBackdrop).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .background(MobileStyle.canvas.ignoresSafeArea())
        .task(id: PreviewRequest(source: photo.map { document.libraryRenderRequestKey($0) }, scrubbing: stripScrubbing, edge: fitEdge, zoomed: zoomedDemand)) {
            if previewID != photoID { preview = nil; previewID = nil }
            developedPreview = false
            previewLoading = true
            defer {
                if !Task.isCancelled {
                    previewLoading = false
                    if preview == nil { entryCurtain = false }
                }
            }
            guard let photo else { return }
            let cached = document.libraryPreviewURL(photo)
            let started = ProcessInfo.processInfo.systemUptime
            let edge = fitEdge ?? 1600
            if let ready = recentRenditions.first(where: { $0.key == cached && $0.edge >= edge }) {
                preview = ready.image; previewID = photo.id; developedPreview = true; displayedFilmKey = cached
#if DEBUG
                GalleryTileAudit.record("fit memory-hit \(max(ready.image.width, ready.image.height)) px")
#endif
                return
            }
            let warm = await Self.loadPreview(cached, limit: 384)
            guard !Task.isCancelled else { return }
            if let warm {
                if preview == nil || stripProxyID == photo.id || displayedFilmKey != cached {
                    preview = warm; previewID = photo.id; stripProxyID = nil; displayedFilmKey = cached
#if DEBUG
                    GalleryTileAudit.record("film cached \(max(warm.width, warm.height)) px at \(ProcessInfo.processInfo.systemUptime - started)s")
#endif
                }
            } else if preview == nil || (stripProxyID == photo.id && !stripScrubbing) {
                let original = await Self.loadPreview(document.url(for: photo), limit: 960)
                guard !Task.isCancelled else { return }
                if let original {
                    preview = original; previewID = photo.id; stripProxyID = nil
                    displayedFilmKey = nil
                }
            }
            guard !stripScrubbing, fitEdge != nil || preview == nil else { return }
            // A cold RAW shows a small film render first, rather than waiting
            // for the complete display tier before any film color appears.
            do {
                if photo.id != entryPhotoID { try await Task.sleep(for: .milliseconds(110)) }
                let renderEngine = renderer
                if displayedFilmKey != cached {
                    do {
                        let draft = try await withTaskCancellationHandler {
                            try await document.renderLibraryDraft(photo, using: renderEngine)
                        } onCancel: { renderEngine.workGate.cancel() }
                        try Task.checkCancellation()
                        preview = draft; previewID = photo.id; displayedFilmKey = cached
#if DEBUG
                        GalleryTileAudit.record("film draft \(max(draft.width, draft.height)) px at \(ProcessInfo.processInfo.systemUptime - started)s")
#endif
                    } catch { try Task.checkCancellation() }
                }
                // A first zoom must not wait for a fitted tier that it no
                // longer needs. A visible film draft can back the detail tile.
                if zoomedDemand && displayedFilmKey == cached { return }
                let result = try await withTaskCancellationHandler {
                    try await document.renderLibraryDetail(photo, fitEdge: edge, using: renderEngine)
                } onCancel: {
                    renderEngine.workGate.cancel()
                }
                try Task.checkCancellation()
                guard self.photo?.id == photo.id, self.photo.map({ document.libraryPreviewURL($0) }) == result.cacheKey else { return }
                recentRenditions.removeAll { $0.key == cached || $0.key == result.cacheKey }
                recentRenditions.insert((result.cacheKey, edge, result.image), at: 0)
                if recentRenditions.count > 2 { recentRenditions.removeLast() }
                preview = result.image; previewID = photo.id; developedPreview = true; displayedFilmKey = result.cacheKey
#if DEBUG
                GalleryTileAudit.record("fit rendered \(max(result.image.width, result.image.height)) px at \(ProcessInfo.processInfo.systemUptime - started)s")
#endif
            } catch { /* Keep the best already available rendition. */ }
        }
        .task(id: originalHoldID) {
            guard let id = originalHoldID, let photo, photo.id == id else { return }
            let url = document.url(for: photo)
            let geometry = photo.geometry
            let screenEdge = min(2560, fitEdge ?? 1920)
            guard originalProxy?.id != id || (originalProxy?.requestedEdge ?? 0) < screenEdge else { return }
            let work = UUID()
            originalFitWork = work
            defer { if originalFitWork == work { originalFitWork = nil } }
            let trace = GalleryRenderTrace("original-hold")
            if originalProxy?.id != id {
                trace.mark("embedded preview start")
                if let seed = await Self.loadPreview(url, limit: 960), !Task.isCancelled {
                    let proxy = await Self.cropComparison(seed, geometry: geometry)
                    guard !Task.isCancelled, originalHoldID == id, photoID == id else { return }
                    originalProxy = (id, proxy, 960)
                    trace.mark("embedded preview displayed \(max(proxy.width, proxy.height)) px")
                }
            }
            guard (originalProxy?.requestedEdge ?? 0) < screenEdge, !Task.isCancelled else { return }
            trace.mark("fit original start; target \(screenEdge) px")
            guard let fitted = await Self.loadPreview(url, limit: screenEdge, forceThumbnail: true),
                  !Task.isCancelled else { return }
            let rendered = await Self.cropComparison(fitted, geometry: geometry)
            guard !Task.isCancelled, originalHoldID == id, photoID == id else { return }
            let actual = max(rendered.width, rendered.height)
            let current = originalProxy.map { max($0.image.width, $0.image.height) } ?? 0
            if actual >= current { originalProxy = (id, rendered, screenEdge) }
            trace.mark("fit original completed \(actual) px")
        }
        .task(id: originalTileRequest) { await renderOriginalTile() }
        .onChange(of: tileRequest, initial: true) { old, new in
            if new == nil || (old != nil && (old?.key != new?.key || old?.memoryDrop != new?.memoryDrop)) {
                cancelTileWork()
            }
            if new == nil, canvasDemand?.viewport == nil, galleryTile != nil {
                galleryTile = nil
                let detail = galleryDetailRenderer
                Task { await detail.clear() }
            } else {
                startTileWorkIfNeeded()
            }
        }
        .task(id: photoID) {
            if originalHoldID != photoID { originalHoldID = nil }
            if originalProxy?.id != photoID { originalProxy = nil }
            originalTile = nil; originalUnavailable = false; filmUnavailable = false
            let url = photo.map { document.url(for: $0) }
            await galleryDetailRenderer.discardGallerySource(except: url)
        }
        .task(id: photoID) { await prepareNeighbors() }
        .task(id: photoIDs) {
            pageIndexes = photoIDs.enumerated().reduce(into: [:]) { $0[$1.element] = $1.offset }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            recentRenditions.removeAll()
            DetailQuickPreviewCache.images.removeAllObjects()
            cancelTileWork()
            galleryTile = nil
            originalProxy = nil
            originalTile = nil
            originalUnavailable = true; filmUnavailable = true
            canvasDemand = nil
            memoryDrop += 1
            galleryDetailRenderer.engine.workGate.cancel()
            let detailEngine = galleryDetailRenderer
            Task { await detailEngine.clear() }
            let renderEngine = renderer
            Task { await renderEngine.close() }
        }
        .onDisappear {
            cancelTileWork()
            galleryDetailRenderer.engine.workGate.cancel()
            renderer.workGate.cancel()
            let detailEngine = galleryDetailRenderer
            let fitEngine = renderer
            let beforeEngine = originalDetailRenderer
            Task { await detailEngine.clear(); await fitEngine.close(); await beforeEngine.close() }
        }
        .onChange(of: photoID) { _, _ in showingFilm = false }
        .background {
            ProcessBarGeometryProbe(windowSizeChanged: { windowSize = $0 },
                                        hingeChanged: { hinge = .measured($0) })
                .allowsHitTesting(false)
        }
    }

    private func content(_ photo: MobilePhoto) -> some View {
        ZStack {
            // The canvas uses the whole window. Chrome is laid out in the
            // safe area above it; none of those controls changes the fit.
            picture(photo).ignoresSafeArea(.container, edges: .all)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                filmstrip.frame(height: Self.stripBand)
            }
            // The strip may go to the bottom edge only when the actions
            // are in the system side lane, not above a real bottom toolbar.
            .padding(.bottom, placement == .systemSide ? EditorDesign.contentInset : 0)
            .ignoresSafeArea(.container, edges: placement == .systemSide ? .bottom : [])
            .opacity(showsControls ? 1 : 0)
            .allowsHitTesting(showsControls)
            .accessibilityHidden(!showsControls)
        }
        .overlay(alignment: .top) {
            previewStatus(photo)
                .padding(.horizontal, EditorDesign.gutter)
                .padding(.top, 6)
                .allowsHitTesting(false)
        }
        .background(MobileStyle.canvas.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: photoID)
    }

    private var showsDuoLandscapeFilmName: Bool {
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--gallery-duo-test-wide-film-name") { return true }
#endif
        let size = detailWindowSize
        return placement == .systemSide && size.width > size.height && size.width >= 560
    }

    private var hostedFilmLabelSize: CGSize? {
        if UIDevice.current.userInterfaceIdiom == .pad && detailWindowSize.width >= 680 {
            // iPad has room for a longer name, but its top-row glass is shorter.
            return CGSize(width: 148, height: 28)
        }
        if showsDuoLandscapeFilmName {
            return CGSize(width: Self.titledFilmLabelWidth, height: 36)
        }
        return nil
    }

    private func filmButton(_ photo: MobilePhoto) -> some View {
        let id = photo.recipe["film_stock"]?.stringValue ?? MobileProcessContract.defaults["film_stock"]?.stringValue
        let name = id.flatMap { StockCatalog.shared.stock($0)?.displayName }
        let title = T("Choose Film", "切换胶片", "切換膠片")
        return Group {
            if #available(iOS 26.0, *), let labelSize = hostedFilmLabelSize {
                // The native toolbar can reduce even a titleAndIcon Label to
                // an icon. Host only the wide film label to keep its name.
                HStack(spacing: 0) {
                    Button { showingFilm = true } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "film")
                                .font(.system(size: Self.toolbarFilmSymbolSize))
                            Text(shortFilmTitle(name ?? T("Film", "胶片", "膠片")))
                                .lineLimit(1).truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(EditorDesign.sectionTitle)
                        .frame(width: labelSize.width, height: labelSize.height)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .fixedSize()
                    .accessibilityLabel(title)
                    .accessibilityValue(name ?? "")
                    .accessibilityIdentifier("photo-detail.film")
                }
            } else {
                Button { showingFilm = true } label: {
                    let minimumWidth: CGFloat = switch placement {
                    case .iPad: 680
                    case .systemSide: 430
                    case .bottom, .duoPortrait: 510
                    }
                    if detailWindowSize.width >= minimumWidth {
                        Label {
                            Text(shortFilmTitle(name ?? T("Film", "胶片", "膠片")))
                                .lineLimit(1)
                                .frame(width: Self.titledFilmLabelWidth, alignment: .leading)
                        } icon: {
                            Image(systemName: "film")
                        }
                        .labelStyle(.titleAndIcon)
                    } else {
                        Label(title, systemImage: "film")
                    }
                }
            }
        }
        .accessibilityLabel(title)
        .accessibilityValue(name ?? "")
        .accessibilityIdentifier("photo-detail.film")
        .popover(isPresented: $showingFilm, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            // Keep the original attachment, but use more of the window height
            // so browsing usually shows additional rows before scrolling.
            let height = min(550, max(260, detailWindowSize.height * 0.68))
            if isDuo && hingeClosed == true {
                // Leave room for the system side lane and its popover margins.
                // Oversized content otherwise overlaps the trigger on the cover.
                let room = detailWindowSize.width - 56 - 2 * EditorDesign.contentInset
                filmPicker(photo).frame(width: min(308, max(210, room)), height: height)
                    .presentationCompactAdaptation(.none)
            } else {
                filmPicker(photo).frame(height: height).presentationCompactAdaptation(.none)
            }
        }
    }

    private func filmPicker(_ photo: MobilePhoto) -> some View {
        let id = photo.recipe["film_stock"]?.stringValue ?? MobileProcessContract.defaults["film_stock"]?.stringValue
        return MobileFilmPickerGrid(stocks: StockCatalog.shared.filmsForPicker, selectedID: id, cancel: { showingFilm = false }) { film in
            guard photoID == photo.id else { showingFilm = false; return }
            document.setLibraryFilm(film, for: photo.id)
            showingFilm = false
        }
    }

    private func shortFilmTitle(_ name: String) -> String {
        for brand in ["Kodak Professional ", "Kodak ", "Fujifilm ", "Fuji ", "Ilford ", "CineStill ", "Agfa "]
            where name.hasPrefix(brand) { return String(name.dropFirst(brand.count)) }
        return name
    }

    @ToolbarContentBuilder
    private func navigationItems(_ photo: MobilePhoto) -> some ToolbarContent {
        if #available(iOS 27.1, *), placement == .systemSide {
            backItem.axisBehavior(.verticalPreferred).visibilityPriority(.init(higherThan: .high))
        } else {
            backItem
        }
        if #available(iOS 27.1, *) {
            dateItem(photo).axisBehavior(.horizontalOnly)
                .visibilityPriority(.init(higherThan: .high))
                .sharedBackgroundVisibility(.hidden)
            ratingItem(photo).axisBehavior(.horizontalOnly).visibilityPriority(.high)
            ToolbarSpacer(.fixed, placement: .topBarTrailing).axisBehavior(.horizontalOnly)
            flagItem(photo).axisBehavior(.horizontalOnly).visibilityPriority(.high)
            ToolbarSpacer(.fixed, placement: .topBarTrailing).axisBehavior(.horizontalOnly)
            if hostedFilmLabelSize != nil {
                filmItem(photo).axisBehavior(.horizontalOnly).visibilityPriority(.high)
                    .sharedBackgroundVisibility(.hidden)
            } else {
                filmItem(photo).axisBehavior(.horizontalOnly).visibilityPriority(.high)
            }
            if !usesSpreadPhotoActions {
                ToolbarSpacer(.fixed, placement: .topBarTrailing).axisBehavior(.horizontalOnly)
            }
        } else if #available(iOS 26.0, *) {
            dateItem(photo).sharedBackgroundVisibility(.hidden)
            ratingItem(photo)
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            flagItem(photo)
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            if hostedFilmLabelSize != nil {
                filmItem(photo).sharedBackgroundVisibility(.hidden)
            } else {
                filmItem(photo)
            }
            if !usesSpreadPhotoActions { ToolbarSpacer(.fixed, placement: .topBarTrailing) }
        } else {
            dateItem(photo)
            ratingItem(photo)
            flagItem(photo)
            filmItem(photo)
        }
        actionToolbar(photo)
    }

    @ToolbarContentBuilder
    private func actionToolbar(_ photo: MobilePhoto) -> some ToolbarContent {
        if #available(iOS 27.1, *), placement == .systemSide {
            // Register with the same native navigation/sidebar host as the editor.
            // The OS owns this lane, including its safe regions and rotations.
            ToolbarItem(placement: .topBarTrailing) {
                more(photo)
            }.axisBehavior(.verticalPreferred).visibilityPriority(.low)
            ToolbarItem(id: "photo-detail.native-export", placement: .bottomBar) {
                exportTool(photo)
            }.axisBehavior(.verticalPreferred)
            ToolbarItem(id: "photo-detail.native-info", placement: .bottomBar) {
                infoTool(photo)
            }.axisBehavior(.verticalPreferred)
            ToolbarItem(id: "photo-detail.native-edit", placement: .bottomBar) {
                editTool(photo)
            }.axisBehavior(.verticalPreferred).visibilityPriority(.high)
            ToolbarItem(id: "photo-detail.native-delete", placement: .bottomBar) {
                deleteTool(photo)
            }.axisBehavior(.verticalPreferred)
        } else if #available(iOS 26.0, *), placement == .iPad {
            ToolbarItem(placement: .topBarTrailing) { more(photo) }
            ToolbarItem(placement: .bottomBar) { exportTool(photo) }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItemGroup(placement: .bottomBar) {
                infoTool(photo)
                editTool(photo)
                deleteTool(photo)
            }
        } else {
            if !usesSpreadPhotoActions {
                ToolbarItem(placement: .topBarTrailing) { more(photo) }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                exportTool(photo)
                Spacer()
                if usesSpreadPhotoActions { more(photo) }
                infoTool(photo)
                editTool(photo)
                if usesSpreadPhotoActions { Spacer() }
                deleteTool(photo)
            }
        }
    }

    // Match More: a native Menu directly inside its own ToolbarItem.
    // The toolbar owns the material, highlight and dismissal geometry.
    private func ratingItem(_ photo: MobilePhoto) -> ToolbarItem<String, some View> {
        ToolbarItem(id: "photo-detail.native-rating", placement: .topBarTrailing) { rating(photo) }
    }

    private func flagItem(_ photo: MobilePhoto) -> ToolbarItem<String, some View> {
        ToolbarItem(id: "photo-detail.native-flag", placement: .topBarTrailing) { flag(photo) }
    }

    private func filmItem(_ photo: MobilePhoto) -> ToolbarItem<String, some View> {
        ToolbarItem(id: "photo-detail.native-film", placement: .topBarTrailing) { filmButton(photo) }
    }

    private func dateItem(_ photo: MobilePhoto) -> ToolbarItem<String, some View> {
        ToolbarItem(id: "photo-detail.native-date", placement: .topBarLeading) {
            dateLabel(photo)
        }
    }

    private func dateLabel(_ photo: MobilePhoto) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let date = photo.libraryDate {
                // Ask for exactly the width of the two localized strings.
                // The variable-width film chip should give up its title
                // before either of these lines is compressed or truncated.
                Text(date.formatted(date: .numeric, time: .omitted))
                    .font(EditorDesign.panelTitle).monospacedDigit().lineLimit(1)
                Text(date.formatted(date: .omitted, time: .shortened))
                    .font(EditorDesign.parameter).monospacedDigit()
                    .foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text(photo.name)
                    .font(EditorDesign.panelTitle).lineLimit(1)
                    .frame(maxWidth: 88, alignment: .leading)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(photo.libraryDate?.formatted(date: .long, time: .shortened) ?? photo.name)
        .accessibilityIdentifier("photo-detail.date")
    }

    private var backItem: ToolbarItem<String, some View> {
        ToolbarItem(id: "photo-detail.native-back", placement: .topBarLeading) {
            tool(backLabel, "chevron.left", id: "photo-detail.back") { backCommand += 1 }
        }
    }

    private static nonisolated func cropComparison(_ image: CGImage, geometry: MobileGeometry) async -> CGImage {
        await Task.detached(priority: .userInitiated) { (try? geometry.apply(to: image)) ?? image }.value
    }

    private static nonisolated func loadPreview(_ url: URL, limit: Int, forceThumbnail: Bool = false) async -> CGImage? {
        let key = "\(url.absoluteString)#\(limit)#\(forceThumbnail)" as NSString
        if let image = DetailQuickPreviewCache.images.object(forKey: key) { return image }
        let task = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled,
                  let source = CGImageSourceCreateWithURL(url as CFURL,
                    [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil as CGImage? }
            let sourcePolicy = forceThumbnail ? kCGImageSourceCreateThumbnailFromImageAlways : kCGImageSourceCreateThumbnailFromImageIfAbsent
            let options: [CFString: Any] = [sourcePolicy: true, kCGImageSourceShouldCacheImmediately: true,
                                          kCGImageSourceCreateThumbnailWithTransform: true,
                                          kCGImageSourceThumbnailMaxPixelSize: limit]
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            if let image, !Task.isCancelled {
                DetailQuickPreviewCache.images.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
            }
            return image
        }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    private func more(_ photo: MobilePhoto) -> some View {
        Menu {
            Button(T("Zoom to Fit", "适合窗口", "適合視窗"), systemImage: "arrow.down.right.and.arrow.up.left") {
                fitZoomCommand += 1
            }.accessibilityIdentifier("photo-detail.zoom-to-fit")
            Button(T("Actual Pixels (1:1)", "实际像素（1:1）", "實際像素（1:1）"), systemImage: "1.magnifyingglass") {
                filmUnavailable = false; originalUnavailable = false
                nativeZoomCommand += 1
            }.accessibilityIdentifier("photo-detail.native-zoom")
            Button(T("Copy edits", "复制编辑项", "複製編輯項"), systemImage: "doc.on.doc") { onCopy(photo) }
            Button(T("Paste edits", "粘贴编辑项", "貼上編輯項"), systemImage: "doc.on.clipboard") {
                document.pasteSettings(to: [photo.id])
            }.disabled(document.settingsClipboard == nil)
            Button(T("Remove from Library", "从图库删除", "從圖庫刪除"), systemImage: "trash", role: .destructive) { onDelete(photo) }
        } label: { Label(T("More", "更多", "更多"), systemImage: "ellipsis") }
        .accessibilityIdentifier("photo-detail.menu")
    }

    private func rating(_ photo: MobilePhoto) -> some View {
        Menu {
            ForEach(0...5, id: \.self) { value in
                Button(value == 0 ? T("Clear rating", "清除星标", "清除星標") : "\(value) ★") {
                    document.markPhotos([photo.id], rating: value)
                }
            }
        } label: {
            Label {
                Text(T("Rating", "星标", "星標"))
            } icon: {
                if let icon = Self.ratedToolbarImages[photo.rating] {
                    Image(uiImage: icon)
                } else {
                    Image(systemName: "star")
                }
            }
        }
        .accessibilityLabel(T("Rating", "星标", "星標"))
        .accessibilityValue(photo.rating > 0 ? "\(photo.rating) / 5" : T("Unrated", "尚未评分", "尚未評分"))
        .accessibilityIdentifier("photo-detail.rating")
    }

    // The native bar extracts one image from a Menu label. Render the
    // existing star and number as a single template, never its glass.
    @MainActor private static let ratedToolbarImages: [Int: UIImage] = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        guard let symbol = UIImage(systemName: "star.fill", withConfiguration: configuration)?
            .withTintColor(.black, renderingMode: .alwaysOriginal) else { return [:] }
        let font = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        let size = CGSize(width: 27, height: 19)
        return Dictionary(uniqueKeysWithValues: (1...5).map { value in
            let number = String(value) as NSString
            let icon = UIGraphicsImageRenderer(size: size).image { _ in
                symbol.draw(at: CGPoint(x: 1, y: (size.height - symbol.size.height) / 2))
                number.draw(at: CGPoint(x: 19, y: (size.height - number.size(withAttributes: attributes).height) / 2),
                            withAttributes: attributes)
            }
            return (value, icon.withRenderingMode(.alwaysTemplate))
        })
    }()

    private func flag(_ photo: MobilePhoto) -> some View {
        let symbol = photo.flag == "pick" ? "flag.fill" : photo.flag == "reject" ? "flag.slash" : "flag"
        return Menu {
            Button(T("Pick", "保留", "保留"), systemImage: "flag.fill") { document.markPhotos([photo.id], flag: "pick") }
            Button(T("Reject", "淘汰", "淘汰"), systemImage: "flag.slash") { document.markPhotos([photo.id], flag: "reject") }
            Button(T("Clear flag", "清除旗标", "清除旗標")) { document.markPhotos([photo.id], flag: "none") }
        } label: {
            Label(T("Flag", "旗标", "旗標"), systemImage: symbol)
                .foregroundStyle(["pick", "reject"].contains(photo.flag) ? MobileStyle.accent : Color.primary)
        }
        .accessibilityIdentifier("photo-detail.flag")
    }

    private func cancelTileWork() {
        if let tileWork {
#if DEBUG
            GalleryTileAudit.record("detail cancel requested")
#endif
            tileWork.cancel()
            tileGeneration += 1
            self.tileWork = nil
        }
    }

    private func startTileWorkIfNeeded() {
        guard tileWork == nil, let request = tileRequest, let photo else { return }
        if let galleryTile, galleryTile.key == request.key,
           Self.tile(galleryTile.tile, satisfies: request) { return }
        filmUnavailable = false
        let generation = tileGeneration
        tileWork = Task {
            await renderTile(request, photo: photo)
            guard generation == tileGeneration else { return }
            tileWork = nil
            // New viewport within the same photo: finish the high-res whole
            // frame once, then use that cache to crop the latest viewport.
            if let latest = tileRequest, latest != request, latest.key == request.key {
                startTileWorkIfNeeded()
            }
        }
    }

    private func renderTile(_ request: TileRequest, photo: MobilePhoto) async {
        let detail = galleryDetailRenderer
#if DEBUG
        GalleryTileAudit.record("request \(request.viewport)")
#endif
        do {
            // The canvas reports a stopped gesture, not every frame of a pan.
            let result = try await withTaskCancellationHandler {
                try await document.renderLibraryTile(photo, viewport: request.viewport, using: detail)
            } onCancel: {
                detail.engine.workGate.cancel()
            }
            try Task.checkCancellation()
            guard let latest = tileRequest, latest.key == request.key else { return }
            let actual = max(Double(result.image.width) / result.rect.width, Double(result.image.height) / result.rect.height)
            guard (request.wantsNative && result.nativeSize != nil)
                || actual > Double(request.viewport.previewLongEdge) * (request.wantsNative ? 1.001 : 1.07) else {
                filmUnavailable = true
#if DEBUG
                GalleryTileAudit.record("detail unchanged: current \(request.viewport.previewLongEdge) px, available \(Int(actual)) px")
#endif
                return
            }
            // A tile is pinned to normalized image coordinates. Only show
            // it if it covers at least part of the still-visible area.
            if result.rect.intersects(latest.viewport.rect) { galleryTile = (request.key, result) }
#if DEBUG
            GalleryTileAudit.record("visible \(result.rect) \(result.image.width)x\(result.image.height), equivalent long edge \(Int(actual)) px")
#endif
        } catch {
            if !Task.isCancelled, !(error is CancellationError), tileRequest?.key == request.key { filmUnavailable = true }
#if DEBUG
            if error is CancellationError { GalleryTileAudit.record("detail canceled") }
            else {
                let memory = error.localizedDescription.contains("内存") || error.localizedDescription.contains("記憶體")
                    || error.localizedDescription.localizedCaseInsensitiveContains("memory")
                GalleryTileAudit.record(memory ? "detail skipped by memory protection" : "detail failed \(type(of: error))")
            }
#endif
            // Memory pressure or quick paging leaves the usable fit image in place.
        }
    }

    private func renderOriginalTile() async {
        guard let request = originalTileRequest, let photo else { return }
        if let originalTile, originalTile.key == request.key,
           Self.tile(originalTile.tile, satisfies: request) { return }
        originalUnavailable = false
        let work = UUID()
        originalDetailWork = work
        defer { if originalDetailWork == work { originalDetailWork = nil } }
        do {
            let result = try await document.renderLibraryOriginalTile(photo, viewport: request.viewport,
                                                                       using: originalDetailRenderer)
            try Task.checkCancellation()
            guard originalTileRequest == request else { return }
            let actual = max(Double(result.image.width) / result.rect.width, Double(result.image.height) / result.rect.height)
            guard (request.wantsNative && result.nativeSize != nil)
                || actual > Double(request.viewport.previewLongEdge) * (request.wantsNative ? 1.001 : 1.07) else { originalUnavailable = true; return }
            originalTile = (request.key, result)
#if DEBUG
            GalleryTileAudit.record("original viewport \(Int(actual)) px; native=\(result.nativeSize != nil)")
#endif
        } catch {
            if !Task.isCancelled, originalTileRequest == request { originalUnavailable = true }
        }
    }

    private static func tile(_ tile: MobileDetailTile, satisfies request: TileRequest) -> Bool {
        let viewport = request.viewport
        guard tile.rect.contains(viewport.rect) else { return false }
        if tile.nativeSize != nil { return true }
        if request.wantsNative { return false }
        let edge = max(Double(tile.image.width) / tile.rect.width, Double(tile.image.height) / tile.rect.height)
        return edge >= viewport.pixelLongEdge * 0.97
    }

    private func picture(_ photo: MobilePhoto) -> some View {
        ZStack {
            DetailZoomCanvas(photoID: photo.id, name: photo.name, image: previewID == photo.id ? preview : nil,
                             reduceMotion: reduceMotion, developed: developedPreview,
                             tile: galleryTile?.key == document.libraryPreviewURL(photo) ? galleryTile?.tile : nil,
                             comparisonTile: originalHoldID == photo.id && originalTile?.key == document.libraryPreviewURL(photo) ? originalTile?.tile : nil,
                             nativeOutput: document.galleryNativeOutput(photo, original: false),
                             originalNativeOutput: document.galleryNativeOutput(photo, original: true),
                             nativeZoomCommand: nativeZoomCommand, fitZoomCommand: fitZoomCommand,
                             comparisonImage: originalHoldID == photo.id && originalProxy?.id == photo.id ? originalProxy?.image : nil,
                             onCompare: { hold in
                                 originalFitWork = nil
                                 originalDetailWork = nil
                                 originalHoldID = hold ? photo.id : nil
                             },
                             onDemand: { demand in
                if demand.photoID == photoID, canvasDemand != demand {
                    canvasDemand = demand
#if DEBUG
                    GalleryTileAudit.record("fit \(demand.fitEdge) demand \(String(describing: demand.viewport))")
#endif
                }
            }, prefersCoverFill: isDuo, neighbors: neighbors,
                             gridBackdrop: gridBackdrop, gridTarget: gridTarget, entryTarget: entryTarget, backCommand: backCommand,
                             onEntryStarted: { entryCurtain = false }, onPage: page, onPull: { active in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { pulling = active }
            }, onDismiss: onPullDismiss, onTap: {
                guard !voiceOver else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { chromeVisible.toggle() }
            })
            if preview == nil || previewID != photo.id {
                if previewLoading { ProgressView().allowsHitTesting(false).accessibilityHidden(true) }
                else {
                    Label(T("Preview unavailable", "无法显示预览", "無法顯示預覽"), systemImage: "photo")
                        .foregroundStyle(.secondary).allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private func previewStatus(_ photo: MobilePhoto) -> some View {
        if originalHoldID == photo.id {
            previewBadge(originalLabel(photo), id: "photo-detail.original-hold",
                         loading: originalFitWork != nil || originalDetailWork != nil)
        } else if canvasDemand?.nativeZoom == true, showsControls {
            let result = visibleTile(galleryTile, photo: photo, viewport: canvasDemand?.viewport)
            let output = document.galleryNativeOutput(photo, original: false)
            let nativeEdge = max(output.width, output.height)
            let baseIsNative = nativeEdge > 0 && !MobileFilmGate.presents(photo.recipe) && developedPreview
                && preview.map { Double(max($0.width, $0.height)) >= Double(nativeEdge) * 0.999 } == true
            let fullResolution = result?.nativeSize != nil || baseIsNative
            let loading = !fullResolution && result == nil && !filmUnavailable && tileRequest != nil
            let label = fullResolution ? T("Full resolution", "原始分辨率", "原始解析度")
                : result != nil ? T("High-resolution preview", "高清预览", "高解析度預覽")
                : T("Fit preview", "适屏预览", "適屏預覽")
            previewBadge(label, id: "photo-detail.native-status", loading: loading)
        }
    }

    private func previewBadge(_ title: String, id: String, loading: Bool) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier(id)
                .accessibilityValue(loading ? T("Loading", "正在加载", "正在載入") : "")
            if loading {
                ProgressView()
                    .controlSize(.mini)
                    .tint(reduceTransparency ? .white : .primary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .foregroundStyle(reduceTransparency ? Color.white : Color.primary)
        .modifier(ChromeSurface())
        .allowsHitTesting(false)
    }

    private func visibleTile(_ cached: (key: URL, tile: MobileDetailTile)?, photo: MobilePhoto,
                             viewport: MobileViewport?) -> MobileDetailTile? {
        guard let cached, cached.key == document.libraryPreviewURL(photo),
              let viewport, cached.tile.rect.contains(viewport.rect) else { return nil }
        return cached.tile
    }

    private func originalLabel(_ photo: MobilePhoto) -> String {
        if let visible = visibleTile(originalTile, photo: photo, viewport: canvasDemand?.originalViewport) {
            return visible.nativeSize != nil ? T("Original · Full resolution", "原图 · 原始分辨率", "原圖 · 原始解析度")
                : T("Original · High-resolution preview", "原图 · 高清预览", "原圖 · 高解析度預覽")
        }
        return originalProxy?.id == photo.id || originalUnavailable
            ? T("Original · Fit preview", "原图 · 适屏预览", "原圖 · 適屏預覽")
            : T("Original", "原图", "原圖")
    }

    private func neighbor(_ step: Int) -> MobilePhoto? {
        let cachedIndex = pageIndexes[photoID]
        guard let index = cachedIndex.flatMap({ photoIDs.indices.contains($0) && photoIDs[$0] == photoID ? $0 : nil })
            ?? photoIDs.firstIndex(of: photoID) else { return nil }
        var next = index + step
        while photoIDs.indices.contains(next) {
            if let p = document.libraryPhoto(withID: photoIDs[next]) { return p }
            next += step
        }
        return nil
    }

    private func prepareNeighbors() async {
        let current = photoID
        let adjacent = [-1, 1].compactMap { step in
            neighbor(step).map { (step, $0, document.libraryPreviewURL($0), document.url(for: $0)) }
        }
        neighbors = Dictionary(uniqueKeysWithValues: adjacent.map { step, photo, url, _ in
            (step, DetailPageNeighbor(id: photo.id, image: recentRenditions.first(where: { $0.key == url })?.image))
        })
        for (step, photo, cached, original) in adjacent {
            if neighbors[step]?.image != nil { continue }
            var quick = await Self.loadPreview(cached, limit: 384)
            if quick == nil, !Task.isCancelled { quick = await Self.loadPreview(original, limit: 960) }
            guard !Task.isCancelled, photoID == current else { return }
            neighbors[step] = DetailPageNeighbor(id: photo.id, image: quick)
        }
    }

    private func page(_ step: Int) {
        guard let target = neighbor(step) else { return }
        let first = neighbors[step]
        if first?.id == target.id { preview = first?.image; previewID = target.id }
        photoID = target.id
    }

    private var filmstrip: some View {
        // Only the IDs are passed to UICollectionView. Invalidate visible
        // cells on metadata and preview changes without copying the version map.
        let preferences = document.preferences.values
        let revision = DetailFilmstrip.ContentRevision(records: document.libraryPhotosRevision,
            previews: document.libraryPreviewRevision, cropRemapsEffects: preferences.cropRemapsEffects,
            diBlueCompensation: preferences.diBlueCompensation)
        return DetailFilmstrip(photoIDs: photoIDs, contentRevision: revision, item: { id in
            guard let photo = document.libraryPhoto(withID: id) else { return nil }
            return DetailFilmstrip.Item(id: id, name: photo.name, previewURL: document.libraryPreviewURL(photo),
                                        sourceURL: document.url(for: photo), version: document.libraryPreviewVersions[id, default: 0])
        }, selection: photoID, reduceMotion: reduceMotion, onScrubbing: { stripScrubbing = $0 }) { id, image in
            guard photoID != id else { return }
            if let adjacent = neighbors.values.first(where: { $0.id == id })?.image {
                preview = adjacent; previewID = id; stripProxyID = nil
            } else if let image {
                preview = image; previewID = id; stripProxyID = id
            } else {
                preview = nil; previewID = nil; stripProxyID = nil
            }
            photoID = id
        }
        .frame(height: 56)
        .frame(maxWidth: 560)
        .mask {
            if reduceTransparency {
                Rectangle()
            } else {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 12)
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 12)
                }
            }
        }
        .padding(.horizontal, EditorDesign.gutter)
    }

    private func deleteTool(_ photo: MobilePhoto) -> some View {
        Button(role: .destructive) { onDelete(photo) } label: {
            Label(T("Remove from Library", "从图库删除", "從圖庫刪除"), systemImage: "trash")
        }
        .accessibilityIdentifier("photo-detail.delete")
    }

    private func exportTool(_ photo: MobilePhoto) -> some View {
        tool(T("Export", "导出", "匯出"), "square.and.arrow.up", id: "photo-detail.export") { onExport(photo) }
    }

    private func infoTool(_ photo: MobilePhoto) -> some View {
        tool(T("Information", "信息", "資訊"), "info.circle", id: "photo-detail.info") { onInfo(photo) }
    }

    private func editTool(_ photo: MobilePhoto) -> some View {
        tool(T("Edit", "编辑", "編輯"), "slider.horizontal.3", id: "photo-detail.edit") { onEdit(photo) }
    }

    private func tool(_ label: String, _ symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(label, systemImage: symbol) }
            .accessibilityIdentifier(id)
    }
}

struct MobileFilmPickerGrid: View {
    let stocks: [Stock]
    let selectedID: String?
    let cancel: () -> Void
    let select: (Stock) -> Void
    var identifier = "photo-detail.film"
    @State private var query = ""
    @State private var filter = MobileMaterialFilter.all

    private let filters: [MobileMaterialFilter] = [.all, .positive, .negative, .monochrome, .experimental]
    private let gap = EditorDesign.unit * 2
    private let inset = EditorDesign.contentInset
    private var matches: [Stock] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let results = stocks.filter { stock in
            filter.includes(stock, favorites: [], recent: [])
                && (query.isEmpty || stock.name.localizedStandardContains(query)
                    || stock.displayName.localizedStandardContains(query)
                    || (stock.speedLabel?.localizedStandardContains(query) ?? false))
        }
        guard query.isEmpty, let selected = results.first(where: { $0.id == selectedID }) else { return results }
        return [selected] + results.filter { $0.id != selectedID }
    }

    var body: some View {
        GeometryReader { geometry in
            let usableWidth = max(1, geometry.size.width - 2 * inset)
            let columns = min(4, max(2, Int((usableWidth + gap) / (98 + gap))))
            let cardWidth = max(1, (usableWidth - CGFloat(columns - 1) * gap) / CGFloat(columns))
            pickerBody(columns: columns, cardWidth: cardWidth)
                .frame(width: usableWidth, height: geometry.size.height)
                .padding(.horizontal, inset)
        }
        .frame(idealWidth: 440, idealHeight: 390)
        .accessibilityAction(.escape) { cancel() }
    }

    private func pickerBody(columns: Int, cardWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: EditorDesign.unit) {
                HStack {
                    Text(T("Choose Film", "切换胶片", "切換膠片"))
                        .font(.headline).accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier(identifier + "-title")
                    Spacer(minLength: EditorDesign.unit)
                    Menu {
                        ForEach(filters) { item in
                            Button {
                                filter = item
                            } label: {
                                if filter == item { Label(item.title, systemImage: "checkmark") }
                                else { Text(item.title) }
                            }
                            .accessibilityIdentifier(identifier + "-filter." + String(describing: item))
                        }
                    } label: {
                        Image(systemName: filter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                            .font(EditorDesign.sectionTitle)
                            .foregroundStyle(filter == .all ? Color.primary : MobileStyle.accent)
                            .frame(width: EditorDesign.hitSize, height: EditorDesign.hitSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(T("Filter films", "筛选胶片", "篩選膠片"))
                    .accessibilityValue(filter.title)
                    .accessibilityIdentifier(identifier + "-filter")
                    Button(action: cancel) {
                        Image(systemName: "xmark").font(EditorDesign.sectionTitle)
                            .frame(width: EditorDesign.hitSize, height: EditorDesign.hitSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(T("Close", "关闭", "關閉"))
                    .accessibilityIdentifier(identifier + "-close")
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(T("Search films", "搜索胶片", "搜尋膠片"), text: $query)
                        .textFieldStyle(.plain)
                        .submitLabel(.search)
                        .accessibilityIdentifier(identifier + "-search")
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                .frame(minWidth: 36, minHeight: 40)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(T("Clear search", "清除搜索", "清除搜尋"))
                        .accessibilityIdentifier(identifier + "-clear")
                    }
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(.primary.opacity(0.07), in: .rect(cornerRadius: 12))
            }
            .padding(.top, EditorDesign.gutter).padding(.bottom, EditorDesign.unit * 2)
            if matches.isEmpty {
                ContentUnavailableView(T("No matching film", "没有匹配的胶片", "沒有符合的膠片"), systemImage: "film")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(cardWidth), spacing: gap), count: columns), spacing: gap) {
                        ForEach(matches) { stock in card(stock, width: cardWidth) }
                    }
                    .padding(.bottom, inset)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier(identifier + "-grid")
            }
        }
    }

    private func card(_ stock: Stock, width: CGFloat) -> some View {
        let selected = stock.id == selectedID
        let subtitle = stock.speedLabel ?? ""
        return Button { select(stock) } label: {
            BrowserCard(title: stock.displayName, subtitle: subtitle, width: width,
                        selected: selected, stock: stock, compact: true) {
                if let artwork = stock.packagingArtworkURL {
                    FilmstripThumbnail(url: artwork, fillsFrame: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Image(systemName: "film").frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(MobileStyle.well)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(stock.displayName)
        .accessibilityValue(subtitle)
        .accessibilityHint(stock.isFotufilm ? "Fotufilm" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier + "-stock." + stock.id)
    }
}


private struct DetailNoScrollMask: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.scrollEdgeEffectHidden(true, for: .top) }
        else { content }
    }
}

private enum DetailQuickPreviewCache {
    // NSCache serializes its own access. The singleton never changes identity.
    nonisolated(unsafe) static let images: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.totalCostLimit = 32 * 1024 * 1024
        cache.countLimit = 42
        return cache
    }()
}

private struct DetailToolbarAxis: ViewModifier {
    let usesTop: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.toolbarVerticalBehavior(usesTop ? .disabled : .automatic)
        } else { content }
    }
}

/// UIKit's zoom recognizer, deceleration, and rubber-banding are used instead
/// of composing SwiftUI magnify/drag gestures that compete with photo paging.
private struct DetailPageNeighbor {
    let id: UUID
    let image: CGImage?
}

/// A render-local timing token. Events are written asynchronously and contain
/// no asset identifiers, URLs, settings, or pixels.
struct GalleryRenderTrace: Sendable {
    private let prefix: String
    private let started: TimeInterval

    init(_ stage: String) {
        started = ProcessInfo.processInfo.systemUptime
        prefix = stage + " #" + String(UUID().uuidString.prefix(6))
    }

    func mark(_ phase: String) {
#if DEBUG
        guard GalleryTileAudit.enabled else { return }
        let ms = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
        GalleryTileAudit.record("\(prefix) +\(ms)ms \(phase)")
#endif
    }
}

#if DEBUG
enum GalleryTileAudit {
    static let enabled = ProcessInfo.processInfo.arguments.contains("--gallery-tile-audit")
        || ProcessInfo.processInfo.arguments.contains("--gallery-compare-audit")
        || ProcessInfo.processInfo.arguments.contains("--gallery-native-audit")
        || Bundle.main.bundleIdentifier?.hasSuffix(".galleryqa") == true
    private static let writer = DispatchQueue(label: "silverphase.gallery-timing", qos: .utility)

    static func record(_ line: String) {
        guard enabled else { return }
        let time = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
        writer.async {
            let url = URL.documentsDirectory.appendingPathComponent("gallery-tile-audit.txt")
            let previous = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let output = String(previous.suffix(33_000)) + time + " " + line + "\n"
            try? output.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
#endif

private struct GalleryCanvasDemand: Equatable {
    let photoID: UUID
    let fitEdge: Int
    let viewport: MobileViewport?
    let originalViewport: MobileViewport?
    let nativeZoom: Bool
}

private struct DetailZoomCanvas: UIViewRepresentable {
    let photoID: UUID
    let name: String
    let image: CGImage?
    let reduceMotion: Bool
    let developed: Bool
    let tile: MobileDetailTile?
    let comparisonTile: MobileDetailTile?
    let nativeOutput: CGSize
    let originalNativeOutput: CGSize
    let nativeZoomCommand: Int
    let fitZoomCommand: Int
    let comparisonImage: CGImage?
    let onCompare: (Bool) -> Void
    let onDemand: (GalleryCanvasDemand) -> Void
    let prefersCoverFill: Bool
    let neighbors: [Int: DetailPageNeighbor]
    let gridBackdrop: UIImage?
    let gridTarget: CGRect?
    let entryTarget: CGRect?
    let backCommand: Int
    let onEntryStarted: () -> Void
    let onPage: (Int) -> Void
    let onPull: (Bool) -> Void
    let onDismiss: () -> Void
    let onTap: () -> Void

    func makeUIView(context: Context) -> ZoomView { ZoomView() }

    static func dismantleUIView(_ uiView: ZoomView, coordinator: ()) {
        uiView.stopDemand()
        uiView.removeTransition()
    }

    func updateUIView(_ view: ZoomView, context: Context) {
        view.onPage = onPage; view.onTap = onTap; view.reduceMotion = reduceMotion
        view.neighbors = neighbors; view.gridBackdrop = gridBackdrop; view.gridTarget = gridTarget
        view.onPull = onPull; view.onDismiss = onDismiss
        view.entryTarget = entryTarget; view.onEntryStarted = onEntryStarted
        view.onDemand = onDemand
        view.onCompare = onCompare
        view.update(photoID: photoID, name: name, image: image, developed: developed, prefersCoverFill: prefersCoverFill)
        view.updateTile(tile)
        view.updateComparison(comparisonImage, detail: comparisonTile)
        view.nativeOutputEdges = (max(nativeOutput.width, nativeOutput.height),
                                  max(originalNativeOutput.width, originalNativeOutput.height))
        view.requestNativeZoom(nativeZoomCommand, output: nativeOutput)
        view.requestFitZoom(fitZoomCommand)
        view.requestBack(backCommand)
    }

    final class ZoomView: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        private let photoView = UIImageView()
        private let tileView = UIImageView()
        private let compareView = UIImageView()
        private let originalTileView = UIImageView()
        private var displayedOriginal: CGImage?
        private var displayedOriginalTile: MobileDetailTile?
        private var nativeCommand = 0
        private var fitCommand = 0
        var nativeOutputEdges: (film: CGFloat, original: CGFloat) = (0, 0)
        private var nativeZoom = false
        var onCompare: ((Bool) -> Void)?
        private var tile: MobileDetailTile?
        private var demandTask: Task<Void, Never>?
        private var lastScheduledDemand: GalleryCanvasDemand?
        var onDemand: ((GalleryCanvasDemand) -> Void)?
        private var source: CGImage?
        private var photoID: UUID?
        private var lastViewport = CGSize.zero
        private var prefersCoverFill = false
        private var needsFit = false

        private var settingGeometry = false
        private var correctingFitOffset = false
        private enum SwipeAxis { case horizontal, pull }
        private var axis: SwipeAxis?
        private var transitionHost: UIView?
        private let transitionGrid = UIImageView()
        private let transitionCurrent = UIImageView()
        private let transitionNeighbor = UIImageView()
        private var transitionStart = CGRect.zero
        private var transitionViewport = CGRect.zero
        private var pendingPage: UUID?
        private var activeStep: Int?
        private var settling = false
        private var entered = false
        private var scheduledEntry = false
        private var handledBack = 0
        var entryTarget: CGRect?
        var onEntryStarted: (() -> Void)?
        var neighbors: [Int: DetailPageNeighbor] = [:]
        var gridBackdrop: UIImage?
        var gridTarget: CGRect?
        var onPull: ((Bool) -> Void)?
        var onDismiss: (() -> Void)?
#if DEBUG
        private var captureTask: Task<Void, Never>?
#endif
        var reduceMotion = false
        var onPage: ((Int) -> Void)?
        var onTap: (() -> Void)?

        init() {
            super.init(frame: .zero)
            delegate = self
            minimumZoomScale = 1
            maximumZoomScale = 6
            bouncesZoom = true
            showsVerticalScrollIndicator = false
            showsHorizontalScrollIndicator = false
            contentInsetAdjustmentBehavior = .never
            if #available(iOS 26.0, *) {
                topEdgeEffect.isHidden = true
                bottomEdgeEffect.isHidden = true
                leftEdgeEffect.isHidden = true
                rightEdgeEffect.isHidden = true
            }
            backgroundColor = .clear
            clipsToBounds = true
            // Its frame is already aspect-correct. A second aspect fit in
            // UIImageView can leave a one-pixel gutter from fractional points.
            photoView.contentMode = .scaleToFill
            photoView.layer.edgeAntialiasingMask = []
            photoView.layer.allowsEdgeAntialiasing = false
            addSubview(photoView)
            tileView.isUserInteractionEnabled = false
            tileView.contentMode = .scaleToFill
            tileView.isHidden = true
            photoView.addSubview(tileView)
            compareView.isUserInteractionEnabled = false
            compareView.contentMode = .scaleAspectFit
            compareView.backgroundColor = .black
            compareView.isHidden = true
            photoView.addSubview(compareView)
            originalTileView.isUserInteractionEnabled = false
            originalTileView.contentMode = .scaleToFill
            originalTileView.isHidden = true
            compareView.addSubview(originalTileView)

            let hold = UILongPressGestureRecognizer(target: self, action: #selector(holdOriginal(_:)))
            hold.minimumPressDuration = 0.32
            hold.allowableMovement = 10
            hold.delegate = self
            addGestureRecognizer(hold)
            let single = UITapGestureRecognizer(target: self, action: #selector(singleTap))
            let double = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
            double.numberOfTapsRequired = 2
            single.require(toFail: double)
            single.require(toFail: hold)
            addGestureRecognizer(single)
            addGestureRecognizer(double)
            let browse = UIPanGestureRecognizer(target: self, action: #selector(browsePan(_:)))
            browse.maximumNumberOfTouches = 1
            browse.delegate = self
            addGestureRecognizer(browse)
            isAccessibilityElement = true
            accessibilityTraits = [.image]
            accessibilityIdentifier = "photo-detail.image"
            accessibilityCustomActions = [
                UIAccessibilityCustomAction(name: T("Zoom in or out", "切换缩放", "切換縮放")) { [weak self] _ in
                    guard let self, self.source != nil else { return false }
                    self.toggleZoom(at: self.viewportCenterInPhoto)
                    return true
                }
            ]
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func update(photoID: UUID, name: String, image: CGImage?, developed: Bool, prefersCoverFill: Bool) {
            if self.prefersCoverFill != prefersCoverFill { self.prefersCoverFill = prefersCoverFill; needsFit = true }
            accessibilityLabel = name
            if self.photoID != photoID {
                self.photoID = photoID
                stopDemand()
                updateTile(nil)
                updateComparison(nil, detail: nil)
                nativeZoom = false
                setZoomScale(1, animated: false)
                source = nil
                photoView.image = nil
                photoView.layer.removeAllAnimations()
                needsFit = true
            }
            if let image, image !== source {
                let oldAspect = source.map { CGFloat($0.width) / CGFloat($0.height) }
                let aspect = CGFloat(image.width) / CGFloat(image.height)
                source = image
                photoView.image = UIImage(cgImage: image)
#if DEBUG
                scheduleFixtureCapture()
#endif
                // A higher-res rendition of the same crop must not touch
                // zoom, offset, or deceleration just to swap pixel buffers.
                if oldAspect.map({ abs($0 / aspect - 1) > 0.006 }) ?? true { needsFit = true }
            }
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--photo-detail-resolution-audit") {
                let pixels = image.map { max($0.width, $0.height) } ?? 0
                accessibilityValue = "\(developed ? "developed" : "initial")-\(pixels)"
            }
#endif
            if needsFit { setNeedsLayout() }
            else { scheduleEntryIfReady(); scheduleDemand() }
            if pendingPage == photoID, source != nil {
                layoutIfNeeded()
                removeTransition()
            }
#if DEBUG
            updateGeometryAudit()
#endif
        }

        private var viewportCenterInPhoto: CGPoint {
            photoView.convert(CGPoint(x: bounds.minX + lastViewport.width / 2,
                                      y: bounds.minY + lastViewport.height / 2), from: self)
        }

        private var isFitted: Bool { zoomScale <= minimumZoomScale + 0.015 }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard !settingGeometry, bounds.width > 0, bounds.height > 0 else { return }
            if needsFit || lastViewport != bounds.size {
                if transitionHost != nil && !settling && lastViewport != bounds.size {
                    let wasPull = axis == .pull
                    removeTransition()
                    if wasPull { onPull?(false) }
                }
                let scale = zoomScale
                let center = viewportCenterInPhoto
                let normalized = CGPoint(x: center.x / max(1, photoView.bounds.width),
                                         y: center.y / max(1, photoView.bounds.height))
                lastViewport = bounds.size
#if DEBUG
                scheduleFixtureCapture()
#endif
                needsFit = false
                settingGeometry = true
                setZoomScale(1, animated: false)
                let pixelSize = source.map { CGSize(width: $0.width, height: $0.height) } ?? bounds.size
                let fitted = defaultSize(for: pixelSize)
                photoView.frame = CGRect(origin: .zero, size: fitted)
                contentSize = fitted
                setZoomScale(scale, animated: false)
                updateCentering()
                let offset = CGPoint(x: normalized.x * fitted.width * scale - bounds.width / 2,
                                     y: normalized.y * fitted.height * scale - bounds.height / 2)
                if scale <= minimumZoomScale + 0.015 {
                    contentOffset = defaultOffset
                } else {
                    contentOffset = CGPoint(
                        x: min(max(offset.x, -contentInset.left), max(-contentInset.left, contentSize.width - bounds.width + contentInset.right)),
                        y: min(max(offset.y, -contentInset.top), max(-contentInset.top, contentSize.height - bounds.height + contentInset.bottom)))
                }
                settingGeometry = false
                updateZoomState()
            } else {
                updateCentering()
                centerFittedPhoto()
            }
            if let host = transitionHost, host.superview === self, host.frame != bounds { host.frame = bounds }
            layoutTile()
            compareView.frame = photoView.bounds
            layoutOriginalTile()
            scheduleEntryIfReady()
            scheduleDemand()
#if DEBUG
            updateGeometryAudit()
#endif
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { source == nil ? nil : photoView }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            if pinchGestureRecognizer?.state == .began { nativeZoom = false }
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard !settingGeometry else { return }
            updateCentering()
            updateZoomState()
            layoutTile()
            scheduleDemand()
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            centerFittedPhoto()
            updateZoomState()
            layoutTile()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in self?.scheduleDemand() }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { scheduleDemand() }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { scheduleDemand() }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            centerFittedPhoto()
            if !settingGeometry, zoomScale > 1.05 { scheduleDemand() }
        }

        func stopDemand() {
            demandTask?.cancel()
            lastScheduledDemand = nil
        }

        func updateComparison(_ image: CGImage?, detail: MobileDetailTile?) {
            if displayedOriginal !== image {
                displayedOriginal = image
                compareView.frame = photoView.bounds
                compareView.image = image.map { UIImage(cgImage: $0) }
                compareView.isHidden = image == nil
#if DEBUG
                if let image { GalleryTileAudit.record("hold original displayed \(max(image.width, image.height)) px") }
                else { GalleryTileAudit.record("hold original released") }
#endif
                scheduleDemand()
            }
            if displayedOriginalTile?.image !== detail?.image || displayedOriginalTile?.rect != detail?.rect {
                displayedOriginalTile = detail
                originalTileView.image = detail.map { UIImage(cgImage: $0.image) }
            }
            layoutOriginalTile()
        }

        private var comparisonFrame: CGRect {
            let bounds = compareView.bounds
            guard let image = displayedOriginal, bounds.width > 0, bounds.height > 0 else { return .zero }
            let scale = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
            let w = CGFloat(image.width) * scale, h = CGFloat(image.height) * scale
            return CGRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
        }

        private func layoutOriginalTile() {
            let b = comparisonFrame
            guard let tile = displayedOriginalTile, displayedOriginal != nil, zoomScale > 1.05, !b.isEmpty else {
                originalTileView.isHidden = true
                return
            }
            originalTileView.frame = CGRect(x: b.minX + b.width * tile.rect.minX, y: b.minY + b.height * tile.rect.minY,
                                        width: b.width * tile.rect.width, height: b.height * tile.rect.height)
            originalTileView.isHidden = false
        }

        func requestNativeZoom(_ command: Int, output: CGSize) {
            guard command != nativeCommand, source != nil, max(output.width, output.height) > 0, let window else { return }
            nativeCommand = command
            nativeZoom = true
            let logical = max(photoView.bounds.width, photoView.bounds.height)
            let target = CGFloat(MobilePreviewPolicy.nativeZoom(nativeLongEdge: Double(max(output.width, output.height)),
                                                               fitLongEdgePoints: Double(logical),
                                                               displayScale: Double(window.traitCollection.displayScale)))
            maximumZoomScale = max(6, min(16, target))
            let center = viewportCenterInPhoto
            let z = min(maximumZoomScale, max(1, target))
            let w = bounds.width / z, h = bounds.height / z
            zoom(to: CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h), animated: !reduceMotion)
            lastScheduledDemand = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in self?.scheduleDemand() }
        }

        func requestFitZoom(_ command: Int) {
            guard command != fitCommand else { return }
            fitCommand = command
            nativeZoom = false
            lastScheduledDemand = nil
            setZoomScale(1, animated: !reduceMotion)
            centerFittedPhoto()
            scheduleDemand()
        }

        @objc private func holdOriginal(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began: if source != nil, transitionHost == nil { onCompare?(true) }
            case .ended, .cancelled, .failed: onCompare?(false)
            default: break
            }
        }

        func updateTile(_ replacement: MobileDetailTile?) {
            if tile?.image !== replacement?.image || tile?.rect != replacement?.rect {
                tile = replacement
                tileView.image = replacement.map { UIImage(cgImage: $0.image) }
            }
            layoutTile()
        }

        private func layoutTile() {
            guard let tile, zoomScale > 1.05 else {
                tileView.isHidden = true
#if DEBUG
                auditTileStatus(active: false)
#endif
                return
            }
            let b = photoView.bounds
            tileView.frame = CGRect(x: b.width * tile.rect.minX, y: b.height * tile.rect.minY,
                                    width: b.width * tile.rect.width, height: b.height * tile.rect.height)
            tileView.isHidden = false
#if DEBUG
            auditTileStatus(active: true)
#endif
        }

        private func scheduleDemand() {
            guard !settingGeometry, !isZooming, !isZoomAnimating, !isDragging, !isDecelerating,
                  let id = photoID, let source,
                  photoView.bounds.width > 1, photoView.bounds.height > 1, let window else { return }
            let displayScale = window.traitCollection.displayScale
            let b = photoView.bounds
            let edge = MobilePreviewPolicy.fitEdge(pixels: Double(max(b.width, b.height) * displayScale))
            let visible = photoView.convert(bounds, from: self)
            func request(for frame: CGRect, previewEdge: Int, nativeEdge: CGFloat) -> MobileViewport? {
                guard (nativeZoom || zoomScale > 1.05), !frame.isEmpty else { return nil }
                let cropped = visible.intersection(frame)
                guard !cropped.isNull, !cropped.isEmpty else { return nil }
                let rect = CGRect(x: (cropped.minX - frame.minX) / frame.width, y: (cropped.minY - frame.minY) / frame.height,
                                  width: cropped.width / frame.width, height: cropped.height / frame.height)
                let limit = nativeZoom ? 16384.0 : 10240.0
                let target = nativeZoom && nativeEdge > 0 ? nativeEdge : max(frame.width, frame.height) * zoomScale * displayScale
                let pixels = min(limit, Double(target))
                return MobileViewport(rect: rect, zoom: Double(zoomScale), pixelLongEdge: pixels, previewLongEdge: previewEdge)
            }
            let normalized = request(for: b, previewEdge: max(source.width, source.height), nativeEdge: nativeOutputEdges.film)
            let originalRequest = displayedOriginal.flatMap {
                request(for: comparisonFrame, previewEdge: max($0.width, $0.height), nativeEdge: nativeOutputEdges.original)
            }
            let next = GalleryCanvasDemand(photoID: id, fitEdge: edge, viewport: normalized,
                                           originalViewport: originalRequest, nativeZoom: nativeZoom)
            guard next != lastScheduledDemand else { return }
            lastScheduledDemand = next
            demandTask?.cancel()
            demandTask = Task { @MainActor [weak self] in
                if normalized != nil {
                    do { try await Task.sleep(for: .milliseconds(135)) } catch { return }
                } else { await Task.yield() }
                guard let self, !Task.isCancelled, self.photoID == id else { return }
                if self.isZooming || self.isZoomAnimating || self.isDragging || self.isDecelerating {
                    self.lastScheduledDemand = nil
                    return
                }
                self.onDemand?(next)
            }
        }

        private func centerFittedPhoto() {
            guard isFitted, !isZooming, !isZoomAnimating, !settingGeometry, !correctingFitOffset else { return }
            let target = defaultOffset
            if abs(contentOffset.x - target.x) > 0.5 || abs(contentOffset.y - target.y) > 0.5 {
                correctingFitOffset = true
                contentOffset = target
                correctingFitOffset = false
            }
        }

        private func updateZoomState() {
            // Pan only as a zoomed photo. A one-finger swipe at fit advances
            // the gallery; a two-finger pinch never turns into a page switch.
            let allowPan = !isFitted
            if panGestureRecognizer.isEnabled != allowPan { panGestureRecognizer.isEnabled = allowPan }
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--photo-detail-resolution-audit")
                || ProcessInfo.processInfo.arguments.contains("--gallery-tile-audit") { return }
#endif
            let value = "\(Int((zoomScale * 100).rounded()))%"
            if accessibilityValue != value { accessibilityValue = value }
#if DEBUG
            updateGeometryAudit()
#endif
        }

#if DEBUG
        private func auditTileStatus(active: Bool) {
            guard ProcessInfo.processInfo.arguments.contains("--gallery-tile-audit"), let source else { return }
            let pixels = max(source.width, source.height)
            let zoom = Int((zoomScale * 100).rounded())
            let value = "\(active ? "tile" : "fit")-\(pixels)-\(zoom)"
            if accessibilityValue != value { accessibilityValue = value }
        }

        private func updateGeometryAudit() {
            guard ProcessInfo.processInfo.arguments.contains("--photo-detail-geometry-audit"), let window else { return }
            let image = photoView.convert(photoView.bounds, to: window)
            let canvas = convert(bounds, to: window)
            func describe(_ frame: CGRect) -> String {
                [frame.minX, frame.minY, frame.width, frame.height].map { String(Int($0.rounded())) }.joined(separator: ",")
            }
            accessibilityValue = "\(Int((zoomScale * 100).rounded()))%|\(describe(image))|\(describe(canvas))"
        }


        private func scheduleFixtureCapture() {
            let args = ProcessInfo.processInfo.arguments
            guard args.contains("--photo-detail-qa-capture"),
                  args.contains("--library-ui-regression"),
                  args.contains("--documentation-captures") else { return }
            captureTask?.cancel()
            captureTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled, let self, self.source != nil, let window = self.window else { return }
                let rect = window.bounds
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let image = UIGraphicsImageRenderer(bounds: rect, format: format).image { _ in
                    window.drawHierarchy(in: rect, afterScreenUpdates: true)
                }
                let orientation = rect.width > rect.height ? "landscape" : "portrait"
                try? image.pngData()?.write(to: URL.documentsDirectory.appendingPathComponent("gallery-fixture-\(orientation).png"), options: .atomic)
                if let source = self.photoView.image {
                    try? source.pngData()?.write(to: URL.documentsDirectory.appendingPathComponent("gallery-fixture-rendition.png"), options: .atomic)
                }
            }
        }
#endif

        private func defaultSize(for image: CGSize) -> CGSize {
            guard image.width > 0, image.height > 0 else { return .zero }
            let scale = MobilePhotoFit.scale(image: image, available: bounds.size, duo: prefersCoverFill)
            return CGSize(width: image.width * scale, height: image.height * scale)
        }

        private var defaultOffset: CGPoint {
            // On the cover an oversized axis is cropped symmetrically, not
            // pinned to the top/left. Manual zoom/pan owns all other offsets.
            CGPoint(x: max(0, photoView.frame.width - bounds.width) / 2 - contentInset.left,
                    y: max(0, photoView.frame.height - bounds.height) / 2 - contentInset.top)
        }

        private func updateCentering() {
            let rendered = photoView.frame.size
            let x = max(0, bounds.width - rendered.width) / 2
            let y = max(0, bounds.height - rendered.height) / 2
            let inset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
            if contentInset != inset { contentInset = inset }
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer is UILongPressGestureRecognizer {
                return source != nil && transitionHost == nil && !isZooming && !isZoomAnimating
            }
            if gestureRecognizer is UIPanGestureRecognizer && gestureRecognizer !== panGestureRecognizer {
                return isFitted && !isZooming && !isZoomAnimating && !settling && source != nil
            }
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }

        @objc private func browsePan(_ gesture: UIPanGestureRecognizer) {
            guard !settling, let window else { return }
            let d = gesture.translation(in: window)
            let v = gesture.velocity(in: window)
            switch gesture.state {
            case .began, .changed:
                if axis == nil {
                    let x = abs(d.x), y = abs(d.y)
                    // Lock once and never let a diagonal hand movement turn
                    // a page into a dismissal halfway through the gesture.
                    if x >= 9 && x > y * 1.16 { axis = .horizontal }
                    else if d.y >= 12 && y > x * 1.26 { axis = .pull }
                    guard let axis else { return }
                    startTransition(showsGrid: axis == .pull)
                    if axis == .pull { onPull?(true) }
                }
                guard let axis else { return }
                switch axis {
                case .horizontal:
                    let step = d.x < 0 ? 1 : -1
                    let hasNeighbor = neighbors[step] != nil
                    let travel = min(transitionViewport.width, max(-transitionViewport.width, d.x))
                    showPage(step: step, travel: hasNeighbor ? travel : travel * 0.24)
                case .pull:
                    let progress = min(1, max(0, d.y / max(1, transitionViewport.height * 0.45)))
                    let scale = reduceMotion ? 1 : 1 - progress * 0.34
                    transitionCurrent.bounds.size = CGSize(width: transitionStart.width * scale, height: transitionStart.height * scale)
                    transitionCurrent.center = CGPoint(x: transitionStart.midX + d.x * 0.22, y: transitionStart.midY + max(0, d.y))
                    transitionCurrent.layer.cornerRadius = reduceMotion ? 0 : progress * 12
                    transitionGrid.alpha = min(1, progress * 1.9)
                }
            case .ended:
                guard let axis else { return }
                if axis == .horizontal {
                    let step = d.x < 0 ? 1 : -1
                    let enough = abs(d.x) >= transitionViewport.width * 0.24
                        || (abs(d.x) > 24 && abs(v.x) > 420 && d.x * v.x > 0)
                    if enough, let candidate = neighbors[step] {
                        finishPage(step: step, candidate: candidate)
                    } else { restoreTransition(pulling: false) }
                } else {
                    let enough = d.y >= min(160, transitionViewport.height * 0.19) || (d.y > 28 && v.y > 680)
                    if enough { finishPull() } else { restoreTransition(pulling: true) }
                }
            case .cancelled, .failed:
                if let axis { restoreTransition(pulling: axis == .pull) }
            default: break
            }
        }

        private func scheduleEntryIfReady() {
            guard !entered, !scheduledEntry, source != nil, !needsFit,
                  let window, !photoView.bounds.isEmpty else { return }
            scheduledEntry = true
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window, !self.entered else { return }
                self.scheduledEntry = false
                self.entered = true
                guard !self.reduceMotion, self.transitionHost == nil, let tile = self.entryTarget,
                      !tile.isEmpty, window.bounds.insetBy(dx: -2, dy: -2).contains(tile),
                      self.gridBackdrop != nil else {
                    self.onEntryStarted?()
                    return
                }
                self.startTransition(showsGrid: true)
                self.settling = true
                self.transitionGrid.alpha = 1
                self.transitionCurrent.contentMode = .scaleAspectFill
                self.transitionCurrent.frame = self.transitionHost?.convert(tile, from: window) ?? tile
                self.transitionCurrent.layer.cornerRadius = 7
                self.onEntryStarted?()
                UIView.animate(withDuration: 0.30, delay: 0,
                               options: [.curveEaseInOut, .beginFromCurrentState]) {
                    self.transitionCurrent.frame = self.transitionStart
                    self.transitionCurrent.layer.cornerRadius = 0
                    self.transitionGrid.alpha = 0
                } completion: { [weak self] _ in
                    self?.removeTransition()
                }
            }
        }

        func requestBack(_ command: Int) {
            guard command != handledBack else { return }
            handledBack = command
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard !self.reduceMotion, self.window != nil, self.source != nil,
                      self.transitionHost == nil else { self.onDismiss?(); return }
                self.axis = .pull
                self.startTransition(showsGrid: true)
                self.onPull?(true)
                self.finishPull()
            }
        }

        private func startTransition(showsGrid: Bool) {
            let host = UIView(frame: bounds)
            host.isUserInteractionEnabled = false
            host.clipsToBounds = true
            // Every photo animation lives inside the canvas underneath both
            // the native toolbar and the floating thumbnail browser.
            addSubview(host)
            transitionHost = host
            transitionViewport = host.bounds
            transitionStart = photoView.convert(photoView.bounds, to: host)
            if showsGrid {
                transitionGrid.frame = host.bounds
                transitionGrid.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                transitionGrid.contentMode = .scaleAspectFill
                let windowAspect = host.bounds.width / max(1, host.bounds.height)
                if let gridBackdrop, abs((gridBackdrop.size.width / max(1, gridBackdrop.size.height)) / windowAspect - 1) < 0.1 {
                    transitionGrid.image = gridBackdrop
                } else {
                    transitionGrid.image = nil
                    transitionGrid.backgroundColor = backgroundColor ?? .clear
                }
                transitionGrid.alpha = 0
                host.addSubview(transitionGrid)
            }
            transitionNeighbor.contentMode = .scaleToFill
            transitionNeighbor.clipsToBounds = true
            host.addSubview(transitionNeighbor)
            transitionCurrent.image = photoView.image
            transitionCurrent.contentMode = .scaleToFill
            transitionCurrent.clipsToBounds = true
            transitionCurrent.layer.cornerRadius = 0
            transitionCurrent.alpha = 1
            transitionCurrent.frame = transitionStart
            host.addSubview(transitionCurrent)
            photoView.alpha = 0
        }

        private func neighborFrame(_ step: Int) -> CGRect {
            let center = CGPoint(x: transitionStart.midX + CGFloat(step) * (transitionViewport.width + 12),
                                 y: transitionStart.midY)
            let size = neighbors[step]?.image.map { CGSize(width: $0.width, height: $0.height) } ?? transitionStart.size
            let fitted = defaultSize(for: size)
            return CGRect(x: center.x - fitted.width / 2, y: center.y - fitted.height / 2,
                          width: fitted.width, height: fitted.height)
        }

        private func showPage(step: Int, travel: CGFloat) {
            if activeStep != step {
                activeStep = step
                transitionNeighbor.transform = .identity
                transitionNeighbor.image = neighbors[step]?.image.map { UIImage(cgImage: $0) }
                transitionNeighbor.frame = neighborFrame(step)
            } else if transitionNeighbor.image == nil, let incoming = neighbors[step]?.image {
                transitionNeighbor.transform = .identity
                transitionNeighbor.image = UIImage(cgImage: incoming)
                transitionNeighbor.frame = neighborFrame(step)
            }
            // Keep both image layouts fixed while dragging. Updating two
            // transforms avoids resizing views or recomputing fit every frame.
            let transform = CGAffineTransform(translationX: travel, y: 0)
            transitionCurrent.transform = transform
            transitionNeighbor.transform = transform
        }

        private func finishPage(step: Int, candidate: DetailPageNeighbor) {
            settling = true
            let end = -CGFloat(step) * (transitionViewport.width + 12)
            if activeStep != step { showPage(step: step, travel: 0) }
            let duration = reduceMotion ? 0 : 0.24
            UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                self.showPage(step: step, travel: end)
            } completion: { [weak self] _ in
                guard let self else { return }
                self.pendingPage = candidate.image == nil ? nil : candidate.id
                self.onPage?(step)
                if self.pendingPage == nil { self.removeTransition() }
            }
        }

        private func finishPull() {
            settling = true
            let target: CGRect?
            if transitionGrid.image != nil, let gridTarget, let window, let host = transitionHost {
                let local = host.convert(gridTarget, from: window)
                target = transitionViewport.insetBy(dx: -2, dy: -2).contains(local)
                    && local.width > 8 && local.height > 8 ? local : nil
            } else { target = nil }
            let duration = reduceMotion ? 0 : 0.27
            UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
                if let target {
                    self.transitionCurrent.contentMode = .scaleAspectFill
                    self.transitionCurrent.frame = target
                } else {
                    self.transitionCurrent.alpha = 0
                    self.transitionCurrent.transform = CGAffineTransform(scaleX: 0.66, y: 0.66)
                }
                self.transitionCurrent.layer.cornerRadius = 7
                self.transitionGrid.alpha = 1
            } completion: { [weak self] _ in self?.onDismiss?() }
        }

        private func restoreTransition(pulling: Bool) {
            settling = true
            UIView.animate(withDuration: reduceMotion ? 0 : 0.25, delay: 0,
                           usingSpringWithDamping: 0.9, initialSpringVelocity: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction]) {
                if pulling {
                    self.transitionCurrent.frame = self.transitionStart
                    self.transitionCurrent.layer.cornerRadius = 0
                    self.transitionGrid.alpha = 0
                } else if let step = self.activeStep { self.showPage(step: step, travel: 0) }
            } completion: { [weak self] _ in
                self?.removeTransition()
                if pulling { self?.onPull?(false) }
            }
        }

        func removeTransition() {
            transitionGrid.removeFromSuperview()
            transitionNeighbor.removeFromSuperview()
            transitionCurrent.removeFromSuperview()
            transitionHost?.removeFromSuperview()
            transitionHost = nil
            transitionGrid.image = nil
            transitionCurrent.image = nil
            transitionCurrent.transform = .identity
            transitionNeighbor.image = nil
            transitionNeighbor.transform = .identity
            photoView.alpha = 1
            activeStep = nil
            pendingPage = nil
            axis = nil
            settling = false
        }

        @objc private func singleTap() { onTap?() }

        @objc private func doubleTap(_ gesture: UITapGestureRecognizer) {
            toggleZoom(at: gesture.location(in: photoView))
        }

        private func toggleZoom(at point: CGPoint) {
            nativeZoom = false
            guard source != nil, !isZooming, bounds.width > 0, bounds.height > 0 else { return }
            if !isFitted {
                setZoomScale(minimumZoomScale, animated: !reduceMotion)
                return
            }
            let target: CGFloat = min(2.5, maximumZoomScale)
            let size = CGSize(width: bounds.width / target, height: bounds.height / target)
            let center = CGPoint(x: min(max(point.x, 0), photoView.bounds.width),
                                 y: min(max(point.y, 0), photoView.bounds.height))
            zoom(to: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                            width: size.width, height: size.height),
                 animated: !reduceMotion)
        }
    }
}
