#if DEBUG
import Foundation

enum MobileRulerChecks {
    struct Failure: LocalizedError { let errorDescription: String? }
    struct Case {
        let name: String
        let range: ClosedRange<Double>
        let baseline: Double
        var step: Double?
        var resolution = 0.01
    }
    static func run(_ cases: [Case]) throws {
        func require(_ passed: Bool, _ message: String) throws { if !passed { throw Failure(errorDescription: message) } }
        for item in cases {
            let minor = item.step ?? ToolRulerScale.step(in: item.range)
            let ticks = ToolRulerScale.ticks(in: item.range, range: item.range, step: minor, anchor: item.baseline, keyMarks: [])
            try require(ticks.contains { abs($0.value - item.baseline) < 1e-9 && $0.major }, item.name + "默认值不是关键刻度")
            var previous = -Double.infinity
            for index in 0...200 {
                let value = item.range.lowerBound + Double(index) / 200 * (item.range.upperBound - item.range.lowerBound)
                let snapped = ToolRulerScale.quantized(value, in: item.range, resolution: item.resolution)
                try require(snapped >= previous - 1e-9, item.name + "吸附方向反转")
                try require(abs(snapped - value) <= item.resolution / 2 + 1e-8, item.name + "精度受视觉刻度影响")
                let released = ToolRulerScale.quantized(snapped, in: item.range, resolution: item.resolution)
                try require(abs(released - snapped) < 1e-8, item.name + "松手改变已显示数值")
                previous = snapped
            }
            let start = ToolRulerScale.quantized(item.baseline, in: item.range, resolution: item.resolution)
            for forward in [true, false] {
                let advanced = ToolRulerScale.advanced(start, forward: forward, range: item.range, resolution: item.resolution)
                let expected = min(item.range.upperBound, max(item.range.lowerBound, start + (forward ? item.resolution : -item.resolution)))
                try require(abs(advanced - expected) < 1e-8, item.name + "辅助功能没有按最小精度步进")
            }
        }
        let exposure = ToolRulerScale.ticks(in: -4...4, range: -4...4, step: 1 / 3.0, anchor: 0, keyMarks: [])
        for ev in [-1.0, 0, 1] {
            try require(exposure.contains { abs($0.value - ev) < 1e-9 && $0.major }, "整数EV不是主刻度")
        }
        for range in [0.0...30, 0.0...4, 0.0...2, -4.0...4] {
            for value in [0.85, 0.95, 0.99, 1.01, 1.15] {
                try require(abs(ToolRulerScale.quantized(value, in: range, resolution: 0.01) - value) < 1e-9,
                            "精细数值被吸附到粗刻度/默认值")
            }
        }
    }
}
#endif
