//  ScrubSlider.swift — desktop parameter bars with hover ticks and animated values.
//
//  Built once and used everywhere. Drag anywhere on the track, ⌥ for ×0.25
//  sensitivity, ⇧ snaps to `snap`, double-click resets to `zero`, and the
//  value column is an editable field. `onCommit` fires on release; continuous
//  updates go through the binding while dragging.

import SwiftUI

/// The numbers a slider is drawn with. A default-constructed one is the
/// editor's rails, which is what every caller but the export page wants; the
/// export page's drawing has a narrower label column, a thinner track and a
/// shorter row. The knob is not here because both drawings agree on it.
private struct RulerInteractionKey: EnvironmentKey {
    static let defaultValue: (@MainActor (Bool) -> Void)? = nil
}

extension EnvironmentValues {
    var rulerInteraction: (@MainActor (Bool) -> Void)? {
        get { self[RulerInteractionKey.self] }
        set { self[RulerInteractionKey.self] = newValue }
    }
}

private struct RailSliderMetricsKey: EnvironmentKey { static let defaultValue = SliderMetrics() }

extension EnvironmentValues {
    /// The slider grid of the rail a slider sits on. The Parameters rail sets
    /// `.parameters`; everything else keeps the default.
    var railSliderMetrics: SliderMetrics {
        get { self[RailSliderMetricsKey.self] }
        set { self[RailSliderMetricsKey.self] = newValue }
    }
}

struct SliderMetrics {
    /// The rails' default: an 84 pt label column at 10.5 pt. **Every rail
    /// uses it, Camera included.** v3 drew Camera a second way — 9 pt labels
    /// in a 70 pt column — and that second density was a typographic
    /// inconsistency inside one rail, not a hierarchy the section can carry:
    /// 测光模式 sat 1.5 pt shorter than the 胶片 label above it for no reason
    /// a reader can see. UI-SPEC 字体一节 records the unification; the drawing's
    /// x 86.35 for Camera's controls is history.
    static let rail = SliderMetrics()

    var labelWidth: CGFloat = Theme.Metric.sliderLabelWidth
    var valueWidth: CGFloat = Theme.Metric.sliderValueWidth
    var rowHeight: CGFloat = Theme.Metric.gridRow
    var trackHeight: CGFloat = Theme.Metric.trackHeight
    var labelFont: Font = Theme.Font.label
    var valueFont: Font = Theme.Font.value
    /// Whether the value is drawn **in a pill** (the 2026-09-17 drawing: a
    /// `.st13` rounded rectangle at `rx 8.5`, every slider) or as bare text
    /// (the export page's drawing, which has one slider and no pill).
    var valueInPill: Bool = true
}

struct ScrubSlider: View {
    let label: String
    var sublabel: String? = nil
    /// A second label line that is a *view* rather than text — the white
    /// balance rows put their "As Shot" checkbox there. Alternative to
    /// `sublabel`, and it wins when both are set.
    var sublabelView: AnyView? = nil
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// The value field can accept legacy values beyond the useful drag range.
    /// Omitted for ordinary sliders, whose text and track have the same bounds.
    var entryRange: ClosedRange<Double>? = nil
    var zero: Double = 0
    var snap: Double = 0.5
    var format: (Double) -> String = { String(format: "%.1f", $0) }
    var parse: (String) -> Double? = { Double($0.replacingOccurrences(of: ",", with: ".")) }
    var trackGradient: [Color]? = nil
    /// The part of the range the value can rest on, when that is not all of
    /// it (Scene Placement's pull-backs the Fit takes). Drawn as a band around
    /// the track, so where the knob can go is visible before anyone drags:
    /// the band is the usable part, bare track is not. 1.3.1 drew the band
    /// on the refused part, and it read the other way round.
    var usable: [ClosedRange<Double>] = []
    var disabled = false
    /// See `SliderMetrics`. Nil takes the rail's (`\.railSliderMetrics`), which
    /// is how every slider on the Parameters rail lands on one grid without
    /// each call site having to say so.
    var metrics: SliderMetrics? = nil
    var ruler = true
    var resolution = 0.01
    var onInteraction: ((Bool) -> Void)? = nil
    @Environment(\.rulerInteraction) private var inheritedInteraction
    var onCommit: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.railSliderMetrics) private var railMetrics
    private var m: SliderMetrics { metrics ?? railMetrics }

    @State private var dragStart: Double?
    @State private var editing = false
    @State private var text = ""
    @State private var hovered = false
    @FocusState private var focused: Bool

    private var hasSecondLine: Bool { sublabelView != nil || sublabel != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if ruler { photosRow } else {
            HStack(spacing: 0) {
                Text(label)
                    .font(m.labelFont)
                    .foregroundStyle(Theme.Ink.secondary)
                    // A column, not a cage (2026-09-28): the label is at least
                    // the column wide and grows past it rather than truncate.
                    .fixedSize()
                    .padding(.trailing, 6)
                    .frame(minWidth: m.labelWidth, alignment: .leading)
                track
                    .padding(.trailing, Theme.Metric.sliderValueGap)
                valueField
                    .frame(width: m.valueWidth)
            }
            // **The ink band.** Every row of every table puts its control's
            // ink in a `gridControl`-tall band at the top of a `gridRow`-tall
            // box, so two rows read as the same distance apart whatever kind
            // of control they hold: a pill's fill is 16 pt, a slider's knob 9,
            // a readout's text 10 — centred in the same 16 the *visible* gap
            // below each row is the same. Top-aligning the ink to the row box
            // instead (option A on its own) left a pill 3 pt closer to the row
            // below than a text line.
            .frame(height: Theme.Metric.gridControl)
            .frame(height: m.rowHeight, alignment: .top)
            }
            // The second line is the drawing's own: "As Shot" and its box sit
            // **under the label**, not beside the value, so they line up with
            // the label column rather than floating in the middle of the row.
            if let sublabelView {
                sublabelView.frame(height: Theme.Metric.subRowHeight, alignment: .leading)
            } else if let sublabel {
                // Wraps, never widens the row (1.2.2). This line carries
                // messages as well as units — Scene Placement's refusal is a
                // sentence — and a `.fixedSize()` sentence made the whole
                // Parameters rail wider than the window, pushing every value
                // off its right edge (reported from Xiaohongshu, 2026-09-30).
                Text(sublabel).font(Theme.Font.sublabel).foregroundStyle(Theme.Ink.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: Theme.Metric.subRowHeight, alignment: .leading)
            }
        }
        .rowEnabled(!disabled)
    }

    // Desktop bar: labels and numbers share a single shallow surface.
    // Ticks are discoverable on hover; the baseline remains visible at rest.
    private var photosRow: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Metric.parameterRowRadius).fill(Theme.Ink.secondary.opacity(0.13))
                if let gradient = trackGradient {
                    RoundedRectangle(cornerRadius: Theme.Metric.parameterRowRadius)
                        .fill(LinearGradient(colors: gradient, startPoint: .leading, endPoint: .trailing))
                        .opacity(0.3)
                }
                Canvas { context, size in
                    let baseline = zeroFraction * size.width
                    let position = fraction * size.width
                    let active = hovered || dragStart != nil
                    if dragStart != nil {
                        let fill = CGRect(x: min(baseline, position), y: 0,
                                          width: abs(position - baseline), height: size.height)
                        context.fill(Path(fill), with: .color(Theme.accent.opacity(0.24)))
                    }
                    let pointer = CGRect(x: min(size.width - 2, max(0, position - 1.5)), y: 0, width: 3, height: size.height)
                    context.fill(Path(pointer), with: .color(active ? Theme.accent : Theme.Ink.tertiary.opacity(0.6)))
                    if active {
                        for tick in ToolRulerScale.ticks(in: range, range: range, step: rulerStep, anchor: zero, keyMarks: []) {
                            let x = (tick.value - range.lowerBound) / (range.upperBound - range.lowerBound) * size.width
                            context.fill(Path(CGRect(x: x, y: 0, width: 0.6, height: tick.major ? 6 : 3)),
                                         with: .color(Theme.Ink.secondary.opacity(tick.major ? 0.7 : 0.4)))
                        }
                    }
                }
                .allowsHitTesting(false)
                HStack {
                    Text(label).font(m.labelFont).foregroundStyle(Theme.Ink.secondary)
                        .lineLimit(1).allowsHitTesting(false)
                    Spacer(minLength: 6)
                    valueField.frame(width: m.valueWidth + 12)
                }.padding(.horizontal, Theme.Metric.parameterRowInset)
                HStack(spacing: 0) {
                    DesktopRulerInput(onChanged: { rulerDragged($0, width: geo.size.width) },
                                      onEnded: rulerEnded, onReset: resetRuler, onStep: stepRuler,
                                      onEditValue: beginValueEntry, valueEntryWidth: valueEntryWidth,
                                      value: value, step: rulerStep, readValue: { value }, inputEnabled: !disabled)
                    if editing {
                        Color.clear.frame(width: valueEntryWidth).allowsHitTesting(false)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.parameterRowRadius))
            .onHover { hovered = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
            .accessibilityValue(format(value))
            .accessibilityAdjustableAction { stepRuler($0 == .increment) }
            .accessibilityAction(named: Text(T("Reset", "重置"))) { resetRuler() }
            .accessibilityAction(named: Text(T("Edit Value", "输入数值"))) { beginValueEntry() }
            .onDisappear { rulerEnded() }
        }
        .frame(height: max(Theme.Metric.parameterRowHeight, m.rowHeight))
        .padding(.bottom, Theme.Metric.parameterRowGap)
    }

    private var fraction: CGFloat {
        CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)).clamped(to: 0...1)
    }
    private var zeroFraction: CGFloat {
        CGFloat((zero - range.lowerBound) / (range.upperBound - range.lowerBound)).clamped(to: 0...1)
    }

    private var track: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let knobW = Theme.Metric.knobSize.width
            let knobH = Theme.Metric.knobSize.height
            let span = max(w - knobW, 1)
            let x = fraction * span + knobW / 2
            let live = hovered || dragStart != nil
            ZStack(alignment: .leading) {
                Group {
                    if let g = trackGradient {
                        Capsule().fill(LinearGradient(colors: g, startPoint: .leading, endPoint: .trailing))
                    } else {
                        // **Two tones, one track** (UI-SPEC §2.5): behind the
                        // knob is a faint rule, in front of it a lightened
                        // one. Deliberately *not* the accent — the accent is
                        // the one "look here" in the palette, and a track
                        // that is always tinted spends it on a fact nobody
                        // needs told (that the slider is a slider).
                        //
                        // Where the lightened part *starts* is the zero tick
                        // when zero is inside the range, and the track's low
                        // end only when it is not. Filling from the low end
                        // unconditionally made every bipolar control (Film
                        // Exposure, Temp, Tint) read as a progress bar that
                        // was 60 % done at rest — caught in a capture.
                        let anchor = (zeroFraction > 0.001 && zeroFraction < 0.999)
                                     ? zeroFraction : 0
                        let lo = min(anchor, fraction)
                        let hi = max(anchor, fraction)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.trackRest)
                            Capsule().fill(Theme.trackActive)
                                .frame(width: (hi - lo) * span)
                                .offset(x: lo * span)
                        }
                        .opacity(live ? 1 : 0.88)
                    }
                }
                .frame(height: m.trackHeight)
                .padding(.horizontal, knobW / 2)
                ForEach(Array(usable.enumerated()), id: \.offset) { _, usable in
                    let span = range.upperBound - range.lowerBound
                    let lo = CGFloat((max(usable.lowerBound, range.lowerBound) - range.lowerBound) / span)
                    let hi = CGFloat((min(usable.upperBound, range.upperBound) - range.lowerBound) / span)
                    Capsule().fill(Theme.Ink.tertiary.opacity(0.35))
                        .frame(width: max((hi - lo) * (w - knobW), 3), height: 5)
                        .offset(x: lo * (w - knobW) + knobW / 2)
                        .allowsHitTesting(false)
                }
                // Zero tick, only when zero is not at an end.
                if zeroFraction > 0.001 && zeroFraction < 0.999 && abs(fraction - zeroFraction) > 0.02 {
                    Rectangle().fill(Theme.text.opacity(0.55)).frame(width: 1, height: 6)
                        .offset(x: zeroFraction * span + knobW / 2 - 0.5)
                }
                // The knob divides the two tones, so it has to be findable:
                // 9 pt round, a 1 px light edge and one shadow. That shadow is
                // the only one on a rail — UI-SPEC §2.2 puts elevation in the
                // stroke, and this is the single element that earns more.
                RoundedRectangle(cornerRadius: Theme.Metric.knobRadius, style: .continuous)
                    .fill(Theme.knob)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Metric.knobRadius, style: .continuous)
                            .strokeBorder(Theme.knobEdge, lineWidth: 1)
                    }
                    .shadow(color: Theme.knobShadow, radius: 1, y: 1)
                    .frame(width: knobW, height: knobH)
                    .offset(x: x - knobW / 2)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let mods = NSEvent.modifierFlags
                        let span = range.upperBound - range.lowerBound
                        if dragStart == nil {
                            dragStart = value
                            // Jump to the click point on a fresh press.
                            let f = ((g.startLocation.x - knobW / 2) / max(w - knobW, 1)).clamped(to: 0...1)
                            let target = range.lowerBound + Double(f) * span
                            if abs(target - value) > span * 0.03 { dragStart = target }
                        }
                        let sens: Double = mods.contains(.option) ? 0.25 : 1
                        var v = (dragStart ?? value) + Double(g.translation.width / max(w - knobW, 1)) * span * sens
                        if mods.contains(.shift) { v = (v / snap).rounded() * snap }
                        value = v.clamped(to: range)
                    }
                    .onEnded { _ in dragStart = nil; onCommit() }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { value = zero; onCommit() })
        }
        .frame(height: m.rowHeight)
    }

    private var rulerStep: Double { snap == 0.5 ? ToolRulerScale.step(in: range) : snap }

    private func interactionChanged(_ active: Bool) {
        if let onInteraction { onInteraction(active) } else { inheritedInteraction?(active) }
    }

    private func rulerDragged(_ translation: Double, width: CGFloat? = nil) {
        if dragStart == nil { dragStart = value; interactionChanged(true) }
        let sensitivity = NSEvent.modifierFlags.contains(.option) ? 0.25 : 1.0
        let delta = width.map { translation / max(Double($0), 1) * (range.upperBound - range.lowerBound) }
            ?? (-translation / 12 * rulerStep)
        var proposed = (dragStart ?? value) + delta * sensitivity
        if NSEvent.modifierFlags.contains(.shift) { proposed = (proposed / snap).rounded() * snap }
        let next = ToolRulerScale.quantized(proposed, in: range, resolution: resolution)
        value = next
    }

    private func rulerEnded() {
        guard dragStart != nil else { return }
        dragStart = nil
        interactionChanged(false); onCommit()
    }

    private func resetRuler() {
        rulerEnded()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { value = zero }
        onCommit()
    }

    private func stepRuler(_ forward: Bool) {
        let increment = NSEvent.modifierFlags.contains(.shift) ? snap : resolution
        value = ToolRulerScale.advanced(value, forward: forward, range: range, resolution: increment)
        onCommit()
    }

    private var valueEntryWidth: CGFloat { m.valueWidth + 12 + Theme.Metric.parameterRowInset }

    private func beginValueEntry() {
        guard !disabled, !editing else { return }
        text = format(value)
        editing = true
        focused = true
    }

    private var valueField: some View {
        // Keep the readout alive under the editor so committing a typed value
        // can roll from the previous number rather than insert a new Text.
        ZStack {
                Text(format(value))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: (value * 1000).rounded()))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: format(value))
                    .font(m.valueFont)
                    .foregroundStyle(Theme.text)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: beginValueEntry)
                    .opacity(editing ? 0 : 1)
                    .allowsHitTesting(!ruler && !editing)
            if editing {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(m.valueFont)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.text)
                    .focused($focused)
                    .onSubmit { commitText() }
                    .onChange(of: focused) { _, f in if !f { commitText() } }
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .frame(height: m.valueInPill ? Theme.Metric.gridControl : nil)
        // The value box is the same material as every pill and field; Camera's
        // rows show the number as plain text and so opt out of the surface.
        .modifier(ValueBoxSurface(inPill: m.valueInPill && !ruler, hovered: hovered, pressed: editing))
    }

    private func commitText() {
        guard editing else { return }
        if let v = parse(text), v.isFinite {
            value = v.clamped(to: entryRange ?? range)
            onCommit()
        }
        editing = false
    }
}

/// The slider's value box, in the shared control surface — but only where the
/// metrics ask for a pill.
///
/// It is a modifier rather than an inline `if` because a slider's two
/// densities disagree about this: the rail's rows box the number, Camera's
/// rows print it plain. Both still hover and both still show the pressed
/// stroke while the field is being typed in.
private struct ValueBoxSurface: ViewModifier {
    let inPill: Bool
    let hovered: Bool
    let pressed: Bool

    func body(content: Content) -> some View {
        if inPill {
            content.controlSurface(hovered: hovered, pressed: pressed)
        } else {
            content
        }
    }
}

/// The checkbox: a small square with a 1 pt border, filled with the accent
/// when it is on.
///
/// The reference drawing's 5 pt square inside a 16 pt target was not readable
/// or reliably clickable on a laptop. Both values now come from product
/// accessibility tokens: 10 pt of visible state inside a 28 pt target.
struct CheckBox: View {
    @Binding var isOn: Bool
    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Metric.checkboxRadius, style: .continuous)
                    .fill(isOn ? Theme.accent : Theme.checkboxFill)
                RoundedRectangle(cornerRadius: Theme.Metric.checkboxRadius, style: .continuous)
                    .strokeBorder(Theme.controlStroke, lineWidth: Theme.Metric.rule)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: Theme.Metric.checkboxMark, weight: .bold))
                        .foregroundStyle(Theme.card)
                }
            }
            .frame(width: Theme.Metric.checkbox, height: Theme.Metric.checkbox)
            // **A `gridControl` box, a 28 pt target.** The frame used to be
            // the 28 pt target, which made every row that carries a checkbox
            // 28 pt tall; it is the ink band now — the same 16 every other
            // control fills — and the target is a shape the row's overlay
            // tests against, which the layout does not pay for.
            .frame(width: Theme.Metric.gridControl, height: Theme.Metric.gridControl)
            .contentShape(Rectangle())
        }
        // The pointer's region, which is wider than the ink: `contentShape`
        // above is the box, and this is what the *row* tests against, so the
        // 6 pt around the box belong to the control rather than to the label.
        .contentShape(Rectangle()
            .inset(by: -Theme.Metric.checkboxHitOutset))
        .buttonStyle(.plain)
        .accessibilityValue(Text(isOn ? T("On", "开启") : T("Off", "关闭")))
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// Label at the left, checkbox at the right — Grain, Halation, Glare and Lens
/// Correction.
///
/// `enabled` is the PRD's "if one option is non-selectable, both the text and
/// the input pill is greyed across the app", and it is one modifier on the
/// row rather than a colour each half has to remember (`View.rowEnabled(_:)`).
struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool
    /// Which of the two v3 densities this row is in: Film's 10.5 (the
    /// default, and the EDR row's) or Camera's 9.
    var labelFont: Font = Theme.Font.label
    var enabled = true
    var reason: String = ""
    /// One line under the label, in the metadata ink, for a switch whose
    /// **scope** is not guessable from where it sits.
    ///
    /// A checkbox on a panel implies "this changes what the panel is about",
    /// and most of them do. The ones that do not — a switch that changes the
    /// render everywhere rather than only the thing above it — read as
    /// view settings and get used as if they were. Saying so costs a 9.5 pt
    /// line and is the difference between a control and a guess.
    var sublabel: String = ""
    /// What it does, for the hover. Distinct from `reason`, which is why it
    /// cannot be used right now.
    var help: String = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(labelFont).foregroundStyle(Theme.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !sublabel.isEmpty {
                    Text(sublabel).font(Theme.Font.sublabel).foregroundStyle(Theme.Ink.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            // Align visible ink, using the layout container's inset. The
            // larger pointer target does not move the square past the fields.
            CheckBox(isOn: $isOn)
                .padding(.trailing, Theme.Metric.checkboxTrailingInset)
        }
        // A row with a sublabel is two lines and sizes itself; one without is
        // the grid's row, with its ink in the same band every other row uses.
        .frame(height: sublabel.isEmpty ? Theme.Metric.gridControl : nil)
        .frame(height: sublabel.isEmpty ? Theme.Metric.toggleRowHeight : nil,
               alignment: sublabel.isEmpty ? .top : .center)
        .frame(minHeight: sublabel.isEmpty ? nil : Theme.Metric.toggleRowHeight)
        .rowEnabled(enabled, because: reason)
        .modifier(DisabledReason(show: !help.isEmpty, reason: help))
    }
}

// Shared scale and mark behaviour from the iOS ruler.


enum ToolRulerScale {
    static let spacing = 12.0

    static func step(in range: ClosedRange<Double>) -> Double {
        let raw = max(0.0001, (range.upperBound - range.lowerBound) / 40)
        let scale = pow(10, floor(log10(raw)))
        return ([1.0, 2, 2.5, 5, 10].first { $0 * scale >= raw - 1e-10 } ?? 10) * scale
    }

    /// Display ticks describe the scale, never the permitted parameter values.
    /// Quantise only to the numeric label's precision; landmarks exert no pull.
    static func quantized(_ value: Double, in range: ClosedRange<Double>, resolution: Double) -> Double {
        let bounded = min(range.upperBound, max(range.lowerBound, value))
        let rounded = (bounded / resolution).rounded() * resolution
        return min(range.upperBound, max(range.lowerBound, rounded))
    }
    static func advanced(_ value: Double, forward: Bool, range: ClosedRange<Double>, resolution: Double) -> Double {
        quantized(value + (forward ? resolution : -resolution), in: range, resolution: resolution)
    }
    static func majorStep(minor: Double) -> Double {
        if abs(minor - 1.0 / 3) < 1e-8 { return 1 }
        let raw = minor * 4
        let scale = pow(10, floor(log10(raw)))
        return ([1.0, 2, 5, 10].first { $0 * scale >= raw - 1e-10 } ?? 10) * scale
    }
    struct Tick { let value: Double; let major: Bool }
    static func ticks(in visible: ClosedRange<Double>, range: ClosedRange<Double>, step: Double,
                      anchor: Double, keyMarks: [Double]) -> [Tick] {
        let marks = Array(Set(([range.lowerBound, range.upperBound, anchor] + keyMarks).filter { range.contains($0) }))
        let first = Int(ceil(max(range.lowerBound, visible.lowerBound) / step - 1e-9))
        let last = Int(floor(min(range.upperBound, visible.upperBound) / step + 1e-9))
        let major = majorStep(minor: step)
        var result: [Tick] = []
        if first <= last {
            for index in first...last {
                let value = Double(index) * step
                // Replace a nearby minor line with the exact default marker.
                if marks.contains(where: { abs($0 - value) < step * 0.45 }) { continue }
                result.append(Tick(value: value, major: abs(value / major - (value / major).rounded()) < 1e-7))
            }
        }
        result += marks.filter { visible.contains($0) }.map { Tick(value: $0, major: true) }
        return result.sorted { $0.value < $1.value }
    }
}

/// Preserve the system pointer drag, including accessibility three-finger
/// dragging. AppKit's default performer selects the current input device;
/// never replace scrolling with a custom touch gesture.
struct DesktopRulerInput: NSViewRepresentable {
    var onChanged: (Double) -> Void
    var onEnded: () -> Void
    var onReset: () -> Void
    var onStep: (Bool) -> Void
    var onEditValue: () -> Void
    var valueEntryWidth: CGFloat
    var value: Double
    var step: Double
    var readValue: () -> Double
    var inputEnabled = true
    @Environment(\.isEnabled) private var isEnabled

    func makeNSView(context: Context) -> InputView {
        let view = InputView()
        return view
    }
    func updateNSView(_ view: InputView, context: Context) {
        view.change = onChanged; view.end = onEnded; view.reset = onReset
        view.advance = onStep; view.value = value; view.step = step; view.readValue = readValue
        view.editValue = onEditValue; view.valueEntryWidth = valueEntryWidth
        view.inputEnabled = inputEnabled && isEnabled
    }
    static func dismantleNSView(_ view: InputView, coordinator: ()) { view.finish() }

    final class InputView: NSView {
        var change: (Double) -> Void = { _ in }
        var end: () -> Void = {}
        var reset: () -> Void = {}
        var advance: (Bool) -> Void = { _ in }
        var editValue: () -> Void = {}
        var valueEntryWidth: CGFloat = 0
        var inputEnabled = true
        var value = 0.0
        var step = 1.0
        var readValue: () -> Double = { 0 }
        private var mouseStart: CGFloat?
        private var pendingDoubleClick: (() -> Void)?
        private var lastTick: Int?
        private var lastFeedback = -Double.infinity
        override var acceptsFirstResponder: Bool { true }
        override var focusRingType: NSFocusRingType { get { .none } set {} }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard inputEnabled else { return }
            finish()
            window?.makeFirstResponder(self)
            // Defer double-click actions until mouse-up so a drag can start
            // anywhere on the ruler, including on a quick second press.
            if event.clickCount == 2 {
                let x = convert(event.locationInWindow, from: nil).x
                pendingDoubleClick = x >= bounds.maxX - valueEntryWidth ? editValue : reset
            }
            mouseStart = event.locationInWindow.x
            lastTick = Int((value / max(step, 1e-9)).rounded())
        }
        override func mouseDragged(with event: NSEvent) {
            guard inputEnabled, let start = mouseStart else { finish(); return }
            pendingDoubleClick = nil
            change(Double(event.locationInWindow.x - start))
            // Read the binding again after the synchronous parameter write;
            // clamped endpoints must not keep ticking on overscroll.
            let tick = Int((readValue() / max(step, 1e-9)).rounded())
            if RulerFeedbackGate.shouldPerform(draggingSlider: true, previousTick: lastTick,
                                               tick: tick, elapsed: event.timestamp - lastFeedback) {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                lastFeedback = event.timestamp
            }
            lastTick = tick
        }
        override func mouseUp(with event: NSEvent) {
            let action = inputEnabled ? pendingDoubleClick : nil
            finish()
            action?()
        }
        override func keyDown(with event: NSEvent) {
            guard inputEnabled else { return }
            if event.keyCode == 123 || event.keyCode == 124 { advance(event.keyCode == 124) }
            else { super.keyDown(with: event) }
        }
        // Wheel events remain in the standard responder chain.
        override func scrollWheel(with event: NSEvent) { super.scrollWheel(with: event) }
        func finish() {
            let wasActive = mouseStart != nil
            mouseStart = nil; lastTick = nil; pendingDoubleClick = nil
            if wasActive { end() }
        }
    }
}

enum RulerFeedbackGate {
    static func shouldPerform(draggingSlider: Bool, previousTick: Int?, tick: Int, elapsed: Double) -> Bool {
        draggingSlider && previousTick != nil
            && previousTick != tick && elapsed >= 0.04
    }
}
