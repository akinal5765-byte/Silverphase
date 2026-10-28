import SwiftUI

// Adapted from Lumina-HDR/SharedUIUtils.swift. Scale the animation's comparison
// value to retain the same rolling transition for fractional photographic units.
struct AdjustmentNumberTransition: ViewModifier {
    let value: Double?
    var fractionDigits = 2
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var animatedValue: Double? { value.map { ($0 * pow(10, Double(fractionDigits))).rounded() } }
    func body(content: Content) -> some View {
        content.monospacedDigit()
            .contentTransition(animatedValue.map { .numericText(value: $0) } ?? .identity)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: animatedValue)
    }
}

struct RulerParameterRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double
    var fractionDigits = 2
    var entryRange: ClosedRange<Double>? = nil
    var step: Double? = nil
    var onInteraction: ((Bool) -> Void)? = nil
    let onReset: () -> Void
    @State private var preview: Double?
    @State private var entering = false
    @State private var entry = ""
    private var shown: Double { preview ?? value }
    private var resolution: Double { pow(10, -Double(fractionDigits)) }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text(title).font(.system(size: 13)).foregroundStyle(.secondary)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    onInteraction?(false)
                    entry = String(format: "%.*f", fractionDigits, value); entering = true
                } label: {
                    Text(String(format: "%.*f", fractionDigits, shown))
                        .font(.system(size: 14, weight: .medium))
                        .modifier(AdjustmentNumberTransition(value: shown, fractionDigits: fractionDigits))
                        .foregroundStyle(.primary)
                        .frame(minWidth: EditorDesign.hitSize, minHeight: EditorDesign.hitSize, alignment: .trailing)
                }.buttonStyle(.plain).accessibilityLabel("输入" + title)
            }.frame(minHeight: EditorDesign.hitSize)
            ToolTickRuler(value: $value, range: range, keyMarks: [], anchor: defaultValue,
                          height: EditorDesign.hitSize, step: step, resolution: resolution,
                          onPreview: { preview = $0; if onInteraction != nil { value = $0 } },
                          onDragging: { onInteraction?($0) }, onEnd: { preview = nil },
                          onReset: onReset)
                .frame(maxWidth: .infinity, minHeight: EditorDesign.hitSize, maxHeight: EditorDesign.hitSize)
                .clipped()
                .accessibilityElement().accessibilityLabel(title)
                .accessibilityIdentifier("ruler." + title)
                .accessibilityValue(String(format: "%.*f", fractionDigits, shown))
                .accessibilityHint("双击刻度尺恢复默认值")
                .accessibilityAction(named: "恢复默认值") { preview = nil; onReset() }
                .accessibilityAdjustableAction { direction in
                    value = ToolRulerScale.advanced(value, forward: direction == .increment, range: range, resolution: resolution)
                }
        }
        .padding(.bottom, 8).frame(maxWidth: .infinity, alignment: .leading)
        .alert("输入" + title, isPresented: $entering) {
            TextField(title, text: $entry).keyboardType(.numbersAndPunctuation)
            Button("取消", role: .cancel) { entering = false }
            Button("确定") {
                entering = false
                onInteraction?(false)
                let localized = entry.replacingOccurrences(of: ",", with: ".")
                if let number = Double(localized), number.isFinite { let bounds = entryRange ?? range; value = min(bounds.upperBound, max(bounds.lowerBound, number)) }
            }
        } message: { Text(String(format: "范围 %g 至 %g", (entryRange ?? range).lowerBound, (entryRange ?? range).upperBound)) }
    }
}
