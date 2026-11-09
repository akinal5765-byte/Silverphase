import Foundation

// Shared by capture, the editor and the lock-screen handoff. These select the
// film pipeline's metering/diffusion, independently of AVFoundation exposure.
enum MobileMeteringMode: String, CaseIterable, Codable, Sendable {
    case custom, balanced, center, protect_highlights, protect_shadows, center_weighted

    var title: String {
        switch self {
        case .custom: "关闭胶片自动测光"
        case .balanced: "均衡"
        case .center: "中央主体"
        case .protect_highlights: "保护高光"
        case .protect_shadows: "保护阴影"
        case .center_weighted: "中央加权"
        }
    }
}

enum MobileDiffusionFilter: String, CaseIterable, Codable, Sendable {
    case off, glimmerglass, black_pro_mist, pro_mist, cinebloom

    var title: String {
        switch self {
        case .off: "关闭"
        case .glimmerglass: "Glimmerglass"
        case .black_pro_mist: "Black Pro-Mist"
        case .pro_mist: "Pro-Mist"
        case .cinebloom: "Cinebloom"
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
