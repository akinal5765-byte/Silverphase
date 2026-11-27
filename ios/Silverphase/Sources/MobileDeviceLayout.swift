import SwiftUI
import UIKit

@MainActor final class MobileDeviceLayout: NSObject, UIApplicationDelegate {
    private static var hasHinge: Bool?
    private static var cameraPresented = false
    private static var cameraFollowsInterface = false
    static var orientations: UIInterfaceOrientationMask {
        let detectsHinge: Bool
        if #available(iOS 27.1, *) { detectsHinge = true } else { detectsHinge = false }
        return supportedOrientations(isPhone: UIDevice.current.userInterfaceIdiom == .phone,
                                     detectsHinge: detectsHinge, hasHinge: hasHinge,
                                     cameraPresented: cameraPresented, cameraFollowsInterface: cameraFollowsInterface)
    }
    static func supportedOrientations(isPhone: Bool, detectsHinge: Bool, hasHinge: Bool?,
                                      cameraPresented: Bool, cameraFollowsInterface: Bool = false) -> UIInterfaceOrientationMask {
        if cameraPresented { return detectsHinge && cameraFollowsInterface ? .all : .portrait }
        guard isPhone else { return .all }
        if detectsHinge, hasHinge == nil { return .all }
        return hasHinge == true ? .all : .portrait
    }
#if DEBUG
    static var cameraPresentationForChecks: Bool { cameraPresented }
#endif
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientations
    }
    static func update(hasHinge: Bool, window: UIWindow) {
        guard Self.hasHinge != hasHinge else { return }
        Self.hasHinge = hasHinge
        refreshOrientations(in: window)
    }
    static func setCameraPresented(_ presented: Bool, window: UIWindow, followsInterface: Bool = false) {
        let followsInterface = presented && followsInterface
        guard cameraPresented != presented || cameraFollowsInterface != followsInterface else { return }
        cameraPresented = presented
        cameraFollowsInterface = followsInterface
        refreshOrientations(in: window)
    }
    private static func refreshOrientations(in window: UIWindow) {
        // The camera is a full-screen presentation. Invalidate it as well as
        // the library's root controller when the hinge changes.
        var controller = window.rootViewController
        while let current = controller {
            current.setNeedsUpdateOfSupportedInterfaceOrientations()
            controller = current.presentedViewController
        }
        // A native Duo camera already follows its current scene/display.
        // Do not issue a competing orientation request during screen handoff.
        if cameraPresented && cameraFollowsInterface { return }
        window.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: orientations))
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

/// Keep a portrait coordinate system only while the camera is visible.
/// MobileCameraCanvas also compensates hosts that ignore this preference.
/// Library/editor pages recover their original orientation policy on dismissal.
struct MobileCameraOrientationObserver: UIViewRepresentable {
    var followsInterface = false
    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.followsInterface = followsInterface
        return probe
    }
    func updateUIView(_ view: Probe, context: Context) {
        view.followsInterface = followsInterface
        view.applyOrientation()
    }
    static func dismantleUIView(_ view: Probe, coordinator: ()) { view.releaseOrientation() }

    final class Probe: UIView {
        private weak var cameraWindow: UIWindow?
        var followsInterface = false

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if cameraWindow !== window { releaseOrientation() }
            cameraWindow = window
            applyOrientation()
        }
        func applyOrientation() {
            guard let window else { return }
            MobileDeviceLayout.setCameraPresented(true, window: window, followsInterface: followsInterface)
        }
        func releaseOrientation() {
            guard let cameraWindow else { return }
            MobileDeviceLayout.setCameraPresented(false, window: cameraWindow)
        }
    }
}
