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
