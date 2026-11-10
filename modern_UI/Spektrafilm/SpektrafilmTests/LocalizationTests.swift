//  LocalizationTests.swift — the language setting's resolution rules, and the
//  three-column table's shape.
//
//  `Localization.resolve` is pure and `nonisolated` on purpose, so the rules
//  that used to be prose in `Localization.swift` can be asserted here without a
//  running app or a configured system. What is *not* tested is that a change
//  repaints the window: that is `@Observable`'s job and a UI test's, not a unit
//  test's.

import XCTest

//  No `@testable import`: the test target compiles the app's own sources next
//  to these files (see `Tools/gen-project.py`), so `Localization`, `Language`
//  and `S` are in scope already.

@MainActor
final class LocalizationTests: XCTestCase {

    // MARK: - resolution

    func testEnglishAndItsRegions() {
        XCTAssertEqual(Localization.resolve(["en"]), .english)
        XCTAssertEqual(Localization.resolve(["en-US"]), .english)
        XCTAssertEqual(Localization.resolve(["en-GB"]), .english)
    }

    func testSimplifiedByScriptAndByRegion() {
        XCTAssertEqual(Localization.resolve(["zh-Hans"]), .simplifiedChinese)
        XCTAssertEqual(Localization.resolve(["zh-Hans-CN"]), .simplifiedChinese)
        XCTAssertEqual(Localization.resolve(["zh-CN"]), .simplifiedChinese)
        XCTAssertEqual(Localization.resolve(["zh-SG"]), .simplifiedChinese)
        // An unstated script on a bare `zh` is read as Simplified, which is what
        // macOS writes when the script is unstated.
        XCTAssertEqual(Localization.resolve(["zh"]), .simplifiedChinese)
    }

    func testTraditionalByScriptAndByRegion() {
        XCTAssertEqual(Localization.resolve(["zh-Hant"]), .traditionalChinese)
        XCTAssertEqual(Localization.resolve(["zh-Hant-TW"]), .traditionalChinese)
        XCTAssertEqual(Localization.resolve(["zh-TW"]), .traditionalChinese)
        XCTAssertEqual(Localization.resolve(["zh-HK"]), .traditionalChinese)
        XCTAssertEqual(Localization.resolve(["zh-MO"]), .traditionalChinese)
    }

    /// The rule that used to send `zh-Hant` to English. It is the reason the
    /// third column exists, so it is pinned rather than left to prose: a
    /// reader in Taipei must never be given Simplified because it is the
    /// nearest script at hand.
    func testTraditionalIsNeverAnsweredWithSimplified() {
        XCTAssertEqual(Localization.resolve(["zh-Hant"]), .traditionalChinese)
        XCTAssertNotEqual(Localization.resolve(["zh-Hant"]), .simplifiedChinese)
        XCTAssertEqual(Localization.resolve(["zh-TW", "zh-Hans"]), .traditionalChinese)
    }

    /// Script beats region: a tag that names a script is answered by the script
    /// before the region is consulted.
    func testScriptOutranksRegion() {
        XCTAssertEqual(Localization.resolve(["zh-Hans-TW"]), .simplifiedChinese)
        XCTAssertEqual(Localization.resolve(["zh-Hant-CN"]), .traditionalChinese)
    }

    /// The first tag with copy wins, even when a later one would also match.
    func testFirstMatchingTagWins() {
        XCTAssertEqual(Localization.resolve(["ja", "zh-Hant", "en"]), .traditionalChinese)
        XCTAssertEqual(Localization.resolve(["fr", "en", "zh-Hans"]), .english)
    }

    /// No copy for a language means English, not the nearest neighbour.
    func testUnknownLanguagesFallBackToEnglish() {
        XCTAssertEqual(Localization.resolve([]), .english)
        XCTAssertEqual(Localization.resolve(["ja"]), .english)
        XCTAssertEqual(Localization.resolve(["de-DE"]), .english)
        XCTAssertEqual(Localization.resolve(["yue"]), .english)
    }

    /// `en_GB` (underscore) is what some callers and fixtures write; the tag
    /// splitter has to accept it as well as `en-GB`.
    func testUnderscoreSeparators() {
        XCTAssertEqual(Localization.resolve(["zh_Hant"]), .traditionalChinese)
        XCTAssertEqual(Localization.resolve(["zh_Hans"]), .simplifiedChinese)
    }

    // MARK: - the setting

    func testEverySettingMapsToItsOwnLanguage() {
        XCTAssertNil(LanguageSetting.system.explicit)
        XCTAssertEqual(LanguageSetting.english.explicit, .english)
        XCTAssertEqual(LanguageSetting.simplifiedChinese.explicit, .simplifiedChinese)
        XCTAssertEqual(LanguageSetting.traditionalChinese.explicit, .traditionalChinese)
        XCTAssertEqual(LanguageSetting.allCases.count, 4)
    }

    /// A language's own name is written in its own language, whatever the
    /// interface is currently showing — the one menu a user opens *because*
    /// the current language is wrong.
    func testLanguageNamesDoNotFollowTheActiveLanguage() {
        for active in Language.allCases {
            XCTAssertEqual(LanguageSetting.english.label(in: active), "English")
            XCTAssertTrue(LanguageSetting.simplifiedChinese.label(in: active)
                .hasPrefix("简体中文"))
            XCTAssertTrue(LanguageSetting.traditionalChinese.label(in: active)
                .hasPrefix("繁體中文"))
        }
    }

    /// Only "follow the system" is translated, because it is the one item with
    /// no name of its own.
    func testFollowSystemFollowsTheActiveLanguage() {
        XCTAssertEqual(LanguageSetting.system.label(in: .english),
                       L(.languageFollowSystem, in: .english))
        XCTAssertEqual(LanguageSetting.system.label(in: .simplifiedChinese),
                       L(.languageFollowSystem, in: .simplifiedChinese))
        XCTAssertEqual(LanguageSetting.system.label(in: .traditionalChinese),
                       L(.languageFollowSystem, in: .traditionalChinese))
    }

    /// The stored setting round-trips, and an unknown stored value lands on
    /// "follow the system" rather than on a crash or an empty menu.
    func testStoredSettingRoundTrips() throws {
        let suite = "LocalizationTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let key = Session.uiKey + "language"

        defaults.removeObject(forKey: key)
        XCTAssertEqual(Localization(defaults: defaults).language, .system)

        defaults.set("traditionalChinese", forKey: key)
        XCTAssertEqual(Localization(defaults: defaults).language, .traditionalChinese)

        defaults.set("klingon", forKey: key)
        XCTAssertEqual(Localization(defaults: defaults).language, .system)
    }

    // MARK: - the table

    /// Every key has all three columns, and none of them is blank. The switches
    /// already make a missing *case* a build error; this catches the entry that
    /// was added with an empty string because someone was in a hurry.
    func testEveryKeyIsTranslated() {
        for key in S.allCases {
            XCTAssertFalse(key.english.isEmpty, "\(key.rawValue) has no English")
            XCTAssertFalse(key.simplifiedChinese.isEmpty,
                           "\(key.rawValue) has no Simplified Chinese")
            XCTAssertFalse(key.traditionalChinese.isEmpty,
                           "\(key.rawValue) has no Traditional Chinese")
        }
    }

    /// Placeholders are part of the contract: a translation that drops `%d`
    /// or `%@` renders a format string with the wrong arguments.
    func testFormatSpecifiersSurviveTranslation() {
        let pattern = try! NSRegularExpression(pattern: "%(?:\\d+\\$)?[@dfsu]")
        for key in S.allCases {
            let expected = pattern.numberOfMatches(
                in: key.english, range: NSRange(key.english.startIndex..., in: key.english))
            for (name, value) in [("simplified", key.simplifiedChinese),
                                  ("traditional", key.traditionalChinese)] {
                let actual = pattern.numberOfMatches(
                    in: value, range: NSRange(value.startIndex..., in: value))
                XCTAssertEqual(actual, expected,
                               "\(key.rawValue): \(name) has \(actual) format specifiers, "
                               + "English has \(expected)")
            }
        }
    }

    /// The three columns are written rather than derived, and the two Chinese
    /// columns are not merely a glyph substitution of each other. These are the
    /// word-level decisions the pass made, pinned so that re-running a converter
    /// over the Traditional column fails here rather than in a screenshot:
    /// 設置/設置 → 設定, 內存 → 記憶體, 緩存 → 快取, 撤銷 → 還原, 導出 → 匯出.
    func testTraditionalUsesItsOwnVocabulary() {
        XCTAssertEqual(S.setTabMemory.traditionalChinese, "記憶體")
        XCTAssertEqual(S.setDiskCache.traditionalChinese, "磁碟快取")
        XCTAssertEqual(S.menuUndo.traditionalChinese, "還原")
        XCTAssertEqual(S.menuExport.traditionalChinese, "匯出…")
        // 沖, not 衝: the conversion's most visible mistake.
        XCTAssertEqual(S.actionPrintNegative.traditionalChinese, "沖印")
        // Brand names stay in Latin script; the densities are named.
        XCTAssertEqual(S.diffusionClean.traditionalChinese, "Glimmerglass")
        XCTAssertEqual(S.diffusionDeep.traditionalChinese, "黑柔")
        XCTAssertEqual(S.diffusionWide.traditionalChinese, "CineBloom")
    }
}
