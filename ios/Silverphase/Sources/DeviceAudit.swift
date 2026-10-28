#if DEBUG
import Foundation
import CryptoKit
import UIKit
import Darwin
import Metal
import ImageIO

@MainActor enum MobileDeviceAudit {
    private static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return status == KERN_SUCCESS ? info.phys_footprint : 0
    }
    static func samples(_ image: CGImage) -> [Double] {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return [] }
        var values: [Double] = []
        for y in 0..<24 { for x in 0..<16 {
            let sx = min(image.width - 1, (2 * x + 1) * image.width / 32)
            let sy = min(image.height - 1, (2 * y + 1) * image.height / 48)
            let p = bytes + sy * image.bytesPerRow + sx * 8
            for c in 0..<3 { values.append(Double(UInt16(p[c * 2]) | UInt16(p[c * 2 + 1]) << 8) / 65535) }
        } }
        return values
    }
    static func run(document appDocument: MobileDocument? = nil) async {
        UIApplication.shared.isIdleTimerDisabled = true // only in explicit diagnostics; normal relaunch restores automatic locking
        let args = ProcessInfo.processInfo.arguments
        let color = args.contains("--audit-color")
        if args.contains("--audit-overscan") {
            let trace = URL.documentsDirectory.appendingPathComponent("device-overscan-stages.log")
            try? FileManager.default.removeItem(at: trace)
            setenv("SPEKTRAFILM_MEMORY_TRACE", trace.path, 1)
        }
        if args.contains("--clear-device-audit") {
            let manager = FileManager.default
            let generated: Set<String> = ["DeviceAuditInput.ARW", "Synthetic.tif", "raw-import-regression.jpeg", "device-overscan-stages.log",
                "smoke-report.json", "raw-import-report.json", "editor-layout-audit.json", "large-jpeg-phases.json",
                "last-export.json", "native-stage-controls.json", "process-bar-layout.json"]
            for file in (try? manager.contentsOfDirectory(at: .documentsDirectory, includingPropertiesForKeys: nil)) ?? [] {
                if generated.contains(file.lastPathComponent) || (file.lastPathComponent.hasPrefix("device-") && file.pathExtension == "json") {
                    try? manager.removeItem(at: file)
                }
            }
            for file in (try? manager.contentsOfDirectory(at: .temporaryDirectory, includingPropertiesForKeys: nil)) ?? [] {
                if ["Export-", "DocumentSmoke-", "RAW-Regression-", "Interruption-Audit-"].contains(where: { file.lastPathComponent.hasPrefix($0) }) {
                    try? manager.removeItem(at: file)
                }
            }
            // Optional exact legacy artifact name, supplied only after listing
            // and identifying it. Never delete images by UUID/glob alone.
            if let argument = args.first(where: { $0.hasPrefix("--clear-legacy-temp=") }) {
                let name = String(argument.dropFirst(20))
                if !name.isEmpty, name != ".", name != "..", URL(fileURLWithPath: name).lastPathComponent == name {
                    try? manager.removeItem(at: URL.temporaryDirectory.appendingPathComponent(name))
                }
            }
            try? manager.removeItem(at: URL.applicationSupportDirectory.appendingPathComponent("Silverphase-Diagnostics"))
            UIApplication.shared.isIdleTimerDisabled = false
            return
        }
        let mp = args.first { $0.hasPrefix("--audit-mp=") }.flatMap { Double($0.dropFirst(11)) } ?? 2
        let source = URL.documentsDirectory.appendingPathComponent("DeviceAuditInput.ARW")
        let report = URL.documentsDirectory.appendingPathComponent(args.contains("--audit-overscan") ? "device-overscan.json" : args.contains("--audit-preview-races") ? "device-preview-races.json" : args.contains("--audit-live-preview") ? "device-live-preview.json" : color ? "device-color-audit.json" : (args.contains("--audit-pool-parity") ? "device-pool-parity.json" : args.contains("--audit-large-jpeg") ? "device-large-jpeg-\(Int(mp)).json" : args.contains("--audit-export-interruption") ? (args.contains("--audit-full") ? "device-full-workflow.json" : "device-export-interruption.json") : args.contains("--audit-jpeg") ? "device-jpeg-audit.json" : args.contains("--audit-export") ? "device-export-\(Int(mp)).json" : "device-performance-\(Int(mp)).json"))
        var record: [String: Any] = ["passed": false, "megapixels": mp, "thermalStart": ProcessInfo.processInfo.thermalState.rawValue,
                                     "lowPower": ProcessInfo.processInfo.isLowPowerModeEnabled, "physicalMemory": ProcessInfo.processInfo.physicalMemory,
                                     "availableStart": os_proc_available_memory(), "footprintStart": footprint()]
        func write() { if let data = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: report, options: .atomic) } }
        write()
        var auditPeak = footprint()
        let auditMonitor = Task { @MainActor in
            var ticks = 0
            while !Task.isCancelled {
                auditPeak = max(auditPeak, footprint())
                ticks += 1
                if args.contains("--audit-overscan"), ticks % 8 == 0 { record["observedPeakFootprint"] = auditPeak; write() }
                do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
            }
        }
        defer { auditMonitor.cancel() }
        do {
            guard FileManager.default.fileExists(atPath: source.path) else { throw MobileFailure.message("缺少临时审计输入") }
            if color {
                let probe = MobileEngine()
                record["inputSamples"] = try await probe.auditInput(source)
                await probe.close()
                var outputs: [String: Any] = [:]
                for legacy in [false, true] {
                    let engine = MobileEngine()
                    var recipe: [String: WireValue] = ["grain_active": .bool(false), "glare_active": .bool(false)]
                    if legacy { recipe.merge(["print_stock": .string("kodak_portra_endura"), "extended_dynamic_range": .bool(false), "film_format_mm": .double(35)]) { _, new in new } }
                    let result = try await engine.render(url: source, recipe: recipe, megapixels: 2)
                    let params = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result.resolved))
                    outputs[legacy ? "legacy" : "aligned"] = ["width": result.image.width, "height": result.image.height,
                                                               "samples": samples(result.image), "params": params]
                    await engine.close()
                }
                record["outputs"] = outputs
            } else if args.contains("--audit-overscan") {
                record["megapixels"] = MobileImageMetadata.read(source).megapixels
                record["phase"] = "import"; write()
                let document = appDocument ?? MobileDocument()
                await document.importFiles([source]).value
                for _ in 0..<400 { if !document.busy { break }; try await Task.sleep(for: .milliseconds(50)) }
                document.finishDevelopment()
                record["phase"] = "overscan-preview"; write()
                document.setValues(["overscan_active": .bool(true), "overscan_format": .string("135"), "overscan_mode": .string("strip")])
                for _ in 0..<400 { if !document.busy { break }; try await Task.sleep(for: .milliseconds(50)) }
                guard document.error == nil, document.image != nil else { throw MobileFailure.message(document.error ?? "片边预览未完成") }
                document.zoomToNative()
                record["phase"] = "native-detail"; write()
                for _ in 0..<1200 { if !document.busy && !document.detailBusy && document.detailTile?.nativeSize != nil { break }; try await Task.sleep(for: .milliseconds(50)) }
                guard let native = document.detailTile?.nativeSize else { throw MobileFailure.message("片边原始细节失败：" + document.previewStatus) }
                record["nativeDetail"] = ["width": native.width, "height": native.height, "viewport": document.viewportAudit(), "cache": await document.detailAudit()]; write()
                let recipe = document.current?.recipe ?? [:]
                document.setActive(false)
                await document.waitForPreviewCleanup()
                let exporter = MobileEngine()
                var options = MobileExportRecipe(); options.sizeMode = "original"; options.format = .jpeg; options.quality = 0.8
                record["phase"] = "jpeg-export"; write()
                let files = try await exporter.exportFiles(url: source, recipe: recipe, geometry: MobileGeometry(), options: options, stem: "Overscan-Audit")
                defer { try? FileManager.default.removeItem(at: files[0].deletingLastPathComponent()) }
                guard let jpeg = CGImageSourceCreateWithURL(files[0] as CFURL, nil), let decoded = CGImageSourceCreateImageAtIndex(jpeg, 0, nil),
                      decoded.width == Int(native.width), decoded.height == Int(native.height) else { throw MobileFailure.message("片边完整JPG未保留原始画布尺寸") }
                record["jpeg"] = ["width": decoded.width, "height": decoded.height, "bytes": (try Data(contentsOf: files[0])).count]
                await exporter.close()
            } else if args.contains("--audit-preview-races") {
                let folder = URL.temporaryDirectory.appendingPathComponent("DocumentSmoke-Races-" + UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: folder) }
                let visible = args.contains("--audit-visible")
                let document = visible ? appDocument ?? MobileDocument(directory: folder) : MobileDocument(directory: folder)
                defer { document.setActive(false) }
                await document.importFiles([source]).value
                for _ in 0..<400 { if !document.busy { break }; try await Task.sleep(for: .milliseconds(50)) }
                guard document.image != nil, !document.busy else { throw MobileFailure.message("混合预览测试输入未完成") }
                if visible, !UIAccessibility.isReduceMotionEnabled {
                    guard let assets = document.development, !document.developmentRunning else { throw MobileFailure.message("首次画面没有等待胶片印相") }
                    document.printNegative()
                    for _ in 0..<160 { if document.development == nil { break }; try await Task.sleep(for: .milliseconds(50)) }
                    let animation = assets.presentationAudit()
                    record["developmentPresentation"] = animation; write()
                    guard document.development == nil, (animation["submittedFrames"] as? Int ?? 0) > 15,
                          animation["lastProgress"] as? Float == 1, animation["error"] as? String == "" else { throw MobileFailure.message("可见画布显影动画没有完成") }
                } else { document.finishDevelopment() }
                let fit = MobileViewport(rect: CGRect(x: 0, y: 0, width: 1, height: 1), zoom: 1, pixelLongEdge: 1600, previewLongEdge: 1600)
                let native = MobileViewport(rect: CGRect(x: 0.35, y: 0.35, width: 0.1, height: 0.1), zoom: 8, pixelLongEdge: 12000, previewLongEdge: 1600)
                if visible {
                    for _ in 0..<200 { if document.requestedViewportAudit() != nil { break }; try await Task.sleep(for: .milliseconds(20)) }
                }
                @MainActor func showFit() async throws {
                    if visible { document.zoomToFit() } else { document.requestDetail(fit) }
                    try await Task.sleep(for: .milliseconds(70))
                }
                @MainActor func showNative() async throws {
                    if visible { document.zoomToNative() } else { document.requestDetail(native) }
                    try await Task.sleep(for: .milliseconds(70))
                }
                document.requestDetail(native)
                record["intent"] = document.viewportAudit(); write()
                guard document.viewportAudit()["requestedEdge"] == native.pixelLongEdge else { throw MobileFailure.message("缩放意图被临时分辨率覆盖") }
                // A viewport arriving while another preview owns the worker
                // must resume without a second viewport/drag notification.
                try await showFit()
                for _ in 0..<400 { if !document.busy && !document.detailBusy { break }; try await Task.sleep(for: .milliseconds(50)) }
                document.busy = true
                try await showNative()
                try await Task.sleep(for: .milliseconds(200))
                document.busy = false
                try await Task.sleep(for: .milliseconds(350))
                guard document.detailBusy || document.detailTile?.nativeSize != nil else { throw MobileFailure.message("预览解除占用后未自动唤醒细节，仍依赖下一次画布拖动") }
                record["idleTransitionWakesDetailWithoutViewportChange"] = true; write()
                try await showNative()
                record["visibleCanvasDriven"] = visible
                var checkpoints: [[String: Any]] = []
                for (index, delay) in [350, 750, 1100].enumerated() {
                    let key = ["_printBrightnessStops", "exposure_compensation_ev", "_temperature"][index]
                    let finalValue = index == 2 ? 6300.0 : Double(index * 16 + 15) / 100
                    for _ in 0..<200 { if (await document.detailAudit())["inFlight"] ?? 0 > 0 { break }; try await Task.sleep(for: .milliseconds(20)) }
                    try await Task.sleep(for: .milliseconds(delay))
                    try await showFit()
                    try await showNative()
                    document.beginParameterInteraction()
                    for value in 0..<16 {
                        document.set(key, .double(index == 2 ? 6000 + Double(value) * 20 : Double(index * 16 + value) / 100))
                        if value % 3 == 0 { try await showFit() } else { try await showNative() }
                        try await Task.sleep(for: .milliseconds(15))
                    }
                    try await showNative()
                    document.endParameterInteraction()
                    for _ in 0..<800 { if !document.busy && !document.detailBusy && document.detailTile?.nativeSize != nil { break }; try await Task.sleep(for: .milliseconds(50)) }
                    guard !document.busy, !document.detailBusy, let tile = document.detailTile, let size = tile.nativeSize,
                          document.current?.recipe[key]?.doubleValue == finalValue,
                          document.image.map({ max($0.width, $0.height) >= 3800 }) == true,
                          (!visible || abs((document.viewportAudit()["requestedEdge"] ?? 0) - max(size.width, size.height)) < 1),
                          (!visible || (abs((document.viewportAudit()["canvasWidthPixels"] ?? 0) - size.width) < 1 && abs((document.viewportAudit()["canvasHeightPixels"] ?? 0) - size.height) < 1)),
                          tile.rect.contains(document.requestedViewportAudit()?.rect ?? native.rect),
                          (await document.detailRecipeAudit())[key] == document.current?.recipe[key] else { throw MobileFailure.message("连续调参/缩放后没有恢复最新原始精度：" + document.previewStatus) }
                    checkpoints.append(["round": index + 1, "parameter": key, "finalValue": finalValue, "baseEdge": document.image.map { max($0.width, $0.height) } ?? 0,
                                        "nativeWidth": size.width, "nativeHeight": size.height, "cache": await document.detailAudit(), "intent": document.viewportAudit()])
                    record["checkpoints"] = checkpoints; write()
                    try await showFit()
                    try await showNative()
                }
                for _ in 0..<800 { if !document.busy && !document.detailBusy && document.detailTile?.nativeSize != nil { break }; try await Task.sleep(for: .milliseconds(50)) }
                guard let beforeComparison = document.detailTile else { throw MobileFailure.message("原图对比测试没有原始细节") }
                let comparisonCache = await document.detailAudit()
                for _ in 0..<3 {
                    document.compareCanvas(true)
                    document.requestDetail(fit) // original-image layout must not replace the processed viewport
                    if !visible { document.requestOriginalDetail(native) }
                    for _ in 0..<400 { if !document.originalDetailBusy && document.originalDetailTile?.nativeSize != nil { break }; try await Task.sleep(for: .milliseconds(50)) }
                    guard let originalTile = document.originalDetailTile, let originalSize = originalTile.nativeSize,
                          abs(Double(originalTile.image.width) / originalTile.rect.width - originalSize.width) < 1,
                          abs(Double(originalTile.image.height) / originalTile.rect.height - originalSize.height) < 1,
                          !visible || (abs((document.originalViewportAudit()["widthPixels"] ?? 0) - originalSize.width) < 1 && abs((document.originalViewportAudit()["heightPixels"] ?? 0) - originalSize.height) < 1) else {
                        throw MobileFailure.message("原图对比仍使用低分辨率插值")
                    }
                    record["originalNativeSize"] = [originalSize.width, originalSize.height]
                    document.compareCanvas(false)
                    try await Task.sleep(for: .milliseconds(350))
                }
                let afterComparison = await document.detailAudit()
                record["comparisonCache"] = afterComparison; write()
                guard document.detailTile?.image === beforeComparison.image,
                      afterComparison["renders"] == comparisonCache["renders"], afterComparison["residentPixels"] == comparisonCache["residentPixels"] else {
                    throw MobileFailure.message("原图对比清除了原始细节缓存")
                }
                record["comparisonPreservesNativeCache"] = true
                record["comparisonShowsNativeOriginalPixels"] = true
                let middle = MobileViewport(rect: CGRect(x: 0.2, y: 0.25, width: 0.2, height: 0.2), zoom: 4, pixelLongEdge: 5120, previewLongEdge: 1600)
                try await showFit(); document.requestDetail(middle)
                for _ in 0..<200 { if (await document.detailAudit())["inFlight"] ?? 0 > 0 { break }; try await Task.sleep(for: .milliseconds(20)) }
                try await showNative()
                for _ in 0..<800 { if !document.busy && !document.detailBusy && document.detailTile?.nativeSize != nil { break }; try await Task.sleep(for: .milliseconds(50)) }
                guard document.detailTile?.nativeSize != nil, document.detailTile?.rect.contains(document.requestedViewportAudit()?.rect ?? native.rect) == true else { throw MobileFailure.message("低级预览覆盖了后来的原始精度请求") }
                record["nativeSupersedesInFlightMiddleTier"] = true; write()
                let stableBase = document.image
                for _ in 0..<3 { document.releaseMemory(); try await Task.sleep(for: .milliseconds(100)) }
                for _ in 0..<800 { if !document.busy && !document.detailBusy && document.detailTile?.nativeSize != nil { break }; try await Task.sleep(for: .milliseconds(50)) }
                guard document.detailTile?.nativeSize != nil else { throw MobileFailure.message("释放缓存后没有自动恢复当前缩放精度") }
                guard document.image === stableBase else { throw MobileFailure.message("内存回收反复重做已经完成的普通预览") }
                record["memoryRecoveryPreservesCurrentBase"] = true
                record["memoryReleaseRestoresCurrentDemand"] = true
                try await showFit()
                for _ in 0..<100 { if (await document.detailAudit())["residentPixels"] == 0 { break }; try await Task.sleep(for: .milliseconds(20)) }
                guard (await document.detailAudit())["residentPixels"] == 0 else { throw MobileFailure.message("缩回后遗留原始大图缓存") }
                record["requestedIntentSurvivesLOD"] = true
            } else if args.contains("--audit-live-preview") {
                let defaults = UserDefaults.standard
                let saved = defaults.data(forKey: "mobile.preferences.v1")
                defer { if let saved { defaults.set(saved, forKey: "mobile.preferences.v1") } else { defaults.removeObject(forKey: "mobile.preferences.v1") } }
                let folder = URL.temporaryDirectory.appendingPathComponent("DocumentSmoke-Live-" + UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: folder) }
                let visible = args.contains("--audit-visible")
                let document = visible ? appDocument ?? MobileDocument(directory: folder) : MobileDocument(directory: folder)
                let originalPreferences = document.preferences.values
                defer { document.preferences.values = originalPreferences }
                record["visibleEditor"] = visible
                document.preferences.values.previewEdge = 3840
                document.previewEdgeOverride = 3840
                document.preferences.values.lowerPreviewInLowPower = false
                await document.importFiles([source]).value
                for _ in 0..<400 { if !document.busy { break }; try await Task.sleep(for: .milliseconds(50)) }
                guard !document.busy, document.image != nil else { throw MobileFailure.message("实时预览测试输入未完成") }
                var cases: [[String: Any]] = []
                for key in ["_printBrightnessStops", "exposure_compensation_ev", "_temperature"] {
                    let before = document.current?.recipe[key]
                    document.beginParameterInteraction()
                    let started = ContinuousClock.now
                    for index in 0..<50 {
                        document.set(key, .double(key == "_temperature" ? 6000 + Double(index) * 20 : Double(index) / 100))
                        try await Task.sleep(for: .milliseconds(40))
                    }
                    let frames = document.interactionFrames
                    let times = document.interactionSeconds
                    let cached = document.interactionCachedFrames
                    let inputDuration = started.duration(to: .now)
                    let inputSeconds = Double(inputDuration.components.seconds) + Double(inputDuration.components.attoseconds) / 1e18
                    document.endParameterInteraction()
                    for _ in 0..<400 { if !document.busy { break }; try await Task.sleep(for: .milliseconds(50)) }
                    record["interactionProgress"] = ["key": key, "frames": frames, "busy": document.busy,
                        "value": document.current?.recipe[key]?.doubleValue ?? -999,
                        "width": document.image?.width ?? 0, "height": document.image?.height ?? 0,
                        "error": document.error ?? "", "status": document.previewStatus]
                    write()
                    guard frames > 1, !document.busy, document.current?.recipe[key]?.doubleValue == (key == "_temperature" ? 6980 : 0.49),
                          document.resolved["_draft"]?.boolValue != true,
                          let image = document.image, max(image.width, image.height) >= 3800 else { throw MobileFailure.message("实时/最终预览没有正确更新") }
                    let elapsed = started.duration(to: .now)
                    cases.append(["key": key, "framesDuringInput": frames, "inputSeconds": inputSeconds, "updatesPerSecond": Double(frames) / inputSeconds, "frameSeconds": times, "cachedNegativeFrames": cached,
                                  "finalLongEdge": max(image.width, image.height), "totalSeconds": Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18])
                    record["interaction"] = cases; write()
                    document.undo()
                    guard document.current?.recipe[key] == before else { throw MobileFailure.message("连续拖动未合并为一次撤销") }
                    for _ in 0..<400 { if !document.busy { break }; try await Task.sleep(for: .milliseconds(50)) }
                }
                record["interaction"] = cases
                let reused = MobileEngine()
                for temperature in [6500.0, 6900] {
                    let settings: [String: WireValue] = ["_temperature": .double(temperature), "_interactivePreview": .bool(true), "_interactiveEdge": .double(1600), "grain_active": .bool(false), "glare_active": .bool(false)]
                    let a = try await reused.render(url: source, recipe: settings, megapixels: 2)
                    let fresh = MobileEngine()
                    let b = try await fresh.render(url: source, recipe: settings, megapixels: 2)
                    guard a.image.dataProvider!.data! as Data == b.image.dataProvider!.data! as Data else { throw MobileFailure.message("交互白平衡缓存改变了真实像素") }
                    await fresh.close()
                }
                await reused.close()
                record["interactiveWBReopenPixelParity"] = true
                let tiers = MobileEngine()
                for (key, value) in [("_printBrightnessStops", 0.49), ("exposure_compensation_ev", 0.49), ("_temperature", 6980.0)] {
                    var baseline: [String: WireValue] = ["grain_active": .bool(false), "glare_active": .bool(false)]
                    _ = try await tiers.render(url: source, recipe: baseline, megapixels: 2)
                    baseline[key] = .double(value)
                    var live = baseline; live["_interactivePreview"] = .bool(true); live["_interactiveEdge"] = .double(1600)
                    _ = try await tiers.render(url: source, recipe: live, megapixels: 2)
                    let final = try await tiers.render(url: source, recipe: baseline, megapixels: 2)
                    let fresh = MobileEngine()
                    let reference = try await fresh.render(url: source, recipe: baseline, megapixels: 2)
                    guard final.resolved["_draft"]?.boolValue != true, final.image.dataProvider!.data! as Data == reference.image.dataProvider!.data! as Data else { throw MobileFailure.message("松手后的最终质量与独立渲染不一致：" + key) }
                    await fresh.close()
                }
                await tiers.close()
                record["liveToFullPixelParity"] = true
                var details: [[String: Any]] = []
                for request in [MobileViewport(rect: CGRect(x: 0.25, y: 0.25, width: 0.2, height: 0.2), zoom: 4, pixelLongEdge: 5120, previewLongEdge: 3840),
                                MobileViewport(rect: CGRect(x: 0.55, y: 0.3, width: 0.2, height: 0.2), zoom: 4, pixelLongEdge: 5120, previewLongEdge: 3840),
                                MobileViewport(rect: CGRect(x: 0.35, y: 0.4, width: 0.1, height: 0.1), zoom: 8, pixelLongEdge: 12000, previewLongEdge: 3840)] {
                    let started = ContinuousClock.now
                    document.requestDetail(request)
                    guard !document.isInteractionLocked else { throw MobileFailure.message("载入细节错误锁定了编辑器") }
                    for _ in 0..<600 { if !document.detailBusy { break }; try await Task.sleep(for: .milliseconds(50)) }
                    guard !document.detailBusy, let tile = document.detailTile, tile.rect.contains(request.rect) else { throw MobileFailure.message("可见区域细节未完成：" + document.previewStatus) }
                    let elapsed = started.duration(to: .now)
                    details.append(["pixelLongEdge": request.pixelLongEdge, "width": tile.image.width, "height": tile.image.height,
                                    "seconds": Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18, "cache": await document.detailAudit()])
                }
                record["detail"] = details
                document.requestDetail(MobileViewport(rect: CGRect(x: 0, y: 0, width: 1, height: 1), zoom: 1, pixelLongEdge: 1800, previewLongEdge: 3840))
                try await Task.sleep(for: .milliseconds(100))
                guard document.detailTile == nil, (await document.detailAudit())["residentPixels"] == 0 else { throw MobileFailure.message("缩回后未释放细节缓存") }
                record["detailReleasedOnZoomOut"] = true
                document.setActive(false)
            } else if args.contains("--audit-pool-parity") {
                var cases: [[String: Any]] = []
                for grain in [false, true] {
                    let plain = MobileEngine(), striped = MobileEngine()
                    let recipe: [String: WireValue] = ["grain_active": .bool(grain), "glare_active": .bool(false)]
                    let a = try await plain.render(url: source, recipe: recipe, megapixels: 8)
                    await plain.close()
                    var bands = recipe; bands["striped"] = .bool(true); bands["strip_rows"] = .double(256)
                    let b = try await striped.render(url: source, recipe: bands, megapixels: 8)
                    guard a.image.dataProvider!.data! as Data == b.image.dataProvider!.data! as Data else { throw MobileFailure.message("内存复用修复改变了实际RAW像素") }
                    let memory = await striped.auditMemory()
                    let object = try JSONSerialization.jsonObject(with: Data(memory.utf8)) as? [String: Any] ?? [:]
                    let pool = object["pool"] as? [String: Any] ?? [:]
                    let audit = pool["audit"] as? [String: Any] ?? [:]
                    for key in ["live_underflows", "over_releases", "reclaim_while_encoding"] {
                        guard (audit[key] as? NSNumber)?.intValue == 0 else { throw MobileFailure.message("缓冲所有权检查失败：" + key) }
                    }
                    let taken = (audit["reuse_max_taken"] as? NSNumber)?.doubleValue ?? 0
                    let requested = (audit["reuse_max_taken_for_request"] as? NSNumber)?.doubleValue ?? 0
                    guard taken < 64 * 1024 * 1024 || taken < requested * 4 else { throw MobileFailure.message("大缓冲仍被用于小条带") }
                    cases.append(["grain": grain, "identicalPixels": true, "width": a.image.width, "height": a.image.height, "memory": object])
                    await striped.close()
                }
                record["cases"] = cases
            } else if args.contains("--audit-large-jpeg") {
                try? FileManager.default.removeItem(at: URL.documentsDirectory.appendingPathComponent("large-jpeg-phases.json"))
                let engine = MobileEngine()
                var options = MobileExportRecipe()
                options.maximumMegapixels = mp
                let repeatable = args.contains("--audit-repeatable")
                if repeatable { options.metadata = false }
                var geometry = MobileGeometry()
                if args.contains("--audit-crop") {
                    var g = Geometry(); g.crop = CropRect(x: 0.12, y: 0.15, width: 0.72, height: 0.64)
                    let metadata = MobileImageMetadata.read(source)
                    let size = CGSize(width: sqrt(metadata.megapixels * 1e6 * metadata.aspect), height: sqrt(metadata.megapixels * 1e6 / metadata.aspect))
                    g = g.straightened(to: 8.3, in: size).turned(by: 1); g.flipH = true
                    geometry = MobileGeometry(value: g)
                    let expected = g.outputSize(for: size)
                    record["expectedCropSize"] = [Int(expected.width), Int(expected.height)]
                }
                if args.contains("--audit-full") { options.sizeMode = "original" }
                record["sourceMegapixels"] = MobileImageMetadata.read(source).megapixels
                var peak = footprint()
                let sampler = Task { @MainActor in while !Task.isCancelled { peak = max(peak, footprint()); try? await Task.sleep(for: .milliseconds(25)) } }
                defer { sampler.cancel() }
                let started = ContinuousClock.now
                let files = try await engine.exportFiles(url: source, recipe: repeatable ? ["glare_active": .bool(false)] : [:], geometry: geometry, options: options, stem: "Large-JPG-Audit")
                defer { try? FileManager.default.removeItem(at: files[0].deletingLastPathComponent()) }
                sampler.cancel(); peak = max(peak, footprint())
                let elapsed = started.duration(to: .now)
                guard let input = CGImageSourceCreateWithURL(files[0] as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(input, 0, nil) else { throw MobileFailure.message("高像素JPG无法读回") }
                let sourceMP = args.contains("--audit-full") ? MobileImageMetadata.read(source).megapixels : mp
                let expected = sourceMP * geometry.value.crop.width * geometry.value.crop.height
                guard Double(image.width * image.height) >= expected * 1e6 * 0.99 else { throw MobileFailure.message("高像素JPG未达到请求像素") }
                if let size = record["expectedCropSize"] as? [Int] {
                    guard image.width == size[0], image.height == size[1] else { throw MobileFailure.message("完整RAW的裁切导出尺寸与桌面模型不一致") }
                }
                record["width"] = image.width; record["height"] = image.height
                record["peakFootprint"] = peak
                record["seconds"] = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                record["bytes"] = try FileManager.default.attributesOfItem(atPath: files[0].path)[.size]
                if repeatable {
                    let bytes = try Data(contentsOf: files[0], options: .mappedIfSafe)
                    record["sha256"] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                }
            } else if args.contains("--audit-export-interruption") {
                let defaults = UserDefaults.standard
                let saved = defaults.data(forKey: "mobile.export.current")
                defer { if let saved { defaults.set(saved, forKey: "mobile.export.current") } else { defaults.removeObject(forKey: "mobile.export.current") } }
                let folder = URL.temporaryDirectory.appendingPathComponent("Interruption-Audit-" + UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: folder) }
                let visible = args.contains("--audit-visible")
                let document = visible ? appDocument ?? MobileDocument(directory: folder) : MobileDocument(directory: folder)
                let batchCount = args.first { $0.hasPrefix("--audit-batch=") }.flatMap { Int($0.dropFirst(14)) } ?? 1
                await document.importFiles(Array(repeating: source, count: min(3, max(1, batchCount)))).value
                for _ in 0..<300 {
                    if !document.busy && !document.resolved.isEmpty { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard !document.busy && !document.resolved.isEmpty else { throw MobileFailure.message("复现输入未加载完成") }
                // Preserve the user's actual output space/quality/preferences.
                if args.contains("--audit-full") { document.exportRecipe.sizeMode = "original" }
                let expectedMP = args.contains("--audit-full") ? MobileImageMetadata.read(source).megapixels : 24
                let started = ContinuousClock.now
                document.export(.jpeg, ids: document.photos.map(\.id))
                document.releaseMemory(); document.schedule()
                document.setActive(false, background: false)
                try await Task.sleep(for: .milliseconds(100))
                document.setActive(true, background: false)
                for _ in 0..<300 {
                    if !document.delivering { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard !document.delivering, document.error == nil, document.exportedFiles.count == batchCount, let file = document.exportedFiles.first,
                      let input = CGImageSourceCreateWithURL(file as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(input, 0, nil), Double(image.width * image.height) >= expectedMP * 1e6 * 0.99 else { throw MobileFailure.message("真实RAW导出中断回归失败：" + (document.error ?? document.exportStatus)) }
                let elapsed = started.duration(to: .now)
                record["batchCount"] = document.exportedFiles.count
                record["previewEdge"] = document.preferences.values.previewEdge
                record["exportSpace"] = document.exportRecipe.colorSpace.rawValue
                record["exportQuality"] = document.exportRecipe.quality
                record["jpegWidth"] = image.width; record["jpegHeight"] = image.height
                record["seconds"] = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                record["memoryWarningAndInactiveSurvived"] = true
                if visible {
                    // The actual editor presents its native activity sheet.
                    // No external share action or Photos write is performed.
                    try await Task.sleep(for: .seconds(4))
                    document.clearExport()
                    record["visibleEditor"] = true
                } else { document.clearExport(); document.setActive(false) }
                let metadata = MobileImageMetadata.read(source)
                record["fullResolutionMegapixels"] = metadata.megapixels
                var full = MobileExportRecipe(); full.sizeMode = "original"
                let engine = MobileEngine()
                if args.contains("--audit-full") { record["fullResolutionStatus"] = "exported" }
                else { do {
                    let files = try await engine.exportFiles(url: source, recipe: [:], geometry: MobileGeometry(), options: full, stem: "Full-Resolution-Audit")
                    guard let input = CGImageSourceCreateWithURL(files[0] as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(input, 0, nil), Double(image.width * image.height) >= metadata.megapixels * 1e6 * 0.99 else { throw MobileFailure.message("完整分辨率被静默降低") }
                    record["fullResolutionStatus"] = "exported"
                    try? FileManager.default.removeItem(at: files[0].deletingLastPathComponent())
                } catch {
                    guard error.localizedDescription.contains("内存不足") else { throw error }
                    record["fullResolutionStatus"] = "blockedByMemory"
                    record["fullResolutionMessage"] = error.localizedDescription
                } }
            } else if args.contains("--audit-jpeg") {
                var cases: [[String: Any]] = []
                let engine = MobileEngine()
                for index in 0..<5 {
                    var options = MobileExportRecipe()
                    options.maximumMegapixels = index == 0 ? 24 : 12
                    options.colorSpace = index == 1 ? .srgb : index == 2 ? .adobe : .p3
                    options.quality = index == 1 ? 0.85 : 0.95
                    options.location = false
                    if index == 3 { options.sizeMode = "longEdge"; options.longEdge = 2048 }
                    if index == 4 { options.maximumMegapixels = 6; options.metadata = false }
                    let geometry = index == 3 ? MobileGeometry(quarterTurns: 1, aspect: 1) : MobileGeometry()
                    var peak = footprint()
                    let sampler = Task { @MainActor in while !Task.isCancelled { peak = max(peak, footprint()); try? await Task.sleep(for: .milliseconds(25)) } }
                    defer { sampler.cancel() }
                    let started = ContinuousClock.now
                    let stem = options.stem(original: "RAW-Check.ARW", film: "portra400", paper: "supra", counter: index + 1)
                    let files = try await engine.exportFiles(url: source, recipe: [:], geometry: geometry, options: options, stem: stem)
                    defer { try? FileManager.default.removeItem(at: files[0].deletingLastPathComponent()) }
                    let elapsed = started.duration(to: .now)
                    sampler.cancel(); peak = max(peak, footprint())
                    guard let input = CGImageSourceCreateWithURL(files[0] as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(input, 0, nil), let properties = CGImageSourceCopyPropertiesAtIndex(input, 0, nil) as? [String: Any] else { throw MobileFailure.message("JPG无法完整读回") }
                    guard image.bitsPerComponent == 8, properties[kCGImagePropertyProfileName as String] != nil, properties[kCGImagePropertyGPSDictionary as String] == nil else { throw MobileFailure.message("JPG位深、色彩或定位策略错误") }
                    let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
                    if options.metadata, exif[kCGImagePropertyExifFNumber as String] == nil { throw MobileFailure.message("JPG丢失拍摄信息") }
                    if !options.metadata, exif[kCGImagePropertyExifFNumber as String] != nil { throw MobileFailure.message("JPG未移除拍摄信息") }
                    if index == 3 {
                        guard image.width == 2048, image.height == 2048 else { throw MobileFailure.message("JPG旋转裁切长边不正确") }
                    } else { guard Double(image.width * image.height) >= options.maximumMegapixels * 1e6 * 0.95 else { throw MobileFailure.message("JPG没有达到所选分辨率") } }
                    let size = try FileManager.default.attributesOfItem(atPath: files[0].path)[.size] as? NSNumber
                    cases.append(["width": image.width, "height": image.height, "profile": properties[kCGImagePropertyProfileName as String] ?? "", "quality": options.quality, "metadata": options.metadata, "bytes": size?.intValue ?? 0, "filename": files[0].lastPathComponent, "peakFootprint": peak, "seconds": Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18, "thermal": ProcessInfo.processInfo.thermalState.rawValue])
                    record["cases"] = cases; write()
                }
            } else if args.contains("--audit-export") {
                var cases: [[String: Any]] = []
                let engine = MobileEngine()
                for format in [MobileExportFormat.jpeg, .tiff, .di] {
                    let requested = format == .di ? min(12, mp) : mp
                    var options = MobileExportRecipe(); options.format = format; options.maximumMegapixels = requested; options.embedsPreview = format == .tiff
                    record["currentCase"] = format.rawValue; record["availableBeforeCase"] = os_proc_available_memory(); write()
                    var peak = footprint()
                    let sampler = Task { @MainActor in
                        while !Task.isCancelled { peak = max(peak, footprint()); try? await Task.sleep(for: .milliseconds(25)) }
                    }
                    defer { sampler.cancel() }
                    let started = ContinuousClock.now
                    let files = try await engine.exportFiles(url: source, recipe: [:], geometry: MobileGeometry(), options: options, stem: "Device-Export-Audit")
                    let elapsed = started.duration(to: .now)
                    sampler.cancel(); peak = max(peak, footprint())
                    guard let input = CGImageSourceCreateWithURL(files[0] as CFURL, nil), let properties = CGImageSourceCopyPropertiesAtIndex(input, 0, nil) as? [String: Any] else { throw MobileFailure.message("无法读回导出文件") }
                    let width = properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0
                    let height = properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0
                    guard Double(width * height) > requested * 1_000_000 * 0.95 else { throw MobileFailure.message("导出没有达到请求尺寸") }
                    if format == .di, properties[kCGImagePropertyProfileName as String] != nil { throw MobileFailure.message("数字中间片错误继承源图色彩标记") }
                    cases.append(["format": format.rawValue, "megapixels": requested, "seconds": Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18,
                                  "peakFootprint": peak, "width": properties[kCGImagePropertyPixelWidth as String] ?? 0, "height": properties[kCGImagePropertyPixelHeight as String] ?? 0,
                                  "depth": properties[kCGImagePropertyDepth as String] ?? 0, "profile": properties[kCGImagePropertyProfileName as String] ?? "untagged",
                                  "pages": CGImageSourceGetCount(input), "files": files.count, "thermal": ProcessInfo.processInfo.thermalState.rawValue])
                    try? FileManager.default.removeItem(at: files[0].deletingLastPathComponent())
                    record["cases"] = cases; write()
                }
            } else {
                let available = os_proc_available_memory()
                guard Double(available) > (Double(mp) * 70 + 400) * 1_000_000 else { record["skippedForMemory"] = true; write(); return }
                guard ProcessInfo.processInfo.thermalState.rawValue < 2 else { record["skippedForThermal"] = true; write(); return }
                let engine = MobileEngine()
                var cases: [[String: Any]] = []
                let recipes: [(String, [String: WireValue])] = [("open-defaults", [:]), ("film-exposure", ["exposure_compensation_ev": .double(1.0 / 3)]),
                    ("print-exposure", ["exposure_compensation_ev": .double(1.0 / 3), "_printBrightnessStops": .double(0.25)]),
                    ("effects-stress", ["_grainAmount": .double(2), "halation_amount": .double(4), "glare_amount": .double(4)])]
                for (name, recipe) in recipes {
                    var peak = footprint()
                    let sampler = Task { @MainActor in
                        while !Task.isCancelled { peak = max(peak, footprint()); try? await Task.sleep(for: .milliseconds(25)) }
                    }
                    defer { sampler.cancel() }
                    let start = ContinuousClock.now
                    let result = try await engine.render(url: source, recipe: recipe, megapixels: mp)
                    let elapsed = start.duration(to: .now)
                    sampler.cancel()
                    peak = max(peak, footprint())
                    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                    cases.append(["case": name, "seconds": seconds, "width": result.image.width, "height": result.image.height,
                                  "peakFootprint": peak, "availableAfter": os_proc_available_memory(), "engineMemory": await engine.auditMemory(),
                                  "thermal": ProcessInfo.processInfo.thermalState.rawValue, "negativeWasCached": result.negativeWasCached])
                    record["cases"] = cases; write()
                }
                await engine.close()
            }
            record["passed"] = true
        } catch { record["error"] = error.localizedDescription }
        record["thermalEnd"] = ProcessInfo.processInfo.thermalState.rawValue
        record["footprintEnd"] = footprint()
        record["overallPeakFootprint"] = max(auditPeak, footprint())
        write()
    }
}
#endif
