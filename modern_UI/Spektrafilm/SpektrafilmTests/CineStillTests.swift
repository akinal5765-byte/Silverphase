import XCTest

final class CineStillTests: XCTestCase {
    func testSharedCatalogOffersCineStillWithItsInheritedPairingAndArtwork() throws {
        let stock = try XCTUnwrap(StockCatalog.shared.stock("cinestill_800t"))
        XCTAssertEqual(stock.name, "CineStill 800T")
        XCTAssertTrue(stock.isFilm)
        XCTAssertFalse(stock.isCine)
        XCTAssertFalse(stock.isMonochrome)
        XCTAssertEqual(stock.type, "negative")
        XCTAssertEqual(stock.targetPrint, StockCatalog.shared.stock("kodak_vision3_500t")?.targetPrint)
        XCTAssertEqual(stock.speedLabel, "ISO 800")
        XCTAssertNotNil(stock.packagingArtworkURL)
        XCTAssertTrue(StockCatalog.shared.filmsForPicker.contains { $0.id == stock.id })
    }

    func testHeadroomSurvivesSidecarsAndOldEditsUseEngineDefault() throws {
        var params = FilmParams.default
        params.halationHeadroom = 7
        let data = try JSONEncoder().encode(params)
        XCTAssertEqual(try JSONDecoder().decode(FilmParams.self, from: data).halationHeadroom, 7)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "halationHeadroom")
        XCTAssertEqual(try JSONDecoder().decode(FilmParams.self, from: JSONSerialization.data(withJSONObject: legacy)).halationHeadroom, 4)
        params.halationHeadroom = 99
        XCTAssertEqual(params.wire.first { $0.name == "halation_headroom_ev" }?.value, .double(8))
    }
}
