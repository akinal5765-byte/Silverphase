//  TopBar.swift — the canvas's own bar: select · pan · crop …… before/after
//  · [100 %] · zoom-out · zoom-in · full screen.
//
//  **v3 (2026-09-18) flattened it and re-ordered it.** It was a rounded pill
//  floating on ground; it is now a plain rectangle filling the centre
//  column's top, flush with both rails and with the window's top edge, 38 pt
//  tall like the rail headers beside it (`Theme.Metric.topBarHeight`, which
//  *is* `panelHeaderHeight`) and closed by a hairline drawn by
//  `EditorWindow`. It still belongs to the centre column and is as wide as
//  the picture is.
//
//  Two orders changed, both from v3's measured glyph centres:
//
//  - **Zoom out before zoom in**, with the percentage plate ahead of both:
//    `… Before/After · 1405.64 % · 1478.38 − · 1541.06 + · 1601.37 ⤢`. The
//    old bar had `+` then the pill then `−`, which reads as a stepper
//    straddling its own readout; v3's reads left-to-right as one cluster with
//    the value at its head.
//  - **The percentage plate is 41 pt, not 105.** It holds `100 %` and nothing
//    else, so `Fit · 100 %` does not fit in it. Fit keeps its ⌘0, its View
//    menu item and its place in this pill's own menu; what it loses is the
//    prefix in the readout, and a 105 pt plate sized for a string that is
//    only sometimes there was 64 pt of permanent air.
//
//  The drawing's three tools are exactly the three that were here — import
//  and export live on the left rail's header, because opening a file is not a
//  thing you do to the picture.
//
//  **Two things the bar hosts only while a rail is folded.** The window
//  buttons sit on the rail header's centreline, which is also the bar's, so
//  when the left rail goes the bar is what has to leave room for them
//  (`barLeadingWithButtons`). And each `sidebar` toggle moves here from its
//  own rail's header for the same reason: the PRD requires both to be on
//  screen at every moment, and a folded rail has no header to hold one.
//
//  **Selection is orange, not grey.** A selected control tints the glyph
//  itself (`Theme.accent`) instead of putting a darker plate behind it. That
//  is Capture One's convention and it is the better one here for a specific
//  reason: this interface is almost entirely greys, so a grey-on-grey plate
//  reads as a rendering artefact at a glance and has to be looked *for*. The
//  one accent colour in the palette exists to be found without looking.

import SwiftUI

struct TopBar: View {
    @Bindable var session: Session

    // **The full-screen button and its state are gone.** Full screen is the
    // green window button, ⌃⌘F, the View menu and the window gesture; a fifth
    // door on the bar was the only glyph there that said nothing about the
    // photograph (the user's note: "最右边那个全屏按钮意义不大"). Nothing else
    // on this bar changes with full screen, so the `fullScreen` flag and its
    // two notification observers went with it.

    var body: some View {
        HStack(spacing: 0) {
            // Everything here is spaced from the bar's leading edge, and that
            // edge is either the bar's own padding or the room the window
            // buttons need — they are on this row whenever the left rail is
            // not (Windows/TrafficLights.swift).
            Spacer()
                .frame(width: session.leftCollapsed ? Theme.Metric.barLeadingWithButtons
                                                    : Theme.Metric.barPadding)
            if session.leftCollapsed {
                SidebarToggle(edge: .leading, collapsed: $session.leftCollapsed)
                    .padding(.trailing, Theme.Metric.barClusterGap)
            }
            // ---- files -------------------------------------------------
            // **The file actions live here now.** They were on the left rail's
            // header, which meant folding that rail took Open and Export off
            // screen and left only their shortcuts — two file actions
            // disappearing with a panel of presets (UI-SPEC §1.4). The bar is
            // the one row that is always there.
            PanelIconButton(systemImage: "square.and.arrow.down", help: L(.helpOpen) + " (⌘O)") {
                session.openPanel()
            }
            PanelIconButton(systemImage: "square.and.arrow.up", help: L(.helpExport) + " (⌘E)",
                            enabled: session.selection != nil) {
                session.showExport = true
            }
            clusterDivider()
            // ---- tools --------------------------------------------------
            // Shortcuts are appended at the call site rather than stored in the
            // table — the spec's rule, and it is what keeps a translation from
            // having to place `(V)` inside a Chinese phrase.
            //
            // **Two tools, and the second one is the only real mode.** There
            // were three: Select and Pan both fell through to the same branch
            // in the canvas (drag pans), so two buttons did one thing and
            // differed only in the cursor they drew. Pan is gone; Select is
            // the neutral mode and drag pans in it. Crop stays because it *is*
            // a mode — handles, a straighten gesture, a lock on zooming.
            //
            // **Crop has no key** beyond its own (C); the spec lists Select
            // and Pan among the toolbar's tools and gives Crop no row, and its
            // Chinese in the table (裁剪) belongs to the *section*.
            toolButton("cursorarrow", .select, L(.helpSelect) + " (V)")
            toolButton("crop", .crop, "Crop (C)")
                .padding(.leading, Theme.Metric.barItemGap)
            clusterDivider()
            // ---- the drag surface, then the view cluster ------------------
            // The bar's middle is the window's drag surface: the titlebar is
            // hidden, and this is where a toolbar would be.
            WindowDragHandle().frame(minWidth: 8, maxWidth: .infinity)
            // ---- view ---------------------------------------------------
            // "full" once the frame is on the canvas at its own resolution,
            // accented while that render is still on its way. Nothing here is
            // about zoom any more: the canvas settles at the frame's own size
            // after every edit, whatever the zoom.
            if session.fullPending || session.renderer.showsFullRender {
                Text(session.renderer.showsFullRender ? L(.statusFull) : L(.statusFullPending))
                    .font(Theme.Font.caption)
                    .foregroundStyle(session.fullPending ? Theme.accent : Theme.dim)
                    .help(session.renderer.showsFullRender
                          ? "The canvas is showing this frame at its own resolution."
                          : "Rendering this frame at its own resolution…")
                    .padding(.trailing, Theme.Metric.barClusterGap)
            }
            // **The original has no button of its own.** It had a filled pill
            // beside this one and both answered "what am I looking at", which is
            // one question and wants one control: the split glyph now carries
            // it, by turning orange and swapping which half of the block is
            // filled while ⎵ is held (the user's note: "按空格的时候那个开关
            // 图标变成橙色,并且图标上的方块左右切换就行了"). The canvas is still
            // where the gesture lives — this only reports it.
            //
            // Before/after, left of the zoom controls: it belongs with zoom
            // rather than with the tools because it changes how the canvas is
            // *displayed*, not what a click on it does.
            let showingOriginal = session.showingOriginal
            Button { session.comparing.toggle() } label: {
                BeforeAfterIcon(color: (session.comparing || showingOriginal) ? Theme.accent : Theme.text,
                                showingBefore: showingOriginal)
                    .frame(width: Theme.Metric.beforeAfterIcon.width,
                           height: Theme.Metric.beforeAfterIcon.height)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!session.canCompare)
            .opacity(session.canCompare ? 1 : 0.4)
            // The spec's row is the phrase only. Its "drag the line on the
            // canvas" clause has no row and an English sentence cannot be
            // appended to a Chinese one, so the tooltip is the phrase plus the
            // shortcut the spec says to append — and now the held key as well,
            // because a state this glyph draws has to say somewhere how it is
            // entered.
            .help(L(.helpBeforeAfter) + " (⌥\\)\n" + L(.helpHoldOriginal))
            .padding(.trailing, Theme.Metric.barClusterGap)
            // The value, then out, then in.
            zoomPill.rowEnabled(!session.zoomLocked)
            iconButton("minus.magnifyingglass", L(.helpZoomOut) + " (⌘−)", disabled: session.zoomLocked) { session.zoomStep(-1) }
                .padding(.leading, Theme.Metric.barItemGap)
            iconButton("plus.magnifyingglass", L(.helpZoomIn) + " (⌘+)", disabled: session.zoomLocked) { session.zoomStep(1) }
                .padding(.leading, Theme.Metric.barItemGap)
            // **The full-screen button is gone.** It was the fifth way to do
            // the same thing — the green window button, ⌃⌘F, the View menu and
            // the full-screen gesture all reach it — and it was the one item
            // on the bar whose glyph meant nothing about the photograph. The
            // user's note: "最右边那个全屏按钮意义不大".
            //
            // The right rail's toggle, when its own header is not on screen —
            // the same rule as the left one: a folded rail has no header to
            // hold its door, and the PRD requires both doors on screen at
            // every moment.
            if session.rightCollapsed {
                clusterDivider()
                SidebarToggle(edge: .trailing, collapsed: $session.rightCollapsed)
            }
            // ---- the negative, and the one thing to do about it ----------
            // **The app's most prominent moment, so it gets the most prominent
            // place: the trailing end of the bar.** A frame opened for the
            // first time arrives as the film that was just developed — the
            // engine's own `scan_film` render — and this prints it. It is the
            // only accent-filled button in the bar and it exists only while
            // there is a negative waiting.
            //
            // It moved here from the middle of the bar, and the whole canvas is
            // now a target for the same action as well (`Session.canvasClicked`):
            // a button that appears for one moment in a bar nobody has looked at
            // yet is a button that gets missed, and the moment it belongs to is
            // the picture. The bar keeps it because a *visible* control is what
            // makes the gesture discoverable at all.
            if session.negativePending {
                clusterDivider()
                Button { session.printNegative() } label: {
                    Text(L(.actionPrintNegative))
                        .font(Theme.Font.label)
                }
                .buttonStyle(.primarySurface)
                .keyboardShortcut(.return, modifiers: [])
                .help(L(.helpPrintNegative))
            }
            Spacer().frame(width: Theme.Metric.barPadding)
        }
        .frame(height: Theme.Metric.topBarHeight)
        .barCard()
        // The whole bar is a window drag surface behind its controls, not
        // just the gap in the middle: with the titlebar hidden and the bar
        // now flush with the window's top edge, this row *is* where a
        // titlebar would be, and a flush bar whose only draggable part is an
        // 8 pt gap between two clusters is a window that feels nailed down.
        .background(WindowDragHandle())
    }

    /// The seam between two clusters on the bar.
    ///
    /// A hard divider is what makes a toolbar read as groups rather than as a
    /// row of unrelated glyphs: the eye gets four short runs instead of one
    /// long one, and the gaps inside a run can then be *small*. It is made of
    /// `ruleSoft`, the same material as every other divider (UI-SPEC §2.6), so
    /// the bar has no line the rest of the interface does not have.
    private func clusterDivider() -> some View {
        Rectangle()
            .fill(Theme.ruleSoft)
            .frame(width: 1, height: 16)
            .padding(.horizontal, Theme.Metric.barClusterGap)
    }

    // `statusText` moved to the canvas with the status itself (see
    // `EditorWindow`'s bottom-leading overlay): the service cannot report real
    // progress — a render call does not return until it is finished and the
    // transport is single-flight, so there is nothing to poll — and elapsed
    // time is what is actually known.

    private func toolButton(_ name: String, _ tool: CanvasTool, _ help: String) -> some View {
        BarIcon(name: name, help: help,
                selected: session.tool == tool,
                restOpacity: 0.55) { session.tool = tool }
    }

    /// `disabled` is for the controls the crop tool locks: greyed out, so the
    /// toolbar says *why* nothing happens, rather than a live-looking button
    /// that quietly does nothing (`Theme.text` at 0.4 is the same weight the
    /// before/after button uses when it has nothing to compare).
    private func iconButton(_ name: String, _ help: String, disabled: Bool = false,
                            action: @escaping () -> Void) -> some View {
        BarIcon(name: name, help: help, disabled: disabled, action: action)
    }

    private var zoomPill: some View {
        Menu {
            Button(L(.helpFit)) { session.zoomToFit() }
            ForEach([0.25, 0.5, 1.0, 2.0, 4.0], id: \.self) { f in
                Button("\(Int(f * 100)) %") { session.zoomTo(fraction: f) }
            }
        } label: {
            // zoomPercent is 0 until an image is on the canvas.
            //
            // **No `Fit ·` prefix.** v3's plate is 41.29 pt and the prefix
            // does not fit in it. Whether the canvas is fitted is still worth
            // knowing, so it is said in the tooltip and by the check mark in
            // this menu rather than by a string that would either truncate
            // the number or size the plate for a case that is usually absent.
            Text(session.zoomPercent == 0 ? "—" : "\(session.zoomPercent) %")
                .font(Theme.Font.zoomValue)
                .foregroundStyle(Theme.text)
                .frame(width: Theme.Metric.zoomPill.width, height: Theme.Metric.zoomPill.height)
                // The drawing's plain `.st13` plate, now wearing the shared
                // pill surface so it is the same material as every other pill
                // — and so it stops being the one flat capsule on a bar of
                // bare glyphs, which is how it read in a capture.
                .pillSurface(base: Theme.pill)
                .contentShape(Capsule())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help(session.isFit ? "Fitted to the window — \(session.zoomPercent) % (⌘0)"
                            : "Zoom — \(session.zoomPercent) %")
    }
}

/// A top-bar glyph: ink, a hover wash, and nothing else.
///
/// No plate and no border — this bar is flush and 38 pt, so a capsule around
/// one glyph would be the only rounded thing on it. Selection stays an accent
/// glyph rather than a plate, which is the bar's own documented decision (a
/// grey-on-grey plate reads as a rendering artefact in an interface this
/// grey); the hover wash is what tells the pointer the glyph is live, so the
/// bar has some feedback that is not colour.
private struct BarIcon: View {
    let name: String
    let help: String
    var disabled = false
    var selected = false
    /// Where the glyph sits when nothing is happening. The tools are dimmer at
    /// rest than the zoom cluster, and that difference is the drawing's.
    var restOpacity: Double = 1
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: Theme.Metric.toolIcon, weight: .regular))
                .foregroundStyle(ink)
                .frame(width: 28, height: 28)
                .background {
                    if hovered && !disabled {
                        RoundedRectangle(cornerRadius: Theme.Metric.fieldRadius, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
        .onHover { hovered = $0 }
    }

    private var ink: Color {
        if disabled { return Theme.text.opacity(0.4) }
        if selected { return Theme.accent }
        return hovered ? Theme.text : Theme.text.opacity(restOpacity)
    }
}
