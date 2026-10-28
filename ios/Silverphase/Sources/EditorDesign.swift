import SwiftUI

/// Executable tokens for ios/DESIGN.md. No panel owns a private spacing scale.
enum EditorDesign {
    static let unit: CGFloat = 4
    static let gutter: CGFloat = 12
    static let contentInset: CGFloat = 16
    static let canvasInfoInset: CGFloat = 28
    static let hitSize: CGFloat = 44
    static let glyphSize: CGFloat = 20
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
}

struct ToolbarGlyph: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol).resizable().scaledToFit()
            .symbolRenderingMode(.monochrome)
            .frame(width: EditorDesign.glyphSize, height: EditorDesign.glyphSize)
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

/// Same image, title and subtitle baselines for every card; no white inversion.
struct BrowserCard<Artwork: View>: View {
    let title: String?
    let subtitle: String
    let width: CGFloat
    let selected: Bool
    @ViewBuilder let artwork: () -> Artwork
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            artwork()
                .frame(width: width - EditorDesign.cardInset * 2, height: EditorDesign.artworkHeight + (title == nil ? 14 : 0))
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: EditorDesign.artworkRadius, style: .continuous))
                .padding(.bottom, 4)
            if let title {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary)
                    .lineLimit(1).frame(maxWidth: .infinity, minHeight: 14, maxHeight: 14, alignment: .leading)
            }
            Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                .lineLimit(1).frame(maxWidth: .infinity, minHeight: 12, maxHeight: 12, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(EditorDesign.cardInset)
        .frame(width: width, height: EditorDesign.cardHeight, alignment: .topLeading)
        .modifier(BrowserSelection(selected: selected))
    }
}
