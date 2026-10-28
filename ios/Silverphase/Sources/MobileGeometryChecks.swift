#if DEBUG
import Foundation
import CoreGraphics

enum MobileGeometryChecks {
    struct Failure: LocalizedError { let errorDescription: String? }
    static func run() throws {
        func require(_ value: Bool, _ message: String) throws { if !value { throw Failure(errorDescription: message) } }
        let size = CGSize(width: 192, height: 128)
        var pixels = [UInt16](repeating: 65535, count: 192 * 128 * 4)
        for y in 0..<128 { for x in 0..<192 {
            let i = (y * 192 + x) * 4
            pixels[i] = UInt16(x * 257); pixels[i + 1] = UInt16(y * 257); pixels[i + 2] = 32768
        } }
        let data = pixels.withUnsafeBytes { Data($0) }
        let provider = CGDataProvider(data: data as CFData)!
        let image = CGImage(width: 192, height: 128, bitsPerComponent: 16, bitsPerPixel: 64, bytesPerRow: 192 * 8,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue).union(.byteOrder16Little),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .relativeColorimetric)!
        for turns in 0..<4 { for h in [false, true] { for v in [false, true] {
            var g = Geometry(); g.crop = CropRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
            g.quarterTurns = turns; g.flipH = h; g.flipV = v
            let output = try MobileGeometry(value: g).apply(to: image)
            let expected = g.outputSize(for: size)
            try require(output.width == Int(expected.width) && output.height == Int(expected.height), "裁切输出尺寸错误")
            let bytes = output.dataProvider!.data! as Data
            for y in [0, output.height / 2, output.height - 1] { for x in [0, output.width / 2, output.width - 1] {
                let source = g.sourcePoint(forOutput: CGPoint(x: (Double(x) + 0.5) / Double(output.width), y: (Double(y) + 0.5) / Double(output.height)), imageSize: size)
                let expectedR = Int(floor(source.x * size.width)) * 257
                let expectedG = Int(floor(source.y * size.height)) * 257
                let i = y * output.bytesPerRow + x * 8
                let r = Int(bytes[i]) | Int(bytes[i + 1]) << 8, green = Int(bytes[i + 2]) | Int(bytes[i + 3]) << 8
                try require(abs(r - expectedR) <= 40 && abs(green - expectedG) <= 40,
                            "裁切预览/导出坐标不同：turns=\(turns), flip=\(h)/\(v), pixel=\(x)/\(y), got=\(r)/\(green), expected=\(expectedR)/\(expectedG)")
            } }
        } } }
        for angle in [-45.0, -12, 0, 23, 45] {
            let g = Geometry().straightened(to: angle, in: size)
            try require(g.fits(in: size), "校直角落超出原图")
            let restored = g.straightened(to: 0, in: size)
            try require(abs(restored.crop.width - 1) < 1e-8, "校直回零未恢复原始范围")
        }
        var g = Geometry(); g.aspect = .r4x5
        g = g.constrained(in: size)
        let resized = g.resized(handle: .bottomRight, to: CGPoint(x: 0.6, y: 0.8), in: size)
        let moved = resized.moved(by: CGSize(width: 5, height: -5), in: size)
        try require(moved.fits(in: size), "拖动裁切离开原图")
        try require(abs(moved.crop.width * size.width / (moved.crop.height * size.height) - 0.8) < 1e-6, "拖动丢失锁定比例")
    }
}
#endif
