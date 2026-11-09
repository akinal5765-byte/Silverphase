import SwiftUI
import UIKit

/// The camera keeps one device-relative coordinate system even when its host
/// window rotates (including hosts that ignore supported-orientation masks).
/// Only camera content is compensated; menus and other app pages keep UIKit's
/// ordinary orientation behaviour.
struct MobileCameraCanvasGeometry: Equatable {
    let contentSize: CGSize
    let rotation: Double

    init(viewport: CGSize, interfaceQuarterTurn: Double) {
        let quarterTurn = interfaceQuarterTurn.isFinite ? (interfaceQuarterTurn / 90).rounded() * 90 : 0
        rotation = quarterTurn.remainder(dividingBy: 360)
        let swapsAxes = abs(rotation.remainder(dividingBy: 180)) == 90
        contentSize = swapsAxes ? CGSize(width: viewport.height, height: viewport.width) : viewport
    }
}

struct MobileCameraCanvas<Content: View>: View {
    let content: Content
    @State private var interfaceQuarterTurn = 0.0

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        GeometryReader { geometry in
            let layout = MobileCameraCanvasGeometry(viewport: geometry.size, interfaceQuarterTurn: interfaceQuarterTurn)
            content
                .frame(width: layout.contentSize.width, height: layout.contentSize.height)
                .rotationEffect(.degrees(layout.rotation))
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera.canvas")
#if DEBUG
        .accessibilityValue(ProcessInfo.processInfo.arguments.contains("--camera-layout-check")
                            ? String(Int(interfaceQuarterTurn)) : "")
#endif
        .background {
            CameraCanvasOrientationProbe { interfaceQuarterTurn = $0 }
                .allowsHitTesting(false)
        }
    }
}

private struct CameraCanvasOrientationProbe: UIViewRepresentable {
    let changed: (Double) -> Void
    func makeUIView(context: Context) -> Probe { Probe(changed: changed) }
    func updateUIView(_ view: Probe, context: Context) {
        view.changed = changed
        view.measure()
    }
    final class Probe: UIView {
        var changed: (Double) -> Void
        private var previous: Double?
        init(changed: @escaping (Double) -> Void) {
            self.changed = changed
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() { super.didMoveToWindow(); measure() }
        override func layoutSubviews() { super.layoutSubviews(); measure() }
        override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); measure() }
        func measure() {
            guard let scene = window?.windowScene else { return }
            let orientation: UIInterfaceOrientation
            if #available(iOS 26, *) { orientation = scene.effectiveGeometry.interfaceOrientation }
            else { orientation = scene.interfaceOrientation }
            let quarterTurn: Double
            switch orientation {
            case .landscapeLeft: quarterTurn = 90
            case .landscapeRight: quarterTurn = -90
            case .portraitUpsideDown: quarterTurn = 180
            default: quarterTurn = 0
            }
            guard previous != quarterTurn else { return }
            previous = quarterTurn
            DispatchQueue.main.async { [weak self] in self?.changed(quarterTurn) }
        }
    }
}
