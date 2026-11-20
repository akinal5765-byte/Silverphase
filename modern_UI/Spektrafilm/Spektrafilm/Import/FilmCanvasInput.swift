import CoreImage
import Foundation
import Metal

/// Framing precedes exposure when the gate and the date back are present.
enum FilmCanvasInput {
    static let imageEdgeRange = 16...16_384
    static let imagePixelLimit = 96_000_000

    enum SizeError: LocalizedError {
        case limits

        var errorDescription: String? {
            "The requested size and crop exceed the film frame's pixel limit."
        }
    }

    /// The full input grows with a tighter crop, retaining the physical film
    /// frame and the location of the crop within it.
    nonisolated static func workingSize(source: CGSize, crop: CGSize, longEdge: Int) throws -> CGSize {
        let scale = CGFloat(longEdge) / max(crop.width, crop.height)
        let width = max(1, (source.width * scale).rounded())
        let height = max(1, (source.height * scale).rounded())
        guard imageEdgeRange.contains(longEdge), scale.isFinite, scale > 0,
              source.width.isFinite, source.height.isFinite, source.width > 0, source.height > 0,
              width <= CGFloat(imageEdgeRange.upperBound), height <= CGFloat(imageEdgeRange.upperBound),
              width * height <= CGFloat(imagePixelLimit) else { throw SizeError.limits }
        return CGSize(width: width, height: height)
    }

    nonisolated static func pictureSize(_ source: CGSize, params: FilmParams, geometry: Geometry) -> CGSize {
        if !params.filmPresentationActive {
            // The final crop is rounded on the resized frame. Rounding the
            // source crop too would miss the target on small crops.
            let width = source.width * geometry.crop.width
            let height = source.height * geometry.crop.height
            return geometry.quarterTurns % 2 == 0 ? CGSize(width: width, height: height)
                                                   : CGSize(width: height, height: width)
        }
        let cropped = geometry.outputSize(for: source)
        return params.filmEdge.effective ? gateSize(cropped, params: params) : cropped
    }

    nonisolated private static func gateSize(_ size: CGSize, params: FilmParams) -> CGSize {
        let gate = params.filmEdge.gateMM
        let aspect = size.width >= size.height ? gate.long / gate.short : gate.short / gate.long
        let width = min(size.width, size.height * aspect)
        return CGSize(width: width, height: width / aspect)
    }

    nonisolated static func resize(_ input: CIImage, to size: CGSize) -> CIImage {
        let extent = input.extent
        guard extent.size != size else { return input }
        let placed = input.transformed(by: .init(translationX: -extent.minX, y: -extent.minY))
        let scale = size.height / extent.height
        return placed.clampedToExtent().applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: scale,
            kCIInputAspectRatioKey: (size.width / extent.width) / scale
        ]).cropped(to: CGRect(origin: .zero, size: size))
    }

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
        let size = gateSize(framed.extent.size, params: params)
        let rect = CGRect(x: framed.extent.midX - size.width / 2,
                          y: framed.extent.midY - size.height / 2, width: size.width, height: size.height)
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

/// Fits a single exposure through the selected look against the camera's embedded preview.
enum CameraBrightnessMatch {
    typealias Failure = CameraBrightnessFit.Failure
    typealias Fit = CameraBrightnessFit.Fit
    typealias Sample = CameraBrightnessFit.Sample

    nonisolated static func fit(_ reference: Sample, trial: (Double) async throws -> Sample) async throws -> Fit {
        try await CameraBrightnessFit.fit(reference, trial: trial)
    }

    nonisolated static func renderInputs(for params: FilmParams) -> [String: ParamValue] {
        var neutral = params
        neutral.cameraTone = CameraTone()
        neutral.printBrightnessStops = 0
        var delta = neutral.fullDelta.filter { !$0.key.hasPrefix("grain_")
            && !$0.key.hasPrefix("glare_") && !$0.key.hasPrefix("overscan_")
            && !$0.key.hasPrefix("date_imprint_") }
        delta["overscan_active"] = .bool(false)
        delta["date_imprint_active"] = .bool(false)
        delta["grain_active"] = .bool(false)
        delta["glare_active"] = .bool(false)
        delta["extended_dynamic_range"] = .bool(false)
        delta["output_color_space"] = .string("sRGB")
        delta["output_cctf_encoding"] = .bool(true)
        delta["product_defaults"] = .bool(true)
        delta["preview_long_edge"] = .double(800)
        return delta
    }

    nonisolated static func exposure(for decoded: DecodedImage, params: [String: ParamValue],
                                     device: MTLDevice) async throws -> Fit {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw Failure.render }
        let reference = try CameraBrightnessFit.reference(at: decoded.sourceURL,
            aspect: decoded.pixelSize.width / max(1, decoded.pixelSize.height), space: space)
        let frame = try ImageDecoder.engineFrame(from: decoded.linear, device: device, maxEdge: CameraBrightnessFit.edge)
        let client = EngineClient(device: device)
        let result: Fit
        do {
            let open = try await client.open(frame, paramsDelta: params)
            result = try await fit(reference) { ev in
                let outcome = try await client.render(.previewRender, RenderRequest(
                    sessionID: open.sessionID, paramsDelta: ["camera_prep_exposure_ev": .double(ev)], tier: "live"
                ))
                guard let image = outcome.texture?.makeCGImage(space: space) else { throw Failure.render }
                return try Sample(image, space: space)
            }
        } catch {
            await client.stop()
            throw error
        }
        await client.stop()
        return result
    }
}
