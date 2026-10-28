import Foundation
import CoreGraphics
import Darwin

struct MobileViewport: Equatable, Sendable {
    var rect: CGRect
    var zoom: Double
    var pixelLongEdge: Double
    var previewLongEdge: Int
    var pixelSize = CGSize.zero
    var needsDetail: Bool { !rect.isEmpty && !rect.isNull && pixelLongEdge > Double(previewLongEdge) * 1.15 }
}

enum MobilePreviewPolicy {
    static func fitEdge(pixels: Double) -> Int {
        [1080, 1600, 1920, 2560, 3200, 3840].first { Double($0) >= pixels } ?? 3840
    }
    static func nativeZoom(nativeLongEdge: Double, fitLongEdgePoints: Double, displayScale: Double) -> Double {
        max(0.01, nativeLongEdge / max(1, fitLongEdgePoints * displayScale))
    }
    static func megapixels(edge: Int, aspect: Double) -> Double {
        Double(edge * edge) / max(aspect, 1 / max(0.001, aspect)) / 1e6
    }
    static func nextInteractionEdge(_ edge: Int, seconds: Double) -> Int {
        if seconds > 0.20 { return max(800, Int(Double(edge) * 0.8)) }
        if seconds < 0.07 { return min(3840, Int(Double(edge) * 1.15)) }
        return edge
    }
}

struct MobileDetailTile: @unchecked Sendable {
    let image: CGImage
    let rect: CGRect // normalised, top-left origin in the final output
    var nativeSize: CGSize? = nil
}

/// Whole-frame physics, bounded viewport display. Never render a cropped RAW
/// independently: exposure, halos and film dimensions depend on the full frame.
actor MobileDetailRenderer {
    nonisolated let engine = MobileEngine()
    private var source: CGImage?
    private var sourceURL: URL?
    private var recipe: [String: WireValue] = [:]
    private var geometry = MobileGeometry()
    private var sourceMP = 0.0
    private var metadata: MobileImageMetadata?
#if DEBUG
    private var renders = 0
    private var inFlight = 0
    func audit() -> [String: Int] { ["renders": renders, "residentPixels": source.map { $0.width * $0.height } ?? 0, "inFlight": inFlight] }
    func auditRecipe() -> [String: WireValue] { recipe }
#endif

    func clear() async {
        source = nil; sourceURL = nil; recipe = [:]; sourceMP = 0; metadata = nil
        await engine.close()
    }
    func tile(url: URL, recipe: [String: WireValue], geometry: MobileGeometry, viewport: CGRect, pixelLongEdge: Double) async throws -> MobileDetailTile {
        let metadata = sourceURL == url ? self.metadata ?? MobileImageMetadata.read(url) : MobileImageMetadata.read(url)
        let tier = [2560, 3840, 5120, 7168, 10240].first { Double($0) >= pixelLongEdge } ?? Int(ceil(pixelLongEdge))
        var size = MobileExportRecipe(); size.sizeMode = "longEdge"; size.longEdge = tier
        var mp = size.megapixels(sourceMP: metadata.megapixels, aspect: metadata.aspect, geometry: geometry)
        if sourceURL == url, self.recipe == recipe, self.geometry == geometry, let source, sourceMP > 0 {
            // Film gates/edges change output dimensions. Use the observed
            // output scale rather than retrying the same undersized tier.
            let edge = Double(max(source.width, source.height))
            mp = min(metadata.megapixels, max(mp, sourceMP * pow(Double(tier) / max(1, edge), 2)))
        }
        if source == nil || sourceURL != url || self.recipe != recipe || self.geometry != geometry || sourceMP < mp * 0.9999 {
            source = nil
            guard Double(os_proc_available_memory()) > (mp * 70 + 600) * 1e6 else {
                throw MobileFailure.message("当前内存不足以载入原始细节，保留现有预览")
            }
            var settings = recipe
            settings["_exporting"] = .bool(true) // bounded bands; no full-size before image
            settings["_exportTargetSpace"] = .string(MobileOutputSpace.p3.rawValue)
#if DEBUG
            inFlight += 1
            defer { inFlight -= 1 }
#endif
            let result = try await engine.render(url: url, recipe: settings, megapixels: mp, geometry: geometry, inputMetadata: metadata)
#if DEBUG
            renders += 1
#endif
            try Task.checkCancellation()
            source = try MobileFilmGate.presents(recipe) ? result.image : geometry.apply(to: result.image)
            sourceURL = url; self.recipe = recipe; self.geometry = geometry; sourceMP = mp; self.metadata = metadata
        }
        try Task.checkCancellation()
        guard let source else { throw CancellationError() }
        let expanded = viewport.insetBy(dx: -viewport.width * 0.15, dy: -viewport.height * 0.15).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let pixels = CGRect(x: expanded.minX * Double(source.width), y: expanded.minY * Double(source.height),
                            width: expanded.width * Double(source.width), height: expanded.height * Double(source.height)).integral
            .intersection(CGRect(x: 0, y: 0, width: source.width, height: source.height))
        let tile = try Self.copy(source, rect: pixels)
        let display = try await engine.canvasImage(tile)
        try Task.checkCancellation()
        return MobileDetailTile(image: display, rect: CGRect(x: pixels.minX / Double(source.width), y: pixels.minY / Double(source.height), width: pixels.width / Double(source.width), height: pixels.height / Double(source.height)), nativeSize: sourceMP >= metadata.megapixels * 0.999 ? CGSize(width: source.width, height: source.height) : nil)
    }
    // Copy the exact pixels into a packed tile. No resampling, CI colour
    // round-trip, or borrowed provider offset hidden behind CGImage.cropping.
    static func copy(_ source: CGImage, rect: CGRect) throws -> CGImage {
        let x = Int(rect.minX), y = Int(rect.minY), w = Int(rect.width), h = Int(rect.height)
        guard w > 0, h > 0, x >= 0, y >= 0, x + w <= source.width, y + h <= source.height,
              source.bitsPerComponent == 16, source.bitsPerPixel == 64, let bytes = source.dataProvider?.data,
              let base = CFDataGetBytePtr(bytes), CFDataGetLength(bytes) >= source.bytesPerRow * source.height else {
            throw MobileFailure.message("无法读取细节预览像素")
        }
        var packed = Data(count: w * h * 8)
        packed.withUnsafeMutableBytes { destination in
            for row in 0..<h {
                memcpy(destination.baseAddress!.advanced(by: row * w * 8), base.advanced(by: (y + row) * source.bytesPerRow + x * 8), w * 8)
            }
        }
        guard let provider = CGDataProvider(data: packed as CFData), let space = source.colorSpace,
              let output = CGImage(width: w, height: h, bitsPerComponent: 16, bitsPerPixel: 64, bytesPerRow: w * 8,
                                   space: space, bitmapInfo: source.bitmapInfo, provider: provider, decode: nil,
                                   shouldInterpolate: true, intent: .relativeColorimetric) else { throw MobileFailure.message("无法创建细节预览") }
        return output
    }
}
