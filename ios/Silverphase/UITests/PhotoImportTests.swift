import XCTest

final class PhotoImportTests: XCTestCase {
    @MainActor func testOrdinaryPhonePortraitAndVerticalMaterials() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--library-ui-regression", "--reset-library-fixture", "--documentation-captures"]
        app.launch()
        let photo = app.buttons["library.photo.来源"]
        XCTAssertTrue(photo.waitForExistence(timeout: 15))
        XCTAssertGreaterThan(app.frame.height, app.frame.width, "Ordinary phone launches in portrait even while held sideways")
        photo.tap()
        XCTAssertTrue(app.images["editor.canvas"].waitForExistence(timeout: 15))
        app.processStage("film").tap()
        app.buttons["editor.change-film"].tap()
        let list = app.scrollViews["materials.vertical-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let stockButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "materials.stock."))
        let before = stockButtons.allElementsBoundByIndex.filter(\.isHittable).map(\.identifier)
        list.swipeUp()
        let after = stockButtons.allElementsBoundByIndex.filter(\.isHittable).map(\.identifier)
        XCTAssertFalse(before.isEmpty); XCTAssertNotEqual(before, after, "Vertical swiping changes visible material rows")
        app.buttons["搜索材料"].tap()
        app.textFields["materials.search"].tap(); app.textFields["materials.search"].typeText("Gold 200")
        let gold = app.buttons["materials.stock.kodak_gold_200"]
        XCTAssertTrue(gold.waitForExistence(timeout: 3)); gold.tap()
        XCTAssertTrue(list.exists, "Keep the material list open for comparing live previews")
        XCTAssertEqual(gold.value as? String, "已选中")
        app.buttons["editor.material-done"].tap()
        XCTAssertTrue(app.buttons["editor.change-film"].label.contains("Gold 200"))
        app.processStage("print").tap()
        app.buttons["editor.change-paper"].tap()
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        let paper = try XCTUnwrap(stockButtons.allElementsBoundByIndex.first(where: \.isHittable))
        paper.tap(); XCTAssertTrue(list.exists)
        XCTAssertEqual(paper.value as? String, "已选中")
        app.buttons["editor.material-done"].tap()
        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertGreaterThan(app.frame.height, app.frame.width, "Editing remains portrait")
        let pixels = try XCTUnwrap(UIImage(data: XCUIScreen.main.screenshot().pngRepresentation))
        XCTAssertGreaterThan(pixels.size.height, pixels.size.width)
        app.terminate()
    }

    @MainActor func testCaptureCompactPhoneDocumentation() throws {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--library-ui-regression", "--reset-library-fixture", "--documentation-captures"]
        app.launch()
        func capture(_ name: String) {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Documentation - " + name; shot.lifetime = .keepAlways; add(shot)
        }
        let photo = app.buttons["library.photo.来源"]
        XCTAssertTrue(photo.waitForExistence(timeout: 15)); photo.tap()
        let canvas = app.images["editor.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["editor.library"].exists)
        canvas.tap()
        let panel = app.descendants(matching: .any).matching(identifier: "editor.parameters").firstMatch
        app.processStage("output").tap()
        XCTAssertEqual(app.staticTexts["inspector.title"].label, "扫描")
        let handle = app.descendants(matching: .any).matching(identifier: "editor.panel-resize").firstMatch
        let grip = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: 0, dy: -350)))
        capture("portrait-panel")
        app.buttons["editor.panel-collapse"].tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 3))
        canvas.pinch(withScale: 2, velocity: 1)
        capture("portrait-canvas")
        app.processStage("film").tap()
        XCTAssertEqual(app.staticTexts["inspector.title"].label, "胶片")
        app.buttons["editor.change-film"].tap()
        XCTAssertTrue(app.scrollViews["materials.vertical-list"].waitForExistence(timeout: 3))
        capture("portrait-materials")
        app.buttons["editor.material-done"].tap()
        app.buttons["editor.panel-collapse"].tap()
        app.buttons["editor.export"].tap()
        XCTAssertEqual(app.staticTexts["inspector.title"].label, "导出成片")
        let naming = app.buttons["export.naming.original"]
        for _ in 0..<8 { if naming.isHittable { break }; panel.swipeUp() }
        XCTAssertTrue(naming.isHittable)
        capture("portrait-export-naming")
        app.buttons["editor.menu"].tap(); app.buttons["设置"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        let storage = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "应用内图库")).firstMatch
        for _ in 0..<5 { if storage.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(storage.isHittable)
        capture("portrait-settings")
        app.terminate()
    }

    @MainActor func testCompactPhonePanelFloatsOverStableCanvas() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--compact-editor-ui-regression"]
        app.launch()
        let tabs = app.descendants(matching: .any).matching(identifier: "editor.compact-tabs").firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 15))
        let canvas = app.descendants(matching: .any).matching(identifier: "editor.canvas").firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(canvas.frame.width, app.frame.width * 0.95, "Portrait canvas must not reserve a side toolbar column")
        XCTAssertLessThanOrEqual(canvas.frame.minY, app.frame.minY + 2)
        XCTAssertGreaterThanOrEqual(canvas.frame.maxY, app.frame.maxY - 2)
        XCTAssertFalse(app.navigationBars.staticTexts["相机"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "editor.photo-info").firstMatch.exists)
        canvas.pinch(withScale: 2, velocity: 1)
        let fit = try XCTUnwrap(canvas.value as? String)
        XCTAssertTrue(fit.contains("pixels:"))
        XCTAssertFalse(app.staticTexts["无法读取图像"].exists)
        XCTAssertFalse(app.buttons["editor.material-summary"].exists)
        XCTAssertFalse(app.buttons["editor.undo"].exists)
        XCTAssertTrue(app.buttons["editor.export"].exists)
        XCTAssertTrue(app.buttons["editor.menu"].exists)
        for stage in ["camera", "film", "development", "print", "output", "geometry", "filmEdge"] {
            let button = app.processStage(stage)
            XCTAssertTrue(button.isHittable, "All seven process destinations must be reachable")
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            button.tap()
            XCTAssertEqual(canvas.value as? String, fit, "Switching process must preserve the photo's fit and transform")
        }
        let tabsFrame = tabs.frame
        let firstStage = app.processStage("camera")
        let lastStage = app.processStage("filmEdge")
        let firstFrame = firstStage.frame
        firstStage.press(forDuration: 0.1, thenDragTo: lastStage)
        XCTAssertEqual(tabs.frame, tabsFrame, "Dragging selects a segment without moving the whole bar")
        XCTAssertEqual(app.processStage("camera").frame, firstFrame)
        XCTAssertTrue(lastStage.isSelected, "Native glass drag selection remains available")
        app.processStage("camera").tap()
        let panel = app.descendants(matching: .any).matching(identifier: "editor.parameters").firstMatch
        let originalHeight = panel.frame.height
        let handle = app.descendants(matching: .any).matching(identifier: "editor.panel-resize").firstMatch
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -350)))
        XCTAssertGreaterThan(panel.frame.height, originalHeight)
        XCTAssertLessThanOrEqual(panel.frame.height, 520.5)
        XCTAssertEqual(canvas.value as? String, fit, "Expanding a floating panel cannot shrink the photograph")
        let expanded = XCTAttachment(screenshot: app.screenshot()); expanded.name = "Compact phone expanded panel"; expanded.lifetime = .keepAlways; add(expanded)
        app.buttons["editor.panel-collapse"].tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 3))
        XCTAssertEqual(canvas.value as? String, fit, "Collapsing the panel cannot resize the photograph")
        let collapsed = XCTAttachment(screenshot: app.screenshot()); collapsed.name = "Compact phone collapsed panel"; collapsed.lifetime = .keepAlways; add(collapsed)
        app.processStage("film").tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["inspector.title"].label, "胶片")
        XCTAssertFalse(app.buttons["editor.material-toggle"].exists)
        app.buttons["editor.change-film"].tap()
        XCTAssertTrue(app.scrollViews["materials.vertical-list"].waitForExistence(timeout: 3))
        app.buttons["editor.material-done"].tap()
        XCTAssertEqual(app.staticTexts["inspector.title"].label, "胶片")
        XCTAssertEqual(canvas.value as? String, fit)
        app.buttons["editor.export"].tap()
        XCTAssertEqual(app.staticTexts["inspector.title"].label, "导出成片")
        XCTAssertEqual(canvas.value as? String, fit)
        app.terminate()
    }

    @MainActor func testSelectedProcessReopensPanelAndLeavesExport() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--compact-editor-ui-regression"]
        app.launch()
        defer { app.terminate() }
        let camera = app.processStage("camera")
        XCTAssertTrue(camera.waitForExistence(timeout: 15))
        camera.tap()
        let panel = app.descendants(matching: .any).matching(identifier: "editor.parameters").firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        app.buttons["editor.panel-collapse"].tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 3))
        XCTAssertTrue(camera.isSelected)
        camera.tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 3), "Tapping the selected process must reopen its panel")
        XCTAssertEqual(app.staticTexts["inspector.title"].label, "相机")
        app.buttons["editor.export"].tap()
        XCTAssertEqual(app.staticTexts["inspector.title"].label, "导出成片")
        XCTAssertTrue(camera.isSelected)
        camera.tap()
        XCTAssertEqual(app.staticTexts["inspector.title"].label, "相机",
                       "Tapping the selected process must leave export")
    }

    @MainActor func testFoldedDuoKeepsNativeSideNavigation() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--compact-editor-ui-regression"]
        app.launch()
        let camera = app.buttons["相机"]
        XCTAssertTrue(camera.waitForExistence(timeout: 15))
        let panel = app.descendants(matching: .any).matching(identifier: "editor.parameters").firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "editor.compact-tabs").firstMatch.exists)
        XCTAssertGreaterThan(camera.frame.midX, panel.frame.maxX)
        app.terminate()
    }

    @MainActor func testDuoReturnIsAtTopLeading() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--library-ui-regression", "--reset-library-fixture"]
        app.launch()
        let photo = app.buttons["library.photo.来源"]
        XCTAssertTrue(photo.waitForExistence(timeout: 15))
        photo.tap()
        let back = app.buttons["editor.library"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        XCTAssertLessThan(back.frame.midX, app.frame.midX)
        XCTAssertLessThan(back.frame.maxY, app.frame.height * 0.25)
        defer { XCUIDevice.shared.orientation = .portrait }
        let info = app.descendants(matching: .any).matching(identifier: "editor.photo-info").firstMatch
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft, .landscapeRight, .portrait] {
            XCUIDevice.shared.orientation = orientation
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                info.exists && info.frame.minY >= back.frame.maxY + 8 && info.frame.minY <= back.frame.maxY + 32 && !info.frame.intersects(back.frame)
            }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
            XCTAssertFalse(app.navigationBars.staticTexts["相机"].exists)
            XCTAssertFalse(info.label.contains("来源"))
            XCTAssertFalse(info.label.contains("96"))
            let orientationShot = XCTAttachment(screenshot: app.screenshot())
            orientationShot.name = "Status below return - " + String(orientation.rawValue)
            orientationShot.lifetime = .keepAlways; add(orientationShot)
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Duo top leading return"; shot.lifetime = .keepAlways; add(shot)
        back.tap()
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        app.terminate()
    }

    @MainActor func testLibraryNativeToolbarLayout() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--library-ui-regression", "--reset-library-fixture"]
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        if UIDevice.current.userInterfaceIdiom == .pad {
            let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        }
        let source = app.buttons["library.photo.来源"]
        XCTAssertTrue(source.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["原图缩略图"].exists)
        XCTAssertFalse(app.staticTexts["编辑预览"].exists)
        XCTAssertTrue(app.buttons["library.rating-filter"].isHittable)
        XCTAssertTrue(app.buttons["library.flag-filter"].isHittable)
        app.buttons["library.flag-filter"].tap()
        app.buttons["保留"].tap()
        XCTAssertTrue(app.buttons["library.flag-filter"].label.contains("保留"))
        XCTAssertFalse(source.exists)
        app.buttons["library.flag-filter"].tap()
        app.buttons["全部旗标"].tap()
        XCTAssertTrue(source.waitForExistence(timeout: 3))
        app.buttons["library.select"].tap()
        let all = app.buttons["library.select-all"]
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["library.edit-selected"].isEnabled)
        let controls = XCTAttachment(screenshot: app.screenshot())
        controls.name = "Selection controls before select all"; controls.lifetime = .keepAlways; add(controls)
        all.tap()
        XCTAssertEqual(source.value as? String, "已选择")
        XCTAssertTrue(app.buttons["library.edit-selected"].isEnabled)
        XCTAssertTrue(app.buttons["library.export-selected"].isEnabled)
        XCTAssertFalse(app.buttons["library.rating-filter"].exists)
        XCTAssertFalse(app.buttons["library.flag-filter"].exists)
        XCTAssertEqual(all.label, "清空选择")
        for id in ["library.select-all", "library.edit-selected", "library.export-selected", "library.selection-menu"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.isHittable, "Native selection action must be directly reachable: " + id)
            if UIDevice.current.userInterfaceIdiom == .pad {
                XCTAssertLessThan(button.frame.maxY, source.frame.minY, "iPad uses its native upper toolbar")
            } else {
                XCTAssertGreaterThan(button.frame.midX, source.frame.maxX, "Duo actions belong in the shared side rail")
            }
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Native gallery toolbar"; attachment.lifetime = .keepAlways; add(attachment)
        all.tap()
        XCTAssertEqual(source.value as? String, "未选择")
        XCTAssertFalse(app.buttons["library.export-selected"].isEnabled)
        app.terminate()
    }

    @MainActor func testLibrarySwipeSelection() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--library-ui-regression", "--reset-library-fixture"]
        app.launch()
        let source = app.buttons["library.photo.来源"]
        let first = app.buttons["library.photo.目标 A"]
        let other = app.buttons["library.photo.目标 B"]
        XCTAssertTrue(source.waitForExistence(timeout: 15))
        app.buttons["library.select"].tap()
        XCTAssertEqual(app.buttons["library.select-all"].label, "全选")
        let start = source.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.4))
        let end = first.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.4))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertEqual(source.value as? String, "已选择")
        XCTAssertEqual(first.value as? String, "已选择")
        XCTAssertEqual(other.value as? String, "未选择")
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertEqual(source.value as? String, "未选择")
        XCTAssertEqual(first.value as? String, "未选择")
        source.tap()
        end.press(forDuration: 0.05, thenDragTo: start)
        XCTAssertEqual(source.value as? String, "已选择", "A reverse stroke adds a range without toggling earlier selected cards")
        XCTAssertEqual(first.value as? String, "已选择")
        XCTAssertFalse(app.buttons["editor.menu"].exists, "Selection swipes must never open an editor")
        app.terminate()
    }

    @MainActor func testLibrarySelectionEditingExportAndColdRestore() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--library-ui-regression", "--reset-library-fixture"]
        app.launch()
        let source = app.buttons["library.photo.来源"]
        let first = app.buttons["library.photo.目标 A"]
        let second = app.buttons["library.photo.目标 B"]
        XCTAssertTrue(source.waitForExistence(timeout: 15))
        app.buttons["library.select"].tap(); source.tap()
        app.buttons["library.selection-menu"].tap(); app.buttons["复制编辑项"].tap()
        XCTAssertTrue(app.buttons["clipboard.confirm-copy"].waitForExistence(timeout: 3))
        app.buttons["清除"].tap()
        app.switches["clipboard.group.camera"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["clipboard.confirm-copy"].tap()
        XCTAssertTrue(app.buttons["clipboard.confirm-copy"].waitForNonExistence(timeout: 3))
        source.tap(); first.tap(); second.tap()
        app.buttons["library.selection-menu"].tap(); app.buttons["粘贴到所选 2 张"].tap()
        XCTAssertEqual(first.value as? String, "已选择")
        XCTAssertEqual(second.value as? String, "已选择")
        app.buttons["library.selection-menu"].tap()
        let rating = app.buttons["评分"]
        XCTAssertTrue(rating.waitForExistence(timeout: 3))
        rating.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let fourStars = app.buttons["4 星"]
        XCTAssertTrue(fourStars.waitForExistence(timeout: 3))
        fourStars.tap()
        let grid = XCTAttachment(screenshot: app.screenshot()); grid.name = "Persistent library selection"; grid.lifetime = .keepAlways; add(grid)
        app.buttons["library.export-selected"].tap()
        XCTAssertTrue(app.staticTexts["export.selected-count"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["export.selected-count"].label, "已选 2 张照片")
        app.buttons["library.export-done"].tap()
        app.buttons["library.edit-selected"].tap()
        XCTAssertTrue(app.buttons["editor.apply-batch"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["filmstrip.photo.目标 A"].exists)
        XCTAssertFalse(app.buttons["filmstrip.photo.来源"].exists)
        app.buttons["editor.apply-batch"].tap()
        XCTAssertTrue(app.navigationBars["批量应用编辑项"].waitForExistence(timeout: 3))
        app.buttons["取消"].tap()
        if app.buttons["editor.library"].exists { app.buttons["editor.library"].tap() }
        else { app.buttons["editor.menu"].tap(); app.buttons["editor.library"].tap() }
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertEqual(first.value as? String, "已选择")
        app.buttons["library.select"].tap()
        first.tap()
        XCTAssertTrue(app.buttons["editor.menu"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["filmstrip.photo.目标 A"].exists, "Single-photo editing hides filmstrip")
        let ruler = app.descendants(matching: .any).matching(identifier: "ruler.曝光补偿 · EV").firstMatch
        for _ in 0..<5 { if ruler.isHittable { break }; app.otherElements["editor.parameters"].swipeUp() }
        XCTAssertEqual(ruler.value as? String, "1.00")
        app.terminate()
        app.launchArguments = ["--library-ui-regression"]
        app.launch()
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        app.buttons["library.rating-filter"].tap(); app.buttons["至少 4 星"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 3)); XCTAssertTrue(second.exists); XCTAssertFalse(source.exists)
        first.tap()
        XCTAssertTrue(app.buttons["editor.menu"].waitForExistence(timeout: 5))
        for _ in 0..<5 { if ruler.isHittable { break }; app.otherElements["editor.parameters"].swipeUp() }
        XCTAssertEqual(ruler.value as? String, "1.00", "Pasted edit survives actual process termination")
        app.terminate()
    }

    @MainActor func testIPadNativeProcessPickerAndActions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--library-ui-regression", "--reset-library-fixture"]
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        let photo = app.buttons["library.photo.来源"]
        XCTAssertTrue(photo.waitForExistence(timeout: 15))
        photo.tap()
        let picker = app.descendants(matching: .any).matching(identifier: "editor.horizontal-process-picker").firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
        XCTAssertFalse(app.otherElements["editor.primary-navigation"].exists)
        let canvas = app.descendants(matching: .any).matching(identifier: "editor.canvas").firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            let portrait = orientation == .portrait
            let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                portrait ? app.frame.height > app.frame.width : app.frame.width > app.frame.height
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
            for id in ["camera", "film", "development", "print", "output", "geometry", "filmEdge"] {
                let segment = app.processStage(id)
                XCTAssertTrue(segment.isHittable, "Seven native stages remain reachable: " + id)
                XCTAssertGreaterThanOrEqual(segment.frame.width, 44)
                segment.tap()
                XCTAssertTrue(segment.isSelected)
            }
            app.processStage("camera").tap()
            canvas.pinch(withScale: 2, velocity: 1)
            let transform = try XCTUnwrap(canvas.value as? String)
            let frame = picker.frame
            app.processStage("camera").press(forDuration: 0.1, thenDragTo: app.processStage("filmEdge"))
            XCTAssertTrue(app.processStage("filmEdge").isSelected)
            XCTAssertEqual(picker.frame, frame, "Dragging changes selection without moving the dock")
            XCTAssertEqual(canvas.value as? String, transform)
            XCTAssertLessThanOrEqual(canvas.frame.minY, app.frame.minY + 2)
            XCTAssertGreaterThanOrEqual(canvas.frame.maxY, app.frame.maxY - 2)
            for id in ["editor.library", "editor.export", "editor.menu"] {
                let action = app.buttons[id]
                XCTAssertTrue(action.isHittable)
                XCTAssertLessThan(abs(action.frame.midY - picker.frame.midY), 4,
                                  "Process picker and all actions must share one native toolbar row: " + id)
                XCTAssertFalse(action.frame.intersects(picker.frame))
            }
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = portrait ? "iPad native portrait" : "iPad native landscape"
            capture.lifetime = .keepAlways; add(capture)
        }
        let menu = app.buttons["editor.menu"]
        XCTAssertTrue(menu.isHittable)
        menu.tap()
        XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 3))
        app.buttons["设置"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 3))
        app.buttons["完成"].tap()
        XCTAssertTrue(menu.isHittable)
        app.terminate()
        app.launchArguments = ["--layout-audit"]
        app.launch()
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        for id in ["camera", "film", "development", "print", "output", "geometry", "filmEdge"] {
            XCTAssertFalse(app.processStage(id).isEnabled, "Empty sessions keep process selection disabled")
        }
        app.terminate()
    }

    @MainActor func testSelectiveCopyAndMultiPhotoPaste() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--clipboard-ui-regression"]
        app.launch()
        let source = app.buttons["filmstrip.photo.来源"]
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        let toolbar = XCTAttachment(screenshot: app.screenshot()); toolbar.name = "Photo toolbar icons"; toolbar.lifetime = .keepAlways; add(toolbar)
        app.buttons["clipboard.copy"].tap()
        XCTAssertTrue(app.buttons["clipboard.confirm-copy"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.switches["clipboard.group.camera"].value as? String, "1")
        app.buttons["清除"].tap()
        XCTAssertFalse(app.buttons["clipboard.confirm-copy"].isEnabled)
        app.switches["clipboard.group.camera"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(app.switches["clipboard.group.camera"].value as? String, "1")
        XCTAssertTrue(app.buttons["clipboard.confirm-copy"].isEnabled)
        let copySheet = XCTAttachment(screenshot: app.screenshot()); copySheet.name = "Copy parameter scope"; copySheet.lifetime = .keepAlways; add(copySheet)
        app.buttons["clipboard.confirm-copy"].tap()
        XCTAssertTrue(app.buttons["clipboard.confirm-copy"].waitForNonExistence(timeout: 3))
        let first = app.buttons["filmstrip.photo.目标 A"]
        let second = app.buttons["filmstrip.photo.目标 B"]
        first.press(forDuration: 1)
        let menu = XCTAttachment(screenshot: app.screenshot()); menu.name = "Photo context menu"; menu.lifetime = .keepAlways; add(menu)
        app.buttons["选择多张"].tap()
        XCTAssertEqual(first.value as? String, "已选择")
        XCTAssertEqual(second.value as? String, "未选择")
        second.tap()
        XCTAssertEqual(second.value as? String, "已选择")
        XCTAssertEqual(app.buttons["clipboard.paste-selected"].label, "粘贴到 2 张")
        let selected = XCTAttachment(screenshot: app.screenshot()); selected.name = "Multi-photo paste selection"; selected.lifetime = .keepAlways; add(selected)
        app.buttons["clipboard.paste-selected"].tap()
        XCTAssertTrue(app.buttons["clipboard.paste-selected"].exists, "Paste must not open another range sheet or exit selection")
        XCTAssertFalse(app.buttons["clipboard.confirm-copy"].exists)
        app.buttons["filmstrip.done"].tap()
        first.tap()
        let ruler = app.descendants(matching: .any).matching(identifier: "ruler.曝光补偿 · EV").firstMatch
        for _ in 0..<5 { if ruler.isHittable { break }; app.otherElements["editor.parameters"].swipeUp() }
        XCTAssertEqual(ruler.value as? String, "1.00")
        if app.buttons["editor.undo"].exists { app.buttons["editor.undo"].tap() }
        else { app.buttons["editor.menu"].tap(); app.buttons["撤销"].tap() }
        XCTAssertEqual(ruler.value as? String, "-1.00", "A single undo must reverse batch paste after changing preview")
        second.tap()
        XCTAssertEqual(ruler.value as? String, "-2.00", "The same undo must also restore the second target")
        if app.buttons["editor.redo"].exists { app.buttons["editor.redo"].tap() }
        else { app.buttons["editor.menu"].tap(); app.buttons["重做"].tap() }
        XCTAssertEqual(ruler.value as? String, "1.00")
        app.buttons["filmstrip.select"].tap()
        XCTAssertFalse(app.buttons["clipboard.paste-selected"].isEnabled)
        first.tap()
        XCTAssertEqual(app.buttons["clipboard.paste-selected"].label, "粘贴到 1 张")
        app.buttons["filmstrip.done"].tap()
        app.terminate()
    }

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
    @MainActor func testSideProcessAndActionsAlignToOppositeEdges() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--compact-editor-ui-regression"]
        app.launch()
        let first = app.processStage("camera")
        let last = app.processStage("filmEdge")
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        let export = app.buttons["editor.export"]
        let menu = app.buttons["editor.menu"]
        XCTAssertTrue(export.isHittable); XCTAssertTrue(menu.isHittable)
        XCTAssertLessThan(export.frame.maxY, first.frame.minY)
        XCTAssertLessThan(menu.frame.maxY, first.frame.minY)
        XCTAssertGreaterThanOrEqual(last.frame.maxY, app.frame.maxY - 44, "Process group must align to the bottom safe edge")
        XCTAssertLessThanOrEqual(last.frame.maxY, app.frame.maxY)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Duo top actions and bottom process group"; capture.lifetime = .keepAlways; add(capture)
        app.terminate()
    }

    @MainActor func testSideProcessSurvivesToolbarPressure() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--compact-editor-ui-regression", "--side-toolbar-pressure"]
        app.launch()
        // Require actual system overflow, rather than assuming that the
        // additional item consumed space or that this is a crowded layout.
        let overflow = app.buttons.matching(NSPredicate(format: "identifier CONTAINS %@", "OverflowBarButtonItem")).firstMatch
        XCTAssertTrue(overflow.waitForExistence(timeout: 15), "The test must actually trigger native toolbar overflow")
        for id in ["camera", "film", "development", "print", "output", "geometry", "filmEdge"] {
            let control = app.processStage(id)
            XCTAssertTrue(control.waitForExistence(timeout: 5))
            XCTAssertTrue(control.isHittable, "Process must remain outside overflow: " + id)
            XCTAssertGreaterThanOrEqual(control.frame.height, 43.5)
            control.tap()
            XCTAssertTrue(control.isSelected)
        }
        let photo = app.buttons["filmstrip.photo.Compact layout fixture"]
        XCTAssertTrue(photo.exists)
        XCTAssertGreaterThanOrEqual(photo.frame.maxY, app.frame.maxY - 50, "Moving the process group upward must not shorten the workspace")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Duo process selection under toolbar pressure"; capture.lifetime = .keepAlways; add(capture)
        app.terminate()
    }

    @MainActor func testImportedPhotoActivatesNativeStagesAndTracksSelection() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        for arguments in [["--layout-audit"], ["--compact-editor-ui-regression"]] {
            app.launchArguments = arguments
            app.launch()
            let menu = app.buttons["editor.menu"]
            XCTAssertTrue(menu.waitForExistence(timeout: 8))
            XCTAssertFalse(app.otherElements["editor.primary-navigation"].exists)
            if arguments.contains("--compact-editor-ui-regression") {
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["editor.export"])
                XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 35), .completed)
            }
            XCTAssertFalse(app.tabBars.firstMatch.exists, "Seven stages must avoid system tab overflow")
            for (id, title) in [("camera", "相机"), ("film", "胶片"), ("development", "显影"), ("print", "印相"), ("output", "扫描"), ("geometry", "构图"), ("filmEdge", "片边")] {
                let control = app.processStage(id)
                XCTAssertTrue(control.waitForExistence(timeout: 5), "Missing native stage: " + title)
                if !arguments.contains("--compact-editor-ui-regression") {
                    XCTAssertFalse(control.isEnabled, "Empty session must keep stages disabled: " + title)
                    continue
                }
                XCTAssertTrue(control.isEnabled)
                XCTAssertTrue(control.isHittable)
                control.tap()
                let titleMatches = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", title), object: app.staticTexts["inspector.title"])
                XCTAssertEqual(XCTWaiter.wait(for: [titleMatches], timeout: 3), .completed)
                XCTAssertTrue(control.isSelected, "Native segment has no selected state: " + title)
            }
            XCTAssertTrue(app.buttons["editor.export"].exists)
            XCTAssertFalse(app.buttons["editor.compare"].exists)
            menu.tap()
            XCTAssertTrue(app.buttons["从照片导入"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["从文件导入"].exists)
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
            XCTAssertTrue(app.processStage(stage).exists, "Stage must be on the main editor: " + stage)
        }
        app.processStage("film").tap()
        XCTAssertEqual(app.staticTexts["inspector.title"].label, "胶片")
        app.processStage("development").tap()
        XCTAssertEqual(app.staticTexts["inspector.title"].label, "显影")
        app.buttons["收起面板"].tap()
        XCTAssertTrue(app.processStage("camera").isHittable)
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

private extension XCUIApplication {
    func processStage(_ id: String) -> XCUIElement {
        let button = buttons["stage." + id]
        if button.exists { return button }
        // Native segments expose their image's identifier and use its label
        // for VoiceOver. Query the containing button to exercise real tracking.
        return buttons.containing(.image, identifier: "stage." + id).firstMatch
    }
}
