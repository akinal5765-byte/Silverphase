import SwiftUI

enum MobileStyle {
    // Current desktop Theme tokens, kept explicit until Theme's AppKit types
    // can be isolated. Layout follows EditorWindow.modernLayout, not legacy rails.
    static let accent = Color(uiColor: .systemOrange)
    static let canvas = Color(.sRGB, white: 0x18 / 255.0, opacity: 1)
    static let gutter: CGFloat = 8
    static let panel: CGFloat = 288
    static let radius: CGFloat = 16
    static let row: CGFloat = EditorDesign.hitSize
    static let well = Color.white.opacity(0.09)
    static let rule = Color.white.opacity(0.09)
    // Explicit semantic colour: hierarchical .secondary can disappear inside
    // a ScrollView over regularMaterial on iOS 18. Keep text independent of
    // material vibrancy, while retaining dark/light/accessibility adaptation.
    static let secondaryText = Color(uiColor: .secondaryLabel)
    static let muted = Color.white.opacity(0.28)
}

struct ChromeSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var radius: CGFloat = MobileStyle.radius
    var topBar = false
    var interactive = false
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            let shape = Self.boundary(radius: radius, topBar: topBar)
            if reduceTransparency {
                content.clipShape(shape).background(MobileStyle.canvas, in: shape)
            } else {
                // No backing plate: the glass already carries the system's own
                // scrim. A second dark layer is what made a tool panel read
                // thicker — and blurrier — than the system's own controls.
                content.clipShape(shape)
                    .glassEffect(.regular.interactive(interactive), in: shape)
            }
        } else {
            content.clipShape(RoundedRectangle(cornerRadius: topBar ? 0 : radius)).background(.regularMaterial, in: RoundedRectangle(cornerRadius: topBar ? 0 : radius))
        }
    }
    @available(iOS 26.0, *)
    static func boundary(radius: CGFloat = MobileStyle.radius, topBar: Bool) -> ConcentricRectangle {
        ConcentricRectangle(
            topLeadingCorner: .concentric(minimum: .fixed(radius)),
            topTrailingCorner: .concentric(minimum: .fixed(radius)),
            bottomLeadingCorner: topBar ? .fixed(0) : .concentric(minimum: .fixed(radius)),
            bottomTrailingCorner: topBar ? .fixed(0) : .concentric(minimum: .fixed(radius)))
    }

}

// Adapted from Lumina-HDR/SharedUIUtils.swift. Scale the animation's comparison
// value to retain the same rolling transition for fractional photographic units.
struct AdjustmentNumberTransition: ViewModifier {
    let value: Double?
    var fractionDigits = 2
    var label: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var animatedValue: Double? { value.map { ($0 * pow(10, Double(fractionDigits))).rounded() } }
    func body(content: Content) -> some View {
        content.monospacedDigit()
            .contentTransition(animatedValue.map { .numericText(value: $0) }
                ?? (label == nil ? .identity : .numericText(countsDown: false)))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: animatedValue)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: label)
    }
}
