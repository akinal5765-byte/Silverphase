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
    let onBack: () -> Void
    let onEdit: (MobilePhoto) -> Void
    let onExport: (MobilePhoto) -> Void
    let onInfo: (MobilePhoto) -> Void
    let onCopy: (MobilePhoto) -> Void
    let onDelete: (MobilePhoto) -> Void

    @State private var renderer = MobileEngine()
    @State private var preview: CGImage?
    @State private var previewLoading = true
    @State private var previewID: UUID?
    @State private var developedPreview = false
    @State private var showingFilm = false
    @State private var hinge: HingeReading = .pending
    @State private var windowSize: CGSize = .zero
    @State private var chromeVisible = true
    @State private var stableFit: FitSample?
    @State private var recentRenditions: [(key: URL, image: CGImage)] = []
    private static let ratingsBand: CGFloat = 52
    private static let stripBand: CGFloat = 58
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

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

    private var photo: MobilePhoto? { document.photos.first { $0.id == photoID } }
    private var strip: [MobilePhoto] {
        let index = photoIDs.firstIndex(of: photoID) ?? 0
        guard !photoIDs.isEmpty else { return [] }
        let indexed = Dictionary(uniqueKeysWithValues: document.photos.map { ($0.id, $0) })
        return photoIDs[max(0, index - 16)...min(photoIDs.count - 1, index + 16)].compactMap { indexed[$0] }
    }

    var body: some View {
        NavigationStack {
            if let photo {
                content(photo)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { navigationItems(photo) }
                    .toolbar(chromeVisible ? .visible : .hidden, for: .navigationBar)
                    .toolbar(chromeVisible && placement != .top ? .visible : .hidden, for: .bottomBar)
                    .toolbarBackground(.hidden, for: .navigationBar, .bottomBar)
                    .modifier(DetailToolbarAxis(usesTop: placement == .top))
            } else {
                Button(T("Back to Library", "返回图库", "返回圖庫"), action: onBack)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .tint(.primary)
        .background(MobileStyle.canvas.ignoresSafeArea())
        .task(id: photo.map { document.libraryPreviewURL($0) }) {
            if previewID != photoID { preview = nil; previewID = nil }
            developedPreview = false
            previewLoading = true
            defer { if !Task.isCancelled { previewLoading = false } }
            guard let photo else { return }
            let cached = document.libraryPreviewURL(photo)
            if let ready = recentRenditions.first(where: { $0.key == cached }) {
                preview = ready.image; previewID = photo.id; developedPreview = true
                return
            }
            let warm = await Self.loadPreview(cached, limit: 384)
            guard !Task.isCancelled else { return }
            if let warm { preview = warm; previewID = photo.id }
            else if preview == nil {
                let original = await Self.loadPreview(document.url(for: photo), limit: 960)
                guard !Task.isCancelled else { return }
                preview = original; previewID = photo.id
            }
            // Rapid swipes get a first frame immediately, without queueing
            // a full render for each photograph the user passes over.
            do {
                try await Task.sleep(for: .milliseconds(170))
                let renderEngine = renderer
                let result = try await withTaskCancellationHandler {
                    try await document.renderLibraryDetail(photo, using: renderEngine)
                } onCancel: {
                    renderEngine.workGate.cancel()
                }
                try Task.checkCancellation()
                recentRenditions.removeAll { $0.key == cached }
                recentRenditions.insert((cached, result), at: 0)
                if recentRenditions.count > 2 { recentRenditions.removeLast() }
                preview = result; previewID = photo.id; developedPreview = true
            } catch { /* Keep the best already available rendition. */ }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            recentRenditions.removeAll()
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
                x: safeFrame.minX + EditorDesign.gutter, y: safeFrame.minY + Self.ratingsBand,
                width: max(1, safeFrame.width - 2 * EditorDesign.gutter),
                height: max(1, safeFrame.height - Self.ratingsBand - Self.stripBand)))
            ZStack {
                // Like the editor, the canvas bleeds to the window edges.
                // Its framed-to-fit pose is a separate, stable safe rectangle.
                picture(photo).ignoresSafeArea(.container, edges: .all)
                VStack(spacing: 0) {
                    metadata(photo)
                        .frame(height: Self.ratingsBand)
                    Spacer(minLength: 0)
                    filmstrip
                        .frame(height: Self.stripBand)
                }
                .opacity(chromeVisible ? 1 : 0)
                .allowsHitTesting(chromeVisible)
                .accessibilityHidden(!chromeVisible)
            }
            .frame(width: safe.size.width, height: safe.size.height)
            .task(id: chromeVisible ? sample : nil) {
                // Chrome visibility is not a layout version. Reopening it
                // cannot overwrite the fit rectangle in the same posture.
                guard chromeVisible, stableFit?.mode != sample.mode else { return }
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
        HStack(spacing: EditorDesign.gutter) {
            rating(photo)
            flag(photo)
            Button { showingFilm = true } label: {
                let id = photo.recipe["film_stock"]?.stringValue ?? MobileProcessContract.defaults["film_stock"]?.stringValue
                chip(id.flatMap { StockCatalog.shared.stock($0)?.displayName }, symbol: "film")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(T("Choose Film", "切换胶片", "切換膠片"))
            .accessibilityIdentifier("photo-detail.film")
        }
        .padding(.horizontal, EditorDesign.gutter)
        .modifier(WorkspaceGlassGroup())
    }

    @ToolbarContentBuilder
    private func navigationItems(_ photo: MobilePhoto) -> some ToolbarContent {
        if #available(iOS 27.1, *), placement == .systemSide {
            backItem.axisBehavior(.horizontalOnly)
        } else {
            backItem
        }
        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text(photo.libraryDate?.formatted(date: .abbreviated, time: .omitted) ?? photo.name)
                    .font(.subheadline.weight(.semibold)).lineLimit(1)
                if let date = photo.libraryDate {
                    Text(date.formatted(date: .omitted, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }.accessibilityElement(children: .combine)
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

    private var backItem: ToolbarItem<String, some View> {
        ToolbarItem(id: "photo-detail.native-back", placement: .topBarLeading) {
            tool(T("Back to Library", "返回图库", "返回圖庫"), "chevron.left", id: "photo-detail.back", action: onBack)
        }
    }

    private static nonisolated func loadPreview(_ url: URL, limit: Int) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                          kCGImageSourceCreateThumbnailWithTransform: true,
                                          kCGImageSourceThumbnailMaxPixelSize: limit]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
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
        .accessibilityLabel(T("Flag", "旗标", "旗標")).accessibilityIdentifier("photo-detail.flag")
    }

    private func picture(_ photo: MobilePhoto) -> some View {
        ZStack {
            DetailZoomCanvas(photoID: photo.id, name: photo.name, image: previewID == photo.id ? preview : nil,
                             reduceMotion: reduceMotion, developed: developedPreview,
                             fitFrame: fittedFrame, onPage: page, onTap: {
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

    private func page(_ step: Int) {
        guard let index = photoIDs.firstIndex(of: photoID) else { return }
        var next = index + step
        while photoIDs.indices.contains(next) {
            let id = photoIDs[next]
            if document.photos.contains(where: { $0.id == id }) {
                photoID = id
                return
            }
            next += step
        }
    }

    private var filmstrip: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 5) {
                    ForEach(strip) { item in
                        Button { photoID = item.id } label: {
                            let cached = document.libraryPreviewURL(item)
                            FilmstripThumbnail(url: FileManager.default.fileExists(atPath: cached.path) ? cached : document.url(for: item),
                                               fillsFrame: true, version: document.libraryPreviewVersions[item.id, default: 0])
                                .frame(width: 40, height: 44)
                                .clipShape(.rect(cornerRadius: 5))
                                .overlay { if item.id == photoID { RoundedRectangle(cornerRadius: 5).strokeBorder(MobileStyle.accent, lineWidth: 2) } }
                        }.buttonStyle(.plain).id(item.id).accessibilityLabel(item.name)
                    }
                }.padding(.horizontal, 12)
            }.scrollIndicators(.hidden)
                .onChange(of: photoID, initial: true) { _, id in
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.24)) { reader.scrollTo(id, anchor: .center) }
                }
        }.frame(height: 48)
            .frame(maxWidth: min(560, CGFloat(strip.count) * 45 + 20))
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

    private func chip(_ title: String?, symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            if let title { Text(title).lineLimit(1) }
            Image(systemName: "chevron.down").font(.system(size: 8))
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 12).frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .modifier(ChromeSurface(radius: 22, interactive: true))
    }
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
private struct DetailZoomCanvas: UIViewRepresentable {
    let photoID: UUID
    let name: String
    let image: CGImage?
    let reduceMotion: Bool
    let developed: Bool
    let fitFrame: CGRect?
    let onPage: (Int) -> Void
    let onTap: () -> Void

    func makeUIView(context: Context) -> ZoomView { ZoomView() }

    func updateUIView(_ view: ZoomView, context: Context) {
        view.onPage = onPage; view.onTap = onTap; view.reduceMotion = reduceMotion
        view.update(photoID: photoID, name: name, image: image, developed: developed, fitFrame: fitFrame)
    }

    final class ZoomView: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        private let photoView = UIImageView()
        private var source: CGImage?
        private var photoID: UUID?
        private var lastViewport = CGSize.zero
        private var fitFrame: CGRect?
        private var fitCenter = CGPoint.zero
        private var needsFit = false
        private var animatesNextPhoto = false
        private var settingGeometry = false
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
            backgroundColor = .clear
            clipsToBounds = true
            // Its frame is already aspect-correct. A second aspect fit in
            // UIImageView can leave a one-pixel gutter from fractional points.
            photoView.contentMode = .scaleToFill
            photoView.layer.edgeAntialiasingMask = []
            photoView.layer.allowsEdgeAntialiasing = false
            addSubview(photoView)

            let single = UITapGestureRecognizer(target: self, action: #selector(singleTap))
            let double = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
            double.numberOfTapsRequired = 2
            single.require(toFail: double)
            addGestureRecognizer(single)
            addGestureRecognizer(double)
            for direction: UISwipeGestureRecognizer.Direction in [.left, .right] {
                let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swipePhoto(_:)))
                swipe.direction = direction
                swipe.delegate = self
                addGestureRecognizer(swipe)
                panGestureRecognizer.require(toFail: swipe)
            }

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
                let hadPhoto = self.photoID != nil
                self.photoID = photoID
                setZoomScale(1, animated: false)
                source = nil
                photoView.image = nil
                photoView.layer.removeAllAnimations()
                animatesNextPhoto = hadPhoto
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
                if animatesNextPhoto, !reduceMotion {
                    let fade = CABasicAnimation(keyPath: "opacity")
                    fade.fromValue = 0.15; fade.toValue = 1; fade.duration = 0.21
                    fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    photoView.layer.add(fade, forKey: "detail.page-fade")
                }
                animatesNextPhoto = false
            }
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--photo-detail-resolution-audit") {
                let pixels = image.map { max($0.width, $0.height) } ?? 0
                accessibilityValue = "\(developed ? "developed" : "initial")-\(pixels)"
            }
#endif
            if needsFit { setNeedsLayout() }
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
            }
#if DEBUG
            updateGeometryAudit()
#endif
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { source == nil ? nil : photoView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard !settingGeometry else { return }
            updateCentering()
            updateZoomState()
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            updateZoomState()
        }

        private func updateZoomState() {
            // Pan only as a zoomed photo. A one-finger swipe at fit advances
            // the gallery; a two-finger pinch never turns into a page switch.
            let allowPan = !isFitted
            if panGestureRecognizer.isEnabled != allowPan { panGestureRecognizer.isEnabled = allowPan }
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--photo-detail-resolution-audit") { return }
#endif
            let value = "\(Int((zoomScale * 100).rounded()))%"
            if accessibilityValue != value { accessibilityValue = value }
#if DEBUG
            updateGeometryAudit()
#endif
        }

#if DEBUG
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
            if let fitFrame {
                let origin = convert(bounds, to: window).origin
                let local = fitFrame.offsetBy(dx: -origin.x, dy: -origin.y)
                // A rotation can arrive while the toolbar is hidden. Do not
                // apply an old landscape fit rect to a portrait window.
                if viewport.contains(local) { return local }
            }
            let insets = window.safeAreaInsets
            return CGRect(x: insets.left + 8, y: insets.top + 52,
                          width: max(1, viewport.width - insets.left - insets.right - 16),
                          height: max(1, viewport.height - insets.top - insets.bottom - 110))
        }

        private func updateCentering() {
            let x = max(0, bounds.width - contentSize.width)
            let y = max(0, bounds.height - contentSize.height)
            let leading = min(x, max(0, fitCenter.x - contentSize.width / 2))
            let top = min(y, max(0, fitCenter.y - contentSize.height / 2))
            let inset = UIEdgeInsets(top: top, left: leading, bottom: y - top, right: x - leading)
            if contentInset != inset { contentInset = inset }
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer is UISwipeGestureRecognizer { return isFitted && !isZooming && !isZoomAnimating }
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }

        @objc private func swipePhoto(_ gesture: UISwipeGestureRecognizer) {
            guard isFitted, !isZooming, !isZoomAnimating else { return }
            onPage?(gesture.direction == .left ? 1 : -1)
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
