import Photos
import Foundation

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
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
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
}
