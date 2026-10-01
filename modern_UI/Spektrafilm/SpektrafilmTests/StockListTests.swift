//  StockListTests.swift — the film and print lists after v3 took their well
//  away, and the two rules that replaced the one this file inherited.
//
//  ## What happened to the odd-row rule
//
//  `LayoutTests.testStockListShowsAnOddNumberOfRows` asserted that each list
//  showed an **odd** number of rows, and it was a real rule with a real
//  defect behind it: the list centres its selected row, which puts that row's
//  centre on the viewport's centre, so rows landed on the viewport's edges
//  only with a whole number of them either side of the middle one. At an even
//  count every row sat half a row out of register and the well's 11.5 pt
//  corner radius cut the first and last rows through the glyphs. The film
//  list shipped at 6 and did exactly that.
//
//  v3 removes both halves of it. There is **no well** — the rows sit directly
//  on the rail, so there is no corner to cut with — and the lists are
//  **grouped**, so a viewport holding a caption and four rows cannot be
//  described by the parity of a row count at all. Handoff §3 says so
//  directly: "a grouped implementation must use complete row alignment and
//  update that assumption rather than blindly reuse the odd-count rule."
//
//  So the surviving rule is the one underneath it — the viewport is a whole
//  multiple of the row pitch, so whatever is scrolled to rests on a row
//  boundary — and it is asserted here rather than as a parity check.
//
//  `LayoutTests.testWellPaddingClearsItsOwnCornerRadius` is gone with the
//  same drawing. `wellVPadding` and `wellRadius` still exist, but the only
//  thing that reads them now is the export page's recipe list, whose own
//  drawing has not been translated; asserting them against the editor's
//  lists would be asserting a relationship no editor view has any more.

import SwiftUI
import XCTest
import ImageIO

@MainActor
final class StockListTests: XCTestCase {

    /// A list's viewport is a whole number of rows.
    func testEveryListViewportRestsOnARowBoundary() {
        let pitch = Theme.Metric.listRowHeight
        for (name, rows) in [("film", FilmSection.wellRows),
                             ("print", PrintProfileSection.wellRows)] {
            XCTAssertGreaterThan(rows, 0, "\(name)")
            let height = pitch * CGFloat(rows)
            XCTAssertEqual(height.truncatingRemainder(dividingBy: pitch), 0, accuracy: 0.001,
                           "the \(name) list's viewport would present a part row at its edge")
        }
    }

    /// A list is **exactly** its rows tall — measured on the real view, not
    /// recomputed from the same tokens the view uses.
    ///
    /// This is the assertion that catches the padding coming back. The old
    /// 8 pt of `wellVPadding` existed to hold rows off a corner radius; with
    /// the plate gone it is a gap that floats the first row away from the
    /// section header above it *and* breaks the boundary rule above, because
    /// a viewport of `pitch * n + 16` does not rest on a row. Restating the
    /// arithmetic here would pass either way — hosting the view is what makes
    /// it evidence.
    func testAListIsExactlyItsRowsTall() {
        let pitch = Theme.Metric.listRowHeight
        let rows = (0..<6).map { StockList.Row(id: "s\($0)", name: "Stock \($0)") }
        let list = StockList(rows: rows, selected: "s2",
                             visibleRows: FilmSection.wellRows) { _ in }
        let host = NSHostingView(rootView: list)
        host.frame = CGRect(x: 0, y: 0, width: Theme.Metric.leftPanelWidth, height: 600)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.height,
                       pitch * CGFloat(FilmSection.wellRows), accuracy: 0.5,
                       "a list's height is its rows and nothing else")
    }

    /// **The whole catalogue is on offer, grouped.**
    ///
    /// Handoff §8.6: v3's illustration shows 3 positive and 4 negative rows,
    /// and those are the counts of a *viewport*, not a filter or permission
    /// to drop entries. The grouping is taken from the catalogue's `type`
    /// rather than from names or the artwork's order.
    func testFilmGroupingKeepsTheWholeCatalogue() throws {
        let catalog = StockCatalog.shared
        // A catalogue is needed for this to say anything; the bundle carries
        // one, and an empty one would make every assertion below vacuous —
        // `try`, not `try?`, because a discarded skip is a test that passes
        // on no evidence.
        try XCTSkipIf(catalog.films.isEmpty, "no catalogue in the test bundle")
        let grouped = catalog.filmGroups.flatMap(\.films)
        XCTAssertEqual(Set(grouped.map(\.id)), Set(catalog.films.map(\.id)),
                       "grouping dropped or invented a film")
        XCTAssertEqual(grouped.count, catalog.films.count, "a film is in two groups")
        // Positive first, as drawn, and the split is on `type`.
        XCTAssertEqual(catalog.filmGroups.map(\.title), ["Positive", "Negative"])
        for group in catalog.filmGroups {
            for film in group.films {
                XCTAssertEqual(film.isPositive, group.title == "Positive",
                               "\(film.id) is in the \(group.title) group")
            }
        }
        // Within a group the picker's order survives, so a cine stock still
        // follows its group's stills rather than being hoisted.
        let pickerOrder = catalog.filmsForPicker.map(\.id)
        for group in catalog.filmGroups {
            let indices = group.films.compactMap { pickerOrder.firstIndex(of: $0.id) }
            XCTAssertEqual(indices, indices.sorted(), "\(group.title) reordered the picker")
        }
    }

    /// The paper list's own grouping is untouched by v3, including the
    /// `scan_film` sentinel that is not a paper.
    func testPaperGroupsAreUnchanged() {
        XCTAssertEqual(StockCatalog.shared.paperGroups.map(\.title), ["Still", "Cine"])
    }

    /// The selection mark is a capsule inside its row, and every number that
    /// makes it one holds.
    ///
    /// Four separate mistakes are available here and each of them would still
    /// draw *something*: a mark as tall as its row (a filled cell), a mark as
    /// wide as the rail (the band v3 replaced), text starting on the capsule's
    /// own edge, and a radius that is not half the height (a rounded rectangle
    /// rather than a capsule).
    func testTheSelectionMarkIsACapsuleInsideItsRow() {
        let m = Theme.Metric.self
        XCTAssertLessThan(m.stockSelectionHeight, m.listRowHeight)
        XCTAssertEqual(m.stockSelectionRadius, m.stockSelectionHeight / 2, accuracy: 0.01)
        // On the reference rail the capsule is inset at both ends, by
        // different amounts — and the text inside it is on the rail's own
        // label column, so the list and the controls above it share one left
        // edge (UI-SPEC §2.4).
        let width = m.leftPanelWidth - m.stockLeadingInset - m.stockTrailingInset
        XCTAssertEqual(width, 216.52, accuracy: 0.1)
        XCTAssertLessThan(width, m.leftPanelWidth)
        XCTAssertEqual(m.stockTextLeadingInset, m.rowInset, accuracy: 0.05)
        XCTAssertGreaterThan(m.stockTextLeadingInset, m.stockLeadingInset)
        XCTAssertLessThan(m.stockTextLeadingInset,
                          m.leftPanelWidth - m.stockTrailingInset)
    }

    /// The lists stopped using `well`, and that is a colour decision worth
    /// pinning.
    ///
    /// `well` is still `ground` — a lighter grey than the rail — and the
    /// export page's recipe list still sits on it. The editor's stock lists
    /// sit on `stockList`, which is the rail's own colour. Handoff §9 warns
    /// against the shortcut that would have made this one line: "Do not
    /// overwrite generic `well` to change only stock lists."
    func testTheStockListsSitOnTheRail() {
        XCTAssertEqual(Theme.stockList, Theme.card,
                       "v3 puts the lists straight on the rail")
        XCTAssertNotEqual(Theme.stockList, Theme.well,
                          "overwriting `well` would have dragged the export page along")
        XCTAssertEqual(Theme.well, Theme.ground,
                       "the export page's well is unchanged")
    }
    func testMaterialBrowserFiltersIntersectSearchWithoutLosingCatalog() throws {
        let catalog = StockCatalog.shared
        try XCTSkipIf(catalog.films.isEmpty, "catalog unavailable")
        let all = MaterialBrowserChoice.choices(catalog: catalog, tab: .film, filter: .all,
                                               query: "", favorites: [], recent: [])
        XCTAssertEqual(Set(all.map(\.id)), Set(catalog.films.map(\.id)))
        let filtered = MaterialBrowserChoice.choices(catalog: catalog, tab: .film, filter: .negative,
                                                    query: "portra", favorites: [], recent: [])
        XCTAssertFalse(filtered.isEmpty)
        XCTAssertTrue(filtered.allSatisfy { $0.stock?.isPositive == false && $0.title.localizedStandardContains("portra") })
        let favorite = MaterialBrowserChoice.choices(catalog: catalog, tab: .film, filter: .favorites,
                                                    query: "velvia", favorites: ["kodak_portra_400"], recent: [])
        XCTAssertTrue(favorite.isEmpty, "search and favourite filter must intersect")
        let recent = MaterialBrowserChoice.choices(catalog: catalog, tab: .film, filter: .recent,
                                                  query: "", favorites: [], recent: ["missing", "kodak_portra_400", "fujifilm_velvia_100", MaterialBrowserChoice.diID])
        XCTAssertEqual(recent.map(\.id), ["kodak_portra_400", "fujifilm_velvia_100"])
        let paper = MaterialBrowserChoice.choices(catalog: catalog, tab: .paper, filter: .all,
                                                 query: "", favorites: [], recent: [])
        XCTAssertEqual(paper.count, catalog.papers.count + 2)
        XCTAssertEqual(Array(paper.prefix(2).map(\.id)), [MaterialBrowserChoice.scanID, MaterialBrowserChoice.diID])
    }

    func testMaterialPreferencesPersistIDsAndDeduplicateRecentUse() {
        let suite = "material-browser-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = MaterialBrowserLibrary(defaults: defaults)
        library.toggleFavorite("a")
        library.toggleFavorite("b")
        library.toggleFavorite("b")
        for i in 0..<25 { library.recordUse("s\(i)") }
        library.recordUse("s20")
        let restored = MaterialBrowserLibrary(defaults: defaults)
        XCTAssertEqual(restored.favorites, ["a"])
        XCTAssertEqual(restored.recent.count, 20)
        XCTAssertEqual(restored.recent.first, "s20")
        XCTAssertEqual(restored.recent.filter { $0 == "s20" }.count, 1)
        XCTAssertFalse(restored.recent.contains("s0"))
    }

    func testCatalogCarriesNominalSpeedsOnlyForCameraFilms() throws {
        let url = try XCTUnwrap(StockCatalog.bundle.url(forResource: "StockCatalog", withExtension: "json", subdirectory: "Resources"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let stocks = try XCTUnwrap(root["stocks"] as? [[String: Any]])
        for stock in stocks {
            if stock["stage"] as? String == "filming" {
                XCTAssertGreaterThan(stock["nominalSpeed"] as? Int ?? 0, 0, "\(stock["id"] ?? "") needs nominal speed")
            } else {
                XCTAssertNil(stock["nominalSpeed"] as? Int, "printing stocks must not inherit camera ISO")
            }
        }
        let push = try XCTUnwrap(stocks.first { $0["id"] as? String == "kodak_portra_800_push2" })
        XCTAssertEqual(push["nominalSpeed"] as? Int, 800, "push processing does not rename nominal film speed")
    }

    func testEmptyLibraryDoesNotShowOrReserveBottomChrome() {
        let session = Session()
        XCTAssertTrue(session.frames.isEmpty)
        XCTAssertFalse(session.showsBottomStrip)
        XCTAssertEqual(session.bottomChromeOcclusion, 0,
                       "empty canvas must not reserve an invisible navigation bar")
    }

    func testMaterialCardShortNamesPreserveProcessingAndStockIdentity() throws {
        let catalog = StockCatalog.shared
        let kodachrome = try XCTUnwrap(catalog.stock("kodak_kodachrome_64"))
        let choice = MaterialBrowserChoice(id: kodachrome.id, stock: kodachrome)
        XCTAssertEqual(choice.cardTitle, "Kodachrome 64")
        XCTAssertEqual(choice.stock?.name, "Kodak Kodachrome 64")
        let pushed = try XCTUnwrap(catalog.stock("kodak_portra_800_push2"))
        let pushChoice = MaterialBrowserChoice(id: pushed.id, stock: pushed)
        XCTAssertEqual(pushChoice.cardTitle, "Portra 800 (Push 2)")
        XCTAssertEqual(pushChoice.id, "kodak_portra_800_push2")
        let scan = MaterialBrowserChoice(id: MaterialBrowserChoice.scanID, stock: nil)
        XCTAssertEqual(scan.cardTitle, scan.title)
    }

    func testAllMaterialPackagingArtworkDecodesFromBundle() throws {
        let catalog = StockCatalog.shared
        XCTAssertEqual(catalog.stocks.count, 28)
        for stock in catalog.stocks {
            let url = try XCTUnwrap(stock.packagingArtworkURL, stock.id)
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), stock.id)
            let image = try XCTUnwrap(CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 224,
            ] as CFDictionary), stock.id)
            XCTAssertEqual(Double(image.width) / Double(image.height), 16.0 / 9.0, accuracy: 0.02, stock.id)
        }
        for id in [MaterialBrowserChoice.scanID, MaterialBrowserChoice.diID] {
            let choice = MaterialBrowserChoice(id: id, stock: nil)
            let url = try XCTUnwrap(choice.artworkURL, id)
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), id)
            XCTAssertNotNil(CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 224,
            ] as CFDictionary), id)
        }
        let portra = try XCTUnwrap(catalog.stock("kodak_portra_800"))
        XCTAssertEqual(catalog.stock("kodak_portra_800_push1")?.packagingArtworkURL, portra.packagingArtworkURL)
        XCTAssertEqual(catalog.stock("kodak_portra_800_push2")?.packagingArtworkURL, portra.packagingArtworkURL)
    }

}
