//  SectionHeader.swift — disclosure triangle, title, "•••" — the row every
//  section in both rails starts with, and the well a list sits in.
//
//  **v3 (2026-09-18) added two things.** A section title's size is now a
//  property of *which rail it is on* — 12 on the left, 10.5 on the right —
//  so `SectionMetrics` carries the font and the two rails pass different
//  ones (`SectionMetrics.left` / `.right`). And a header can carry a direct
//  **reset** affordance beside its "•••", which v3 draws on Camera and Film.
//  It is `action`, an explicit title-and-handler pair rather than a Boolean,
//  because handoff §8.3 leaves reset *scope* unresolved: a bare arrow that
//  might reset a slider or might reset a whole section is the ellipsis
//  problem again, so a caller that wants one has to say in words what it
//  resets, and that sentence becomes the tooltip.
//
//  The 2026-09-17 drawing changed three things here. The header is 30 pt (its
//  two collapsed sections, White Balance and Exposure, measure 29.05 and
//  31.05 between hairlines). It carries **no icon**: the drawing's headers are
//  a triangle, a title and a menu, and the glyph that used to sit between the
//  first two is gone. And a section is closed by a `Hairline` drawn by the
//  rail rather than by air, so the only vertical space a section owns is the
//  12 pt under its content — and a *collapsed* section owns none at all,
//  which is what makes two shut sections 30 pt apart.

import SwiftUI

/// The pinned stage title shared by the Modern inspector and export page.
/// Content-block titles and their actions scroll beneath it.
struct StageHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Metric.space8) {
                Text(title)
                    .font(Theme.Font.modernSectionTitle)
                    .foregroundStyle(Theme.Ink.primary)
                    .lineLimit(1)
                Spacer(minLength: Theme.Metric.space8)
                trailing()
            }
            .padding(.horizontal, Theme.Metric.modernContentInset)
            .frame(height: Theme.Metric.modernHeaderHeight)
            Hairline()
        }
    }
}

/// A stage header with nothing beside its name; actions belong to its blocks.
struct BareStageHeader: View {
    let title: String
    var body: some View {
        StageHeader(title: title) { EmptyView() }
    }
}

/// A menu button for pages that still place actions in their pinned header.
struct StageHeaderMenu: View {
    let menu: AnyView
    var body: some View {
        Menu { menu } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: Theme.Metric.panelIcon - 2, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: Theme.Metric.controlHitTarget,
                       height: Theme.Metric.controlHitTarget)
                .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .help(L(.helpSectionMenu))
        .padding(.trailing, -Theme.Metric.space4)
    }
}

/// A direct affordance on a section header, beside its menu. v3 draws one on
/// Camera and Film; `help` is required and is what makes the arrow legible —
/// see the note at the top of this file about §8.3.
struct SectionAction {
    let systemImage: String
    let help: String
    let enabled: Bool
    let perform: () -> Void

    init(systemImage: String = "arrow.counterclockwise", help: String,
         enabled: Bool = true, perform: @escaping () -> Void) {
        self.systemImage = systemImage; self.help = help
        self.enabled = enabled; self.perform = perform
    }
}

struct SectionHeader: View {
    /// Nil is supported for older callers; Modern content blocks use titles.
    let title: String?
    /// Kept for the callers that still pass a name (the export page's own
    /// sections, and every settings/harness caller).
    init(title: String?, systemImage: String? = nil, expanded: Binding<Bool>,
         action: SectionAction? = nil, menu: (() -> AnyView)? = nil) {
        self.title = title
        self.systemImage = systemImage
        self._expanded = expanded
        self.action = action
        self.menu = menu
    }
    var systemImage: String? = nil
    @Binding var expanded: Bool
    var action: SectionAction? = nil
    var menu: (() -> AnyView)? = nil

    @State private var hovered = false

    var body: some View { modernHeader }

    /// A content-block header: title and optional actions, 40 pt tall.
    ///
    /// **No disclosure triangle**, and that is the layout rather than a gap:
    /// the inspector shows one physical stage at a time and the tool bar's
    /// stage buttons change it, so a section here is the whole panel and has
    /// nothing to fold away from. `PanelSection` therefore keeps its content
    /// whatever the stored expansion says, and drawing a triangle would be a
    /// control that reports a state it never keeps.
    private var modernHeader: some View {
        HStack(spacing: Theme.Metric.space8) {
            if let title {
                Text(title)
                    .font(Theme.Font.modernSectionTitle)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Metric.space4)
            if let menu {
                Menu {
                    if let action {
                        Button(action.help, action: action.perform)
                            .disabled(!action.enabled)
                        Divider()
                    }
                    menu()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: Theme.Metric.panelIcon - 2, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: Theme.Metric.controlHitTarget,
                               height: Theme.Metric.controlHitTarget)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .help(L(.helpSectionMenu))
            } else if let action {
                Button(T("Reset", "重置"), action: action.perform)
                    .buttonStyle(.plain)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Ink.secondary)
                    .rowEnabled(action.enabled)
                    .help(action.help)
            }
        }
        .frame(height: 40)
    }

}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct EllipsisGlyph: View {
    var body: some View {
        HStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Circle().fill(Theme.text).frame(width: 3, height: 3) } }
    }
}

/// The rounded well a list sits in.
///
/// On the editor's rails there are exactly two of these — the film list and
/// the print list — and everything else sits directly on the rail. That is
/// the drawing: a well is now what holds a *choice from a set*, not what
/// holds a group of controls.
///
/// `inset` is how far the well is held off the rail's own edges, and it is a
/// parameter rather than a constant because the two drawings disagree: the
/// editor's wells are 4 pt in and the export page's are its own
/// `Export.wellInset`. It used to be `Theme.Metric.wellInset` for both, which
/// meant the export page silently followed the editor's number.
struct Well<Content: View>: View {
    var padding: CGFloat = Theme.Metric.wellPadding
    var vertical: CGFloat = 10
    var inset: CGFloat = Theme.Metric.wellInset
    var radius: CGFloat = Theme.Metric.wellRadius
    /// Whether the plate is drawn at all.
    ///
    /// A well means "these rows are a *list*, and the plate is its edge" — a
    /// film catalogue, a recipe list. It does not mean "these rows belong to
    /// the same section", which is what the hairline above them already says.
    /// The export page had a plate under every group, so Location, Naming,
    /// Format and Summary each read as a grey block rather than as rows, and
    /// four blocks in a column read as one. Its drawing puts a plate under
    /// the recipe list and nothing else; `fill: false` is the rest.
    var fill: Bool = true
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(.horizontal, padding)
            .padding(.vertical, vertical)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if fill {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.well)
                }
            }
            .padding(.horizontal, inset)
    }
}

/// A named content block. Legacy expansion keys remain readable.
struct PanelSection<Content: View>: View {
    let title: String
    /// A named content block beneath a pinned stage header. The stage names
    /// the process step; this names the operation, so the two do not repeat.
    var blockTitle: String? = nil
    var systemImage: String? = nil
    let key: String
    var initiallyExpanded = true
    var action: SectionAction? = nil
    var menu: (() -> AnyView)? = nil
    @ViewBuilder var content: () -> Content
    @AppStorage private var expanded: Bool

    init(_ title: String, systemImage: String? = nil, key: String, initiallyExpanded: Bool = true,
         blockTitle: String? = nil,
         action: SectionAction? = nil,
         menu: (() -> AnyView)? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.blockTitle = blockTitle
        self.systemImage = systemImage; self.key = key
        self.initiallyExpanded = initiallyExpanded; self.action = action
        self.menu = menu
        self.content = content
        _expanded = AppStorage(wrappedValue: initiallyExpanded, Session.uiKey + "section.\(key)")
    }

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(title: blockTitle ?? title, systemImage: systemImage, expanded: $expanded,
                          action: action, menu: menu)
            // A floating surface's section is **never collapsed**: the rail
            // shows one stage at a time and the tool bar's stage buttons
            // change it, so there is nothing to fold and the header draws no
            // disclosure (UI-SPEC §3.7). The stored `expanded` key survives
            // only so an older preferences file still decodes.
            content()
                .padding(.top, Theme.Metric.modernHeaderToContent)
                .padding(.bottom, Theme.Metric.modernSectionBottom)
        }
    }

}

/// A second or later content block in a stage. The first uses PanelSection's
/// `blockTitle`; every following block gets the same header rhythm and rule.
struct InspectorSubblock<Content: View>: View {
    let title: String
    var menu: (() -> AnyView)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            SectionHeader(title: title, expanded: .constant(true), menu: menu)
            content()
                .padding(.top, Theme.Metric.modernHeaderToContent)
        }
        .padding(.top, Theme.Metric.modernSectionBottom)
    }
}
