//  FormatPicker.swift — the menu pill, and the two rows built on it.
//
//  Three shapes come out of the 2026-09-17 drawing and they are not
//  interchangeable:
//
//    * `PillMenu` **filling** the row after its label — AE Method, whose pill
//      runs from the label column to the row's trailing edge (the drawing:
//      86.35 → 235.6 on a 254 pt rail).
//    * `PillMenu` at a **fixed** width, right-aligned — Film Type and Side,
//      drawn 107 wide with the rest of the row left empty.
//    * `UnitField`, a number field and a unit pill side by side — Side
//      Length, whose field is `rx 8.5` (not a capsule) and whose unit pill is.
//
//  Both rules are in the drawing and both are kept, so `fill` is a parameter
//  and not a judgement made per caller.

import SwiftUI

struct PillMenu<T: Hashable>: View {
    let label: String
    let options: [T]
    let title: (T) -> String
    @Binding var selection: T
    /// The label column. The editor's rails take the shared 84 — the drawing
    /// asks for 68.35 and macOS sets the same strings wider, so the column is
    /// `Theme.Metric.sliderLabelWidth`; the export page's is 68.5, its own
    /// drawing, and every row on a page has to pass the same one or the pills
    /// stop lining up. (This comment said 74 for a release after the token
    /// moved to 84 — the same half-fixed pair the audit found in `Theme`.)
    var labelWidth: CGFloat = Theme.Metric.sliderLabelWidth
    /// The face both the label and the value are drawn in.
    var font: Font = Theme.Font.label
    /// Whether the pill takes the whole row after the label, or a fixed
    /// `pickerWidth` at the trailing edge. See the note at the top.
    var fill: Bool = true
    /// A pill on a **rail** is ground-coloured; a pill inside a **well** —
    /// the export page, Settings — has to be darker than the well it sits on.
    var plate: Color = Theme.pill
    var enabled: Bool = true
    var reason: String = ""
    /// An extra mark after the value: the `CINE` pill, on a cine film type.
    var trailingBadge: (T) -> Bool = { _ in false }

    @State private var hovered = false

    /// **Always.** A floating panel's controls share one left edge and one
    /// right edge, so a pill that stopped two thirds of the way across read
    /// as an unfinished row — which is what the user saw on the Film panel.
    private var fillsControlColumn: Bool { true }

    var body: some View {
        HStack(spacing: 0) {
            Text(label).font(font).foregroundStyle(Theme.Ink.secondary)
                .lineLimit(1)
                .frame(width: labelWidth, alignment: .leading)
            if !fillsControlColumn { Spacer(minLength: 0) }
            Menu {
                ForEach(options, id: \.self) { o in
                    Button { selection = o } label: {
                        if o == selection { Label(title(o), systemImage: "checkmark") } else { Text(title(o)) }
                    }
                }
            } label: {
                HStack(spacing: 0) {
                    // **The pill's own inset scale**, which is not the panel's:
                    // a capsule 13.9 pt tall holding 10.5 pt text has 1.7 pt of
                    // real air, so its text sits 10 in and its chevron 9 off
                    // the trailing edge. The two menu rows and the unit pill
                    // used to disagree on all four numbers (10/9/5/4 against
                    // 6/2/5); they are these now, for both shapes.
                    Text(title(selection)).font(font).foregroundStyle(Theme.text).lineLimit(1)
                        .padding(.leading, PillGeometry.textInset)
                    if trailingBadge(selection) {
                        CinePill().padding(.leading, Theme.Metric.space4)
                    }
                    Spacer(minLength: Theme.Metric.space2)
                    // The drawing's chevron is the **same hollow triangle**
                    // the section headers disclose with, not SF Symbols'
                    // double chevron. One mark, two places, one meaning:
                    // "there is more under this".
                    Triangle()
                        .stroke(Theme.text, style: StrokeStyle(lineWidth: 1, lineJoin: .round))
                        .frame(width: PillGeometry.chevron.width, height: PillGeometry.chevron.height)
                        .padding(.trailing, PillGeometry.chevronInset)
                }
                .frame(height: Theme.Metric.gridControl)
                // `width`, not `maxWidth`. A maximum with `fixedSize` under
                // it resolves to the *intrinsic* width, so every non-filling
                // pill came out as wide as its own word — Film Type 42 pt,
                // Side 44 pt, the unit pill narrower again — and the trailing
                // column had a different left edge on every row. The drawing
                // gives them one width and one left edge; this is that.
                .frame(width: fillsControlColumn ? nil : Theme.Metric.pickerWidth)
                .frame(maxWidth: fillsControlColumn ? .infinity : nil)
                .pillSurface(base: plate, hovered: hovered && enabled)
                .contentShape(Capsule())
                .onHover { hovered = $0 }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: false, vertical: false)
        }
        // **Top-aligned in the row box.** Every control row is `gridRow`
        // tall and its content starts at the box's top (option A, 2026-09-26),
        // so a section's first row sits at the same height whether that row
        // is a pill, a slider, a checkbox or a bare number. Centred content
        // made a pill's first ink land 3 pt below a text row's, which read as
        // two different header-to-content gaps in the same panel.
        .frame(height: Theme.Metric.gridRow, alignment: .top)
        .rowEnabled(enabled, because: reason)
    }
}

/// A menu pill's own geometry: one inset pair and one chevron, shared by both
/// pill shapes and by `UnitField`, so the two capsules in a row line up.
///
/// A file-level namespace rather than `PillMenu`'s own statics: `PillMenu` is
/// generic, and Swift does not allow a static stored property in a generic
/// type.
enum PillGeometry {
    static let textInset: CGFloat = 10
    static let chevronInset: CGFloat = 9
    static let chevron = CGSize(width: 8, height: 5)
}

/// Side Length: a number field and a unit pill, right-aligned, and greyed
/// unless the film type is Custom.
///
/// The drawing's two shapes are different on purpose — the field is `rx 8.5`
/// against the unit pill's `rx 13.9` — because one is typed into and the
/// other is chosen from. The field is 50 pt and the unit 38.
struct UnitField: View {
    let label: String
    @Binding var value: Double
    @Binding var unit: SideUnit
    var enabled: Bool
    var reason: String = ""

    @State private var editing = false
    @State private var text = ""
    @FocusState private var focused: Bool

    private var shown: String {
        String(format: "%.\(unit.decimals)f", unit.fromMM(value))
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(label).font(Theme.Font.label).foregroundStyle(Theme.Ink.secondary)
                .lineLimit(1)
                .frame(width: Theme.Metric.sliderLabelWidth, alignment: .leading)
            // **The field fills the column and the unit keeps its width**, so
            // this row's right edge is the same edge as the two menu pills
            // above it.
            //
            // It was the opposite — a fixed `fieldWidth` field and a trailing
            // gap — on the argument that "0.945 stretched across 200 pt is a
            // text box with three characters in it". That is true of a field
            // standing alone and false of one in a table: the user's read of
            // the Film panel was that this row was the only one that did not
            // line up. A single column has one right edge.
            field
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Theme.Metric.gridControl)
            Spacer().frame(width: Theme.Metric.space4)
            Menu {
                ForEach(SideUnit.allCases) { u in
                    Button { unit = u } label: {
                        if u == unit { Label(u.title, systemImage: "checkmark") } else { Text(u.title) }
                    }
                }
            } label: {
                HStack(spacing: 0) {
                    // The drawing's unit pill is 38.3 pt wide and has to hold
                    // "mm" *and* a chevron, so its padding is tighter than
                    // every other pill's. At the menu pill's 10/9 it had 13 pt
                    // for the word and showed "…".
                    Text(unit.title).font(Theme.Font.value).foregroundStyle(Theme.Ink.tertiary)
                        .fixedSize()
                        .padding(.leading, Theme.Metric.space8)
                    Spacer(minLength: Theme.Metric.space2)
                    Triangle()
                        .stroke(Theme.text, style: StrokeStyle(lineWidth: 1, lineJoin: .round))
                        .frame(width: 7, height: 4.5)
                        .padding(.trailing, Theme.Metric.space4)
                }
                .frame(width: Theme.Metric.unitWidth, height: Theme.Metric.gridControl)
                .background(Theme.pill, in: Capsule())
                .contentShape(Capsule())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        }
        .frame(height: Theme.Metric.gridRow, alignment: .top)
        // The **unit** stays live when the length does not: a 135 frame is
        // still 0.945 in, and reading it in inches is not editing it. Only
        // the field takes the greying.
        .rowEnabled(true)
    }

    private var field: some View {
        Group {
            if editing && enabled {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.value)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.text)
                    .focused($focused)
                    .onSubmit { commit() }
                    .onChange(of: focused) { _, f in if !f { commit() } }
            } else {
                Text(shown)
                    .font(Theme.Font.value)
                    .foregroundStyle(Theme.text)
                    .contentShape(Rectangle())
                    .onTapGesture { text = shown; editing = true; focused = true }
            }
        }
        .lineLimit(1)
        .rowEnabled(enabled, because: reason)
    }

    private func commit() {
        if let v = Double(text.replacingOccurrences(of: ",", with: ".")) { value = unit.toMM(v) }
        editing = false
    }
}

/// The orange `CINE` mark — `.st2` in the drawing: `fill: none; stroke:
/// #eca650; stroke-width: 2px`, so an outline in the accent rather than a
/// plate. It follows a cinema film stock in the list and a cine format in the
/// Film Type pill.
struct CinePill: View {
    var body: some View {
        Text("CINE")
            .font(Theme.Font.cine)
            .foregroundStyle(Theme.accent)
            .frame(width: Theme.Metric.cinePill.width, height: Theme.Metric.cinePill.height)
            .overlay(Capsule().stroke(Theme.accent, lineWidth: 1))
    }
}
