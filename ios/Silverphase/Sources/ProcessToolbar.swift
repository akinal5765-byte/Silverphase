import SwiftUI
import UIKit

/// Like Layerlight, destinations belong to a native tab bar; actions belong
/// to the NavigationStack above it. The system owns grouping and selection.
struct ProcessToolbar: ViewModifier {
    @Bindable var document: MobileDocument
    @Binding var inspector: Bool
    @Binding var materials: Bool
    @Binding var exporting: Bool
    @Binding var about: Bool
    @Binding var settings: Bool
    @Binding var importing: Bool
    @Binding var pickingPhotos: Bool
    var enabled: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 27.1, *), enabled {
            content
                .toolbar(.visible, for: .navigationBar)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            exporting = true; inspector = true; materials = false
                        } label: { Label("导出", systemImage: "square.and.arrow.up") }
                            .tint(.primary)
                            .disabled(document.image == nil || document.isInteractionLocked)
                            .accessibilityIdentifier("editor.export")
                    }.axisBehavior(.verticalPreferred)
                    ToolbarItem(placement: .topBarLeading) {
                        NativeEditorMenu(document: document, inspector: $inspector, materials: $materials,
                                         exporting: $exporting, about: $about, settings: $settings,
                                         importing: $importing, pickingPhotos: $pickingPhotos)
                    }.axisBehavior(.verticalPreferred)
                }
        } else {
            content.toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct NativeEditorMenu: View {
    @Bindable var document: MobileDocument
    @Binding var inspector: Bool
    @Binding var materials: Bool
    @Binding var exporting: Bool
    @Binding var about: Bool
    @Binding var settings: Bool
    @Binding var importing: Bool
    @Binding var pickingPhotos: Bool
    var body: some View {
        Menu {
            Section("导入照片") {
                Button("从照片导入", systemImage: "photo.on.rectangle") { pickingPhotos = true }
                    .accessibilityIdentifier("import.photos")
                Button("从文件导入", systemImage: "folder") { importing = true }
                    .accessibilityIdentifier("import.files")
            }
            Section {
                Button("撤销", systemImage: "arrow.uturn.backward") { document.undo() }.disabled(!document.canUndo)
                Button("重做", systemImage: "arrow.uturn.forward") { document.redo() }.disabled(!document.canRedo)
                Button("重置当前照片", systemImage: "arrow.counterclockwise") { document.reset() }.disabled(document.current == nil)
            }
            Section {
                Button("适合窗口", systemImage: "arrow.down.right.and.arrow.up.left") { document.zoomToFit() }.disabled(document.image == nil || document.cropEditing)
                Button("1:1 原始像素", systemImage: "1.magnifyingglass") { document.zoomToNative() }.disabled(document.image == nil || document.cropEditing)
            }
            Section {
                Button("设置", systemImage: "gearshape") { settings = true }
                Button("关于 Silverphase", systemImage: "info.circle") { about = true }
            }
        } label: { Label("菜单", systemImage: "ellipsis") }
        .tint(.primary)
        .disabled(document.isInteractionLocked)
        .accessibilityIdentifier("editor.menu")
    }
}

struct ProcessNavigation<Content: View>: View {
    @Bindable var document: MobileDocument
    @Binding var stage: MobileStage
    @Binding var inspector: Bool
    @Binding var materials: Bool
    @Binding var exporting: Bool
    var enabled: Bool
    @ViewBuilder var content: () -> Content
    private var selection: Binding<MobileStage> {
        Binding(get: { stage }, set: { item in
            guard document.current != nil, !document.isInteractionLocked, !document.delivering else { return }
            stage = item; inspector = true; exporting = false
            materials = item == .film || item == .print
        })
    }
    private func stageIcon(_ item: MobileStage) -> UIImage {
        let color: UIColor = stage == item ? .systemOrange : .label
        let colorTraits = UITraitCollection(userInterfaceStyle: .dark)
        let source = (UIImage(systemName: item.symbol,
                              withConfiguration: UIImage.SymbolConfiguration(pointSize: EditorDesign.glyphSize, weight: .regular)) ?? UIImage())
            .withTintColor(color.resolvedColor(with: colorTraits), renderingMode: .alwaysOriginal)
        let side = EditorDesign.glyphSize
        let scale = min(side / max(1, source.size.width), side / max(1, source.size.height))
        let size = CGSize(width: source.size.width * scale, height: source.size.height * scale)
        // A point-size configuration is a font metric, not an image bound.
        // Normalize every native tab symbol to the same drawing box used by
        // other editor glyphs; keep the system's larger touch region intact.
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            source.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2,
                                   width: size.width, height: size.height))
        }.withRenderingMode(.alwaysOriginal)
    }
    @ViewBuilder var body: some View {
        if #available(iOS 27.1, *), enabled {
            TabView(selection: selection) {
                ForEach(MobileStage.allCases) { item in
                    Tab(value: item) {
                        // Inactive tab canvases must not publish stale/zero
                        // geometry into the selected photo's detail request.
                        if stage == item { content().tint(.primary) } else { Color.clear }
                    } label: {
                        Label {
                            Text(item.rawValue)
                        } icon: {
                            // The shared Duo bar can replace a template icon's
                            // tint with its action group's primary color. As in
                            // Layerlight's system picker, retain the icon color
                            // while leaving selection/glass/tracking native.
                            Image(uiImage: stageIcon(item)).renderingMode(.original)
                        }
                        .accessibilityIdentifier("stage." + item.id)
                    }
                    .disabled(document.current == nil || document.isInteractionLocked || document.delivering)
                }
            }
            .tabViewStyle(.tabBarOnly)
            .tint(MobileStyle.accent)
        } else { content() }
    }
}

/// Read the system's actual tab-bar surface in window coordinates. Align
/// custom panels to that surface, not to a guessed safe-area bottom inset.
struct ProcessBarGeometryProbe: UIViewRepresentable {
    var update: (CGRect?) -> Void
    func makeUIView(context: Context) -> Probe { Probe(update: update) }
    func updateUIView(_ view: Probe, context: Context) {
        view.update = update
        view.setNeedsLayout()
    }
    final class Probe: UIView {
        var update: (CGRect?) -> Void
        private var last: CGRect?
        init(update: @escaping (CGRect?) -> Void) { self.update = update; super.init(frame: .zero); isUserInteractionEnabled = false }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() { super.didMoveToWindow(); schedule() }
        override func layoutSubviews() { super.layoutSubviews(); schedule() }
        private func schedule() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                @MainActor func tabBar(in view: UIView) -> UITabBar? {
                    if let bar = view as? UITabBar, !bar.isHidden, bar.alpha > 0 { return bar }
                    for child in view.subviews { if let bar = tabBar(in: child) { return bar } }
                    return nil
                }
                guard let bar = tabBar(in: window) else { return }
                let container = bar.convert(bar.bounds, to: window)
                let vertical = container.height > container.width
                // UIKit relocates the tab content into a shared host. That
                // host does not expose its virtual accessibility children as
                // UIView labels. Locate the narrow vertical group by the
                // public frames of its equally aligned tab hit regions.
                // Do not depend on private UIKit class names or selectors.
                var surfaces: [CGRect] = []
                let count = bar.items?.count ?? MobileStage.allCases.count
                @MainActor func collect(_ view: UIView) {
                    guard !view.isHidden, view.alpha > 0.01 else { return }
                    let rect = view.convert(view.bounds, to: window)
                    if vertical, rect.width >= 40, rect.width <= container.width,
                       rect.height > rect.width, rect.minX > window.bounds.midX {
                        let hits = view.subviews.filter { !$0.isHidden && $0.alpha > 0.01 }.map { $0.convert($0.bounds, to: window) }
                            .filter { $0.width >= 32 && $0.width <= rect.width && $0.height >= 32 && $0.height < rect.height }
                        let rows = Set(hits.map { Int($0.midY.rounded()) })
                        if count > 1, rows.count == count,
                           hits.allSatisfy({ abs($0.midX - rect.midX) < 1 && rect.contains($0) }) {
                            surfaces.append(rect)
                        }
                    }
                    for child in view.subviews { collect(child) }
                }
                collect(window)
                let validSurface = surfaces.min { $0.width * $0.height < $1.width * $1.height }
                let frame = vertical ? (validSurface ?? container) : container
#if DEBUG
                EditorLayoutAudit.record("system.tabbar.container", container)
                if let validSurface { EditorLayoutAudit.record("system.tabbar.surface", validSurface) }
#endif
                guard frame != self.last else { return }
                self.last = frame
                self.update(frame)
            }
        }
    }
}

#if DEBUG
@MainActor private enum EditorLayoutAudit {
    static var frames: [String: [String: Double]] = [:]
    static func record(_ name: String, _ frame: CGRect) {
        guard ProcessInfo.processInfo.arguments.contains("--smoke-test") || ProcessInfo.processInfo.arguments.contains("--layout-audit") else { return }
        frames[name] = ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
        if let data = try? JSONSerialization.data(withJSONObject: frames, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL.documentsDirectory.appendingPathComponent("editor-layout-audit.json"), options: .atomic)
        }
    }
}
#endif

extension View {
    @ViewBuilder func auditEditorBounds(_ name: String, safe: Bool = false) -> some View {
#if DEBUG
        self.onGeometryChange(for: CGRect.self) { geometry in
            let frame = geometry.frame(in: .global)
            let insets = geometry.safeAreaInsets
            return safe ? CGRect(x: frame.minX + insets.leading, y: frame.minY + insets.top,
                                 width: max(0, frame.width - insets.leading - insets.trailing),
                                 height: max(0, frame.height - insets.top - insets.bottom)) : frame
        } action: { EditorLayoutAudit.record(name, $0) }
#else
        self
#endif
    }
}
