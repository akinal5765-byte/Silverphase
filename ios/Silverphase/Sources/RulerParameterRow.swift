import SwiftUI

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
                Text(title).font(EditorDesign.parameter).foregroundStyle(MobileStyle.secondaryText)
                    .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    onInteraction?(false)
                    entry = String(format: "%.*f", fractionDigits, value); entering = true
                } label: {
                    Text(String(format: "%.*f", fractionDigits, shown))
                        .font(EditorDesign.numericValue)
                        .modifier(AdjustmentNumberTransition(value: shown, fractionDigits: fractionDigits))
                        .foregroundStyle(.primary)
                        .frame(minWidth: EditorDesign.hitSize, minHeight: EditorDesign.hitSize, alignment: .trailing)
                }.buttonStyle(.plain).accessibilityLabel(T("Enter ", "输入", "輸入") + title)
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
                .accessibilityHint(T("Double-tap the ruler to restore the default", "双击刻度尺恢复默认值", "按兩下刻度尺恢復預設值"))
                .accessibilityAction(named: T("Restore the default", "恢复默认值", "恢復預設值")) { preview = nil; onReset() }
                .accessibilityAdjustableAction { direction in
                    value = ToolRulerScale.advanced(value, forward: direction == .increment, range: range, resolution: resolution)
                }
        }
        .padding(.bottom, 8).frame(maxWidth: .infinity, alignment: .leading)
        .alert(T("Enter ", "输入", "輸入") + title, isPresented: $entering) {
            TextField(title, text: $entry).keyboardType(.numbersAndPunctuation)
            Button(T("Cancel", "取消", "取消"), role: .cancel) { entering = false }
            Button(T("OK", "确定", "確定")) {
                entering = false
                onInteraction?(false)
                let localized = entry.replacingOccurrences(of: ",", with: ".")
                if let number = Double(localized), number.isFinite { let bounds = entryRange ?? range; value = min(bounds.upperBound, max(bounds.lowerBound, number)) }
            }
        } message: { Text(String(format: T("Range %g to %g", "范围 %g 至 %g", "範圍 %g 至 %g"), (entryRange ?? range).lowerBound, (entryRange ?? range).upperBound)) }
    }
}
