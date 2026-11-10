import Foundation

// Shared by capture, the editor and the lock-screen handoff. These select the
// film pipeline's metering/diffusion, independently of AVFoundation exposure.
//
// `title` is `@MainActor` because the copy comes from `T(_:_:_:)`, which reads
// the language setting; every use of it is in a view or a capture-chrome label.
// The wire values (`rawValue`) are untouched by translation — they are what the
// sidecar and the engine read.
enum MobileMeteringMode: String, CaseIterable, Codable, Sendable {
    case custom, balanced, center, protect_highlights, protect_shadows, center_weighted

    @MainActor var title: String {
        switch self {
        case .custom:
            T("Auto exposure off (RAW baseline)", "关闭胶片自动测光", "關閉膠片自動測光")
        case .balanced: T("Balanced", "均衡", "均衡")
        case .center: T("Center", "中央主体", "中央主體")
        case .protect_highlights: T("Protect highlights", "保护高光", "保護高光")
        case .protect_shadows: T("Protect shadows", "保护阴影", "保護陰影")
        case .center_weighted: T("Center weighted", "中央加权", "中央加權")
        }
    }
}

enum MobileDiffusionFilter: String, CaseIterable, Codable, Sendable {
    case off, glimmerglass, black_pro_mist, pro_mist, cinebloom

    /// The four filters keep the brand names they are sold under, and the two
    /// Pro-Mist densities are named — which is the line the desktop table
    /// draws too (its 简体 column says 黑柔 / 白柔). Translating
    /// `Black Pro-Mist` into words would invent a product; leaving the
    /// densities in English would leave a Chinese reader with nothing to tell
    /// the two apart but the word "Black".
    @MainActor var title: String {
        switch self {
        case .off: T("Off", "关闭", "關閉")
        case .glimmerglass: "Glimmerglass"
        case .black_pro_mist: T("Black Pro-Mist", "黑柔", "黑柔")
        case .pro_mist: T("Pro-Mist", "白柔", "白柔")
        case .cinebloom: "CineBloom"
        }
    }
}

struct MobileCameraRecipe: Codable, Equatable, Hashable, Sendable {
    static let defaultFilmID = "kodak_portra_400"
    // Optional so captures from earlier extension versions remain readable.
    var filmID: String? = nil
    var metering: MobileMeteringMode = .center_weighted
    var diffusion: MobileDiffusionFilter = .off

    static func sidecar(for original: URL) -> URL {
        original.appendingPathExtension("camera.json")
    }

#if SILVERPHASE_APP
    var values: [String: WireValue] {
        var result: [String: WireValue] = [
            "auto_exposure": .bool(metering != .custom),
            "camera_diffusion_active": .bool(diffusion != .off),
            "camera_diffusion_strength": .double(0.5),
            "camera_diffusion_range": .double(1),
        ]
        if metering != .custom { result["auto_exposure_method"] = .string(metering.rawValue) }
        if diffusion != .off { result["camera_diffusion_family"] = .string(diffusion.rawValue) }
        return result
    }
#endif
}
