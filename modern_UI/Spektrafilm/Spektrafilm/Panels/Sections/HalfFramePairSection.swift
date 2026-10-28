import SwiftUI

struct HalfFramePairSection: View {
    @Bindable var session: Session
    private func number(_ side: HalfFramePair.Side, _ path: WritableKeyPath<HalfFramePair.Hole, Double>) -> Binding<Double> {
        Binding(get: { session.halfFramePair?[side]?[keyPath: path] ?? 0 }, set: { value in
            session.updateHalfFramePair { pair in
                guard var hole = pair[side] else { return }; hole[keyPath: path] = value; pair[side] = hole
            }
        })
    }
    var body: some View {
        PanelSection(T("Half-frame Pair", "半格双联画"), key: "halfFramePair") {
            Button(T("Create Pair…", "创建双联画…")) { session.createHalfFramePair() }
            if let pair = session.halfFramePair {
                ToggleRow(label: T("Turned Camera", "相机竖拍"), isOn: Binding(get: { pair.turned }, set: { value in session.updateHalfFramePair { $0.turned = value } }))
                ScrubSlider(label: T("Spacing · mm", "间隔 · mm"), value: Binding(get: { pair.spacingMM }, set: { value in session.updateHalfFramePair { $0.spacingMM = value } }), range: 0.5...2, zero: 1, disabled: pair.onStrip)
                ForEach(HalfFramePair.Side.allCases, id: \.rawValue) { side in
                    InspectorSubblock(title: side == .left ? T("First Frame", "第一格") : T("Second Frame", "第二格")) {
                        if let hole = pair[side] {
                            Text(hole.url.lastPathComponent).font(.caption).lineLimit(1)
                                .help(T("Each photograph keeps the white balance and lens correction saved in its own settings before pairing.", "各格保留组成双联画前各照片已保存的白平衡和镜头校正。"))
                            RailRows {
                                ToggleRow(label: T("Auto Exposure", "自动测光"), isOn: Binding(get: { hole.autoExposure }, set: { value in session.updateHalfFramePair { $0[side]?.autoExposure = value } }))
                                PillMenu(label: T("Metering", "测光方式"), options: ExposureMethod.allCases,
                                         title: { $0.title }, selection: Binding(get: { ExposureMethod(rawValue: hole.meterMethod ?? "balanced") ?? .balanced }, set: { value in session.updateHalfFramePair { $0[side]?.meterMethod = value.rawValue } }))
                                    .disabled(!hole.autoExposure)
                                ScrubSlider(label: T("Exposure · EV", "曝光 · EV"), value: number(side, \.exposureEV), range: -8...8, snap: 1/3)
                                ToggleRow(label: T("Scene Placement", "场景安置"), isOn: Binding(get: { hole.sceneLatitude.active }, set: { value in session.updateHalfFramePair { $0[side]?.sceneLatitude.active = value } }))
                                ScrubSlider(label: T("Highlights", "高光回拉"), value: number(side, \.sceneLatitude.highlightPullBack), range: 0...8, disabled: !hole.sceneLatitude.active)
                                ScrubSlider(label: T("Shadows", "暗部回拉"), value: number(side, \.sceneLatitude.shadowPullBack), range: 0...8, disabled: !hole.sceneLatitude.active)
                                ScrubSlider(label: T("Scale", "取景缩放"), value: number(side, \.placement.scale), range: 1...4, zero: 1)
                                ScrubSlider(label: T("Horizontal", "水平位置"), value: number(side, \.placement.x), range: -1...1)
                                ScrubSlider(label: T("Vertical", "垂直位置"), value: number(side, \.placement.y), range: -1...1)
                            }
                            HStack {
                                Button(T("Rotate", "旋转")) { session.updateHalfFramePair { $0[side]?.placement.quarterTurns += 1 } }
                                Button(T("Replace…", "替换…")) { session.replacePairHole(side) }
                                Button(T("Clear", "清空")) { session.updateHalfFramePair { $0[side] = nil } }
                            }.buttonStyle(.borderless)
                        } else {
                            Button(T("Choose Photograph…", "选择照片…")) { session.replacePairHole(side) }
                        }
                    }
                }
            }
        }
    }
}
