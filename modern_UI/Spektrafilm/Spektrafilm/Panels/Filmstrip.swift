//  Filmstrip.swift — the library. Thumbnails at one height, a white frame on
//  the open frame and a weaker one on the rest of the picked set, chevrons at
//  both ends, and the folder name with a count at the far left when there is
//  room.
//
//  Selection is the white frame and **nothing else** (PRD §5): the open
//  frame is marked by the strongest frame and a picked one by the same frame
//  held back, and no cell carries a state pip next to it.
//
//  Which frame a cell gets is `Session.framing(of:)`, not a comparison made
//  here — the Browse grid asks the same function, so the two surfaces cannot
//  draw a different set from the same state.
//
//  `LazyHStack` so a 500-image folder builds only what is visible; thumbnails
//  come from ImageIO off the main actor and are replaced by the rendered print
//  once a frame has been through the engine.

import AppKit
import SwiftUI
import ImageIO

struct Filmstrip: View {
    @Bindable var session: Session
    var compact = false
    var leadingInset: CGFloat = 0
    var trailingInset: CGFloat = 0

    @State private var batchEXIF = ""
    @State private var markFilter = PhotoMarkFilter()
    private var visibleFrames: [Frame] {
        guard compact && markFilter.isActive else { return session.frames }
        return session.frames.filter { markFilter.includes(session.photoMarks.marks(for: $0.id)) }
    }
    private var stripHeight: CGFloat { compact ? Theme.Metric.modernStripHeight : Theme.Metric.filmstripHeight }
    /// The strip's own leading inset. **Both states now inset by the same
    /// rule**: Traditional by the drawing's 10, Modern by the panel inset its
    /// photographs share with the inspector's labels. Modern used to inset by
    /// nothing while the chooser that replaces it inset by 20, so the same
    /// slot's first item moved 20 pt when the Film stage opened.
    /// **Zero.** The strip is a canvas overlay, and the canvas has one gutter
    /// (`modernSurfaceGutter`) which its container already applies — a second
    /// inset inside the strip put its first photograph 20 pt right of the
    /// histogram plate above it.
    private var stripInset: CGFloat { 0 }

    var body: some View {
        Group {
            if compact {
                VStack(spacing: Theme.Metric.space8) {
                    navigatorToolbar
                    thumbnails.frame(height: Theme.Metric.browserContentHeight)
                }
                .padding(Theme.Metric.browserInset)
                .frame(height: stripHeight)
                .modifier(EditorChromeSurface())
            } else {
                thumbnails.frame(height: stripHeight)
            }
        }
        .background(PhotoSelectAllShortcut(scope: visibleFrames.map(\.id)) {
            session.selectAllFrames(in: $0)
        })
        .task(id: session.frames.map(\.id)) { await session.photoMarks.preload(session.frames.map(\.id)) }
        .task(id: session.selectedFrames) {
            let urls = session.selectedFrames
            guard urls.count > 1 else { batchEXIF = ""; return }
            batchEXIF = ""
            let readouts = await Task.detached(priority: .utility) { urls.map { EXIFReadout.read($0) } }.value
            guard !Task.isCancelled else { return }
            batchEXIF = EXIFReadout.summary(readouts)
        }
    }

    private var thumbnails: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: leadingInset)
            if !compact {
                edgeButton("chevron.left", L(.helpPreviousFrame), enabled: !session.frames.isEmpty) { session.selectRelative(-1) }
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: compact ? Theme.Metric.space4 : 14) {
                        ForEach(visibleFrames) { frame in
                            FilmstripCell(frame: frame,
                                          framing: session.framing(of: frame.id),
                                          state: session.frameStates[frame.id] ?? .unprocessed,
                                          height: compact ? Theme.Metric.browserContentHeight : Theme.Metric.thumbHeight,
                                          cornerRadius: compact ? Theme.Metric.modernCardRadius : 2,
                                          modernSelection: compact,
                                          markLibrary: session.photoMarks,
                                          cropGeometry: session.thumbnailGeometry(for: frame.id))
                                .id(frame.id)
                                // The modifier is read here rather than
                                // declared as a second gesture: a plain
                                // `TapGesture` on macOS matches a ⌘-click too,
                                // so stacking one would fire both and a
                                // ⌘-click would collapse the set as well.
                                .onTapGesture {
                                    session.click(frame.id,
                                                  command: NSEvent.modifierFlags.contains(.command),
                                                  shift: NSEvent.modifierFlags.contains(.shift),
                                                  rangeScope: visibleFrames.map(\.id))
                                }
                                .contextMenu {
                                    SettingsClipboardMenu(session: session, frame: frame.id)
                                    Divider()
                                    Button(L(.helpRevealInFinder)) { NSWorkspace.shared.activateFileViewerSelecting([frame.id]) }
                                    Button(L(.helpResetDefaults)) {
                                        if frame.id == session.selection { session.resetParams(); session.resetAdjustments() }
                                        else { Sidecar.remove(for: frame.id) }
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, stripInset)
                    .frame(height: compact ? Theme.Metric.browserContentHeight : stripHeight)
                    .background(HorizontalStripWheelBridge())
                }
                .onChange(of: session.selection) { _, new in
                    if let new { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(new, anchor: .center) } }
                }
            }
            if !compact {
                edgeButton("chevron.right", L(.helpNextFrame), enabled: !session.frames.isEmpty) { session.selectRelative(1) }
            }
            Spacer().frame(width: trailingInset)
        }
        .overlay(alignment: .center) {
            // Always in the tree, hidden by opacity. As a `if
            // frames.isEmpty { … }` inside an overlay builder it was observed
            // still on screen next to a loaded thumbnail: the branch had been
            // taken when the strip was empty and was not re-evaluated when it
            // filled. Opacity depends on the same value every pass, so it
            // cannot go stale.
            Text(compact ? T("No photos match these filters", "没有符合筛选条件的照片") : L(.statusEmptyFilmstrip))
                .font(Theme.Font.label).foregroundStyle(Theme.dim)
                .opacity((compact ? visibleFrames.isEmpty && markFilter.isActive : session.frames.isEmpty) ? 1 : 0)
                .allowsHitTesting(false)
        }
        // The outer navigator owns the shared glass surface.
        .modifier(EditorChromeSurface(bare: compact))
    }

    private var navigatorToolbar: some View {
        BottomStripToolbar {
            HStack(spacing: Theme.Metric.space8) {
                Text(session.selectedFrames.count > 1
                     ? T("\(session.selectedFrames.count) photos selected", "已选 \(session.selectedFrames.count) 张照片")
                     : (session.selection?.lastPathComponent ?? ""))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1).truncationMode(.middle).layoutPriority(1)
                Text(session.selectedFrames.count > 1 ? batchEXIF : EXIFReadout.summary([session.exif]))
                    .foregroundStyle(Theme.Ink.secondary).lineLimit(1)
            }
            .padding(.horizontal, Theme.Metric.bottomStripToolbarTextInset)
            Spacer(minLength: Theme.Metric.space8)
            BottomStripToolbarGroup {
                BottomStripToolbarMenu(selected: markFilter.minimumRating > 0 || markFilter.unratedOnly) {
                    BottomStripFilterOption(title: T("All ratings", "全部星级"), selected: markFilter.minimumRating == 0 && !markFilter.unratedOnly) { markFilter.minimumRating = 0; markFilter.unratedOnly = false }
                    BottomStripFilterOption(title: T("Unrated", "未评分"), selected: markFilter.unratedOnly) { markFilter.minimumRating = 0; markFilter.unratedOnly = true }
                    Divider()
                    ForEach(1...5, id: \.self) { rating in
                        BottomStripFilterOption(title: T("At least \(rating) stars", "至少 \(rating) 星"), selected: markFilter.minimumRating == rating && !markFilter.unratedOnly) {
                            markFilter.minimumRating = rating; markFilter.unratedOnly = false
                        }
                    }
                } label: {
                    RoundedFavoriteStar().fill()
                        .frame(width: Theme.Metric.bottomStripToolbarGlyphSize, height: Theme.Metric.bottomStripToolbarGlyphSize)
                    Text(markFilter.unratedOnly ? T("Unrated", "未评分") : (markFilter.minimumRating > 0
                        ? "≥ \(markFilter.minimumRating)" : T("All ratings", "全部星级")))
                }
                .help(T("Filter photos by rating", "按照片星级筛选"))
                BottomStripToolbarMenu(selected: markFilter.flag != nil) {
                    BottomStripFilterOption(title: T("All flags", "全部旗标"), selected: markFilter.flag == nil) { markFilter.flag = nil }
                    BottomStripFilterOption(title: T("Unflagged", "无旗标"), selected: markFilter.flag == FrameMarks.Flag.none) { markFilter.flag = FrameMarks.Flag.none }
                    BottomStripFilterOption(title: T("Pick", "保留"), selected: markFilter.flag == .pick) { markFilter.flag = .pick }
                    BottomStripFilterOption(title: T("Reject", "淘汰"), selected: markFilter.flag == .reject) { markFilter.flag = .reject }
                } label: {
                    Image(systemName: "flag")
                        .frame(width: Theme.Metric.bottomStripToolbarGlyphSize, height: Theme.Metric.bottomStripToolbarGlyphSize)
                    Text(flagFilterTitle)
                }
                .help(T("Filter photos by flag", "按照片旗标筛选"))
                if markFilter.isActive {
                    Button { markFilter = PhotoMarkFilter() } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .frame(width: Theme.Metric.bottomStripToolbarGlyphSize, height: Theme.Metric.bottomStripToolbarGlyphSize)
                            .bottomStripToolbarControl(iconOnly: true)
                    }
                    .buttonStyle(.toolbarSelection(selected: true))
                    .help(T("Clear photo filters", "清除照片筛选"))
                    .accessibilityLabel(T("Clear photo filters", "清除照片筛选"))
                }
            }
            BottomStripToolbarGroup {
                Button { session.requestCopySettings() } label: {
                    Image(systemName: "doc.on.doc")
                        .frame(width: Theme.Metric.bottomStripToolbarGlyphSize, height: Theme.Metric.bottomStripToolbarGlyphSize)
                        .bottomStripToolbarControl(iconOnly: true)
                }
                .buttonStyle(.toolbarSelection(selected: false))
                .disabled(!session.canRequestCopySettings).help(L(.menuCopySettings))
                .accessibilityLabel(L(.menuCopySettings))
                Button { session.pasteSettings() } label: {
                    Image(systemName: "doc.on.clipboard")
                        .frame(width: Theme.Metric.bottomStripToolbarGlyphSize, height: Theme.Metric.bottomStripToolbarGlyphSize)
                        .bottomStripToolbarControl(iconOnly: true)
                }
                .buttonStyle(.toolbarSelection(selected: false))
                .disabled(!session.canPasteSettings).help(L(.menuPasteSettings))
                .accessibilityLabel(L(.menuPasteSettings))
            }
        }
    }

    private var flagFilterTitle: String {
        switch markFilter.flag {
        case nil: T("All flags", "全部旗标")
        case .some(.none): T("Unflagged", "无旗标")
        case .some(.pick): T("Pick", "保留")
        case .some(.reject): T("Reject", "淘汰")
        }
    }

    /// A chevron at the strip's edge. It had no tooltip and no disabled
    /// reason, and its ink was 18 pt wide inside a full-height box (button
    /// audit 2026-09-23); the box is now `railIconTarget` wide and the two
    /// states are said out loud.
    ///
    /// **Traditional only** — Modern's navigator has no chevrons, because its
    /// selection follows the open frame — but it takes the shared row-glyph
    /// size anyway: an 11 pt chevron is not a fact about the deprecated
    /// layout, and a literal here was the last inline type size in this file.
    private func edgeButton(_ name: String, _ help: String, enabled: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: Theme.Metric.modernRowGlyph, weight: .medium))
                .foregroundStyle(Theme.text)
                .frame(width: Theme.Metric.railIconTarget, height: compact ? Theme.Metric.browserToolbarHeight : stripHeight).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rowEnabled(enabled, because: L(.reasonNoFrames))
        .help(help)
    }
}

/// The navigator owns its filter, so it also owns the scope of Cmd+A.
/// A local key monitor preserves native text-field Select All and modal sheets.
struct PhotoSelectAllShortcut: NSViewRepresentable {
    let scope: [URL]
    let select: ([URL]) -> Void

    func makeNSView(context: Context) -> ShortcutView { ShortcutView() }
    func updateNSView(_ view: ShortcutView, context: Context) {
        view.scope = scope
        view.select = select
    }
    static func dismantleNSView(_ view: ShortcutView, coordinator: ()) { view.stopMonitoring() }

    static func accepts(_ event: NSEvent, firstResponder: NSResponder?, hasSheet: Bool, hasPhotos: Bool) -> Bool {
        !hasSheet && hasPhotos && !(firstResponder is NSTextView) && !(firstResponder is NSTextField)
            && event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command
            && event.charactersIgnoringModifiers?.lowercased() == "a"
    }

    final class ShortcutView: NSView {
        var scope: [URL] = []
        var select: (([URL]) -> Void)?
        private var monitor: Any?
        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      !self.isHiddenOrHasHiddenAncestor,
                      PhotoSelectAllShortcut.accepts(event, firstResponder: window.firstResponder,
                                                    hasSheet: window.attachedSheet != nil,
                                                    hasPhotos: !self.scope.isEmpty) else { return event }
                self.select?(self.scope)
                return nil
            }
        }
    }
}

private struct ThumbnailMarks: View {
    let imageURL: URL
    let library: PhotoMarkLibrary
    private var marks: FrameMarks { library.marks(for: imageURL) }
    let hovered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var saveError: String?

    var body: some View {
        VStack {
            HStack {
                Spacer(minLength: 0)
                Menu {
                    Button(T("Unflagged", "无旗标")) { update(flag: FrameMarks.Flag.none) }
                    Button(T("Pick", "保留")) { update(flag: .pick) }
                    Button(T("Reject", "淘汰")) { update(flag: .reject) }
                } label: {
                    Image(systemName: marks.flag == .reject ? "flag.slash.fill" : (marks.flag == .pick ? "flag.fill" : "flag"))
                        .font(Theme.Font.label)
                        .frame(width: Theme.Metric.browserToolbarHeight, height: Theme.Metric.browserToolbarHeight)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .opacity(hovered || marks.flag != .none ? 1 : 0)
                .allowsHitTesting(hovered || marks.flag != .none)
                .help(T("Flag photo", "照片旗标"))
                .accessibilityLabel(T("Flag photo", "照片旗标"))
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Metric.space4)
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: hovered ? 0 : Theme.Metric.photoRatingDotSpacing) {
                ForEach(1...5, id: \.self) { rating in
                    Button { update(rating: marks.rating == rating ? 0 : rating) } label: {
                        ZStack {
                            Circle().fill(rating <= marks.rating ? Theme.accent : Theme.text.opacity(0.65))
                                .frame(width: Theme.Metric.photoRatingDotSize, height: Theme.Metric.photoRatingDotSize)
                                .opacity(hovered ? 0 : 1)
                            Group {
                                if rating <= marks.rating { RoundedFavoriteStar().fill(Theme.accent) }
                                else { RoundedFavoriteStar().stroke(Theme.text, lineWidth: Theme.Metric.rule) }
                            }
                            .frame(width: Theme.Metric.photoRatingGlyphSize, height: Theme.Metric.photoRatingGlyphSize)
                            .opacity(hovered ? 1 : 0)
                        }
                        .frame(width: hovered ? Theme.Metric.photoRatingTargetWidth : Theme.Metric.photoRatingDotSize,
                               height: hovered ? Theme.Metric.browserToolbarHeight : Theme.Metric.photoRatingDotSize)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(T("Set \(rating) stars (key \(rating)); click again to clear", "设为 \(rating) 星（数字键 \(rating)），再次点击清除"))
                    .accessibilityLabel(T("Set \(rating) stars", "设为 \(rating) 星"))
                    .accessibilityValue(rating <= marks.rating ? T("Rated", "已评分") : T("Unrated", "未评分"))
                }
            }
            .padding(.leading, hovered ? Theme.Metric.space4 : Theme.Metric.photoRatingDotLeadingInset)
            .padding(.bottom, hovered ? Theme.Metric.space4 : Theme.Metric.photoRatingDotBottomInset)
            .animation(reduceMotion ? nil : Theme.Motion.hover, value: hovered)
            .allowsHitTesting(hovered)
        }
        .foregroundStyle(Theme.text)
        .shadow(color: .black.opacity(0.8), radius: Theme.Metric.rule)
        .alert(T("Unable to save photo marks", "无法保存照片标记"), isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button(T("OK", "好")) { saveError = nil }
            } message: { Text(saveError ?? "") }
    }
    private func update(rating: Int? = nil, flag: FrameMarks.Flag? = nil) {
        var next = marks
        if let rating { next.rating = rating }
        if let flag { next.flag = flag }
        do { try library.set(next, for: imageURL) }
        catch { saveError = error.localizedDescription }
    }
}

struct FilmstripCell: View {
    let frame: Frame
    /// Whether this cell is on the canvas, in the picked set, or neither —
    /// one value from `Session.framing(of:)` rather than two booleans, so the
    /// strip and the grid cannot spell the same state two ways.
    let framing: FrameFraming
    /// Unread by this cell; kept as the guard test's construction seam.
    let state: FrameState
    var height: CGFloat = Theme.Metric.thumbHeight
    var cornerRadius: CGFloat = 2
    var modernSelection = false
    var markLibrary: PhotoMarkLibrary? = nil
    var cropGeometry = Geometry()
    @State private var rawImage: CGImage?
    @State private var shownImage: CGImage?
    private var image: CGImage? { shownImage ?? rawImage }
    @State private var hovered = false

    var body: some View {
        ZStack {
            Group {
                if let image {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius).fill(Theme.well)
                        .aspectRatio(3 / 2, contentMode: .fit)
                        .overlay(Image(systemName: "photo").foregroundStyle(Theme.dim))
                }
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            // Every surface in the interface has a 1 px edge (UI-SPEC §2.2),
            // and a thumbnail is a surface: without it a light photograph
            // bleeds into the card it sits on.
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.controlStroke, lineWidth: 1)
            }
            // The mark stays a **frame**, not a capsule — the cell is a
            // photograph, and a light band behind one is not a mark you can
            // see. What it was missing is the material everything else has:
            // the frame now lies *on* the picture (a shadow under it), and an
            // unmarked cell answers the pointer with a faint frame of its own,
            // which is the only affordance a 100 pt thumbnail has room for.
            .overlay {
                if framing.opacity > 0 {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        // The compact strip has no spare height and only a
                        // 2 pt gap between photos. Keep the whole stroke
                        // inside this thumbnail so ScrollView/neighbours
                        // cannot cut off its outer half.
                        .strokeBorder(modernSelection ? Theme.accent : Theme.selectionFrame,
                                      lineWidth: modernSelection
                                          ? (framing == .open ? Theme.Metric.photoSelectionStrokeWidth : Theme.Metric.photoPickedStrokeWidth) : framing.lineWidth)
                        .shadow(color: modernSelection ? .clear : Theme.overlayInkShadow, radius: 2)
                        .opacity(modernSelection ? 1 : framing.opacity)
                } else if hovered {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.30), lineWidth: 1)
                }
            }
        }
        .overlay {
            if modernSelection, let markLibrary { ThumbnailMarks(imageURL: frame.id, library: markLibrary, hovered: hovered) }
        }
        .help(frame.name)
        .onHover { hovered = $0 }
        .task(id: CropMask.Key(image: rawImage.map(ObjectIdentifier.init), geometry: cropGeometry)) {
            shownImage = rawImage.map { CropMask.masked($0, by: cropGeometry) }
        }
        .task(id: frame.id) {
            rawImage = await ThumbnailCache.shared.thumbnail(for: frame.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .thumbnailUpdated)) { n in
            guard (n.object as? URL) == frame.id else { return }
            Task { rawImage = await ThumbnailCache.shared.thumbnail(for: frame.id) }
        }
    }

}

/// Modern's multi-selection contact sheet. It is a second view of the same
/// picked set as the navigator and export queue, not a separate worklist.
/// Visible filenames are omitted so the canvas gives the photographs the space.
struct SelectedFramesGrid: View {
    @Bindable var session: Session

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220),
                                    spacing: Theme.Metric.space20)]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, alignment: .center, spacing: Theme.Metric.space20) {
                ForEach(session.frames.filter { session.isPicked($0.id) }) { frame in
                    SelectedFrameTile(frame: frame, isOpen: frame.id == session.selection,
                                      cropGeometry: session.thumbnailGeometry(for: frame.id))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { session.click(frame.id) }
                        .onTapGesture {
                            if NSEvent.modifierFlags.contains(.shift) {
                                session.click(frame.id,
                                              command: NSEvent.modifierFlags.contains(.command),
                                              shift: true)
                            } else if NSEvent.modifierFlags.contains(.command) {
                                session.togglePick(frame.id)
                            } else {
                                session.open(frame.id)
                            }
                        }
                }
            }
            .padding(Theme.Metric.space20)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.ground)
        .contextMenu { SettingsClipboardMenu(session: session) }
        .accessibilityLabel(T("Selected photos", "已选照片"))
    }
}

private struct SelectedFrameTile: View {
    let frame: Frame
    let isOpen: Bool
    var cropGeometry = Geometry()
    @State private var rawImage: CGImage?
    @State private var shownImage: CGImage?
    private var image: CGImage? { shownImage ?? rawImage }

    /// A tile's own cap. 260 was the width multiplier, the height cap and the
    /// frame height at once, which is three jobs for one number; the cap is a
    /// size and the grid's column width is a layout answer.
    private static let tileCap: CGFloat = 200

    var body: some View {
        GeometryReader { box in
            if let image {
                let aspect = CGFloat(image.width) / CGFloat(max(image.height, 1))
                let width = min(box.size.width, Self.tileCap * aspect)
                let height = min(Self.tileCap, box.size.width / aspect)
                Image(decorative: image, scale: 1)
                    .resizable()
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.modernCardRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Metric.modernCardRadius, style: .continuous)
                            .strokeBorder(Theme.accent, lineWidth: isOpen ? Theme.Metric.photoSelectionStrokeWidth : Theme.Metric.photoPickedStrokeWidth)
                    }
                    .position(x: box.size.width / 2, y: box.size.height / 2)
            } else {
                RoundedRectangle(cornerRadius: Theme.Metric.modernCardRadius, style: .continuous)
                    .fill(Theme.well)
                    .overlay(Image(systemName: "photo").foregroundStyle(Theme.Ink.tertiary))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: Self.tileCap)
        .accessibilityLabel(frame.name)
        .task(id: CropMask.Key(image: rawImage.map(ObjectIdentifier.init), geometry: cropGeometry)) {
            shownImage = rawImage.map { CropMask.masked($0, by: cropGeometry) }
        }
        .task(id: frame.id) {
            rawImage = await ThumbnailCache.shared.thumbnail(for: frame.id, maxPixel: 640)
        }
        .onReceive(NotificationCenter.default.publisher(for: .thumbnailUpdated)) { note in
            guard (note.object as? URL) == frame.id else { return }
            Task { rawImage = await ThumbnailCache.shared.thumbnail(for: frame.id, maxPixel: 640) }
        }
    }
}

/// A toolbar above material content, sharing its footprint with photo browsing.
struct FilmChoiceStrip: View {
    @Bindable var session: Session
    @AppStorage("ui2.materialBrowser.tab") private var tab: MaterialBrowserTab = .film
    @State private var filter: MaterialBrowserFilter = .all
    @AppStorage("ui2.materialBrowser.listMode") private var listMode = false

    private var choices: [MaterialBrowserChoice] {
        MaterialBrowserChoice.choices(catalog: session.catalog, tab: tab, filter: filter,
                                      query: "", favorites: session.materialLibrary.favorites,
                                      recent: session.materialLibrary.recent)
    }
    private var emptyMessage: String {
        if filter == .favorites { return T("No favorites yet. Use a card’s star to add one.", "还没有收藏的材质，点卡片上的星标添加。") }
        if filter == .recent { return T("Materials you choose will appear here.", "使用过的材质会显示在这里。") }
        return T("No matching materials", "没有符合条件的材质")
    }
    private var selectedID: String {
        if tab == .film { return session.params.filmStock }
        return session.params.scanFilm ? MaterialBrowserChoice.scanID
            : session.digitalIntermediateActive ? MaterialBrowserChoice.diID : session.params.printStock
    }
    private var filters: [MaterialBrowserFilter] {
        tab == .film ? MaterialBrowserFilter.filmTabs : [.all, .favorites, .recent]
    }

    var body: some View {
        VStack(spacing: Theme.Metric.space8) {
            toolbar
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    Group {
                        if listMode {
                            LazyHStack(spacing: Theme.Metric.space8) {
                                ForEach(Array(stride(from: 0, to: choices.count, by: 2)), id: \.self) { start in
                                    VStack(spacing: Theme.Metric.space8) {
                                        ForEach(Array(choices.dropFirst(start).prefix(2))) { choice in
                                            choiceCard(choice, compact: true)
                                                .id(choice.id)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .frame(height: Theme.Metric.browserContentHeight, alignment: .top)
                                }
                            }
                        } else {
                            LazyHStack(spacing: Theme.Metric.space8) {
                                ForEach(choices) { choice in
                                    choiceCard(choice, compact: false).id(choice.id)
                                }
                            }
                        }
                    }
                    .background(HorizontalStripWheelBridge())
                }
                .frame(height: Theme.Metric.browserContentHeight)
                .overlay {
                    if choices.isEmpty {
                        Text(emptyMessage)
                            .font(Theme.Font.caption).foregroundStyle(Theme.Ink.secondary)
                    }
                }
                .onAppear { revealSelection(proxy) }
                .onChange(of: selectedID) { _, _ in revealSelection(proxy) }
                .onChange(of: tab) { _, _ in revealSelection(proxy) }
                .onChange(of: filter) { _, _ in revealSelection(proxy) }
                .onChange(of: listMode) { _, _ in revealSelection(proxy) }
            }
        }
        .padding(Theme.Metric.browserInset)
        .frame(height: Theme.Metric.modernBottomStripHeight)
        .modifier(EditorChromeSurface())
        .disabled(session.batchExporting)
    }

    private var toolbar: some View {
        GeometryReader { geometry in
            if geometry.size.width < Theme.Metric.browserToolbarCompactWidth {
                compactToolbar
            } else {
                fullToolbar
            }
        }
        .frame(height: Theme.Metric.browserToolbarHeight)
    }

    private var compactToolbar: some View {
        BottomStripToolbar {
            BottomStripToolbarGroup {
                tabButton(L(.sectionFilm), target: .film)
                tabButton(L(.sectionPaper), target: .paper)
            }
            BottomStripToolbarMenu(selected: filter != .all) {
                ForEach(filters, id: \.self) { value in
                    BottomStripFilterOption(title: filterTitle(value), selected: filter == value) { filter = value }
                }
            } label: {
                Text(filterTitle(filter))
            }
            Spacer(minLength: Theme.Metric.space8)
            BottomStripToolbarGroup {
                modeButton("rectangle.grid.1x2", list: false, help: T("Cards", "卡片视图"))
                modeButton("list.bullet", list: true, help: T("List", "列表视图"))
            }
        }
    }

    private var fullToolbar: some View {
        BottomStripToolbar {
            BottomStripToolbarGroup {
                tabButton(L(.sectionFilm), target: .film)
                tabButton(L(.sectionPaper), target: .paper)
            }
            ViewThatFits(in: .horizontal) {
                BottomStripToolbarGroup {
                    ForEach(filters, id: \.self) { value in filterButton(value) }
                }
                BottomStripToolbarMenu(selected: filter != .all) {
                    ForEach(filters, id: \.self) { value in
                        BottomStripFilterOption(title: filterTitle(value), selected: filter == value) { filter = value }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .frame(width: Theme.Metric.bottomStripToolbarGlyphSize, height: Theme.Metric.bottomStripToolbarGlyphSize)
                    Text(filterTitle(filter))
                }
            }
            Spacer(minLength: Theme.Metric.space8)
            BottomStripToolbarGroup {
                modeButton("rectangle.grid.1x2", list: false, help: T("Cards", "卡片视图"))
                modeButton("list.bullet", list: true, help: T("List", "列表视图"))
            }

        }
    }

    private func tabButton(_ title: String, target: MaterialBrowserTab) -> some View {
        Button {
            tab = target; filter = .all
        } label: {
            Text(title).bottomStripToolbarControl()
        }
        .buttonStyle(.toolbarSelection(selected: tab == target))
        .accessibilityAddTraits(tab == target ? [.isSelected] : [])
    }

    private func filterTitle(_ value: MaterialBrowserFilter) -> String {
        switch value {
        case .all: return T("All", "全部")
        case .negative: return L(filmGroup: "Negative")
        case .positive: return L(filmGroup: "Positive")
        case .experimental: return T("Experimental", "实验")
        case .blackwhiteExperimental: return T("B&W (Experimental)", "黑白（实验）")
        case .favorites: return T("Favorites", "收藏")
        case .recent: return T("Recently used", "最近使用")
        }
    }
    private func filterButton(_ value: MaterialBrowserFilter) -> some View {
        Button { filter = value } label: {
            HStack(spacing: Theme.Metric.bottomStripToolbarLabelGap) {
                if value == .favorites {
                    RoundedFavoriteStar().fill()
                        .frame(width: Theme.Metric.bottomStripToolbarGlyphSize, height: Theme.Metric.bottomStripToolbarGlyphSize)
                }
                if value == .recent {
                    Image(systemName: "clock")
                        .frame(width: Theme.Metric.bottomStripToolbarGlyphSize, height: Theme.Metric.bottomStripToolbarGlyphSize)
                }
                Text(filterTitle(value))
            }
            .bottomStripToolbarControl()
        }
        .buttonStyle(.toolbarSelection(selected: filter == value))
        .accessibilityAddTraits(filter == value ? [.isSelected] : [])
    }
    private func modeButton(_ glyph: String, list: Bool, help: String) -> some View {
        Button { listMode = list } label: {
            Image(systemName: glyph)
                .frame(width: Theme.Metric.bottomStripToolbarGlyphSize, height: Theme.Metric.bottomStripToolbarGlyphSize)
                .bottomStripToolbarControl(iconOnly: true)

        }
        .buttonStyle(.toolbarSelection(selected: listMode == list)).help(help).accessibilityLabel(help)
        .accessibilityAddTraits(listMode == list ? [.isSelected] : [])
    }
    private func choiceCard(_ choice: MaterialBrowserChoice, compact: Bool) -> some View {
        MaterialBrowserCard(choice: choice, selected: choice.id == selectedID,
                            disabled: tab == .paper && choice.id != MaterialBrowserChoice.scanID && session.filmIsPositive,
                            favorite: session.materialLibrary.favorites.contains(choice.id),
                            compact: compact,
                            toggleFavorite: { session.materialLibrary.toggleFavorite(choice.id) }) {
            if choice.id == MaterialBrowserChoice.scanID { session.selectScanFilm() }
            else if choice.id == MaterialBrowserChoice.diID { session.selectDigitalIntermediate() }
            else if tab == .film { session.selectFilmStock(choice.id) }
            else { session.selectPrintStock(choice.id) }
        }
    }
    private func revealSelection(_ proxy: ScrollViewProxy) {
        guard let id = choices.first(where: { $0.id == selectedID })?.id ?? choices.first?.id else { return }
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
    }
}

/// Decode once at thumbnail resolution; hover and selection reuse the same image.
@MainActor
private enum MaterialArtworkCache {
    static let cache = NSCache<NSURL, NSImage>()

    static func image(at url: URL) -> NSImage? {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Theme.Metric.browserArtworkDecodeSize,
                kCGImageSourceShouldCacheImmediately: true,
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: thumbnail, size: .zero)
        cache.setObject(image, forKey: key, cost: thumbnail.bytesPerRow * thumbnail.height)
        return image
    }
}

private struct MaterialBrowserCard: View {
    let choice: MaterialBrowserChoice
    let selected: Bool
    let disabled: Bool
    let favorite: Bool
    let compact: Bool
    let toggleFavorite: () -> Void
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if compact {
                    HStack(spacing: Theme.Metric.space8) {
                        coverPlaceholder
                            .frame(width: Theme.Metric.browserListRowHeight - Theme.Metric.space8 * 2)
                        labels
                    }
                } else {
                    VStack(alignment: .leading, spacing: Theme.Metric.space4) {
                        coverPlaceholder
                            .frame(height: Theme.Metric.browserCoverHeight)
                        labels
                    }
                }
            }
            .padding(compact ? Theme.Metric.space8 : Theme.Metric.browserCardInset)
            .frame(width: compact ? Theme.Metric.browserListWidth : Theme.Metric.browserCardWidth,
                   height: compact ? Theme.Metric.browserListRowHeight : Theme.Metric.browserContentHeight,
                   alignment: .topLeading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Metric.modernCardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metric.modernCardRadius, style: .continuous)
                    .fill(Theme.rowHoverWash.opacity(hovered ? 1 : 0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metric.modernCardRadius, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Theme.controlStroke,
                                  lineWidth: selected ? Theme.Metric.modernSelectionStrokeWidth : Theme.Metric.rule)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Metric.modernCardRadius, style: .continuous))
        }
        .buttonStyle(.plain).disabled(disabled)
        .opacity(disabled ? Theme.disabledOpacity : 1)
        .onHover { hovered = $0 }
        .help(disabled ? T("Paper printing is unavailable for reversal film", "正片不使用相纸印放") : (choice.stock?.name ?? choice.title))
        .accessibilityLabel((choice.stock?.name ?? choice.title) + ", " + choice.subtitle)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .overlay(alignment: .topTrailing) {
            Button(action: toggleFavorite) {
                Group {
                    if favorite {
                        RoundedFavoriteStar().fill(Theme.accent)
                    } else {
                        RoundedFavoriteStar()
                            .stroke(compact ? Theme.Ink.secondary : (choice.artworkURL == nil ? Theme.materialPlaceholderControlInk : Theme.text),
                                    style: StrokeStyle(lineWidth: Theme.Metric.rule, lineCap: .round, lineJoin: .round))
                    }
                }
                    .frame(width: Theme.Metric.browserFavoriteGlyphSize, height: Theme.Metric.browserFavoriteGlyphSize)
                    .shadow(color: !compact && choice.artworkURL != nil ? .black.opacity(0.8) : .clear,
                            radius: Theme.Metric.rule)
                    .frame(width: Theme.Metric.browserToolbarHeight, height: Theme.Metric.browserToolbarHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(favorite ? T("Remove favorite", "取消收藏") : T("Add favorite", "收藏材质"))
            .accessibilityLabel(favorite ? T("Remove favorite", "取消收藏") : T("Add favorite", "收藏材质"))
            .padding(Theme.Metric.browserFavoriteInset)
        }
    }

    private var coverPlaceholder: some View {
        RoundedRectangle(cornerRadius: Theme.Metric.browserCoverRadius, style: .continuous)
            .fill(Theme.materialPlaceholder)
            .overlay {
                if let url = choice.artworkURL,
                   let image = MaterialArtworkCache.image(at: url) {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(Theme.Font.label)
                        .foregroundStyle(Theme.materialPlaceholderInk)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.browserCoverRadius, style: .continuous))
            .accessibilityHidden(true)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: Theme.Metric.space2) {
            Text(choice.cardTitle).font(Theme.Font.chooserCard).foregroundStyle(Theme.text)
                .lineLimit(1)
                .padding(.trailing, compact ? Theme.Metric.browserToolbarHeight : 0)
            Text(choice.subtitle).font(Theme.Font.caption).foregroundStyle(Theme.Ink.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, compact ? 0 : Theme.Metric.browserTextInset - Theme.Metric.browserCardInset)
    }
}

/// Both the navigator and the contact sheet act on the same selection.
/// A right click must never collapse an existing batch.
private struct SettingsClipboardMenu: View {
    @Bindable var session: Session
    var frame: URL?

    var body: some View {
        Button(L(.menuCopySettings)) {
            prepareSingleFrame()
            session.requestCopySettings()
        }
        .disabled(!session.canRequestCopySettings)
        Button(L(.menuPasteSettings)) {
            prepareSingleFrame()
            session.pasteSettings()
        }
        .disabled(!session.canPasteSettings)
    }

    private func prepareSingleFrame() {
        if session.selectedFrames.count <= 1, let frame, frame != session.selection {
            session.click(frame)
        }
    }
}
