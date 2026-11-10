import SwiftUI
import Darwin
import UniformTypeIdentifiers
import CoreGraphics
import ImageIO

enum MobilePrintAnimationFrequency: String, Codable {
    case perLaunch, perPhoto
}

enum MobileCameraSavePolicy: String, Codable {
    case finishedPhoto = "jpegInPhotos"
    case rawAndFinishedPhoto = "rawAndJPEGInPhotos"
}

@MainActor @Observable final class MobilePreferences {
    struct Values: Codable, Equatable {
        var previewEdge = 2560 // legacy preference decoder; editor quality is automatic
        var lowerPreviewInLowPower = true
        var cropRemapsEffects = false
        var diBlueCompensation = false
        private var savedCameraSavePolicy: MobileCameraSavePolicy? = nil
        var cameraSavePolicy: MobileCameraSavePolicy {
            get { savedCameraSavePolicy ?? .finishedPhoto }
            set { savedCameraSavePolicy = newValue }
        }
        private var savedCameraUsesHEIF: Bool? = nil
        var cameraUsesHEIF: Bool {
            get { savedCameraUsesHEIF ?? false }
            set { savedCameraUsesHEIF = newValue }
        }
        private var savedMirrorsFrontCamera: Bool? = nil
        var mirrorsFrontCamera: Bool {
            get { savedMirrorsFrontCamera ?? true }
            set { savedMirrorsFrontCamera = newValue }
        }
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

enum MobileSettingsPresentation: Equatable {
    case sheet, fullScreen

    init(folded: Bool) { self = folded ? .fullScreen : .sheet }
}

extension View {
    func mobileSettings(document: MobileDocument, presentation: Binding<MobileSettingsPresentation?>) -> some View {
        func isPresented(_ mode: MobileSettingsPresentation) -> Binding<Bool> {
            Binding {
                presentation.wrappedValue == mode
            } set: { visible in
                if !visible && presentation.wrappedValue == mode { presentation.wrappedValue = nil }
            }
        }
        return self
            .sheet(isPresented: isPresented(.sheet)) { MobileSettingsView(document: document) }
            .fullScreenCover(isPresented: isPresented(.fullScreen)) { MobileSettingsView(document: document) }
    }
}

struct MobileSettingsView: View {
    @Bindable var document: MobileDocument
    @Bindable var preferences: MobilePreferences
    init(document: MobileDocument) { self.document = document; self.preferences = document.preferences }
    @AppStorage(MobileCaptureLocation.preferenceKey) private var recordsLocation = true
    @State private var cameraLocation = MobileCameraLocation.shared
    @AppStorage(MobileCameraPreviewMode.key) private var previewMode = MobileCameraPreviewMode.initial()
    @Environment(\.dismiss) private var dismiss
    @State private var showsIntroduction = false
    @State private var availableMemory: UInt64 = 0
    @State private var originalBytes: Int64?
    var body: some View {
        NavigationStack {
            Form {
                // First on the page, because it is the control for the thing
                // that changes every other word on the screen — including the
                // labels of the rows below it.
                Section {
                    Picker(T("Language", "语言", "語言"),
                           selection: Binding(get: { MobileLocalization.shared.language },
                                              set: { MobileLocalization.shared.language = $0 })) {
                        ForEach(MobileLanguageSetting.allCases) { setting in
                            Text(setting.label(in: MobileLocalization.shared.resolved))
                                .tag(setting)
                        }
                    }
                    .accessibilityIdentifier("settings.language")
                    Text(T("Film, paper, camera and lens names stay in English, as do technical abbreviations. The change applies immediately.",
                           "胶片、相纸、相机与镜头名称以及技术缩写保持英文。切换立即生效。",
                           "膠片、相紙、相機與鏡頭名稱以及技術縮寫保持英文。切換立即生效。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button(T("Getting started", "使用引导", "使用引導"), systemImage: "sparkles") { showsIntroduction = true }
                        .fullScreenCover(isPresented: $showsIntroduction) {
                            MobileIntroduction { showsIntroduction = false }
                        }
                }
                Section(T("Rendering", "渲染", "渲染")) {
                    Text(T("Preview detail follows the window and zoom; 1:1 shows original pixels.", "预览清晰度随窗口和缩放自动调整，1:1 查看原始像素。", "預覽清晰度隨視窗與縮放自動調整，1:1 檢視原始像素。")).font(.caption).foregroundStyle(.secondary)
                    Toggle(T("Prefer smoothness in Low Power Mode", "低电量模式优先流畅", "低電量模式優先流暢"), isOn: $preferences.values.lowerPreviewInLowPower).tint(MobileStyle.accent)
                    Toggle(T("Rescale physical effects after crop", "裁切后重新计算物理效果尺度", "裁切後重新計算物理效果尺度"), isOn: $preferences.values.cropRemapsEffects).tint(MobileStyle.accent)
                    Toggle(T("Digital Intermediate blue compensation", "数字中间片蓝色补偿", "數位中間片藍色補償"), isOn: $preferences.values.diBlueCompensation).tint(MobileStyle.accent)
                    Text(T("Blue compensation applies to Digital Intermediate output only. Off by default.", "蓝色补偿仅作用于数字中间片；默认关闭。", "藍色補償僅作用於數位中間片；預設關閉。")).font(.caption).foregroundStyle(.secondary)
                }
                Section(T("Editor", "编辑器", "編輯器")) {
                    Picker(T("Print animation", "印相动画", "印相動畫"), selection: $preferences.values.printAnimationFrequency) {
                        Text(T("Once per launch", "每次启动一次", "每次啟動一次")).tag(MobilePrintAnimationFrequency.perLaunch)
                        Text(T("Once per photo", "每张照片一次", "每張照片一次")).tag(MobilePrintAnimationFrequency.perPhoto)
                    }
                    Text(T("Once per photo: the animation plays the first time each photo is printed in this launch.", "每张照片一次：本次启动中，每张照片首次进入印相时显示动画。", "每張照片一次：本次啟動中，每張照片首次進入印相時顯示動畫。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(T("Camera", "相机", "相機")) {
                    Picker(T("Live film preview", "实时胶片取景", "即時膠片取景"), selection: $previewMode) {
                        ForEach(MobileCameraPreviewMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                        .accessibilityIdentifier("settings.camera.filmPreview")
                    Text(T("The smooth approximation is recommended: film colour and diffusion are there to compose with, and neither grain nor halation is simulated. The native engine preview is experimental and refreshes slowly. Neither mode guarantees the same exposure as the RAW-finished photo. The system viewfinder shows no preview effect; the finished photo always uses the selected recipe.", "建议使用流畅近似预览，胶片色彩与柔光用于构图参考，不模拟颗粒与胶片光晕。原生引擎预览为实验选项，刷新较慢，两种模式均不保证与 RAW 成片曝光相同。系统取景关闭预览效果；成片始终应用所选配方。", "建議使用流暢近似預覽，膠片色彩與柔光用於構圖參考，不模擬顆粒與膠片光暈。原生引擎預覽為實驗選項，更新較慢，兩種模式均不保證與 RAW 成片曝光相同。系統取景關閉預覽效果；成片始終套用所選配方。"))
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle(T("Record capture location", "记录拍摄位置", "記錄拍攝位置"), isOn: $recordsLocation)
                        .tint(MobileStyle.accent)
                        .accessibilityIdentifier("settings.camera.location")
                    Text(T("Writes an available location into the original and the finished photo when shooting in the app. On by default; capture still works when no location is available.", "在应用内拍摄时，将可用位置写入原片和成片。默认开启；无法定位时仍正常拍照。", "在應用程式內拍攝時，將可用位置寫入原片和成片。預設開啟；無法定位時仍可正常拍攝。"))
                        .font(.caption).foregroundStyle(.secondary)
                    if recordsLocation && cameraLocation.denied {
                        Button(T("Allow Location in System Settings", "在系统设置中允许定位", "在系統設定中允許定位")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                    Toggle(T("Mirror front camera", "镜像前置镜头", "鏡像前置鏡頭"), isOn: $preferences.values.mirrorsFrontCamera)
                        .tint(MobileStyle.accent)
                    Picker(T("Capture save policy", "拍摄保存策略", "拍攝儲存策略"), selection: $preferences.values.cameraSavePolicy) {
                        Text(T("Finished photo only", "相册仅存成片", "相簿僅存成片")).tag(MobileCameraSavePolicy.finishedPhoto)
                        Text(T("RAW + finished photo", "相册存 RAW＋成片", "相簿存 RAW＋成片")).tag(MobileCameraSavePolicy.rawAndFinishedPhoto)
                    }
                    Picker(T("Photo format in Photos", "相册成片格式", "相簿成片格式"), selection: $preferences.values.cameraUsesHEIF) {
                        Text("JPEG").tag(false)
                        Text("HEIF").tag(true)
                    }
                    Text(T("The original always stays in Silverphase. When RAW is captured it can be saved into Photos as a single photo together with the finished image; when the current lens does not capture RAW, Photos receives the finished photo only. HEIF usually takes less space than JPEG.", "原片始终保存在 Silverphase。拍到 RAW 时可与成片合存为相册中的一张照片；当前镜头没有拍到 RAW 时，相册只存成片。HEIF 通常比 JPEG 更省空间。", "原片始終儲存在 Silverphase。拍到 RAW 時可與成片合存為相簿中的一張照片；目前鏡頭沒有拍到 RAW 時，相簿只存成片。HEIF 通常比 JPEG 更節省空間。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(T("Library storage", "图库存储", "圖庫儲存")) {
                    LabeledContent(T("Photo storage", "照片存储", "照片儲存"), value: T("In-app library", "应用内图库", "應用程式內圖庫"))
                    LabeledContent(T("Photos", "照片数量", "照片數量"),
                                   value: T("\(document.photos.count) photos",
                                            "\(document.photos.count) 张",
                                            "\(document.photos.count) 張"))
                    if let originalBytes {
                        LabeledContent(T("Originals on disk", "原片占用", "原片佔用"), value: ByteCountFormatter.string(fromByteCount: originalBytes, countStyle: .file))
                    }
                    Text(T("Captured and imported originals are kept inside Silverphase and take up local storage. Finished photos and RAW copies saved to Photos are managed by Photos separately.", "拍摄和导入的原片会保存在 Silverphase 内，占用本机存储空间。保存到系统相册的成片和 RAW 副本由系统相册单独管理。", "拍攝和匯入的原片會儲存在 Silverphase 內，佔用本機儲存空間。儲存到系統相簿的成片和 RAW 副本由系統相簿另行管理。"))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(T("Removing a photo from the Silverphase library deletes the in-app original and its edit record. Copies in Photos and the source files you imported from stay where they are.", "从 Silverphase 图库移除照片会删除 App 内的原片和编辑记录。系统相册里的副本和导入前的原文件可在各自位置管理。", "從 Silverphase 圖庫移除照片會刪除 App 內的原片和編輯記錄。系統相簿裡的副本和匯入前的原始檔案可在各自位置管理。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(T("Memory", "内存", "記憶體")) {
                    LabeledContent(T("Device memory", "设备内存", "裝置記憶體"), value: String(format: "%.1f GB", Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824))
                    LabeledContent(T("Available to this app", "应用当前可用内存", "應用程式目前可用記憶體"), value: String(format: "%.2f GB", Double(availableMemory) / 1_000_000_000))
                    Text(T("Total device memory is shared by the system and every app; this is the amount the system currently lets this app use.", "设备总内存由系统与所有应用共享；这里显示系统当前允许本应用继续使用的额度。", "裝置總記憶體由系統與所有應用程式共用；這裡顯示系統目前允許本應用程式繼續使用的額度。")).font(.caption).foregroundStyle(.secondary)
                    LabeledContent(T("Memory protection", "内存保护", "記憶體保護"), value: T("Automatic", "自动", "自動"))
                    Button(T("Release render cache", "释放渲染缓存", "釋放渲染快取")) { document.releaseMemory(); document.schedule() }.disabled(document.delivering)
                }
                Section(T("Diagnostics", "诊断", "診斷")) {
                    LabeledContent(T("Render engine", "渲染引擎", "渲染引擎"), value: "Native Metal")
                    LabeledContent(T("Colour working space", "色彩工作空间", "色彩工作空間"), value: "ProPhoto RGB")
                    Button(T("Reset to Defaults", "恢复默认设置", "恢復預設設定"), role: .destructive) { document.preferences.values = MobilePreferences.Values(); previewMode = .approximate; recordsLocation = true }
                }
                MobileSupportSection()
                MobileRelatedAppSection()
            }
            .navigationTitle(T("Settings", "设置", "設定"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(T("Done", "完成", "完成")) { dismiss() } } }
        }
        .presentationDetents([.large])
        .onChange(of: recordsLocation) { _, enabled in cameraLocation.setEnabled(enabled, requestPermission: enabled) }
        .task(id: document.photos.map(\.id)) {
            let sources = document.photos.map { document.url(for: $0) }
            let bytes = await Task.detached(priority: .utility) {
                sources.reduce(Int64(0)) { total, source in
                    total + Int64((try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                }
            }.value
            if !Task.isCancelled { originalBytes = bytes }
        }
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
        Section(T("Support & Privacy", "支持与隐私", "支援與隱私")) {
            Link(T("Help & Support", "帮助与支持", "幫助與支援"), destination: URL(string: "https://github.com/akinal5765-byte/Silverphase/blob/main/docs/SUPPORT.md")!)
            Link(T("Privacy Policy", "隐私政策", "隱私權政策"), destination: URL(string: "https://github.com/akinal5765-byte/Silverphase/blob/main/docs/PRIVACY.md")!)
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
        Section(T("More from the developer", "开发者的其他应用", "開發者的其他應用程式")) {
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
                        Text(T("Layerlight · HDR photo editor", "Layerlight · HDR 图片编辑器", "Layerlight · HDR 照片編輯器"))
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                    }
                    Text(T("Adds HDR light and depth to photos, and adjusts photographic styles in the iOS Photos app.", "为照片增添 HDR 光影层次，还可在 iOS「照片」中调整摄影风格。", "為照片增添 HDR 光影層次，還可在 iOS「照片」中調整攝影風格。"))
                        .foregroundStyle(.secondary)
                    Text(T("Photographic styles need a supported device and system version. Some features require Pro.", "摄影风格需受支持的设备与系统。部分功能需 Pro。", "攝影風格需受支援的裝置與系統。部分功能需 Pro。"))
                        .foregroundStyle(.secondary)
                    Label(T("View in the App Store", "在 App Store 查看", "在 App Store 檢視"), systemImage: "arrow.up.right")
                        .foregroundStyle(MobileStyle.accent)
                }
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("related-app.layerlight")
            .accessibilityHint(T("Opens Layerlight's page in the App Store", "打开 Layerlight 的 App Store 页面", "開啟 Layerlight 的 App Store 頁面"))
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
    /// `@MainActor` because the copy comes from `T(_:_:_:)`, which reads the
    /// language setting. Every use of this name is in a view body; a display
    /// name is not a value the model layer needs.
    @MainActor var title: String {
        switch self {
        case .original: T("Original name", "原文件名", "原檔名")
        case .film: T("Film", "胶片型号", "膠片型號")
        case .paper: T("Paper", "相纸型号", "相紙型號")
        case .date: T("Export date", "导出日期", "匯出日期")
        case .counter: T("Counter", "序号", "序號")
        }
    }
}

struct MobileExportRecipe: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    /// Empty means "not named yet". The name is user data and is persisted, so
    /// it must not be written in whichever language was active when the preset
    /// was saved; what the interface shows is `displayName`.
    var name = ""
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
    /// What an unnamed recipe is called, resolved at draw time so it follows
    /// the interface language instead of freezing one into the saved preset.
    @MainActor static var defaultName: String {
        T("Custom recipe", "自定配方", "自訂配方")
    }
    @MainActor var displayName: String { name.isEmpty ? Self.defaultName : name }

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
