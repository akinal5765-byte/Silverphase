import SwiftUI

struct MobileFilmstrip: View {
    @Bindable var document: MobileDocument
    let photos: [MobilePhoto]
    var allowsSelection = true
    @Binding var minimumRating: Int
    @Binding var flagFilter: String
    @State private var deleting: UUID?
    @State private var copyRequest: MobileSettingsCopyRequest?

    private var isSelectingPhotos: Bool { allowsSelection && document.isSelectingPhotos }

    var body: some View {
        VStack(spacing: EditorDesign.browserGap) {
            Group {
                if isSelectingPhotos { selectionToolbar }
                else { photoToolbar }
            }
            .padding(.leading, 12).padding(.trailing, 4).frame(height: 44)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(photos) { photo in
                        Button {
                            if isSelectingPhotos { document.togglePhotoSelection(photo.id) }
                            else { document.select(photo.id) }
                        } label: {
                            BrowserCard(title: nil,
                                        subtitle: (photo.rating > 0 ? String(repeating: "★", count: photo.rating) : T("Unrated", "未评分", "未評分")) + (photo.flag == "pick" ? T(" · Pick", " · 保留", " · 保留") : photo.flag == "reject" ? T(" · Reject", " · 淘汰", " · 淘汰") : ""),
                                        width: 80, selected: photo.id == document.selection) {
                                FilmstripThumbnail(url: document.url(for: photo))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.15))
                            }
                            .overlay(alignment: .topTrailing) {
                                if isSelectingPhotos {
                                    Image(systemName: document.selectedPhotoIDs.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 21, weight: .semibold))
                                        .foregroundStyle(document.selectedPhotoIDs.contains(photo.id) ? MobileStyle.accent : .white)
                                        .background(.black.opacity(0.65), in: Circle())
                                        .padding(5)
                                }
                            }
                        }
                        .buttonStyle(.plain).accessibilityLabel(photo.name)
                        .accessibilityIdentifier("filmstrip.photo." + photo.name)
                        .accessibilityValue(isSelectingPhotos ? (document.selectedPhotoIDs.contains(photo.id) ? T("Selected", "已选择", "已選擇") : T("Not selected", "未选择", "未選擇")) : (photo.id == document.selection ? T("Previewing", "正在预览", "正在預覽") : ""))
                        .contextMenu {
                            if isSelectingPhotos {
                                Button(T("Paste to \(document.selectedPhotoIDs.count) selected", "粘贴到所选 \(document.selectedPhotoIDs.count) 张", "貼到所選 \(document.selectedPhotoIDs.count) 張"), systemImage: "doc.on.clipboard") { document.pasteSettings() }
                                    .disabled(document.settingsClipboard == nil || document.selectedPhotoIDs.isEmpty)
                                Button(T("Deselect", "取消选择", "取消選擇"), systemImage: "xmark") { document.endPhotoSelection() }
                            } else {
                                if allowsSelection {
                                    Button(T("Select multiple", "选择多张", "選擇多張"), systemImage: "checkmark.circle") { document.beginPhotoSelection(photo.id) }
                                }
                                Menu(T("Rating", "评分", "評分"), systemImage: "star") {
                                    ForEach(0...5, id: \.self) { rating in Button(rating == 0 ? T("Clear rating", "清除评分", "清除評分") : T("\(rating) stars", "\(rating) 星", "\(rating) 星")) { document.mark(photo.id, rating: rating) } }
                                }
                                Button(T("Pick", "保留", "保留"), systemImage: "flag.fill") { document.mark(photo.id, flag: "pick") }
                                Button(T("Reject", "淘汰", "淘汰"), systemImage: "flag.slash") { document.mark(photo.id, flag: "reject") }
                                Button(T("Clear flag", "清除旗标", "清除旗標")) { document.mark(photo.id, flag: "none") }
                                Divider()
                                Button(T("Copy Parameters", "复制参数", "複製參數"), systemImage: "doc.on.doc") { requestCopy(photo) }
                                Button(T("Paste Parameters", "粘贴参数", "貼上參數"), systemImage: "doc.on.clipboard") { document.pasteSettings(to: [photo.id]) }
                                    .disabled(document.settingsClipboard == nil)
                                Button(T("Remove from Library", "从图库删除", "從圖庫刪除"), systemImage: "trash", role: .destructive) { deleting = photo.id }
                            }
                        }
                    }
                    if photos.isEmpty { Text(T("No photos match these filters", "没有符合筛选条件的照片", "沒有符合篩選條件的照片")).font(EditorDesign.label).foregroundStyle(.secondary).padding() }
                }.padding(.horizontal, EditorDesign.cardInset)
            }.frame(height: EditorDesign.cardHeight).clipped()
        }
        .padding(.vertical, EditorDesign.cardInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: photos.map(\.id)) { _, ids in
            if allowsSelection { document.restrictPhotoSelection(to: ids) }
        }
        .alert(T("Remove from Library?", "从图库删除照片？", "從圖庫刪除照片？"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
               presenting: deleting) { id in
            Button(T("Cancel", "取消", "取消"), role: .cancel) { deleting = nil }
            Button(T("Delete", "删除", "刪除"), role: .destructive) { document.remove(id); deleting = nil }
        } message: { _ in
            Text(T("This deletes the in-app originals and edit records. It cannot be undone; Photos and the sources you imported from are not affected.", "将删除应用内原文件和编辑记录。此操作无法撤销，系统相册和导入来源不受影响。", "將刪除應用內原檔案和編輯記錄。此操作無法還原，系統相簿和導入來源不受影響。"))
        }
        .sheet(item: $copyRequest) { request in MobileCopySettingsSheet(document: document, request: request) }
    }

    private func requestCopy(_ photo: MobilePhoto) {
        document.endParameterInteraction()
        // Capture now. Cancel leaves the previous clipboard untouched.
        copyRequest = MobileSettingsCopyRequest(source: photo, groups: document.copyGroups)
    }

    private var photoToolbar: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(document.current?.name ?? T("Photo", "照片", "照片")).font(EditorDesign.caption).lineLimit(1).truncationMode(.middle)
                if let summary = document.current?.exifSummary, !summary.isEmpty {
                    Text(summary).font(EditorDesign.instrument).foregroundStyle(.secondary).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button(T("All ratings", "全部星级", "全部星級")) { minimumRating = 0 }
                ForEach(1...5, id: \.self) { rating in Button(T("At least \(rating) stars", "至少 \(rating) 星", "至少 \(rating) 星")) { minimumRating = rating } }
            } label: {
                ToolbarGlyph(symbol: "star.fill", size: EditorDesign.filmstripGlyphSize)
                    .foregroundStyle(minimumRating > 0 ? MobileStyle.accent : .white.opacity(0.75))
                    .frame(width: 44, height: 44)
                    .overlay(alignment: .bottomTrailing) {
                        if minimumRating > 0 {
                            Text("\(minimumRating)").font(EditorDesign.badge)
                                .foregroundStyle(MobileStyle.accent)
                                .padding(.trailing, 5).padding(.bottom, 3)
                        }
                    }
            }.accessibilityLabel(T("Filter by rating", "按星级筛选", "按星級篩選"))
                .accessibilityValue(minimumRating == 0 ? T("All ratings", "全部星级", "全部星級") : T("At least \(minimumRating) stars", "至少 \(minimumRating) 星", "至少 \(minimumRating) 星"))
                .accessibilityIdentifier("filmstrip.rating-filter")
            Menu {
                Button(T("All flags", "全部旗标", "全部旗標")) { flagFilter = "all" }
                Button(T("Unflagged", "无旗标", "無旗標")) { flagFilter = "none" }
                Button(T("Pick", "保留", "保留")) { flagFilter = "pick" }
                Button(T("Reject", "淘汰", "淘汰")) { flagFilter = "reject" }
            } label: {
                ToolbarGlyph(symbol: flagFilter == "pick" ? "flag.fill" : flagFilter == "reject" ? "flag.slash.fill" : "flag", size: EditorDesign.filmstripGlyphSize)
                    .foregroundStyle(flagFilter != "all" ? MobileStyle.accent : .white.opacity(0.75))
                    .frame(width: 44, height: 44)
                    .overlay(alignment: .bottomTrailing) {
                        if flagFilter == "none" {
                            Text(T("None", "无", "無")).font(EditorDesign.badge).foregroundStyle(MobileStyle.accent)
                                .padding(.trailing, 3).padding(.bottom, 3)
                        }
                    }
            }.accessibilityLabel(T("Filter by flag", "按旗标筛选", "按旗標篩選"))
                .accessibilityValue(flagFilter == "all" ? T("All flags", "全部旗标", "全部旗標") : flagFilter == "pick" ? T("Pick", "保留", "保留") : flagFilter == "reject" ? T("Reject", "淘汰", "淘汰") : T("Unflagged", "无旗标", "無旗標"))
                .accessibilityIdentifier("filmstrip.flag-filter")
            ChromeButton(title: T("Copy Parameters", "复制参数", "複製參數"), symbol: "doc.on.doc", enabled: document.current != nil, glyphSize: EditorDesign.filmstripGlyphSize) {
                if let photo = document.current { requestCopy(photo) }
            }.accessibilityIdentifier("clipboard.copy")
            ChromeButton(title: T("Paste Parameters", "粘贴参数", "貼上參數"), symbol: "doc.on.clipboard", enabled: document.settingsClipboard != nil && document.current != nil, glyphSize: EditorDesign.filmstripGlyphSize) {
                if let id = document.selection { document.pasteSettings(to: [id]) }
            }.accessibilityIdentifier("clipboard.paste")
            if allowsSelection {
                ChromeButton(title: T("Select photos", "选择多张照片", "選擇多張照片"), symbol: "checkmark.circle", enabled: !photos.isEmpty, glyphSize: EditorDesign.filmstripGlyphSize) {
                    document.beginPhotoSelection()
                }.accessibilityIdentifier("filmstrip.select")
            }
        }
    }

    private var selectionToolbar: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                Text(T("\(document.selectedPhotoIDs.count) selected", "已选 \(document.selectedPhotoIDs.count) 张", "已選 \(document.selectedPhotoIDs.count) 張")).font(EditorDesign.label)
                if let clip = document.settingsClipboard {
                    Text(clip.summary).font(EditorDesign.instrument).foregroundStyle(.secondary).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine).accessibilityIdentifier("filmstrip.selection-count")
            Button(document.selectedPhotoIDs.count == photos.count && !photos.isEmpty ? T("Clear", "清除", "清除") : T("Select all", "全选", "全選")) {
                if document.selectedPhotoIDs.count == photos.count { document.clearPhotoSelection() }
                else { document.selectAllPhotos(photos.map(\.id)) }
            }.font(EditorDesign.label).frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("filmstrip.select-all")
            Button(T("Paste to \(document.selectedPhotoIDs.count)", "粘贴到 \(document.selectedPhotoIDs.count) 张", "貼到 \(document.selectedPhotoIDs.count) 張")) { document.pasteSettings() }
                .font(EditorDesign.label).frame(minHeight: 44)
                .disabled(document.settingsClipboard == nil || document.selectedPhotoIDs.isEmpty)
                .accessibilityIdentifier("clipboard.paste-selected")
            Button(T("Done", "完成", "完成")) { document.endPhotoSelection() }
                .font(EditorDesign.label).frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("filmstrip.done")
        }
    }
}

struct MobileCopySettingsSheet: View {
    @Bindable var document: MobileDocument
    let request: MobileSettingsCopyRequest
    let applyIDs: Set<UUID>?
    @State private var groups: Set<MobileClipboardGroup>
    @Environment(\.dismiss) private var dismiss

    init(document: MobileDocument, request: MobileSettingsCopyRequest, applyIDs: Set<UUID>? = nil) {
        self.document = document; self.request = request; self.applyIDs = applyIDs
        _groups = State(initialValue: request.groups)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(applyIDs.map { T("Applies the selected edits from \(request.source.name) to \($0.count) photos in this batch.", "从 \(request.source.name) 应用所选编辑项到本批 \($0.count) 张照片。", "從 \(request.source.name) 應用所選編輯項到本批 \($0.count) 張照片。") } ?? T("Copies the selected parameters from \(request.source.name). Pasting applies these groups directly.", "从 \(request.source.name) 复制所选参数。粘贴时直接应用这些分区。", "從 \(request.source.name) 複製所選參數。貼上時直接應用這些分區。")).font(.subheadline)
                    HStack {
                        Button(T("Select all", "全选", "全選")) { groups = Set(MobileClipboardGroup.allCases) }
                        Spacer()
                        Button(T("Clear", "清除", "清除")) { groups = [] }
                    }.buttonStyle(.borderless)
                }
                Section(T("Parameter scope", "参数范围", "參數範圍")) {
                    ForEach(MobileClipboardGroup.allCases) { group in
                        Toggle(isOn: Binding(get: { groups.contains(group) }, set: { selected in
                            if selected { groups.insert(group) } else { groups.remove(group) }
                        })) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.title)
                                Text(group.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }.tint(MobileStyle.accent).accessibilityIdentifier("clipboard.group." + group.id)
                    }
                }
            }
            .mobilePageBackground()
            .navigationTitle(applyIDs == nil ? T("Copy Edits", "复制编辑项", "複製編輯項") : T("Apply Edits to Batch", "批量应用编辑项", "批量應用編輯項")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(T("Cancel", "取消", "取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(applyIDs == nil ? T("Copy", "复制", "複製") : T("Apply", "应用", "應用")) {
                        document.copySettings(request.source, groups: groups)
                        if let applyIDs { document.pasteSettings(to: applyIDs) }
                        dismiss()
                    }
                        .disabled(groups.isEmpty || document.isInteractionLocked)
                        .accessibilityIdentifier("clipboard.confirm-copy")
                }
            }
        }.tint(.primary).presentationDetents([.large]).presentationBackground(MobileStyle.canvas).preferredColorScheme(.dark)
    }
}
