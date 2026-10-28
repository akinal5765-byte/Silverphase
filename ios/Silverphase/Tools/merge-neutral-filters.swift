import Foundation

// Product measurements supplement the reference database. Replacing the file
// loses every colour-paper calibration and silently falls back to 0/65/55.
let paths = CommandLine.arguments.dropFirst().map { URL(fileURLWithPath: $0) }
guard paths.count == 3 else { fatalError("Usage: merge-neutral-filters.swift BASE OVERLAY OUTPUT") }
typealias Database = [String: [String: [String: [Double]]]]
let base = try JSONDecoder().decode(Database.self, from: Data(contentsOf: paths[0]))
let overlay = try JSONDecoder().decode(Database.self, from: Data(contentsOf: paths[1]))
var merged = base
for (paper, illuminants) in overlay {
    for (illuminant, films) in illuminants {
        for (film, pack) in films { merged[paper, default: [:]][illuminant, default: [:]][film] = pack }
    }
}
// A supplement must not accidentally remove any measured base combination.
for (paper, illuminants) in base {
    for (illuminant, films) in illuminants {
        for (film, pack) in films where overlay[paper]?[illuminant]?[film] == nil {
            guard merged[paper]?[illuminant]?[film] == pack else { fatalError("Lost neutral calibration: \(paper)/\(illuminant)/\(film)") }
        }
    }
}
let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
try encoder.encode(merged).write(to: paths[2], options: .atomic)
