import SwiftUI
import UIKit

struct LibraryCellFrames: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

/// Horizontal motion starts range selection; ordinary vertical motion scrolls.
/// Once started, the same stroke can cross rows and scroll at either edge.
struct LibrarySelectionGesture: UIViewRepresentable {
    var enabled: Bool
    var ids: [UUID]
    var frames: [UUID: CGRect]
    var selection: Set<UUID>
    var commit: (Set<UUID>) -> Void

    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) { view.configuration = self; view.attach() }
    static func dismantleUIView(_ view: Probe, coordinator: ()) { view.detach() }

    final class Probe: UIView, UIGestureRecognizerDelegate {
        var configuration: LibrarySelectionGesture?
        private weak var scroll: UIScrollView?
        private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(moved))
        private var displayLink: CADisplayLink?
        private var baseline: Set<UUID> = []
        private var anchor: Int?
        private var adding = true
        private var fingerInWindow = CGPoint.zero
        private var orderedIDs: [UUID] = []
        override init(frame: CGRect) { super.init(frame: frame); isUserInteractionEnabled = false }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didMoveToWindow() { super.didMoveToWindow(); attach() }
        override func didMoveToSuperview() { super.didMoveToSuperview(); attach() }
        func attach() {
            var parent = superview
            while let view = parent, !(view is UIScrollView) { parent = view.superview }
            guard let found = parent as? UIScrollView else { return }
            if scroll !== found {
                detach(); scroll = found; pan.delegate = self; pan.cancelsTouchesInView = true
                found.addGestureRecognizer(pan)
                found.panGestureRecognizer.require(toFail: pan)
            }
            pan.isEnabled = configuration?.enabled == true
            if !pan.isEnabled { finish() }
        }
        func detach() { finish(); scroll?.removeGestureRecognizer(pan); scroll = nil }
        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let configuration, configuration.enabled, let scroll else { return false }
            let velocity = pan.velocity(in: scroll)
            guard abs(velocity.x) > abs(velocity.y) else { return false }
            let start = pan.location(in: self) - pan.translation(in: self)
            return configuration.frames.values.contains { $0.contains(start) }
        }
        @objc private func moved() {
            guard let configuration, configuration.enabled else { finish(); return }
            fingerInWindow = pan.location(in: window)
            switch pan.state {
            case .began:
                let start = pan.location(in: self) - pan.translation(in: self)
                orderedIDs = configuration.ids
                guard let id = configuration.frames.first(where: { $0.value.contains(start) })?.key,
                      let index = orderedIDs.firstIndex(of: id) else { return }
                baseline = configuration.selection; anchor = index; adding = !baseline.contains(id)
                displayLink = CADisplayLink(target: self, selector: #selector(tick))
                displayLink?.add(to: .main, forMode: .common)
                apply(at: pan.location(in: self))
            case .changed: apply(at: pan.location(in: self))
            default: finish()
            }
        }
        private func apply(at point: CGPoint) {
            guard let configuration, let anchor, configuration.ids == orderedIDs else { finish(); return }
            // Gaps between cards still map to their nearest visible neighbour.
            guard let id = configuration.frames.min(by: { distance(point, $0.value) < distance(point, $1.value) })?.key,
                  let index = orderedIDs.firstIndex(of: id) else { return }
            let range = Set(orderedIDs[min(anchor, index)...max(anchor, index)])
            let result = adding ? baseline.union(range) : baseline.subtracting(range)
            if result != configuration.selection { configuration.commit(result) }
        }
        @objc private func tick(_ link: CADisplayLink) {
            guard let configuration, configuration.enabled, let scroll, anchor != nil else { finish(); return }
            let finger = scroll.convert(fingerInWindow, from: window)
            let top = scroll.bounds.minY + scroll.adjustedContentInset.top
            let bottom = scroll.bounds.maxY - scroll.adjustedContentInset.bottom
            let edge: CGFloat = 56
            let velocity: CGFloat = finger.y < top + edge ? -min(1, max(0, (top + edge - finger.y) / edge)) : finger.y > bottom - edge ? min(1, max(0, (finger.y - bottom + edge) / edge)) : 0
            let minimum = -scroll.adjustedContentInset.top
            let maximum = max(minimum, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            let next = min(maximum, max(minimum, scroll.contentOffset.y + velocity * 420 * CGFloat(link.targetTimestamp - link.timestamp)))
            if next != scroll.contentOffset.y {
                scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: next), animated: false)
                apply(at: convert(fingerInWindow, from: window))
            }
        }
        private func finish() { displayLink?.invalidate(); displayLink = nil; anchor = nil; baseline = []; orderedIDs = [] }
        private func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
            let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
            let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
            return dx * dx + dy * dy
        }
    }
}

private func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
