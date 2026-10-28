import Foundation

/// Captured from the current desktop FilmParams.default.wire by the desktop
/// contract test; never substitute the engine/reference defaults for the UI.
enum MobileProcessContract {
    struct Frame: Decodable, Sendable { let id: String; let short: Double; let long: Double }
    struct UI: Decodable, Sendable { let frames: [Frame] }
    struct Contract: Decodable, Sendable { let wire: [String: WireValue]; let ui: UI }
    private static let loaded: Result<Contract, Error> = Result {
        guard let url = Bundle.main.url(forResource: "DesktopControlDefaults", withExtension: "json", subdirectory: StockCatalog.resourceDirectory) else {
            throw MobileFailure.message("缺少与桌面端对照的默认参数")
        }
        return try JSONDecoder().decode(Contract.self, from: Data(contentsOf: url))
    }
    static var defaults: [String: WireValue] { (try? loaded.get().wire) ?? [:] }
    static var frames: [Frame] { (try? loaded.get().ui.frames) ?? [] }
    static let clientDefaults: [String: WireValue] = [
        "_grainAmount": .double(1), "_grainSoftness": .double(1), "_scannerActive": .bool(true), "_scannerStrength": .double(1),
        "_filmFrame": .string("135"), "_filmSide": .string("short"), "_sideLengthMM": .double(24), "_sideUnit": .string("mm"),
        "_dateOrder": .string("japan"), "_dateWithData": .bool(false), "_whiteBalancePreset": .string("asShot"),
        "_printEffects": .bool(true), "_printBrightnessStops": .double(0), "_diBlue": .bool(false),
        "overscan_format": .string("135"), "overscan_mode": .string("strip"), "overscan_gate": .string("auto"),
        "overscan_holes": .string("white"), "overscan_carrier": .string("none"), "overscan_fog": .double(1),
        "overscan_leaks": .double(0), "overscan_frame_number": .double(0), "overscan_camera_seed": .double(1), "overscan_frame_seed": .double(1),
        "date_imprint_style": .string("lcd"), "date_imprint_text": .string(""), "date_imprint_placement": .string("frame"),
        "date_imprint_corner": .string("br"), "date_imprint_ev": .double(3.5), "date_imprint_size": .double(1),
        "date_imprint_inset_x": .double(3), "date_imprint_inset_y": .double(2.4),
    ]
    static let steps: [String: Double] = [
        "_temperature": 100, "_tint": 5, "exposure_compensation_ev": 1.0 / 3,
        "_grainAmount": 0.1, "grain_size_scale": 0.1, "_grainSoftness": 0.1,
        "halation_amount": 0.1, "halation_scatter_amount": 0.1, "density_curve_gamma": 0.05,
        "dir_couplers_amount": 0.05, "print_contrast": 0.05, "y_filter_shift": 1, "m_filter_shift": 1,
        "preflash_exposure": 0.005, "_scannerStrength": 0.1, "glare_amount": 0.1,
        "camera_diffusion_strength": 0.125, "enlarger_diffusion_strength": 0.125,
        "camera_diffusion_range": 0.1, "enlarger_diffusion_range": 0.1, "overscan_frame_number": 1,
        "_placementHighlight": 0.25, "_placementShadow": 0.25,
    ]
    static func ownGrain(_ id: String) -> Double {
        switch StockCatalog.canonicalID(id) {
        case "kodak_tri_x_400": 1.70
        case "ilford_hp5_plus_400": 1.49
        case "kodak_tmax_100": 0.74
        case "fujifilm_neopan_acros_100_ii": 0.64
        default: 1
        }
    }
    static func wire(_ recipe: [String: WireValue], aspect: Double) throws -> [String: WireValue] {
        var values = try loaded.get().wire
        values.merge(recipe.filter { !$0.key.hasPrefix("_") }) { _, new in new }
        func number(_ key: String, _ fallback: Double) -> Double { recipe[key]?.doubleValue ?? fallback }
        func bool(_ key: String, _ fallback: Bool) -> Bool { recipe[key]?.boolValue ?? fallback }
        let film = values["film_stock"]?.stringValue ?? "kodak_portra_400"
        let positive = StockCatalog.shared.stock(film)?.isPositive == true
        let paper = values["print_stock"]?.stringValue ?? "kodak_supra_endura"
        let monoPaper = StockCatalog.shared.stock(paper)?.isMonochrome == true
        let upstreamBW = ownGrain(film) != 1
        let scan = positive || values["scan_film"]?.boolValue == true
        let di = !scan && values["digital_intermediate"]?.boolValue == true
        values["scan_film"] = .bool(scan)
        values["digital_intermediate"] = .bool(di)
        values["digital_intermediate_blue_compensation"] = .bool(di && bool("_diBlue", false))
        values["grain_amount"] = .double(min(2, number("_grainAmount", recipe["grain_amount"]?.doubleValue.map { $0 / ownGrain(film) } ?? 1) * ownGrain(film)))
        values["grain_softness"] = .double(number("_grainSoftness", number("grain_softness", 0.65) / 0.65) * 0.65)
        values["grain_sublayers_active"] = .bool(!upstreamBW && values["grain_active"]?.boolValue == true && values["grain_sublayers_active"]?.boolValue == true)
        values["scanner_sharpening_amount"] = .double(!di && bool("_scannerActive", true) ? 0.7 * number("_scannerStrength", number("scanner_sharpening_amount", 0.7) / 0.7) : 0)
        if let stops = recipe["_printBrightnessStops"]?.doubleValue { values["print_exposure"] = .double(pow(2, -stops)) }
        let effects = bool("_printEffects", true)
        values["glare_active"] = .bool(!scan && !di && effects && values["glare_active"]?.boolValue == true)
        if !effects { values["preflash_exposure"] = .double(0) }
        values["extended_dynamic_range"] = .bool(!scan && !di && !monoPaper && values["extended_dynamic_range"]?.boolValue == true)
        if scan || di { values["enlarger_diffusion_active"] = .bool(false) }
        if di { values["scene_latitude_active"] = .bool(false) }
        if recipe["film_format_mm"] == nil || recipe["_filmFrame"] != nil || recipe["_filmSide"] != nil {
            let side = recipe["_filmSide"]?.stringValue ?? "short"
            let length = number("_sideLengthMM", 24)
            values["film_format_mm"] = .double(min(200, max(4, side == "long" ? length : length * max(aspect, 1 / max(0.001, aspect)))))
        }
        if paper == "ilford_multigrade_iv_rc", !scan, !di {
            if let url = Bundle.main.url(forResource: "paper_grades", withExtension: "json", subdirectory: StockCatalog.resourceDirectory + "/engine"),
               let table = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
               let grades = table["grades"] as? [String: [String: Double]], let grade = grades[recipe["_paperGrade"]?.stringValue ?? "2"] {
                for key in ["m_filter_neutral", "y_filter_neutral", "c_filter_neutral"] { if let v = grade[key] { values[key] = .double(v) } }
                values["print_exposure"] = .double(min(20, max(0.05, (values["print_exposure"]?.doubleValue ?? 1) * (grade["print_exposure"] ?? 1))))
                values["m_filter_shift"] = .double(0); values["y_filter_shift"] = .double(0)
            }
        }
        // Off stages still show their desktop defaults before first activation.
        for (key, value) in clientDefaults where !key.hasPrefix("_") && values[key] == nil { values[key] = value }
        return values
    }
}
