//  EditorWindow.swift — two presentations of the same editor state.
//
//  Modern: a window-wide toolbar and a full-width canvas with a bare photo row. The
//  right parameter rail overlays the canvas; the Film stage turns the bottom
//  strip into the film/paper chooser. The viewport's unobscured rectangle
//  controls Fit placement, but zoomed images are not moved when the panel
//  opens. Traditional: the former three-column layout,
//  with the toolbar in the centre and both rails taking layout width.
//
//  Both layouts use the same Session, panel widths, controls and renderer.
//  Only navigation and placement change; switching never rewrites a recipe.

import SwiftUI
import UniformTypeIdentifiers

struct EditorWindow: View {
    @Bindable var session: Session
    /// Opening the export page's scene. A `Window` scene is addressed by its
    /// id from anywhere with the environment, which is how this window hands
    /// the request on without either of them owning the other.
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // One layout. The window used to switch to a `BrowseView` worklist
        // whenever a folder was open and no frame chosen; that page is gone
        // and the filmstrip is the only list. Opening a folder still develops
        // nothing until a frame is picked — see `Session.unloadSelection()`.
        printLayout
        .background(Theme.ground)
        // Above the browse/print switch, so the buttons are re-placed in
        // either state and the observer outlives every card that can fold.
        // See `TrafficLightAlignment` for why that matters.
        .background(
            TrafficLightAlignment(centreY: session.interfaceLayout == .modern
                                  ? Theme.Metric.modernTopBarHeight / 2
                                  : Theme.Metric.trafficLightCentreY,
                                  leading: Theme.Metric.trafficLightLeading)
                .frame(width: 0, height: 0)
        )
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            Task { @MainActor in
                var urls: [URL] = []
                for p in providers {
                    if let u = try? await p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                       let url = URL(dataRepresentation: u, relativeTo: nil) { urls.append(url) }
                }
                if !urls.isEmpty { session.open(urls: urls) }
            }
            return true
        }
        // The export page is a window of its own (RFC-018 §6): with a
        // per-destination transform the canvas is a Display P3 proof of a
        // different thing, so the two are worth looking at side by side, which
        // a modal sheet over the editor forbids. `showExport` is unchanged and
        // still means "an export was asked for" — it is now consumed here
        // rather than presented, so ⌘E, the editor's menu item and the
        // toolbar's button all keep working without knowing the page moved.
        .onChange(of: session.showExport) { _, wanted in
            guard wanted else { return }
            session.showExport = false
            openWindow(id: ExportWindowID.scene)
        }
    }

    /// The Print state: the four cards, exactly as drawn.
    ///
    /// `session.topCollapsed` is deliberately not read here. The bar is not a
    /// card that folds any more (PRD §1): it is the row that hosts the window
    /// buttons, so it has to be present for the window to have a corner. The
    /// stored property stays for the session's state and for a launch that
    /// reads it back, but no view consults it.
    /// The panels' widths, which are the user's now (PRD: "the collapse tabs
    /// should be non-fixed, and there should be one narrowest and widest for
    /// both").
    ///
    /// `@State` and not on `Session`: a panel width is chrome, and `Session` is
    /// the document — its `uiKey` namespace is for state that has to come back
    /// with a frame. `PanelWidthStore` writes its own keys, so the lifetime
    /// here only has to be the window's, which is what `@State` is.
    @State private var leftWidth = PanelWidthStore(name: "editor.left",
                                                   range: Theme.Metric.leftPanelRange)
    @State private var rightWidth = PanelWidthStore(name: "editor.right",
                                                    range: Theme.Metric.rightPanelRange)
    private var canvasRightOcclusion: CGFloat {
        guard session.interfaceLayout == .modern && !session.rightCollapsed else { return 0 }
        return (session.snapshotPanelWidths ? rightWidth.range.standard : rightWidth.width)
            + Theme.Metric.modernChromeInset * 2
    }
    private var printLayout: some View {
        Group {
            if session.interfaceLayout == .modern { modernLayout }
            else { traditionalLayout }
        }
        .onAppear { updateCanvasOcclusion() }
        .onChange(of: session.interfaceLayout) { _, _ in updateCanvasOcclusion() }
        .onChange(of: session.rightCollapsed) { _, _ in updateCanvasOcclusion() }
        .onChange(of: session.inspectorStage) { _, _ in updateCanvasOcclusion() }
        .onChange(of: session.filmstripCollapsed) { _, _ in updateCanvasOcclusion() }
        .onChange(of: session.snapshotPanelWidths) { _, _ in updateCanvasOcclusion() }
        .onChange(of: rightWidth.width) { _, _ in updateCanvasOcclusion() }
    }

    private var modernLayout: some View {
        ZStack(alignment: .top) {
            workspace
            TopBar(session: session)
                .frame(height: Theme.Metric.modernTopBarHeight)
        }
    }

    private var traditionalLayout: some View {
        HStack(spacing: 0) {
            if !session.leftCollapsed { leftRail(traditional: true) }
            VStack(spacing: 0) {
                TopBar(session: session)
                    .frame(height: Theme.Metric.topBarHeight)
                Hairline()
                centreColumn
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !session.rightCollapsed { rightRail(traditional: true) }
        }
    }

    private func updateCanvasOcclusion() {
        let modern = session.interfaceLayout == .modern
        let stripVisible = modern || !session.filmstripCollapsed
        let stripHeight: CGFloat = session.modernFilmChooserActive ? 92 : 72
        session.setCanvasOcclusion(left: 0, right: canvasRightOcclusion,
                                   top: modern ? Theme.Metric.modernTopBarHeight + Theme.Metric.modernChromeInset : 0,
                                   bottom: modern && stripVisible ? stripHeight + Theme.Metric.modernChromeInset : 0)
    }

    /// The panels are overlays: only the photograph's fitted placement reacts
    /// to their widths. The Metal canvas itself always has the window width.
    private var workspace: some View {
        ZStack {
            centreColumn
            HStack(spacing: 0) {
                // The Modern material catalogue lives in the bottom chooser;
                // the old left rail remains available only in Traditional.
                Spacer(minLength: 0)
                if !session.rightCollapsed { rightRail(traditional: false) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    private func leftRail(traditional: Bool) -> some View {
        LeftPanel(session: session, traditional: traditional)
            .frame(width: session.snapshotPanelWidths ? leftWidth.range.standard : leftWidth.width)
            .overlay(alignment: .trailing) {
                PanelResizeHandle(side: .trailingEdge, range: leftWidth.range, width: $leftWidth.width)
            }
            .overlay(alignment: .trailing) { VerticalHairline().allowsHitTesting(false) }
            .transition(.move(edge: .leading))
    }

    private func rightRail(traditional: Bool) -> some View {
        RightPanel(session: session, traditional: traditional)
            .frame(width: session.snapshotPanelWidths ? rightWidth.range.standard : rightWidth.width)
            .overlay(alignment: .leading) {
                PanelResizeHandle(side: .leadingEdge, range: rightWidth.range, width: $rightWidth.width)
            }
            .overlay(alignment: .leading) {
                if traditional { VerticalHairline().allowsHitTesting(false) }
            }
            .environment(\.colorBalanceWidth,
                         ColorBalanceLayout.interior(panelWidth: rightWidth.width))
            .padding(.top, traditional ? 0 : Theme.Metric.modernTopBarHeight + Theme.Metric.modernChromeInset)
            .padding(.bottom, traditional ? 0 : Theme.Metric.modernChromeInset)
            .padding(.trailing, traditional ? 0 : Theme.Metric.modernChromeInset)
            .transition(.move(edge: .trailing))
    }

    /// Modern keeps the Metal canvas window-sized, with the bottom navigator
    /// over it. Traditional retains the older stacked centre column.
    private var centreColumn: some View {
        Group {
            if session.interfaceLayout == .modern {
                CanvasArea(session: session,
                           obscuredRight: canvasRightOcclusion,
                           topInset: Theme.Metric.modernTopBarHeight + Theme.Metric.modernChromeInset,
                           chromeInset: Theme.Metric.modernChromeInset)
                    .overlay(alignment: .bottom) {
                        Group {
                            if session.modernFilmChooserActive {
                                FilmChoiceStrip(session: session)
                            } else {
                                Filmstrip(session: session, compact: true)
                            }
                        }
                        .frame(height: session.modernFilmChooserActive ? 92 : 72)
                        .padding(.leading, Theme.Metric.modernChromeInset)
                        .padding(.trailing, canvasRightOcclusion == 0 ? Theme.Metric.modernChromeInset : canvasRightOcclusion)
                        .padding(.bottom, Theme.Metric.modernChromeInset)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
            } else {
                VStack(spacing: 0) {
                    CanvasArea(session: session)
                    if !session.filmstripCollapsed {
                        Hairline()
                        Filmstrip(session: session)
                            .frame(height: Theme.Metric.filmstripHeight)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The centre: the Metal view (or, in snapshot mode, an offscreen render of
/// it) with the four collapse tabs on its edges.
struct CanvasArea: View {
    @Bindable var session: Session
    var obscuredLeft: CGFloat = 0
    var obscuredRight: CGFloat = 0
    var topInset: CGFloat = 0
    var chromeInset: CGFloat = CanvasBadges.inset
    @Environment(\.snapshotMode) private var snapshotMode
    @State private var showsMoreInformation = true

    var body: some View {
        ZStack {
            if snapshotMode {
                SnapshotCanvas(session: session)
            } else {
                MetalCanvasView(host: session)
            }
            // Handles, thirds grid and the straighten line. The shader does
            // the dimming; this does the lines, which want to stay crisp.
            if session.tool == .crop && !snapshotMode {
                CropOverlay(session: session)
            } else if FeatureFlags.masks && !snapshotMode && session.selectedMask != nil {
                MaskOverlay(session: session)
            }
            // Above both: the split's handle is a control, and it is the only
            // overlay that takes the mouse.
            //
            // Drawn in snapshot mode too, unlike the other two. The shader
            // puts the split at `ouv.x`, this puts the line at a view point,
            // and the two arithmetics are written in different files — so a
            // capture where the line does not sit on the seam is the only
            // thing that catches them disagreeing.
            CompareOverlay(session: session)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Everything in this stack is positioned in **view coordinates**, and
        // a view coordinate at high zoom is off the canvas: the crop frame's
        // corners, its grips and the mask handles all ran past the canvas edge
        // and were painted over the side panels and the toolbar. SwiftUI does
        // not clip by default; the canvas is the one place that must.
        //
        // Not the Metal view's problem — a `CAMetalLayer` cannot draw outside
        // itself (which is why a zoomed picture looks *cut off* at the canvas
        // edge rather than spilling, and why the crop tool's view is fitted to
        // the picture: `Renderer.fitRotatedPhoto`). This is the overlay half.
        .clipped()
        // **One edge, not three.** The left and right tabs are gone: the
        // drawing folds a rail with the `sidebar.left` / `sidebar.right`
        // button in that rail's own header, and a second control that does
        // the same thing is a control that will disagree with the first about
        // being there. The bottom one is untouched — "except the bottom
        // gallery view remains unchanged" — and is still the pill that
        // appears when the pointer comes near the canvas's lower edge.
        .overlay(alignment: .bottom) {
            if session.interfaceLayout == .traditional {
                HoverEdgeTab(edge: .bottom, collapsed: $session.filmstripCollapsed)
            }
        }
        .overlay {
            if session.interfaceLayout == .modern && session.frames.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(Theme.Ink.secondary)
                    Text(T("Open photos to start editing", "打开照片开始编辑"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.Ink.primary)
                    Text(L(.statusEmptyFilmstrip))
                        .font(Theme.Font.label)
                        .foregroundStyle(Theme.Ink.secondary)
                        .multilineTextAlignment(.center)
                    Button(T("Open Photos", "打开照片")) { session.openPanel() }
                        .buttonStyle(.primarySurface)
                        .padding(.top, 4)
                }
                .frame(maxWidth: 420)
                .padding(24)
            }
        }
        .overlay(alignment: .topLeading) {
            if session.interfaceLayout == .modern {
                VStack(alignment: .leading, spacing: 8) {
                    CanvasHistogram(session: session)
                    if !modernCanvasInformation.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Button {
                                withAnimation(.easeOut(duration: 0.16)) {
                                    showsMoreInformation.toggle()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(T("More Information", "更多信息"))
                                    Image(systemName: showsMoreInformation ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 9, weight: .medium))
                                }
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Ink.secondary)
                            }
                            .buttonStyle(.plain)
                            if showsMoreInformation {
                                ForEach(modernCanvasInformation, id: \.self) { information in
                                    Text(information)
                                        .font(Theme.Font.caption)
                                        .foregroundStyle(Theme.Ink.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .padding(.leading, 12)
                        .frame(maxWidth: 220, alignment: .leading)
                    }
                }
                .padding(.leading, obscuredLeft + chromeInset)
                .padding(.top, topInset)
            } else if session.histogram.contains(where: { $0 > 0 }) {
                CanvasHistogram(session: session)
                    .padding(.leading, obscuredLeft + chromeInset)
                    .padding(.top, CanvasBadges.inset)
            }
        }
        .overlay(alignment: .topTrailing) {
            if session.interfaceLayout == .traditional {
                VStack(alignment: .trailing, spacing: CanvasBadges.spacing) {
                    ForEach(session.canvasBadges, id: \.self) { badge($0) }
                }
                .padding(.trailing, obscuredRight + chromeInset)
                .padding(.top, CanvasBadges.inset)
            }
        }
        // Contract §2's "a visible error rather than a blank canvas". Centred
        // and opaque, not a corner badge: the app is not going to render, and
        // a caption the user has to go looking for would leave them staring at
        // an empty canvas deciding the app is broken — which it is, but not in
        // a way they can act on without being told.
        .overlay {
            if let why = session.serviceBlocked {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Theme.accent)
                    Text("The render service cannot be used")
                        .font(Theme.Font.sectionTitle).foregroundStyle(Theme.text)
                    Text(why)
                        .font(Theme.Font.caption).foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center).frame(maxWidth: 380)
                    Button("Restart the render service") { session.restartService() }
                        .buttonStyle(.plain).font(Theme.Font.caption).foregroundStyle(Theme.accent)
                        .padding(.top, 2)
                }
                .padding(20)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 8)
            }
        }
        .overlay(alignment: .bottomLeading) {
            // Traditional retains its canvas status. Modern keeps task state
            // under the filename, leaving the photograph and navigator clear.
            if session.interfaceLayout == .traditional {
                VStack(alignment: .leading, spacing: 4) {
                    if let w = session.stockWarning {
                        Text(w).font(Theme.Font.caption).foregroundStyle(Theme.text)
                            .lineLimit(2).frame(maxWidth: 360, alignment: .leading)
                    }
                    HStack(spacing: 8) {
                        if session.working {
                            ProgressView().controlSize(.small).scaleEffect(0.7)
                        }
                        Text(session.working
                             ? String(format: "%@ · %.1f s", session.status, session.workSeconds)
                             : session.status)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        if !session.serviceReady, session.selection != nil {
                            Button(L(.actionRestart)) { session.restartService() }
                                .buttonStyle(.plain)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.accent)
                                .help("The render service is not running. Start it again.")
                        }
                    }
                }
                .padding(.leading, obscuredLeft + chromeInset)
                .padding(.bottom, CanvasBadges.inset)
                .shadow(color: Theme.overlayInkShadow, radius: 1)
            }
        }
    }

    private var modernCanvasInformation: [String] {
        session.canvasBadges.filter { $0 != "full" && $0 != "full resolution…" }
    }

    private func badge(_ text: String) -> some View {
        // No plate either (§2.9): the ink and its shadow are the badge.
        Text(text).font(Theme.Font.caption).foregroundStyle(Theme.text)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .shadow(color: Theme.overlayInkShadow, radius: 1)
    }
}

/// The histogram is a read-only instrument painted **on** the photograph, not
/// a panel that floated over it.
///
/// It used to be a card: `.black.opacity(0.58)` inside a rounded rectangle
/// with 10 pt of padding, plus the section title and a button. Three things
/// were wrong with that. A plate that dark is a hole in the picture; a title
/// is a label on an instrument whose shape already says what it is; and a
/// one-shot action button does not belong on the canvas at all (UI-SPEC
/// §1.3). The button moved to the Frame menu.
///
/// Modern gives the plot the same floating glass surface and inset as the
/// other canvas controls. Traditional keeps the original soft scrim.
private struct CanvasHistogram: View {
    @Bindable var session: Session

    var body: some View {
        Group {
            if session.interfaceLayout == .modern {
                plot.padding(12)
                    .modifier(EditorChromeSurface(modern: true))
            } else {
                plot.background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.overlayScrim)
                        .blur(radius: 7)
                        .padding(-7)
                }
            }
        }
    }

    private var plot: some View {
        HistogramPlot(bins: session.histogram, channels: [.rgb],
                      showGrid: false, background: .clear)
            .frame(width: 196, height: 54)
            .shadow(color: Theme.overlayInkShadow, radius: 1)
    }
}

/// Snapshot stand-in: the renderer draws offscreen into an image at the
/// canvas's real size, so a capture shows the real render path.
///
/// It takes over `Renderer.needsDraw`, which in the running app is the
/// `MTKView`'s `scheduleDraw`. That is the whole point: the previous version
/// re-rendered on a hand-written list of properties — `previewSoft`,
/// `histogram`, `zoomPercent`, `detailTier`, `detailPending` — and so was
/// blind to every state that invalidates the canvas without touching one of
/// them. Masks were the case that found it: `--mask` captured an image with
/// no mask in it, and the feature was fine. Anything the renderer considers a
/// reason to redraw is now a reason to re-capture, with no list to maintain.
struct SnapshotCanvas: View {
    @Bindable var session: Session
    @State private var image: CGImage?
    @State private var revision = 0
    @State private var rendering = false

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image { Image(decorative: image, scale: 2).resizable() } else { Theme.ground }
            }
            .onAppear { session.renderer.needsDraw = { revision &+= 1 } }
            .onChange(of: geo.size, initial: true) { _, size in render(size) }
            .onChange(of: revision) { _, _ in render(geo.size) }
        }
    }

    private func render(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        // A render can invalidate the canvas again (the detail tier swaps a
        // texture in), and that arrives here as another revision. One level
        // is enough; re-entering would be a loop.
        guard !rendering else { return }
        rendering = true
        defer { rendering = false }
        session.renderer.viewport.backingScale = 2
        session.renderer.viewport.resize(viewport: size)
        session.viewportChanged()
        image = session.renderer.renderOffscreen(size: size, backingScale: 2)?.makeCGImage()
    }
}

private struct SnapshotModeKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var snapshotMode: Bool { get { self[SnapshotModeKey.self] } set { self[SnapshotModeKey.self] = newValue } }
}

/// The window's drag handle. `.windowStyle(.hiddenTitleBar)` removes the
/// titlebar a window is normally dragged by, and the strip reserved for the
/// traffic lights is SwiftUI content, which would otherwise eat the gesture.
/// `performDrag` hands it to the window server the way the real titlebar does.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: event) }
        }
    }
}
