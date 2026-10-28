// Adapted from the user-owned Lumina-HDR ToolTickRuler.swift (2026-10-26).
// Retains moving ticks, haptics and Reduce Motion. Precision release
// deliberately has no velocity projection or spring overshoot.
// Silverphase: compact height, semantic ticks and exact default markers,
// vertical-scroll cooperation and cancellation when a control disappears.
import SwiftUI

struct ToolTickRuler: View {
    enum Orientation { case horizontal, vertical }
    @Binding var value: Double
    let range: ClosedRange<Double>
    let keyMarks: [Double]
    let anchor: Double
    var orientation: Orientation = .horizontal
    var height: CGFloat = 44
    var step: Double? = nil
    var resolution = 0.01
    var onPreview: (Double) -> Void
    var onDragging: (Bool) -> Void
    var onEnd: () -> Void
    var onReset: () -> Void

    var body: some View {
        AnimatedToolRuler(value: $value, range: range, anchor: anchor, keyMarks: keyMarks, orientation: orientation, height: height, commitsWhileDragging: false, tickStep: step, resolution: resolution,
                          onPreview: onPreview, onDragging: onDragging, onEnd: onEnd, onReset: onReset)
    }
}

/// Shared horizontal and vertical interaction and rendering.
private struct AnimatedToolRuler: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let anchor: Double
    let keyMarks: [Double]
    var orientation: ToolTickRuler.Orientation = .horizontal
    var height: CGFloat = 44
    var commitsWhileDragging = true
    var tickStep: Double? = nil
    var resolution = 0.01
    var onPreview: (Double) -> Void = { _ in }
    var onDragging: (Bool) -> Void = { _ in }
    var onEnd: () -> Void = { }
    var onReset: () -> Void = { }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlightDirection = 0.0
    @State private var highlightStrength = 0.0
    @State private var motionID = UUID()
    @State private var interactionValue: Double?
    private var displayedValue: Double { interactionValue ?? value }
    @State private var rejectsDrag = false
    @State private var dragStart: Double?
    @GestureState private var dragRecognized = false
    @State private var overscroll = 0.0
    @State private var lastStep: Int?
    @State private var feedback = UIImpactFeedbackGenerator(style: .light)
    private let spacing = ToolRulerScale.spacing
    private var unitsPerTick: Double { tickStep ?? ToolRulerScale.step(in: range) }

    var body: some View {
        ToolRulerMarks(value: displayedValue + overscroll, range: range, spacing: spacing, unitsPerTick: unitsPerTick,
                            anchor: anchor, keyMarks: keyMarks,
                            highlightDirection: highlightDirection, highlightStrength: highlightStrength,
                            orientation: orientation)
            .frame(width: orientation == .vertical ? 26 : nil,
                   height: orientation == .horizontal ? height : nil)
            .overlay(alignment: orientation == .horizontal ? .bottom : .trailing) {
                Capsule()
                    .fill(MobileStyle.accent)
                    .frame(width: orientation == .horizontal ? 3 : 22,
                           height: orientation == .horizontal ? 22 : 3)
                    .shadow(color: MobileStyle.accent.opacity(0.3), radius: 4)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 8)
                .updating($dragRecognized) { _, state, _ in state = true }
                .onChanged { gesture in
                    if rejectsDrag { return }
                    if dragStart == nil {
                        if orientation == .horizontal && abs(gesture.translation.height) > abs(gesture.translation.width) {
                            rejectsDrag = true; return
                        }
                        motionID = UUID()
                        dragStart = value
                        onDragging(true)
                        lastStep = Int((value / unitsPerTick).rounded())
                        feedback.prepare()
                    }
                    let displacement = orientation == .horizontal ? gesture.translation.width : gesture.translation.height
                    let proposed = (dragStart ?? value) - Double(displacement) / spacing * unitsPerTick
                    let clamped = ToolRulerScale.quantized(proposed, in: range, resolution: resolution)
                    // Every tool has 40 intervals across 480 pt; only the numeric step changes.
                    if abs(clamped - displayedValue) > 0.0001 {
                        highlightDirection = clamped > displayedValue ? 1 : -1
                        highlightStrength = 1
                    }
                    if commitsWhileDragging { value = clamped }
                    else { interactionValue = clamped }
                    onPreview(clamped)
                    let excess = proposed - clamped
                    overscroll = excess / (1 + abs(excess) / (unitsPerTick * 2)) * 0.2
                    let step = Int((clamped / unitsPerTick).rounded())
                    if step != lastStep {
                        let tickValue = (clamped / unitsPerTick).rounded() * unitsPerTick
                        let majorUnit = ToolRulerScale.majorStep(minor: unitsPerTick)
                        let major = abs(clamped - anchor) < resolution / 2 || abs(tickValue / majorUnit - (tickValue / majorUnit).rounded()) < 1e-7
                        feedback.impactOccurred(intensity: major ? 1.0 : 0.6)
                        feedback.prepare()
                        lastStep = step
                    }
                }
                .onEnded { _ in
                    defer { rejectsDrag = false }
                    guard dragStart != nil else { return }
                    // Release at the finger's value. No velocity projection:
                    // fast swipes must not turn into a different adjustment.
                    let target = ToolRulerScale.quantized(displayedValue, in: range, resolution: resolution)
                    dragStart = nil
                    if abs(target - displayedValue) > 0.0001 {
                        highlightDirection = target > displayedValue ? 1 : -1
                        highlightStrength = 1
                    }
                    let completedMotion = motionID
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                        value = target
                        interactionValue = nil
                        overscroll = 0
                    } completion: {
                        guard motionID == completedMotion, dragStart == nil else { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                            highlightStrength = 0
                        }
                    }
                    onPreview(target)
                    onDragging(false)
                    onEnd()
                    feedback.impactOccurred(intensity: 0.4)
                    lastStep = nil
                })
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                resetInteraction()
                onEnd()
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                    onReset()
                }
                feedback.impactOccurred(intensity: 0.4)
            })
            .onChange(of: range) { _, _ in resetInteraction() }
            .onChange(of: dragRecognized) { _, active in if !active { resetInteraction() } }
            .onChange(of: anchor) { _, _ in resetInteraction() }
            .onDisappear { resetInteraction() }
    }

    private func resetInteraction() {
        let wasDragging = dragStart != nil
        motionID = UUID()
        highlightStrength = 0
        dragStart = nil
        rejectsDrag = false
        interactionValue = nil
        overscroll = 0
        lastStep = nil
        if wasDragging {
            onDragging(false)
            onEnd()
        }
    }

}

private struct ToolRulerMarks: View, Animatable {
    var value: Double
    let range: ClosedRange<Double>
    let spacing: Double
    let unitsPerTick: Double
    let anchor: Double
    let keyMarks: [Double]
    let highlightDirection: Double
    var highlightStrength: Double
    let orientation: ToolTickRuler.Orientation
    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(value, highlightStrength) }
        set {
            value = newValue.first
            highlightStrength = newValue.second
        }
    }

    var body: some View {
        Canvas { context, size in
            let length = orientation == .horizontal ? size.width : size.height
            let center = length / 2
            let half = (Double(length) / (2 * spacing) + 1) * unitsPerTick
            let ticks = ToolRulerScale.ticks(in: (value - half)...(value + half), range: range, step: unitsPerTick, anchor: anchor, keyMarks: keyMarks)
            for tick in ticks {
                let x = center + (tick.value - value) / unitsPerTick * spacing
                let major = tick.major
                // Only ticks that have crossed the pointer receive a trailing highlight.
                let distancePastPointer = (center - x) * highlightDirection
                let proximity = distancePastPointer >= 0
                    ? max(0, 1 - distancePastPointer / (spacing * 1.25)) : 0
                let highlight = proximity * proximity * (3 - 2 * proximity) * highlightStrength
                let baseHeight: CGFloat = major ? 20 : 12
                let baseWidth: CGFloat = major ? 1.8 : 1.2
                let height = baseHeight + (22 - baseHeight) * highlight
                let width = baseWidth + (3 - baseWidth) * highlight
                let rect = orientation == .horizontal
                    ? CGRect(x: x - width / 2, y: size.height - height, width: width, height: height)
                    : CGRect(x: size.width - height, y: x - width / 2, width: height, height: width)
                let path = Path(roundedRect: rect, cornerRadius: width / 2)
                context.fill(path, with: .color(.primary.opacity((major ? 0.6 : 0.3) * (1 - highlight))))
                context.fill(path, with: .color(MobileStyle.accent.opacity(highlight)))

            }
        }
        .mask(LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .black, location: 0.18),
            .init(color: .black, location: 0.82),
            .init(color: .clear, location: 1)
        ], startPoint: orientation == .horizontal ? .leading : .top,
           endPoint: orientation == .horizontal ? .trailing : .bottom))
        .clipped()
    }
}
