// Host-side regression: swiftc ParamValue.swift GalleryPreviewSizing.swift GalleryPreviewSizingChecks.swift -o <tmp-binary>
import Foundation
import CoreGraphics

@main enum GalleryPreviewSizingChecks {
    static func main() {
        let full = CGSize(width: 6000, height: 4000)
        let half = CGSize(width: 3000, height: 2000)
        func target(_ requested: Double, _ visible: CGSize, _ available: Double = 3e9) -> Double {
            GalleryPreviewSizing.fitMP(requested: requested, inputSize: full, pictureSize: visible, availableBytes: available)
        }
        precondition(target(8, full) == 3.3 && target(2, full) == 2)
        let request = 24 * pow(1920.0 / 3000.0, 2)
        let mp = target(request, half)
        precondition(abs(half.width * sqrt(mp / 24) - 1920) < 0.01)
        precondition(target(request, half, 7e8) == 3.3)
        precondition(target(request, half, 1.5e9) < request && target(request, half, 1.5e9) > 3.3)

        func gate(_ size: CGSize, _ recipe: [String: ParamValue]) -> CGRect {
            let extent = CGRect(origin: .zero, size: size)
            return MobileFilmGate.aspect(for: size, recipe: recipe).map {
                GalleryPreviewSizing.gateRect(in: extent, aspect: $0)
            } ?? extent
        }
        precondition(gate(full, ["date_imprint_active": .bool(true)]).size == full)
        let square: [String: ParamValue] = ["overscan_active": .bool(true), "overscan_format": .string("120_6x6")]
        precondition(gate(full, square) == CGRect(x: 1000, y: 0, width: 4000, height: 4000))
        precondition(gate(CGSize(width: 3000, height: 4500), square).size == CGSize(width: 3000, height: 3000))
        let xpan: [String: ParamValue] = ["overscan_active": .bool(true), "overscan_format": .string("135_xpan")]
        precondition(gate(CGSize(width: 4000, height: 6000), xpan).size == CGSize(width: 2215, height: 5999))
        // 24 MP native, 1.5 MP fit: scaled canvas includes the measured border, unlike the unframed original.
        let measured = CGSize(width: 1050, height: 1060)
        precondition(GalleryPreviewSizing.nativeCanvas(fit: measured, inputMP: 1.5, nativeMP: 24) == CGSize(width: 4200, height: 4240))
        precondition(GalleryPreviewSizing.nativeCanvas(fit: measured, inputMP: 8, nativeMP: 6) == measured)
        print("Gallery fit budgets, gate sizes, and native border scaling passed.")
    }
}
