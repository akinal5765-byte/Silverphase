import CoreGraphics
import ImageIO
import Metal
import XCTest
import UniformTypeIdentifiers

@MainActor
final class EXIFRoundTripTests: XCTestCase {
    private func properties(_ url: URL) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    func testCameraIdentitySurvivesJPEGAndTIFFExport() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "spk-camera-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "source.tif")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(source as CFURL,
            UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image(), [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "SONY", kCGImagePropertyTIFFModel: "ILCE-7RM5"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifISOSpeedRatings: [100]],
            kCGImagePropertyExifAuxDictionary: [kCGImagePropertyExifAuxLensModel: "Example 35mm"],
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCCopyrightNotice: "Example photographer"],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 35.0,
                kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 139.0,
                kCGImagePropertyGPSLongitudeRef: "E"]
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        for format in [ExportFormat.jpeg, .tiff] {
            let output = directory.appending(path: "output.\(format == .jpeg ? "jpg" : "tif")")
            try Exporter.write(image(), to: output, format: format,
                               sourceMetadata: ImageDecoder.sourceMetadata(from: source))
            let p = try properties(output)
            let tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
            XCTAssertEqual(tiff?[kCGImagePropertyTIFFMake] as? String, "SONY")
            XCTAssertEqual(tiff?[kCGImagePropertyTIFFModel] as? String, "ILCE-7RM5")
            let aux = p[kCGImagePropertyExifAuxDictionary] as? [CFString: Any]
            XCTAssertEqual(aux?[kCGImagePropertyExifAuxLensModel] as? String, "Example 35mm")
            let iptc = p[kCGImagePropertyIPTCDictionary] as? [CFString: Any]
            XCTAssertEqual(iptc?[kCGImagePropertyIPTCCopyrightNotice] as? String, "Example photographer")
            let gps = p[kCGImagePropertyGPSDictionary] as? [CFString: Any]
            XCTAssertEqual(gps?[kCGImagePropertyGPSLatitude] as? Double, 35.0)
        }
    }

    func testTIFFColorSpaceDescribesOutputNotSource() throws {
        let profile = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4,
            bitsPerComponent: 8, bytesPerRow: 16, space: profile,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let url = FileManager.default.temporaryDirectory.appending(path: "spk-color-\(UUID().uuidString).tif")
        defer { try? FileManager.default.removeItem(at: url) }
        try Exporter.write(try XCTUnwrap(context.makeImage()), to: url, format: .tiff,
            sourceEXIF: [kCGImagePropertyExifColorSpace: 1])
        let p = try properties(url)
        XCTAssertEqual(p[kCGImagePropertyProfileName] as? String, "Display P3")
        let exif = try XCTUnwrap(p[kCGImagePropertyExifDictionary] as? [CFString: Any])
        XCTAssertEqual(exif[kCGImagePropertyExifColorSpace] as? Int, 0xFFFF)
    }

    func testRenderedMetadataReplacesRAWGeometryAndStorageTags() throws {
        let source: [CFString: Any] = [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFOrientation: 6,
                kCGImagePropertyTIFFCompression: 7, kCGImagePropertyTIFFPhotometricInterpretation: 32803],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifPixelXDimension: 9504,
                kCGImagePropertyExifPixelYDimension: 6336, kCGImagePropertyExifColorSpace: 1,
                kCGImagePropertyExifMakerNote: Data([1, 2, 3])]
        ]
        let output = Exporter.outputMetadata(source, image: image())
        let exif = try XCTUnwrap(output[kCGImagePropertyExifDictionary] as? [CFString: Any])
        let tiff = try XCTUnwrap(output[kCGImagePropertyTIFFDictionary] as? [CFString: Any])
        XCTAssertEqual(output[kCGImagePropertyOrientation] as? Int, 1)
        XCTAssertEqual(tiff[kCGImagePropertyTIFFOrientation] as? Int, 1)
        XCTAssertNil(tiff[kCGImagePropertyTIFFCompression])
        XCTAssertNil(tiff[kCGImagePropertyTIFFPhotometricInterpretation])
        XCTAssertNil(exif[kCGImagePropertyExifMakerNote])
        XCTAssertEqual(exif[kCGImagePropertyExifPixelXDimension] as? Int, 4)
        XCTAssertEqual(exif[kCGImagePropertyExifPixelYDimension] as? Int, 4)
        let originalEXIF = source[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertEqual(originalEXIF?[kCGImagePropertyExifPixelXDimension] as? Int, 9504)
    }

    private func image() -> CGImage {
        let data = Data(repeating: 127, count: 4 * 4 * 4)
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(width: 4, height: 4, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }

    private func writeSource(_ url: URL, exif: [CFString: Any]) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image(), [
            kCGImagePropertyExifDictionary: exif
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    func testCaptureEXIFSurvivesFinishedExport() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "spk-exif-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("source.tif")
        let output = directory.appendingPathComponent("output.tif")
        let expected: [CFString: Any] = [
            kCGImagePropertyExifISOSpeedRatings: [400],
            kCGImagePropertyExifExposureTime: 1.0 / 125.0,
            kCGImagePropertyExifFNumber: 2.8,
            kCGImagePropertyExifLensModel: "Example 50mm",
            kCGImagePropertyExifDateTimeOriginal: "2026:09:22 12:34:56"
        ]
        try writeSource(source, exif: expected)

        let sourceImage = try XCTUnwrap(CGImageSourceCreateWithURL(source as CFURL, nil))
        let sourceProperties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(sourceImage, 0, nil)
            as? [CFString: Any])
        let sourceReadback = try XCTUnwrap(sourceProperties[kCGImagePropertyExifDictionary]
            as? [CFString: Any])
        let carried = try XCTUnwrap(ImageDecoder.sourceEXIF(from: source))
        XCTAssertTrue((carried as NSDictionary).isEqual(to: sourceReadback),
                      "the import side channel changed the source EXIF")

        try Exporter.write(image(), to: output, format: .tiff, sourceEXIF: carried)
        let result = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(result, 0, nil)
            as? [CFString: Any])
        let exported = try XCTUnwrap(properties[kCGImagePropertyExifDictionary]
            as? [CFString: Any])
        for key in expected.keys {
            XCTAssertTrue(NSDictionary(dictionary: [key: exported[key] as Any])
                .isEqual(to: [key: sourceReadback[key] as Any]), "capture field \(key) changed")
        }
    }

    func testBackgroundTextureWriteKeepsPixelsProfileAndEXIF() async throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Unorm, width: 4, height: 4, mipmapped: false)
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        var pixels = [UInt16](repeating: 65535, count: 4 * 4 * 4)
        for i in 0..<16 { pixels[i * 4] = 16000; pixels[i * 4 + 1] = 30000 }
        pixels.withUnsafeBytes {
            texture.replace(region: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0,
                            withBytes: $0.baseAddress!, bytesPerRow: 4 * 8)
        }
        let url = FileManager.default.temporaryDirectory
            .appending(path: "spk-background-export-\(UUID().uuidString).tif")
        defer { try? FileManager.default.removeItem(at: url) }
        let profile = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))
        let exif: [CFString: Any] = [kCGImagePropertyExifISOSpeedRatings: [400]]
        try await Exporter.writeFinishedTexture(texture, space: profile, to: url,
                                                format: .tiff, sourceEXIF: exif)

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.bitsPerComponent, 16)
        XCTAssertEqual(image.width, 4)
        XCTAssertNotNil(image.colorSpace)
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any])
        let storedEXIF = try XCTUnwrap(properties[kCGImagePropertyExifDictionary]
            as? [CFString: Any])
        XCTAssertEqual(storedEXIF[kCGImagePropertyExifISOSpeedRatings] as? [Int], [400])
    }
}
