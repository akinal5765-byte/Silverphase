//  CameraSection.swift — how the photograph enters the film: Metering Mode,
//  Exposure Compensation, Temperature, Tint, Lens Correction and shooting
//  diffusion.
//
//  **v3 (2026-09-18) renamed three things and added one.** The section is
//  **Input / Capture**; `AE Method` is **Metering Mode**. Both are visual renames
//  only — `session.aeMethod` keeps its name, its offered values and its
//  legacy restoration, which handoff §7 requires. The addition is a **reset
//  arrow on the header**, beside the "•••". Its scope is left open by §8.3,
//  so it is wired to the one reset this section already had a name for —
//  exposure compensation — and the tooltip says exactly that rather than implying it
//  resets the section. Camera's labels are set at 9 pt in a 70 pt column,
//  which is v3's measurement and narrower than the rail's shared 84.
//
//  The 2026-09-17 drawing's first section, and every row of it is a row of
//  the drawing. No well: controls sit directly on the rail, which is what
//  changed across the whole interface — a well now holds a *choice from a
//  set* (the film and print lists) and nothing else.
//
//  **Metering** (`auto_exposure` + `auto_exposure_method`, and the pill is
//  wired to `Session.aeMethod`). The four intents are what the engine's meter
//  follows: overall correctness (`balanced`), a subject in the middle
//  (`center`), the brightest part kept (`protect highlights`), the darkest
//  kept (`protect shadows`). `Custom` is the meter **off** — the PRD's
//  "linearized baseline as the +0.0 baseline" — and it needed no new field,
//  because `camera.auto_exposure` has been in the schema all along.
//
//  **Exposure Compensation** (`exposure_compensation_ev`) sits directly under it, as
//  the PRD asks, because the two are one decision read in two lines: the
//  method chooses a baseline and the slider offsets it. It is **film
//  placement, not print brightness** — the print gain is taken from a mid-grey
//  exposed at this offset (`printing.cpp`), so the print re-normalises what
//  the slider moves: measured on the smoke frame, a 4 EV sweep moves the mean
//  print luminance by 2.4 %, downward, while the contrast rises. What it buys
//  is where the scene sits on the film curve: grain, latitude, saturation.
//
//  **Temperature and Tint** are unchanged, as the PRD says ("How Temperature
//  and Tint is wired remain unchanged") — decode-side white balance, with the
//  "As Shot" box each axis has always had (`WhiteBalanceRows`).
//
//  **Vignetting** is client-side (Layer 2's lens fall-off). The engine has no
//  vignette parameter; it sits here because that is where a photographer
//  looks for it.
//
//  **Lens Correction** is decode-side too, and the one row in this section
//  that can be non-selectable — see `Session.lensCorrectionEnabled`.

import SwiftUI

struct CameraSection: View {
    @Bindable var session: Session

    var body: some View {
        PanelSection(L(.sectionCamera), key: "camera",
                     blockTitle: T("Metering & Exposure", "测光与曝光"),
                     menu: { AnyView(exposureMenu) }) {
            RailRows {
                PillMenu(label: L(.cameraMetering),
                         options: AEMethod.offered,
                         title: { L($0.key) },
                         selection: Binding(get: { session.aeMethod },
                                            set: { session.aeMethod = $0 }))
                    .disabled(session.halfFramePair != nil)
                ScrubSlider(label: L(.cameraFilmExposure),
                            sublabelView: asShotLine,
                            value: Binding(get: { session.params.exposureCompensationEV },
                                           set: { var p = session.params; p.exposureCompensationEV = $0; session.params = p }),
                            range: -4...4, snap: 1 / 3, format: { String(format: "%+.1f", $0) })
            }
            if session.halfFramePair == nil {
            InspectorSubblock(title: T("White Balance", "白平衡"),
                              menu: { AnyView(whiteBalanceMenu) }) {
                WhiteBalanceRows(session: session)
            }
            }
            InspectorSubblock(title: T("Lens & Diffusion", "镜头与柔化")) {
                RailRows {
                    ToggleRow(label: L(.cameraLensCorrection),
                              isOn: Binding(get: { session.decode.lensCorrection },
                                            set: { session.setLensCorrection($0) }),
                              enabled: session.halfFramePair == nil && session.lensCorrectionEnabled,
                              reason: session.lensCorrectionReason)
                    PillMenu(label: T("Colour Filter", "光谱滤镜"), options: CameraFilterChoice.allCases,
                             title: { $0.title },
                             selection: Binding(get: { session.params.cameraFilter },
                                                set: { var p = session.params; p.cameraFilter = $0; session.params = p }))
                    .help(T("Wratten lens filters shape the light before film exposure. Exposure loss is compensated automatically; colour films retain the filter's colour cast.",
                            "Wratten 镜头滤镜在胶片曝光前改变入射光谱，并自动补偿曝光损失；彩色胶片会保留滤镜色偏。"))
                    PillMenu(label: L(.cameraDiffusion), options: DiffusionChoice.allCases,
                             title: { $0.title },
                             selection: Binding(
                                get: { DiffusionChoice(rawValue: session.params.cameraDiffusion) ?? .off },
                                set: { var p = session.params; p.cameraDiffusion = $0.rawValue; session.params = p }))
                    .help(L(.lensFilterHelp))
                    ScrubSlider(label: L(.lensFilterStrength),
                                value: Binding(get: { session.params.cameraDiffusionStrength },
                                               set: { var p = session.params; p.cameraDiffusionStrength = $0; session.params = p }),
                                range: 0.125...2, zero: 0.5, snap: 0.125,
                                format: { String(format: "%.3g", $0) },
                                disabled: session.params.cameraDiffusion == "off")
                    ScrubSlider(label: L(.lensHaloRange),
                                value: Binding(get: { session.params.cameraDiffusionRange },
                                               set: { var p = session.params; p.cameraDiffusionRange = $0; session.params = p }),
                                range: 0.5...2, zero: 1, snap: 0.1,
                                format: { String(format: "%.1f×", $0) },
                                disabled: session.params.cameraDiffusion == "off")
                    .help(L(.lensHaloRangeHelp))
                }
            }
        }
    }

    /// "As Shot ☐" under Exposure Compensation — the line the drawing puts under the
    /// first three sliders. What it means and what clicking it does are
    /// `Session.filmExposureIsAsShot` and `setFilmExposureAsShot(_:)`; this is
    /// only the two views.
    private var asShotLine: AnyView {
        AnyView(AsShotLine(isOn: Binding(get: { session.filmExposureIsAsShot },
                                         set: { session.setFilmExposureAsShot($0) }),
                           enabled: true))
    }

    /// What the drawing has no room for and the section still needs: the
    /// white-balance presets and the neutral picker, which were a pill and an
    /// eyedropper on a row of their own. The drawing's Camera section is five
    /// rows and none of them is that row — so they are here, in the "•••" the
    /// drawing *does* give every section.
    private var exposureMenu: some View {
        Button(L(.helpResetFilmExposure)) {
            var p = session.params; p.exposureCompensationEV = 0; session.params = p
        }
    }

    private var whiteBalanceMenu: some View {
        Group {
            Button(L(.helpPickNeutral)) { session.wbPickerActive.toggle() }
                .disabled(session.selection == nil)
            // The presets are not in the spec's tables, and their names are
            // closest to profile names — which stay as they are. They are the
            // only rows in this section left in English.
            Menu(L(.helpWhiteBalancePreset)) {
                ForEach(DecodeSettings.WhiteBalance.allCases.filter { $0 != .custom }, id: \.self) { wb in
                    Button {
                        session.setWhiteBalance(wb)
                    } label: {
                        if session.decode.whiteBalance == wb { Label(wb.rawValue, systemImage: "checkmark") }
                        else { Text(wb.rawValue) }
                    }
                }
            }
        }
    }
}

/// "As Shot" and its box, on the second line of a slider row.
///
/// The box's own padding is a hit area rather than layout (it is drawn 8 pt),
/// so the negative vertical padding keeps the line from growing to suit it.
///
/// **One view, three rows.** It draws the line under Exposure Compensation here and
/// under Temperature and Tint in `WhiteBalanceRows`, so its label is one
/// string in all three places: the two white-balance rows cannot say "As
/// Shot" while this one says 拍摄时设置 without a `label:` parameter, which
/// would be a shape change this pass was told not to make. The spec lists
/// "As Shot" once, next to Exposure Compensation.
struct AsShotLine: View {
    @Binding var isOn: Bool
    var enabled: Bool
    var body: some View {
        // **The app's one switch shape**: the label on the row's leading edge,
        // the box on its trailing edge, the whole row clickable
        // (UI-SPEC §2.12).
        //
        // It was a caption with a bare checkbox right after it — the text read
        // as an explanation and the box as something appended to a sentence,
        // which is why the user asked why a caption has a switch at all. It
        // *is* a switch: "this value is the one the camera recorded". What was
        // wrong was its shape, not its existence.
        HStack(spacing: 0) {
            Text(L(.cameraFilmExposureAsShot))
                .font(Theme.Font.sublabel)
                .foregroundStyle(Theme.Ink.tertiary)
            Spacer(minLength: Theme.Metric.space4)
            // Match the visible right edge of the other parameter controls;
            // the expanded pointer target does not participate in alignment.
            CheckBox(isOn: $isOn)
                .padding(.trailing, Theme.Metric.checkboxTrailingInset)
        }
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
        .rowEnabled(enabled)
    }
}

/// The rows of a section: the grid's gap between them, and no inset of its
/// own.
///
/// One container rather than a modifier on each row, because the inset is a
/// property of the *column* — a row that forgot it would not look wrong on
/// its own, only out of line with the four above it, which is exactly the
/// kind of drift a capture catches late.
///
/// **Both numbers are Modern's on a Modern surface.** They used to be the
/// drawing's 16/9 in both layouts, because the drawing's rail and the
/// floating inspector both happen to hold a stack of rows — but they are not
/// the same surface: Traditional's rail carries the whole process chain and
/// Modern's inspector shows one stage of it, so the tighter scale is the
/// right one there and the drawing's is the right one here. The horizontal
/// inset is 0 on a Modern surface because the panel already pads by
/// `modernContentInset` and this container must not add a second one.
struct RailRows<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metric.modernRowSpacing) {
            content()
        }
        // **No horizontal inset.** The panel pads its whole body by
        // `modernContentInset`; a container that added its own put every row's
        // first glyph on a second left edge.
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
