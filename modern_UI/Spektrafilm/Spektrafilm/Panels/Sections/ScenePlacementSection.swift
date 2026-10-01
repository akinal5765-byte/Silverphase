import SwiftUI

struct ScenePlacementSection: View {
    @Bindable var session: Session
    /// The value under the pointer while a drag is in progress. Nil at rest,
    /// when the slider shows what is committed.
    @State private var dragging: (highlight: Double?, shadow: Double?) = (nil, nil)

    static let range: ClosedRange<Double> = 0...8

    private var developed: Bool { session.latitude.reply != nil && session.latitude.frame == session.selection }

    var body: some View {
        PanelSection(L(.sectionScenePlacement), key: "scenePlacement",
                     action: SectionAction(help: L(.helpResetPlacement),
                                           enabled: session.params.sceneLatitude.active) {
                         dragging = (nil, nil); session.resetScenePlacement()
                     }) {
            RailRows {
                row(L(.placementHighlight), side: "highlight",
                    committed: session.params.sceneLatitude.highlightPullBack,
                    minimum: session.latitude.reply?.fit.highlight.minimumPullBack,
                    shown: dragging.highlight) { v in
                    dragging.highlight = v
                    session.placeScene(highlight: v, shadow: dragging.shadow ?? session.params.sceneLatitude.shadowPullBack)
                } end: { dragging.highlight = nil }
                row(L(.placementShadow), side: "shadow",
                    committed: session.params.sceneLatitude.shadowPullBack,
                    minimum: session.latitude.reply?.fit.shadow.minimumPullBack,
                    shown: dragging.shadow) { v in
                    dragging.shadow = v
                    session.placeScene(highlight: dragging.highlight ?? session.params.sceneLatitude.highlightPullBack, shadow: v)
                } end: { dragging.shadow = nil }
            }
            .rowEnabled(developed && !session.digitalIntermediateActive,
                        because: session.digitalIntermediateActive ? L(.reasonPlacementInDigitalIntermediate)
                                                                   : L(.reasonNotDeveloped))
        }
    }

    private func row(_ label: String, side: String, committed: Double, minimum: Double?, shown: Double?,
                     set: @escaping (Double) -> Void, end: @escaping () -> Void) -> some View {
        let blocked: ClosedRange<Double>? = (minimum ?? 0) > 0 ? 0...(minimum ?? 0) : nil
        return ScrubSlider(label: label,
                           sublabel: session.latitude.refusalMessage(for: side),
                           value: Binding(get: { shown ?? committed }, set: set),
                           range: Self.range, zero: 0, snap: 0.25,
                           format: { String(format: "%.2f", $0) },
                           blocked: blocked, onCommit: end)
    }
}
