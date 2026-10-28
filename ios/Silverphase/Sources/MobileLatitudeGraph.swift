import SwiftUI

/// The desktop LatitudePlot's semantics, with the existing engine measurement.
/// A neutral-medium probe is not an RGB histogram of the rendered photograph.
struct MobileLatitudeGraph: View {
    let latitude: MobileLatitude
    var body: some View {
        VStack(spacing: 8) {
            Canvas { context, size in
                let plotHeight: CGFloat = 78
                let bandY: CGFloat = 82
                func x(_ ev: Double) -> CGFloat { (ev + 8) / 16 * size.width }
                let bins = Array(zip(latitude.centres, latitude.bins)).filter { (-8...8).contains($0.0) }
                let peak = max(bins.map { sqrt(max(0, $0.1)) }.max() ?? 0, 1e-9)
                let half = (latitude.hiEV - latitude.loEV) / Double(max(1, latitude.bins.count)) / 2
                context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: plotHeight)), with: .color(.black.opacity(0.1)))
                for ev in stride(from: -6, through: 6, by: 2) {
                    var grid = Path(); grid.move(to: CGPoint(x: x(Double(ev)), y: 0)); grid.addLine(to: CGPoint(x: x(Double(ev)), y: plotHeight))
                    context.stroke(grid, with: .color(.white.opacity(ev == 0 ? 0.18 : 0.07)), lineWidth: 0.5)
                }
                var histogram = Path()
                histogram.move(to: CGPoint(x: 0, y: plotHeight))
                for (ev, fraction) in bins {
                    let y = plotHeight - (plotHeight - 4) * sqrt(max(0, fraction)) / peak
                    histogram.addLine(to: CGPoint(x: x(ev - half), y: y))
                    histogram.addLine(to: CGPoint(x: x(ev + half), y: y))
                }
                histogram.addLine(to: CGPoint(x: size.width, y: plotHeight)); histogram.closeSubpath()
                let low = min(size.width, max(0, x(latitude.shadow)))
                let high = min(size.width, max(low, x(latitude.highlight)))
                for (start, end, inside) in [(CGFloat(0), low, false), (low, high, true), (high, size.width, false)] {
                    context.drawLayer { layer in
                        layer.clip(to: Path(CGRect(x: start, y: 0, width: end - start, height: plotHeight)))
                        layer.fill(histogram, with: .color(.white.opacity(inside ? 0.5 : 0.18)))
                        layer.stroke(histogram, with: .color(inside ? .white.opacity(0.7) : MobileStyle.accent), lineWidth: 1)
                    }
                }
                let separation = latitude.separation.filter { (-8...8).contains($0.0) }
                let stops = separation.map { Gradient.Stop(color: Color.white.opacity($0.1 * 0.85), location: ($0.0 + 8) / 16) }
                if !stops.isEmpty {
                    context.fill(Path(roundedRect: CGRect(x: 0, y: bandY, width: size.width, height: 6), cornerRadius: 3),
                                 with: .linearGradient(Gradient(stops: stops), startPoint: CGPoint(x: 0, y: bandY), endPoint: CGPoint(x: size.width, y: bandY)))
                }
                for ev in [latitude.shadow, latitude.highlight] where (-8...8).contains(ev) {
                    var boundary = Path(); boundary.move(to: CGPoint(x: x(ev), y: 1)); boundary.addLine(to: CGPoint(x: x(ev), y: bandY + 6))
                    context.stroke(boundary, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 0.75, dash: [2, 2]))
                    let label = Text(String(format: "%+.2f", ev)).font(.system(size: 10)).foregroundStyle(.secondary)
                    let anchor: UnitPoint = x(ev) < 42 ? .topLeading : x(ev) > size.width - 42 ? .topTrailing : .top
                    context.draw(label, at: CGPoint(x: min(size.width - 2, max(2, x(ev))), y: 2), anchor: anchor)
                }
                for ev in stride(from: -8, through: 8, by: 2) {
                    context.draw(Text(ev > 0 ? "+\(ev)" : "\(ev)").font(.system(size: 9)).foregroundStyle(.secondary),
                                 at: CGPoint(x: x(Double(ev)), y: 94), anchor: ev == -8 ? .topLeading : ev == 8 ? .topTrailing : .top)
                }
            }.frame(height: 108).clipped()
            HStack(spacing: 4) {
                share("低于", latitude.below, warns: true)
                Spacer(minLength: 0)
                share("范围内", latitude.within, warns: false)
                Spacer(minLength: 0)
                share("高于", latitude.above, warns: true)
            }
            Text(String(format: "%.2f 档保留 · %+.2f → %+.2f EV", latitude.highlight - latitude.shadow, latitude.shadow, latitude.highlight))
                .font(EditorDesign.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            Text("统计完整输入场景；裁切不改变测光。")
                .font(.system(size: 10)).foregroundStyle(.tertiary).frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityElement(children: .combine).accessibilityLabel("场景分布与胶片相纸宽容度")
    }
    private func share(_ title: String, _ value: Double, warns: Bool) -> some View {
        Text(title + String(format: " %.1f%%", value * 100))
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(warns && value >= 0.005 ? MobileStyle.accent : .secondary)
    }
}
