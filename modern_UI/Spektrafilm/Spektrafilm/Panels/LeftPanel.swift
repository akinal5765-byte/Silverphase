//  LeftPanel.swift — the darkroom rail: a header row, then the sections in
//  the drawing's order, each one closed by a hairline. To add a section:
//  write a view in Panels/Sections and add one line to the stack.
//
//  **v3 (2026-09-18) gave the header a name.** It reads **Develop**, set in
//  `Theme.Font.railTitle`, with import and export at the *trailing* end — the
//  older layout had the two glyphs leading and nothing else on the row. It is
//  a label and not a mode button: there is no second rail to switch to, and a
//  word that looks pressable and is not is worse than a word.
//
//  It is also the row the three window buttons are placed on, so it opens
//  with their clearance rather than with v3's 10 pt
//  (`Theme.Metric.trafficLightClearance`). v3's artwork contains neither the
//  window buttons nor the sidebar toggles; handoff §8.2 says to keep both and
//  **record the deviation rather than hide the functionality**, which is what
//  this row does — the title sits after the buttons' clearance, and
//  `sidebar.left` stays at the far end past import and export.
//
//  Import and export are here rather than on the top bar. The bar is a
//  *canvas* control, and opening a file is not a thing you do to the picture.

import SwiftUI

struct LeftPanel: View {
    @Bindable var session: Session

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            // **The rail still scrolls as a whole**, and the lists keep their
            // own fixed heights. That is deliberate: a `ScrollView` is greedy,
            // so a list told to "fill the slack" eats the rail and pushes the
            // paper section to the bottom with the gap *between* the two
            // lists — which reads worse than the air it was meant to remove.
            // Measured, in a capture. The catalogue's own height is the knob
            // for "show more films" (`FilmSection.wellRows`).
            //
            // **Presets only.** The left rail is what Lightroom Classic puts
            // on the left: the things you *choose* (a film, a paper). The
            // things you *set* moved to the right rail
            // (`Panels/RightPanel.swift`). UI-SPEC §1.4.
            ScrollView(.vertical, showsIndicators: false) {
                // A hairline **between** sections, never after the last one:
                // the stack used to be `Section(); Hairline()` repeated, which
                // draws a rule under the final section against empty rail — a
                // bottom border, not a separator.
                VStack(spacing: 0) {
                    let sections: [(String, AnyView)] =
                        [("navigator", AnyView(NavigatorSection(session: session))),
                         ("filmList", AnyView(FilmSection(session: session, part: .list))),
                         ("printList", AnyView(PrintProfileSection(session: session, part: .list)))]
                    ForEach(Array(sections.enumerated()), id: \.element.0) { index, entry in
                        if index > 0 { Hairline() }
                        entry.1
                    }
                }
            }
        }
        .railCard()
    }

    private var header: some View {
        HStack(spacing: 0) {
            // The three window buttons live here (Windows/TrafficLights.swift).
            // They are *placed* in window coordinates, so this is a reservation
            // and not a container — which is why folding the rail does not move
            // them: the bar takes over the same reservation.
            Spacer().frame(width: Theme.Metric.trafficLightClearance)
            Text(L(.railPresets))
                .font(Theme.Font.railTitle)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 4)
            // **Import and export moved to the top bar.** They used to live
            // here, which meant folding this rail took them off screen and
            // left only ⌘O / ⌘E — two file actions disappearing with a panel
            // of parameters. A file action is not a property of the thing it
            // sits beside. UI-SPEC §1.4.
            SidebarToggle(edge: .leading, collapsed: $session.leftCollapsed)
                .padding(.trailing, Theme.Metric.panelHeaderTrailing)
        }
        .frame(height: Theme.Metric.panelHeaderHeight)
        // The header row is the window's drag surface, as a sidebar header is
        // in Xcode. It is a background so that the glyphs above it still take
        // their own clicks.
        .background(WindowDragHandle())
    }
}

/// `sidebar.left` / `sidebar.right` — the two buttons that fold a rail.
///
/// The PRD's requirement is that they are on screen *at every moment*, which
/// is why this is one view used in three places rather than a button drawn in
/// each: a rail's header holds its own while the rail is open, and the bar
/// holds it while the rail is folded. The glyph never changes — `sidebar.left`
/// always means "the left rail", open or shut.
///
/// **It does not tint.** It used to go `Theme.accent` while its rail was
/// folded, on the reasoning that a selected control tints its glyph. That was
/// the wrong category: this is not a mode you are in, it is a door you push,
/// and the state it would be reporting — whether a whole rail is on screen —
/// is not something you need a 6 pt orange glyph to tell you. The accent is
/// the one colour in the palette that means "look here", and spending it on
/// a fact already filling half the window devalues it everywhere else.
struct SidebarToggle: View {
    enum Edge { case leading, trailing }
    let edge: Edge
    @Binding var collapsed: Bool

    private var symbol: String { edge == .leading ? "sidebar.left" : "sidebar.right" }
    private var help: String {
        switch (edge, collapsed) {
        case (.leading, false): L(.helpDevelopRailHide)
        case (.leading, true): L(.helpDevelopRailShow)
        case (.trailing, false): L(.helpEditRailHide)
        case (.trailing, true): L(.helpEditRailShow)
        }
    }

    @State private var hovered = false

    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.18)) { collapsed.toggle() } } label: {
            Image(systemName: symbol)
                .font(.system(size: Theme.Metric.sidebarIcon, weight: .regular))
                .foregroundStyle(Theme.text)
                .frame(width: Theme.Metric.railIconTarget, height: Theme.Metric.railIconTarget)
                // The same pointer wash the bar's glyphs draw: this button
                // and `PanelIconButton` are the two rail-header glyphs that
                // sat next to hoverable siblings with no hover of their own
                // (button audit 2026-09-23).
                .background {
                    if hovered {
                        RoundedRectangle(cornerRadius: Theme.Metric.fieldRadius, style: .continuous)
                            .fill(Theme.buttonHoverWash)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }
}

struct PanelIconButton: View {
    let systemImage: String
    var help: String = ""
    /// Why it cannot be used, when it cannot. `rowEnabled(_:because:)` is the
    /// app's one answer to §5.1's "never grey a control without saying why";
    /// this control used to pass no reason at all (button audit 2026-09-23).
    var reason: String = ""
    var active = false
    /// A glyph that cannot be used is greyed, like every other non-selectable
    /// control in the app (PRD; `View.rowEnabled(_:)`).
    var enabled = true
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: Theme.Metric.panelIcon, weight: .regular))
                .foregroundStyle(active ? Theme.accent : Theme.text)
                .frame(width: Theme.Metric.railIconTarget, height: Theme.Metric.railIconTarget)
                .background {
                    if hovered && enabled {
                        RoundedRectangle(cornerRadius: Theme.Metric.fieldRadius, style: .continuous)
                            .fill(Theme.buttonHoverWash)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .rowEnabled(enabled, because: reason)
        .onHover { hovered = $0 }
        .modifier(DisabledReason(show: !help.isEmpty, reason: help))
    }
}

struct VerticalEllipsis: View {
    var body: some View {
        VStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Circle().fill(Theme.text).frame(width: 3, height: 3) } }
    }
}

extension View {
    // `panelCard()` — a rounded card on a visible ground — used to live here
    // for the export page and the Browse grid. Both are gone: the grid was
    // removed with the import page, and the export page is three flush rails
    // like the editor. Nothing in the app is a floating card now, so the
    // modifier is not kept "just in case" — a second surface treatment that
    // nothing uses is how the two pages drifted apart in the first place.

    /// A rail, or the filmstrip: flush with the window and square, because
    /// the 2026-09-17 drawing separates regions with a hairline rather than
    /// with a gap and a radius.
    func railCard() -> some View {
        self.background(Theme.cardFill)
    }

    /// The one thing that still floats: the tool bar's pill.
    func barCard() -> some View {
        self.background(Theme.cardFill,
                        in: RoundedRectangle(cornerRadius: Theme.Metric.barRadius, style: .continuous))
    }
}
