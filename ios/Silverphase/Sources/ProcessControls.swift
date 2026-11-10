import SwiftUI

struct ProcessControls: View {
    @Bindable var document: MobileDocument
    @Environment(MobileOverlays.self) private var overlays
    let stage: MobileStage
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch stage {
            case .camera:
                if let latitude = document.latitude {
                    Text(materialPair).font(EditorDesign.panelSummary).foregroundStyle(MobileStyle.secondaryText).padding(.top, 8).padding(.bottom, 12)
                    MobileLatitudeGraph(latitude: latitude).padding(.bottom, 8)
                } else {
                    Text(document.busy ? T("Measuring the latitude of this film and paper…", "正在测量当前胶片与相纸的宽容度…", "正在測量目前膠片與相紙的寬容度…") : (document.value("_latitudeFailure")?.stringValue ?? T("No latitude measurement is available for this pairing", "当前组合的宽容度测量不可用", "目前組合的寬容度測量不可用")))
                        .font(EditorDesign.help).foregroundStyle(MobileStyle.secondaryText).frame(maxWidth: .infinity, minHeight: 64)
                }
                if (document.value("_placementHighlight")?.doubleValue ?? 0) > 0 ||
                    (document.value("_placementShadow")?.doubleValue ?? 0) > 0 {
                    Button(T("Clear old scene placement", "清除旧场景置位", "清除舊場景置位")) {
                        document.resetKeys(["_placementHighlight", "_placementShadow"])
                    }.buttonStyle(.plain).font(EditorDesign.parameter).frame(minHeight: EditorDesign.hitSize)
                }
                section(T("Metering & Exposure", "测光与曝光", "測光與曝光"))
                choice(T("Metering Mode", "测光模式", "測光模式"), "_meter", MobileMeteringMode.allCases.map { ($0.rawValue, $0.title) })
                number(T("Exposure Compensation · EV", "曝光补偿 · EV", "曝光補償 · EV"), "exposure_compensation_ev", -4...4)
                section(T("Tone", "影调", "影調"))
                number(T("Highlights", "高光", "高光"), "camera_tone_highlights", MobileProcessContract.cameraToneRange, fractionDigits: 0)
                number(T("Shadows", "阴影", "陰影"), "camera_tone_shadows", MobileProcessContract.cameraToneRange, fractionDigits: 0)
                number(T("Whites", "白色色阶", "白色色階"), "camera_tone_whites", MobileProcessContract.cameraToneRange, fractionDigits: 0)
                number(T("Blacks", "黑色色阶", "黑色色階"), "camera_tone_blacks", MobileProcessContract.cameraToneRange, fractionDigits: 0)
                Button(T("Reset Tone", "重置影调", "重設影調")) { document.resetKeys(MobileProcessContract.cameraToneKeys) }
                    .buttonStyle(.plain).font(EditorDesign.parameter).frame(minHeight: EditorDesign.hitSize)
                section(T("White Balance", "白平衡", "白平衡"))
                if document.value("_raw")?.boolValue == true {
                    choice(T("White Balance Preset", "白平衡预设", "白平衡預設"), "_whiteBalancePreset", [("asShot", T("As Shot", "拍摄时", "拍攝時")), ("daylight", T("Daylight", "日光", "日光")), ("cloudy", T("Cloudy", "多云", "多雲")), ("shade", T("Shade", "阴影", "陰影")), ("tungsten", T("Tungsten", "钨丝灯", "鎢絲燈")), ("fluorescent", T("Fluorescent", "荧光灯", "螢光燈")), ("custom", T("Custom", "自定", "自定"))])
                    number(T("Temperature · K", "色温 · K", "色溫 · K"), "_temperature", 2000...12000)
                    asShotAxis(T("Temperature as shot", "色温使用拍摄时设置", "色溫使用拍攝時設定"), key: "_temperature")
                    number(T("Tint", "色调", "色調"), "_tint", -150...150)
                    asShotAxis(T("Tint as shot", "色调使用拍摄时设置", "色調使用拍攝時設定"), key: "_tint")
                    Button(document.pickingNeutral ? T("Cancel neutral pick", "取消中性点取样", "取消中性點取樣") : T("Pick neutral", "取中性点", "取中性點"), systemImage: "eyedropper") { document.beginNeutralPick() }
                        .buttonStyle(.plain).font(EditorDesign.parameter).frame(minHeight: EditorDesign.hitSize)
                    if document.pickingNeutral { Text(T("Tap a neutral area on the full original", "在完整原图上轻点中性色区域", "在完整原圖上輕點中性色區域")).font(EditorDesign.help).foregroundStyle(MobileStyle.secondaryText) }
                    Button(T("Restore as-shot white balance", "恢复拍摄时白平衡", "恢復拍攝時白平衡")) { document.resetKeys(["_temperature", "_tint"]) }
                        .buttonStyle(.plain).font(EditorDesign.parameter).frame(minHeight: 44)
                } else {
                    Text(T("White balance is baked into this file. A RAW capture allows the as-shot temperature and tint to be changed.", "此文件已完成白平衡；RAW 可调整拍摄色温与色调。", "此檔案已完成白平衡；RAW 可調整拍攝色溫與色調。")).font(EditorDesign.help).foregroundStyle(MobileStyle.secondaryText).padding(.vertical, 8)
                }
                section(T("Lens & Diffusion", "镜头与柔光", "鏡頭與柔光"))
                if document.value("_lensSupported")?.boolValue == true {
                    Button { document.setDiscrete("_lens", .bool(!(document.value("_lens")?.boolValue ?? false))) } label: {
                        HStack { Text(T("Lens Correction", "镜头校正", "鏡頭校正")).foregroundStyle(MobileStyle.secondaryText); Spacer(); Image(systemName: document.value("_lens")?.boolValue == true ? "checkmark.square.fill" : "square") }.font(EditorDesign.parameter).frame(minHeight: 44)
                    }.buttonStyle(.plain)
                }
                choice(T("Colour Filter", "光谱滤镜", "光譜濾鏡"), "camera_filter", [("", T("Off", "关闭", "關閉")), ("w8", T("No. 8 · Yellow", "8号 · 黄", "8號 · 黃")), ("w11", T("No. 11 · Yellow-Green", "11号 · 黄绿", "11號 · 黃綠")), ("w12", T("No. 12 · Deep Yellow", "12号 · 深黄", "12號 · 深黃")), ("w15", T("No. 15 · Deep Yellow", "15号 · 深黄", "15號 · 深黃")), ("w21", T("No. 21 · Orange", "21号 · 橙", "21號 · 橙")), ("w25", T("No. 25 · Red", "25号 · 红", "25號 · 紅")), ("w47", T("No. 47 · Blue", "47号 · 蓝", "47號 · 藍")), ("w58", T("No. 58 · Green", "58号 · 绿", "58號 · 綠"))])
                diffusion(T("Shooting Diffusion", "拍摄柔光", "拍攝柔光"), prefix: "camera")
            case .film:
                section(T("Frame", "画幅", "畫幅"))
                choice(T("Film Format", "胶片规格", "膠片規格"), "_filmFrame", MobileProcessContract.frames.map { ($0.id, $0.id == "Custom" ? T("Custom", "自定", "自定") : $0.id) })
                choice(T("Size Basis", "尺寸基准", "尺寸基準"), "_filmSide", [("short", T("Short", "短边", "短邊")), ("long", T("Long", "长边", "長邊"))])
                choice(T("Length Unit", "长度单位", "長度單位"), "_sideUnit", [("mm", "mm"), ("cm", "cm"), ("inch", "inch")])
                sideLength
                    .disabled(document.value("_filmFrame")?.stringValue != "Custom")
                section(T("Grain & Halation", "颗粒与光晕", "顆粒與光暈"))
                flag(T("Grain", "颗粒", "顆粒"), "grain_active")
                Group {
                    number(T("Grain Strength · ×", "颗粒强度 · 倍率", "顆粒強度 · 倍率"), "_grainAmount", 0...2)
                    flag(T("Sub-layers", "分层颗粒", "分層顆粒"), "grain_sublayers_active").disabled(MobileProcessContract.ownGrain(document.value("film_stock")?.stringValue ?? "") != 1)
                    number(T("Grain Size", "颗粒尺度", "顆粒尺度"), "grain_size_scale", 0.5...2)
                    number(T("Grain Softness · ×", "颗粒柔化 · 倍率", "顆粒柔化 · 倍率"), "_grainSoftness", 0...2)
                }.disabled(document.value("grain_active")?.boolValue == false)
                choice(T("Film Halation", "胶片光晕", "膠片光暈"), "_halation", [("profile", T("Follow film", "跟随胶片", "跟隨膠片")), ("none", T("High", "高", "高")), ("weak", T("Medium", "中", "中")), ("strong", T("Low", "低", "低")), ("off", T("Off", "关闭", "關閉"))])
                Group {
                    number(T("Halation Strength", "光晕强度", "光暈強度"), "halation_amount", 0...4)
                    if document.value("film_stock")?.stringValue == "cinestill_800t" {
                        number(T("Highlight Headroom · EV", "高光余量 · EV", "高光餘量 · EV"), "halation_headroom_ev", 0...8)
                            .disabled(document.value("_halation")?.stringValue != "profile" || document.value("halation_amount")?.doubleValue == 0)
                    }
                    number(T("Scatter", "散射", "散射"), "halation_scatter_amount", 0...1)
                }.disabled(document.value("halation_active")?.boolValue == false)
            case .development:
                section(T("Negative Response", "负片响应", "負片響應"))
                number(T("Development Contrast", "显影反差", "顯影反差"), "density_curve_gamma", 0.5...1.5)
                flag(T("DIR Effect", "DIR 效应", "DIR 效應"), "dir_couplers_active").disabled(filmIsMonochrome)
                number(T("Couplers Strength", "成色剂强度", "成色劑強度"), "dir_couplers_amount", 0...1.4)
                    .disabled(document.value("dir_couplers_active")?.boolValue == false || filmIsMonochrome)
            case .print:
                flag(T("Scan Film Directly", "直接扫描胶片", "直接掃描膠片"), "scan_film")
                flag(T("Digital Intermediate", "数字中间片", "數位中間片"), "digital_intermediate")
                if document.value("scan_film")?.boolValue != true && document.value("digital_intermediate")?.boolValue != true {
                    section(T("Exposure & Filtration", "曝光与滤色", "曝光與濾色"))
                    printBrightness
                    number(T("Paper Contrast", "相纸反差", "相紙反差"), "print_contrast", 0.7...1.3)
                    if document.value("print_stock")?.stringValue == "ilford_multigrade_iv_rc" {
                        paperGrades
                    } else {
                        number(T("Yellow (Y)", "黄滤色（Y）", "黃濾色（Y）"), "y_filter_shift", -50...50)
                        number(T("Magenta (M)", "品红滤色（M）", "品紅濾色（M）"), "m_filter_shift", -50...50)
                    }
                    flag(T("Print Effects", "相纸效果", "相紙效果"), "_printEffects")
                    number(T("Pre-flash", "相纸预闪", "相紙預閃"), "preflash_exposure", 0...0.05, entryRange: 0...1).disabled(document.value("_printEffects")?.boolValue == false)
                    diffusion(T("Soft-Focus Enlargement", "柔光放大", "柔光放大"), prefix: "enlarger")
                } else {
                    Text(T("Direct scan and Digital Intermediate bypass the paper print.", "直接扫描与数字中间片绕过相纸印相。", "直接掃描與數位中間片繞過相紙印相。")).font(EditorDesign.help).foregroundStyle(MobileStyle.secondaryText).padding(.vertical, 8)
                }
            case .output:
                section(T("Scan Rendering", "扫描呈现", "掃描呈現"))
                flag(T("Scan Sharpening", "扫描锐化", "掃描銳化"), "_scannerActive").disabled(diActive)
                number(T("Sharpening Strength · ×", "锐化强度 · 倍率", "銳化強度 · 倍率"), "_scannerStrength", 0...2)
                    .disabled(diActive || document.value("_scannerActive")?.boolValue == false)
                flag(T("Paper Glare", "相纸眩光", "相紙眩光"), "glare_active").disabled(printBypassed)
                number(T("Glare Strength", "耀光强度", "耀光強度"), "glare_amount", 0...4)
                    .disabled(printBypassed || document.value("glare_active")?.boolValue == false)
                flag(T("Highlight Expansion", "高光层次展开", "高光層次展開"), "extended_dynamic_range").disabled(printBypassed || paperIsMonochrome)
            case .filmEdge:
                section(T("Film Edge", "片边", "片邊"))
                flag(T("Show Film Edge", "显示片边", "顯示片邊"), "overscan_active")
                choice(T("Negative Format", "底片规格", "底片規格"), "overscan_format", [("135", "135"), ("135_half", T("135 half-frame", "135 半格", "135 半格")), ("120_645", "645"), ("120_6x6", "6×6"), ("120_6x7", "6×7"), ("120_6x8", "6×8"), ("120_6x9", "6×9"), ("135_xpan", "XPan"), ("120_6x12", "6×12"), ("120_6x17", "6×17")])
                choice(T("Edge Rendering", "片边呈现", "片邊呈現"), "overscan_mode", [("strip", T("Film strip", "胶片条", "膠片條")), ("filed", T("Filed carrier", "打磨片夹", "打磨片夾"))])
                choice(T("Gate", "片门", "片門"), "overscan_gate", [("auto", T("Auto", "自动", "自動")), ("square", T("Square", "方角", "方角")), ("rounded", T("Rounded", "圆角", "圓角")), ("eared", T("Eared", "耳形", "耳形")), ("shouldered", T("Shouldered", "肩形", "肩形")), ("kicked", T("Kicked", "偏角", "偏角"))])
                choice(T("Sprocket holes", "齿孔", "齒孔"), "overscan_holes", [("white", T("White", "白", "白")), ("black", T("Black", "黑", "黑"))])
                number(T("Frame number · 0 = auto", "帧号 · 0 为自动", "幀號 · 0 為自動"), "overscan_frame_number", 0...99)
                number(T("Edge fog", "边缘雾化", "邊緣霧化"), "overscan_fog", 0...4)
                number(T("Light leaks", "漏光", "漏光"), "overscan_leaks", 0...4)
                choice(T("Carrier", "片夹", "片夾"), "overscan_carrier", [("none", T("None", "无", "無")), ("black", T("Black", "黑色", "黑色")), ("open", T("Open", "透光", "透光"))])
                HStack {
                    Button(T("Change Body", "更换机身", "更換機身")) { document.setDiscrete("overscan_camera_seed", .double(Double(Int.random(in: 1...999)))) }
                    Spacer()
                    Button(T("Advance Film", "重新过片", "重新過片")) { document.setDiscrete("overscan_frame_seed", .double(Double(Int.random(in: 1...999999)))) }
                }.font(EditorDesign.parameter).frame(minHeight: EditorDesign.hitSize).buttonStyle(.borderless)
                section(T("Date Back", "日期背", "日期背"))
                flag(T("Date Exposure", "日期曝光", "日期曝光"), "date_imprint_active")
                text(T("Date Text", "日期文字", "日期文字"), "date_imprint_text")
                choice(T("Date Style", "日期样式", "日期樣式"), "date_imprint_style", [("lcd", T("LCD", "数码管", "數碼管")), ("dots", T("Dot matrix", "点阵", "點陣")), ("data", T("Data back", "数据后背", "數據後背"))])
                number(T("Date Exposure · EV", "日期曝光 · EV", "日期曝光 · EV"), "date_imprint_ev", -2...8)
                number(T("Date Size", "日期尺寸", "日期尺寸"), "date_imprint_size", 0.4...3)
                choice(T("Date Format", "日期格式", "日期格式"), "_dateOrder", [("japan", T("Y · M · D", "年 · 月 · 日", "年 · 月 · 日")), ("us", T("M · D · Y", "月 · 日 · 年", "月 · 日 · 年"))])
                flag(T("Also print capture data", "同时打印拍摄数据", "同時列印拍攝數據"), "_dateWithData")
                choice(T("Date Position", "日期位置", "日期位置"), "date_imprint_placement", [("frame", T("In frame", "画面内", "畫面內")), ("rebate", T("Film Edge", "片边", "片邊"))])
                choice(T("Date Corner", "日期角落", "日期角落"), "date_imprint_corner", [("br", T("Bottom right", "右下", "右下")), ("bl", T("Bottom left", "左下", "左下")), ("tr", T("Top right", "右上", "右上")), ("tl", T("Top left", "左上", "左上"))])
                number(T("Horizontal Inset · mm", "水平边距 · mm", "水平邊距 · mm"), "date_imprint_inset_x", 0...30)
                number(T("Vertical Inset · mm", "垂直边距 · mm", "垂直邊距 · mm"), "date_imprint_inset_y", 0...30)
                Text(T("Empty text uses the photo's EXIF capture date, and nothing is printed when there is none. A 120 date needs the rebate, and panoramic formats have no date back.", "未填文字时使用照片的 EXIF 拍摄日期；无拍摄日期时不打印。120 日期需要片边，全景画幅不支持日期背。", "未填文字時使用照片的 EXIF 拍攝日期；無拍攝日期時不列印。120 日期需要片邊，全景畫幅不支援日期背。"))
                    .font(EditorDesign.help).foregroundStyle(MobileStyle.secondaryText).fixedSize(horizontal: false, vertical: true).padding(.vertical, 8)
            case .geometry:
                section(T("Composition", "构图", "構圖"))
                MobileCropControls(document: document)
            }
        }.disabled(document.current == nil || document.resolved.isEmpty || document.delivering)
    }
    private var materialPair: String {
        let film = document.value("film_stock")?.stringValue.flatMap { StockCatalog.shared.stock($0)?.name } ?? T("Film", "胶片", "膠片")
        if document.value("scan_film")?.boolValue == true { return film }
        if document.value("digital_intermediate")?.boolValue == true { return film + T(" · Digital Intermediate", " · 数字中间片", " · 數位中間片") }
        let paper = document.value("print_stock")?.stringValue.flatMap { StockCatalog.shared.stock($0)?.name } ?? T("Paper", "相纸", "相紙")
        return film + " · " + paper
    }
    private var filmIsMonochrome: Bool {
        document.value("film_stock")?.stringValue.flatMap { StockCatalog.shared.stock($0) }?.isMonochrome == true
    }
    private func section(_ title: String) -> some View {
        ToolSectionTitle(title: title)
    }
    private func diffusion(_ title: String, prefix: String) -> some View {
        Group {
            choice(title, "_" + prefix + "Diffusion", MobileDiffusionFilter.allCases.map { ($0.rawValue, $0.title) })
            Group {
                number(T("Diffusion Strength", "柔光强度", "柔光強度"), prefix + "_diffusion_strength", 0.125...2)
                number(T("Diffusion Spread", "扩散范围", "擴散範圍"), prefix + "_diffusion_range", 0.5...2)
            }.disabled(document.value(prefix + "_diffusion_active")?.boolValue != true)
        }
    }
    private var diActive: Bool { document.value("digital_intermediate")?.boolValue == true && document.value("scan_film")?.boolValue != true }
    private var printBypassed: Bool { diActive || document.value("scan_film")?.boolValue == true }
    private var paperIsMonochrome: Bool { document.value("print_stock")?.stringValue.flatMap { StockCatalog.shared.stock($0) }?.isMonochrome == true }
    private var sideLength: some View {
        let unit = document.value("_sideUnit")?.stringValue ?? "mm"
        let factor = unit == "inch" ? 25.4 : unit == "cm" ? 10.0 : 1.0
        return RulerParameterRow(title: T("Reference Size · ", "基准尺寸 · ", "基準尺寸 · ") + unit, value: Binding(get: { (document.value("_sideLengthMM")?.doubleValue ?? 24) / factor }, set: { document.set("_sideLengthMM", .double($0 * factor)) }), range: (4 / factor)...(200 / factor), defaultValue: (document.defaultNumber("_sideLengthMM") ?? 24) / factor, fractionDigits: unit == "inch" ? 3 : 1, onInteraction: document.parameterInteraction, onReset: { document.resetKeys(["_sideLengthMM"]) })
    }
    private func asShotAxis(_ title: String, key: String) -> some View {
        Button { document.resetKeys([key]) } label: {
            HStack { Text(title); Spacer(); Image(systemName: document.current?.recipe[key] == nil ? "checkmark.square.fill" : "square") }
                .font(EditorDesign.parameter).foregroundStyle(MobileStyle.secondaryText).frame(minHeight: EditorDesign.hitSize)
        }.buttonStyle(.plain)
    }
    private var printBrightness: some View {
        RulerParameterRow(title: T("Enlarger Exposure · EV", "放大曝光 · EV", "放大曝光 · EV"), value: Binding(get: { document.value("_printBrightnessStops")?.doubleValue ?? 0 }, set: { document.set("_printBrightnessStops", .double($0)) }), range: -3...3, defaultValue: 0, step: 0.25, onInteraction: document.parameterInteraction, onReset: { document.resetKeys(["_printBrightnessStops", "print_exposure"]) })
    }
    private var paperGrades: some View {
        Menu {
            Picker(T("Paper Grade", "相纸等级", "相紙等級"), selection: Binding(get: { document.value("_paperGrade")?.stringValue ?? "2" }, set: applyPaperGrade)) {
                ForEach(["00", "0", "1", "2", "3", "4", "5"], id: \.self) { Text($0).tag($0) }
            }
        } label: {
            HStack { Text(T("Paper Grade", "相纸等级", "相紙等級")).foregroundStyle(MobileStyle.secondaryText); Spacer(); Text(document.value("_paperGrade")?.stringValue ?? "2").font(EditorDesign.selectedValue).monospacedDigit(); Image(systemName: "chevron.up.chevron.down") }.font(EditorDesign.parameter).frame(minHeight: EditorDesign.hitSize)
        }.tint(.primary)
    }
    private func applyPaperGrade(_ grade: String) {
        document.setDiscrete("_paperGrade", .string(grade))
    }
    @ViewBuilder private func text(_ title: String, _ key: String) -> some View {
        if let value = document.value(key)?.stringValue {
            HStack { Text(title).foregroundStyle(MobileStyle.secondaryText); TextField(title, text: Binding(get: { document.value(key)?.stringValue ?? value }, set: { document.setDiscrete(key, .string($0)) })).textFieldStyle(.plain).font(EditorDesign.selectedValue).multilineTextAlignment(.trailing) }
                .font(EditorDesign.parameter).frame(minHeight: 44)
        }
    }
    @ViewBuilder private func number(_ title: String, _ key: String, _ range: ClosedRange<Double>, entryRange: ClosedRange<Double>? = nil, fractionDigits: Int? = nil) -> some View {
        if let value = document.value(key)?.doubleValue {
            let baseline = document.defaultNumber(key) ?? range.lowerBound
            let rulerRange = min(range.lowerBound, baseline)...max(range.upperBound, baseline)
            RulerParameterRow(title: title, value: Binding(get: { document.value(key)?.doubleValue ?? value }, set: { document.set(key, .double($0)) }), range: rulerRange, defaultValue: baseline, fractionDigits: fractionDigits ?? (key == "_temperature" || key == "overscan_frame_number" ? 0 : key == "preflash_exposure" ? 3 : 2), entryRange: entryRange, step: MobileProcessContract.steps[key], onInteraction: document.parameterInteraction, onReset: { document.resetKeys([key]) })
        }
    }
    @ViewBuilder private func flag(_ title: String, _ key: String) -> some View {
        if let value = document.value(key)?.boolValue {
            Button { document.setDiscrete(key, .bool(!value)) } label: {
                HStack {
                    Text(title).font(EditorDesign.parameter).foregroundStyle(MobileStyle.secondaryText)
                    Spacer()
                    ZStack {
                        RoundedRectangle(cornerRadius: 3).strokeBorder(value ? MobileStyle.accent : .white.opacity(0.3), lineWidth: 1)
                        if value { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(MobileStyle.accent) }
                    }.frame(width: 14, height: 14)
                }.frame(height: MobileStyle.row).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(value ? T("On", "已开启", "已開啟") : T("Off", "已关闭", "已關閉"))
        }
    }
    @ViewBuilder private func choice(_ title: String, _ key: String, _ options: [(String, String)]) -> some View {
        if let value = document.value(key)?.stringValue {
            HStack(spacing: 8) {
                Text(title).font(EditorDesign.parameter).foregroundStyle(MobileStyle.secondaryText)
                    .frame(width: EditorDesign.labelWidth, alignment: .leading)
                Menu {
                    Picker(title, selection: Binding(get: { document.value(key)?.stringValue ?? value }, set: { document.setDiscrete(key, .string($0)) })) {
                        ForEach(options, id: \.0) { option in Text(option.1).tag(option.0) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(options.first { $0.0 == value }?.1 ?? value).font(EditorDesign.selectedValue).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .medium))
                    }.font(EditorDesign.parameter).frame(maxWidth: .infinity, minHeight: EditorDesign.hitSize)
                }.accessibilityLabel(title).tint(.primary)
            }.frame(height: EditorDesign.hitSize)
        }
    }
}
