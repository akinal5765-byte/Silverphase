import XCTest

@MainActor
final class CopySettingsDialogTests: XCTestCase {
    override func setUp() {
        super.setUp()
        let key = Session.clipboardGroupsKey
        let previous = UserDefaults.standard.object(forKey: key)
        addTeardownBlock {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }

    func testRequestAndCancellationPreserveTheClipboardAndRememberedGroups() throws {
        let s = Session()
        s.selection = URL(fileURLWithPath: "/tmp/source.tif")
        s.clipboardGroups = [.camera]
        s.copySettings()
        let previous = s.clipboard
        s.requestCopySettings()
        XCTAssertNotNil(s.copySettingsRequest)
        XCTAssertEqual(s.clipboard, previous)
        s.copySettingsRequest = nil // sheet dismissal, including Escape
        XCTAssertEqual(s.clipboard, previous)
        XCTAssertEqual(s.clipboardGroups, [.camera])
    }

    func testConfirmationCopiesFrozenSourceAndOnlyConfirmedGroups() throws {
        let s = Session()
        s.selection = URL(fileURLWithPath: "/tmp/source.tif")
        s.sidecar.params.printBrightnessStops = 2
        s.clipboardGroups = [.camera]
        s.requestCopySettings()
        let request = try XCTUnwrap(s.copySettingsRequest)
        s.sidecar.params.printBrightnessStops = -1
        s.selection = URL(fileURLWithPath: "/tmp/other.tif")
        s.confirmCopySettings(requestID: request.id, groups: [.camera])
        XCTAssertEqual(s.clipboard?.sourceName, "source.tif")
        XCTAssertEqual(s.clipboard?.settings.params.printBrightnessStops, 2)
        XCTAssertEqual(s.clipboard?.groups, [.camera])
        XCTAssertEqual(s.clipboardGroups, [.camera])
        XCTAssertNil(s.copySettingsRequest)
    }

    func testEmptyRememberedSelectionCanReopenDialogAndEmptyConfirmationDoesNothing() throws {
        let s = Session()
        s.selection = URL(fileURLWithPath: "/tmp/source.tif")
        s.clipboardGroups = []
        XCTAssertTrue(s.canRequestCopySettings)
        s.requestCopySettings()
        let request = try XCTUnwrap(s.copySettingsRequest)
        s.confirmCopySettings(requestID: request.id, groups: [])
        XCTAssertNil(s.clipboard)
        XCTAssertNotNil(s.copySettingsRequest)
        s.confirmCopySettings(requestID: request.id, groups: [.film])
        XCTAssertEqual(s.clipboard?.groups, [.film])
    }

    func testFilmstripCopyFreezesOfflineSourceWithoutChangingCanvasOrPicks() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "spk-context-copy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let urls = ["A.tif", "B.tif", "C.tif"].map { directory.appending(path: $0) }
        addTeardownBlock {
            for url in urls { Sidecar.remove(for: url) }
            try? FileManager.default.removeItem(at: directory)
        }
        for url in urls { try PortTestFrame.write(to: url) }

        var offline = Sidecar()
        offline.params.printBrightnessStops = 2
        try offline.save(for: urls[2])
        let session = Session()
        session.open(urls: urls)
        XCTAssertEqual(session.selection, urls[0])
        session.sidecar.params.printBrightnessStops = -1
        session.click(urls[1], command: true)
        let targets = session.pasteTargets
        XCTAssertEqual(Set(targets), Set(urls.prefix(2)))

        // Only the row's explicit action may name a source during a batch.
        XCTAssertFalse(session.canRequestCopySettings)
        XCTAssertTrue(session.canRequestContextCopy(from: urls[2]))
        session.requestCopySettings(from: urls[2])
        let request = try XCTUnwrap(session.copySettingsRequest)
        XCTAssertEqual(session.selection, urls[0])
        XCTAssertEqual(session.pasteTargets, targets)
        XCTAssertEqual(session.sidecar.params.printBrightnessStops, -1)

        offline.params.printBrightnessStops = 1
        try offline.save(for: urls[2])
        session.confirmCopySettings(requestID: request.id, groups: [.print])
        XCTAssertEqual(session.clipboard?.sourceName, "C.tif")
        XCTAssertEqual(session.clipboard?.settings.params.printBrightnessStops, 2)
        XCTAssertEqual(session.pasteTargets, targets)
    }

    func testFilmstripCopyDoesNotFallBackForAFrameOutsideTheLibrary() {
        let session = Session()
        session.selection = URL(fileURLWithPath: "/tmp/on-canvas.tif")
        let absent = URL(fileURLWithPath: "/tmp/removed.tif")
        XCTAssertFalse(session.canRequestContextCopy(from: absent))
        session.requestCopySettings(from: absent)
        XCTAssertNil(session.copySettingsRequest)
    }

    func testBatchExportAndStaleConfirmationCannotReplaceClipboard() throws {
        let s = Session()
        s.selection = URL(fileURLWithPath: "/tmp/source.tif")
        s.clipboardGroups = [.camera]
        s.copySettings()
        let previous = s.clipboard
        s.requestCopySettings()
        let request = try XCTUnwrap(s.copySettingsRequest)
        s.confirmCopySettings(requestID: UUID(), groups: [.film])
        XCTAssertEqual(s.clipboard, previous)
        s.batchExporting = true
        XCTAssertFalse(s.canRequestCopySettings)
        s.confirmCopySettings(requestID: request.id, groups: [.film])
        XCTAssertEqual(s.clipboard, previous)
        s.copySettingsRequest = nil
        s.requestCopySettings()
        XCTAssertNil(s.copySettingsRequest)
        s.batchExporting = false
    }
}
