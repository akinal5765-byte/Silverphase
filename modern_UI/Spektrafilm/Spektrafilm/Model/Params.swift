//  Params.swift — Layer 1: the engine's parameters, as the UI holds them.
//
//  Mirrors `src/spektrafilm/service/schema.py` field for field. Two rules:
//
//  1. Wire names are the schema's names. `delta(from:)` produces exactly the
//     `params_delta` object the service validates, nothing else.
//  2. Every field knows its layer (`shoot` / `print`) — the same table the
//     service uses to decide between a 190 ms reprint and a film-side
//     re-render. The scheduler routes on it, so a wrong layer here is a
//     correctness bug, not a metadata one.

import Foundation

enum ParamLayer: String, Codable, Sendable { case shoot, print }

enum DiffusionChoice: String, CaseIterable, Identifiable, Sendable {
    case off, glimmerglass, blackProMist = "black_pro_mist", proMist = "pro_mist", cinebloom
    var id: String { rawValue }
    @MainActor var title: String {
        switch self {
        case .off: L(.diffusionOff)
        case .glimmerglass: L(.diffusionClean)
        case .blackProMist: L(.diffusionDeep)
        case .proMist: L(.diffusionSoft)
        case .cinebloom: L(.diffusionWide)
        }
    }
    var engineFamily: String { self == .off ? "black_pro_mist" : rawValue }
}

/// The physical frame a photograph is recorded on, as **both** of its sides.
///
/// The engine's `film_format_mm` is a single number and means the frame's
/// **long edge** (it derives pixel pitch as `film_format_mm * 1000 / max(w, h)`,
/// which is what sets the scale of grain, halation and DIR diffusion). One
/// number cannot say whether 56 mm is 645 or 6×6, which is the gap the PRD
/// closes: a Film Type, a **Side**, and the length of that side.
///
/// So a preset carries a short side and a long side, the user picks which one
/// the length refers to, and the wire's long edge is derived from the *photo's
/// own aspect* — `Session.filmFormatMM(for:)`. With Side = Short at 56 mm a
/// square frame derives 56 and a 6×7 derives 70, from the same preset, without
/// a menu of every medium-format back ever made.
///
/// `long` is the classic frame for the type, and it is what Side = Long shows.
/// It is **not** what gets sent: the derivation always goes through the photo.
struct FilmFrame: Identifiable, Hashable, Sendable {
    let id: String
    /// Millimetres.
    let short: Double
    let long: Double
    let isCine: Bool

    /// The custom entry. Its two sides are the user's `sideLengthMM`, so the
    /// numbers here are only the value a fresh Custom starts at.
    static let custom = FilmFrame(id: "Custom", short: 24, long: 36, isCine: false)

    /// Cine first, as the drawing lists them, each with the orange `CINE`
    /// pill. Camera-negative frames (what the film is exposed at), not
    /// projection apertures.
    static let cine: [FilmFrame] = [
        .init(id: "Super 8", short: 4.01, long: 5.79, isCine: true),
        .init(id: "16mm", short: 7.49, long: 10.26, isCine: true),
        .init(id: "Super 16", short: 7.41, long: 12.52, isCine: true),
        .init(id: "Super 35", short: 14.00, long: 24.89, isCine: true),
        .init(id: "65mm", short: 23.01, long: 52.63, isCine: true),
    ]

    /// The still formats the PRD names: "110, APS, 135, 120, custom".
    ///
    /// 120 is a film *width*, not a frame, which is exactly why the short side
    /// is the useful number: every 120 back exposes the same 56 mm across the
    /// film and differs only in how far along it. Side = Short at 56 therefore
    /// covers 645, 6×6, 6×7 and 6×9 with one entry, and gets each of them
    /// right from the photo's aspect.
    static let still: [FilmFrame] = [
        .init(id: "110", short: 13, long: 17, isCine: false),
        .init(id: "APS", short: 16.7, long: 30.2, isCine: false),
        .init(id: "135", short: 24, long: 36, isCine: false),
        .init(id: "120", short: 56, long: 56, isCine: false),
        custom,
    ]

    static var all: [FilmFrame] { cine + still }
    static func named(_ id: String) -> FilmFrame { all.first { $0.id == id } ?? custom }

    func side(_ s: FilmSide) -> Double { s == .short ? short : long }
}

/// Which side of the photograph the Side Length refers to.
enum FilmSide: String, CaseIterable, Identifiable, Sendable {
    case short, long
    var id: String { rawValue }
    var title: String { self == .short ? "Short" : "Long" }
}

/// The unit the Side Length is typed in. Display only — the wire is always
/// millimetres — so it is an app preference rather than part of a frame's
/// settings.
enum SideUnit: String, CaseIterable, Identifiable, Sendable {
    case mm, cm, inch
    var id: String { rawValue }
    /// "inch" in full since 2026-09-28; millimetres and centimetres keep
    /// their SI symbols, which are units, not abbreviations of a word.
    var title: String { self == .inch ? "inch" : rawValue }
    /// Millimetres per unit.
    var perMM: Double {
        switch self {
        case .mm: 1
        case .cm: 10
        case .inch: 25.4
        }
    }
    func fromMM(_ mm: Double) -> Double { mm / perMM }
    func toMM(_ v: Double) -> Double { v * perMM }
    /// How many decimals the field shows. A millimetre reading wants one; an
    /// inch reading of the same frame wants three, or 135 reads as "0.9 in"
    /// and every still format looks like the same film.
    var decimals: Int {
        switch self {
        case .mm: 1
        case .cm: 2
        case .inch: 3
        }
    }
}

/// RFC-015 §2.3's four exposure intents, as the Camera section's Tone pill
/// offers them. The case names are the wire values.
enum ExposureMethod: String, CaseIterable, Identifiable, Sendable {
    case balanced
    case center
    case protectHighlights = "protect_highlights"
    case protectShadows = "protect_shadows"

    var id: String { rawValue }

    /// What the pill shows: lowercase, as the user's drawing has it.
    var title: String {
        switch self {
        case .balanced: "balanced"
        case .center: "center"
        case .protectHighlights: "protect highlights"
        case .protectShadows: "protect shadows"
        }
    }

    /// The pill's text for a wire value.
    ///
    /// `nil` is a sidecar written before this field existed. It still meters
    /// with the engine's `center_weighted`, so the pill says which meter is
    /// actually running rather than pretending to be one of the four — and
    /// that name is deliberately not in the menu, because choosing it is not a
    /// thing a user can do.
    static func title(forWire value: String?) -> String {
        guard let value else { return "center-weighted (legacy)" }
        return ExposureMethod(rawValue: value)?.title ?? value
    }
}

/// What the **AE Method** pill offers, which is the four intents plus
/// `custom` — and `custom` is not a fifth meter. It is the meter switched
/// **off**.
///
/// The PRD: "take the linearized baseline as the +0.0 baseline (also `As
/// Shot`, clicking this automatically switches AE method to custom), and the
/// different AE methods just adjust the exposure based on it."
///
/// That is exactly the engine's existing `camera.auto_exposure` flag, which
/// has been in the schema all along and which nothing has ever set: with it
/// false the meter contributes nothing (`engine.cpp`: `camera.auto_exposure ?
/// meter.evs.of(method) : nullopt`) and `exposure_compensation_ev` is the
/// whole of the film exposure, measured from the linearized frame. So Custom
/// needs **no new wire field and no new value** — only the flag that was
/// already declared.
enum AEMethod: Hashable, Identifiable, Sendable {
    case custom
    case metered(ExposureMethod)
    /// A sidecar written before the field existed: the engine's own
    /// `center_weighted`, also available as an explicit menu choice.
    case legacy

    var id: String {
        switch self {
        case .custom: "custom"
        case .metered(let m): m.rawValue
        case .legacy: "legacy"
        }
    }

    var title: String {
        switch self {
        case .custom: "Auto exposure off (RAW baseline)"
        case .metered(let m): m.title.capitalizedFirst
        case .legacy: "Center weighted"
        }
    }

    /// Every offered intent, including the original linear-light meter.
    static var offered: [AEMethod] { [.custom] + ExposureMethod.allCases.map(AEMethod.metered) + [.legacy] }

    /// Read the pair of fields a frame actually carries.
    static func of(_ p: FilmParams) -> AEMethod {
        guard p.autoExposure else { return .custom }
        guard let wire = p.autoExposureMethod else { return .legacy }
        return ExposureMethod(rawValue: wire).map(AEMethod.metered) ?? .legacy
    }

    /// Write it back. Custom leaves `autoExposureMethod` alone, so turning the
    /// meter off and on again comes back to the intent it had — which is what
    /// makes Custom usable as a comparison rather than a destination.
    func apply(to p: inout FilmParams) {
        switch self {
        case .custom:
            p.autoExposure = false
        case .metered(let m):
            p.autoExposure = true
            p.autoExposureMethod = m.rawValue
        case .legacy:
            p.autoExposure = true
            // Explicitly switch an already-open session; nil omits the wire field.
            p.autoExposureMethod = "center_weighted"
        }
    }
}

extension String {
    /// "protect highlights" → "Protect highlights". The drawing capitalises
    /// the pill's value ("Custom"), where the previous one lower-cased it.
    var capitalizedFirst: String { isEmpty ? self : prefix(1).uppercased() + dropFirst() }
}

/// RFC-024's virtual contrast mask: a regional gain on the enlarger's image
/// exposure, before pre-flash and paper (API-SPEC §11). Print layer, so an edit
/// reprints the cached negative. Every value is the user's; the defaults are
/// the engine's placeholders and do nothing while `active` is false or both
/// amounts are 0 (RFC-024 §12.5).
struct ContrastMaskSettings: Codable, Equatable, Sendable {
    var active = false
    /// Stops by which the print's highlights (low paper exposure) are raised.
    var highlights = 0.0           // 0…3
    /// Stops by which the print's shadows (high paper exposure) are lowered.
    var shadows = 0.0              // 0…3
    /// Half-width of the untouched core about the negative's mid-grey, stops.
    var core = 1.0                 // 0…3
    /// The blur's sigma as a fraction of the frame's long edge.
    var scale = 0.03               // 0.002…0.12
    /// The base extractor by name; `gaussian` is the only product scheme.
    var scheme = "gaussian"

    static let scaleRange = 0.002...0.12

    init() {}

    /// Every key optional, so a sidecar from before a field existed decodes.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ContrastMaskSettings()
        active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? d.active
        highlights = try c.decodeIfPresent(Double.self, forKey: .highlights) ?? d.highlights
        shadows = try c.decodeIfPresent(Double.self, forKey: .shadows) ?? d.shadows
        core = try c.decodeIfPresent(Double.self, forKey: .core) ?? d.core
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? d.scale
        scheme = try c.decodeIfPresent(String.self, forKey: .scheme) ?? d.scheme
    }
}

/// RFC-023's Scene Latitude (API-SPEC §12). Two halves, and keeping them apart
/// is the RFC's §8.3:
///
/// - the **pull-backs** are UI state -- what the user dragged -- and never
///   reach the wire;
/// - the **resolved curve** (knees, rooms) is what `spk_scene_latitude` solved
///   from them and is the only thing the engine renders. A paper change must
///   not re-render an old edit, so nothing here is re-derived implicitly: the
///   resolved values change only when a fit is applied.
///
/// Shoot layer: the curve sits before the film, so an edit re-develops.
struct SceneLatitudeSettings: Codable, Equatable, Sendable {
    // --- UI state, not on the wire ---
    /// Stops the scene's top is pulled back; 0 = the highlight side is off.
    var highlightPullBack = 0.0
    /// Stops the scene's bottom is pulled up (the bounded landing); 0 = off.
    var shadowPullBack = 0.0
    /// Which robust extreme each side is fitted to: 0.1 or 1, 99.9 or 99.
    var shadowPercentile = 0.1
    var highlightPercentile = 99.9
    // --- the resolved curve, on the wire ---
    var active = false
    var norm = "power"
    var highlightKnee = 2.0
    var highlightRoom = 0.0
    var shadowKnee = -2.0
    var shadowRoom = 0.0
    var rolloff = 2.0              // 1…4
    var maxLift = 4.0              // 0.25…12

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SceneLatitudeSettings()
        highlightPullBack = try c.decodeIfPresent(Double.self, forKey: .highlightPullBack) ?? d.highlightPullBack
        shadowPullBack = try c.decodeIfPresent(Double.self, forKey: .shadowPullBack) ?? d.shadowPullBack
        shadowPercentile = try c.decodeIfPresent(Double.self, forKey: .shadowPercentile) ?? d.shadowPercentile
        highlightPercentile = try c.decodeIfPresent(Double.self, forKey: .highlightPercentile) ?? d.highlightPercentile
        active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? d.active
        norm = try c.decodeIfPresent(String.self, forKey: .norm) ?? d.norm
        highlightKnee = try c.decodeIfPresent(Double.self, forKey: .highlightKnee) ?? d.highlightKnee
        highlightRoom = try c.decodeIfPresent(Double.self, forKey: .highlightRoom) ?? d.highlightRoom
        shadowKnee = try c.decodeIfPresent(Double.self, forKey: .shadowKnee) ?? d.shadowKnee
        shadowRoom = try c.decodeIfPresent(Double.self, forKey: .shadowRoom) ?? d.shadowRoom
        rolloff = try c.decodeIfPresent(Double.self, forKey: .rolloff) ?? d.rolloff
        maxLift = try c.decodeIfPresent(Double.self, forKey: .maxLift) ?? d.maxLift
    }

    /// The request that re-solves these pull-backs against the session's
    /// current medium and scene.
    var request: SceneLatitudeRequest {
        SceneLatitudeRequest(highlightPullBack: highlightPullBack, shadowPullBack: shadowPullBack,
                             rolloff: rolloff, maxLift: maxLift, norm: norm,
                             shadowPercentile: shadowPercentile,
                             highlightPercentile: highlightPercentile)
    }

    /// Take a fit: the pull-backs it was solved for become the UI state and
    /// its resolved curve becomes the render state. Returns false -- and
    /// changes nothing -- for a fit the engine refused, which carries no
    /// `params_delta`, so a refused fit cannot be committed by accident.
    @discardableResult
    mutating func apply(_ fit: SceneLatitudeResponse.Fit) -> Bool {
        guard fit.valid, let d = fit.paramsDelta else { return false }
        highlightPullBack = fit.highlight.pullBack
        shadowPullBack = fit.shadow.pullBack
        active = d.active
        norm = d.norm
        highlightKnee = d.highlightKnee
        highlightRoom = d.highlightRoom
        shadowKnee = d.shadowKnee
        shadowRoom = d.shadowRoom
        rolloff = d.rolloff
        maxLift = d.maxLift
        return true
    }
}

/// RFC-025: each film effect's strength, apart from the film that sets it.
///
/// The stock decides *how much* halation, grain and coupler cross-talk a
/// negative has -- its antihalation tag, its grain model, its DIR matrix -- and
/// until now the only thing the user could do about any of it was switch it
/// off. These are multipliers on the stock's own value, so 1 is always "this
/// film, as modelled", whichever film that is, and every default is the
/// engine's, so a frame that has never seen them renders as it did.
///
/// Local halation reflection and DIR amount remain in their established
/// physical controls; these fields supply the missing strengths and switches.
struct EffectStrengths: Codable, Equatable, Sendable {
    /// `grain_amount`: the grained density mixed over the clean one.
    var grain = 1.0                // 0…2
    /// `grain_sublayers_active`, which the Grain switch used to set too: the
    /// three-sub-layer model against the single-layer one.
    var grainLayered = true
    /// `halation_scatter_amount`: the in-emulsion scatter, a mix weight.
    var scatter = 1.0              // 0…1
    /// `dir_couplers_active` / `dir_couplers_amount`: the inter-layer
    /// inhibition that gives a stock its colour separation.
    var couplersActive = true
    /// `glare_amount`: the print's veil.
    var glare = 1.0                // 0…4

    static let grainRange = 0.0...2.0
    static let scatterRange = 0.0...1.0
    static let glareRange = 0.0...4.0

    static let `default` = EffectStrengths()
    var isDefault: Bool { self == .default }

    init() {}

    /// Every key optional, so a sidecar from before a field existed decodes.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = EffectStrengths()
        grain = try c.decodeIfPresent(Double.self, forKey: .grain) ?? d.grain
        grainLayered = try c.decodeIfPresent(Bool.self, forKey: .grainLayered) ?? d.grainLayered
        scatter = try c.decodeIfPresent(Double.self, forKey: .scatter) ?? d.scatter
        couplersActive = try c.decodeIfPresent(Bool.self, forKey: .couplersActive) ?? d.couplersActive
        glare = try c.decodeIfPresent(Double.self, forKey: .glare) ?? d.glare
    }
}

struct FilmParams: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case filmStock, printStock, exposureCompensationEV, autoExposureMethod, autoExposure
        case filmFormatMM, filmFrame, filmSide, sideLengthMM, grainActive, grainSizeScale, halationActive
        case grainSoftness
        case cameraDiffusion, cameraDiffusionStrength, cameraDiffusionRange
        case enlargerDiffusion, enlargerDiffusionStrength, enlargerDiffusionRange
        case halationAmount, antihalationMode, developmentContrast, colorSeparation
        case filmEdge, dateBack, pairSceneLatitude, pairSceneLatitudeSplit
        case cameraFilter
        case paperGrade
        case printBrightnessStops, printContrast, yFilterShift, mFilterShift, preflashExposure, glareActive, scanFilm
        case extendedDynamicRange
        case contrastMask, sceneLatitude, effects, printEffects, digitalIntermediate
        case scannerSharpeningActive, scannerSharpeningStrength
    }

    // --- stock (shoot for film, print for paper) ---
    var filmStock: String = "kodak_portra_400"
    var printStock: String = "kodak_supra_endura"
    var pairSceneLatitude: SceneLatitudeSettings?
    var pairSceneLatitudeSplit: Double = 19.0 / 37.0
    var filmEdge = FilmEdgeSettings.default
    var dateBack = DateBackSettings()
    var cameraFilter: CameraFilterChoice = .off
    var paperGrade: PaperGrade = .two
    var multigradePrinting: Bool {
        StockCatalog.canonicalID(printStock) == "ilford_multigrade_iv_rc" && !scanFilm && !digitalIntermediate
    }
    var effectivePrintExposure: Double {
        let compensation = multigradePrinting ? paperGrade.filtration.exposure : 1
        return (Self.printExposure(stops: printBrightnessStops) * compensation).clamped(to: 0.05...20)
    }
    // --- shoot ---
    var exposureCompensationEV: Double = 0          // -8…8
    /// Which exposure intent the engine's meter follows (RFC-015 §2.3),
    /// as its wire name.
    ///
    /// **`nil` means "send nothing"**, and that is the whole legacy story: a
    /// sidecar written before this field existed decodes to `nil` (the
    /// synthesized `init(from:)` uses `decodeIfPresent`, which ignores the
    /// default below), the wire carries no `auto_exposure_method`, and the
    /// engine keeps its own default of `center_weighted`, so that edit renders
    /// byte for byte as it always did. The four names are the intents:
    /// `balanced`, `center`, `protect_highlights`, `protect_shadows`.
    ///
    /// New frames use the centre-weighted meter as a portrait-oriented
    /// starting point. Persisted frames retain their saved method.
    var autoExposureMethod: String? = "center_weighted"
    /// The engine's `camera.auto_exposure`, and the whole of what the AE
    /// Method pill's `Custom` means: with it false the meter contributes
    /// nothing and Film Exposure is measured from the linearized frame
    /// (`AEMethod`).
    ///
    /// It has always been in the schema and nothing has ever sent it, so the
    /// engine has always run with its own `true`. The default here is that,
    /// which is what keeps every sidecar written before this field rendering
    /// exactly as it did.
    var autoExposure: Bool = true
    /// The frame's **long edge** in millimetres, which is what the engine
    /// means by `film_format_mm`. It is **derived** — from the three fields
    /// below and the photograph's own aspect — and stored because the
    /// derivation needs a decoded frame and this struct has never seen one.
    /// `Session.recomputeFilmFormat()` is the one place that writes it.
    var filmFormatMM: Double = 36                    // 4…200
    /// Film Type, Side and Side Length: the user's half of that derivation.
    /// Not wire fields — the engine takes one number — but they have to come
    /// back with the frame, so they live here beside the number they make.
    var filmFrame: String = "135"
    var filmSide: String = FilmSide.short.rawValue
    var sideLengthMM: Double = 24
    var grainActive: Bool = true
    /// Relative particle diameter; 1 retains the existing emulsion model.
    var grainSizeScale: Double = 1
    /// Relative density smoothing, not particle diameter or dye-cloud size.
    /// 1 preserves the upstream 0.65 px grain blur; zero disables that blur.
    var grainSoftness: Double = 1
    static let grainSoftnessRange: ClosedRange<Double> = 0...2
    var cameraDiffusion: String = DiffusionChoice.off.rawValue
    var cameraDiffusionStrength: Double = 0.5
    /// PSF width multiplier; 1 preserves the selected family's physical scale.
    var cameraDiffusionRange: Double = 1
    var enlargerDiffusion: String = DiffusionChoice.off.rawValue
    var enlargerDiffusionStrength: Double = 0.5
    var enlargerDiffusionRange: Double = 1
    var halationActive: Bool = true
    /// A multiplier on the stock's own halation response; 1 preserves it.
    var halationAmount: Double = 1
    /// "profile" follows the stock; the other modes override only its
    /// anti-halation reflection preset, without changing the profile file.
    var antihalationMode: String = "profile"
    /// Density-curve gamma, not a chemical push/pull model.
    var developmentContrast: Double = 1
    /// Relative strength of the film's DIR coupler inhibition.
    var colorSeparation: Double = 1
    // --- print ---
    /// UI stops, brighter positive. Wire: `print_exposure = 2^(-stops)`,
    /// because less enlarger exposure prints brighter (API-SPEC §2).
    var printBrightnessStops: Double = 0            // -3…3
    /// Relative gamma of the paper's fitted density curve; 1 is unchanged.
    var printContrast: Double = 1
    var yFilterShift: Double = 0                     // -50…50 Kodak CC, yellow ↔ blue
    var mFilterShift: Double = 0                     // -50…50 Kodak CC, magenta ↔ green
    var preflashExposure: Double = 0                 // 0…1, enlarger preflash
    var glareActive: Bool = true
    /// Scanner USM: keep the original full-resolution radius (0.7 px).
    /// A relative strength of 1 maps to the historical amount of 0.7.
    /// The switch preserves the stored strength while sending zero to bypass.
    var scannerSharpeningActive: Bool = true
    var scannerSharpeningStrength: Double = 1
    static let scannerSharpeningRange: ClosedRange<Double> = 0...2
    /// "No print profile": scan the developed film instead of printing it, so
    /// a slide film reads as a positive and a negative film reads as the
    /// negative it is — orange mask and all.
    ///
    /// The engine drops the three `printing.*` nodes and runs the scan chain
    /// from `Tap.CMY_FILM`, under the film's own viewing illuminant. It is a
    /// print-layer parameter, so switching it costs a reprint (~60 ms) and
    /// not a re-render.
    ///
    /// It is deliberately **not** spelled as `print_stock: "none"`, which is
    /// what the frontend asked for first: `print_stock` names a paper, and a
    /// sentinel there would collapse "which paper" and "is there a paper"
    /// into one field. Keeping them apart is also what lets the user's paper
    /// choice survive toggling the Positive row on and off.
    var scanFilm: Bool = false
    /// RFC-028's **Digital Intermediate** (数字中间片): the negative read in
    /// printing density with its orange mask removed per wavelength, reversed
    /// on the film's own neutral curve, and written as Cineon-style log. It
    /// takes the paper's place the way `scanFilm` does, and like it is a
    /// switch beside `printStock` rather than a paper id, so the paper choice
    /// survives turning it on and off. `scanFilm` wins if both are set, and a
    /// slide film ignores it (it has no mask and no paper). Print layer.
    var digitalIntermediate: Bool = false
    /// True when the DI is what the engine renders: the switch, on a negative,
    /// with no film scan in front of it. The film's polarity lives in the
    /// catalogue, so the caller supplies it.
    func digitalIntermediateActive(filmIsPositive: Bool) -> Bool {
        digitalIntermediate && !scanFilm && !filmIsPositive
    }
    /// RFC-028 §10: the optional blue-sector correction of the DI's colour
    /// step. An app setting (Settings ▸ Rendering), off by default by the
    /// user's decision of 2026-09-29 -- read here so the wire, the print cache
    /// stamp and every export carry it without a second path.
    nonisolated static let diBlueCompensationKey = "ui2.diBlueCompensation"
    nonisolated static var diBlueCompensation: Bool {
        UserDefaults.standard.bool(forKey: diBlueCompensationKey)
    }
    /// Preserve the extended range while rendering a selected print profile.
    /// This is a print-layer choice, so it reprints the cached negative. The
    /// preference is retained when `scanFilm` is selected, but is made
    /// ineffective on the direct film-scan path.
    var extendedDynamicRange: Bool = true

    /// The backend only applies EDR to an actual print profile. Keep the
    /// user's preference in the sidecar while making the wire value false for
    /// the Positive / No Print Profile path, so a persisted preference cannot
    /// change direct film scanning.
    var effectiveExtendedDynamicRange: Bool {
        extendedDynamicRange && !scanFilm && !digitalIntermediate &&
            StockCatalog.shared.stock(printStock)?.isMonochrome != true
    }

    /// Defaults adopted from SpektraLab 1.3.3 (Hanze Qiu). These stocks use
    /// the upstream particle path.
    nonisolated static func ownGrain(of stock: String) -> Double {
        switch StockCatalog.canonicalID(stock) {
        case "kodak_tri_x_400": 1.70
        case "ilford_hp5_plus_400": 1.49
        case "kodak_tmax_100": 0.74
        case "fujifilm_neopan_acros_100_ii": 0.64
        default: 1
        }
    }
    var usesUpstreamBlackWhite: Bool {
        ["kodak_tri_x_400", "ilford_hp5_plus_400", "kodak_tmax_100", "fujifilm_neopan_acros_100_ii"].contains(StockCatalog.canonicalID(filmStock))
    }

    /// The enlarger's pre-flash: a uniform paper exposure of this many times
    /// the light through the film's clear base, added before development
    /// (`printing.cpp`). **Not in EV** -- measured on `_DSC2663`, 0.01 is ~9 %
    /// of the mid-grey exposure and the useful range is 0…0.03 of the wire's
    /// 0…1 (`output/preflash_DSC2663/report.md`). Print layer, live.
    /// RFC-024. Print layer.
    var contrastMask = ContrastMaskSettings()
    /// RFC-023. Shoot layer.
    var sceneLatitude = SceneLatitudeSettings()
    /// RFC-025. Shoot layer except glare, which is the print's.
    var effects = EffectStrengths()
    /// The Print section's **Print Effects** switch: off leaves the paper's
    /// colour transformation and nothing else -- no glare, no pre-flash, no
    /// Tone Mask -- without forgetting any of their settings. A gate on the
    /// wire, like `effectiveExtendedDynamicRange`, so turning it back on
    /// restores exactly what was there.
    var printEffects = true

    init() {
        filmStock = "kodak_portra_400"
        printStock = "kodak_supra_endura"
        exposureCompensationEV = 0
        autoExposureMethod = "center_weighted"
        autoExposure = true
        filmFormatMM = 36
        filmFrame = "135"
        filmSide = FilmSide.short.rawValue
        sideLengthMM = 24
        grainActive = true
        grainSizeScale = 1
        cameraDiffusion = DiffusionChoice.off.rawValue
        cameraDiffusionStrength = 0.5
        cameraDiffusionRange = 1
        enlargerDiffusion = DiffusionChoice.off.rawValue
        enlargerDiffusionStrength = 0.5
        enlargerDiffusionRange = 1
        halationActive = true
        halationAmount = 1
        antihalationMode = "profile"
        developmentContrast = 1
        colorSeparation = 1
        printBrightnessStops = 0
        printContrast = 1
        yFilterShift = 0
        mFilterShift = 0
        preflashExposure = 0
        glareActive = true
        scanFilm = false
        extendedDynamicRange = true
        digitalIntermediate = false
        contrastMask = ContrastMaskSettings()
        sceneLatitude = SceneLatitudeSettings()
        effects = EffectStrengths()
        printEffects = true
    }

    /// Keep sidecars written before EDR readable. Stored properties with
    /// defaults still use `decode(_:forKey:)` in synthesized Codable, so an
    /// absent key would otherwise reject the whole `FilmParams` value. The
    /// older fields retain their synthesized Codable requirements; a missing
    /// exposure method deliberately remains nil because that is the legacy
    /// wire state. New physical controls default to their identity values.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        filmStock = StockCatalog.canonicalID(try c.decode(String.self, forKey: .filmStock))
        printStock = StockCatalog.canonicalID(try c.decode(String.self, forKey: .printStock))
        pairSceneLatitude = try c.decodeIfPresent(SceneLatitudeSettings.self, forKey: .pairSceneLatitude)
        pairSceneLatitudeSplit = try c.decodeIfPresent(Double.self, forKey: .pairSceneLatitudeSplit) ?? 19.0 / 37.0
        filmEdge = try c.decodeIfPresent(FilmEdgeSettings.self, forKey: .filmEdge) ?? .default
        dateBack = try c.decodeIfPresent(DateBackSettings.self, forKey: .dateBack) ?? DateBackSettings()
        cameraFilter = CameraFilterChoice(rawValue: try c.decodeIfPresent(String.self, forKey: .cameraFilter) ?? "") ?? .off
        paperGrade = PaperGrade(rawValue: try c.decodeIfPresent(String.self, forKey: .paperGrade) ?? "2") ?? .two
        exposureCompensationEV = try c.decode(Double.self, forKey: .exposureCompensationEV)
        autoExposureMethod = try c.decodeIfPresent(String.self, forKey: .autoExposureMethod)
        autoExposure = try c.decode(Bool.self, forKey: .autoExposure)
        filmFormatMM = try c.decode(Double.self, forKey: .filmFormatMM)
        filmFrame = try c.decode(String.self, forKey: .filmFrame)
        filmSide = try c.decode(String.self, forKey: .filmSide)
        sideLengthMM = try c.decode(Double.self, forKey: .sideLengthMM)
        grainActive = try c.decode(Bool.self, forKey: .grainActive)
        grainSizeScale = try c.decodeIfPresent(Double.self, forKey: .grainSizeScale) ?? 1
        grainSoftness = try c.decodeIfPresent(Double.self, forKey: .grainSoftness) ?? 1
        cameraDiffusion = try c.decodeIfPresent(String.self, forKey: .cameraDiffusion) ?? "off"
        cameraDiffusionStrength = try c.decodeIfPresent(Double.self, forKey: .cameraDiffusionStrength) ?? 0.5
        cameraDiffusionRange = try c.decodeIfPresent(Double.self, forKey: .cameraDiffusionRange) ?? 1
        enlargerDiffusion = try c.decodeIfPresent(String.self, forKey: .enlargerDiffusion) ?? "off"
        enlargerDiffusionStrength = try c.decodeIfPresent(Double.self, forKey: .enlargerDiffusionStrength) ?? 0.5
        enlargerDiffusionRange = try c.decodeIfPresent(Double.self, forKey: .enlargerDiffusionRange) ?? 1
        halationActive = try c.decode(Bool.self, forKey: .halationActive)
        halationAmount = try c.decodeIfPresent(Double.self, forKey: .halationAmount) ?? 1
        antihalationMode = try c.decodeIfPresent(String.self, forKey: .antihalationMode) ?? "profile"
        developmentContrast = try c.decodeIfPresent(Double.self, forKey: .developmentContrast) ?? 1
        colorSeparation = try c.decodeIfPresent(Double.self, forKey: .colorSeparation) ?? 1
        printBrightnessStops = try c.decode(Double.self, forKey: .printBrightnessStops)
        printContrast = try c.decodeIfPresent(Double.self, forKey: .printContrast) ?? 1
        yFilterShift = try c.decode(Double.self, forKey: .yFilterShift)
        mFilterShift = try c.decode(Double.self, forKey: .mFilterShift)
        glareActive = try c.decode(Bool.self, forKey: .glareActive)
        scannerSharpeningActive = try c.decodeIfPresent(Bool.self, forKey: .scannerSharpeningActive) ?? true
        scannerSharpeningStrength = try c.decodeIfPresent(Double.self, forKey: .scannerSharpeningStrength) ?? 1
        scanFilm = try c.decode(Bool.self, forKey: .scanFilm)
        // An older sidecar without this key keeps the rendering it had when
        // it was saved; the new default applies only to new/reset photos.
        digitalIntermediate = try c.decodeIfPresent(Bool.self, forKey: .digitalIntermediate) ?? false
        extendedDynamicRange = try c.decodeIfPresent(Bool.self, forKey: .extendedDynamicRange) ?? false
        preflashExposure = try c.decodeIfPresent(Double.self, forKey: .preflashExposure) ?? 0
        contrastMask = try c.decodeIfPresent(ContrastMaskSettings.self, forKey: .contrastMask)
            ?? ContrastMaskSettings()
        sceneLatitude = try c.decodeIfPresent(SceneLatitudeSettings.self, forKey: .sceneLatitude)
            ?? SceneLatitudeSettings()
        effects = try c.decodeIfPresent(EffectStrengths.self, forKey: .effects) ?? EffectStrengths()
        printEffects = try c.decodeIfPresent(Bool.self, forKey: .printEffects) ?? true
    }

    static let `default` = FilmParams()

    /// Wire representation of every field. Order is stable for tests.
    var wire: [(name: String, value: ParamValue, layer: ParamLayer)] {
        var fields: [(name: String, value: ParamValue, layer: ParamLayer)] = [
            ("camera_filter", .string(cameraFilter.rawValue), .shoot),
            ("film_stock", .string(StockCatalog.canonicalID(filmStock)), .shoot),
            ("print_stock", .string(StockCatalog.canonicalID(printStock)), .print),
            ("exposure_compensation_ev", .double(exposureCompensationEV), .shoot),
        ]
        // Only when set. A legacy sidecar has no method, and sending one would
        // change how it meters — the engine's default is what it has always
        // rendered with (see `autoExposureMethod`).
        if let method = autoExposureMethod {
            fields.append(("auto_exposure_method", .string(method), .shoot))
        }
        fields += [
            // Sent always, unlike the method: it has a default here and the
            // default is the engine's, so a legacy frame is unchanged by it.
            ("auto_exposure", .bool(autoExposure), .shoot),
            ("film_format_mm", .double(wireFilmFormatMM), .shoot),
            ("grain_active", .bool(grainActive), .shoot),
            ("grain_sublayers_active", .bool(grainActive && effects.grainLayered && !usesUpstreamBlackWhite), .shoot),
            ("grain_size_scale", .double(grainSizeScale), .shoot),
            ("grain_softness", .double(0.65 * grainSoftness.clamped(to: Self.grainSoftnessRange)), .shoot),
            ("camera_diffusion_active", .bool(cameraDiffusion != "off"), .shoot),
            ("camera_diffusion_family", .string(DiffusionChoice(rawValue: cameraDiffusion)?.engineFamily ?? "black_pro_mist"), .shoot),
            ("camera_diffusion_strength", .double(cameraDiffusionStrength), .shoot),
            ("camera_diffusion_range", .double(cameraDiffusionRange), .shoot),
            ("halation_active", .bool(halationActive), .shoot),
            ("halation_amount", .double(halationAmount), .shoot),
            ("antihalation_mode", .string(antihalationMode), .shoot),
            ("density_curve_gamma", .double(developmentContrast), .shoot),
            ("dir_couplers_amount", .double(colorSeparation), .shoot),
            ("print_exposure", .double(effectivePrintExposure), .print),
            ("print_contrast", .double(printContrast), .print),
            ("enlarger_diffusion_active", .bool(!scanFilm && enlargerDiffusion != "off"), .print),
            ("enlarger_diffusion_family", .string(DiffusionChoice(rawValue: enlargerDiffusion)?.engineFamily ?? "black_pro_mist"), .print),
            ("enlarger_diffusion_strength", .double(enlargerDiffusionStrength), .print),
            ("enlarger_diffusion_range", .double(enlargerDiffusionRange), .print),
            ("y_filter_shift", .double(multigradePrinting ? 0 : yFilterShift), .print),
            ("m_filter_shift", .double(multigradePrinting ? 0 : mFilterShift), .print),
            ("glare_active", .bool(glareActive && printEffects), .print),
            ("scanner_sharpening_amount", .double(scannerSharpeningActive
                ? 0.7 * scannerSharpeningStrength.clamped(to: Self.scannerSharpeningRange) : 0), .print),
            ("scan_film", .bool(scanFilm), .print),
            ("extended_dynamic_range", .bool(effectiveExtendedDynamicRange), .print),
            ("preflash_exposure", .double(printEffects ? preflashExposure : 0), .print),
            // RFC-024 (API-SPEC §11). Sent always: the defaults are the
            // engine's, and off is a structural bypass, so a legacy frame
            // renders byte for byte as before.
            ("contrast_mask_active", .bool(contrastMask.active && printEffects && FeatureFlags.toneMask), .print),
            ("contrast_mask_highlights", .double(contrastMask.highlights), .print),
            ("contrast_mask_shadows", .double(contrastMask.shadows), .print),
            ("contrast_mask_core", .double(contrastMask.core), .print),
            ("contrast_mask_scale", .double(contrastMask.scale.clamped(to: ContrastMaskSettings.scaleRange)), .print),
            ("contrast_mask_scheme", .string(contrastMask.scheme), .print),
            // RFC-023 (API-SPEC §12): the resolved curve only; the pull-backs
            // are UI state and stay in the sidecar.
            // Off under the Digital Intermediate (RFC-028): placement fits a
            // scene into a paper's range, and the DI keeps the film's whole
            // one. The pull-backs stay in the sidecar for when a paper returns.
            ("scene_latitude_active", .bool(sceneLatitude.active && !(digitalIntermediate && !scanFilm)), .shoot),
            ("scene_latitude_norm", .string(sceneLatitude.norm), .shoot),
            ("scene_latitude_highlight_knee", .double(sceneLatitude.highlightKnee), .shoot),
            ("scene_latitude_highlight_room", .double(sceneLatitude.highlightRoom), .shoot),
            ("scene_latitude_shadow_knee", .double(sceneLatitude.shadowKnee), .shoot),
            ("scene_latitude_shadow_room", .double(sceneLatitude.shadowRoom), .shoot),
            ("scene_latitude_rolloff", .double(sceneLatitude.rolloff), .shoot),
            ("scene_latitude_max_lift", .double(sceneLatitude.maxLift), .shoot),
            // RFC-025. Sent always, like RFC-024's: every default is the
            // engine's and 1 is a bypass, so the picture of a legacy frame is
            // unchanged (its stamp is not -- new fields miss the cache once).
            ("halation_scatter_amount", .double(effects.scatter.clamped(to: EffectStrengths.scatterRange)), .shoot),
            ("grain_amount", .double((effects.grain * Self.ownGrain(of: filmStock)).clamped(to: EffectStrengths.grainRange)), .shoot),
            ("dir_couplers_active", .bool(effects.couplersActive), .shoot),
            ("glare_amount", .double(effects.glare.clamped(to: EffectStrengths.glareRange)), .print),
            // RFC-028. The DI is sent always, like the rest (off is the
            // paper, exactly). The blue compensation only while the DI is on,
            // so the Settings switch cannot move any other frame's stamp.
            ("digital_intermediate", .bool(digitalIntermediate), .print),
            ("digital_intermediate_blue_compensation",
             .bool(digitalIntermediate && FilmParams.diBlueCompensation), .print),
        ]
        // The selected Multigrade pack; supplied by the caller, not the profile.
        if multigradePrinting {
            let filtration = paperGrade.filtration
            fields += [("c_filter_neutral", .double(0), .print),
                       ("m_filter_neutral", .double(filtration.magenta), .print),
                       ("y_filter_neutral", .double(filtration.yellow), .print)]
        }
        fields += [("scene_latitude_split", .double(filmEdge.pair ? pairSceneLatitudeSplit : 0), .shoot),
                   ("scene_latitude_b_active", .bool(filmEdge.pair && pairSceneLatitude?.active == true), .shoot)]
        if filmEdge.pair, let second = pairSceneLatitude {
            fields += [("scene_latitude_b_highlight_knee", .double(second.highlightKnee), .shoot),
                       ("scene_latitude_b_highlight_room", .double(second.highlightRoom), .shoot),
                       ("scene_latitude_b_shadow_knee", .double(second.shadowKnee), .shoot),
                       ("scene_latitude_b_shadow_room", .double(second.shadowRoom), .shoot)]
        }
        fields += filmEdge.wire
        fields += dateBack.wire(filmEdge: filmEdge, scale: dateScale)
        return fields
    }

    static func printExposure(stops: Double) -> Double {
        (pow(2.0, -stops)).clamped(to: 0.05...20)
    }

    /// The `params_delta` that turns `other` into `self`, and the layers it
    /// touches. An empty delta means nothing to send.
    func delta(from other: FilmParams) -> (delta: [String: ParamValue], layers: Set<ParamLayer>) {
        var delta: [String: ParamValue] = [:]
        var layers = Set<ParamLayer>()
        let theirs = Dictionary(uniqueKeysWithValues: other.wire.map { ($0.name, $0.value) })
        for f in wire where theirs[f.name] != f.value {
            delta[f.name] = f.value
            layers.insert(f.layer)
        }
        // A film change also invalidates the print side (the service says so).
        if delta["film_stock"] != nil { layers.insert(.print) }
        return (delta, layers)
    }

    /// Everything, as sent with `open`.
    var fullDelta: [String: ParamValue] {
        Dictionary(uniqueKeysWithValues: wire.map { ($0.name, $0.value) })
    }

    /// Fields the service can write onto a live pipeline without a rebuild
    /// (`schema.LIVE_MUTABLE`). Informational — the client sends the same
    /// delta either way — but the scheduler uses it to pick the tighter
    /// debounce.
    static let liveMutable: Set<String> = ["print_exposure", "m_filter_shift", "y_filter_shift", "preflash_exposure"]
}
