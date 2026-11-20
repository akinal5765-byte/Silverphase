import CoreGraphics
import Foundation
import ImageIO

/// The camera-preview exposure fit shared by desktop and mobile.
enum CameraBrightnessFit {
    static let limit = 3.0
    static let edge = 256

    enum Failure: String, Error {
        case reference, midtones, render, range
    }

    struct Fit: Sendable {
        let exposure: Double
        let highlightLimited: Bool
    }

    nonisolated static func reference(at url: URL, aspect: Double, space: CGColorSpace) throws -> Sample {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: edge
              ] as CFDictionary),
              abs(log((Double(preview.width) / Double(preview.height)) / aspect)) < 0.055 else {
            throw Failure.reference
        }
        return try Sample(preview, space: space)
    }

    struct Sample: Sendable {
        let quantiles: [Double]
        let nearWhite: Double

        nonisolated init(_ image: CGImage, space: CGColorSpace) throws {
            let scale = min(1, Double(CameraBrightnessFit.edge) / Double(max(image.width, image.height)))
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

    static func fit(_ reference: Sample, isolation: isolated (any Actor)? = #isolation, trial: (Double) async throws -> Sample) async throws -> Fit {
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

}
