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

    private var stripHeight: CGFloat { compact ? 72 : Theme.Metric.filmstripHeight }

    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: leadingInset)
            if !compact {
                edgeButton("chevron.left", L(.helpPreviousFrame), enabled: !session.frames.isEmpty) { session.selectRelative(-1) }
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: compact ? 2 : 14) {
                        ForEach(session.frames) { frame in
                            FilmstripCell(frame: frame,
                                          framing: session.framing(of: frame.id),
                                          state: session.frameStates[frame.id] ?? .unprocessed,
                                          height: compact ? 72 : Theme.Metric.thumbHeight,
                                          cornerRadius: compact ? 6 : 2)
                                .id(frame.id)
                                // The modifier is read here rather than
                                // declared as a second gesture: a plain
                                // `TapGesture` on macOS matches a ⌘-click too,
                                // so stacking one would fire both and a
                                // ⌘-click would collapse the set as well.
                                .onTapGesture {
                                    session.click(frame.id,
                                                  command: NSEvent.modifierFlags.contains(.command))
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
                    .padding(.horizontal, compact ? 0 : 10)
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
        .modifier(EditorChromeSurface(modern: compact, bare: compact))
    }

    /// A chevron at the strip's edge. It had no tooltip and no disabled
    /// reason, and its ink was 18 pt wide inside a full-height box (button
    /// audit 2026-09-23); the box is now `railIconTarget` wide and the two
    /// states are said out loud.
    private func edgeButton(_ name: String, _ help: String, enabled: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.text)
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
                        .stroke(Theme.selectionFrame, lineWidth: framing.lineWidth)
                        .shadow(color: Theme.overlayInkShadow, radius: 2)
                        .opacity(framing.opacity)
                } else if hovered {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.30), lineWidth: 1)
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

/// Modern film mode replaces photo thumbnails with physical stock choices.
/// The little canister is drawn in SwiftUI, not sampled from a photograph:
/// a recognisable, consistent symbol for every stock without pretending that
/// a preview of one photograph describes the stock's measured response.
struct FilmChoiceStrip: View {
    @Bindable var session: Session
    var trailingInset: CGFloat = 0
    @State private var tab: MaterialTab = .film

    private enum MaterialTab { case film, paper }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                tabButton(L(.sectionFilm), tab: .film)
                tabButton(L(.sectionPaper), tab: .paper)
            }
            .padding(3)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: 9))

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 7) {
                        if tab == .film {
                            ForEach(session.catalog.filmGroups, id: \.title) { group in
                                Text(L(filmGroup: group.title))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Theme.dim)
                                    .padding(.horizontal, 4)
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
                                VStack(spacing: 3) {
                                    Image(systemName: "rectangle.slash")
                                        .font(.system(size: 19))
                                    Text(L(.printNone)).font(.system(size: 10)).lineLimit(2)
                                }
                                .frame(width: 106, height: 70)
                                .foregroundStyle(session.params.scanFilm ? Theme.onSelection : Theme.text)
                                .background(session.params.scanFilm ? Theme.selection : Theme.well,
                                            in: RoundedRectangle(cornerRadius: 9))
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
                    .padding(.horizontal, 4)
                    .frame(height: 92)
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
        .padding(.leading, Theme.Metric.modernContentInset)
        .padding(.trailing, trailingInset + Theme.Metric.modernContentInset)
        .modifier(EditorChromeSurface(modern: true))
    }

    private func tabButton(_ title: String, tab target: MaterialTab) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.16)) { tab = target }
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tab == target ? Theme.onSelection : Theme.text)
                .frame(width: 52, height: 30)
                .background(tab == target ? Theme.selection : .clear,
                            in: RoundedRectangle(cornerRadius: 7))
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
            VStack(spacing: 2) {
                if stock.isFilm {
                    FilmCanisterGlyph(positive: stock.isPositive)
                        .frame(width: 25, height: 37)
                        .scaleEffect(0.72)
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 20, weight: .light))
                        .frame(height: 37)
                }
                Text(stock.name.replacingOccurrences(of: "Professional ", with: ""))
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(selected ? Theme.onSelection : Theme.text)
            .frame(width: 106, height: 70)
            .background(selected ? Theme.selection : Theme.well,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
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

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: positive ? 0x453947 : 0x333B45))
                .frame(width: 25, height: 36)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: positive ? 0xD067A2 : 0xE6A348))
                .frame(width: 25, height: 7)
                .offset(y: -8)
            Capsule().fill(Color(hex: 0xADB1B5)).frame(width: 29, height: 5).offset(y: -19)
            Capsule().fill(Color(hex: 0x6F7378)).frame(width: 27, height: 4).offset(y: 18)
            Image(systemName: "film")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .offset(y: 6)
        }
        .accessibilityHidden(true)
    }
}
