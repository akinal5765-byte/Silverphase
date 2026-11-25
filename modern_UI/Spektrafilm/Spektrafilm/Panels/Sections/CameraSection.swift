import SwiftUI

struct CameraSection: View {
    @Bindable var session: Session
    @State private var editingLegacyTone = false

    var body: some View {
        PanelSection(L(.sectionCamera), key: "camera",
                     blockTitle: session.halfFramePair == nil ? T("Prep Tone", "入片影调", "入片影調") : legacyToneTitle,
                     menu: { session.halfFramePair == nil ? AnyView(toneMenu) : AnyView(legacyToneMenu) }) {
            if session.halfFramePair == nil {
                RailRows {
                    if session.canMatchCameraBrightness { cameraBrightnessRow }
                    prepExposureRow
                    prepRow(T("Brights", "亮部", "亮部"), \.localBrights,
                            help: T("Adjusts local bright areas while retaining texture.", "调整局部亮部，保留纹理。", "調整局部亮部，保留紋理。"))
                    prepRow(T("Darks", "暗部", "暗部"), \.localDarks,
                            help: T("Adjusts local shadows while protecting the deepest blacks.", "调整局部暗部，保护最深的黑位。", "調整局部暗部，保護最深的黑位。"))
                    prepRow(T("Contrast", "对比度", "對比度"), \.prepContrast,
                            help: T("Expands or compresses tones around middle grey.", "以中灰为中心拉开或收拢影调。", "以中灰為中心拉開或收攏影調。"))
                    prepRow(T("Lift", "低端提升", "低端提升"), \.prepLift,
                            help: T("Adjusts the low end of the scene globally.", "整体调整场景影调的低端。", "整體調整場景影調的低端。"))
                    prepRow(T("Gain", "高端增益", "高端增益"), \.prepGain,
                            help: T("Adjusts the high end of the scene globally.", "整体调整场景影调的高端。", "整體調整場景影調的高端。"))
                }
                InspectorSubblock(title: T("Prep Detail", "入片细节", "入片細節")) {
                    RailRows {
                        prepRow(T("Midtone Detail", "中间调细节", "中間調細節"), \.prepDetail,
                                help: T("Strengthens or softens local texture near the midtones.", "加强或柔化中间调的局部纹理。", "加強或柔化中間調的局部紋理。"))
                    }
                }
                InspectorSubblock(title: T("Prep Colour", "入片色彩", "入片色彩")) {
                    RailRows {
                        prepRow(T("Colour Boost", "色彩增强", "色彩增強"), \.prepVibrance,
                                help: T("Adjusts muted colours more than strong colours.", "优先调整较淡的颜色。", "優先調整較淡的顏色。"))
                        prepRow(T("Saturation", "饱和度", "飽和度"), \.prepSaturation,
                                help: T("Adjusts all colours before film exposure.", "在入片前整体调整饱和度。", "在入片前整體調整飽和度。"))
                    }
                }
            }
            if session.halfFramePair != nil {
                legacyToneRows
            } else {
                if editingLegacyTone || session.params.cameraTone.hasLegacyAdjustments {
                    InspectorSubblock(title: legacyToneTitle, menu: { AnyView(legacyToneMenu) }) {
                        legacyToneRows
                    }
                }
                InspectorSubblock(title: T("White Balance", "白平衡", "白平衡"),
                                  menu: { AnyView(whiteBalanceMenu) }) {
                    WhiteBalanceRows(session: session)
                }
            }
            InspectorSubblock(title: T("Lens & Diffusion", "镜头与柔化", "鏡頭與柔化")) {
                RailRows {
                    ToggleRow(label: L(.cameraLensCorrection),
                              isOn: Binding(get: { session.decode.lensCorrection },
                                            set: { session.setLensCorrection($0) }),
                              enabled: session.halfFramePair == nil && session.lensCorrectionEnabled,
                              reason: session.lensCorrectionReason)
                    PillMenu(label: T("Colour Filter", "光谱滤镜", "光譜濾鏡"), options: CameraFilterChoice.allCases,
                             title: { $0.title },
                             selection: Binding(get: { session.params.cameraFilter },
                                                set: { var p = session.params; p.cameraFilter = $0; session.params = p }))
                    .help(T("Wratten lens filters shape the light before film exposure. Exposure loss is compensated automatically; colour films retain the filter's colour cast.",
                            "Wratten 镜头滤镜在胶片曝光前改变入射光谱，并自动补偿曝光损失；彩色胶片会保留滤镜色偏。", "Wratten 鏡頭濾鏡在膠片曝光前改變入射光譜，並自動補償曝光損失；彩色膠片會保留濾鏡色偏。"))
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
        .onChange(of: session.selection) { editingLegacyTone = false }
    }

    private var legacyToneTitle: String { T("Legacy Tone", "旧影调", "舊影調") }

    private var legacyToneRows: some View {
        RailRows {
            toneRow(T("Highlights", "高光", "高光"), \.highlights)
            toneRow(T("Shadows", "阴影", "陰影"), \.shadows)
            toneRow(T("Whites", "白色色阶", "白色色階"), \.whites)
            toneRow(T("Blacks", "黑色色阶", "黑色色階"), \.blacks)
        }
    }

    private var cameraBrightnessRow: some View {
        ToggleRow(label: T("Match Camera Preview Brightness", "匹配相机预览亮度", "比對相機預覽亮度"),
                  isOn: Binding(get: { session.params.cameraTone.matchesCameraBrightness == true },
                                set: { session.setCameraBrightnessMatching($0) }),
                  labelFont: Theme.Font.label,
                  help: T("Matches the camera preview once for this photo. Turn off and on to match again.",
                          "按相机预览为此照片匹配一次。关闭后再开启即可重新匹配。",
                          "按相機預覽為此照片比對一次。關閉後再開啟即可重新比對。"))
    }

    private var matchedExposureReadout: String? {
        let tone = session.params.cameraTone
        guard session.canMatchCameraBrightness, tone.matchesCameraBrightness == true else { return nil }
        let message = session.cameraBrightnessMessage
        if !message.isEmpty { return message }
        guard let match = tone.matchedCameraExposure else { return nil }
        let automatic = String(format: "%+.2f", match)
        if tone.matchedCameraHighlightLimited == true {
            return T("Starts at \(automatic) EV to protect highlights.",
                     "起始曝光 \(automatic) EV，提亮受高光保护限制。",
                     "起始曝光 \(automatic) EV，提亮受高光保護限制。")
        }
        return T("Matched starting exposure: \(automatic) EV.",
                 "匹配后的起始曝光为 \(automatic) EV。",
                 "比對後的起始曝光為 \(automatic) EV。")
    }

    private var prepExposureRow: some View {
        let tone = session.params.cameraTone
        let match = session.canMatchCameraBrightness && tone.matchesCameraBrightness == true
            ? tone.matchedCameraExposure : nil
        return ScrubSlider(label: T("Prep Exposure", "入片曝光", "入片曝光"),
                           sublabel: matchedExposureReadout,
                           value: Binding(get: { session.params.cameraTone.effectivePrepExposure }, set: { total in
                               var params = session.params
                               let offset = total - params.cameraTone.cameraExposureBaseline
                               params.cameraTone.prepExposure = abs(offset) < 1e-9 ? nil : offset
                               session.params = params
                           }),
                           range: -3...3, referenceValue: match, snap: 0.05,
                           format: { String(format: "%+.2f EV", $0) })
            .help(prepExposureHelp)
    }

    private var prepExposureHelp: String {
        if session.canMatchCameraBrightness && session.params.cameraTone.matchesCameraBrightness == true {
            return T("Shows the applied exposure. The orange tick marks the matched starting exposure.",
                     "显示实际入片曝光。滑杆内的橙色短线标记匹配后的起始曝光。",
                     "顯示實際入片曝光。滑桿內的橘色短線標記比對後的起始曝光。")
        }
        return T("Changes scene brightness without print exposure compensation.",
                 "整体调整入片亮度，不参与印相曝光补偿。",
                 "整體調整入片亮度，不參與印相曝光補償。")
    }

    private var toneMenu: some View {
        Group {
            Button(T("Reset Prep", "重置入片调整", "重設入片調整")) {
                var p = session.params
                let old = p.cameraTone
                p.cameraTone = CameraTone(highlights: old.highlights, shadows: old.shadows,
                                          whites: old.whites, blacks: old.blacks)
                session.params = p
            }
            if session.halfFramePair == nil && session.params.sceneLatitude.active {
                Button(T("Clear Legacy Scene Placement", "清除旧场景置位", "清除舊場景置位")) {
                    session.resetScenePlacement()
                }
            }
        }
    }

    private var legacyToneMenu: some View {
        Button(T("Reset Legacy Tone", "重置旧影调", "重設舊影調")) {
            var p = session.params
            p.cameraTone.highlights = 0
            p.cameraTone.shadows = 0
            p.cameraTone.whites = 0
            p.cameraTone.blacks = 0
            editingLegacyTone = false
            session.params = p
        }
    }

    private func toneRow(_ title: String, _ keyPath: WritableKeyPath<CameraTone, Double>) -> some View {
        ScrubSlider(label: title, value: Binding(
            get: { session.params.cameraTone[keyPath: keyPath] },
            set: { value in
                var p = session.params
                editingLegacyTone = true
                p.cameraTone[keyPath: keyPath] = value
                session.params = p
            }), range: CameraTone.range, zero: 0, snap: 1,
            format: { String(format: "%+.0f", $0) })
            .help(T("Adjusts scene tones before film exposure.", "在胶片曝光前调整场景影调。", "在膠片曝光前調整場景影調。"))
    }

    private func prepRow(_ title: String, _ keyPath: WritableKeyPath<CameraTone, Double?>,
                         help: String) -> some View {
        ScrubSlider(label: title, value: Binding(
            get: { session.params.cameraTone[keyPath: keyPath] ?? 0 },
            set: { value in
                var p = session.params
                p.cameraTone[keyPath: keyPath] = value == 0 ? nil : value
                session.params = p
            }), range: CameraTone.range, zero: 0, snap: 1,
            format: { String(format: "%+.0f", $0) })
            .help(help)
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

/// Lets either white-balance axis follow the recorded camera value.
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
            Text(L(.whiteBalanceAsShot))
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
