import XCTest
import CoreImage
import ImageIO
import UniformTypeIdentifiers

final class FilmPresentationTests: XCTestCase {
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

    func testEXIFDateAndMarksMatchUpstream() {
        XCTAssertNil(ShootingData.day(""))
        XCTAssertEqual(ShootingData.day("2026:10:12 08:00:00")?.day, 12)
        XCTAssertEqual(DateBackSettings.format(year: 2026, month: 10, day: 12, order: .japan), "'26 10 12")
        XCTAssertEqual(Session.edgeText(for: StockCatalog.shared.stock("kodak_tri_x_400")), "KODAK 400TX")
        XCTAssertEqual(Session.edgeText(for: StockCatalog.shared.stock("fujifilm_provia_100f")), "FUJI RDPIII")
    }
}
