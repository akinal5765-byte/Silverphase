import Photos
import Foundation

// Add-only access. The editor never needs to enumerate the user's library in
// order to save a finished render; the system picker owns photo selection.
enum PhotoLibraryWriter {
    static func authorize() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw MobileFailure.message("未获准添加照片。请在系统设置中允许 Silverphase 向照片图库添加照片。")
        }
    }
    static func save(_ file: URL) async throws {
        try await authorize()
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = file.lastPathComponent
            request.addResource(with: .photo, fileURL: file, options: options)
        }
    }
}
