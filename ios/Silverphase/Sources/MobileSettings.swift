import SwiftUI
import Darwin
import UniformTypeIdentifiers
import CoreGraphics

@MainActor @Observable final class MobilePreferences {
    struct Values: Codable, Equatable {
        var previewEdge = 2560 // legacy preference decoder; editor quality is automatic
        var lowerPreviewInLowPower = true
        var cropRemapsEffects = false
        var diBlueCompensation = false
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
                Section("会话与内存") {
                    LabeledContent("照片存储", value: "本次会话")
                    Text("重新启动清空已加载图片。设置与导出配方会保留，原始文件和系统图库不受影响。").font(.caption).foregroundStyle(.secondary)
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

enum MobileOutputSpace: String, Codable, CaseIterable, Identifiable, Sendable {
    case p3 = "Display P3", srgb = "sRGB", adobe = "Adobe RGB (1998)", prophoto = "ProPhoto RGB"
    var id: String { rawValue }
    var cgSpace: CGColorSpace {
        let name: CFString
        switch self { case .p3: name = CGColorSpace.displayP3; case .srgb: name = CGColorSpace.sRGB; case .adobe: name = CGColorSpace.adobeRGB1998; case .prophoto: name = CGColorSpace.rommrgb }
        return CGColorSpace(name: name)!
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
