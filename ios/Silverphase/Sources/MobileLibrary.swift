import SwiftUI
import UniformTypeIdentifiers

struct MobileLibrary: View {
    @Bindable var document: MobileDocument
    @State private var minimumRating = 0
    @State private var flagFilter = "all"
    @State private var search = ""
    @State private var pickingPhotos = false
    @State private var importing = false
    @State private var settings = false
    @State private var about = false
    @State private var editor: LibraryEditorRequest?
    @State private var exportRequest: LibraryExportRequest?
    @State private var copyRequest: MobileSettingsCopyRequest?
    @State private var deleting: Set<UUID> = []
    @State private var cellFrames: [UUID: CGRect] = [:]
    @State private var storageBytes: Int64 = 0

    private var filtered: [MobilePhoto] {
        document.photos.filter {
            $0.rating >= minimumRating && (flagFilter == "all" || $0.flag == flagFilter) &&
            (search.isEmpty || $0.name.localizedStandardContains(search))
        }
    }
    private var selected: [MobilePhoto] { document.photos.filter { document.selectedPhotoIDs.contains($0.id) } }
    var body: some View {
        NavigationStack {
            ScrollView {
                Text("\(document.photos.count) 张照片 · 原文件 " + ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 12)
                    .accessibilityIdentifier("library.summary")
                if let issue = document.libraryReadError {
                    ContentUnavailableView("图库暂时无法读取", systemImage: "externaldrive.badge.exclamationmark", description: Text(issue + "\n原文件与记录已保留，请稍后重启重试。"))
                        .padding(.top, 80)
                } else if document.photos.isEmpty {
                    ContentUnavailableView {
                        Label("图库", systemImage: "photo.on.rectangle.angled")
                    } description: {
                        Text("导入照片与编辑会自动保存在此设备，随时回来继续。")
                    } actions: {
                        Button("从照片导入", systemImage: "plus") { pickingPhotos = true }
                    }.padding(.top, 80)
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 240), spacing: 12)], spacing: 16) {
                        ForEach(filtered) { photo in photoCell(photo) }
                    }.padding(16)
                        .coordinateSpace(name: "library.grid")
                        .onPreferenceChange(LibraryCellFrames.self) { cellFrames = $0 }
                        .background {
                            LibrarySelectionGesture(enabled: document.isSelectingPhotos && !document.isInteractionLocked,
                                ids: filtered.map(\.id), frames: cellFrames, selection: document.selectedPhotoIDs,
                                commit: { document.selectAllPhotos(Array($0)) })
                        }
                }
            }
            .background(MobileStyle.surface.ignoresSafeArea())
            .navigationTitle(document.isSelectingPhotos ? "已选 \(selected.count) 张" : "图库")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "搜索照片名称")
            .toolbar { libraryToolbar }
            .disabled(document.isInteractionLocked)
        }
        .tint(.primary)
        .background(MobileStyle.surface.ignoresSafeArea())
        .onChange(of: filtered.map(\.id)) { _, ids in document.restrictPhotoSelection(to: ids) }
        .task(id: document.photos.map(\.id)) {
            let urls = document.photos.map { document.url(for: $0) }
            storageBytes = await Task.detached(priority: .utility) {
                urls.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            }.value
        }
        .fullScreenCover(item: $editor, onDismiss: { document.closeEditor() }) { request in
            MobileEditor(document: document, batchIDs: request.ids, returnToLibrary: { editor = nil })
        }
        .sheet(item: $copyRequest) { MobileCopySettingsSheet(document: document, request: $0) }
        .sheet(item: $exportRequest) { request in
            NavigationStack {
                ScrollView { MobileExportPanel(document: document, filteredIDs: request.ids, fixedIDs: request.ids) }
                    .navigationTitle("导出成片").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { exportRequest = nil }.disabled(document.isInteractionLocked).accessibilityIdentifier("library.export-done") } }
                    .disabled(document.isInteractionLocked)
                    .overlay { notification(covered: document.exported != nil) }
                    .sheet(isPresented: shareBinding) { shareSheet }
            }.interactiveDismissDisabled(document.isInteractionLocked)
        }
        .sheet(isPresented: $pickingPhotos) {
            LibraryPhotoPicker(isPresented: $pickingPhotos,
                onStart: { document.beginPhotoImport(total: $0) },
                onProgress: { document.photoImportProgress(index: $0, total: $1, name: $2) }) { files, skipped, errors in
                Task {
                    if !files.isEmpty {
                        await document.importFiles(files.map(\.url), displayNames: Dictionary(uniqueKeysWithValues: files.map { ($0.url, $0.name) }),
                                                   removeSourcesAfterImport: true, continuingPhotoSelection: true).value
                    } else { document.finishPhotoImportWithoutFiles() }
                    if skipped > 0 { document.postNotification("已跳过 \(skipped) 张不支持或无法读取的照片", style: .warning) }
                    if !errors.isEmpty { document.error = errors.joined(separator: "\n") }
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .rawImage], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): document.importFiles(urls)
            case .failure(let error): document.error = error.localizedDescription
            }
        }
        .sheet(isPresented: $settings) { MobileSettingsView(document: document) }
        .sheet(isPresented: $about) { MobileAbout() }
        .confirmationDialog("从图库删除 \(deleting.count) 张照片？", isPresented: Binding(get: { !deleting.isEmpty }, set: { if !$0 { deleting = [] } })) {
            Button("删除应用内原文件和编辑记录", role: .destructive) { document.removePhotos(deleting); deleting = [] }
        } message: { Text("此操作无法撤销。系统相册和导入来源不受影响。") }
        .overlay { notification(covered: editor != nil || exportRequest != nil || pickingPhotos || importing || settings || about || copyRequest != nil) }
    }
    private var shareBinding: Binding<Bool> {
        Binding(get: { document.exported != nil }, set: { if !$0 { document.clearExport() } })
    }
    @ViewBuilder private var shareSheet: some View {
        if let url = document.exported { ActivitySheet(urls: document.exportedFiles.isEmpty ? [url] : document.exportedFiles) }
    }
    private func notification(covered: Bool) -> some View {
        MobileNotificationCenter(notification: document.currentNotification, isCovered: covered, dismiss: document.dismissNotification)
    }
    private func open(_ photos: [MobilePhoto]) {
        guard let first = photos.first else { return }
        document.openEditor(first.id, ids: photos.map(\.id))
        editor = LibraryEditorRequest(ids: photos.count > 1 ? photos.map(\.id) : nil)
    }
    private func requestCopy(_ photo: MobilePhoto) {
        document.endParameterInteraction()
        copyRequest = MobileSettingsCopyRequest(source: photo, groups: document.copyGroups)
    }
    private func photoCell(_ photo: MobilePhoto) -> some View {
        let preview = document.libraryPreviewURL(photo)
        let hasPreview = FileManager.default.fileExists(atPath: preview.path)
        return Button {
            if document.isSelectingPhotos { document.togglePhotoSelection(photo.id) }
            else { open([photo]) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                FilmstripThumbnail(url: hasPreview ? preview : document.url(for: photo), fillsFrame: false)
                    .frame(maxWidth: .infinity).frame(height: 140)
                    .background(.black.opacity(0.3)).clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .topTrailing) {
                        if document.isSelectingPhotos {
                            Image(systemName: document.selectedPhotoIDs.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title2).foregroundStyle(document.selectedPhotoIDs.contains(photo.id) ? MobileStyle.accent : .white)
                                .background(.black.opacity(0.65), in: Circle()).padding(8)
                        }
                    }
                Text(photo.name).font(.caption).lineLimit(1)
                HStack(spacing: 4) {
                    if photo.rating > 0 { Text(String(repeating: "★", count: photo.rating)).foregroundStyle(MobileStyle.accent) }
                    if photo.flag != "none" { Image(systemName: photo.flag == "pick" ? "flag.fill" : "flag.slash") }
                    Spacer(minLength: 0)
                }.font(.caption2).foregroundStyle(.secondary).frame(height: 14)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background { GeometryReader { proxy in
            Color.clear.preference(key: LibraryCellFrames.self, value: [photo.id: proxy.frame(in: .named("library.grid"))])
        } }
        .accessibilityLabel(photo.name)
        .accessibilityValue(document.selectedPhotoIDs.contains(photo.id) ? "已选择" : "未选择")
        .accessibilityIdentifier("library.photo." + photo.name)
        .contextMenu {
            Button("编辑", systemImage: "slider.horizontal.3") { open([photo]) }
            Button("选择多张", systemImage: "checkmark.circle") { document.beginPhotoSelection(photo.id) }
            Button("复制编辑项", systemImage: "doc.on.doc") { requestCopy(photo) }
            Button("粘贴编辑项", systemImage: "doc.on.clipboard") { document.pasteSettings(to: [photo.id]) }.disabled(document.settingsClipboard == nil)
            Button("导出", systemImage: "square.and.arrow.up") { exportRequest = LibraryExportRequest(ids: [photo.id]) }
            ratingMenu(ids: [photo.id])
            Button("从图库删除", systemImage: "trash", role: .destructive) { deleting = [photo.id] }
        }
    }
    private var verticalToolbar: Bool {
        if #available(iOS 27.1, *) { UIDevice.current.userInterfaceIdiom == .phone }
        else { false }
    }
    @ToolbarContentBuilder private var libraryToolbar: some ToolbarContent {
        if !document.isSelectingPhotos {
            MobileLibraryToolbarItem(placement: .topBarLeading, vertical: verticalToolbar) {
                Menu {
                    Button("从照片导入", systemImage: "photo.on.rectangle") { pickingPhotos = true }
                    Button("从文件导入", systemImage: "folder") { importing = true }
                } label: { Label("导入", systemImage: "plus") }
                    .accessibilityIdentifier("library.import").disabled(document.libraryReadError != nil)
            }
        }
        if !document.isSelectingPhotos { MobileLibraryToolbarSeparator(vertical: verticalToolbar) }
        MobileLibraryToolbarItem(vertical: verticalToolbar) {
            Button {
                if document.isSelectingPhotos { document.endPhotoSelection() }
                else { document.beginPhotoSelection() }
            } label: {
                Label(document.isSelectingPhotos ? "完成" : "选择", systemImage: document.isSelectingPhotos ? "checkmark" : "checkmark.circle")
            }.disabled(document.photos.isEmpty).accessibilityIdentifier("library.select")
        }
        if document.isSelectingPhotos {
            MobileLibraryToolbarItem(vertical: verticalToolbar) {
                let all = selected.count == filtered.count && !filtered.isEmpty
                Button {
                    if all { document.clearPhotoSelection() }
                    else { document.selectAllPhotos(filtered.map(\.id)) }
                } label: {
                    Label(all ? "清空选择" : "全选", systemImage: all ? "xmark.square" : "checkmark.rectangle.stack")
                }.disabled(filtered.isEmpty).accessibilityIdentifier("library.select-all")
            }
            MobileLibraryToolbarSeparator(vertical: verticalToolbar)
            MobileLibraryToolbarItem(vertical: verticalToolbar) {
                Button("编辑", systemImage: "slider.horizontal.3") { open(selected) }
                    .disabled(selected.isEmpty).accessibilityIdentifier("library.edit-selected")
            }
            MobileLibraryToolbarItem(vertical: verticalToolbar) {
                Button("导出", systemImage: "square.and.arrow.up") {
                    exportRequest = LibraryExportRequest(ids: selected.map(\.id))
                }.disabled(selected.isEmpty).accessibilityIdentifier("library.export-selected")
            }
            MobileLibraryToolbarSeparator(vertical: verticalToolbar)
            MobileLibraryToolbarItem(vertical: verticalToolbar) {
                Menu {
                    Button("复制编辑项", systemImage: "doc.on.doc") { if let photo = selected.first { requestCopy(photo) } }.disabled(selected.count != 1)
                    Button("粘贴到所选 \(selected.count) 张", systemImage: "doc.on.clipboard") { document.pasteSettings() }.disabled(document.settingsClipboard == nil)
                    ratingMenu(ids: document.selectedPhotoIDs)
                    Button("从图库删除", systemImage: "trash", role: .destructive) { deleting = document.selectedPhotoIDs }
                } label: { Label("更多", systemImage: "ellipsis") }
                    .disabled(selected.isEmpty).accessibilityIdentifier("library.selection-menu")
            }
        }
        if !document.isSelectingPhotos {
            MobileLibraryToolbarSeparator(vertical: verticalToolbar)
            MobileLibraryToolbarItem(vertical: verticalToolbar) {
                Menu {
                    Picker("星级", selection: $minimumRating) {
                        Text("全部星级").tag(0)
                        ForEach(1...5, id: \.self) { Text("至少 \($0) 星").tag($0) }
                    }
                } label: {
                    Label {
                        Text("按星级筛选 · " + (minimumRating == 0 ? "全部星级" : "至少 \(minimumRating) 星"))
                    } icon: {
                        filterGlyph("star", active: minimumRating > 0, badge: minimumRating > 0 ? "\(minimumRating)" : nil)
                    }
                }.accessibilityIdentifier("library.rating-filter")
                    .accessibilityLabel("按星级筛选 · " + (minimumRating == 0 ? "全部星级" : "至少 \(minimumRating) 星"))
                    .accessibilityValue(minimumRating == 0 ? "全部星级" : "至少 \(minimumRating) 星")
            }
            MobileLibraryToolbarItem(vertical: verticalToolbar) {
                Menu {
                    Picker("旗标", selection: $flagFilter) {
                        Text("全部旗标").tag("all"); Text("无旗标").tag("none")
                        Text("保留").tag("pick"); Text("淘汰").tag("reject")
                    }
                } label: {
                    Label {
                        Text("按旗标筛选 · " + flagSummary)
                    } icon: {
                        filterGlyph(flagFilter == "pick" ? "flag.fill" : flagFilter == "reject" ? "flag.slash" : "flag",
                                    active: flagFilter != "all", badge: flagFilter == "none" ? "无" : nil)
                    }
                }.accessibilityIdentifier("library.flag-filter")
                    .accessibilityLabel("按旗标筛选 · " + flagSummary)
                    .accessibilityValue(flagFilter == "all" ? "全部旗标" : flagFilter == "pick" ? "保留" : flagFilter == "reject" ? "淘汰" : "无旗标")
            }
            MobileLibraryToolbarSeparator(vertical: verticalToolbar)
            MobileLibraryToolbarItem(vertical: verticalToolbar) {
                Menu {
                    Button("设置", systemImage: "gearshape") { settings = true }
                    Button("关于 Silverphase", systemImage: "info.circle") { about = true }
                } label: {
                    Label("图库菜单", systemImage: "ellipsis.circle")
                }.accessibilityIdentifier("library.menu")
            }
        }
    }
    private var flagSummary: String {
        flagFilter == "all" ? "全部旗标" : flagFilter == "pick" ? "保留" : flagFilter == "reject" ? "淘汰" : "无旗标"
    }
    private func filterGlyph(_ symbol: String, active: Bool, badge: String?) -> some View {
        // An original-rendered symbol retains state colour in Duo's shared rail
        // without tinting the menu's ordinary actions.
        let color: UIColor = active ? .systemOrange : .label
        let icon = (UIImage(systemName: symbol) ?? UIImage())
            .withTintColor(color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)), renderingMode: .alwaysOriginal)
        return Image(uiImage: icon).renderingMode(.original)
            .overlay(alignment: .bottomTrailing) {
                if let badge {
                    Text(badge).font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(active ? MobileStyle.accent : .primary)
                        .padding(2).background(MobileStyle.surface, in: Circle()).offset(x: 7, y: 7)
                }
            }
    }
    private func ratingMenu(ids: Set<UUID>) -> some View {
        Group {
            Menu("评分", systemImage: "star") {
                ForEach(0...5, id: \.self) { rating in
                    Button(rating == 0 ? "清除评分" : "\(rating) 星") { document.markPhotos(ids, rating: rating) }
                }
            }
            Button("保留", systemImage: "flag.fill") { document.markPhotos(ids, flag: "pick") }
            Button("淘汰", systemImage: "flag.slash") { document.markPhotos(ids, flag: "reject") }
            Button("清除旗标") { document.markPhotos(ids, flag: "none") }
        }
    }
}
private struct LibraryEditorRequest: Identifiable { let id = UUID(); let ids: [UUID]? }
private struct LibraryExportRequest: Identifiable { let id = UUID(); let ids: [UUID] }

/// Duo's shared rail owns vertical placement; iPad and older phones use the
/// same native actions in their navigation toolbar, with no bottom action slab.
private struct MobileLibraryToolbarItem<Content: View>: ToolbarContent {
    var placement: ToolbarItemPlacement = .topBarTrailing
    var vertical: Bool
    @ViewBuilder var content: () -> Content
    @ToolbarContentBuilder var body: some ToolbarContent {
        if #available(iOS 27.1, *), vertical {
            ToolbarItem(placement: .topBarLeading) { content().labelStyle(.iconOnly) }
                .axisBehavior(.verticalPreferred)
        } else {
            ToolbarItem(placement: placement) { content().labelStyle(.iconOnly) }
        }
    }
}

private struct MobileLibraryToolbarSeparator: ToolbarContent {
    var vertical: Bool
    @ToolbarContentBuilder var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: vertical ? .topBarLeading : .topBarTrailing)
        } else {
            ToolbarItem(placement: .topBarTrailing) { Divider().frame(height: 20) }
        }
    }
}
