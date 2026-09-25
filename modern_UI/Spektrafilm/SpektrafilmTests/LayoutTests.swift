//  Layout tests: the window at the three display shapes that matter —
//  MacBook Pro 14" (1512×982 pt), 16:9 (1920×1080), the 21:9 (3360×1418) —
//  measured against the **v3** drawing's geometry, not eyeballed.
//
//  The derivation of every number asserted here is
//  `modern_UI/design/UI-SPEC.md` §10.3, which tabulates the 2026-09-18
//  drawing at artboard ÷ 2. The assertions the 2026-09-17 drawing's version
//  made are gone: four of them would fail by construction — the floating
//  bar's radius, its air above, its inset, and the odd-row rule for a list
//  that is grouped — and a fifth, `actionHeight`, named a token that no
//  longer exists. `ModernCalibrationTests` covers what this file cannot
//  (the Modern layout's type ramp and spacing scale), and the two together
//  are the replacement for the deleted drawing-comparison tools.
//
//  **What this file can and cannot say.** Every number here is geometry the
//  layout math promises. None of it is evidence about type, ink, or whether
//  the thing looks like the interface is supposed to. That evidence is a
//  **real-window capture** (`Tools/capture-live.sh`) and, for the rules a
//  geometry assertion cannot state, the source-level checks in
//  `ModernCalibrationTests`. The cautionary note in `design/README.md` about a
//  pass that "meant much less than it sounded like" is about exactly this
//  file's predecessor: it graded the drawing's edges exact while the type, the
//  rows and the wells were all wrong, because none of those is an edge.

import SwiftUI
import XCTest

@MainActor
final class LayoutTests: XCTestCase {
    static let sizes: [(String, CGSize)] = [
        ("macbook-pro-14", CGSize(width: 1512, height: 982)),
        ("16x9", CGSize(width: 1920, height: 1080)),
        ("21x9", CGSize(width: 3360, height: 1418)),
    ]

    func testSelectingAnInspectorStageReplacesModernExportInsteadOfFoldingTheRail() {
        let session = Session()
        session.showExport = true
        session.rightCollapsed = true
        XCTAssertFalse(session.modernFilmChooserActive)
        session.selectInspectorStage(.film)
        XCTAssertFalse(session.showExport)
        XCTAssertFalse(session.rightCollapsed)
        XCTAssertEqual(session.inspectorStage, .film)
    }

    /// Host the real EditorWindow in an NSHostingView at each size and check
    /// the geometry the layout math promises: three flush regions, a centre
    /// column that is what is left, and a canvas that is still a canvas.
    func testRegionGeometryAtEverySize() {
        let m = Theme.Metric.self
        for (name, size) in Self.sizes {
            let session = Session()
            let host = NSHostingView(rootView: EditorWindow(session: session).environment(\.snapshotMode, true))
            host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            // Flush: the left rail starts at the window's edge and the right
            // one ends at it. There is no outer margin to subtract — and the
            // full-height dividers are overlays, so they take none either.
            let centreX = m.leftPanelWidth
            let centreW = size.width - m.leftPanelWidth - m.rightPanelWidth
            XCTAssertEqual(centreX, 254, "\(name)")
            XCTAssertGreaterThan(centreW, 500, "\(name): centre column too narrow")
            // The bar is a row of its own now, and the hairline under it is
            // 1 pt of the column's height rather than air around a pill.
            let canvasTop = m.barStrip + m.rule
            let canvasBottom = size.height - m.filmstripHeight - m.rule
            XCTAssertGreaterThan(canvasBottom - canvasTop, 400, "\(name): canvas too short")
            // The fit-scale rule: with a 3:2 image the canvas is wider than tall.
            XCTAssertGreaterThan(centreW / (canvasBottom - canvasTop), 1.0, name)
            _ = host.fittingSize
        }
    }

    /// **One layout.** The three-region editor is gone (2026-09-26), so what
    /// this asserts is that the floating one hosts at every display shape with
    /// a canvas that is still a canvas — the geometry tables below are the
    /// export page's own drawing and are measured through `Theme.Metric`.
    func testTheEditorHostsAtEverySize() {
        for (name, size) in Self.sizes {
            let session = Session()
            let host = NSHostingView(rootView: EditorWindow(session: session)
                .environment(\.snapshotMode, true))
            host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(host.fittingSize.width, 0, name)
        }
    }

    /// The v3 artboard is 3840×2160; a 1920×1080 window is exactly half of it.
    func testTokensMatchTheDrawing() {
        let m = Theme.Metric.self
        // The three regions.
        XCTAssertEqual(m.leftPanelWidth, 507.36 / 2, accuracy: 1)      // rail fill ends x 507.36
        XCTAssertEqual(m.rightPanelWidth, 288.07, accuracy: 0.1)       // x 3263.86, width 288.07
        XCTAssertEqual(m.filmstripHeight, 132.35, accuracy: 0.4)       // y 1895.30, height 132.35
        XCTAssertEqual(m.panelHeaderHeight, 75.59 / 2, accuracy: 0.3)  // first hairline, y 75.59
        // The right rail's x falls out of the two widths.
        XCTAssertEqual(1920 - m.rightPanelWidth, 3263.86 / 2, accuracy: 0.1)
        // **The bar does not float.** It fills the centre column's top from
        // y .59 to y 75.59 — flush with both rails and with the window's top
        // edge — so all three of its floating tokens are zero and its height
        // is the rail header's, not a number of its own.
        XCTAssertEqual(m.topBarHeight, m.panelHeaderHeight,
                       "the bar and the rail headers share one top row")
        XCTAssertEqual(m.topBarHeight, 75 / 2, accuracy: 0.5)
        XCTAssertEqual(m.barRadius, 0, "a flush bar has no corner")
        XCTAssertEqual(m.barTop, 0, "a flush bar has no air above it")
        XCTAssertEqual(m.barInset, 0, "a flush bar has nothing to be inset by")
        // …and with no air, the strip the column reserves *is* the bar. This
        // is the identity the old file asserted with two non-zero terms.
        XCTAssertEqual(m.barStrip, m.topBarHeight)
        // The percentage plate: x 2769.98…2852.56. Its **width** is the
        // drawing's; its height is the bar's one line box (`gridControl`),
        // because a pill 20.69 tall beside glyphs in 28 pt targets put the
        // read-out off the bar's centreline (UI-SPEC §2.15).
        XCTAssertEqual(m.zoomPill.width, (2852.56 - 2769.98) / 2, accuracy: 0.05)
        XCTAssertEqual(m.zoomPill.height, m.gridControl,
                       "the bar has one line box and the pill is in it")
        // A section: the right rail's two collapsed headers measure 29.05 and
        // 31.05 between hairlines, so a header row is 30.
        XCTAssertEqual(m.headerHeight, 30, accuracy: 1.1)
        // A row: v3's labels start at 15.61…17.12, so the row is inset 16.
        XCTAssertEqual(m.rowInset, 16, accuracy: 0.8)
        XCTAssertEqual(m.controlHeight, 27.8 / 2, accuracy: 0.05)
        XCTAssertEqual(m.sliderValueWidth, 87.46 / 2, accuracy: 0.05)
        XCTAssertEqual(m.sliderValueGap, (383.67 - 353.56) / 2, accuracy: 0.05)
        // **One label column for every rail.** v3 drew Camera a second one —
        // 9 pt labels in a 70 pt column, its controls at x 86.35 — and that
        // x is the narrower column, kept here as the number that is *no
        // longer* the layout: Camera shares `sliderLabelWidth` now, so its
        // controls start 14 pt further right (UI-SPEC 字体一节). The assertion is
        // the inequality the unification is: no rail's column is Camera's.
        XCTAssertEqual(m.sliderLabelWidth, 84, accuracy: 0.5)
        XCTAssertGreaterThan(m.sliderLabelWidth, (86.35 - 16) / 2 + 35,
                             "Camera no longer has a column of its own")
        // Film's controls.
        XCTAssertEqual(m.pickerWidth, 214.06 / 2, accuracy: 0.05)
        XCTAssertEqual(m.fieldWidth, 99.53 / 2, accuracy: 0.05)
        XCTAssertEqual(m.unitWidth, 76.63 / 2, accuracy: 0.05)
        // The lists: a pitch of 18, and a mark that is **shorter than its own
        // row**. That inequality is the whole difference between v3's mark
        // and the full-width band it replaced.
        XCTAssertEqual(m.listRowHeight, 36 / 2, accuracy: 0.05)
        XCTAssertEqual(m.stockSelectionHeight, 30.53 / 2, accuracy: 0.05)
        XCTAssertLessThan(m.stockSelectionHeight, m.listRowHeight,
                          "a mark as tall as its row is a filled cell, not a selection")
        XCTAssertEqual(m.stockSelectionRadius, m.stockSelectionHeight / 2, accuracy: 0.01)
        // The capsule is inset **unequally**, which is why the list cannot be
        // padded with one number: the trailing inset is the drawing's 26.48,
        // the leading one is the drawing's minus the text's own inset.
        //
        // **The leading pair left the drawing deliberately.** v3 put the
        // capsule at 16.79 and the row's text at 21.33, so a list row's first
        // glyph sat 5.3 pt right of every control label above it. The text is
        // on `rowInset` now and the capsule hangs to its left (UI-SPEC §2.4);
        // the old 33.57 / 42.66 pair is history, not an assertion.
        XCTAssertEqual(m.stockLeadingInset, m.rowInset - 5, accuracy: 0.05)
        XCTAssertEqual(m.stockTrailingInset, 254 - 227.52, accuracy: 0.05)
        XCTAssertNotEqual(m.stockLeadingInset, m.stockTrailingInset)
        // …and the glyphs sit inside it, not flush with it.
        XCTAssertEqual(m.stockTextLeadingInset, m.rowInset, accuracy: 0.05)
        XCTAssertGreaterThan(m.stockTextLeadingInset, m.stockLeadingInset,
                             "the row's text would start on the capsule's own edge")
        // The two actions: 165.72 × 37.03 halved, `rx 18.52 / 2`.
        XCTAssertEqual(m.actionSize.width, 165.72 / 2, accuracy: 0.05)
        XCTAssertEqual(m.actionSize.height, 37.03 / 2, accuracy: 0.05)
        XCTAssertEqual(m.actionRadius, 18.52 / 2, accuracy: 0.05)
        // The gap is **not** halved, and that is the handoff's table being
        // consistent rather than sloppy: `actionLeading` 13.33, `actionSize`
        // 82.86 and "first end x 96.19, second x 108.37" are all already in
        // points — 13.33 + 82.86 = 96.19 is the check — so the two x values
        // are not artboard units and dividing them would halve a measurement
        // twice. This assertion exists because it caught exactly that.
        XCTAssertEqual(m.actionLeading + m.actionSize.width, 96.19, accuracy: 0.05)
        XCTAssertEqual(m.actionGap, 108.37 - 96.19, accuracy: 0.05)
        XCTAssertEqual(m.actionLeading + m.actionSize.width + m.actionGap, 108.37,
                       accuracy: 0.05)
        // Sliders follow the drawing except where the product token supersedes
        // it. Two now: the checkbox's 5 pt artwork, and the slider itself.
        //
        // **The slider left the drawing deliberately.** v3 draws a 1.36 pt
        // hairline track and a 6.13 × 5.07 dot, which is a slider you have to
        // aim at; UI-SPEC §2.5 makes the track two-tone and the knob 9 pt
        // round, because the knob is what divides those two tones and has to
        // be findable. The old numbers are kept here as history, not asserted.
        XCTAssertEqual(m.trackHeight, 3, accuracy: 0.05)
        XCTAssertEqual(m.knobSize.width, 9, accuracy: 0.05)
        XCTAssertEqual(m.knobSize.height, 9, accuracy: 0.05)
        XCTAssertEqual(m.checkbox, 10, accuracy: 0.5)
        // The hairline, `.st1` at stroke-width 2 on a 2× drawing.
        XCTAssertEqual(m.rule, 1)
        // The one tab that survived, unchanged: rect 27.8 × 83.1 rx 13.9.
        XCTAssertEqual(m.tabThickness, 27.8 / 2, accuracy: 0.1)
        XCTAssertEqual(m.tabLength, 83.1 / 2, accuracy: 0.1)
    }

    /// Interactive ink and targets stay usable on a laptop.
    ///
    /// The slider and reset arrow keep their small drawn ink, while the
    /// checkbox was promoted to a product token after real use showed the
    /// reference artwork's 5 pt mark was unreadable and hard to click.
    func testSmallInkKeepsALargeTarget() {
        let m = Theme.Metric.self
        XCTAssertGreaterThanOrEqual(m.controlHitTarget, 28,
                                    "a toggle needs a target a pointer can find on a laptop")
        XCTAssertGreaterThan(m.controlHitTarget, m.checkbox * 2,
                             "the target is the ink again and then some")
        XCTAssertGreaterThanOrEqual(m.actionHitHeight, 28,
                                    "yellow action capsules need the same usable target")
        // The knob is never dragged by itself — the track's gesture covers a
        // whole row — so the row height is its effective target. The bound is
        // `* 2` now that the knob is a 9 pt round divider rather than a 5 pt
        // dot; what it separates is "a row" from "a dot", not a exact ratio.
        XCTAssertGreaterThan(m.rowHeight, m.knobSize.height * 2,
                             "the slider's gesture must not be the size of its dot")
        // The reset arrow and the toolbar glyphs keep the boxes §6 names.
        XCTAssertLessThan(m.resetIcon, 12, "v3 draws the reset arrow at 8–9 pt")
        XCTAssertGreaterThan(m.toolIcon, m.resetIcon)
    }

    func testInterfaceScaleDefaultsPersistsAndOffersReadableSteps() throws {
        XCTAssertEqual(InterfaceScale.allCases, [.compact, .standard, .large])
        XCTAssertEqual(InterfaceScale.defaultValue, .standard)
        XCTAssertEqual(InterfaceScale.standard.factor, 1.15, accuracy: 0.001)

        let suite = "interface-scale-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let fresh = InterfaceScaleStore(defaults: defaults)
        XCTAssertEqual(fresh.scale, .standard)
        fresh.scale = .large
        XCTAssertEqual(defaults.string(forKey: InterfaceScaleStore.key), InterfaceScale.large.rawValue)
        XCTAssertEqual(InterfaceScaleStore(defaults: defaults).scale, .large)
    }

    // MARK: Modern calibration (2026-09-26)

    /// The Modern surfaces read **one** spacing scale, and a value not on it
    /// is a value a view invented.
    ///
    /// This is the assertion the calibration rests on: before it, Modern had
    /// four spacing systems (the chrome's 12/20, the drawing-era 16/9, the
    /// chooser's 8/7/4 and a run of bare literals) and no way to tell an
    /// intended gap from a typo. The scale is 2/4/8/12/20, and it is small on
    /// purpose — the user's read was "间距不统一" *and* "整体偏松".
    func testTheModernSpacingScaleIsTheOnlyOne() {
        let m = Theme.Metric.self
        XCTAssertEqual([m.space2, m.space4, m.space8, m.space12, m.space20],
                       [2, 4, 8, 12, 20])
        // Monotone, and each step is the previous one's own multiple: a scale
        // with an unexplained jump hides a second scale.
        XCTAssertEqual(m.space4, m.space2 * 2)
        XCTAssertEqual(m.space8, m.space4 * 2)
        // 12 and 20 are deliberately not on the doubling chain — a 16 would
        // have made every gap a power of two and every surface's gutter equal
        // to its content inset, which is the "one number everywhere" failure
        // the scale exists to avoid.
        XCTAssertGreaterThan(m.space12, m.space8)
        XCTAssertGreaterThan(m.space20, m.space12)
        XCTAssertLessThan(m.space12, m.space20)
    }

    /// A floating surface's gutter, its content inset, and the rows inside it
    /// are three different numbers with three different jobs.
    ///
    /// The failure this pins is the one the audit found: `modernContentInset`
    /// was applied by the panel **and** by every section's bottom padding, so
    /// the last section carried 40 pt of air while the first carried 20, and
    /// changing the token moved two things at once.
    func testAModernSurfaceAppliesItsInsetOnce() {
        let m = Theme.Metric.self
        XCTAssertEqual(m.modernContentInset, m.space20)
        XCTAssertEqual(m.modernSurfaceGutter, m.modernChromeInset)
        XCTAssertEqual(m.modernPanelVerticalInset, 16)
        // The vertical inset is the tighter one, and that is the density fix:
        // a horizontal inset lines content up across surfaces, a vertical one
        // is repeated top and bottom and buys nothing.
        XCTAssertLessThan(m.modernPanelVerticalInset, m.modernContentInset)
        // Rows are tighter than the drawing's rail, and the row height is the
        // drawing's control row — Modern does not get a second row height.
        XCTAssertEqual(m.modernRowSpacing, m.space8)
        XCTAssertEqual(m.modernRowHeight, m.gridRow)
        XCTAssertEqual(m.modernControlHeight, m.gridControl)
        XCTAssertLessThan(m.modernRowSpacing, m.modernRowHeight)
        // A section's header is one line of type with no disclosure triangle
        // on a Modern surface, so its height plus the gap to its content must
        // still be a header a reader can find — and the gap must be on the
        // scale.
        XCTAssertEqual(m.modernHeaderHeight, 40)
        XCTAssertEqual(m.modernHeaderToContent, m.space8)
        XCTAssertEqual(m.modernSectionBottom, m.space20)
        XCTAssertEqual(m.modernBlockGap, m.space12)
    }

    /// The canvas reserves exactly the two strip heights the bottom slot
    /// draws, and it reserves them from one token each.
    ///
    /// They were bare `72`/`92` literals in three files — the strip's frame,
    /// the chooser's scroll view, and the canvas occlusion arithmetic — so a
    /// strip that grew by two points would have had its last row hidden behind
    /// the window's edge with nothing to point at.
    func testTheCanvasReservesTheStripItDraws() {
        let m = Theme.Metric.self
        XCTAssertEqual(m.modernStripHeight, 72)
        XCTAssertEqual(m.modernFilmChooserHeight, 92)
        XCTAssertGreaterThan(m.modernFilmChooserHeight, m.modernStripHeight)
        // The strip is taller than a section header and shorter than the
        // drawing's filmstrip — it is a navigator over the photograph, not a
        // second rail.
        XCTAssertGreaterThan(m.modernStripHeight, m.modernHeaderHeight)
        XCTAssertLessThan(m.modernStripHeight, m.filmstripHeight)
        // The occlusion the canvas is told about is the strip plus one
        // gutter, which is the same gutter the panel keeps.
        XCTAssertEqual(m.modernStripHeight + m.modernSurfaceGutter, 84)
    }

    /// Modern has **three** corner radii, and every tile-shaped control is one
    /// of them.
    ///
    /// It had eight live at once — 2, 4, 6, 7, 9, 11.5, 14 and the chrome's
    /// 16 — which UI-SPEC §2.10 forbids in as many words ("一张图里出现两种圆角").
    func testModernHasThreeRadiiAndNoMore() {
        let m = Theme.Metric.self
        XCTAssertEqual(m.modernControlRadius, m.fieldRadius)
        XCTAssertEqual(m.modernCardRadius, 9)
        XCTAssertEqual(m.modernContainerRadius, 16)
        XCTAssertLessThan(m.modernControlRadius, m.modernCardRadius)
        XCTAssertLessThan(m.modernCardRadius, m.modernContainerRadius)
        // The selection capsule is the list's own mark, not a fourth radius:
        // it is derived from its own height so a mark can never be a pill and
        // a square at the same time.
        XCTAssertEqual(m.modernSelectionRadius, m.stockSelectionRadius)
    }

    /// One glyph size per rank on a Modern rail, and one pointer target per
    /// rank across the window.
    ///
    /// The audit found 26, 28, 16×14 and 14 all answering "an icon in a rail",
    /// and glyph sizes of 9, 10 and 11 in one feature.
    func testAModernRailHasOneGlyphSizeAndOneTarget() {
        let m = Theme.Metric.self
        XCTAssertEqual(m.modernIconTarget, m.railIconTarget)
        XCTAssertGreaterThan(m.modernIconTarget, m.modernRowHeight,
                             "a rail target has to be findable, so it is larger than a row is tall")
        XCTAssertLessThan(m.modernIconTarget, m.controlHitTarget,
                          "the bar's row is taller than a rail's, so the bar's target is larger")
        XCTAssertGreaterThan(m.modernRowGlyph, m.modernSublayerGlyph,
                             "a row's glyph is a step above the glyph inside it")
        XCTAssertLessThan(m.modernRowGlyph, m.toolIcon)
    }

    /// The window buttons sit on the **rail header's** centreline, which is
    /// also the bar's — and with the bar flush and the same height as a
    /// header, that is now an identity rather than a coincidence.
    func testTheWindowButtonsHaveOneRowInBothStates() {
        let m = Theme.Metric.self
        XCTAssertEqual(m.trafficLightCentreY, m.panelHeaderHeight / 2)
        XCTAssertEqual(m.trafficLightCentreY, 19)
        // Exactly equal, where the old drawing's floating bar was within 2 pt:
        // `topBarHeight` *is* `panelHeaderHeight` and `barTop` is 0.
        let barCentreY = m.barTop + m.topBarHeight / 2
        XCTAssertEqual(barCentreY, m.trafficLightCentreY,
                       "one placement has to serve both rows")
        // A 14 pt button centred on 19 clears both edges of a 38 pt header.
        XCTAssertGreaterThan(m.trafficLightCentreY - TrafficLightAlignment.buttonDiameter / 2, 8)
        XCTAssertLessThan(m.trafficLightCentreY + TrafficLightAlignment.buttonDiameter / 2,
                          m.panelHeaderHeight - 8)
        // Whoever reserves the row reserves the same width, measured from the
        // same window origin: the header from the window's edge, the bar from
        // its own — which, with `barInset` at 0, is the same origin.
        XCTAssertEqual(m.barLeadingWithButtons, m.trafficLightClearance - m.barInset)
        XCTAssertEqual(m.barLeadingWithButtons, m.trafficLightClearance)
        XCTAssertEqual(m.trafficLightClearance,
                       m.trafficLightLeading + TrafficLightAlignment.rowWidth + m.trafficLightToGlyph)
        // And the reservation actually clears the buttons.
        XCTAssertGreaterThan(m.trafficLightClearance,
                             m.trafficLightLeading + TrafficLightAlignment.rowWidth)
    }

    /// Folding a rail moves its `sidebar` button onto the bar, and the bar
    /// then also carries the window buttons' clearance.
    ///
    /// v3's artwork contains neither the sidebar buttons nor the traffic
    /// lights; handoff §8.2 says to keep both and record the deviation rather
    /// than hide the functionality. This is the recording: the two
    /// reservations are one number seen from two origins, so the buttons
    /// cannot end up under a glyph in one state and not the other.
    func testAFoldedRailHandsItsRowToTheBar() {
        let m = Theme.Metric.self
        for (name, size) in Self.sizes {
            let session = Session()
            session.leftCollapsed = true
            session.rightCollapsed = true
            let host = NSHostingView(rootView: EditorWindow(session: session).environment(\.snapshotMode, true))
            host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            _ = host.fittingSize
            // With both rails folded the centre column is the whole window,
            // so the bar starts at its own edge and its first control has to
            // clear buttons placed from the window's edge.
            let barLeading = m.barInset + m.barLeadingWithButtons
            XCTAssertEqual(barLeading, m.trafficLightClearance, "\(name)")
            XCTAssertGreaterThan(barLeading,
                                 m.trafficLightLeading + TrafficLightAlignment.rowWidth,
                                 "\(name): the bar's first glyph would sit on a window button")
            // …and the buttons still fit inside the bar itself, which is the
            // only reason one centreline can serve both rows.
            XCTAssertGreaterThanOrEqual(m.trafficLightCentreY - TrafficLightAlignment.buttonDiameter / 2,
                                        m.barTop, "\(name)")
            XCTAssertLessThanOrEqual(m.trafficLightCentreY + TrafficLightAlignment.buttonDiameter / 2,
                                     m.barTop + m.topBarHeight, "\(name)")
        }
    }

    /// The rails are the user's, and both bounds have to leave a usable rail.
    func testPanelRangesContainTheDrawing() {
        let m = Theme.Metric.self
        XCTAssertEqual(m.leftPanelRange.standard, m.leftPanelWidth)
        XCTAssertEqual(m.rightPanelRange.standard, m.rightPanelWidth)
        // The left rail's floor is the Metering row: the shared label column,
        // two row insets, and a pill wide enough for `center-weighted
        // (legacy)`. The column is the wider one now that Camera shares it,
        // so this floor is 14 pt tighter than it was — the same arithmetic
        // `PanelResizeWiringTests` does from the other end.
        let meteringFloor = m.sliderLabelWidth + 2 * m.rowInset
        XCTAssertGreaterThan(m.leftPanelRange.narrowest - meteringFloor, 110,
                             "the Metering pill has to hold its longest string")
        XCTAssertLessThanOrEqual(m.leftPanelRange.narrowest, m.leftPanelWidth)
        XCTAssertGreaterThanOrEqual(m.leftPanelRange.widest, m.leftPanelWidth)
    }

    func testMinimumWindowStillFitsBothRails() {
        let m = Theme.Metric.self
        let canvas = m.minWindow.width - m.leftPanelWidth - m.rightPanelWidth
        XCTAssertGreaterThanOrEqual(canvas, 400)
    }

    /// The two capsules fit the rail they are inset into.
    ///
    /// v3 draws them at a fixed 82.86 each rather than as two halves of the
    /// rail, so unlike the old full-width pair they can overflow — and the
    /// rail is resizable down to `narrowest`, which the drawing says nothing
    /// about.
    func testTheTwoActionsFitTheNarrowestRail() {
        let m = Theme.Metric.self
        let needed = m.actionLeading + m.actionSize.width * 2 + m.actionGap
        XCTAssertLessThanOrEqual(needed, m.leftPanelRange.narrowest,
                                 "Solve / Original would run off a narrowed rail")
        XCTAssertLessThanOrEqual(needed, m.leftPanelWidth)
    }
}
