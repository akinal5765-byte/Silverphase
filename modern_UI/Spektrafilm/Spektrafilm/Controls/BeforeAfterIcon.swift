//  BeforeAfterIcon.swift — the split-view glyph, from the drawing.
//
//  Traced from `modern_UI/control_asset/SVG/资源 1.svg` rather than
//  approximated: the numbers below are that file's, on its own 60.8 × 48.11
//  viewBox, scaled to whatever box the view is given. An outlined rectangle on
//  the left (what the picture was), a filled one on the right (what it is),
//  and the divider between them — the same three marks the shader draws.
//
//  It is a view rather than an asset because it has to take the interface's
//  colour: selected controls tint orange (Capture One's convention, and the
//  rule this app now follows), and a bitmap or a colour-baked SVG cannot.

import SwiftUI

struct BeforeAfterIcon: View {
    /// The glyph's colour. The filled half is drawn at reduced opacity so the
    /// two rectangles stay distinguishable in one colour.
    var color: Color = Theme.text
    var lineWidth: CGFloat = 1.4
    /// Which half is **filled**: the picture on the right (the print) by
    /// default, the frame on the left when the *original* is what the canvas is
    /// showing. The block changing sides is the whole of the state change —
    /// the divider stays where it is, because it is the split and not the
    /// selection, and a glyph whose divider moved would be saying the split had
    /// moved too.
    var showingBefore = false

    /// The source drawing's coordinate system.
    private static let art = CGSize(width: 60.8, height: 48.11)

    var body: some View {
        GeometryReader { geo in
            let m = BeforeAfterIcon.fit(geo.size)
            // The drawing's two rectangles, in view coordinates.
            let left = m.rect(1, 6.32, 23.52, 35.28)
            let right = m.rect(35.87, 5.27, 24.93, 37.39)
            ZStack(alignment: .topLeading) {
                // The block: filled where the picture is, empty where the frame
                // is. It swaps sides and nothing else about the glyph moves.
                Path { $0.addRect(left) }
                    .fill(color.opacity(showingBefore ? 0.5 : 0))
                Path { $0.addRect(right) }
                    .fill(color.opacity(showingBefore ? 0 : 0.5))
                // The outline follows the block, so the half that is not filled
                // reads as a frame rather than as nothing.
                Path { $0.addRect(showingBefore ? right : left) }
                    .stroke(color, lineWidth: lineWidth)
                // The divider, full height.
                Path { p in
                    p.move(to: m.point(30.5, 0))
                    p.addLine(to: m.point(30.5, BeforeAfterIcon.art.height))
                }
                .stroke(color, lineWidth: lineWidth)
            }
        }
    }

    /// Art coordinates → view coordinates: aspect-fit, centred.
    struct Fit {
        var scale: CGFloat, dx: CGFloat, dy: CGFloat
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: dx + x * scale, y: dy + y * scale)
        }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(origin: point(x, y), size: CGSize(width: w * scale, height: h * scale))
        }
    }

    static func fit(_ size: CGSize) -> Fit {
        let s = min(size.width / art.width, size.height / art.height)
        return Fit(scale: s,
                   dx: (size.width - art.width * s) / 2,
                   dy: (size.height - art.height * s) / 2)
    }
}
