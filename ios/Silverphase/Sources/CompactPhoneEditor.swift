import SwiftUI

/// Floating tools never participate in the photograph's fit rectangle.
struct CompactPhoneLayout {
    let inspector: CGRect
    let media: CGRect
    let tabs: CGRect
    let maximumPanelHeight: CGFloat
    init(size: CGSize, fraction: Double, showsPhotos: Bool) {
        let gap: CGFloat = 12
        let width = max(1, size.width - 2 * gap)
        tabs = CGRect(x: gap, y: max(gap, size.height - 56 - gap), width: width, height: 56)
        let mediaHeight: CGFloat = showsPhotos ? (size.height < 480 ? 84 : EditorDesign.browserHeight) : 0
        media = showsPhotos ? CGRect(x: gap, y: tabs.minY - gap - mediaHeight, width: width, height: mediaHeight) : .zero
        let bottom = (showsPhotos ? media.minY : tabs.minY) - gap
        let top = gap
        maximumPanelHeight = max(1, min(520, size.height * 0.72, bottom - top))
        let height = min(maximumPanelHeight, max(min(176, maximumPanelHeight), size.height * min(0.72, max(0.25, fraction))))
        inspector = CGRect(x: gap, y: bottom - height, width: width, height: height)
    }
}

/// A compact seven-destination bar with one shared, sliding selection surface.
/// The photograph is a single sibling view, never recreated for each tab.
struct CompactProcessTabs: View {
    let stage: MobileStage
    var enabled: Bool
    let select: (MobileStage) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection
    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width - 8, CGFloat(MobileStage.allCases.count) * 44)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(MobileStage.allCases) { item in
                            Button {
                                withAnimation(reduceMotion ? nil : .spring(duration: 0.32, bounce: 0.12)) { select(item) }
                            } label: {
                                VStack(spacing: 3) {
                                    Image(systemName: item.symbol).font(.system(size: 18, weight: .regular))
                                        .frame(height: 20)
                                    Text(item.rawValue).font(.system(size: 9, weight: .medium)).lineLimit(1)
                                }
                                .foregroundStyle(stage == item ? MobileStyle.accent : .primary)
                                .frame(width: width / CGFloat(MobileStage.allCases.count), height: 48)
                                .background {
                                    if stage == item {
                                        Capsule().fill(.white.opacity(0.12))
                                            .matchedGeometryEffect(id: "selected-process", in: selection)
                                    }
                                }.contentShape(Capsule())
                            }
                            .buttonStyle(.plain).disabled(!enabled).id(item)
                            .accessibilityLabel(item.rawValue).accessibilityIdentifier("stage." + item.id)
                            .accessibilityAddTraits(stage == item ? .isSelected : [])
                        }
                    }.padding(4)
                }
                .onChange(of: stage) { _, item in
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { proxy.scrollTo(item, anchor: .center) }
                }
            }
        }
        .modifier(CompactTabSurface())
        .accessibilityElement(children: .contain).accessibilityIdentifier("editor.compact-tabs")
    }
}

private struct CompactTabSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !opaque {
            content.clipShape(Capsule()).glassEffect(.regular, in: Capsule())
        } else {
            content.clipShape(Capsule()).background(opaque ? AnyShapeStyle(MobileStyle.surface) : AnyShapeStyle(.regularMaterial), in: Capsule())
        }
    }
}

extension ToolbarContent {
    @ToolbarContentBuilder func compactHorizontalAxis() -> some ToolbarContent {
        if #available(iOS 27.1, *) { self.axisBehavior(.horizontalOnly) }
        else { self }
    }
}
