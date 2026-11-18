import CoreImage
import Foundation
import ImageIO
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
    static let limit = 3.0
    static let edge = 256

    enum Failure: Error {
        case reference, midtones, render, range
    }

    struct Fit: Sendable {
        let exposure: Double
        let highlightLimited: Bool
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

    struct Sample: Sendable {
        let quantiles: [Double]
        let nearWhite: Double

        nonisolated init(_ image: CGImage, space: CGColorSpace) throws {
            let scale = min(1, Double(CameraBrightnessMatch.edge) / Double(max(image.width, image.height)))
            let width = max(1, Int(Double(image.width) * scale))
            let height = max(1, Int(Double(image.height) * scale))
            guard let context = CGContext(data: nil, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
                  let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { throw Failure.render }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let mx = width / 10, my = height / 10
            let linear = (0...255).map { i in
                let v = Double(i) / 255
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            var luminance: [Double] = []
            var whiteCount = 0
            luminance.reserveCapacity((width - 2 * mx) * (height - 2 * my))
            for y in my..<(height - my) {
                for x in mx..<(width - mx) {
                    let offset = (y * width + x) * 4
                    let r = Int(bytes[offset]), g = Int(bytes[offset + 1]), b = Int(bytes[offset + 2])
                    luminance.append(0.2126 * linear[r] + 0.7152 * linear[g] + 0.0722 * linear[b])
                    if max(r, g, b) >= 250 { whiteCount += 1 }
                }
            }
            guard luminance.count >= 128 else { throw Failure.reference }
            luminance.sort()
            quantiles = (1...9).map { luminance[$0 * (luminance.count - 1) / 10] }
            nearWhite = Double(whiteCount) / Double(luminance.count)
        }
    }

    nonisolated static func fit(_ reference: Sample, trial: (Double) async throws -> Sample) async throws -> Fit {
        // The target determines which ranks count. A dark scene never gets
        // pushed to a generic middle grey.
        let usable = reference.quantiles.indices.filter { (0.020...0.692).contains(reference.quantiles[$0]) }
        guard usable.count >= 3 else { throw Failure.midtones }
        func error(_ sample: Sample) -> Double {
            let differences = usable.map { index in
                log2(max(1e-6, sample.quantiles[index]) / reference.quantiles[index])
            }.sorted()
            return differences[differences.count / 2]
        }

        let baseline = try await trial(0)
        let initialError = error(baseline)
        if abs(initialError) < 0.025 { return Fit(exposure: 0, highlightLimited: false) }
        let budget = max(baseline.nearWhite, reference.nearWhite) + 0.01
        let boundary = initialError < 0 ? limit : -limit
        let endpoint = try await trial(boundary)
        let endpointError = error(endpoint)
        if (initialError < 0) == (endpointError < 0) && abs(endpointError) > 0.05 &&
            (boundary < 0 || endpoint.nearWhite <= budget) { throw Failure.range }

        var low = min(0, boundary)
        var high = max(0, boundary)
        var best = 0.0
        var bestError = abs(initialError)
        var limited = boundary > 0 && endpoint.nearWhite > budget
        for _ in 0..<9 {
            try Task.checkCancellation()
            let candidate = (low + high) / 2
            let sample = try await trial(candidate)
            let residual = error(sample)
            let protected = candidate <= 0 || sample.nearWhite <= budget
            limited = limited || !protected
            if protected && abs(residual) < bestError {
                best = candidate
                bestError = abs(residual)
            }
            if protected && abs(residual) < 0.025 { break }
            if !protected || residual > 0 { high = candidate } else { low = candidate }
        }
        return Fit(exposure: best, highlightLimited: limited && bestError >= 0.025)
    }

    nonisolated static func exposure(for decoded: DecodedImage, params: [String: ParamValue],
                                     device: MTLDevice) async throws -> Fit {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let source = CGImageSourceCreateWithURL(decoded.sourceURL as CFURL, nil),
              let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: edge
              ] as CFDictionary) else { throw Failure.reference }
        let referenceAspect = Double(preview.width) / Double(preview.height)
        let sourceAspect = decoded.pixelSize.width / max(1, decoded.pixelSize.height)
        guard abs(log(referenceAspect / sourceAspect)) < 0.055 else { throw Failure.reference }
        let reference = try Sample(preview, space: space)
        let frame = try ImageDecoder.engineFrame(from: decoded.linear, device: device, maxEdge: edge)
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
