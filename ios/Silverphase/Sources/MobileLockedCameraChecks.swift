#if DEBUG
import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import UIKit

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

            let legacy = try JSONDecoder().decode(MobileCameraRecipe.self,
                from: Data(#"{"metering":"center_weighted","diffusion":"off"}"#.utf8))
            try require(legacy.filmID == nil, "Legacy captures must not invent a film")
            var legacyValues: [String: WireValue] = ["film_stock": .string("kodak_portra_400")]
            try MobileDocument.applyCapturedRecipe(legacy, to: &legacyValues)
            try require(legacyValues["film_stock"]?.stringValue == "kodak_portra_400", "Legacy import changed its film")
            checks.append("old lock-screen sidecars remain readable and preserve their original film policy")

            let films = ["kodak_portra_400", "ilford_hp5_plus_400", "kodak_ektachrome_100"]
            var combinations = 0
            for id in films {
                let stock = StockCatalog.shared.stock(id)!
                for mode in MobileMeteringMode.allCases { for diffusion in MobileDiffusionFilter.allCases {
                    let selected = MobileCameraRecipe(filmID: id, metering: mode, diffusion: diffusion)
                    let encoded = try JSONEncoder().encode(selected)
                    try require(encoded.count < 4096, "CameraCaptureIntent context exceeds its size budget")
                    let restored = try JSONDecoder().decode(MobileCameraRecipe.self, from: encoded)
                    try require(restored == selected, "Per-shot recipe lost a setting")
                    var values: [String: WireValue] = [:]
                    try MobileDocument.applyCapturedRecipe(restored, to: &values)
                    try require(values["film_stock"]?.stringValue == id, "Selected film was not imported")
                    try require(values["auto_exposure"]?.boolValue == (mode != .custom), "Imported meter differs")
                    try require(values["camera_diffusion_active"]?.boolValue == (diffusion != .off), "Imported filter differs")
                    try require(values["digital_intermediate"]?.boolValue == false, "Capture unexpectedly enabled DI")
                    if stock.isPositive { try require(values["scan_film"]?.boolValue == true, "Slide film must scan directly") }
                    if let paper = stock.targetPrint { try require(values["print_stock"]?.stringValue == paper, "Lost target paper") }
                    combinations += 1
                } }
            }
            try require(combinations == 90, "Incomplete capture recipe coverage")
            checks.append("90 negative/B&W/slide x metering x diffusion round trips; target paper, direct scan and app-context size")
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
