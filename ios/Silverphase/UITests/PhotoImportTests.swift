import XCTest

final class PhotoImportTests: XCTestCase {
    @MainActor func testRulerDoubleTapResetsWithoutContextMenu() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--smoke-test"]
        // Can attach to the smoke fixture opened by devicectl when Xcode's
        // debugger launch channel is unavailable on the paired device.
        if app.state == .notRunning { app.launch() } else { app.activate() }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["editor.export"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 35), .completed)
        let ruler = app.descendants(matching: .any).matching(identifier: "ruler.曝光补偿 · EV").firstMatch
        for _ in 0..<5 { if ruler.isHittable { break }; app.otherElements["editor.parameters"].swipeUp() }
        XCTAssertTrue(ruler.isHittable)
        app.buttons["输入曝光补偿 · EV"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        let previous = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + "1")
        app.alerts.buttons["确定"].tap()
        if app.alerts.firstMatch.exists { app.alerts.buttons["确定"].tap() }
        XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 4))
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1.00"), object: ruler)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        ruler.doubleTap()
        let reset = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0.00"), object: ruler)
        XCTAssertEqual(XCTWaiter.wait(for: [reset], timeout: 5), .completed, "Physical double tap failed to restore the default")
        // A subsequent edit must still reset to the default, never undo the
        // reset back to the previous edited value.
        let start = ruler.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: -48, dy: 0)))
        let editedAgain = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", "0.00"), object: ruler)
        XCTAssertEqual(XCTWaiter.wait(for: [editedAgain], timeout: 3), .completed)
        ruler.doubleTap()
        let defaultAgain = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0.00"), object: ruler)
        XCTAssertEqual(XCTWaiter.wait(for: [defaultAgain], timeout: 5), .completed)
        ruler.press(forDuration: 0.8)
        XCTAssertFalse(app.buttons["重置曝光补偿 · EV"].exists)
        XCTAssertFalse(app.buttons["重置场景置位"].exists)
        app.terminate()
    }
    @MainActor func testHalationMenuRefreshesAfterMaximumAmount() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-ui-regression"]
        app.launch()
        let pending = app.staticTexts["轻点照片开始印相"]
        XCTAssertTrue(pending.waitForExistence(timeout: 45))
        let canvas = app.descendants(matching: .any).matching(identifier: "editor.canvas").firstMatch
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.4)).tap()
        XCTAssertTrue(pending.waitForNonExistence(timeout: 6))
        app.buttons["胶片"].tap()
        let amount = app.buttons["输入晕光强度"]
        for _ in 0..<4 { if amount.isHittable { break }; app.otherElements["editor.parameters"].swipeUp() }
        XCTAssertTrue(amount.isHittable)
        amount.tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        let previous = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + "4")
        app.alerts.buttons["确定"].tap()
        if app.alerts.firstMatch.exists { app.alerts.buttons["确定"].tap() }
        XCTAssertTrue(app.alerts.firstMatch.waitForNonExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["处理中…"].waitForNonExistence(timeout: 20))
        let before = canvas.value as? String ?? ""
        app.buttons["晕光"].tap()
        app.buttons["高"].tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", before), object: canvas)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 20), .completed, "Menu selection did not publish a new preview image")
        XCTAssertTrue(app.staticTexts["高"].exists)
        app.terminate()
    }
    @MainActor func testCanvasTapStageZoomAndComparison() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--interaction-ui-regression"]
        app.launch()
        let pending = app.staticTexts["轻点照片开始印相"]
        XCTAssertTrue(pending.waitForExistence(timeout: 45))
        let canvas = app.descendants(matching: .any).matching(identifier: "editor.canvas").firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.4)).tap()
        XCTAssertTrue(pending.waitForNonExistence(timeout: 6), "A physical canvas tap must start the development animation")
        XCTAssertTrue(app.staticTexts["显影中…"].waitForNonExistence(timeout: 6))
        let menu = app.buttons["editor.menu"]
        menu.tap()
        app.buttons["1:1 原始像素"].tap()
        let native = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value BEGINSWITH %@", "native;"), object: canvas)
        XCTAssertEqual(XCTWaiter.wait(for: [native], timeout: 5), .completed)
        XCTAssertTrue(app.staticTexts["原始像素"].waitForExistence(timeout: 45))
        let dragStart = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.4))
        dragStart.press(forDuration: 0.1, thenDragTo: dragStart.withOffset(CGVector(dx: 45, dy: 28)))
        let originalTransform = canvas.value as? String
        print("Stage controls: " + app.buttons.allElementsBoundByIndex.map { $0.identifier + ":" + $0.label }.joined(separator: " | "))
        for title in ["胶片", "显影", "印相", "扫描", "相机"] {
            app.buttons[title].tap()
            XCTAssertEqual(canvas.value as? String, originalTransform, "Stage changed the canvas transform: " + title)
        }
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.4)).press(forDuration: 0.7)
        XCTAssertEqual(canvas.value as? String, originalTransform)
        XCTAssertTrue(app.staticTexts["原始像素"].waitForExistence(timeout: 2), "Comparison discarded native detail")
        canvas.pinch(withScale: 1.2, velocity: 0.5)
        let manualTransform = canvas.value as? String
        XCTAssertTrue(manualTransform?.hasPrefix("manual;") == true)
        for title in ["胶片", "相机"] {
            app.buttons[title].tap()
            XCTAssertEqual(canvas.value as? String, manualTransform, "Stage changed the manually zoomed physical pixel scale")
        }
        app.terminate()
    }
    @MainActor func testCropHandlesAndRotationAreInteractive() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--smoke-test"]
        app.launch()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["editor.export"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 45), .completed)
        let tab = app.tabBars.firstMatch.buttons["构图"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5)); tab.tap()
        let canvas = app.descendants(matching: .any)["crop.canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        let original = canvas.value as? String
        let handle = app.descendants(matching: .any)["crop.handle.bottomRight"].firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 5)); XCTAssertTrue(handle.isHittable)
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: -35, dy: -30)))
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", original ?? ""), object: canvas)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        app.buttons["恢复完整画面"].tap()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", original ?? ""), object: canvas)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
        app.buttons["向右旋转"].tap()
        XCTAssertNotEqual(canvas.value as? String, original)
        app.buttons["水平翻转"].tap()
        XCTAssertTrue((canvas.value as? String)?.hasSuffix(";1;1;0") == true)
        app.terminate()
    }
    @MainActor func testImportedPhotoActivatesNativeStagesAndTracksSelection() throws {
        let app = XCUIApplication()
        for arguments in [["--layout-audit"], ["--smoke-test"]] {
            app.launchArguments = arguments
            app.launch()
            let menu = app.buttons["editor.menu"]
            XCTAssertTrue(menu.waitForExistence(timeout: 8))
            XCTAssertFalse(app.otherElements["editor.primary-navigation"].exists)
            if arguments.contains("--smoke-test") {
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["editor.export"])
                XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 35), .completed)
            }
            let bar = app.tabBars.firstMatch
            XCTAssertTrue(bar.waitForExistence(timeout: 5), "Stages must use the native tab bar")
            for title in ["相机", "胶片", "显影", "印相", "扫描", "构图", "片边"] {
                let control = bar.buttons[title]
                XCTAssertTrue(control.waitForExistence(timeout: 5), "Missing native stage: " + title)
                if !arguments.contains("--smoke-test") {
                    XCTAssertFalse(control.isEnabled, "Empty session must keep stages disabled: " + title)
                    continue
                }
                XCTAssertTrue(control.isEnabled)
                XCTAssertTrue(control.isHittable)
                control.tap()
                let titleMatches = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", title), object: app.staticTexts["inspector.title"])
                XCTAssertEqual(XCTWaiter.wait(for: [titleMatches], timeout: 3), .completed)
                XCTAssertTrue(control.isSelected, "System tab has no selected state: " + title)
            }
            XCTAssertTrue(app.buttons["editor.export"].exists)
            XCTAssertFalse(app.buttons["editor.compare"].exists)
            menu.tap()
            XCTAssertTrue(app.buttons["import.photos"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["import.files"].exists)
            app.terminate()
        }
    }

    @MainActor func testExpandedStagesAreDirectMainNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--smoke-test"]
        app.launch()
        XCTAssertGreaterThan(min(app.frame.width, app.frame.height), 600, "Run this gate on the actually opened Duo inner display")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["导出"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 35), .completed)
        for stage in ["camera", "film", "development", "print", "output", "geometry"] {
            XCTAssertTrue(app.buttons["stage." + stage].exists, "Stage must be on the main editor: " + stage)
        }
        app.buttons["stage.film"].tap()
        XCTAssertEqual(app.staticTexts["inspector.title"].label, "胶片")
        app.buttons["stage.development"].tap()
        XCTAssertEqual(app.staticTexts["inspector.title"].label, "显影")
        app.buttons["收起面板"].tap()
        XCTAssertTrue(app.buttons["stage.camera"].isHittable)
    }

    @MainActor func testFinishedRenderSavesToPhotos() throws {
        // The test simulator grants photos-add before the suite; never change
        // privacy settings on a real phone or use a personal image as input.
        let app = XCUIApplication()
        app.launchArguments = ["--smoke-test"]
        app.launch()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["导出"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 35), .completed)
        app.buttons["导出"].tap()
        let save = app.buttons["export.photos"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.staticTexts["photos.saved"].waitForExistence(timeout: 35), app.debugDescription)
        XCTAssertFalse(app.staticTexts["delivery.error"].exists)
    }

    @MainActor func testExportOffersSaveToPhotos() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--smoke-test"]
        app.launch()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["导出"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 35), .completed)
        app.buttons["导出"].tap()
        XCTAssertTrue(app.buttons["export.photos"].waitForExistence(timeout: 5), app.debugDescription)
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }
    // Seed the simulator library with the app's generated Synthetic.tif using
    // simctl addmedia before this suite. Never use personal photos as fixtures.
    @MainActor func testSelectedPhotoImportsIntoEditor() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertFalse(app.buttons["导出"].isEnabled)
        app.buttons["import.menu"].tap()
        app.buttons["import.photos"].tap()
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 8), app.debugDescription)
        photo.tap()
        let add = app.buttons.matching(NSPredicate(format: "label IN %@", ["Done", "完成", "Add", "添加"])).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3), app.debugDescription)
        add.tap()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["导出"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 25), .completed, app.debugDescription)
        XCTAssertFalse(app.alerts["处理未完成"].exists)
    }

    @MainActor func testPhotoMenuPresentsSystemPickerAndCanCancel() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["import.menu"].tap()
        let action = app.buttons["import.photos"]
        XCTAssertTrue(action.waitForExistence(timeout: 3), app.debugDescription)
        action.tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "取消"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 8), app.debugDescription)
        cancel.tap()
        XCTAssertTrue(app.buttons["import.menu"].waitForExistence(timeout: 3))
    }
}
