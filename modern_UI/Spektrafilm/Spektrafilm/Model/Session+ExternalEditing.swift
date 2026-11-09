import AppKit
import ImageIO
import CoreServices

enum LightroomInput {
    static func isLightroom(_ bundleID: String?) -> Bool {
        guard let id = bundleID?.lowercased() else { return false }
        return id.hasPrefix("com.adobe.lightroom")
    }

    @MainActor static func currentSenderIsLightroom() -> Bool {
        guard let pid = NSAppleEventManager.shared().currentAppleEvent?
            .attributeDescriptor(forKeyword: keySenderPIDAttr)?.int32Value else { return false }
        return isLightroom(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier)
    }
    static func retain(_ source: URL) throws -> URL {
        let backup = source.deletingLastPathComponent()
            .appendingPathComponent(".\(source.lastPathComponent).silverphase-input.\(source.pathExtension)")
        if !FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.copyItem(at: source, to: backup)
        }
        return backup
    }
}

extension Session {
    var isLightroomEditing: Bool { lightroomDestination != nil }

    func openFromLightroom(_ urls: [URL]) {
        guard !batchExporting else { return }
        guard urls.count == 1, let source = urls.first,
              ["tif", "tiff", "jpg", "jpeg"].contains(source.pathExtension.lowercased()) else {
            status = "Lightroom: send one TIFF or JPEG at a time."
            return
        }
        do {
            let input = try LightroomInput.retain(source)
            lightroomDestination = source
            lightroomInput = input
            open(urls: [input])
            showExport = false
            rightCollapsed = false
            status = "Lightroom · \(source.lastPathComponent)"
        } catch { status = "Could not open Lightroom input: \(error.localizedDescription)" }
    }

    var canSaveToLightroom: Bool {
        lightroomDestination != nil && selection == lightroomInput &&
        serviceSessionIDForExport != nil && !batchExporting && !busy
    }

    func saveAndReturnToLightroom() async -> Bool {
        guard canSaveToLightroom, let destination = lightroomDestination,
              let sid = serviceSessionIDForExport else { return false }
        batchExporting = true
        beginBatchExport()
        defer { batchExporting = false; endBatchExport() }
        do {
            var recipe = ExportRecipe()
            recipe.format = ["jpg", "jpeg"].contains(destination.pathExtension.lowercased()) ? .jpeg : .tiff
            recipe.colorSpace = .builtIn(CGColorSpace.rommrgb as String)
            let rendered = try await Exporter.filePixels(session: self, recipe: recipe, sessionID: sid)
            let metadata = lightroomInput.flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) }
                .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
            try await Exporter.writeFinishedTexture(rendered.texture, scratch: rendered.scratch,
                space: rendered.target, to: destination, format: recipe.format, sourceMetadata: metadata)
            status = "Saved to Lightroom: \(destination.lastPathComponent)"
            flushSave()
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.adobe.LightroomClassicCC7") {
                _ = try? await NSWorkspace.shared.openApplication(at: app, configuration: .init())
            }
            return true
        } catch {
            status = "Lightroom save failed: \(error.localizedDescription)"
            noteFailure(error, operation: "Lightroom return", frame: destination.lastPathComponent)
            return false
        }
    }
}
