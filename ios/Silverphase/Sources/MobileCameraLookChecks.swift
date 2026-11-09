#if DEBUG
import Foundation
import CoreImage
import Metal
import ImageIO
import UniformTypeIdentifiers

/// Compare actual video-preview rendering against the independent file/develop
/// path, rather than checking only an approximation's internal consistency.
enum MobileCameraLookChecks {
    @MainActor static func run() async {
        let folder = URL.temporaryDirectory.appendingPathComponent("Camera-Look-Checks-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let report = URL.documentsDirectory.appendingPathComponent("camera-look-report.json")
        var checks: [String] = []
        var maximumReferenceDifference = 0
        var diffusionDifferences: [String: Int] = [:]
        var timings: [String: [Double]] = [:]
        var environment: [String: Any] = ["os": ProcessInfo.processInfo.operatingSystemVersionString,
            "thermalStateAtStart": ProcessInfo.processInfo.thermalState.rawValue,
            "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled]
        do {
            func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
                if !condition() { throw MobileFailure.message(message) }
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let inputLevels = (1...100).map { Double($0) / 125 }
            let videoSummary = try MobileCameraExposureSummary.make(inputLevels, aspect: 4.0 / 3)
            let halfRaw = try MobileCameraExposureSummary.make(inputLevels.map { $0 * 0.5 }, aspect: 3.0 / 4)
            let uniform = MobileCameraExposureSummary.compare(raw: halfRaw, video: videoSummary)
            try require(abs((uniform["medianEV"] as? Double ?? 10) + 1) < 0.000001 &&
                        uniform["consistentWithUniformGain"] as? Bool == true, "Exposure probe lost the direction of a one-stop input difference")
            let curvedRaw = try MobileCameraExposureSummary.make(inputLevels.map { pow($0, 1.8) }, aspect: 4.0 / 3)
            try require(MobileCameraExposureSummary.compare(raw: curvedRaw, video: videoSummary)["consistentWithUniformGain"] as? Bool == false,
                        "Exposure probe called a tone-curve difference a constant gain")
            let wrongAspect = try MobileCameraExposureSummary.make(inputLevels, aspect: 16.0 / 9)
            try require(MobileCameraExposureSummary.compare(raw: wrongAspect, video: videoSummary)["status"] as? String == "different_field_of_view", "Mismatched frame coverage accepted")
            let black = try MobileCameraExposureSummary.make([0, 0, 0], aspect: 4.0 / 3)
            try require(MobileCameraExposureSummary.compare(raw: black, video: black)["status"] as? String == "insufficient_midtones", "Black input produced a calibration")
            checks.append("input exposure diagnostic distinguishes signed scalar EV from tone curves, rejects field-of-view mismatch and unusable black frames; applies no correction")

            let sampleMixing = try checkColorSampleContract()
            checks.append("colour sample layout/permutation invariance for negative/B&W/slide/CineStill; old photo-render lattice mixing reproduced (max16bit=\(sampleMixing)); saved params/results preserved")

            try checkReplacementContract()
            checks.append("native replacement rejects invalid inputs transactionally, copies borrowed pixels and retains old results")
            let small = try makeFrame(width: 48, height: 32, serial: 1)
            let mailbox = MobileCameraLookFrames()
            for _ in 0..<20 { mailbox.store(small.buffer, rotation: 0) }
            let held = mailbox.latest()!
            mailbox.clear()
            try require(held.serial == 20 && mailbox.latest() == nil, "Frame mailbox is not latest-only")
            try require(CVPixelBufferGetWidth(held.buffer) == 48, "Acquired video frame was released early")
            checks.append("latest-only video mailbox and acquired-frame lifetime after clear")

            let firstGeneration = mailbox.beginConfiguration()
            try require(mailbox.latest() == nil && mailbox.currentGeneration() == firstGeneration, "Input change retained an old video frame")
            mailbox.store(small.buffer, rotation: 0)
            try require(mailbox.latest()?.generation == firstGeneration && held.generation == 0,
                        "Input generations do not preserve acquired-frame identity")
            checks.append("physical/portrait input configuration clears queued frame and advances generation; acquired old frame identity stays immutable")

            let source = folder.appendingPathComponent("source.tiff")
            try writeFrame(small, to: source)
            let preview = MobileCameraLookEngine(), reference = MobileEngine()
            let films = ["kodak_portra_400", "ilford_hp5_plus_400", "kodak_ektachrome_100"]
            var kept: MobileCameraLookResult?
            var keptBytes: Data?
            var comparisons = 0
            for film in films {
                var modeOutputs = Set<Data>()
                for meter in MobileMeteringMode.allCases {
                    let recipe = MobileCameraRecipe(filmID: film, metering: meter, diffusion: .off)
                    let live = try await preview.render(small, angle: 0, mirrored: false, recipe: recipe, longEdge: 640)
                    let intent = try MobileCameraLookEngine.intent(recipe)
                    let developed = try await reference.render(url: source, recipe: intent, megapixels: 0.01)
                    let expected = try await reference.canvasImage(developed.image)
                    try require(live.image.width == expected.width && live.image.height == expected.height, "Video/file dimensions differ")
                    let difference = maxDifference(live.image, expected)
                    maximumReferenceDifference = max(maximumReferenceDifference, difference)
                    try require(difference <= 1, "Video/file colour mismatch for \(film)/\(meter.rawValue): \(difference) counts")
                    modeOutputs.insert(pixelData(live.image))
                    if kept == nil { kept = live; keptBytes = pixelData(live.image) }
                    comparisons += 1
                }
                try require(modeOutputs.count >= 3, "Metering modes did not affect the actual native preview")
            }
            try require(comparisons == 18, "Missing colour/meter reference comparisons")
            checks.append("18 native preview vs file/develop comparisons: negative/B&W/slide and all six metering modes")

            // Same-size, same-recipe consecutive frames must re-meter and
            // invalidate the tier source/negative, not silently reuse either.
            let changed = try makeFrame(width: 48, height: 32, serial: 3, highlight: true)
            let changedSource = folder.appendingPathComponent("changed.tiff")
            try writeFrame(changed, to: changedSource)
            for meter in MobileMeteringMode.allCases {
                let recipe = MobileCameraRecipe(filmID: films[0], metering: meter, diffusion: .glimmerglass)
                for (frame, file) in [(small, source), (changed, changedSource), (small, source)] {
                    let live = try await preview.render(frame, angle: 0, mirrored: false, recipe: recipe, longEdge: 640)
                    let developed = try await reference.render(url: file, recipe: MobileCameraLookEngine.intent(recipe), megapixels: 0.01)
                    let expected = try await reference.canvasImage(developed.image)
                    let difference = maxDifference(live.image, expected)
                    maximumReferenceDifference = max(maximumReferenceDifference, difference)
                    try require(difference <= 1, "Stream replacement retained old pixels/meter for \(meter.rawValue): \(difference)")
                }
            }
            checks.append("18 alternating source replacements vs file/develop: all six meters, diffusion, return to original frame")

            // An asymmetric frame catches a row flip and front mirroring while
            // using the same full-frame preparation as production.
            let rotated = try await preview.render(small, angle: 90, mirrored: false,
                recipe: MobileCameraRecipe(filmID: films[0], metering: .custom), longEdge: 640)
            try require(rotated.image.width == 32 && rotated.image.height == 48, "Video preview quarter-turn dimensions")
            let ordinary = try await preview.render(small, angle: 0, mirrored: false,
                recipe: MobileCameraRecipe(filmID: films[0], metering: .custom), longEdge: 640)
            let mirrored = try await preview.render(small, angle: 0, mirrored: true,
                recipe: MobileCameraRecipe(filmID: films[0], metering: .custom), longEdge: 640)
            try require(pixelData(ordinary.image) != pixelData(mirrored.image), "Front mirror was ignored")
            checks.append("actual native video render quarter-turn and front-mirror preparation")

            let brightScene = try makeFrame(width: 640, height: 480, serial: 2, highlight: true)
            for reduced in [false, true] {
                let budget = MobileCameraLookBudget(reducedPower: reduced)
                let offRecipe = MobileCameraRecipe(filmID: films[0], metering: .custom, diffusion: .off)
                let off = try await preview.render(brightScene, angle: 0, mirrored: false, recipe: offRecipe, longEdge: budget.longEdge)
                for family in MobileDiffusionFilter.allCases where family != .off {
                    let recipe = MobileCameraRecipe(filmID: films[0], metering: .custom, diffusion: family)
                    let on = try await preview.render(brightScene, angle: 0, mirrored: false, recipe: recipe, longEdge: budget.longEdge)
                    let difference = maxDifference(off.image, on.image)
                    diffusionDifferences[family.rawValue + (reduced ? "-reduced" : "-normal")] = difference
                    try require(difference > 16, "Native diffusion did not visibly affect preview: \(family.rawValue), reduced=\(reduced)")
                }
            }
            checks.append("all four actual native diffusion families remain active at normal and reduced-power resolutions")

            // Interleaved old/new paths use the same recipe, resolution and
            // warm engine setup. Timings are observations, never a flaky gate.
            let baseline = MobileCameraLookEngine(reusesSession: false)
            let benchmarkRecipe = MobileCameraRecipe(filmID: films[0], metering: .custom, diffusion: .glimmerglass)
            for edge in [640, 480] {
                for iteration in 0..<8 {
                    let arms: [(String, MobileCameraLookEngine)] = iteration.isMultiple(of: 2)
                        ? [("open", baseline), ("stream", preview)] : [("stream", preview), ("open", baseline)]
                    var outputs: [CGImage] = []
                    for (name, renderer) in arms {
                        let start = ProcessInfo.processInfo.systemUptime
                        let result = try await renderer.render(brightScene, angle: 0, mirrored: false,
                                                              recipe: benchmarkRecipe, longEdge: edge)
                        if iteration >= 2 {
                            timings["\(name)-\(edge)", default: []].append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                        }
                        outputs.append(result.image)
                    }
                    try require(maxDifference(outputs[0], outputs[1]) == 0, "Streaming optimization changed pixels at \(edge)px")
                }
            }
            await baseline.close()
            checks.append("interleaved reopened/streaming warm renders at 640/480px retain identical pixels")

            // Hold the metering source fixed while changing display tiers.
            // Include a strong halation stock and changing highlight scenes;
            // compare a fresh session against the streamed session at each tier.
            let detailed = try makeFrame(width: 1280, height: 960, serial: 7, highlight: true)
            let changedDetailed = try makeFrame(width: 1280, height: 960, serial: 8)
            let fresh = MobileCameraLookEngine(reusesSession: false)
            for film in ["kodak_portra_400", "cinestill_800t"] {
                let recipe = MobileCameraRecipe(filmID: film, metering: .center_weighted)
                for source in [detailed, changedDetailed, detailed] {
                    let large = try await preview.render(source, angle: 0, mirrored: false, recipe: recipe, longEdge: 640)
                    let reduced = try await preview.render(source, angle: 0, mirrored: false, recipe: recipe, longEdge: 480)
                    try require(large.image.width == 640 && reduced.image.width == 480, "Native display resolution was reduced unexpectedly")
                    try require(large.exposureEV != nil && large.exposureEV == reduced.exposureEV, "Native exposure changed with display resolution")
                    let independent = try await fresh.render(source, angle: 0, mirrored: false, recipe: recipe, longEdge: 480)
                    try require(maxDifference(reduced.image, independent.image) == 0, "Streamed halation/exposure differs from a fresh session")
                }
            }
            await fresh.close()
            checks.append("640/480 display tiers share unchanged metering on 1280px inputs; Portra/CineStill highlight scenes match fresh-session halation and exposure")

            let unusedMeterControl = MobileCameraLookEngine(forcesUnusedMeter: true)
            let manualRecipe = MobileCameraRecipe(filmID: films[0], metering: .custom)
            for iteration in 0..<8 {
                let arms: [(String, MobileCameraLookEngine)] = iteration.isMultiple(of: 2)
                    ? [("manual-unused-meter-640", unusedMeterControl), ("manual-skip-meter-640", preview)]
                    : [("manual-skip-meter-640", preview), ("manual-unused-meter-640", unusedMeterControl)]
                var results: [MobileCameraLookResult] = []
                for (name, renderer) in arms {
                    let start = ProcessInfo.processInfo.systemUptime
                    let result = try await renderer.render(changedDetailed, angle: 0, mirrored: false, recipe: manualRecipe, longEdge: 640)
                    if iteration >= 2 { timings[name, default: []].append((ProcessInfo.processInfo.systemUptime - start) * 1000) }
                    try require(result.exposureEV == nil, "Auto exposure off applied a meter correction")
                    results.append(result)
                }
                try require(maxDifference(results[0].image, results[1].image) == 0, "Skipping unused metering changed manual-exposure pixels")
            }
            await unusedMeterControl.close()
            checks.append("manual exposure skips unused 1280px meter analysis without changing pixels or applying an exposure correction; interleaved timing control")

            // SDR highlight energy is not a RAW scene estimate. Reproduce the
            // previous +4 EV input reconstruction as a control, with identical
            // film/PSF/meter/output settings; quantify the halo outside the light.
            let restoredHeadroom = MobileCameraLookEngine(headroomForChecks: 4)
            for mode in [MobileMeteringMode.custom, .balanced] {
                let recipe = MobileCameraRecipe(filmID: "cinestill_800t", metering: mode)
                let recorded = try await preview.render(brightScene, angle: 0, mirrored: false, recipe: recipe, longEdge: 640)
                let boosted = try await restoredHeadroom.render(brightScene, angle: 0, mirrored: false, recipe: recipe, longEdge: 640)
                try require(recorded.exposureEV == boosted.exposureEV, "SDR headroom policy changed the actual meter")
                try require(maxDifference(recorded.image, boosted.image) > 16, "CineStill headroom control did not exercise highlight amplification")
                try require(haloRed(recorded.image) < haloRed(boosted.image), "SDR policy did not reduce amplified red halo outside the source")
                let still = try MobileProcessContract.wire(recipe.values.merging(["film_stock": .string("cinestill_800t")]) { _, new in new }, aspect: 4.0 / 3)
                try require(recipe.values["halation_headroom_ev"] == nil && still["halation_headroom_ev"]?.doubleValue == 4,
                            "Video policy leaked into saved camera recipe")
                try require(still["halation_active"]?.boolValue == true && still["halation_amount"]?.doubleValue == 1,
                            "Video fix modified physical halation capability")
            }
            await restoredHeadroom.close()
            checks.append("CineStill SDR input policy reduces reconstructed red halo in manual/balanced modes with identical meter EV, preserving captured recipe and still headroom/halation")

            let defaultsName = "Camera-Look-Preferences-" + UUID().uuidString
            let defaults = UserDefaults(suiteName: defaultsName)!
            defer { defaults.removePersistentDomain(forName: defaultsName) }
            try require(MobileCameraPreviewMode.initial(in: defaults) == .approximate, "Default is not fluent approximate preview")
            defaults.set(false, forKey: "mobile.camera.filmPreview")
            try require(MobileCameraPreviewMode.initial(in: defaults) == .system, "Old disabled preview was lost")
            defaults.set(MobileCameraPreviewMode.native.rawValue, forKey: MobileCameraPreviewMode.key)
            try require(MobileCameraPreviewMode.initial(in: defaults) == .native, "Explicit native preference was lost")
            let migrationName = "Camera-Look-Migration-" + UUID().uuidString
            let migration = UserDefaults(suiteName: migrationName)!
            defer { migration.removePersistentDomain(forName: migrationName) }
            migration.set(MobileCameraPreviewMode.native.rawValue, forKey: MobileCameraPreviewMode.key)
            try require(MobileCameraPreviewMode.initial(in: migration) == .approximate &&
                        migration.string(forKey: MobileCameraPreviewMode.key) == MobileCameraPreviewMode.approximate.rawValue,
                        "Existing experimental native choice did not migrate to accepted approximate default")
            migration.set(MobileCameraPreviewMode.native.rawValue, forKey: MobileCameraPreviewMode.key)
            try require(MobileCameraPreviewMode.initial(in: migration) == .native, "Default migration overwrites later explicit choice")
            migration.removePersistentDomain(forName: migrationName)
            migration.set(MobileCameraPreviewMode.system.rawValue, forKey: MobileCameraPreviewMode.key)
            try require(MobileCameraPreviewMode.initial(in: migration) == .system, "Default migration overrides explicit preview off")
            checks.append("default approximate mode, legacy off migration and explicit native preference use an isolated defaults suite")

            let fast = MobileCameraFastLookEngine()
            for i in 0...128 {
                let coordinate = Float(i) / 128
                let value = MobileCameraLookDomain.value(coordinate)
                try require(abs(MobileCameraLookDomain.coordinate(value) - coordinate) < 0.00001, "Linear HDR shaper does not round-trip")
            }
            let hdr = try makeHDRFrame()
            var maximumApproximateRMSE = 0.0
            for film in films + ["cinestill_800t"] {
                let recipe = MobileCameraRecipe(filmID: film, metering: .custom)
                for fixture in [small, hdr] {
                    let approximate = try await fast.render(fixture, angle: 0, mirrored: false, recipe: recipe, longEdge: 960)
                    let direct = try await fast.directColorReference(fixture, recipe: recipe)
                    let error = colorRMSE(approximate.image, direct)
                    maximumApproximateRMSE = max(maximumApproximateRMSE, error)
                    try require(error < 0.005, "Approximate LUT colour differs from direct pointwise engine: \(film), RMSE=\(error)")
                }
            }
            let hdrRecipe = MobileCameraRecipe(filmID: films[0], metering: .custom)
            let hdrApproximation = try await fast.render(hdr, angle: 0, mirrored: false, recipe: hdrRecipe, longEdge: 960)
            let hdrDirect = try await fast.directColorReference(hdr, recipe: hdrRecipe)
            let hdrClipped = try await fast.directColorReference(hdr, recipe: hdrRecipe, clampAtWhite: true)
            try require(colorRMSE(hdrApproximation.image, hdrDirect) < colorRMSE(hdrClipped, hdrDirect),
                        "HDR table does not improve over clipping exposed light at SDR white")
            checks.append("linear 49-cubed HDR table vs direct native colour samples for four film families, shadow/HDR shaper round-trip and no premature white clipping; max RGB RMSE=\(maximumApproximateRMSE)")

            var changedInput = small
            changedInput.generation = 7
            let processedInput = try await fast.render(changedInput, angle: 0, mirrored: false, recipe: hdrRecipe, longEdge: 960)
            let nativeInput = try await preview.render(changedInput, angle: 0, mirrored: false, recipe: hdrRecipe, longEdge: 640)
            try require(processedInput.sourceGeneration == 7 && nativeInput.sourceGeneration == 7,
                        "Processed preview discarded input generation")
            let oldInput = MobileCameraLookResult(image: processedInput.image, recipe: hdrRecipe, sourceSerial: 999, sourceGeneration: 6)
            try require(!MobileCameraPreviewTransition.canReveal(mode: .approximate, unavailable: false, result: oldInput,
                        recipe: hdrRecipe, frozenGeneration: 6, currentGeneration: 7), "Transition revealed stale input with a newer serial")
            try require(!MobileCameraPreviewTransition.canReveal(mode: .approximate, unavailable: false, result: nil,
                        recipe: hdrRecipe, frozenGeneration: 6, currentGeneration: 7), "Transition revealed unprocessed raw preview")
            try require(MobileCameraPreviewTransition.canReveal(mode: .approximate, unavailable: false, result: processedInput,
                        recipe: hdrRecipe, frozenGeneration: 6, currentGeneration: 7), "Transition cannot reveal processed new camera input")
            try require(!MobileCameraPreviewTransition.canReveal(mode: .native, unavailable: false, result: processedInput,
                        recipe: MobileCameraRecipe(filmID: films[1]), frozenGeneration: 6, currentGeneration: 7), "Transition accepted old recipe")
            try require(MobileCameraPreviewTransition.canReveal(mode: .system, unavailable: false, result: nil,
                        recipe: hdrRecipe, frozenGeneration: 6, currentGeneration: 7), "System preview transition waits for film processing")
            checks.append("lens/portrait transition releases only matching processed new-generation frames; stale, missing and wrong-recipe images cannot reveal raw video")
            // Restore the HDR frame used by the cache ownership comparison.
            _ = try await fast.render(hdr, angle: 0, mirrored: false, recipe: hdrRecipe, longEdge: 960)
            let warmCount = await fast.tableBuildCount
            let warmPixels = pixelData(hdrApproximation.image)
            await fast.close(keepingColorTables: true)
            let resumedFast = try await fast.render(hdr, angle: 0, mirrored: false, recipe: hdrRecipe, longEdge: 960)
            let resumedBuildCount = await fast.tableBuildCount
            try require(resumedBuildCount == warmCount && pixelData(resumedFast.image) == warmPixels,
                        "Returning from capture rebuilt or changed a retained colour table")
            // Cache two films and revisit the first without rebaking, then
            // confirm the third evicts only the least recently used film.
            for film in [films[1], films[0], films[2], films[0]] {
                _ = try await fast.render(small, angle: 0, mirrored: false,
                    recipe: MobileCameraRecipe(filmID: film, metering: .custom), longEdge: 960)
            }
            let afterLRU = await fast.tableBuildCount
            try require(afterLRU == resumedBuildCount + 2, "Colour table cache does not preserve the recently used film")
            checks.append("capture suspension releases engine/work buffers while retaining immutable tables; two-film LRU avoids rebuilds and preserves pixels")

            let fastOff = try await fast.render(brightScene, angle: 0, mirrored: false,
                recipe: MobileCameraRecipe(filmID: films[0], metering: .custom), longEdge: 640)
            let frozenFast = pixelData(fastOff.image)
            for reduced in [false, true] {
                for family in MobileDiffusionFilter.allCases where family != .off {
                    let off = try await fast.render(brightScene, angle: 0, mirrored: false,
                        recipe: MobileCameraRecipe(filmID: films[0], metering: .custom), longEdge: reduced ? 400 : 640)
                    let on = try await fast.render(brightScene, angle: 0, mirrored: false,
                        recipe: MobileCameraRecipe(filmID: films[0], metering: .custom, diffusion: family), longEdge: reduced ? 400 : 640)
                    try require(maxDifference(off.image, on.image) > 16, "Approximate diffusion inactive: \(family)")
                }
            }
            var meterOutputs = Set<Data>()
            for mode in MobileMeteringMode.allCases {
                let output = try await fast.render(small, angle: 0, mirrored: false,
                    recipe: MobileCameraRecipe(filmID: films[0], metering: mode), longEdge: 640)
                meterOutputs.insert(pixelData(output.image))
            }
            try require(meterOutputs.count >= 3, "Approximate metering selections ignored")
            let fastRecipe = MobileCameraRecipe(filmID: films[0], metering: .custom, diffusion: .glimmerglass)
            for i in 0..<10 {
                let start = ProcessInfo.processInfo.systemUptime
                _ = try await fast.render(brightScene, angle: 0, mirrored: false, recipe: fastRecipe, longEdge: 960)
                if i >= 2 { timings["approximate-960", default: []].append((ProcessInfo.processInfo.systemUptime - start) * 1000) }
            }
            for film in films.dropFirst() {
                _ = try await fast.render(small, angle: 90, mirrored: true,
                    recipe: MobileCameraRecipe(filmID: film), longEdge: 960)
            }
            await fast.close()
            try require(pixelData(fastOff.image) == frozenFast, "Approximate freeze changed after renders/shutdown")
            fast.workGate.setActive(false)
            var fastCancelled = false
            do { _ = try await fast.render(small, angle: 0, mirrored: false, recipe: fastRecipe, longEdge: 960) }
            catch is CancellationError { fastCancelled = true }
            try require(fastCancelled, "Inactive approximate preview submitted work")
            checks.append("approximate GPU preview: film families, six meters, four bloom families at both budgets, freeze lifetime, cancellation and warm timings")

            guard let kept, let keptBytes else { throw MobileFailure.message("No retained preview frame") }
            let frozen = kept.snapshot(for: kept.recipe)
            try require(frozen != nil && pixelData(frozen!) == keptBytes, "Shutter snapshot is not the processed frame")
            try require(kept.snapshot(for: MobileCameraRecipe(filmID: films[1])) == nil, "Shutter accepted a stale film recipe")
            await preview.close(); await reference.close()
            try require(pixelData(frozen!) == keptBytes, "Later renders or renderer shutdown mutated the frozen frame")
            checks.append("processed shutter freeze retains identical owned pixels across later renders/shutdown; stale recipes reject")

            preview.workGate.setActive(false)
            var cancelled = false
            do { _ = try await preview.render(small, angle: 0, mirrored: false, recipe: kept.recipe, longEdge: 640) }
            catch is CancellationError { cancelled = true }
            try require(cancelled, "Inactive preview submitted a frame")
            preview.workGate.setActive(true)
            let resumed = try await preview.render(small, angle: 0, mirrored: false, recipe: kept.recipe, longEdge: 640)
            try require(pixelData(resumed.image) == keptBytes, "Preview restart changed the look")
            await preview.close()
            checks.append("inactive cancellation and restart preserve the same native look")
            environment["thermalStateAtEnd"] = ProcessInfo.processInfo.thermalState.rawValue
            try writeReport(report, passed: true, checks: checks, referenceDifference: maximumReferenceDifference,
                            diffusionDifferences: diffusionDifferences, timings: timings, environment: environment, error: nil)
        } catch {
            try? writeReport(report, passed: false, checks: checks, referenceDifference: maximumReferenceDifference,
                             diffusionDifferences: diffusionDifferences, timings: timings, environment: environment, error: error.localizedDescription)
        }
    }
    private static func checkColorSampleContract() throws -> Int {
        guard let device = MTLCreateSystemDefaultDevice(),
              let resources = Bundle.main.url(forResource: "engine", withExtension: nil, subdirectory: StockCatalog.resourceDirectory),
              let engine = spk_engine_create(resources.path, Unmanaged.passUnretained(device as AnyObject).toOpaque()) else {
            throw MobileFailure.message("Cannot create independent colour-sample engine")
        }
        defer { spk_engine_destroy(engine) }
        func require(_ value: Bool, _ message: String) throws { if !value { throw MobileFailure.message(message) } }
        let count = 63
        let palette: [[Float]] = (0..<count).map { i in
            [Float(i * 37 % count) / 62, Float((i * 19 + 3) % count) / 62, Float((i * 11 + 7) % count) / 62]
        }
        let permutation = (0..<count).map { $0 * 17 % count }
        func open(_ order: [Int], width: Int, json: String) throws -> OpaquePointer {
            let samples = order.flatMap { palette[$0] }
            let session = samples.withUnsafeBufferPointer { p -> OpaquePointer? in
                var image = spk_image(data: p.baseAddress, width: UInt32(width), height: UInt32(count / width), channels: 3)
                return spk_open(engine, &image, json, nil)
            }
            guard let session else { throw MobileFailure.message(String(cString: spk_last_error(engine))) }
            return session
        }
        func pixels(_ result: spk_result) -> [[UInt16]] {
            (0..<count).map { i in
                let p = result.rgba16! + (i / Int(result.width) * Int(result.row_stride_px) + i % Int(result.width)) * 4
                return [p[0], p[1], p[2], p[3]]
            }
        }
        func params(_ session: OpaquePointer) throws -> String {
            var reply: UnsafeMutablePointer<CChar>?
            guard spk_get_params(session, &reply) == SPK_OK, let reply else { throw MobileFailure.message("Cannot read sample parameters") }
            defer { spk_string_free(reply) }
            return String(cString: reply)
        }
        var legacyDifference = 0
        for film in ["kodak_portra_400", "ilford_hp5_plus_400", "kodak_ektachrome_100", "cinestill_800t"] {
            var values = try MobileCameraFastLookEngine.colorIntent(filmID: film)
            // The helper must enforce independence even with normal camera
            // metering, spatial filtering and geometry in the source session.
            values["auto_exposure"] = .bool(true)
            values["camera_diffusion_active"] = .bool(true)
            values["geometry_rotation_deg"] = .double(8)
            let json = String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
            let original = try open(Array(0..<count), width: 7, json: json)
            let reordered = try open(permutation, width: 7, json: json)
            let reshaped = try open(Array(0..<count), width: 63, json: json)
            defer { spk_session_release(original); spk_session_release(reordered); spk_session_release(reshaped) }
            var documentBefore = spk_result(), documentAfter = spk_result()
            defer { spk_result_free(&documentBefore); spk_result_free(&documentAfter) }
            func ownedPixels(_ result: spk_result) -> [UInt16] {
                var value: [UInt16] = []
                for y in 0..<Int(result.height) { for x in 0..<Int(result.width) {
                    let p = result.rgba16! + (y * Int(result.row_stride_px) + x) * 4
                    value += [p[0], p[1], p[2], p[3]]
                } }
                return value
            }
            try require(spk_render(original, "full", &documentBefore) == SPK_OK, "Cannot establish cached document negative before colour sampling")
            let documentPixels = ownedPixels(documentBefore)
            let before = try params(original)
            var first = spk_result(), second = spk_result(), third = spk_result()
            defer { spk_result_free(&first); spk_result_free(&second); spk_result_free(&third) }
            try require(spk_render_color_samples(original, &first) == SPK_OK && first.width == 7 && first.height == 9,
                        "Independent sample render failed")
            let kept = pixels(first)
            try require(spk_render_color_samples(reordered, &second) == SPK_OK && spk_render_color_samples(reshaped, &third) == SPK_OK,
                        "Permuted/reshaped sample render failed")
            try require(zip(pixels(second), permutation).allSatisfy { $0.0 == kept[$0.1] }, "Colour samples depend on adjacent colours: \(film)")
            try require(pixels(third) == kept && pixels(first) == kept, "Colour samples depend on chart aspect or retained pixels changed: \(film)")
            try require(try params(original) == before, "Colour sampling mutated saved photo parameters")
            try require(spk_reprint(original, "full", &documentAfter) == SPK_OK && documentAfter.negative_was_cached != 0,
                        "Colour sampling invalidated the document's cached negative")
            try require(ownedPixels(documentAfter) == documentPixels && ownedPixels(documentBefore) == documentPixels,
                        "Colour sampling changed the source/document render or retained texture")
            if film == "kodak_portra_400" {
                // Reproduce the old baker: halation/diffusion off, but normal
                // DIR diffusion and scanner sharpening still mix lattice cells.
                values["auto_exposure"] = .bool(false); values["camera_diffusion_active"] = .bool(false)
                values["geometry_rotation_deg"] = .double(0); values["halation_active"] = .bool(false)
                values["extended_dynamic_range"] = .bool(false)
                values["input_color_space"] = .string("sRGB"); values["input_cctf_decoding"] = .bool(true)
                let legacyJSON = String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
                let a = try open(Array(0..<count), width: 7, json: legacyJSON)
                let b = try open(permutation, width: 7, json: legacyJSON)
                defer { spk_session_release(a); spk_session_release(b) }
                var left = spk_result(), right = spk_result()
                defer { spk_result_free(&left); spk_result_free(&right) }
                try require(spk_render(a, "full", &left) == SPK_OK && spk_render(b, "full", &right) == SPK_OK, "Legacy chart reproduction failed")
                let lp = pixels(left), rp = pixels(right)
                for i in 0..<count { for c in 0..<3 { legacyDifference = max(legacyDifference, abs(Int(rp[i][c]) - Int(lp[permutation[i]][c]))) } }
                try require(legacyDifference > 16, "Legacy spatial-mixing control was not exercised")
            }
        }
        return legacyDifference
    }

    private static func checkReplacementContract() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let resources = Bundle.main.url(forResource: "engine", withExtension: nil, subdirectory: StockCatalog.resourceDirectory),
              let engine = spk_engine_create(resources.path, Unmanaged.passUnretained(device as AnyObject).toOpaque())
        else { throw MobileFailure.message("Cannot create streaming contract engine") }
        defer { spk_engine_destroy(engine) }
        func require(_ value: Bool, _ message: String) throws { if !value { throw MobileFailure.message(message) } }
        let width = 32, height = 24
        let values = (0..<(width * height * 4)).map { Float($0 % 4 == 3 ? 1 : 0.18) }
        let changed = (0..<(width * height * 4)).map { Float($0 % 4 == 3 ? 1 : 0.025 + Double($0 % 29) / 70) }
        guard let buffer = device.makeBuffer(bytes: values, length: values.count * 4, options: .storageModeShared),
              let replacement = device.makeBuffer(bytes: changed, length: changed.count * 4, options: .storageModeShared),
              let reference = device.makeBuffer(bytes: changed, length: changed.count * 4, options: .storageModeShared)
        else { throw MobileFailure.message("Cannot create streaming contract buffers") }
        let json = #"{"input_color_space":"ProPhoto RGB","input_cctf_decoding":false,"grain_active":false,"glare_active":false,"product_defaults":true}"#
        var input = spk_device_image(buffer: Unmanaged.passUnretained(buffer as AnyObject).toOpaque(), width: UInt32(width), height: UInt32(height), channels: 4)
        guard let session = spk_open_device(engine, &input, json, nil) else { throw MobileFailure.message("Cannot open contract frame") }
        defer { spk_session_release(session) }
        func render(_ session: OpaquePointer) throws -> spk_result {
            var out = spk_result()
            guard spk_render(session, "full", &out) == SPK_OK else { throw MobileFailure.message(String(cString: spk_last_error(engine))) }
            return out
        }
        func bytes(_ result: spk_result) -> Data { Data(bytes: result.rgba16!, count: Int(result.row_stride_px * result.height) * 8) }
        var invalid = spk_result()
        try require(spk_render_viewfinder(session, 0, &invalid) == SPK_ERR_INVALID_ARG &&
                    spk_render_viewfinder(session, 1601, &invalid) == SPK_ERR_INVALID_ARG, "Invalid viewfinder size accepted")
        var first = try render(session)
        defer { spk_result_free(&first) }
        let before = bytes(first)
        try require(spk_replace_device_frame(session, nil) == SPK_ERR_INVALID_ARG, "Null replacement accepted")
        input.width += 1
        try require(spk_replace_device_frame(session, &input) == SPK_ERR_INVALID_ARG, "Wrong dimensions accepted")
        input.width -= 1; input.channels = 2
        try require(spk_replace_device_frame(session, &input) == SPK_ERR_INVALID_ARG, "Wrong channels accepted")
        var unchanged = try render(session)
        defer { spk_result_free(&unchanged) }
        try require(bytes(unchanged) == before, "Rejected replacement changed the source")
        input.channels = 4; input.buffer = Unmanaged.passUnretained(replacement as AnyObject).toOpaque()
        try require(spk_replace_device_frame(session, &input) == SPK_OK, "Valid replacement failed")
        memset(replacement.contents(), 0, replacement.length)
        input.buffer = Unmanaged.passUnretained(reference as AnyObject).toOpaque()
        guard let expectedSession = spk_open_device(engine, &input, json, nil) else { throw MobileFailure.message("Cannot open independent stream reference") }
        defer { spk_session_release(expectedSession) }
        var actual = try render(session), expected = try render(expectedSession)
        defer { spk_result_free(&actual); spk_result_free(&expected) }
        try require(bytes(actual) == bytes(expected) && bytes(actual) != before, "Replacement retained borrowed input or stale exposure/source")
        try require(bytes(first) == before, "Source replacement mutated a retained result")
    }

    private static func makeHDRFrame() throws -> MobileCameraLookFrame {
        var buffer: CVPixelBuffer?
        let width = 24, height = 16
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_128RGBAFloat, nil, &buffer) == kCVReturnSuccess,
              let buffer else { throw MobileFailure.message("Cannot make floating HDR fixture") }
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = CVPixelBufferGetBaseAddress(buffer)!
        let levels: [Float] = [0.001, 0.004, 0.02, 0.08, 0.184, 0.5, 1.2, 3.5]
        for y in 0..<height { for x in 0..<width {
            let pixel = (base + y * CVPixelBufferGetBytesPerRow(buffer)).assumingMemoryBound(to: Float.self) + x * 4
            pixel[0] = levels[x % levels.count]
            pixel[1] = levels[(x / levels.count + y) % levels.count]
            pixel[2] = levels[(x + y * 3) % levels.count]
            pixel[3] = 1
        } }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        CVBufferSetAttachment(buffer, kCVImageBufferCGColorSpaceKey, CGColorSpace(name: CGColorSpace.linearSRGB)!, .shouldPropagate)
        return MobileCameraLookFrame(buffer: buffer, rotation: 0, serial: 10)
    }

    private static func colorRMSE(_ a: CGImage, _ b: CGImage) -> Double {
        guard a.width == b.width && a.height == b.height else { return .infinity }
        return pixelData(a).withUnsafeBytes { ap in pixelData(b).withUnsafeBytes { bp in
            let left = ap.bindMemory(to: UInt16.self), right = bp.bindMemory(to: UInt16.self)
            var sum = 0.0
            for y in 0..<a.height { for x in 0..<a.width { for c in 0..<3 {
                let delta = (Double(left[y * a.bytesPerRow / 2 + x * 4 + c]) - Double(right[y * b.bytesPerRow / 2 + x * 4 + c])) / 65535
                sum += delta * delta
            } } }
            return sqrt(sum / Double(a.width * a.height * 3))
        } }
    }

    private static func makeFrame(width: Int, height: Int, serial: UInt64, highlight: Bool = false) throws -> MobileCameraLookFrame {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess,
              let buffer else { throw MobileFailure.message("Cannot allocate synthetic video frame") }
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height { for x in 0..<width {
            let pixel = base + y * stride + x * 4
            if highlight {
                let bright = abs(x - width / 2) < width / 24 && abs(y - height / 2) < height / 16
                pixel[0] = bright ? 255 : 18; pixel[1] = bright ? 255 : 24; pixel[2] = bright ? 255 : 32
            } else {
                pixel[0] = UInt8(12 + (x * 181 / width + y * 19 / height) % 230)
                pixel[1] = UInt8(10 + y * 220 / height)
                pixel[2] = UInt8(8 + x * 236 / width)
            }
            pixel[3] = 255
        } }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        CVBufferSetAttachment(buffer, kCVImageBufferCGColorSpaceKey, CGColorSpace(name: CGColorSpace.sRGB)!, .shouldPropagate)
        return MobileCameraLookFrame(buffer: buffer, rotation: 0, serial: serial)
    }
    private static func writeFrame(_ frame: MobileCameraLookFrame, to url: URL) throws {
        let buffer = frame.buffer
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer), stride = CVPixelBufferGetBytesPerRow(buffer)
        let bytes = Data(bytes: CVPixelBufferGetBaseAddress(buffer)!, count: stride * height)
        guard let provider = CGDataProvider(data: bytes as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: stride, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .relativeColorimetric),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil)
        else { throw MobileFailure.message("Cannot create reference video fixture") }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 1] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw MobileFailure.message("Cannot finish reference fixture") }
    }
    private static func haloRed(_ image: CGImage) -> Double {
        let data = pixelData(image)
        return data.withUnsafeBytes { bytes in
            let pixels = bytes.bindMemory(to: UInt16.self)
            var red = 0.0
            let cx = image.width / 2, cy = image.height / 2
            for y in max(0, cy - image.height / 5)..<min(image.height, cy + image.height / 5) {
                for x in max(0, cx - image.width / 5)..<min(image.width, cx + image.width / 5) {
                    if abs(x - cx) <= image.width / 20 && abs(y - cy) <= image.height / 12 { continue }
                    red += Double(pixels[y * image.bytesPerRow / 2 + x * 4])
                }
            }
            return red
        }
    }
    private static func pixelData(_ image: CGImage) -> Data { image.dataProvider!.data! as Data }
    private static func maxDifference(_ a: CGImage, _ b: CGImage) -> Int {
        guard a.width == b.width, a.height == b.height else { return Int.max }
        let left = pixelData(a), right = pixelData(b)
        guard left.count == right.count else { return Int.max }
        return left.withUnsafeBytes { ap in right.withUnsafeBytes { bp in
            zip(ap.bindMemory(to: UInt16.self), bp.bindMemory(to: UInt16.self))
                .map { abs(Int($0) - Int($1)) }.max() ?? 0
        } }
    }
    private static func writeReport(_ url: URL, passed: Bool, checks: [String], referenceDifference: Int,
                                    diffusionDifferences: [String: Int], timings: [String: [Double]], environment: [String: Any], error: String?) throws {
        var object: [String: Any] = ["passed": passed, "checks": checks,
            "maxVideoVsFileDifference16Bit": referenceDifference, "interleavedWarmRenderMilliseconds": timings, "environment": environment, "nativeDiffusionDifferences16Bit": diffusionDifferences,
            "scope": "synthetic native video/file colour, metering, diffusion and processed-freeze checks; no real camera, RAW equivalence, frame-rate or thermal acceptance"]
        if let error { object["error"] = error }
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted]).write(to: url, options: .atomic)
    }
}
#endif
