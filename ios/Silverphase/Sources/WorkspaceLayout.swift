import SwiftUI

/// Window geometry, not a device model or orientation, decides the workspace.
/// All frames are in the root GeometryReader's local coordinate space.
struct WorkspaceLayout {
    let navigation: CGRect
    let navigationContent: CGRect
    let inspector: CGRect
    let media: CGRect
    let usesSidebar: Bool
    let usesTwoNavigationRows: Bool
    let photoInsets: EdgeInsets
    private let windowWidth: CGFloat

    init(size: CGSize, safe: EdgeInsets, exclusions: [CGRect],
         showsMedia: Bool, systemBars: Bool = false, systemBarFrame: CGRect? = nil, showInspector: Bool = true, materialBrowser: Bool, dockFraction: Double) {
        windowWidth = size.width
        let gap = EditorDesign.gutter
        // The editor passes zero extra insets because NavigationStack already
        // constrains its GeometryReader proposal to the hardware/toolbar safe
        // area. `safe` is for callers supplying an unconstrained viewport.
        let left = gap + max(0, safe.leading)
        // Keep a full-height column left of Duo's status/camera sidebar.
        // Moving the column horizontally is preferable to cutting it in half.
        let trailingObstacles = exclusions.filter { (systemBarFrame == nil || $0.maxX < systemBarFrame!.minX) && $0.maxX > size.width * 0.75 && $0.minY < size.height * 0.8 }
        let systemRight = systemBarFrame.map { $0.minX - gap } ?? size.width - max(gap, safe.trailing)
        let contentRight = min(systemRight,
                               trailingObstacles.map { $0.minX - gap }.min() ?? size.width - gap)
        let usable = max(1, contentRight - left)
        let twoRows = !systemBars && usable < 620
        usesTwoNavigationRows = twoRows
        navigation = CGRect(x: 0, y: 0, width: size.width,
                            height: systemBars ? 0 : max(0, safe.top) + (twoRows ? 96 : 52))
        let headerBand = CGRect(x: max(8, safe.leading), y: max(0, safe.top) + (twoRows ? 2 : 4),
                                width: max(1, size.width - max(8, safe.leading) - max(8, safe.trailing)),
                                height: twoRows ? 92 : 44)
        navigationContent = Self.unobstructedHeader(headerBand, exclusions: exclusions, gap: gap)
        let workTop = navigation.maxY + gap
        let bottom = min(size.height - max(gap, safe.bottom), systemBarFrame?.maxY ?? .greatestFiniteMagnitude)
        usesSidebar = usable >= (systemBars ? 240 : 320) + 264 + gap
        let panelWidth = min(324, max(264, usable * 0.34))
        let mediaHeight: CGFloat = showsMedia ? EditorDesign.browserHeight : 0
        if usesSidebar {
            inspector = CGRect(x: contentRight - panelWidth, y: workTop,
                               width: panelWidth, height: max(1, bottom - workTop))
        } else {
            let height = min((bottom - workTop) * min(0.65, max(0.25, dockFraction)), 360)
            inspector = CGRect(x: left, y: bottom - mediaHeight - gap - height,
                               width: usable, height: max(1, height))
        }
        let mediaRight = usesSidebar && showInspector ? inspector.minX - gap : contentRight
        media = showsMedia ? CGRect(x: left, y: bottom - mediaHeight,
                                    width: max(1, mediaRight - left), height: mediaHeight) : .zero
        photoInsets = EdgeInsets(top: workTop, leading: left,
                                 bottom: showsMedia ? size.height - media.minY + gap : size.height - bottom,
                                 trailing: size.width - contentRight)
    }

    private static func unobstructedHeader(_ frame: CGRect, exclusions: [CGRect], gap: CGFloat) -> CGRect {
        var spans = [(frame.minX, frame.maxX)]
        for exclusion in exclusions where exclusion.intersects(frame) {
            spans = spans.flatMap { start, end -> [(CGFloat, CGFloat)] in
                guard exclusion.maxX > start && exclusion.minX < end else { return [(start, end)] }
                return [(start, min(end, exclusion.minX - gap)), (max(start, exclusion.maxX + gap), end)].filter { $0.1 > $0.0 }
            }
        }
        let best = spans.max { $0.1 - $0.0 < $1.1 - $1.0 } ?? (frame.minX, frame.minX + 1)
        return CGRect(x: best.0, y: frame.minY, width: best.1 - best.0, height: frame.height)
    }

    func imageInsets(showInspector: Bool) -> EdgeInsets {
        var result = photoInsets
        if showInspector {
            if usesSidebar { result.trailing = max(result.trailing, windowWidth - inspector.minX + EditorDesign.gutter) }
            else { result.bottom += inspector.height + EditorDesign.gutter }
        }
        return result
    }


}

func workspaceExclusions(_ geometry: GeometryProxy) -> [CGRect] {
    if #available(iOS 27.1, *) {
        return (geometry.reservedRegions(kind: .occlusion) + geometry.reservedRegions(kind: .division)).map { region in
            let f = region.frame, m = region.margins
            return CGRect(x: f.minX - m.leading, y: f.minY - m.top,
                          width: f.width + m.leading + m.trailing, height: f.height + m.top + m.bottom)
        }.filter { !$0.isEmpty }
    }
    return []
}

struct WorkspaceGlassGroup: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { GlassEffectContainer(spacing: 12) { content } }
        else { content }
    }
}
