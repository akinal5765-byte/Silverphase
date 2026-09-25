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

struct Filmstrip: View {
    @Bindable var session: Session
    var compact = false
    var leadingInset: CGFloat = 0
    var trailingInset: CGFloat = 0

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
        HStack(spacing: 0) {
            Spacer().frame(width: leadingInset)
            if !compact {
                edgeButton("chevron.left", L(.helpPreviousFrame), enabled: !session.frames.isEmpty) { session.selectRelative(-1) }
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: compact ? Theme.Metric.space4 : 14) {
                        ForEach(session.frames) { frame in
                            FilmstripCell(frame: frame,
                                          framing: session.framing(of: frame.id),
                                          state: session.frameStates[frame.id] ?? .unprocessed,
                                          height: compact ? Theme.Metric.modernStripHeight : Theme.Metric.thumbHeight,
                                          cornerRadius: compact ? Theme.Metric.modernCardRadius : 2,
                                          modernSelection: compact)
                                .id(frame.id)
                                // The modifier is read here rather than
                                // declared as a second gesture: a plain
                                // `TapGesture` on macOS matches a ⌘-click too,
                                // so stacking one would fire both and a
                                // ⌘-click would collapse the set as well.
                                .onTapGesture {
                                    session.click(frame.id,
                                                  command: NSEvent.modifierFlags.contains(.command),
                                                  shift: NSEvent.modifierFlags.contains(.shift))
                                }
                                .contextMenu {
                                    Button(L(.helpRevealInFinder)) { NSWorkspace.shared.activateFileViewerSelecting([frame.id]) }
                                    Button(L(.helpResetDefaults)) {
                                        if frame.id == session.selection { session.resetParams(); session.resetAdjustments() }
                                        else { Sidecar.remove(for: frame.id) }
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, stripInset)
                    .frame(height: stripHeight)
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
            Text(L(.statusEmptyFilmstrip))
                .font(Theme.Font.label).foregroundStyle(Theme.dim)
                .opacity(session.frames.isEmpty && !compact ? 1 : 0)
                .allowsHitTesting(false)
        }
        // The modern navigator is a row of photographs over the canvas, not a
        // glass tray. Their own selection frames provide the only backing.
        .modifier(EditorChromeSurface(bare: compact))
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
                .frame(width: Theme.Metric.railIconTarget, height: stripHeight).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rowEnabled(enabled, because: L(.reasonNoFrames))
        .help(help)
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
    @State private var image: CGImage?
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
                                          ? (framing == .open ? 3 : 2.5) : framing.lineWidth)
                        .shadow(color: modernSelection ? .clear : Theme.overlayInkShadow, radius: 2)
                        .opacity(modernSelection ? 1 : framing.opacity)
                } else if hovered {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.30), lineWidth: 1)
                }
            }
        }
        .help(frame.name)
        .onHover { hovered = $0 }
        .task(id: frame.id) {
            image = await ThumbnailCache.shared.thumbnail(for: frame.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .thumbnailUpdated)) { n in
            guard (n.object as? URL) == frame.id else { return }
            Task { image = await ThumbnailCache.shared.thumbnail(for: frame.id) }
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
                    SelectedFrameTile(frame: frame, isOpen: frame.id == session.selection)
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
        .accessibilityLabel(T("Selected photos", "已选照片"))
    }
}

private struct SelectedFrameTile: View {
    let frame: Frame
    let isOpen: Bool
    @State private var image: CGImage?

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
                            .strokeBorder(Theme.accent, lineWidth: isOpen ? 3 : 2.5)
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
        .task(id: frame.id) {
            image = await ThumbnailCache.shared.thumbnail(for: frame.id, maxPixel: 640)
        }
        .onReceive(NotificationCenter.default.publisher(for: .thumbnailUpdated)) { note in
            guard (note.object as? URL) == frame.id else { return }
            Task { image = await ThumbnailCache.shared.thumbnail(for: frame.id, maxPixel: 640) }
        }
    }
}

/// Modern film mode replaces photo thumbnails with physical stock choices.
/// The little canister is drawn in SwiftUI, not sampled from a photograph:
/// a recognisable, consistent symbol for every stock without pretending that
/// a preview of one photograph describes the stock's measured response.
struct FilmChoiceStrip: View {
    @Bindable var session: Session
    @State private var tab: MaterialTab = .film

    private enum MaterialTab { case film, paper }

    var body: some View {
        HStack(spacing: Theme.Metric.space12) {
            HStack(spacing: Theme.Metric.space2) {
                tabButton(L(.sectionFilm), tab: .film)
                tabButton(L(.sectionPaper), tab: .paper)
            }
            .padding(Theme.Metric.space2)
            .background(Theme.well,
                        in: RoundedRectangle(cornerRadius: Theme.Metric.modernCardRadius))

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: Theme.Metric.space8) {
                        if tab == .film {
                            ForEach(session.catalog.filmGroups, id: \.title) { group in
                                Text(L(filmGroup: group.title))
                                    .font(Theme.Font.groupHeader)
                                    .foregroundStyle(Theme.Ink.tertiary)
                                    .padding(.horizontal, Theme.Metric.space4)
                                ForEach(group.films) { stock in
                                    FilmChoiceCard(stock: stock,
                                                   selected: session.params.filmStock == stock.id,
                                                   disabled: false) {
                                        session.selectFilmStock(stock.id)
                                    }
                                    .id(stock.id)
                                }
                            }
                        } else {
                            Button {
                                var p = session.params
                                p.scanFilm = true
                                session.params = p
                            } label: {
                                VStack(spacing: Theme.Metric.space2) {
                                    Image(systemName: "rectangle.slash")
                                        .font(.system(size: Theme.Metric.modernChooserGlyph))
                                    Text(L(.printNone)).font(Theme.Font.chooserCard).lineLimit(2)
                                }
                                .frame(width: Theme.Metric.modernChooserCard.width,
                                       height: Theme.Metric.modernChooserCard.height)
                                .foregroundStyle(session.params.scanFilm ? Theme.onSelection : Theme.text)
                                .background(session.params.scanFilm ? Theme.selection : Theme.well,
                                            in: RoundedRectangle(cornerRadius: Theme.Metric.modernCardRadius))
                            }
                            .buttonStyle(.plain)
                            .id("__scan_film__")
                            ForEach(session.catalog.papers) { stock in
                                FilmChoiceCard(stock: stock,
                                               selected: !session.params.scanFilm && session.params.printStock == stock.id,
                                               disabled: session.filmIsPositive) {
                                    session.selectPrintStock(stock.id)
                                }
                                .id(stock.id)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Metric.space4)
                    .frame(height: Theme.Metric.modernFilmChooserHeight)
                }
                .onAppear { scrollToSelection(proxy) }
                .onChange(of: tab) { _, _ in scrollToSelection(proxy) }
                .onChange(of: session.params.filmStock) { _, _ in
                    if tab == .film { scrollToSelection(proxy) }
                }
                .onChange(of: session.params.printStock) { _, _ in
                    if tab == .paper { scrollToSelection(proxy) }
                }
            }
        }
        .padding(.horizontal, Theme.Metric.modernContentInset)
        .modifier(EditorChromeSurface())
    }

    private func tabButton(_ title: String, tab target: MaterialTab) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { tab = target }
        } label: {
            Text(title)
                .font(Theme.Font.chooserTab)
                .foregroundStyle(tab == target ? Theme.onSelection : Theme.text)
                .frame(width: Theme.Metric.modernChooserTab.width,
                       height: Theme.Metric.modernChooserTab.height)
                .background(tab == target ? Theme.selection : .clear,
                            in: RoundedRectangle(cornerRadius: Theme.Metric.modernCardRadius))
        }
        .buttonStyle(.plain)
    }

    private func scrollToSelection(_ proxy: ScrollViewProxy) {
        let id = tab == .film ? session.params.filmStock
            : (session.params.scanFilm ? "__scan_film__" : session.params.printStock)
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
    }
}

private struct FilmChoiceCard: View {
    let stock: Stock
    let selected: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Metric.space2) {
                if stock.isFilm {
                    FilmCanisterGlyph(positive: stock.isPositive)
                        .frame(width: Theme.Metric.panelIcon + Theme.Metric.space8,
                               height: Theme.Metric.modernChooserCard.height / 2 + 2)
                        .scaleEffect(0.72)
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: Theme.Metric.modernChooserGlyph))
                        .frame(height: Theme.Metric.modernChooserCard.height / 2 + 2)
                }
                Text(stock.name.replacingOccurrences(of: "Professional ", with: ""))
                    .font(Theme.Font.chooserCard)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(selected ? Theme.onSelection : Theme.text)
            .frame(width: Theme.Metric.modernChooserCard.width,
                   height: Theme.Metric.modernChooserCard.height)
            .background(selected ? Theme.selection : Theme.well,
                        in: RoundedRectangle(cornerRadius: Theme.Metric.modernCardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metric.modernCardRadius, style: .continuous)
                    .strokeBorder(selected ? AnyShapeStyle(Theme.selection) : AnyShapeStyle(Theme.controlStroke), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? Theme.disabledOpacity : 1)
        .help(stock.name)
        .accessibilityLabel(stock.name)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct FilmCanisterGlyph: View {
    let positive: Bool

    /// The canister's own drawing, in one place. These are the one shape in
    /// the interface that is *a picture of an object* rather than a control,
    /// so they are local constants rather than panel tokens — but they are
    /// constants, not numbers scattered through five modifiers.
    private enum Ink {
        static let body = CGSize(width: 25, height: 36)
        static let label = CGSize(width: 25, height: 7)
        static let spoolTop = CGSize(width: 29, height: 5)
        static let spoolBottom = CGSize(width: 27, height: 4)
        static let labelOffset: CGFloat = 8
        static let spoolTopOffset: CGFloat = 19
        static let spoolBottomOffset: CGFloat = 18
        static let glyphOffset: CGFloat = 6
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Metric.fieldRadius)
                .fill(Color(hex: positive ? 0x453947 : 0x333B45))
                .frame(width: Ink.body.width, height: Ink.body.height)
            RoundedRectangle(cornerRadius: Theme.Metric.space2)
                .fill(Color(hex: positive ? 0xD067A2 : 0xE6A348))
                .frame(width: Ink.label.width, height: Ink.label.height)
                .offset(y: -Ink.labelOffset)
            Capsule().fill(Color(hex: 0xADB1B5))
                .frame(width: Ink.spoolTop.width, height: Ink.spoolTop.height)
                .offset(y: -Ink.spoolTopOffset)
            Capsule().fill(Color(hex: 0x6F7378))
                .frame(width: Ink.spoolBottom.width, height: Ink.spoolBottom.height)
                .offset(y: Ink.spoolBottomOffset)
            Image(systemName: "film")
                .font(.system(size: Theme.Metric.modernRowGlyph, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .offset(y: Ink.glyphOffset)
        }
        .accessibilityHidden(true)
    }
}
