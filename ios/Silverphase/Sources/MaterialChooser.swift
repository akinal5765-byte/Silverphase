import SwiftUI

enum MobileMaterialFilter: String, CaseIterable, Identifiable {
    case all = "全部", positive = "正片", negative = "负片", monochrome = "黑白", experimental = "实验", favorites = "收藏", recent = "最近"
    var id: String { rawValue }
    func includes(_ stock: Stock, favorites: Set<String>, recent: [String]) -> Bool {
        return switch self {
        case .all: true
        case .positive: stock.isPositive && !stock.isExperimental
        case .negative: stock.isFilm && !stock.isPositive && !stock.isExperimental
        case .monochrome: stock.isMonochrome
        case .experimental: stock.isExperimental
        case .favorites: favorites.contains(stock.id)
        case .recent: recent.contains(stock.id)
        }
    }
}

struct MaterialChooser: View {
    @Bindable var document: MobileDocument
    var startsWithPaper = false
    var vertical = false
    @State private var paper = false
    @State private var query = ""
    @State private var searching = false
    @State private var filter = MobileMaterialFilter.all
    @State private var favorites: Set<String> = []
    @State private var recent: [String] = []
    private let catalog = StockCatalog.shared
    private var stocks: [Stock] {
        let choices = (paper ? catalog.papers : catalog.filmsForPicker).filter {
            (query.isEmpty || $0.name.localizedStandardContains(query)) && filter.includes($0, favorites: favorites, recent: recent)
        }
        return filter == .recent ? choices.sorted { (recent.firstIndex(of: $0.id) ?? 999) < (recent.firstIndex(of: $1.id) ?? 999) } : choices
    }
    private var filters: [MobileMaterialFilter] {
        paper ? [.all, .monochrome, .favorites, .recent] : MobileMaterialFilter.allCases.filter {
            $0 != .experimental || catalog.films.contains(where: \.isExperimental)
        }
    }
    var body: some View {
        VStack(spacing: EditorDesign.browserGap) {
            HStack(spacing: 4) {
                tab("胶片", selected: !paper) { paper = false; filter = .all }
                tab("相纸", selected: paper) { paper = true; filter = .all }
                Rectangle().fill(MobileStyle.rule).frame(width: 1, height: 20)
                if searching {
                    TextField("搜索材料", text: $query).font(EditorDesign.label).textFieldStyle(.plain)
                        .frame(minWidth: 0, maxWidth: .infinity).accessibilityIdentifier("materials.search")
                    ChromeButton(title: "结束搜索", symbol: "xmark") { searching = false; query = "" }
                } else if vertical {
                    Menu {
                        ForEach(filters) { item in
                            Button { filter = item } label: {
                                if filter == item { Label(item.rawValue, systemImage: "checkmark") }
                                else { Text(item.rawValue) }
                            }.accessibilityIdentifier("materials.filter." + String(describing: item))
                        }
                    } label: {
                        HStack { Text(filter.rawValue); Image(systemName: "chevron.down") }
                            .font(EditorDesign.parameter).frame(minHeight: EditorDesign.hitSize)
                    }.accessibilityLabel("材料分类").accessibilityIdentifier("materials.category")
                    Spacer(minLength: 0)
                    ChromeButton(title: "搜索材料", symbol: "magnifyingglass") { searching = true }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(filters) { item in
                                tab(item.rawValue, selected: filter == item) { filter = item }
                                    .accessibilityIdentifier("materials.filter." + String(describing: item))
                            }
                        }
                    }.frame(minWidth: 0, maxWidth: .infinity).clipped()
                    ChromeButton(title: "搜索材料", symbol: "magnifyingglass") { searching = true }
                }
            }.frame(height: EditorDesign.panelHeader).padding(.horizontal, EditorDesign.cardInset)
            ScrollViewReader { proxy in
                Group {
                    if vertical {
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 8) { materialItems }
                                .padding(.horizontal, EditorDesign.contentInset).padding(.bottom, EditorDesign.cardInset)
                        }.accessibilityIdentifier("materials.vertical-list")
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 8) { materialItems }.padding(.horizontal, EditorDesign.cardInset)
                        }.frame(height: EditorDesign.cardHeight)
                    }
                }.clipped()
                .onChange(of: paper) { _, _ in reveal(proxy) }
                .onChange(of: filter) { _, _ in reveal(proxy) }
                .onAppear { reveal(proxy) }
            }
        }
        .padding(.vertical, EditorDesign.cardInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .disabled(document.current == nil || document.delivering)
        .onAppear { paper = startsWithPaper }
        .onChange(of: startsWithPaper) { _, value in paper = value; filter = .all }
    }
    @ViewBuilder private var materialItems: some View {
        if paper && filter == .all && query.isEmpty {
            specialCard("不使用相纸", subtitle: "直接扫描胶片", symbol: "film", selected: document.value("scan_film")?.boolValue == true) { document.setPaper(nil) }
            specialCard("数字中间片", subtitle: "Cineon Log", symbol: "film.stack", selected: document.value("digital_intermediate")?.boolValue == true && document.value("scan_film")?.boolValue != true) {
                document.setValues(["scan_film": .bool(false), "digital_intermediate": .bool(true)])
            }
        }
        ForEach(stocks) { stock in
            Button {
                if paper { document.setPaper(stock) } else { document.setFilm(stock) }
                recent.removeAll { $0 == stock.id }; recent.insert(stock.id, at: 0)
            } label: {
                if vertical { materialRow(stock.name, subtitle: subtitle(stock), selected: isSelected(stock)) { artwork(stock) } }
                else { BrowserCard(title: shortName(stock.name), subtitle: subtitle(stock), width: EditorDesign.materialCardWidth, selected: isSelected(stock)) { artwork(stock) } }
            }.buttonStyle(.plain).id(stock.id)
            .accessibilityLabel(stock.name + ", " + subtitle(stock))
            .accessibilityIdentifier("materials.stock." + stock.id)
            .accessibilityValue(isSelected(stock) ? "已选中" : "未选中")
            .contextMenu {
                Button(favorites.contains(stock.id) ? "取消收藏" : "收藏", systemImage: "star") {
                    if favorites.contains(stock.id) { favorites.remove(stock.id) } else { favorites.insert(stock.id) }
                }
            }.disabled(paper && selectedFilmIsPositive)
        }
        if stocks.isEmpty { Text("没有符合筛选条件的材料").font(EditorDesign.label).foregroundStyle(.secondary).padding(12) }
    }
    private func artwork(_ stock: Stock) -> some View {
        ZStack(alignment: .topTrailing) {
            if let url = stock.packagingArtworkURL ?? stock.coverURL {
                FilmstripThumbnail(url: url, fillsFrame: true).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: paper ? "photo" : "film").font(.system(size: EditorDesign.glyphSize)).frame(maxWidth: .infinity, maxHeight: .infinity).background(MobileStyle.well)
            }
            if favorites.contains(stock.id) { Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(MobileStyle.accent).padding(6).shadow(radius: 2) }
        }
    }
    private func materialRow<Artwork: View>(_ title: String, subtitle: String, selected: Bool, @ViewBuilder artwork: () -> Artwork) -> some View {
        HStack(spacing: 12) {
            artwork().frame(width: 72, height: 40).clipped().clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(EditorDesign.selectedValue).foregroundStyle(.primary).lineLimit(2)
                Text(subtitle).font(EditorDesign.help).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "checkmark").font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MobileStyle.accent).opacity(selected ? 1 : 0).frame(width: 20)
        }.padding(12).frame(minHeight: 64).modifier(BrowserSelection(selected: selected))
    }
    private var selectedFilmIsPositive: Bool {
        document.value("film_stock")?.stringValue.flatMap { catalog.stock($0) }?.isPositive == true
    }
    private func isSelected(_ stock: Stock) -> Bool {
        document.value(paper ? "print_stock" : "film_stock")?.stringValue == stock.id && (!paper || (document.value("scan_film")?.boolValue != true && document.value("digital_intermediate")?.boolValue != true))
    }
    private func shortName(_ name: String) -> String {
        for prefix in ["Kodak Professional ", "Kodak ", "Fujifilm ", "Fuji ", "Ilford "] where name.hasPrefix(prefix) { return String(name.dropFirst(prefix.count)) }
        return name
    }
    private func subtitle(_ stock: Stock) -> String {
        let kind = stock.isMonochrome ? "黑白" : stock.isPaper ? "相纸" : stock.isPositive ? "正片" : "负片"
        return [kind, stock.speedLabel].compactMap { $0 }.joined(separator: " · ")
    }
    private func reveal(_ proxy: ScrollViewProxy) {
        let id = document.value(paper ? "print_stock" : "film_stock")?.stringValue
        if let id, stocks.contains(where: { $0.id == id }) { proxy.scrollTo(id, anchor: .center) }
        else if let first = stocks.first { proxy.scrollTo(first.id, anchor: vertical ? .top : .leading) }
    }
    private func tab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1).fixedSize()
                .foregroundStyle(selected ? MobileStyle.accent : .secondary)
                .frame(minWidth: EditorDesign.hitSize, minHeight: EditorDesign.hitSize).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
    }
    private func specialCard(_ title: String, subtitle: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if vertical {
                materialRow(title, subtitle: subtitle, selected: selected) {
                    Image(systemName: symbol).font(.system(size: EditorDesign.glyphSize)).frame(maxWidth: .infinity, maxHeight: .infinity).background(MobileStyle.well)
                }
            } else {
                BrowserCard(title: title, subtitle: subtitle, width: EditorDesign.materialCardWidth, selected: selected) {
                    Image(systemName: symbol).font(.system(size: EditorDesign.glyphSize)).frame(maxWidth: .infinity, maxHeight: .infinity).background(MobileStyle.well)
                }
            }
        }.buttonStyle(.plain)
    }
}
