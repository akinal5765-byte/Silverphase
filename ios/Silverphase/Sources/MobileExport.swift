import SwiftUI
import UniformTypeIdentifiers

struct MobileExportPanel: View {
    @Bindable var document: MobileDocument
    let filteredIDs: [UUID]
    var fixedIDs: [UUID]? = nil
    @State private var selectingFolder = false
    private var recipe: Binding<MobileExportRecipe> { $document.exportRecipe }
    private var targets: [UUID] {
        if let fixedIDs { return fixedIDs.filter { id in document.photos.contains { $0.id == id } } }
        return switch document.exportRecipe.scope {
        case "all": document.photos.map(\.id)
        case "picked": document.photos.filter { $0.flag == "pick" }.map(\.id)
        case "filtered": filteredIDs
        default: document.selection.map { [$0] } ?? []
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ToolSectionTitle(title: T("Export Recipe", "导出配方", "匯出配方"))
            row(T("Recipe", "配方", "配方")) {
                Menu {
                    ForEach(document.exportPresets) { preset in Button(preset.displayName) { document.exportRecipe = preset } }
                    Divider()
                    Button(T("Save Current Recipe", "保存当前配方", "儲存目前配方")) {
                        var value = document.exportRecipe; value.id = UUID()
                        document.exportPresets.append(value); document.exportRecipe = value
                    }
                    Button(T("Restore Default Recipe", "恢复默认配方", "恢復預設配方")) { document.exportRecipe = MobileExportRecipe() }
                    Button(T("Delete Saved Recipe", "删除已保存配方", "刪除已儲存配方"), role: .destructive) { document.exportPresets.removeAll { $0.id == document.exportRecipe.id } }
                } label: { Text(document.exportRecipe.displayName); Image(systemName: "chevron.down") }
            }
            TextField(T("Recipe name", "配方名称", "配方名稱"), text: recipe.name).textFieldStyle(.roundedBorder).font(EditorDesign.parameter).padding(.vertical, 8)
            if let fixedIDs { Text(T("\(fixedIDs.count) photos selected", "已选 \(fixedIDs.count) 张照片", "已選 \(fixedIDs.count) 張照片")).accessibilityIdentifier("export.selected-count") }
            else {
                row(T("Export scope", "导出范围", "匯出範圍")) {
                    Picker(T("Export scope", "导出范围", "匯出範圍"), selection: recipe.scope) {
                        Text(T("Current photo", "当前照片", "目前照片")).tag("current"); Text(T("All photos", "全部照片", "全部照片")).tag("all"); Text(T("Picked photos", "已保留照片", "已保留照片")).tag("picked"); Text(T("Current filter", "当前筛选结果", "目前篩選結果")).tag("filtered")
                    }.labelsHidden()
                }
            }
            ToolSectionTitle(title: T("File & Colour", "文件与色彩", "檔案與色彩"))
            row(T("Format", "格式", "格式")) { Picker(T("Format", "格式", "格式"), selection: recipe.format) { ForEach(MobileExportFormat.allCases) { Text($0.title).tag($0) } }.labelsHidden() }
            row(T("Bit depth", "位深", "位深")) { Text(document.exportRecipe.format.isEightBit ? "8-bit" : "16-bit").monospacedDigit() }
            if document.exportRecipe.format != .di {
                row(T("Colour space", "色彩空间", "色彩空間")) {
                    Picker(T("Colour space", "色彩空间", "色彩空間"), selection: recipe.colorSpace) {
                        ForEach(MobileOutputSpace.allCases.filter { $0 != .prophoto || document.exportRecipe.format == .tiff }) { Text($0.rawValue).tag($0) }
                    }.labelsHidden()
                }
                if document.exportRecipe.format.hasLossyQuality {
                    RulerParameterRow(title: T("\(document.exportRecipe.format.title) quality · %", "\(document.exportRecipe.format.title) 质量 · %", "\(document.exportRecipe.format.title) 質量 · %"), value: Binding(get: { document.exportRecipe.quality * 100 }, set: { document.exportRecipe.quality = $0 / 100 }), range: 10...100, defaultValue: 95, fractionDigits: 0, step: 1, onReset: { document.exportRecipe.quality = 0.95 })
                }
            } else {
                Text(T("Cineon log, ProPhoto primaries, no embedded ICC. Output TIFF carries the same view LUT as both desktop front ends; positive film is not supported.", "Cineon 对数，ProPhoto 原色，不嵌入 ICC。输出 TIFF 与两个桌面端相同的视图 LUT；正片不支持。", "Cineon 對數，ProPhoto 原色，不嵌入 ICC。輸出 TIFF 與兩個桌面端相同的視圖 LUT；正片不支援。")).font(EditorDesign.help).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.vertical, 8)
            }
            ToolSectionTitle(title: T("Output Size", "输出尺寸", "輸出尺寸"))
            row(T("Size mode", "尺寸方式", "尺寸方式")) {
                Picker(T("Size mode", "尺寸方式", "尺寸方式"), selection: recipe.sizeMode) { Text(T("Maximum megapixels", "最大像素", "最大像素")).tag("megapixels"); Text(T("Long edge", "长边", "長邊")).tag("longEdge"); Text(T("Full resolution", "完整分辨率", "完整解析度")).tag("original") }.labelsHidden()
            }
            if document.exportRecipe.sizeMode == "megapixels" {
                row(T("Pixel limit", "像素上限", "像素上限")) { Picker(T("Pixel limit", "像素上限", "像素上限"), selection: recipe.maximumMegapixels) { ForEach([6.0, 12, 24, 36, 48], id: \.self) { Text("\(Int($0)) MP").tag($0) } }.labelsHidden() }
            } else if document.exportRecipe.sizeMode == "longEdge" {
                RulerParameterRow(title: T("Output long edge · px", "输出长边 · px", "輸出長邊 · px"), value: Binding(get: { Double(document.exportRecipe.longEdge) }, set: { document.exportRecipe.longEdge = Int($0.rounded()) }), range: 256...12000, defaultValue: 4000, fractionDigits: 0, step: 100, onReset: { document.exportRecipe.longEdge = 4000 })
            } else {
                if let photo = document.current {
                    let width = Int(sqrt(photo.sourceMegapixels * 1_000_000 * photo.sourceAspect).rounded())
                    let height = Int(sqrt(photo.sourceMegapixels * 1_000_000 / photo.sourceAspect).rounded())
                    Text(T("Source \(width) × \(height) · ", "源图 \(width) × \(height) · ", "源圖 \(width) × \(height) · ") + String(format: "%.1f MP", photo.sourceMegapixels))
                        .font(EditorDesign.panelSummary).foregroundStyle(.secondary).monospacedDigit()
                }
                Text(T("Uses the input photo's own pixels, ignoring preview resolution and the 24 MP limit; cropping removes pixels. If it will not fit in the memory available on the phone the export says so rather than quietly lowering quality.", "使用输入照片的原始像素，不受预览分辨率和24 MP上限限制；裁切会减少像素。超过手机当前可用内存时明确提示，不自动降画质。", "使用輸入照片的原始像素，不受預覽解析度和24 MP上限限制；裁切會減少像素。超過手機目前可用記憶體時明確提示，不自動降畫質。")).font(EditorDesign.help).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.vertical, 8)
            }
            ToolSectionTitle(title: T("Naming & Metadata", "命名与元数据", "命名與元數據"))
            Text(T("Tick what the file name contains", "勾选文件名包含的内容", "勾選檔案名包含的內容")).font(EditorDesign.parameter).padding(.top, 8)
            ForEach(MobileFilenameField.allCases) { field in
                let selected = document.exportRecipe.filenameFields.contains(field)
                Button {
                    var fields = document.exportRecipe.filenameFields
                    if selected { fields.remove(field) } else { fields.insert(field) }
                    document.exportRecipe.filenameFields = fields
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selected ? "checkmark.square.fill" : "square")
                            .foregroundStyle(selected ? MobileStyle.accent : .secondary)
                        Text(field.title).foregroundStyle(.primary)
                        Spacer()
                    }.frame(minHeight: EditorDesign.hitSize).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .disabled(selected && document.exportRecipe.filenameFields.count == 1)
                    .accessibilityLabel(field.title)
                    .accessibilityValue(selected ? T("Ticked", "已勾选", "已勾選") : T("Not ticked", "未勾选", "未勾選"))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("export.naming." + field.id)
            }
            Text(T("Joined in the order above with underscores; at least one must stay ticked. The counter starts at 0001.", "按上方顺序组合，用下划线分隔；至少保留一项。序号从 0001 开始。", "按上方順序組合，用下劃線分隔；至少保留一項。序號從 0001 開始。"))
                .font(EditorDesign.help).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.vertical, 8)
            if document.exportRecipe.usesCustomFilename {
                Text(T("The saved custom name is in use; changing the ticks switches to the ticked fields.", "当前沿用已保存的自定义命名；修改勾选后使用所选项目组合。", "目前沿用已儲存的自訂命名；修改勾選後使用所選項目組合。"))
                    .font(EditorDesign.help).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            let photo = targets.first.flatMap { id in document.photos.first { $0.id == id } }
            let film = photo?.recipe["film_stock"]?.stringValue ?? MobileProcessContract.defaults["film_stock"]?.stringValue ?? "film"
            let paper = photo?.recipe["print_stock"]?.stringValue ?? MobileProcessContract.defaults["print_stock"]?.stringValue ?? "paper"
            Text(T("Preview: ", "预览：", "預覽：") + document.exportRecipe.stem(original: photo?.name ?? T("photo.jpg", "照片.jpg", "照片.jpg"), film: film, paper: paper, counter: 1) + "." + document.exportRecipe.format.fileExtension)
                .font(EditorDesign.help).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8).accessibilityIdentifier("export.naming-preview")
            Toggle(T("Keep capture metadata", "保留拍摄元数据", "保留拍攝元數據"), isOn: recipe.metadata).frame(minHeight: EditorDesign.hitSize).tint(MobileStyle.accent)
            Toggle(T("Keep location", "保留定位信息", "保留定位資訊"), isOn: recipe.location).frame(minHeight: EditorDesign.hitSize).tint(MobileStyle.accent).disabled(!document.exportRecipe.metadata)
            if document.exportRecipe.format == .tiff { Toggle(T("Embed TIFF preview page", "嵌入 TIFF 预览页", "嵌入 TIFF 預覽頁"), isOn: recipe.embedsPreview).frame(minHeight: EditorDesign.hitSize).tint(MobileStyle.accent) }
            ToolSectionTitle(title: T("Save Location", "保存位置", "儲存位置"))
            row(T("Output folder", "输出文件夹", "輸出檔案夾")) { Button(document.exportFolder?.lastPathComponent ?? T("Share or Save to Files…", "分享／存储到文件…", "分享／存儲到檔案…")) { selectingFolder = true }.lineLimit(1) }
            if document.exportFolder != nil {
                row(T("Existing files", "同名文件", "同名檔案")) { Picker(T("Existing files", "同名文件", "同名檔案"), selection: recipe.existing) { Text(T("Add a number", "添加序号", "加入序號")).tag("suffix"); Text(T("Overwrite", "覆盖", "覆蓋")).tag("overwrite"); Text(T("Skip", "跳过", "跳過")).tag("skip") }.labelsHidden() }
                Button(T("Use the system share sheet", "改用系统分享", "改用系統分享")) { document.exportFolder = nil }.font(EditorDesign.parameter)
            }
            SmallAction(title: document.delivering ? T("Saving…", "正在保存…", "正在儲存…") : T("Save to Photos · \(targets.count)", "保存到照片 · \(targets.count) 张", "儲存到照片 · \(targets.count) 張"), symbol: "photo.badge.arrow.down", prominent: true) {
                document.export(document.exportRecipe.format, destination: .photos, ids: targets)
            }.padding(.top, 12).accessibilityIdentifier("export.photos").disabled(document.busy || document.delivering || targets.isEmpty || document.exportRecipe.format == .di)
            SmallAction(title: document.exportFolder == nil ? T("Export or Share Files…", "导出／分享文件…", "匯出／分享檔案…") : T("Export to Folder", "导出到文件夹", "匯出到檔案夾"), symbol: "square.and.arrow.up") {
                document.export(document.exportRecipe.format, ids: targets)
            }.padding(.top, 8).accessibilityIdentifier("export.files").disabled(document.busy || document.delivering || targets.isEmpty)
        }
        .font(EditorDesign.parameter).toggleStyle(.switch).pickerStyle(.menu)
        .padding(.horizontal, EditorDesign.contentInset).padding(.vertical, 8)
        .onChange(of: document.exportRecipe.format) { _, format in
            if format != .tiff, document.exportRecipe.colorSpace == .prophoto { document.exportRecipe.colorSpace = .p3 }
        }
        .fileImporter(isPresented: $selectingFolder, allowedContentTypes: [.folder]) { result in
            do { document.exportFolder = try result.get() } catch { document.error = error.localizedDescription }
        }
    }
    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) { Text(title).font(EditorDesign.parameter).foregroundStyle(.secondary); Spacer(minLength: 4); content().font(EditorDesign.selectedValue).foregroundStyle(.primary) }.frame(minHeight: EditorDesign.hitSize)
    }
}
