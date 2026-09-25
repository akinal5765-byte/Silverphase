//  DevelopmentSection.swift — controls that act on the developed negative.
//  Both values are relative to the selected stock's measured defaults.

import SwiftUI

struct DevelopmentSection: View {
    @Bindable var session: Session

    var body: some View {
        PanelSection(L(.sectionDevelopment), key: "development",
                     initiallyExpanded: false,
                     blockTitle: T("Negative Response", "负片响应"),
                     // **Every stage's `•••` carries a Reset.** A stage is a
                     // group of settings, and "put this group back" is the one
                     // action every group has — a stage whose menu is empty is
                     // a stage the user cannot undo from.
                     menu: { AnyView(resetItem) }) {
            RailRows {
                ScrubSlider(label: L(.developmentContrast),
                            value: Binding(get: { session.params.developmentContrast },
                                           set: { var p = session.params; p.developmentContrast = $0; session.params = p }),
                            range: 0.5...1.5, zero: 1, snap: 0.05,
                            format: { String(format: "%.2f×", $0) })
                ScrubSlider(label: L(.developmentColorSeparation),
                            value: Binding(get: { session.params.colorSeparation },
                                           set: { var p = session.params; p.colorSeparation = $0; session.params = p }),
                            // Across 20 filming stocks the first DIR inverse
                            // loses monotonicity at 1.473 (Portra 800 Push 2).
                            range: 0...1.4, zero: 1, snap: 0.05,
                            format: { String(format: "%.2f×", $0) })
            }
        }
    }

    /// The one item a stage's menu is never without — see `ScanOutputSection`
    /// for the rule.
    private var resetItem: some View {
        Button(L(.helpResetDevelopment)) { reset() }
    }

    private func reset() {
        var p = session.params
        p.developmentContrast = 1
        p.colorSeparation = 1
        session.params = p
    }
}
