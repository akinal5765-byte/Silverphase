//  MobileLocalization.swift — which language the interface is drawn in, and how
//  that is decided.
//
//  The same shape as the desktop's `Localization.swift`, and deliberately so:
//  one product, one answer to "how does the interface change language". There is
//  no `.xcstrings`, no `.lproj` and no `NSLocalizedString` here either, because a
//  catalog is resolved through `Bundle` at lookup time and cannot be swapped
//  underneath a running process — the standard answer is "relaunch", and the
//  setting says "nothing needs restarting". The copy lives in
//  `MobileStrings.swift`; this file is the setting, its resolution, and the
//  observable that makes a change redraw.
//
//  The difference from the desktop is only in scale. The desktop keeps a table
//  of ~400 shared keys plus inline triples for one-off copy; iOS has almost no
//  string used in two places, so it is nearly all inline `T(_:_:_:)` and the
//  table is short.

import Foundation
import Observation

/// A language this app has copy for.
///
/// Two Chinese cases, not one `zh` with a script flag: every string in
/// `MobileStrings.swift` and at every `T(_:_:_:)` call site is chosen per case,
/// and 简体 / 繁體 are different words for the same control as often as they are
/// different glyphs — 设置 / 設定, 保存 / 儲存, 缓存 / 快取.
enum MobileLanguage: String, CaseIterable, Sendable {
    case english
    case simplifiedChinese
    case traditionalChinese
}

/// What the Settings menu offers: the three languages, plus "whatever the
/// system says" — the default, and not the same thing as English.
enum MobileLanguageSetting: String, CaseIterable, Sendable, Identifiable {
    case system, english, simplifiedChinese, traditionalChinese

    var id: String { rawValue }

    /// The language this setting asks for, or `nil` when it defers to the
    /// system. One place relates the setting to the language; `resolved` and
    /// `label` both read it.
    nonisolated var explicit: MobileLanguage? {
        switch self {
        case .system: nil
        case .english: .english
        case .simplifiedChinese: .simplifiedChinese
        case .traditionalChinese: .traditionalChinese
        }
    }

    /// The menu's own label. Every language case is written in its own
    /// language and never in the active one — a language menu is the one menu
    /// a user opens *because* the current language is wrong. Only `.system`
    /// follows the active language, because it has no name of its own.
    ///
    /// Pure and `nonisolated` so a `Picker` can call it inside a view body
    /// without reaching into main-actor state, which also makes it checkable
    /// without a running app.
    nonisolated func label(in active: MobileLanguage) -> String {
        switch self {
        case .system:
            return T("Follow the system", "跟随系统", "跟隨系統", in: active)
        case .english: return "English"
        case .simplifiedChinese: return "简体中文 (zh-Hans)"
        case .traditionalChinese: return "繁體中文 (zh-Hant)"
        }
    }
}

/// The language setting, and the observable every localized string reads.
///
/// `@Observable` rather than a plain singleton, and that is load-bearing:
/// `T(_:_:_:)` reads `resolved` from this object inside a view's body, so
/// SwiftUI records the dependency and changing `language` repaints every view
/// that draws a string. A plain `static var` would compile, look right, and
/// leave the whole library in the old language until something else happened
/// to invalidate it.
@MainActor
@Observable
final class MobileLocalization {
    static let shared = MobileLocalization()

    /// Persisted under `mobile.language`, the same `mobile.` namespace as the
    /// rest of the app's preferences (`mobile.preferences.v1`), so it travels
    /// with them rather than starting a second convention.
    var language: MobileLanguageSetting {
        didSet {
            guard language != oldValue else { return }
            defaults.set(language.rawValue, forKey: Keys.language)
            Self.snapshotStorage = resolved
        }
    }

    /// The language copy is actually drawn in. Computed, not stored: it is a
    /// function of the setting and the system, and a stored copy would be a
    /// second source of truth. Reading `self.language` here is what registers
    /// the `@Observable` dependency.
    var resolved: MobileLanguage {
        language.explicit ?? Self.resolve(Self.systemPreferredLanguages)
    }

    /// The user's preferred languages, read **once**.
    ///
    /// `Locale.preferredLanguages` is a preferences read, and `resolved` sits on
    /// the path of every label in a scrollable editor; a stored `static let`
    /// pays for it once. The cost is that a system language change mid-session
    /// is not followed — the setting is re-read on the next launch, which is
    /// what the system does with everything else.
    private static let systemPreferredLanguages = Locale.preferredLanguages

    private let defaults: UserDefaults

    private enum Keys {
        static let language = "mobile.language"
    }

    /// `defaults` is injectable so a test can write a setting and read back what
    /// the app would do with it without disturbing the real one.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = defaults.string(forKey: Keys.language)
            .flatMap(MobileLanguageSetting.init(rawValue:)) ?? .system
        // `didSet` may not run for the assignment above, so seed the snapshot
        // explicitly rather than relying on it.
        Self.snapshotStorage = language.explicit ?? Self.resolve(Self.systemPreferredLanguages)
    }

    /// The resolved language, readable away from the main actor.
    ///
    /// The renderer throws its failures from the queue that owns the GPU, and
    /// those messages are shown to the user later — so they are copy, and they
    /// need a language. Hopping to the main actor to read an `@Observable`
    /// property is not allowed there, and moving the whole renderer onto the
    /// main actor to satisfy a label would cost more than the label is worth.
    ///
    /// This is the same value, mirrored: written whenever the setting or the
    /// launch resolution changes, read by `TDetached`. A one-frame stale read
    /// is possible and harmless — it can only happen while somebody is changing
    /// the language, and the string it affects is an error the user is about to
    /// read after the change has landed.
    private nonisolated(unsafe) static var snapshotStorage: MobileLanguage = .english
    nonisolated static var snapshot: MobileLanguage { snapshotStorage }

    // MARK: - resolution

    /// Which language a preference list resolves to: the first tag this app has
    /// copy for wins, which is the system's own rule.
    ///
    /// The two Chinese scripts are never substituted for each other. A reader
    /// whose system says `zh-Hant` gets Traditional or, failing that, English —
    /// never Simplified because it is the nearest script at hand.
    nonisolated static func resolve(_ preferred: [String]) -> MobileLanguage {
        for tag in preferred {
            if let match = match(tag) { return match }
        }
        return .english
    }

    /// One tag, or `nil` when it names a language this app has no copy for.
    private nonisolated static func match(_ tag: String) -> MobileLanguage? {
        let parts = tag.lowercased()
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map(String.init)
        guard let primary = parts.first else { return nil }
        switch primary {
        case "en":
            return .english
        case "zh":
            // Script beats region: `zh-Hans-TW` is Simplified and `zh-Hant-CN`
            // is Traditional, because a tag that names a script has said which
            // one it wants.
            if parts.contains("hant") { return .traditionalChinese }
            if parts.contains("hans") { return .simplifiedChinese }
            // No script given, so the region decides. `zh-TW`, `zh-HK` and
            // `zh-MO` are the traditional regions.
            if parts.contains("tw") || parts.contains("hk") || parts.contains("mo") {
                return .traditionalChinese
            }
            // Bare `zh` and the remaining regions: Simplified, which is the
            // majority reading of an unstated `zh`.
            return .simplifiedChinese
        default:
            return nil
        }
    }
}
