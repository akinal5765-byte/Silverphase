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

    var body: some View {
        HStack(spacing: 0) {
            edgeButton("chevron.left") { session.selectRelative(-1) }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(session.frames) { frame in
                            FilmstripCell(frame: frame,
                                          framing: session.framing(of: frame.id),
                                          state: session.frameStates[frame.id] ?? .unprocessed)
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
                    .padding(.horizontal, 10)
                    .frame(height: Theme.Metric.filmstripHeight)
                }
                .onChange(of: session.selection) { _, new in
                    if let new { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(new, anchor: .center) } }
                }
            }
            edgeButton("chevron.right") { session.selectRelative(1) }
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
                .opacity(session.frames.isEmpty ? 1 : 0)
                .allowsHitTesting(false)
        }
        .railCard()
    }

    private func edgeButton(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.text)
                .frame(width: 18, height: Theme.Metric.filmstripHeight).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(session.frames.isEmpty)
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
    @State private var image: CGImage?
    @State private var hovered = false

    var body: some View {
        ZStack {
            Group {
                if let image {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.well)
                        .aspectRatio(3 / 2, contentMode: .fit)
                        .overlay(Image(systemName: "photo").foregroundStyle(Theme.dim))
                }
            }
            .frame(height: Theme.Metric.thumbHeight)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            // Every surface in the interface has a 1 px edge (UI-SPEC §2.2),
            // and a thumbnail is a surface: without it a light photograph
            // bleeds into the card it sits on.
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
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
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(Theme.selectionFrame, lineWidth: framing.lineWidth)
                        .shadow(color: Theme.overlayInkShadow, radius: 2)
                        .opacity(framing.opacity)
                } else if hovered {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
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
