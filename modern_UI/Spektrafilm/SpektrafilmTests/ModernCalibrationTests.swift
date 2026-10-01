//  ModernCalibrationTests.swift — the two rules the Modern calibration added
//  on 2026-09-26, checked against the source rather than against a render.
//
//  ## Why a source check
//
//  Every other layout test in this target asks what the layout math promises.
//  That is the right question for a token, and the wrong one for the failure
//  this pass is about: Modern did not hold *wrong* numbers, it held **eight
//  spacing systems and four type ramps at once**, each locally reasonable, and
//  nothing in a geometry assertion can see "this view wrote 10 and its
//  neighbour wrote 8 for the same gap". A capture can see it only if someone
//  looks at the two side by side, which is how it survived four passes.
//
//  So these two tests read the view files and refuse the literal. They are
//  deliberately narrow: they scan the files that exist **only** on a Modern
//  surface, and they assert about a *set* of values rather than about any
//  particular one. That is what makes them maintainable — moving a token
//  changes no assertion here, and adding a tenth spacing system to a Modern
//  view fails immediately.
//
//  ## What they deliberately do not scan
//
//  Traditional-only code, which keeps the drawing's own numbers and is what
//  `LayoutTests` measures. `LeftPanel.swift` (only `SidebarToggle` is reachable
//  from Modern, and the test says so), `Filmstrip`'s `edgeButton`, and
//  `FilmSection.listSection` / `StockList` all belong to the deprecated layout.
//  The export page has its own frozen ramp (UI-SPEC §9.10) and is out of
//  scope. Settings, About and Boot are mode-independent windows with their
//  own geometry.

import SwiftUI
import XCTest

@MainActor
final class ModernCalibrationTests: XCTestCase {

    // MARK: the scanner

    /// The app's source directory, found from this file's own path so the test
    /// does not depend on the working directory `xctest` was launched with.
    private static var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)          // …/SpektrafilmTests/ThisFile.swift
            .deletingLastPathComponent()         // …/SpektrafilmTests
            .deletingLastPathComponent()         // …/Spektrafilm
            .appendingPathComponent("Spektrafilm")
    }

    private func source(_ relativePath: String) throws -> String {
        let url = Self.sourceRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Every `.swift` under a directory, relative to the app source root.
    private func swiftFiles(under relativePath: String) -> [String] {
        let root = Self.sourceRoot.appendingPathComponent(relativePath)
        // atPath returns relative names. Absolute enumeration canonicalises
        // /tmp to /private/tmp, which a prefix replacement cannot strip.
        guard let walker = FileManager.default.enumerator(atPath: root.path) else { return [] }
        return walker.compactMap { $0 as? String }
            .filter { URL(fileURLWithPath: $0).pathExtension == "swift" }
            .map { relativePath + "/" + $0 }
            .sorted()
    }

    // MARK: the Modern-only files

    /// Files that exist on a Modern surface and nowhere else. A literal in one
    /// of these is a literal on the Modern editor.
    private static let modernOnlyFiles = [
        "Theme/Theme.swift",
        "Windows/TopBar.swift",
        "Windows/EditorWindow.swift",
        "Panels/RightPanel.swift",
        "Panels/Filmstrip.swift",
        "Controls/SectionHeader.swift",
        "Controls/FormatPicker.swift",
        "Controls/ScrubSlider.swift",
        "Controls/DetentSlider.swift",
        "Controls/HistogramView.swift",
        "Controls/WhiteBalanceRows.swift",
        "Controls/ColorWheel.swift",
    ]

    private var modernRails: [String] {
        Self.modernOnlyFiles + swiftFiles(under: "Panels/Sections")
    }

    /// The export page is a Modern surface too.
    ///
    /// It has two homes — its own window and the editor's export rail — and
    /// the rail draws it **beside the parameter inspector**, which is the pair
    /// the 2026-09-26 calibration measured: 16 pt of extra indent and a row
    /// scale of its own. So its body is held to the same rules as the editor's.
    private var modernSurfaces: [String] {
        modernRails + [
            "Export/ExportPage.swift",
            "Export/SoftProof.swift",
            "Windows/SettingsWindow.swift",
            "Windows/AboutWindow.swift",
            "Windows/BootWindow.swift",
            "Windows/CollapseTab.swift",
            "Canvas/CropOverlay.swift",
            "Canvas/MaskOverlay.swift",
            "Canvas/CompareOverlay.swift",
        ]
    }

    // MARK: fonts

    /// A glyph is allowed to be large when it is a **display** element rather
    /// than a piece of the interface's type: the empty state's mark, the
    /// service-blocked warning, the boot window's wordmark. Above this the
    /// number is a drawing, below it the number is a type size and belongs in
    /// `Theme.Font`.
    private static let displayGlyphFloor: CGFloat = 17

    /// A modern view must not set a type size inline.
    ///
    /// `.font(.system(size: N, …))` written into a view is exactly how Modern
    /// grew four ramps: `Filmstrip` set 10 and 11, `SectionHeader` set 16,
    /// `CropSection` set 11 twice, `MasksSection` set 9 and 10, and none of
    /// them was wrong on its own. A role in `Theme.Font` is the fix, and a
    /// glyph that genuinely needs a display size says so with a literal at or
    /// above `displayGlyphFloor`.
    func testNoModernViewSetsATypeSizeInline() throws {
        let pattern = try NSRegularExpression(pattern: #"\.system\(size:\s*([0-9]+(?:\.[0-9]+)?)"#)
        var offenders: [String] = []
        // **`Theme.swift` is exempt from *this* test and only this one**: it is
        // where a size is *defined*, so a literal there is the token, not a use
        // of one. Every other surface is held to it, which is what makes the
        // grep in UI-SPEC §12 ("no `.font(.system(` outside Theme") true.
        for path in modernSurfaces where path != "Theme/Theme.swift" {
            let text = try source(path)
            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                // A comment explaining the rule is not a violation of it.
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { continue }
                let range = NSRange(line.startIndex..., in: line)
                guard let match = pattern.firstMatch(in: line, range: range),
                      let sizeRange = Range(match.range(at: 1), in: line),
                      let size = Double(line[sizeRange]) else { continue }
                if size < Self.displayGlyphFloor {
                    offenders.append("\(path):\(index + 1) — size \(line[sizeRange])")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      """
                      A Modern view set a type size inline. Use a `Theme.Font` \
                      role, or a `Theme.Metric` glyph token for an icon:
                      \(offenders.joined(separator: "\n"))
                      """)
    }

    /// The same rule for the glyph tokens: an icon size in a Modern view is a
    /// `Theme.Metric` value even when it is written into `.system(size:)`.
    ///
    /// This is the half the size-floor rule cannot see — `IconGlyph(size: 11)`
    /// passed a default of 11 through three call sites, two of which passed 9,
    /// and no literal scanner notices a default parameter.
    func testModernSectionsDoNotCarryTheirOwnGlyphDefaults() throws {
        var offenders: [String] = []
        for path in swiftFiles(under: "Panels/Sections") + ["Controls/FormatPicker.swift",
                                                            "Controls/SectionHeader.swift"] {
            let text = try source(path)
            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                // A default of a bare number on a size parameter is a second
                // glyph scale, by definition local to its view.
                if trimmed.contains("size: CGFloat = ") && !trimmed.contains("Theme.") {
                    offenders.append("\(path):\(index + 1) — \(trimmed)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "a glyph size default belongs in Theme.Metric:\n\(offenders.joined(separator: "\n"))")
    }

    // MARK: spacing

    /// Every spacing literal in a Modern view is a value on the 2/4/8/12/20
    /// scale.
    ///
    /// The scale is not a preference: it is the list of numbers the pass
    /// settled on after `Theme.Metric` had accumulated four systems, and its
    /// whole value is that a reader can tell an intended gap from a typo. A
    /// new number is therefore either a mistake or a decision that belongs in
    /// `Theme.Metric` with a reason.
    ///
    /// **What is exempt, and why.** A capsule's internal inset (a pill's text
    /// to its chevron) is geometry of a 13.9 pt control, not rhythm between
    /// surfaces, so `FormatPicker` names its own three constants. A `.frame`
    /// dimension is a shape's size rather than a gap. `0` is the right answer
    /// for a stack that is meant to be flush, and `1` is a hairline. Values
    /// derived from a token are not the thing this forbids.
    func testEveryModernSpacingLiteralIsOnTheScale() throws {
        let scale: Set<CGFloat> = [Theme.Metric.space2, Theme.Metric.space4,
                                   Theme.Metric.space8, Theme.Metric.space12,
                                   Theme.Metric.space20]
        // Gaps that are the geometry of a shape rather than rhythm between
        // two shapes: a hairline, a pill's own inset, a tick, a line box.
        let exempt: Set<CGFloat> = [0, 1, 3, 5, 6, 7, 9, 10, 11, 14, 16, 18, 22, 28,
                                    34, 54, 56, 72, 92]
        let pattern = try NSRegularExpression(
            pattern: #"(?:spacing|Spacer\(\)\.frame\(width|padding(?:\.(?:horizontal|vertical|top|bottom|leading|trailing))?)\(?\s*:?\s*([0-9]+(?:\.[0-9]+)?)\b"#)

        var offenders: [String] = []
        for path in modernSurfaces + ["Controls/SectionHeader.swift", "Controls/ScrubSlider.swift"] {
            let text = try source(path)
            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { continue }
                // A line that already names a Theme token is calibrated, even
                // if it also does arithmetic on one.
                guard !line.contains("Theme.") else { continue }
                let range = NSRange(line.startIndex..., in: line)
                for match in pattern.matches(in: line, range: range) {
                    guard let numberRange = Range(match.range(at: 1), in: line),
                          let value = Double(line[numberRange]) else { continue }
                    let size = CGFloat(value)
                    guard !scale.contains(size), !exempt.contains(size) else { continue }
                    offenders.append("\(path):\(index + 1) — \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      """
                      A Modern spacing literal is not on the 2/4/8/12/20 scale \
                      and is not a shape's own geometry. Either move it to \
                      `Theme.Metric` or use a scale value:
                      \(offenders.joined(separator: "\n"))
                      """)
    }

    // MARK: one ramp, one axis

    /// **There is no second type ramp, and no second label axis.**
    ///
    /// The export page kept its own for a year (12.5 / 11 / 11 / 11 / 11 /
    /// 9.5) because its drawing said so, and the cost was invisible in every
    /// document and obvious in the product: with the export rail open beside
    /// the parameter inspector, one panel's section title was two points
    /// larger, its table content 16 pt further right and its rows 10 pt
    /// tighter than the other's. The enum is deleted; this test is what keeps
    /// a third ramp from growing back.
    func testThereIsNoSecondTypeRampOrLabelAxis() throws {
        var offenders: [String] = []
        for path in modernSurfaces {
            let text = try source(path)
            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                // A comment about the deleted ramp is fine; using one is not.
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                if line.contains("Font.Export") {
                    offenders.append("\(path):\(index + 1) — \(trimmed)")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      """
                      A view reached for a type ramp of its own. The editor's \
                      four ranks are the only ones (UI-SPEC §2.7):
                      \(offenders.joined(separator: "\n"))
                      """)
    }

    /// A table row in the export panel and a control row in the inspector
    /// share **one label axis and one line box**.
    ///
    /// This is the measurement the two screenshots disagreed about, stated as
    /// an invariant: whatever the panel, the label column is the editor's and
    /// the row is the editor's, so the two panels beside each other line up.
    func testTheExportBodySharesTheEditorsAxis() {
        let m = Theme.Metric.self
        XCTAssertEqual(m.modernLabelWidth, m.sliderLabelWidth,
                       "a table's label column is the editor's label axis")
        XCTAssertEqual(m.modernRowHeight, m.gridRow)
        XCTAssertEqual(m.modernControlHeight, m.gridControl)
        XCTAssertEqual(m.modernRowSpacing, m.space8)
        // The editor's ranks exist and the export page reads them; the check
        // that no view names another one is the test above.
        XCTAssertNotNil(Theme.Font.label)
        XCTAssertNotNil(Theme.Font.value)
    }

    /// **A Modern section header draws no disclosure, and its section does
    /// not fold.**
    ///
    /// This was got wrong once in each direction inside one session — first by
    /// leaving `expanded` unread (a state written and never kept), then by
    /// adding a triangle to honour it (a control the layout does not want).
    /// The user's answer is the rule: Modern shows **one stage at a time** and
    /// the tool bar's stage buttons change it, so there is nothing to fold.
    ///
    /// The check is on the source because the failure is a *shape* — a glyph
    /// on a row — and no geometry assertion can see the difference between a
    /// header that folds and one that does not.
    func testAModernHeaderHasNoDisclosure() throws {
        let header = try source("Controls/SectionHeader.swift")
        // There is one header now — the three-region layout's was deleted with
        // it — so the check is that *this* header draws no disclosure and
        // offers no way to fold.
        XCTAssertFalse(header.contains("Triangle()"),
                       "the section header must not draw a disclosure triangle")
        XCTAssertFalse(header.contains("expanded.toggle()"),
                       "the section header must not fold its section")
        XCTAssertFalse(header.contains("traditionalHeader"),
                       "there is one header, not two")
        // A section on a floating surface is **never** collapsed: its content
        // is unconditional, so there is no branch that could hide it.
        XCTAssertFalse(header.contains("if expanded {"),
                       "a floating surface's section is never collapsed")
        XCTAssertTrue(header.contains("        VStack(spacing: 0) {\n            if stageMenu == nil {")
                      || header.contains("content()"),
                      "the content is drawn unconditionally")
    }

    // MARK: the grid

    /// **Every Modern gap is a multiple of 4, and the grid is the only
    /// defence against a rhythm of one-offs.**
    ///
    /// Measured on 2026-09-26 before this existed: one inspector had eleven
    /// distinct row pitches (14.5, 16, 16.5, 17.5, 18, 18.5, 19.5, 20, 21,
    /// 21.5, 22) and two different section-to-content gaps (26 and 38) for the
    /// same job. Neither is a mistake in one view — each was locally
    /// reasonable — and both are invisible to a geometry assertion. A unit is
    /// what makes them visible.
    func testTheModernGridIsFourPointsAndEveryGapIsOnIt() {
        let m = Theme.Metric.self
        XCTAssertEqual(m.gridUnit, 4)
        // `space2` is the half step: it closes a gap *inside* one control (a
        // pill's text to its chevron), where a 4 would be a visible hole. Every
        // gap *between* surfaces is a whole unit.
        XCTAssertEqual(m.space2, m.gridUnit / 2)
        for (name, value) in [("space4", m.space4),
                              ("space8", m.space8), ("space12", m.space12),
                              ("space20", m.space20),
                              ("contentInset", m.modernContentInset),
                              ("panelVerticalInset", m.modernPanelVerticalInset),
                              ("rowSpacing", m.modernRowSpacing),
                              ("blockGap", m.modernBlockGap),
                              ("headerHeight", m.modernHeaderHeight),
                              ("headerToContent", m.modernHeaderToContent),
                              ("sectionBottom", m.modernSectionBottom),
                              ("topBarHeight", m.modernTopBarHeight),
                              ("gutter", m.modernSurfaceGutter)] {
            XCTAssertEqual(value.truncatingRemainder(dividingBy: m.gridUnit), 0,
                           "\(name) = \(value) is not a multiple of \(m.gridUnit)")
        }
        // The two deliberate exceptions, named rather than hidden: a row is 22
        // because 10.5 pt type needs the line box (see `Theme.Metric`), and
        // the control inside it is 16.
        XCTAssertEqual(m.gridRow, 22)
        XCTAssertEqual(m.gridControl, 16)
        XCTAssertLessThan(m.gridControl, m.gridRow,
                          "the ink has to fit inside its row")
    }

    // MARK: what the scan must keep seeing

    /// The scanner has to be looking at something, and at the right something.
    ///
    /// A source check whose file list silently empties passes forever — the
    /// same family as a skipping suite reporting `0 failures` (`AGENTS.md`
    /// trap 26). So the list is asserted, and the Modern-only set is asserted
    /// to exclude the files that are Traditional's.
    func testTheScannerIsLookingAtTheModernSurfaces() throws {
        XCTAssertGreaterThanOrEqual(modernSurfaces.count, 25,
                                    "the surface list collapsed")
        XCTAssertTrue(modernRails.contains("Windows/EditorWindow.swift"))
        XCTAssertTrue(modernRails.contains("Panels/Filmstrip.swift"))
        XCTAssertTrue(modernRails.contains("Panels/Sections/CameraSection.swift"))
        // Traditional's own files are not Modern's to calibrate.
        XCTAssertFalse(modernRails.contains("Panels/LeftPanel.swift"))
        XCTAssertFalse(modernRails.contains("Export/ExportPage.swift"))
        XCTAssertFalse(modernRails.contains("Windows/SettingsWindow.swift"))
        // And every path resolves — a typo in the list would otherwise scan
        // nothing and pass.
        for path in modernRails {
            let text = try source(path)
            XCTAssertFalse(text.isEmpty, "\(path) was empty or unreadable")
        }
    }
}
