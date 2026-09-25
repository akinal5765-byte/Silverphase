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
    @State private var modernProofRecipe: ExportRecipe?
    @State private var modernProof: SoftProof?

    private struct ModernProofRequest: Hashable {
        var frame: URL?
        var recipe: ExportRecipe?
    }

    private var modernProofRequest: ModernProofRequest {
        ModernProofRequest(frame: session.selection,
                           recipe: modernProofRecipe)
    }

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
            TrafficLightAlignment(centreY: Theme.Metric.modernTopBarHeight / 2,
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
        // The export page is this window's right-hand inspector (), so `⌘E`
        // toggles a rail rather than opening a scene. `ExportWindow` and its
        // scene are kept only for the standalone capture and for anyone with
        // the old window in their Window menu.
        .onChange(of: session.showExport) { _, wanted in
            if !wanted { modernProofRecipe = nil }
        }
        .task(id: modernProofRequest) {
            let request = modernProofRequest
            modernProof = nil
            guard let recipe = request.recipe, request.frame != nil else { return }
            let made = await session.softProofForDisplay(
                recipe: recipe, paneSize: session.viewportSnapshot.viewport)
            guard !Task.isCancelled, request == modernProofRequest else { return }
            modernProof = made
        }
        .onChange(of: session.params) { _, _ in
            // A proof is a snapshot of a particular development. Never leave
            // old output pixels on screen after a parameter edit.
            modernProofRecipe = nil
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
    /// How much of the canvas's right-hand side a floating surface covers:
    /// the inspector **plus one gutter** — the same gutter the canvas keeps at
    /// its own trailing edge. The panel is already inset by that gutter, so
    /// adding it twice here (as the old `width + inset * 2` did) left a 24 pt
    /// hole between the photograph and the inspector, while the strip below
    /// kept 12.
    private var canvasRightOcclusion: CGFloat {
        let panel = session.showExport
            ? Theme.Metric.modernExportPanelWidth : Theme.Metric.modernPanelWidth
        guard session.showExport || !session.rightCollapsed else { return 0 }
        return panel + Theme.Metric.modernSurfaceGutter
    }
    private var printLayout: some View {
        modernLayout
        .onAppear { updateCanvasOcclusion() }
        .onChange(of: session.rightCollapsed) { _, _ in updateCanvasOcclusion() }
        .onChange(of: session.showExport) { _, _ in updateCanvasOcclusion() }
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

    private func updateCanvasOcclusion() {
        let stripHeight: CGFloat = session.modernFilmChooserActive
            ? Theme.Metric.modernFilmChooserHeight : Theme.Metric.modernStripHeight
        session.setCanvasOcclusion(
            left: 0, right: canvasRightOcclusion,
            top: Theme.Metric.modernTopBarHeight + Theme.Metric.modernSurfaceGutter,
            bottom: stripHeight + Theme.Metric.modernSurfaceGutter)
    }

    /// The panels are overlays: only the photograph's fitted placement reacts
    /// to their widths. The Metal canvas itself always has the window width.
    private var workspace: some View {
        ZStack {
            centreColumn
            HStack(spacing: 0) {
                // The material catalogue lives in the bottom chooser, so the
                // window has one rail: the inspector, or the export page.
                Spacer(minLength: 0)
                if session.showExport { modernExportRail }
                else if !session.rightCollapsed { inspectorRail }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    /// The one rail. It floats over the canvas at a fixed width, so only the
    /// photograph's fitted placement reacts to it — never the Metal view.
    private var inspectorRail: some View {
        let panelWidth = Theme.Metric.modernPanelWidth
        return RightPanel(session: session)
            .frame(width: panelWidth)
            .environment(\.colorBalanceWidth,
                         ColorBalanceLayout.interior(panelWidth: panelWidth))
            .padding(.top, Theme.Metric.modernTopBarHeight + Theme.Metric.modernSurfaceGutter)
            .padding(.bottom, Theme.Metric.modernSurfaceGutter)
            .padding(.trailing, Theme.Metric.modernSurfaceGutter)
            .transition(.move(edge: .trailing))
    }

    private var modernExportRail: some View {
        ExportPage(session: session, compact: true,
                   editorProofRecipe: $modernProofRecipe)
            .frame(width: Theme.Metric.modernExportPanelWidth)
            .padding(.top, Theme.Metric.modernTopBarHeight + Theme.Metric.modernSurfaceGutter)
            .padding(.bottom, Theme.Metric.modernSurfaceGutter)
            .padding(.trailing, Theme.Metric.modernSurfaceGutter)
            .transition(.move(edge: .trailing))
    }

    /// The Metal canvas is **window-sized**: the rails float over it, so the
    /// photograph is never squeezed into a column and the viewport's
    /// unobscured rectangle is what Fit placements respect.
    private var centreColumn: some View {
        CanvasArea(session: session,
                   obscuredRight: canvasRightOcclusion,
                   topInset: Theme.Metric.modernTopBarHeight + Theme.Metric.modernSurfaceGutter,
                   chromeInset: Theme.Metric.modernSurfaceGutter,
                   outputProof: modernProof,
                   outputProofRequested: modernProofRecipe != nil,
                   onHideOutputProof: { modernProofRecipe = nil })
            .overlay(alignment: .bottom) {
                        Group {
                            if session.modernFilmChooserActive {
                                FilmChoiceStrip(session: session)
                            } else {
                                Filmstrip(session: session, compact: true)
                            }
                        }
                        .frame(height: session.modernFilmChooserActive
                               ? Theme.Metric.modernFilmChooserHeight
                               : Theme.Metric.modernStripHeight)
                        // **One gutter at the canvas's leading edge, and one
                        // at the inspector's.** The strip used to be padded
                        // clear of the whole panel on the right and carry its
                        // own 20 pt inset on the left, so its first
                        // photograph sat 32 pt in while the histogram plate
                        // above it sat at 12 — two left edges on one canvas,
                        // which is what the user saw. The plate's edge and the
                        // photograph's edge are the same edge; the panel's
                        // edge is the other one.
                        .padding(.leading, Theme.Metric.modernSurfaceGutter)
                        .padding(.trailing, max(Theme.Metric.modernSurfaceGutter,
                                                canvasRightOcclusion + Theme.Metric.modernSurfaceGutter))
                        .padding(.bottom, Theme.Metric.modernSurfaceGutter)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
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
    var chromeInset: CGFloat = Theme.Metric.modernSurfaceGutter
    var outputProof: SoftProof? = nil
    var outputProofRequested = false
    var onHideOutputProof: (() -> Void)? = nil
    @Environment(\.snapshotMode) private var snapshotMode
    @State private var showsMoreInformation = true
    private var showingBatchGrid: Bool { session.modernBatchGridActive && !outputProofRequested }

    var body: some View {
        ZStack {
            if snapshotMode {
                SnapshotCanvas(session: session)
            } else {
                MetalCanvasView(host: session)
            }
            if showingBatchGrid {
                GeometryReader { geometry in
                    let width = max(geometry.size.width - obscuredRight - chromeInset * 2, 1)
                    let height = max(geometry.size.height - topInset
                                     - Theme.Metric.modernStripHeight - chromeInset, 1)
                    SelectedFramesGrid(session: session)
                        .frame(width: width, height: height)
                        .position(x: chromeInset + width / 2,
                                  y: topInset + height / 2)
                }
                .background(Theme.ground)
            }
            if outputProofRequested, let outputProof {
                GeometryReader { geometry in
                    let bottomInset = (session.modernFilmChooserActive
                                       ? Theme.Metric.modernFilmChooserHeight
                                       : Theme.Metric.modernStripHeight) + chromeInset
                    let usableWidth = max(geometry.size.width - obscuredRight - chromeInset * 2, 1)
                    let usableHeight = max(geometry.size.height - topInset - bottomInset, 1)
                    ZStack(alignment: .topLeading) {
                        Theme.ground
                        Image(decorative: outputProof.displayImage, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: usableWidth, height: usableHeight)
                            .position(x: (geometry.size.width - obscuredRight) / 2,
                                      y: topInset + usableHeight / 2)
                    }
                }
                .allowsHitTesting(false)
            }
            // Handles, thirds grid and the straighten line. The shader does
            // the dimming; this does the lines, which want to stay crisp.
            if !outputProofRequested && !showingBatchGrid && session.tool == .crop && !snapshotMode {
                CropOverlay(session: session)
            } else if !outputProofRequested && !showingBatchGrid && FeatureFlags.masks && !snapshotMode && session.selectedMask != nil {
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
            if !outputProofRequested && !showingBatchGrid { CompareOverlay(session: session) }
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
        }
        .overlay {
            if session.frames.isEmpty {
                VStack(spacing: Theme.Metric.space12) {
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
                        .padding(.top, Theme.Metric.space4)
                }
                .frame(maxWidth: 420)
                .padding(Theme.Metric.space20)
            }
        }
        .overlay(alignment: .topLeading) {
            if !outputProofRequested && !showingBatchGrid {
                VStack(alignment: .leading, spacing: Theme.Metric.space8) {
                    // **Nothing on the canvas until there is a picture to
                    // measure.** A Modern histogram is a glass plate over the
                    // photograph, and with no frame open it drew an empty
                    // rounded rectangle in the corner — a control-shaped mark
                    // that said "loading" about a state that is simply empty.
                    if session.selection != nil, session.histogram.contains(where: { $0 > 0 }) {
                        CanvasHistogram(session: session)
                    }
                    if !modernCanvasInformation.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Metric.space4) {
                            Button {
                                withAnimation(.easeOut(duration: 0.16)) {
                                    showsMoreInformation.toggle()
                                }
                            } label: {
                                HStack(spacing: Theme.Metric.space4) {
                                    Text(T("More Information", "更多信息"))
                                    Image(systemName: showsMoreInformation ? "chevron.up" : "chevron.down")
                                        .font(.system(size: Theme.Metric.modernRowGlyph, weight: .medium))
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
                        .padding(.leading, Theme.Metric.space12)
                        .frame(maxWidth: 220, alignment: .leading)
                    }
                }
                .padding(.leading, obscuredLeft + chromeInset)
                .padding(.top, topInset)
            }
        }
        .overlay(alignment: .top) {
            if outputProofRequested {
                HStack(spacing: Theme.Metric.space8) {
                    if outputProof == nil { ProgressView().controlSize(.mini) }
                    Text(outputProof.map { T("Output Proof · \($0.targetName)", "输出软打样 · \($0.targetName)") }
                         ?? T("Preparing output proof…", "正在生成输出软打样…"))
                        .font(Theme.Font.caption)
                    Button { onHideOutputProof?() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: Theme.Metric.modernRowGlyph, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help(T("Return to editing", "返回编辑"))
                }
                .foregroundStyle(Theme.Ink.primary)
                .padding(.horizontal, Theme.Metric.space12)
                .padding(.vertical, Theme.Metric.space8)
                .modifier(EditorChromeSurface())
                .padding(.top, topInset)
            }
        }
        // Contract §2's "a visible error rather than a blank canvas". Centred
        // and opaque, not a corner badge: the app is not going to render, and
        // a caption the user has to go looking for would leave them staring at
        // an empty canvas deciding the app is broken — which it is, but not in
        // a way they can act on without being told.
        .overlay {
            if let why = session.serviceBlocked {
                VStack(spacing: Theme.Metric.space8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Theme.accent)
                    Text(T("The render service cannot be used", "渲染服务不可用"))
                        .font(Theme.Font.sectionTitle).foregroundStyle(Theme.text)
                    Text(why)
                        .font(Theme.Font.caption).foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center).frame(maxWidth: 380)
                    Button(T("Restart the render service", "重启渲染服务")) { session.restartService() }
                        .buttonStyle(.plain).font(Theme.Font.caption).foregroundStyle(Theme.accent)
                        .padding(.top, Theme.Metric.space2)
                }
                .padding(Theme.Metric.space20)
                .background(Theme.card,
                            in: RoundedRectangle(cornerRadius: Theme.Metric.modernContainerRadius,
                                                 style: .continuous))
                .shadow(color: Theme.overlayInkShadow, radius: Theme.Metric.space8)
            }
        }
    }

    private var modernCanvasInformation: [String] {
        session.canvasBadges.filter { $0 != "full" && $0 != "full resolution…" }
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
/// The plot wears the same floating glass surface and inset as the other
/// canvas controls, so the plate on the photograph is the same plate.
private struct CanvasHistogram: View {
    @Bindable var session: Session

    var body: some View {
        plot.padding(Theme.Metric.modernPlotInset)
            .modifier(EditorChromeSurface())
    }

    private var plot: some View {
        HistogramPlot(bins: session.histogram, channels: [.rgb],
                      showGrid: false, background: .clear)
            .frame(width: Theme.Metric.modernPlot.width, height: Theme.Metric.modernPlot.height)
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
