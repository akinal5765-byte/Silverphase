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
                    Text(materialPair).font(.system(size: 12, weight: .semibold)).padding(.top, 8).padding(.bottom, 12)
                    MobileLatitudeGraph(latitude: latitude).padding(.bottom, 8)
                    section("场景置位")
                    placement("高光", key: "_placementHighlight", minimum: latitude.minimumHighlight)
                    placement("阴影", key: "_placementShadow", minimum: latitude.minimumShadow)
                    Button("自动适配胶片与相纸宽容度") {
                        document.setValues(["_placementHighlight": .double(latitude.suggestedHighlight), "_placementShadow": .double(latitude.suggestedShadow)])
                    }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(MobileStyle.accent).frame(minHeight: 44).disabled(!latitude.suggestionValid)
                } else {
                    Text(document.busy ? "正在测量当前胶片与相纸的宽容度…" : (document.value("_latitudeFailure")?.stringValue ?? "当前组合的宽容度测量不可用"))
                        .font(EditorDesign.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 64)
                }
                section("测光与曝光")
                choice("测光模式", "_meter", [("custom", "手动"), ("balanced", "均衡"), ("center", "中央"), ("protect_highlights", "保护高光"), ("protect_shadows", "保护阴影"), ("center_weighted", "中央加权")])
                number("曝光补偿 · EV", "exposure_compensation_ev", -4...4)
                section("白平衡")
                if document.value("_raw")?.boolValue == true {
                    choice("白平衡预设", "_whiteBalancePreset", [("asShot", "拍摄时"), ("daylight", "日光"), ("cloudy", "多云"), ("shade", "阴影"), ("tungsten", "钨丝灯"), ("fluorescent", "荧光灯"), ("custom", "自定")])
                    number("色温 · K", "_temperature", 2000...12000)
                    asShotAxis("色温使用拍摄时设置", key: "_temperature")
                    number("色调", "_tint", -150...150)
                    asShotAxis("色调使用拍摄时设置", key: "_tint")
                    Button(document.pickingNeutral ? "取消中性点取样" : "取中性点", systemImage: "eyedropper") { document.beginNeutralPick() }
                        .buttonStyle(.plain).font(EditorDesign.label).frame(minHeight: EditorDesign.hitSize)
                    if document.pickingNeutral { Text("在完整原图上轻点中性色区域").font(EditorDesign.caption).foregroundStyle(.secondary) }
                    Button("恢复拍摄时白平衡") { document.resetKeys(["_temperature", "_tint"]) }
                        .buttonStyle(.plain).font(.system(size: 12)).frame(minHeight: 44)
                } else {
                    Text("此文件已完成白平衡；RAW 可调整拍摄色温与色调。").font(.system(size: 11)).foregroundStyle(.secondary).padding(.vertical, 8)
                }
                section("镜头与柔化")
                if document.value("_lensSupported")?.boolValue == true {
                    Button { document.setDiscrete("_lens", .bool(!(document.value("_lens")?.boolValue ?? false))) } label: {
                        HStack { Text("镜头校正"); Spacer(); Image(systemName: document.value("_lens")?.boolValue == true ? "checkmark.square.fill" : "square") }.font(.system(size: 12)).frame(minHeight: 44)
                    }.buttonStyle(.plain)
                }
                choice("光谱滤镜", "camera_filter", [("", "关闭"), ("w8", "8号 · 黄"), ("w11", "11号 · 黄绿"), ("w12", "12号 · 深黄"), ("w15", "15号 · 深黄"), ("w21", "21号 · 橙"), ("w25", "25号 · 红"), ("w47", "47号 · 蓝"), ("w58", "58号 · 绿")])
                diffusion("拍摄柔化", prefix: "camera")
            case .film:
                section("画幅")
                choice("胶片画幅", "_filmFrame", MobileProcessContract.frames.map { ($0.id, $0.id == "Custom" ? "自定" : $0.id) })
                choice("参考边", "_filmSide", [("short", "短边"), ("long", "长边")])
                choice("长度单位", "_sideUnit", [("mm", "mm"), ("cm", "cm"), ("inch", "inch")])
                sideLength
                    .disabled(document.value("_filmFrame")?.stringValue != "Custom")
                section("颗粒与光晕")
                flag("颗粒", "grain_active")
                Group {
                    number("颗粒强度 · 倍率", "_grainAmount", 0...2)
                    flag("分层颗粒", "grain_sublayers_active").disabled(MobileProcessContract.ownGrain(document.value("film_stock")?.stringValue ?? "") != 1)
                    number("颗粒尺度", "grain_size_scale", 0.5...2)
                    number("颗粒柔化 · 倍率", "_grainSoftness", 0...2)
                }.disabled(document.value("grain_active")?.boolValue == false)
                choice("晕光", "_halation", [("profile", "跟随胶片"), ("none", "高"), ("weak", "中"), ("strong", "低"), ("off", "关闭")])
                Group {
                    number("晕光强度", "halation_amount", 0...4)
                    number("乳剂散射", "halation_scatter_amount", 0...1)
                }.disabled(document.value("halation_active")?.boolValue == false)
            case .development:
                section("负片响应")
                number("显影反差", "density_curve_gamma", 0.5...1.5)
                flag("色彩分离", "dir_couplers_active").disabled(filmIsMonochrome)
                number("分离强度", "dir_couplers_amount", 0...1.4)
                    .disabled(document.value("dir_couplers_active")?.boolValue == false || filmIsMonochrome)
            case .print:
                flag("直接扫描胶片", "scan_film")
                flag("数字中间片", "digital_intermediate")
                if document.value("scan_film")?.boolValue != true && document.value("digital_intermediate")?.boolValue != true {
                    section("曝光与滤色")
                    printBrightness
                    number("印相反差", "print_contrast", 0.7...1.3)
                    if document.value("print_stock")?.stringValue == "ilford_multigrade_iv_rc" {
                        paperGrades
                    } else {
                        number("黄色滤光", "y_filter_shift", -50...50)
                        number("品红滤光", "m_filter_shift", -50...50)
                    }
                    flag("印相效果", "_printEffects")
                    number("预闪", "preflash_exposure", 0...0.05, entryRange: 0...1).disabled(document.value("_printEffects")?.boolValue == false)
                    section("光学柔化")
                    diffusion("放大机柔化", prefix: "enlarger")
                } else {
                    Text("直接扫描与数字中间片绕过相纸印相。").font(.system(size: 11)).foregroundStyle(.secondary).padding(.vertical, 8)
                }
            case .output:
                section("扫描呈现")
                flag("扫描锐化", "_scannerActive").disabled(diActive)
                number("锐化强度 · 倍率", "_scannerStrength", 0...2)
                    .disabled(diActive || document.value("_scannerActive")?.boolValue == false)
                flag("印相眩光", "glare_active").disabled(printBypassed)
                number("眩光强度", "glare_amount", 0...4)
                    .disabled(printBypassed || document.value("glare_active")?.boolValue == false)
                flag("高光扩展", "extended_dynamic_range").disabled(printBypassed || paperIsMonochrome)
            case .filmEdge:
                section("片边")
                flag("显示片边", "overscan_active")
                choice("底片规格", "overscan_format", [("135", "135"), ("135_half", "135 半格"), ("120_645", "645"), ("120_6x6", "6×6"), ("120_6x7", "6×7"), ("120_6x8", "6×8"), ("120_6x9", "6×9"), ("135_xpan", "XPan"), ("120_6x12", "6×12"), ("120_6x17", "6×17")])
                choice("片边呈现", "overscan_mode", [("strip", "胶片条"), ("filed", "打磨片夹")])
                choice("片门", "overscan_gate", [("auto", "自动"), ("square", "方角"), ("rounded", "圆角"), ("eared", "耳形"), ("shouldered", "肩形"), ("kicked", "偏角")])
                choice("齿孔", "overscan_holes", [("white", "白"), ("black", "黑")])
                number("帧号 · 0 为自动", "overscan_frame_number", 0...99)
                number("边缘雾化", "overscan_fog", 0...4)
                number("漏光", "overscan_leaks", 0...4)
                choice("片夹", "overscan_carrier", [("none", "无"), ("black", "黑色"), ("open", "透光")])
                HStack {
                    Button("更换机身") { document.setDiscrete("overscan_camera_seed", .double(Double(Int.random(in: 1...999)))) }
                    Spacer()
                    Button("重新过片") { document.setDiscrete("overscan_frame_seed", .double(Double(Int.random(in: 1...999999)))) }
                }.font(EditorDesign.label).frame(minHeight: EditorDesign.hitSize).buttonStyle(.borderless)
                section("日期后背")
                flag("日期曝光", "date_imprint_active")
                text("日期文字", "date_imprint_text")
                choice("日期样式", "date_imprint_style", [("lcd", "数码管"), ("dots", "点阵"), ("data", "数据后背")])
                number("日期曝光 · EV", "date_imprint_ev", -2...8)
                number("日期尺寸", "date_imprint_size", 0.4...3)
                choice("日期格式", "_dateOrder", [("japan", "年 · 月 · 日"), ("us", "月 · 日 · 年")])
                flag("同时打印拍摄数据", "_dateWithData")
                choice("日期位置", "date_imprint_placement", [("frame", "画面内"), ("rebate", "片边")])
                choice("日期角落", "date_imprint_corner", [("br", "右下"), ("bl", "左下"), ("tr", "右上"), ("tl", "左上")])
                number("水平边距 · mm", "date_imprint_inset_x", 0...30)
                number("垂直边距 · mm", "date_imprint_inset_y", 0...30)
                Text("未填文字时使用照片的 EXIF 拍摄日期；无拍摄日期时不打印。120 日期需要片边，全景画幅不支持日期背。")
                    .font(EditorDesign.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.vertical, 8)
            case .geometry:
                section("构图")
                MobileCropControls(document: document)
            }
        }.disabled(document.current == nil || document.resolved.isEmpty || document.delivering)
    }
    private var materialPair: String {
        let film = document.value("film_stock")?.stringValue.flatMap { StockCatalog.shared.stock($0)?.name } ?? "胶片"
        if document.value("scan_film")?.boolValue == true { return film }
        if document.value("digital_intermediate")?.boolValue == true { return film + " · 数字中间片" }
        let paper = document.value("print_stock")?.stringValue.flatMap { StockCatalog.shared.stock($0)?.name } ?? "相纸"
        return film + " · " + paper
    }
    private var filmIsMonochrome: Bool {
        document.value("film_stock")?.stringValue.flatMap { StockCatalog.shared.stock($0) }?.isMonochrome == true
    }
    private func section(_ title: String) -> some View {
        HStack { Text(title).font(.system(size: 12, weight: .semibold)); Spacer() }
            .padding(.top, 18).padding(.bottom, 8)
    }
    private func placement(_ title: String, key: String, minimum: Double) -> some View {
        RulerParameterRow(title: title, value: Binding(get: { document.value(key)?.doubleValue ?? 0 }, set: {
            document.set(key, .double($0 < max(0.15, minimum) / 2 ? 0 : max(minimum, $0)))
        }), range: 0...12, defaultValue: 0, step: 0.25, onInteraction: document.parameterInteraction, onReset: { document.resetKeys([key]) })
    }
    private func diffusion(_ title: String, prefix: String) -> some View {
        Group {
            choice(title, "_" + prefix + "Diffusion", [("off", "关闭"), ("glimmerglass", "Glimmerglass"), ("black_pro_mist", "Black Pro-Mist"), ("pro_mist", "Pro-Mist"), ("cinebloom", "Cinebloom")])
            Group {
                number("柔化强度", prefix + "_diffusion_strength", 0.125...2)
                number("光晕范围", prefix + "_diffusion_range", 0.5...2)
            }.disabled(document.value(prefix + "_diffusion_active")?.boolValue != true)
        }
    }
    private var diActive: Bool { document.value("digital_intermediate")?.boolValue == true && document.value("scan_film")?.boolValue != true }
    private var printBypassed: Bool { diActive || document.value("scan_film")?.boolValue == true }
    private var paperIsMonochrome: Bool { document.value("print_stock")?.stringValue.flatMap { StockCatalog.shared.stock($0) }?.isMonochrome == true }
    private var sideLength: some View {
        let unit = document.value("_sideUnit")?.stringValue ?? "mm"
        let factor = unit == "inch" ? 25.4 : unit == "cm" ? 10.0 : 1.0
        return RulerParameterRow(title: "参考边长度 · " + unit, value: Binding(get: { (document.value("_sideLengthMM")?.doubleValue ?? 24) / factor }, set: { document.set("_sideLengthMM", .double($0 * factor)) }), range: (4 / factor)...(200 / factor), defaultValue: (document.defaultNumber("_sideLengthMM") ?? 24) / factor, fractionDigits: unit == "inch" ? 3 : 1, onInteraction: document.parameterInteraction, onReset: { document.resetKeys(["_sideLengthMM"]) })
    }
    private func asShotAxis(_ title: String, key: String) -> some View {
        Button { document.resetKeys([key]) } label: {
            HStack { Text(title); Spacer(); Image(systemName: document.current?.recipe[key] == nil ? "checkmark.square.fill" : "square") }
                .font(EditorDesign.caption).frame(minHeight: 32)
        }.buttonStyle(.plain)
    }
    private var printBrightness: some View {
        RulerParameterRow(title: "印相亮度 · EV", value: Binding(get: { document.value("_printBrightnessStops")?.doubleValue ?? 0 }, set: { document.set("_printBrightnessStops", .double($0)) }), range: -3...3, defaultValue: 0, step: 0.25, onInteraction: document.parameterInteraction, onReset: { document.resetKeys(["_printBrightnessStops", "print_exposure"]) })
    }
    private var paperGrades: some View {
        Menu {
            Picker("相纸等级", selection: Binding(get: { document.value("_paperGrade")?.stringValue ?? "2" }, set: applyPaperGrade)) {
                ForEach(["00", "0", "1", "2", "3", "4", "5"], id: \.self) { Text($0).tag($0) }
            }
        } label: {
            HStack { Text("相纸等级"); Spacer(); Text(document.value("_paperGrade")?.stringValue ?? "2"); Image(systemName: "chevron.up.chevron.down") }.font(EditorDesign.label).frame(minHeight: EditorDesign.hitSize)
        }.tint(.primary)
    }
    private func applyPaperGrade(_ grade: String) {
        document.setDiscrete("_paperGrade", .string(grade))
    }
    @ViewBuilder private func text(_ title: String, _ key: String) -> some View {
        if let value = document.value(key)?.stringValue {
            HStack { Text(title); TextField(title, text: Binding(get: { document.value(key)?.stringValue ?? value }, set: { document.setDiscrete(key, .string($0)) })).textFieldStyle(.plain).multilineTextAlignment(.trailing) }
                .font(.system(size: 12)).frame(minHeight: 44)
        }
    }
    @ViewBuilder private func number(_ title: String, _ key: String, _ range: ClosedRange<Double>, entryRange: ClosedRange<Double>? = nil) -> some View {
        if let value = document.value(key)?.doubleValue {
            let baseline = document.defaultNumber(key) ?? range.lowerBound
            let rulerRange = min(range.lowerBound, baseline)...max(range.upperBound, baseline)
            RulerParameterRow(title: title, value: Binding(get: { document.value(key)?.doubleValue ?? value }, set: { document.set(key, .double($0)) }), range: rulerRange, defaultValue: baseline, fractionDigits: key == "_temperature" || key == "overscan_frame_number" ? 0 : key == "preflash_exposure" ? 3 : 2, entryRange: entryRange, step: MobileProcessContract.steps[key], onInteraction: document.parameterInteraction, onReset: { document.resetKeys([key]) })
        }
    }
    @ViewBuilder private func flag(_ title: String, _ key: String) -> some View {
        if let value = document.value(key)?.boolValue {
            Button { document.setDiscrete(key, .bool(!value)) } label: {
                HStack {
                    Text(title).font(EditorDesign.label).foregroundStyle(.secondary)
                    Spacer()
                    ZStack {
                        RoundedRectangle(cornerRadius: 3).strokeBorder(value ? MobileStyle.accent : .white.opacity(0.3), lineWidth: 1)
                        if value { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(MobileStyle.accent) }
                    }.frame(width: 14, height: 14)
                }.frame(height: MobileStyle.row).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(title).accessibilityValue(value ? "已开启" : "已关闭")
        }
    }
    @ViewBuilder private func choice(_ title: String, _ key: String, _ options: [(String, String)]) -> some View {
        if let value = document.value(key)?.stringValue {
            HStack(spacing: 8) {
                Text(title).font(EditorDesign.label).foregroundStyle(.secondary)
                    .frame(width: EditorDesign.labelWidth, alignment: .leading)
                Menu {
                    Picker(title, selection: Binding(get: { document.value(key)?.stringValue ?? value }, set: { document.setDiscrete(key, .string($0)) })) {
                        ForEach(options, id: \.0) { option in Text(option.1).tag(option.0) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(options.first { $0.0 == value }?.1 ?? value).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .medium))
                    }.font(EditorDesign.label).frame(maxWidth: .infinity, minHeight: EditorDesign.hitSize)
                }.accessibilityLabel(title).tint(.primary)
            }.frame(height: EditorDesign.hitSize)
        }
    }
}
