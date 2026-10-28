import Foundation
import ImageIO

struct ShootingData: Equatable, Sendable {
    struct Day: Equatable, Sendable { var year: Int, month: Int, day: Int }

    /// `DateTimeOriginal`: when the shutter fired.
    var captureDay: Day?
    var exposureTime: Double?
    var fNumber: Double?
    /// `ExposureProgram`: 1 manual, 2 program, 3 aperture priority, 4 shutter
    /// priority. The scene programs (5–8) have no letter on a data back.
    var program: Int?
    /// `ExposureBiasValue`: the camera's own compensation (answer E9). Never
    /// the Film Exposure slider, which is a development decision.
    var bias: Double?
    /// `FocalLenIn35mmFilm`: the 135 equivalent, which is what a 135 data
    /// back would print.
    var focal35: Double?

    init() {}

    init(exif: [CFString: Any]?) {
        guard let exif else { return }
        if let s = exif[kCGImagePropertyExifDateTimeOriginal] as? String { captureDay = Self.day(s) }
        exposureTime = Self.positive(exif[kCGImagePropertyExifExposureTime])
        fNumber = Self.positive(exif[kCGImagePropertyExifFNumber])
        program = (exif[kCGImagePropertyExifExposureProgram] as? NSNumber)?.intValue
        bias = (exif[kCGImagePropertyExifExposureBiasValue] as? NSNumber)?.doubleValue
        focal35 = Self.positive(exif[kCGImagePropertyExifFocalLenIn35mmFilm])
    }

    /// EXIF's `yyyy:MM:dd HH:mm:ss`; anything else is no date.
    static func day(_ s: String) -> Day? {
        let parts = s.prefix(10).split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]),
              parts[0] > 1800 else { return nil }
        return Day(year: parts[0], month: parts[1], day: parts[2])
    }

    private static func positive(_ v: Any?) -> Double? {
        guard let d = (v as? NSNumber)?.doubleValue, d.isFinite, d > 0 else { return nil }
        return d
    }

    /// The date as the `lcd` and `dots` faces print it, or "" with no date
    /// (an empty text prints nothing).
    func dateText(order: DateBackOrder) -> String {
        guard let d = captureDay else { return "" }
        return DateBackSettings.format(year: d.year, month: d.month, day: d.day, order: order)
    }

    /// The longest line Nikon's between-frames imprint holds (RFC-033 §5):
    /// `1/250 F5.6 A +0.3 24mm` is exactly this long.
    static let dataLineMax = 22

    /// The `data` face's line, after the F6: shutter, aperture, mode,
    /// compensation, focal length. No ISO and no name line (answer E7), the
    /// real f-number (E8), the camera's compensation, omitted at zero (E9).
    /// Fields drop from the right until the line fits. Only characters the
    /// 5×7 face draws: the seconds mark is `s`, since the face has no `"`.
    var dataText: String {
        var fields: [String] = []
        if let t = exposureTime { fields.append(Self.shutter(t)) }
        if let f = fNumber { fields.append("F" + Self.trimmed(f)) }
        if let m = program.flatMap(Self.mode) { fields.append(m) }
        if let b = bias, let s = Self.compensation(b) { fields.append(s) }
        if let mm = focal35 { fields.append("\(Int(mm.rounded()))mm") }
        while fields.joined(separator: " ").count > Self.dataLineMax { fields.removeLast() }
        return fields.joined(separator: " ")
    }

    static func shutter(_ t: Double) -> String {
        if t >= 1 { return trimmed(t) + "s" }
        return "1/\(Int((1 / t).rounded()))"
    }

    static func mode(_ program: Int) -> String? {
        switch program {
        case 1: "M"
        case 2: "P"
        case 3: "A"
        case 4: "S"
        default: nil
        }
    }

    /// `+0.3`, `-1.0`; nil at zero.
    static func compensation(_ ev: Double) -> String? {
        let r = (ev * 10).rounded() / 10
        guard r != 0 else { return nil }
        return String(format: "%+.1f", r)
    }

    /// One decimal, without a trailing `.0`: `1.8`, `2`, `11`.
    static func trimmed(_ v: Double) -> String {
        let s = String(format: "%.1f", v)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
}

// MARK: - the film canvas, estimated

/// How big the engine's film canvas will be, before the engine is asked.
///
/// A stand-in for `spk_overscan_geometry` (API-SPEC §13, not built), from the
/// engine's own layout arithmetic (`overscan_layout`) at its widest draws, so
/// it errs large: it is for the memory forecast and the texture-limit refusal,
/// which must not under-count, and never for placing anything on the picture.
enum FilmCanvasEstimate {
    static func size(picture: CGSize, format: FilmEdgeFormat, view: FilmEdgeView, pair: Bool = false) -> CGSize {
        let w = Double(picture.width), h = Double(picture.height)
        guard w > 0, h > 0 else { return .zero }
        // A pair's picture is both holes and the advance between them.
        let gate = pair ? (long: 37.0, short: 24.0) : format.gateMM
        let px = gate.long / max(w, h)                        // mm per pixel
        // The film runs along the picture axis that is not the gate's across
        // size (the engine's `vertical`).
        let acrossMM = format.gauge == "135" ? 24.0 : 56.0
        let vertical = abs(w * px - acrossMM) < abs(h * px - acrossMM) && w != h
        let alongPx = vertical ? h : w
        let marginMM: Double
        let acrossCanvasMM: Double
        switch view {
        case .strip:
            // 135 advances 38 mm for 36 (0.75–0.95 a side), half frame 19 for
            // 18 (0.40–0.50); 120's spacing is the camera's, ±0.25 per frame.
            marginMM = format == .f135Half ? 0.5 : (format.isPerforated ? 0.95 : 2.35)
            // The film's width (120's is cut to +-0.15) and nothing past it:
            // a strip scan shows no carrier since 1.3.1 (the engine's
            // `overscan_carrier` is `none` unless asked).
            acrossCanvasMM = format.filmWidthMM + (format.isPerforated ? 0 : 0.15)
        case .filed:
            marginMM = 1.0
            acrossCanvasMM = (vertical ? w : h) * px + 2.2
        }
        let along = alongPx + 2 * (marginMM / px).rounded()
        let across = (acrossCanvasMM / px).rounded()
        return vertical ? CGSize(width: across, height: along) : CGSize(width: along, height: across)
    }
}

/// A film edge the engine could render but the canvas could not hold: the
/// film around the picture is wider than the GPU's largest texture. Worded so
/// `EngineMessage` files it as a size refusal, with the badge that goes with
/// one, rather than as an unknown engine error.
struct FilmEdgeTooLarge: Error, CustomStringConvertible {
    let canvas: CGSize
    let limit: Int
    let format: FilmEdgeFormat
    var description: String {
        "the film edge is too large for this GPU: the \(format.rawValue) film around this picture would be "
            + "about \(Int(canvas.width)) x \(Int(canvas.height)) px, above the device's \(limit) px texture "
            + "limit — crop the picture smaller or choose a format whose film is narrower"
    }
}

// MARK: - the session's half
