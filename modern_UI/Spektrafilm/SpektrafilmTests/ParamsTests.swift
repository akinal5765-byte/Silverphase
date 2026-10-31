import XCTest

final class ParamsTests: XCTestCase {
    func testRetiredPrintCompensationSettingDoesNotAffectSavedPhotos() throws {
        let original = FilmParams.default
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json["printExposureCompensation"] = true
        let restored = try JSONDecoder().decode(FilmParams.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored, original)
        XCTAssertNil(restored.fullDelta["print_exposure_compensation"])
    }

    func testCameraFiltersSaveAndInvalidateNegative() throws {
        var p = FilmParams.default
        XCTAssertEqual(p.cameraFilter, .off)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        json.removeValue(forKey: "cameraFilter")
        XCTAssertEqual(try JSONDecoder().decode(FilmParams.self, from: JSONSerialization.data(withJSONObject: json)).cameraFilter, .off)
        json["cameraFilter"] = "w99"
        XCTAssertEqual(try JSONDecoder().decode(FilmParams.self, from: JSONSerialization.data(withJSONObject: json)).cameraFilter, .off)
        for filter in CameraFilterChoice.allCases {
            p.cameraFilter = filter
            XCTAssertEqual(p.fullDelta["camera_filter"], .string(filter.rawValue))
            XCTAssertEqual(try JSONDecoder().decode(FilmParams.self, from: JSONEncoder().encode(p)), p)
            if filter != .off { XCTAssertEqual(p.delta(from: .default).layers, [.shoot]) }
        }
        XCTAssertEqual(CameraFilterChoice.allCases.count, 9)
    }


    func testMultigradeSelectionUsesPackAndExposureCompensation() throws {
        var p = FilmParams.default
        p.filmStock = "kodak_tri_x_400"
        p.printStock = "ilford_multigrade_iv_rc"
        p.printBrightnessStops = 1
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        json["paperGrade"] = "5"
        let selected = try JSONDecoder().decode(FilmParams.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(selected.fullDelta["m_filter_neutral"], .double(151.7))
        XCTAssertEqual(selected.fullDelta["y_filter_neutral"], .double(0))
        XCTAssertEqual(selected.fullDelta["print_exposure"]?.doubleValue ?? 0, 0.5 * 1.3507, accuracy: 1e-10)
        XCTAssertEqual(selected.delta(from: p).layers, [.print])
    }

    func testPaperGradeDefaultsRoundTripsAndKeepsColorSettings() throws {
        var p = FilmParams.default
        XCTAssertEqual(p.paperGrade, .two)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        json.removeValue(forKey: "paperGrade")
        XCTAssertEqual(try JSONDecoder().decode(FilmParams.self, from: JSONSerialization.data(withJSONObject: json)).paperGrade, .two)
        json["paperGrade"] = "unknown"
        XCTAssertEqual(try JSONDecoder().decode(FilmParams.self, from: JSONSerialization.data(withJSONObject: json)).paperGrade, .two)
        for grade in PaperGrade.allCases {
            p.paperGrade = grade
            let restored = try JSONDecoder().decode(FilmParams.self, from: JSONEncoder().encode(p))
            XCTAssertEqual(restored, p)
            XCTAssertTrue(p.delta(from: .default).delta.isEmpty, "grade has no effect on a colour paper")
        }
        p.paperGrade = .five
        p.printStock = "ilford_multigrade_iv_rc"
        p.mFilterShift = 21
        p.yFilterShift = -13
        XCTAssertEqual(p.fullDelta["m_filter_shift"], .double(0))
        XCTAssertEqual(p.fullDelta["y_filter_shift"], .double(0))
        p.scanFilm = true
        var other = p; other.paperGrade = .softest
        XCTAssertTrue(p.delta(from: other).delta.isEmpty)
        p.scanFilm = false; p.digitalIntermediate = true
        other = p; other.paperGrade = .softest
        XCTAssertTrue(p.delta(from: other).delta.isEmpty)
        p.digitalIntermediate = false; p.printStock = "kodak_supra_endura"
        XCTAssertEqual(p.fullDelta["m_filter_shift"], .double(21))
        XCTAssertEqual(p.fullDelta["y_filter_shift"], .double(-13))
        XCTAssertEqual(p.paperGrade, .five)
    }

    func testEveryMultigradePackMatchesTheShippedTable() throws {
        let url = try XCTUnwrap(StockCatalog.bundle.url(forResource: "paper_grades", withExtension: "json", subdirectory: "Resources/engine"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let grades = try XCTUnwrap(json["grades"] as? [String: [String: Double]])
        XCTAssertEqual(Set(grades.keys), Set(PaperGrade.allCases.map(\.rawValue)))
        for grade in PaperGrade.allCases {
            var p = FilmParams.default
            p.printStock = "ilford_multigrade_iv_rc"; p.paperGrade = grade
            let row = try XCTUnwrap(grades[grade.rawValue])
            XCTAssertEqual(p.fullDelta["m_filter_neutral"], .double(row["m_filter_neutral"]!))
            XCTAssertEqual(p.fullDelta["y_filter_neutral"], .double(row["y_filter_neutral"]!))
            XCTAssertEqual(p.fullDelta["print_exposure"], .double(row["print_exposure"]!))
            p.printBrightnessStops = -100
            XCTAssertLessThanOrEqual(p.effectivePrintExposure, 20)
        }
    }

    func testUpstreamBlackWhiteWireAndLegacySidecars() throws {
        for (stock, grain) in [("kodak_tri_x_400", 1.70), ("ilford_hp5_plus_400", 1.49),
                               ("kodak_tmax_100", 0.74), ("fujifilm_neopan_acros_100_ii", 0.64)] {
            var p = FilmParams.default
            p.filmStock = stock
            p.printStock = "ilford_multigrade_iv_rc"
            p.effects.grain = 1
            p.effects.grainLayered = true
            XCTAssertEqual(p.fullDelta["grain_amount"], .double(grain))
            XCTAssertEqual(p.fullDelta["grain_sublayers_active"], .bool(false))
            XCTAssertEqual(p.fullDelta["extended_dynamic_range"], .bool(false))
            XCTAssertEqual(p.fullDelta["y_filter_neutral"], .double(68))
            p.effects.grain = 2
            XCTAssertEqual(p.fullDelta["grain_amount"], .double(min(2, 2 * grain)))
        }
        for stock in ["kodak_tri_x_400", "ilford_hp5_plus_400"] {
            var old = FilmParams.default
            old.filmStock = stock + "_experimental"
            old.printStock = "silverphase_neutral_bw_print_experimental"
            let restored = try JSONDecoder().decode(FilmParams.self, from: JSONEncoder().encode(old))
            XCTAssertEqual(restored.filmStock, stock)
            XCTAssertEqual(restored.printStock, "ilford_multigrade_iv_rc")
            XCTAssertEqual(restored.fullDelta, old.fullDelta)
        }
        var retired = FilmParams.default
        retired.filmStock = "ilford_xp2_super_400_experimental"
        let restored = try JSONDecoder().decode(FilmParams.self, from: JSONEncoder().encode(retired))
        XCTAssertEqual(restored.filmStock, retired.filmStock, "a missing material must not silently become another film")
        XCTAssertNil(StockCatalog(stocks: StockCatalog.shared.stocks.filter { !$0.isExperimental }).stock(restored.filmStock))
    }

    func testGrainSoftnessRoutesToFilmWithoutChangingParticleSize() {
        var p = FilmParams.default
        XCTAssertEqual(p.fullDelta["grain_softness"], .double(0.65))
        p.grainSoftness = 2
        let delta = p.delta(from: .default)
        XCTAssertEqual(delta.layers, [.shoot])
        XCTAssertEqual(delta.delta, ["grain_softness": .double(1.3)])
        XCTAssertEqual(p.grainSizeScale, 1)
        p.grainSoftness = -1
        XCTAssertEqual(p.fullDelta["grain_softness"], .double(0))
        p.grainSoftness = 9
        XCTAssertEqual(p.fullDelta["grain_softness"], .double(1.3))
    }

    func testGrainSoftnessSidecarCompatibilityAndRoundTrip() throws {
        let original = Sidecar()
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        var params = try XCTUnwrap(root["params"] as? [String: Any])
        params.removeValue(forKey: "grainSoftness")
        root["params"] = params
        let legacy = try JSONDecoder().decode(Sidecar.self, from: JSONSerialization.data(withJSONObject: root))
        XCTAssertEqual(legacy.params, original.params)
        var changed = original
        changed.params.grainSoftness = 0
        let restored = try JSONDecoder().decode(Sidecar.self, from: JSONEncoder().encode(changed))
        XCTAssertEqual(restored.params, changed.params)
    }

    func testScannerSharpeningRoutesToScanAndPreservesStrengthWhenOff() {
        var p = FilmParams.default
        XCTAssertEqual(p.fullDelta["scanner_sharpening_amount"], .double(0.7))
        p.scannerSharpeningStrength = 2
        XCTAssertEqual(p.delta(from: .default).layers, [.print])
        XCTAssertEqual(p.delta(from: .default).delta["scanner_sharpening_amount"], .double(1.4))
        p.scannerSharpeningActive = false
        XCTAssertEqual(p.fullDelta["scanner_sharpening_amount"], .double(0))
        XCTAssertEqual(p.scannerSharpeningStrength, 2)
        p.scannerSharpeningActive = true
        XCTAssertEqual(p.fullDelta["scanner_sharpening_amount"], .double(1.4))
        p.scannerSharpeningStrength = -1
        XCTAssertEqual(p.fullDelta["scanner_sharpening_amount"], .double(0))
        p.scannerSharpeningStrength = 9
        XCTAssertEqual(p.fullDelta["scanner_sharpening_amount"], .double(1.4))
    }

    func testScannerSharpeningSidecarCompatibilityAndRoundTrip() throws {
        let original = Sidecar()
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        var params = try XCTUnwrap(root["params"] as? [String: Any])
        params.removeValue(forKey: "scannerSharpeningActive")
        params.removeValue(forKey: "scannerSharpeningStrength")
        root["params"] = params
        let legacy = try JSONDecoder().decode(Sidecar.self, from: JSONSerialization.data(withJSONObject: root))
        XCTAssertEqual(legacy.params, original.params)

        var changed = original
        changed.params.scannerSharpeningActive = false
        changed.params.scannerSharpeningStrength = 1.6
        let restored = try JSONDecoder().decode(Sidecar.self, from: JSONEncoder().encode(changed))
        XCTAssertEqual(restored.params, changed.params)
    }

    func testDeltaIsEmptyForEqualParams() {
        let (d, l) = FilmParams.default.delta(from: .default)
        XCTAssertTrue(d.isEmpty); XCTAssertTrue(l.isEmpty)
    }

    func testPrintSliderRoutesToPrintLayer() {
        var p = FilmParams.default
        p.printBrightnessStops = 1
        let (d, l) = p.delta(from: .default)
        XCTAssertEqual(l, [.print])
        XCTAssertEqual(d["print_exposure"]?.doubleValue ?? 0, 0.5, accuracy: 1e-9, "brighter by one stop = half the enlarger exposure")
    }

    func testPrintFilterShiftsStayInKodakCCUnits() {
        var p = FilmParams.default
        p.yFilterShift = -50
        p.mFilterShift = 50
        let (delta, layers) = p.delta(from: .default)
        XCTAssertEqual(layers, [.print])
        XCTAssertEqual(delta["y_filter_shift"], .double(-50))
        XCTAssertEqual(delta["m_filter_shift"], .double(50))

        // Existing sidecars with fractional CC values are passed through,
        // not silently rescaled when the UI range grows.
        p = .default
        p.yFilterShift = 0.4
        XCTAssertEqual(p.delta(from: .default).delta["y_filter_shift"], .double(0.4))
    }

    func testPhysicalControlsRouteToTheirActualStages() {
        var p = FilmParams.default
        p.halationAmount = 1.5
        p.developmentContrast = 1.1
        p.colorSeparation = 0.8
        let shoot = p.delta(from: .default)
        XCTAssertEqual(shoot.layers, [.shoot])
        XCTAssertEqual(shoot.delta["halation_amount"], .double(1.5))
        XCTAssertEqual(shoot.delta["density_curve_gamma"], .double(1.1))
        XCTAssertEqual(shoot.delta["dir_couplers_amount"], .double(0.8))

        p = .default
        p.halationAmount = 4
        XCTAssertEqual(p.delta(from: .default).delta["halation_amount"], .double(4))

        p = .default
        p.antihalationMode = "none"
        XCTAssertEqual(p.delta(from: .default).layers, [.shoot])
        XCTAssertEqual(p.delta(from: .default).delta["antihalation_mode"], .string("none"))

        p = .default
        p.preflashExposure = 0.25
        let printDelta = p.delta(from: .default)
        XCTAssertEqual(printDelta.layers, [.print])
        XCTAssertEqual(printDelta.delta["preflash_exposure"], .double(0.25))
    }

    func testGrainSizeAndPrintContrastKeepTheirStageAndIdentity() {
        let defaults = FilmParams.default
        XCTAssertEqual(defaults.grainSizeScale, 1)
        XCTAssertEqual(defaults.printContrast, 1)
        var p = defaults
        p.grainSizeScale = 1.5
        var delta = p.delta(from: defaults)
        XCTAssertEqual(delta.layers, [.shoot])
        XCTAssertEqual(delta.delta["grain_size_scale"], .double(1.5))

        p = defaults
        p.printContrast = 1.2
        delta = p.delta(from: defaults)
        XCTAssertEqual(delta.layers, [.print])
        XCTAssertEqual(delta.delta["print_contrast"], .double(1.2))
    }

    func testDiffusionRoutesToItsPhysicalStage() {
        var p = FilmParams.default
        p.cameraDiffusion = DiffusionChoice.blackProMist.rawValue
        p.cameraDiffusionStrength = 1
        var delta = p.delta(from: .default)
        XCTAssertEqual(delta.layers, [.shoot])
        XCTAssertEqual(delta.delta["camera_diffusion_active"], .bool(true))
        XCTAssertEqual(delta.delta["camera_diffusion_strength"], .double(1))
        p = .default
        p.cameraDiffusionRange = 1.5
        delta = p.delta(from: .default)
        XCTAssertEqual(delta.layers, [.shoot])
        XCTAssertEqual(delta.delta["camera_diffusion_range"], .double(1.5))

        p = .default
        p.enlargerDiffusion = DiffusionChoice.cinebloom.rawValue
        delta = p.delta(from: .default)
        XCTAssertEqual(delta.layers, [.print])
        XCTAssertEqual(delta.delta["enlarger_diffusion_family"], .string("cinebloom"))
        p.scanFilm = true
        XCTAssertEqual(p.wire.first { $0.name == "enlarger_diffusion_active" }?.value, .bool(false))

        p = .default
        p.enlargerDiffusionRange = 0.8
        delta = p.delta(from: .default)
        XCTAssertEqual(delta.layers, [.print])
        XCTAssertEqual(delta.delta["enlarger_diffusion_range"], .double(0.8))
    }

    func testOldSidecarDefaultsNewScaleAndContrastToIdentity() throws {
        let original = Sidecar()
        guard var root = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any],
              var params = root["params"] as? [String: Any] else {
            return XCTFail("encoded sidecar did not contain params")
        }
        params.removeValue(forKey: "grainSizeScale")
        params.removeValue(forKey: "printContrast")
        for key in ["cameraDiffusion", "cameraDiffusionStrength", "cameraDiffusionRange",
                    "enlargerDiffusion", "enlargerDiffusionStrength", "enlargerDiffusionRange"] {
            params.removeValue(forKey: key)
        }
        root["params"] = params
        let legacy = try JSONSerialization.data(withJSONObject: root)
        XCTAssertEqual(try JSONDecoder().decode(Sidecar.self, from: legacy).params, original.params)
    }

    func testOldSidecarDefaultsNewPhysicalControlsToProfileValues() throws {
        let original = Sidecar()
        guard var root = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any],
              var params = root["params"] as? [String: Any] else {
            return XCTFail("encoded sidecar did not contain params")
        }
        for key in ["halationAmount", "antihalationMode", "developmentContrast", "colorSeparation", "preflashExposure"] {
            params.removeValue(forKey: key)
        }
        root["params"] = params
        let old = try JSONSerialization.data(withJSONObject: root)
        XCTAssertEqual(try JSONDecoder().decode(Sidecar.self, from: old).params, original.params)
    }

    func testPreflashKeepsLegacyRawValueThroughSidecarAndWire() throws {
        var sidecar = Sidecar()
        sidecar.params.preflashExposure = 0.25
        let decoded = try JSONDecoder().decode(Sidecar.self,
                                               from: JSONEncoder().encode(sidecar))
        XCTAssertEqual(decoded.params.preflashExposure, 0.25)
        XCTAssertEqual(decoded.params.delta(from: .default).delta["preflash_exposure"],
                       .double(0.25))
    }

    func testExtendedDynamicRangeDefaultsOnAndRoutesToPrintLayer() {
        XCTAssertTrue(FilmParams.default.extendedDynamicRange)
        XCTAssertEqual(FilmParams.default.wire.first { $0.name == "extended_dynamic_range" }?.value,
                       .bool(true))

        var p = FilmParams.default
        p.extendedDynamicRange = false
        let (delta, layers) = p.delta(from: .default)
        XCTAssertEqual(layers, [.print])
        XCTAssertEqual(delta["extended_dynamic_range"], .bool(false))

        // The preference stays in the sidecar when the Positive / No Print
        // Profile row is selected, but its effective wire value is forced off
        // so direct film scanning cannot be changed by a persisted EDR choice.
        p.extendedDynamicRange = true
        p.scanFilm = true
        XCTAssertTrue(p.extendedDynamicRange)
        XCTAssertFalse(p.effectiveExtendedDynamicRange)
        var activePrint = FilmParams.default
        activePrint.extendedDynamicRange = true
        XCTAssertEqual(p.delta(from: activePrint).delta["extended_dynamic_range"], .bool(false))
    }

    func testSidecarMissingOnlyExtendedDynamicRangeDefaultsOff() throws {
        var sidecar = Sidecar()
        sidecar.params.extendedDynamicRange = true
        let original = sidecar.params
        guard var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(sidecar)) as? [String: Any],
              var params = object["params"] as? [String: Any]
        else { return XCTFail("encoded sidecar did not contain params") }
        XCTAssertNotNil(params.removeValue(forKey: "extendedDynamicRange"))
        object["params"] = params
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(Sidecar.self, from: legacy)

        var expected = original
        expected.extendedDynamicRange = false
        XCTAssertEqual(decoded.params, expected)
    }

    func testShootFieldsRouteToShootLayer() {
        var p = FilmParams.default
        p.grainActive = false
        p.filmFormatMM = 56
        let (d, l) = p.delta(from: .default)
        XCTAssertEqual(l, [.shoot])
        XCTAssertEqual(Set(d.keys), ["grain_active", "grain_sublayers_active", "film_format_mm"])
    }

    func testFilmChangeInvalidatesBothLayers() {
        var p = FilmParams.default
        p.filmStock = "kodak_vision3_250d"
        XCTAssertEqual(p.delta(from: .default).layers, [.shoot, .print])
    }

    func testWireNamesMatchTheServiceSchema() {
        // The names the Python schema declares (service/schema.py). A rename
        // there must be mirrored here or the delta is rejected at runtime.
        let known: Set<String> = ["overscan_active", "date_imprint_active", "scene_latitude_split", "scene_latitude_b_active", "camera_filter", "film_stock", "print_stock", "exposure_compensation_ev", "film_format_mm",
                                  "grain_active", "grain_sublayers_active", "grain_size_scale", "grain_softness",
                                  "camera_diffusion_active", "camera_diffusion_family", "camera_diffusion_strength", "camera_diffusion_range",
                                  "enlarger_diffusion_active", "enlarger_diffusion_family", "enlarger_diffusion_strength", "enlarger_diffusion_range",
                                  "halation_active", "print_exposure", "print_contrast",
                                  "y_filter_shift", "m_filter_shift", "glare_active", "scan_film",
                                  "extended_dynamic_range", "halation_amount", "antihalation_mode", "density_curve_gamma",
                                  "dir_couplers_amount", "dir_couplers_active", "preflash_exposure",
                                  "grain_amount", "glare_amount", "halation_scatter_amount", "scanner_sharpening_amount",
                                  "digital_intermediate", "digital_intermediate_blue_compensation",
                                  "contrast_mask_active", "contrast_mask_highlights", "contrast_mask_shadows",
                                  "contrast_mask_core", "contrast_mask_scale", "contrast_mask_scheme",
                                  "scene_latitude_active", "scene_latitude_norm", "scene_latitude_highlight_knee",
                                  "scene_latitude_highlight_room", "scene_latitude_shadow_knee", "scene_latitude_shadow_room",
                                  "scene_latitude_rolloff", "scene_latitude_max_lift",
                                  // RFC-015 §3. Shoot layer; absent from a legacy
                                  // frame's delta, which is why this list holds
                                  // the name and `wire` only carries it when set.
                                  "auto_exposure_method",
                                  // The AE Method pill's `Custom` — the meter
                                  // switched off. Declared by the engine all
                                  // along (`camera.auto_exposure`) and never
                                  // sent until the 2026-09-17 rework, which is
                                  // why `Custom` needed no new field.
                                  "auto_exposure"]
        XCTAssertEqual(Set(FilmParams.default.wire.map(\.name)), known)
    }

    /// `Custom` is `auto_exposure = false` and nothing else, and the four
    /// intents are the flag **plus** the method — so turning the meter off and
    /// on again comes back to the intent it had.
    func testAEMethodIsTheFlagAndTheMethod() {
        var p = FilmParams.default
        XCTAssertEqual(AEMethod.of(p), .legacy)

        AEMethod.custom.apply(to: &p)
        XCTAssertFalse(p.autoExposure)
        XCTAssertEqual(p.autoExposureMethod, "center_weighted", "Custom must not forget the intent")
        XCTAssertEqual(AEMethod.of(p), .custom)
        XCTAssertEqual(p.delta(from: .default).delta["auto_exposure"], .bool(false))
        XCTAssertNil(p.delta(from: .default).delta["auto_exposure_method"],
                     "turning the meter off is not a change of intent")

        AEMethod.metered(.protectHighlights).apply(to: &p)
        XCTAssertTrue(p.autoExposure)
        XCTAssertEqual(p.autoExposureMethod, "protect_highlights")

        // A sidecar written before the method existed: the engine's own
        // `center_weighted`, now also selectable from the menu.
        let previous = p
        AEMethod.legacy.apply(to: &p)
        XCTAssertEqual(p.autoExposureMethod, "center_weighted")
        XCTAssertEqual(AEMethod.of(p), .legacy)
        XCTAssertTrue(AEMethod.offered.contains(.legacy))
        XCTAssertEqual(p.delta(from: previous).delta["auto_exposure_method"],
                       .string("center_weighted"), "Selecting the original meter must reach an already-open engine session")
    }

    /// The physical frame: the user says a type, a side and a length, and the
    /// engine gets a **long edge**.
    func testTheFrameDerivesTheEngineSLongEdge() {
        let m: (FilmSide, Double, Double) -> Double = { Session.filmFormatMM(side: $0, sideLengthMM: $1, aspect: $2) }
        // 135, short side 24, on a 3:2 photograph — the drawing's own row, and
        // it has to come out at the 36 the old single-number Format sent.
        XCTAssertEqual(m(.short, 24, 3.0 / 2.0), 36, accuracy: 1e-9)
        // Side = Long passes straight through, whatever the photograph is.
        XCTAssertEqual(m(.long, 36, 3.0 / 2.0), 36, accuracy: 1e-9)
        XCTAssertEqual(m(.long, 36, 1.0), 36, accuracy: 1e-9)
        // **The whole reason there are three controls.** One `120` entry, one
        // 56 mm short side, and 645 / 6×6 / 6×7 each come out right because
        // the photograph's own aspect is what closes the gap.
        XCTAssertEqual(m(.short, 56, 1.0), 56, accuracy: 1e-9)          // 6×6
        XCTAssertEqual(m(.short, 56, 7.0 / 6.0), 65.333, accuracy: 0.01) // 6×7
        XCTAssertEqual(m(.short, 56, 4.0 / 3.0), 74.666, accuracy: 0.01) // 6×8
        // An aspect below 1 is a portrait photograph, which is the same frame
        // turned round — not a shorter long edge.
        XCTAssertEqual(m(.short, 24, 0.5), 24, accuracy: 1e-9)
        // And the service's range is a range: 200 is the ceiling, 4 the floor.
        XCTAssertEqual(m(.short, 56, 20), 200, accuracy: 1e-9)
        XCTAssertEqual(m(.long, 1, 1), 4, accuracy: 1e-9)
    }

    func testCustomSideLengthMatchesTheEngineRange() {
        let aspect = 3.0 / 2.0
        let short = Session.customSideLength(500, side: .short, aspect: aspect)
        XCTAssertEqual(short, 200 / aspect, accuracy: 1e-9)
        XCTAssertEqual(Session.filmFormatMM(side: .short, sideLengthMM: short,
                                            aspect: aspect), 200, accuracy: 1e-9)

        let long = Session.customSideLength(500, side: .long, aspect: aspect)
        XCTAssertEqual(long, 200, accuracy: 1e-9)
        XCTAssertEqual(Session.filmFormatMM(side: .long, sideLengthMM: long,
                                            aspect: aspect), 200, accuracy: 1e-9)

        let minimum = Session.customSideLength(0, side: .short, aspect: aspect)
        XCTAssertEqual(minimum, 4 / aspect, accuracy: 1e-9)
        XCTAssertEqual(Session.filmFormatMM(side: .short, sideLengthMM: minimum,
                                            aspect: aspect), 4, accuracy: 1e-9)
    }

    /// Every preset lands inside the service's 4…200 on an ordinary
    /// photograph, on either side.
    func testEveryFilmFrameIsWithinTheServiceRange() {
        for f in FilmFrame.all {
            for side in FilmSide.allCases {
                let mm = Session.filmFormatMM(side: side, sideLengthMM: f.side(side),
                                              aspect: 3.0 / 2.0)
                XCTAssertTrue((4...200).contains(mm), "\(f.id) \(side.rawValue) → \(mm)")
            }
        }
        XCTAssertEqual(FilmFrame.named("135").short, 24)
        XCTAssertEqual(FilmFrame.named("nonsense").id, FilmFrame.custom.id,
                       "an unknown id is Custom, not a crash")
    }

    /// Display only, and it has to survive the round trip a typed value makes.
    func testSideUnitsConvert() {
        XCTAssertEqual(SideUnit.mm.fromMM(24), 24, accuracy: 1e-9)
        XCTAssertEqual(SideUnit.cm.fromMM(56), 5.6, accuracy: 1e-9)
        XCTAssertEqual(SideUnit.inch.fromMM(25.4), 1, accuracy: 1e-9)
        for u in SideUnit.allCases {
            XCTAssertEqual(u.toMM(u.fromMM(56)), 56, accuracy: 1e-9, u.rawValue)
        }
        // Three decimals on inches, because 135 is 0.945 in and at one decimal
        // every still format reads as the same film.
        XCTAssertGreaterThan(SideUnit.inch.decimals, SideUnit.mm.decimals)
    }

    func testParamValueJSON() throws {
        let enc = try JSONEncoder().encode(["a": ParamValue.double(1.5), "b": .bool(true), "c": .string("x")])
        let dec = try JSONDecoder().decode([String: ParamValue].self, from: enc)
        XCTAssertEqual(dec["a"], .double(1.5)); XCTAssertEqual(dec["b"], .bool(true)); XCTAssertEqual(dec["c"], .string("x"))
    }

    func testSidecarRoundTrip() throws {
        var s = Sidecar()
        s.params.yFilterShift = 0.3
        s.adjustments.curves.rgb.insert(CGPoint(x: 0.4, y: 0.5))
        s.geometry.crop = CropRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(Sidecar.self, from: data)
        XCTAssertEqual(back, s)
    }
}
