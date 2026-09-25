//  ExportPage.swift — the export page: the recipe on the left, the picture it
//  will write in the middle, the worklist down the right.
//
//  It replaces a 590 pt sheet whose own header argued that the image could be
//  left out, "because the canvas behind this sheet is already showing the
//  frame at the grade being exported". RFC-018 §2.5 retires that: the app now
//  converts once, at the end, per destination, so the canvas is a proof of the
//  *working* space and nothing more — and the recipes most likely to differ
//  from it are exactly the ones a person cannot check by looking at the canvas. So the
//  centre pane is the point of this page, and it is a soft proof
//  (`Export/SoftProof.swift`) rather than a second copy of the canvas.
//
//  **The layout is `reference_layout/Export_Page/export_page.svg`** — read as
//  a document: the numbers it is drawn with come from its markup rather than
//  from a render of it, which is why they are halves of its own (its window is
//  2981.27 units wide and its artboard is at 2×, the same scale the editor's
//  tokens were measured at — three of them land on the drawing exactly). Its
//  `notes.md` remains the authority on *behaviour*, and the two are cited
//  where they disagree.
//
//  The style is the rest of the app's: `PanelSection` headers, `Well` grounds,
//  `PillMenu` pills, `ScrubSlider` and `Theme` tokens. This page's drawing has
//  tighter rows, a heavier face and its own orange, so it passes those three
//  through `SectionMetrics`, `SliderMetrics` and its own accent token rather
//  than restyling the shared controls.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ExportPage: View {
    @Bindable var session: Session
    /// Modern presents only the recipe controls from the editor's toolbar.
    /// Traditional keeps the full three-column export window.
    var compact = false
    var editorProofRecipe: Binding<ExportRecipe?>? = nil
    /// Which mode to open in. Only the snapshot harness passes anything but
    /// the default: `--export-grid` is how the Grid half of the mode
    /// transition gets looked at, and a transition only ever exercised in one
    /// direction is the one that is broken.
    var startIn: Mode = .viewer
    @State private var store = ExportRecipeStore()

    /// Which of the two modes the centre is in (`notes.md`: "There are two
    /// modes").
    @State private var mode: Mode = .viewer
    /// The settings card folds away to the left, which is what the tab on its
    /// trailing edge in the drawing is for. Persisted like the editor's own
    /// collapse flags (`Session.leftCollapsed` and friends), so a card someone
    /// folded stays folded — and so a capture can reach the folded state
    /// without a pointer.
    @AppStorage(Session.uiKey + "exportSettingsCollapsed") private var settingsCollapsed = false
    /// Both cards' widths, and the user's. The page opens at the drawing's own
    /// and the grips move the edges from there — which is what makes the
    /// collapse tab non-fixed: it hangs off the canvas, so it follows the edge
    /// wherever the edge goes (`Controls/PanelResize.swift` says why nothing
    /// about the tab had to change).
    @State private var leftWidth = PanelWidthStore(name: "export.left", range: M.leftRange)
    @State private var rightWidth = PanelWidthStore(name: "export.right", range: M.rightRange)
    /// How many columns the Grid draws its thumbnails in — the value the bar's
    /// detented slider sets. Persisted like every other view setting, so the
    /// grid someone arranged is the grid they come back to.
    @AppStorage(Session.uiKey + "exportGridColumns") private var gridColumns = 5

    @State private var zoom: CGFloat = 1
    @State private var paneSize: CGSize = .zero
    @State private var proof: SoftProof?
    @State private var proving = false
    /// **The picture that came out of the file**, after an export has actually
    /// written one. The user's answer to what the pane shows once there is a
    /// file to show: "the render before, the file's own embedded preview
    /// after" — which is a stronger claim than the proof makes, because it is
    /// not "this is what it will look like" but "this is what it does look
    /// like".
    ///
    /// Cleared whenever a new proof is rendered, so any edit puts the render
    /// back: it describes one file that exists, and the next keystroke is
    /// about to make a different one.
    @State private var filePreview: CGImage?

    @State private var running = false
    @State private var note: ResultNote?
    /// The rename dialog's draft, non-nil while it is up. A recipe is a named
    /// thing — the list is a list of names — and the old sheet's Name field
    /// went with the sheet: without this, every recipe anyone creates is called
    /// "Untitled" for good, which the drawing would not have caught because it
    /// draws the list, not the making of one.
    @State private var renameDraft: String?
    @State private var confirmRecipeDeletion = false
    @State private var confirmRecipeReset = false

    /// The drawing's own numbers, so the body reads the way the drawing does.
    private typealias M = Theme.Metric.Export

    // MARK: one body, two homes
    //
    // This page is served two ways — its own window (`ExportWindow`) and the
    // Modern editor's right-hand **export rail** (`compactPanel`) — and it
    // used to draw its own typography and its own rhythm in both. Measured
    // against the parameter inspector it sits beside, the rail's table
    // content was **16 pt further right** and its rows **10 pt tighter**, with
    // six different gaps where the inspector has two: two panels, one window,
    // two designs.
    //
    // So the **body** takes the editor's scale in either home. What stays the
    // drawing's is only what geometry forces: the standalone window's own
    // width, and the fact that it has room for a 20 pt well inset where the
    // 344 pt rail does not.
    //
    //     body          editor role        why
    //     label / value  Font.label 10.5 / Font.value 9   the ranks every other
    //                                                     control uses
    //     label column   84                the editor's one label axis, so a
    //                                     table and a slider row line up
    //     row height     22                the editor's line box
    //     control height 13.9              the editor's pill
    //     row spacing    8                 Modern's scale step
    //     section title  Font.modernSectionTitle (10.5 semibold)  one header rank
    //
    // `F.sectionTitle` was 12.5 — the export drawing's frozen value — so the
    // page's section titles were **two points larger than the inspector's** in
    // the same window. The export ramp is kept below for the one role that is
    // still its own (a chip's face), which is where the size difference is
    // deliberate rather than accidental.

    /// A body label — the question half of a table row.
    private var bodyLabel: Font { Theme.Font.label }
    /// A body value — the answer half of a table row.
    private var bodyValue: Font { Theme.Font.value }

    /// The label column.
    ///
    /// **The one width the export page keeps for itself**, and it is a width
    /// rather than a rhythm: the editor's 84 pt column plus a control leaves
    /// this page's 293 pt of body 209 pt of control, and the four naming chips
    /// (原文件名 / 胶片 / 相纸 / 日期) need 208 — so 84 clips them and the
    /// drawing's 68.5 does not. The label's *font* is the editor's, its axis
    /// starts on `modernContentInset`, and only the column's width is the
    /// window's own.
    private var labelColumn: CGFloat { M.labelWidth }
    /// A table row's line box.
    private var bodyRowHeight: CGFloat { Theme.Metric.modernRowHeight }
    /// Between two rows of one table.
    private var bodyRowSpacing: CGFloat { Theme.Metric.modernRowSpacing }
    /// A control's own height: a field, a pill, a chip.
    private var bodyControlHeight: CGFloat { Theme.Metric.modernControlHeight }

    /// **Zero, on every surface.** `modernContentInset` (20) is the one
    /// horizontal inset this panel has, and anything added to it is added
    /// twice.
    ///
    /// The drawing insets its wells 5.9 pt inside a 20 pt page, and this used
    /// to follow it here and add a well *padding* on top — so the table's
    /// first glyph landed at **37 pt** in the standalone window and 38 pt in
    /// the rail, against 20 for a section title in the same panel. The
    /// measured screenshot: `分区标题 x=21 pt`, `文件夹 x=37 pt`. One column
    /// cannot have two left edges, and the panel's own inset is the one that
    /// matters.
    ///
    /// So the well starts at the content edge and its `padding` is what sets
    /// where *inside* the table the glyphs begin.
    private var wellInset: CGFloat { 0 }
    /// A table's own inner padding — the air between the well's edge and the
    /// first glyph, and the **only** horizontal offset inside the panel.
    ///
    /// It is 0, so a table row starts on the same `modernContentInset` edge as
    /// the section title above it. The drawing's 9.8 was right while an inset
    /// sat under it and put the glyphs at a *third* number; with the inset
    /// gone, keeping it would move the table 10 pt right of its own header —
    /// which is the misalignment, one size smaller.
    private var wellPadding: CGFloat { 0 }
    /// Air above and below a well's rows.
    private var wellVertical: CGFloat { Theme.Metric.modernBlockGap }

    /// **No `compact ?` in any of these.** The window and the rail are the same
    /// page, so a value that differed by home was a second design by another
    /// name — and the two had drifted into opposite errors: measured on
    /// 2026-09-26, the standalone window's table sat 17 pt right of its own
    /// section title and the rail's rows ran 6.5 pt apart against the
    /// inspector's 17–20. Both now read the editor's scale, and the only thing
    /// the window keeps is the width it has room for.
    ///
    /// The one deliberate difference is **`Metric.Export.labelWidth`**: the
    /// editor's 84 pt column plus a control leaves a 313 pt card 209 pt of
    /// control, and the naming chips need 208. A *narrower* label column is a
    /// width decision, not a second rhythm — and it is the same decision
    /// `TOKENS-main-v3` records for the export page's own drawing.
    private var sliderMetrics: SliderMetrics {
        SliderMetrics(labelWidth: labelColumn, valueWidth: 40, rowHeight: bodyRowHeight,
                      trackHeight: M.trackHeight, labelFont: bodyLabel, valueFont: bodyValue)
    }

    enum Mode: String, CaseIterable, Identifiable {
        case grid, viewer
        var id: String { rawValue }
        /// `notes.md` names both glyphs.
        var glyph: String { self == .grid ? "square.grid.2x2" : "rectangle.grid.3x1" }
        @MainActor var help: String { self == .grid ? T("Grid", "网格") : T("Viewer", "预览") }
    }

    private struct ResultNote: Identifiable {
        let id = UUID()
        var text: String
        var warning: Bool
    }

    /// The selected recipe, written straight back through the store so every
    /// edit is saved. There is no "apply" button on purpose — a recipe is a
    /// saved preference, and a preference that needs confirming is one people
    /// lose.
    private var recipe: Binding<ExportRecipe> {
        Binding(get: { store.selected ?? ExportRecipe() },
                set: { store.selected = $0 })
    }

    var body: some View {
        Group {
            if compact { compactPanel }
            else { classicLayout }
        }
        .onAppear { if !compact { mode = startIn } }
        .task(id: compact ? nil : proofKey) { if !compact { await makeProof() } }
        .task(id: recipe.wrappedValue.format) { OpenWithCatalog.refresh(for: recipe.wrappedValue.format) }
        .onChange(of: recipe.wrappedValue) { _, newRecipe in
            if editorProofRecipe?.wrappedValue != nil { editorProofRecipe?.wrappedValue = newRecipe }
        }
        .alert(T("Rename Recipe", "重命名配方"), isPresented: Binding(
            get: { renameDraft != nil },
            set: { if !$0 { renameDraft = nil } })) {
            TextField(T("Name", "名称"), text: Binding(get: { renameDraft ?? "" },
                                            set: { renameDraft = $0 }))
            Button(T("Cancel", "取消"), role: .cancel) { renameDraft = nil }
            Button(T("Rename", "重命名")) {
                let trimmed = (renameDraft ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { recipe.wrappedValue.name = trimmed }
                renameDraft = nil
            }
        } message: {
            Text(T("The name in the recipe list.", "此名称会显示在配方列表中。"))
        }
        .confirmationDialog(T("Delete Recipe?", "删除配方？"),
                            isPresented: $confirmRecipeDeletion) {
            Button(T("Delete Recipe", "删除配方"), role: .destructive) {
                if let selected = store.selected { store.remove(selected) }
            }
            Button(T("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(T("The selected recipe will be removed. Exported files are not affected.",
                   "将移除当前配方，已导出的文件不会受影响。"))
        }
        .confirmationDialog(T("Reset Recipe Settings?", "重置配方设置？"),
                            isPresented: $confirmRecipeReset) {
            Button(T("Reset Settings", "重置设置"), role: .destructive) {
                resetSelectedRecipe()
            }
            Button(T("Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(T("This recipe's location, naming and format settings will return to their defaults.",
                   "此配方的位置、命名和格式等设置将恢复默认值。"))
        }
    }

    private var compactPanel: some View {
        VStack(spacing: 0) {
            StageHeader(title: T("Export", "导出")) { EmptyView() }
            recipeSelector
                .disabled(running)
            Hairline()
            ScrollView {
                settingsSections
                    .disabled(running)
                    .padding(.horizontal, Theme.Metric.modernContentInset)
                    .padding(.vertical, Theme.Metric.modernPanelVerticalInset)
            }
            footer
        }
        .frame(maxHeight: .infinity)
        .modifier(EditorChromeSurface())
    }

    private var classicLayout: some View {
        // Three flush columns, and the bar floats over the middle one.
        //
        // This page kept the **old** shape for two months after the editor
        // stopped using it: four rounded cards, `M.gap` between them, on a
        // visible ground. The 2026-09-17 drawing had already retired that
        // language, and so had this page's own drawing —
        // `export_page.svg` runs its settings rail and its worklist to the
        // window's edges at full height and separates everything with 1 pt
        // hairlines, exactly as the editor's does. A page on cards beside an
        // editor on rails is two apps.
        //
        // The bar moved with it. It used to be a full-width row *above* the
        // columns, which is why the rails began 31 pt down and the window had
        // no square corner; it is now the editor's arrangement — a pill on
        // the ground over the centre column only, with the rails running the
        // full height either side of it.
        HStack(spacing: 0) {
                if !settingsCollapsed {
                    settingsPanel
                        .frame(width: leftWidth.width)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    PanelResizeHandle(side: .trailingEdge, range: M.leftRange,
                                      width: $leftWidth.width)
                }
                // Everything right of the settings card, as one thing — because
                // the collapse tab hangs off *its* leading edge, and in Grid
                // mode that edge belongs to a different card than in Viewer.
                // The tab follows whichever is there, which is what makes it
                // non-fixed in the sense the user meant.
                rightOfSettings
                    // `stroked` only in Grid: there the pill sits on the grid
                    // card, which is the same colour as the pill. On the
                    // ground in Viewer the original drawing draws it plain,
                    // and its tab is deliberately unstroked — a border there
                    // would be inventing one.
                    .overlay(alignment: .leading) {
                        HoverEdgeTab(edge: .leading, collapsed: $settingsCollapsed,
                                     stroked: mode == .grid)
                    }
        }
        // `notes.md`: "write the transition between the modes in both
        // ways" — both branches of `rightOfSettings` carry one and the
        // animation is on the row that holds them.
        .animation(.easeOut(duration: 0.18), value: mode)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - the worklist

    /// The picked set, in the strip's order, is the page's content.
    private var worklist: [Frame] {
        session.frames.filter { session.isPicked($0.id) }
    }

    /// `notes.md`: "Multi-select is allowed, and the export setting is applied
    /// to all the selected images." The export page's gesture keeps that set
    /// as its content: a plain click opens one picked frame, while ⌘ toggles
    /// one without moving the canvas, so the proof on screen does not jump
    /// away from what the person was looking at while they pick the rest of
    /// the batch.
    ///
    /// The editor's bottom navigator handles ⇧ range selection. This export
    /// worklist contains only already-picked frames, so tapping here changes
    /// the frame being previewed rather than establishing a new range.
    ///
    /// The modifier is read off `NSEvent` rather than declared as two
    /// gestures: a plain `TapGesture` on macOS matches a ⌘-click too, so
    /// stacked variants both fire and a ⌘-click becomes a plain one as well.
    private func tap(_ frame: Frame) {
        if NSEvent.modifierFlags.contains(.command) {
            session.togglePick(frame.id)
        } else {
            session.open(frame.id)
        }
    }

    /// The frames this export will write, in the strip's order so the run is
    /// reproducible — `notes.md`: "the export setting is applied to all the
    /// selected images".
    ///
    /// `session.selectedFrames`, and **not** `session.selection`: the two are
    /// different questions — what gets exported, and what is on the canvas —
    /// and `notes.md` is explicit that picking several must not move the
    /// second one ("the viewed image stays as the one the user is previously
    /// on"). The set lives on `Session` beside the open frame rather than here
    /// because the filmstrip and the Browse grid mark the same frames; a batch
    /// kept on this page is a batch that can disagree with what the person can
    /// see. It was a local `Set<URL>` until multi-selection landed.
    ///
    /// RFC-017 §8 Q2 wants apply-to-all to take "the selection when there is
    /// one, the folder otherwise". This property is that input.
    private var batch: [URL] { session.selectedFrames }

    // MARK: - the proof

    /// What the proof depends on: which frame, which destination space, and
    /// whether the format has a colour at all. Everything else a recipe
    /// carries — the name, the folder, the existing-file policy — changes no
    /// pixel, and keying on the whole recipe would re-render the proof on
    /// every keystroke in the Name field.
    ///
    /// **The window's size is not in here and must not be.** The render is the
    /// file's own full-size pixels regardless of how much of it is on screen;
    /// the pane contributes only the display downsample chosen when that
    /// render starts. A resize that started a 24-megapixel render would be the
    /// worst kind of waste, and there used to be a budget in this key that did
    /// exactly that.
    private struct ProofKey: Hashable {
        var frame: URL?
        var space: ExportColorSpace
        var takesColour: Bool
        /// The recipe's own output size, because it is a size the *file* will
        /// have — the proof is the file's pixels now, so anything that changes
        /// how many there are changes the proof. (It is a size, unlike the
        /// next field, and it comes from the recipe rather than the window.)
        var outputSize: OutputSize
        /// Whether the centre has a pane to draw in — **not a render input but
        /// a cost input**, and the one thing here that does not change the
        /// file-sized render. In Grid mode there is no pane at all, and the
        /// render is seconds of engine time. It is a `Bool` and not `paneSize`
        /// for the reason above: a resize must not re-key this, and a resize
        /// cannot change whether a pane exists.
        var hasPane: Bool
    }

    private var proofKey: ProofKey {
        ProofKey(frame: session.selection,
                 space: recipe.wrappedValue.colorSpace,
                 takesColour: recipe.wrappedValue.format.takesColorSpace,
                 outputSize: recipe.wrappedValue.outputSize,
                 hasPane: paneSize.width > 1)
    }

    /// **The render is still full size; only what the page holds and draws
    /// shrank.** `softProofForDisplay` runs `Exporter.filePixels` at the
    /// file's own size, keeps the full-frame statistics, then downsamples the
    /// converted texture once to roughly twice the pane's longest side. The
    /// page holds only that display image and the file's real pixel size.
    ///
    /// This does **not** reverse "the proof is the file": it is still the same
    /// `Exporter.filePixels` tail, with the display downsample after the
    /// transform. Do not re-add the old `maxPixels` or canvas-tier clamps;
    /// those bounded the render, while this bounds only the page's copy.

    /// Renders the proof, keeping whatever is already on screen until the new
    /// one is ready.
    ///
    /// **Coalescing is `.task(id:)`'s**, not a queue: when the key changes
    /// SwiftUI cancels this task and starts another, so the last edit wins and
    /// the ones before it are abandoned rather than run in turn. A full-size
    /// proof is expensive enough that the difference matters — a queue would
    /// render every keystroke and show the first one last.
    private func makeProof() async {
        guard !worklist.isEmpty, session.selection != nil else { proof = nil; return }
        // Nothing to show it in. In Grid mode there is no pane at all, and the
        // proof is wanted the moment the Viewer brings one back.
        guard paneSize.width > 1 else { return }
        proving = true
        defer { proving = false }
        // The develop, if the frame has not been through one, is `softProof`'s
        // — it is the same request for the page and for the export, so it is
        // asked for on the side both of them share rather than here.
        //
        // Cancellation is the task's too: a superseded call returns nil rather
        // than a stale picture, so a keystroke that changes the key does not
        // have to be waited on and cannot land the old proof. A superseded
        // render's result is dropped rather than shown — the pane is already
        // showing the previous proof, which is a truer thing to look at than a
        // picture of a recipe the person has moved on from.
        let made = await session.softProofForDisplay(recipe: recipe.wrappedValue,
                                                     paneSize: paneSize)
        guard !Task.isCancelled else { return }
        // An edit puts the render back: `filePreview` describes one file that
        // exists, and this key changing means the next one will not be it.
        filePreview = nil
        proof = made
    }

    /// The file's second page, or nil when it has one image and no more.
    ///
    /// **By index, not by thumbnail.** `CGImageSourceCreateThumbnailAtIndex`
    /// does not find an embedded preview — measured by the writer's half of
    /// this seam — and silently returns a downscale of the full picture at the
    /// same cost, so a thumbnail call looks like it worked and shows the wrong
    /// thing.
    ///
    /// A JPEG or a PNG has one image and returns nil here, which is the whole
    /// of the "only where there is something to swap to" rule: the caller
    /// keeps the render it already had.
    /// `internal`, not private, so a test can reach it: the index is the whole
    /// of the behaviour and the obvious alternative is silently wrong.
    static func embeddedPreview(of url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(src) > 1 else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 1, nil)
    }

    // MARK: - the top bar

    /// The page's own bar: the mode toggle, the zoom cluster and the count. It
    /// is the window's first row and spans it, like the editor's, so the three
    /// window buttons land on its centreline (`Windows/TrafficLights.swift`).
    ///
    /// The count pill is centred **over the filmstrip card** rather than inset
    /// from the window's edge — measured, its centre is 0.65 pt from the
    /// card's — because it labels the strip below it.
    private var topBar: some View {
        HStack(spacing: 0) {
            // `M.modeToggleLeading` is **not** used any more, and leaving it
            // in was a layout bug rather than a cosmetic one. It is 330 pt:
            // the distance from the *window's* leading edge to the mode
            // buttons, measured while the bar was a full-width row that had
            // to clear the window buttons and the settings card. The bar is a
            // pill over the centre column now, so that spacer became 330 pt
            // of minimum width demanded from the middle of the layout — which
            // the settings rail paid for. Widening the rail by 120 moved its
            // edge by 114, and by 188 moved it 168.5, because the bar would
            // not compress. `ExportPanelTests` measures exactly that.
            Spacer().frame(width: Theme.Metric.barPadding)
            modeButton(.grid)
            modeButton(.viewer).padding(.leading, M.modeSpacing)
            // The empty middle is the window's drag surface, exactly as it is
            // on the editor's bar: the titlebar is hidden.
            WindowDragHandle().frame(minWidth: 8, maxWidth: .infinity)
            // One span, two controls: the zoom cluster in Viewer mode, where
            // the drawing puts it, and the grid-size slider in Grid mode. Both
            // are exactly `zoomClusterWidth` wide, so switching modes does not
            // move the count pill beside them.
            windowCluster
            Spacer().frame(width: M.zoomToCount)
            countPill
            Spacer().frame(width: M.countTrailingInset)
        }
        .frame(height: M.topBarHeight)
        .barCard()
        // `notes.md`: "Remember to write the transition between the modes in
        // both ways." Both branches of the cluster carry one and the animation
        // is on the row that holds them, so neither direction is the one that
        // happens to animate.
        .animation(.easeOut(duration: 0.18), value: mode)
    }

    /// The bar's right-hand control. In Viewer it is the zoom cluster the
    /// drawing draws there; in Grid it is the slider the drawing's own margin
    /// asks for — "Turns to choose grid size in grid view mode", at x 2279.75
    /// of the artboard, which halves to 1139.9 pt and lands inside this span.
    ///
    /// What it sizes is the **thumbnail**, and the pane still takes the width
    /// it is given: the count of columns is what the stops stand for, and the
    /// cells grow into whatever the pane can afford. That is Finder's
    /// behaviour, and the user asked for Finder's.
    @ViewBuilder private var windowCluster: some View {
        if mode == .viewer {
            // One `HStack`, not three loose controls: a transition belongs to
            // a view, and three siblings each fading on their own is a
            // cross-fade with holes in it — the buttons would pop while the
            // pill dissolved. One container is one transition, in both
            // directions.
            HStack(spacing: 0) {
                zoomButton("plus.magnifyingglass", T("Zoom in", "放大"), 1.5)
                zoomPill.padding(.horizontal, M.zoomClusterGap)
                zoomButton("minus.magnifyingglass", T("Zoom out", "缩小"), 1 / 1.5)
            }
            .frame(width: M.zoomClusterWidth)
            .transition(.opacity)
        } else {
            DetentSlider(value: $gridColumns, range: M.gridColumns,
                         width: M.zoomClusterWidth,
                         help: T("Thumbnail size — \(gridColumns) columns", "缩略图大小 — \(gridColumns) 列"))
                .transition(.opacity)
        }
    }

    /// Both glyphs are named in `notes.md`, and the viewer's is drawn turned a
    /// quarter turn. Selection is this page's accent rather than a plate — the
    /// rule the editor's tool row follows for the same reason, and the one
    /// `notes.md` restates for the naming chips.
    private func modeButton(_ m: Mode) -> some View {
        let on = mode == m
        return ExportIcon(glyph: m.glyph, help: m.help, selected: on,
                          rotation: m == .viewer ? 90 : 0) { mode = m }
    }

    private func zoomButton(_ glyph: String, _ help: String, _ factor: CGFloat) -> some View {
        // No `disabled:` — this control is only built inside the viewer
        // branch, so `mode != .viewer` could never be true (space audit,
        // dead state). `ExportIcon`'s parameter stays for the mode buttons.
        ExportIcon(glyph: glyph, help: help, restOpacity: 0.5) {
            zoom = (zoom * factor).clamped(to: 0.1...8)
        }
    }

    /// A plain well-coloured capsule with no outline: the drawing strokes
    /// neither this pill nor the count beside it.
    private var zoomPill: some View {
        Menu {
            Button(T("Fit", "适合窗口")) { zoom = 1 }
            Divider()
            ForEach([0.5, 1.0, 2.0, 4.0], id: \.self) { f in
                Button("\(Int(f * 100)) %") { zoom = CGFloat(f) }
            }
        } label: {
            Text("\(Int((zoom * 100).rounded())) %")
                .font(bodyValue)
                .foregroundStyle(Theme.text)
                .frame(width: M.pillWidth, height: M.pillHeight)
                .pillSurface(base: Theme.well)
                .contentShape(Capsule())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    private var countPill: some View {
        Text(imageCount(batch.count))
            .font(bodyLabel)
            .foregroundStyle(Theme.text)
            .frame(width: M.pillWidth + 22, height: M.pillHeight)
            .background(Theme.well, in: Capsule())
            .help(batch.count == session.frames.count
                  ? T("Every image in the session", "会话中的全部照片")
                  : T("\(batch.count) of \(session.frames.count) selected for this export",
                      "已选 \(batch.count)/\(session.frames.count) 张照片用于导出"))
    }

    // MARK: - the left card

    private var settingsPanel: some View {
        VStack(spacing: 0) {
            // The window buttons' row.
            //
            // Required, not decorative. `ExportWindow` hides the titlebar and
            // *places* the three buttons at `Export.topBarHeight / 2`; while
            // the page opened with a full-width bar they landed in it. Now
            // that the rails run to the top of the window, this rail owns
            // that row, and without it "Export Formula" is drawn underneath
            // the close button.
            railHeader
            Hairline()
            recipeSelector
                .disabled(running)
            Hairline()
            ScrollView {
                settingsSections
                    .disabled(running)
            }
            footer
        }
        .railCard()
    }

    /// Settings belong to the selected recipe; the selector itself is outside
    /// this stack, above it, rather than pretending to be a peer section.
    private var settingsSections: some View {
        VStack(spacing: 0) {
            let sections: [(String, AnyView)] =
                [("location", AnyView(locationSection)),
                 ("naming", AnyView(namingSection)),
                 ("format", AnyView(formatSection)),
                 ("summary", AnyView(summarySection))]
            ForEach(Array(sections.enumerated()), id: \.element.0) { index, entry in
                if index > 0 { Hairline() }
                entry.1
            }
        }
    }

    /// The strip at the top of the settings rail that the three window
    /// buttons are placed over. Empty on purpose — the drawing puts nothing
    /// else in it — and a drag surface, as the editor's rail header is.
    private var railHeader: some View {
        Color.clear
            .frame(height: M.topBarHeight)
            .frame(maxWidth: .infinity)
            .background(WindowDragHandle())
    }

    /// A recipe is the parent of every setting below, not one more settings block.
    /// Keep its identity visible while scrolling. Management actions belong
    /// to the block header; choosing a recipe is the content beneath it.
    private var recipeSelector: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: T("Export Recipe", "导出配方"),
                          expanded: .constant(true),
                          menu: { AnyView(recipeManagementActions) })
            Menu {
                ForEach(store.recipes) { item in
                    Button {
                        store.selectedID = item.id
                    } label: {
                        if item.id == store.selected?.id {
                            Label(item.name, systemImage: "checkmark")
                        } else {
                            Text(item.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: Theme.Metric.space8) {
                    Text(store.selected?.name ?? T("Choose a Recipe", "选择配方"))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .font(bodyLabel)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, PillFieldGeometry.textInset)
                .frame(height: bodyControlHeight)
                .pillSurface(base: Theme.pill)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .frame(maxWidth: .infinity)
            .padding(.top, Theme.Metric.modernHeaderToContent)
            Text(T("Location, naming and format changes are saved to this recipe automatically.",
                   "位置、命名和格式等修改会自动保存到此配方。"))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Metric.space8)
        }
        .padding(.horizontal, Theme.Metric.modernContentInset)
        .padding(.vertical, Theme.Metric.modernPanelVerticalInset)
    }

    @ViewBuilder private var recipeManagementActions: some View {
        Button(T("New Recipe…", "新建配方…")) {
            store.add()
            renameDraft = store.selected?.name
        }
        Button(T("Duplicate Recipe…", "复制配方…")) {
            if let selected = store.selected {
                store.duplicate(selected)
                renameDraft = store.selected?.name
            }
        }
        .disabled(store.selected == nil)
        Button(T("Rename Recipe…", "重命名配方…")) {
            renameDraft = store.selected?.name
        }
        .disabled(store.selected == nil)
        Divider()
        Button(T("Reset Recipe Settings…", "重置配方设置…")) { confirmRecipeReset = true }
            .disabled(store.selected == nil)
        Button(T("Delete Recipe…", "删除配方…")) { confirmRecipeDeletion = true }
            .disabled(store.recipes.count < 2)
        Divider()
        Button(T("Reveal Recipes File in Finder", "在访达中显示配方文件")) {
            NSWorkspace.shared.activateFileViewerSelecting([store.url])
        }
    }

    /// Where the files land, and — the part that was missing — **how many
    /// places that is**.
    ///
    /// The folder is chosen in the row itself rather than in the section's
    /// "...": a destination reached only through a menu on a header is a
    /// destination people do not know they can change, and "Beside the
    /// original" being the sole visible option read as the only one.
    ///
    /// The line at the foot used to print one path with its head truncated.
    /// Under `.besideOriginal` that path is the open frame's folder and the
    /// batch may be writing into a dozen others — the page stated one of them
    /// as if it were the answer. It now counts them, and the button beside it
    /// opens the one it can show.
    private var locationSection: some View {
        // **No menu.** Every item it had was already a row on screen — the
        // folder picker is the 文件夹 pill's own menu, the subfolder is a text
        // field, and Reveal is the button on the destination line. A `•••`
        // whose items the reader can already see is a second way to do four
        // things and a fifth place to look (UI-SPEC §2.16g).
        PanelSection(T("Location", "位置"), key: "exportLocation") {
            Well(padding: wellPadding, vertical: wellVertical, inset: wellInset, fill: false) {
                VStack(spacing: bodyRowSpacing) {
                    // **Three rows, one shape.** They used to be three
                    // different things — a hand-written `HStack` around a
                    // `PillField`, a `TextField` with its own padding, and a
                    // `PillMenu` — and the three controls came out at three
                    // widths: the folder pill hugged its text, the field
                    // stretched to its own padding, the menu filled its row.
                    // The user's read of it was "三个下拉菜单用了三个尺寸".
                    //
                    // So all three go through `row(_:control:)`, which is the
                    // one place that says what a row in this panel is: a label
                    // column, a control that fills what is left, and one line
                    // box. `PillField` and the field take `.frame(maxWidth:
                    // .infinity)` for the same reason `PillMenu` already did.
                    row(T("Folder", "文件夹")) {
                        PillField(title: folderLabel(recipe.wrappedValue.folder), font: bodyLabel,
                                  help: folderHelp) {
                            Button(T("Beside the original", "与原片同目录")) {
                                recipe.wrappedValue.folder = .besideOriginal
                            }
                            if case .fixed(let p) = recipe.wrappedValue.folder {
                                Button((p as NSString).abbreviatingWithTildeInPath) {}
                                    .disabled(true)
                            }
                            Divider()
                            Button(T("Choose Folder…", "选择文件夹…")) { chooseFolder() }
                        }
                    }
                    row(T("Subfolder", "子文件夹")) {
                        // The pill's surface with a field inside it, so this
                        // row's control is the *same box* as the two pills
                        // around it rather than a field wearing a background.
                        // A field's intrinsic width is its own, so the shape
                        // has to come from the container.
                        HStack(spacing: 0) {
                            TextField(T("none", "无"), text: recipe.subfolder)
                                .textFieldStyle(.plain)
                                .font(bodyLabel).foregroundStyle(Theme.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .onSubmit { store.save() }
                        }
                        .padding(.horizontal, PillFieldGeometry.textInset)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: bodyControlHeight)
                        .pillSurface(base: Theme.pill)
                    }
                    // `PillField`, the same shape as the Folder row: the
                    // label is the row's, so the control is only the pill.
                    // `PillMenu` carries its own label column and would have
                    // drawn a second one.
                    row(T("Existing File", "同名文件")) {
                        // `PillMenu` with a zero label column: the row above
                        // owns the label, and the pill has to be the same shape
                        // as the Folder row's — which is why this is neither a
                        // second `PillField` shape nor a `PillMenu` that draws
                        // its own label twice.
                        PillMenu(label: "", options: ExistingFilePolicy.allCases,
                                 title: { $0.localizedLabel }, selection: recipe.existing,
                                 labelWidth: 0, font: bodyLabel)
                    }
                    destinationLine
                }
            }
        }
    }

    /// The resolved destination, and the Finder button for it.
    private var destinationLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(destinationSummary)
                .font(bodyValue).foregroundStyle(Theme.Ink.tertiary)
                .lineLimit(2).truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(destinationHelp)
            Button(T("Reveal", "显示")) { reveal(destinationFolders.first) }
                .buttonStyle(.plain)
                .font(bodyValue).foregroundStyle(Theme.exportAccent)
                .help(destinationFolders.count > 1
                      ? T("Open the first of these folders. The rest are beside their own frames.",
                          "打开第一个文件夹。其余文件会保存在各自原片旁。")
                      : T("Open this folder in the Finder. A folder that does not exist yet opens its nearest parent — the export creates the rest.",
                          "在访达中打开此文件夹。若尚未创建，将打开最近的上级文件夹；导出时会创建余下路径。"))
                .rowEnabled(!destinationFolders.isEmpty)
        }
    }

    /// Every distinct folder this recipe would write into for the current
    /// selection. One under a fixed folder; under `.besideOriginal`, as many
    /// as the batch has source folders.
    private var destinationFolders: [URL] {
        let r = recipe.wrappedValue
        let sources = batch.isEmpty ? [session.selection].compactMap { $0 } : batch
        guard !sources.isEmpty else { return [URL(fileURLWithPath: writePath)] }
        var seen: [URL] = []
        for s in sources where !seen.contains(r.directory(for: s)) {
            seen.append(r.directory(for: s))
        }
        return seen
    }

    private var destinationSummary: String {
        let folders = destinationFolders
        guard let first = folders.first else { return writePath }
        let path = (first.path as NSString).abbreviatingWithTildeInPath
        guard folders.count > 1 else { return path }
        return T("\(folders.count) folders — one beside each original, starting \(path)",
                 "\(folders.count) 个文件夹 — 分别位于原片旁；第一个是 \(path)")
    }

    private var destinationHelp: String {
        let folders = destinationFolders
        guard folders.count > 1 else { return folders.first?.path ?? writePath }
        let shown = folders.prefix(8).map(\.path)
        let rest = folders.count - shown.count
        return ([T("Beside the original writes into each frame's own folder:", "与原片同目录会写入每张照片自己的文件夹：")] + shown
                + (rest > 0 ? [T("…and \(rest) more", "…以及另外 \(rest) 个")] : [])).joined(separator: "\n")
    }

    private var folderHelp: String {
        switch recipe.wrappedValue.folder {
        case .besideOriginal:
            T("Each frame's own folder. A batch drawn from several folders therefore writes into several — the line below counts them.",
              "每张照片写入其原片所在文件夹。若批次来自多个文件夹，下面会显示目标数量。")
        case .fixed:
            T("One folder for every frame in the batch.", "整个批次写入同一个文件夹。")
        }
    }

    /// Open a folder in the Finder, walking up to the nearest one that exists:
    /// the subfolder is created by the export and not before, so the exact
    /// path is usually not there yet and `selectFile` on it would do nothing
    /// at all rather than say why.
    private func reveal(_ url: URL?) {
        guard var u = url else { return }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        while !(fm.fileExists(atPath: u.path, isDirectory: &isDir) && isDir.boolValue) {
            let parent = u.deletingLastPathComponent()
            if parent.path == u.path { return }
            u = parent
        }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: u.path)
    }

    /// `notes.md`: "Four Naming options … (at least one must be selected),
    /// selection is marked with Orange highlight `#f08724`, and the actual
    /// order can be altered by user dragging". All four are always drawn, in
    /// the rule's own order; the ones switched on take the accent and the rest
    /// the grey plate the drawing gives every chip, and dragging one onto
    /// another reorders the row.
    private var namingSection: some View {
        // **No menu.** Four chips fit one row; "select all" and "original
        // name only" are bulk conveniences for clicking four things, and the
        // third item acted on a chip *order* the page does not draw.
        PanelSection(T("Naming", "命名"), key: "exportNaming") {
            Well(padding: wellPadding, vertical: wellVertical, inset: wellInset, fill: false) {
                VStack(alignment: .leading, spacing: bodyRowSpacing) {
                    row(T("Format", "格式")) { tokenRow }
                    resolvedNameRow
                }
            }
        }
    }

    /// The filename this recipe writes, **whole**.
    ///
    /// It was one line, `truncationMode(.middle)`, at the width of a 313 pt
    /// card — so the moment more than two tokens were on, the middle of the
    /// name was replaced by an ellipsis. The middle is where the tokens are.
    /// A naming control whose read-out hides the part you are editing is a
    /// control you verify by exporting, which is the thing the read-out exists
    /// to avoid: "the current truncated sample hides the exact information
    /// users need to check".
    ///
    /// So it wraps instead of truncating, it is selectable so the exact string
    /// can be copied and compared, and it is drawn in the value face because
    /// it is the answer rather than the question. It is resolved against the
    /// open frame whenever there is one (`nameContext`) — the rest of a batch
    /// differs only where the original-name token is.
    private var resolvedNameRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(T("File name", "文件名")).font(bodyLabel).foregroundStyle(Theme.Ink.secondary)
                .lineLimit(1)
                .frame(width: labelColumn, alignment: .leading)
            Text(sampleName)
                .font(bodyValue).foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(session.selection == nil
              ? T("An example — no frame is open, so this is the model frame from the recipe file.",
                  "这是示例文件名；当前没有打开照片。")
              : T("The name this recipe gives the open frame. Every other frame in the batch differs only where the original name is.",
                  "这是当前照片导出后的文件名。批次中其他照片仅在原文件名部分不同。"))
    }

    private var tokenRow: some View {
        HStack(spacing: M.chipSpacing) {
            ForEach(recipe.wrappedValue.naming.chips) { t in tokenChip(t) }
        }
    }

    private func tokenChip(_ t: NameToken) -> some View {
        let on = recipe.wrappedValue.naming.isOn(t)
        let last = recipe.wrappedValue.naming.tokens.count == 1
        return Text(t.localizedLabel)
            .font(bodyValue)
            .foregroundStyle(on ? Theme.card : Theme.text)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 5)
            .frame(height: bodyControlHeight)
            // The chips are the export page's smallest controls and the only
            // two-tone ones: orange means "in the name", grey means "not".
            // Both get the same surface, so the pair reads as one switch
            // rather than as a button and a label. UI-SPEC §2.2.
            .pillSurface(base: on ? Theme.exportAccent : Theme.exportChip, wash: !on)
            .contentShape(Capsule())
            .onTapGesture {
                var n = recipe.wrappedValue.naming
                n.toggle(t)
                recipe.wrappedValue.naming = n
            }
            // Only the last one on refuses to go off (`NamingRule.toggle`), so
            // the chip says so rather than looking broken.
            .help(on && last ? T("A filename needs at least one part", "文件名至少需要一个组成部分")
                  : (on ? T("Remove \(t.helpName) from the filename", "从文件名中移除\(t.localizedHelpName)")
                        : T("Add \(t.helpName) to the filename", "将\(t.localizedHelpName)加入文件名")))
            .draggable(t.rawValue)
            .dropDestination(for: String.self) { items, _ in
                guard let raw = items.first, let moving = NameToken(rawValue: raw) else { return false }
                var n = recipe.wrappedValue.naming
                n.move(moving, before: t)
                recipe.wrappedValue.naming = n
                return true
            }
    }

    /// **No section menu.** It carried two items, and both were a second way
    /// to do something the well already does: "Set to Original Size" is now
    /// the Size row's own first choice, and Open With had a row of its own
    /// three lines below it. The user's note — "there are two repeated paths
    /// to show open with, keep the explicit one" — is the general rule as much
    /// as the particular fix: a "..." that only repeats the panel under it
    /// teaches people to open it looking for something that is not there.
    private var formatSection: some View {
        PanelSection(T("Format and Size", "格式与尺寸"), key: "exportFormat") {
            Well(padding: wellPadding, vertical: wellVertical, inset: wellInset, fill: false) {
                VStack(spacing: bodyRowSpacing) {
                    // **One control, filling the column**, like every other
                    // row on the page. This one used to be a hand-written
                    // `HStack` with a second, `.fixedSize()` pill beside it, so
                    // its right edge was wherever that pill left off — 4 pt
                    // inside every neighbouring row's. It was also a second way
                    // to say one thing: `ExportFormat` *is* the pair of
                    // container and depth, and `withDepth` switches format.
                    // The depth therefore lives in the item's own title, where
                    // it is read as part of the choice rather than as a
                    // separate control that sometimes cannot be changed.
                    row(T("Format", "格式")) {
                        PillMenu(label: "", options: ExportFormat.allCases,
                                 title: { "\($0.shortLabel) · \($0.bitDepth) bit" },
                                 selection: recipe.format,
                                 labelWidth: 0, font: bodyLabel)
                    }
                    if recipe.wrappedValue.format == .di { diNote }
                    if recipe.wrappedValue.format.takesColorSpace {
                        // **The label is the row's, not the pill's.** It used to
                        // be drawn by the pill (`labelWidth: labelColumn`),
                        // which put this row's control 5 pt right of the rows
                        // whose label came from `row(_:)` — two left edges in
                        // one table, the same failure as the indent this pass
                        // started from, one size smaller.
                        //
                        // The name is data, not a fixed label: an installed
                        // profile can be called anything, and the narrowest
                        // card truncates the long ones. The tooltip carries
                        // the whole of it, so a truncated name costs a hover
                        // rather than the information.
                        row(T("Color Space", "色彩空间")) {
                            PillMenu(label: "", options: ColorSpaceCatalog.all.map(\.space),
                                     title: { ColorSpaceCatalog.name(for: $0) ?? T("Unknown profile", "未知配置文件") },
                                     selection: recipe.colorSpace,
                                     labelWidth: 0, font: bodyLabel)
                                .help(ColorSpaceCatalog.name(for: recipe.wrappedValue.colorSpace)
                                      ?? T("This profile is not on this machine", "本机没有此色彩配置文件"))
                        }
                    }
                    if recipe.wrappedValue.format.takesQuality {
                        ScrubSlider(label: T("Quality", "质量"), sublabel: nil,
                                    value: recipe.quality, range: 0.3...1, snap: 0.01,
                                    format: { String(format: "%.0f", $0 * 100) },
                                    metrics: sliderMetrics,
                                    onCommit: { store.save() })
                    }
                    if recipe.wrappedValue.format.carriesPreviewPage { previewRow }
                    sizeRows
                    openWithRow
                }
            }
        }
    }

    /// What a DI package **is**, on the page, because nothing else on it says.
    ///
    /// Every other format is a file whose name you recognise. This one is two
    /// files and a convention, and the pill that selects it says "DI package"
    /// — which tells someone who already knows exactly what they already knew.
    /// Both halves matter and neither is guessable: the TIFF is not a picture
    /// (it is untagged normalised density and looks wrong opened as one), and
    /// it is only half the export without the cube beside it.
    ///
    /// The last line is the **next step**, which is the part a person actually
    /// needs: these two files are an input to a grading system, not a
    /// deliverable.
    private var diNote: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(T("Two files: a 16-bit TIFF of normalised film density, untagged, and the print profile as a 3D .cube LUT, in a folder named for the export.",
                   "包含两个文件：未标记色彩空间的 16-bit 胶片密度 TIFF，以及印相配置的 3D .cube LUT，保存在以导出名称命名的文件夹中。"))
            Text(T("Next: load both into Resolve, Baselight or Nuke and apply the cube to the TIFF. Opened on its own the TIFF is density, not a picture.",
                   "下一步：在 Resolve、Baselight 或 Nuke 中载入两者，并将 LUT 应用于 TIFF。单独打开的 TIFF 是密度数据，不是成片。"))
        }
        .font(bodyValue).foregroundStyle(Theme.Ink.tertiary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(T("The TIFF carries the film's density normalised by the LUT's own axes and is written in device RGB on purpose, so nothing converts the numbers the cube indexes. The cube is the paper's transform, domain 0–1, and it carries a preview page so the package has something a person can look at.",
                "TIFF 按 LUT 的坐标轴归一化胶片密度，刻意使用设备 RGB，避免改变 LUT 索引的数值。LUT 是定义域为 0–1 的相纸变换；包内也附有可查看的预览页。"))
    }

    /// The bit depth is not a free choice: `ExportFormat` *is* the format and
    /// the depth together, so this pill switches between the two containers
    /// that carry the asked-for depth, and says why it is inert for JPEG and
    /// the DI package rather than pretending to move.

    /// Write a preview into the TIFF. Off by default, TIFF only, and a row
    /// that exists in no drawing — the user's call of 2026-09-14: "every TIFF,
    /// but opt-in per recipe".
    ///
    /// The checkbox is the app's own `CheckBox`; the row is this page's,
    /// because `ToggleRow` is drawn at the editor's size and font and this
    /// page's rows are tighter. The cost is in the tooltip rather than on the
    /// page: it is a tenth of the file, which is worth knowing before ticking
    /// it and not worth a sentence in front of someone who has not.
    private var previewRow: some View {
        row(T("Preview", "预览图")) {
            CheckBox(isOn: recipe.embedsPreview)
                .help(T("Writes a preview image into the TIFF, about a tenth larger. Off unless a recipe asks for it.",
                        "将预览图写入 TIFF，文件约增大一成；仅在配方启用时写入。"))
        }
    }

    /// Size: **what kind of size**, then the number it needs, then the pixels
    /// that fall out of it.
    ///
    /// It was two fields, `width × height`, and both of its problems came from
    /// that. The first is the bug: each field wrote its own axis and left the
    /// other alone, so typing a width silently changed the shape of the
    /// picture and the resample stretched it. The second is that a width means
    /// nothing to a batch — one recipe runs over every selected frame
    /// (`notes.md`), and a selection of portraits and landscapes has no common
    /// width, only a common long edge.
    ///
    /// So the row leads with the choice and the number is subordinate to it,
    /// and the line under it states the result in pixels rather than leaving
    /// it to be inferred: a size control whose consequence you have to work
    /// out is a size control you check after the export instead of before.
    private var sizeRows: some View {
        VStack(alignment: .leading, spacing: Theme.Metric.space4) {
            // **The label meets its control slot at zero; the controls inside
            // that slot take the grid's gap.** Collapsing the whole stack to
            // `spacing: 0` to align the label also glued the pill to the number
            // beside it — one gap was doing two jobs, and only one of them was
            // the label's.
            HStack(spacing: 0) {
                Text(T("Size", "尺寸")).font(bodyLabel).foregroundStyle(Theme.Ink.secondary)
                    .lineLimit(1)
                    .frame(width: labelColumn, alignment: .leading)
                HStack(spacing: Theme.Metric.space8) {
                    PillField(title: sizeModeLabel, font: bodyLabel,
                              help: T("Original keeps each frame's own pixels. Long edge resamples every frame so its longer side is the number you set, whichever way round the frame is.",
                                      "原始尺寸保留每张照片自己的像素尺寸；长边模式按设定值重采样，不受横竖方向影响。")) {
                        Button(T("Original Size", "原始尺寸")) { recipe.wrappedValue.outputSize = .original }
                        Button(T("Resize: Long Edge", "调整尺寸：长边")) {
                            recipe.wrappedValue.outputSize = OutputSize.clamped(currentLongEdge)
                        }
                    }
                    if recipe.wrappedValue.outputSize.edge != nil { longEdgeField }
                }
                // The slot fills what the label left, so the pill expands and
                // the two controls sit exactly `space8` apart — the taxonomy's
                // one gap between two controls in a row. Without this the slot
                // hugged its contents and the gap came out twice the grid's.
                .frame(maxWidth: .infinity)
            }
            .frame(height: Theme.Metric.gridControl)
            .frame(height: bodyRowHeight, alignment: .top)
            Text(resultingSizeLine)
                .font(bodyValue).foregroundStyle(Theme.Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, labelColumn)
                .help(resultingSizeHelp)
        }
    }

    /// Put the selected recipe's settings back to the app's defaults, keeping
    /// the two things that name it.
    private func resetSelectedRecipe() {
        guard var r = store.selected else { return }
        let id = r.id, name = r.name
        r = ExportRecipe()
        r.id = id
        r.name = name
        store.selected = r
    }

    /// **Output Proof**, as a switch: on shows the selected recipe's output on
    /// the canvas. Disabled with a reason when the recipe cannot be proofed
    /// (no frame, or a format with no colour space to convert into).
    private var proofRow: some View {
        // **The app's `ToggleRow`**, so this switch has the same shape as
        // every other one — label on the leading edge, box on the trailing
        // edge, the whole row clickable. Drawn as a bare `row()` it put the box
        // right after the words, which is what looked wrong in place.
        ToggleRow(label: T("Output Proof", "输出软打样"),
                  isOn: Binding(
                    get: { editorProofRecipe?.wrappedValue != nil },
                    set: { on in
                        editorProofRecipe?.wrappedValue = on ? recipe.wrappedValue : nil
                    }),
                  enabled: session.selection != nil && recipe.wrappedValue.format.takesColorSpace,
                  reason: T("A proof needs an open frame and a format that carries colour.",
                            "需要打开一张照片，且格式要带色彩空间。"))
    }

    /// The frame's own long edge, which is what "Resize" starts at — switching
    /// the mode must not itself resample anything. The number is there to be
    /// changed, not to be discovered afterwards.
    private var currentLongEdge: Int {
        let p = nameContext.pixelSize
        let edge = max(p.width, p.height).rounded()
        guard edge.isFinite, edge > 0, edge < CGFloat(Int.max) else { return 1 }
        return Int(edge)
    }

    private var sizeModeLabel: String {
        recipe.wrappedValue.outputSize.isOriginal ? T("Original", "原始") : T("Long Edge", "长边")
    }

    /// The largest number the field takes. For one frame that is the frame's
    /// own long edge — there is no super-resolution path, so anything above
    /// it would be a promise the export does not keep. A batch can hold
    /// frames bigger than this one, so it keeps the global bound and
    /// `OutputSize.pixels(for:)` stops each frame at its own size.
    private var longEdgeCeiling: Int {
        batch.count > 1 ? OutputSize.bounds.upperBound
                        : max(OutputSize.bounds.lowerBound, currentLongEdge)
    }

    /// One number, committed on Return or on leaving the field, clamped to
    /// `OutputSize.bounds` and to `longEdgeCeiling` rather than accepted and
    /// quietly not honoured.
    private var longEdgeField: some View {
        TextField("", value: Binding(
            get: { recipe.wrappedValue.outputSize.edge ?? currentLongEdge },
            set: { recipe.wrappedValue.outputSize = OutputSize.clamped(min($0, longEdgeCeiling)) }),
                  format: .number.grouping(.never))
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(bodyValue).foregroundStyle(Theme.text)
            // **A field, not a pill.** This is the one place the app drew a
            // typed value as a capsule: every other value box (the sliders',
            // the Film panel's reference size) is a rounded rectangle, because
            // the shape says what the control *is* — a capsule is something
            // you choose from and a rectangle is something you type into. It
            // was also 22 pt tall against the pills' 16, and a hard 62 pt wide.
            .frame(width: Theme.Metric.fieldWidth, height: Theme.Metric.gridControl)
            .controlSurface()
            .onSubmit { store.save() }
            .help(T("Pixels on the longer side, \(OutputSize.bounds.lowerBound)–\(longEdgeCeiling). Frames are never enlarged.",
                    "长边像素数：\(OutputSize.bounds.lowerBound)–\(longEdgeCeiling)。照片不会被放大。"))
    }

    /// The pixels this recipe writes **for the frame on the canvas** — and, in
    /// a batch, the fact that the others are their own shape.
    ///
    /// Said about one named frame rather than about "the export", because
    /// under Original a batch has as many answers as it has frames and under a
    /// long edge it still has one answer per aspect ratio. Naming which frame
    /// it is is the difference between a read-out and a claim.
    private var resultingSizeLine: String {
        let source = nameContext.pixelSize
        let out = recipe.wrappedValue.outputSize.pixels(for: source) ?? source
        guard let px = Self.formattedPixelSize(out) else {
            return T("Reading image size…", "正在读取照片尺寸…")
        }
        guard batch.count > 1 else { return px }
        let others = batch.count - 1
        return recipe.wrappedValue.outputSize.isOriginal
            ? T("\(px) for this frame · \(others) more at their own sizes", "当前照片 \(px) · 另有 \(others) 张保留各自尺寸")
            : T("\(px) for this frame · \(others) more, each keeping its own shape, none enlarged",
                "当前照片 \(px) · 另有 \(others) 张保持各自比例，均不放大")
    }

    /// A photo switch briefly exposes an unset geometry while the new frame
    /// is decoded. The export rail remains mounted, so never bridge those
    /// transitional (or malformed) floating-point dimensions to `Int`.
    static func formattedPixelSize(_ size: CGSize) -> String? {
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0,
              size.width < CGFloat(Int.max), size.height < CGFloat(Int.max) else { return nil }
        return "\(Int(size.width)) × \(Int(size.height)) px"
    }

    private var resultingSizeHelp: String {
        recipe.wrappedValue.outputSize.isOriginal
            ? T("Every frame is written at its own pixels, after the crop and the straighten.",
                "每张照片在裁剪和拉直后按自身像素尺寸写出。")
            : T("Every frame is resampled so its longer side is \(recipe.wrappedValue.outputSize.edge ?? currentLongEdge) px. A portrait and a landscape in the same batch therefore come out the same size on their long side and keep their own shape. A frame already smaller than that is written at its own pixels — nothing is ever enlarged.",
                "每张照片的长边调整为 \(recipe.wrappedValue.outputSize.edge ?? currentLongEdge) px，横竖照片保持各自比例。较小的照片保留原尺寸，不会放大。")
    }

    /// `notes.md`: "Open with allows the user to select the default open_app."
    ///
    /// **The only way in.** It used to be reachable from here, from the Size
    /// row's "..." and from the section's — three doors onto one pill, two of
    /// them invisible until opened. This is the explicit one and the other two
    /// are gone.
    private var openWithRow: some View {
        HStack(spacing: 0) {
            Text(T("Open With", "打开方式")).font(bodyLabel).foregroundStyle(Theme.Ink.secondary)
                .frame(width: labelColumn, alignment: .leading)
            PillField(title: recipe.wrappedValue.openWith?.name ?? T("None", "无"), font: bodyLabel,
                      help: T("Hand the finished files to this application when the export ends.",
                              "导出完成后用此应用打开生成的文件。")) {
                openWithItems
            }
        }
        .frame(height: Theme.Metric.gridControl)
        .frame(height: bodyRowHeight, alignment: .top)
    }

    @ViewBuilder private var openWithItems: some View {
        Button(T("None", "无")) { recipe.wrappedValue.openWith = nil }
        if !OpenWithCatalog.apps.isEmpty { Divider() }
        ForEach(OpenWithCatalog.apps, id: \.path) { app in
            Button(app.name) { recipe.wrappedValue.openWith = app }
        }
    }

    private var summarySection: some View {
        // **Open by default.** It was shut, which put the one view that
        // states the whole recipe in one place behind a click, and left the
        // rail's bottom third empty to do it. Everything else on this page
        // is a control; this is the read-back, and a read-back nobody opens
        // is a read-back that is not checked.
        // The summary is a read-out; "copy" is the one thing a read-out is
        // for, and it is the block's only action — kept, as its `•••`.
        PanelSection(T("Summary", "摘要"), key: "exportSummary", menu: sectionMenu {
            Button(T("Copy Summary", "复制摘要")) {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(summaryLines.joined(separator: "\n"), forType: .string)
            }
        }) {
            Well(padding: wellPadding, vertical: wellVertical, inset: wellInset, fill: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(summaryLines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(bodyValue).foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    // **The proof is a switch on the result, so it lives in the
                    // block that describes the result.** It was a labelled
                    // button in the stage header, then a menu item, then a row
                    // under the recipe *list* — none of which is what it is:
                    // "show me what this will produce" is a state you turn on
                    // beside the description of what it will produce
                    // (UI-SPEC §2.16c).
                    proofRow
                        .padding(.top, Theme.Metric.space4)
                }
            }
        }
    }

    // MARK: - the footer

    /// The export affordance, in the card's lower third — which the drawing
    /// leaves empty, because it draws no way to start an export anywhere in
    /// it. The user's decision put the button here, with the progress and the
    /// result beside it: a page that cannot export is not a page, so this is
    /// part of the page rather than an addition to it.
    private var footer: some View {
        VStack(spacing: Theme.Metric.space8) {
            if let problem = store.problem { message(problem, warning: true) }
            if let note { message(note.text, warning: note.warning) }
            HStack(spacing: Theme.Metric.space8) {
                if running, let p = session.exportProgress {
                    ProgressView(value: p).controlSize(.small).frame(width: 70)
                }
                Text(running ? T("Exporting…", "正在导出…") : exportButtonTitle)
                    .font(Theme.Font.caption).foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                // The page has exactly one primary action, so it is drawn as
                // one (UI-SPEC §3.6): accent-filled, same inner stroke as
                // every other control. It used to be the system's default
                // button, which in a dark rail read as a grey word.
                primaryButton(running ? T("Exporting…", "正在导出…") : T("Export", "导出"),
                              enabled: !running && !batch.isEmpty && store.selected != nil) { run() }
            }
        }
        .padding(.horizontal, compact ? Theme.Metric.modernContentInset : M.wellPadding + 4)
        .padding(.vertical, compact ? 12 : 8)
        .overlay(alignment: .top) { Rectangle().fill(Theme.ruleSoft).frame(height: 1) }
    }

    /// The one primary button on this page.
    private func primaryButton(_ title: String, enabled: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(bodyLabel)
                .foregroundStyle(enabled ? Theme.card : Theme.text.opacity(Theme.disabledOpacity))
                .padding(.horizontal, 12)
                .frame(height: bodyRowHeight)
                .pillSurface(base: enabled ? Theme.accent : Theme.pill, wash: !enabled)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .disabled(!enabled)
        .help(enabled ? T("Write the selected images with this recipe", "使用此配方导出所选照片")
                      : T("Pick at least one image and one recipe first", "请先选择至少一张照片和一个配方"))
    }

    private var exportButtonTitle: String {
        switch batch.count {
        case 0: T("No images selected", "未选择照片")
        default: imageCount(batch.count) + " · " + (store.selected?.name ?? "")
        }
    }

    private func imageCount(_ count: Int) -> String {
        count == 1 ? T("1 image", "1 张照片") : T("\(count) images", "\(count) 张照片")
    }

    private func message(_ text: String, warning: Bool) -> some View {
        Text(text)
            .font(Theme.Font.caption)
            .foregroundStyle(warning ? Theme.exportAccent : Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - the centre

    /// The proof, on the ground — Viewer mode's centre pane. Grid mode does not
    /// put cells here at all: the grid card takes this space and the filmstrip
    /// card's together, which is the correction the second drawing makes.
    private var centre: some View {
        viewerPane
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.ground)
    }

    /// The bar's reserved strip: ground, with the pill floating on it.
    ///
    /// The strip is *reserved* rather than overlaid, which is the editor's
    /// arrangement and is there for the same reason — it is the only one in
    /// which a picture fitted to the pane is never partly under a toolbar.
    private var barStrip: some View {
        topBar
            .padding(.horizontal, Theme.Metric.barInset)
            .padding(.top, Theme.Metric.barTop)
            .padding(.bottom, Theme.Metric.barTop)
            .frame(maxWidth: .infinity)
            .background(Theme.ground)
    }

    /// Viewer's middle column: the bar's strip, then the proof.
    private var centreWithBar: some View {
        VStack(spacing: 0) {
            barStrip
            centre
        }
    }

    /// What sits to the right of the settings card. In Viewer it is the proof
    /// on the ground with the filmstrip card beside it; in Grid the drawing
    /// makes the centre pane and the filmstrip **one card** — x 634.64 width
    /// 2350.54 against a window 2981.27 wide, so it starts one gap right of
    /// the settings card and ends at the window's edge — and the grid lives
    /// inside that.
    ///
    /// **The gap is 6 pt, not the drawing's 3.9.** The drawing measures 7.81
    /// units between the two cards, which is 3.9 pt — but the resize handle
    /// has to live between them in both modes or the settings card cannot be
    /// dragged in Grid, and the handle is `PanelResizeHandle.hitWidth`, 6 pt.
    /// Adding a spacer to make up the drawing's number would put 9.9 pt there
    /// and separate the two cards further than anything draws them. So the
    /// handle *is* the gap, and the 2.1 pt between 6 and 3.9 is what the
    /// control costs. `Theme.Metric.Export.gridGap` is not used for it.
    ///
    /// A `ZStack` rather than a bare `@ViewBuilder` switch: a transition keeps
    /// both branches alive while it runs, and a modifier applied to the
    /// conditional is applied to *each* of them — which meant two hover bands
    /// and two collapse tabs for the length of every mode change. One
    /// container, one overlay, and only its contents swap.
    private var rightOfSettings: some View {
        ZStack {
            switch mode {
            case .viewer:
                HStack(spacing: 0) {
                    centreWithBar
                    PanelResizeHandle(side: .leadingEdge, range: M.rightRange,
                                      width: $rightWidth.width)
                    stripPanel
                        .frame(width: rightWidth.width)
                }
                .transition(.opacity)
            case .grid:
                VStack(spacing: 0) {
                    barStrip
                    gridCard
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// What is on the pane: the file's own picture once one has been written
    /// and it carries one, the render otherwise. **Nothing on this page asks
    /// which**, and there is no caption, badge or border that says so — the
    /// whole point is that after an export the pane is not a prediction, and a
    /// label announcing the difference would turn it back into one.
    private var displayImage: CGImage? { filePreview ?? proof?.displayImage }

    private var viewerPane: some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                ZStack {
                    if let shown = displayImage {
                        Image(decorative: shown, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: fitted.width * zoom, height: fitted.height * zoom)
                    } else if proving {
                        VStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(T("Rendering the preview…", "正在渲染预览…"))
                                .font(bodyLabel).foregroundStyle(Theme.Ink.tertiary)
                        }
                    } else {
                        Text(worklist.isEmpty
                             ? T("Nothing is selected. ⌘-click images in the filmstrip to add them.",
                                 "尚未选择照片。按住 ⌘ 点击胶片条中的照片可将其加入导出。")
                             : session.selection == nil
                               ? T("No frame is open. Choose one from the strip.", "尚未打开照片，请从胶片条中选择。")
                               : T("Nothing to prove for this recipe.", "此配方暂无可预览的内容。"))
                            .font(bodyLabel).foregroundStyle(Theme.dim)
                    }
                }
                .frame(width: max(geo.size.width, fitted.width * zoom),
                       height: max(geo.size.height, fitted.height * zoom))
                .overlay(alignment: .bottom) { proofCaption }
            }
            .onAppear { paneSize = geo.size }
            .onChange(of: geo.size) { _, s in paneSize = s }
        }
        .transition(.opacity)
    }

    /// The proof's size on screen at 100 %: the picture fitted into the pane
    /// with the page's own air around it.
    private var fitted: CGSize {
        guard let shown = displayImage else { return CGSize(width: 320, height: 213) }
        let w = CGFloat(shown.width), h = CGFloat(shown.height)
        guard w > 0, h > 0, paneSize.width > 1 else { return CGSize(width: 320, height: 213) }
        let avail = CGSize(width: max(1, paneSize.width - M.proofInset * 2),
                           height: max(1, paneSize.height - M.proofInset * 2 - 44))
        let s = min(avail.width / w, avail.height / h, 1)
        return CGSize(width: (w * s).rounded(), height: (h * s).rounded())
    }

    /// RFC-018 §6's three statements in one place: which space the proof is in
    /// and that the canvas is in another, what the destination could not hold,
    /// and whether this is a proof at all. The middle one is proportional on
    /// purpose — "a saturated frame into sRGB is worth a word, a frame that
    /// fits is worth silence" — so it is absent when the frame fits.
    ///
    /// `isPlaceholder` is false now that the output transform has landed, and
    /// the branch stays because the API keeps the field: it is what a future
    /// approximation — a lower-resolution proof, a cached one — would set.
    @ViewBuilder private var proofCaption: some View {
        if let proof, session.selection != nil {
            // **What it is, then what is wrong with it.** The caveats used to
            // come first, so the first line of the caption was "44 % rolled
            // into Display P3" — a statement about a picture that had not yet
            // been identified as a preview of anything. Naming the thing costs
            // one line and is what the rest of the caption is then about.
            VStack(spacing: 3) {
                Text(spaceLine(proof)).foregroundStyle(Theme.secondaryText)
                // A full-size render takes a moment, and the picture on screen
                // is the **previous** one while it does. A spinner on its own
                // said "something is happening"; it did not say that what you
                // are looking at is out of date, which is the only part that
                // can mislead. So it says it.
                if proving {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini).scaleEffect(0.55)
                        Text(T("Updating preview…", "正在更新预览…")).foregroundStyle(Theme.dim)
                    }
                }
                if proof.isPlaceholder {
                    Text(T("Placeholder — these pixels are not the ones the file will carry.",
                           "占位预览 — 这些像素并非最终文件内容。"))
                        .foregroundStyle(Theme.exportAccent)
                }
                let caveats = ProofCaveat.lines(for: proof)
                ForEach(caveats, id: \.text) { caveat in
                    Text(caveat.text)
                        .foregroundStyle(caveat.isWarning ? Theme.exportAccent : Theme.dim)
                }
            }
            .font(Theme.Font.caption)
            .help(captionHelp(proof))
            .multilineTextAlignment(.center)
            .frame(maxWidth: 560)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.card.opacity(0.9), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.bottom, 10)
        }
    }

    /// The space, and **only** the space. The size is stated two other places
    /// — the Size row and the Summary — and the canvas is worth mentioning
    /// only when it is a different space, which is the case RFC-018 §6 is
    /// actually about. Naming the file's pixels and both spaces in one line
    /// told a photographer nothing they could act on.
    /// The long version, one hover away: what a proof is, one size, and both
    /// spaces. Cheap to reach, and not in the way.
    private func captionHelp(_ proof: SoftProof) -> String {
        // The size is the file's, carried by the proof independently of the
        // smaller display image. It used to say "the file *will be*", which was
        // true while the proof was a sample rather than the same render.
        let pixels = "\(Int(proof.filePixelSize.width)) × \(Int(proof.filePixelSize.height))"
        let canvas = session.workingSpaceName
        var lines = [
            T("The picture above is a proof of the file: the same render and conversion as the export, shown downsampled for the pane.",
              "上方画面是导出文件的软打样：采用相同的渲染与转换，并为此面板缩小显示。"),
            T("The file is \(pixels) px, in \(proof.targetName).", "文件尺寸为 \(pixels) px，色彩空间为 \(proof.targetName)。"),
        ]
        if proof.targetName != canvas { lines.append(T("The canvas is in \(canvas).", "编辑画布使用 \(canvas)。")) }
        if let detail = ProofCaveat.explain(proof) { lines.append(detail) }
        return lines.joined(separator: "\n")
    }

    /// The one-line caption. See `captionHelp` for the rest of it.
    ///
    /// **It leads with what the picture is.** It used to read "Proof in
    /// Display P3 · the canvas is Linear ProPhoto", which asks the reader to
    /// hold two spaces and two meanings of the word *canvas* — the pane in
    /// front of them, and the working space — before it has told them what
    /// they are looking at. The working space is still one hover away in
    /// `captionHelp`, where a second space is a detail rather than a
    /// comparison the caption makes on the reader's behalf.
    private func spaceLine(_ proof: SoftProof) -> String {
        T("Output preview · \(proof.targetName)", "导出预览 · \(proof.targetName)")
    }

    /// Grid mode's card: the centre pane and the filmstrip as one, from just
    /// right of the settings card to the window's right edge, with the grid
    /// inside it. The drawing's own card — see `rightOfSettings`.
    ///
    /// The columns are the bar's detented slider and nothing else, so the grid
    /// never chooses a size for itself: two panes of different widths show the
    /// same count and a different thumbnail, which is Finder's behaviour and
    /// what the user asked for.
    ///
    /// Laid out from the leading edge rather than centred, at the drawing's
    /// own inset: the pitch is what falls out of the card's width and the
    /// column count, and a thumbnail takes the drawing's 0.66 of its column,
    /// so the gap between two is the other third at every count.
    private var gridCard: some View {
        GeometryReader { geo in
            let pitch = max(1, geo.size.width - M.gridPadding) / CGFloat(gridColumns)
            let cell = pitch * M.gridCellFraction
            let gap = pitch - cell
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: gap),
                                         count: gridColumns),
                          alignment: .leading,
                          spacing: M.gridRowSpacing) {
                    if worklist.isEmpty {
                        emptyWorklist
                    } else {
                        ForEach(worklist) { frame in
                            ExportGridCell(frame: frame,
                                           chosen: frame.id == session.selection,
                                           state: session.frameStates[frame.id] ?? .unprocessed,
                                           width: cell)
                                .onTapGesture { tap(frame) }
                                .contextMenu {
                                    Button(T("Reveal in Finder", "在访达中显示")) {
                                        NSWorkspace.shared.activateFileViewerSelecting([frame.id])
                                    }
                                }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, M.gridPadding)
                .padding(.top, M.gridTopInset)
                .padding(.bottom, M.gridTopInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .railCard()
        .transition(.opacity)
    }

    // MARK: - the right card

    // Internal so the export-panel test can render the smallest view that owns
    // the worklist ForEach, rather than trying to count cells in the full page.
    var stripPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .center, spacing: M.cellLabelGap) {
                if worklist.isEmpty {
                    emptyWorklist
                } else {
                    ForEach(worklist) { frame in
                        ExportStripCell(frame: frame,
                                        chosen: frame.id == session.selection,
                                        state: session.frameStates[frame.id] ?? .unprocessed)
                            .onTapGesture { tap(frame) }
                    }
                }
            }
            .padding(.horizontal, M.thumbMargin)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .railCard()
    }

    private var emptyWorklist: some View {
        Text(T("Nothing is selected. ⌘-click images in the filmstrip to add them.",
               "尚未选择照片。按住 ⌘ 点击胶片条中的照片可将其加入导出。"))
            .font(bodyLabel)
            .foregroundStyle(Theme.dim)
            .multilineTextAlignment(.center)
            .padding(20)
    }

    // MARK: - derived strings

    private var folderOptions: [ExportFolder] {
        if case .fixed(let p) = recipe.wrappedValue.folder { return [.besideOriginal, .fixed(path: p)] }
        return [.besideOriginal]
    }

    private func folderLabel(_ f: ExportFolder) -> String {
        switch f {
        case .besideOriginal: T("Beside the original", "与原片同目录")
        case .fixed(let p): (p as NSString).abbreviatingWithTildeInPath
        }
    }

    /// The naming context for the frame on the canvas, or the model sample
    /// when there is none — so the page shows a real filename whenever it can.
    private var nameContext: NamingRule.Context {
        guard let sel = session.selection else { return NamingRule.sampleContext }
        let source = session.sourceImageSize
        let sourceEdge = max(source.width, source.height)
        // During `select` the previous frame's long edge may still be set
        // while the new source is zero. Dividing those produces infinity and
        // the settings rail is evaluated before the decode has finished.
        let pixels: CGSize
        if source.width.isFinite, source.height.isFinite, sourceEdge > 0,
           session.sourceLongEdge.isFinite {
            let out = session.geometry.outputSize(for: source)
            let scale = session.sourceLongEdge > 0 ? session.sourceLongEdge / sourceEdge : 1
            pixels = CGSize(width: (out.width * scale).rounded(),
                            height: (out.height * scale).rounded())
        } else {
            pixels = .zero
        }
        return NamingRule.Context(
            originalName: sel.deletingPathExtension().lastPathComponent,
            filmStock: session.params.filmStock,
            printStock: session.params.printStock,
            pixelSize: pixels,
            counter: 1, date: Date())
    }

    private var sampleName: String {
        recipe.wrappedValue.naming.stem(nameContext) + "." + recipe.wrappedValue.format.ext
    }

    private var writePath: String {
        let source = session.selection ?? URL(fileURLWithPath: "/Users/you/Pictures/_DSC4037.NEF")
        return recipe.wrappedValue.directory(for: source).path
    }

    private var summaryLines: [String] {
        let r = recipe.wrappedValue
        var lines = [
            T("Recipe  \(r.name)", "配方  \(r.name)"),
            T("Images  \(batch.count) of \(session.frames.count)", "照片  \(batch.count)/\(session.frames.count)"),
            T("File name  \(sampleName)", "文件名  \(sampleName)"),
            T("Format  \(r.format.shortLabel) · \(r.format.bitDepth) bit",
              "格式  \(r.format.shortLabel) · \(r.format.bitDepth) bit"),
            T("Size  \(resultingSizeLine)", "尺寸  \(resultingSizeLine)"),
        ]
        if r.format.takesColorSpace {
            let name = ColorSpaceCatalog.name(for: r.colorSpace) ?? T("Unknown profile", "未知配置文件")
            lines.append(T("Colour space  \(name)", "色彩空间  \(name)"))
        } else {
            lines.append(T("Colour space  untagged (density)", "色彩空间  未标记（密度数据）"))
        }
        if let proof, session.selection != nil {
            lines.append(T("Proof  \(proof.targetName)", "软打样  \(proof.targetName)"))
        }
        lines.append(T("Folder  \(destinationSummary)", "文件夹  \(destinationSummary)"))
        return lines
    }

    // MARK: - helpers

    /// A labelled row: the label in the drawing's own column, the control
    /// after it, and the pair on the drawing's row height.
    ///
    /// **`maxWidth: .infinity, alignment: .leading` is load-bearing.** A
    /// `VStack` centres its children, so a row whose control is narrower than
    /// the well — a checkbox is 21 pt — collapses to the width of its own
    /// contents and is then centred, which puts the label halfway across the
    /// well while every neighbouring row's label is at the column. It filled
    /// by accident before, because every control in a row happened to want all
    /// the width it could get.
    private func row<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 0) {
            // `Ink.secondary`, as every label in the editor is: a label is the
            // thing being asked and the control beside it is the thing being
            // said. Drawn in `Theme.text` they were the same weight, the same
            // size and the same colour as the values, which is the "everything
            // competing, nothing leading" the rails were rebuilt to fix — and
            // this page had stayed behind. `PillMenu`'s own rows were already
            // secondary, so the well did not even agree with itself.
            Text(label).font(bodyLabel).foregroundStyle(Theme.Ink.secondary)
                .lineLimit(1)
                .frame(width: labelColumn, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The ink band, then the row box — see `ScrubSlider` for why both.
        .frame(height: Theme.Metric.gridControl)
        .frame(height: bodyRowHeight, alignment: .top)
    }

    /// One item of the Existing File menu. The check mark is the mark the
    /// app's other menus use for the chosen row.
    @ViewBuilder
    private func existingFileButton(_ policy: ExistingFilePolicy) -> some View {
        let chosen = policy == recipe.wrappedValue.existing
        Button {
            recipe.wrappedValue.existing = policy
        } label: {
            if chosen {
                Label(policy.localizedLabel, systemImage: "checkmark")
            } else {
                Text(policy.localizedLabel)
            }
        }
    }

    /// `PanelSection`'s menu is an `AnyView` closure; this keeps the call sites
    /// reading like a menu rather than like a cast.
    private func sectionMenu<V: View>(@ViewBuilder _ content: @escaping () -> V) -> () -> AnyView {
        { AnyView(content()) }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = T("Choose", "选择")
        panel.message = T("Where should this recipe write its files?", "此配方应将文件写入哪个文件夹？")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        recipe.wrappedValue.folder = .fixed(path: url.path)
    }

    // MARK: - running it

    /// `notes.md`: "the export setting is applied to all the selected images".
    /// The batch runs through the one frame at a time the engine can hold, so
    /// each is selected, developed and written in turn, and the frame the
    /// person was looking at is put back afterwards.
    private func run() {
        guard let r = store.selected, !batch.isEmpty, !running else { return }
        running = true
        note = nil
        // The file on the pane is about to be replaced by one that does not
        // exist yet; until it does, the render stands.
        filePreview = nil
        Task {
            defer { running = false }
            let home = session.selection
            let urls = batch
            var written: [URL] = []
            /// The file the pane will show once the run is over: the one
            /// written for the frame the person was looking at.
            ///
            /// **A batch writes several files and the pane shows one picture**,
            /// and the frame the person was viewing is the one they were
            /// looking at when they pressed Export — `notes.md`'s "the viewed
            /// image stays as the one the user is previously on" is about
            /// exactly that. If their frame was not in the batch, the first
            /// file written is the fallback.
            var shown: URL?
            var problems: [String] = []
            var fellBack = false
            for (i, url) in urls.enumerated() {
                session.exportProgress = Double(i) / Double(urls.count)
                // `select`, not `click`: the run has to put each frame on the
                // canvas — the exporter reads the open frame — and a click
                // would collapse the picked set to that one frame on the first
                // pass and empty the batch it is walking.
                if session.selection != url { session.select(url) }
                guard let sid = await session.ensureDeveloped() else {
                    problems.append(T("\(url.lastPathComponent) is still developing.",
                                      "\(url.lastPathComponent) 仍在冲洗处理中。"))
                    continue
                }
                do {
                    let out = try await Exporter.export(session: session, recipe: r,
                                                        context: nameContext, sessionID: sid)
                    switch out {
                    case .wrote(let files, _, let fb):
                        written += files
                        if url == home, let first = files.first { shown = first }
                        fellBack = fellBack || fb
                    case .skipped(let existing):
                        problems.append(T("\(existing.lastPathComponent) already exists — skipped.",
                                          "\(existing.lastPathComponent) 已存在，已跳过。"))
                    }
                } catch {
                    problems.append("\(url.lastPathComponent): \(EngineMessage.userFacing(error))")
                }
            }
            session.exportProgress = nil
            if let home, session.selection != home { session.select(home) }
            if let target = shown ?? written.first { filePreview = Self.embeddedPreview(of: target) }
            if fellBack {
                problems.append(T("That profile is not on this machine — the files were tagged Display P3 instead.",
                                  "本机没有此色彩配置文件；文件已改为标记 Display P3。"))
            }
            if !written.isEmpty, let app = r.openWith {
                NSWorkspace.shared.open(written,
                                        withApplicationAt: URL(fileURLWithPath: app.path),
                                        configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    guard let error else { return }
                    Task { @MainActor in
                        note = ResultNote(text: T("\(app.name) would not open them: ",
                                                  "\(app.name) 无法打开文件：")
                                          + error.localizedDescription, warning: true)
                    }
                }
            }
            var parts: [String] = written.isEmpty
                ? [T("Nothing was written.", "未写入任何文件。")]
                : [T("Wrote ", "已写入：") + written.map(\.lastPathComponent).joined(separator: ", ")]
            parts += problems
            note = ResultNote(text: parts.joined(separator: "\n"), warning: !problems.isEmpty)
        }
    }
}

// The recipe model keeps stable English identifiers in JSON. Only these
// presentation names follow the UI language.
private extension NameToken {
    @MainActor var localizedLabel: String {
        switch self {
        case .originalName: T("Org. Name", "原文件名")
        case .filmStock: T("Film", "胶片")
        case .printStock: T("Print", "相纸")
        case .date: T("Date", "日期")
        }
    }

    @MainActor var localizedHelpName: String {
        switch self {
        case .originalName: T("Original Name", "原文件名")
        case .filmStock: T("Film", "胶片")
        case .printStock: T("Print", "相纸")
        case .date: T("Date", "日期")
        }
    }
}

private extension ExistingFilePolicy {
    @MainActor var localizedLabel: String {
        switch self {
        case .addSuffix: T("Add a suffix", "添加后缀")
        case .overwrite: T("Overwrite", "覆盖")
        case .skip: T("Skip", "跳过")
        }
    }
}

// MARK: - the strip's cell

/// One thumbnail down the right-hand card.
///
/// `notes.md`, and it is right: "Only the chosen image gets a white frame
/// around it, and the actual image name got displayed, the non-selected ones
/// are just there (no actual grey frame around it). The export batch is the
/// worklist, while `chosen` is only the current preview, so filenames remain
/// visible for every item even though only one gets the white frame.
///
/// This was briefly changed to stroke every cell in the drawing's `#686969`,
/// on a reading of the grid drawing's two rectangles per cell as chrome. They
/// are not: they are two example images — a white-framed 3:2 landscape and a
/// grey-framed 2:3 portrait, overlapping, each hugging its own aspect. The
/// drawing was a diagram of the behaviour, and the notes had described it
/// correctly from the start.
private struct ExportStripCell: View {
    let frame: Frame
    let chosen: Bool
    /// Unread by this cell; kept as the guard test's construction seam.
    let state: FrameState
    @State private var image: CGImage?

    /// Keep the frame on the fitted image, not on the strip's fixed-height
    /// layout box.  The latter is what made a portrait thumbnail look as if
    /// it had a square frame: the box is deliberately shared by every cell,
    /// while the picture inside it has its own aspect ratio.
    private var frameStroke: some View {
        RoundedRectangle(cornerRadius: 2)
            .stroke(Theme.selectionFrame, lineWidth: chosen ? 2 : 0)
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                let box = CGSize(width: geometry.size.width,
                                 height: Theme.Metric.Export.thumbMax)
                ZStack {
                    Color.clear
                    if let image {
                        let size = exportFittedImageSize(
                            imageSize: CGSize(width: image.width, height: image.height), in: box)
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .frame(width: size.width, height: size.height)
                            .overlay(frameStroke)
                    } else {
                        let size = exportFittedImageSize(imageSize: CGSize(width: 3, height: 2), in: box)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.well)
                            .frame(width: size.width, height: size.height)
                            .overlay(Image(systemName: "photo").foregroundStyle(Theme.dim))
                            .overlay(frameStroke)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Metric.Export.thumbMax)
            .frame(maxWidth: .infinity)
            Text(frame.name)
                .font(Theme.Font.stockItem)
                .foregroundStyle(Theme.text)
                .lineLimit(1).truncationMode(.middle)
        }
        .help(frame.name)
        .task(id: frame.id) {
            image = await ThumbnailCache.shared.thumbnail(for: frame.id, maxPixel: 1024)
        }
        .onReceive(NotificationCenter.default.publisher(for: .thumbnailUpdated)) { n in
            guard (n.object as? URL) == frame.id else { return }
            Task { image = await ThumbnailCache.shared.thumbnail(for: frame.id, maxPixel: 1024) }
        }
    }
}

// MARK: - the grid's cell

/// One cell of the grid card: the thumbnail with its filename beneath.
///
/// Not the filmstrip's cell. The editor's strip is a worklist and draws each
/// frame on a lighter plate inside a 3:2 box; the drawing's grid card draws
/// the frame itself on the card, stroked, at whatever shape it is — a
/// landscape one is wide and short, a portrait one is the other way about —
/// and its name centred under it. The two are different cells that happen to
/// show the same picture.
///
/// The white frame marks the **chosen** item and nothing else — the grid
/// drawing's second rectangle in each cell is a grey-framed *example*, not a
/// rule about unselected cells. It hugs the picture rather than boxing the
/// cell: 3:2 on a landscape frame of film, 2:3 on a portrait one, which is how
/// the editor's own filmstrip draws it. The cell keeps its pitch for layout;
/// what is drawn inside it is the picture's own size.
private struct ExportGridCell: View {
    let frame: Frame
    let chosen: Bool
    /// Unread by this cell; kept as the guard test's construction seam.
    let state: FrameState
    /// The column's thumbnail width, from the card's width and the slider.
    let width: CGFloat
    @State private var image: CGImage?

    /// The box a picture is fitted into, and the cell's own width. Nearly
    /// square, and slightly taller — the drawing's two example frames are a
    /// landscape filling the box's width and a portrait filling its height,
    /// both centred, which is only possible if the box is a little taller than
    /// it is wide.
    private var box: CGSize { CGSize(width: width, height: width * 1.03) }

    /// The stroke is on the **picture**, not on the box: the drawing's
    /// landscape frame hugs a landscape frame of film and its portrait hugs a
    /// portrait one, so a wide picture is outlined wide. The fitted size is
    /// calculated explicitly from the pixels and the box before the overlay
    /// is attached, rather than relying on SwiftUI's proposed size.
    private var frameStroke: some View {
        RoundedRectangle(cornerRadius: 2)
            .stroke(Theme.selectionFrame, lineWidth: chosen ? 2 : 0)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Color.clear
                    .frame(width: box.width, height: box.height)
                        .overlay {
                            if let image {
                                let size = exportFittedImageSize(
                                    imageSize: CGSize(width: image.width, height: image.height), in: box)
                                Image(decorative: image, scale: 1)
                                    .resizable()
                                    .frame(width: size.width, height: size.height)
                                    .overlay(frameStroke)
                            } else {
                                // Nothing of its own to hug yet, so a 3:2 stand-in
                                // on the card's colour.
                                let size = exportFittedImageSize(imageSize: CGSize(width: 3, height: 2), in: box)
                                Rectangle().fill(Theme.card)
                                    .frame(width: size.width, height: size.height)
                                    .overlay(frameStroke)
                            }
                        }
            }
            Text(frame.name)
                .font(Theme.Font.stockItem)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: box.width)
        }
        .help(frame.name)
        .task(id: frame.id) {
            image = await ThumbnailCache.shared.thumbnail(for: frame.id, maxPixel: 1024)
        }
        .onReceive(NotificationCenter.default.publisher(for: .thumbnailUpdated)) { n in
            guard (n.object as? URL) == frame.id else { return }
            Task { image = await ThumbnailCache.shared.thumbnail(for: frame.id, maxPixel: 1024) }
        }
    }
}

/// Return the exact size an export thumbnail occupies when aspect-fitted into
/// its layout box. Keeping this calculation explicit makes the selection
/// outline attach to the picture's bounds, rather than to SwiftUI's proposed
/// box (which can be wider than a portrait image).
func exportFittedImageSize(imageSize: CGSize, in box: CGSize) -> CGSize {
    guard imageSize.width > 0, imageSize.height > 0,
          box.width > 0, box.height > 0 else { return .zero }
    let scale = min(box.width / imageSize.width, box.height / imageSize.height)
    return CGSize(width: (imageSize.width * scale).rounded(),
                  height: (imageSize.height * scale).rounded())
}

// MARK: - the pill chrome

/// The capsule `PillMenu` draws, for the rows whose menu is not a plain list:
/// the format and its bit depth, which are one setting in two controls, and
/// Open With, whose list is the machine's installed applications.
///
/// The chrome is written out rather than `PillMenu` generalised because
/// `PillMenu` lives in `Controls/` and belongs to the whole app; when a third
/// caller wants this shape, that is the moment to give it a home there.
/// A pill's own text inset, shared by the `PillField` pill and the `TextField`
/// that plays the same role one row down — the two are the same surface and
/// had different padding (9 and 8), which is half of why their widths
/// differed.
///
/// A file-level name and not a static on `PillField`: that type is generic, and
/// Swift will not resolve a static member of a generic type from a call site
/// that does not name its parameter. (The same trap produced
/// `PillGeometry` in `Controls/FormatPicker.swift`.)
enum PillFieldGeometry {
    /// **The same numbers `PillMenu` uses.** The two are the same surface and
    /// share a table, so they are one geometry: a 9 pt text inset against the
    /// other's 10 and a 13.9 pt height against its 16 put every `PillField`
    /// row 5 pt right, 2 pt shorter and 4 pt narrower than every `PillMenu`
    /// row — the user's "大大小小" in one section.
    static let textInset: CGFloat = PillGeometry.textInset
    static let chevronInset: CGFloat = PillGeometry.chevronInset
    static let chevron = PillGeometry.chevron
}

private struct PillField<MenuContent: View>: View {
    let title: String
    var dimmed = false
    /// **The body label**, in both homes. This used to default to the export
    /// drawing's own 11 pt face, which is what let the page keep a second
    /// scale after the editor had one; every call site passes `bodyLabel`
    /// now, and the default is the same face rather than a third one.
    var font: Font = Theme.Font.label
    var help: String?
    @ViewBuilder var menu: () -> MenuContent

    var body: some View {
        Menu { menu() } label: {
            HStack {
                Text(title).font(font)
                    .foregroundStyle(dimmed ? Theme.dim : Theme.text)
                    .padding(.leading, PillFieldGeometry.textInset)
                Spacer(minLength: 4)
                // `PillMenu`'s mark, not SF Symbols' double chevron. One
                // glyph for "there is more under this", everywhere — the two
                // pills sat in the same row wearing different ones.
                Triangle()
                    .stroke(dimmed ? Theme.dim : Theme.text,
                            style: StrokeStyle(lineWidth: 1, lineJoin: .round))
                    .frame(width: PillFieldGeometry.chevron.width,
                           height: PillFieldGeometry.chevron.height)
                    .padding(.trailing, PillFieldGeometry.chevronInset)
            }
            .frame(height: Theme.Metric.gridControl)
            .frame(maxWidth: .infinity)
            .pillSurface(base: Theme.pill)
            .contentShape(Capsule())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .rowEnabled(!dimmed, because: dimmed ? (help ?? "") : "")
        .modifier(DisabledReason(show: !dimmed && help != nil, reason: help ?? ""))
    }
}

// MARK: - what the destination could not hold

/// RFC-018 §6's middle statement, in words whose size follows the number: "a
/// saturated frame into sRGB is worth a word, a frame that fits is worth
/// silence."
///
/// Two things get said, because they are two different losses. *Compressed*
/// means the gamut map moved the pixel and it kept its detail at a lower
/// chroma; *clipped* means it ended up pinned to the container's edge and lost
/// detail. The second is the one worth interrupting for, so it is the one
/// drawn in the accent.
///
/// `compressedFraction` and not `movedFraction`: the latter is RFC §5.3's
/// literal counter — pixels the knee acted on — which reads ~1.0 on a plain
/// grey frame and is not a warning about anything.
enum ProofCaveat {
    struct Line: Hashable {
        var text: String
        var isWarning: Bool
    }

    /// Below this fraction the sentence is longer than the problem.
    static let silence = 0.0001      // 0.01 % of the frame
    /// At least this much and the wording stops being hedged.
    static let emphatic = 0.01       // 1 %

    /// **A number and a verb, and nothing else.** The verbs are the whole
    /// distinction — *rolled* kept its detail at a lower chroma, *clipped*
    /// lost it — and the sentences that used to spell that out are what the
    /// user asked to stop reading. `explain(_:)` is the same two statements
    /// for a tooltip, where they cost nothing.
    @MainActor static func lines(for proof: SoftProof) -> [Line] {
        var out: [Line] = []
        if proof.compressedFraction >= silence {
            out.append(Line(text: T("\(share(proof.compressedFraction)) rolled into \(proof.targetName)",
                                    "\(share(proof.compressedFraction)) 已压入 \(proof.targetName) 色域"),
                            isWarning: false))
        }
        if proof.clippedFraction >= silence {
            out.append(Line(text: T("\(share(proof.clippedFraction)) clipped in \(proof.targetName)",
                                    "\(share(proof.clippedFraction)) 在 \(proof.targetName) 中被裁切"),
                            isWarning: true))
        }
        return out
    }

    /// The long form, for wherever there is room to hover.
    @MainActor static func explain(_ proof: SoftProof) -> String? {
        guard !lines(for: proof).isEmpty else { return nil }
        var out: [String] = []
        if proof.compressedFraction >= silence {
            out.append(T("\(share(proof.compressedFraction)) of the frame is outside \(proof.targetName) and was rolled into it rather than cut off.",
                         "画面中 \(share(proof.compressedFraction)) 超出 \(proof.targetName) 色域，已压缩回色域内，未直接裁切。"))
        }
        if proof.clippedFraction >= silence {
            out.append(T("\(share(proof.clippedFraction)) of the frame sits on the edge of \(proof.targetName) and has lost detail.",
                         "画面中 \(share(proof.clippedFraction)) 落在 \(proof.targetName) 色域边界，细节已丢失。"))
        }
        return out.joined(separator: "\n")
    }

    @MainActor static func share(_ fraction: Double) -> String {
        if fraction >= emphatic { return "\(Int((fraction * 100).rounded())) %" }
        if fraction * 1000 < 1 { return T("Under 0.1 %", "低于 0.1 %") }
        return String(format: "%.1f %%", fraction * 100)
    }
}

// MARK: - Open With

/// The applications this machine says can open the recipe's format.
///
/// Asked once per extension and cached: `NSWorkspace`'s handler query wants a
/// file to ask about, so a throwaway one with the right suffix is made in the
/// temporary directory — cheaper and far more reliable than walking
/// `/Applications` and guessing at which bundles open a TIFF.
@MainActor
enum OpenWithCatalog {
    private(set) static var apps: [OpenWith] = []
    private static var cache: [String: [OpenWith]] = [:]

    static func refresh(for format: ExportFormat) {
        let ext = format.ext
        if let hit = cache[ext] { apps = hit; return }
        let probe = FileManager.default.temporaryDirectory
            .appending(path: "spektralab-openwith-probe.\(ext)")
        FileManager.default.createFile(atPath: probe.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: probe) }
        let list = NSWorkspace.shared.urlsForApplications(toOpen: probe)
            .map { OpenWith(path: $0.path) }
            .filter { !$0.name.isEmpty }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        cache[ext] = list
        apps = list
    }
}

/// A glyph button on the export page's own bar — the editor's `BarIcon`, at
/// this page's metrics and inks.
///
/// Same rule as the editor's: ink, a hover wash, and nothing else. No plate
/// and no border, because the bar is flush; selection stays an accent glyph
/// rather than a background plate.
private struct ExportIcon: View {
    let glyph: String
    let help: String
    var selected = false
    var restOpacity: Double = 1
    var rotation: Double = 0
    var disabled = false
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: glyph)
                .font(.system(size: Theme.Metric.Export.modeGlyph, weight: .regular))
                .rotationEffect(.degrees(rotation))
                .foregroundStyle(ink)
                .frame(width: 24, height: Theme.Metric.Export.topBarHeight)
                .background {
                    if hovered && !disabled {
                        RoundedRectangle(cornerRadius: Theme.Metric.fieldRadius, style: .continuous)
                            .fill(Theme.buttonHoverWash)
                            .padding(.vertical, 4)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .help(help)
        .onHover { hovered = $0 }
    }

    private var ink: Color {
        if disabled { return Theme.text.opacity(Theme.disabledOpacity) }
        if selected { return Theme.exportAccent }
        return hovered ? Theme.text : Theme.text.opacity(restOpacity)
    }
}
