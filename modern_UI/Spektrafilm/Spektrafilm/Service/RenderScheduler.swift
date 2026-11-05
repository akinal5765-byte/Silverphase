//  RenderScheduler.swift — turns a stream of parameter edits into the fewest
//  service calls that still land the latest value.
//
//  The transport is single-flight and a reprint costs ~200 ms, so the UI must
//  never queue one request per slider tick. The scheduler keeps two values —
//  what the service *has* (`sent`) and what the user *wants* (`wanted`) — and
//  a single loop that, whenever they differ, waits a short debounce, sends
//  one delta for the whole difference, and applies the result only if its
//  parameters are still wanted and no newer frame was opened. Shoot-layer
//  edits, which re-run the film side, get a longer debounce than print-layer
//  edits, which reprint from the cached negative.
//
//  The debounce is measured from the *last* edit, not from the start of the
//  loop's turn. A fixed sleep charged the full window again after every
//  render, including the one the user let go during: a shoot-layer drag
//  released mid-render waited out that render and then 220 ms more before
//  the frame they stopped on was even sent. Sleeping only the remainder is
//  never longer than the fixed sleep, is the same while the hand is still
//  moving (the last edit is always recent), and is zero once it has stopped.

import Foundation

@MainActor
final class RenderScheduler {
    typealias Render = @Sendable (Method, RenderRequest) async throws -> RenderOutcome
    private let render: Render
    /// Where the "a render was superseded" record goes (RFC-016 §3). Injected
    /// rather than reached for through `Log.shared`, so a test reads the log it
    /// configured.
    private let log: Log
    private(set) var sent = FilmParams.default
    private var wanted = FilmParams.default
    private var previewEdge: Int?
    private var interactionFloor = 800
    private var interactionEdge: Int?
    private var interacting = false
    private(set) var renderedPreviewEdge: Int?
    private var desiredPreviewEdge: Int? { interacting ? interactionEdge : previewEdge }

    // Size changes travel in the same serial request as edits, never in a
    // parallel setParams/reprint task. The final edit restores settled quality.
    func setInteraction(_ active: Bool, pixelLongEdge: Double, elapsedMs: Double) {
        interacting = active
        if active, let previewEdge {
            let fit = [1080, 1600, 1920, 2560, 3200, 3840].first { Double($0) >= pixelLongEdge } ?? 3840
            // A desktop viewport can contain several times the pixels of a
            // phone. Latency adaptation must never undersample its fit image.
            interactionFloor = min(previewEdge, fit)
            interactionEdge = interactionFloor
        }
        startLoop()
    }

    func setPreviewEdge(_ edge: Int) {
        previewEdge = edge
        interactionEdge = min(interactionEdge ?? edge, edge)
        startLoop()
    }

    private func startLoop() {
        guard sessionID != nil else { return }
        if loop == nil { loop = Task { await run() } }
    }

    nonisolated static func nextInteractionEdge(_ edge: Int, elapsedMs: Double, ceiling: Int) -> Int {
        if elapsedMs > 200 { return max(800, Int(Double(edge) * 0.8)) }
        if elapsedMs < 70 { return min(ceiling, Int(Double(edge) * 1.15)) }
        return edge
    }
    private var loop: Task<Void, Never>?
    private var generation = 0
    private var sessionID: String?
    /// When `request(_:)` last ran: the start of the debounce window.
    private var lastRequestAt = ContinuousClock.now
    /// The debounce windows. The same numbers the fixed sleep used, so a
    /// single click lands exactly as soon as it did.
    private let debounce: (print: Duration, shoot: Duration)
    var onResult: (@MainActor (RenderOutcome, Int) -> Void)?
    /// The error itself, not a string. It used to hand over `"\(error)"`,
    /// which meant the only place that could rewrite the engine's
    /// developer-facing text for a user was too late to know what the failure
    /// was (`EngineMessage`).
    var onError: (@MainActor (Error) -> Void)?
    var onBusy: (@MainActor (Bool) -> Void)?

    init(client: EngineClient, log: Log = .shared) {
        self.render = { method, request in try await client.render(method, request) }
        self.log = log
        self.debounce = RenderScheduler.defaultDebounce
    }

    /// A controlled render seam keeps scheduling tests independent of GPU time.
    /// `debounce` is here so a test can widen the window past timer jitter.
    init(log: Log = .shared,
         debounce: (print: Duration, shoot: Duration) = RenderScheduler.defaultDebounce,
         render: @escaping Render) {
        self.render = render
        self.log = log
        self.debounce = debounce
    }

    nonisolated static let defaultDebounce: (print: Duration, shoot: Duration) =
        (.milliseconds(40), .milliseconds(220))

    /// True while an edit has been requested but not yet accepted by the
    /// service. The detail renderer checks this before spending the transport
    /// on a 6–17 s full-resolution render: the transport is single-flight, so
    /// a detail render would sit in front of the user's next slider release.
    var pending: Bool { wanted != sent || desiredPreviewEdge != renderedPreviewEdge }

    /// A new service session: what it holds now, and which generation it is.
    func reset(sessionID: String, params: FilmParams, previewEdge: Int? = nil) -> Int {
        loop?.cancel(); loop = nil
        generation += 1
        onBusy?(false)
        self.sessionID = sessionID
        sent = params
        wanted = params
        self.previewEdge = previewEdge
        interactionEdge = previewEdge
        renderedPreviewEdge = previewEdge
        interacting = false
        return generation
    }

    func invalidate() {
        loop?.cancel(); loop = nil
        generation += 1
        onBusy?(false)
        sessionID = nil
    }

    func request(_ params: FilmParams) {
        wanted = params
        lastRequestAt = .now
        startLoop()
    }

    /// A render the engine ran and the user will never see: a newer generation
    /// or newer parameters arrived while it was rendering, so the result is
    /// dropped instead of shown.
    ///
    /// This is the only place that knows. `Session` never hears about the
    /// result, `EngineClient` cannot see the generations, and a record that
    /// silently never said "superseded" would be the guard-that-cannot-fire
    /// shape this repository keeps getting bitten by — so it carries the
    /// engine's own `ms` and pixel count, which exist only if the render
    /// really ran.
    private func noteSuperseded(_ outcome: RenderOutcome, issuedGeneration: Int,
                                layers: Set<ParamLayer>) {
        let r = outcome.response
        log.info(.render, "superseded", [
            .init("outcome", "superseded"),
            .init("kind", layers.contains(.shoot) ? "render" : "reprint"),
            .init("tier", r.tier),
            .init("ms", r.elapsedMs),
            .init("px", (r.width ?? 0) * (r.height ?? 0)),
            .init("reprint", r.reprint),
            .init("generation", issuedGeneration),
            .init("current_generation", generation),
        ])
    }

    private func run() async {
        let gen = generation
        // An older, uncancellable engine call can finish after reset has
        // installed a new loop. Only that loop may clear its own handle.
        defer { if gen == generation { loop = nil } }
        while !Task.isCancelled, gen == generation, let sid = sessionID {
            let (delta, layers) = wanted.delta(from: sent)
            if delta.isEmpty && desiredPreviewEdge == renderedPreviewEdge { return }
            let shoot = layers.contains(.shoot)
            let window = interacting ? min(debounce.print, .milliseconds(16)) : (shoot ? debounce.shoot : debounce.print)
            // Only what is left of the window since the last edit: a lone
            // edit waits exactly the window, as it always did, and an edit
            // that was made while the previous render ran is sent at once.
            let still = ContinuousClock.now - lastRequestAt
            if still < window { try? await Task.sleep(for: window - still) }
            if Task.isCancelled || gen != generation {
                // A render that was never issued: the edit it was for has been
                // superseded before the engine saw anything. Recorded at
                // `debug` and *without* numbers, which is what tells it apart
                // from the render below — that one ran, and its record says so.
                log.debug(.render, "superseded before it was sent", [
                    .init("outcome", "not_issued"),
                    .init("generation", gen), .init("current_generation", generation),
                    .init("layer", shoot ? "shoot" : "print"),
                    .init("params", delta.keys.sorted().joined(separator: ",")),
                ])
                return
            }
            // Re-read after the debounce: the user kept dragging.
            let target = wanted
            var (d2, l2) = target.delta(from: sent)
            let targetEdge = desiredPreviewEdge
            if targetEdge != renderedPreviewEdge, let targetEdge {
                d2["preview_long_edge"] = .double(Double(targetEdge))
            }
            if d2.isEmpty { continue }
            onBusy?(true)
            do {
                let trace = PerformanceTrace.begin("Interactive Render")
                defer { PerformanceTrace.end("Interactive Render", trace) }
                var req = RenderRequest(sessionID: sid, paramsDelta: d2)
                let r: RenderOutcome
                if l2.contains(.shoot) {
                    req.layer = "shoot"
                    r = try await render(.previewRender, req)
                } else {
                    r = try await render(.reprint, req)
                }
                if gen == generation {
                    sent = target
                    renderedPreviewEdge = targetEdge
                    let matchingSize = targetEdge == desiredPreviewEdge
                    if (target == wanted || interacting) && matchingSize {
                        onResult?(r, gen)
                    } else {
                        noteSuperseded(r, issuedGeneration: gen, layers: l2)
                    }
                    // Adapt only when another edit is waiting, so a stationary
                    // pointer cannot create an endless resize/render loop.
                    if interacting, target != wanted, let edge = targetEdge, let ceiling = previewEdge {
                        interactionEdge = max(interactionFloor, Self.nextInteractionEdge(edge, elapsedMs: r.response.elapsedMs, ceiling: ceiling))
                    }
                } else {
                    noteSuperseded(r, issuedGeneration: gen, layers: l2)
                }
            } catch {
                if gen == generation {
                    onError?(error)
                    // Do not spin on a failing delta: accept it as sent.
                    sent = target
                    renderedPreviewEdge = targetEdge
                }
            }
            if gen == generation { onBusy?(false) }
        }
    }
}
