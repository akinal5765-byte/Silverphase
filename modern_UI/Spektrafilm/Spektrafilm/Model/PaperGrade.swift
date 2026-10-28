import Foundation

/// Multigrade IV RC's physical enlarger grades, from SpektraLab's table.
/// No half grades: they were not fitted by the upstream measurement.
enum PaperGrade: String, CaseIterable, Codable, Sendable {
    case softest = "00", zero = "0", one = "1", two = "2"
    case three = "3", four = "4", five = "5"

    struct Filtration: Decodable, Sendable {
        let magenta: Double
        let yellow: Double
        let exposure: Double
        private enum CodingKeys: String, CodingKey {
            case magenta = "m_filter_neutral", yellow = "y_filter_neutral"
            case exposure = "print_exposure"
        }
    }

    private struct Table: Decodable { let grades: [String: Filtration] }
    private static let table: [String: Filtration] = {
        guard let url = StockCatalog.bundle.url(forResource: "paper_grades", withExtension: "json",
                                                subdirectory: "Resources/engine"),
              let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode(Table.self, from: data),
              allCases.allSatisfy({ table.grades[$0.rawValue] != nil }) else {
            preconditionFailure("Missing Multigrade grade table; run engine/build.sh bundle")
        }
        return table.grades
    }()

    var filtration: Filtration { Self.table[rawValue]! }
}
