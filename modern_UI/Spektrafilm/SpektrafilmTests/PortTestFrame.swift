import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Synthetic encoded scene for pipeline/sidecar tests, never a RAW decode oracle.
enum PortTestFrame {
    static func write(to url: URL, highContrast: Bool = false) throws {
        let w = 256, h = 192
        var bytes = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let v = UInt8(highContrast ? (x < w / 2 ? 3 : 250) : 20 + 210 * x / (w - 1))
            let i = (y * w + x) * 4
            bytes[i] = v; bytes[i + 1] = v; bytes[i + 2] = v
        }}
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }
}
