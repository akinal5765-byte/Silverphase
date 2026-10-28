import SwiftUI

struct FilmEdgeSection: View {
    @Bindable var session: Session
    private func edge<V>(_ path: WritableKeyPath<FilmEdgeSettings, V>) -> Binding<V> {
        Binding(get: { session.params.filmEdge[keyPath: path] }, set: {
            var p = session.params; p.filmEdge[keyPath: path] = $0; session.params = p
        })
    }
    private func date<V>(_ path: WritableKeyPath<DateBackSettings, V>) -> Binding<V> {
        Binding(get: { session.params.dateBack[keyPath: path] }, set: {
            var p = session.params; p.dateBack[keyPath: path] = $0; session.params = p
        })
    }
    private func gateTitle(_ gate: FilmEdgeGate) -> String {
        switch gate {
        case .auto: T("Auto", "自动")
        case .square: T("Square", "直角")
        case .rounded: T("Rounded", "圆角")
        case .eared: T("Eared", "耳形")
        case .shouldered: T("Shouldered", "肩形")
        case .kicked: T("Kicked", "斜角")
        }
    }
    private func cornerTitle(_ corner: DateBackCorner) -> String {
        switch corner {
        case .br: T("Bottom Right", "右下")
        case .bl: T("Bottom Left", "左下")
        case .tr: T("Top Right", "右上")
        case .tl: T("Top Left", "左上")
        }
    }
    var body: some View {
        PanelSection(T("Film Edge", "片边"), key: "filmEdge") {
            RailRows {
                ToggleRow(label: T("Film Edge", "显示片边"), isOn: edge(\.active))
                PillMenu(label: T("Format", "画幅"), options: FilmEdgeFormat.allCases,
                         title: { $0 == .f135Half ? T("135 · Half-frame", "135 · 半格") : $0 == .xpan ? "135 · XPan" : $0.rawValue.replacingOccurrences(of: "120_", with: "120 · ") }, selection: edge(\.format))
                    .disabled(session.halfFramePair != nil)
                PillMenu(label: T("View", "范围"), options: FilmEdgeView.allCases,
                         title: { $0 == .strip ? T("Full Strip", "完整片宽") : T("Filed Gate", "画框边缘") }, selection: edge(\.view))
                PillMenu(label: T("Gate", "画框"), options: FilmEdgeGate.allCases,
                         title: { gateTitle($0) }, selection: edge(\.gate))
                PillMenu(label: T("Holes", "齿孔"), options: FilmEdgeHoles.allCases,
                         title: { $0 == .white ? T("Scan Light", "扫描光源") : T("Black", "黑色背板") }, selection: edge(\.holes))
                PillMenu(label: T("Carrier", "片夹"), options: ["none", "black", "open"],
                         title: { $0 == "none" ? T("None", "无") : $0 == "black" ? T("Black", "黑色") : T("Open", "透光") }, selection: edge(\.carrier))
                ScrubSlider(label: T("Frame", "帧号"), value: Binding(get: { Double(session.params.filmEdge.frameNumber) }, set: { var p = session.params; p.filmEdge.frameNumber = Int($0); session.params = p }), range: 0...99, snap: 1, format: { $0 == 0 ? T("Auto", "自动") : String(Int($0)) })
                ScrubSlider(label: T("Edge Fog", "边缘灰雾"), value: edge(\.fog), range: 0...4, zero: 1)
                ScrubSlider(label: T("Light Leaks", "漏光"), value: edge(\.leaks), range: 0...4)
                HStack {
                    Button(T("Another Body", "更换机身")) { var p = session.params; p.filmEdge.cameraSeed = Int.random(in: 1...999); session.params = p }
                    Button(T("Advance Film", "重新过片")) { var p = session.params; p.filmEdge.frameSeed = Int.random(in: 1...999999); session.params = p }
                }.buttonStyle(.borderless)
            }
            .help(T("The picture is cropped to the selected gate before exposure; grain and markings develop with the film.", "曝光前将画面裁切到所选画框；片边、标记与画面共同显影。"))
        }
        PanelSection(T("Date Back", "日期背"), key: "dateBack") {
            RailRows {
                ToggleRow(label: T("Date Back", "日期背"), isOn: date(\.active))
                PillMenu(label: T("Face", "字形"), options: DateBackFace.allCases, title: { $0 == .lcd ? "LCD" : $0 == .dots ? T("Dot Matrix", "点阵") : T("Shooting Data", "拍摄数据") }, selection: date(\.face))
                PillMenu(label: T("Order", "日期格式"), options: DateBackOrder.allCases, title: { $0 == .japan ? T("Year · Month · Day", "年 · 月 · 日") : T("Month · Day · Year", "月 · 日 · 年") }, selection: date(\.order))
                PillMenu(label: T("Placement", "位置"), options: DateBackPlacement.allCases, title: { $0 == .frame ? T("In Frame", "画面内") : T("Rebate", "片边") }, selection: date(\.placement))
                PillMenu(label: T("Corner", "角落"), options: DateBackCorner.allCases, title: { cornerTitle($0) }, selection: date(\.corner))
                TextField(T("EXIF date, or custom text", "EXIF 日期或自定义文字"), text: Binding(get: { session.params.dateBack.customText ?? "" }, set: { var p = session.params; p.dateBack.customText = $0.isEmpty ? nil : $0; session.params = p }))
                ToggleRow(label: T("Shooting Data", "拍摄数据"), isOn: date(\.withData))
                ScrubSlider(label: T("Exposure", "曝光"), value: date(\.brightnessEV), range: -2...8, zero: 3.5)
                ScrubSlider(label: T("Size", "尺寸"), value: date(\.size), range: 0.4...3, zero: 1)
                ScrubSlider(label: T("Horizontal", "水平边距"), value: date(\.insetXMM), range: 0...30, zero: 3)
                ScrubSlider(label: T("Vertical", "垂直边距"), value: date(\.insetYMM), range: 0...30, zero: 2.4)
            }
            .help(T("120 dates require a visible film margin. Panoramic formats have no date back. An absent EXIF date prints nothing.", "120 日期印在片边，需要打开片边；全景画幅不支持日期背。没有 EXIF 日期时不虚构日期。"))
        }
        HalfFramePairSection(session: session)
    }
}
