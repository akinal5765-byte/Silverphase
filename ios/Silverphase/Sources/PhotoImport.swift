import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO
import CoreImage

struct MobileImageMetadata: Sendable {
    var typeIdentifier: String?
    var exifSummary = ""
    var aspect = 1.5
    var megapixels = 0.0
    var isRaw: Bool { typeIdentifier.flatMap(UTType.init)?.conforms(to: .rawImage) == true }
    var fileExtension: String? { typeIdentifier.flatMap(UTType.init)?.preferredFilenameExtension }

    static func read(_ url: URL, hint: UTType? = nil) -> Self {
        autoreleasepool { readInPool(url, hint: hint) }
    }
    private static func readInPool(_ url: URL, hint: UTType?) -> Self {
        func source(_ type: UTType?) -> CGImageSource? {
            let options = type.map { [kCGImageSourceTypeIdentifierHint: $0.identifier] as CFDictionary }
            return CGImageSourceCreateWithURL(url as CFURL, options)
        }
        var input = source(hint)
        var properties = input.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [String: Any] }
        // A RAW returned under a generic .jpeg name can be mistaken for its
        // TIFF wrapper, with no readable image properties. Probe decoder hints
        // only in that ambiguous case; never accept the embedded JPEG preview.
        if properties?[kCGImagePropertyPixelWidth as String] == nil,
           input.flatMap(CGImageSourceGetType).map({ $0 as String }) == UTType.tiff.identifier {
            let bytes = try? Data(contentsOf: url, options: .mappedIfSafe)
            let types = CGImageSourceCopyTypeIdentifiers() as? [String] ?? []
            for identifier in types where UTType(identifier)?.conforms(to: .rawImage) == true {
                guard let bytes, let raw = CIRAWFilter(imageData: bytes, identifierHint: identifier),
                      raw.nativeSize.width > 0, raw.nativeSize.height > 0,
                      let candidate = source(UTType(identifier)),
                      let info = CGImageSourceCopyPropertiesAtIndex(candidate, 0, nil) as? [String: Any],
                      info[kCGImagePropertyPixelWidth as String] != nil else { continue }
                input = candidate; properties = info; break
            }
        }
        var result = Self(typeIdentifier: input.flatMap(CGImageSourceGetType).map { $0 as String })
        if let w = properties?[kCGImagePropertyPixelWidth as String] as? NSNumber,
           let h = properties?[kCGImagePropertyPixelHeight as String] as? NSNumber, h.doubleValue > 0 {
            result.aspect = w.doubleValue / h.doubleValue
            result.megapixels = w.doubleValue * h.doubleValue / 1_000_000
            if let orientation = properties?[kCGImagePropertyOrientation as String] as? NSNumber, (5...8).contains(orientation.intValue) { result.aspect = 1 / result.aspect }
        }
        // RAW ImageIO dimensions may describe its embedded JPEG, not sensor data.
        // Budget/export from the decoder's native frame, never that preview.
        if result.isRaw, let raw = CIRAWFilter(imageURL: url), raw.nativeSize.width > 0, raw.nativeSize.height > 0 {
            result.megapixels = raw.nativeSize.width * raw.nativeSize.height / 1_000_000
            result.aspect = raw.nativeSize.width / raw.nativeSize.height
            if let orientation = properties?[kCGImagePropertyOrientation as String] as? NSNumber, (5...8).contains(orientation.intValue) { result.aspect = 1 / result.aspect }
        }
        let exif = properties?[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        var fields: [String] = []
        if let aperture = exif[kCGImagePropertyExifFNumber as String] as? NSNumber, aperture.doubleValue > 0 {
            fields.append("f/" + String(format: "%g", aperture.doubleValue))
        }
        if let shutter = exif[kCGImagePropertyExifExposureTime as String] as? NSNumber, shutter.doubleValue > 0 {
            fields.append(shutter.doubleValue < 1 ? "1/\(Int((1 / shutter.doubleValue).rounded())) s" : String(format: "%g s", shutter.doubleValue))
        }
        if let speeds = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber], let iso = speeds.first {
            fields.append("ISO \(iso.intValue)")
        }
        if let focal = exif[kCGImagePropertyExifFocalLength as String] as? NSNumber, focal.doubleValue > 0 {
            fields.append(String(format: "%g mm", focal.doubleValue))
        }
        result.exifSummary = fields.joined(separator: " · ")
        return result
    }

    func displayName(suggested: String?, fallback: String) -> String {
        let original = suggested.map { URL(fileURLWithPath: $0).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 }
        guard let original else { return fallback }
        let name = URL(fileURLWithPath: original)
        guard name.pathExtension.isEmpty, let fileExtension else { return original }
        return original + "." + fileExtension
    }
}

struct LibraryPhotoImport: Sendable {
    let url: URL
    let name: String
}

/// The system picker stays permission-free. Preserve the selected file and its
/// colour profile; prefer an offered RAW over its rendered preview.
struct LibraryPhotoPicker: UIViewControllerRepresentable {
    static let flatTypes: [UTType] = [.jpeg, .heic, .heif, .png, .tiff]
    @Binding var isPresented: Bool
    let onStart: (Int) -> Bool
    let onProgress: (Int, Int, String) -> Void
    let onFinish: ([LibraryPhotoImport], Int, [String]) -> Void
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 0
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ picker: PHPickerViewController, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: LibraryPhotoPicker
        init(parent: LibraryPhotoPicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false
            guard !results.isEmpty else { return }
            guard parent.onStart(results.count) else { return }
            Task {
                var files: [LibraryPhotoImport] = []
                var skipped = 0
                var errors: [String] = []
                for (index, result) in results.enumerated() {
                    parent.onProgress(index + 1, results.count, result.itemProvider.suggestedName ?? "")
                    do {
                        if let file = try await Self.load(result.itemProvider) { files.append(file) }
                        else { skipped += 1 }
                    } catch { errors.append(error.localizedDescription) }
                }
                parent.onFinish(files, skipped, errors)
            }
        }
        static func load(_ provider: NSItemProvider) async throws -> LibraryPhotoImport? {
            let types = provider.registeredTypeIdentifiers.compactMap(UTType.init)
            let type = types.first { $0.conforms(to: .rawImage) }
                ?? types.first { type in LibraryPhotoPicker.flatTypes.contains { type.conforms(to: $0) } }
                ?? types.first { $0.conforms(to: .image) } ?? .image
            let suggested = provider.suggestedName
            let hint = type.conforms(to: .rawImage) ? type : suggested.flatMap { UTType(filenameExtension: URL(fileURLWithPath: $0).pathExtension) }.flatMap { $0.conforms(to: .rawImage) ? $0 : nil }
            return try await withCheckedThrowingContinuation { continuation in
                provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                    do {
                        if let error { throw error }
                        guard let url else { throw MobileFailure.message("系统照片未提供可读取的文件。") }
                        let info = MobileImageMetadata.read(url, hint: hint)
                        let flat = info.typeIdentifier.flatMap(UTType.init).map { type in
                            LibraryPhotoPicker.flatTypes.contains { type.conforms(to: $0) }
                        } == true && info.megapixels > 0
                        // A RAW request must never silently become its JPEG preview.
                        guard info.isRaw || (hint == nil && flat) else { continuation.resume(returning: nil); return }
                        let ext = info.fileExtension ?? (info.isRaw ? "raw" : "jpg")
                        let destination = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
                        try FileManager.default.copyItem(at: url, to: destination)
                        let name = info.displayName(suggested: suggested, fallback: "未提供原始文件名." + ext)
                        continuation.resume(returning: LibraryPhotoImport(url: destination, name: name))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }
    }
}

/// Capture-side text follows the desktop date back: no fabricated date, real
/// focal/aperture/exposure data, no leading zeros, and a bounded data line.
enum MobileCaptureText {
    static func read(_ url: URL, order: String) -> (date: String, data: String, aperture: Double) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] else { return ("", "", 0) }
        func number(_ key: CFString) -> Double? { (exif[key as String] as? NSNumber)?.doubleValue }
        func trimmed(_ v: Double) -> String { let text = String(format: "%.1f", v); return text.hasSuffix(".0") ? String(text.dropLast(2)) : text }
        var date = ""
        if let stamp = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            let parts = stamp.prefix(10).split(separator: ":").compactMap { Int($0) }
            if parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) {
                let yy = String(format: "'%02d", parts[0] % 100)
                date = order == "us" ? "\(parts[1]) \(parts[2]) \(yy)" : "\(yy) \(parts[1]) \(parts[2])"
            }
        }
        var fields: [String] = []
        if let t = number(kCGImagePropertyExifExposureTime), t > 0 { fields.append(t >= 1 ? trimmed(t) + "s" : "1/\(Int((1 / t).rounded()))") }
        let aperture = number(kCGImagePropertyExifFNumber) ?? 0
        if aperture > 0 { fields.append("F" + trimmed(aperture)) }
        if let mode = number(kCGImagePropertyExifExposureProgram).flatMap({ [1: "M", 2: "P", 3: "A", 4: "S"][Int($0)] }) { fields.append(mode) }
        if let bias = number(kCGImagePropertyExifExposureBiasValue), abs(bias) >= 0.05 { fields.append(String(format: "%+.1f", bias)) }
        if let focal = number(kCGImagePropertyExifFocalLenIn35mmFilm), focal > 0 { fields.append("\(Int(focal.rounded()))mm") }
        while fields.joined(separator: " ").count > 22 { fields.removeLast() }
        return (date, fields.joined(separator: " "), aperture)
    }
}
