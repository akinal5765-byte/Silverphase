import CoreGraphics
import CoreImage
import Foundation

extension Comparable {
    func clamped(to bounds: ClosedRange<Self>) -> Self { min(bounds.upperBound, max(bounds.lowerBound, self)) }
}

// Geometry.swift is compiled directly from the desktop model. CropRect is its
// small value dependency, declared there in the otherwise desktop-only Sidecar.
struct CropRect: Codable, Equatable, Sendable {
    var x: Double = 0, y: Double = 0, width: Double = 1, height: Double = 1
    static let full = CropRect()
    var isFull: Bool { self == .full }
    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct MobileGeometry: Codable, Equatable, Sendable {
    var value = Geometry()
    init(value: Geometry = Geometry()) { self.value = value }
    // Compatibility for explicit diagnostics from the earlier centre-crop tool.
    init(quarterTurns: Int, aspect: Double) {
        value.quarterTurns = quarterTurns
        value.aspect = aspect == 1 ? .square : .free
        value = value.constrained(in: CGSize(width: 1500, height: 1000))
    }
    var quarterTurns: Int { value.quarterTurns }
    func outputSize(for source: CGSize) -> CGSize { value.outputSize(for: source) }

    func apply(to image: CIImage) -> CIImage {
        guard !value.isIdentity else { return image }
        let size = image.extent.size
        let output = value.outputSize(for: size)
        // Desktop mapping uses top-left pixel coordinates; CI uses bottom-left.
        // Convert around the SAME inverse map rather than maintaining a second
        // implementation of crop/straighten/turn/flip ordering.
        let origin = CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY)
        let topLeft = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
        let bottomLeft = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: output.height)
        let map = origin.concatenating(topLeft)
            .concatenating(value.outputToSourceTransform(imageSize: size).inverted())
            .concatenating(bottomLeft)
        return image.transformed(by: map).cropped(to: CGRect(origin: .zero, size: output))
    }
    func apply(to image: CGImage) throws -> CGImage {
        guard !value.isIdentity else { return image }
        return try autoreleasepool {
            let input = apply(to: CIImage(cgImage: image))
            let context = CIContext(options: [.cacheIntermediates: false])
            defer { context.clearCaches() }
            guard let result = context.createCGImage(input, from: input.extent, format: .RGBA16, colorSpace: image.colorSpace) else {
                throw MobileFailure.message(TDetached("The crop failed", "裁切失败", "裁切失敗"))
            }
            return result
        }
    }
}

/// The requested edge is the cropped picture before the film border is added.
enum MobileSimulationSize {
    static let key = "_filmImageLongEdge"
    static let edgeRange = 16...16_384

    static func edge(in recipe: [String: WireValue]) -> Int? {
        recipe[key]?.doubleValue.flatMap(Int.init(exactly:))
    }

    static func workingSize(in recipe: [String: WireValue], geometry: MobileGeometry, aspect: Double) throws -> CGSize? {
        guard let edge = edge(in: recipe) else { return nil }
        let crop = geometry.value.crop
        var picture = CGSize(width: aspect * crop.width, height: crop.height)
        if geometry.quarterTurns % 2 != 0 { picture = CGSize(width: picture.height, height: picture.width) }
        if recipe["overscan_active"]?.boolValue == true {
            let gate = MobileFilmGate.size(recipe["overscan_format"]?.stringValue ?? "135")
            let ratio = picture.width >= picture.height ? gate.0 / gate.1 : gate.1 / gate.0
            picture.width = min(picture.width, picture.height * ratio)
            picture.height = picture.width / ratio
        }
        let scale = Double(edge) / max(picture.width, picture.height)
        let size = CGSize(width: max(1, (aspect * scale).rounded()), height: max(1, scale.rounded()))
        guard edgeRange.contains(edge), scale.isFinite, scale > 0,
              size.width <= 16_384, size.height <= 16_384,
              size.width * size.height <= 96_000_000 else {
            throw MobileFailure.message(TDetached("The requested size and crop exceed the film frame’s pixel limit.", "模拟尺寸与裁切超出胶片画幅的像素上限。", "模擬尺寸與裁切超出膠片畫幅的像素上限。"))
        }
        return size
    }

    static func megapixels(_ size: CGSize) -> Double { size.width * size.height / 1_000_000 }

    static func resize(_ image: CIImage, to size: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.size != size else { return image }
        let placed = image.transformed(by: .init(translationX: -extent.minX, y: -extent.minY))
        let scale = size.height / extent.height
        return placed.clampedToExtent().applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: scale,
            kCIInputAspectRatioKey: (size.width / extent.width) / scale
        ]).cropped(to: CGRect(origin: .zero, size: size))
    }
}
