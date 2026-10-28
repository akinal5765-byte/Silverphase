import CoreImage
import Foundation
import Metal

/// Framing precedes exposure when the gate and the date back are present.
enum FilmCanvasInput {
    nonisolated static func engineImage(_ linear: CIImage, size: CGSize, cut: Geometry?) -> CIImage {
        guard let g = cut, !g.isIdentity, size.width > 0, size.height > 0 else { return linear }
        let out = g.outputSize(for: size)
        let flipOut = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: out.height)
        let flipSource = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
        let mapping = flipOut.concatenating(g.outputToSourceTransform(imageSize: size)).concatenating(flipSource)
        let placed = linear.transformed(by: .init(translationX: -linear.extent.minX, y: -linear.extent.minY))
        return placed.clampedToExtent().transformed(by: mapping.inverted()).cropped(to: CGRect(origin: .zero, size: out))
    }

    static func image(_ decoded: DecodedImage, params: FilmParams, geometry: Geometry) -> CIImage {
        guard params.filmPresentationActive else { return decoded.linear }
        let framed = engineImage(decoded.linear, size: decoded.pixelSize, cut: geometry)
        guard params.filmEdge.effective else { return framed }
        let gate = params.filmEdge.gateMM
        let size = framed.extent.size
        let aspect = size.width >= size.height ? gate.long / gate.short : gate.short / gate.long
        let w = min(size.width, size.height * aspect)
        let h = w / aspect
        let rect = CGRect(x: framed.extent.midX - w / 2, y: framed.extent.midY - h / 2, width: w, height: h)
        return framed.cropped(to: rect).transformed(by: .init(translationX: -rect.minX, y: -rect.minY))
    }
}

extension FilmCanvasInput {
    static func exposePair(_ decoded: DecodedImage, pair: HalfFramePair, params: FilmParams,
                           device: MTLDevice) async throws -> (image: CIImage, first: SceneLatitudeSettings?, second: SceneLatitudeSettings?) {
        let across = Int(pair.turned ? decoded.pixelSize.width : decoded.pixelSize.height)
        let layout = HalfFramePair.layout(holeHeight: across, spacingMM: pair.effectiveSpacingMM, turned: pair.turned)
        let meter = EngineClient(device: device)
        var stops: [HalfFramePair.Side: Double] = [:]
        var curves: [HalfFramePair.Side: SceneLatitudeSettings] = [:]
        do {
        for side in HalfFramePair.Side.allCases {
            guard let hole = pair[side], hole.exists else { continue }
            var ev = hole.exposureEV
            do {
                let picture = PairComposer.meterImage(decoded.linear, layout: layout, side: side)
                let frame = try ImageDecoder.engineFrame(from: picture, device: device)
                var fields = params.fullDelta
                fields["overscan_active"] = .bool(false)
                fields["date_imprint_active"] = .bool(false)
                fields["overscan_pair"] = .bool(false)
                fields["auto_exposure"] = .bool(false)
                fields["exposure_compensation_ev"] = .double(0)
                fields["scene_latitude_active"] = .bool(false)
                fields["scene_latitude_b_active"] = .bool(false)
                fields["scene_latitude_split"] = .double(0)
                fields["auto_exposure_method"] = .string(hole.meterMethod ?? params.autoExposureMethod ?? "balanced")
                let response = try await meter.open(frame, paramsDelta: fields)
                let solved = try await meter.call(.solve, SolveRequest(sessionID: response.sessionID, target: "exposure"), as: SolveResponse.self)
                if hole.autoExposure { ev += solved.solvedParams["exposure_compensation_ev"] ?? 0 }
                var curve = hole.sceneLatitude
                if curve.active {
                    // Fit each hole on its exposed scene before composing the strip.
                    _ = try await meter.call(.setParams, SetParamsRequest(sessionID: response.sessionID, paramsDelta: ["auto_exposure": .bool(false), "exposure_compensation_ev": .double(ev)]), as: SetParamsResponse.self)
                    let fit = try await meter.sceneLatitude(curve.request)
                    _ = curve.apply(fit.fit)
                }
                curves[side] = curve
            }
            stops[side] = ev
        }
        } catch {
            await meter.stop()
            throw error
        }
        await meter.stop()
        return (PairComposer.exposed(decoded.linear, layout: layout, stops: stops), curves[.left], curves[.right])
    }
}
