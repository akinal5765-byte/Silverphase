//  SidebarToggle.swift — the one control that folds a rail.
//
//  It lives in the rail that owns it (`RightPanel`'s header) and, when that
//  rail is away, on the tool bar — the PRD requires it to be on screen at
//  every moment, and a rail with no header has no other place to put it.
//
//  This file was `LeftPanel.swift`: the film and paper catalogues it held are
//  in the bottom chooser now, and the three views it also carried — the rail
//  itself, `PanelIconButton` and `VerticalEllipsis` — had no caller left once
//  the three-region layout was retired (2026-09-26). What remains is the one
//  control both layouts shared.

import SwiftUI

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
