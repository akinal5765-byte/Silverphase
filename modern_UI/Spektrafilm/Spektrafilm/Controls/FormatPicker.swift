// FormatPicker.swift — Photos-style full-width menu bars and unit fields.
// Menus share their visible height, insets, radius and row gap with sliders.
// Legacy width hints remain in the initializer for caller compatibility.

import SwiftUI

private struct EmbeddedParameterRowKey: EnvironmentKey { static let defaultValue = false }
private struct ParameterRowLabelKey: EnvironmentKey { static let defaultValue: String? = nil }
private struct ParameterRowLabelWidthKey: EnvironmentKey { static let defaultValue: CGFloat? = nil }

extension EnvironmentValues {
    var parameterRowLabel: String? {
        get { self[ParameterRowLabelKey.self] }
        set { self[ParameterRowLabelKey.self] = newValue }
    }
    var parameterRowLabelWidth: CGFloat? {
        get { self[ParameterRowLabelWidthKey.self] }
        set { self[ParameterRowLabelWidthKey.self] = newValue }
    }
    var embeddedParameterRow: Bool {
        get { self[EmbeddedParameterRowKey.self] }
        set { self[EmbeddedParameterRowKey.self] = newValue }
    }
}

/// One menu face for the inspector, export recipes and custom export menus.
struct ParameterMenuFace<Badge: View>: View {
    var label = ""
    let title: String
    var labelWidth: CGFloat = Theme.Metric.sliderLabelWidth
    var font: Font = Theme.Font.label
    var plate: Color = Theme.pill
    var dimmed = false
    @ViewBuilder var badge: () -> Badge
    @Environment(\.embeddedParameterRow) private var embedded
    @Environment(\.parameterRowLabel) private var rowLabel
    @Environment(\.parameterRowLabelWidth) private var rowWidth
    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Metric.parameterRowInset) {
            if !(rowLabel ?? label).isEmpty {
                Text(rowLabel ?? label).font(font).foregroundStyle(Theme.Ink.secondary)
                    .lineLimit(1)
                    .frame(width: max(0, rowWidth ?? labelWidth), alignment: .leading)
            }
            Text(title).font(font).foregroundStyle(dimmed ? Theme.dim : Theme.text)
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            badge()
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: Theme.Metric.parameterMenuChevron, weight: .semibold))
                .foregroundStyle(dimmed ? Theme.dim : Theme.text)
        }
        .padding(.horizontal, Theme.Metric.parameterRowInset)
        .frame(maxWidth: .infinity)
        .frame(height: Theme.Metric.parameterRowHeight)
        .background(RoundedRectangle(cornerRadius: Theme.Metric.parameterRowRadius)
            .fill(embedded && !hovered ? Color.clear : plate.opacity(hovered ? 1 : 0.8)))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Metric.parameterRowRadius))
        .onHover { hovered = $0 }
    }
}

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
    /// Legacy layout hint; desktop menu bars now always fill their row.
    var fill: Bool = true
    /// A pill on a **rail** is ground-coloured; a pill inside a **well** —
    /// the export page, Settings — has to be darker than the well it sits on.
    var plate: Color = Theme.pill
    var enabled: Bool = true
    var reason: String = ""
    /// An extra mark after the value: the `CINE` pill, on a cine film type.
    var trailingBadge: (T) -> Bool = { _ in false }

    @Environment(\.embeddedParameterRow) private var embedded
    @Environment(\.parameterRowLabel) private var rowLabel

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button { selection = option } label: {
                    if option == selection {
                        Label(title(option), systemImage: "checkmark")
                    } else {
                        Text(title(option))
                    }
                }
            }
        } label: {
            ParameterMenuFace(label: label, title: title(selection), labelWidth: labelWidth, font: font, plate: plate) {
                if trailingBadge(selection) { CinePill() }
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .disabled(!enabled)
        .accessibilityLabel((rowLabel ?? label).isEmpty ? title(selection) : (rowLabel ?? label))
        .accessibilityValue(title(selection))
        .padding(.bottom, embedded ? 0 : Theme.Metric.parameterRowGap)
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
                .frame(height: Theme.Metric.parameterRowHeight)
                .controlSurface(radius: Theme.Metric.parameterRowRadius)
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
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: Theme.Metric.parameterMenuChevron, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .padding(.trailing, Theme.Metric.space4)
                }
                .frame(height: Theme.Metric.parameterRowHeight)
                .frame(minWidth: Theme.Metric.unitWidth)
                .controlSurface(radius: Theme.Metric.parameterRowRadius)
                .contentShape(RoundedRectangle(cornerRadius: Theme.Metric.parameterRowRadius))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        }
        .frame(height: Theme.Metric.parameterRowHeight)
        .padding(.bottom, Theme.Metric.parameterRowGap)
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
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, Theme.Metric.parameterRowInset)
                    .focused($focused)
                    .onSubmit { commit() }
                    .onChange(of: focused) { _, f in if !f { commit() } }
            } else {
                Text(shown)
                    .font(Theme.Font.value)
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, Theme.Metric.parameterRowInset)
                    .frame(maxHeight: .infinity)
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
