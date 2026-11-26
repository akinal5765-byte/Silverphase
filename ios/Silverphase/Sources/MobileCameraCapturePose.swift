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

    /// Divider frames above are already in GeometryReader-local points.
    /// The reader's origin is the safe edge, so restore the omitted sides
    /// for the wheel only. The lower camera stays inside its existing layout.
    func upperWheelFrame(leading: CGFloat, trailing: CGFloat) -> CGRect {
        CGRect(x: upper.minX - leading, y: upper.minY,
               width: upper.width + leading + trailing, height: upper.height)
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

    /// Permit a small center crop on the lower panel, not a large crop when a
    /// portrait photograph and the tabletop panel have opposing axes.
    static func tabletopCanFill(canvas: CGSize, aspect: CGFloat) -> Bool {
        guard canvas.width > 0, canvas.height > 0, aspect.isFinite, aspect > 0 else { return false }
        let fit = aspectSize(in: canvas, aspect: aspect, cover: false)
        let cover = aspectSize(in: canvas, aspect: aspect, cover: true)
        return cover.width <= fit.width * 1.12
    }

    static func imageSize(in canvas: CGSize, aspect: CGFloat, fillsPanel: Bool) -> CGSize {
        guard canvas.width > 0, canvas.height > 0 else { return .zero }
        if fillsPanel { return canvas }
        return aspectSize(in: canvas, aspect: aspect, cover: false)
    }
}

/// A logical track in units of covers, independent of aperture width and
/// screen origin. Crossing either catalog end only wraps the artwork index.
struct MobileWaistFilmTrack {
    let count: Int

    func index(at slot: Int) -> Int { ((slot % count) + count) % count }

    func closestSlot(of index: Int, to slot: Int) -> Int {
        let sameLap = slot - self.index(at: slot) + index
        return [sameLap, sameLap - count, sameLap + count]
            .min { abs($0 - slot) < abs($1 - slot) } ?? sameLap
    }

    func nearestSlot(to coordinate: CGFloat) -> Int { Int(coordinate.rounded()) }

    func release(from coordinate: CGFloat, velocity: CGFloat, startedAt: TimeInterval) -> Settle {
        let speed = velocity.isFinite ? velocity : 0
        let springThreshold: CGFloat = 1.1     // cover slots per second
        // Keep the fastest throws bounded by stronger friction, not by
        // clamping the first frame's velocity and visibly grabbing the strip.
        let drag: CGFloat = 3.35 * max(1, abs(speed) / 12)
        let coastDuration = log(max(1, abs(speed) / springThreshold)) / drag
        let coastEnd = coordinate - speed * expm1(-drag * coastDuration) / drag
        let coastVelocity = speed * exp(-drag * coastDuration)
        let destination = nearestSlot(to: coastEnd + coastVelocity * 0.10)
        return Settle(origin: coordinate, destination: destination, velocity: speed, startedAt: startedAt,
                      coastDuration: coastDuration, drag: drag, springDuration: 0.31)
    }

    struct Aperture {
        let size: CGSize
        var width: CGFloat {
            min(242, max(1, size.width * 0.42), max(1, size.height - 40) * 16 / 9)
        }
        var height: CGFloat { width * 9 / 16 }
        var pitch: CGFloat { max(1, min(width * 0.90, size.width * 0.282)) }
        var laneHeight: CGFloat { height + 12 }

        func centerX(of slot: Int, at coordinate: CGFloat) -> CGFloat {
            let distance = CGFloat(slot) - coordinate
            return size.width / 2 + distance * pitch
                + MobileWaistFilmTrack.coverSeparation(at: distance, width: width, pitch: pitch)
        }

        func coverPose(of slot: Int, at coordinate: CGFloat, reduceMotion: Bool) -> CoverPose {
            let center = centerX(of: slot, at: coordinate) - size.width / 2
            return MobileWaistFilmTrack.pose(at: CGFloat(slot) - coordinate, screenX: center,
                                            focalLength: max(1, width * 3.2, size.width * 1.08),
                                            reduceMotion: reduceMotion)
        }

        func slots(around center: Int) -> ClosedRange<Int> {
            let radius = min(6, max(3, Int(ceil((size.width + width) / (2 * pitch))) + 1))
            return (center - radius)...(center + radius)
        }
    }

    struct Settle: Equatable {
        let origin: CGFloat
        let destination: Int
        let velocity: CGFloat
        let startedAt: TimeInterval
        let coastDuration: TimeInterval
        private let drag: CGFloat
        private let springDuration: TimeInterval
        var duration: TimeInterval { coastDuration + springDuration }

        init(origin: CGFloat, destination: Int, velocity: CGFloat, startedAt: TimeInterval,
             coastDuration: TimeInterval = 0, drag: CGFloat = 0, springDuration: TimeInterval = 0.43) {
            self.origin = origin
            self.destination = destination
            self.velocity = velocity
            self.startedAt = startedAt
            self.coastDuration = coastDuration
            self.drag = drag
            self.springDuration = springDuration
        }

        private func coastPosition(at elapsed: TimeInterval) -> CGFloat {
            guard drag > 0 else { return origin }
            return origin - velocity * expm1(-drag * elapsed) / drag
        }

        func position(at time: TimeInterval) -> CGFloat {
            let elapsed = max(0, time - startedAt)
            let target = CGFloat(destination)
            guard elapsed < duration else { return target }
            guard elapsed >= coastDuration else { return coastPosition(at: elapsed) }

            // The spring starts at the actual end of the coast with the same
            // velocity. Ease its residual to 0 so both position and velocity
            // land exactly on the detent, even on a dropped final frame.
            let damping: CGFloat = 19
            let difference = coastPosition(at: coastDuration) - target
            let speed = velocity * exp(-drag * coastDuration)
            let t = CGFloat(elapsed - coastDuration)
            let fade = min(1, max(0, (t / springDuration - 0.7) / 0.3))
            let weight = 1 - fade * fade * (3 - 2 * fade)
            return target + (difference + (speed + damping * difference) * t) * exp(-damping * t) * weight
        }
    }

    private static let neighborScale: CGFloat = 1 / (1 + 0.59 / 1.42)

    static func coverSeparation(at position: CGFloat, width: CGFloat, pitch: CGFloat) -> CGFloat {
        let distance = min(2, abs(position))
        let separation = max(0, width * (1 + neighborScale) / 2 - pitch + 2)
        // Keep the hero cover clear. The second neighbor only needs enough
        // separation to peek out at the rim, not to become another full card.
        let weight = distance <= 1 ? distance : 1 - 0.70 * (distance - 1)
        return separation * weight * (position < 0 ? -1 : 1)
    }

    struct CoverPose: Equatable {
        let horizontalScale: CGFloat
        let verticalScale: CGFloat
        let perspective: CGFloat
        let opacity: Double

        func project(_ point: CGPoint) -> CGPoint {
            let depth = 1 + perspective * point.x
            return CGPoint(x: horizontalScale * point.x / depth, y: verticalScale * point.y / depth)
        }

        func contains(_ point: CGPoint, width: CGFloat, height: CGFloat) -> Bool {
            // Invert the same common-camera projection used by the renderer;
            // hit testing must not use the pre-tilt, rectangular artwork bounds.
            let divisor = horizontalScale - perspective * point.x
            guard divisor > 0 else { return false }
            let x = point.x / divisor
            let y = point.y * (1 + perspective * x) / verticalScale
            return abs(x) <= width / 2 && abs(y) <= height / 2
        }
    }

    static func pose(at position: CGFloat, screenX: CGFloat, focalLength: CGFloat, reduceMotion: Bool) -> CoverPose {
        let distance = abs(position)
        let squared = distance * distance
        // Recede along a shallow track, not individual up/down translations.
        // A centered observer and focal length are shared by every card.
        let depth = 1 + 0.59 * squared / (1 + 0.42 * squared)
        let yaw = reduceMotion ? 0 : -atan(screenX / focalLength) * 0.66
        let slope = sin(yaw) / focalLength
        return CoverPose(horizontalScale: (cos(yaw) - screenX * slope) / depth,
                         verticalScale: 1 / depth, perspective: slope / depth,
                         opacity: max(0.44, 1 - Double(distance) * 0.21))
    }
}
