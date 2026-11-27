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

    static func compactCoastGain(for velocity: CGFloat) -> CGFloat {
        // Keep precise, slow selection unchanged; only give a quick flick
        // more runway. The existing high-speed friction cap remains.
        guard velocity.isFinite else { return 1.35 }
        let t = min(1, max(0, (abs(velocity) - 5) / 13))
        return 1.35 + 0.80 * t * t * (3 - 2 * t)
    }

    func release(from coordinate: CGFloat, velocity: CGFloat, startedAt: TimeInterval,
                 coastGain: CGFloat = 1) -> Settle {
        let speed = velocity.isFinite ? velocity : 0
        let springThreshold: CGFloat = 1.1     // cover slots per second
        // Keep the fastest throws bounded by stronger friction, not by
        // clamping the first frame's velocity and visibly grabbing the strip.
        let drag: CGFloat = 3.35 * max(1, abs(speed) / 12) / coastGain
        let coastDuration = log(max(1, abs(speed) / springThreshold)) / drag
        let coastEnd = coordinate - speed * expm1(-drag * coastDuration) / drag
        let coastVelocity = speed * exp(-drag * coastDuration)
        let destination = nearestSlot(to: coastEnd + coastVelocity * 0.10)
        return Settle(origin: coordinate, destination: destination, velocity: speed, startedAt: startedAt,
                      coastDuration: coastDuration, drag: drag, springDuration: 0.31)
    }

    /// A pan may take over mid-coast, after the recognizer has consumed
    /// several points. Only subsequent finger travel moves the displayed slot.
    struct Grab {
        let position: CGFloat
        let translation: CGFloat
        let pitch: CGFloat

        func position(at drag: CGFloat) -> CGFloat { position - (drag - translation) / pitch }
    }

    /// A continuous presentation transition, independent of the mechanical
    /// slot/coast state. Interruptions start at the actually displayed fold.
    struct Fold: Equatable {
        let origin: CGFloat
        let destination: CGFloat
        let began: TimeInterval
        let duration: TimeInterval

        func amount(at now: TimeInterval) -> CGFloat {
            let t = CGFloat(min(1, max(0, (now - began) / duration)))
            return origin + (destination - origin) * t * t * (3 - 2 * t)
        }
    }

    struct Aperture {
        let size: CGSize
        var width: CGFloat {
            min(242, max(1, size.width * 0.42), max(1, size.height - 40) * 16 / 9)
        }
        var height: CGFloat { width * 9 / 16 }
        var pitch: CGFloat { max(1, min(width * 0.90, size.width * 0.282)) }
        var compactPitch: CGFloat { max(1, pitch * 0.43) }

        func dragPitch(reduceMotion: Bool) -> CGFloat { reduceMotion ? pitch : compactPitch }

        // Rotating the reference rack does not rotate the 16:9 film art:
        // its vertical edge stays the short edge. A fixed lane prevents
        // the selected card and its name from expanding as the drag begins.
        var laneHeight: CGFloat { height + 12 }

        private var focalLength: CGFloat { max(1, width * 3.2, size.width * 1.08) }
        private var coverGap: CGFloat { min(6, width * 0.05) }

        private func naturalCenter(at distance: CGFloat) -> CGFloat {
            distance * pitch + MobileWaistFilmTrack.coverSeparation(at: distance, width: width, pitch: pitch)
        }

        private func pose(at distance: CGFloat, center: CGFloat, reduceMotion: Bool) -> CoverPose {
            let projected = MobileWaistFilmTrack.restingPose(at: distance, screenX: center, focalLength: focalLength,
                                                           reduceMotion: reduceMotion)
            return projected.fittedVertically(width: width, height: height, halfLane: height / 2)
        }

        private func edge(at distance: CGFloat, center: CGFloat, side: CGFloat) -> CGFloat {
            let point = CGPoint(x: side * width / 2, y: 0)
            let tilted = pose(at: distance, center: center, reduceMotion: false)
            return center + side * max(abs(tilted.project(point).x), abs(point.x) * tilted.verticalScale)
        }

        private func restingCenter(of slot: Int, at coordinate: CGFloat) -> CGFloat {
            let leftSlot = Int(floor(coordinate))
            let phase = coordinate - CGFloat(leftSlot)
            let leftDistance = -phase, rightDistance = 1 - phase
            let naturalLeft = naturalCenter(at: leftDistance)
            let naturalRight = naturalCenter(at: rightDistance)
            var left = naturalLeft, right = naturalRight
            // Keep a gutter between projected edges throughout the drag.
            // The nearer cover moves less; on a detent it stays on the axis.
            for _ in 0..<6 {
                let gap = edge(at: rightDistance, center: right, side: -1)
                    - edge(at: leftDistance, center: left, side: 1)
                guard gap < coverGap - 0.001 else { break }
                let correction = coverGap - gap
                left -= correction * phase
                right += correction * (1 - phase)
            }
            let side: CGFloat = slot <= leftSlot ? -1 : 1
            var current = side < 0 ? leftSlot : leftSlot + 1
            var center = side < 0 ? left : right
            // Keep the original placement of the outer covers unless their
            // visible edges would touch. This preserves the outer peek.
            while current != slot {
                let precedingEdge = edge(at: CGFloat(current) - coordinate, center: center, side: side)
                current += side < 0 ? -1 : 1
                let distance = CGFloat(current) - coordinate
                center = naturalCenter(at: distance)
                for _ in 0..<6 {
                    let facingEdge = edge(at: distance, center: center, side: -side)
                    let correction = coverGap - side * (facingEdge - precedingEdge)
                    guard correction > 0.001 else { break }
                    center += side * correction
                }
            }
            return size.width / 2 + center
        }

        struct Cover: Equatable {
            let centerX: CGFloat
            let pose: CoverPose
        }

        // The two vertical edges of an upright flat print in screen points.
        // y is the projected half-height above and below the shared horizon.
        private struct Edges {
            let left: CGPoint
            let right: CGPoint

            func blended(toward other: Edges, amount: CGFloat) -> Edges {
                func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
                    CGPoint(x: a.x + amount * (b.x - a.x), y: a.y + amount * (b.y - a.y))
                }
                return Edges(left: mix(left, other.left), right: mix(right, other.right))
            }

            func cover(width: CGFloat, height: CGFloat, opacity: Double) -> Cover {
                // Opposite edge heights recover the homogeneous depths. This
                // homography maps all four corners exactly and keeps type upright.
                let sum = left.y + right.y
                let skew = (left.y - right.y) / sum
                let center = left.x + (right.x - left.x) * left.y / sum
                let pose = CoverPose(horizontalScale: (right.x - left.x) * (1 - skew * skew) / width,
                                     verticalScale: 4 * left.y * right.y / (sum * height),
                                     perspective: 2 * skew / width, opacity: opacity)
                return Cover(centerX: center, pose: pose)
            }
        }

        private func stackEdges(at distance: CGFloat) -> Edges {
            let spine = distance * compactPitch
            // Project the back edge of a sleeve pointing into the rack. Every
            // spine is on the front plane, every bank shares this eye and depth.
            // In sleeve-width units, the eye is 1.5 from the front plane
            // and 2.5 from the rear plane.
            let backScale: CGFloat = 1.5 / 2.5
            let parallelReach = abs(spine) * (1 - backScale)
            // Fan the rear edges outward as they approach the preceding spine.
            // The reach approaches the gutter smoothly as a cover moves out.
            let limit = compactPitch - coverGap
            let shoulder = limit * 0.75
            let excess = max(0, parallelReach - shoulder)
            let reach = min(parallelReach, shoulder) + excess / (1 + excess / (limit - shoulder))
            let middle = size.width / 2 + spine - (spine < 0 ? -reach : reach) / 2

            // Round the edge-on crossing in screen space. Both edges keep
            // exchanging depth through the middle without mirroring the print.
            let crossing = 0.76 * compactPitch
            let faceWidth = reach < crossing ? (crossing + reach * reach / crossing) / 2 : reach
            let bank = distance + 0.28
            let t = min(1, abs(bank) / 1.3)
            let squared = distance * distance
            // Both banks get progressively lower away from the center.
            // At the detent the upright edge is exactly the original height;
            // use just enough opposing skew to keep the thin face readable.
            let near = height / 2 / (1 + 0.16 * squared / (1 + 0.32 * squared))
            let sideDepth = (bank < 0 ? -1 : 1) * (1 - backScale) * t * t * (3 - 2 * t)
            // The center print stays tipped toward the same bank while it
            // traverses the axis. The receding edge stays short instead of
            // briefly drawing a square. Swap banks outside the center zone.
            let blend = min(1, max(0, (abs(distance) - 0.38) / 0.42))
            let depth = 0.25 + (sideDepth - 0.25) * blend * blend * (3 - 2 * blend)
            return Edges(left: CGPoint(x: middle - faceWidth / 2, y: near * (1 - max(0, depth))),
                         right: CGPoint(x: middle + faceWidth / 2, y: near * (1 + min(0, depth))))
        }

        func cover(of slot: Int, at coordinate: CGFloat, reduceMotion: Bool, fold: CGFloat = 0) -> Cover {
            let distance = CGFloat(slot) - coordinate
            let amount = reduceMotion ? 0 : fold
            let opacity = max(0.44, 1 - Double(abs(distance)) * (0.21 - 0.095 * Double(amount)))
            if amount == 1 { return stackEdges(at: distance).cover(width: width, height: height, opacity: opacity) }
            let center = restingCenter(of: slot, at: coordinate)
            let open = pose(at: distance, center: center - size.width / 2, reduceMotion: reduceMotion)
            guard amount > 0 else { return Cover(centerX: center, pose: open) }
            func edge(_ x: CGFloat) -> CGPoint {
                let p = open.project(CGPoint(x: x, y: height / 2))
                return CGPoint(x: center + p.x, y: p.y)
            }
            // Interpolating visible edges preserves positive gutters and lane
            // clearance at every intermediate fold and fractional track phase.
            let rest = Edges(left: edge(-width / 2), right: edge(width / 2))
            return rest.blended(toward: stackEdges(at: distance), amount: amount)
                .cover(width: width, height: height, opacity: opacity)
        }

        func slots(around center: Int, fold: CGFloat = 0) -> ClosedRange<Int> {
            let spacing = pitch + (compactPitch - pitch) * fold
            let radius = min(9, max(3, Int(ceil((size.width + width) / (2 * spacing))) + 1))
            return (center - radius)...(center + radius)
        }
    }

    /// Landscape-friendly stack of flat film sleeves ordered back to front.
    /// Relative coordinates are continuous so a sleeve never jumps between ranks.
    struct Wallet {
        let size: CGSize
        var laneHeight: CGFloat { max(1, size.height - 26) }
        var pitch: CGFloat { min(39, max(20, laneHeight * 0.105)) }
        private var fullWidth: CGFloat { max(1, min(336, size.width * 0.70, laneHeight * 1.02)) }

        struct Card {
            let frame: CGRect
            let opacity: Double
            let shade: Double
        }

        func card(at relative: CGFloat, reveal: CGFloat) -> Card {
            let progress = min(1, max(0, (relative + 5.5) / 7.8))
            let peak = max(0, 1 - abs(relative))
            let pop = peak * peak * reveal
            // Depth is uniform scaling, overlap and shading, never a warp.
            let width = fullWidth * (0.42 + 0.58 * progress + 0.05 * pop)
            let height = width * 9 / 16
            let travel = max(0, laneHeight - fullWidth * 9 / 16 - 15)
            let expanded = pow(progress, 1.58)
            let compact = 0.28 + expanded * 0.56
            let upper = 8 + travel * (expanded + (compact - expanded) * reveal)
                - min(28, travel * 0.41) * pop
            let revealX = min(24, size.width * 0.06) * pop
            // Only the edge slots fade in transit. At a detent the stack is opaque.
            let edge = min(1, max(0, relative + 5), max(0, 2 - relative))
            let alpha = edge * edge * (3 - 2 * edge)
            let shade = max(0, (1 - progress) * 0.32 - 0.12 * pop)
            return Card(frame: CGRect(x: (size.width - width) / 2 + revealX, y: upper,
                                      width: width, height: height), opacity: Double(alpha), shade: Double(shade))
        }

        func slots(at coordinate: CGFloat, count: Int) -> ClosedRange<Int> {
            let focus = Int(coordinate.rounded())
            if count == 1 { return focus...focus }
            if count < 10 { return (focus - count + 2)...(focus + 1) }
            let lower = Int(floor(coordinate))
            return (lower - 6)...(lower + 3)
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

        func fittedVertically(width: CGFloat, height: CGFloat, halfLane: CGFloat) -> CoverPose {
            let corner = CGPoint(x: perspective < 0 ? width / 2 : -width / 2, y: height / 2)
            let tip = abs(project(corner).y)
            guard tip > halfLane else { return self }
            let fit = halfLane / tip
            return CoverPose(horizontalScale: horizontalScale * fit, verticalScale: verticalScale * fit,
                             perspective: perspective, opacity: opacity)
        }

        func unproject(_ point: CGPoint) -> CGPoint? {
            let divisor = horizontalScale - perspective * point.x
            guard divisor > 0 else { return nil }
            let x = point.x / divisor
            let y = point.y * (1 + perspective * x) / verticalScale
            return CGPoint(x: x, y: y)
        }
    }

    private static func restingPose(at position: CGFloat, screenX: CGFloat, focalLength: CGFloat, reduceMotion: Bool) -> CoverPose {
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
