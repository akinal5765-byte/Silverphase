import SwiftUI
import UIKit
import CoreImage
import UniformTypeIdentifiers

typealias WireValue = ParamValue

enum MobileExportDestination { case share, photos }

enum MobileExportFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case jpeg = "JPEG", png = "PNG", tiff = "TIFF 16-bit", di = "数字中间片"
    var id: String { rawValue }
    var type: UTType { switch self { case .jpeg: .jpeg; case .png: .png; case .tiff, .di: .tiff } }
    var fileExtension: String { switch self { case .jpeg: "jpg"; case .png: "png"; case .tiff, .di: "tif" } }
}

struct MobilePhoto: Codable, Identifiable {
    var id = UUID()
    var name: String
    var filename: String
    var recipe: [String: WireValue] = [:]
    var geometry = MobileGeometry()
    var rating = 0
    var flag = "none"
    var exifSummary = ""
    var sourceMegapixels = 0.0
    var sourceAspect = 1.5
}

@MainActor @Observable final class MobileDocument {
    let preferences = MobilePreferences()
    var exportRecipe = UserDefaults.standard.data(forKey: "mobile.export.current").flatMap { try? JSONDecoder().decode(MobileExportRecipe.self, from: $0) } ?? MobileExportRecipe() {
        didSet { if let data = try? JSONEncoder().encode(exportRecipe) { UserDefaults.standard.set(data, forKey: "mobile.export.current") } }
    }
    var exportPresets = UserDefaults.standard.data(forKey: "mobile.export.presets").flatMap { try? JSONDecoder().decode([MobileExportRecipe].self, from: $0) } ?? [] {
        didSet { if let data = try? JSONEncoder().encode(exportPresets) { UserDefaults.standard.set(data, forKey: "mobile.export.presets") } }
    }
    var exportFolder: URL?
    var exportStatus = ""
    var exportedFiles: [URL] = []
    var photos: [MobilePhoto] = []
    var selection: UUID? { didSet { if oldValue != selection { canvasState.reset(); pendingDefaultValues = [:] } } }
    private var pendingDefaultValues: [String: WireValue] = [:]
    let canvasState = MobileCanvasState()
    var image: CGImage?
    var original: CGImage?
    var cropSourceImage: CGImage?
    var cropEditing = false { didSet { if oldValue != cropEditing { cropSourceImage = nil; schedule() } } }
    var resolved: [String: WireValue] = [:]
    var latitude: MobileLatitude?
    var busy = false { didSet { if oldValue && !busy { queueDetailReconciliation() } } }
    private(set) var operation: MobileOperationProgress? {
        didSet {
            if let operation, oldValue?.id != operation.id { notification = nil }
            if oldValue != nil && operation == nil { queueDetailReconciliation() }
        }
    }
    private(set) var notification: MobileNotification?
    var currentNotification: MobileNotification? { operation.map(MobileNotification.operation) ?? notification }
    @discardableResult
    func postNotification(_ title: String, detail: String = "", style: MobileNotification.Style = .information,
                          fraction: Double? = nil, duration: Duration? = nil) -> UUID {
        let message = MobileNotification(style: style, title: title, detail: detail, fraction: fraction, duration: duration)
        notification = message
        return message.id
    }
    // Future progress producers retain this token. Stale producers cannot update
    // or dismiss a newer notification; updates never replay the entry animation.
    func updateNotification(_ id: UUID, detail: String, fraction: Double? = nil) {
        guard notification?.id == id else { return }
        notification?.detail = detail
        notification?.fraction = fraction
    }
    func dismissNotification(_ id: UUID) {
        guard notification?.id == id else { return }
        notification = nil
        error = nil
    }
    var isInteractionLocked: Bool { operation != nil }
    var isImporting: Bool { operation?.kind == .importing }
    private var importWasIdleDisabled: Bool?
    private var importCancelledPreview = false
    var error: String? {
        didSet {
            if let error { postNotification("处理未完成", detail: error, style: .failure) }
            else if notification?.style == .failure { notification = nil }
        }
    }
    var exported: URL?
    var delivering = false
    var notice: String? {
        get { notification?.style == .failure ? nil : notification?.title }
        set {
            if let newValue { postNotification(newValue, style: .success) }
            else { notification = nil }
        }
    }
    var active = true
    var showOriginal = false { didSet { if oldValue && !showOriginal { cancelOriginalDetail(clear: false); queueDetailReconciliation() } } }
    var pickingNeutral = false { didSet { if oldValue && !pickingNeutral { queueDetailReconciliation() } } }
    var neutralPreview: CGImage?
    var revision = 0
    private var undoStack: [MobilePhoto] = []
    private var redoStack: [MobilePhoto] = []
    private let engine = MobileEngine()
    private let detailRenderer = MobileDetailRenderer()
    var detailTile: MobileDetailTile?
    var detailBusy = false
    private let originalDetailEngine = MobileEngine()
    private var originalDetailWork: Task<Void, Never>?
    private var originalDetailGeneration = 0
    private var originalViewport: MobileViewport?
    private(set) var originalDetailTile: MobileDetailTile?
    private(set) var originalDetailBusy = false
    var originalNativeOutputSize: CGSize {
        if let size = originalDetailTile?.nativeSize { return size }
        if MobileFilmGate.presents(current?.recipe ?? [:]), let current, let original, lastFinalSourceMP > 0 {
            let ratio = sqrt(current.sourceMegapixels / lastFinalSourceMP)
            return CGSize(width: Double(original.width) * ratio, height: Double(original.height) * ratio)
        }
        return current?.geometry.outputSize(for: geometrySourceSize) ?? .zero
    }
    var previewStatus = ""
    private(set) var development: MobileDevelopmentAssets? { didSet { if oldValue != nil && development == nil { queueDetailReconciliation() } } }
    private(set) var developmentRunning = false
    // One opening ritual per document lifetime (one app launch), not per photo.
    private var developmentOffered = false
    func printNegative() { if development != nil { developmentRunning = true } }
    func finishDevelopment(_ id: UUID? = nil) {
        guard id == nil || development?.id == id else { return }
        development = nil; developmentRunning = false
    }
    var canvasZoomRequest = 0
    var canvasWantsNative = false
    private var fitPreviewEdge = 1920
    private var lastFinalRequestedEdge = 0
    private var lastCompletedPreviewRevision = -1
    private var detailRetryAfter = 0.0
    private var lastMemoryWarning = -Double.infinity
    private var memoryWarningBurst = 0
    private var memoryRecoveryTask: Task<Void, Never>?
    private var nativeCanvasSize = CGSize.zero
    private var nativeCanvasSizeIsExact = false
    var nativeOutputSize: CGSize { nativeCanvasSize == .zero ? current?.geometry.outputSize(for: geometrySourceSize) ?? .zero : nativeCanvasSize }
    func zoomToNative() { canvasState.reset(native: true); canvasWantsNative = true; canvasZoomRequest += 1 }
    func zoomToFit() { canvasState.reset(); canvasWantsNative = false; canvasZoomRequest += 1 }
    private var finalPreviewEdge: Int {
#if DEBUG
        if let previewEdgeOverride { return previewEdgeOverride }
#endif
        let wanted = max(fitPreviewEdge, min(3840, Int(viewport?.pixelLongEdge ?? 0)))
        return preferences.values.lowerPreviewInLowPower && ProcessInfo.processInfo.isLowPowerModeEnabled ? min(1920, wanted) : wanted
    }
    private func previewMegapixels(_ photo: MobilePhoto, edge: Int) -> Double {
        let native = nativeOutputSize
        let long = max(1, max(native.width, native.height))
        let sourceCap = MobilePreviewPolicy.megapixels(edge: 3840, aspect: photo.sourceAspect)
        return max(0.01, min(sourceCap, min(photo.sourceMegapixels, photo.sourceMegapixels * pow(Double(edge) / long, 2))))
    }
    private var viewport: MobileViewport?
    private var detailTask: Task<Void, Never>?
    private var detailCleanupTask: Task<Void, Never>?
    private var detailReconciliationTask: Task<Void, Never>?
    private var detailGeneration = 0
    private var interactionStart: MobilePhoto?
    private var interactionTask: Task<Void, Never>?
    private var interactionGeneration = 0
    private var interactionVersion = 0
    private var interactionEdge = 1600
    private var activeInteractionEdge = 1600
    private var lastFinalSourceMP = 0.0
    private var activeInteractionSourceMP = 0.0
#if DEBUG
    private(set) var interactionFrames = 0
    private(set) var interactionSeconds: [Double] = []
    private(set) var interactionCachedFrames = 0
    var previewEdgeOverride: Int?
    func detailAudit() async -> [String: Int] { await detailRenderer.audit() }
    func viewportAudit() -> [String: Double] { ["requestedEdge": viewport?.pixelLongEdge ?? 0, "nativeEdge": max(nativeOutputSize.width, nativeOutputSize.height), "nativeExact": nativeCanvasSizeIsExact ? 1 : 0, "canvasWidthPixels": Double(viewport?.pixelSize.width ?? 0), "canvasHeightPixels": Double(viewport?.pixelSize.height ?? 0)] }
    func requestedViewportAudit() -> MobileViewport? { viewport }
    func originalViewportAudit() -> [String: Double] {
        ["widthPixels": Double(originalViewport?.pixelSize.width ?? 0), "heightPixels": Double(originalViewport?.pixelSize.height ?? 0)]
    }
    func detailRecipeAudit() async -> [String: WireValue] { await detailRenderer.auditRecipe() }
    func waitForPreviewCleanup() async { await detailCleanupTask?.value; await previewCleanupTask?.value }
#endif
    private let exportEngine = MobileEngine()
    private var previewAfterExport = false
    private var exportInterruptedByBackground = false
    private var renderTask: Task<Void, Never>?
    private var previewCleanupTask: Task<Void, Never>?
    private let directory: URL
    var current: MobilePhoto? { photos.first { $0.id == selection } }
    var canUndo: Bool { !isInteractionLocked && !undoStack.isEmpty }
    var canRedo: Bool { !isInteractionLocked && !redoStack.isEmpty }

    init(directory: URL? = nil) {
        // Imported files are owned temporary copies for this launch only.
        self.directory = directory ?? URL.applicationSupportDirectory.appendingPathComponent(ProcessInfo.processInfo.arguments.contains("--smoke-test") ? "Silverphase-Diagnostics" : "Silverphase", isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: self.directory.path) {
                try FileManager.default.removeItem(at: self.directory)
            }
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        } catch { self.error = "准备临时工作区失败：\(error.localizedDescription)" }
    }

    func url(for photo: MobilePhoto) -> URL { directory.appendingPathComponent(photo.filename) }
    func select(_ id: UUID) {
        guard !isInteractionLocked, id != selection else { return }
        endParameterInteraction(); cancelDetail(); viewport = nil; nativeCanvasSize = .zero; nativeCanvasSizeIsExact = false; lastFinalRequestedEdge = 0
        selection = id; image = nil; original = nil; cropSourceImage = nil; resolved = [:]; latitude = nil; neutralPreview = nil; pickingNeutral = false
        undoStack = []; redoStack = []; showOriginal = false
        schedule()
    }
    @discardableResult func beginPhotoImport(total: Int) -> Bool {
        guard !isInteractionLocked, !delivering else { return false }
        beginImport(stage: .receiving, total: total)
        return true
    }
    func photoImportProgress(index: Int, total: Int, name: String) {
        guard isImporting, operation?.stage == .receiving else { return }
        operation?.index = index; operation?.total = total; operation?.filename = name
    }
    func finishPhotoImportWithoutFiles() {
        guard isImporting, operation?.stage == .receiving, let id = operation?.id else { return }
        finishImport(id: id, resumePrevious: true)
    }
    private func beginImport(stage: MobileOperationProgress.Stage, total: Int) {
        finishDevelopment()
        showOriginal = false
        endParameterInteraction(); cancelDetail(); viewport = nil
        importCancelledPreview = busy
        revision += 1; renderTask?.cancel(); renderTask = nil; engine.workGate.cancel()
        pickingNeutral = false; neutralPreview = nil
        operation = MobileOperationProgress(kind: .importing, stage: stage, total: total)
        error = nil; busy = true
        importWasIdleDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
    }
    private func finishImport(id: UUID?, resumePrevious: Bool = false) {
        guard let id, isImporting, operation?.id == id else { return }
        let resume = resumePrevious && importCancelledPreview
        operation = nil; busy = false; importCancelledPreview = false
        if let previous = importWasIdleDisabled { UIApplication.shared.isIdleTimerDisabled = previous }
        importWasIdleDisabled = nil
        if resume, active, current != nil { schedule() }
    }
    @discardableResult func importFiles(_ urls: [URL], displayNames: [URL: String] = [:], removeSourcesAfterImport: Bool = false,
                                        continuingPhotoSelection: Bool = false) -> Task<Void, Never> {
        let adoptingPicker = continuingPhotoSelection && isImporting && operation?.stage == .receiving
        guard !delivering, !isInteractionLocked || adoptingPicker else { return Task {} }
        if !adoptingPicker { beginImport(stage: .copying, total: urls.count) }
        guard let importID = operation?.id else { return Task {} }
        operation?.stage = .copying; operation?.total = urls.count; operation?.index = 1
        return Task {
            var imported: [MobilePhoto] = []
            var failures: [String] = []
            for (index, source) in urls.enumerated() {
                operation?.index = index + 1
                operation?.filename = displayNames[source] ?? source.lastPathComponent
                var photo = MobilePhoto(name: displayNames[source] ?? source.lastPathComponent,
                                        filename: UUID().uuidString + "." + source.pathExtension)
                let destination = url(for: photo)
                do {
                    let metadata = try await Task.detached(priority: .userInitiated) {
                        let scoped = source.startAccessingSecurityScopedResource()
                        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                        var coordinationError: NSError?
                        var copyError: Error?
                        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
                            do { try FileManager.default.copyItem(at: readable, to: destination) }
                            catch { copyError = error }
                        }
                        if let error = coordinationError ?? copyError as NSError? { throw error }
                        return MobileImageMetadata.read(destination)
                    }.value
                    photo.exifSummary = metadata.exifSummary
                    photo.sourceMegapixels = metadata.megapixels
                    photo.sourceAspect = metadata.aspect
                    if let ext = metadata.fileExtension, metadata.isRaw, destination.pathExtension.lowercased() != ext.lowercased() {
                        let corrected = destination.deletingPathExtension().appendingPathExtension(ext)
                        try FileManager.default.moveItem(at: destination, to: corrected)
                        photo.filename = corrected.lastPathComponent
                    }
                    imported.append(photo)
                } catch {
                    try? FileManager.default.removeItem(at: destination)
                    failures.append("导入 \(photo.name) 失败：\(error.localizedDescription)")
                }
                if removeSourcesAfterImport { try? FileManager.default.removeItem(at: source) }
            }
            photos += imported; save()
            if !failures.isEmpty { error = failures.joined(separator: "\n") }
            if let first = imported.first {
                // Keep the same operation through the first usable preview.
                selection = first.id; image = nil; original = nil; cropSourceImage = nil; resolved = [:]; latitude = nil
                nativeCanvasSize = .zero; nativeCanvasSizeIsExact = false; lastFinalRequestedEdge = 0
                undoStack = []; redoStack = []; showOriginal = false
                operation?.stage = .preview; operation?.filename = first.name
                operation?.index = 1; operation?.total = imported.count
                scheduleRender(importID: importID)
            } else { finishImport(id: importID, resumePrevious: true) }
        }
    }
    func beginNeutralPick() {
        guard !isInteractionLocked else { return }
        finishDevelopment()
        if pickingNeutral { pickingNeutral = false; neutralPreview = nil; return }
        guard let photo = current else { return }
        revision += 1
        let generation = revision
        renderTask?.cancel(); engine.workGate.cancel(); busy = true
        let url = url(for: photo)
        var sampling = photo.recipe
        sampling["overscan_active"] = .bool(false); sampling["date_imprint_active"] = .bool(false)
        renderTask = Task {
            do {
                let result = try await engine.render(url: url, recipe: sampling, megapixels: 2)
                guard generation == revision, selection == photo.id else { return }
                neutralPreview = result.original; pickingNeutral = true; busy = false
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription; busy = false }
        }
    }
    func pickNeutral(_ point: CGPoint) {
        guard !isInteractionLocked, pickingNeutral, let photo = current else { return }
        let url = url(for: photo)
        renderTask = Task {
            do {
                let pair = try await engine.neutralPoint(url: url, point: point)
                guard selection == photo.id, pickingNeutral else { return }
                pickingNeutral = false; neutralPreview = nil
                setValues(["_temperature": .double(pair.0), "_tint": .double(pair.1), "_whiteBalancePreset": .string("custom")])
            } catch { self.error = error.localizedDescription }
        }
    }
    func defaultNumber(_ key: String) -> Double? {
        if key == "_temperature" { return resolved["_asShotTemperature"]?.doubleValue }
        if key == "_tint" { return resolved["_asShotTint"]?.doubleValue }
        if key == "_placementHighlight" || key == "_placementShadow" { return 0 }
        if key == "_sideLengthMM", let frame = MobileProcessContract.frames.first(where: { $0.id == value("_filmFrame")?.stringValue }) {
            return value("_filmSide")?.stringValue == "long" ? frame.long : frame.short
        }
        return MobileProcessContract.clientDefaults[key]?.doubleValue ?? MobileProcessContract.defaults[key]?.doubleValue
    }
    func value(_ key: String) -> WireValue? {
        func raw(_ key: String) -> WireValue? { current?.recipe[key] ?? pendingDefaultValues[key] ?? resolved[key] ?? MobileProcessContract.clientDefaults[key] ?? MobileProcessContract.defaults[key] }
        if key == "_meter" { return .string(raw("auto_exposure")?.boolValue == false ? "custom" : raw("auto_exposure_method")?.stringValue ?? "center_weighted") }
        if key == "_halation" { return .string(raw("halation_active")?.boolValue == false ? "off" : raw("antihalation_mode")?.stringValue ?? "profile") }
        for prefix in ["camera", "enlarger"] where key == "_" + prefix + "Diffusion" {
            return .string(raw(prefix + "_diffusion_active")?.boolValue == true ? raw(prefix + "_diffusion_family")?.stringValue ?? "black_pro_mist" : "off")
        }
        return raw(key)
    }
    func set(_ key: String, _ value: WireValue) {
        edit { photo in
            if key == "_meter", let method = value.stringValue {
                photo.recipe["auto_exposure"] = .bool(method != "custom")
                if method != "custom" { photo.recipe["auto_exposure_method"] = .string(method) }
                return
            }
            if key == "_halation", let mode = value.stringValue {
                photo.recipe["halation_active"] = .bool(mode != "off")
                if mode != "off" { photo.recipe["antihalation_mode"] = .string(mode) }
                return
            }
            for prefix in ["camera", "enlarger"] where key == "_" + prefix + "Diffusion" {
                let family = value.stringValue ?? "off"
                photo.recipe[prefix + "_diffusion_active"] = .bool(family != "off")
                if family != "off" { photo.recipe[prefix + "_diffusion_family"] = .string(family) }
                return
            }
            if key == "_whiteBalancePreset", let preset = value.stringValue {
                if preset == "asShot" { photo.recipe.removeValue(forKey: "_temperature"); photo.recipe.removeValue(forKey: "_tint") }
                else if let temperature = ["daylight": 5500.0, "cloudy": 6500.0, "shade": 7500.0, "tungsten": 3200.0, "fluorescent": 4000.0][preset] {
                    photo.recipe["_temperature"] = .double(temperature); photo.recipe["_tint"] = .double(0)
                }
            }
            if key == "_temperature" || key == "_tint" { photo.recipe["_whiteBalancePreset"] = .string("custom") }
            photo.recipe[key] = value
            if key == "_filmFrame" || key == "_filmSide" {
                let name = photo.recipe["_filmFrame"]?.stringValue ?? "135"
                if let frame = MobileProcessContract.frames.first(where: { $0.id == name }), name != "Custom" {
                    photo.recipe["_sideLengthMM"] = .double(photo.recipe["_filmSide"]?.stringValue == "long" ? frame.long : frame.short)
                }
            }
        }
    }
    func setDiscrete(_ key: String, _ value: WireValue) {
        // A menu/button is a completed edit, even if a ruler's drag was
        // cancelled by the menu before receiving onEnded.
        endParameterInteraction()
        set(key, value)
    }
    func setFilm(_ film: Stock) {
        endParameterInteraction()
        let wasPositive = value("film_stock")?.stringValue.flatMap { StockCatalog.shared.stock($0) }?.isPositive == true
        edit {
            $0.recipe["film_stock"] = .string(film.id)
            if film.isPositive || wasPositive { $0.recipe["scan_film"] = .bool(film.isPositive) }
            $0.recipe["digital_intermediate"] = .bool(false)
            if let paper = film.targetPrint { $0.recipe["print_stock"] = .string(paper) }
        }
    }
    func setPaper(_ paper: Stock?) {
        endParameterInteraction()
        edit {
            $0.recipe["scan_film"] = .bool(paper == nil)
            $0.recipe["digital_intermediate"] = .bool(false)
            $0.recipe.removeValue(forKey: "_paperGrade")
            $0.recipe.removeValue(forKey: "c_filter_neutral")
            $0.recipe.removeValue(forKey: "m_filter_neutral")
            $0.recipe.removeValue(forKey: "y_filter_neutral")
            if let paper { $0.recipe["print_stock"] = .string(paper.id) }
        }
    }
    var geometrySourceSize: CGSize {
        let aspect = current?.sourceAspect ?? 1.5
        let area = max(1, (current?.sourceMegapixels ?? 1) * 1_000_000)
        return CGSize(width: sqrt(area * aspect), height: sqrt(area / aspect))
    }
    func setGeometry(_ value: Geometry) {
        let fitted = value.fitted(in: geometrySourceSize)
        edit { $0.geometry = MobileGeometry(value: fitted) }
    }
    func rotate() { guard let g = current?.geometry.value else { return }; setGeometry(g.turned(by: 1)) }
    func aspect(_ aspect: Double) {
        guard var g = current?.geometry.value else { return }
        g.aspect = CropAspect.pickerCases.flatMap { [$0, $0.transposed] }.first { abs(($0.fixedRatio ?? 0) - aspect) < 1e-6 } ?? .free
        setGeometry(g.constrained(in: geometrySourceSize))
    }
    func resetStage(_ stage: MobileStage) {
        let keys: [String]
        switch stage {
        case .camera: keys = ["auto_exposure", "auto_exposure_method", "exposure_compensation_ev", "_temperature", "_tint", "_whiteBalancePreset", "_lens", "camera_filter", "camera_diffusion_active", "camera_diffusion_family", "camera_diffusion_strength", "camera_diffusion_range", "_placementHighlight", "_placementShadow"]
        case .film: keys = ["film_format_mm", "_filmFrame", "_filmSide", "_sideLengthMM", "_sideUnit", "grain_active", "grain_sublayers_active", "_grainAmount", "grain_amount", "grain_size_scale", "_grainSoftness", "grain_softness", "halation_active", "antihalation_mode", "halation_amount", "halation_scatter_amount"]
        case .development: keys = ["density_curve_gamma", "dir_couplers_active", "dir_couplers_amount"]
        case .print: keys = ["_printBrightnessStops", "print_exposure", "print_contrast", "_paperGrade", "y_filter_shift", "m_filter_shift", "preflash_exposure", "_printEffects", "enlarger_diffusion_active", "enlarger_diffusion_family", "enlarger_diffusion_strength", "enlarger_diffusion_range"]
        case .output: keys = ["_scannerActive", "_scannerStrength", "scanner_sharpening_amount", "glare_active", "glare_amount", "extended_dynamic_range"]
        case .filmEdge: keys = Array(MobileProcessContract.clientDefaults.keys.filter { $0.hasPrefix("overscan_") || $0.hasPrefix("date_imprint_") || $0.hasPrefix("_date") }) + ["overscan_active", "date_imprint_active"]
        case .geometry: edit { $0.geometry = MobileGeometry() }; return
        }
        edit { photo in
            for key in keys { photo.recipe.removeValue(forKey: key) }
            // Desktop's explicit output-section Reset turns highlight expansion
            // off; creating/resetting the whole photo still defaults to on.
            if stage == .output { photo.recipe["extended_dynamic_range"] = .bool(false) }
        }
    }
    func reset() { edit { $0.recipe = [:]; $0.geometry = MobileGeometry() } }
    private func invalidateNativeGeometry(from before: MobilePhoto, to after: MobilePhoto) {
        if before.geometry != after.geometry || ["overscan_active", "overscan_format", "overscan_mode", "overscan_gate", "overscan_carrier", "overscan_camera_seed", "date_imprint_active", "_lens"].contains(where: { before.recipe[$0] != after.recipe[$0] }) {
            nativeCanvasSize = .zero; nativeCanvasSizeIsExact = false
        }
    }
    private func edit(_ change: (inout MobilePhoto) -> Void) {
        guard !isInteractionLocked else { return }
        guard let index = photos.firstIndex(where: { $0.id == selection }) else { return }
        pickingNeutral = false; neutralPreview = nil
        let before = photos[index]; change(&photos[index])
        invalidateNativeGeometry(from: before, to: photos[index])
        if interactionStart?.id == selection {
            interactionVersion += 1; scheduleInteraction(); return
        }
        undoStack.append(before)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack = []; save(); schedule()
    }
    func undo() {
        guard !isInteractionLocked else { return }
        endParameterInteraction()
        guard let index = photos.firstIndex(where: { $0.id == selection }), let previous = undoStack.popLast() else { return }
        invalidateNativeGeometry(from: photos[index], to: previous)
        redoStack.append(photos[index]); photos[index] = previous; save(); schedule()
    }
    func redo() {
        guard !isInteractionLocked else { return }
        endParameterInteraction()
        guard let index = photos.firstIndex(where: { $0.id == selection }), let next = redoStack.popLast() else { return }
        invalidateNativeGeometry(from: photos[index], to: next)
        undoStack.append(photos[index]); photos[index] = next; save(); schedule()
    }
    // Retained as an in-memory change hook; no library or recipe sidecars.
    func save() { }
    var settingsClipboard: MobilePhoto?
    func copySettings(_ photo: MobilePhoto) { if !isInteractionLocked { settingsClipboard = photo } }
    func pasteSettings() {
        guard let settingsClipboard else { return }
        let geometry = MobileGeometry(value: settingsClipboard.geometry.value.fitted(in: geometrySourceSize))
        edit { $0.recipe = settingsClipboard.recipe; $0.geometry = geometry }
    }
    func mark(_ id: UUID, rating: Int? = nil, flag: String? = nil) {
        guard !isInteractionLocked else { return }
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        if let rating { photos[index].rating = min(5, max(0, rating)) }
        if let flag { photos[index].flag = flag }
    }
    func remove(_ id: UUID) {
        guard !isInteractionLocked, !delivering, let index = photos.firstIndex(where: { $0.id == id }) else { return }
        endParameterInteraction()
        let removed = photos.remove(at: index)
        if selection == id {
            finishDevelopment(); cancelDetail(); viewport = nil
            nativeCanvasSize = .zero; nativeCanvasSizeIsExact = false
            revision += 1; renderTask?.cancel(); engine.workGate.cancel()
            selection = nil; image = nil; original = nil; resolved = [:]; latitude = nil
            undoStack = []; redoStack = []; busy = false
            queuePreviewClose()
            if let next = photos.first { select(next.id) }
        }
        try? FileManager.default.removeItem(at: url(for: removed))
    }
    func resetKeys(_ keys: [String]) {
        guard !isInteractionLocked, current != nil else { return }
        for key in keys {
            if let number = defaultNumber(key) { pendingDefaultValues[key] = .double(number) }
        }
        edit { photo in
            keys.forEach { photo.recipe.removeValue(forKey: $0) }
            if keys.contains("_temperature") || keys.contains("_tint"), photo.recipe["_temperature"] == nil, photo.recipe["_tint"] == nil { photo.recipe["_whiteBalancePreset"] = .string("asShot") }
        }
    }
    func setValues(_ values: [String: WireValue]) { endParameterInteraction(); edit { $0.recipe.merge(values) { _, new in new } } }
    func beginParameterInteraction() {
        guard !isInteractionLocked, interactionStart == nil, let photo = current else { return }
        finishDevelopment()
        interactionStart = photo; interactionGeneration += 1; interactionVersion = 0
        activeInteractionEdge = min(interactionEdge, max(fitPreviewEdge, min(3840, Int(viewport?.pixelLongEdge ?? 0))))
        activeInteractionSourceMP = lastFinalSourceMP
        if preferences.values.lowerPreviewInLowPower && ProcessInfo.processInfo.isLowPowerModeEnabled { activeInteractionEdge = min(1920, activeInteractionEdge) }
#if DEBUG
        interactionFrames = 0; interactionSeconds = []; interactionCachedFrames = 0
#endif
        renderTask?.cancel(); renderTask = nil; revision += 1
        engine.workGate.cancel(); cancelDetail()
    }
    func parameterInteraction(_ dragging: Bool) {
        if dragging { beginParameterInteraction() } else { endParameterInteraction() }
    }
    func endParameterInteraction() {
        guard let start = interactionStart else { return }
        interactionStart = nil; interactionGeneration += 1
        interactionTask?.cancel(); interactionTask = nil; engine.workGate.cancel()
        if let photo = current, photo.id == start.id, photo.recipe != start.recipe || photo.geometry != start.geometry {
            undoStack.append(start); if undoStack.count > 100 { undoStack.removeFirst() }
            redoStack = []; save()
        }
        schedule()
    }
    private func scheduleInteraction() {
        guard interactionTask == nil, active, !delivering, !isImporting else { return }
        let token = interactionGeneration
        let cleanup = detailCleanupTask
        let previewCleanup = previewCleanupTask
        busy = true; previewStatus = "交互预览"
        interactionTask = Task {
            defer { if token == interactionGeneration { interactionTask = nil; busy = false } }
            do {
                try await Task.sleep(for: .milliseconds(16))
                await cleanup?.value
                await previewCleanup?.value
                try Task.checkCancellation()
                while let photo = current, interactionStart?.id == photo.id, token == interactionGeneration {
                    let version = interactionVersion
                    var settings = photo.recipe
                    settings["_diBlue"] = .bool(preferences.values.diBlueCompensation)
                    settings["_cropRecalc"] = .bool(preferences.values.cropRemapsEffects)
                    settings["_interactivePreview"] = .bool(true)
                    settings["_interactiveEdge"] = .double(Double(max(800, activeInteractionEdge)))
                    let changesDecode = ["_temperature", "_tint", "_lens"].contains { photo.recipe[$0] != interactionStart?.recipe[$0] }
                    let inputMP = changesDecode || activeInteractionSourceMP <= 0 ? MobilePreviewPolicy.megapixels(edge: activeInteractionEdge, aspect: photo.sourceAspect) : activeInteractionSourceMP
                    let began = ContinuousClock.now
                    let result = try await engine.render(url: url(for: photo), recipe: settings,
                        megapixels: inputMP, geometry: photo.geometry)
                    let working = try MobileFilmGate.presents(photo.recipe) ? result.image : photo.geometry.apply(to: result.image)
                    let display = try await engine.canvasImage(working)
                    try Task.checkCancellation()
                    guard active, token == interactionGeneration, selection == photo.id else { return }
                    image = display; resolved = result.resolved
                    if let latitude = result.latitude { self.latitude = latitude }
                    let elapsed = began.duration(to: .now)
                    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
#if DEBUG
                    interactionFrames += 1; interactionSeconds.append(seconds)
                    if result.negativeWasCached { interactionCachedFrames += 1 }
#endif
                    interactionEdge = MobilePreviewPolicy.nextInteractionEdge(activeInteractionEdge, seconds: seconds)
                    if version == interactionVersion { break }
                    // One in flight, one latest value. Never queue every touch.
                }
            } catch is CancellationError { }
            catch { if token == interactionGeneration { previewStatus = "松手后更新完整预览" } }
        }
    }
    private func cancelDetail() {
        cancelOriginalDetail(clear: true)
        let originalWork = originalDetailWork
        let previousCleanup = detailCleanupTask
        let previousWork = detailTask
        detailGeneration += 1; detailTask?.cancel(); detailTask = nil
        detailRenderer.engine.workGate.cancel(); detailTile = nil; detailBusy = false
        if previewStatus.hasPrefix("细节") { previewStatus = "" }
        let token = detailGeneration
        detailCleanupTask = Task {
            await previousCleanup?.value
            await previousWork?.value
            await originalWork?.value
            await detailRenderer.clear()
            if token == detailGeneration { detailCleanupTask = nil }
        }
    }
    @discardableResult private func queuePreviewClose() -> Task<Void, Never> {
        let prior = previewCleanupTask
        let detailCleanup = detailCleanupTask
        let previousWork = renderTask
        let task = Task {
            await prior?.value
            await detailCleanup?.value
            await previousWork?.value
            await engine.close()
        }
        previewCleanupTask = task
        return task
    }
    func requestDetail(_ requested: MobileViewport) {
        guard !showOriginal else { return } // a brief comparison must not discard native detail
        // Store the user's screen-space demand unchanged. A temporary low-res
        // frame (or native estimate) must never overwrite the requested zoom.
        viewport = requested
        fitPreviewEdge = MobilePreviewPolicy.fitEdge(pixels: requested.pixelLongEdge / max(0.01, requested.zoom))
        reconcileDetail()
    }
    private func cancelOriginalDetail(clear: Bool) {
        originalDetailGeneration += 1; originalDetailWork?.cancel(); originalDetailBusy = false
        if previewStatus.hasPrefix("原图细节") { previewStatus = "" }
        if clear { originalDetailTile = nil; originalViewport = nil }
    }
    func requestOriginalDetail(_ request: MobileViewport) {
        guard showOriginal, active, !isInteractionLocked, let photo = current else { return }
        originalViewport = request
        guard ProcessInfo.processInfo.systemUptime >= detailRetryAfter else { return }
        guard request.needsDetail else { return }
        if let tile = originalDetailTile, originalSatisfies(tile, request) { return }
        guard !originalDetailBusy else { return }
        let previous = originalDetailWork
        let processedWork = detailTask
        let previewWork = renderTask
        let token = originalDetailGeneration
        originalDetailBusy = true
        originalDetailWork = Task {
            defer { if token == originalDetailGeneration { originalDetailBusy = false } }
            await previous?.value
            await processedWork?.value
            await previewWork?.value
            do {
                try Task.checkCancellation()
                while let requested = originalViewport, showOriginal {
                    let tile = try await originalDetailEngine.originalDetail(url: url(for: photo), recipe: photo.recipe,
                        geometry: photo.geometry, viewport: requested.rect, pixelLongEdge: requested.pixelLongEdge)
                    try Task.checkCancellation()
                    guard token == originalDetailGeneration, selection == photo.id, showOriginal else { return }
                    if let latest = originalViewport, originalSatisfies(tile, latest) {
                        originalDetailTile = tile
                        break
                    }
                }
            } catch is CancellationError { }
            catch { if token == originalDetailGeneration { previewStatus = "原图细节暂不可用" } }
        }
    }
    private func originalSatisfies(_ tile: MobileDetailTile, _ request: MobileViewport) -> Bool {
        let edge = max(Double(tile.image.width) / tile.rect.width, Double(tile.image.height) / tile.rect.height)
        return tile.rect.contains(request.rect) && (tile.nativeSize != nil || edge >= request.pixelLongEdge * 0.999)
    }
    private var currentDetailDemand: MobileViewport? {
        guard var request = viewport else { return nil }
        request.previewLongEdge = image.map { max($0.width, $0.height) } ?? request.previewLongEdge
        request.pixelLongEdge = min(request.pixelLongEdge, max(nativeOutputSize.width, nativeOutputSize.height))
        return request
    }
    private func satisfies(_ tile: MobileDetailTile, _ request: MobileViewport) -> Bool {
        guard tile.rect.contains(request.rect) else { return false }
        let nativeEdge = max(nativeOutputSize.width, nativeOutputSize.height)
        if request.pixelLongEdge >= nativeEdge * 0.995 { return tile.nativeSize != nil }
        let edge = max(Double(tile.image.width) / tile.rect.width, Double(tile.image.height) / tile.rect.height)
        return tile.nativeSize != nil || edge >= request.pixelLongEdge * 0.999
    }
    private func queueDetailReconciliation() {
        guard detailReconciliationTask == nil else { return }
        // Let the whole state transition settle first (image, busy, import
        // lock, comparison). A stationary viewport sends no second event.
        detailReconciliationTask = Task { [weak self] in
            await Task.yield()
            guard let self else { return }
            detailReconciliationTask = nil
            reconcileDetail()
        }
    }
    private func reconcileDetail() {
        guard !showOriginal, development == nil, let request = currentDetailDemand else { return }
        guard ProcessInfo.processInfo.systemUptime >= detailRetryAfter else { return }
        if request.zoom <= 1.05, lastFinalRequestedEdge < finalPreviewEdge, !busy, !isInteractionLocked, interactionStart == nil {
            schedule(); return
        }
        guard request.needsDetail, !showOriginal, !pickingNeutral, !cropEditing else {
            if detailTask != nil || detailTile != nil { cancelDetail() }
            return
        }
        guard active, !busy, !isInteractionLocked, interactionStart == nil, let photo = current else { return }
        if let tile = detailTile, satisfies(tile, request) { return }
        guard detailTask == nil else { return }
        let token = detailGeneration
        let cleanup = detailCleanupTask
        let previewCleanup = previewCleanupTask
        let originalWork = originalDetailWork
        detailBusy = true
        detailTask = Task {
            var reconcileOnCompletion = true
            defer {
                if token == detailGeneration {
                    detailTask = nil; detailBusy = false
                    if reconcileOnCompletion { queueDetailReconciliation() }
                }
            }
            do {
                try await Task.sleep(for: .milliseconds(120))
                await cleanup?.value
                await previewCleanup?.value
                await originalWork?.value
                try Task.checkCancellation()
                await engine.close() // release the preview arena before growing detail
                try Task.checkCancellation()
                var failures = 0
                while let requested = currentDetailDemand, requested.needsDetail {
                    do {
                        var settings = photo.recipe
                        settings["_diBlue"] = .bool(preferences.values.diBlueCompensation)
                        settings["_cropRecalc"] = .bool(preferences.values.cropRemapsEffects)
                        let tile = try await detailRenderer.tile(url: url(for: photo), recipe: settings, geometry: photo.geometry,
                                                               viewport: requested.rect, pixelLongEdge: requested.pixelLongEdge)
                        try Task.checkCancellation()
                        guard active, token == detailGeneration, selection == photo.id else { return }
                        // Zoom/pan may have changed while the GPU was running.
                        // Publish only if this tile fulfils the CURRENT demand.
                        if let latest = currentDetailDemand, latest.needsDetail, satisfies(tile, latest) {
                            detailTile = tile; previewStatus = ""
                            if let native = tile.nativeSize { nativeCanvasSize = native; nativeCanvasSizeIsExact = true }
                            break
                        }
                    } catch {
                        guard !Task.isCancelled, active, token == detailGeneration, failures < 2 else { throw error }
                        failures += 1
                        await detailRenderer.clear()
                        try await Task.sleep(for: .milliseconds(250 * failures))
                    }
                }
            } catch is CancellationError { }
            catch {
                reconcileOnCompletion = false // bounded retries; no hot failure loop
                if token == detailGeneration { previewStatus = "细节暂不可用，保留现有预览" }
            }
        }
    }
    func schedule() {
        guard !isImporting else { return }
        scheduleRender()
    }
    func compareCanvas(_ held: Bool) {
        guard held else { showOriginal = false; return }
        guard active, !isInteractionLocked, !pickingNeutral, !cropEditing, original != nil else { return }
        finishDevelopment()
        showOriginal = true
    }
    private func scheduleRender(importID: UUID? = nil) {
        finishDevelopment()
        cancelDetail()
        guard !delivering else { previewAfterExport = true; return }
        revision += 1
        let generation = revision
        renderTask?.cancel()
        engine.workGate.cancel()
        guard active, let photo = current else { return }
        let url = url(for: photo)
        let targetEdge = finalPreviewEdge
        let targetMP = previewMegapixels(photo, edge: targetEdge)
        let cleanup = detailCleanupTask
        let previewCleanup = previewCleanupTask
        busy = true
        renderTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(180))
                await cleanup?.value
                await previewCleanup?.value
                try Task.checkCancellation()
                var settings = photo.recipe
                settings["_diBlue"] = .bool(preferences.values.diBlueCompensation)
                settings["_cropRecalc"] = .bool(preferences.values.cropRemapsEffects)
                let result = try await engine.render(url: url, recipe: settings, megapixels: targetMP, geometry: photo.geometry)
                guard !Task.isCancelled, generation == revision, active else { return }
                let working = try MobileFilmGate.presents(photo.recipe) ? result.image : photo.geometry.apply(to: result.image)
                let before = try MobileFilmGate.presents(photo.recipe) ? result.original : photo.geometry.apply(to: result.original)
                let display = try await engine.canvasImage(working)
                let displayOriginal = try await engine.canvasImage(before)
                let cropDisplay: CGImage?
                if !cropEditing { cropDisplay = nil }
                else if MobileFilmGate.presents(photo.recipe) {
                    if let source = cropSourceImage { cropDisplay = source }
                    else { cropDisplay = try await engine.cropCanvasImage(url: url, recipe: settings, megapixels: targetMP) }
                } else { cropDisplay = photo.geometry.value.isIdentity ? display : try await engine.canvasImage(result.image) }
                guard !Task.isCancelled, generation == revision, active else { return }
                let shouldDevelop = !developmentOffered && !UIAccessibility.isReduceMotionEnabled && result.resolved["scan_film"]?.boolValue != true
                let developmentAssets = shouldDevelop ? try? await engine.developmentAssets(print: working, geometry: photo.geometry,
                    framed: MobileFilmGate.presents(photo.recipe), scanStyle: result.resolved["digital_intermediate"]?.boolValue == true) : nil
                guard !Task.isCancelled, generation == revision, active else { return }
                developmentOffered = true
                image = display; original = displayOriginal; cropSourceImage = cropDisplay
                development = developmentAssets; developmentRunning = false
                if !nativeCanvasSizeIsExact, !MobileFilmGate.presents(photo.recipe) {
                    nativeCanvasSize = photo.geometry.outputSize(for: geometrySourceSize)
                } else if nativeCanvasSize == .zero {
                    let nativeScale = sqrt(photo.sourceMegapixels / max(0.001, min(photo.sourceMegapixels, targetMP)))
                    nativeCanvasSize = CGSize(width: Double(working.width) * nativeScale, height: Double(working.height) * nativeScale)
                }
                lastFinalRequestedEdge = targetEdge
                lastFinalSourceMP = targetMP
                lastCompletedPreviewRevision = generation
                resolved = result.resolved
                pendingDefaultValues = [:]
                latitude = result.latitude
                busy = false
                previewStatus = ""
                if let importID, operation?.id == importID {
                    let count = operation?.total ?? 0
                    finishImport(id: importID)
                    if notification == nil { postNotification("已导入 \(count) 张照片", style: .success) }
                }
                reconcileDetail()
            } catch is CancellationError { }
            catch {
                guard generation == revision else { return }
                self.error = error.localizedDescription; busy = false
                finishImport(id: importID)
            }
        }
    }
    func releaseMemory() {
        let originalDemand = originalViewport
        let baseIsCurrent = image != nil && lastCompletedPreviewRevision == revision && interactionStart == nil
        let now = ProcessInfo.processInfo.systemUptime
        memoryWarningBurst = now - lastMemoryWarning < 12 ? min(5, memoryWarningBurst + 1) : 0
        lastMemoryWarning = now
        let retryDelay = min(6, 0.35 * pow(2, Double(memoryWarningBurst)))
        detailRetryAfter = now + retryDelay
        memoryRecoveryTask?.cancel()
        finishDevelopment()
        endParameterInteraction()
        cancelDetail()
        if isImporting {
            renderTask?.cancel(); engine.workGate.cancel(); busy = true
            let id = operation?.id
            let close = queuePreviewClose()
            Task {
                await close.value
                if active, isImporting, operation?.id == id, operation?.stage == .preview { scheduleRender(importID: id) }
            }
            return
        }
        if delivering {
            // A memory warning trims preview resources; it must not cancel the
            // separately budgeted user export or change its generation.
            original = nil; previewAfterExport = true
            engine.workGate.cancel()
            queuePreviewClose()
            return
        }
        revision += 1; renderTask?.cancel(); busy = false
        if baseIsCurrent { lastCompletedPreviewRevision = revision }
        engine.workGate.cancel()
        let close = queuePreviewClose()
        let generation = revision
        memoryRecoveryTask = Task {
            await close.value
            do { try await Task.sleep(for: .seconds(retryDelay)) } catch { return }
            guard active, revision == generation, !busy, !detailBusy, !isInteractionLocked, current != nil else { return }
            if baseIsCurrent {
                if showOriginal, let demand = originalViewport ?? originalDemand { requestOriginalDetail(demand) }
                else { reconcileDetail() }
            } else { schedule() }
        }
    }
    func setActive(_ active: Bool, background: Bool = true) {
        if !active { finishDevelopment() }
        if !active { showOriginal = false }
        if !active { endParameterInteraction(); cancelDetail() }
        detailRenderer.engine.workGate.setActive(active)
        self.active = active
        engine.workGate.setActive(active)
        if !active && background {
            exportInterruptedByBackground = true
            exportEngine.workGate.setActive(false)
        } else if active && !delivering { exportEngine.workGate.setActive(true) }
        if active {
            if isImporting {
                if operation?.stage == .preview { scheduleRender(importID: operation?.id) }
            } else { schedule() }
        }
        else {
            renderTask?.cancel()
            if !delivering { revision += 1; busy = isImporting }
            queuePreviewClose()
        }
    }
    func export(_ format: MobileExportFormat, destination: MobileExportDestination = .share, ids: [UUID]? = nil) {
        guard active, !isInteractionLocked, !busy, !delivering, current != nil else { return }
        finishDevelopment()
        showOriginal = false
        cancelDetail()
        let detailCleanup = detailCleanupTask
        let previewCleanup = previewCleanupTask
        let targets = ids.map { selected in photos.filter { selected.contains($0.id) } } ?? current.map { [$0] } ?? []
        guard !targets.isEmpty else { return }
        var options = exportRecipe; options.format = format
        if destination == .photos && format == .di { error = "数字中间片请导出到文件，不能作为成片存入照片图库。"; return }
        busy = true; delivering = true; notice = nil; error = nil
        operation = MobileOperationProgress(kind: .exporting, stage: .preparing, total: targets.count)
        let operationID = operation!.id
        let previewEdgeForAudit = image.map { max($0.width, $0.height) } ?? lastFinalRequestedEdge
        renderTask?.cancel(); renderTask = nil; engine.workGate.cancel()
        // Keep a lightweight view while a full-resolution user export owns the
        // budget. Release both large before/after images before entering it.
        if let shown = image, max(shown.width, shown.height) > 1280 {
            image = autoreleasepool {
                let scale = 1280 / Double(max(shown.width, shown.height))
                let small = CIImage(cgImage: shown).transformed(by: .init(scaleX: scale, y: scale))
                return CIContext(options: [.cacheIntermediates: false]).createCGImage(small, from: small.extent.integral, format: .RGBA8, colorSpace: shown.colorSpace)
            }
        }
        original = nil; cropSourceImage = nil; neutralPreview = nil; previewAfterExport = true
        exportInterruptedByBackground = false
        exportEngine.workGate.setActive(true)
        let generation = revision
        let folder = exportFolder
        MobileExportJournal.shared.begin(options: options, count: targets.count, previewEdge: previewEdgeForAudit,
                                         destination: destination == .photos ? "photos" : folder == nil ? "share" : "folder")
        let exportSampler = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                MobileExportJournal.shared.sample()
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
        }
        let wasIdleDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        Task {
            defer { UIApplication.shared.isIdleTimerDisabled = wasIdleDisabled; exportSampler.cancel() }
            var staged: [URL] = []
            var folders: Set<URL> = []
            var delivered = 0, skipped = 0
            let shareDirectory = URL.temporaryDirectory.appendingPathComponent("Export-Share-" + UUID().uuidString, isDirectory: true)
            let scoped = folder?.startAccessingSecurityScopedResource() ?? false
            defer { if scoped { folder?.stopAccessingSecurityScopedResource() } }
            do {
                if destination == .photos { try await PhotoLibraryWriter.authorize() }
                await detailCleanup?.value
                await previewCleanup?.value
                await detailRenderer.clear()
                await engine.close() // preview cache never competes with export
                for (index, photo) in targets.enumerated() {
                    try Task.checkCancellation()
                    guard !exportInterruptedByBackground else { throw CancellationError() }
                    MobileExportJournal.shared.record("photo.begin", detail: ["index": index + 1, "name": photo.name,
                        "recipe": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(photo.recipe))) ?? [:]])
                    operation?.index = index + 1; operation?.filename = photo.name; operation?.stage = .preparing
                    let fileIndex = index + 1
                    await exportEngine.setProgressHandler { [weak self] phase in
                        Task { @MainActor [weak self] in
                            guard let self, self.operation?.id == operationID, self.operation?.index == fileIndex,
                                  let stage = MobileOperationProgress.exportStage(phase),
                                  stage.outputOrder >= (self.operation?.stage.outputOrder ?? 0) else { return }
                            self.operation?.stage = stage
                        }
                    }
                    exportStatus = "正在导出 \(index + 1) / \(targets.count) · \(photo.name)"
                    var recipe = photo.recipe
                    recipe["_diBlue"] = .bool(preferences.values.diBlueCompensation)
                    recipe["_cropRecalc"] = .bool(preferences.values.cropRemapsEffects)
                    let film = recipe["film_stock"]?.stringValue ?? MobileProcessContract.defaults["film_stock"]?.stringValue ?? "film"
                    let paper = recipe["print_stock"]?.stringValue ?? MobileProcessContract.defaults["print_stock"]?.stringValue ?? "paper"
                    let stem = options.stem(original: photo.name, film: film, paper: paper, counter: index + 1)
                    let files = try await exportEngine.exportFiles(url: url(for: photo), recipe: recipe, geometry: photo.geometry, options: options, stem: stem)
                    files.forEach { folders.insert($0.deletingLastPathComponent()) }
                    if destination == .photos {
                        operation?.stage = .photos
                        MobileExportJournal.shared.record("photos.begin")
                        try await PhotoLibraryWriter.save(files[0]); delivered += 1
                        MobileExportJournal.shared.record("photos.saved")
                        try? FileManager.default.removeItem(at: files[0].deletingLastPathComponent())
                    } else if let folder {
                        var wrotePhoto = false
                        for file in files {
                            var target = folder.appendingPathComponent(file.lastPathComponent)
                            if FileManager.default.fileExists(atPath: target.path) {
                                if options.existing == "skip" || file.pathExtension == "cube" { skipped += 1; continue }
                                if options.existing == "overwrite" {
                                    let partial = folder.appendingPathComponent("." + UUID().uuidString + ".partial")
                                    try FileManager.default.copyItem(at: file, to: partial)
                                    _ = try FileManager.default.replaceItemAt(target, withItemAt: partial)
                                    if file == files[0] { wrotePhoto = true }
                                    continue
                                }
                                var counter = 1
                                while FileManager.default.fileExists(atPath: target.path) {
                                    target = folder.appendingPathComponent(file.deletingPathExtension().lastPathComponent + "-\(counter)").appendingPathExtension(file.pathExtension)
                                    counter += 1
                                }
                            }
                            try FileManager.default.copyItem(at: file, to: target)
                            if file == files[0] { wrotePhoto = true }
                        }
                        if wrotePhoto { delivered += 1 }
                        try? FileManager.default.removeItem(at: files[0].deletingLastPathComponent())
                    } else {
                        try FileManager.default.createDirectory(at: shareDirectory, withIntermediateDirectories: true)
                        folders.insert(shareDirectory)
                        for file in files {
                            var target = shareDirectory.appendingPathComponent(file.lastPathComponent)
                            if file.pathExtension == "cube", FileManager.default.fileExists(atPath: target.path) { continue }
                            var counter = 1
                            while FileManager.default.fileExists(atPath: target.path) {
                                target = shareDirectory.appendingPathComponent(file.deletingPathExtension().lastPathComponent + "-\(counter)").appendingPathExtension(file.pathExtension)
                                counter += 1
                            }
                            try FileManager.default.moveItem(at: file, to: target); staged.append(target)
                        }
                        try? FileManager.default.removeItem(at: files[0].deletingLastPathComponent())
                        delivered += 1
                    }
                }
                if !staged.isEmpty { exportedFiles = staged; exported = staged.first }
                notice = "已导出 \(delivered) 张" + (skipped > 0 ? "，跳过 \(skipped) 个已有文件" : "")
                exportStatus = notice ?? ""
                MobileExportJournal.shared.finish()
            } catch {
                for folder in folders { try? FileManager.default.removeItem(at: folder) }
                MobileExportJournal.shared.finish(error: error.localizedDescription)
                self.error = error is CancellationError ? "导出因应用进入后台而停止，请保持应用在前台后重试。" : error.localizedDescription
                exportStatus = "导出未全部完成 · 已处理 \(delivered) / \(targets.count)"
            }
            await exportEngine.setProgressHandler(nil)
            await exportEngine.close()
            if operation?.id == operationID { operation = nil }
            delivering = false
            if generation == revision { busy = false }
            if active && previewAfterExport {
                previewAfterExport = false
                schedule()
            }
        }
    }

    func clearExport() {
        for folder in Set(exportedFiles.map { $0.deletingLastPathComponent() }) { try? FileManager.default.removeItem(at: folder) }
        if let exported, exportedFiles.isEmpty { try? FileManager.default.removeItem(at: exported) }
        exported = nil; exportedFiles = []
    }
}
