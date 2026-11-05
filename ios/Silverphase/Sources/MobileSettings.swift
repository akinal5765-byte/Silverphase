import SwiftUI
import Darwin
import UniformTypeIdentifiers
import CoreGraphics
import ImageIO

enum MobilePrintAnimationFrequency: String, Codable {
    case perLaunch, perPhoto
}

@MainActor @Observable final class MobilePreferences {
    struct Values: Codable, Equatable {
        var previewEdge = 2560 // legacy preference decoder; editor quality is automatic
        var lowerPreviewInLowPower = true
        var cropRemapsEffects = false
        var diBlueCompensation = false
        private var savedPrintAnimationFrequency: MobilePrintAnimationFrequency? = nil
        var printAnimationFrequency: MobilePrintAnimationFrequency {
            get { savedPrintAnimationFrequency ?? .perLaunch }
            set { savedPrintAnimationFrequency = newValue }
        }
    }
    var values: Values { didSet { if let data = try? JSONEncoder().encode(values) { UserDefaults.standard.set(data, forKey: "mobile.preferences.v1") } } }
    init() {
        values = UserDefaults.standard.data(forKey: "mobile.preferences.v1").flatMap { try? JSONDecoder().decode(Values.self, from: $0) } ?? Values()
        if ![1080, 1920, 2560, 3840].contains(values.previewEdge) { values.previewEdge = 2560 }
    }
    func megapixels(aspect: Double) -> Double {
        let edge = values.lowerPreviewInLowPower && ProcessInfo.processInfo.isLowPowerModeEnabled ? min(1920, values.previewEdge) : values.previewEdge
        return Double(edge * edge) / max(aspect, 1 / max(0.001, aspect)) / 1_000_000
    }
}

struct MobileSettingsView: View {
    @Bindable var document: MobileDocument
    @Bindable var preferences: MobilePreferences
    init(document: MobileDocument) { self.document = document; self.preferences = document.preferences }
    @Environment(\.dismiss) private var dismiss
    @State private var availableMemory: UInt64 = 0
    var body: some View {
        NavigationStack {
            Form {
                Section("渲染") {
                    Text("预览清晰度随窗口和缩放自动调整，1:1 查看原始像素。").font(.caption).foregroundStyle(.secondary)
                    Toggle("低电量模式优先流畅", isOn: $preferences.values.lowerPreviewInLowPower).tint(MobileStyle.accent)
                    Toggle("裁切后重新计算物理效果尺度", isOn: $preferences.values.cropRemapsEffects).tint(MobileStyle.accent)
                    Toggle("数字中间片蓝色补偿", isOn: $preferences.values.diBlueCompensation).tint(MobileStyle.accent)
                    Text("蓝色补偿仅作用于数字中间片；默认关闭。").font(.caption).foregroundStyle(.secondary)
                }
                Section("编辑器") {
                    Picker("印相动画", selection: $preferences.values.printAnimationFrequency) {
                        Text("每次启动一次").tag(MobilePrintAnimationFrequency.perLaunch)
                        Text("每张照片一次").tag(MobilePrintAnimationFrequency.perPhoto)
                    }
                    Text("每张照片一次：本次启动中，每张照片首次进入印相时显示动画。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("图库存储") {
                    LabeledContent("照片存储", value: "应用内图库")
                    LabeledContent("照片数量", value: "\(document.photos.count) 张")
                    Text("导入的原文件和编辑记录保存在本机，重启应用后仍可继续编辑。在图库中移除照片不会影响系统照片库或导入前的原始文件。").font(.caption).foregroundStyle(.secondary)
                }
                Section("内存") {
                    LabeledContent("设备内存", value: String(format: "%.1f GB", Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824))
                    LabeledContent("应用当前可用内存", value: String(format: "%.2f GB", Double(availableMemory) / 1_000_000_000))
                    Text("设备总内存由系统与所有应用共享；这里显示系统当前允许本应用继续使用的额度。").font(.caption).foregroundStyle(.secondary)
                    LabeledContent("内存保护", value: "自动")
                    Button("释放渲染缓存") { document.releaseMemory(); document.schedule() }.disabled(document.delivering)
                }
                Section("诊断") {
                    LabeledContent("渲染引擎", value: "Native Metal")
                    LabeledContent("色彩工作空间", value: "ProPhoto RGB")
                    Button("恢复默认设置", role: .destructive) { document.preferences.values = MobilePreferences.Values() }
                }
                MobileSupportSection()
                MobileRelatedAppSection()
            }
            .navigationTitle("设置")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.large])
        .task {
            while !Task.isCancelled {
                availableMemory = UInt64(os_proc_available_memory())
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
}

struct MobileSupportSection: View {
    var body: some View {
        Section("支持与隐私") {
            Link("帮助与支持", destination: URL(string: "https://github.com/akinal5765-byte/Silverphase/blob/main/docs/SUPPORT.md")!)
            Link("隐私政策", destination: URL(string: "https://github.com/akinal5765-byte/Silverphase/blob/main/docs/PRIVACY.md")!)
        }
    }
}

struct MobileRelatedAppSection: View {
    private static let layerlightURL = URL(string: "https://apps.apple.com/app/id6756343255")!
    private static let layerlightIcon: CGImage? = {
        guard let url = Bundle.main.url(forResource: "layerlight-icon", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }()

    var body: some View {
        Section("开发者的其他应用") {
            Link(destination: Self.layerlightURL) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Group {
                            if let icon = Self.layerlightIcon {
                                Image(decorative: icon, scale: 1)
                                    .renderingMode(.original)
                                    .resizable()
                                    .scaledToFit()
                            } else {
                                Image(systemName: "camera.aperture")
                                    .resizable()
                                    .scaledToFit()
                            }
                        }
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                        Text("Layerlight · HDR 图片编辑器")
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                    Text("为照片增添 HDR 光影层次，还可在 iOS「照片」中调整摄影风格。")
                        .foregroundStyle(.secondary)
                    Text("摄影风格需受支持的设备与系统。部分功能需 Pro。")
                        .foregroundStyle(.secondary)
                    Label("在 App Store 查看", systemImage: "arrow.up.right")
                        .foregroundStyle(MobileStyle.accent)
                }
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("related-app.layerlight")
            .accessibilityHint("打开 Layerlight 的 App Store 页面")
        }
    }
}

enum MobileOutputSpace: String, Codable, CaseIterable, Identifiable, Sendable {
    case p3 = "Display P3", srgb = "sRGB", adobe = "Adobe RGB (1998)", prophoto = "ProPhoto RGB"
    var id: String { rawValue }
    var cgSpace: CGColorSpace {
        let name: CFString
        switch self { case .p3: name = CGColorSpace.displayP3; case .srgb: name = CGColorSpace.sRGB; case .adobe: name = CGColorSpace.adobeRGB1998; case .prophoto: name = CGColorSpace.rommrgb }
        return CGColorSpace(name: name)!
    }
}

enum MobileFilenameField: String, CaseIterable, Identifiable, Sendable {
    case original, film, paper, date, counter
    var id: String { rawValue }
    var token: String { "{" + rawValue + "}" }
    var title: String {
        switch self {
        case .original: "原文件名"
        case .film: "胶片型号"
        case .paper: "相纸型号"
        case .date: "导出日期"
        case .counter: "序号"
        }
    }
}

struct MobileExportRecipe: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name = "自定配方"
    var format = MobileExportFormat.jpeg
    var colorSpace = MobileOutputSpace.p3
    var quality = 0.95
    var maximumMegapixels = 24.0
    var longEdge = 4000
    var sizeMode = "megapixels"
    var naming = "{original}_{film}_{paper}"
    var existing = "suffix"
    var metadata = true
    var location = true
    var embedsPreview = false
    var scope = "current"
    // Keep the stored representation compatible with existing export presets.
    // Only the UI chooses fields; template syntax is never user-facing.
    var filenameFields: Set<MobileFilenameField> {
        get { Set(MobileFilenameField.allCases.filter { naming.contains($0.token) }) }
        set {
            let fields = newValue.isEmpty ? Set([MobileFilenameField.original]) : newValue
            naming = MobileFilenameField.allCases.filter { fields.contains($0) }.map(\.token).joined(separator: "_")
        }
    }
    var usesCustomFilename: Bool {
        naming != MobileFilenameField.allCases.filter { filenameFields.contains($0) }.map(\.token).joined(separator: "_")
    }
    func stem(original: String, film: String, paper: String, counter: Int) -> String {
        let originalStem = URL(fileURLWithPath: original).deletingPathExtension().lastPathComponent
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd"
        let fields = ["{original}": originalStem, "{film}": film, "{paper}": paper, "{counter}": String(format: "%04d", counter), "{date}": formatter.string(from: Date())]
        var value = naming
        for (key, text) in fields { value = value.replacingOccurrences(of: key, with: text) }
        value = value.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? originalStem : value
    }
    func megapixels(sourceMP: Double, aspect: Double, geometry: MobileGeometry = MobileGeometry()) -> Double {
        switch sizeMode {
        case "original": return max(0.1, sourceMP)
        case "longEdge":
            let source = CGSize(width: aspect * 10000, height: 10000)
            let output = geometry.outputSize(for: source)
            let w = output.width, h = output.height
            let sourceLong = max(source.width, source.height)
            let required = Double(longEdge) * sourceLong / max(w, h)
            return min(max(0.1, sourceMP), required * required / max(aspect, 1 / max(0.001, aspect)) / 1_000_000)
        default: return min(max(0.1, sourceMP), maximumMegapixels)
        }
    }
}
