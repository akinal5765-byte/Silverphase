#if DEBUG
import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import SwiftUI
import UIKit
import Darwin

// Explicit launch-only diagnostics. Synthetic input is generated inside the
// app container; no personal photos are copied into the repository or bundle.
enum MobileSmokeChecks {
    @MainActor static func flatImportRegression() async {
        let report = URL.documentsDirectory.appendingPathComponent("flat-import-report.json")
        let workspace = URL.temporaryDirectory.appendingPathComponent("Flat-Regression-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: workspace) }
        var checks: [String] = []
        var exportsValidated = true
        do {
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            let engine = MobileEngine()
            let base: [String: WireValue] = ["auto_exposure": .bool(false), "grain_active": .bool(false), "glare_active": .bool(false)]
            var cases: [(UTType, CFString, Int, Int)] = [(.jpeg, CGColorSpace.sRGB, 96, 64), (.jpeg, CGColorSpace.displayP3, 96, 64),
                (.jpeg, CGColorSpace.adobeRGB1998, 96, 64), (.heic, CGColorSpace.displayP3, 96, 64), (.png, CGColorSpace.sRGB, 96, 64), (.tiff, CGColorSpace.sRGB, 96, 64)]
            if ProcessInfo.processInfo.arguments.contains("--flat-import-large") {
                cases += [(.jpeg, CGColorSpace.sRGB, 4032, 3024), (.heic, CGColorSpace.displayP3, 4032, 3024)]
            }
            for (index, item) in cases.enumerated() {
                let (type, spaceName, width, height) = item
                let space = CGColorSpace(name: spaceName)!
                // Neutral mid-grey must decode near 0.216, rather than stay
                // encoded at 0.502 or be decoded twice to roughly 0.038.
                let bytes = Data(repeating: 128, count: width * height * 3)
                let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24,
                    bytesPerRow: width * 3, space: space, bitmapInfo: CGBitmapInfo(rawValue: 0),
                    provider: CGDataProvider(data: bytes as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
                let source = workspace.appendingPathComponent("source-\(index)." + type.preferredFilenameExtension!)
                guard let writer = CGImageDestinationCreateWithURL(source as CFURL, type.identifier as CFString, 1, nil) else {
                    throw MobileFailure.message("无法创建输入测试图片")
                }
                CGImageDestinationAddImage(writer, image, [kCGImagePropertyOrientation: 6,
                    kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFOrientation: 6],
                    kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
                guard CGImageDestinationFinalize(writer) else { throw MobileFailure.message("输入测试图片写入失败") }
                let provider = NSItemProvider()
                provider.suggestedName = "Photo-\(index)." + type.preferredFilenameExtension!
                provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
                    completion(source, false, nil); return nil
                }
                guard let loaded = try await LibraryPhotoPicker.Coordinator.load(provider) else {
                    throw MobileFailure.message("普通照片被相册入口跳过：\(type.identifier)")
                }
                defer { try? FileManager.default.removeItem(at: loaded.url) }
                guard loaded.name == provider.suggestedName, MobileImageMetadata.read(loaded.url).typeIdentifier == type.identifier,
                      try Data(contentsOf: loaded.url) == Data(contentsOf: source) else {
                    throw MobileFailure.message("输入名称或格式未保留")
                }
                let samples = try await engine.auditInput(loaded.url)
                let expected = spaceName == CGColorSpace.adobeRGB1998 ? 0.2195 : 0.2159
                guard samples.allSatisfy({ $0.isFinite && abs($0 - expected) < 0.012 }) else {
                    throw MobileFailure.message("输入灰阶线性化错误：\(spaceName)")
                }
                let result = try await engine.render(url: loaded.url, recipe: base, megapixels: Double(width * height) / 1e6)
                guard result.resolved["_raw"]?.boolValue == false, result.resolved["_lensSupported"]?.boolValue == false,
                      result.resolved["_asShotTemperature"] == nil, result.image.width == height, result.image.height == width else {
                    throw MobileFailure.message("普通照片类型或 EXIF 方向错误：\(result.image.width)x\(result.image.height), raw=\(String(describing: result.resolved["_raw"])), lens=\(String(describing: result.resolved["_lensSupported"])), asShot=\(String(describing: result.resolved["_asShotTemperature"]))")
                }
                var canCheckExport = true
#if targetEnvironment(simulator)
                // Some simulator runtimes report an insufficient process budget
                // even for tiny fixtures. Keep the production guard and report this
                // missing export check explicitly, rather than bypassing it.
                canCheckExport = Double(os_proc_available_memory()) > 607_000_000
#endif
                if canCheckExport {
                    let output = try await engine.export(url: loaded.url, recipe: base, geometry: MobileGeometry(), format: .jpeg)
                    defer { try? FileManager.default.removeItem(at: output.deletingLastPathComponent()) }
                    guard let reader = CGImageSourceCreateWithURL(output as CFURL, nil),
                          let exported = CGImageSourceCreateImageAtIndex(reader, 0, nil),
                          exported.width == height, exported.height == width, exported.bitsPerComponent == 8,
                          CGImageSourceCopyPropertiesAtIndex(reader, 0, nil).flatMap { ($0 as NSDictionary)[kCGImagePropertyProfileName] } != nil else { throw MobileFailure.message("普通照片导出尺寸或 ICC 错误") }
                } else {
                    exportsValidated = false
                }
                if index == 0 {
                    let document = MobileDocument(directory: workspace.appendingPathComponent("session"))
                    await document.importFiles([loaded.url], displayNames: [loaded.url: loaded.name]).value
                    for _ in 0..<600 {
                        if !document.isInteractionLocked { break }
                        try await Task.sleep(for: .milliseconds(50))
                    }
                    guard document.current?.name == loaded.name, document.value("_raw")?.boolValue == false,
                          !document.isInteractionLocked, document.error == nil else {
                        throw MobileFailure.message("JPG 编辑器导入或首次预览失败")
                    }
                    document.setActive(false)
                    await document.waitForPreviewCleanup()
                }
                checks.append("\(type.identifier) / \(spaceName) / \(width)x\(height): picker, original bytes/name, linear grey, orientation, render" + (canCheckExport ? ", JPEG export ICC" : "; export unavailable: simulator memory budget"))
            }
            let invalid = workspace.appendingPathComponent("invalid.jpg")
            try Data("not an image".utf8).write(to: invalid)
            let provider = NSItemProvider()
            provider.registerFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier, fileOptions: [], visibility: .all) { completion in
                completion(invalid, false, nil); return nil
            }
            guard try await LibraryPhotoPicker.Coordinator.load(provider) == nil else { throw MobileFailure.message("损坏文件被接收") }
            checks.append("invalid image rejected")
            let rawProvider = NSItemProvider()
            rawProvider.registerFileRepresentation(forTypeIdentifier: UTType.rawImage.identifier, fileOptions: [], visibility: .all) { completion in
                completion(workspace.appendingPathComponent("source-0").appendingPathExtension(UTType.jpeg.preferredFilenameExtension!), false, nil); return nil
            }
            rawProvider.registerFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier, fileOptions: [], visibility: .all) { completion in
                completion(nil, false, MobileFailure.message("错误请求了 RAW 的 JPEG 预览")); return nil
            }
            guard try await LibraryPhotoPicker.Coordinator.load(rawProvider) == nil else {
                throw MobileFailure.message("RAW 请求被静默替换成 JPEG")
            }
            checks.append("RAW representation preferred; rendered substitute rejected")
            await engine.close()
            try JSONSerialization.data(withJSONObject: ["passed": true, "exportsValidated": exportsValidated, "checks": checks], options: [.prettyPrinted, .sortedKeys]).write(to: report, options: .atomic)
        } catch {
            try? JSONSerialization.data(withJSONObject: ["passed": false, "checks": checks, "error": error.localizedDescription], options: [.prettyPrinted, .sortedKeys]).write(to: report, options: .atomic)
        }
    }

    @MainActor static func rawImportRegression() async {
        let source = URL.documentsDirectory.appendingPathComponent("raw-import-regression.jpeg")
        let report = URL.documentsDirectory.appendingPathComponent("raw-import-report.json")
        let workspace = URL.temporaryDirectory.appendingPathComponent("RAW-Regression-" + UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: workspace)
        }
        do {
            let metadata = MobileImageMetadata.read(source)
            guard metadata.isRaw, !metadata.exifSummary.isEmpty else { throw MobileFailure.message("RAW 内容识别或 EXIF 回归失败") }
            let provider = NSItemProvider()
            provider.suggestedName = "RAW-Import-Regression.ARW"
            provider.registerFileRepresentation(forTypeIdentifier: metadata.typeIdentifier!, fileOptions: [], visibility: .all) { completion in
                completion(source, false, nil); return nil
            }
            // The picker may offer both RAW and a rendered preview. The loader
            // must choose the RAW representation and retain its suggested name.
            provider.registerFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier, fileOptions: [], visibility: .all) { completion in
                completion(nil, false, MobileFailure.message("错误请求了 JPEG 预览")); return nil
            }
            guard let loaded = try await LibraryPhotoPicker.Coordinator.load(provider) else { throw MobileFailure.message("RAW 被误跳过") }
            defer { try? FileManager.default.removeItem(at: loaded.url) }
            let document = MobileDocument(directory: workspace)
            await document.importFiles([loaded.url], displayNames: [loaded.url: loaded.name]).value
            for _ in 0..<300 {
                if !document.isInteractionLocked { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            guard let photo = document.current, photo.name == "RAW-Import-Regression.ARW",
                  !photo.exifSummary.isEmpty, document.url(for: photo).pathExtension.lowercased() == "arw" else {
                throw MobileFailure.message("原始名称、EXIF 或 RAW 存储后缀未保留")
            }
            let engine = MobileEngine()
            let result = try await engine.render(url: document.url(for: photo), recipe: ["auto_exposure": .bool(false), "grain_active": .bool(false), "glare_active": .bool(false)])
            guard result.resolved["_raw"]?.boolValue == true, result.image.width > 0, result.image.height > 0 else {
                throw MobileFailure.message("RAW 未到达真实 RAW 解码和出图路径")
            }
            let outputSize = [result.image.width, result.image.height]
            document.setActive(false)
            await engine.close()
            let png = workspace.appendingPathComponent("non-raw.png")
            let image = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
            try CIContext().writePNGRepresentation(of: image, to: png, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
            let nonRawProvider = NSItemProvider()
            nonRawProvider.suggestedName = "Non-RAW.png"
            nonRawProvider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { completion in
                completion(png, false, nil); return nil
            }
            guard let flat = try await LibraryPhotoPicker.Coordinator.load(nonRawProvider) else { throw MobileFailure.message("普通照片被误跳过") }
            defer { try? FileManager.default.removeItem(at: flat.url) }
            let values: [String: Any] = ["passed": true, "rawType": metadata.typeIdentifier ?? "", "exifPresent": true,
                                        "displayNamePreserved": true, "correctedStorageExtension": true,
                                        "flatImageAccepted": true, "rawPreferredOverJPEGPreview": true, "rawDecoded": true, "outputSize": outputSize]
            try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]).write(to: report, options: .atomic)
        } catch {
            let values: [String: Any] = ["passed": false, "error": error.localizedDescription]
            try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]).write(to: report, options: .atomic)
        }
    }

    @MainActor static func clipboardRegression() {
        let report = URL.documentsDirectory.appendingPathComponent("clipboard-report.json")
        let directory = URL.temporaryDirectory.appendingPathComponent("Clipboard-Regression-" + UUID().uuidString)
        let document = MobileDocument(directory: directory)
        document.active = false
        defer { try? FileManager.default.removeItem(at: directory) }
        var checks: [String] = []
        do {
            func require(_ condition: Bool, _ message: String) throws {
                guard condition else { throw MobileFailure.message(message) }
                checks.append(message)
            }
            var source = MobilePhoto(name: "Source", filename: "source.tif")
            source.recipe = ["exposure_compensation_ev": .double(1), "film_stock": .string("kodak_gold_200"),
                             "_placementHighlight": .double(2), "_whiteBalancePreset": .string("asShot"),
                             "_temperature": .double(8000), "_lens": .bool(true)]
            source.geometry = MobileGeometry(quarterTurns: 1, aspect: 1)
            var first = MobilePhoto(name: "Target A", filename: "a.tif")
            first.recipe = ["exposure_compensation_ev": .double(-1), "density_curve_gamma": .double(1.2),
                            "_temperature": .double(3200), "_tint": .double(25), "_whiteBalancePreset": .string("custom"),
                            "_lens": .bool(false), "_raw": .bool(true), "camera_filter": .string("w25")]
            var second = MobilePhoto(name: "Target B", filename: "b.tif")
            second.recipe = ["exposure_compensation_ev": .double(-2), "film_stock": .string("kodak_portra_400")]
            let untouched = MobilePhoto(name: "Unselected", filename: "c.tif")
            document.photos = [source, first, second, untouched]; document.selection = first.id
            document.copySettings(source); document.pasteSettings()
            try require(document.current?.geometry == first.geometry, "default clipboard preserves target geometry")
            document.undo()
            try require(document.current?.recipe == first.recipe, "single paste undo restores sparse overrides")
            document.copySettings(source, groups: [.camera])
            document.photos[0].recipe["exposure_compensation_ev"] = .double(3)
            document.photos[0].name = "Renamed Source"
            document.beginPhotoSelection(first.id); document.togglePhotoSelection(second.id)
            let preview = document.selection
            try require(document.selectedPhotoIDs == [first.id, second.id] && document.selection == preview, "multi-selection does not change preview")
            let count = document.pasteSettings()
            try require(count == 2 && document.selectedPhotoIDs.count == 2 && document.isSelectingPhotos, "paste targets selected photos and retains selection")
            try require(document.photos[1].recipe["exposure_compensation_ev"]?.doubleValue == 1 && document.photos[2].recipe["exposure_compensation_ev"]?.doubleValue == 1, "clipboard is a copy-time snapshot across targets")
            try require(document.settingsClipboard?.sourceName == "Source" && document.settingsClipboard?.groups == [.camera], "clipboard retains source label and confirmed groups")
            try require(document.photos[1].recipe["density_curve_gamma"]?.doubleValue == 1.2 && document.photos[2].recipe["film_stock"] == second.recipe["film_stock"], "unselected parameter groups remain intact")
            try require(document.photos[1].recipe["camera_filter"] == nil && document.photos[1].recipe["_temperature"] == nil && document.photos[1].recipe["_tint"] == nil, "source defaults remove old overrides and As Shot uses target camera")
            try require(document.photos[1].recipe["_lens"] == .bool(false) && document.photos[1].recipe["_raw"] == .bool(true), "lens calibration and decode metadata are not pasted")
            try require(document.photos[1].recipe["_placementHighlight"] == .double(2) && document.photos[1].recipe["scene_latitude_highlight_knee"] == nil, "scene placement copies intent rather than fitted curve")
            try require(document.photos[3].recipe == untouched.recipe && document.photos[0].recipe["exposure_compensation_ev"] == .double(3), "unselected source and photo remain unchanged")
            document.mark(first.id, rating: 5, flag: "pick")
            document.select(untouched.id)
            document.undo()
            try require(document.photos[1].recipe == first.recipe && document.photos[2].recipe == second.recipe, "one undo restores the entire batch after switching preview")
            try require(document.photos[1].rating == 5 && document.photos[1].flag == "pick", "undo preserves later ratings and flags")
            document.redo()
            try require(document.photos[1].recipe["exposure_compensation_ev"] == .double(1) && document.photos[2].recipe["exposure_compensation_ev"] == .double(1), "one redo reapplies the entire batch")
            document.pasteSettings()
            document.undo()
            try require(document.photos[1].recipe == first.recipe && document.photos[2].recipe == second.recipe, "repeating an identical paste adds no empty undo step")
            document.redo()
            document.restrictPhotoSelection(to: [second.id, untouched.id])
            try require(document.selectedPhotoIDs == [second.id], "filter changes remove hidden paste targets")
            document.selectAllPhotos([second.id, untouched.id, UUID()])
            try require(document.selectedPhotoIDs == [second.id, untouched.id], "select all uses supplied visible existing photos only")
            document.clearPhotoSelection()
            try require(document.pasteSettings() == 0, "empty multi-selection never falls back to current photo")
            document.endPhotoSelection()
            try require(!document.isSelectingPhotos && document.selectedPhotoIDs.isEmpty, "done exits and clears multi-selection")
            let clip = document.settingsClipboard
            document.copySettings(source, groups: [])
            try require(document.settingsClipboard?.summary == clip?.summary, "empty copy leaves confirmed clipboard untouched")
            document.copySettings(source, groups: [.geometry])
            document.pasteSettings(to: [second.id])
            try require(document.photos[2].geometry != second.geometry && document.photos[2].recipe["exposure_compensation_ev"] == .double(1), "geometry is opt-in and does not replace recipe")
            document.undo()
            try require(document.photos[2].geometry == second.geometry, "geometry paste is undoable")
            var manual = source
            manual.name = "Manual WB"
            manual.recipe = ["_whiteBalancePreset": .string("custom"), "_temperature": .double(5100)]
            document.copySettings(manual, groups: [.camera]); document.pasteSettings(to: [first.id])
            try require(document.photos[1].recipe["_temperature"] == .double(5100) && document.photos[1].recipe["_tint"] == nil, "custom white balance copies only explicit axes")
            let allKeys = MobileClipboardGroup.allCases.flatMap { Array($0.keys) }
            try require(Set(allKeys).count == allKeys.count, "clipboard parameter groups have unique ownership")
            let lockedRecipe = document.photos[1].recipe
            _ = document.beginPhotoImport(total: 1)
            document.beginPhotoSelection(first.id); document.copySettings(source); document.pasteSettings(to: [first.id]); document.undo()
            try require(document.photos[1].recipe == lockedRecipe && document.settingsClipboard?.sourceName == manual.name && !document.isSelectingPhotos, "import lock blocks copy selection paste and history mutations")
            document.finishPhotoImportWithoutFiles()
            document.undo() // undo last camera paste, revealing the preceding batch history
            document.remove(second.id)
            while document.canUndo { document.undo() }
            try require(!document.photos.contains { $0.id == second.id }, "history never resurrects a removed target")
            document.select(first.id)
            let beforeDrag = document.current?.recipe
            document.beginParameterInteraction()
            document.set("exposure_compensation_ev", .double(0.33))
            document.set("exposure_compensation_ev", .double(0.66))
            document.setDiscrete("camera_filter", .string("w8"))
            document.undo()
            try require(document.current?.recipe["camera_filter"] == beforeDrag?["camera_filter"] && document.current?.recipe["exposure_compensation_ev"] == .double(0.66), "discrete edit after a ruler drag has its own undo step")
            document.undo()
            try require(document.current?.recipe == beforeDrag, "continuous ruler edits still undo as one transaction")
            document.redo()
            try require(document.current?.recipe["exposure_compensation_ev"] == .double(0.66), "continuous ruler edits still redo as one transaction")
            let result: [String: Any] = ["passed": true, "checks": checks]
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: report, options: .atomic)
        } catch {
            try? JSONSerialization.data(withJSONObject: ["passed": false, "checks": checks, "error": error.localizedDescription], options: [.prettyPrinted, .sortedKeys]).write(to: report, options: .atomic)
        }
    }

    @MainActor static func prepareIPadChromeUI(_ document: MobileDocument) {
        document.active = false
        let color = CIImage(color: CIColor(red: 1, green: 0.25, blue: 0.05)).cropped(to: CGRect(x: 0, y: 0, width: 128, height: 128))
        guard let image = CIContext().createCGImage(color, from: color.extent) else { return }
        var photo = MobilePhoto(name: "Chrome boundary fixture", filename: "chrome-fixture.tif")
        photo.sourceMegapixels = 0.016384; photo.sourceAspect = 1
        document.photos = [photo]; document.selection = photo.id
        document.image = image; document.original = image
        document.canvasState.scale = 12
    }

    @MainActor static func prepareClipboardUI(_ document: MobileDocument) {
        document.active = false
        document.photos = ["来源", "目标 A", "目标 B"].enumerated().map { index, name in
            var photo = MobilePhoto(name: name, filename: "clipboard-ui-\(index).tif")
            photo.recipe["exposure_compensation_ev"] = .double(index == 0 ? 1 : -Double(index))
            return photo
        }
        document.selection = document.photos.first?.id
    }

    @MainActor static func run() async throws -> URL {
        let previousIdle = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = previousIdle }
        let directory = URL.documentsDirectory
        let reportURL = directory.appendingPathComponent("smoke-report.json")
        try? FileManager.default.removeItem(at: reportURL)
        var checks: [String] = []
        do {
            func require(_ condition: Bool, _ message: String) throws {
                guard condition else { throw MobileFailure.message(message) }
            }
            try MobileGeometryChecks.run()
            checks.append("desktop crop mapping: 16 turn/flip combinations, off-centre crop, straighten, ratio lock and drag bounds")
            let source = directory.appendingPathComponent("Synthetic.tif")
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let image = CIFilter(name: "CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 192, y: 128),
                "inputColor0": CIColor(red: 0.06, green: 0.15, blue: 0.4),
                "inputColor1": CIColor(red: 0.8, green: 0.5, blue: 0.2)
            ])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 192, height: 128))
            try CIContext().writeTIFFRepresentation(of: image, to: source, format: .RGBA16, colorSpace: space)
            let base: [String: WireValue] = ["auto_exposure": .bool(false), "grain_active": .bool(false), "glare_active": .bool(false)]
            let engine = MobileEngine()
            let first = try await engine.render(url: source, recipe: base)
            try require(first.image.width == 192 && first.image.height == 128, "输入尺寸未保留")
            try require(first.image.colorSpace?.name == CGColorSpace.rommrgb, "预览未标记 ProPhoto")
            checks.append("encoded TIFF input and tagged ProPhoto preview")
            var menuRecipe = base
            menuRecipe["halation_amount"] = .double(4)
            menuRecipe["antihalation_mode"] = .string("profile")
            var previousMenu = try await engine.render(url: source, recipe: menuRecipe)
            for mode in ["none", "weak", "strong", "none", "profile"] {
                menuRecipe["antihalation_mode"] = .string(mode)
                let warm = try await engine.render(url: source, recipe: menuRecipe)
                let fresh = MobileEngine()
                let reference = try await fresh.render(url: source, recipe: menuRecipe)
                try require(warm.resolved["antihalation_mode"]?.stringValue == mode && warm.resolved["halation_amount"]?.doubleValue == 4,
                            "晕光菜单未提交完整最新设置")
                try require(warm.image.dataProvider!.data! as Data == reference.image.dataProvider!.data! as Data,
                            "晕光模式切换后复用了错误的引擎状态")
                try require(warm.image.dataProvider!.data! as Data != previousMenu.image.dataProvider!.data! as Data,
                            "晕光4.0切换模式没有改变图像：" + mode)
                previousMenu = warm
                await fresh.close()
            }
            _ = try await engine.render(url: source, recipe: base)
            checks.append("halation 4.0 profile/high/medium/low transitions refresh pixels and match fresh rendering")
            var familyRecipe = base
            for patch: [String: WireValue] in [
                ["camera_diffusion_active": .bool(true), "camera_diffusion_family": .string("black_pro_mist"), "camera_diffusion_strength": .double(1)],
                ["camera_diffusion_family": .string("glimmerglass")],
                ["camera_diffusion_active": .bool(false)],
                ["enlarger_diffusion_active": .bool(true), "enlarger_diffusion_family": .string("cinebloom"), "enlarger_diffusion_strength": .double(1)],
                ["enlarger_diffusion_family": .string("pro_mist")],
                ["enlarger_diffusion_active": .bool(false)],
                ["camera_filter": .string("w25")], ["camera_filter": .string("")]
            ] {
                familyRecipe.merge(patch) { _, new in new }
                let warm = try await engine.render(url: source, recipe: familyRecipe)
                let fresh = MobileEngine()
                let reference = try await fresh.render(url: source, recipe: familyRecipe)
                try require(warm.image.dataProvider!.data! as Data == reference.image.dataProvider!.data! as Data, "柔化/滤镜菜单增量更新与新建渲染不一致")
                await fresh.close()
            }
            _ = try await engine.render(url: source, recipe: base)
            checks.append("camera/enlarger diffusion families, enable/disable and spectral filter menus match fresh rendering")
            let expectedPrint = try await engine.canvasImage(first.image)
            let beforeDetail = MobileEngine()
            let beforeReference = try await engine.canvasImage(first.original)
            let beforeTile = try await beforeDetail.originalDetail(url: source, recipe: base, geometry: MobileGeometry(),
                viewport: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.4), pixelLongEdge: 192)
            let beforeSize = beforeTile.nativeSize ?? .zero
            let beforeRect = CGRect(x: (beforeTile.rect.minX * beforeSize.width).rounded(), y: (beforeTile.rect.minY * beforeSize.height).rounded(),
                width: CGFloat(beforeTile.image.width), height: CGFloat(beforeTile.image.height))
            let beforeExpected = try MobileDetailRenderer.copy(beforeReference, rect: beforeRect)
            try require(beforeSize == CGSize(width: 192, height: 128) && beforeTile.image.dataProvider!.data! as Data == beforeExpected.dataProvider!.data! as Data,
                        "原图细节坐标/色彩与正常原图不一致")
            await beforeDetail.close()
            checks.append("native original viewport pixels match full camera-rendered before image, including top-left coordinates and P3 output")
            let expectedPrintBytes = expectedPrint.dataProvider!.data! as Data
            for scanStyle in [false, true] {
                let assets = try await engine.developmentAssets(print: first.image, geometry: MobileGeometry(), framed: false, scanStyle: scanStyle)
                let negative = try assets.auditFrame(0), middle = try assets.auditFrame(0.45), finished = try assets.auditFrame(1)
                try require(finished == expectedPrintBytes, "显影动画末帧与正常P3输出不一致")
                try require(negative != finished && middle != negative && middle != finished, "胶片/相纸显影动画未使用真实中间画面")
                try require(assets.duration == (scanStyle ? 0.35 : 2.2), "桌面显影动画节奏不一致")
            }
            let afterScan = try await engine.render(url: source, recipe: base)
            try require(afterScan.image.dataProvider!.data! as Data == first.image.dataProvider!.data! as Data, "胶片扫描动画改变了当前印相配方/输出")
            checks.append("desktop developPaper shader, paper/scan timing, exact P3 endpoint and unchanged engine recipe")
            let tile = try MobileDetailRenderer.copy(first.image, rect: CGRect(x: 20, y: 15, width: 80, height: 60))
            let originalPixels = first.image.dataProvider!.data! as Data
            let tilePixels = tile.dataProvider!.data! as Data
            for row in 0..<60 {
                let start = (row + 15) * first.image.bytesPerRow + 20 * 8
                try require(tilePixels[(row * 80 * 8)..<((row + 1) * 80 * 8)] == originalPixels[start..<(start + 80 * 8)], "细节块坐标/像素发生变化")
            }
            try require(!MobileViewport(rect: .zero, zoom: 8, pixelLongEdge: 12000, previewLongEdge: 3840).needsDetail &&
                MobilePreviewPolicy.nextInteractionEdge(1600, seconds: 0.3) < 1600 &&
                MobilePreviewPolicy.nextInteractionEdge(800, seconds: 0.3) == 800, "动态预览策略或空视口错误")
            try require(MobilePreviewPolicy.fitEdge(pixels: 1800) == 1920 &&
                abs(MobilePreviewPolicy.nativeZoom(nativeLongEdge: 9504, fitLongEdgePoints: 600, displayScale: 3) * 1800 - 9504) < 1e-8 &&
                MobilePreviewPolicy.nativeZoom(nativeLongEdge: 600, fitLongEdgePoints: 400, displayScale: 3) == 0.5,
                "自动适屏/1:1未按实际屏幕像素计算")
            checks.append("viewport detail tiles preserve exact pixels and adaptive interaction policy respects bounds")
            let stripedEngine = MobileEngine()
            for grain in [false, true] {
                var settings = base; settings["grain_active"] = .bool(grain)
                let plain = try await engine.render(url: source, recipe: settings)
                settings["striped"] = .bool(true)
                settings["strip_rows"] = .double(7) // non-dividing strips, not the whole-plane default
                let striped = try await stripedEngine.render(url: source, recipe: settings)
                try require(plain.image.dataProvider!.data! as Data == striped.image.dataProvider!.data! as Data, "条带渲染改变了像素")
            }
            await stripedEngine.close()
            _ = try await engine.render(url: source, recipe: base)
            checks.append("striped and whole-frame output are bit-identical with and without grain")
            for grain in [false, true] {
                let referenceEngine = MobileEngine(), exportEngine = MobileEngine()
                var settings = base; settings["grain_active"] = .bool(grain)
                let reference = try await referenceEngine.render(url: source, recipe: settings)
                settings["_exporting"] = .bool(true); settings["_keepExportSession"] = .bool(true)
                let exported = try await exportEngine.render(url: source, recipe: settings)
                try require(reference.image.dataProvider!.data! as Data == exported.image.dataProvider!.data! as Data, "跳过导出分析改变了图像像素")
                await referenceEngine.close(); await exportEngine.close()
            }
            checks.append("export without unused latitude analysis preserves every pixel, grain on and off")
            try require(first.resolved["print_stock"]?.stringValue == "kodak_supra_endura" && first.resolved["extended_dynamic_range"]?.boolValue == true, "新照片未使用桌面默认相纸/高光扩展")
            try require(abs((first.resolved["m_filter_neutral"]?.doubleValue ?? 0) - 50.73008094647558) < 1e-6, "彩色相纸校准表未保留")
            let canvas = try await engine.canvasImage(first.image)
            try require(canvas.colorSpace?.name == CGColorSpace.displayP3 && canvas.width == first.image.width, "画布未使用桌面 P3 输出变换")
            let bw = try MobileProcessContract.wire(["film_stock": .string("kodak_tri_x_400")], aspect: 1.5)
            try require(bw["grain_amount"]?.doubleValue == 1.7 && bw["grain_sublayers_active"]?.boolValue == false, "黑白胶片默认颗粒倍率/分层与桌面不符")
            var stable = base; stable["exposure_compensation_ev"] = .double(0)
            let grainReference = try await engine.render(url: source, recipe: stable)
            var printOnly = stable; printOnly["print_exposure"] = .double(0.8)
            let reprinted = try await engine.render(url: source, recipe: printOnly)
            try require(reprinted.negativeWasCached, "印相编辑未复用负片")
            printOnly["print_exposure"] = .double(1)
            let restoredPrint = try await engine.render(url: source, recipe: printOnly)
            let referenceBytes = grainReference.image.dataProvider!.data! as Data
            let restoredBytes = restoredPrint.image.dataProvider!.data! as Data
            try require(restoredPrint.negativeWasCached && referenceBytes == restoredBytes, "印相来回调整改变了同一负片")
            checks.append("desktop defaults, full calibration database, P3 shader, B&W grain defaults and cached-negative reprint")
            try require(!(first.latitude?.bins.isEmpty ?? true), "场景宽容度与直方图未接入")
            var controls = base
            controls["camera_diffusion_active"] = .bool(true)
            controls["camera_diffusion_family"] = .string("glimmerglass")
            controls["camera_diffusion_strength"] = .double(0.5)
            controls["enlarger_diffusion_active"] = .bool(true)
            controls["enlarger_diffusion_family"] = .string("cinebloom")
            controls["grain_sublayers_active"] = .bool(true)
            controls["extended_dynamic_range"] = .bool(true)
            controls["_placementHighlight"] = .double(0)
            controls["_placementShadow"] = .double(0)
            let connected = try await engine.render(url: source, recipe: controls)
            try require(connected.resolved["camera_diffusion_family"]?.stringValue == "glimmerglass" && connected.resolved["enlarger_diffusion_active"]?.boolValue == true, "新工艺控件未到达引擎")
            checks.append("scene latitude histogram, capture/enlarger diffusion and client-only recipe fields")
            var edgeRecipe = base
            edgeRecipe["overscan_active"] = .bool(true)
            edgeRecipe["overscan_format"] = .string("120_6x6")
            edgeRecipe["overscan_mode"] = .string("strip")
            edgeRecipe["overscan_fog"] = .double(1)
            let edgeResult = try await engine.render(url: source, recipe: edgeRecipe)
            var bandedEdgeRecipe = edgeRecipe
            bandedEdgeRecipe["_exporting"] = .bool(true)
            let bandedEdge = try await engine.render(url: source, recipe: bandedEdgeRecipe)
            try require(edgeResult.image.width == bandedEdge.image.width && edgeResult.image.height == bandedEdge.image.height &&
                        edgeResult.image.dataProvider!.data! as Data == bandedEdge.image.dataProvider!.data! as Data,
                        "片边分条处理改变了画布尺寸/像素")
            checks.append("overscan expanded canvas survives the mobile export/detail striped path without changing pixels")
            try require(edgeResult.original.width == edgeResult.original.height, "片边开启后没有按 6×6 片门准备输入")
            try require(edgeResult.image.width != edgeResult.original.width || edgeResult.image.height != edgeResult.original.height, "片边没有扩大实际渲染画布")
            let cropSource = try await engine.cropCanvasImage(url: source, recipe: edgeRecipe, megapixels: 2)
            try require(cropSource.width == 192 && cropSource.height == 128, "片边开启时裁切未使用完整原始画面")
            let edgeReset = try await engine.render(url: source, recipe: base)
            try require(edgeReset.image.width == first.image.width && edgeReset.image.height == first.image.height, "关闭片边未恢复原画幅")
            checks.append("6x6 film gate crops source before exposure, edge expands rendered canvas and disabling restores frame")
            for format in ["135", "135_half", "120_645", "135_xpan"] {
                edgeRecipe["overscan_format"] = .string(format)
                let turnedEdge = try await engine.render(url: source, recipe: edgeRecipe, geometry: MobileGeometry(quarterTurns: 1, aspect: 0))
                try require(turnedEdge.original.height > turnedEdge.original.width, "片门没有保留旋转后的纵向输入")
            }
            checks.append("135, half-frame, 645 and XPan gates accept correctly prepared portrait input")
            if let latitude = first.latitude {
                try require(abs(latitude.below + latitude.within + latitude.above - 1) < 0.001 && !latitude.separation.isEmpty, "宽容度占比或层次带没有接入")
            }
            let rulerRanges: [(String, ClosedRange<Double>)] = [
                ("exposure_compensation_ev", -4...4), ("camera_diffusion_strength", 0.125...2), ("camera_diffusion_range", 0.5...2),
                ("enlarger_diffusion_strength", 0.125...2), ("enlarger_diffusion_range", 0.5...2),
                ("_grainAmount", 0...2), ("grain_size_scale", 0.5...2), ("_grainSoftness", 0...2),
                ("halation_amount", 0...4), ("halation_scatter_amount", 0...1), ("density_curve_gamma", 0.5...1.5),
                ("dir_couplers_amount", 0...1.4), ("print_contrast", 0.7...1.3), ("y_filter_shift", -50...50), ("m_filter_shift", -50...50),
                ("preflash_exposure", 0...0.05), ("_scannerStrength", 0...2), ("glare_amount", 0...4),
                ("overscan_frame_number", 0...99), ("overscan_fog", 0...4), ("overscan_leaks", 0...4),
                ("date_imprint_ev", -2...8), ("date_imprint_size", 0.4...3), ("date_imprint_inset_x", 0...30), ("date_imprint_inset_y", 0...30)
            ]
            var rulerCases: [MobileRulerChecks.Case] = []
            for (key, range) in rulerRanges {
                guard let baseline = MobileProcessContract.clientDefaults[key]?.doubleValue ?? MobileProcessContract.defaults[key]?.doubleValue else { throw MobileFailure.message("缺少刻度尺默认值：" + key) }
                rulerCases.append(.init(name: key, range: range, baseline: baseline, step: MobileProcessContract.steps[key], resolution: key == "overscan_frame_number" ? 1 : key == "preflash_exposure" ? 0.001 : 0.01))
            }
            rulerCases += [
                .init(name: "RAW as-shot temperature", range: 2000...12000, baseline: 4041, step: 100, resolution: 1),
                .init(name: "RAW as-shot tint", range: -150...150, baseline: 17.3, step: 5),
                .init(name: "frame millimetres", range: 4...200, baseline: 24, resolution: 0.1),
                .init(name: "frame centimetres", range: 0.4...20, baseline: 2.4, resolution: 0.1),
                .init(name: "frame inches", range: (4 / 25.4)...(200 / 25.4), baseline: 24 / 25.4, resolution: 0.001),
                .init(name: "print brightness", range: -3...3, baseline: 0, step: 0.25),
                .init(name: "placement", range: 0...12, baseline: 0, step: 0.25),
                .init(name: "straighten", range: -45...45, baseline: 0, step: 0.1, resolution: 0.1),
                .init(name: "JPEG quality", range: 10...100, baseline: 95, step: 1, resolution: 1),
                .init(name: "export long edge", range: 256...12000, baseline: 4000, step: 100, resolution: 1)
            ]
            try MobileRulerChecks.run(rulerCases)
            checks.append("all 35 ruler configurations: visual defaults, independent numeric precision, unchanged release value and fine accessibility steps; 0.85 never jumps to 1")
            let mono = catalogForFilters()
            try require(mono, "材料分类没有按目录语义筛选")
            checks.append("ruler snapping across signed/fractional ranges, latitude shares/separation and material filters")
            let layout = WorkspaceLayout(size: CGSize(width: 951, height: 669), safe: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 46), exclusions: [CGRect(x: 905, y: 120, width: 46, height: 300)], showsMedia: true, showInspector: true, materialBrowser: false, dockFraction: 0.42)
            try require(layout.inspector.maxX < 905 && layout.inspector.maxY >= 650 && layout.inspector.minY < 80, "参数列没有左移避让并保留完整高度")
            try require(layout.media.maxX < layout.inspector.minX && layout.navigation.minX == 0 && layout.navigation.width == 951, "主面板与底部条布局错误")
            checks.append("full-width navigation, full-height inspector beside reserved sidebar and independent filmstrip")
            for size in [CGSize(width: 895, height: 669), CGSize(width: 613, height: 951)] {
                // The native bar's reserved width has already been removed
                // from the content proposal; do not reserve a second sidebar.
                let duo = WorkspaceLayout(size: size, safe: EdgeInsets(), exclusions: [], showsMedia: true, systemBars: true, showInspector: true, materialBrowser: true, dockFraction: 0.42)
                try require(!duo.usesTwoNavigationRows && duo.navigation.height == 0, "Duo 仍为自绘顶栏保留空间")
                try require(duo.usesSidebar && duo.media.minX == EditorDesign.gutter && duo.media.maxX < duo.inspector.minX && duo.inspector.maxX < size.width, "内容区重复增加侧栏或超出系统安全区")
            }
            let bar = CGRect(x: 879, y: 280, width: 48, height: 365)
            let aligned = WorkspaceLayout(size: CGSize(width: 951, height: 669), safe: EdgeInsets(), exclusions: [], showsMedia: true, systemBars: true, systemBarFrame: bar, showInspector: true, materialBrowser: false, dockFraction: 0.42)
            try require(aligned.inspector.maxY == bar.maxY && aligned.media.maxY == bar.maxY, "面板未与系统导航表面底部对齐")
            try require(bar.minX - aligned.inspector.maxX == EditorDesign.gutter && aligned.inspector.minX - aligned.media.maxX == EditorDesign.gutter, "系统栏间距与面板间距不一致")
            let tablet = WorkspaceLayout(size: CGSize(width: 1194, height: 834), safe: EdgeInsets(), exclusions: [], showsMedia: true, systemBars: false, showInspector: true, materialBrowser: true, dockFraction: 0.42)
            try require(!tablet.usesTwoNavigationRows, "iPad 未保留横向工艺顶栏")
            checks.append("native-bar-sized Duo content has no custom stage rail and preserves iPad horizontal navigation")
            let cameraRegion = CGRect(x: 790, y: 0, width: 161, height: 100)
            let cameraLayout = WorkspaceLayout(size: CGSize(width: 951, height: 669), safe: EdgeInsets(), exclusions: [cameraRegion], showsMedia: true, systemBars: true, showInspector: true, materialBrowser: false, dockFraction: 0.42)
            try require(!cameraLayout.navigationContent.intersects(cameraRegion) && cameraLayout.navigationContent.maxX <= cameraRegion.minX - EditorDesign.gutter, "顶部动作仍位于相机预留区域内")
            checks.append("top action band avoids active camera exclusions independently of native safe-area insets")
            var changed = base; changed["exposure_compensation_ev"] = .double(1)
            let edited = try await engine.render(url: source, recipe: changed)
            let firstData = first.image.dataProvider!.data! as Data
            try require(firstData != edited.image.dataProvider!.data! as Data, "曝光没有改变输出")
            checks.append("live film exposure changes pixels")
            let reset = try await engine.render(url: source, recipe: base)
            try require(reset.resolved["exposure_compensation_ev"]?.doubleValue == first.resolved["exposure_compensation_ev"]?.doubleValue,
                        "移除覆盖后曝光未恢复默认值")
            try require(firstData == reset.image.dataProvider!.data! as Data, "移除覆盖未恢复原始输出")
            checks.append("removed override restores defaults and exact deterministic output")
            await engine.close()
            let reopened = try await engine.render(url: source, recipe: base)
            try require(firstData == reopened.image.dataProvider!.data! as Data, "重新打开后的配方输出改变")
            checks.append("session teardown and reopen preserve pixels")
            let catalog = StockCatalog.shared
            try require(!catalog.films.isEmpty && !catalog.papers.isEmpty, "随包胶片目录为空")
            for id in ["ilford_hp5_plus_400", "fujifilm_provia_100f"] {
                // Use real catalogue identities; changing stock must not retain
                // a previous material's resolved defaults.
                guard let film = catalog.stock(id) else { throw MobileFailure.message("随包目录缺少 \(id)") }
                var recipe = base
                recipe["film_stock"] = .string(film.id)
                recipe["scan_film"] = .bool(film.isPositive)
                if let paper = film.targetPrint { recipe["print_stock"] = .string(paper) }
                let stockResult = try await engine.render(url: source, recipe: recipe)
                try require(stockResult.resolved["film_stock"]?.stringValue == film.id, "胶片切换没有生效")
            }
            checks.append("bundled catalogue, monochrome product profile and reversal-film switching")
            let geometry = MobileGeometry(quarterTurns: 1, aspect: 1)
            let cropped = try geometry.apply(to: first.image)
            try require(cropped.width == cropped.height, "旋转裁切比例错误")
            checks.append("rotation and aspect crop")
            for format in MobileExportFormat.allCases where format != .di {
                let file = try await engine.export(url: source, recipe: base, geometry: geometry, format: format)
                guard let input = CGImageSourceCreateWithURL(file as CFURL, nil),
                      let output = CGImageSourceCreateImageAtIndex(input, 0, nil),
                      let properties = CGImageSourceCopyPropertiesAtIndex(input, 0, nil) as? [String: Any] else {
                    throw MobileFailure.message("无法读回导出文件")
                }
                try require(output.width == cropped.width && output.height == cropped.height, "导出裁切与预览不一致")
                try require(properties[kCGImagePropertyProfileName as String] != nil, "导出缺少颜色配置")
                if format == .tiff { try require(output.bitsPerComponent == 16, "TIFF 未保留 16-bit") }
                checks.append("\(format.rawValue) export decode, geometry and ICC")
                try FileManager.default.removeItem(at: file)
            }
            var options = MobileExportRecipe(); options.format = .tiff; options.embedsPreview = true
            let previewFiles = try await engine.exportFiles(url: source, recipe: base, geometry: MobileGeometry(), options: options, stem: "preview-test")
            let previewSource = CGImageSourceCreateWithURL(previewFiles[0] as CFURL, nil)!
            try require(CGImageSourceGetCount(previewSource) == 2, "TIFF 预览页没有写入")
            try? FileManager.default.removeItem(at: previewFiles[0].deletingLastPathComponent())
            options.format = .di; options.embedsPreview = false
            let diFiles = try await engine.exportFiles(url: source, recipe: base, geometry: MobileGeometry(), options: options, stem: "DI-test")
            let diSource = CGImageSourceCreateWithURL(diFiles[0] as CFURL, nil)!
            let diProps = CGImageSourceCopyPropertiesAtIndex(diSource, 0, nil) as? [String: Any] ?? [:]
            try require(diFiles.count == 3 && diFiles.dropFirst().allSatisfy { $0.pathExtension == "cube" } && CGImageSourceGetCount(diSource) == 2, "数字中间片主文件、视图 LUT 或预览缺失")
            try require((diProps[kCGImagePropertyDepth as String] as? Int) == 16 && diProps[kCGImagePropertyProfileName as String] == nil, "Cineon 主文件必须为16位且不嵌入 ICC")
            try? FileManager.default.removeItem(at: diFiles[0].deletingLastPathComponent())
            checks.append("TIFF opt-in preview page and untagged 16-bit Cineon master with two view LUTs")
            let unavailable = directory.appendingPathComponent("missing.raw")
            do {
                _ = try await engine.render(url: unavailable, recipe: base)
                throw MobileFailure.message("缺失输入没有报错")
            } catch let error as MobileFailure {
                try require(error.localizedDescription != "缺失输入没有报错", error.localizedDescription)
            }
            await engine.close()
            checks.append("missing input reports an error")
            try await importInteractionCheck(source: source)
            checks.append("import excludes selection and editing until first preview completes")
            try await documentChecks(source: source)
            checks.append("per-photo edits, preview setting persistence, batch JPG share/folder collision policy and fresh session cleanup")
            engine.workGate.setActive(false)
            do {
                _ = try await engine.render(url: source, recipe: base)
                throw MobileFailure.message("后台状态仍允许启动渲染")
            } catch is CancellationError { }
            checks.append("inactive scene rejects new GPU work")
            try JSONSerialization.data(withJSONObject: ["passed": true, "checks": checks], options: [.prettyPrinted, .sortedKeys]).write(to: reportURL, options: .atomic)
            return source
        } catch {
            try? JSONSerialization.data(withJSONObject: ["passed": false, "checks": checks, "error": error.localizedDescription], options: [.prettyPrinted, .sortedKeys]).write(to: reportURL, options: .atomic)
            throw error
        }
    }
    private static func catalogForFilters() -> Bool {
        let stocks = StockCatalog.shared.films
        return stocks.filter { MobileMaterialFilter.positive.includes($0, favorites: [], recent: []) }.allSatisfy(\.isPositive) &&
            stocks.filter { MobileMaterialFilter.monochrome.includes($0, favorites: [], recent: []) }.allSatisfy(\.isMonochrome) &&
            MobileMaterialFilter.allCases.allSatisfy { filter in
                stocks.filter(\.isExperimental).allSatisfy { stock in
                    !filter.includes(stock, favorites: [stock.id], recent: [stock.id])
                }
            } && stocks.contains { !$0.isExperimental && MobileMaterialFilter.all.includes($0, favorites: [], recent: []) }
    }
    @MainActor private static func importInteractionCheck(source: URL) async throws {
        let folder = URL.temporaryDirectory.appendingPathComponent("DocumentSmoke-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let document = MobileDocument(directory: folder)
        await document.importFiles([source, source]).value
        for _ in 0..<200 {
            if !document.busy && !document.resolved.isEmpty { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard let selected = document.selection, let other = document.photos.last?.id else { throw MobileFailure.message("导入互斥测试缺少输入") }
        let previous = document.current?.recipe
        guard document.beginPhotoImport(total: 2), document.isInteractionLocked,
              document.operation?.kind == .importing, document.operation?.stage == .receiving else { throw MobileFailure.message("图库读取阶段没有立即锁定界面") }
        document.photoImportProgress(index: 2, total: 2, name: "Second.RAW")
        guard document.operation?.filename == "Second.RAW", document.operation?.index == 2 else { throw MobileFailure.message("图库读取进度未更新") }
        document.finishPhotoImportWithoutFiles()
        guard !document.isInteractionLocked, !document.busy else { throw MobileFailure.message("图库无有效结果未解除锁定") }
        document.setActive(false)
        let pending = document.importFiles([source])
        let duplicate = document.importFiles([source])
        guard document.isInteractionLocked, document.operation?.stage == .copying else { throw MobileFailure.message("文件导入没有立即锁定界面") }
        document.select(other)
        document.set("exposure_compensation_ev", .double(2))
        let excluded = document.selection == selected && document.current?.recipe == previous
        await pending.value; await duplicate.value
        guard document.isInteractionLocked, document.operation?.stage == .preview,
              document.photos.count == 3 else { throw MobileFailure.message("首张预览前提前解锁，或重复导入未被拒绝") }
        document.setActive(true)
        for _ in 0..<200 {
            if !document.busy { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard !document.isInteractionLocked, document.image != nil else { throw MobileFailure.message("预览完成后未解除锁定") }
        let selection = document.selection
        await document.importFiles([folder.appendingPathComponent("Missing.RAW")]).value
        guard !document.isInteractionLocked, !document.busy, document.selection == selection, document.error != nil else { throw MobileFailure.message("导入失败未正确解除锁定") }
        document.setActive(false)
        guard excluded else { throw MobileFailure.message("导入期间仍允许切换照片或修改参数") }
    }

    @MainActor private static func documentChecks(source: URL) async throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("DocumentSmoke-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults.standard
        let preferenceData = defaults.data(forKey: "mobile.preferences.v1")
        let exportData = defaults.data(forKey: "mobile.export.current")
        defer {
            if let preferenceData { defaults.set(preferenceData, forKey: "mobile.preferences.v1") } else { defaults.removeObject(forKey: "mobile.preferences.v1") }
            if let exportData { defaults.set(exportData, forKey: "mobile.export.current") } else { defaults.removeObject(forKey: "mobile.export.current") }
        }
        let preferences = MobilePreferences()
        preferences.values.previewEdge = 1080
        preferences.values.lowerPreviewInLowPower = false
        let restoredPreferences = MobilePreferences()
        guard restoredPreferences.values.previewEdge == 1080, abs(restoredPreferences.megapixels(aspect: 1.5) - 0.7776) < 1e-8 else { throw MobileFailure.message("预览设置未保存或未计算实际渲染尺寸") }
        let document = MobileDocument(directory: directory)
        document.setActive(false)
        await document.importFiles([source, source]).value
        document.setActive(true)
        for _ in 0..<200 {
            if !document.busy && !document.isInteractionLocked { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard !document.isInteractionLocked else { throw MobileFailure.message("导入未完成预览") }
        if !UIAccessibility.isReduceMotionEnabled {
            guard let assets = document.development, !document.developmentRunning else { throw MobileFailure.message("首次印相未等待胶片") }
            document.printNegative()
            guard document.developmentRunning else { throw MobileFailure.message("轻点画布未开始印相") }
            document.finishDevelopment(UUID())
            guard document.development?.id == assets.id else { throw MobileFailure.message("过期动画回调清除了当前画面") }
            document.finishDevelopment(assets.id)
            document.schedule()
            for _ in 0..<200 { if !document.busy { break }; try await Task.sleep(for: .milliseconds(50)) }
            guard document.development == nil else { throw MobileFailure.message("后续预览重复播放首次印相") }
        }
        document.beginParameterInteraction()
        document.set("halation_amount", .double(4))
        document.setDiscrete("_halation", .string("none"))
        for _ in 0..<200 { if !document.busy { break }; try await Task.sleep(for: .milliseconds(50)) }
        guard document.resolved["antihalation_mode"]?.stringValue == "none", document.resolved["halation_amount"]?.doubleValue == 4,
              document.resolved["_draft"]?.boolValue != true else { throw MobileFailure.message("菜单没有结束被取消的刻度尺交互并更新完整预览") }
        document.undo()
        guard document.current?.recipe["halation_amount"]?.doubleValue == 4, document.current?.recipe["antihalation_mode"] == nil else { throw MobileFailure.message("菜单与刻度尺被错误合并为一次撤销") }
        document.undo()
        guard document.current?.recipe["halation_amount"] == nil else { throw MobileFailure.message("刻度尺交互没有正确结束") }
        document.set("exposure_compensation_ev", .double(0.7))
        for _ in 0..<200 { if !document.busy { break }; try await Task.sleep(for: .milliseconds(50)) }
        document.set("exposure_compensation_ev", .double(1.2))
        document.resetKeys(["exposure_compensation_ev"])
        guard document.value("exposure_compensation_ev")?.doubleValue == document.defaultNumber("exposure_compensation_ev") else { throw MobileFailure.message("重置先显示上一次值而不是默认值") }
        if let shown = document.image {
            document.detailTile = MobileDetailTile(image: shown, rect: CGRect(x: 0, y: 0, width: 1, height: 1))
            document.compareCanvas(true)
            guard document.showOriginal else { throw MobileFailure.message("画布按住未显示原图") }
            document.requestDetail(MobileViewport(rect: CGRect(x: 0, y: 0, width: 1, height: 1), zoom: 1, pixelLongEdge: 192, previewLongEdge: 192))
            guard document.detailTile != nil else { throw MobileFailure.message("短暂对比丢弃了细节缓存") }
            document.compareCanvas(false)
            guard !document.showOriginal else { throw MobileFailure.message("画布松开未恢复处理图") }
            document.detailTile = nil
        }
        guard document.photos.count == 2, let first = document.photos.first, let second = document.photos.last else {
            throw MobileFailure.message("多张照片导入失败")
        }
        document.select(first.id)
        let interactionBefore = document.current?.recipe
        document.beginParameterInteraction()
        for index in 0..<40 { document.set("_grainAmount", .double(Double(index) / 100)) }
        for _ in 0..<200 {
            if document.interactionFrames > 0 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard document.interactionFrames > 0, document.interactionFrames < 40 else { throw MobileFailure.message("交互预览未合并连续输入") }
        document.endParameterInteraction()
        for _ in 0..<200 { if !document.busy { break }; try await Task.sleep(for: .milliseconds(50)) }
        guard document.current?.recipe["_grainAmount"]?.doubleValue == 0.39 else { throw MobileFailure.message("交互预览丢失最后一个值") }
        document.undo()
        guard document.current?.recipe == interactionBefore else { throw MobileFailure.message("一次拖动未合并为一次撤销") }
        var crop = Geometry(); crop.crop = CropRect(x: 0.2, y: 0.1, width: 0.6, height: 0.7)
        document.setGeometry(crop)
        guard let appliedCrop = document.current?.geometry.value,
              abs(appliedCrop.crop.x - 0.2) < 1e-9, abs(appliedCrop.crop.y - 0.1) < 1e-9,
              abs(appliedCrop.crop.width - 0.6) < 1e-9, abs(appliedCrop.crop.height - 0.7) < 1e-9 else { throw MobileFailure.message("裁切未写入当前照片") }
        document.undo()
        guard document.current?.geometry.value.isIdentity == true else { throw MobileFailure.message("裁切撤销未恢复完整画面") }
        document.redo()
        guard document.current?.geometry.value == appliedCrop else { throw MobileFailure.message("裁切重做丢失框选") }
        document.resetStage(.geometry)
        document.set("exposure_compensation_ev", .double(1))
        document.undo()
        guard document.current?.recipe["exposure_compensation_ev"] == nil else { throw MobileFailure.message("撤销未移除参数") }
        document.redo()
        document.select(second.id)
        guard document.current?.recipe["exposure_compensation_ev"] == nil else { throw MobileFailure.message("参数泄漏到另一张照片") }
        document.mark(first.id, rating: 4, flag: "pick")
        guard document.photos.first?.rating == 4 && document.photos.first?.flag == "pick" else { throw MobileFailure.message("评分旗标未生效") }
        document.copySettings(document.photos[0]); document.pasteSettings()
        guard document.current?.recipe["exposure_compensation_ev"]?.doubleValue == 1 else { throw MobileFailure.message("设置粘贴失败") }
        document.setActive(true)
        for _ in 0..<200 {
            if !document.busy && !document.resolved.isEmpty { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard !document.busy && !document.resolved.isEmpty else { throw MobileFailure.message("JPG批量测试预览未完成") }
        document.exportRecipe = MobileExportRecipe()
        document.exportRecipe.naming = "same-name"
        document.export(.jpeg, ids: document.photos.map(\.id))
        let exportRevision = document.revision
        let exportOperation = document.operation?.id
        guard document.operation?.kind == .exporting, document.isInteractionLocked, document.operation?.total == 2 else { throw MobileFailure.message("导出未复用统一进度/锁定状态") }
        document.compareCanvas(true)
        guard !document.showOriginal else { throw MobileFailure.message("导出锁定期间仍可触发画布对比") }
        let selected = document.selection
        let beforeExport = document.current?.recipe
        document.select(first.id); document.set("exposure_compensation_ev", .double(2))
        guard document.selection == selected, document.current?.recipe == beforeExport else { throw MobileFailure.message("导出仍允许切换或编辑") }
        document.releaseMemory() // system warning while a user export is queued
        document.schedule() // foreground/settings refresh must not replace export
        document.setActive(false, background: false) // permission sheet, not background
        document.setActive(true, background: false)
        guard document.busy, document.revision == exportRevision, document.operation?.id == exportOperation else { throw MobileFailure.message("预览回收抢占了导出任务状态") }
        for _ in 0..<200 {
            if !document.delivering { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard !document.delivering, !document.isInteractionLocked, document.exportedFiles.count == 2, Set(document.exportedFiles.map(\.lastPathComponent)).count == 2,
              document.exportedFiles.allSatisfy({ CGImageSourceCreateWithURL($0 as CFURL, nil) != nil }) else { throw MobileFailure.message("批量JPG分享、同名处理或文件写入失败：" + (document.error ?? "未知")) }
        document.clearExport()
        for _ in 0..<200 {
            if !document.busy { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let outputDirectory = directory.appendingPathComponent("Output")
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        document.exportFolder = outputDirectory
        document.exportRecipe.existing = "skip"
        document.export(.jpeg, ids: document.photos.map(\.id))
        for _ in 0..<200 {
            if !document.delivering { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard !document.delivering, !document.isInteractionLocked, try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path).count == 1,
              document.notice?.contains("已导出 1 张") == true else { throw MobileFailure.message("JPG文件夹同名跳过或计数失败") }
        for _ in 0..<200 {
            if !document.busy { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        document.exportFolder = source // a file cannot be an output directory
        document.export(.jpeg, ids: [first.id])
        for _ in 0..<200 {
            if !document.delivering { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard !document.delivering, !document.isInteractionLocked, document.error != nil else { throw MobileFailure.message("导出失败没有解除统一进度锁定") }
        document.setActive(false)
        let firstCopy = document.url(for: first)
        let reopened = MobileDocument(directory: directory)
        reopened.setActive(false)
        guard reopened.photos.isEmpty && reopened.selection == nil && !FileManager.default.fileExists(atPath: firstCopy.path) else { throw MobileFailure.message("新启动未清空临时照片") }
        guard FileManager.default.fileExists(atPath: source.path) else { throw MobileFailure.message("误删原始输入") }
    }

}
#endif
