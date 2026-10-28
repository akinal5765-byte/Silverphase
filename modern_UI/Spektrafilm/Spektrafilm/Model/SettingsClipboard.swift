//  SettingsClipboard.swift — RFC-027: what ⇧⌘C takes and what ⇧⌘V writes.
//
//  Selective settings clipboard, with groups chosen in the copy dialog. The
//  groups are ticked **at copy time**: a clip is the source frame's settings
//  plus the groups it was taken with, and a paste writes exactly those.
//
//  A paste writes **settings, not solved numbers** (the user's decision,
//  2026-09-28). The target meters its own exposure, keeps its own camera
//  white balance under As Shot, and fits its own Scene Placement curve. The
//  source's fitted curve is never pasted: it is the source photograph's
//  histogram in absolute scene stops, and on a contrastier frame it was what
//  blew the print out.
//
//  `applied(to:)` is pure, Sidecar in and Sidecar out, so the whole meaning of
//  a paste is testable without a window, an engine or a file. `Session`
//  decides only how the result reaches a frame.

import Foundation

enum ClipboardGroup: String, CaseIterable, Codable, Sendable, Identifiable {
    /// The boxes the copy dialog shows. 遮罩 (the Tone Mask and local masks) is not
    /// offered while both are withdrawn (`FeatureFlags`): a box for settings
    /// that cannot be seen or changed would be a box that lies. The group stays
    /// in the model, so its fields keep their one owner.
    static var offered: [ClipboardGroup] {
        allCases.filter { $0 != .masks || FeatureFlags.masks || FeatureFlags.toneMask }
    }

    case camera, film, development, print, output, masks

    /// Only the remembered checkbox selection uses the old group IDs.
    /// Map their coverage onto the current process stages; photo sidecars are unchanged.
    static func fromStored(_ names: [String]) -> Set<ClipboardGroup> {
        let legacy: [String: Set<ClipboardGroup>] = [
            "filmAndPaper": [.film, .print, .output],
            "exposure": [.camera, .print], "whiteBalance": [.camera, .print],
            "filmEffects": [.camera, .film, .development],
            "printEffects": [.print, .output], "scenePlacement": [.camera],
        ]
        return names.reduce(into: []) { result, name in
            if let group = Self(rawValue: name) { result.insert(group) }
            else if let groups = legacy[name] { result.formUnion(groups) }
        }
    }

    var id: String { rawValue }

    /// The stored fields this group owns, as prefixes of the encoded sidecar
    /// (`params.effects` owns every `params.effects.*`).
    ///
    /// **Every stored field has exactly one owner or a `notCopied` reason**,
    /// and `SettingsClipboardTests` enforces it by walking the model. A new
    /// field fails that test until someone decides which it is.
    var paths: [String] {
        switch self {
        case .camera:
            ["params.cameraFilter", "params.autoExposure", "params.autoExposureMethod", "params.exposureCompensationEV",
             "decode.whiteBalance", "decode.temperature", "decode.tint",
             "params.cameraDiffusion", "params.cameraDiffusionStrength", "params.cameraDiffusionRange",
             "params.sceneLatitude", "placementNeedsFit"]
        case .film:
            // The film format sets the physical scale of grain and halation.
            ["params.filmEdge", "params.dateBack", "params.filmStock", "params.filmFormatMM", "params.filmFrame", "params.filmSide", "params.sideLengthMM",
             "params.grainActive", "params.grainSizeScale", "params.grainSoftness", "params.halationActive", "params.halationAmount", "params.antihalationMode",
             "params.effects.grain", "params.effects.grainLayered", "params.effects.scatter"]
        case .development:
            ["params.developmentContrast", "params.colorSeparation", "params.effects.couplersActive"]
        case .print:
            // Pre-flash is gated by the Print Effects switch already.
            ["params.printStock", "params.scanFilm", "params.digitalIntermediate",
             "params.paperGrade", "params.printBrightnessStops", "params.yFilterShift", "params.mFilterShift",
             "params.printEffects", "params.preflashExposure",
             "params.printContrast", "params.enlargerDiffusion", "params.enlargerDiffusionStrength", "params.enlargerDiffusionRange"]
        case .output:
            ["params.extendedDynamicRange", "params.glareActive", "params.effects.glare",
             "params.scannerSharpeningActive", "params.scannerSharpeningStrength"]
        case .masks:
            ["params.contrastMask", "masks"]
        }
    }

    /// Stored fields no group owns, and why.
    static let notCopied: [String: String] = [
        "params.pairSceneLatitude": "resolved from each pair hole, fitted again on reopen",
        "params.pairSceneLatitudeSplit": "derived from pair spacing, resolved again on reopen",
        "decode.lensCorrection": "a property of the lens, not of the look",
        "adjustments": "the Post-Dev grade, outside the 2026-09-23 positioning",
        "geometry": "crop and framing belong to the photograph (PRD §7)",
        "solvedEV": "a report of the meter, refilled by the target's own develop",
        "state": "whether the frame has been rendered",
        "source": "which file the sidecar belongs to",
        "schemaVersion": "the file format",
        "decoder": "the file format",
    ]

    @MainActor var title: String {
        switch self {
        case .camera: InspectorStage.camera.title
        case .film: InspectorStage.film.title
        case .development: InspectorStage.development.title
        case .print: InspectorStage.print.title
        case .output: InspectorStage.output.title
        case .masks: L(.clipMasks)
        }
    }

    @MainActor var help: String {
        switch self {
        case .camera: T("Metering, film exposure, white balance, lens filters and scene placement. The target fits its own scene.", "测光、胶片曝光、白平衡、镜头滤镜与场景安置；目标照片按自身画面重新拟合。")
        case .film: T("Film stock, format, grain, halation and scatter.", "胶片型号、画幅、颗粒、光晕与散射。")
        case .development: T("Development contrast and colour separation.", "显影反差与色彩分离。")
        case .print: T("Paper/output mode, print exposure, filter pack, preflash and enlarger diffusion.", "相纸与输出模式、印相曝光、滤色、预闪及柔光放大。")
        case .output: T("Scan sharpening, print glare and highlight expansion.", "扫描锐化、印相眩光与高光层次保留。")
        case .masks: L(.clipMasksHelp)
        }
    }
}

struct SettingsClip: Equatable, Sendable {
    var groups: Set<ClipboardGroup>
    /// The source frame's settings when it was copied.
    var settings: Sidecar
    /// The source frame's file name, for the section's "what is held" line.
    var sourceName: String

    /// `target` with this clip's groups written into it, and nothing else.
    func applied(to target: Sidecar) -> Sidecar {
        var out = target
        let s = settings
        if groups.contains(.film) {
            out.params.filmEdge = s.params.filmEdge
            out.params.dateBack = s.params.dateBack
            out.params.filmStock = s.params.filmStock
        }
        if groups.contains(.print) {
            out.params.printStock = s.params.printStock
            out.params.scanFilm = s.params.scanFilm
            out.params.digitalIntermediate = s.params.digitalIntermediate
        }
        if groups.contains(.camera) {
            out.params.cameraFilter = s.params.cameraFilter
            let meterChanged = out.params.autoExposure != s.params.autoExposure
                || out.params.autoExposureMethod != s.params.autoExposureMethod
            out.params.autoExposure = s.params.autoExposure
            out.params.autoExposureMethod = s.params.autoExposureMethod
            out.params.exposureCompensationEV = s.params.exposureCompensationEV
            // The target's report is of the target's old meter. Nil until its
            // develop, or `retargetSolvedEV`, measures the new one.
            if meterChanged { out.solvedEV = nil }
        }
        if groups.contains(.camera) {
            out.decode.whiteBalance = s.decode.whiteBalance
            // As Shot is the *target's* camera: its numbers are its own, and
            // the source's Kelvin must not come with the word.
            if s.decode.whiteBalance != .asShot {
                out.decode.temperature = s.decode.temperature
                out.decode.tint = s.decode.tint
            }
            out.params.cameraDiffusion = s.params.cameraDiffusion
            out.params.cameraDiffusionStrength = s.params.cameraDiffusionStrength
            out.params.cameraDiffusionRange = s.params.cameraDiffusionRange
        }
        if groups.contains(.film) {
            // `filmFormatMM` is derived from these and the target's aspect;
            // the session re-derives it (`recomputeFilmFormat`), and so does
            // the next decode.
            out.params.filmFormatMM = s.params.filmFormatMM
            out.params.filmFrame = s.params.filmFrame
            out.params.filmSide = s.params.filmSide
            out.params.sideLengthMM = s.params.sideLengthMM
            out.params.grainActive = s.params.grainActive
            out.params.halationActive = s.params.halationActive
            out.params.grainSizeScale = s.params.grainSizeScale
            out.params.grainSoftness = s.params.grainSoftness
            out.params.halationAmount = s.params.halationAmount
            out.params.antihalationMode = s.params.antihalationMode
            out.params.effects.grain = s.params.effects.grain
            out.params.effects.grainLayered = s.params.effects.grainLayered
            out.params.effects.scatter = s.params.effects.scatter
        }
        if groups.contains(.development) {
            out.params.developmentContrast = s.params.developmentContrast
            out.params.colorSeparation = s.params.colorSeparation
            out.params.effects.couplersActive = s.params.effects.couplersActive
        }
        if groups.contains(.output) {
            out.params.extendedDynamicRange = s.params.extendedDynamicRange
            out.params.glareActive = s.params.glareActive
            out.params.scannerSharpeningActive = s.params.scannerSharpeningActive
            out.params.scannerSharpeningStrength = s.params.scannerSharpeningStrength
            out.params.effects.glare = s.params.effects.glare
        }
        if groups.contains(.print) {
            out.params.paperGrade = s.params.paperGrade
            out.params.printBrightnessStops = s.params.printBrightnessStops
            out.params.yFilterShift = s.params.yFilterShift
            out.params.mFilterShift = s.params.mFilterShift
            out.params.printEffects = s.params.printEffects
            out.params.preflashExposure = s.params.preflashExposure
            out.params.printContrast = s.params.printContrast
            out.params.enlargerDiffusion = s.params.enlargerDiffusion
            out.params.enlargerDiffusionStrength = s.params.enlargerDiffusionStrength
            out.params.enlargerDiffusionRange = s.params.enlargerDiffusionRange
        }
        if groups.contains(.camera) {
            // The intent and the Fit's inputs; the curve stays the identity
            // until the target's own Fit lands (`resolvePendingPlacement`).
            let from = s.params.sceneLatitude
            var to = SceneLatitudeSettings()
            to.highlightPullBack = from.highlightPullBack
            to.shadowPullBack = from.shadowPullBack
            to.highlightPercentile = from.highlightPercentile
            to.shadowPercentile = from.shadowPercentile
            to.rolloff = from.rolloff
            to.maxLift = from.maxLift
            to.norm = from.norm
            out.params.sceneLatitude = to
            out.placementNeedsFit = to.highlightPullBack > 0 || to.shadowPullBack > 0
        }
        if groups.contains(.masks) {
            out.params.contrastMask = s.params.contrastMask
            out.masks = s.masks
        }
        return out
    }
}

/// A frozen source while the copy dialog is open. Checkbox edits are a draft;
/// neither the clipboard nor the remembered selection changes until confirmation.
struct SettingsCopyRequest: Identifiable {
    let id = UUID()
    let settings: Sidecar
    let sourceName: String
    let groups: Set<ClipboardGroup>
}
