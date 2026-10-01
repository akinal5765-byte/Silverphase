//  CropMaskedThumbnail.swift — a frame's thumbnail the way Capture One draws
//  it: the whole photograph, with everything outside the crop under a dark,
//  nearly opaque mask, turned and flipped the way the canvas is.
//
//  The user's decision (2026-09-26), for the filmstrip and the export page's
//  cells: show the full picture but make the crop the thing you see. The
//  navigator is different on purpose — it is a map of the canvas, so it shows
//  the cropped frame only (`NavigatorSection.frame`).
//
//  The thumbnail itself stays the uncropped print (`ThumbnailCache`): the
//  mask is drawn over it here, per cell, from the frame's own geometry —
//  the live one for the open frame, the saved one for every other
//  (`Session.thumbnailGeometry(for:)`).

import SwiftUI

enum CropMask {
    struct Key: Equatable {
        let image: ObjectIdentifier?
        let geometry: Geometry
    }
    /// How much of the outside the mask hides. "Very non-transparent": the
    /// cropped-away part is still legible as context, and no more.
    static let opacity: CGFloat = 0.82

    /// `image` with the outside of `geometry`'s crop masked, then turned and
    /// flipped as the canvas turns and flips it. An identity geometry returns
    /// the image itself.
    static func masked(_ image: CGImage, by geometry: Geometry) -> CGImage {
        guard !geometry.isIdentity else { return image }
        var composite = image
        if !(geometry.crop.isFull && geometry.angle == 0),
           let drawn = drawMask(over: image, geometry: geometry) {
            composite = drawn
        }
        // The turns and flips, through the navigator's drawing with a full,
        // level crop — so the orientation arithmetic exists once.
        var orient = Geometry()
        orient.quarterTurns = geometry.quarterTurns
        orient.flipH = geometry.flipH
        orient.flipV = geometry.flipV
        return oriented(composite, by: orient) ?? composite
    }

    private static func oriented(_ image: CGImage, by geometry: Geometry) -> CGImage? {
        guard !geometry.isIdentity else { return image }
        let source = CGSize(width: image.width, height: image.height)
        let out = geometry.outputSize(for: source)
        let w = Int(out.width), h = Int(out.height)
        let space = image.colorSpace ?? ImageDecoder.displayP3
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
                ?? CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                             bytesPerRow: 0, space: ImageDecoder.displayP3,
                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return image }
        ctx.interpolationQuality = .high
        // Innermost last: Core Graphics' bottom-left image placement → the
        // source's top-left pixels → the output's top-left pixels → the
        // context's bottom-left device space.
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
        ctx.concatenate(geometry.outputToSourceTransform(imageSize: source).inverted())
        ctx.translateBy(x: 0, y: source.height); ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: source))
        return ctx.makeImage()
    }

    private static func drawMask(over image: CGImage, geometry: Geometry) -> CGImage? {
        let w = image.width, h = image.height
        let size = CGSize(width: w, height: h)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: image.colorSpace ?? ImageDecoder.displayP3,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
                ?? CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                             space: ImageDecoder.displayP3,
                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        // The crop's corners are normalised with a top-left origin; the
        // context's is bottom-left.
        let corners = geometry.corners(in: size).map { CGPoint(x: $0.x * size.width, y: (1 - $0.y) * size.height) }
        let path = CGMutablePath()
        path.addRect(CGRect(origin: .zero, size: size))
        path.addLines(between: corners)
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(CGColor(gray: 0, alpha: opacity))
        ctx.fillPath(using: .evenOdd)
        return ctx.makeImage()
    }
}
