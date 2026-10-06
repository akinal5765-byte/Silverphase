//  SelectionModelTests.swift — the picked set, and the two gestures that move
//  frames in and out of it.
//
//  The set is what an export's batch is (`ExportPage.batch` is
//  `session.selectedFrames`), so every rule here is a rule about which
//  photographs get written. Four of them:
//
//  * a plain click picks exactly one frame, collapsing whatever set there was;
//  * ⌘-click toggles one frame, in both directions;
//  * the frame on the canvas cannot be removed from the set;
//  * the filmstrip and the Browse grid draw the same marks, from the one
//    function that decides them.
//
//  No decode is needed for any of this — the set is URLs — so the fixtures are
//  empty files with openable extensions, in a temporary folder. That also
//  keeps the suite away from `tests/Test_image/`, which the checkout's copy
//  shares with every other suite (`develop-writes-a-sidecar-copy-the-fixture`).

import AppKit
import XCTest

@MainActor
final class SelectionModelTests: XCTestCase {

    /// A folder of four frames, opened as a session. Opening a folder lands in
    /// Browse with nothing picked, which is the state the first rule starts
    /// from.
    private func openedSession(frameCount: Int = 4) throws -> (Session, [URL]) {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "spk-pick-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        for i in 0..<frameCount {
            // Named so `Library` sorts them, and with an extension it opens.
            try Data().write(to: dir.appending(path: String(format: "frame-%02d.png", i)))
        }
        let session = Session()
        session.open(urls: [dir])
        // The URLs come back **out of** the session rather than being the ones
        // written above: `temporaryDirectory` hands out `/var/…` and the
        // directory listing hands back `/private/var/…`, so the same file has
        // two spellings and `Set<URL>` is a string comparison. Taking them from
        // `frames` is what the app itself does — every click in the UI is on a
        // `Frame.id` — so this is the closer test, not the looser one.
        XCTAssertEqual(session.frames.count, frameCount,
                       "the fixture is not the session this test assumes")
        return (session, session.frames.map(\.id))
    }

    func testLateEXIFFromPreviousFrameCannotReplaceCurrentFrame() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "spk-exif-selection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = dir.appending(path: "frame-00.png")
        let second = dir.appending(path: "frame-01.png")
        try Data().write(to: first)
        try Data().write(to: second)

        let firstStarted = expectation(description: "first EXIF read started")
        let releaseFirst = DispatchSemaphore(value: 0)
        defer { releaseFirst.signal() }
        let session = Session(exifReader: { url in
            if url.lastPathComponent == first.lastPathComponent {
                firstStarted.fulfill()
                releaseFirst.wait()
                return EXIFReadout(iso: "ISO 100")
            }
            return EXIFReadout(iso: "ISO 800")
        })
        session.open(urls: [dir])
        await fulfillment(of: [firstStarted], timeout: 5)
        let urls = session.frames.map(\.id)
        XCTAssertEqual(urls.count, 2)
        session.select(urls[1])
        XCTAssertNil(session.exif, "the old frame's metadata remained visible after switching")
        for _ in 0..<100 where session.exif?.iso != "ISO 800" {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(session.exif?.iso, "ISO 800")
        releaseFirst.signal()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(session.exif?.iso, "ISO 800",
                       "a canceled EXIF read replaced the current frame's metadata")
    }

    /// A plain click: exactly one frame, and it opens.
    ///
    /// The collapse is the whole point — a click that merely *added* would
    /// leave the previous picks in the batch, and the export would write
    /// photographs the person had already moved on from.
    func testAPlainClickPicksOneFrameAndOpensIt() throws {
        let (session, urls) = try openedSession()
        session.click(urls[0])
        session.click(urls[1], command: true)
        session.click(urls[2], command: true)
        XCTAssertEqual(session.selectedFrames, [urls[0], urls[1], urls[2]])

        session.click(urls[3])
        XCTAssertEqual(session.selectedFrames, [urls[3]], "a plain click did not collapse the set")
        XCTAssertEqual(session.selection, urls[3], "a plain click did not open the frame")
    }

    func testModernBatchGridTracksMultiplePicksAndKeepsPhotoNavigator() throws {
        let (session, urls) = try openedSession()
        session.click(urls[0])
        session.selectInspectorStage(.film)
        XCTAssertTrue(session.modernFilmChooserActive)
        XCTAssertFalse(session.modernBatchGridActive)

        session.click(urls[1], command: true)
        XCTAssertEqual(session.selectedFrames, [urls[0], urls[1]])
        XCTAssertTrue(session.modernBatchGridActive)
        XCTAssertFalse(session.modernFilmChooserActive,
                       "The photo navigator must remain available for batch selection")

        session.open(urls[1])
        XCTAssertEqual(session.selectedFrames, [urls[0], urls[1]])
        XCTAssertTrue(session.modernBatchGridActive)
        session.click(urls[1])
        XCTAssertFalse(session.modernBatchGridActive)
        XCTAssertTrue(session.modernFilmChooserActive)

        // A plain click is a **pick**: it replaces the batch with the frame
        // it named. ⌘-click then grows it again, and the contact sheet
        // follows the batch rather than any mode.
        XCTAssertEqual(session.selectedFrames, [urls[1]])
        session.click(urls[0], command: true)
        XCTAssertEqual(session.selectedFrames, [urls[0], urls[1]],
                       "⌘-click toggles membership without moving the canvas")
        XCTAssertTrue(session.modernBatchGridActive)
    }

    /// The export-page gesture opens a picked frame without changing the batch.
    func testOpeningAnExportCellMovesSelectionAndLeavesPickedUnchanged() throws {
        let (session, urls) = try openedSession()
        session.click(urls[0])
        session.click(urls[1], command: true)
        let picked = session.selectedFrames

        session.open(urls[1])
        XCTAssertEqual(session.selection, urls[1])
        XCTAssertEqual(session.selectedFrames, picked,
                       "opening an export cell changed the picked set")
    }

    /// The export-page gesture refuses a frame outside the batch (§2.3: the
    /// proof is of a frame in the batch, so the guard is the rule).
    func testOpeningAnUnpickedCellIsANoOp() throws {
        let (session, urls) = try openedSession()
        session.click(urls[0])
        session.click(urls[1], command: true)

        session.open(urls[3])
        XCTAssertEqual(session.selection, urls[0],
                       "opening an unpicked cell moved the canvas")
    }

    /// ⌘-click toggles, both directions, and never moves the canvas.
    func testCommandClickTogglesAndLeavesTheCanvasAlone() throws {
        let (session, urls) = try openedSession()
        session.click(urls[0])

        session.click(urls[2], command: true)
        XCTAssertEqual(session.selectedFrames, [urls[0], urls[2]])
        XCTAssertEqual(session.selection, urls[0],
                       "⌘-click moved the canvas — notes.md says the viewed image stays put")

        session.click(urls[2], command: true)
        XCTAssertEqual(session.selectedFrames, [urls[0]], "⌘-click did not remove")
        XCTAssertEqual(session.selection, urls[0])

        // And it toggles *the set*, not "everything after the open frame":
        // ⌘-clicking a frame that was never picked, twice, is a round trip.
        session.click(urls[3], command: true)
        session.click(urls[3], command: true)
        XCTAssertEqual(session.selectedFrames, [urls[0]])
    }

    func testShiftSelectsInclusiveRangeWithoutMovingViewedFrame() throws {
        let (session, urls) = try openedSession()
        session.click(urls[0])
        session.click(urls[3], shift: true)
        XCTAssertEqual(session.selectedFrames, urls)
        XCTAssertEqual(session.selection, urls[0])

        // The original anchor remains fixed: moving the range end narrows it.
        session.click(urls[2], shift: true)
        XCTAssertEqual(session.selectedFrames, Array(urls[0...2]))
        XCTAssertEqual(session.selection, urls[0])

        session.click(urls[2])
        session.click(urls[0], shift: true)
        XCTAssertEqual(session.selectedFrames, Array(urls[0...2]))
        XCTAssertEqual(session.selection, urls[2])
    }

    func testCommandShiftAddsRangeAndPlainClickResetsAnchor() throws {
        let (session, urls) = try openedSession()
        session.click(urls[0])
        session.click(urls[2], command: true)
        session.click(urls[3], command: true, shift: true)
        XCTAssertEqual(session.selectedFrames, [urls[0], urls[2], urls[3]])
        XCTAssertEqual(session.selection, urls[0])

        session.click(urls[1])
        session.click(urls[3], shift: true)
        XCTAssertEqual(session.selectedFrames, Array(urls[1...3]))
        XCTAssertEqual(session.selection, urls[1])
    }

    func testFilteredShiftRangeNeverIncludesHiddenFrames() throws {
        let (session, urls) = try openedSession(frameCount: 7)
        let visible = [urls[0], urls[2], urls[4], urls[6]]
        session.click(visible[0], rangeScope: visible)
        session.click(visible[3], shift: true, rangeScope: visible)
        XCTAssertEqual(session.selectedFrames, visible)
        XCTAssertEqual(session.selection, visible[0])
        session.click(visible[1], shift: true, rangeScope: visible)
        XCTAssertEqual(session.selectedFrames, Array(visible.prefix(2)))
        session.click(visible[3], rangeScope: visible)
        session.click(visible[0], shift: true, rangeScope: visible)
        XCTAssertEqual(session.selectedFrames, visible)
    }

    func testFilteredCommandShiftAddsOnlyVisibleRange() throws {
        let (session, urls) = try openedSession(frameCount: 7)
        let visible = [urls[0], urls[2], urls[4], urls[6]]
        session.click(urls[0])
        session.click(urls[2], command: true, rangeScope: visible)
        session.click(urls[6], command: true, shift: true, rangeScope: visible)
        XCTAssertEqual(session.selectedFrames, visible)
        XCTAssertEqual(session.selection, urls[0])
    }

    func testFilteredShiftDoesNotReviveHiddenAnchorOrViewedFrame() throws {
        let (session, urls) = try openedSession(frameCount: 7)
        session.click(urls[1])
        let visible = [urls[0], urls[2], urls[4], urls[6]]
        session.click(urls[6], shift: true, rangeScope: visible)
        XCTAssertEqual(session.selectedFrames, [urls[6]])
        XCTAssertEqual(session.selection, urls[6])
        session.click(urls[0], shift: true, rangeScope: visible)
        XCTAssertEqual(session.selectedFrames, visible)
    }

    func testSelectAllFramesUsesVisibleScopeAndPreservesVisibleCanvas() throws {
        let (session, urls) = try openedSession(frameCount: 7)
        let visible = [urls[0], urls[2], urls[4], urls[6]]
        session.click(urls[2])
        session.selectAllFrames(in: visible)
        XCTAssertEqual(session.selectedFrames, visible)
        XCTAssertEqual(session.selection, urls[2])
        session.selectAllFrames()
        XCTAssertEqual(session.selectedFrames, urls)
        XCTAssertEqual(session.selection, urls[2])
    }

    func testSelectAllFramesReplacesHiddenPicksAndOpensVisibleFrame() throws {
        let (session, urls) = try openedSession(frameCount: 7)
        session.click(urls[1])
        session.selectAllFrames(in: [urls[0], urls[2], urls[4]])
        XCTAssertEqual(session.selectedFrames, [urls[0], urls[2], urls[4]])
        XCTAssertEqual(session.selection, urls[0])
        session.click(urls[4], shift: true, rangeScope: [urls[0], urls[2], urls[4]])
        XCTAssertEqual(session.selectedFrames, [urls[0], urls[2], urls[4]])
    }

    func testNavigatorSelectAllShortcutLeavesTextAndSheetsAlone() throws {
        func event(_ modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                          timestamp: 0, windowNumber: 0, context: nil,
                                          characters: "a", charactersIgnoringModifiers: "a",
                                          isARepeat: false, keyCode: 0))
        }
        let cmdA = try event(.command)
        XCTAssertTrue(PhotoSelectAllShortcut.accepts(cmdA, firstResponder: nil, hasSheet: false, hasPhotos: true))
        XCTAssertFalse(PhotoSelectAllShortcut.accepts(cmdA, firstResponder: NSTextView(), hasSheet: false, hasPhotos: true))
        XCTAssertFalse(PhotoSelectAllShortcut.accepts(cmdA, firstResponder: NSTextField(), hasSheet: false, hasPhotos: true))
        XCTAssertFalse(PhotoSelectAllShortcut.accepts(cmdA, firstResponder: nil, hasSheet: true, hasPhotos: true))
        XCTAssertFalse(PhotoSelectAllShortcut.accepts(cmdA, firstResponder: nil, hasSheet: false, hasPhotos: false))
        XCTAssertFalse(PhotoSelectAllShortcut.accepts(try event([.command, .shift]), firstResponder: nil,
                                                     hasSheet: false, hasPhotos: true))
    }

    /// The open frame can never leave the set, however it is clicked.
    ///
    /// A batch that excludes the photograph on the canvas is a state with
    /// nothing to read off it: the export page proves the frame it is about to
    /// write, so the alternative is a proof of a picture the run will not
    /// produce. It is also one ⌘-click away, which is how a person loses a
    /// selection they did not mean to lose.
    func testTheOpenFrameCannotBePickedOff() throws {
        let (session, urls) = try openedSession()
        session.click(urls[1])
        session.click(urls[0], command: true)
        session.click(urls[2], command: true)
        XCTAssertEqual(session.selectedFrames, [urls[0], urls[1], urls[2]])

        session.click(urls[1], command: true)
        XCTAssertEqual(session.selectedFrames, [urls[0], urls[1], urls[2]],
                       "⌘-clicking the open frame removed it from the batch")
        XCTAssertEqual(session.selection, urls[1], "…and it moved the canvas doing it")

        // The way to drop it is to open another frame, which is a plain click
        // — and that collapses the set, so the frame it left is gone too. Both
        // are the same rule: the set is never short of the open frame.
        session.click(urls[2])
        XCTAssertEqual(session.selectedFrames, [urls[2]])
        XCTAssertTrue(session.selectedFrames.contains(try XCTUnwrap(session.selection)))
    }

    /// The set is dropped with the library, and with a frame that goes.
    ///
    /// `selectedFrames` maps over `frames`, so a url left behind is invisible
    /// — the batch would be short by one with nothing on screen to say which.
    func testTheSetFollowsTheLibrary() throws {
        let (session, urls) = try openedSession()
        session.click(urls[0])
        session.click(urls[3], command: true)
        XCTAssertEqual(session.selectedFrames, [urls[0], urls[3]])

        session.remove(urls[3])
        XCTAssertEqual(session.selectedFrames, [urls[0]],
                       "a removed frame is still in the batch")
        // …and the set itself, not only the batch it projects to. The two are
        // not the same assertion: `selectedFrames` maps over `frames` and
        // filters, so a url left behind in `picked` is *invisible* through it
        // — which is the whole reason the invariant is `picked ⊆ frames` and
        // not "whatever the batch comes back as".
        XCTAssertFalse(session.picked.contains(urls[3]),
                       "the set kept a frame that is no longer in the library")

        // A new folder is a new set: the old picks are not photographs of this
        // one, and there is no frame here they could still name.
        //
        // **A folder now lands on its first frame** (2026-09-23). It used to
        // land on nothing, which opened a batch onto an empty canvas and the
        // instruction to pick a frame; the user's note was that a folder
        // should open on frame one and show its negative. So the assertion is
        // two things at once: the first frame *is* chosen, and the previous
        // library's pick is gone — which the batch could not show, because
        // that frame is no longer in `frames`.
        let (other, otherURLs) = try openedSession(frameCount: 2)
        other.open(urls: [otherURLs[1]])
        XCTAssertEqual(other.selectedFrames, [otherURLs[1]])
        XCTAssertTrue(other.picked.contains(otherURLs[1]))
        other.open(urls: [urls[0].deletingLastPathComponent()])
        XCTAssertEqual(other.selectedFrames, [urls[0]],
                       "opening a folder did not land on its first frame")
        XCTAssertFalse(other.picked.contains(otherURLs[1]),
                       "the set kept a frame from the last library, which the batch "
                       + "hides because it is no longer in `frames`")
    }

    /// The two surfaces agree, and they agree **by construction**.
    ///
    /// Both ask `Session.framing(of:)`, spelled the same way, and neither
    /// compares `selection` itself. The last assertion is a source scan, which
    /// this suite does once and only here: what it protects is that there is
    /// *one* expression deciding a cell's mark, and that is not a thing a
    /// rendered strip can tell you — an offscreen render of two views that
    /// each decided correctly would look identical to one where they did not.
    func testBothSurfacesAskTheOneFunction() throws {
        let (session, urls) = try openedSession()
        session.click(urls[0])
        session.click(urls[2], command: true)

        // The marks, exhaustively: open, picked, neither.
        XCTAssertEqual(session.framing(of: urls[0]), .open)
        XCTAssertEqual(session.framing(of: urls[2]), .picked)
        XCTAssertEqual(session.framing(of: urls[1]), .none)

        // The open frame is the strongest mark; a picked frame is framed
        // more weakly, which is what makes the two readable apart on a
        // thumbnail that can be any colour.
        XCTAssertGreaterThan(FrameFraming.open.lineWidth, FrameFraming.picked.lineWidth)
        XCTAssertGreaterThan(FrameFraming.open.opacity, FrameFraming.picked.opacity)
        XCTAssertGreaterThan(FrameFraming.picked.opacity, FrameFraming.none.opacity)
        XCTAssertFalse(FrameFraming.none.isFramed)

        // One rule, and every call site spells it the same way. `BrowseView`
        // was the second site until the Browse grid was removed (2026-09-17);
        // the filmstrip is the only list of frames now, so this guards the
        // one that is left rather than pretending there are still two.
        for file in ["Panels/Filmstrip.swift"] {
            XCTAssertTrue(try source(file).contains("framing: session.framing(of: frame.id)"),
                          "\(file) does not ask Session how to mark a cell")
        }
    }

    // MARK: - helpers

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SpektrafilmTests
            .deletingLastPathComponent()   // Spektrafilm
            .appending(path: "Spektrafilm/\(relative)")
        return try String(contentsOf: root, encoding: .utf8)
    }
    func testPhotoMarksRoundTripWithoutWritingSourceOrRenderSettings() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let photo = root.appending(path: "photo.tif")
        let source = Data("original photo".utf8)
        try source.write(to: photo)
        let store = root.appending(path: "store")
        try FrameMarks(rating: 4, flag: .pick).save(for: photo, directory: store)
        XCTAssertEqual(FrameMarks.load(for: photo, directory: store), FrameMarks(rating: 4, flag: .pick))
        XCTAssertEqual(try Data(contentsOf: photo), source)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.appending(path: Sidecar.key(for: photo)).path))
        try FrameMarks(rating: 99, flag: .reject).save(for: photo, directory: store)
        XCTAssertEqual(FrameMarks.load(for: photo, directory: store), FrameMarks(rating: 5, flag: .reject))
        XCTAssertEqual(FrameMarks.load(for: root.appending(path: "other.tif"), directory: store), FrameMarks())
        try FrameMarks().save(for: photo, directory: store)
        XCTAssertEqual(FrameMarks.load(for: photo, directory: store), FrameMarks())
    }

    func testNavigatorEXIFSummaryPreservesSharedAndMixedFields() {
        let a = EXIFReadout(iso: "ISO 400", shutter: "1/250 s", aperture: "f/2.8")
        XCTAssertEqual(EXIFReadout.summary([a]), "f/2.8 · 1/250 s · ISO 400")
        XCTAssertEqual(EXIFReadout.summary([a, a]), EXIFReadout.summary([a]))
        let b = EXIFReadout(iso: "ISO 800", shutter: "1/250 s", aperture: nil)
        let mixed = EXIFReadout.summary([a, b])
        XCTAssertTrue(mixed.contains("1/250 s"))
        XCTAssertFalse(mixed.contains("ISO 400"))
        XCTAssertFalse(mixed.contains("f/2.8"))
        XCTAssertEqual(EXIFReadout.summary([nil]), "")
    }

    func testSharedPhotoMarksAndCombinedFilters() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let photo = root.appending(path: "rated.png")
        let library = PhotoMarkLibrary(directory: root.appending(path: "marks"))
        try library.set(FrameMarks(rating: 4, flag: .pick), for: photo)
        await library.preload([photo])
        XCTAssertEqual(library.marks(for: photo), FrameMarks(rating: 4, flag: .pick))
        let filter = PhotoMarkFilter(minimumRating: 3, flag: .pick)
        XCTAssertTrue(filter.includes(library.marks(for: photo)))
        XCTAssertFalse(filter.includes(FrameMarks(rating: 2, flag: .pick)))
        XCTAssertFalse(filter.includes(FrameMarks(rating: 5, flag: .reject)))
        XCTAssertTrue(PhotoMarkFilter(unratedOnly: true).includes(FrameMarks()))
        XCTAssertFalse(PhotoMarkFilter(unratedOnly: true).includes(library.marks(for: photo)))
        XCTAssertTrue(PhotoMarkFilter(flag: FrameMarks.Flag.none).includes(FrameMarks()))
        XCTAssertFalse(PhotoMarkFilter(flag: FrameMarks.Flag.none).includes(library.marks(for: photo)))
        try library.set(FrameMarks(rating: 1, flag: .pick), for: photo)
        XCTAssertFalse(filter.includes(library.marks(for: photo)))
        XCTAssertEqual(FrameMarks.load(for: photo, directory: root.appending(path: "marks")).rating, 1)
    }

    func testRatingShortcutAppliesToSelectedSetAndPreservesFlags() throws {
        let (session, urls) = try openedSession()
        session.click(urls[0])
        session.click(urls[2], command: true)
        try session.photoMarks.set(FrameMarks(flag: .pick), for: urls[0])
        let selection = session.selectedFrames
        session.rateFrame(5)
        XCTAssertEqual(session.photoMarks.marks(for: urls[0]), FrameMarks(rating: 5, flag: .pick))
        XCTAssertEqual(session.photoMarks.marks(for: urls[2]).rating, 5)
        XCTAssertEqual(session.photoMarks.marks(for: urls[1]).rating, 0)
        XCTAssertEqual(session.selectedFrames, selection)
        session.rateFrame(0)
        XCTAssertEqual(session.photoMarks.marks(for: urls[0]), FrameMarks(flag: .pick))
    }

    func testRatingKeysDoNotInterceptParameterEditingOrSheets() throws {
        func key(_ text: String, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 0, windowNumber: 0, context: nil, characters: text,
                charactersIgnoringModifiers: text, isARepeat: false, keyCode: 18))
        }
        for digit in 0...5 {
            XCTAssertEqual(CanvasNSView.photoRatingShortcut(try key("\(digit)"), firstResponder: nil, hasSheet: false), digit)
        }
        for digit in ["6", "9", "a", "12"] { XCTAssertNil(FrameMarks.ratingShortcut(digit)) }
        XCTAssertNil(CanvasNSView.photoRatingShortcut(try key("3"), firstResponder: NSTextView(), hasSheet: false))
        XCTAssertNil(CanvasNSView.photoRatingShortcut(try key("3"), firstResponder: NSTextField(), hasSheet: false))
        XCTAssertNil(CanvasNSView.photoRatingShortcut(try key("3"), firstResponder: nil, hasSheet: true))
        for modifier: NSEvent.ModifierFlags in [.command, .control, .option, .shift] {
            XCTAssertNil(CanvasNSView.photoRatingShortcut(try key("3", modifiers: modifier), firstResponder: nil, hasSheet: false))
        }
    }

}
