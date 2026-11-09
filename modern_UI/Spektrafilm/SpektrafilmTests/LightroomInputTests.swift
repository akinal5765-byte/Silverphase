import XCTest

final class LightroomInputTests: XCTestCase {
    @MainActor
    func testSaveWaitsForDebouncedParameterChanges() {
        let session = Session()
        session.scheduler.reset(sessionID: "readiness-test", params: session.params)
        defer { session.scheduler.invalidate() }
        XCTAssertTrue(session.lightroomRenderSettled)
        var changed = session.params
        changed.exposureCompensationEV += 1
        session.scheduler.request(changed)
        XCTAssertFalse(session.busy, "The debounce has not issued a render yet")
        XCTAssertFalse(session.lightroomRenderSettled, "Save must reject the unsent edit")
    }

    @MainActor
    func testFinderOpenDoesNotReplaceActiveLightroomSelection() {
        let session = Session()
        let input = URL(fileURLWithPath: "/tmp/retained-lightroom-input.tif")
        session.lightroomInput = input
        session.lightroomDestination = URL(fileURLWithPath: "/tmp/lightroom-output.tif")
        session.selection = input
        session.open(urls: [URL(fileURLWithPath: "/tmp/finder-other-photo.jpg")])
        XCTAssertEqual(session.selection, input)
        XCTAssertEqual(session.lightroomInput, input)
        XCTAssertTrue(session.isLightroomEditing)
    }

    func testOnlyAdobeLightroomSendersEnterExternalEditing() {
        XCTAssertTrue(LightroomInput.isLightroom("com.adobe.LightroomClassicCC7"))
        XCTAssertFalse(LightroomInput.isLightroom("com.apple.finder"))
        XCTAssertFalse(LightroomInput.isLightroom(nil))
    }

    func testReopeningDoesNotReplaceInputWithDevelopedOutput() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Lightroom-Edit.tif")
        let original = Data([1, 2, 3])
        try original.write(to: source)
        let retained = try LightroomInput.retain(source)
        XCTAssertEqual(try Data(contentsOf: retained), original)
        try Data([4, 5, 6]).write(to: source)
        XCTAssertEqual(try LightroomInput.retain(source), retained)
        XCTAssertEqual(try Data(contentsOf: retained), original)
        XCTAssertEqual(try Data(contentsOf: source), Data([4, 5, 6]))
    }
}
