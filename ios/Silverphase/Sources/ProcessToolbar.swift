import SwiftUI
import UIKit

private struct ReturnToLibraryKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable () -> Void)? = nil
}
extension EnvironmentValues {
    var returnToLibrary: (@MainActor @Sendable () -> Void)? {
        get { self[ReturnToLibraryKey.self] }
        set { self[ReturnToLibraryKey.self] = newValue }
    }
}

/// NavigationStack owns editor actions and the side process picker. Native
/// segmented selection avoids tab-bar overflow while retaining system feedback.
struct ProcessToolbar: ViewModifier {
    let stage: MobileStage
    @Environment(\.returnToLibrary) private var returnToLibrary
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
                .toolbarBackground(.hidden, for: .navigationBar, .bottomBar)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
#if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--side-toolbar-pressure") {
                        // Reproduce competing vertical chrome without relying
                        // on a personal Live Activity or device-only UI.
                        ToolbarItem(placement: .topBarLeading) {
                            Color.clear.frame(width: 44, height: 120)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("侧栏空间测试占位")
                                .accessibilityIdentifier("editor.toolbar-pressure")
                        }.axisBehavior(.verticalPreferred).visibilityPriority(.high)
                        ToolbarSpacer(.fixed, placement: .topBarLeading).axisBehavior(.verticalPreferred)
                    }
#endif

                    if let returnToLibrary {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("返回", systemImage: "chevron.left") { returnToLibrary() }
                                .tint(.primary).disabled(document.isInteractionLocked)
                                .accessibilityIdentifier("editor.library")
                        }.axisBehavior(.horizontalOnly)
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            exporting = true; inspector = true; materials = false
                        } label: { Label("导出", systemImage: "square.and.arrow.up") }
                            .tint(.primary)
                            .disabled(document.image == nil || document.isInteractionLocked)
                            .accessibilityIdentifier("editor.export")
                    }.axisBehavior(.verticalPreferred).visibilityPriority(.low)
                    ToolbarItem(placement: .topBarLeading) {
                        NativeEditorMenu(document: document, inspector: $inspector, materials: $materials,
                                         exporting: $exporting, about: $about, settings: $settings,
                                         importing: $importing, pickingPhotos: $pickingPhotos)
                    }.axisBehavior(.verticalPreferred).visibilityPriority(.low)
                }
        } else if UIDevice.current.userInterfaceIdiom == .pad {
            content
                .toolbar(.visible, for: .navigationBar)
                .toolbarBackground(.hidden, for: .navigationBar)
                .navigationTitle(document.current == nil ? "" : exporting ? "导出成片" : stage.rawValue)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if let returnToLibrary {
                            Button("返回", systemImage: "chevron.left") { returnToLibrary() }
                                .disabled(document.isInteractionLocked)
                                .accessibilityIdentifier("editor.library")
                        }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("导出", systemImage: "square.and.arrow.up") {
                            exporting = true; inspector = true; materials = false
                        }
                        .disabled(document.image == nil || document.isInteractionLocked || document.delivering)
                        .accessibilityIdentifier("editor.export")
                        NativeEditorMenu(document: document, inspector: $inspector, materials: $materials,
                                         exporting: $exporting, about: $about, settings: $settings,
                                         importing: $importing, pickingPhotos: $pickingPhotos)
                    }
                }
        } else {
            content.toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct NativeEditorMenu: View {
    @Environment(\.returnToLibrary) private var returnToLibrary
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
            if let returnToLibrary {
                Button("返回", systemImage: "chevron.left") { returnToLibrary() }.accessibilityIdentifier("editor.library-menu")
            }
            if returnToLibrary == nil {
                Section("导入照片") {
                    Button("从照片导入", systemImage: "photo.on.rectangle") { pickingPhotos = true }
                        .accessibilityIdentifier("import.photos")
                    Button("从文件导入", systemImage: "folder") { importing = true }
                        .accessibilityIdentifier("import.files")
                }
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
    @ViewBuilder var body: some View {
        if #available(iOS 27.1, *), enabled {
            content()
                .toolbar(.visible, for: .bottomBar)
                .toolbar {
                    ToolbarItem(id: "editor.process-picker", placement: .bottomBar) {
                        NativeProcessPicker(stage: stage,
                                            enabled: document.current != nil && !document.isInteractionLocked && !document.delivering,
                                            vertical: true, size: CGSize(width: 48, height: 308)) { item in
                            document.endParameterInteraction()
                            selection.wrappedValue = item
                        }
                        .frame(width: 48, height: 308)
                        .accessibilityIdentifier("editor.side-process-picker")
                    }
                    .axisBehavior(.verticalPreferred)
                    // Process selection must outlast action groups in crowded
                    // vertical bars (including expanded Live Activities).
                    .visibilityPriority(.init(higherThan: .high))
                    .sharedBackgroundVisibility(.hidden)
                }
        } else if UIDevice.current.userInterfaceIdiom == .pad {
            content()
                .toolbar {
                    if #available(iOS 26.0, *) {
                        iPadProcessItem.sharedBackgroundVisibility(.hidden)
                    } else {
                        iPadProcessItem
                    }
                }
        } else { content() }
    }

    private var iPadProcessItem: some ToolbarContent {
        ToolbarItem(id: "editor.process-picker", placement: .topBarLeading) {
            NativeProcessPicker(stage: stage,
                                enabled: document.current != nil && !document.isInteractionLocked && !document.delivering,
                                vertical: false, size: CGSize(width: 336, height: 44),
                                embeddedInToolbar: true, showsTitles: false) { item in
                document.endParameterInteraction()
                selection.wrappedValue = item
            }
            .frame(width: 336, height: 44)
            .accessibilityIdentifier("editor.horizontal-process-picker")
        }
    }
}

/// Read the process picker's actual system-toolbar frame in window coordinates. Align
/// custom panels to that surface, not to a guessed safe-area bottom inset.
struct ProcessBarGeometryProbe: UIViewRepresentable {
    var update: (CGRect?) -> Void
    var windowSizeChanged: ((CGSize) -> Void)? = nil
    var hingeChanged: ((Bool?) -> Void)? = nil
    func makeUIView(context: Context) -> Probe { Probe(update: update, windowSizeChanged: windowSizeChanged, hingeChanged: hingeChanged) }
    func updateUIView(_ view: Probe, context: Context) {
        view.update = update
        view.windowSizeChanged = windowSizeChanged
        view.hingeChanged = hingeChanged
        view.setNeedsLayout()
    }
    final class Probe: UIView {
        var update: (CGRect?) -> Void
        private var last: CGRect?
        private var lastWindowSize: CGSize?
        var windowSizeChanged: ((CGSize) -> Void)?
        var hingeChanged: ((Bool?) -> Void)?
        init(update: @escaping (CGRect?) -> Void, windowSizeChanged: ((CGSize) -> Void)?, hingeChanged: ((Bool?) -> Void)?) {
            self.update = update; self.windowSizeChanged = windowSizeChanged; self.hingeChanged = hingeChanged
            super.init(frame: .zero); isUserInteractionEnabled = false
            if #available(iOS 27.1, *) {
                addInteraction(UIHingeInteraction { [weak self] _, update in
                    let closed = update.hinge.map { $0.status == .closed || $0.status == .unknown }
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.window != nil else { return }
                        self.hingeChanged?(closed)
                    }
                })
            }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() { super.didMoveToWindow(); schedule() }
        override func layoutSubviews() { super.layoutSubviews(); schedule() }
        override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); schedule() }
        private func schedule() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                if self.lastWindowSize != window.bounds.size {
                    self.lastWindowSize = window.bounds.size; self.windowSizeChanged?(window.bounds.size)
                    // System bars finish relocating after the window size notification.
                    for delay in [0.1, 0.3, 0.6, 1.0] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.schedule() }
                    }
                }
                @MainActor func processPicker(in view: UIView) -> UIView? {
                    guard !view.isHidden, view.alpha > 0 else { return nil }
                    if view.accessibilityIdentifier == "editor.side-process-picker" { return view }
                    for child in view.subviews { if let picker = processPicker(in: child) { return picker } }
                    return nil
                }
                guard let picker = processPicker(in: window) else {
                    if self.last != nil { self.last = nil; self.update(nil) }
                    return
                }
                let frame = picker.convert(picker.bounds, to: window)
#if DEBUG
                EditorLayoutAudit.record("system.process-picker", frame)
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
