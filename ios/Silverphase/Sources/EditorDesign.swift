import SwiftUI

/// Executable tokens for ios/DESIGN.md. No panel owns a private spacing scale.
enum EditorDesign {
    static let unit: CGFloat = 4
    static let gutter: CGFloat = 12
    static let contentInset: CGFloat = 16
    static let canvasInfoInset: CGFloat = 28
    static let hitSize: CGFloat = 44
    static let glyphSize: CGFloat = 20
    static let filmstripGlyphSize: CGFloat = 18
    static let panelHeader: CGFloat = 44
    static let cardInset: CGFloat = 6
    static let cardRadius: CGFloat = 12
    static let artworkRadius: CGFloat = cardRadius - cardInset
    static let materialArtworkAspect: CGFloat = 16 / 9
    static let materialCardWidth: CGFloat = artworkHeight * materialArtworkAspect + cardInset * 2
    static let artworkHeight: CGFloat = 42
    static let cardHeight: CGFloat = 84
    static let browserGap: CGFloat = 4
    static let browserHeight: CGFloat = cardInset * 2 + panelHeader + browserGap + cardHeight
    static let labelWidth: CGFloat = 92
    static let valueWidth: CGFloat = 48
    static let label = Font.system(size: 12)
    static let caption = Font.system(size: 11)
    static let badge = Font.system(size: 10, weight: .semibold)
    static let cardTitle = Font.system(size: 12, weight: .semibold)
    static let noticeTitle = Font.system(size: 13, weight: .semibold)

    // Inspector roles: keep parameter rows consistent across ruler/menu/toggle controls.
    static let panelTitle = Font.system(size: 15, weight: .semibold)
    static let sectionTitle = Font.system(size: 13, weight: .semibold)
    static let parameter = Font.system(size: 13)
    static let selectedValue = Font.system(size: 13, weight: .medium)
    static let numericValue = Font.system(size: 14, weight: .medium)
    static let panelSummary = Font.system(size: 12)
    static let help = Font.system(size: 11)
    static let instrument = Font.system(size: 10).monospacedDigit()
}

/// Duo gains at most a small symmetric crop. Manual zoom remains a
/// separate transform in both photo canvases.
enum MobilePhotoFit {
    static func scale(image: CGSize, available: CGSize, duo: Bool) -> CGFloat {
        guard image.width > 0, image.height > 0 else { return 1 }
        let x = available.width / image.width
        let y = available.height / image.height
        let fit = min(x, y)
        return duo ? min(max(x, y), fit * 1.06) : fit
    }
}

struct ToolbarGlyph: View {
    let symbol: String
    var size: CGFloat = EditorDesign.glyphSize
    var body: some View {
        Image(systemName: symbol).resizable().font(.system(size: size, weight: .regular)).scaledToFit()
            .symbolRenderingMode(.monochrome)
            .frame(width: size, height: size)
            // The arrow raises the export glyph's bounds above its square body.
            // Align the visual mass with the comparison rectangle, not its bounds.
            .offset(y: symbol == "square.and.arrow.up" ? -2 : 0)
            .frame(width: EditorDesign.hitSize, height: EditorDesign.hitSize)
            .contentShape(Rectangle())
    }
}

struct BrowserSelection: ViewModifier {
    let selected: Bool
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: EditorDesign.cardRadius, style: .continuous)
        content
            .background(selected ? MobileStyle.accent.opacity(0.06) : Color.white.opacity(0.035), in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(selected ? MobileStyle.accent : .white.opacity(0.16), lineWidth: selected ? 2 : 1))
            .contentShape(shape)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

extension View {
    func fotufilmBadge(for stock: Stock?) -> some View {
        overlay(alignment: .bottomLeading) {
            if stock?.isFotufilm == true {
                Text("Fotufilm")
                    .font(EditorDesign.badge)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.78), in: Capsule())
                    .fixedSize()
                    .padding(4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Same image, title and subtitle baselines for every card; no white inversion.
struct BrowserCard<Artwork: View>: View {
    let title: String?
    let subtitle: String
    let width: CGFloat
    let selected: Bool
    var stock: Stock? = nil
    var compact = false
    @ViewBuilder let artwork: () -> Artwork
    private var artworkWidth: CGFloat { width - EditorDesign.cardInset * 2 }
    private var artworkHeight: CGFloat {
        stock == nil ? EditorDesign.artworkHeight + (title == nil ? 14 : 0) : artworkWidth / EditorDesign.materialArtworkAspect
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            artwork()
                .frame(width: artworkWidth, height: artworkHeight)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: EditorDesign.artworkRadius, style: .continuous))
                .fotufilmBadge(for: stock)
                .padding(.bottom, 4)
            if let title {
                Text(title).font(EditorDesign.cardTitle).foregroundStyle(.primary)
                    .lineLimit(1).frame(maxWidth: .infinity, minHeight: 14, maxHeight: 14, alignment: .leading)
            }
            Text(subtitle).font(EditorDesign.instrument).foregroundStyle(.secondary)
                .lineLimit(1).frame(maxWidth: .infinity, minHeight: 12, maxHeight: 12, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(EditorDesign.cardInset)
        .frame(width: width, height: compact
               ? artworkHeight + EditorDesign.cardInset * 2 + (title == nil ? 16 : 30)
               : EditorDesign.cardHeight + (stock == nil ? 0 : max(0, artworkHeight - EditorDesign.artworkHeight)),
               alignment: .topLeading)
        .modifier(BrowserSelection(selected: selected))
    }
}

/// Shared heading rhythm for process and export inspectors.
struct ToolSectionTitle: View {
    let title: String
    var body: some View {
        Text(title).font(EditorDesign.sectionTitle).foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 24).padding(.bottom, 10)
            .accessibilityAddTraits(.isHeader)
    }
}
