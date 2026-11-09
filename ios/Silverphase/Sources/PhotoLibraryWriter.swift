import Photos
import Foundation
import CoreLocation
import ImageIO

// Add-only access. The editor never needs to enumerate the user's library in
// order to save a finished render; the system picker owns photo selection.
enum PhotoLibraryWriter {
    static func authorize() async throws {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let status = current == .notDetermined ? await PHPhotoLibrary.requestAuthorization(for: .addOnly) : current
        guard status == .authorized || status == .limited else {
            throw MobileFailure.message("未获准添加照片。请在系统设置中允许 Silverphase 向照片图库添加照片。")
        }
    }
    static func save(_ file: URL, pairedRAW: URL? = nil) async throws {
        try await authorize()
        let location = location(in: file)
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.location = location
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = file.lastPathComponent
            request.addResource(with: .photo, fileURL: file, options: options)
            if let pairedRAW {
                let rawOptions = PHAssetResourceCreationOptions()
                rawOptions.originalFilename = file.deletingPathExtension().lastPathComponent + "." + pairedRAW.pathExtension
                request.addResource(with: .alternatePhoto, fileURL: pairedRAW, options: rawOptions)
            }
        }
    }
    static func location(in file: URL) -> CLLocation? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let gps = metadata[kCGImagePropertyGPSDictionary as String] as? [String: Any],
              let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double,
              let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double,
              let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String,
              let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String,
              ["N", "S"].contains(latRef), ["E", "W"].contains(lonRef),
              lat.isFinite, lon.isFinite, lat >= 0, lat <= 90, lon >= 0, lon <= 180 else { return nil }
        return CLLocation(latitude: latRef == "S" ? -lat : lat, longitude: lonRef == "W" ? -lon : lon)
    }

}
