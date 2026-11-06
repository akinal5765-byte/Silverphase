import SwiftUI

// Custom control geometry and hierarchy, using the system Liquid Glass
// material for floating navigation/control surfaces, as on the desktop.
struct ChromeButton: View {
    let title: String
    let symbol: String
    var selected = false
    var enabled = true
    var glyphSize: CGFloat = EditorDesign.glyphSize
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ToolbarGlyph(symbol: symbol, size: glyphSize)
                .foregroundStyle(!enabled ? MobileStyle.muted : selected ? MobileStyle.accent : .white.opacity(0.85))
                 .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!enabled).accessibilityLabel(title)
    }
}

struct MobileOption: Identifiable {
    let id: String
    let title: String
    var symbol: String? = nil
    var enabled = true
    var accessibilityID: String? = nil
}

@MainActor struct MobileChoice {
    let title: String
    let options: [MobileOption]
    var selected: String? = nil
    let choose: (String) -> Void
}

@MainActor @Observable final class MobileOverlays {
    var choice: MobileChoice?
}

struct ChoiceOverlay: View {
    @Bindable var overlays: MobileOverlays
    var body: some View {
        if let choice = overlays.choice {
            GeometryReader { geometry in
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { overlays.choice = nil }
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(choice.title).font(EditorDesign.noticeTitle)
                            Spacer()
                            ChromeButton(title: "关闭", symbol: "xmark") { overlays.choice = nil }
                        }.padding(.leading, 12)
                        Rectangle().fill(MobileStyle.rule).frame(height: 1)
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(choice.options) { option in
                                    Button {
                                        overlays.choice = nil
                                        choice.choose(option.id)
                                    } label: {
                                        HStack(spacing: 8) {
                                            if let symbol = option.symbol { Image(systemName: symbol).frame(width: 18) }
                                            Text(option.title).frame(maxWidth: .infinity, alignment: .leading)
                                            if choice.selected == option.id { Image(systemName: "checkmark").foregroundStyle(.primary) }
                                        }
                                        .font(EditorDesign.parameter).foregroundStyle(option.enabled ? .white : MobileStyle.muted)
                                        .frame(minHeight: 44).padding(.horizontal, 12).contentShape(Rectangle())
                                    }.buttonStyle(.plain).disabled(!option.enabled)
                                        .accessibilityIdentifier(option.accessibilityID ?? option.id)
                                }
                            }
                        }.frame(maxHeight: min(CGFloat(choice.options.count * 44), geometry.size.height * 0.65))
                    }
                    .frame(maxWidth: min(320, geometry.size.width - 24))
                    .modifier(ChromeSurface()).shadow(color: .black.opacity(0.4), radius: 16, y: 6)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct SmallAction: View {
    let title: String
    let symbol: String
    var prominent = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) { Image(systemName: symbol); Text(title); Spacer() }
                .font(EditorDesign.selectedValue)
                .foregroundStyle(prominent ? Color.black : Color.white)
                .padding(.horizontal, 12).frame(height: 44)
                .background(prominent ? MobileStyle.accent : MobileStyle.well, in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
