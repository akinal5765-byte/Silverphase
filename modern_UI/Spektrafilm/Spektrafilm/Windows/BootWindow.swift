//  BootWindow.swift — the small window the app shows while the engine starts.
//
//  Photoshop and Capture One both do this, and the reason is not decoration:
//  a photo application has a fixed, unavoidable amount of setup — here the
//  engine's warm-up, the Metal device, and the pipeline for one film/paper
//  pair — and doing it silently behind an empty editor makes a working app
//  look broken.
//
//  **The rule, amended 2026-09-23.** This window covers work the app has to do
//  anyway, and it used to say "nothing in it sleeps and nothing is padded". The
//  user asked for the opposite of that, in as many words: "现在加载太快了，宁可
//  人为的让他慢一点，能塑造品牌感，并且强调色也使用 Apple 橙，像 Adobe 那类
//  专业软件一样". So the window now has a **minimum** time on screen
//  (`BootWindowController.minimumOnScreen`), which is padding by definition and
//  is deliberate: a splash that appears for four frames reads as a flicker and
//  not as a product. It is a *floor*, never a delay added to real work — the
//  handover still happens as soon as the engine is up and the floor is paid,
//  and a failure hands over immediately.
//
//  It also reports which engine started, which is the one thing an earlier
//  session most needed and did not have (HANDOFF-GPU-WIRING §0): a whole day's
//  work landed against a backend nobody was running, and the only symptom was
//  that things felt slow.

import AppKit
import SwiftUI

struct BootWindow: View {
    @Bindable var session: Session
    /// Set by `--boot-phase` so a capture can show the middle of the boot.
    /// `nil` in the app, which reads the session.
    var phase: Session.BootPhase? = nil

    /// How far the bar is, from what the session is actually doing. Three
    /// states, three positions — a determinate bar that matches the phases is
    /// worth more than a spinner, because it is the same information the phase
    /// line carries and it reads from across a room.
    private var progress: Double {
        switch phase ?? session.bootPhase {
        case .starting: 0.28
        case .warming: 0.68
        case .ready: 1.0
        case .failed: 0.0
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // The wordmark, and under it the line that says what it is for.
            // **No icon.** It was the first thing drawn here and the user cut
            // it: "不用出现图标了…加上图标感觉整个版面太大了". The Dock has
            // already shown the icon — this window's job is the name, the bar
            // and the engine, and the icon made all three smaller to fit.
            // The tagline is tracked out rather than set in a second size: a
            // 9.5 pt line at 2.6 pt of tracking reads as a label under a name,
            // where 12 pt text reads as a second sentence competing with it.
            Text("Silverphase")
                .font(Theme.Font.of(28, .semibold))
                .foregroundStyle(Theme.text)
                .padding(.top, 20)
            // Tracked out **in English only**. Letterspacing a Latin wordmark is
            // a house style; the same tracking on Chinese characters is a gap
            // between every syllable, which reads as a spacing bug rather than
            // as a label (the localization spec's own rule: an English
            // typographic idiom is not a translation).
            let english = Localization.shared.resolved == .english
            Text(english ? L(.bootTagline).uppercased() : L(.bootTagline))
                .font(Theme.Font.of(english ? 9.5 : 11, .medium))
                .tracking(english ? 2.6 : 0.6)
                .foregroundStyle(Theme.dim)
                .padding(.top, 7)

            Spacer(minLength: 0)

            ProgressBar(value: progress)
                .frame(height: 4)
                .padding(.horizontal, 34)

            HStack(spacing: 7) {
                if case .failed = phase ?? session.bootPhase {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10)).foregroundStyle(Theme.accent)
                }
                // **The engine badge is gone** (the user: "拿掉右侧文字", and
                // the line on the left made longer to carry the row alone).
                // `NATIVE-METAL` is developer jargon for a value that Settings
                // ▸ This session and every log record already report, and the
                // splash is the brand moment, not the diagnostics panel. It was
                // worth having while an earlier session could run the wrong
                // core without noticing; there is one core now.
                Text(message)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 34)
            .padding(.top, 12)
            .padding(.bottom, 22)
        }
        .frame(width: BootWindowController.card.width, height: BootWindowController.card.height)
        .background {
            // **The card, drawn by us.** The window is borderless now (see the
            // controller), so this rounded rect *is* the window's shape, and it
            // wears the L1 material like every other card: fill, one inner
            // stroke read top-to-bottom, and nothing else. The shadow lives in
            // the transparent margin the window keeps around it.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.cardFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.controlStroke, lineWidth: 1)
                }
                .overlay(alignment: .top) {
                    LinearGradient(colors: [Color.white.opacity(0.05), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .shadow(color: .black.opacity(0.55), radius: 18, y: 8)
        }
        .frame(width: BootWindowController.size.width, height: BootWindowController.size.height)
        .preferredColorScheme(.dark)
    }

    /// A failure is its own sentence and has no translation — it is a
    /// capabilities refusal, and the reader of it is the person who has to act
    /// on it.
    private var message: String {
        if case .failed(let why) = phase ?? session.bootPhase { return why }
        return L((phase ?? session.bootPhase).key)
    }
}

/// The bar itself: a recessed track with a **flat** Apple-orange fill.
///
/// Flat, not a gradient: the whole interface's accent is flat now (the user's
/// "橙色不需要渐变了"), and a bar is the one control where a gradient is most
/// tempting and least useful — it makes a quarter-full bar look like it has
/// shading rather than progress.
private struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.well)
                    .overlay {
                        Capsule().strokeBorder(
                            LinearGradient(colors: [Color.black.opacity(0.45), Color.white.opacity(0.06)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1)
                    }
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
                    .shadow(color: Theme.accent.opacity(0.35), radius: 4)
            }
        }
        .animation(.easeInOut(duration: 0.55), value: value)
        .accessibilityElement()
        .accessibilityLabel(L(.bootStarting))
        .accessibilityValue("\(Int(value * 100)) %")
    }
}

/// Owns the boot window and the handover to the editor.
///
/// The editor window is **ordered out** rather than never created: SwiftUI
/// builds its `Window` scene at launch and there is no supported way to defer
/// that. Hiding it and bringing it forward when boot completes gives the
/// Photoshop shape — small window, then the real one — without fighting the
/// scene system.
@MainActor
final class BootWindowController {
    /// The **card**, which is what the user sees.
    static let card = CGSize(width: 360, height: 194)
    /// The **window**, which is the card plus a transparent margin for its
    /// shadow. A SwiftUI shadow is clipped by the window it is drawn in, so the
    /// window has to be bigger than the thing casting it.
    static let size = CGSize(width: card.width + 28, height: card.height + 28)

    /// The floor, and the whole of the deliberate slowness: 2.6 s on screen
    /// however fast the engine was. Measured on this machine, a warm start
    /// finishes the session's warm-up in ~650 ms, so without a floor the window
    /// was up for two thirds of a second — long enough to be a flicker and too
    /// short to read the name, which is the opposite of what it is for.
    static let minimumOnScreen: Double = 2.6

    private var window: NSWindow?
    private var observer: Task<Void, Never>?

    /// The editor scene's window, or nil if SwiftUI has not made it yet.
    ///
    /// Identified by **not being the boot window**, which is the only
    /// discriminator that is actually reliable here. Measured at the
    /// handover: neither window carries an `identifier` (both print `nil`),
    /// both have a `contentView`, and neither is an `NSPanel` — the boot
    /// window is an `NSWindow` we made and the editor is SwiftUI's private
    /// `TUINSWindow`, and matching on that class name would be matching on an
    /// implementation detail. We hold the boot window's reference, so
    /// excluding it by identity is exact and cannot go stale.
    private func editorWindow() -> NSWindow? {
        NSApp.windows.first { $0 !== window && !($0 is NSPanel) && $0.contentView != nil }
    }

    /// Show it, hide the editor, and hand over when the session says it is up.
    func present(session: Session) {
        // An editor window that never appears is worse than a visible one, so
        // every path below has a `reveal()`.
        //
        // Nothing is cached here. This runs from
        // `applicationDidFinishLaunching`, and at that point SwiftUI has
        // created **no windows at all** — measured: `NSApp.windows` is empty,
        // so the old cache was always nil and the fallback in `reveal()` was
        // doing all the work by luck. The editor is looked up at `reveal()`
        // time instead, which is the moment it is wanted and by which it
        // exists.

        // **Borderless.** It was `.titled` with a transparent, hidden titlebar,
        // and that still leaves the system's titlebar strip drawn across the
        // top — the user's exact words: "顶部那一条黑条也很奇怪，这里并没有窗口".
        // There is no title to show and no traffic lights to offer on a window
        // that lives for two seconds, so the window is just a shape now and the
        // card in the view is what it looks like.
        let w = NSWindow(contentRect: CGRect(origin: .zero, size: BootWindowController.size),
                         styleMask: [.borderless],
                         backing: .buffered, defer: false)
        w.isMovableByWindowBackground = true
        w.appearance = NSAppearance(named: .darkAqua)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false      // the card draws its own, inside the margin
        w.contentView = NSHostingView(rootView: BootWindow(session: session))
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
        let shownAt = Date()

        // **The editor goes away until the handover.** The header has always
        // claimed this ("Show it, hide the editor") and the code never did it:
        // the handover was fast enough that the editor window — which SwiftUI
        // makes at launch and orders in on its own — was never *seen* behind the
        // splash. Giving the splash a floor exposed it: two seconds of the real
        // window sitting behind a 400 pt card is not a splash. Hidden here and
        // again每 tick, because the scene can order it in at any moment during
        // the wait.
        editorWindow()?.orderOut(nil)

        observer = Task { @MainActor [weak self] in
            // A hard ceiling, because a boot window that never goes away is
            // the worst outcome of the whole feature — worse than no boot
            // window at all. If warm-up is still running at the deadline the
            // editor comes up anyway and the work continues behind it; the
            // gate in `openInService` still holds, so nothing renders early.
            let deadline = Date().addingTimeInterval(20)
            while Date() < deadline {
                if case .failed = session.bootPhase { break }   // never hold a failure
                if session.booted || session.serviceBlocked != nil { break }
                self?.editorWindow()?.orderOut(nil)
                try? await Task.sleep(for: .milliseconds(60))
            }
            // The floor, unless something went wrong: a failure is information
            // the user needs now, and holding it for the brand would be holding
            // the explanation of a broken app behind a logo.
            if session.serviceBlocked == nil, !session.bootPhase.isFailure {
                let remaining = BootWindowController.minimumOnScreen
                    - Date().timeIntervalSince(shownAt)
                if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            }
            self?.reveal()
        }
    }

    private func reveal() {
        observer = nil
        // Find the editor **before** letting go of the boot window, and order
        // the boot window out after. The old version nilled `window` first,
        // so its own fallback — "the first window with a content view" —
        // could and did pick the boot window it had just ordered out, and
        // `makeKeyAndOrderFront` brought it straight back. That is what an
        // app stuck on a boot screen with a warmed-up session looked like.
        let target = editorWindow()
        window?.orderOut(nil)
        window = nil
        guard let target else {
            // Nothing to hand over to. Say so rather than leaving a user
            // staring at a desktop wondering whether the app launched: this
            // is unreachable in the normal path, and the log record is how we
            // would find out it had become reachable again.
            Diagnostics.shared.log.error(.app, "the boot window had no editor window to hand over to", [
                .init("windows", NSApp.windows.count),
            ])
            return
        }
        target.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private extension Session.BootPhase {
    var isFailure: Bool { if case .failed = self { true } else { false } }
}
