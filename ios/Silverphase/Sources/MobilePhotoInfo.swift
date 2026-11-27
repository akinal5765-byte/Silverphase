import CoreImage
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// A read-only snapshot of the original. ImageIO only reads container
/// properties; RAW dimensions are queried without rendering a frame.
struct MobilePhotoInfoMetadata: Sendable {
    var typeIdentifier: String?
    var width: Int?
    var height: Int?
    var bytes: Int64?
    var depth: Int?
    var profile: String?
    var camera: String?
    var lens: String?
    var aperture: Double?
    var shutter: Double?
    var iso: Int?
    var focal: Double?
    var equivalentFocal: Double?
    var bias: Double?
    var capturedAt: Date?

    static func read(_ url: URL, knownTypeIdentifier: String?) -> Self {
        var result = Self()
        result.bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        let knownRaw = [knownTypeIdentifier.flatMap(UTType.init), UTType(filenameExtension: url.pathExtension)]
            .compactMap { $0 }.first(where: { $0.conforms(to: .rawImage) })
        result.typeIdentifier = knownRaw?.identifier
        var options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        if let knownRaw { options[kCGImageSourceTypeIdentifierHint] = knownRaw.identifier }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else { return result }
        result.typeIdentifier = knownRaw?.identifier ?? CGImageSourceGetType(source).map { $0 as String }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options as CFDictionary) as? [String: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let raw = result.typeIdentifier.flatMap(UTType.init)?.conforms(to: .rawImage) == true
        let native = raw ? CIRAWFilter(imageURL: url)?.nativeSize : nil
        // A RAW container's first ImageIO image may be its embedded JPEG. Do
        // not describe the embedded image's dimensions, depth, or profile as RAW.
        let width = raw ? integer(native.map { Double($0.width) }) : integer(number(properties, kCGImagePropertyPixelWidth))
        let height = raw ? integer(native.map { Double($0.height) }) : integer(number(properties, kCGImagePropertyPixelHeight))
        if let width, let height {
            let orientation = integer(number(properties, kCGImagePropertyOrientation)) ?? 1
            (result.width, result.height) = (5...8).contains(orientation) ? (height, width) : (width, height)
        }
        if !raw {
            result.depth = integer(number(properties, kCGImagePropertyDepth))
            result.profile = string(properties, kCGImagePropertyProfileName)
        }
        let make = string(tiff, kCGImagePropertyTIFFMake)
        let model = string(tiff, kCGImagePropertyTIFFModel)
        result.camera = [make.flatMap { name in model?.localizedCaseInsensitiveContains(name) == true ? nil : name }, model]
            .compactMap { $0 }.joined(separator: " ")
        if result.camera?.isEmpty == true { result.camera = nil }
        result.lens = string(exif, kCGImagePropertyExifLensModel)
        result.aperture = number(exif, kCGImagePropertyExifFNumber)
        result.shutter = number(exif, kCGImagePropertyExifExposureTime)
        result.iso = integer((exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first?.doubleValue
                             ?? number(exif, kCGImagePropertyExifISOSpeedRatings))
        result.focal = number(exif, kCGImagePropertyExifFocalLength)
        result.equivalentFocal = number(exif, kCGImagePropertyExifFocalLenIn35mmFilm)
        result.bias = number(exif, kCGImagePropertyExifExposureBiasValue, positiveOnly: false)
        result.capturedAt = MobileImageMetadata.captureDate(in: exif)
        return result
    }

    private static func number(_ data: [String: Any], _ key: CFString, positiveOnly: Bool = true) -> Double? {
        guard let value = (data[key as String] as? NSNumber)?.doubleValue, value.isFinite,
              !positiveOnly || value > 0 else { return nil }
        return value
    }
    private static func integer(_ number: Double?) -> Int? {
        guard let number, number.isFinite, (1...1_000_000).contains(number) else { return nil }
        return Int(number.rounded())
    }
    private static func string(_ data: [String: Any], _ key: CFString) -> String? {
        guard let text = (data[key as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }
}

struct MobilePhotoInfoPage: View {
    let photo: MobilePhoto
    let originalURL: URL
    let thumbnailURL: URL
    let onDone: () -> Void
    @State private var loaded: MobilePhotoInfoMetadata?

    private struct Row: Identifiable {
        let id: String
        let label: String
        let value: String
    }

    private var film: Stock? {
        material("film_stock")
    }
    private var format: String? {
        let type = loaded?.typeIdentifier ?? photo.sourceTypeIdentifier
        let ext = originalURL.pathExtension.uppercased()
        if let type, UTType(type)?.conforms(to: .rawImage) == true {
            return ext.isEmpty || ext == "RAW" ? "RAW" : ext + " · RAW"
        }
        return MobileImageMetadata.formatBadge(for: type) ?? (ext.isEmpty ? nil : ext)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: EditorDesign.contentInset) {
                    header
                    if let loaded {
                        capture(loaded)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel(T("Reading photo information", "正在读取照片信息", "正在讀取照片資訊"))
                    }
                    section(T("Original file", "原始文件", "原始檔案"), icon: "doc", rows: fileRows)
                    recipe
                }
                .frame(maxWidth: 600)
                .padding(.horizontal, EditorDesign.contentInset)
                .padding(.vertical, EditorDesign.contentInset)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("photo-info.scroll")
            .mobilePageBackground()
            .navigationTitle(T("Photo Info", "照片信息", "照片資訊"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(T("Done", "完成", "完成"), action: onDone)
                        .accessibilityIdentifier("photo-info.done")
                }
            }
        }
        .presentationBackground(MobileStyle.canvas)
        .task(id: originalURL) {
            loaded = nil
            let knownType = photo.sourceTypeIdentifier
            let reader = Task.detached(priority: .utility) { [originalURL] in
                MobilePhotoInfoMetadata.read(originalURL, knownTypeIdentifier: knownType)
            }
            let result = await withTaskCancellationHandler { await reader.value } onCancel: { reader.cancel() }
            if !Task.isCancelled { loaded = result }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            FilmstripThumbnail(url: thumbnailURL, fillsFrame: true)
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(photo.name).font(.headline).lineLimit(3).textSelection(.enabled)
                    .accessibilityIdentifier("photo-info.filename")
                if let format {
                    Text(format).font(.caption.weight(.semibold)).foregroundStyle(MobileStyle.accent)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(MobileStyle.accent.opacity(0.12), in: Capsule())
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func capture(_ metadata: MobilePhotoInfoMetadata) -> some View {
        let metrics: [Row] = [
            metadata.shutter.map { Row(id: "shutter", label: T("Shutter", "快门", "快門"), value: shutter($0)) },
            metadata.aperture.map { Row(id: "aperture", label: T("Aperture", "光圈", "光圈"), value: "ƒ/" + decimal($0)) },
            metadata.iso.map { Row(id: "iso", label: "ISO", value: String($0)) },
            metadata.focal.map { Row(id: "focal", label: T("Focal length", "焦距", "焦距"), value: decimal($0) + " mm") }
        ].compactMap { $0 }
        let cameraRows: [Row] = [
            metadata.camera.map { Row(id: "camera", label: T("Camera", "相机", "相機"), value: $0) },
            metadata.lens.map { Row(id: "lens", label: T("Lens", "镜头", "鏡頭"), value: $0) },
            metadata.capturedAt.map { Row(id: "date", label: T("Captured", "拍摄时间", "拍攝時間"), value: $0.formatted(date: .abbreviated, time: .shortened)) },
            metadata.equivalentFocal.map { Row(id: "equivalent", label: T("35 mm equivalent", "35 mm 等效", "35 mm 等效"), value: decimal($0) + " mm") },
            metadata.bias.map { Row(id: "bias", label: T("Exposure bias", "曝光补偿", "曝光補償"), value: ($0 > 0 ? "+" : "") + decimal($0) + " EV") }
        ].compactMap { $0 }
        if !metrics.isEmpty || !cameraRows.isEmpty {
            block(T("Capture", "拍摄", "拍攝"), icon: "camera") {
                if !metrics.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 102), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(metrics) { metric in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(metric.value).font(.callout.weight(.semibold)).monospacedDigit()
                                Text(metric.label).font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.primary.opacity(0.055), in: .rect(cornerRadius: 8))
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("photo-info." + metric.id)
                        }
                    }
                }
                rows(cameraRows)
            }
        } else if !photo.exifSummary.isEmpty {
            block(T("Capture", "拍摄", "拍攝"), icon: "camera") {
                Text(photo.exifSummary).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var fileRows: [Row] {
        var items: [Row] = []
        if let w = loaded?.width, let h = loaded?.height {
            items.append(Row(id: "dimensions", label: T("Dimensions", "像素尺寸", "像素尺寸"), value: "\(w) × \(h) px"))
        }
        let megapixels = loaded.flatMap { data in
            data.width.flatMap { w in data.height.map { Double(w) * Double($0) / 1_000_000 } }
        } ?? photo.sourceMegapixels
        if megapixels > 0, megapixels.isFinite {
            items.append(Row(id: "resolution", label: T("Resolution", "分辨率", "解析度"), value: (megapixels < 0.1 ? "< 0.1" : decimal(megapixels)) + " MP"))
        }
        if let bytes = loaded?.bytes {
            items.append(Row(id: "size", label: T("File size", "文件大小", "檔案大小"), value: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))
        }
        if let depth = loaded?.depth {
            items.append(Row(id: "depth", label: T("Bit depth", "位深", "位元深度"), value: "\(depth)-bit"))
        }
        if let profile = loaded?.profile {
            items.append(Row(id: "profile", label: T("Color profile", "色彩配置", "色彩描述檔"), value: profile))
        }
        if loaded?.capturedAt == nil, let date = photo.libraryDate {
            items.append(Row(id: "library-date", label: T("Library date", "图库日期", "圖庫日期"), value: date.formatted(date: .abbreviated, time: .omitted)))
        }
        return items
    }

    @ViewBuilder private var recipe: some View {
        if let film {
            let direct = value("scan_film")?.boolValue == true
            let intermediate = value("digital_intermediate")?.boolValue == true
            block(T("Film simulation", "胶片模拟", "底片模擬"), icon: "film") {
                HStack(spacing: 12) {
                    if let cover = film.packagingArtworkURL {
                        FilmstripThumbnail(url: cover, fillsFrame: true)
                            .frame(width: 80, height: 45).clipShape(.rect(cornerRadius: 6)).accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(film.displayName).font(.subheadline.weight(.semibold)).accessibilityIdentifier("photo-info.film")
                        if film.isFotufilm { Text("Fotufilm").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                }
                if intermediate {
                    rows([Row(id: "output", label: T("Output", "输出", "輸出"), value: T("Digital intermediate", "数字中间片", "數位中間片"))])
                } else if direct {
                    rows([Row(id: "output", label: T("Output", "输出", "輸出"), value: T("Direct film scan", "胶片直扫", "底片直掃"))])
                } else if let paper = material("print_stock") {
                    rows([Row(id: "paper", label: T("Print paper", "相纸", "相紙"), value: paper.displayName)])
                }
            }
        }
    }

    private func value(_ key: String) -> WireValue? { photo.recipe[key] ?? MobileProcessContract.defaults[key] }
    private func material(_ key: String) -> Stock? { value(key)?.stringValue.flatMap { StockCatalog.shared.stock($0) } }

    @ViewBuilder private func section(_ title: String, icon: String, rows: [Row]) -> some View {
        if !rows.isEmpty { block(title, icon: icon) { self.rows(rows) } }
    }
    private func block<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MobileStyle.well, in: .rect(cornerRadius: 14))
    }
    private func rows(_ rows: [Row]) -> some View {
        ForEach(rows) { row in
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.label).foregroundStyle(.secondary).fixedSize()
                    Spacer(minLength: 16)
                    Text(row.value).fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.label).foregroundStyle(.secondary)
                    Text(row.value)
                }
            }
            .font(.subheadline)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("photo-info." + row.id)
            .textSelection(.enabled)
        }
    }
    private func decimal(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
    private func shutter(_ seconds: Double) -> String {
        if seconds < 0.33, seconds >= 0.000_001 { return "1/\(Int((1 / seconds).rounded())) s" }
        return decimal(seconds) + " s"
    }
}
