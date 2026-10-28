import SwiftUI

struct MobileCropControls: View {
    @Bindable var document: MobileDocument
    private var g: Geometry { document.current?.geometry.value ?? Geometry() }
    private var size: CGSize { document.geometrySourceSize }
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("裁切比例").foregroundStyle(.secondary)
                Spacer()
                Picker("裁切比例", selection: Binding(get: { g.aspect.canonical }, set: { aspect in
                    var next = g; next.aspect = g.aspect.isPortrait ? aspect.transposed : aspect
                    document.setGeometry(next.constrained(in: size))
                })) {
                    ForEach(CropAspect.pickerCases) { aspect in
                        Text(aspect == .free ? "自由" : aspect == .original ? "原始比例" : aspect.label).tag(aspect)
                    }
                }.labelsHidden().pickerStyle(.menu).font(EditorDesign.selectedValue)
                Button {
                    var next = g; next.aspect = g.aspect.transposed
                    document.setGeometry(next.constrained(in: size))
                } label: { Image(systemName: g.aspect.isPortrait ? "rectangle.portrait" : "rectangle") }
                    .frame(width: 44, height: 44).disabled(!g.aspect.hasOrientation)
                    .accessibilityLabel("切换裁切方向")
            }.frame(minHeight: 44)
            RulerParameterRow(title: "校直 · °", value: Binding(get: { g.angle }, set: {
                document.setGeometry(g.straightened(to: $0, in: size))
            }), range: -45...45, defaultValue: 0, fractionDigits: 1, step: 0.1,
                              onInteraction: document.parameterInteraction, onReset: { document.setGeometry(g.straightened(to: 0, in: size)) })
            HStack {
                tool("rotate.left", "向左旋转") { document.setGeometry(g.turned(by: -1)) }
                tool("rotate.right", "向右旋转") { document.setGeometry(g.turned(by: 1)) }
                tool("arrow.left.and.right.righttriangle.left.righttriangle.right", "水平翻转", active: g.flipH) {
                    var next = g; next.flipH.toggle(); document.setGeometry(next)
                }
                tool("arrow.up.and.down.righttriangle.up.righttriangle.down", "垂直翻转", active: g.flipV) {
                    var next = g; next.flipV.toggle(); document.setGeometry(next)
                }
                Spacer(minLength: 0)
            }
            let output = g.outputSize(for: size)
            Text(String(format: "%d × %d · %.1f MP", Int(output.width), Int(output.height), output.width * output.height / 1e6)).font(EditorDesign.panelSummary)
                .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                .modifier(AdjustmentNumberTransition(value: output.width * output.height / 1e6, fractionDigits: 1))
            Text("拖动框内移动裁切；拖动边缘或四角调整范围。空白处拖动可重新框选。")
                .font(EditorDesign.help).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("恢复完整画面") { document.setGeometry(Geometry()) }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }.font(EditorDesign.parameter).buttonStyle(.plain)
        if MobileFilmGate.presents(document.current?.recipe ?? [:]) {
            Text("当前使用原始画面编辑裁切，完成后再装入胶片画幅并应用片边／日期背。")
                .font(EditorDesign.help).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func tool(_ symbol: String, _ title: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 18)).frame(width: 44, height: 44) }
            .foregroundStyle(active ? Color.orange : Color.primary).accessibilityLabel(title)
    }
}

struct MobileCropCanvas: View {
    let image: CGImage
    let geometry: Geometry
    let sourceSize: CGSize
    let insets: EdgeInsets
    let commit: (Geometry) -> Void
    @State private var draft: Geometry?
    @State private var baseline: Geometry?
    private var current: Geometry { draft ?? geometry }
    var body: some View {
        GeometryReader { proxy in
            let available = CGSize(width: max(1, proxy.size.width - insets.leading - insets.trailing - 44),
                                   height: max(1, proxy.size.height - insets.top - insets.bottom - 44))
            let rect = CGRect(x: insets.leading + 22, y: insets.top + 22, width: available.width, height: available.height)
            let photoOutline = Path { p in
                p.addLines([CGPoint.zero, CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)].map { point($0, in: rect) }); p.closeSubpath()
            }
            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1).resizable().frame(width: sourceSize.width, height: sourceSize.height)
                    .transformEffect(viewMap(in: rect)).allowsHitTesting(false)
                photoOutline.fill(.white.opacity(0.001)).contentShape(photoOutline).gesture(redraw(in: rect))
                Canvas { context, _ in
                    let corners = current.corners(in: sourceSize).map { point($0, in: rect) }
                    var polygon = Path(); polygon.addLines(corners); polygon.closeSubpath()
                    var mask = photoOutline; mask.addPath(polygon)
                    context.fill(mask, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
                    context.stroke(polygon, with: .color(.white), lineWidth: 1)
                    var grid = Path()
                    for t in [1.0 / 3, 2.0 / 3] {
                        for ends in [[CGPoint(x: t, y: 0), CGPoint(x: t, y: 1)], [CGPoint(x: 0, y: t), CGPoint(x: 1, y: t)]] {
                            let points = ends.map { p in
                                point(current.rotated(CGPoint(x: current.crop.x + p.x * current.crop.width,
                                                              y: current.crop.y + p.y * current.crop.height), in: sourceSize), in: rect)
                            }
                            grid.move(to: points[0]); grid.addLine(to: points[1])
                        }
                    }
                    context.stroke(grid, with: .color(.white.opacity(0.5)), lineWidth: 0.5)
                }.allowsHitTesting(false)
                // Body and all eight grips share desktop hit/move/resize math.
                Path { p in p.addLines(current.corners(in: sourceSize).map { point($0, in: rect) }); p.closeSubpath() }
                    .fill(.white.opacity(0.001)).contentShape(Path { p in
                        p.addLines(current.corners(in: sourceSize).map { point($0, in: rect) }); p.closeSubpath()
                    }).gesture(drag(.body, in: rect))
                ForEach(CropHandle.allCases.filter { $0 != .body }, id: \.rawValue) { handle in
                    let anchor = current.rotated(CGPoint(x: current.crop.x + handle.position.x * current.crop.width,
                                                         y: current.crop.y + handle.position.y * current.crop.height), in: sourceSize)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.white).frame(width: handle.isCorner ? 10 : handle.movesTop || handle.movesBottom ? 22 : 4,
                                            height: handle.isCorner ? 10 : handle.movesTop || handle.movesBottom ? 4 : 22)
                        .rotationEffect(.degrees(Double(current.quarterTurns * 90)))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                        .position(point(anchor, in: rect)).gesture(drag(handle, in: rect))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("调整裁切范围")
                        .accessibilityIdentifier("crop.handle." + handle.rawValue)
                }
            }.frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }.coordinateSpace(name: "mobileCropCanvas").clipped()
            .accessibilityElement(children: .contain).accessibilityIdentifier("crop.canvas")
            .accessibilityValue(String(format: "%.4f,%.4f,%.4f,%.4f;%.1f;%d;%d;%d", current.crop.x, current.crop.y, current.crop.width, current.crop.height, current.angle, current.quarterTurns, current.flipH ? 1 : 0, current.flipV ? 1 : 0))
            .onChange(of: geometry) { _, _ in if baseline == nil { draft = nil } }
    }
    private func viewMap(in rect: CGRect) -> CGAffineTransform {
        // Keep the crop frame level while the picture turns underneath it,
        // like desktop edit space. Coarse turns/flips also remain visible.
        let turn = -current.angle * .pi / 180 + Double(current.quarterTurns) * .pi / 2
        let rotation = CGAffineTransform(translationX: -sourceSize.width / 2, y: -sourceSize.height / 2)
            .concatenating(.init(rotationAngle: turn))
            .concatenating(.init(scaleX: current.flipH ? -1 : 1, y: current.flipV ? -1 : 1))
        let bounds = CGRect(origin: .zero, size: sourceSize).applying(rotation)
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        return rotation.concatenating(.init(scaleX: scale, y: scale))
            .concatenating(.init(translationX: rect.midX - bounds.midX * scale, y: rect.midY - bounds.midY * scale))
    }
    private func point(_ p: CGPoint, in rect: CGRect) -> CGPoint { CGPoint(x: p.x * sourceSize.width, y: p.y * sourceSize.height).applying(viewMap(in: rect)) }
    private func source(_ p: CGPoint, in rect: CGRect) -> CGPoint {
        let pixel = p.applying(viewMap(in: rect).inverted())
        return CGPoint(x: pixel.x / sourceSize.width, y: pixel.y / sourceSize.height)
    }
    private func drag(_ handle: CropHandle, in rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("mobileCropCanvas")).onChanged { event in
            if baseline == nil { baseline = geometry }
            guard let start = baseline else { return }
            if handle == .body {
                let a = source(event.startLocation, in: rect), b = source(event.location, in: rect)
                draft = start.moved(by: CGSize(width: b.x - a.x, height: b.y - a.y), in: sourceSize)
            } else { draft = start.resized(handle: handle, to: start.unrotated(source(event.location, in: rect), in: sourceSize), in: sourceSize) }
        }.onEnded { _ in finish() }
    }
    private func redraw(in rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("mobileCropCanvas")).onChanged { event in
            if baseline == nil { baseline = geometry }
            let a = geometry.unrotated(source(event.startLocation, in: rect), in: sourceSize)
            let b = geometry.unrotated(source(event.location, in: rect), in: sourceSize)
            draft = geometry.redrawn(as: CropRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y)), in: sourceSize)
        }.onEnded { _ in finish() }
    }
    private func finish() { if let draft { commit(draft) }; baseline = nil; draft = nil }
}
