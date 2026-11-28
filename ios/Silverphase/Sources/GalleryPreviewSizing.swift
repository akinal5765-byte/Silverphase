import Foundation
import CoreGraphics

enum MobileFilmGate {
    static func size(_ id: String) -> (Double, Double) {
        switch id {
        case "135_half": (24, 18)
        case "120_645": (56, 41.5)
        case "120_6x6": (56, 56)
        case "120_6x7": (69.5, 56)
        case "120_6x8": (76, 56)
        case "120_6x9": (84, 56)
        case "135_xpan": (65, 24)
        case "120_6x12": (112, 56)
        case "120_6x17": (168, 56)
        default: (36, 24)
        }
    }
    static func aspect(for picture: CGSize, recipe: [String: ParamValue]) -> Double? {
        guard recipe["overscan_active"]?.boolValue == true else { return nil }
        let gate = size(recipe["overscan_format"]?.stringValue ?? "135")
        return picture.width >= picture.height ? gate.0 / gate.1 : gate.1 / gate.0
    }
    static func presents(_ recipe: [String: ParamValue]) -> Bool {
        recipe["overscan_active"]?.boolValue == true || recipe["date_imprint_active"]?.boolValue == true
    }
}

/// Gallery-only policy. Dimensions are in pixels (never points).
enum GalleryPreviewSizing {
    /// Same centre crop and integer rounding used when feeding the film gate.
    static func gateRect(in extent: CGRect, aspect: Double) -> CGRect {
        let width = max(1, min(extent.width, extent.height * aspect).rounded(.down))
        let height = max(1, (width / aspect).rounded())
        return CGRect(x: (extent.midX - width / 2).rounded(.down),
                      y: (extent.midY - height / 2).rounded(.down), width: width, height: height)
    }

    /// The ordinary viewer budget is a *visible* pixel budget. Allow more input
    /// only when cropping discards pixels, and only with the tile renderer's
    /// overlap allowance. 'requested' already has the editor's 3840-input-edge cap.
    static func fitMP(requested: Double, inputSize: CGSize, pictureSize: CGSize, availableBytes: Double) -> Double {
        let visibleFraction = min(1, (pictureSize.width * pictureSize.height) / max(1, inputSize.width * inputSize.height))
        let memoryLimit = (0.72 * availableBytes / 1e6 - 600) / 70
        return min(requested, 3.3 / max(0.001, visibleFraction), max(3.3, memoryLimit))
    }

    /// The processed film border is added *after* the picture is gated; its
    /// dimensions vary with the format, seeds and carrier. Scale the measured
    /// output instead of duplicating the C++ border layout or counting it twice.
    static func nativeCanvas(fit: CGSize, inputMP: Double, nativeMP: Double) -> CGSize {
        let scale = sqrt(nativeMP / min(inputMP, nativeMP))
        return CGSize(width: (fit.width * scale).rounded(), height: (fit.height * scale).rounded())
    }
}
