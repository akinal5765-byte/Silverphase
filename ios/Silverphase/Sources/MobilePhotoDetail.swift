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
    let onPullDismiss: () -> Void
    let onEdit: (MobilePhoto) -> Void
    let onExport: (MobilePhoto) -> Void
    let onInfo: (MobilePhoto) -> Void
    let onCopy: (MobilePhoto) -> Void
    let onDelete: (MobilePhoto) -> Void

    @State private var renderer = MobileEngine()
    @State private var galleryDetailRenderer = MobileDetailRenderer()
    @State private var canvasDemand: GalleryCanvasDemand?
    @State private var galleryTile: (key: URL, tile: MobileDetailTile)?
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
    @State private var filmstripItems: [DetailFilmstrip.Item] = []
    @State private var stableFit: FitSample?
    @State private var recentRenditions: [(key: URL, edge: Int, image: CGImage)] = []
    private static let stripBand: CGFloat = 58
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    private var showsControls: Bool { chromeVisible && !pulling }

    private enum HingeReading { case pending, measured(Bool?) }
    private enum Placement: Equatable { case top, bottom, systemSide }
    private struct FitMode: Equatable {
        let window: CGSize
        let placement: Placement
    }
    private struct FitSample: Equatable {
        let mode: FitMode
        let frame: CGRect
    }
    private var fitMode: FitMode {
        FitMode(window: windowSize == .zero ? initialWindowSize : windowSize, placement: placement)
    }
    private var fittedFrame: CGRect? { stableFit?.mode == fitMode ? stableFit?.frame : nil }

    private var placement: Placement {
        if UIDevice.current.userInterfaceIdiom == .pad { return .top }
        let closed = switch hinge {
        case .pending: initialHingeClosed
        case .measured(let value): value
        }
        if #available(iOS 27.1, *), let closed {
            let size = windowSize == .zero ? initialWindowSize : windowSize
            return closed || size.width >= size.height ? .systemSide : .top
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
    }

    private var zoomedDemand: Bool { canvasDemand?.photoID == photoID && canvasDemand?.viewport != nil }
    private var fitEdge: Int? { canvasDemand?.photoID == photoID ? canvasDemand?.fitEdge : nil }
    private var tileRequest: TileRequest? {
        guard !stripScrubbing, previewID == photoID,
              displayedFilmKey == photo.map({ document.libraryPreviewURL($0) }),
              let photo, let demand = canvasDemand, demand.photoID == photo.id,
              let viewport = demand.viewport, viewport.needsDetail else { return nil }
        return TileRequest(key: document.libraryPreviewURL(photo), viewport: viewport, memoryDrop: memoryDrop)
    }

    private var photo: MobilePhoto? { document.photos.first { $0.id == photoID } }
    var body: some View {
        NavigationStack {
            if let photo {
                content(photo)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { navigationItems(photo) }
                    .toolbar(showsControls ? .visible : .hidden, for: .navigationBar)
                    .toolbar(showsControls && placement != .top ? .visible : .hidden, for: .bottomBar)
                    .toolbarBackground(.hidden, for: .navigationBar, .bottomBar)
                    .modifier(DetailNoScrollMask())
                    .modifier(DetailToolbarAxis(usesTop: placement == .top))
            } else {
                Button(T("Back to Library", "返回图库", "返回圖庫"), action: onPullDismiss)
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
        .task(id: PreviewRequest(source: photo.map { document.libraryPreviewURL($0) }, scrubbing: stripScrubbing, edge: fitEdge, zoomed: zoomedDemand)) {
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
                recentRenditions.removeAll { $0.key == cached }
                recentRenditions.insert((cached, edge, result), at: 0)
                if recentRenditions.count > 2 { recentRenditions.removeLast() }
                preview = result; previewID = photo.id; developedPreview = true; displayedFilmKey = cached
#if DEBUG
                GalleryTileAudit.record("fit rendered \(max(result.width, result.height)) px at \(ProcessInfo.processInfo.systemUptime - started)s")
#endif
            } catch { /* Keep the best already available rendition. */ }
        }
        .task(id: tileRequest) { await reconcileTile(tileRequest) }
        .task(id: photoID) {
            let url = photo.map { document.url(for: $0) }
            await galleryDetailRenderer.discardGallerySource(except: url)
        }
        .task(id: photoID) { await prepareNeighbors() }
        .task(id: photoIDs) {
            let byID = Dictionary(uniqueKeysWithValues: document.photos.map { ($0.id, $0) })
            filmstripItems = photoIDs.compactMap { byID[$0].map(stripItem) }
        }
        .onChange(of: document.libraryPreviewVersions[photoID]) { _, _ in
            guard let photo, let index = filmstripItems.firstIndex(where: { $0.id == photoID }) else { return }
            filmstripItems[index] = stripItem(photo)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            recentRenditions.removeAll()
            DetailQuickPreviewCache.images.removeAllObjects()
            galleryTile = nil
            canvasDemand = nil
            memoryDrop += 1
            galleryDetailRenderer.engine.workGate.cancel()
            let detailEngine = galleryDetailRenderer
            Task { await detailEngine.clear() }
            let renderEngine = renderer
            Task { await renderEngine.close() }
        }
        .onDisappear {
            galleryDetailRenderer.engine.workGate.cancel()
            let detailEngine = galleryDetailRenderer
            Task { await detailEngine.clear() }
        }
        .sheet(isPresented: $showingFilm) {
            NavigationStack {
                List(StockCatalog.shared.filmsForPicker) { film in
                    Button(film.displayName) {
                        if let photo { document.setLibraryFilm(film, for: photo.id) }
                        showingFilm = false
                    }
                }
                .navigationTitle(T("Choose Film", "切换胶片", "切換膠片"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(T("Cancel", "取消", "取消")) { showingFilm = false }
                    }
                }
            }
        }
        .background {
            ProcessBarGeometryProbe(windowSizeChanged: { windowSize = $0 },
                                        hingeChanged: { hinge = .measured($0) })
                .allowsHitTesting(false)
        }
    }

    private func content(_ photo: MobilePhoto) -> some View {
        GeometryReader { safe in
            let safeFrame = safe.frame(in: .global)
            let sample = FitSample(mode: fitMode, frame: CGRect(
                x: safeFrame.minX + EditorDesign.gutter, y: safeFrame.minY + EditorDesign.gutter,
                width: max(1, safeFrame.width - 2 * EditorDesign.gutter),
                height: max(1, safeFrame.height - EditorDesign.gutter)))
            ZStack {
                // Like the editor, the canvas bleeds to the window edges.
                // Its framed-to-fit pose is a separate, stable safe rectangle.
                picture(photo).ignoresSafeArea(.container, edges: .all)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    filmstrip
                        .frame(height: Self.stripBand)
                }
                .opacity(showsControls ? 1 : 0)
                .allowsHitTesting(showsControls)
                .accessibilityHidden(!showsControls)
            }
            .frame(width: safe.size.width, height: safe.size.height)
            .task(id: showsControls ? sample : nil) {
                // Chrome visibility is not a layout version. Reopening it
                // cannot overwrite the fit rectangle in the same posture.
                guard showsControls, stableFit?.mode != sample.mode else { return }
                if stableFit != nil {
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                }
                stableFit = sample
            }
        }
        .background(MobileStyle.canvas.ignoresSafeArea())
        .sensoryFeedback(.selection, trigger: photoID)
    }

    private func metadata(_ photo: MobilePhoto) -> some View {
        HStack(spacing: 8) {
            rating(photo).frame(width: 44, height: 44)
            flag(photo).frame(width: 44, height: 44)
            Button { showingFilm = true } label: {
                let id = photo.recipe["film_stock"]?.stringValue ?? MobileProcessContract.defaults["film_stock"]?.stringValue
                let name = id.flatMap { StockCatalog.shared.stock($0)?.displayName }
                chip(fitMode.window.width >= 620 ? name : nil, symbol: "film", wideLabel: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(T("Choose Film", "切换胶片", "切換膠片"))
            .accessibilityIdentifier("photo-detail.film")
        }
    }

    @ToolbarContentBuilder
    private func navigationItems(_ photo: MobilePhoto) -> some ToolbarContent {
        if #available(iOS 27.1, *), placement == .systemSide {
            backItem.axisBehavior(.horizontalOnly)
        } else {
            backItem
        }
        if #available(iOS 27.1, *) {
            dateItem(photo).axisBehavior(.horizontalOnly).visibilityPriority(.low).sharedBackgroundVisibility(.hidden)
            metadataItem(photo).axisBehavior(.horizontalOnly).visibilityPriority(.high).sharedBackgroundVisibility(.hidden)
        } else if #available(iOS 26.0, *) {
            dateItem(photo).sharedBackgroundVisibility(.hidden)
            metadataItem(photo).sharedBackgroundVisibility(.hidden)
        } else {
            dateItem(photo)
            metadataItem(photo)
        }
        if placement == .top {
            ToolbarItemGroup(placement: .topBarTrailing) {
                exportTool(photo)
                infoTool(photo)
                editTool(photo)
                more(photo)
            }
        } else if #available(iOS 27.1, *), placement == .systemSide {
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
        } else {
            ToolbarItem(placement: .topBarTrailing) { more(photo) }
            ToolbarItemGroup(placement: .bottomBar) {
                exportTool(photo)
                Spacer()
                infoTool(photo)
                editTool(photo)
            }
        }
    }

    private func metadataItem(_ photo: MobilePhoto) -> ToolbarItem<String, some View> {
        ToolbarItem(id: "photo-detail.native-metadata", placement: .topBarTrailing) {
            metadata(photo)
        }
    }

    private func dateItem(_ photo: MobilePhoto) -> ToolbarItem<String, some View> {
        ToolbarItem(id: "photo-detail.native-date", placement: .topBarLeading) {
            VStack(alignment: .leading, spacing: 1) {
                if let date = photo.libraryDate {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                        .fixedSize(horizontal: fitMode.window.width >= 620, vertical: false)

                    Text(date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text(photo.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
            }
            .frame(maxWidth: fitMode.window.width >= 620 ? 148 : 108, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("photo-detail.date")
        }
    }

    private var backItem: ToolbarItem<String, some View> {
        ToolbarItem(id: "photo-detail.native-back", placement: .topBarLeading) {
            tool(T("Back to Library", "返回图库", "返回圖庫"), "chevron.left", id: "photo-detail.back") { backCommand += 1 }
        }
    }

    private static nonisolated func loadPreview(_ url: URL, limit: Int) async -> CGImage? {
        let key = "\(url.absoluteString)#\(limit)" as NSString
        if let image = DetailQuickPreviewCache.images.object(forKey: key) { return image }
        let task = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled,
                  let source = CGImageSourceCreateWithURL(url as CFURL,
                    [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil as CGImage? }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                                          kCGImageSourceShouldCacheImmediately: true,
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
            chip(photo.rating > 0 ? "\(photo.rating)" : nil, symbol: photo.rating > 0 ? "star.fill" : "star")
                .foregroundStyle(photo.rating > 0 ? MobileStyle.accent : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(T("Rating", "星标", "星標"))
        .accessibilityValue(photo.rating > 0 ? "\(photo.rating) / 5" : T("Unrated", "尚未评分", "尚未評分"))
        .accessibilityIdentifier("photo-detail.rating")
    }

    private func flag(_ photo: MobilePhoto) -> some View {
        Menu {
            Button(T("Pick", "保留", "保留"), systemImage: "flag.fill") { document.markPhotos([photo.id], flag: "pick") }
            Button(T("Reject", "淘汰", "淘汰"), systemImage: "flag.slash") { document.markPhotos([photo.id], flag: "reject") }
            Button(T("Clear flag", "清除旗标", "清除旗標")) { document.markPhotos([photo.id], flag: "none") }
        } label: {
            chip(nil, symbol: photo.flag == "pick" ? "flag.fill" : photo.flag == "reject" ? "flag.slash" : "flag")
                .foregroundStyle(["pick", "reject"].contains(photo.flag) ? MobileStyle.accent : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(T("Flag", "旗标", "旗標")).accessibilityIdentifier("photo-detail.flag")
    }

    private func reconcileTile(_ request: TileRequest?) async {
        guard let request, let photo else {
            if canvasDemand?.viewport == nil, galleryTile != nil {
                galleryTile = nil
                await galleryDetailRenderer.clear()
            }
            return
        }
        if let galleryTile, galleryTile.key == request.key,
           Self.tile(galleryTile.tile, satisfies: request.viewport) { return }
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
            guard tileRequest == request else { return }
            let actual = max(Double(result.image.width) / result.rect.width, Double(result.image.height) / result.rect.height)
            guard actual > Double(request.viewport.previewLongEdge) * 1.07 else {
#if DEBUG
                GalleryTileAudit.record("detail unchanged: current \(request.viewport.previewLongEdge) px, available \(Int(actual)) px")
#endif
                return
            }
            galleryTile = (request.key, result)
#if DEBUG
            GalleryTileAudit.record("visible \(result.rect) \(result.image.width)x\(result.image.height), equivalent long edge \(Int(actual)) px")
#endif
        } catch {
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

    private static func tile(_ tile: MobileDetailTile, satisfies viewport: MobileViewport) -> Bool {
        let edge = max(Double(tile.image.width) / tile.rect.width, Double(tile.image.height) / tile.rect.height)
        return tile.rect.contains(viewport.rect) && (tile.nativeSize != nil || edge >= viewport.pixelLongEdge * 0.97)
    }

    private func picture(_ photo: MobilePhoto) -> some View {
        ZStack {
            DetailZoomCanvas(photoID: photo.id, name: photo.name, image: previewID == photo.id ? preview : nil,
                             reduceMotion: reduceMotion, developed: developedPreview,
                             tile: galleryTile?.key == document.libraryPreviewURL(photo) ? galleryTile?.tile : nil,
                             onDemand: { demand in
                if demand.photoID == photoID, canvasDemand != demand {
                    canvasDemand = demand
#if DEBUG
                    GalleryTileAudit.record("fit \(demand.fitEdge) demand \(String(describing: demand.viewport))")
#endif
                }
            }, fitFrame: fittedFrame, neighbors: neighbors,
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

    private func neighbor(_ step: Int) -> MobilePhoto? {
        guard let index = photoIDs.firstIndex(of: photoID) else { return nil }
        var next = index + step
        while photoIDs.indices.contains(next) {
            if let p = document.photos.first(where: { $0.id == photoIDs[next] }) { return p }
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

    private func stripItem(_ photo: MobilePhoto) -> DetailFilmstrip.Item {
        DetailFilmstrip.Item(id: photo.id, name: photo.name, previewURL: document.libraryPreviewURL(photo),
                            sourceURL: document.url(for: photo), version: document.libraryPreviewVersions[photo.id, default: 0])
    }

    private var filmstrip: some View {
        DetailFilmstrip(items: filmstripItems, selection: photoID, reduceMotion: reduceMotion,
                        onScrubbing: { stripScrubbing = $0 }) { id, image in
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
        .padding(.horizontal, EditorDesign.gutter)
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

    private func chip(_ title: String?, symbol: String, wideLabel: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            if let title {
                if wideLabel {
                    ViewThatFits(in: .horizontal) {
                        Text(title).fixedSize(horizontal: true, vertical: false)
                        Text(title).lineLimit(1)
                    }
                    .frame(maxWidth: fitMode.window.width >= 800 ? 240 : 166, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                    Image(systemName: "chevron.down").font(.system(size: 8))
                } else {
                    Text(title).lineLimit(1)
                }
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, wideLabel && title != nil ? 10 : 0).frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .modifier(ChromeSurface(radius: 22, interactive: true))
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

#if DEBUG
@MainActor private enum GalleryTileAudit {
    static func record(_ line: String) {
        // Debug QA keeps a small timing-only trace; never write filenames,
        // identifiers, recipes or image bytes.
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--gallery-tile-audit") || Bundle.main.bundleIdentifier?.hasSuffix(".galleryqa") == true else { return }
        let url = URL.documentsDirectory.appendingPathComponent("gallery-tile-audit.txt")
        let previous = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let time = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
        let output = String(previous.suffix(24_000)) + time + " " + line + "\n"
        try? output.write(to: url, atomically: true, encoding: .utf8)
    }
}
#endif

private struct GalleryCanvasDemand: Equatable {
    let photoID: UUID
    let fitEdge: Int
    let viewport: MobileViewport?
}

private struct DetailZoomCanvas: UIViewRepresentable {
    let photoID: UUID
    let name: String
    let image: CGImage?
    let reduceMotion: Bool
    let developed: Bool
    let tile: MobileDetailTile?
    let onDemand: (GalleryCanvasDemand) -> Void
    let fitFrame: CGRect?
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
        view.update(photoID: photoID, name: name, image: image, developed: developed, fitFrame: fitFrame)
        view.updateTile(tile)
        view.requestBack(backCommand)
    }

    final class ZoomView: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        private let photoView = UIImageView()
        private let tileView = UIImageView()
        private var tile: MobileDetailTile?
        private var demandTask: Task<Void, Never>?
        private var lastScheduledDemand: GalleryCanvasDemand?
        var onDemand: ((GalleryCanvasDemand) -> Void)?
        private var source: CGImage?
        private var photoID: UUID?
        private var lastViewport = CGSize.zero
        private var fitFrame: CGRect?
        private var fitCenter = CGPoint.zero
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

            let single = UITapGestureRecognizer(target: self, action: #selector(singleTap))
            let double = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
            double.numberOfTapsRequired = 2
            single.require(toFail: double)
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

        func update(photoID: UUID, name: String, image: CGImage?, developed: Bool, fitFrame: CGRect?) {
            if self.fitFrame != fitFrame { self.fitFrame = fitFrame; needsFit = true }
            accessibilityLabel = name
            if self.photoID != photoID {
                self.photoID = photoID
                stopDemand()
                updateTile(nil)
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
                let available = fitRectForCurrentWindow()
                fitCenter = CGPoint(x: available.midX, y: available.midY)
                let fit = min(available.width / pixelSize.width, available.height / pixelSize.height)
                let fitted = CGSize(width: pixelSize.width * fit, height: pixelSize.height * fit)
                photoView.frame = CGRect(origin: .zero, size: fitted)
                contentSize = fitted
                setZoomScale(scale, animated: false)
                updateCentering()
                let offset = CGPoint(x: normalized.x * fitted.width * scale - bounds.width / 2,
                                     y: normalized.y * fitted.height * scale - bounds.height / 2)
                if scale <= minimumZoomScale + 0.015 {
                    contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
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
            scheduleEntryIfReady()
            scheduleDemand()
#if DEBUG
            updateGeometryAudit()
#endif
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { source == nil ? nil : photoView }

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
            let normalized: MobileViewport?
            if zoomScale > 1.05 {
                let inPhoto = photoView.convert(bounds, from: self).intersection(b)
                if inPhoto.isNull || inPhoto.isEmpty { normalized = nil }
                else {
                    let rect = CGRect(x: (inPhoto.minX - b.minX) / b.width, y: (inPhoto.minY - b.minY) / b.height,
                                      width: inPhoto.width / b.width, height: inPhoto.height / b.height)
                    let pixels = min(10240, Double(max(b.width, b.height) * zoomScale * displayScale))
                    normalized = MobileViewport(rect: rect, zoom: Double(zoomScale), pixelLongEdge: pixels,
                                                previewLongEdge: max(source.width, source.height))
                }
            } else { normalized = nil }
            let next = GalleryCanvasDemand(photoID: id, fitEdge: edge, viewport: normalized)
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
            let target = CGPoint(x: -contentInset.left, y: -contentInset.top)
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

        private func fitRectForCurrentWindow() -> CGRect {
            let viewport = CGRect(origin: .zero, size: bounds.size)
            guard let window else { return viewport }
            let insets = window.safeAreaInsets
            // Chrome overlays the image. Use a symmetric vertical fit based
            // on hardware insets only, never the visible filmstrip or toolbar.
            let insetY = max(insets.top, insets.bottom, 6)
            let fitHeight = max(1, viewport.height - 2 * insetY)
            if let fitFrame {
                let origin = convert(bounds, to: window).origin
                let local = fitFrame.offsetBy(dx: -origin.x, dy: -origin.y)
                // A rotation can arrive while the toolbar is hidden. Do not
                // apply an old landscape fit rect to a portrait window.
                if viewport.insetBy(dx: -1, dy: -1).contains(local),
                   local.width > viewport.width * 0.60,
                   (viewport.width * 0.33...viewport.width * 0.67).contains(local.midX) {
                    return CGRect(x: local.minX, y: insetY, width: local.width, height: fitHeight)
                }
            }
            return CGRect(x: insets.left + 8, y: insetY,
                          width: max(1, viewport.width - insets.left - insets.right - 16), height: fitHeight)
        }

        private func updateCentering() {
            let rendered = photoView.frame.size
            let x = max(0, bounds.width - rendered.width)
            let y = max(0, bounds.height - rendered.height)
            let leading = min(x, max(0, fitCenter.x - rendered.width / 2))
            let top = min(y, max(0, fitCenter.y - rendered.height / 2))
            let inset = UIEdgeInsets(top: top, left: leading, bottom: y - top, right: x - leading)
            if contentInset != inset { contentInset = inset }
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
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
            if !reduceMotion, entryTarget != nil, gridBackdrop != nil, fitFrame == nil { return }
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
            let fit = fitRectForCurrentWindow().size
            let scale = min(fit.width / max(1, size.width), fit.height / max(1, size.height))
            let fitted = CGSize(width: size.width * scale, height: size.height * scale)
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
