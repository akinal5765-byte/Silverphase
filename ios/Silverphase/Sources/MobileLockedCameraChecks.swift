#if DEBUG
import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import UIKit
import SwiftUI

/// Pure configuration checks plus synthetic file/engine checks. No camera,
/// lock-screen activation, Photos permission or private input is used.
enum MobileLockedCameraChecks {
    @MainActor static func run() async {
        var checks: [String] = []
        var maximumDifference = 0
        let folder = URL.temporaryDirectory.appendingPathComponent("LockedCamera-Checks-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let report = URL.documentsDirectory.appendingPathComponent("locked-camera-report.json")
        do {
            func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
                if !condition() { throw MobileFailure.message(message) }
            }
            for (turn, pose) in [(0.0, MobileCameraCapturePose.portrait), (90, .landscapeLeft),
                                 (-90, .landscapeRight), (180, .portraitUpsideDown),
                                 (360, .portrait), (450, .landscapeLeft), (-180, .portraitUpsideDown)] {
                try require(MobileCameraCapturePose(quarterTurn: turn) == pose, "Incorrect physical capture pose")
            }
            try require(MobileCameraCapturePose(quarterTurn: .nan) == .portrait, "Nonfinite pose must not crash")
            checks.append("physical shutter-pose normalization across all four orientations; no host-window input")
            for canonical in [CGSize(width: 393, height: 852), CGSize(width: 768, height: 1024),
                              CGSize(width: 834, height: 1194), CGSize(width: 600, height: 800)] {
                for turn in [0.0, 90, -90, 180] {
                    let swapped = abs(turn) == 90
                    let viewport = swapped ? CGSize(width: canonical.height, height: canonical.width) : canonical
                    let layout = MobileCameraCanvasGeometry(viewport: viewport, interfaceQuarterTurn: turn)
                    try require(layout.contentSize == canonical, "Host rotation changed the camera's canonical layout size")
                }
            }
            checks.append("same camera canvas across four host orientations and phone/tablet/foldable/window sizes")
            let policies: [(Bool, Bool, Bool?, Bool, UIInterfaceOrientationMask)] = [
                (true, false, nil, false, .portrait), (true, false, nil, true, .portrait),
                (true, true, true, false, .all), (true, true, true, true, .portrait),
                (true, true, false, false, .portrait), (true, true, false, true, .portrait),
                (true, true, nil, false, .all), (true, true, nil, true, .portrait),
                (false, true, nil, false, .all), (false, true, nil, true, .portrait)]
            for (phone, detects, hinge, camera, expected) in policies {
                try require(MobileDeviceLayout.supportedOrientations(isPhone: phone, detectsHinge: detects,
                    hasHinge: hinge, cameraPresented: camera) == expected, "Camera restriction leaked into another device/page policy")
            }
            let previousCameraState = MobileDeviceLayout.cameraPresentationForChecks
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            window.rootViewController = UIViewController()
            do {
                defer { MobileDeviceLayout.setCameraPresented(previousCameraState, window: window) }
                let probe = MobileCameraOrientationObserver.Probe()
                window.addSubview(probe)
                try require(MobileDeviceLayout.cameraPresentationForChecks, "Camera observer did not acquire its scoped orientation policy")
                probe.removeFromSuperview()
                try require(!MobileDeviceLayout.cameraPresentationForChecks, "Camera observer did not release its scoped orientation policy")
            }
            checks.append("camera-only orientation policies and real UIView attachment/removal restore the workspace policy")

            for turn in [0.0, 90, -90, 180] {
                let viewport = CGSize(width: 720, height: 560)
                let layout = MobileCameraCanvasGeometry(viewport: viewport, interfaceQuarterTurn: turn, followsInterface: true)
                try require(layout.contentSize == viewport && layout.rotation == 0, "Unfolded camera must not counter-rotate the UIKit scene")
            }
            try require(MobileDeviceLayout.supportedOrientations(isPhone: true, detectsHinge: true,
                            hasHinge: true, cameraPresented: true, cameraFollowsInterface: true) == .all,
                        "Unfolded camera must allow UIKit landscape")
            let tabletop = MobileWaistCameraGeometry(viewport: CGSize(width: 720, height: 560),
                divisionFrames: [CGRect(x: 0, y: 263, width: 720, height: 14)])
            try require(tabletop?.upper.maxY == 263 && tabletop?.lower.minY == 277,
                        "Tabletop layout must keep the two panels out of the hinge")
            try require(MobileWaistCameraGeometry(viewport: CGSize(width: 720, height: 560),
                            divisionFrames: [CGRect(x: 354, y: 0, width: 12, height: 560)]) == nil,
                        "Book posture must not enter tabletop camera")
            try require(MobileWaistCameraGeometry(viewport: CGSize(width: 720, height: 560), divisionFrames: []) == nil,
                        "Flat posture must not enter tabletop camera")
            checks.append("unfolded Duo orientation selection and system division geometry for tabletop vs book/flat")

            let wheel = MobileWaistFilmTrack(count: 27)
            let last = 26
            try require(wheel.index(at: last + 1) == 0 && wheel.index(at: last + 2) == 1 &&
                        wheel.index(at: -1) == 26,
                        "The film track must wrap through adjoining physical slots in both directions")
            try require(wheel.closestSlot(of: 0, to: last) == last + 1 &&
                        wheel.closestSlot(of: 26, to: last + 1) == last,
                        "Film choices from the lower picker should travel the shortest path around the track")
            let asymmetricPanel = MobileWaistCameraGeometry(
                viewport: CGSize(width: 627, height: 820),
                divisionFrames: [CGRect(x: -42, y: 410, width: 669, height: 12)]
            )
            let upperWheel = asymmetricPanel?.upperWheelFrame(leading: 42, trailing: 0) ?? .null
            try require(upperWheel.midX + 42 == 334.5,
                        "The upper wheel must share the physical screen axis with asymmetric safe insets")
            let settle = MobileWaistFilmTrack.Settle(origin: 26.42, destination: 28, velocity: 3, startedAt: 5)
            try require(abs(settle.position(at: 5) - 26.42) < 0.00001 && settle.position(at: 6) == 28,
                        "A release must begin at its dragged position and end exactly on the snapped slot")
            let pitch = MobileWaistFilmTrack.Aperture(size: CGSize(width: 669, height: 410)).pitch
            let smallStep: TimeInterval = 0.00001
            let releases = [300.0, 800.0, 1500.0].map {
                wheel.release(from: 26.21, velocity: $0 / pitch, startedAt: 5)
            }
            try require(zip(releases.map(\.destination), [26, 27, 28]).allSatisfy(==),
                        "A slow drag stays near its stock; a fast flick should coast over multiple slots")
            let extendedReleases = [-16.0, -8, 8, 16].map { velocity in
                wheel.release(from: 26.21, velocity: velocity, startedAt: 5, coastGain: 1.35)
            }
            for longer in extendedReleases {
                let prior = wheel.release(from: longer.origin, velocity: longer.velocity, startedAt: longer.startedAt)
                let priorTravel = abs(prior.position(at: prior.startedAt + prior.coastDuration) - prior.origin)
                let newTravel = abs(longer.position(at: longer.startedAt + longer.coastDuration) - longer.origin)
                try require(priorTravel > 0 && abs(newTravel / priorTravel - 1.35) < 0.00001 &&
                            abs(longer.destination - wheel.nearestSlot(to: longer.origin)) <= 5,
                            "The tabletop coast is longer in either direction but still bounded")
            }
            try require(MobileWaistFilmTrack.compactCoastGain(for: 4) == 1.35 &&
                        MobileWaistFilmTrack.compactCoastGain(for: 12) > 1.7 &&
                        MobileWaistFilmTrack.compactCoastGain(for: 18) > 2.1 &&
                        MobileWaistFilmTrack.compactCoastGain(for: -18) == MobileWaistFilmTrack.compactCoastGain(for: 18),
                        "Slow flicks keep their precision, while fast flicks get more symmetrical coasting")
            let fastReleases = [-30.0, -18, 18, 30].map { speed in
                wheel.release(from: 26.21, velocity: speed, startedAt: 5,
                              coastGain: MobileWaistFilmTrack.compactCoastGain(for: speed))
            }
            for fast in fastReleases {
                let prior = wheel.release(from: fast.origin, velocity: fast.velocity, startedAt: fast.startedAt, coastGain: 1.35)
                let pastTravel = abs(prior.position(at: prior.startedAt + prior.coastDuration) - prior.origin)
                let newTravel = abs(fast.position(at: fast.startedAt + fast.coastDuration) - fast.origin)
                try require(newTravel > pastTravel * 1.5 && abs(fast.destination - wheel.nearestSlot(to: fast.origin)) <= 8,
                            "A strong flick travels noticeably farther but stays bounded")
            }
            for motion in releases + extendedReleases + fastReleases {
                let seam = motion.startedAt + motion.coastDuration
                let initialSlope = (motion.position(at: 5 + smallStep) - motion.origin) / smallStep
                let coastSlope = (motion.position(at: seam) - motion.position(at: seam - smallStep)) / smallStep
                let springSlope = (motion.position(at: seam + smallStep) - motion.position(at: seam)) / smallStep
                let finish = motion.startedAt + motion.duration
                try require(abs(initialSlope - motion.velocity) < 0.002 && abs(coastSlope - springSlope) < 0.002 &&
                            motion.position(at: finish + smallStep) == CGFloat(motion.destination) &&
                            abs(motion.position(at: finish - smallStep) - CGFloat(motion.destination)) < 0.000001,
                            "Inertia, detent spring and final rest must share continuous position and speed")
            }
            for width: CGFloat in [390, 627, 669, 820] {
                let aperture = MobileWaistFilmTrack.Aperture(size: CGSize(width: width, height: 410))
                let center = aperture.cover(of: 28, at: settle.position(at: 6), reduceMotion: false).centerX
                let left = aperture.cover(of: 27, at: 28, reduceMotion: false).centerX
                let right = aperture.cover(of: 29, at: 28, reduceMotion: false).centerX
                try require(center == width / 2 && abs((left + right) / 2 - center) < 0.00001,
                            "Resizing the aperture must preserve the center of the settled group")
            }
            let wheelAperture = MobileWaistFilmTrack.Aperture(size: CGSize(width: 669, height: 410))
            let centeredCover = wheelAperture.cover(of: 0, at: 0, reduceMotion: false).pose
            let leftCover = wheelAperture.cover(of: -1, at: 0, reduceMotion: false).pose
            let rightCover = wheelAperture.cover(of: 1, at: 0, reduceMotion: false).pose
            let farCover = wheelAperture.cover(of: 2, at: 0, reduceMotion: false).pose
            let flatCover = wheelAperture.cover(of: 1, at: 0, reduceMotion: true).pose
            let corner = CGPoint(x: 83, y: 45)
            let leftCorner = leftCover.project(CGPoint(x: -corner.x, y: corner.y))
            let rightCorner = rightCover.project(corner)
            try require(centeredCover.project(corner) == corner && centeredCover.perspective == 0 &&
                        abs(leftCorner.x + rightCorner.x) < 0.00001 &&
                        abs(leftCorner.y - rightCorner.y) < 0.00001 &&
                        rightCover.verticalScale > farCover.verticalScale && flatCover.perspective == 0 &&
                        rightCover.contains(rightCorner, width: wheelAperture.width, height: wheelAperture.height),
                        "Keep the center cover flat, mirror peers about a common horizon, and hit-test the actual projection")
            for size in [CGSize(width: 390, height: 410), CGSize(width: 627, height: 410),
                         CGSize(width: 669, height: 410), CGSize(width: 820, height: 125)] {
                let aperture = MobileWaistFilmTrack.Aperture(size: size)
                func edge(_ slot: Int, at position: CGFloat, side: CGFloat, flat: Bool) -> CGFloat {
                    let cover = aperture.cover(of: slot, at: position, reduceMotion: flat)
                    return cover.centerX + cover.pose.project(CGPoint(x: side * aperture.width / 2, y: 0)).x
                }
                for step in -32...32 {
                    let position = CGFloat(step) / 32
                    for slot in -3..<3 {
                        for flat in [false, true] {
                            let gap = edge(slot + 1, at: position, side: -1, flat: flat)
                                - edge(slot, at: position, side: 1, flat: flat)
                            try require(gap > 5.9, "Tabletop covers must not touch while sliding or at rest")
                        }
                    }
                }
            }
            try require(wheelAperture.cover(of: 2, at: 0, reduceMotion: false).centerX
                            + farCover.project(CGPoint(x: -wheelAperture.width / 2, y: 0)).x
                            < wheelAperture.size.width - 12,
                        "Keep the next cover peeking at the Duo edge")
            checks.append("tabletop film wheel wraps continuously and chooses the nearest centered stock")

            // Measure the screen silhouette, including placement. A positive
            // perspective coefficient alone can describe an almost rectangular row.
            func silhouette(_ aperture: MobileWaistFilmTrack.Aperture, slot: Int, at position: CGFloat,
                            fold: CGFloat) -> (left: CGPoint, right: CGPoint) {
                let card = aperture.cover(of: slot, at: position, reduceMotion: false, fold: fold)
                func edge(_ x: CGFloat) -> CGPoint {
                    let p = card.pose.project(CGPoint(x: x, y: aperture.height / 2))
                    return CGPoint(x: p.x + card.centerX, y: p.y)
                }
                return (edge(-aperture.width / 2), edge(aperture.width / 2))
            }
            let hero = silhouette(wheelAperture, slot: 0, at: 0, fold: 1)
            let heroWidth = hero.right.x - hero.left.x
            let spinePitch = wheelAperture.compactPitch
            try require(heroWidth > 0.33 * spinePitch && heroWidth < 0.5 * spinePitch &&
                        abs(hero.left.y / hero.right.y - 0.75) < 0.00001 &&
                        abs(max(hero.left.y, hero.right.y) * 2 - wheelAperture.height) < 0.00001 &&
                        wheelAperture.dragPitch(reduceMotion: false) < wheelAperture.pitch * 0.5 &&
                        wheelAperture.dragPitch(reduceMotion: true) == wheelAperture.pitch,
                        "The folded center keeps a readable face, with the receding edge shorter")
            for step in -12...12 {
                let phase = CGFloat(step) / 32
                let pass = silhouette(wheelAperture, slot: 0, at: phase, fold: 1)
                try require(abs(pass.left.y / pass.right.y - 0.75) < 0.00001,
                            "The far edge stays shorter on both sides of the center crossing")
            }
            for phase: CGFloat in [-0.4, 0, 0.4] {
                for sign in [-1, 1] {
                    let inner = silhouette(wheelAperture, slot: 2 * sign, at: phase, fold: 1)
                    let outer = silhouette(wheelAperture, slot: 3 * sign, at: phase, fold: 1)
                    let near = sign < 0 ? outer.left : outer.right
                    let far = sign < 0 ? outer.right : outer.left
                    let preceding = sign < 0 ? inner.left : inner.right
                    try require(abs(abs(near.x - preceding.x) - spinePitch) < 1 &&
                                near.y < preceding.y && near.y * 2 < wheelAperture.height &&
                                far.y / near.y < 0.68 && outer.right.x - outer.left.x > 2 * heroWidth,
                                "Both banks taper in height away from the hinge while keeping opposing perspective")
                }
            }
            let opening = MobileWaistFilmTrack.Fold(origin: 1, destination: 0, began: 1, duration: 0.24)
            try require(opening.amount(at: 1) == 1 && opening.amount(at: 2) == 0 &&
                        abs(opening.amount(at: 1.12) - 0.5) < 0.00001,
                        "The cover reveal starts at the folded pose and reaches the front without overshoot")
            for release in fastReleases {
                let now = release.startedAt + 0.09
                let moving = release.position(at: now)
                let initialDrag: CGFloat = release.velocity > 0 ? 11 : -9
                let grab = MobileWaistFilmTrack.Grab(position: moving, translation: initialDrag, pitch: spinePitch)
                let partial = opening.amount(at: 1.12)
                let reversal = MobileWaistFilmTrack.Fold(origin: partial, destination: 1, began: now, duration: 0.11)
                try require(grab.position(at: initialDrag) == moving &&
                            abs(grab.position(at: initialDrag + spinePitch) - (moving - 1)) < 0.00001 &&
                            reversal.amount(at: now) == partial,
                            "Taking over a coast or a reveal preserves the displayed slot and fold at recognition")
            }
            for size in [CGSize(width: 390, height: 160), CGSize(width: 669, height: 410),
                         CGSize(width: 820, height: 125)] {
                let aperture = MobileWaistFilmTrack.Aperture(size: size)
                for foldIndex in 0...8 {
                    let amount = CGFloat(foldIndex) / 8
                    let lane = aperture.laneHeight
                    let hero = silhouette(aperture, slot: 0, at: 0, fold: amount)
                    try require(abs((hero.left.x + hero.right.x) / 2 - size.width / 2) < 0.00001 &&
                                lane + 28 <= size.height + 0.00001 &&
                                abs(max(hero.left.y, hero.right.y) * 2 - aperture.height) < 0.00001,
                                "Center the silhouette in the upper panel and leave room for the caption")
                    for phase in 0...24 {
                        let position = CGFloat(phase) / 24
                        for slot in -4..<4 {
                            let cover = aperture.cover(of: slot, at: position, reduceMotion: false, fold: amount)
                            let flat = aperture.cover(of: slot, at: position, reduceMotion: true, fold: amount)
                            try require(flat == aperture.cover(of: slot, at: position, reduceMotion: true),
                                        "Reduce Motion always uses the resting layout")
                            let face = silhouette(aperture, slot: slot, at: position, fold: amount)
                            let next = silhouette(aperture, slot: slot + 1, at: position, fold: amount)
                            try require(max(face.left.y, face.right.y) * 2 <= aperture.height + 0.00001,
                                        "Projected film graphics never grow taller than the native 16:9 cover")
                            try require(next.left.x - face.right.x > 2.8 && face.right.x > face.left.x,
                                        "Adjacent projected faces stay upright and separated during a drag")
                            let transform = cover.pose.transform(width: aperture.width, height: aperture.height)
                            for x in [-aperture.width / 2, aperture.width / 2] {
                                for y in [-aperture.height / 2, aperture.height / 2] {
                                    let p = cover.pose.project(CGPoint(x: x, y: y))
                                    let drawn = CGPoint(x: x + aperture.width / 2, y: y + aperture.height / 2)
                                        .applying(transform)
                                    try require(abs(drawn.x - aperture.width / 2 - p.x) < 0.00001 &&
                                                abs(drawn.y - aperture.height / 2 - p.y) < 0.00001 &&
                                                abs(p.y) < lane / 2 - 0.9,
                                                "All four rendered corners agree with the model and clear the clip")
                                }
                            }
                            let clippedCorner = CGPoint(x: aperture.width / 2 - 0.1, y: aperture.height / 2 - 0.1)
                            try require(!cover.pose.contains(cover.pose.project(clippedCorner),
                                                             width: aperture.width, height: aperture.height),
                                        "A tap outside the rounded artwork corner misses even inside the projected quad")
                            // Probe the sloping edge midway between its vertical ends.
                            let x = (face.left.x + face.right.x) / 2 - cover.centerX
                            let y = (face.left.y + face.right.y) / 2
                            try require(cover.pose.contains(CGPoint(x: x, y: y - 1), width: aperture.width, height: aperture.height) &&
                                        !cover.pose.contains(CGPoint(x: x, y: y + 1), width: aperture.width, height: aperture.height),
                                        "Touch follows the projected face boundary")
                        }
                    }
                }
            }
            checks.append("tabletop stack silhouette, spine spacing, fold/regrab continuity, clip and projected touch boundary")

            for size in [CGSize(width: 390, height: 125), CGSize(width: 669, height: 260),
                         CGSize(width: 820, height: 410)] {
                let stack = MobileWaistFilmTrack.Wallet(size: size)
                let selected = stack.card(at: 0, reveal: 1).frame
                let retracted = stack.card(at: 0, reveal: 0).frame
                let front = stack.card(at: 1, reveal: 1).frame
                try require(selected.midX > retracted.midX && selected.minY < retracted.minY &&
                            selected.intersects(front) && front.minY - selected.minY > 8,
                            "The selected film peeks out as the second sleeve without clearing the front sleeve")
                for slot in -6...3 {
                    let card = stack.card(at: CGFloat(slot), reveal: 1)
                    try require(card.opacity == ((-4...1).contains(slot) ? 1 : 0),
                                "Stationary sleeves show opaque faces, with no ghost in front or behind")
                }
                let distant = stack.card(at: -3, reveal: 1)
                let foreground = stack.card(at: 1, reveal: 1)
                try require(foreground.perspective > distant.perspective &&
                            stack.card(at: 1, reveal: 1, reduceMotion: true).perspective == 0,
                            "Near cards visibly converge more; Reduce Motion flattens them")
                for step in -32...32 {
                    let coordinate = CGFloat(step) / 32
                    for count in [1, 2, 5, 9, 14] {
                        let slots = stack.slots(at: coordinate, count: count)
                        let model = MobileWaistFilmTrack(count: count)
                        try require(Set(slots.map { model.index(at: $0) }).count == slots.count,
                                    "Wallet stack never duplicates films when the catalog is short")
                        for slot in slots {
                            let card = stack.card(at: CGFloat(slot) - coordinate, reveal: 1)
                            try require(card.frame.minY >= 0 && card.frame.maxY <= stack.laneHeight &&
                                        card.frame.minX >= 0 && card.frame.maxX <= size.width &&
                                        abs(card.frame.width / card.frame.height - 16.0 / 9.0) < 0.00001,
                                        "Wallet sleeves stay within the wide panel and preserve the film cover ratio")
                            let inner = CGPoint(x: 0.72 * card.frame.width, y: 0.80 * card.frame.height)
                            let drawn = inner.applying(card.transform)
                            let panel = CGPoint(x: drawn.x + card.frame.minX, y: drawn.y + card.frame.minY)
                            let recovered = card.localPoint(panel)
                            try require(abs((recovered?.x ?? -.infinity) - inner.x) < 0.00001 &&
                                        abs((recovered?.y ?? -.infinity) - inner.y) < 0.00001,
                                        "The projected and tappable card faces use the same mapping")
                        }
                    }
                }
            }
            checks.append("tabletop wallet stacked sleeves adapt to the panel and reveal the second card")

            let captureAspect: CGFloat = 4.0 / 3.0
            for canvas in [CGSize(width: 528, height: 386), CGSize(width: 408, height: 258),
                           CGSize(width: 402, height: 778)] {
                for turn in [CGFloat(0), 90, 180, 270] {
                    let expected = turn == 90 || turn == 270 ? 1 / captureAspect : captureAspect
                    let aspect = MobileCameraViewfinderGeometry.orientedAspect(captureAspect, angle: turn)
                    let image = MobileCameraViewfinderGeometry.imageSize(in: canvas, aspect: aspect, fillsPanel: false)
                    try require(abs(image.width / image.height - expected) < 0.001 &&
                                    image.width <= canvas.width + 0.001 && image.height <= canvas.height + 0.001 &&
                                    (abs(image.width - canvas.width) < 0.001 || abs(image.height - canvas.height) < 0.001),
                                "The viewfinder should fit the entire oriented capture, not crop it to the panel")
                }
            }
            checks.append("Duo inner, outer, and tabletop preview sizing keeps the full oriented still-photo aspect")

            let innerLandscape = CGSize(width: 640, height: 452)
            let lowerPanel = CGSize(width: 409, height: 258)
            let innerPortrait = CGSize(width: 409, height: 580)
            let extendedLandscape = MobileCameraViewfinderGeometry.previewCanvas(
                panel: innerLandscape, bottomSafeArea: 24, isInner: true, isTabletop: false)
            let extendedTabletop = MobileCameraViewfinderGeometry.previewCanvas(
                panel: lowerPanel, bottomSafeArea: 20, isInner: true, isTabletop: true)
            try require(extendedLandscape == CGSize(width: 640, height: 476) &&
                        extendedTabletop == CGSize(width: 409, height: 278),
                        "Only the Duo photographic canvas extends by the measured bottom system inset")
            try require(MobileCameraViewfinderGeometry.previewCanvas(
                panel: innerPortrait, bottomSafeArea: 24, isInner: true, isTabletop: false) == innerPortrait &&
                        MobileCameraViewfinderGeometry.previewCanvas(
                panel: innerLandscape, bottomSafeArea: 24, isInner: false, isTabletop: false) == innerLandscape,
                        "Duo inner portrait and the outer/folded layout must retain the existing preview canvas")
            let composed = MobileCameraViewfinderGeometry.imageSize(
                in: extendedLandscape, aspect: 0.75, fillsPanel: false)
            try require(composed == CGSize(width: 357, height: 476),
                        "Portrait capture in a landscape Duo scene should reach the lower edge without cropping")
            checks.append("Duo landscape and tabletop camera backdrop extends under the bottom system area without cropping")

            for (inner, closed, selfie, expected) in [
                (false, true, false, true), (false, false, true, true),
                (true, false, false, false), (true, false, true, false), (false, false, false, false)
            ] {
                try require(MobileCameraViewfinderGeometry.usesFullOuterAperture(
                    isInner: inner, hingeClosed: closed, rearSelfie: selfie) == expected,
                    "Only folded and rear-selfie outer viewing use the full outer aperture")
            }
            let outer = MobileCameraViewfinderGeometry.outerViewport(
                safeSize: CGSize(width: 390, height: 760), top: 46, leading: 2, bottom: 34, trailing: 6)
            try require(outer == CGRect(x: -2, y: -46, width: 398, height: 840),
                        "Outer camera and its animation should extend behind all safe insets, not move the controls")
            let outerFinder = MobileCameraViewfinderGeometry.imageSize(in: outer.size, aspect: 0.75, fillsPanel: true)
            for stillAspect in [0.75, 4.0 / 3.0] {
                for swapsAxes in [false, true] {
                    let unrotated = swapsAxes ? CGSize(width: outer.height, height: outer.width) : outer.size
                    let printSize = MobileCameraViewfinderGeometry.aspectSize(in: unrotated, aspect: stillAspect, cover: true)
                    try require(printSize.width >= unrotated.width - 0.001 && printSize.height >= unrotated.height - 0.001
                                 && abs(printSize.width / printSize.height - stillAspect) < 0.001,
                                "The animation should cover the same aperture without stretching the source")
                }
            }
            try require(outerFinder == outer.size, "The viewfinder must cover the full outer frame")
            checks.append("outer rear selfie uses one full-screen viewport for preview and development")

            for capture in [CGFloat(0), 90, 180, 270] {
                let ahead = (capture + 90).truncatingRemainder(dividingBy: 360)
                let behind = (capture + 270).truncatingRemainder(dividingBy: 360)
                try require(MobileCameraViewfinderGeometry.previewAngle(layer: ahead, capture: capture, rearSelfie: true) == behind,
                            "Only rear selfies invert the relative display offset")
                try require(MobileCameraViewfinderGeometry.previewAngle(layer: ahead, capture: capture, rearSelfie: false) == ahead,
                            "Ordinary finder orientation should be untouched")
                try require(MobileCameraViewfinderGeometry.previewAngle(layer: capture, capture: capture, rearSelfie: true) == capture,
                            "Matching still and layer orientations don't need an offset")
                try require(MobileCameraViewfinderGeometry.developmentRotation(capture: capture, preview: behind) == -90,
                            "The developed image must share the finder transform without changing the saved image")
            }
            try require(MobileCameraViewfinderGeometry.developmentRotation(capture: 270, preview: 0) == 90 &&
                        MobileCameraViewfinderGeometry.previewAngle(layer: 90, capture: .nan, rearSelfie: true) == 90,
                        "Development must follow the finder, and invalid capture angles must fall back")
            checks.append("Duo rear-selfie preview and print share the inverse display offset")

            for (pose, expected) in [(0.0, 0.0), (90, -90), (180, -180), (270, 90)] {
                try require(MobileCameraViewfinderGeometry.outerControlRotation(scene: 0, device: pose) == expected,
                            "Outer glyphs must follow gravity when the host stays fixed in portrait")
                try require(MobileCameraViewfinderGeometry.outerControlRotation(scene: pose, device: pose) == 0,
                            "If the scene follows the roll, outer glyphs must not rotate twice")
            }
            checks.append("outer rear-selfie icons follow device orientation relative to the scene")

            let legacy = try JSONDecoder().decode(MobileCameraRecipe.self,
                from: Data(#"{"metering":"center_weighted","diffusion":"off"}"#.utf8))
            try require(legacy.filmID == nil, "Legacy captures must not invent a film")
            try require(legacy.captureGeometry.value.isIdentity, "Legacy captures must remain uncropped")
            let zoomed = MobileCameraRecipe(cropZoom: 2)
            let restoredZoom = try JSONDecoder().decode(MobileCameraRecipe.self, from: JSONEncoder().encode(zoomed))
            try require(restoredZoom.captureGeometry.value.crop == CropRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
                        "The lock-screen handoff must preserve the centered 2× Bayer crop")
            var legacyValues: [String: WireValue] = ["film_stock": .string("kodak_portra_400")]
            try MobileDocument.applyCapturedRecipe(legacy, to: &legacyValues)
            try require(legacyValues["film_stock"]?.stringValue == "kodak_portra_400", "Legacy import changed its film")
            try require(legacyValues["exposure_compensation_ev"] == nil, "Legacy import invented an EV override")
            checks.append("old lock-screen sidecars remain readable and preserve their original film policy")

            let films = ["kodak_portra_400", "ilford_hp5_plus_400", "kodak_ektachrome_100"]
            var combinations = 0
            for id in films {
                let stock = StockCatalog.shared.stock(id)!
                for mode in MobileMeteringMode.allCases { for diffusion in MobileDiffusionFilter.allCases {
                    let ev = [-1.25, 0, 1.5][combinations % 3]
                    let selected = MobileCameraRecipe(filmID: id, metering: mode, diffusion: diffusion, exposureCompensationEV: ev)
                    let encoded = try JSONEncoder().encode(selected)
                    try require(encoded.count < 4096, "CameraCaptureIntent context exceeds its size budget")
                    let restored = try JSONDecoder().decode(MobileCameraRecipe.self, from: encoded)
                    try require(restored == selected, "Per-shot recipe lost a setting")
                    var values: [String: WireValue] = [:]
                    try MobileDocument.applyCapturedRecipe(restored, to: &values)
                    try require(values["film_stock"]?.stringValue == id, "Selected film was not imported")
                    try require(values["auto_exposure"]?.boolValue == (mode != .custom), "Imported meter differs")
                    try require(values["camera_diffusion_active"]?.boolValue == (diffusion != .off), "Imported filter differs")
                    try require(values["exposure_compensation_ev"]?.doubleValue == ev, "Imported EV differs")
                    let wire = try MobileProcessContract.wire(values, aspect: 4.0 / 3)
                    try require(wire["exposure_compensation_ev"]?.doubleValue == ev, "Render EV differs")
                    try require(values["digital_intermediate"]?.boolValue == false, "Capture unexpectedly enabled DI")
                    if stock.isPositive { try require(values["scan_film"]?.boolValue == true, "Slide film must scan directly") }
                    if let paper = stock.targetPrint { try require(values["print_stock"]?.stringValue == paper, "Lost target paper") }
                    combinations += 1
                } }
            }
            try require(combinations == 90, "Incomplete capture recipe coverage")
            checks.append("90 negative/B&W/slide x metering x diffusion round trips with signed EV; target paper, direct scan and app-context size")
            var original: [String: WireValue] = ["film_stock": .string("kodak_portra_400")]
            let unchanged = original
            for id in ["missing-film", "ilford_multigrade_iv_rc"] {
                var rejected = false
                do { try MobileDocument.applyCapturedRecipe(MobileCameraRecipe(filmID: id), to: &original) }
                catch { rejected = true }
                try require(rejected && original == unchanged, "Invalid film must reject without mutating the recipe")
            }
            checks.append("unknown/paper film IDs reject without mutating the recipe")

            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let width = 48, height = 32
            var bytes = [UInt8](repeating: 255, count: width * height * 4)
            for y in 0..<height { for x in 0..<width {
                let i = (y * width + x) * 4
                bytes[i] = x < width / 2 ? 220 : 60
                bytes[i + 1] = y < height / 2 ? 170 : 40
                bytes[i + 2] = (x + y) % 7 < 3 ? 150 : 80
            } }
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let provider = CGDataProvider(data: Data(bytes) as CFData)!
            let raw = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                              bytesPerRow: width * 4, space: space,
                              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                              provider: provider, decode: nil, shouldInterpolate: false, intent: .relativeColorimetric)!
            func write(_ image: CGImage, to url: URL, orientation: Int) throws {
                guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil) else { throw MobileFailure.message("Cannot write orientation fixture") }
                CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
                guard CGImageDestinationFinalize(destination) else { throw MobileFailure.message("Cannot finish orientation fixture") }
            }
            let engine = MobileEngine()
            let recipe: [String: WireValue] = ["auto_exposure": .bool(false), "grain_active": .bool(false),
                "glare_active": .bool(false), "halation_active": .bool(false), "scene_latitude_active": .bool(false)]
            for orientation in [1, 3, 6, 8] {
                let tagged = folder.appendingPathComponent("tagged-\(orientation).tiff")
                let upright = folder.appendingPathComponent("upright-\(orientation).tiff")
                try write(raw, to: tagged, orientation: orientation)
                // Rotate integer pixels, not a colour-managed CI render: the
                // two fixtures must contain precisely the same RGB samples.
                let targetWidth = [6, 8].contains(orientation) ? height : width
                let targetHeight = [6, 8].contains(orientation) ? width : height
                var rotated = [UInt8](repeating: 0, count: bytes.count)
                for y in 0..<height { for x in 0..<width {
                    let dx: Int, dy: Int
                    switch orientation {
                    case 3: dx = width - 1 - x; dy = height - 1 - y
                    case 6: dx = height - 1 - y; dy = x
                    case 8: dx = y; dy = width - 1 - x
                    default: dx = x; dy = y
                    }
                    for channel in 0..<4 {
                        rotated[(dy * targetWidth + dx) * 4 + channel] = bytes[(y * width + x) * 4 + channel]
                    }
                } }
                let expected = CGImage(width: targetWidth, height: targetHeight, bitsPerComponent: 8, bitsPerPixel: 32,
                    bytesPerRow: targetWidth * 4, space: space,
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                    provider: CGDataProvider(data: Data(rotated) as CFData)!, decode: nil,
                    shouldInterpolate: false, intent: .relativeColorimetric)!
                try write(expected, to: upright, orientation: 1)
                let metadata = MobileImageMetadata.read(tagged)
                try require(abs(metadata.aspect - Double(expected.width) / Double(expected.height)) < 1e-6, "Metadata aspect ignored capture orientation")
                let a = try await engine.render(url: tagged, recipe: recipe, megapixels: 0.01)
                let b = try await engine.render(url: upright, recipe: recipe, megapixels: 0.01)
                try require(a.image.width == expected.width && a.image.height == expected.height, "Portrait capture decoded sideways")
                try require(a.image.width == b.image.width && a.image.height == b.image.height, "Equivalent input dimensions differ")
                let ad = a.image.dataProvider!.data! as Data, bd = b.image.dataProvider!.data! as Data
                try require(ad.count == bd.count, "Equivalent input data sizes differ")
                let difference = ad.withUnsafeBytes { ap in bd.withUnsafeBytes { bp in
                    zip(ap.bindMemory(to: UInt16.self), bp.bindMemory(to: UInt16.self)).map { abs(Int($0) - Int($1)) }.max() ?? 0
                } }
                maximumDifference = max(maximumDifference, difference)
                try require(difference <= 1, "EXIF orientation \(orientation) changed the render by \(difference) counts")
            }
            await engine.close()
            checks.append("actual file reader + native engine: four EXIF orientations, portrait dimensions and representation-invariant rendering")
            try writeReport(report, checks: checks, passed: true, error: nil, difference: maximumDifference)
        } catch {
            try? writeReport(report, checks: checks, passed: false, error: error.localizedDescription, difference: maximumDifference)
        }
    }
    private static func writeReport(_ url: URL, checks: [String], passed: Bool, error: String?, difference: Int) throws {
        var values: [String: Any] = ["passed": passed, "checks": checks, "maxRepresentationDifference16Bit": difference,
            "scope": "synthetic configuration, handoff and tagged-file/native-render checks; no physical camera, sensor rotation, lock-screen host or Duo hinge acceptance"]
        if let error { values["error"] = error }
        try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
}
#endif
