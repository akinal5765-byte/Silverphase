import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO
import CoreImage

struct MobileImageMetadata: Sendable {
    var typeIdentifier: String?
    var exifSummary = ""
    var captureDay: Int?
    var captureDate: Date?
    var aspect = 1.5
    var megapixels = 0.0
    var isRaw: Bool { typeIdentifier.flatMap(UTType.init)?.conforms(to: .rawImage) == true }
    static func formatBadge(for identifier: String?) -> String? {
        guard let identifier, let type = UTType(identifier) else { return nil }
        if type.conforms(to: .rawImage) { return "RAW" }
        if type.conforms(to: .jpeg) { return "JPG" }
        if type.conforms(to: .heic) || type.conforms(to: .heif) { return "HEIF" }
        if type.conforms(to: .tiff) { return "TIFF" }
        return type.preferredFilenameExtension?.uppercased()
    }

    static func storedTypeIdentifier(_ url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceGetType(source).map { $0 as String }
    }

    static func libraryDate(forOriginal url: URL) -> (date: Date?, day: Int?) {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
           let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            let day = captureDay(in: exif)
            if let date = captureDate(in: exif) { return (date, day) }
            if let day { return (date(forDay: day), day) }
        }
        let date = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
        return (date, date.map(day(containing:)))
    }

    static func date(forDay day: Int) -> Date? {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: day / 10000, month: day / 100 % 100, day: day % 100))
    }

    private static func captureDate(in exif: [String: Any]) -> Date? {
        guard let stamp = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        if let offset = exif[kCGImagePropertyExifOffsetTimeOriginal as String] as? String {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ssXXXXX"
            if let date = formatter.date(from: stamp + offset) { return date }
        }
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: stamp)
    }

    static func day(containing date: Date) -> Int {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0) * 10000 + (parts.month ?? 0) * 100 + (parts.day ?? 0)
    }

    private static func captureDay(in exif: [String: Any]) -> Int? {
        guard let stamp = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String else { return nil }
        let parts = stamp.prefix(10).split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3, (1...9999).contains(parts[0]),
              (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return parts[0] * 10000 + parts[1] * 100 + parts[2]
    }

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
        result.captureDay = captureDay(in: exif)
        result.captureDate = captureDate(in: exif)
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

/// Prefer original RAW resources when Photos grants access. The picker can
/// still provide selected files when library access is limited or denied.
struct LibraryPhotoPicker: UIViewControllerRepresentable {
    static let flatTypes: [UTType] = [.jpeg, .heic, .heif, .png, .tiff]
    @Binding var isPresented: Bool
    let onStart: (Int) -> Bool
    let onProgress: (Int, Int, String) -> Void
    let onFinish: ([LibraryPhotoImport], Int, [String]) -> Void
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
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
                        if let file = try await Self.load(result) {
                            files.append(file)
                        } else if Self.rawHint(for: result.itemProvider) != nil {
                            let name = result.itemProvider.suggestedName ?? T("Untitled photo", "未命名照片", "未命名照片")
                            errors.append(T("Could not read the RAW original: ", "无法读取 RAW 原片：", "無法讀取 RAW 原片：") + name)
                        } else { skipped += 1 }
                    } catch { errors.append(error.localizedDescription) }
                }
                parent.onFinish(files, skipped, errors)
            }
        }
        private static func rawHint(for provider: NSItemProvider) -> UTType? {
            provider.registeredTypeIdentifiers.compactMap(UTType.init).first { $0.conforms(to: .rawImage) }
                ?? provider.suggestedName.flatMap {
                    UTType(filenameExtension: URL(fileURLWithPath: $0).pathExtension)
                }.flatMap { $0.conforms(to: .rawImage) ? $0 : nil }
        }

        private static func loadOriginalRAW(_ result: PHPickerResult) async throws -> LibraryPhotoImport? {
            guard let id = result.assetIdentifier else { return nil }
            var access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            if access == .notDetermined && rawHint(for: result.itemProvider) == nil {
                access = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            }
            guard access == .authorized || access == .limited,
                  let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
            let resources = PHAssetResource.assetResources(for: asset)
            guard let resource = resources.first(where: {
                ($0.type == .photo || $0.type == .alternatePhoto) &&
                    UTType($0.uniformTypeIdentifier)?.conforms(to: .rawImage) == true
            }) else { return nil }

            let hint = UTType(resource.uniformTypeIdentifier)
            let name = URL(fileURLWithPath: resource.originalFilename).lastPathComponent
            let ext = hint?.preferredFilenameExtension ?? URL(fileURLWithPath: name).pathExtension
            let destination = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            do {
                try await PHAssetResourceManager.default().writeData(for: resource, toFile: destination, options: options)
                try Task.checkCancellation()
                let info = await Task.detached(priority: .userInitiated) {
                    MobileImageMetadata.read(destination, hint: hint)
                }.value
                try Task.checkCancellation()
                guard info.isRaw, info.megapixels > 0 else {
                    throw MobileFailure.message(T("The file Photos returned is not a readable RAW original.", "照片图库返回的文件无法识别为 RAW 原片。", "照片圖庫返回的檔案無法識別為 RAW 原片。"))
                }
                return LibraryPhotoImport(url: destination, name: info.displayName(suggested: name, fallback: destination.lastPathComponent))
            } catch {
                try? FileManager.default.removeItem(at: destination)
                if error is CancellationError { throw CancellationError() }
                throw MobileFailure.message(TDetached("Could not read the RAW original \(name): \(error.localizedDescription)", "无法读取 RAW 原片 \(name)：\(error.localizedDescription)", "無法讀取 RAW 原片 \(name)：\(error.localizedDescription)"))
            }
        }

        private static func load(_ result: PHPickerResult) async throws -> LibraryPhotoImport? {
            // A failed Photos resource request does not invalidate the picker
            // grant. The picker may already have a readable RAW file locally.
            try await loadPreservingRAW(result.itemProvider) { try await loadOriginalRAW(result) }
        }

        private static func loadPreservingRAW(_ provider: NSItemProvider,
                                              original: () async throws -> LibraryPhotoImport?) async throws -> LibraryPhotoImport? {
            do {
                if let file = try await original() { return file }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let originalError = error
                do {
                    if let file = try await load(provider, requiringRAW: true) { return file }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // Keep the original, more specific Photos resource error.
                }
                throw originalError
            }
            return try await load(provider)
        }

        static func load(_ provider: NSItemProvider, requiringRAW: Bool = false) async throws -> LibraryPhotoImport? {
            let types = provider.registeredTypeIdentifiers.compactMap(UTType.init)
            let raw = types.filter { $0.conforms(to: .rawImage) }
            let rendered = types.filter { type in LibraryPhotoPicker.flatTypes.contains { type.conforms(to: $0) } }
            let otherImages = types.filter { $0.conforms(to: .image) }
            let suggested = provider.suggestedName
            let rawHint = rawHint(for: provider)
            let requireRAW = requiringRAW || rawHint != nil
            // Never ask for a separate rendered preview if the picker exposes
            // RAW. Some providers expose only a generic/image identifier for
            // RAW; in that case we still check the actual file's contents.
            let candidates = raw.isEmpty ? rendered + otherImages : raw
            var attempted = Set<String>()
            var firstError: Error?
            var delivered = false
            for type in candidates.isEmpty ? [.image] : candidates {
                guard attempted.insert(type.identifier).inserted else { continue }
                try Task.checkCancellation()
                do {
                    if let file = try await loadRepresentation(provider, type: type, suggested: suggested,
                                                               rawHint: rawHint, requiringRAW: requireRAW) {
                        if Task.isCancelled {
                            try? FileManager.default.removeItem(at: file.url)
                            throw CancellationError()
                        }
                        return file
                    }
                    delivered = true
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    if firstError == nil { firstError = error }
                }
            }
            try Task.checkCancellation()
            // A readable delivery in an unsupported/invalid format remains a
            // skip (or a RAW warning), not a Photos transfer error.
            if !delivered, let firstError { throw firstError }
            return nil
        }

        private static func loadRepresentation(_ provider: NSItemProvider, type: UTType, suggested: String?,
                                               rawHint: UTType?, requiringRAW: Bool) async throws -> LibraryPhotoImport? {
            let unreadable = MobileFailure.message(T("Photos did not provide a readable file.", "系统照片未提供可读取的文件。", "系統照片未提供可讀取的檔案。"))
            let unnamed = T("untitled.", "未提供原始文件名.", "未提供原始檔案名.")
            let flatTypes = LibraryPhotoPicker.flatTypes
            return try await withCheckedThrowingContinuation { continuation in
                provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                    do {
                        if let error { throw error }
                        guard let url else { throw unreadable }
                        let hint = type.conforms(to: .rawImage) ? type : rawHint
                        let info = MobileImageMetadata.read(url, hint: hint)
                        let flat = info.typeIdentifier.flatMap(UTType.init).map { type in
                            flatTypes.contains { type.conforms(to: $0) }
                        } == true
                        guard info.megapixels > 0, info.isRaw || (!requiringRAW && flat) else {
                            continuation.resume(returning: nil); return
                        }
                        let ext = info.fileExtension ?? (info.isRaw ? "raw" : "jpg")
                        let destination = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
                        // Foundation owns the representation only until this
                        // callback returns. Make an independent byte copy here.
                        do {
                            try FileManager.default.copyItem(at: url, to: destination)
                        } catch {
                            try? FileManager.default.removeItem(at: destination)
                            throw error
                        }
                        let name = representationName(info, suggested: suggested, fallback: unnamed + ext, extension: ext)
                        continuation.resume(returning: LibraryPhotoImport(url: destination, name: name))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }

        private nonisolated static func representationName(_ info: MobileImageMetadata, suggested: String?,
                                                           fallback: String, extension ext: String) -> String {
            let name = info.displayName(suggested: suggested, fallback: fallback)
            // If a compatible representation differs from the suggested image
            // suffix, retain the name stem but describe the actual file.
            let url = URL(fileURLWithPath: name)
            guard let declared = UTType(filenameExtension: url.pathExtension), declared.conforms(to: .image),
                  let actual = info.typeIdentifier.flatMap(UTType.init),
                  !actual.conforms(to: declared), !declared.conforms(to: actual) else { return name }
            return url.deletingPathExtension().lastPathComponent + "." + ext
        }
    }
}

#if DEBUG
extension LibraryPhotoPicker.Coordinator {
    /// Exercised by the picker-format smoke launch with synthetic files.
    static func auditRepresentationFallback(jpeg: URL, invalid: URL) async throws -> [String] {
        let unavailable = MobileFailure.message("Synthetic Photos provider: no file available")
        let originalError = MobileFailure.message("Synthetic Photos original RAW is unavailable")
        let ext = UTType.jpeg.preferredFilenameExtension!
        let originalBytes = try Data(contentsOf: jpeg)
        for first in [nil, invalid] as [URL?] {
            let provider = NSItemProvider()
            provider.suggestedName = "Fallback.PNG"
            provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { done in
                done(first, false, first == nil ? unavailable : nil); return nil
            }
            provider.registerFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier, fileOptions: [], visibility: .all) { done in
                done(jpeg, false, nil); return nil
            }
            guard let file = try await load(provider) else {
                throw MobileFailure.message("A later compatible Photos representation was skipped")
            }
            defer { try? FileManager.default.removeItem(at: file.url) }
            guard file.name == "Fallback." + ext, file.url.pathExtension == ext,
                  try Data(contentsOf: file.url) == originalBytes else {
                throw MobileFailure.message("Fallback did not preserve the selected file bytes and accurate image extension")
            }
        }
        let rawNamed = NSItemProvider()
        rawNamed.suggestedName = "Unavailable.DNG"
        rawNamed.registerFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier, fileOptions: [], visibility: .all) { done in
            done(jpeg, false, nil); return nil
        }
        guard try await load(rawNamed) == nil else {
            throw MobileFailure.message("A named RAW original was silently substituted by its rendered preview")
        }
        // Even if the picker metadata does not say RAW, a failed Photos
        // resource lookup knows the selected original is RAW.
        rawNamed.suggestedName = "Unavailable"
        do {
            if let file = try await loadPreservingRAW(rawNamed, original: { throw originalError }) {
                try? FileManager.default.removeItem(at: file.url)
            }
        } catch {
            guard error.localizedDescription == originalError.localizedDescription else { throw error }
            return ["unavailable or corrupt preferred Photos representation retries compatible original bytes",
                    "fallback display extension matches actual file",
                    "RAW does not silently become a JPEG; underlying Photos resource error retained"]
        }
        throw MobileFailure.message("A failed RAW resource request was silently replaced or skipped")
    }
}
#endif

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
