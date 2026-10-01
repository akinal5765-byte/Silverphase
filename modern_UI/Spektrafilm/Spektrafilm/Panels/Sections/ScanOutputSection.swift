//  ScanOutputSection.swift — controls applied after the paper image exists.
//
//  Paper glare and highlight expansion affect the scanned/output image, not
//  the enlarger exposure that forms the paper image. Keeping them in their own
//  stage makes the right rail follow the physical process from capture to
//  output without changing either control's engine field.

import SwiftUI

struct ScanOutputSection: View {
    @Bindable var session: Session

    var body: some View {
        PanelSection(L(.sectionOutput), key: "output", initiallyExpanded: false,
                     blockTitle: T("Scan Rendering", "扫描呈现"),
                     menu: { AnyView(resetItem) }) {
            RailRows {
                ToggleRow(label: L(.filmGlare),
                          isOn: param(\.glareActive),
                          enabled: !session.params.scanFilm && !session.digitalIntermediateActive,
                          reason: L(.reasonPaperGlareDisabledInScanFilm),
                          help: L(.paperGlareHelp))
                ScrubSlider(label: L(.filmGlareStrength),
                            value: Binding(get: { session.params.effects.glare },
                                           set: { var p = session.params; p.effects.glare = $0; session.params = p }),
                            range: EffectStrengths.glareRange, zero: 1, snap: 0.1,
                            format: { String(format: "%.1f×", $0) },
                            disabled: !session.params.glareActive || session.params.scanFilm || session.digitalIntermediateActive)
                ToggleRow(label: L(.printEDR),
                          isOn: param(\.extendedDynamicRange),
                          labelFont: Theme.Font.edrLabel,
                          enabled: !session.params.scanFilm && !session.digitalIntermediateActive,
                          reason: L(.reasonEDRDisabledInScanFilm),
                          sublabel: L(.statusEDRScope),
                          help: L(.highlightExpansionHelp))
            }
        }
    }

    private var resetItem: some View {
        Button(T("Reset this section", "重置本节")) { reset() }
    }

    private func reset() {
        var p = session.params
        p.glareActive = true
        p.effects.glare = 1
        p.extendedDynamicRange = false
        session.params = p
    }

    private func param(_ keyPath: WritableKeyPath<FilmParams, Bool>) -> Binding<Bool> {
        Binding(get: { session.params[keyPath: keyPath] },
                set: { var p = session.params; p[keyPath: keyPath] = $0; session.params = p })
    }
}
