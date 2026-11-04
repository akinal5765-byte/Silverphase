import SwiftUI
import UIKit

/// Floating tools never participate in the photograph's fit rectangle.
struct CompactPhoneLayout {
    let inspector: CGRect
    let media: CGRect
    let tabs: CGRect
    let maximumPanelHeight: CGFloat
    init(size: CGSize, fraction: Double, showsPhotos: Bool) {
        let gap: CGFloat = 12
        let width = max(1, size.width - 2 * gap)
        tabs = CGRect(x: gap, y: max(gap, size.height - 56 - gap), width: width, height: 56)
        let mediaHeight: CGFloat = showsPhotos ? (size.height < 480 ? 84 : EditorDesign.browserHeight) : 0
        media = showsPhotos ? CGRect(x: gap, y: tabs.minY - gap - mediaHeight, width: width, height: mediaHeight) : .zero
        let bottom = (showsPhotos ? media.minY : tabs.minY) - gap
        let top = gap
        maximumPanelHeight = max(1, min(520, size.height * 0.72, bottom - top))
        let height = min(maximumPanelHeight, max(min(176, maximumPanelHeight), size.height * min(0.72, max(0.25, fraction))))
        inspector = CGRect(x: gap, y: bottom - height, width: width, height: height)
    }
}

/// Custom labels inside a native toolbar segmented control. UIKit owns the
/// glass selection lens, tracking and drag animation (as in Layerlight's dock).
struct CompactProcessTabs: View {
    let stage: MobileStage
    var enabled: Bool
    let select: (MobileStage) -> Void
    var body: some View {
        GeometryReader { geometry in
            NativeProcessPicker(stage: stage, enabled: enabled, vertical: false,
                                size: CGSize(width: max(1, geometry.size.width), height: 56), select: select)
                .frame(width: geometry.size.width, height: 56)
        }
        .accessibilityIdentifier("editor.compact-tabs")
    }
}

struct NativeProcessPicker: UIViewRepresentable {
    let stage: MobileStage
    let enabled: Bool
    let vertical: Bool
    let size: CGSize
    var embeddedInToolbar = false
    var showsTitles = true
    let select: (MobileStage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let view: UIView = vertical || embeddedInToolbar ? ProcessSegmentsHost(size: size, vertical: vertical) : ProcessPickerToolbar(size: size, vertical: false)
        let host = (view as? ProcessPickerToolbar)?.host ?? (view as! ProcessSegmentsHost)
        host.control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
        if let toolbar = view as? ProcessPickerToolbar {
            toolbar.configure(size: size, vertical: vertical, stage: stage, enabled: enabled)
        } else if let host = view as? ProcessSegmentsHost {
            // NavigationStack already supplies the native toolbar host.
            host.configure(size: size, vertical: vertical, stage: stage, enabled: enabled, showsTitles: showsTitles)
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? { size }
    final class Coordinator: NSObject {
        var parent: NativeProcessPicker
        init(_ parent: NativeProcessPicker) { self.parent = parent }
        @objc func changed(_ control: UISegmentedControl) {
            guard MobileStage.allCases.indices.contains(control.selectedSegmentIndex), parent.enabled else { return }
            parent.select(MobileStage.allCases[control.selectedSegmentIndex])
        }
    }
}

final class ProcessPickerToolbar: UIToolbar {
    let host: ProcessSegmentsHost
    private var dockSize: CGSize
    init(size: CGSize, vertical: Bool) {
        dockSize = size
        host = ProcessSegmentsHost(size: size, vertical: vertical)
        super.init(frame: CGRect(origin: .zero, size: size))
        let appearance = UIToolbarAppearance()
        appearance.configureWithTransparentBackground()
        standardAppearance = appearance; compactAppearance = appearance; scrollEdgeAppearance = appearance
        let item = UIBarButtonItem(customView: host)
        if #available(iOS 26.0, *) { item.hidesSharedBackground = true }
        setItems([item], animated: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { dockSize }
    override func sizeThatFits(_ size: CGSize) -> CGSize { dockSize }
    func configure(size: CGSize, vertical: Bool, stage: MobileStage, enabled: Bool) {
        dockSize = size
        host.configure(size: size, vertical: vertical, stage: stage, enabled: enabled)
        invalidateIntrinsicContentSize(); setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if let container = host.superview {
            host.frame = convert(CGRect(origin: .zero, size: dockSize), to: container)
        }
    }
}

final class ProcessSegmentsHost: UIView {
    let control = UISegmentedControl()
    private var dockSize: CGSize
    private var vertical: Bool
    private var labelKey = ""
    private var showsTitles = true
    init(size: CGSize, vertical: Bool) {
        dockSize = size; self.vertical = vertical
        super.init(frame: CGRect(origin: .zero, size: size))
        addSubview(control)
        for item in MobileStage.allCases { control.insertSegment(withTitle: item.rawValue, at: control.numberOfSegments, animated: false) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { dockSize }
    override func sizeThatFits(_ size: CGSize) -> CGSize { dockSize }
    func configure(size: CGSize, vertical: Bool, stage: MobileStage, enabled: Bool, showsTitles: Bool = true) {
        dockSize = size; self.vertical = vertical; self.showsTitles = showsTitles
        control.isEnabled = enabled
        for index in MobileStage.allCases.indices { control.setEnabled(enabled, forSegmentAt: index) }
        let index = MobileStage.allCases.firstIndex(of: stage) ?? 0
        // Do not reassign selection during native tracking: doing so can cancel
        // the system's moving glass lens before the valueChanged event settles.
        if control.selectedSegmentIndex != index { control.selectedSegmentIndex = index }
        let key = "\(stage.id)-\(vertical)-\(showsTitles)-\(traitCollection.userInterfaceStyle.rawValue)"
        if key != labelKey {
            labelKey = key
            for (i, item) in MobileStage.allCases.enumerated() {
                let image = label(item, selected: item == stage)
                image.accessibilityLabel = item.rawValue
                image.accessibilityIdentifier = "stage." + item.id
                control.setImage(image, forSegmentAt: i)
            }
        }
        invalidateIntrinsicContentSize(); setNeedsLayout()
    }
    private func label(_ item: MobileStage, selected: Bool) -> UIImage {
        let includesTitles = !vertical && showsTitles
        let canvas = CGSize(width: 36, height: includesTitles ? 44 : 36)
        let color = selected ? UIColor.systemOrange : UIColor.label.resolvedColor(with: traitCollection)
        let symbol = UIImage(systemName: item.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular))?
            .withTintColor(color, renderingMode: .alwaysOriginal)
        let upright = UIGraphicsImageRenderer(size: canvas).image { _ in
            if let symbol {
                let scale = min(20 / max(1, symbol.size.width), 20 / max(1, symbol.size.height))
                let box = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
                symbol.draw(in: CGRect(x: (canvas.width - box.width) / 2, y: (includesTitles ? 5 : (canvas.height - box.height) / 2), width: box.width, height: box.height))
            }
            if includesTitles {
                let text = item.rawValue as NSString
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9, weight: .medium), .foregroundColor: color]
                let width = text.size(withAttributes: attrs).width
                text.draw(at: CGPoint(x: (canvas.width - width) / 2, y: 29), withAttributes: attrs)
            }
        }
        guard vertical else { return upright.withRenderingMode(.alwaysOriginal) }
        // Rotate only the system control's axis; counter-rotate labels so icons
        // remain upright. No private tab-bar views or drawing APIs are used.
        return UIGraphicsImageRenderer(size: canvas).image { context in
            context.cgContext.translateBy(x: canvas.width / 2, y: canvas.height / 2)
            context.cgContext.rotate(by: -.pi / 2)
            upright.draw(in: CGRect(x: -canvas.width / 2, y: -canvas.height / 2, width: canvas.width, height: canvas.height))
        }.withRenderingMode(.alwaysOriginal)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let length = vertical ? bounds.height : bounds.width
        let thickness = vertical ? bounds.width : bounds.height
        control.transform = .identity
        control.bounds = CGRect(x: 0, y: 0, width: length, height: thickness)
        control.center = CGPoint(x: bounds.midX, y: bounds.midY)
        if vertical { control.transform = CGAffineTransform(rotationAngle: .pi / 2) }
        for index in MobileStage.allCases.indices { control.setWidth(length / CGFloat(MobileStage.allCases.count), forSegmentAt: index) }
    }
}

extension ToolbarContent {
    @ToolbarContentBuilder func compactHorizontalAxis() -> some ToolbarContent {
        if #available(iOS 27.1, *) { self.axisBehavior(.horizontalOnly) }
        else { self }
    }
}
