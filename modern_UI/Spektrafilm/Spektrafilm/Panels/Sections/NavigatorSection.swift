//  NavigatorSection.swift — the frame, small, with where you are looking on it.
//
//  The left rail's first block, which is where Lightroom Classic puts it: at a
//  glance, what is open and which part of it the canvas is showing. It is the
//  one thing on this rail that is not a catalogue, and it is what the rail was
//  missing — two lists cannot fill a 982 pt column, and the answer to that is
//  content, not a taller list.
//
//  **Read-only for now.** It draws the viewport but does not drag it: panning
//  is `renderer.viewport`, which `Session` mirrors rather than owns, and a
//  navigator that writes through a mirror needs a method on `Session` to do it
//  properly. The rectangle is still the useful half — "am I zoomed into the
//  corner or the middle" is the question a navigator answers at a glance.

import SwiftUI

struct NavigatorSection: View {
    @Bindable var session: Session
    @State private var image: CGImage?

    var body: some View {
        PanelSection(L(.sectionNavigator), key: "navigator") {
            VStack(alignment: .leading, spacing: 6) {
                picture
                Text(caption)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
        }
        .task(id: session.selection) {
            guard let url = session.selection else { image = nil; return }
            image = await ThumbnailCache.shared.thumbnail(for: url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .thumbnailUpdated)) { note in
            guard (note.object as? URL) == session.selection,
                  let url = session.selection else { return }
            Task { image = await ThumbnailCache.shared.thumbnail(for: url) }
        }
    }

    /// The picture's size in pixels, or `nil` while it is loading.
    private var imageSize: CGSize? {
        guard let image, image.width > 0, image.height > 0 else { return nil }
        return CGSize(width: image.width, height: image.height)
    }

    /// **A fixed box with the picture fitted inside it.**
    ///
    /// This replaced an `aspectRatio` container, and the reason is worth
    /// keeping: an aspect taken from the *thumbnail* is not known until the
    /// thumbnail arrives, so the box was laid out once at a fallback ratio and
    /// then had a portrait frame `fill`ed into a landscape box — magnified and
    /// cropped, which is what "比刚才更奇怪了" was looking at. A fixed box
    /// cannot be laid out twice, and a fitted rect cannot disagree with the
    /// picture: the mark is placed in the picture's own coordinates inside
    /// that rect, so both are computed from one number.
    private var picture: some View {
        GeometryReader { geo in
            let box = CGRect(origin: .zero, size: geo.size)
            let rect = Self.fitted(imageSize, in: box)
            ZStack(alignment: .topLeading) {
                Theme.plot
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                } else {
                    Image(systemName: "photo").foregroundStyle(Theme.dim)
                        .position(x: box.midX, y: box.midY)
                }
                if let f = visibleFraction {
                    let r = CGRect(x: rect.minX + f.minX * rect.width,
                                   y: rect.minY + f.minY * rect.height,
                                   width: f.width * rect.width,
                                   height: f.height * rect.height)
                    Rectangle()
                        .stroke(Theme.selectionFrame, lineWidth: 1.5)
                        .shadow(color: Theme.overlayInkShadow, radius: 1)
                        .frame(width: r.width, height: r.height)
                        .position(x: r.midX, y: r.midY)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        }
        .frame(height: Theme.Metric.navigatorHeight)
        // The same 1 px edge every other surface has (UI-SPEC §2.2), so a
        // bright photograph does not bleed into the rail.
        .overlay {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .strokeBorder(Theme.controlStroke, lineWidth: 1)
        }
    }

    /// The largest rect of `size`'s aspect that fits in `box`, centred. The
    /// same arithmetic the filmstrip cell gets from `aspectRatio(.fit)`, done
    /// by hand because the mark needs the answer as a number.
    private static func fitted(_ size: CGSize?, in box: CGRect) -> CGRect {
        guard let size, size.width > 0, size.height > 0,
              box.width > 0, box.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: box.midX - w / 2, y: box.midY - h / 2, width: w, height: h)
    }

    /// The part of the image the canvas is showing, as a fraction of the whole.
    ///
    /// `nil` when that is all of it: a rectangle drawn round the whole
    /// thumbnail reports nothing, and a mark that is always there stops being
    /// read.
    private var visibleFraction: CGRect? {
        let v = session.viewportSnapshot
        guard v.image.width > 1, v.image.height > 1,
              v.viewport.width > 1, v.viewport.height > 1 else { return nil }
        let frame = v.imageFrame
        guard frame.width > 0, frame.height > 0 else { return nil }
        let visible = frame.intersection(CGRect(origin: .zero, size: v.viewport))
        guard !visible.isNull, visible.width > 0, visible.height > 0 else { return nil }
        let fraction = CGRect(x: (visible.minX - frame.minX) / frame.width,
                              y: (visible.minY - frame.minY) / frame.height,
                              width: visible.width / frame.width,
                              height: visible.height / frame.height)
        return (fraction.width < 0.995 || fraction.height < 0.995) ? fraction : nil
    }

    private var caption: String {
        guard session.selection != nil else { return L(.navigatorEmpty) }
        return session.isFit ? L(.helpFit) : "\(session.zoomPercent) %"
    }
}
