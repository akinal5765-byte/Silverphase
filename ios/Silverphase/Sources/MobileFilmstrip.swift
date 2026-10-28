import SwiftUI

struct MobileFilmstrip: View {
    @Bindable var document: MobileDocument
    let photos: [MobilePhoto]
    @Binding var minimumRating: Int
    @Binding var flagFilter: String
    @State private var copyRequest: MobileSettingsCopyRequest?

    var body: some View {
        VStack(spacing: EditorDesign.browserGap) {
            Group {
                if document.isSelectingPhotos { selectionToolbar }
                else { photoToolbar }
            }
            .padding(.leading, 12).padding(.trailing, 4).frame(height: 44)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(photos) { photo in
                        Button {
                            if document.isSelectingPhotos { document.togglePhotoSelection(photo.id) }
                            else { document.select(photo.id) }
                        } label: {
                            BrowserCard(title: nil,
                                        subtitle: (photo.rating > 0 ? String(repeating: "★", count: photo.rating) : "未评分") + (photo.flag == "pick" ? " · 保留" : photo.flag == "reject" ? " · 淘汰" : ""),
                                        width: 80, selected: photo.id == document.selection) {
                                FilmstripThumbnail(url: document.url(for: photo))
                                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.15))
                            }
                            .overlay(alignment: .topTrailing) {
                                if document.isSelectingPhotos {
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
                        .accessibilityValue(document.isSelectingPhotos ? (document.selectedPhotoIDs.contains(photo.id) ? "已选择" : "未选择") : (photo.id == document.selection ? "正在预览" : ""))
                        .contextMenu {
                            if document.isSelectingPhotos {
                                Button("粘贴到所选 \(document.selectedPhotoIDs.count) 张", systemImage: "doc.on.clipboard") { document.pasteSettings() }
                                    .disabled(document.settingsClipboard == nil || document.selectedPhotoIDs.isEmpty)
                                Button("取消选择", systemImage: "xmark") { document.endPhotoSelection() }
                            } else {
                                Button("选择多张", systemImage: "checkmark.circle") { document.beginPhotoSelection(photo.id) }
                                Menu("评分", systemImage: "star") {
                                    ForEach(0...5, id: \.self) { rating in Button(rating == 0 ? "清除评分" : "\(rating) 星") { document.mark(photo.id, rating: rating) } }
                                }
                                Button("保留", systemImage: "flag.fill") { document.mark(photo.id, flag: "pick") }
                                Button("淘汰", systemImage: "flag.slash") { document.mark(photo.id, flag: "reject") }
                                Button("清除旗标") { document.mark(photo.id, flag: "none") }
                                Divider()
                                Button("复制参数", systemImage: "doc.on.doc") { requestCopy(photo) }
                                Button("粘贴参数", systemImage: "doc.on.clipboard") { document.pasteSettings(to: [photo.id]) }
                                    .disabled(document.settingsClipboard == nil)
                                Button("从本次会话移除", systemImage: "minus.circle", role: .destructive) { document.remove(photo.id) }
                            }
                        }
                    }
                    if photos.isEmpty { Text("没有符合筛选条件的照片").font(.system(size: 12)).foregroundStyle(.secondary).padding() }
                }.padding(.horizontal, EditorDesign.cardInset)
            }.frame(height: EditorDesign.cardHeight).clipped()
        }
        .padding(.vertical, EditorDesign.cardInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: photos.map(\.id)) { _, ids in document.restrictPhotoSelection(to: ids) }
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
                Text(document.current?.name ?? "照片").font(EditorDesign.caption).lineLimit(1).truncationMode(.middle)
                if let summary = document.current?.exifSummary, !summary.isEmpty {
                    Text(summary).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button("全部星级") { minimumRating = 0 }
                ForEach(1...5, id: \.self) { rating in Button("至少 \(rating) 星") { minimumRating = rating } }
            } label: {
                ToolbarGlyph(symbol: "star.fill", size: EditorDesign.filmstripGlyphSize)
                    .foregroundStyle(minimumRating > 0 ? MobileStyle.accent : .white.opacity(0.75))
                    .frame(width: 44, height: 44)
                    .overlay(alignment: .bottomTrailing) {
                        if minimumRating > 0 {
                            Text("\(minimumRating)").font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(MobileStyle.accent)
                                .padding(.trailing, 5).padding(.bottom, 3)
                        }
                    }
            }.accessibilityLabel("按星级筛选")
                .accessibilityValue(minimumRating == 0 ? "全部星级" : "至少 \(minimumRating) 星")
                .accessibilityIdentifier("filmstrip.rating-filter")
            Menu {
                Button("全部旗标") { flagFilter = "all" }
                Button("无旗标") { flagFilter = "none" }
                Button("保留") { flagFilter = "pick" }
                Button("淘汰") { flagFilter = "reject" }
            } label: {
                ToolbarGlyph(symbol: flagFilter == "pick" ? "flag.fill" : flagFilter == "reject" ? "flag.slash.fill" : "flag", size: EditorDesign.filmstripGlyphSize)
                    .foregroundStyle(flagFilter != "all" ? MobileStyle.accent : .white.opacity(0.75))
                    .frame(width: 44, height: 44)
                    .overlay(alignment: .bottomTrailing) {
                        if flagFilter == "none" {
                            Text("无").font(.system(size: 9, weight: .semibold)).foregroundStyle(MobileStyle.accent)
                                .padding(.trailing, 3).padding(.bottom, 3)
                        }
                    }
            }.accessibilityLabel("按旗标筛选")
                .accessibilityValue(flagFilter == "all" ? "全部旗标" : flagFilter == "pick" ? "保留" : flagFilter == "reject" ? "淘汰" : "无旗标")
                .accessibilityIdentifier("filmstrip.flag-filter")
            ChromeButton(title: "复制参数", symbol: "doc.on.doc", enabled: document.current != nil, glyphSize: EditorDesign.filmstripGlyphSize) {
                if let photo = document.current { requestCopy(photo) }
            }.accessibilityIdentifier("clipboard.copy")
            ChromeButton(title: "粘贴参数", symbol: "doc.on.clipboard", enabled: document.settingsClipboard != nil && document.current != nil, glyphSize: EditorDesign.filmstripGlyphSize) { document.pasteSettings() }
                .accessibilityIdentifier("clipboard.paste")
            ChromeButton(title: "选择多张照片", symbol: "checkmark.circle", enabled: !photos.isEmpty, glyphSize: EditorDesign.filmstripGlyphSize) {
                document.beginPhotoSelection()
            }.accessibilityIdentifier("filmstrip.select")
        }
    }

    private var selectionToolbar: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                Text("已选 \(document.selectedPhotoIDs.count) 张").font(EditorDesign.label)
                if let clip = document.settingsClipboard {
                    Text(clip.summary).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine).accessibilityIdentifier("filmstrip.selection-count")
            Button(document.selectedPhotoIDs.count == photos.count && !photos.isEmpty ? "清除" : "全选") {
                if document.selectedPhotoIDs.count == photos.count { document.clearPhotoSelection() }
                else { document.selectAllPhotos(photos.map(\.id)) }
            }.font(EditorDesign.label).frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("filmstrip.select-all")
            Button("粘贴到 \(document.selectedPhotoIDs.count) 张") { document.pasteSettings() }
                .font(EditorDesign.label).frame(minHeight: 44)
                .disabled(document.settingsClipboard == nil || document.selectedPhotoIDs.isEmpty)
                .accessibilityIdentifier("clipboard.paste-selected")
            Button("完成") { document.endPhotoSelection() }
                .font(EditorDesign.label).frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("filmstrip.done")
        }
    }
}

private struct MobileCopySettingsSheet: View {
    @Bindable var document: MobileDocument
    let request: MobileSettingsCopyRequest
    @State private var groups: Set<MobileClipboardGroup>
    @Environment(\.dismiss) private var dismiss

    init(document: MobileDocument, request: MobileSettingsCopyRequest) {
        self.document = document; self.request = request
        _groups = State(initialValue: request.groups)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("从 \(request.source.name) 复制所选参数。粘贴时直接应用这些分区。").font(.subheadline)
                    HStack {
                        Button("全选") { groups = Set(MobileClipboardGroup.allCases) }
                        Spacer()
                        Button("清除") { groups = [] }
                    }.buttonStyle(.borderless)
                }
                Section("参数范围") {
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
            .navigationTitle("复制参数").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("复制") { document.copySettings(request.source, groups: groups); dismiss() }
                        .disabled(groups.isEmpty || document.isInteractionLocked)
                        .accessibilityIdentifier("clipboard.confirm-copy")
                }
            }
        }.tint(.primary).presentationDetents([.large]).preferredColorScheme(.dark)
    }
}
