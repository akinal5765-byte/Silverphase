// Material browser UI state; the shared catalogue is in StockCatalogCore.swift.
import Foundation
import Observation

// MARK: - Material browser preferences (UI state, outside render parameters)

/// Catalogue IDs, never card positions: favourites survive filtering and sorting.
@MainActor @Observable
final class MaterialBrowserLibrary {
    private let defaults: UserDefaults
    private(set) var favorites: Set<String>
    private(set) var recent: [String]
    private static let favoritesKey = "ui2.materialBrowser.favorites"
    private static let recentKey = "ui2.materialBrowser.recent"
    private static let recentLimit = 20

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        favorites = Set((defaults.stringArray(forKey: Self.favoritesKey) ?? []).map(StockCatalog.canonicalID))
        recent = []
        for id in (defaults.stringArray(forKey: Self.recentKey) ?? []).map(StockCatalog.canonicalID) where !recent.contains(id) { recent.append(id) }
    }

    func toggleFavorite(_ id: String) {
        let id = StockCatalog.canonicalID(id)
        if !favorites.insert(id).inserted { favorites.remove(id) }
        defaults.set(favorites.sorted(), forKey: Self.favoritesKey)
    }

    func recordUse(_ id: String) {
        let id = StockCatalog.canonicalID(id)
        recent.removeAll { $0 == id }
        recent.insert(id, at: 0)
        recent = Array(recent.prefix(Self.recentLimit))
        defaults.set(recent, forKey: Self.recentKey)
    }
}

enum MaterialBrowserTab: String { case film, paper }
enum MaterialBrowserFilter: CaseIterable {
    case all, positive, negative, blackwhite, experimental, favorites, recent
    static let filmTabs: [Self] = [.all, .positive, .negative, .blackwhite]
        + (StockCatalog.shared.films.contains(where: \.isExperimental) ? [.experimental] : [])
}

@MainActor struct MaterialBrowserChoice: Identifiable {
    static let scanID = "__scan_film__"
    static let diID = "__digital_intermediate__"
    let id: String
    let stock: Stock?

    static func choices(catalog: StockCatalog, tab: MaterialBrowserTab,
                        filter: MaterialBrowserFilter, query: String,
                        favorites: Set<String>, recent: [String]) -> [Self] {
        var choices = tab == .film
            ? catalog.filmGroups.flatMap(\.films).map { Self(id: $0.id, stock: $0) }
            : [Self(id: scanID, stock: nil), Self(id: diID, stock: nil)]
                + catalog.papers.map { Self(id: $0.id, stock: $0) }
        switch filter {
        case .all: break
        case .negative: choices = choices.filter { $0.stock?.isFilm == true && $0.stock?.isPositive == false && $0.stock?.isExperimental == false }
        case .positive: choices = choices.filter { $0.stock?.isPositive == true && $0.stock?.isExperimental == false }
        case .experimental: choices = choices.filter { $0.stock?.isExperimental == true }
        case .blackwhite:
            choices = choices.filter { $0.stock?.isMonochrome == true }
        case .favorites: choices = choices.filter { favorites.contains($0.id) }
        case .recent:
            let byID = Dictionary(uniqueKeysWithValues: choices.map { ($0.id, $0) })
            choices = recent.compactMap { byID[$0] }
        }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            choices = choices.filter {
                ($0.title + " " + $0.subtitle + " " + $0.id).localizedStandardContains(query)
            }
        }
        return choices
    }

    var title: String {
        if let stock {
            return stock.name.replacingOccurrences(of: "Professional ", with: "")
        }
        return id == Self.scanID ? L(.printNone) : L(.printDigitalIntermediate)
    }
    /// Entity packaging and virtual workflow labels share the same renderer.
    var artworkURL: URL? {
        if let stock { return stock.packagingArtworkURL }
        let filename: String
        switch id {
        case Self.scanID: filename = "workflow_film_scan-v1"
        case Self.diID: filename = "workflow_digital_intermediate-v1"
        default: return nil
        }
        return StockCatalog.bundle.url(forResource: filename, withExtension: "png", subdirectory: "Resources/FilmCovers")
    }

    /// Compact display name; the canonical catalog name remains unchanged.
    var cardTitle: String {
        guard let stock else { return title }
        let prefix = stock.brand + " "
        return title.hasPrefix(prefix) ? String(title.dropFirst(prefix.count)) : title
    }

    var subtitle: String {
        guard let stock else {
            return id == Self.scanID ? T("Film scan", "原片扫描") : T("Digital Intermediate", "数字中间片")
        }
        let type = stock.isMonochrome ? (stock.isFilm ? T("B&W negative", "黑白负片") : T("B&W print", "黑白印相")) :
            (stock.isFilm ? L(filmGroup: stock.isPositive ? "Positive" : "Negative") : L(.sectionPaper))
        return type + " · " + (stock.speedLabel ?? (stock.isCine ? T("Motion picture", "电影") : T("Still photography", "静态摄影")))
    }
}
