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
                ToggleRow(label: T("Scan Sharpening", "扫描锐化"),
                          isOn: param(\.scannerSharpeningActive),
                          enabled: !session.digitalIntermediateActive,
                          reason: T("Digital Intermediate bypasses scanner sharpening.", "数字中间片不应用扫描锐化。"),
                          help: T("Enhances edge contrast during scanning. 1× preserves the original strength; turn off to leave sharpening to another editor.",
                                  "在扫描阶段增强边缘反差。1× 保留原有强度；可关闭后交给其他软件做最终锐化。"))
                ScrubSlider(label: T("Sharpening Strength", "锐化强度"),
                            value: Binding(get: { session.params.scannerSharpeningStrength },
                                           set: { var p = session.params; p.scannerSharpeningStrength = $0; session.params = p }),
                            range: FilmParams.scannerSharpeningRange, zero: 1, snap: 0.1,
                            format: { String(format: "%.1f×", $0) },
                            disabled: !session.params.scannerSharpeningActive || session.digitalIntermediateActive)
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
                          isOn: Binding(get: { !session.paperIsMonochrome && session.params.extendedDynamicRange },
                                        set: { var p = session.params; p.extendedDynamicRange = $0; session.params = p }),
                          labelFont: Theme.Font.edrLabel,
                          enabled: !session.params.scanFilm && !session.digitalIntermediateActive && !session.paperIsMonochrome,
                          reason: session.paperIsMonochrome ? T("The experimental B&W print has no calibrated highlight expansion.", "实验黑白印相没有标定的高光扩展曲线。") : L(.reasonEDRDisabledInScanFilm),
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
        p.scannerSharpeningActive = true
        p.scannerSharpeningStrength = 1
        p.extendedDynamicRange = false
        session.params = p
    }

    private func param(_ keyPath: WritableKeyPath<FilmParams, Bool>) -> Binding<Bool> {
        Binding(get: { session.params[keyPath: keyPath] },
                set: { var p = session.params; p[keyPath: keyPath] = $0; session.params = p })
    }
}
