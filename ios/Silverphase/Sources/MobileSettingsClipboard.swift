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
        case .geometry: "裁切比例"
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
        case .geometry: "仅复制宽高比例，横竖跟随目标；保留目标的构图中心、校直、旋转与翻转。"
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
             "_grainSoftness", "grain_softness", "halation_active", "antihalation_mode", "halation_headroom_ev", "halation_amount", "halation_scatter_amount"]
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
    private let cropRatio: Double

    init(source: MobilePhoto, groups: Set<MobileClipboardGroup>) {
        sourceName = source.name; self.groups = groups
        recipe = source.recipe
        let crop = source.geometry.value.crop
        let ratio = max(0.001, crop.width * source.sourceAspect / max(0.001, crop.height))
        cropRatio = max(ratio, 1 / ratio)
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
            let aspect = max(0.001, target.sourceAspect)
            let size = CGSize(width: 3000 * aspect, height: 3000)
            var g = target.geometry.value
            let turned = g.quarterTurns % 2 != 0
            var currentRatio = g.crop.width * aspect / max(0.001, g.crop.height)
            if turned { currentRatio = 1 / currentRatio }
            // A square crop has no orientation: use the target's turned source.
            let portrait = abs(currentRatio - 1) < 0.000001 ? (turned ? aspect > 1 : aspect < 1) : currentRatio < 1
            var ratio = portrait ? 1 / cropRatio : cropRatio
            if turned { ratio = 1 / ratio }
            let centre = g.centre
            let area = max(0.000001, g.crop.width * size.width * g.crop.height * size.height)
            let width = sqrt(area * ratio) / size.width
            let height = sqrt(area / ratio) / size.height
            g.crop = CropRect(x: centre.x - width / 2, y: centre.y - height / 2, width: width, height: height)
            g.aspect = CropAspect.allCases.first { preset in
                preset.fixedRatio.map { abs($0 - ratio) < 0.000001 } ?? false
            } ?? (abs(ratio - aspect) < 0.000001 ? .original : .free)
            g = g.fitted(in: size)
            g.intendedSize = CGSize(width: g.crop.width, height: g.crop.height)
            result.geometry = MobileGeometry(value: g)
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
