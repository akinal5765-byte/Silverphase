import AppKit
import SwiftUI

/// Convert vertical-only wheel input to the strip's sole scroll axis.
/// Native horizontal gestures remain with NSScrollView, including momentum.
@MainActor
enum HorizontalStripWheel {
    static func delta(x: CGFloat, y: CGFloat, precise: Bool, lineHeight: CGFloat) -> CGFloat? {
        guard abs(y) > abs(x) else { return nil }
        return y * (precise ? 1 : lineHeight)
    }

    static func scroll(_ scrollView: NSScrollView, delta: CGFloat) {
        guard let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        let minimum = document.frame.minX
        let maximum = max(minimum, document.frame.maxX - clip.bounds.width)
        let x = min(maximum, max(minimum, clip.bounds.minX - delta))
        clip.scroll(to: NSPoint(x: x, y: clip.bounds.minY))
        scrollView.reflectScrolledClipView(clip)
    }
}

/// Attach inside the scroll content so the probe resolves the actual enclosing
/// NSScrollView, rather than guessing a SwiftUI view hierarchy or a window.
struct HorizontalStripWheelBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> HorizontalStripWheelProbe { HorizontalStripWheelProbe() }
    func updateNSView(_ nsView: HorizontalStripWheelProbe, context: Context) {}
    static func dismantleNSView(_ nsView: HorizontalStripWheelProbe, coordinator: ()) { nsView.stopMonitoring() }
}

final class HorizontalStripWheelProbe: NSView {
    private var monitor: Any?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, !self.isHiddenOrHasHiddenAncestor,
                  let window = self.window, event.window === window,
                  let scrollView = self.enclosingScrollView,
                  scrollView.bounds.contains(scrollView.convert(event.locationInWindow, from: nil)),
                  event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                  let delta = HorizontalStripWheel.delta(x: event.scrollingDeltaX, y: event.scrollingDeltaY,
                      precise: event.hasPreciseScrollingDeltas, lineHeight: scrollView.verticalLineScroll)
            else { return event }
            HorizontalStripWheel.scroll(scrollView, delta: delta)
            // Consume at either edge too: a strip scroll must not pan the canvas.
            return nil
        }
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
}
