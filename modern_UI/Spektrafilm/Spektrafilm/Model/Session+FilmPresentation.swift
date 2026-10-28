import AppKit
import Metal

extension Session {

    nonisolated static func edgeText(for stock: Stock?, gauge: String = "135") -> String {
        guard let stock else { return "" }
        let own: [String: (String, String)] = [   // (135, 120)
            "kodak_gold_200": ("KODAK GB 200-7", "KODAK 200"),
            "kodak_portra_800": ("KODAK PORTRA 800-3", "KODAK PORTRA 800"),
            "kodak_portra_800_push1": ("KODAK PORTRA 800-3", "KODAK PORTRA 800"),
            "kodak_portra_800_push2": ("KODAK PORTRA 800-3", "KODAK PORTRA 800"),
            "kodak_ultramax_400": ("KODAK GC 400", "KODAK GC 400"),
            "kodak_ektachrome_100": ("KODAK E100", "KODAK E100"),
            "fujifilm_c200": ("FUJI 200", "FUJI 200"),
            "fujifilm_xtra_400": ("S-400", "FUJI S-400"),
            "fujifilm_pro_400h": ("PRO400H", "FUJI PRO400H"),
            "fujifilm_provia_100f": ("FUJI RDPIII", "FUJI RDPIII"),
            "fujifilm_velvia_100": ("RVP100", "FUJI RVP100"),
            "kodak_vision3_50d": ("EASTMAN 5203", "EASTMAN 5203"),
            "kodak_vision3_250d": ("EASTMAN 5207", "EASTMAN 5207"),
            "kodak_vision3_200t": ("EASTMAN 5213", "EASTMAN 5213"),
            "kodak_vision3_500t": ("EASTMAN 5219", "EASTMAN 5219"),
            // black and white, off the strips in research/B&W_Research/film (2026-10-09)
            "kodak_tri_x_400": ("KODAK 400TX", "KODAK 400TX"),
            "kodak_tmax_100": ("KODAK 100TMX", "KODAK 100TMX"),
            "fujifilm_neopan_acros_100_ii": ("FUJI 100 ACROS II", "FUJI 100 ACROS II"),
            "ilford_hp5_plus_400": ("ILFORD HP5 PLUS", "ILFORD HP5 PLUS"),
        ]
        if let t = own[stock.id] { return gauge == "120" ? t.1 : t.0 }
        var name = stock.name
        if let open = name.firstIndex(of: "(") { name = String(name[..<open]) }
        return name.trimmingCharacters(in: .whitespaces).uppercased()
    }


    func resolveFilmPresentation(_ p: inout FilmParams) {
        guard p.filmPresentationActive || halfFramePair != nil else { return }
        p.filmEdge.edgeText = Self.edgeText(for: StockCatalog.shared.stock(p.filmStock), gauge: p.filmEdge.format.gauge)
        let data = ShootingData(exif: decoded?.sourceEXIF)
        p.filmEdge.fNumber = data.fNumber ?? 0
        p.dateBack.text = p.dateBack.face == .data ? data.dataText : data.dateText(order: p.dateBack.order)
        p.dateBack.camera = p.filmEdge.format
        p.dateBack.framing = geometry.isIdentity ? "" : (try? JSONEncoder().encode(geometry).base64EncodedString()) ?? ""
        if let d = decoded {
            let crop = geometry.outputSize(for: d.pixelSize)
            p.dateBack.frameScale = max(crop.width, crop.height) / max(d.pixelSize.width, d.pixelSize.height)
        }
        p.dateBack.dataText = data.dataText
        p.filmEdge.framing = (try? JSONEncoder().encode(geometry).base64EncodedString()) ?? ""
        if !p.filmEdge.seeded {
            p.filmEdge.cameraSeed = FilmEdgeSettings.bodySeed(in: .standard)
            p.filmEdge.frameSeed = Int.random(in: 1...999999)
            p.filmEdge.seeded = true
        }
        if let pair = halfFramePair {
            p.filmEdge.pair = true; p.filmEdge.format = .f135Half; p.autoExposure = false
            p.pairSceneLatitudeSplit = (18 + pair.effectiveSpacingMM) / (36 + pair.effectiveSpacingMM)
            p.dateBack.textB = ""
            if let right = pair.right {
                let dataB = ShootingData(exif: ImageDecoder.sourceEXIF(from: right.url))
                p.dateBack.textB = p.dateBack.face == .data ? dataB.dataText : dataB.dateText(order: p.dateBack.order)
            }
        } else { p.filmEdge.pair = false; p.dateBack.textB = "" }
    }

    func filmCanvasLogicalSize(_ texture: MTLTexture) -> CGSize? {
        guard params.filmPresentationActive else { return decoded?.pixelSize ?? displaySourceSize }
        guard let source = decoded?.pixelSize ?? displaySourceSize else { return nil }
        var picture = geometry.outputSize(for: source)
        if params.filmEdge.effective {
            let gate = params.filmEdge.gateMM
            let aspect = picture.width >= picture.height ? gate.long / gate.short : gate.short / gate.long
            picture.width = min(picture.width, picture.height * aspect)
            picture.height = picture.width / aspect
        }
        let long = max(picture.width, picture.height)
        let k = max(1, long / CGFloat(previewLongEdge))
        return CGSize(width: CGFloat(texture.width) * k, height: CGFloat(texture.height) * k)
    }

    func createHalfFramePair() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.image, .rawImage]
        panel.message = T("Choose two photographs for a half-frame pair.", "选择两张照片组成半格双联画。")
        guard panel.runModal() == .OK, panel.urls.count == 2 else { return }
        let save = NSSavePanel()
        save.nameFieldStringValue = "Pair." + HalfFramePair.fileExtension
        guard save.runModal() == .OK, let chosen = save.url else { return }
        let url = chosen.pathExtension == HalfFramePair.fileExtension ? chosen : chosen.appendingPathExtension(HalfFramePair.fileExtension)
        do {
            var pair = HalfFramePair(folder: panel.urls[0].deletingLastPathComponent().path)
            for (side, source) in zip(HalfFramePair.Side.allCases, panel.urls) {
                var hole = HalfFramePair.Hole(url: source)
                let saved = Sidecar.load(for: source) ?? Sidecar()
                hole.decode = saved.decode; hole.geometry = saved.geometry; hole.sceneLatitude = saved.params.sceneLatitude
                hole.autoExposure = saved.params.autoExposure; hole.meterMethod = saved.params.autoExposureMethod
                pair[side] = hole
            }
            pair.onStrip = true
            try pair.save(to: url)
            var saved = Sidecar()
            saved.params = params
            saved.params.filmEdge.active = true; saved.params.filmEdge.format = .f135Half; saved.params.filmEdge.pair = true
            saved.params.autoExposure = false
            try saved.save(for: url)
            open(urls: [url])
            selectInspectorStage(.filmEdge)
        } catch { status = error.localizedDescription }
    }

    func updateHalfFramePair(_ change: (inout HalfFramePair) -> Void) {
        guard let url = selection, var pair = halfFramePair else { return }
        pushUndo()
        change(&pair)
        do { try pair.save(to: url); halfFramePair = pair; reloadFilmPresentation() }
        catch { status = error.localizedDescription }
    }
}

extension Session {
    func replacePairHole(_ side: HalfFramePair.Side) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .rawImage]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var hole = HalfFramePair.Hole(url: url)
        let saved = Sidecar.load(for: url) ?? Sidecar()
        hole.decode = saved.decode; hole.geometry = saved.geometry; hole.sceneLatitude = saved.params.sceneLatitude
        hole.autoExposure = saved.params.autoExposure; hole.meterMethod = saved.params.autoExposureMethod
        updateHalfFramePair { $0[side] = hole }
    }
}
