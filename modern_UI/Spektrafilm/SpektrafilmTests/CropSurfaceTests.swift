import AppKit
import Metal
import XCTest

@MainActor final class CropSurfaceTests: XCTestCase {
    func testTheHistogramDescribesTheCroppedPicture() throws {
        let renderer = try XCTUnwrap(Renderer())
        let card = try halves(renderer, width: 64, height: 32)
        var bins: [Float] = []
        renderer.onHistogram = { bins = $0 }
        renderer.setLive(card)
        renderer.viewport.backingScale = 1

        // Uncropped: both halves are counted. This is the control — without
        // it, a histogram that never published would pass the assertion below.
        renderer.viewport.resize(viewport: CGSize(width: 64, height: 32), image: CGSize(width: 64, height: 32))
        _ = try XCTUnwrap(renderer.renderOffscreen(size: CGSize(width: 64, height: 32), backingScale: 1))
        XCTAssertEqual(bins.count, 1024, "the histogram did not publish")
        XCTAssertGreaterThan(bins[512 + 255], 0.5, "the control frame has no blue in its histogram")

        var g = Geometry()
        g.crop = CropRect(x: 0, y: 0, width: 0.5, height: 1)
        renderer.geometry = g
        let out = g.outputSize(for: CGSize(width: 64, height: 32))
        renderer.viewport.resize(viewport: out, image: out)
        bins = []
        _ = try XCTUnwrap(renderer.renderOffscreen(size: out, backingScale: 1))
        XCTAssertEqual(bins.count, 1024, "the histogram did not publish")
        XCTAssertEqual(bins[512 + 255], 0, "the histogram counts blue the crop removed")
    }

    func testAThumbnailMasksWhatTheCropRemoves() throws {
        let image = try halvesImage(width: 200, height: 100)
        XCTAssertTrue(CropMask.masked(image, by: .default) === image, "an identity geometry should not redraw")

        var g = Geometry()
        g.crop = CropRect(x: 0, y: 0, width: 0.5, height: 1)
        let m = CropMask.masked(image, by: g)
        XCTAssertEqual(m.width, 200, "the thumbnail is the whole picture, not the crop")
        let inside = try rgb(m, x: 50, y: 50), outside = try rgb(m, x: 150, y: 50)
        XCTAssertEqual(inside.r, 1, accuracy: 0.02, "the crop is masked")
        XCTAssertEqual(outside.b, 1 - CropMask.opacity, accuracy: 0.03,
                       "the outside of the crop is not under the mask")
    }

    /// The thumbnail is turned and flipped the way the canvas is.
    func testAThumbnailIsTurnedAsTheCanvasIs() throws {
        let image = try halvesImage(width: 200, height: 100)
        var g = Geometry()
        g.quarterTurns = 1
        let m = CropMask.masked(image, by: g)
        XCTAssertEqual(m.width, 100); XCTAssertEqual(m.height, 200)
        // Turned clockwise, the red left half is now the top.
        XCTAssertEqual(try rgb(m, x: 50, y: 20).r, 1, accuracy: 0.02)
        XCTAssertEqual(try rgb(m, x: 50, y: 180).b, 1, accuracy: 0.02)
    }

    private func halves(_ renderer: Renderer, width w: Int, height h: Int) throws -> MTLTexture {
        let tex = try XCTUnwrap(renderer.store.makeWritable(width: w, height: h))
        let M: UInt16 = 65535
        var px: [UInt16] = []
        px.reserveCapacity(w * h * 4)
        for _ in 0..<h {
            for x in 0..<w { px += x < w / 2 ? [M, 0, 0, M] : [0, 0, M, M] }
        }
        px.withUnsafeBytes {
            tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                        withBytes: $0.baseAddress!, bytesPerRow: w * 8)
        }
        return tex
    }

    private func halvesImage(width w: Int, height h: Int) throws -> CGImage {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w / 2, height: h))
        ctx.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: w / 2, y: 0, width: w / 2, height: h))
        return try XCTUnwrap(ctx.makeImage())
    }

    /// One pixel, top-left origin, 0…1.
    private func rgb(_ image: CGImage, x: Int, y: Int) throws -> (r: Double, g: Double, b: Double) {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = try XCTUnwrap(CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let i = (y * w + x) * 4
        return (Double(px[i]) / 255, Double(px[i + 1]) / 255, Double(px[i + 2]) / 255)
    }

}
