import XCTest
import Metal
import CoreImage
import ImageIO
import UniformTypeIdentifiers

final class FilmPresentationTests: XCTestCase {
    @MainActor
    func testPreviewTierChangesPreserveTheFilmCanvasSize() throws {
        let session = Session()
        session.displaySourceSize = CGSize(width: 6000, height: 3750)
        var params = session.params
        params.dateBack.active = true
        session.params = params
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let small = try XCTUnwrap(device.makeTexture(descriptor: .texture2DDescriptor(
            pixelFormat: .rgba16Unorm, width: 1280, height: 800, mipmapped: false)))
        let large = try XCTUnwrap(device.makeTexture(descriptor: .texture2DDescriptor(
            pixelFormat: .rgba16Unorm, width: 2560, height: 1600, mipmapped: false)))
        XCTAssertEqual(session.filmCanvasLogicalSize(small, previewEdge: 1280),
                       session.filmCanvasLogicalSize(large, previewEdge: 2560))
        XCTAssertEqual(session.filmCanvasLogicalSize(large),
                       session.filmCanvasLogicalSize(large, previewEdge: session.previewLongEdge),
                       "cached previews use their configured resolution rather than another frame's transient tier")
    }

    func testLegacyParametersAndPresentationDefaults() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(FilmParams.default)) as? [String: Any])
        for key in ["filmEdge", "dateBack", "pairSceneLatitude"] { json.removeValue(forKey: key) }
        let p = try JSONDecoder().decode(FilmParams.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(p.filmEdge.active); XCTAssertFalse(p.dateBack.active)
        XCTAssertEqual(p.fullDelta["overscan_active"], .bool(false))
        XCTAssertEqual(p.fullDelta["date_imprint_active"], .bool(false))
        XCTAssertEqual(p.fullDelta["scene_latitude_split"], .double(0))
    }

    func testAllFormatsAndDateGatesRoundTrip() throws {
        for format in FilmEdgeFormat.allCases {
            var p = FilmParams.default
            p.filmEdge.active = true; p.filmEdge.format = format
            p.filmEdge.frameNumber = 23; p.filmEdge.carrier = "black"
            p.dateBack.active = true; p.dateBack.customText = "'26 10 12"
            let restored = try JSONDecoder().decode(FilmParams.self, from: JSONEncoder().encode(p))
            XCTAssertEqual(restored, p)
            XCTAssertEqual(p.fullDelta["overscan_format"], .string(format.rawValue))
            XCTAssertEqual(p.fullDelta["overscan_carrier"], .string("black"))
            XCTAssertEqual(p.fullDelta["date_imprint_active"], .bool(format.draws(.lcd)))
            XCTAssertEqual(p.delta(from: .default).layers, [.shoot])
        }
    }

    func testCustomEdgeLabelRoundTripsAndOnlyReplacesStockText() throws {
        for format in [FilmEdgeFormat.f135, .f6x6, .f135Half] {
            var automatic = FilmParams.default
            automatic.filmEdge.active = true
            automatic.filmEdge.format = format
            automatic.filmEdge.pair = format == .f135Half
            automatic.filmEdge.frameNumber = 23
            automatic.filmEdge.edgeText = "ORIGINAL STOCK"
            let data = try JSONEncoder().encode(automatic.filmEdge)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertNil(json["customLabel"])
            let priorEdge = try JSONDecoder().decode(FilmEdgeSettings.self, from: data)
            XCTAssertEqual(priorEdge, automatic.filmEdge)

            var custom = automatic
            custom.filmEdge.customLabel = FilmEdgeSettings.editableLabel("roll   2/ ")
            let restored = try JSONDecoder().decode(FilmParams.self, from: JSONEncoder().encode(custom))
            XCTAssertEqual(restored, custom)
            XCTAssertEqual(restored.delta(from: automatic).delta, ["overscan_edge_text": .string("ROLL 2/")])
            XCTAssertEqual(restored.delta(from: automatic).layers, [.shoot])
            XCTAssertNotEqual(Session.printStamp(automatic), Session.printStamp(restored))

            custom.filmEdge.customLabel = "  "
            XCTAssertEqual(custom.fullDelta, automatic.fullDelta)
            XCTAssertEqual(Session.printStamp(custom), Session.printStamp(automatic))
            custom.filmEdge.customLabel = "TAKE 10"
            custom.filmEdge.active = false
            XCTAssertNil(custom.fullDelta["overscan_edge_text"])
        }
        XCTAssertEqual(FilmEdgeSettings.editableLabel("aZ09 +-./x⚡😃%"), "AZ09 +-./X")
        XCTAssertEqual(FilmEdgeSettings.editableLabel("ABCDEFGHIJKLMNOPQRSTUVWXYZ"), "ABCDEFGHIJ")
        XCTAssertNil(FilmEdgeSettings.printableLabel("胶片 🧪"))
    }

    func testFrameAndMarginDateAvailability() {
        var p = FilmParams.default
        p.dateBack.active = true
        XCTAssertTrue(p.dateBack.effective(filmEdge: p.filmEdge))
        p.dateBack.placement = .between
        XCTAssertFalse(p.dateBack.effective(filmEdge: p.filmEdge))
        p.filmEdge.active = true
        XCTAssertTrue(p.dateBack.effective(filmEdge: p.filmEdge))
        p.filmEdge.format = .f6x6
        XCTAssertTrue(p.dateBack.effective(filmEdge: p.filmEdge))
        p.filmEdge.format = .xpan
        XCTAssertFalse(p.dateBack.effective(filmEdge: p.filmEdge))
    }

    func testPairSecondPlacementSwitchesOffWhenLeavingPair() {
        var p = FilmParams.default
        p.filmEdge.active = true; p.filmEdge.format = .f135Half; p.filmEdge.pair = true
        var second = SceneLatitudeSettings(); second.active = true; second.highlightRoom = 2
        p.pairSceneLatitude = second
        XCTAssertEqual(p.fullDelta["scene_latitude_b_active"], .bool(true))
        XCTAssertEqual(p.fullDelta["scene_latitude_b_highlight_room"], .double(2))
        p.filmEdge.pair = false
        XCTAssertEqual(p.fullDelta["overscan_pair"], .bool(false))
        XCTAssertEqual(p.fullDelta["scene_latitude_b_active"], .bool(false))
        XCTAssertEqual(p.fullDelta["scene_latitude_split"], .double(0))
    }

    func testPairReferencesSaveAndItsSourceEditsInvalidateCache() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let left = folder.appending(path: "a.png"), right = folder.appending(path: "b.png")
        try Data([1,2,3]).write(to: left); try Data([4,5,6]).write(to: right)
        var pair = HalfFramePair(folder: folder.path)
        pair.left = .init(url: left); pair.right = .init(url: right)
        pair.left?.exposureEV = 1; pair.right?.sceneLatitude.active = true
        let url = folder.appending(path: "pair.spektrapair")
        try pair.save(to: url)
        XCTAssertEqual(HalfFramePair.load(url), pair)
        let key = CacheKey.sourceIdentity(for: url)
        try Data([7,8,9,10]).write(to: right)
        XCTAssertNotEqual(CacheKey.sourceIdentity(for: url), key)
        XCTAssertEqual(try Data(contentsOf: left), Data([1,2,3]))
        pair.left = .init(url: url)
        try pair.save(to: url)
        XCTAssertNil(HalfFramePair.load(url), "recursive compositions must be refused")
    }

    func testGateCroppingKeepsOrientationAndDoesNotChangeSavedCrop() {
        let linear = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 600, height: 400))
        let d = DecodedImage(linear: linear, display: linear, pixelSize: linear.extent.size, isRAW: false,
                             sourceURL: URL(fileURLWithPath: "/tmp/input.tif"), asShotTemperature: nil, asShotTint: nil)
        for format in FilmEdgeFormat.allCases {
            var p = FilmParams.default; p.filmEdge.active = true; p.filmEdge.format = format
            let image = FilmCanvasInput.image(d, params: p, geometry: .default)
            // Core Image rounds fractional crop bounds to enclosing whole pixels.
            let aspect = format.gateMM.long / format.gateMM.short
            XCTAssertEqual(image.extent.width, image.extent.height * aspect, accuracy: 1 + aspect)
            XCTAssertLessThanOrEqual(image.extent.width, 600)
            XCTAssertLessThanOrEqual(image.extent.height, 400)
        }
        XCTAssertEqual(FilmCanvasInput.image(d, params: .default, geometry: .default).extent, linear.extent)
    }

    func testPairLayoutAndExposureAreIndependent() {
        for turned in [false, true] {
            let layout = HalfFramePair.layout(holeHeight: 240, spacingMM: 1, turned: turned)
            XCTAssertEqual(turned ? layout.size.height : layout.size.width, 370)
            let piece = CIImage(color: CIColor(red: 0.1, green: 0.1, blue: 0.1)).cropped(to: CGRect(origin: .zero, size: layout.size))
            let result = PairComposer.exposed(piece, layout: layout, stops: [.left: 1])
            func pixel(_ side: HalfFramePair.Side) -> Float {
                let r = layout.rect(side)
                var bytes = [Float](repeating: 0, count: 4)
                bytes.withUnsafeMutableBytes {
                    ImageDecoder.context.render(result, toBitmap: $0.baseAddress!, rowBytes: 16,
                        bounds: CGRect(x: r.midX, y: layout.size.height - r.midY, width: 1, height: 1),
                        format: .RGBAf, colorSpace: ImageDecoder.linearProPhoto)
                }
                return bytes[1]
            }
            XCTAssertEqual(pixel(.left) / pixel(.right), 2, accuracy: 0.01)
        }
    }

    @MainActor
    func testPresentationControlsRenderOnCanvasWithoutExport() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "preview.tif")
        try PortTestFrame.write(to: url)
        let session = Session()
        session.open(urls: [url])
        func waitFor(_ condition: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(30)
            while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
            XCTAssertTrue(condition(), "a preview should arrive without exporting")
        }
        try await waitFor { session.renderer.live != nil && session.serviceSessionIDForExport != nil && !session.busy }
        let original = try XCTUnwrap(session.renderer.live)
        var p = session.params
        p.filmEdge.active = true
        p.dateBack.active = true
        p.dateBack.customText = "'26 10 12"
        session.params = p
        try await waitFor { session.renderer.live != nil && session.renderer.live !== original && session.serviceSessionIDForExport != nil && !session.busy }
        let edged = try XCTUnwrap(session.renderer.live)
        XCTAssertGreaterThan(Double(edged.height) / Double(edged.width), Double(original.height) / Double(original.width))

        let pairURL = folder.appending(path: "preview.spektrapair")
        var pair = HalfFramePair(folder: folder.path)
        pair.left = .init(url: url); pair.right = .init(url: url); pair.onStrip = true
        try pair.save(to: pairURL)
        var saved = Sidecar(); saved.params = session.params
        saved.params.filmEdge.format = .f135Half; saved.params.filmEdge.pair = true
        try saved.save(for: pairURL)
        session.open(urls: [pairURL])
        try await waitFor { session.selection == pairURL && session.renderer.live != nil && session.serviceSessionIDForExport != nil && !session.busy }
        XCTAssertNotNil(session.halfFramePair)
        XCTAssertTrue(session.params.filmEdge.pair)
        let previous = try XCTUnwrap(session.renderer.live)
        session.updateHalfFramePair { $0.right?.exposureEV = -1 }
        try await waitFor { session.renderer.live != nil && session.renderer.live !== previous && session.serviceSessionIDForExport != nil && !session.busy }
    }

    @MainActor
    func testCustomEdgeLabelChangesTheSameStripInPreviewAndFullTIFF() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let oldPreview = UserDefaults.standard.object(forKey: Session.previewEdgeKey)
        defer {
            try? FileManager.default.removeItem(at: folder)
            UserDefaults.standard.set(oldPreview, forKey: Session.previewEdgeKey)
        }
        let photo = folder.appending(path: "stock.tif")
        try PortTestFrame.write(to: photo, width: 1400, height: 1200)
        let mediumFormat = folder.appending(path: "medium.tif")
        try FileManager.default.copyItem(at: photo, to: mediumFormat)
        let pairURL = folder.appending(path: "stock.spektrapair")
        var pair = HalfFramePair(folder: folder.path)
        pair.left = .init(url: photo); pair.right = .init(url: photo); pair.onStrip = true
        try pair.save(to: pairURL)

        let session = Session()
        session.setPreviewLongEdge(1080)
        session.beginBatchExport() // Disable the background full-canvas ladder, not preview rendering.
        defer { session.endBatchExport() }
        let rgb = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let readback = CIContext(mtlDevice: session.renderer.device)
        func pixels(_ image: CIImage) -> (w: Int, h: Int, bytes: [UInt8]) {
            let w = Int(image.extent.width), h = Int(image.extent.height)
            var bytes = [UInt8](repeating: 0, count: w * h * 4)
            bytes.withUnsafeMutableBytes { ptr in
                readback.render(image, toBitmap: ptr.baseAddress!, rowBytes: w * 4,
                                bounds: image.extent, format: .RGBA8, colorSpace: rgb)
            }
            return (w, h, bytes)
        }
        func compare(_ a: (w: Int, h: Int, bytes: [UInt8]), _ b: (w: Int, h: Int, bytes: [UInt8])) {
            XCTAssertEqual(a.w, b.w); XCTAssertEqual(a.h, b.h)
            guard a.w == b.w, a.h == b.h else { return }
            var changedOnEdge = 0
            var changedInPicture = 0
            for y in 0..<a.h {
                for x in 0..<a.w {
                    let i = 4 * (y * a.w + x)
                    guard abs(Int(a.bytes[i]) - Int(b.bytes[i])) > 2 else { continue }
                    if y < a.h / 8 || y >= 7 * a.h / 8 { changedOnEdge += 1 }
                    if y > a.h / 3 && y < 2 * a.h / 3 { changedInPicture += 1 }
                }
            }
            XCTAssertGreaterThan(changedOnEdge, 10, "stock lettering should visibly change in the rebate")
            XCTAssertEqual(changedInPicture, 0, "the exposed photos should not change")
        }
        func render(_ url: URL, after preceding: MTLTexture?) async throws ->
            (MTLTexture, (w: Int, h: Int, bytes: [UInt8]), (w: Int, h: Int, bytes: [UInt8])) {
            let deadline = Date().addingTimeInterval(60)
            while Date() < deadline {
                if session.selection == url, let live = session.renderer.live, live !== preceding,
                   let id = session.serviceSessionIDForExport, !session.busy {
                    let workingSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.rommrgb))
                    let preview = try XCTUnwrap(CIImage(mtlTexture: live, options: [.colorSpace: workingSpace]))
                    let previewPixels = pixels(preview)
                    var recipe = ExportRecipe()
                    recipe.format = .tiff; recipe.colorSpace = .sRGB
                    recipe.folder = .fixed(path: folder.appending(path: "out").path)
                    recipe.subfolder = ""; recipe.existing = .overwrite
                    let context = NamingRule.Context(originalName: url.lastPathComponent,
                        filmStock: session.params.filmStock, printStock: session.params.printStock,
                        pixelSize: preview.extent.size, counter: 1, date: Date())
                    let outcome = try await Exporter.export(session: session, recipe: recipe, context: context, sessionID: id)
                    let file = try XCTUnwrap(outcome.urls.first)
                    let source = try XCTUnwrap(CGImageSourceCreateWithURL(file as CFURL, nil))
                    let full = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
                    XCTAssertGreaterThan(max(full.width, full.height), max(live.width, live.height))
                    return (live, previewPixels, pixels(CIImage(cgImage: full)))
                }
                try await Task.sleep(for: .milliseconds(25))
            }
            throw NSError(domain: "FilmPresentationTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No settled preview: \(session.status)"])
        }

        let examples: [(URL, FilmEdgeFormat, String)] = [
            (photo, .f135, "kodak_gold_200"), (mediumFormat, .f6x6, "fujifilm_pro_400h"),
            (pairURL, .f135Half, "kodak_gold_200"),
        ]
        for (url, format, stock) in examples {
            let isPair = format == .f135Half
            var saved = Sidecar()
            saved.params.filmStock = stock
            saved.params.autoExposure = false
            saved.params.grainActive = false
            saved.params.halationActive = false
            saved.params.glareActive = false
            saved.params.filmEdge.active = true
            saved.params.filmEdge.format = format
            saved.params.filmEdge.pair = isPair
            saved.params.filmEdge.seeded = true
            saved.params.filmEdge.frameNumber = 23
            try saved.save(for: url)
            let previous = session.renderer.live
            session.open(urls: [url])
            let (automatic, previewA, fullA) = try await render(url, after: previous)

            var params = session.params
            params.filmEdge.customLabel = "ROLL 24"
            session.params = params
            let (_, previewB, fullB) = try await render(url, after: automatic)
            compare(previewA, previewB)
            compare(fullA, fullB)
            XCTAssertEqual(session.params.filmEdge.frameNumber, 23)
            XCTAssertEqual(session.params.filmEdge.pair, isPair)
            session.flushSave()
            XCTAssertEqual(Sidecar.load(for: url)?.params.filmEdge.customLabel, "ROLL 24")
        }
    }

    func testEXIFDateAndMarksMatchUpstream() {
        XCTAssertNil(ShootingData.day(""))
        XCTAssertEqual(ShootingData.day("2026:10:12 08:00:00")?.day, 12)
        XCTAssertEqual(DateBackSettings.format(year: 2026, month: 10, day: 12, order: .japan), "'26 10 12")
        XCTAssertEqual(Session.edgeText(for: StockCatalog.shared.stock("kodak_tri_x_400")), "KODAK 400TX")
        XCTAssertEqual(Session.edgeText(for: StockCatalog.shared.stock("fujifilm_provia_100f")), "FUJI RDPIII")
    }
}
