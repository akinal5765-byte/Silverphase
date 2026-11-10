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

/// Copy in all three languages, kept where it is shown.
///
/// Reading `Localization.shared.resolved` is not an optimisation to be hoisted —
/// it **is** the mechanism. The property is computed from the `@Observable`
/// setting, so a call made inside a view's `body` registers that view as a
/// dependent of it, and assigning a new language is what repaints every label.
///
/// An empty English argument is a bug rather than a fallback: English is the
/// column everything else falls back to.
@MainActor
func T(_ english: String, _ simplifiedChinese: String, _ traditionalChinese: String) -> String {
    T(english, simplifiedChinese, traditionalChinese, in: MobileLocalization.shared.resolved)
}

/// The same lookup against a language passed in.
///
/// `nonisolated` and pure so that a `Sendable` enum's own `title` — which a
/// `Picker` or an accessibility value reads from a view body — can call it
/// without reaching for main-actor state.
nonisolated func T(_ english: String, _ simplifiedChinese: String,
                   _ traditionalChinese: String, in language: MobileLanguage) -> String {
    switch language {
    case .english:
        return english
    case .simplifiedChinese:
        return simplifiedChinese.isEmpty ? english : simplifiedChinese
    case .traditionalChinese:
        if !traditionalChinese.isEmpty { return traditionalChinese }
        if !simplifiedChinese.isEmpty { return simplifiedChinese }
        return english
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
nonisolated func TDetached(_ english: String, _ simplifiedChinese: String,
                           _ traditionalChinese: String) -> String {
    T(english, simplifiedChinese, traditionalChinese, in: MobileLocalization.snapshot)
}
