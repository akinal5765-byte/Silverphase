//  TopBar.swift — the editor toolbar: select · crop …… before/after · export
//  · [100 %] · zoom-out · zoom-in · full screen.
//
//  **v3 (2026-09-18) flattened it and re-ordered it.** It was a rounded pill
//  floating on ground; it is now a flat bar across the window in Modern,
//  52 pt tall, while Traditional retains the centre column's 38 pt bar.
//  Neither mode puts a rounded capsule behind the stage-button cluster.
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
//  Traditional keeps Open and Export on the left. Modern uses the File menu
//  for Open and places Export last among the right-hand inspector destinations.
//
//  In Modern the old leading material button is gone: the right-hand Film
//  stage opens film parameters and switches the bottom strip to film/paper
//  selection. The bar keeps space for the window buttons at the left edge.
//  Traditional retains its collapsible left material rail.
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
    @State private var zoomHovered = false

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
            // The window buttons are always on this row, so the bar always
            // reserves their clearance.
            Spacer().frame(width: Theme.Metric.barLeadingWithButtons)
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
            toolButton("crop", .crop, L(.helpCrop) + " (C)")
                .padding(.leading, Theme.Metric.barItemGap)
            // **The bar's four groups, one divider each.** tools | stages |
            // view | actions. There were three dividers in four places: none
            // after the tools, so the two modes sat against the six stages as
            // if they were eight of one kind.
            clusterDivider()
            // ---- the drag surface, then the view cluster ------------------
            // The bar's middle is the window's drag surface: the titlebar is
            // hidden, and this is where a toolbar would be.
            WindowDragHandle().frame(minWidth: 8, maxWidth: .infinity)
            // ---- destinations ------------------------------------------
            // **Six stages and Export: one question, seven answers.** "Which
            // surface is the right rail showing?" The export page is one of
            // them — the same *navigation* act as choosing Film — so it sits in
            // this group rather than at the far end with the commands, where a
            // destination read as an action and the app's rarest button took
            // the place the eye arrives last.
            //
            // The selected glyph is the only stage mark: `showExport` turns the
            // six stage glyphs off and this one on, because the rail is showing
            // one surface and only one control may claim it.
            HStack(spacing: 0) {
                inspectorStages
                BarIcon(name: "square.and.arrow.up", help: L(.helpExport) + " (⌘E)",
                        disabled: session.selection == nil,
                        selected: session.showExport) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        session.showExport.toggle()
                    }
                }
            }
            clusterDivider()
            // ---- view ---------------------------------------------------
            // The render state is reported under the document name (below),
            // not as a badge here.
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
                Image(systemName: showingOriginal ? "rectangle.lefthalf.inset.filled"
                                                  : "rectangle.righthalf.inset.filled")
                    .font(.system(size: Theme.Metric.toolIcon, weight: .regular))
                    .foregroundStyle((session.comparing || showingOriginal) ? Theme.accent : Theme.text)
                    .frame(width: Theme.Metric.controlHitTarget, height: Theme.Metric.controlHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!session.canCompare)
            .opacity(session.canCompare ? 1 : Theme.disabledOpacity)
            // The spec's row is the phrase only. Its "drag the line on the
            // canvas" clause has no row and an English sentence cannot be
            // appended to a Chinese one, so the tooltip is the phrase plus the
            // shortcut the spec says to append — and now the held key as well,
            // because a state this glyph draws has to say somewhere how it is
            // entered.
            .help(L(.helpBeforeAfter) + " (⌥\\)\n" + L(.helpHoldOriginal))
            .padding(.trailing, Theme.Metric.barClusterGap)
            // The value, then out, then in.
            zoomReadout.rowEnabled(!session.zoomLocked)
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
            // Stage buttons above are the inspector's persistent doors. Its
            // own header also carries a close button while it is open.
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
            // **A reserved slot.** The negative's action appears for one
            // moment and disappears; drawn as a plain `if` it pushed every
            // control to its right back and forth as frames were opened, which
            // is the bar moving under the pointer. The slot is always there and
            // always the same width, so the bar's layout is the same with and
            // without the button — only its ink comes and goes.
            clusterDivider()
            ZStack {
                if session.negativePending {
                    Button { session.printNegative() } label: {
                        Text(L(.actionPrintNegative))
                            .font(Theme.Font.label)
                    }
                    .buttonStyle(.primarySurface)
                    .keyboardShortcut(.return, modifiers: [])
                    .help(L(.helpPrintNegative))
                }
            }
            .frame(width: Theme.Metric.primaryActionSlot)
            // **The reserved slot is the end of the bar.** Export is a
            // destination and lives with the stages; what is left here is the
            // one *command* the bar carries, so nothing needs a divider after
            // it and an empty slot is simply the bar's trailing air.
            Spacer().frame(width: Theme.Metric.barPadding)
        }
        .frame(height: Theme.Metric.modernTopBarHeight)
        .modifier(EditorChromeSurface(flat: true))
        // The two rails have centred names; the canvas needs the same anchor
        // so the long drag surface does not read as an unfinished toolbar.
        // Keep it out of the way when the centre column is too narrow for
        // both control clusters and a document name.
        .overlay {
            GeometryReader { geometry in
                if geometry.size.width >= 1100 {
                    VStack(spacing: Theme.Metric.space2) {
                        Text(session.modernBatchGridActive
                             ? T("\(session.selectedFrames.count) photos selected",
                                 "已选 \(session.selectedFrames.count) 张照片")
                             : session.selection?.lastPathComponent ?? T("Preview", "预览"))
                            .font(Theme.Font.railTitle)
                            .foregroundStyle(Theme.Ink.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .allowsHitTesting(false)
                        HStack(spacing: Theme.Metric.space4) {
                            if session.working {
                                ProgressView().controlSize(.mini).scaleEffect(0.7)
                            }
                            Text(session.modernBatchGridActive
                                 ? (session.exportProgress == nil
                                    ? T("Ready for batch export", "可批量导出")
                                    : T("Exporting batch…", "正在批量导出…"))
                                 : documentDetail)
                                .font(Theme.Font.caption)
                                .foregroundStyle(session.stockWarning == nil ? Theme.Ink.tertiary : Theme.accent)
                                .lineLimit(1)
                                .help(session.modernBatchGridActive ? "" : documentDetail)
                                .allowsHitTesting(false)
                            if !session.serviceReady && session.selection != nil {
                                Button(L(.actionRestart)) { session.restartService() }
                                    .buttonStyle(.plain)
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .frame(maxWidth: 320)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        // The whole bar is a window drag surface behind its controls, not
        // just the gap in the middle: with the titlebar hidden and the bar
        // now flush with the window's top edge, this row *is* where a
        // titlebar would be, and a flush bar whose only draggable part is an
        // 8 pt gap between two clusters is a window that feels nailed down.
        .background(WindowDragHandle())
    }

    private var documentDetail: String {
        let raw = session.working
            ? String(format: "%@ · %.1f s", session.status, session.workSeconds)
            : session.status
        let status: String
        if let name = session.selection?.lastPathComponent, raw.hasPrefix(name) {
            let remainder = raw.dropFirst(name.count)
                .trimmingCharacters(in: CharacterSet(charactersIn: " ·"))
            status = remainder.isEmpty ? raw : remainder
        } else {
            status = raw
        }
        var parts = [session.stockWarning ?? status]
        if session.fullPending {
            parts.append(L(.statusFullPending))
        } else if session.renderer.showsFullRender {
            parts.append(L(.statusFull))
        }
        return parts.joined(separator: " · ")
    }

    /// The seam between two clusters on the bar.
    ///
    /// A hard divider separates file actions from canvas tools; the flexible
    /// drag surface separates those tools from the view controls. It is made of
    /// `ruleSoft`, the same material as every other divider (UI-SPEC §2.6), so
    /// the bar has no line the rest of the interface does not have.
    private func clusterDivider() -> some View {
        Rectangle()
            .fill(Theme.ruleSoft)
            .frame(width: Theme.Metric.rule, height: Theme.Metric.barDividerHeight)
            .padding(.horizontal, Theme.Metric.barClusterGap)
    }

    private var inspectorStages: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                ForEach(InspectorStage.allCases) { stage in
                    BarIcon(name: stage.symbol, help: stage.title,
                            selected: !session.showExport && !session.rightCollapsed && session.inspectorStage == stage) {
                        withAnimation(.easeOut(duration: 0.18)) {
                            session.selectInspectorStage(stage)
                        }
                    }
                }
            }
            Menu {
                ForEach(InspectorStage.allCases) { stage in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            session.selectInspectorStage(stage)
                        }
                    } label: {
                        Label(stage.title, systemImage: stage.symbol)
                    }
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: Theme.Metric.toolIcon))
                    .frame(width: Theme.Metric.controlHitTarget,
                           height: Theme.Metric.controlHitTarget)
            }
            .menuStyle(.borderlessButton)
            .help(L(.railEdit))
        }
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

    /// **The zoom read-out, not a pill.**
    ///
    /// It was a `.st13` capsule on the argument that a plate makes it read as
    /// a control. It does — and that is the problem: the capsule is the shape
    /// this app reserves for *choosing from a list* (UI-SPEC §2.12), and every
    /// other control on this bar is a bare glyph. One plated control in a row
    /// of glyphs claims to be a different kind of thing, and what the user
    /// actually does here is **read** the magnification (the menu is the
    /// secondary path — the wheel, ⌘± and Fit cover the rest).
    ///
    /// So it is ink with the same hover wash every glyph on this bar has, and
    /// the only plate left on the bar is the primary action's accent fill.
    private var zoomReadout: some View {
        Menu {
            Button(L(.helpFit)) { session.zoomToFit() }
            ForEach([0.25, 0.5, 1.0, 2.0, 4.0], id: \.self) { f in
                Button("\(Int(f * 100)) %") { session.zoomTo(fraction: f) }
            }
        } label: {
            // zoomPercent is 0 until an image is on the canvas. There is no
            // `Fit ·` prefix: whether the canvas is fitted is said in the
            // tooltip and by the check mark in this menu.
            Text(session.zoomPercent == 0 ? "—" : "\(session.zoomPercent) %")
                .font(Theme.Font.zoomValue)
                .foregroundStyle(Theme.text)
                .frame(width: Theme.Metric.zoomPill.width, height: Theme.Metric.zoomPill.height)
                .background {
                    if zoomHovered {
                        RoundedRectangle(cornerRadius: Theme.Metric.modernControlRadius,
                                         style: .continuous)
                            .fill(Theme.buttonHoverWash)
                    }
                }
                .contentShape(Rectangle())
                .onHover { zoomHovered = $0 }
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help(session.isFit
              ? T("Fitted to the window — \(session.zoomPercent) % (⌘0)",
                  "适合窗口 — \(session.zoomPercent) % (⌘0)")
              : T("Zoom — \(session.zoomPercent) %", "缩放 — \(session.zoomPercent) %"))
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
                .frame(width: Theme.Metric.controlHitTarget, height: Theme.Metric.controlHitTarget)
                .background {
                    if hovered && !disabled {
                        RoundedRectangle(cornerRadius: Theme.Metric.fieldRadius, style: .continuous)
                            .fill(Theme.buttonHoverWash)
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
        if disabled { return Theme.text.opacity(Theme.disabledOpacity) }
        if selected { return Theme.accent }
        return hovered ? Theme.text : Theme.text.opacity(restOpacity)
    }
}
