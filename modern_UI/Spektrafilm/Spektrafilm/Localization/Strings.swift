//  Strings.swift — every user-visible string in the main editor, in both
//  languages, and the one function that looks them up.
//
//  `design/UI-SPEC.md` §7 is the spec this table implements; read it
//  before adding a key. Two of its rules are worth repeating here because they
//  are the ones a well-meaning edit gets wrong:
//
//    * **Names stay English.** Every film and paper profile, camera and lens
//      model, file name, and the abbreviations `CINE RAW RGB ISO EV LUT EDR`,
//      the format names, units, aspect ratios and shortcut letters are
//      identifiers, not copy. They have no Chinese value here because they are
//      not translated — a translated `Kodak Portra 400` is a different product
//      name and a broken catalog lookup.
//    * **Same English, different strings.** `Original` is both a crop ratio
//      and a view state, and `Print` is both the section and the stage named
//      inside other sentences. They get one key each, because they are
//      different strings that happen to share a spelling in one language. Do
//      not collapse them and do not global-replace an English word.
//
//  There is deliberately no `default:` in either switch. The compiler then
//  requires every case of `S` to have both languages, so a key added without a
//  translation is a build error rather than a blank label in the window.
//
//  The table covers the main editor. Export's longer, page-specific copy uses
//  `T(_:_:)` below so both languages stay beside each sentence.

import Foundation

/// One case per user-visible string. The raw value is the key's name and the
/// last-resort fallback, so it must never be shown as copy if that can be
/// helped — see `L(_:)`.
///
/// Names are semantic and grouped by prefix: `rail*` `section*` `camera*`
/// `metering*` `film*` `print*` `curve*` `exposure*` `balance*` `crop*`
/// `action*` `help*` `status*` `reason*`, plus this pass's own `setLanguage*`
/// for the Settings section it adds.
enum S: String, CaseIterable, Sendable {
    case actionOriginal, actionSolve
    // MARK: rails
    case railPresets, railDevelop, railEdit

    // MARK: section titles
    case sectionCamera, sectionFilm, sectionDevelopment, sectionPrint, sectionOutput, sectionPaper, sectionCrop
    case sectionNavigator, navigatorEmpty
    case sectionHistogram, sectionWhiteBalance, sectionExposure
    case sectionCurve, sectionColorBalance

    // MARK: Camera
    case cameraMetering, cameraFilmExposure, cameraFilmExposureAsShot
    case cameraTemperature, cameraTint, cameraVignetting, cameraLensCorrection

    // MARK: the metering pill's options
    case meteringCustom, meteringBalanced, meteringCenter
    case meteringProtectHighlights, meteringProtectShadows
    case meteringCenterWeightedLegacy

    // MARK: Film
    case filmGroupPositive, filmGroupNegative
    case filmFormat, filmFormatSide, filmFormatShort, filmFormatLong
    case filmFormatSideLength
    case filmGrain, filmGrainSize, filmHalation, filmHalationAmount, filmHalationOff, filmGlare
    case cameraDiffusion, enlargerDiffusion
    case lensFilterStrength, lensHaloRange, enlargerSoftnessStrength, enlargerSoftnessRange
    case lensFilterHelp, lensHaloRangeHelp, enlargerSoftnessHelp, enlargerSoftnessRangeHelp
    case paperGlareHelp, highlightExpansionHelp
    case diffusionOff, diffusionClean, diffusionDeep, diffusionSoft, diffusionWide
    case filmAntihalationProfile, filmAntihalationLow
    case filmAntihalationMedium, filmAntihalationHigh

    // MARK: Development
    case developmentContrast, developmentColorSeparation

    // MARK: Print
    case printGroupStill, printGroupCine, printNone, printEDR
    case printExposure, printContrast, printYellow, printMagenta, printPreflash
    case filmEffectStrength, filmGrainLayers, filmScatter, filmCouplers
    case printGroupDigital, printDigitalIntermediate, printDigitalIntermediateHelp

    // MARK: Curve
    case curveLuma, curveRed, curveGreen, curveBlue, curveInput, curveOutput

    // MARK: the right rail's sliders
    case exposureContrast, exposureBrightness, exposureSaturation
    case exposureHighlights, exposureShadows
    case exposureBlackPoint, exposureWhitePoint
    case balanceMidtones

    // MARK: Crop
    case cropAspect, cropAspectFree, cropAspectOriginal
    case cropStraighten, cropStraightenUnit, cropRotate

    // MARK: actions and view states
    case actionDeveloped, actionProcess, actionPrintNegative, actionRestart

    // MARK: tooltips, menus and accessibility labels
    case helpOpen, helpExport, helpSelect, helpCrop, helpPan, helpBeforeAfter, helpHoldOriginal
    case helpPreviousFrame, helpNextFrame, helpSectionMenu
    case helpPrintNegative
    case helpZoomIn, helpZoomOut, helpFit
    case helpFullScreenEnter, helpFullScreenLeave
    case helpDevelopRailHide, helpDevelopRailShow
    case helpEditRailHide, helpEditRailShow
    case helpPickNeutral, helpWhiteBalancePreset
    case helpReset, helpResetFilmExposure, helpResetChannels, helpResetCrop
    case helpStraightenZero, helpCropWholeFrame, helpRevealInFinder
    case helpResetDefaults, helpUseFilmPaper
    case helpResetFilmStock, helpResetDevelopment
    case reasonNoFrames
    case helpAllEffectsOn, helpAllEffectsOff, helpFastFlip
    case helpResetEffectStrengths

    // MARK: status and disabled reasons
    case statusFull, statusFullPending, statusDecodeOnly, statusEmptyFilmstrip
    case statusEDRScope, statusRightRailWBScope
    case reasonDecodeWBDisabled, reasonNonCustomSideLength, reasonEffectOff
    case reasonPositiveFilmDisablesPaper, reasonEDRDisabledInScanFilm
    case reasonPaperGlareDisabledInScanFilm

    // MARK: the Settings page's Language section
    case setLanguage, setLanguageCaption, languageFollowSystem
    // MARK: the app's menus, the canvas menu and the About panel
    case bootTagline, bootStarting, bootWarming, bootReady
    case menuAbout, menuSettings, menuOpen, menuExport, menuUndo, menuCopySettings, menuPasteSettings, menuView, menuZoomIn, menuZoomOut, menuZoomFit, menuZoomHundred, menuDevelopRail, menuFilmstrip, menuBeforeAfter, menuHideBeforeAfter, menuRestartService, menuFrame, menuPrevious, menuNext, menuResetAll, menuConvertLegacy, menuRevealSettings, menuCropSection, menuRotateLeft, menuRotateRight, menuFlipHorizontal, menuFlipVertical, menuResetCrop, menuTool, menuToolSelect, menuToolCrop

    // MARK: the Settings page and the About panel
    case setInterface, setScale, setScaleCaption, setRendering, setPreview, setPreviewCaption, setFastStockPreview, setFastStockPreviewCaption, setCropRemaps, setCropRemapsCaption, setDiagnostics, setLogLevel, setLevelNormal, setLevelNormalDetail, setLevelDetailed, setLevelDetailedDetail, setLevelVerbose, setLevelVerboseDetail, setPerNodeTimings, setPerNodeTimingsNote, setMemory, setFootprint, setSessionPeak, setFree, setNotSampled, setReserve, setReserveNote, setWorkingSetCap, setUnlimited, setCapNote, setHeldByApp, setEvictable, setAllowOverReserve, setAllowOverReserveCaption, setDiskCache, setInUse, setCacheUnavailable, setLimit, setCacheNote, setLocation, setRevealInFinder, setEmptyCache, setEmptyCacheHelp, reasonNoDiskCache, setLogs, setKeepFor, setKeepAtMost, setUnitDays, setUnitFiles, setRetentionCaption, setDestination, setChoose, setChooseLogMessage, setLogDirectoryNote, setClearLogs, setClearLogsHelp, setBundle, setIncludeFileNames, setFileNamesNote, setPlaceholderNames, setSaving, setSaveBundle, setBundleCaption, setWroteBundle, setBundleFailed, setMachine, setApp, setEngine, setRenderCore, setLogFile, setNotReported, setNone, setLastSession, setEndedCleanly, setEndedUnclean, setNoEarlierLog, setUncleanCaption, setLastError, setNoCacheAllocations
    case aboutTagline, aboutEngine, aboutCreditsProfiles, aboutCreditsApp, aboutLicenceBody, aboutLutBody, aboutLicences, aboutShowLicenceFiles, aboutNoLicences, aboutShowInFinder, aboutDone
    case reasonDisabledInDigitalIntermediate, reasonPlacementInDigitalIntermediate
    case latitudeUnmeasurable, latitudeNoLight, filmFormatSize, railFilmAndPrint, railParameters, tabPreDev, tabPostDev, sectionEnlarger, sectionLatitude, sectionScenePlacement, sectionToneMask, printEffects, filmGrainStrength, filmHalationStrength, filmScatterStrength, filmCouplersStrength, filmGlareStrength, latitudeBelow, latitudeWithin, latitudeAbove, latitudeHeld, latitudeFullSeparation, latitudeEmpty, placementHighlight, placementShadow, maskEnable, maskHighlights, maskShadows, maskCore, maskRadius, maskCurveCaption, enlargerPreflash, helpResetFilmFormat, helpResetPlacement, helpResetToneMask, helpResetEnlarger, helpSubLayerGrain, reasonPrintEffectsOff, reasonNotDeveloped, setResetLayout, setResetLayoutCaption
    case sectionClipboard, clipCopy, clipPaste, clipPasteTo, clipHolds, clipEmpty
    case clipFilmAndPaper, clipExposure, clipWhiteBalance, clipFilmEffects, clipPrintEffects, clipScenePlacement, clipMasks
    case clipFilmAndPaperHelp, clipExposureHelp, clipWhiteBalanceHelp, clipFilmEffectsHelp, clipPrintEffectsHelp, clipScenePlacementHelp, clipMasksHelp
    case clipCopyHelp, clipPasteHelp
    case setTabGeneral, setTabRendering, setTabMemory, setTabDiagnostics, setTabAgents
    case setAgentsAccess, setAgentsToggle, setAgentsToggleCaption
    case setAgentsCommandLine, setAgentsInstall, setAgentsReinstall, setAgentsUninstall
    case setAgentsInstalled, setAgentsNotInstalled, setAgentsInstalledOther, setAgentsInstallCaption
    case setAgentsMCP, setAgentsClaudeCode, setAgentsClaudeDesktop, setAgentsMCPCaption
    case setAgentsCopy, setAgentsCopied, setAgentsTools
}

// MARK: - the table

extension S {
    /// English. Exhaustive, so this is also the list of what the app can say.
    var english: String {
        switch self {
        // rails and sections
        // **Left rail: what you choose. Right rail: what you set.** The left
        // one is the two catalogues, so its name says so; `railDevelop` is kept
        // for the old single-rail name rather than deleted, in case a later
        // layout wants it back.
        case .railPresets: "Film & Paper"
        case .railDevelop: "Film Process"
        case .railEdit: "Parameters"
        case .sectionCamera: "Input / Capture"
        case .latitudeUnmeasurable: "This film and paper do not print a rising tone scale, so there is no latitude to measure. A slide printed onto print film comes out as a negative."
        case .latitudeNoLight: "The frame has no light in it to measure."
        case .filmFormatSize: "Size"
        case .railFilmAndPrint: "Film and Print"
        case .railParameters: "Parameters"
        case .tabPreDev: "Pre-Dev"
        case .tabPostDev: "Post-Dev"
        case .sectionNavigator: "Navigator"
        case .sectionEnlarger: "Enlarger"
        case .sectionLatitude: "Latitude"
        case .sectionScenePlacement: "Scene Placement"
        case .sectionToneMask: "Tone Mask"
        case .printEffects: "Print Effects"
        case .filmGrainStrength: "Grain Strength"
        case .filmHalationStrength: "Halation Strength"
        case .filmScatterStrength: "Scatter Strength"
        case .filmCouplersStrength: "Couplers Strength"
        case .filmGlareStrength: "Glare Strength"
        case .latitudeBelow: "Below"
        case .latitudeWithin: "Within"
        case .latitudeAbove: "Above"
        case .latitudeHeld: "stops held"
        case .latitudeFullSeparation: "full separation"
        case .latitudeEmpty: "Develop the frame to measure it against this film and paper."
        case .placementHighlight: "Highlight"
        case .placementShadow: "Shadow"
        case .maskEnable: "Enable"
        case .maskHighlights: "Highlights"
        case .maskShadows: "Shadows"
        case .maskCore: "Core"
        case .maskRadius: "Radius"
        case .maskCurveCaption: "Change in paper exposure against the blurred negative, stops"
        case .enlargerPreflash: "Pre-flash"
        case .helpResetFilmFormat: "Reset the film format and its effects"
        case .helpResetPlacement: "Turn Scene Placement off"
        case .helpResetToneMask: "Reset the Tone Mask"
        case .helpResetEnlarger: "Reset the enlarger to the solved pack"
        case .helpSubLayerGrain: "Sub-layer grain model"
        case .reasonPrintEffectsOff: "Print Effects is off in the Print section."
        case .reasonNotDeveloped: "Develop the frame first."
        case .setResetLayout: "Reset All Layout"
        case .setResetLayoutCaption: "Panel widths, section heights and which sections are open, back to the drawing."
        case .sectionClipboard: "Settings Clipboard"
        case .clipCopy: "Copy"
        case .clipPaste: "Paste"
        case .clipPasteTo: "Paste to %d"
        case .clipHolds: "Holds: %@ · %d of 7"
        case .clipEmpty: "The clipboard is empty."
        case .clipFilmAndPaper: "Film & Paper"
        case .clipExposure: "Exposure"
        case .clipWhiteBalance: "White Balance"
        case .clipFilmEffects: "Film Effects"
        case .clipPrintEffects: "Print Effects"
        case .clipScenePlacement: "Scene Placement"
        case .clipMasks: "Masks"
        case .clipFilmAndPaperHelp: "Film, paper, No Print Profile and EDR."
        case .clipExposureHelp: "Metering method, film exposure and enlarger brightness. Each frame meters itself."
        case .clipWhiteBalanceHelp: "Camera white balance and the enlarger's yellow and magenta filters. As Shot stays each frame's own camera value."
        case .clipFilmEffectsHelp: "Film format, grain, halation, glare, scatter and couplers."
        case .clipPrintEffectsHelp: "The Print Effects switch and pre-flash."
        case .clipScenePlacementHelp: "Highlight and shadow pull-back. The curve is fitted again on each frame."
        case .clipMasksHelp: "The Tone Mask and the local masks."
        case .clipCopyHelp: "Copy the ticked groups from the frame on the canvas (⇧⌘C)."
        case .clipPasteHelp: "Paste what the clipboard holds onto every picked frame (⇧⌘V)."
        case .setTabGeneral: "General"
        case .setTabRendering: "Rendering"
        case .setTabMemory: "Memory"
        case .setTabDiagnostics: "Diagnostics"
        case .setTabAgents: "Agents"
        case .setInterface: "Interface"
        case .setScale: "Scale"
        case .setScaleCaption: "Scales type across the editor, Settings and Export. Changes apply immediately."
        case .setAgentsAccess: "Access"
        case .setAgentsToggle: "Allow command line and agent access"
        case .setAgentsToggleCaption: "Lets the spektralab command and MCP agents (Claude Code, Claude Desktop, any MCP client) open, edit, process and export photographs on this Mac — the same edits this window makes, saved where it reads them. Off, every call is refused, including one from an agent already connected. Local only: nothing listens on the network, and originals are never written."
        case .setAgentsCommandLine: "Command line"
        case .setAgentsInstall: "Install spektralab"
        case .setAgentsReinstall: "Reinstall"
        case .setAgentsUninstall: "Remove"
        case .setAgentsInstalled: "Installed"
        case .setAgentsNotInstalled: "Not installed"
        case .setAgentsInstalledOther: "Installed for another copy of the app"
        case .setAgentsInstallCaption: "Writes a two-line script to ~/.local/bin/spektralab that runs this app without a window. Try `spektralab help`; every command prints JSON."
        case .setAgentsMCP: "MCP server"
        case .setAgentsClaudeCode: "Claude Code"
        case .setAgentsClaudeDesktop: "Claude Desktop"
        case .setAgentsMCPCaption: "Add SpektraLab to an agent with one of these. The agent starts the server itself over stdio when it needs it; nothing runs in the background."
        case .setAgentsCopy: "Copy"
        case .setAgentsCopied: "Copied"
        case .setAgentsTools: "Tools"
        case .sectionFilm: "Film"
        case .sectionDevelopment: "Development"
        case .sectionPrint: "Color Enlargement"
        case .sectionOutput: "Scan / Output"
        // The **catalogue** on the left rail, as against the printing
        // parameters on the right. Same word in English; the Chinese pair is
        // where the distinction has to be made, because both rails have a
        // section that could be called 印相 and only one of them is a list of
        // papers.
        case .sectionPaper: "Paper"
        case .sectionNavigator: "Navigator"
        case .navigatorEmpty: "No frame open"
        case .sectionCrop: "Crop"
        case .sectionHistogram: "Histogram"
        case .sectionWhiteBalance: "White Balance"
        case .sectionExposure: "Exposure"
        case .sectionCurve: "Curve"
        case .sectionColorBalance: "Color Balance"

        // Camera
        case .cameraMetering: "Metering Mode"
        case .cameraFilmExposure: "Exposure Compensation"
        case .cameraFilmExposureAsShot: "As Shot"
        case .cameraTemperature: "Temperature"
        case .cameraTint: "Tint"
        case .cameraVignetting: "Vignetting"
        case .cameraLensCorrection: "Lens Correction"

        // metering
        case .meteringCustom: "Auto exposure off (RAW baseline)"
        case .meteringBalanced: "Balanced"
        case .meteringCenter: "Center"
        case .meteringProtectHighlights: "Protect highlights"
        case .meteringProtectShadows: "Protect shadows"
        case .meteringCenterWeightedLegacy: "Center weighted (original default)"

        // Film
        case .filmGroupPositive: "Positive"
        case .filmGroupNegative: "Negative"
        case .filmFormat: "Film Format"
        case .filmFormatSide: "Size Basis"
        case .filmFormatShort: "Short"
        case .filmFormatLong: "Long"
        case .filmFormatSideLength: "Reference Size"
        case .filmGrain: "Grain"
        case .filmGrainSize: "Grain Size"
        case .filmHalation: "Film Halation"
        case .filmHalationAmount: "Halation Strength"
        case .filmHalationOff: "Off"
        case .filmGlare: "Paper Glare"
        case .cameraDiffusion: "Shooting Diffusion"
        case .enlargerDiffusion: "Soft-Focus Enlargement"
        case .lensFilterStrength: "Diffusion Strength"
        case .lensHaloRange: "Diffusion Spread"
        case .enlargerSoftnessStrength: "Softening Strength"
        case .enlargerSoftnessRange: "Diffusion Spread"
        case .lensFilterHelp: "Simulates a diffusion filter in front of the camera lens, before film exposure. Separate from film halation."
        case .lensHaloRangeHelp: "Changes the filter halo width without changing its strength. 1× keeps the selected filter's modeled size."
        case .enlargerSoftnessHelp: "Simulates diffusion in the enlarger light path before the paper is exposed. Separate from print/scan glare."
        case .enlargerSoftnessRangeHelp: "Changes the enlargement halo width without changing diffusion strength. 1× keeps the selected filter's modeled size."
        case .paperGlareHelp: "Glare from viewing or digitising the finished paper image; separate from film halation and enlarger diffusion."
        case .highlightExpansionHelp: "Expands compressed highlight detail in the completed paper image. The canvas and exported file use the same result."
        case .diffusionOff: "Off"
        case .diffusionClean: "Glimmerglass"
        case .diffusionDeep: "Black Pro-Mist"
        case .diffusionSoft: "Pro-Mist"
        case .diffusionWide: "CineBloom"
        // The halation row's values, named after the phenomenon (halation, 晕光)
        // rather than the coating. There is no "no halation" preset — the
        // strongest anti-halation layer still leaves some — which is why the
        // scale is Low/Medium/High and the real off is a separate `Off`. The
        // inversion between this axis and the wire's lives in `HalationChoice`.
        case .filmAntihalationProfile: "Default"
        case .filmAntihalationLow: "Low"
        case .filmAntihalationMedium: "Medium"
        case .filmAntihalationHigh: "High"

        // Development
        case .developmentContrast: "Development Contrast"
        case .developmentColorSeparation: "DIR Effect"
        case .filmEffectStrength: "Strength"
        case .filmGrainLayers: "Sub-layers"
        case .filmScatter: "Scatter"
        case .filmCouplers: "DIR Couplers"

        // Print
        case .printGroupStill: "Still"
        case .printGroupCine: "Cine"
        case .printNone: "No Print Profile"
        case .printEDR: "Highlight Expansion"
        case .printExposure: "Enlarger Exposure"
        case .printContrast: "Paper Contrast"
        case .printYellow: "Yellow Filtration (Y)"
        case .printMagenta: "Magenta Filtration (M)"
        case .printPreflash: "Paper Preflash"
        case .printGroupDigital: "Digital"
        case .printDigitalIntermediate: "Digital Intermediate"
        case .printDigitalIntermediateHelp:
            "The negative with its orange mask removed and reversed on the film's own neutral curve, "
            + "kept as Cineon log for grading elsewhere. Grain, halation and the film's colour stay; "
            + "the paper does not."

        // Curve
        case .curveLuma: "Luma"
        case .curveRed: "Red"
        case .curveGreen: "Green"
        case .curveBlue: "Blue"
        case .curveInput: "Input"
        case .curveOutput: "Output"

        // right rail
        case .exposureContrast: "Contrast"
        case .exposureBrightness: "Brightness"
        case .exposureSaturation: "Saturation"
        case .exposureHighlights: "Highlights"
        case .exposureShadows: "Shadows"
        case .exposureBlackPoint: "Black Point"
        case .exposureWhitePoint: "White Point"
        case .balanceMidtones: "Midtones"

        // Crop
        case .cropAspect: "Aspect"
        case .cropAspectFree: "Free"
        case .cropAspectOriginal: "Original"
        case .cropStraighten: "Straighten"
        case .cropStraightenUnit: "degrees"
        case .cropRotate: "Rotate"

        // actions
        case .actionDeveloped: "Developed"
        case .actionOriginal: "Original"
        case .actionSolve: "Process"
        // The spec's row gives both English forms — "Process / Process
        // this frame" — and this key is the ••• item, not a button. The
        // longer one is chosen because §8.1 of the layout handoff turns on
        // this item naming what it does: with the Developed capsule now a
        // view toggle, this is the only control in the section that changes
        // the picture, and a bare "Process" beside "Use the film's declared
        // paper" does not say that it acts on this frame.
        case .actionProcess: "Expose & balance"
        case .actionPrintNegative: "Print"
        case .actionRestart: "Restart"

        // help
        case .helpOpen: "Open a folder or image"
        case .helpExport: "Export"
        case .helpSelect: "Select"
        case .helpCrop: "Crop"
        case .helpPreviousFrame: "Open the previous frame"
        case .helpNextFrame: "Open the next frame"
        case .helpSectionMenu: "More actions for this section"
        case .helpPan: "Pan"
        // The trailing clause is **not** dropped. The spec's row gives
        // the control's *name*; this key is its tooltip, and the split's
        // handle is a thing you would not discover by looking at it — the
        // one piece of real instruction in the toolbar's help. It is
        // translated below rather than glued on as an English fragment,
        // which is what the spec actually forbids.
        case .helpBeforeAfter: "Before / after split — drag the line on the canvas"
        // The split glyph draws a state that a *held key* enters, and nothing
        // else on the bar says so: the original's own button is gone, and a
        // gesture with no label has to have a tooltip.
        case .helpHoldOriginal: "Hold ⎵ to see the whole original"
        case .helpPrintNegative: "Print the film that was just developed — the negative becomes the print (or click the canvas)."
        case .helpZoomIn: "Zoom in"
        case .helpZoomOut: "Zoom out"
        case .helpFit: "Fit"
        case .helpFullScreenEnter: "Full screen"
        case .helpFullScreenLeave: "Leave full screen"
        case .helpDevelopRailHide: "Hide the darkroom rail"
        case .helpDevelopRailShow: "Show the darkroom rail"
        case .helpEditRailHide: "Hide the adjustments rail"
        case .helpEditRailShow: "Show the adjustments rail"
        case .helpPickNeutral: "Pick a neutral point on the image"
        case .helpWhiteBalancePreset: "White balance preset"
        case .helpReset: "Reset"
        case .helpResetFilmExposure: "Reset film exposure"
        case .helpResetChannels: "Reset all channels"
        case .helpResetCrop: "Reset crop"
        case .helpStraightenZero: "Straighten to 0°"
        case .helpCropWholeFrame: "Crop to whole frame"
        case .helpRevealInFinder: "Reveal in Finder"
        case .helpResetDefaults: "Reset to defaults"
        case .helpResetFilmStock: "Reset the film stock to the default — Kodak Portra 400"
        case .helpResetDevelopment: "Reset development to the defaults the film stock asks for"
        case .reasonNoFrames: "No frames are open yet — open a folder or an image first."
        case .helpUseFilmPaper: "Use the film's declared paper"
        case .helpAllEffectsOn: "All effects on"
        case .helpAllEffectsOff: "All effects off"
        case .helpResetEffectStrengths: "Reset effect strengths to the film's own"
        case .helpFastFlip: "Fast flip (baked LUT, no glare, ignores your print grade)"

        // status and reasons
        case .statusDecodeOnly: "developing\u{2026}"
        case .statusFull: "full"
        case .statusFullPending: "full…"
        case .statusEmptyFilmstrip: "Drop a folder or images here, or press ⌘O."
        case .statusEDRScope: "Opens up bright details in the print; preview and export match."
        case .statusRightRailWBScope: "Print — an adjustment on the scan."
        case .reasonDecodeWBDisabled: "Decode white balance applies to RAW input only."
        case .reasonNonCustomSideLength:
            "Side Length is the film type's own measurement. Choose Custom to type one."
        case .reasonEffectOff: "Turn the effect on to set its strength."
        case .reasonPositiveFilmDisablesPaper:
            "A slide film is already a positive — there is nothing for a paper to interpret. "
            + "Choose a negative film to print onto paper."
        case .reasonEDRDisabledInScanFilm:
            "Highlight detail applies only when printing on paper."
        case .reasonPaperGlareDisabledInScanFilm:
            "Paper glare applies only when printing on paper."
        case .reasonDisabledInDigitalIntermediate:
            "The Digital Intermediate has no paper, so print effects, the Tone Mask and EDR do not apply."
        case .reasonPlacementInDigitalIntermediate:
            "Scene Placement fits a scene into a paper's range. The Digital Intermediate keeps the film's whole range."

        // Settings ▸ Language
        case .setLanguage: "Language"
        case .setLanguageCaption:
            "Film, paper, camera and lens names stay in English, as do technical abbreviations. "
            + "The change applies immediately — nothing needs restarting."
        case .languageFollowSystem: "Follow the system"

        // the boot window (2026-09-23)
        case .bootTagline: "film simulation"
        case .bootStarting: "Starting the render engine · bringing up the Metal device"
        case .bootWarming: "Preparing the film pipeline · profiles, curves and print tables"
        case .bootReady: "Ready · the film pipeline is loaded"

        // menus, Settings and About (2026-09-23)
        case .menuAbout: "About Silverphase"
        case .menuSettings: "Settings…"
        case .menuOpen: "Open…"
        case .menuExport: "Export…"
        case .menuUndo: "Undo"
        case .menuCopySettings: "Copy Settings…"
        case .menuPasteSettings: "Paste Settings"
        case .menuView: "View"
        case .menuZoomIn: "Zoom In"
        case .menuZoomOut: "Zoom Out"
        case .menuZoomFit: "Zoom to Fit"
        case .menuZoomHundred: "Zoom to 100 %"
        case .menuDevelopRail: "Toggle Film Process Panel"
        case .menuFilmstrip: "Toggle Filmstrip"
        case .menuBeforeAfter: "Before / After"
        case .menuHideBeforeAfter: "Hide Before / After"
        case .menuRestartService: "Restart Render Service"
        case .menuFrame: "Frame"
        case .menuPrevious: "Previous"
        case .menuNext: "Next"
        case .menuResetAll: "Reset Film, Paper, Camera and Enlarger"
        case .menuConvertLegacy: "Convert Legacy Grade to Physical"
        case .menuRevealSettings: "Reveal Settings in Finder"
        case .menuCropSection: "Crop"
        case .menuRotateLeft: "Rotate Left"
        case .menuRotateRight: "Rotate Right"
        case .menuFlipHorizontal: "Flip Horizontally"
        case .menuFlipVertical: "Flip Vertically"
        case .menuResetCrop: "Reset Crop"
        case .menuTool: "Tool"
        case .menuToolSelect: "Select"
        case .menuToolCrop: "Crop"
        case .setInterface: "Interface"
        case .setScale: "Scale"
        case .setScaleCaption: "Scales type across the editor, Settings and Export. Changes apply immediately."
        case .setRendering: "Rendering"
        case .setPreview: "Preview"
        case .setPreviewCaption: "The resolution every interactive edit renders at. The frame's own resolution is rendered separately once an edit settles, so this trades responsiveness while dragging against nothing in the finished picture. The recorded cost of a reprint on a 45 MP frame is 13.7 ms at 2560 px, and rises roughly with the pixels."
        case .setFastStockPreview: "Fast stock preview"
        case .setFastStockPreviewCaption: "When a print stock is picked, show the LUT applied to the negative already on the canvas instead of waiting for the full reprint. It is the same table, so the preview and the print agree."
        case .setCropRemaps: "Crop re-maps the frame"
        case .setCropRemapsCaption: "Whether cropping changes the physical scale of grain, halation and glare. Off — the default, and the physically true answer — the crop shows less of the same negative and its grain is the size it always was. On, the cropped rectangle *is* the frame: the Film section's Side Length now describes the crop, so the effects grow with it. This is the setting the Film section's Side Length row is measured against."
        case .setDiagnostics: "Diagnostics"
        case .setLogLevel: "Log level"
        case .setLevelNormal: "Normal"
        case .setLevelNormalDetail: "The everyday record: opens, renders, exports, memory and errors."
        case .setLevelDetailed: "Detailed"
        case .setLevelDetailedDetail: "Adds what the canvas and the engine do per step. Resets to Normal on the next launch."
        case .setLevelVerbose: "Verbose"
        case .setLevelVerboseDetail: "Everything, including per-node traces. Costs render speed, and resets to Normal on the next launch."
        case .setPerNodeTimings: "Per-node GPU timings"
        case .setPerNodeTimingsNote: "Asks the engine for a time per pipeline node. Each node must flush before its timer stops, which gives up the batching the engine depends on — renders get markedly slower. It is a diagnosis mode, never a default."
        case .setMemory: "Memory"
        case .setFootprint: "Footprint"
        case .setSessionPeak: "Session peak"
        case .setFree: "Free"
        case .setNotSampled: "not sampled yet"
        case .setReserve: "Reserve"
        case .setReserveNote: "Memory Silverphase leaves free for everything else. A frame whose forecast peak does not fit under it gets a warning you can dismiss — never a refusal. The override below suppresses the warning, not eviction."
        case .setWorkingSetCap: "Working-set cap"
        case .setUnlimited: "Unlimited"
        case .setCapNote: "How much Silverphase may hold in caches and scratch buffers. The frame you are looking at is never evicted, whatever this says. Free memory is set by the other applications on the machine; this is the part Silverphase decides."
        case .setHeldByApp: "Held by Silverphase"
        case .setEvictable: "Evictable"
        case .setAllowOverReserve: "Allow exceeding the reserve"
        case .setAllowOverReserveCaption: "A frame whose projected peak does not leave the reserve free gets a warning you can override. Nothing is ever blocked; this is the standing answer to that warning, and turning it off makes the app ask again."
        case .setDiskCache: "Disk cache"
        case .setInUse: "In use"
        case .setCacheUnavailable: "the cache could not be opened"
        case .setLimit: "Limit"
        case .setCacheNote: "Disk Silverphase may use for decoded frames and finished prints, so reopening a photo does not decode it again. Nothing here is your work — every entry can be remade from the original file, so the only cost of emptying it is the wait the next time you open those frames. Least-valuable entries are evicted first, by how often each is used against what it cost to make."
        case .setLocation: "Location"
        case .setRevealInFinder: "Reveal in Finder"
        case .setEmptyCache: "Empty cache now"
        case .reasonNoDiskCache: "There is nothing on disk to empty yet — the cache has not been used."
        case .setEmptyCacheHelp: "Deletes every cached decode and print. Nothing of yours is in it."
        case .setLogs: "Logs"
        case .setKeepFor: "Keep for"
        case .setKeepAtMost: "Keep at most"
        case .setUnitDays: "days"
        case .setUnitFiles: "files"
        case .setRetentionCaption: "Whichever limit is reached first wins, oldest file first. Cleaning runs at launch, never during a render."
        case .setDestination: "Destination"
        case .setChoose: "Choose…"
        case .setChooseLogMessage: "Where should Silverphase write its logs?"
        case .setLogDirectoryNote: "Where sessions are written. A change takes effect at the next launch; this session keeps writing to the file it opened."
        case .setClearLogs: "Clear logs now"
        case .setClearLogsHelp: "Deletes every log file except this session's."
        case .setBundle: "Diagnostic bundle"
        case .setIncludeFileNames: "Include image file names"
        case .setFileNamesNote: "The bundle includes the file names of the images you worked on. Untick to replace them with placeholders throughout — the log is otherwise unchanged."
        case .setPlaceholderNames: "Image file names will be replaced with placeholders throughout."
        case .setSaving: "Saving…"
        case .setSaveBundle: "Save diagnostic bundle…"
        case .setBundleCaption: "One zip: the recent log files, the engine's capabilities, the app and engine versions, this machine, the current settings and the last error. Nothing is transmitted — it is written where you choose."
        case .setWroteBundle: "Wrote %@."
        case .setBundleFailed: "Could not write the bundle: "
        case .setMachine: "This session"
        case .setApp: "App"
        case .setEngine: "Engine"
        case .setRenderCore: "Render core"
        case .setLogFile: "Log file"
        case .setNotReported: "not reported yet"
        case .setNone: "none"
        case .setLastSession: "Last session"
        case .setEndedCleanly: "ended cleanly"
        case .setEndedUnclean: "did not end cleanly"
        case .setNoEarlierLog: "no earlier log"
        case .setUncleanCaption: "That log has no session-end record, which is how a hang, an out-of-memory kill or a crash shows up — the app never got to write one. The file is in the log folder and the diagnostic bundle includes it."
        case .setLastError: "Last error"
        case .setNoCacheAllocations: "No cache or frame allocations registered yet."
        case .aboutTagline: "A spectral film and print simulation for macOS."
        case .aboutEngine: "Silverphase builds on SpektraLab's macOS engine and uses spektrafilm's film and paper profiles and the print-preview LUTs baked from them."
        case .aboutCreditsProfiles: "Film simulation, measured profiles and print model"
        case .aboutCreditsApp: "Silverphase and the SpektraLab-derived render engine"
        case .aboutLicenceBody: "Free software under the GNU GPL v3 or later. You have the right to the corresponding source."
        case .aboutLutBody: "The 8 baked print-preview LUTs are derivatives of the profiles and carry the same CC BY-SA 4.0 licence. What was changed, and what was not, is in the changelog below."
        case .aboutLicences: "Licences"
        case .aboutShowLicenceFiles: "Show the licence files in Finder"
        case .aboutNoLicences: "This build carries no licence texts. Run Tools/bundle-licenses.sh and rebuild."
        case .aboutShowInFinder: "Show in Finder"
        case .aboutDone: "Done"
        }
    }

    /// 简体中文. Verbatim from `design/UI-SPEC.md` §7; the keys above
    /// are named after the semantics the spec distinguishes, not after the
    /// English word, so the two `Original`s and the two `Print`s do not collide.
    var simplifiedChinese: String {
        switch self {
        case .actionOriginal: "原图"
        case .actionSolve: "处理"
        // rails and sections
        case .railPresets: "胶片与相纸"
        case .railDevelop: "胶片工艺"
        case .railEdit: "参数"
        case .sectionCamera: "输入 / 拍摄"
        case .latitudeUnmeasurable: "当前胶片与相纸的输出不随曝光递增，无法测量宽容度。反转片印到电影正片上会得到负像。"
        case .latitudeNoLight: "画面中没有可测量的光。"
        case .filmFormatSize: "尺寸"
        case .railFilmAndPrint: "胶片与相纸"
        case .railParameters: "参数"
        case .tabPreDev: "显影前"
        case .tabPostDev: "显影后"
        case .sectionNavigator: "导航"
        case .sectionEnlarger: "放大机"
        case .sectionLatitude: "宽容度"
        case .sectionScenePlacement: "场景置位"
        case .sectionToneMask: "影调蒙版"
        case .printEffects: "相纸效果"
        case .filmGrainStrength: "颗粒强度"
        case .filmHalationStrength: "光晕强度"
        case .filmScatterStrength: "散射强度"
        case .filmCouplersStrength: "成色剂强度"
        case .filmGlareStrength: "耀光强度"
        case .latitudeBelow: "低于"
        case .latitudeWithin: "范围内"
        case .latitudeAbove: "高于"
        case .latitudeHeld: "档保留"
        case .latitudeFullSeparation: "完整层次"
        case .latitudeEmpty: "显影后即可按当前胶片与相纸测量。"
        case .placementHighlight: "高光"
        case .placementShadow: "阴影"
        case .maskEnable: "启用"
        case .maskHighlights: "高光"
        case .maskShadows: "阴影"
        case .maskCore: "核心"
        case .maskRadius: "半径"
        case .maskCurveCaption: "按模糊后负片的曝光量计算的相纸曝光变化（档）"
        case .enlargerPreflash: "预曝光"
        case .helpResetFilmFormat: "重置胶片画幅与效果"
        case .helpResetPlacement: "关闭场景置位"
        case .helpResetToneMask: "重置影调蒙版"
        case .helpResetEnlarger: "将放大机恢复为配光结果"
        case .helpSubLayerGrain: "分层颗粒模型"
        case .reasonPrintEffectsOff: "“相纸效果”已在相纸部分关闭。"
        case .reasonNotDeveloped: "请先显影。"
        case .setResetLayout: "重置全部布局"
        case .setResetLayoutCaption: "将面板宽度、各部分高度与展开状态恢复为默认。"
        case .sectionClipboard: "设置剪贴板"
        case .clipCopy: "复制"
        case .clipPaste: "粘贴"
        case .clipPasteTo: "粘贴到 %d 张"
        case .clipHolds: "剪贴板：%@ · %d/7 项"
        case .clipEmpty: "剪贴板为空。"
        case .clipFilmAndPaper: "胶片&相纸"
        case .clipExposure: "曝光"
        case .clipWhiteBalance: "白平衡"
        case .clipFilmEffects: "胶片效果"
        case .clipPrintEffects: "相纸效果"
        case .clipScenePlacement: "场景置位"
        case .clipMasks: "遮罩"
        case .clipFilmAndPaperHelp: "胶片、相纸、不使用相纸配置与 EDR。"
        case .clipExposureHelp: "测光方式、胶片曝光与放大机亮度。每张照片各自测光。"
        case .clipWhiteBalanceHelp: "相机白平衡与放大机的黄、品滤色。“拍摄时设置”保持每张照片自己的相机值。"
        case .clipFilmEffectsHelp: "胶片画幅、颗粒、光晕、耀光、散射与耦合剂。"
        case .clipPrintEffectsHelp: "相纸效果开关与预闪。"
        case .clipScenePlacementHelp: "高光与阴影的回拉量。曲线在每张照片上重新拟合。"
        case .clipMasksHelp: "影调蒙版与局部蒙版。"
        case .clipCopyHelp: "从画布上的照片复制勾选的项目（⇧⌘C）。"
        case .clipPasteHelp: "把剪贴板里的内容粘贴到所有选中的照片（⇧⌘V）。"
        case .setTabGeneral: "常规"
        case .setTabRendering: "渲染"
        case .setTabMemory: "内存"
        case .setTabDiagnostics: "诊断"
        case .setTabAgents: "智能体"
        case .setInterface: "界面"
        case .setScale: "缩放"
        case .setScaleCaption: "同步调整主界面、设置与导出页的字体大小；更改立即生效。"
        case .setAgentsAccess: "访问"
        case .setAgentsToggle: "允许命令行与智能体访问"
        case .setAgentsToggleCaption: "允许 spektralab 命令与 MCP 智能体（Claude Code、Claude Desktop 或任何 MCP 客户端）在本机打开、编辑、冲印与导出照片——与本窗口的编辑完全相同，并保存在本窗口读取的位置。关闭时所有调用都会被拒绝，包括已连接的智能体。仅限本机：不监听网络，也从不改写原片。"
        case .setAgentsCommandLine: "命令行"
        case .setAgentsInstall: "安装 spektralab"
        case .setAgentsReinstall: "重新安装"
        case .setAgentsUninstall: "移除"
        case .setAgentsInstalled: "已安装"
        case .setAgentsNotInstalled: "未安装"
        case .setAgentsInstalledOther: "已为另一份应用安装"
        case .setAgentsInstallCaption: "在 ~/.local/bin/spektralab 写入一个两行脚本，以无窗口方式运行本应用。可先试 `spektralab help`；每条命令都输出 JSON。"
        case .setAgentsMCP: "MCP 服务"
        case .setAgentsClaudeCode: "Claude Code"
        case .setAgentsClaudeDesktop: "Claude Desktop"
        case .setAgentsMCPCaption: "用以下任一方式把 SpektraLab 添加给智能体。服务由智能体在需要时通过 stdio 自行启动，不在后台常驻。"
        case .setAgentsCopy: "复制"
        case .setAgentsCopied: "已复制"
        case .setAgentsTools: "工具"
        case .sectionFilm: "胶片"
        case .sectionDevelopment: "显影"
        case .sectionPrint: "彩色放大"
        case .sectionOutput: "扫描 / 输出"
        case .sectionPaper: "相纸"
        case .sectionNavigator: "导航器"
        case .navigatorEmpty: "未打开图像"
        case .sectionCrop: "裁剪"
        case .sectionHistogram: "直方图"
        case .sectionWhiteBalance: "白平衡"
        case .sectionExposure: "曝光"
        case .sectionCurve: "曲线"
        case .sectionColorBalance: "色彩平衡"

        // Camera
        case .cameraMetering: "测光模式"
        case .cameraFilmExposure: "曝光补偿"
        case .cameraFilmExposureAsShot: "拍摄时设置"
        case .cameraTemperature: "色温"
        case .cameraTint: "色调"
        case .cameraVignetting: "暗角"
        case .cameraLensCorrection: "镜头校正"

        // metering
        case .meteringCustom: "关闭自动曝光（RAW 基准）"
        case .meteringBalanced: "均衡"
        case .meteringCenter: "中央主体"
        case .meteringProtectHighlights: "保护高光"
        case .meteringProtectShadows: "保护阴影"
        case .meteringCenterWeightedLegacy: "中央加权（原默认）"

        // Film
        case .filmGroupPositive: "正片"
        case .filmGroupNegative: "负片"
        case .filmFormat: "胶片规格"
        case .filmFormatSide: "尺寸基准"
        case .filmFormatShort: "短边"
        case .filmFormatLong: "长边"
        case .filmFormatSideLength: "基准尺寸"
        case .filmGrain: "颗粒"
        case .filmGrainSize: "颗粒尺度"
        case .filmHalation: "胶片光晕"
        case .filmHalationAmount: "光晕强度"
        case .filmHalationOff: "关闭"
        case .filmGlare: "相纸眩光"
        case .cameraDiffusion: "拍摄柔光"
        case .enlargerDiffusion: "柔光放大"
        case .lensFilterStrength: "柔光强度"
        case .lensHaloRange: "扩散范围"
        case .enlargerSoftnessStrength: "柔光强度"
        case .enlargerSoftnessRange: "扩散范围"
        case .lensFilterHelp: "模拟拍摄镜头前的柔光镜，作用于胶片曝光之前；与胶片光晕不同。"
        case .lensHaloRangeHelp: "调整柔光镜的扩散尺度，不改变柔光强度；1× 保持所选柔光镜的模拟尺寸。"
        case .enlargerSoftnessHelp: "模拟在放大机光路中加入柔光镜，作用于相纸曝光之前；与相纸眩光不同。"
        case .enlargerSoftnessRangeHelp: "调整柔光放大的扩散尺度，不改变柔光强度；1× 保持所选柔光镜的模拟尺寸。"
        case .paperGlareHelp: "模拟观看或数字化已形成的相纸影像时的眩光；与胶片光晕和柔光放大不同。"
        case .highlightExpansionHelp: "展开相纸成像中压缩的高光层次；画布与导出文件使用同一结果。"
        case .diffusionOff: "关闭"
        case .diffusionClean: "Glimmerglass"
        case .diffusionDeep: "黑柔"
        case .diffusionSoft: "白柔"
        case .diffusionWide: "CineBloom"
        // 晕光那一行的取值,按现象命名,不按涂层命名。胶片数据记的是**防晕层**:
        // 涂层越强,晕光越弱,两者方向相反。没有"无晕光"这一档(涂层最强也仍有
        // 残余),所以真正的关闭是单独一项「关闭」;与线格式之间的反相写在
        // `HalationChoice` 里,只有那一处。
        case .filmAntihalationProfile: "默认"
        case .filmAntihalationLow: "弱"
        case .filmAntihalationMedium: "中"
        case .filmAntihalationHigh: "强"

        // Development
        case .developmentContrast: "显影反差"
        case .developmentColorSeparation: "DIR 效应"
        case .filmEffectStrength: "强度"
        case .filmGrainLayers: "分层颗粒"
        case .filmScatter: "散射"
        case .filmCouplers: "DIR 成色剂"

        // Print
        case .printGroupStill: "静态摄影"
        case .printGroupCine: "电影"
        case .printNone: "不使用相纸配置"
        case .printEDR: "高光层次展开"
        case .printExposure: "放大曝光"
        case .printContrast: "相纸反差"
        case .printYellow: "黄滤色（Y）"
        case .printMagenta: "品红滤色（M）"
        case .printPreflash: "相纸预闪"
        case .printGroupDigital: "数字"
        case .printDigitalIntermediate: "数字中间片"
        case .printDigitalIntermediateHelp:
            "去除橙色色罩、按胶片自身的中性曲线反转后的负片，以 Cineon 对数保存，供其他软件调色。"
            + "保留颗粒、光晕与胶片的色彩，不含相纸。"

        // Curve
        case .curveLuma: "明度"
        case .curveRed: "红"
        case .curveGreen: "绿"
        case .curveBlue: "蓝"
        case .curveInput: "输入"
        case .curveOutput: "输出"

        // right rail
        case .exposureContrast: "对比度"
        case .exposureBrightness: "亮度"
        case .exposureSaturation: "饱和度"
        case .exposureHighlights: "高光"
        case .exposureShadows: "阴影"
        case .exposureBlackPoint: "黑场"
        case .exposureWhitePoint: "白场"
        case .balanceMidtones: "中间调"

        // Crop
        case .cropAspect: "宽高比"
        case .cropAspectFree: "自由"
        case .cropAspectOriginal: "原始比例"
        case .cropStraighten: "拉直"
        case .cropStraightenUnit: "度"
        case .cropRotate: "旋转"

        // actions
        case .actionDeveloped: "显影效果"
        case .actionProcess: "自动测光与配光"
        case .actionPrintNegative: "冲印"
        case .actionRestart: "重新启动"

        // help
        case .helpOpen: "打开文件夹或图像"
        case .helpExport: "导出"
        case .helpSelect: "选择"
        case .helpCrop: "裁剪"
        case .helpPreviousFrame: "打开上一张"
        case .helpNextFrame: "打开下一张"
        case .helpSectionMenu: "这一节的更多操作"
        case .helpPan: "平移"
        case .helpBeforeAfter: "原图 / 效果对比 — 在画布上拖动分界线"
        case .helpHoldOriginal: "按住空格键看整张原图"
        case .helpPrintNegative: "把刚冲洗出来的底片印成照片 —— 也可以直接点画布"
        case .helpZoomIn: "放大"
        case .helpZoomOut: "缩小"
        case .helpFit: "适合窗口"
        case .helpFullScreenEnter: "进入全屏"
        case .helpFullScreenLeave: "退出全屏"
        case .helpDevelopRailHide: "隐藏胶片与相纸栏"
        case .helpDevelopRailShow: "显示胶片与相纸栏"
        case .helpEditRailHide: "隐藏参数栏"
        case .helpEditRailShow: "显示参数栏"
        case .helpPickNeutral: "在图像中选取中性色"
        case .helpWhiteBalancePreset: "白平衡预设"
        case .helpReset: "重置"
        case .helpResetFilmExposure: "重置曝光补偿"
        case .helpResetChannels: "重置所有通道"
        case .helpResetCrop: "重置裁剪"
        case .helpStraightenZero: "拉直到 0°"
        case .helpCropWholeFrame: "恢复完整画面"
        case .helpRevealInFinder: "在 Finder 中显示"
        case .helpResetDefaults: "恢复默认设置"
        case .helpResetFilmStock: "恢复默认胶片 — Kodak Portra 400"
        case .helpResetDevelopment: "恢复该胶片给出的默认显影参数"
        case .reasonNoFrames: "还没有打开任何画面 —— 先打开一个文件夹或一张图。"
        case .helpUseFilmPaper: "使用胶片预设的相纸"
        case .helpAllEffectsOn: "开启所有效果"
        case .helpAllEffectsOff: "关闭所有效果"
        case .helpFastFlip: "快速切换（使用预烘焙 LUT，不含眩光，忽略彩色放大调整）"
        case .helpResetEffectStrengths: "将效果强度恢复为胶片默认值"

        // status and reasons
        case .statusDecodeOnly: "显影中…"
        case .statusFull: "全分辨率"
        case .statusFullPending: "全分辨率处理中…"
        case .statusEmptyFilmstrip: "将文件夹或图像拖到此处，或按 ⌘O。"
        case .statusEDRScope: "展开相纸成像中压缩的亮部层次；预览与导出同步生效。"
        case .statusRightRailWBScope: "对相纸扫描结果进行调整。"
        case .reasonDecodeWBDisabled: "仅 RAW 图像支持调整解码白平衡。"
        case .reasonNonCustomSideLength: "选择“自定义”规格后可修改基准尺寸。"
        case .reasonPositiveFilmDisablesPaper: "正片无需经彩色放大曝光到相纸。选择负片后可使用相纸配置。"
        case .reasonEDRDisabledInScanFilm: "高光层次展开仅适用于相纸输出。"
        case .reasonPaperGlareDisabledInScanFilm: "相纸眩光仅适用于相纸输出。"
        case .reasonEffectOff: "开启该效果后可调节强度。"
        case .reasonDisabledInDigitalIntermediate: "数字中间片没有相纸，印相效果、影调蒙版与扩展动态范围不适用。"
        case .reasonPlacementInDigitalIntermediate: "场景置位是把场景放进相纸的宽容度里。数字中间片保留胶片的全部宽容度。"

        // Settings ▸ Language
        case .setLanguage: "语言"
        case .setLanguageCaption:
            "胶片、相纸、相机与镜头名称以及技术缩写保持英文。切换立即生效，无需重新启动。"
        case .languageFollowSystem: "跟随系统"

        // 启动画面（2026-09-23）
        case .bootTagline: "胶片与相纸模拟"
        case .bootStarting: "正在启动渲染引擎 · 初始化 Metal 设备"
        case .bootWarming: "正在准备胶片管线 · 配置、特性曲线与彩色放大表"
        case .bootReady: "就绪 · 胶片管线已加载"

        // 菜单、设置与关于（2026-09-23）
        case .menuAbout: "关于 Silverphase"
        case .menuSettings: "设置…"
        case .menuOpen: "打开…"
        case .menuExport: "导出…"
        case .menuUndo: "撤销"
        case .menuCopySettings: "复制设置…"
        case .menuPasteSettings: "粘贴设置"
        case .menuView: "显示"
        case .menuZoomIn: "放大"
        case .menuZoomOut: "缩小"
        case .menuZoomFit: "适合窗口"
        case .menuZoomHundred: "实际大小 100 %"
        case .menuDevelopRail: "显示 / 隐藏胶片与相纸栏"
        case .menuFilmstrip: "显示 / 隐藏胶片条"
        case .menuBeforeAfter: "原图 / 效果对比"
        case .menuHideBeforeAfter: "关闭原图 / 效果对比"
        case .menuRestartService: "重新启动渲染引擎"
        case .menuFrame: "图像"
        case .menuPrevious: "上一张"
        case .menuNext: "下一张"
        case .menuResetAll: "重置胶片、相纸、相机与放大机"
        case .menuConvertLegacy: "把旧版调色转换为物理参数"
        case .menuRevealSettings: "在访达中显示设置文件"
        case .menuCropSection: "裁剪"
        case .menuRotateLeft: "向左旋转"
        case .menuRotateRight: "向右旋转"
        case .menuFlipHorizontal: "水平翻转"
        case .menuFlipVertical: "垂直翻转"
        case .menuResetCrop: "重置裁剪"
        case .menuTool: "工具"
        case .menuToolSelect: "选择"
        case .menuToolCrop: "裁剪"
        case .setInterface: "界面"
        case .setScale: "缩放"
        case .setScaleCaption: "同步调整主界面、设置与导出页的字体大小；更改立即生效。"
        case .setRendering: "渲染"
        case .setPreview: "预览分辨率"
        case .setPreviewCaption: "拖动时每次编辑渲染的分辨率。编辑停下后会按画面自身分辨率再渲染一次，所以这里换的是拖动时的响应速度，而不是成品的画质。45 MP 画面在 2560 px 下重印的实测耗时是 13.7 ms，并大致随像素数上升。"
        case .setFastStockPreview: "相纸快速预览"
        case .setFastStockPreviewCaption: "选择相纸时，把 LUT 直接套在画布上已有的负片上，而不是等完整重印。用的是同一张表，所以预览与成品一致。"
        case .setCropRemaps: "裁剪改变画面物理尺度"
        case .setCropRemapsCaption: "裁剪是否改变颗粒、光晕与眩光的物理尺度。关闭（默认，也是物理上正确的答案）：裁剪只是少看了一部分同一张底片，颗粒大小不变。开启：裁剪框**就是**画面，胶片区的「基准尺寸」从此描述裁剪后的尺寸，这些效果随之放大。胶片区那一行「基准尺寸」就是按这个设置来解读的。"
        case .setDiagnostics: "诊断"
        case .setLogLevel: "日志级别"
        case .setLevelNormal: "常规"
        case .setLevelNormalDetail: "日常记录：打开、渲染、导出、内存与错误。"
        case .setLevelDetailed: "详细"
        case .setLevelDetailedDetail: "追加画布与引擎每一步的动作。下次启动会回到「常规」。"
        case .setLevelVerbose: "全部"
        case .setLevelVerboseDetail: "全部记录，包括逐节点追踪。会拖慢渲染，下次启动会回到「常规」。"
        case .setPerNodeTimings: "逐节点 GPU 计时"
        case .setPerNodeTimingsNote: "让引擎报告每个管线节点的耗时。每个节点都必须先 flush 才能停止计时，而这会放弃引擎赖以提速的批处理 —— 渲染会明显变慢。这是诊断模式，永远不该是默认值。"
        case .setMemory: "内存"
        case .setFootprint: "占用"
        case .setSessionPeak: "本次峰值"
        case .setFree: "可用"
        case .setNotSampled: "尚未采样"
        case .setReserve: "保留量"
        case .setReserveNote: "Silverphase 留给其它一切的空闲内存。某张画面的预计峰值放不进这个额度时，应用会给出一个可以忽略的警告 —— 但从不拒绝渲染。下面的开关压掉的是警告，不是回收。"
        case .setWorkingSetCap: "工作集上限"
        case .setUnlimited: "不限制"
        case .setCapNote: "Silverphase 允许在缓存与临时缓冲上占用的上限。无论这里写什么，正在看的这一帧永不被回收。空闲内存由机器上其它应用决定；这一项是 Silverphase 自己能定的那部分。"
        case .setHeldByApp: "Silverphase 持有"
        case .setEvictable: "可回收"
        case .setAllowOverReserve: "允许超出保留量"
        case .setAllowOverReserveCaption: "如果某张画面的预计峰值会让保留量不再空闲，应用会给出可以忽略的警告。任何操作都不会被阻止；这里是那个警告的长期答案，关掉之后应用会重新询问。"
        case .setDiskCache: "磁盘缓存"
        case .setInUse: "已使用"
        case .setCacheUnavailable: "缓存无法打开"
        case .setLimit: "上限"
        case .setCacheNote: "Silverphase 用来存放已解码画面与已完成成品的磁盘空间，这样再次打开一张照片时不必重新解码。这里没有任何属于你的东西 —— 每一条都能从原始文件重新生成，所以清空它唯一要付的代价是下次打开那些画面时的等待。回收从最不值得留的条目开始，按「用得多不多」对「造得贵不贵」来算。"
        case .setLocation: "位置"
        case .setRevealInFinder: "在访达中显示"
        case .setEmptyCache: "立即清空缓存"
        case .reasonNoDiskCache: "磁盘缓存还是空的，没有可清的内容。"
        case .setEmptyCacheHelp: "删除所有缓存的解码与成品。里面没有你自己的东西。"
        case .setLogs: "日志"
        case .setKeepFor: "保留时长"
        case .setKeepAtMost: "最多保留"
        case .setUnitDays: "天"
        case .setUnitFiles: "个文件"
        case .setRetentionCaption: "哪一个上限先到就按哪一个，从最旧的文件开始。清理只在启动时运行，不会在渲染期间跑。"
        case .setDestination: "目录"
        case .setChoose: "选择…"
        case .setChooseLogMessage: "Silverphase 的日志写到哪里？"
        case .setLogDirectoryNote: "会话写到哪里。更改在下次启动生效；本次会话继续写它已经打开的那个文件。"
        case .setClearLogs: "立即清空日志"
        case .setClearLogsHelp: "删除除本次会话之外的日志文件。"
        case .setBundle: "诊断包"
        case .setIncludeFileNames: "包含图像文件名"
        case .setFileNamesNote: "诊断包里会包含你处理过的图像文件名。取消勾选会在整份包里把它们换成占位符 —— 日志的其它内容不变。"
        case .setPlaceholderNames: "图像文件名会全部替换为占位符。"
        case .setSaving: "正在保存…"
        case .setSaveBundle: "保存诊断包…"
        case .setBundleCaption: "一个 zip：最近的日志文件、引擎能力、应用与引擎版本、这台机器、当前设置和最后一次错误。不会上传任何内容 —— 只写到你选择的位置。"
        case .setWroteBundle: "已写入 %@。"
        case .setBundleFailed: "无法写入诊断包："
        case .setMachine: "本次会话"
        case .setApp: "应用"
        case .setEngine: "引擎"
        case .setRenderCore: "渲染核心"
        case .setLogFile: "日志文件"
        case .setNotReported: "尚未上报"
        case .setNone: "无"
        case .setLastSession: "上次会话"
        case .setEndedCleanly: "正常结束"
        case .setEndedUnclean: "非正常结束"
        case .setNoEarlierLog: "没有更早的日志"
        case .setUncleanCaption: "那份日志没有会话结束记录 —— 卡死、内存不足被杀或崩溃就是这样留下痕迹的：应用没来得及写。文件在日志目录里，诊断包会包含它。"
        case .setLastError: "上次错误"
        case .setNoCacheAllocations: "尚无缓存或画帧分配登记。"
        case .aboutTagline: "为 macOS 打造的光谱胶片与相纸模拟。"
        case .aboutEngine: "Silverphase 基于 SpektraLab 的 macOS 引擎，并使用 spektrafilm 的胶片、相纸配置及其衍生的彩色放大预览 LUT。"
        case .aboutCreditsProfiles: "胶片模拟、实测配置与彩色放大模型"
        case .aboutCreditsApp: "Silverphase 与源自 SpektraLab 的渲染引擎"
        case .aboutLicenceBody: "以 GNU GPL v3 或更高版本发布的自由软件。你有权获得对应的源代码。"
        case .aboutLutBody: "8 个烘焙出的彩色放大预览 LUT 是这些配置的衍生作品，同样以 CC BY-SA 4.0 授权。改动了什么、没改动什么，写在下面的变更记录里。"
        case .aboutLicences: "许可"
        case .aboutShowLicenceFiles: "在访达中显示许可文件"
        case .aboutNoLicences: "这个构建里没有许可文本。请运行 Tools/bundle-licenses.sh 后重新构建。"
        case .aboutShowInFinder: "在访达中显示"
        case .aboutDone: "完成"
        }
    }
}

// MARK: - the lookup

/// Look up `key` in the active language.
///
/// The read of `Localization.shared.resolved` is not an optimisation to be
/// hoisted — it **is** the mechanism. `resolved` is computed from the
/// `@Observable` `language` setting, so a call made inside a view's `body`
/// registers that view as a dependent of it, and assigning a new language is
/// what makes every label in the window repaint. A lookup that cached its
/// answer, or read a plain global, would leave the interface in the old
/// language until something else invalidated it.
///
/// Fallbacks, in order: the active language, then English, then the key's own
/// name. The switches in `S` have no `default:`, so a *missing* translation is
/// a build error and the only way to reach the fallback is an entry that was
/// deliberately or accidentally left blank — which is what the emptiness check
/// below is for. It never returns an empty string.
/// A string kept at its point of use, in both languages (2026-09-28).
///
/// The table above is for strings used in more than one place. Settings holds
/// some eighty that each appear once — captions, readouts, button titles —
/// and a pair written where the string is shown keeps the English and the
/// Chinese side by side for review, which the table cannot. An empty Chinese
/// string falls back to the English, as the table does.
@MainActor
func L(_ english: String, zh chinese: String) -> String {
    switch Localization.shared.resolved {
    case .english: english
    case .simplifiedChinese: chinese.isEmpty ? english : chinese
    }
}

@MainActor
func L(_ key: S) -> String {
    switch Localization.shared.resolved {
    case .english:
        return key.english.nilIfEmpty ?? key.rawValue
    case .simplifiedChinese:
        return key.simplifiedChinese.nilIfEmpty
            ?? key.english.nilIfEmpty
            ?? key.rawValue
    }
}

/// Bilingual copy for page-specific sentences that do not belong to the
/// editor's terminology table. Reading `resolved` here keeps live language
/// switching observable in SwiftUI, just like `L(_:)`.
@MainActor
func T(_ english: String, _ simplifiedChinese: String) -> String {
    Localization.shared.resolved == .simplifiedChinese ? simplifiedChinese : english
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - enums whose own `title` is a display string

//  Four enums carry their display name themselves rather than being given one
//  by a view. Two of them are **asserted by name in the test suite**
//  (`WhiteBalanceTests` pins `ExposureMethod.title`'s lowercase English, and
//  `title(forWire:)` falls back to the raw wire value for a method it does not
//  know), so none of them is rewritten here: the mapping to a key lives beside
//  the table instead, and a view asks for `L(x.key)`.
//
//  That also keeps `Model/` free of the main actor — every one of these is a
//  `nonisolated` computed property on a `Sendable` enum, which is what lets it
//  be read from a `PillMenu`'s `(T) -> String`.

extension Session.BootPhase {
    /// The one line under the progress bar.
    var key: S {
        switch self {
        case .starting: .bootStarting
        case .warming: .bootWarming
        case .ready: .bootReady
        case .failed: .bootReady        // unreachable: a failure draws its own
        }
    }
}

extension LogLevelSetting {
    /// The pill's label, and the one sentence under it (§6: Detailed and
    /// Verbose revert to Normal on the next launch, and the caption says so —
    /// a user who turns one on to capture something must not be left wondering
    /// whether it stayed on).
    var key: S {
        switch self {
        case .normal: .setLevelNormal
        case .detailed: .setLevelDetailed
        case .verbose: .setLevelVerbose
        }
    }

    var detailKey: S {
        switch self {
        case .normal: .setLevelNormalDetail
        case .detailed: .setLevelDetailedDetail
        case .verbose: .setLevelVerboseDetail
        }
    }
}

extension AEMethod {
    /// The metering pill's name for this method.
    ///
    /// `ExposureMethod.title` is lowercase ("balanced") and the pill used to
    /// capitalise it; the table's English is already the capitalised form, so
    /// the call site needs no `capitalizedFirst`. The Chinese has no case, so
    /// nothing is lost by the two agreeing on one form.
    var key: S {
        switch self {
        case .custom: .meteringCustom
        case .metered(.balanced): .meteringBalanced
        case .metered(.center): .meteringCenter
        case .metered(.protectHighlights): .meteringProtectHighlights
        case .metered(.protectShadows): .meteringProtectShadows
        case .legacy: .meteringCenterWeightedLegacy
        }
    }
}

extension FilmSide {
    var key: S { self == .short ? .filmFormatShort : .filmFormatLong }
}

extension CropAspect {
    /// `nil` for a ratio. `1:1`, `3:2`, `16:9` and the rest are aspect ratios,
    /// which the spec keeps as they are; they have no translation and the view
    /// falls back to `label`.
    ///
    /// The ratio cases are written out rather than covered by a `default:` so
    /// that a new *translatable* case cannot arrive silently — it would have
    /// to be given a key or explicitly listed as English here.
    var key: S? {
        switch self {
        case .free: .cropAspectFree
        case .original, .originalPortrait: .cropAspectOriginal
        case .square, .r3x2, .r2x3, .r4x3, .r3x4,
             .r16x9, .r9x16, .r5x4, .r4x5, .r7x5, .r5x7: nil
        }
    }
}

extension CurveChannel {
    /// `nil` for `rgb`: RGB is on the spec's retain-English list, so the
    /// channel has no translation and shows its own `title`.
    var key: S? {
        switch self {
        case .luma: .curveLuma
        case .red: .curveRed
        case .green: .curveGreen
        case .blue: .curveBlue
        case .rgb: nil
        }
    }
}

// MARK: - catalogue group headers

//  Film and paper lists are grouped, and a group's title comes from the
//  catalogue rather than from the view — `StockCatalog.filmGroups` returns
//  "Positive"/"Negative" and `paperGroups` "Still"/"Cine". Those four are the
//  spec's rows, so they are translated.
//
//  The title is also the row's **identity** — `"__group_" + group.title` — so
//  nothing here renames a group. These take the catalogue's title and return a
//  *label*; the id keeps the English in every caller.
//
//  An unknown title comes back unchanged, which is a real branch rather than a
//  formality: a catalogue that grows a third group gets its own name in both
//  languages rather than an empty header or a crash.

/// A film-list group header — Positive / Negative.
@MainActor func L(filmGroup title: String) -> String {
    switch title {
    case "Positive": return L(.filmGroupPositive)
    case "Negative": return L(.filmGroupNegative)
    default: return title
    }
}

/// A paper-list group header — Still / Cine.
@MainActor func L(paperGroup title: String) -> String {
    switch title {
    case "Still": return L(.printGroupStill)
    case "Cine": return L(.printGroupCine)
    default: return title
    }
}
