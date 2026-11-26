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
    static func previewAngle(layer: CGFloat, capture: CGFloat, rearSelfie: Bool) -> CGFloat {
        guard rearSelfie, capture.isFinite, layer.isFinite else { return layer }
        // In the measured open-outer handoff, the verified still reference
        // appeared a quarter-turn clockwise in the finder. Invert the layer's
        // relative display offset instead of baking a fixed turn into pixels.
        let displayOffset = (layer - capture).remainder(dividingBy: 360)
        let angle = (capture - displayOffset).truncatingRemainder(dividingBy: 360)
        return angle < 0 ? angle + 360 : angle
    }

    static func outerControlRotation(scene: Double, device: Double) -> Double {
        (scene - device).remainder(dividingBy: 360)
    }

    static func developmentRotation(capture: CGFloat, preview: CGFloat) -> CGFloat {
        (preview - capture).remainder(dividingBy: 360)
    }

    static func usesFullOuterAperture(isInner: Bool, hingeClosed: Bool, rearSelfie: Bool) -> Bool {
        !isInner && (hingeClosed || rearSelfie)
    }

    static func previewCanvas(panel: CGSize, bottomSafeArea: CGFloat, isInner: Bool, isTabletop: Bool) -> CGSize {
        guard isInner, isTabletop || panel.width > panel.height, bottomSafeArea.isFinite, bottomSafeArea > 0
        else { return panel }
        return CGSize(width: panel.width, height: panel.height + bottomSafeArea)
    }

    /// Coordinates relative to the chrome's safe layout. The preview and
    /// development animation extend behind the chrome together.
    static func outerViewport(safeSize: CGSize, top: CGFloat, leading: CGFloat,
                              bottom: CGFloat, trailing: CGFloat) -> CGRect {
        CGRect(x: -leading, y: -top,
               width: safeSize.width + leading + trailing,
               height: safeSize.height + top + bottom)
    }

    static func aspectSize(in bounds: CGSize, aspect: CGFloat, cover: Bool) -> CGSize {
        guard bounds.width > 0, bounds.height > 0, aspect.isFinite, aspect > 0 else { return .zero }
        let width = cover ? max(bounds.width, bounds.height * aspect) : min(bounds.width, bounds.height * aspect)
        return CGSize(width: width, height: width / aspect)
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
        return aspectSize(in: canvas, aspect: aspect, cover: false)
    }
}

/// Physical repeat cells give a stable identity to each loaded view, including
/// when passing through the last/first stock in the catalog.
struct MobileWaistFilmTrack {
    let count: Int
    var slotCount: Int { count > 1 ? count * 9 : 1 }

    func index(at slot: Int) -> Int { ((slot % count) + count) % count }
    func interiorSlot(of index: Int) -> Int { count > 1 ? 4 * count + index : 0 }
    func isNearPhysicalEnd(_ slot: Int) -> Bool {
        count > 1 && (slot < count || slot >= slotCount - count)
    }

    func closestSlot(of index: Int, to slot: Int) -> Int {
        let sameLap = (slot / count) * count + index
        return [sameLap, sameLap - count, sameLap + count]
            .filter { (0..<slotCount).contains($0) }
            .min { abs($0 - slot) < abs($1 - slot) } ?? interiorSlot(of: index)
    }

    func slot(offset: CGFloat, inset: CGFloat, pitch: CGFloat) -> Int {
        guard pitch > 0, offset.isFinite, inset.isFinite else { return interiorSlot(of: 0) }
        let steps = ((offset + inset) / pitch).rounded()
        return Int(min(CGFloat(slotCount - 1), max(0, steps)))
    }

    func centerOffset(at slot: Int, pitch: CGFloat) -> CGFloat {
        CGFloat(slot) * pitch
    }

    func coastOffset(projected: CGFloat, pitch: CGFloat, reduceMotion: Bool) -> CGFloat {
        let slot = slot(offset: projected, inset: 0, pitch: pitch)
        let center = centerOffset(at: slot, pitch: pitch)
        guard !reduceMotion, projected.isFinite else { return center }
        let slack = min(pitch * 0.10, 11)
        let coast = center + min(slack, max(-slack, projected - center))
        return min(centerOffset(at: slotCount - 1, pitch: pitch), max(0, coast))
    }

    func centerError(at slot: Int, offset: CGFloat, inset: CGFloat, pitch: CGFloat) -> CGFloat {
        offset + inset - centerOffset(at: slot, pitch: pitch)
    }

    private static let neighborScale: CGFloat = 0.64

    static func coverSeparation(at position: CGFloat, width: CGFloat, pitch: CGFloat) -> CGFloat {
        let distance = min(2, abs(position))
        let separation = max(0, width * (1 + neighborScale) / 2 - pitch + 2)
        // Keep the hero cover clear. The second neighbor only needs enough
        // separation to peek out at the rim, not to become another full card.
        let weight = distance <= 1 ? distance : 1 - 0.70 * (distance - 1)
        return separation * weight * (position < 0 ? -1 : 1)
    }

    static func pose(at position: CGFloat, reduceMotion: Bool)
        -> (scale: CGFloat, angle: Double, depth: CGFloat, opacity: Double)
    {
        let distance = min(2, abs(position))
        let focus = 1 - min(1, distance)
        let easedFocus = focus * focus * (3 - 2 * focus)
        return (
            scale: neighborScale + easedFocus * (1 - neighborScale) - max(0, distance - 1) * 0.10,
            angle: reduceMotion ? 0 : Double(max(-1.22, min(1.22, position))) * -17,
            depth: reduceMotion ? 0 : min(8, distance * distance * 4),
            opacity: max(0.42, 1 - Double(distance) * 0.23)
        )
    }
}
