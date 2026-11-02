import SwiftUI
import UIKit

@MainActor final class MobileDeviceLayout: NSObject, UIApplicationDelegate {
    private static var hasHinge: Bool?
    static var orientations: UIInterfaceOrientationMask {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return .all }
        if #available(iOS 27.1, *), hasHinge == nil { return .all }
        return hasHinge == true ? .all : .portrait
    }
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientations
    }
    static func update(hasHinge: Bool, window: UIWindow) {
        guard Self.hasHinge != hasHinge else { return }
        Self.hasHinge = hasHinge
        window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        if let scene = window.windowScene { scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) }
    }
}

/// Observe the window across both library and editor; ordinary phones stay portrait.
struct MobileOrientationObserver: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { Probe() }
    func updateUIView(_ view: UIView, context: Context) {}
    private final class Probe: UIView {
        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            if #available(iOS 27.1, *) {
                addInteraction(UIHingeInteraction { [weak self] _, update in
                    let hasHinge = update.hinge != nil
                    DispatchQueue.main.async { [weak self] in
                        guard let window = self?.window else { return }
                        MobileDeviceLayout.update(hasHinge: hasHinge, window: window)
                    }
                })
            }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
}
