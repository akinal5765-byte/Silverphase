import CoreGraphics
import Foundation

/// Core Motion's quarter-turn, independent of the host window/interface.
/// Left/right follow capture (interface) orientation, not UIDevice's inverted
/// landscape names. AVFoundation resolves the actual sensor mounting angle.
enum MobileCameraCapturePose: Int, CaseIterable, Sendable {
    case portrait = 0, landscapeLeft = 90, portraitUpsideDown = 180, landscapeRight = 270

    var isLandscape: Bool { self == .landscapeLeft || self == .landscapeRight }

    init(quarterTurn: Double) {
        guard quarterTurn.isFinite else { self = .portrait; return }
        let turn = (quarterTurn.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        self = Self(rawValue: (Int((turn / 90).rounded()) * 90) % 360) ?? .portrait
    }
}

/// Camera-local coordinates. An active horizontal division is the system's
/// tabletop signal; a book-fold division or a flat display is not tabletop.
struct MobileWaistCameraGeometry {
    let upper: CGRect
    let lower: CGRect

    init?(viewport: CGSize, divisionFrames: [CGRect]) {
        let bounds = CGRect(origin: .zero, size: viewport)
        guard let hinge = divisionFrames.first(where: {
            $0.width > $0.height && $0.width >= viewport.width * 0.6
                && $0.minY >= 110 && $0.maxY <= viewport.height - 96
        }) else { return nil }
        upper = CGRect(x: 0, y: 0, width: bounds.width, height: hinge.minY)
        lower = CGRect(x: 0, y: hinge.maxY, width: bounds.width, height: bounds.maxY - hinge.maxY)
    }
}


/// The still photo ratio is fitted inside the canvas, independent of where
/// controls are overlaid. Rotating the connection switches its axes.
enum MobileCameraViewfinderGeometry {
    static func previewCanvas(panel: CGSize, bottomSafeArea: CGFloat, isInner: Bool, isTabletop: Bool) -> CGSize {
        guard isInner, isTabletop || panel.width > panel.height, bottomSafeArea.isFinite, bottomSafeArea > 0
        else { return panel }
        return CGSize(width: panel.width, height: panel.height + bottomSafeArea)
    }

    static func orientedAspect(_ landscapeAspect: CGFloat, angle: CGFloat) -> CGFloat {
        let aspect = landscapeAspect.isFinite && landscapeAspect > 0 ? landscapeAspect : 4.0 / 3.0
        guard angle.isFinite else { return aspect }
        let radians = angle * .pi / 180
        return abs(sin(radians)) > abs(cos(radians)) ? 1 / aspect : aspect
    }

    static func imageSize(in canvas: CGSize, aspect: CGFloat, fillsPanel: Bool) -> CGSize {
        guard canvas.width > 0, canvas.height > 0 else { return .zero }
        if fillsPanel { return canvas }
        let width = min(canvas.width, canvas.height * aspect)
        return CGSize(width: width, height: width / aspect)
    }
}
