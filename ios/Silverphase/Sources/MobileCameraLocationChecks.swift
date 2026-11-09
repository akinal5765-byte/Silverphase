#if DEBUG
import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import AVFoundation

@MainActor enum MobileCameraLocationChecks {
    static func run() async {
        let folder = URL.temporaryDirectory.appendingPathComponent("Camera-Location-Checks-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let report = URL.documentsDirectory.appendingPathComponent("camera-location-report.json")
        var checks: [String] = []
        do {
            func require(_ value: Bool, _ message: String) throws { if !value { throw MobileFailure.message(message) } }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let now = Date(timeIntervalSince1970: 1_700_000_000)
            let fix = MobileCaptureLocation(latitude: -33.865, longitude: 151.209, altitude: -12, accuracy: 10, timestamp: now)
            try require(MobileCaptureLocation.snapshot(fix, enabled: false, at: now) == nil, "Off preference recorded location")
            try require(MobileCaptureLocation.snapshot(fix, enabled: true, at: now) == fix, "Current fix lost")
            try require(MobileCaptureLocation.snapshot(fix, enabled: true, at: now.addingTimeInterval(61)) == nil, "Stale fix used")
            try require(MobileCaptureLocation.snapshot(fix, enabled: true, at: now.addingTimeInterval(-6)) == nil, "Future fix used")
            for invalid in [MobileCaptureLocation(latitude: .nan, longitude: 1, altitude: nil, accuracy: 10, timestamp: now),
                            MobileCaptureLocation(latitude: 91, longitude: 1, altitude: nil, accuracy: 10, timestamp: now),
                            MobileCaptureLocation(latitude: 1, longitude: 181, altitude: nil, accuracy: 10, timestamp: now),
                            MobileCaptureLocation(latitude: 1, longitude: 1, altitude: nil, accuracy: -1, timestamp: now)] {
                try require(!invalid.isUsable(at: now), "Invalid location accepted")
            }
            checks.append("shutter-time location rejects off, stale, future, invalid and unavailable fixes")
            let settings = AVCapturePhotoSettings()
            settings.metadata = [kCGImagePropertyGPSDictionary as String: fix.gps]
            try require((settings.metadata[kCGImagePropertyGPSDictionary as String] as? [String: Any])?[kCGImagePropertyGPSLatitudeRef as String] as? String == "S", "Capture settings lost hemisphere")
            try require(fix.gps[kCGImagePropertyGPSDateStamp as String] as? String == "2023:11:14", "GPS date is not UTC")
            try require(fix.gps[kCGImagePropertyGPSTimeStamp as String] as? String == "22:13:20.000", "GPS time is not UTC")
            try require(fix.gps[kCGImagePropertyGPSAltitudeRef as String] as? Int == 1, "Below sea level sign lost")
            let west = MobileCaptureLocation(latitude: 12, longitude: -77, altitude: nil, accuracy: 5000, timestamp: now)
            try require(west.isUsable(at: now) && west.gps[kCGImagePropertyGPSLongitudeRef as String] as? String == "W", "User's approximate location was rejected")
            checks.append("AVCapture metadata accepts GPS; UTC stamps, hemispheres, altitude and approximate accuracy are preserved")
            let frame = CIImage(color: CIColor(red: 0.2, green: 0.3, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 48))
            guard let image = CIContext().createCGImage(frame, from: frame.extent) else { throw MobileFailure.message("No synthetic location fixture") }
            let renderer = MobileEngine()
            for type in [UTType.jpeg, .heic, .tiff] {
                let file = folder.appendingPathComponent("source").appendingPathExtension(type.preferredFilenameExtension!)
                guard let writer = CGImageDestinationCreateWithURL(file as CFURL, type.identifier as CFString, 1, nil) else { throw MobileFailure.message("Cannot create GPS fixture") }
                CGImageDestinationAddImage(writer, image, [kCGImagePropertyGPSDictionary: fix.gps] as CFDictionary)
                try require(CGImageDestinationFinalize(writer), "GPS fixture did not write")
                let original = PhotoLibraryWriter.location(in: file)
                try require(original != nil && abs(original!.coordinate.latitude - fix.latitude) < 0.000001 && abs(original!.coordinate.longitude - fix.longitude) < 0.000001, "Photos location parser lost original GPS")
                let developed = try await renderer.render(url: file, recipe: ["grain_active": .bool(false), "glare_active": .bool(false)], megapixels: 0.01)
                let display = try await renderer.canvasImage(developed.image)
                for (metadata, location) in [(true, true), (true, false), (false, true)] {
                    var options = MobileExportRecipe()
                    options.format = .jpeg; options.metadata = metadata; options.location = location
                    let output = folder.appendingPathComponent(UUID().uuidString + ".jpg")
                    try await renderer.writeExportForChecks(display, source: file, output: output, options: options)
                    let actual = PhotoLibraryWriter.location(in: output)
                    try require((actual != nil) == (metadata && location), "Location stripping policy failed for \(type.identifier)")
                    if let actual { try require(abs(actual.coordinate.latitude - fix.latitude) < 0.000001, "Export changed GPS") }
                }
            }
            await renderer.close()
            checks.append("JPEG/HEIC/TIFF GPS survives native rendering and production JPEG encoding and Photos coordinate parsing; metadata/location-off exports remove GPS")
            let usage = Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") as? String
            try require(usage?.isEmpty == false, "Missing location permission description")
            checks.append("location permission purpose is packaged; no permission, camera or Photos request was made by this test")
            try write(report, passed: true, checks: checks, error: nil)
        } catch { try? write(report, passed: false, checks: checks, error: error.localizedDescription) }
    }
    private static func write(_ url: URL, passed: Bool, checks: [String], error: String?) throws {
        var values: [String: Any] = ["passed": passed, "checks": checks,
            "scope": "synthetic GPS ownership/serialization/export tests; actual location authorization, sensor fixes and on-device RAW capture and full-export memory gate not exercised"]
        if let error { values["error"] = error }
        try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
    }
}
#endif
