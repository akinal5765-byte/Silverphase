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
    /// Both the editor and gallery target the rendered output edge, not
    /// the uncropped RAW dimensions. Callers supply their own output extent.
    static func fitInputMegapixels(edge: Int, sourceAspect: Double, sourceMP: Double,
                                  outputLongEdge: Double, simulationSize: CGSize? = nil,
                                  simulationEdge: Int? = nil) -> Double {
        if let size = simulationSize, let simulationEdge {
            let scale = min(1, Double(edge) / Double(simulationEdge), 3840 / max(size.width, size.height))
            return MobileSimulationSize.megapixels(size) * scale * scale
        }
        let sourceCap = megapixels(edge: 3840, aspect: sourceAspect)
        let requested = sourceMP * pow(Double(edge) / max(1, outputLongEdge), 2)
        return max(0.01, min(sourceCap, sourceMP, requested))
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
    func discardGallerySource(except url: URL?) async {
        guard sourceURL != url else { return }
        await clear()
    }

    func tile(url: URL, recipe: [String: WireValue], geometry: MobileGeometry, viewport: CGRect, pixelLongEdge: Double,
              galleryFitEdge: Int? = nil, galleryNativeEdge: Double? = nil, trace: GalleryRenderTrace? = nil) async throws -> MobileDetailTile {
        let metadata = sourceURL == url ? self.metadata ?? MobileImageMetadata.read(url) : MobileImageMetadata.read(url)
        let tier = [2560, 3840, 5120, 7168, 10240].first { Double($0) >= pixelLongEdge } ?? Int(ceil(pixelLongEdge))
        let simulation = try MobileSimulationSize.workingSize(in: recipe, geometry: geometry, aspect: metadata.aspect)
        let nativeMP = simulation.map(MobileSimulationSize.megapixels) ?? metadata.megapixels
        let sameSource = sourceURL == url && self.recipe == recipe && self.geometry == geometry
        func requiredMP(for tier: Int) -> Double {
            var size = MobileExportRecipe(); size.sizeMode = "longEdge"; size.longEdge = tier
            var mp = size.megapixels(sourceMP: nativeMP, aspect: metadata.aspect, geometry: geometry)
            if let edge = MobileSimulationSize.edge(in: recipe) {
                mp = nativeMP * min(1, pow(Double(tier) / Double(edge), 2))
            }
            if let galleryNativeEdge, galleryNativeEdge > 0 {
                // A square gate (or the border drawn around it) can have a
                // different long edge than the geometry crop. Use output pixels.
                mp = nativeMP * min(1, pow(Double(tier) / galleryNativeEdge, 2))
            }
            if sameSource, let source, sourceMP > 0 {
                let edge = Double(max(source.width, source.height))
                mp = min(nativeMP, max(mp, sourceMP * pow(Double(tier) / max(1, edge), 2)))
            }
            return mp
        }
        let available = Double(os_proc_available_memory())
#if DEBUG && targetEnvironment(simulator)
        let testBudget = ProcessInfo.processInfo.arguments.contains("--gallery-tile-audit")
            || ProcessInfo.processInfo.arguments.contains("--gallery-native-audit")
        let budget = available == 0 && testBudget ? 1_500_000_000 : available
#else
        let budget = available
#endif
        // Gallery can still hold its fitted film and original comparison textures
        // while the next film tier decodes and renders. Leave additional headroom
        // for that overlap; do not change the editor's existing budget.
        let usableBudget = galleryFitEdge == nil ? budget : budget * 0.72
        var mp = requiredMP(for: tier)
        trace?.mark("requested tier \(tier) px; source \(nativeMP) MP; available \(Int(budget / 1e6)) MB; usable \(Int(usableBudget / 1e6)) MB")
        if let galleryFitEdge, usableBudget <= (mp * 70 + 600) * 1e6 {
            // Keep the editor's memory reserve. Gallery can still show an
            // intermediate tier that is measurably sharper than the fit image.
            let alternatives = [7168, 5120, 3840, 3200, 2560, 1920, 1600].filter {
                $0 < tier && Double($0) > Double(galleryFitEdge) * 1.15
            }
            if let safe = alternatives.map(requiredMP(for:)).first(where: { usableBudget > ($0 * 70 + 600) * 1e6 }) {
                mp = safe
            } else if sameSource, let source, Double(max(source.width, source.height)) > Double(galleryFitEdge) * 1.08 {
                mp = sourceMP
            }
        }
        trace?.mark("selected work \(mp) MP")
        if !sameSource || source == nil || sourceMP < mp * 0.9999 {
            guard usableBudget > (mp * 70 + 600) * 1e6 else {
                throw MobileFailure.message(TDetached("Not enough memory to load the original detail; keeping the current preview", "当前内存不足以载入原始细节，保留现有预览", "目前記憶體不足以載入原始細節，保留現有預覽"))
            }
            source = nil
            var settings = recipe
            settings["_exporting"] = .bool(true) // bounded bands; no full-size before image
            if galleryFitEdge != nil { settings["_galleryPreview"] = .bool(true) }
            settings["_exportTargetSpace"] = .string(MobileOutputSpace.p3.rawValue)
#if DEBUG
            inFlight += 1
            defer { inFlight -= 1 }
#endif
            let result = try await engine.render(url: url, recipe: settings, megapixels: mp, geometry: geometry, inputMetadata: metadata, galleryTrace: trace)
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
        trace?.mark("crop and convert tile start")
        let tile = try Self.copy(source, rect: pixels)
        let display = try await engine.canvasImage(tile)
        trace?.mark("crop and convert tile end \(display.width)x\(display.height)")
        try Task.checkCancellation()
        return MobileDetailTile(image: display, rect: CGRect(x: pixels.minX / Double(source.width), y: pixels.minY / Double(source.height), width: pixels.width / Double(source.width), height: pixels.height / Double(source.height)), nativeSize: sourceMP >= nativeMP * 0.999 ? CGSize(width: source.width, height: source.height) : nil)
    }
    // Copy the exact pixels into a packed tile. No resampling, CI colour
    // round-trip, or borrowed provider offset hidden behind CGImage.cropping.
    static func copy(_ source: CGImage, rect: CGRect) throws -> CGImage {
        let x = Int(rect.minX), y = Int(rect.minY), w = Int(rect.width), h = Int(rect.height)
        guard w > 0, h > 0, x >= 0, y >= 0, x + w <= source.width, y + h <= source.height,
              source.bitsPerComponent == 16, source.bitsPerPixel == 64, let bytes = source.dataProvider?.data,
              let base = CFDataGetBytePtr(bytes), CFDataGetLength(bytes) >= source.bytesPerRow * source.height else {
            throw MobileFailure.message(TDetached("The detail preview pixels could not be read", "无法读取细节预览像素", "無法讀取細節預覽像素"))
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
                                   shouldInterpolate: true, intent: .relativeColorimetric) else { throw MobileFailure.message(TDetached("The detail preview could not be created", "无法创建细节预览", "無法創建細節預覽")) }
        return output
    }
}
