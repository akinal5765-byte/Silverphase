import XCTest

final class LightroomInputTests: XCTestCase {
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
