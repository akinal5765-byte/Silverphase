import Foundation

/// Copy user intent, never resolved meter/scene/EXIF values. Each selected
/// group replaces its overrides, including removing overrides absent at source.
enum MobileClipboardGroup: String, CaseIterable, Identifiable, Sendable {
    case camera, film, development, print, output, filmEdge, geometry
    var id: String { rawValue }
    static let defaults = Set(allCases.filter { $0 != .geometry })
    var title: String {
        switch self {
        case .camera: "相机"
        case .film: "胶片"
        case .development: "显影"
        case .print: "印相"
        case .output: "扫描"
        case .filmEdge: "片边与日期"
        case .geometry: "构图"
        }
    }
    var detail: String {
        switch self {
        case .camera: "测光、曝光、白平衡、滤镜与场景置位；目标按自身画面重新计算。"
        case .film: "胶片型号、物理画幅、颗粒、晕光与散射。"
        case .development: "显影反差与色彩分离。"
        case .print: "相纸、直扫／中间片、印相曝光、滤色与柔化。"
        case .output: "扫描锐化、眩光与高光扩展。"
        case .filmEdge: "片门、片边、灰雾、漏光及日期后背；自动日期取目标照片。"
        case .geometry: "裁切、校直、旋转与翻转；默认不复制。"
        }
    }
    var keys: Set<String> {
        switch self {
        case .camera:
            ["auto_exposure", "auto_exposure_method", "exposure_compensation_ev", "camera_filter",
             "_whiteBalancePreset", "_temperature", "_tint", "camera_diffusion_active", "camera_diffusion_family",
             "camera_diffusion_strength", "camera_diffusion_range", "_placementHighlight", "_placementShadow"]
        case .film:
            ["film_stock", "film_format_mm", "_filmFrame", "_filmSide", "_sideLengthMM", "_sideUnit",
             "grain_active", "grain_sublayers_active", "_grainAmount", "grain_amount", "grain_size_scale",
             "_grainSoftness", "grain_softness", "halation_active", "antihalation_mode", "halation_amount", "halation_scatter_amount"]
        case .development: ["density_curve_gamma", "dir_couplers_active", "dir_couplers_amount"]
        case .print:
            ["print_stock", "scan_film", "digital_intermediate", "_paperGrade", "_printBrightnessStops", "print_exposure",
             "print_contrast", "y_filter_shift", "m_filter_shift", "c_filter_neutral", "m_filter_neutral", "y_filter_neutral",
             "preflash_exposure", "_printEffects", "enlarger_diffusion_active", "enlarger_diffusion_family",
             "enlarger_diffusion_strength", "enlarger_diffusion_range"]
        case .output:
            ["_scannerActive", "_scannerStrength", "scanner_sharpening_amount", "glare_active", "glare_amount", "extended_dynamic_range"]
        case .filmEdge:
            ["overscan_active", "overscan_format", "overscan_mode", "overscan_gate", "overscan_holes", "overscan_carrier",
             "overscan_camera_seed", "overscan_frame_seed", "overscan_frame_number", "overscan_fog", "overscan_leaks",
             "date_imprint_active", "date_imprint_text", "date_imprint_style", "date_imprint_placement", "date_imprint_ev",
             "date_imprint_size", "date_imprint_corner", "date_imprint_inset_x", "date_imprint_inset_y", "_dateOrder", "_dateWithData"]
        case .geometry: []
        }
    }
}

struct MobileSettingsClip {
    let sourceName: String
    let groups: Set<MobileClipboardGroup>
    private let recipe: [String: WireValue]
    private let geometry: MobileGeometry

    init(source: MobilePhoto, groups: Set<MobileClipboardGroup>) {
        sourceName = source.name; self.groups = groups
        recipe = source.recipe; geometry = source.geometry
    }
    var summary: String { MobileClipboardGroup.allCases.filter { groups.contains($0) }.map(\.title).joined(separator: "、") }
    func applied(to target: MobilePhoto) -> MobilePhoto {
        var result = target
        for key in groups.reduce(into: Set<String>()) { $0.formUnion($1.keys) } {
            result.recipe[key] = recipe[key]
        }
        // As Shot means this target's camera. A missing individual WB axis
        // remains missing, so the target decoder supplies that axis too.
        if groups.contains(.camera), (recipe["_whiteBalancePreset"]?.stringValue ?? "asShot") == "asShot" {
            result.recipe.removeValue(forKey: "_temperature")
            result.recipe.removeValue(forKey: "_tint")
        }
        if groups.contains(.geometry) {
            let area = max(1, target.sourceMegapixels * 1_000_000)
            let aspect = max(0.001, target.sourceAspect)
            result.geometry = MobileGeometry(value: geometry.value.fitted(in: CGSize(width: sqrt(area * aspect), height: sqrt(area / aspect))))
        }
        return result
    }
}

struct MobileSettingsCopyRequest: Identifiable {
    let id = UUID()
    let source: MobilePhoto
    let groups: Set<MobileClipboardGroup>
}

/// History only owns editable fields. Undo cannot restore an old filename,
/// rating, flag or import metadata, nor resurrect a removed photograph.
struct MobileEditSnapshot {
    let recipe: [String: WireValue]
    let geometry: MobileGeometry
    init(_ photo: MobilePhoto) { recipe = photo.recipe; geometry = photo.geometry }
    func applied(to photo: MobilePhoto) -> MobilePhoto {
        var result = photo; result.recipe = recipe; result.geometry = geometry; return result
    }
    func matches(_ photo: MobilePhoto) -> Bool { recipe == photo.recipe && geometry == photo.geometry }
}
typealias MobileEditTransaction = [UUID: MobileEditSnapshot]
