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
                throw MobileFailure.message("裁切失败")
            }
            return result
        }
    }
}
