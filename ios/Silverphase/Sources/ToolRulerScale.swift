import Foundation

enum ToolRulerScale {
    static let spacing = 12.0

    static func step(in range: ClosedRange<Double>) -> Double {
        let raw = max(0.0001, (range.upperBound - range.lowerBound) / 40)
        let scale = pow(10, floor(log10(raw)))
        return ([1.0, 2, 2.5, 5, 10].first { $0 * scale >= raw - 1e-10 } ?? 10) * scale
    }

    /// Display ticks describe the scale, never the permitted parameter values.
    /// Quantise only to the numeric label's precision; landmarks exert no pull.
    static func quantized(_ value: Double, in range: ClosedRange<Double>, resolution: Double) -> Double {
        let bounded = min(range.upperBound, max(range.lowerBound, value))
        let rounded = (bounded / resolution).rounded() * resolution
        return min(range.upperBound, max(range.lowerBound, rounded))
    }
    static func advanced(_ value: Double, forward: Bool, range: ClosedRange<Double>, resolution: Double) -> Double {
        quantized(value + (forward ? resolution : -resolution), in: range, resolution: resolution)
    }
    static func majorStep(minor: Double) -> Double {
        if abs(minor - 1.0 / 3) < 1e-8 { return 1 }
        let raw = minor * 4
        let scale = pow(10, floor(log10(raw)))
        return ([1.0, 2, 5, 10].first { $0 * scale >= raw - 1e-10 } ?? 10) * scale
    }
    struct Tick { let value: Double; let major: Bool }
    static func ticks(in visible: ClosedRange<Double>, range: ClosedRange<Double>, step: Double,
                      anchor: Double, keyMarks: [Double]) -> [Tick] {
        let marks = Array(Set(([range.lowerBound, range.upperBound, anchor] + keyMarks).filter { range.contains($0) }))
        let first = Int(ceil(max(range.lowerBound, visible.lowerBound) / step - 1e-9))
        let last = Int(floor(min(range.upperBound, visible.upperBound) / step + 1e-9))
        let major = majorStep(minor: step)
        var result: [Tick] = []
        if first <= last {
            for index in first...last {
                let value = Double(index) * step
                // Replace a nearby minor line with the exact default marker.
                if marks.contains(where: { abs($0 - value) < step * 0.45 }) { continue }
                result.append(Tick(value: value, major: abs(value / major - (value / major).rounded()) < 1e-7))
            }
        }
        result += marks.filter { visible.contains($0) }.map { Tick(value: $0, major: true) }
        return result.sorted { $0.value < $1.value }
    }
}
