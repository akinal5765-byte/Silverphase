//  The real MTKView, constructed and drawn into.
//
//  These exist because of a defect the rest of the suite could not see: the
//  canvas was configured with `colorPixelFormat = .rgba16Unorm`, which is a
//  valid *texture* format and not a valid *drawable* format, so `CAMetalLayer`
//  raised `invalid pixel format 110` and the app died on launch. Every other
//  test passed, and the snapshot harness passed too, because snapshot mode
//  substitutes an offscreen render and never builds an `MTKView`.
//
//  So: build the view the app builds, put it in a window, and draw.

import MetalKit
import QuartzCore
import SwiftUI
import XCTest

@MainActor
final class CanvasViewTests: XCTestCase {

    func testBusyFilmScanReleasesTheBlankCanvasWithoutShowingStaleFilm() throws {
        let session = Session()
        let selected = URL(fileURLWithPath: "/tmp/film-scan-selected.tif")
        let previous = URL(fileURLWithPath: "/tmp/film-scan-previous.tif")
        let texture = try XCTUnwrap(session.renderer.store.makeWritable(width: 8, height: 8))
        session.selection = selected
        session.busy = true
        session.renderer.holdForNegative = true

        // A result for another frame must not disturb the current hold.
        session.finishFilmScan(texture, for: previous)
        XCTAssertTrue(session.renderer.holdForNegative)

        // The selected frame's result is obsolete while a newer render runs,
        // but its hold must still end so the print already in hand is visible.
        session.finishFilmScan(texture, for: selected)
        XCTAssertFalse(session.renderer.holdForNegative)
        XCTAssertNil(session.renderer.filmScan)
        XCTAssertFalse(session.negativePending)
    }

    func testNoPaperAndReduceMotionDoNotHoldANegative() throws {
        let session = Session()
        let selected = URL(fileURLWithPath: "/tmp/no-paper-ceremony.tif")
        session.selection = selected
        session.busy = false
        let texture = try XCTUnwrap(session.renderer.store.makeWritable(width: 8, height: 8))
        session.renderer.reduceMotion = { false }
        session.sidecar.params.scanFilm = true
        session.renderer.holdForNegative = true
        session.finishFilmScan(texture, for: selected)
        XCTAssertFalse(session.renderer.holdForNegative)
        XCTAssertNil(session.renderer.filmScan)
        XCTAssertFalse(session.negativePending)

        session.sidecar.params.scanFilm = false
        session.renderer.reduceMotion = { true }
        session.renderer.holdForNegative = true
        session.finishFilmScan(texture, for: selected)
        XCTAssertFalse(session.renderer.holdForNegative)
        XCTAssertFalse(session.negativePending)
    }

    func testParameterEditCancelsTheHeldFilm() throws {
        let session = Session()
        let selected = URL(fileURLWithPath: "/tmp/edit-ceremony.tif")
        session.selection = selected
        session.busy = false
        session.renderer.reduceMotion = { false }
        let texture = try XCTUnwrap(session.renderer.store.makeWritable(width: 8, height: 8))
        session.finishFilmScan(texture, for: selected)
        XCTAssertTrue(session.negativePending)
        var changed = session.params
        changed.scanFilm = true
        session.params = changed
        XCTAssertFalse(session.negativePending)
        XCTAssertNil(session.renderer.filmScan)
        XCTAssertFalse(session.renderer.holdForNegative)
    }

    /// The formats `CAMetalLayer` accepts. Anything else raises an ObjC
    /// exception on assignment, which is a crash, not an error.
    static let drawableFormats: Set<MTLPixelFormat> = [
        .bgra8Unorm, .bgra8Unorm_srgb, .rgba16Float, .rgb10a2Unorm, .bgr10a2Unorm,
        .bgra10_xr, .bgra10_xr_srgb, .bgr10_xr, .bgr10_xr_srgb,
    ]

    func testDrawableFormatIsOneCAMetalLayerAccepts() {
        XCTAssertTrue(Self.drawableFormats.contains(Renderer.drawableFormat),
                      "\(Renderer.drawableFormat) is not a drawable format; CAMetalLayer will throw")
        // The offscreen format is the other half of the split: 16-bit unorm so
        // `makeCGImage()` needs no conversion. It is deliberately NOT a
        // drawable format, so the two must differ.
        XCTAssertEqual(Renderer.offscreenFormat, .rgba16Unorm)
    }

    func testCanvasViewBuildsAndDrawsInAWindow() throws {
        let session = Session()
        let view = CanvasNSView.configured(host: session)
        let layer = try XCTUnwrap(view.layer as? CAMetalLayer)
        XCTAssertEqual(layer.pixelFormat, Renderer.drawableFormat)
        // The layer is tagged with **the space the texture is in**, which is the
        // working space — ProPhoto RGB. ColorSync converts for the display.
        //
        // It was Display P3, and the assertion read the same way either time:
        // tag what the pixels are. RFC-018 §2.4 had the canvas convert into P3
        // first; the user reversed that half ("all displayed image in the main
        // app page would be in ProPhoto RGB and macOS should be handling the
        // color space management"), so the tag moved and the conversion went
        // with it. A mismatch here is the quietest failure in the app — ProPhoto
        // values wearing a P3 tag is a washed-out canvas and no error anywhere.
        XCTAssertEqual(layer.colorspace?.name, ImageDecoder.workingSpace?.name,
                       "the layer must be tagged with the space the canvas holds")
        XCTAssertTrue(view.isFlipped, "mouse points must share the shader's top-left origin")

        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        view.layoutSubtreeIfNeeded()

        // Empty canvas: the ground only.
        session.renderer.draw(in: view)

        // With an image: exercises the drawable render pipeline, which is the
        // state whose pixel format must match the drawable's.
        let tex = try XCTUnwrap(session.renderer.store.makeWritable(width: 4, height: 2))
        session.renderer.setLive(tex)
        session.renderer.viewport.resize(viewport: view.bounds.size, image: CGSize(width: 4, height: 2))
        session.renderer.draw(in: view)
        XCTAssertEqual(view.colorPixelFormat, Renderer.drawableFormat)
    }

    /// A redraw request must produce a draw. This asserts the wiring —
    /// delegate installed, closure connected, view able to dispatch — and it
    /// caught a real defect: `configured(host:)` at one point installed no
    /// `MTKViewDelegate`, so nothing drew however the redraw was requested.
    ///
    /// **What it does not catch, stated so nobody trusts it too far.** The
    /// shipped bug was `needsDisplay = true` failing to fire the delegate in
    /// the running app. In this test process it fires — with the view bare in
    /// a window *and* hosted in `NSHostingView` — so this test passes against
    /// the broken code. Whatever AppKit is doing differently in the real app
    /// does not reproduce in-process. The guard that actually catches it is
    /// `Tools/capture-live.sh`, which photographs the real window through the
    /// window server.
    func testRedrawRequestReachesTheViewWhenHostedBySwiftUI() async throws {
        let session = Session()
        let hosting = NSHostingView(rootView: MetalCanvasView(host: session).frame(width: 400, height: 300))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()

        func canvas(in view: NSView) -> CanvasNSView? {
            (view as? CanvasNSView) ?? view.subviews.lazy.compactMap(canvas(in:)).first
        }
        let view = try XCTUnwrap(canvas(in: hosting), "the representable must produce a CanvasNSView")
        XCTAssertNotNil(view.delegate, "no delegate means no draw, however the redraw is requested")

        // Let the hosting view's own first draws happen, then confirm idle:
        // otherwise the measurement counts those and passes regardless.
        try await Task.sleep(for: .milliseconds(500))
        let settled = session.renderer.drawCount
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(session.renderer.drawCount, settled, "the view must be idle before the measurement")

        let tex = try XCTUnwrap(session.renderer.store.makeWritable(width: 4, height: 2))
        session.renderer.setLive(tex)          // fires needsDraw, exactly as a landed render does
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertGreaterThan(session.renderer.drawCount, settled,
                             "a redraw request must produce a draw, or the canvas stays blank")
    }

    /// The canvas is resized the way the interface actually resizes it: a
    /// stream of small changes, each one its own layout pass, which is what a
    /// panel animation and a window drag both are.
    ///
    /// What this pins is the thing that was *checked and found correct* when
    /// "the picture twitches when the panels move" was investigated — with a
    /// per-draw log across a 40-step resize, a 76-draw live drag and a
    /// frame-by-frame capture of a collapse animation. The three sizes agree
    /// at every step: the viewport the fit was computed against, the view's
    /// bounds, and the drawable the picture is actually drawn into. A drawable
    /// left behind by one layout pass is a picture drawn to the wrong
    /// rectangle — the visible failure everyone expects this bug to be — and
    /// this is the assertion that would catch it.
    ///
    /// **It passes on the code the twitch was reported against.** The defect
    /// that investigation found is in *when* frames are presented, not where
    /// the picture is (see the note in `scheduleDraw`), and no assertion in
    /// this process can see the difference: the canvas draws in a real window
    /// on a real display link and an offscreen test has neither. It earns its
    /// place as a guard on the arithmetic, not as a reproduction.
    func testViewportBoundsAndDrawableAgreeAtEveryResizeStep() throws {
        let session = Session()
        let view = CanvasNSView.configured(host: session)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1448, height: 878),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.frame = CGRect(x: 0, y: 0, width: 1448, height: 878)
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        view.layoutSubtreeIfNeeded()

        // A square frame: the fit is height-limited, so the scale must not
        // change at all as the canvas widens — the picture only re-centres.
        let side: CGFloat = 2084
        let tex = try XCTUnwrap(session.renderer.store.makeWritable(width: Int(side), height: Int(side)))
        session.renderer.viewport.backingScale = 2
        session.renderer.viewport.resize(viewport: view.bounds.size, image: CGSize(width: side, height: side))
        session.renderer.setLive(tex, logical: CGSize(width: side, height: side))

        var widths: [CGFloat] = []
        for step in 0...40 {
            let w = 1448 - CGFloat(step) * 10          // the collapse, in 10 pt steps
            widths.append(w)
            view.frame = CGRect(x: 0, y: 0, width: w, height: 878)
            view.layoutSubtreeIfNeeded()

            let vp = session.renderer.viewport
            let bs = view.window?.backingScaleFactor ?? 2
            let what = "at width \(w)"
            XCTAssertEqual(vp.viewport.width, w, accuracy: 0.5, "the viewport is not the canvas \(what)")
            XCTAssertEqual(view.drawableSize.width, w * bs, accuracy: 1.0,
                           "the drawable is a layout pass behind the canvas \(what)")
            // …and the picture is centred in whatever the canvas now is.
            let imageWidth = vp.image.width * vp.scale
            XCTAssertEqual(vp.offset.x, (vp.viewport.width - imageWidth) / 2, accuracy: 0.01,
                           "the picture is not centred \(what)")
            XCTAssertEqual(vp.scale, 878 / side, accuracy: 1e-9,
                           "a height-limited fit must not rescale when the canvas only widens \(what)")
        }
        // A resize that never happened would pass every assertion above.
        XCTAssertEqual(widths.first! - widths.last!, 400, accuracy: 0.001)
    }

    /// Floating strips are controlled by the toolbar; no edge hover tabs
    /// should create invisible hit regions over the photo.
    func testModernEditorHasNoLegacyHoverBands() {
        let session = Session()
        let host = NSHostingView(rootView: EditorWindow(session: session))
        host.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        host.layoutSubtreeIfNeeded()
        func bands(in view: NSView) -> [HoverBand.Band] {
            (view as? HoverBand.Band).map { [$0] } ?? view.subviews.flatMap(bands(in:))
        }
        XCTAssertTrue(bands(in: host).isEmpty)
    }

    /// The drawable must **cover** the layer it is drawn into.
    ///
    /// `MTKView.autoResizeDrawable` rounds the drawable down from the bounds
    /// while a `CAMetalLayer`'s own bounds are the bounds in pixels, unrounded
    /// — so at any fractional size the drawable is up to a pixel short, and on
    /// an opaque layer that sliver is black, on the **right and bottom**, which
    /// is the side a rounded-down number leaves a gap on. Measured live over
    /// one panel animation: 14 of 28 draws were short, the worst by 0.42 px
    /// (bounds 1762.2101 pt, drawable 3524 px where 3524.42 px of layer were
    /// there). This is the user's "very small black edge on the bottom and
    /// right side of the canvas".
    ///
    /// A *fractional* size is the whole point of the test: at integral points
    /// there is nothing to round, which is why the defect only showed up on a
    /// window someone had dragged to an arbitrary size.
    func testTheDrawableCoversTheViewAtFractionalSizes() throws {
        let session = Session()
        let view = CanvasNSView.configured(host: session)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        for width in [999.0, 1000.37, 1276.21, 1438.63] {
            for height in [701.0, 888.42, 894.71] {
                view.frame = CGRect(x: 0, y: 0, width: width, height: height)
                view.layoutSubtreeIfNeeded()
                let bs = view.window?.backingScaleFactor ?? 2
                let wantW = width * bs, wantH = height * bs
                XCTAssertGreaterThanOrEqual(view.drawableSize.width, wantW - 1e-9,
                                            "drawable \(view.drawableSize.width) px is short of \(wantW) at \(width)×\(height)")
                XCTAssertGreaterThanOrEqual(view.drawableSize.height, wantH - 1e-9,
                                            "drawable \(view.drawableSize.height) px is short of \(wantH) at \(width)×\(height)")
                // …and not absurdly over: one pixel of slack, not a whole point.
                XCTAssertLessThan(view.drawableSize.width, wantW + bs,
                                  "the drawable is more than a pixel wider than the layer")
                XCTAssertLessThan(view.drawableSize.height, wantH + bs,
                                  "the drawable is more than a pixel taller than the layer")
            }
        }
    }

    /// The inspector floats over a window-sized canvas. Fit changes with its
    /// occlusion, while Metal's surface must retain the same dimensions.
    func testInspectorCollapseUpdatesFitWithoutResizingMetalCanvas() async throws {
        let session = Session()
        session.rightCollapsed = false
        session.showExport = false
        session.renderer.setLive(session.renderer.store.makeWritable(width: 600, height: 400))
        let host = NSHostingView(rootView: EditorWindow(session: session))
        host.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        host.layoutSubtreeIfNeeded()
        func findCanvas(in view: NSView) -> CanvasNSView? {
            (view as? CanvasNSView) ?? view.subviews.lazy.compactMap { findCanvas(in: $0) }.first
        }
        let canvas = try XCTUnwrap(findCanvas(in: host))
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let surface = canvas.bounds.size
        let opened = session.renderer.viewport
        XCTAssertGreaterThan(opened.obscuredRight, 0)
        session.renderer.viewport.fit()
        let fitted = session.renderer.viewport

        session.rightCollapsed = true
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let collapsed = session.renderer.viewport
        XCTAssertEqual(canvas.bounds.size, surface)
        XCTAssertEqual(collapsed.viewport, fitted.viewport)
        XCTAssertEqual(collapsed.obscuredRight, 0)
        XCTAssertNotEqual(collapsed.imageFrame, fitted.imageFrame)
        XCTAssertTrue(collapsed.isFit)

        session.rightCollapsed = false
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(canvas.bounds.size, surface)
        XCTAssertEqual(session.renderer.viewport.obscuredRight, opened.obscuredRight)
        XCTAssertEqual(session.renderer.viewport.imageFrame, fitted.imageFrame)
    }

    /// The zoom readout is computed from the viewport, and the viewport only
    /// means anything once there is an image in it. With none, the fit scale
    /// is against a 1×1 placeholder and the pill showed "Fit · 158,000 %".
    func testZoomReadoutFollowsTheImage() throws {
        let session = Session()
        session.viewportChanged()
        XCTAssertEqual(session.zoomPercent, 0, "no image, no zoom to report")

        let tex = try XCTUnwrap(session.renderer.store.makeWritable(width: 1000, height: 500))
        session.renderer.viewport.backingScale = 2
        session.renderer.viewport.resize(viewport: CGSize(width: 500, height: 500))
        session.renderer.setLive(tex)     // fits, and must refresh the readout itself
        XCTAssertEqual(session.zoomPercent, 100, "a 1000 pt image fitted to 500 pt at 2× is 100 %")
        XCTAssertTrue(session.isFit)
    }

    // MARK: the click that prints the negative

    /// **A click on the picture prints the negative; a drag does not.**
    ///
    /// The user asked for the whole preview to be a target for the one action
    /// the app has while a frame is still its film ("防呆"), and what can
    /// silently break it is the difference between a click and a drag: a pan that
    /// printed the negative would make the canvas unusable for the one moment the
    /// ceremony is up. Both are driven through the real view.
    func testAMouseUpWithoutADragIsAClickAndWithOneIsNot() throws {
        let spy = try ClickSpy()
        let view = CanvasNSView.configured(host: spy)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        view.layoutSubtreeIfNeeded()

        func event(_ type: NSEvent.EventType, _ p: CGPoint) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil,
                               eventNumber: 0, clickCount: 1, pressure: 0)
        }
        func press(from: CGPoint, to: CGPoint) throws {
            view.mouseDown(with: try XCTUnwrap(event(.leftMouseDown, from)))
            view.mouseUp(with: try XCTUnwrap(event(.leftMouseUp, to)))
        }

        // A hand on a trackpad moves the pointer a little; that is still a click.
        try press(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 102, y: 101))
        XCTAssertEqual(spy.clicks, 1, "a click on the canvas never reached the host")

        try press(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 140, y: 130))
        XCTAssertEqual(spy.clicks, 1, "a pan printed the negative")
    }

    /// The other half of the same guarantee, and the one that keeps the gesture
    /// honest: at any other moment a click on the canvas is still just a click.
    func testAClickOnTheCanvasPrintsNothingWhenThereIsNoNegative() {
        let session = Session()
        XCTAssertFalse(session.canvasClicked(), "a click on an idle canvas printed something")
    }

    /// The host a click test needs: a real renderer — the view refuses a press
    /// without one — and nothing else, except a count of what it was asked.
    @MainActor
    private final class ClickSpy: CanvasHost {
        let renderer: Renderer
        var tool: CanvasTool = .select
        var pickerActive = false
        var geometry = Geometry.default
        var cropPivot = CGPoint(x: 0.5, y: 0.5)
        var sourceImageSize = CGSize(width: 100, height: 100)
        var maskHandles: [MaskHandle] = []
        private(set) var clicks = 0

        init() throws { renderer = try XCTUnwrap(Renderer()) }

        @discardableResult func canvasClicked() -> Bool { clicks += 1; return true }
        func viewportChanged() {}
        func picked(normalised: CGPoint) {}
        func geometryChanged(_ g: Geometry) {}
        func commitCrop() {}
        func cancelCrop() {}
        func straightenPreview(_ line: StraightenLine?) {}
        func maskHandleDragged(_ handle: MaskHandle, to normalised: CGPoint) {}
        func toggledOriginal(_ on: Bool) {}
        func contextMenu() -> NSMenu? { nil }
        func hovered(normalised: CGPoint?) {}
        func stepFrame(_ delta: Int) {}
    }
}
