//  MobileStrings.swift — the one lookup, and the few words shared by several
//  screens.
//
//  iOS has almost no copy used in two places: the editor, the settings form and
//  the library each say their own thing, and a table of 600 one-use keys would
//  be an index with nothing in it. So the copy lives at the point of use, as
//  `T("English", "简体中文", "繁體中文")`, exactly as the desktop writes its
//  one-off captions. The reason is the same one recorded there: a triple beside
//  the control keeps the three languages on one line for review, which a table
//  cannot.
//
//  Three rules, and they are the ones a well-meaning edit gets wrong:
//
//    * **Names stay English.** Film and paper profiles, camera and lens models,
//      file names, and the abbreviations `RAW HEIF JPEG LUT EDR EV ISO` are
//      identifiers, not copy. `Kodak Portra 400` is not translated, and neither
//      are the diffusion filters' brand names (Glimmerglass, CineBloom) — only
//      the two Pro-Mist densities beside them are (黑柔 / 白柔), which is how
//      the desktop draws the same line.
//    * **The two Chinese columns are written, not converted.** 设置 / 設定,
//      保存 / 儲存, 缓存 / 快取, 导出 / 匯出 are different words. Do not paste
//      a glyph-substituted Simplified string into the third slot.
//    * **Interpolation survives.** All three arguments must carry the same
//      `\(...)` expressions, or the sentence renders with the wrong number in
//      it. The tests in `LocalizationTests.swift` on the desktop check the same
//      property for the table.

import Foundation

/// Keeps the English fallback and a stable catalog key even when the text interpolates
/// values. Translators may reposition {1}, {2}, … without changing the Swift expressions.
struct MobileSourceCopy: ExpressibleByStringInterpolation, Sendable {
    let english: String
    let key: String
    let arguments: [String]

    init(stringLiteral value: String) {
        english = value
        key = value
        arguments = []
    }

    init(stringInterpolation value: StringInterpolation) {
        english = value.english
        key = value.key
        arguments = value.arguments
    }

    struct StringInterpolation: StringInterpolationProtocol, Sendable {
        var english = ""
        var key = ""
        var arguments: [String] = []

        init(literalCapacity: Int, interpolationCount: Int) {
            english.reserveCapacity(literalCapacity)
            key.reserveCapacity(literalCapacity)
            arguments.reserveCapacity(interpolationCount)
        }

        mutating func appendLiteral(_ literal: String) {
            english += literal
            key += literal
        }

        mutating func appendInterpolation<Value>(_ value: Value) {
            let rendered = "\(value)"
            arguments.append(rendered)
            english += rendered
            key += "{\(arguments.count)}"
        }
    }
}

/// Resources are selected explicitly, so an in-app language change does not need
/// a relaunch or a change to the system language. Each target reads its own bundle.
enum MobileCopyCatalog {
    private static let bundled: [String: [String: String]] = {
        var result: [String: [String: String]] = [:]
        for locale in ["ja", "ko", "de"] {
            if let table = load(locale: locale), !table.isEmpty { result[locale] = table }
        }
        return result
    }()

    static func translations(for locale: String) -> [String: String]? {
        bundled[locale]
    }

    static func load(locale: String, bundle: Bundle = .main) -> [String: String]? {
        // Access the requested folder directly: Foundation's normal localized
        // lookup may silently fall back to a different language.
        guard let url = bundle.resourceURL?.appendingPathComponent("\(locale).lproj/MobileCopy.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    private static let placeholder = try? NSRegularExpression(pattern: #"\{([1-9][0-9]*)\}"#)

    static func resolve(_ source: MobileSourceCopy, fileID: String,
                        translations: [String: String]) -> String {
        let filename = fileID.split(separator: "/").last ?? ""
        let stem = filename.hasSuffix(".swift") ? filename.dropLast(6) : filename
        guard let value = translations["\(stem)|\(source.key)"] ?? translations[source.key],
              !value.isEmpty else { return source.english }
        guard let placeholder else { return source.english }
        if source.arguments.isEmpty, !value.contains("{") { return value }
        let matches = placeholder.matches(in: value, range: NSRange(value.startIndex..., in: value))
        var seen = Set<Int>()
        var cursor = value.startIndex
        var result = ""
        for match in matches {
            guard let range = Range(match.range, in: value),
                  let numberRange = Range(match.range(at: 1), in: value),
                  let number = Int(value[numberRange]),
                  source.arguments.indices.contains(number - 1) else { return source.english }
            seen.insert(number)
            result += value[cursor..<range.lowerBound] + source.arguments[number - 1]
            cursor = range.upperBound
        }
        guard seen.count == source.arguments.count else { return source.english }
        return result + value[cursor...]
    }
}

/// Existing English and Chinese copy stays next to the UI; additional languages use the catalog.
///
/// Reading `Localization.shared.resolved` is not an optimisation to be hoisted —
/// it **is** the mechanism. The property is computed from the `@Observable`
/// setting, so a call made inside a view's `body` registers that view as a
/// dependent of it, and assigning a new language is what repaints every label.
///
/// An empty English argument is a bug rather than a fallback: English is the
/// column everything else falls back to.
@MainActor
func T(_ english: MobileSourceCopy, _ simplifiedChinese: String, _ traditionalChinese: String,
       fileID: String = #fileID) -> String {
    T(english, simplifiedChinese, traditionalChinese, in: MobileLocalization.shared.resolved, fileID: fileID)
}

/// The same lookup against a language passed in.
///
/// `nonisolated` and pure so that a `Sendable` enum's own `title` — which a
/// `Picker` or an accessibility value reads from a view body — can call it
/// without reaching for main-actor state.
nonisolated func T(_ english: MobileSourceCopy, _ simplifiedChinese: String,
                   _ traditionalChinese: String, in language: MobileLanguage,
                   fileID: String = #fileID) -> String {
    switch language {
    case .english:
        return english.english
    case .simplifiedChinese:
        return simplifiedChinese.isEmpty ? english.english : simplifiedChinese
    case .traditionalChinese:
        if !traditionalChinese.isEmpty { return traditionalChinese }
        if !simplifiedChinese.isEmpty { return simplifiedChinese }
        return english.english
    case .japanese, .korean, .german:
        guard let locale = language.catalogLocale,
              let table = MobileCopyCatalog.translations(for: locale) else { return english.english }
        return MobileCopyCatalog.resolve(english, fileID: fileID, translations: table)
    }
}

/// One screen's language, for a view that draws many strings and would otherwise
/// read the singleton at every call site.
///
/// `@Environment`-free on purpose: this is a plain property read, and the
/// dependency is recorded where it is read, in the body.
@MainActor
var currentLanguage: MobileLanguage { MobileLocalization.shared.resolved }

/// Copy for code that runs off the main actor.
///
/// The renderer, the camera pipeline and the colour conversion all report
/// failures from their own queues, and those messages reach the interface. They
/// cannot read the `@Observable` setting, so they read the mirror described in
/// `MobileLocalization.snapshot`.
nonisolated func TDetached(_ english: MobileSourceCopy, _ simplifiedChinese: String,
                           _ traditionalChinese: String, fileID: String = #fileID) -> String {
    T(english, simplifiedChinese, traditionalChinese, in: MobileLocalization.snapshot, fileID: fileID)
}
