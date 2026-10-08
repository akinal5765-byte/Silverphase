import SwiftUI

struct ScenePlacementSection: View {
    @Bindable var session: Session

    static let range = Session.placementRange

    private var developed: Bool { session.latitude.reply != nil && session.latitude.frame == session.selection }
    private var committed: SceneLatitudeSettings { session.params.sceneLatitude }

    var body: some View {
        PanelSection(L(.sectionScenePlacement), key: "scenePlacement",
                     action: SectionAction(help: L(.helpResetPlacement),
                                           enabled: session.params.sceneLatitude.active) {
                         session.resetScenePlacement()
                     }) {
            RailRows {
                row(L(.placementHighlight), side: .highlight, committed: committed.highlightPullBack,
                    other: committed.shadowPullBack) {
                    session.placeScene(highlight: $0, shadow: committed.shadowPullBack, moving: .highlight)
                }
                row(L(.placementShadow), side: .shadow, committed: committed.shadowPullBack,
                    other: committed.highlightPullBack) {
                    session.placeScene(highlight: committed.highlightPullBack, shadow: $0, moving: .shadow)
                }
            }
            .rowEnabled(developed && !session.digitalIntermediateActive,
                        because: session.digitalIntermediateActive ? L(.reasonPlacementInDigitalIntermediate)
                                                                   : L(.reasonNotDeveloped))
        }
    }

    /// A slider step is solved and committed in the call that makes it
    /// (`Session.placeScene`), so the row shows what is committed and nothing
    /// else: there is no value in flight to keep.
    private func row(_ label: String, side: PlacementSide, committed: Double, other: Double,
                     set: @escaping (Double) -> Void) -> some View {
        let window = session.placementWindow(for: side, other: other)
        // A side with nothing the Fit takes has no band, and says why without
        // being touched: a slider that will not move owes the reason up front.
        let message = session.latitude.refusalMessage(for: side.rawValue)
            ?? (window.flatMap { $0.span == nil ? session.latitude.message(for: $0.below, side: side.rawValue) : nil })
        return ScrubSlider(label: label, sublabel: message,
                           value: Binding(get: { committed }, set: set),
                           range: Self.range, zero: 0, snap: 0.25,
                           format: { String(format: "%.2f", $0) },
                           usable: window?.span.map { [$0] } ?? [])
    }
}
