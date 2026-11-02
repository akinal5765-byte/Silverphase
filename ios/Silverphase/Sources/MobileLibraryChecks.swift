#if DEBUG
import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

@MainActor enum MobileLibraryChecks {
    static func neutralPickerLifecycle() {
        let report = URL.documentsDirectory.appendingPathComponent("neutral-close-report.json")
        let directory = URL.temporaryDirectory.appendingPathComponent("Neutral-Close-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var checks: [String] = []
        do {
            func require(_ condition: Bool, _ label: String) throws {
                guard condition else { throw MobileFailure.message(label) }; checks.append(label)
            }
            let document = MobileDocument(directory: directory); document.active = false
            let photo = MobilePhoto(name: "Neutral lifecycle", filename: "neutral.tif")
            document.photos = [photo]; document.openEditor(photo.id)
            let input = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
            guard let sampling = CIContext().createCGImage(input, from: input.extent) else { throw MobileFailure.message("sampling fixture unavailable") }
            document.pickingNeutral = true; document.neutralPreview = sampling
            document.closeEditor()
            try require(!document.pickingNeutral && document.neutralPreview == nil, "closing clears neutral picking and sampling preview")
            try require(!document.editorVisible && document.selection == photo.id, "closing preserves the selected library photo")
            document.openEditor(photo.id)
            try require(document.editorVisible && document.selection == photo.id && !document.pickingNeutral && document.neutralPreview == nil, "same-photo reopening cannot resume neutral picking")
            let rendered = CIContext().createCGImage(input, from: input.extent)!
            document.image = rendered
            try require((document.neutralPreview ?? document.image) === rendered, "reopened canvas resolves the rendered image")
            let recipe = document.current?.recipe
            document.pickNeutral(CGPoint(x: 0.5, y: 0.5))
            try require(document.current?.recipe == recipe && !document.pickingNeutral, "canvas taps after reopening do not sample white balance")
            document.closeEditor(); document.openEditor(photo.id)
            try require(!document.pickingNeutral && document.neutralPreview == nil, "repeated close and reopen stays out of sampling mode")
            try JSONSerialization.data(withJSONObject: ["passed": true, "checks": checks], options: [.prettyPrinted, .sortedKeys]).write(to: report, options: .atomic)
        } catch {
            try? JSONSerialization.data(withJSONObject: ["passed": false, "checks": checks, "error": error.localizedDescription], options: [.prettyPrinted, .sortedKeys]).write(to: report, options: .atomic)
        }
    }

    static func run() {
        let directory = URL.temporaryDirectory.appendingPathComponent("Library-Checks-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var checks: [String] = []
        let report = URL.documentsDirectory.appendingPathComponent("library-report.json")
        do {
            func require(_ value: Bool, _ label: String) throws {
                guard value else { throw MobileFailure.message(label) }; checks.append(label)
            }
            let doc = MobileDocument(directory: directory); doc.active = false; doc.editorVisible = false
            var portrait = MobilePhoto(name: "Portrait", filename: "portrait.jpg")
            portrait.sourceAspect = 2.0 / 3; portrait.sourceMegapixels = 12
            portrait.geometry.value.aspect = .r3x4
            portrait.geometry.value = portrait.geometry.value.constrained(in: CGSize(width: 2000, height: 3000))
            portrait.geometry.value.angle = 12; portrait.geometry.value.flipV = true
            var landscape = MobilePhoto(name: "Landscape", filename: "landscape.jpg")
            landscape.sourceAspect = 1.5; landscape.sourceMegapixels = 24
            landscape.geometry.value.crop = CropRect(x: 0.15, y: 0.2, width: 0.5, height: 0.5)
            landscape.geometry.value.angle = -7; landscape.geometry.value.flipH = true
            let original = Data("original bytes".utf8)
            for photo in [portrait, landscape] { try original.write(to: doc.url(for: photo)) }
            doc.photos = [portrait, landscape]; doc.selection = landscape.id
            doc.mark(landscape.id, rating: 4, flag: "pick")
            doc.copySettings(portrait, groups: [.geometry]); doc.pasteSettings(to: [landscape.id])
            let pasted = doc.photos[1].geometry.value
            try require(abs(pasted.crop.width * landscape.sourceAspect / pasted.crop.height - 4.0 / 3) < 1e-8, "portrait 3:4 becomes landscape 4:3")
            try require(pasted.centre == landscape.geometry.value.centre && pasted.angle == -7 && pasted.flipH && !pasted.flipV && pasted.quarterTurns == 0, "ratio paste preserves target centre straighten flips and rotation")
            let loaded = MobileDocument(directory: directory); loaded.active = false; loaded.editorVisible = false
            try require(loaded.photos.count == 2 && loaded.selection == landscape.id && loaded.photos[1].geometry == doc.photos[1].geometry, "cold document restores identity selection and crop")
            try require(loaded.photos[1].rating == 4 && loaded.photos[1].flag == "pick", "ratings and flags survive cold load")
            try require(try Data(contentsOf: loaded.url(for: landscape)) == original, "original bytes survive cold load")
            doc.undo(); try require(doc.photos[1].geometry == landscape.geometry, "ratio paste undo restores target crop")
            doc.redo(); try require(doc.photos[1].geometry.value == pasted, "ratio paste redo restores adapted ratio")
            var turned = landscape; turned.geometry.value.quarterTurns = 1
            let result = MobileSettingsClip(source: portrait, groups: [.geometry]).applied(to: turned)
            let size = result.geometry.outputSize(for: CGSize(width: 6000, height: 4000))
            try require(abs(size.width / size.height - 0.75) < 0.001 && result.geometry.value.quarterTurns == 1, "turned target stays portrait without copying source rotation")
            var free = portrait; free.geometry.value = Geometry(); free.sourceAspect = 0.61
            let custom = MobileSettingsClip(source: free, groups: [.geometry]).applied(to: landscape)
            try require(abs(custom.geometry.value.crop.width * 1.5 / custom.geometry.value.crop.height - 1 / 0.61) < 1e-8, "free and original ratios copy actual numeric proportion")
            let reverse = MobileSettingsClip(source: landscape, groups: [.geometry]).applied(to: portrait)
            try require(abs(reverse.geometry.value.crop.width * portrait.sourceAspect / reverse.geometry.value.crop.height - 2.0 / 3) < 1e-8, "landscape ratio adapts to portrait target")
            var square = landscape; square.geometry.value.aspect = .square
            square.geometry.value = square.geometry.value.constrained(in: CGSize(width: 6000, height: 4000))
            let squarePaste = MobileSettingsClip(source: square, groups: [.geometry]).applied(to: portrait)
            try require(abs(squarePaste.geometry.value.crop.width * portrait.sourceAspect / squarePaste.geometry.value.crop.height - 1) < 1e-8, "square stays square")
            loaded.beginPhotoSelection(portrait.id); loaded.togglePhotoSelection(landscape.id)
            loaded.copySettings(portrait, groups: [.geometry]); loaded.pasteSettings()
            try require(loaded.selectedPhotoIDs.count == 2, "library batch paste retains selection")
            loaded.removePhotos([portrait.id, landscape.id])
            let empty = MobileDocument(directory: directory)
            try require(empty.photos.isEmpty && !FileManager.default.fileExists(atPath: loaded.url(for: landscape).path), "batch delete persists and removes owned originals")
            let scoped = MobileDocument(directory: directory.appendingPathComponent("scoped"))
            scoped.active = false; scoped.photos = [portrait, landscape]
            scoped.openEditor(landscape.id, ids: [landscape.id]); scoped.remove(landscape.id)
            try require(scoped.selection == nil && scoped.photos.map(\.id) == [portrait.id], "deleting last workspace photo never opens an unrelated library photo")
            let manifest = directory.appendingPathComponent("library.json")
            let bad = Data("broken manifest".utf8); try bad.write(to: manifest)
            let broken = MobileDocument(directory: directory)
            try require(broken.error != nil && !broken.save(), "corrupt library fails visibly and refuses overwrite")
            try require(try Data(contentsOf: manifest) == bad, "corrupt manifest is preserved")
            var invalid = landscape; invalid.filename = "../outside.jpg"
            do {
                try MobileLibraryStore(directory: directory).write(.init(photos: [invalid]))
                throw MobileFailure.message("unsafe path was accepted")
            } catch {
                try require(try Data(contentsOf: manifest) == bad, "unsafe relative paths cannot replace manifest")
            }
            try JSONSerialization.data(withJSONObject: ["passed": true, "checks": checks], options: [.prettyPrinted, .sortedKeys]).write(to: report, options: .atomic)
        } catch {
            try? JSONSerialization.data(withJSONObject: ["passed": false, "checks": checks, "error": error.localizedDescription], options: [.prettyPrinted, .sortedKeys]).write(to: report, options: .atomic)
        }
    }
    static func exportBatch() async {
        let directory = URL.temporaryDirectory.appendingPathComponent("Library-Export-Checks-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let report = URL.documentsDirectory.appendingPathComponent("library-export-report.json")
        do {
            let doc = MobileDocument(directory: directory); doc.editorVisible = false
            prepareUI(doc); doc.active = true
            // No editor is open and there is no preview selection. Only IDs
            // chosen in the library may determine the export range.
            doc.selection = nil
            let output = directory.appendingPathComponent("output", isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            doc.exportFolder = output
            let ids = Array(doc.photos.suffix(2).map(\.id))
            doc.export(.jpeg, ids: ids)
            guard doc.delivering else { throw MobileFailure.message("library export did not start without a current photo") }
            while doc.delivering { try await Task.sleep(for: .milliseconds(100)) }
            if let error = doc.error { throw MobileFailure.message(error) }
            guard doc.image == nil else { throw MobileFailure.message("library export unexpectedly prepared an editor preview") }
            let files = try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
            guard files.count == 2 else { throw MobileFailure.message("batch export did not produce exactly two files") }
            for file in files {
                guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width > 0, image.height > 0 else {
                    throw MobileFailure.message("batch output could not be decoded")
                }
            }
            try JSONSerialization.data(withJSONObject: ["passed": true, "count": files.count, "checks": ["selected IDs export without opening editor", "two JPEG files decode", "library preview stays unloaded"]], options: [.prettyPrinted, .sortedKeys]).write(to: report, options: .atomic)
        } catch {
            try? JSONSerialization.data(withJSONObject: ["passed": false, "error": error.localizedDescription], options: [.prettyPrinted, .sortedKeys]).write(to: report, options: .atomic)
        }
    }
    static func prepareUI(_ document: MobileDocument) {
        document.active = false; document.editorVisible = false
        guard document.photos.isEmpty else { return }
        let documentation = ProcessInfo.processInfo.arguments.contains("--documentation-captures")
        let size = documentation ? CGSize(width: 384, height: 576) : CGSize(width: 96, height: 64)
        let input: CIImage
        if documentation {
            input = CIFilter(name: "CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: size.width, y: size.height),
                "inputColor0": CIColor(red: 0.12, green: 0.22, blue: 0.30),
                "inputColor1": CIColor(red: 0.80, green: 0.65, blue: 0.40)
            ])!.outputImage!.cropped(to: CGRect(origin: .zero, size: size))
        } else {
            input = CIImage(color: CIColor(red: 0.75, green: 0.3, blue: 0.1)).cropped(to: CGRect(origin: .zero, size: size))
        }
        guard let image = CIContext().createCGImage(input, from: input.extent) else { return }
        document.photos = ["来源", "目标 A", "目标 B"].enumerated().map { index, name in
            var photo = MobilePhoto(name: name, filename: "fixture-\(index).jpg")
            photo.sourceMegapixels = size.width * size.height / 1_000_000; photo.sourceAspect = size.width / size.height
            photo.recipe["exposure_compensation_ev"] = .double(documentation ? 0 : index == 0 ? 1 : -Double(index))
            if let writer = CGImageDestinationCreateWithURL(document.url(for: photo) as CFURL, UTType.jpeg.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(writer, image, nil); CGImageDestinationFinalize(writer)
            }
            return photo
        }
        document.save()
    }
}
#endif
