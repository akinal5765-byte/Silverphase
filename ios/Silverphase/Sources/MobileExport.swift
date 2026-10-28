import SwiftUI
import UniformTypeIdentifiers

struct MobileExportPanel: View {
    @Bindable var document: MobileDocument
    let filteredIDs: [UUID]
    @State private var selectingFolder = false
    private var recipe: Binding<MobileExportRecipe> { $document.exportRecipe }
    private var targets: [UUID] {
        switch document.exportRecipe.scope {
        case "all": document.photos.map(\.id)
        case "picked": document.photos.filter { $0.flag == "pick" }.map(\.id)
        case "filtered": filteredIDs
        default: document.selection.map { [$0] } ?? []
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ToolSectionTitle(title: "导出配方")
            row("配方") {
                Menu {
                    ForEach(document.exportPresets) { preset in Button(preset.name) { document.exportRecipe = preset } }
                    Divider()
                    Button("保存当前配方") {
                        var value = document.exportRecipe; value.id = UUID()
                        document.exportPresets.append(value); document.exportRecipe = value
                    }
                    Button("恢复默认配方") { document.exportRecipe = MobileExportRecipe() }
                    Button("删除已保存配方", role: .destructive) { document.exportPresets.removeAll { $0.id == document.exportRecipe.id } }
                } label: { Text(document.exportRecipe.name); Image(systemName: "chevron.down") }
            }
            TextField("配方名称", text: recipe.name).textFieldStyle(.roundedBorder).font(EditorDesign.parameter).padding(.vertical, 8)
            row("导出范围") {
                Picker("导出范围", selection: recipe.scope) {
                    Text("当前照片").tag("current"); Text("全部照片").tag("all"); Text("已保留照片").tag("picked"); Text("当前筛选结果").tag("filtered")
                }.labelsHidden()
            }
            ToolSectionTitle(title: "文件与色彩")
            row("格式") { Picker("格式", selection: recipe.format) { ForEach(MobileExportFormat.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden() }
            row("位深") { Text(document.exportRecipe.format == .jpeg || document.exportRecipe.format == .png ? "8-bit" : "16-bit").monospacedDigit() }
            if document.exportRecipe.format != .di {
                row("色彩空间") {
                    Picker("色彩空间", selection: recipe.colorSpace) {
                        ForEach(MobileOutputSpace.allCases.filter { $0 != .prophoto || document.exportRecipe.format == .tiff }) { Text($0.rawValue).tag($0) }
                    }.labelsHidden()
                }
                if document.exportRecipe.format == .jpeg {
                    RulerParameterRow(title: "JPEG 质量 · %", value: Binding(get: { document.exportRecipe.quality * 100 }, set: { document.exportRecipe.quality = $0 / 100 }), range: 10...100, defaultValue: 95, fractionDigits: 0, step: 1, onReset: { document.exportRecipe.quality = 0.95 })
                }
            } else {
                Text("Cineon 对数，ProPhoto 原色，不嵌入 ICC。输出 TIFF 与两个桌面端相同的视图 LUT；正片不支持。").font(EditorDesign.help).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.vertical, 8)
            }
            ToolSectionTitle(title: "输出尺寸")
            row("尺寸方式") {
                Picker("尺寸方式", selection: recipe.sizeMode) { Text("最大像素").tag("megapixels"); Text("长边").tag("longEdge"); Text("完整分辨率").tag("original") }.labelsHidden()
            }
            if document.exportRecipe.sizeMode == "megapixels" {
                row("像素上限") { Picker("像素上限", selection: recipe.maximumMegapixels) { ForEach([6.0, 12, 24, 36, 48], id: \.self) { Text("\(Int($0)) MP").tag($0) } }.labelsHidden() }
            } else if document.exportRecipe.sizeMode == "longEdge" {
                RulerParameterRow(title: "输出长边 · px", value: Binding(get: { Double(document.exportRecipe.longEdge) }, set: { document.exportRecipe.longEdge = Int($0.rounded()) }), range: 256...12000, defaultValue: 4000, fractionDigits: 0, step: 100, onReset: { document.exportRecipe.longEdge = 4000 })
            } else {
                if let photo = document.current {
                    let width = Int(sqrt(photo.sourceMegapixels * 1_000_000 * photo.sourceAspect).rounded())
                    let height = Int(sqrt(photo.sourceMegapixels * 1_000_000 / photo.sourceAspect).rounded())
                    Text("源图 \(width) × \(height) · " + String(format: "%.1f MP", photo.sourceMegapixels))
                        .font(EditorDesign.panelSummary).foregroundStyle(.secondary).monospacedDigit()
                }
                Text("使用输入照片的原始像素，不受预览分辨率和24 MP上限限制；裁切会减少像素。超过手机当前可用内存时明确提示，不自动降画质。").font(EditorDesign.help).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.vertical, 8)
            }
            ToolSectionTitle(title: "命名与元数据")
            TextField("文件名规则", text: recipe.naming).textFieldStyle(.roundedBorder).font(EditorDesign.parameter).padding(.vertical, 8)
            Text("可用：{original} {film} {paper} {date} {counter}").font(EditorDesign.help).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.vertical, 8)
            if let photo = document.current {
                Text(document.exportRecipe.stem(original: photo.name, film: document.value("film_stock")?.stringValue ?? "film", paper: document.value("print_stock")?.stringValue ?? "paper", counter: 1) + "." + document.exportRecipe.format.fileExtension)
                    .font(EditorDesign.help).lineLimit(2).foregroundStyle(.secondary).padding(.vertical, 8)
            }
            Toggle("保留拍摄元数据", isOn: recipe.metadata).frame(minHeight: EditorDesign.hitSize).tint(MobileStyle.accent)
            Toggle("保留定位信息", isOn: recipe.location).frame(minHeight: EditorDesign.hitSize).tint(MobileStyle.accent).disabled(!document.exportRecipe.metadata)
            if document.exportRecipe.format == .tiff { Toggle("嵌入 TIFF 预览页", isOn: recipe.embedsPreview).frame(minHeight: EditorDesign.hitSize).tint(MobileStyle.accent) }
            ToolSectionTitle(title: "保存位置")
            row("输出文件夹") { Button(document.exportFolder?.lastPathComponent ?? "分享／存储到文件…") { selectingFolder = true }.lineLimit(1) }
            if document.exportFolder != nil {
                row("同名文件") { Picker("同名文件", selection: recipe.existing) { Text("添加序号").tag("suffix"); Text("覆盖").tag("overwrite"); Text("跳过").tag("skip") }.labelsHidden() }
                Button("改用系统分享") { document.exportFolder = nil }.font(EditorDesign.parameter)
            }
            SmallAction(title: document.delivering ? "正在保存…" : "保存到照片 · \(targets.count) 张", symbol: "photo.badge.arrow.down", prominent: true) {
                document.export(document.exportRecipe.format, destination: .photos, ids: targets)
            }.padding(.top, 12).accessibilityIdentifier("export.photos").disabled(document.busy || document.delivering || targets.isEmpty || document.exportRecipe.format == .di)
            SmallAction(title: document.exportFolder == nil ? "导出／分享文件…" : "导出到文件夹", symbol: "square.and.arrow.up") {
                document.export(document.exportRecipe.format, ids: targets)
            }.padding(.top, 8).disabled(document.busy || document.delivering || targets.isEmpty)
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
