import SwiftUI
import UniformTypeIdentifiers

struct MobileLibrary: View {
    @Bindable var document: MobileDocument
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var searchFocused: Bool
    @AppStorage("mobile.library.squareThumbnails") private var squareThumbnails = true
    @AppStorage("mobile.library.thumbnailSize") private var thumbnailSize = LibraryThumbnailSize.medium
    @AppStorage("mobile.library.newestFirst") private var newestFirst = false
    @State private var phoneWindowSize = CGSize.zero
    @State private var phoneHingeClosed: Bool?
    @State private var showingSearch = false
    @State private var rawOnly = false
    @State private var photoInfo: MobilePhoto?
    @State private var minimumRating = 0
    @State private var flagFilter = "all"
    @State private var search = ""
    @State private var pickingPhotos = false
    @State private var importing = false
    @State private var showingCamera = false
    @State private var cameraReturnPhotoID: UUID?
    @State private var visiblePhotoID: UUID?
    @State private var legacyPhotoDates: [UUID: (date: Date?, day: Int?)] = [:]
    @State private var settings: MobilePagePresentation?
    @State private var about: MobilePagePresentation?
    @State private var editor: LibraryEditorRequest?
    @State private var exportRequest: LibraryExportRequest?
    @State private var copyRequest: MobileSettingsCopyRequest?
    @State private var deleting: Set<UUID> = []
    @State private var cellFrames: [UUID: CGRect] = [:]

    private var filtered: [MobilePhoto] {
        document.photos.filter {
            $0.rating >= minimumRating && (flagFilter == "all" || $0.flag == flagFilter) &&
            (!rawOnly || isRAW($0)) && (search.isEmpty || $0.name.localizedStandardContains(search))
        }.sorted {
            let lhs = $0.libraryDate ?? legacyPhotoDates[$0.id]?.date ?? .distantPast
            let rhs = $1.libraryDate ?? legacyPhotoDates[$1.id]?.date ?? .distantPast
            return newestFirst ? lhs > rhs : lhs < rhs
        }
    }
    private var selected: [MobilePhoto] { document.photos.filter { document.selectedPhotoIDs.contains($0.id) } }
    private var headerPhoto: MobilePhoto? {
        let photos = filtered
        return photos.first { $0.id == visiblePhotoID } ?? photos.first
    }
    private var legacyPhotoIDs: [UUID] {
        document.photos.filter { $0.libraryDate == nil }.map(\.id)
    }
    private var canHandleCameraShortcut: Bool {
        MobileCameraLaunch.shared.pending && scenePhase == .active && !document.isInteractionLocked &&
            document.libraryReadError == nil && (editor != nil || !document.editorVisible) &&
            !pickingPhotos && !importing && settings == nil && about == nil && exportRequest == nil &&
            copyRequest == nil && photoInfo == nil && deleting.isEmpty
    }
    private var newestPhoto: MobilePhoto? {
        document.photos.reversed().max {
            ($0.libraryDate ?? legacyPhotoDates[$0.id]?.date ?? .distantPast) <
            ($1.libraryDate ?? legacyPhotoDates[$1.id]?.date ?? .distantPast)
        }
    }

    private func cameraThumbnail(for photo: MobilePhoto) -> URL {
        let preview = document.libraryPreviewURL(photo)
        return FileManager.default.fileExists(atPath: preview.path) ? preview : document.url(for: photo)
    }

    var body: some View {
        let photos = filtered
        NavigationStack {
            ScrollView {
                if let issue = document.libraryReadError {
                    ContentUnavailableView(T("The library cannot be read right now", "图库暂时无法读取", "圖庫暫時無法讀取"), systemImage: "externaldrive.badge.exclamationmark", description: Text(issue + T("\nOriginals and records are safe. Restart and try again.",
                                                          "\n原文件与记录已保留，请稍后重启重试。",
                                                          "\n原檔案與記錄已保留，請稍後重新啟動再試。")))
                        .padding(.top, 80)
                } else if document.photos.isEmpty {
                    ContentUnavailableView {
                        Label(T("Library", "图库", "圖庫"), systemImage: "photo.on.rectangle.angled")
                    } description: {
                        Text(T("Imported photos and edits are saved on this device — come back to them any time.", "导入照片与编辑会自动保存在此设备，随时回来继续。", "導入照片與編輯會自動儲存在此設備，隨時回來繼續。"))
                    } actions: {
                        Button(T("Import from Photos", "从照片导入", "從照片導入"), systemImage: "plus") { pickingPhotos = true }
                    }.padding(.top, 80)
                } else if photos.isEmpty {
                    if search.isEmpty {
                        ContentUnavailableView(T("No photos match these filters", "没有符合筛选条件的照片", "沒有符合篩選條件的照片"), systemImage: "line.3.horizontal.decrease.circle")
                    } else {
                        ContentUnavailableView.search(text: search)
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: thumbnailSize.minimumWidth(regular: horizontalSizeClass == .regular)),
                                                     spacing: EditorDesign.unit, alignment: .top)], spacing: EditorDesign.unit) {
                        ForEach(photos) { photo in photoCell(photo) }
                    }
                        .scrollTargetLayout()
                        .padding(.horizontal, EditorDesign.unit)
                        .coordinateSpace(name: "library.grid")
                        .onPreferenceChange(LibraryCellFrames.self) { cellFrames = $0 }
                        .background {
                            LibrarySelectionGesture(enabled: document.isSelectingPhotos && !document.isInteractionLocked,
                                ids: photos.map(\.id), frames: cellFrames, selection: document.selectedPhotoIDs,
                                commit: { document.selectAllPhotos(Array($0)) })
                        }
                }
            }
            .scrollPosition(id: $visiblePhotoID, anchor: .top)
            .background(MobileStyle.canvas.ignoresSafeArea())
            .navigationTitle(document.isSelectingPhotos ? T("\(selected.count) selected", "已选 \(selected.count) 张", "已選 \(selected.count) 張") : "")
            .navigationBarTitleDisplayMode(.inline)
            .modifier(LibraryHeaderBar { libraryTopBar })
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if usesProminentCamera && !document.isSelectingPhotos && !searchFocused {
                    cameraButton(prominent: true).padding(.vertical, EditorDesign.gutter)
                }
            }
            .toolbar { libraryToolbar }
            .disabled(document.isInteractionLocked)
        }
        .background {
            if UIDevice.current.userInterfaceIdiom == .phone {
                ProcessBarGeometryProbe(windowSizeChanged: { phoneWindowSize = $0 }, hingeChanged: { phoneHingeClosed = $0 })
                    .allowsHitTesting(false)
            }
        }
        .tint(.primary)
        .background(MobileStyle.canvas.ignoresSafeArea())
        .task(id: legacyPhotoIDs) { await loadLegacyPhotoDates() }
        .task(id: canHandleCameraShortcut) {
            guard canHandleCameraShortcut else { return }
            if editor != nil {
                editor = nil
            } else {
                MobileCameraLaunch.shared.pending = false
                document.endPhotoSelection()
                searchFocused = false
                showingCamera = true
            }
        }
        .onChange(of: photos.map(\.id)) { _, ids in document.restrictPhotoSelection(to: ids) }
        .fullScreenCover(isPresented: $showingCamera, onDismiss: {
            if let cameraReturnPhotoID {
                visiblePhotoID = cameraReturnPhotoID
                self.cameraReturnPhotoID = nil
            }
        }) {
            MobileCameraView(initialHingeClosed: phoneHingeClosed, libraryThumbnail: newestPhoto.map(cameraThumbnail(for:)),
                             mirrorsFrontCamera: document.preferences.values.mirrorsFrontCamera,
                             prefersRAW: Binding(get: { document.preferences.values.prefersRAW },
                                                 set: { document.preferences.values.prefersRAW = $0 }),
                             prefers12MP: Binding(get: { document.preferences.values.prefers12MP },
                                                  set: { document.preferences.values.prefers12MP = $0 }),
                             importPhoto: { url, film, recipe in
                let previous = document.selection
                let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true).timeSeparator(.omitted))
                let name = "Silverphase-" + stamp + "." + url.pathExtension
                await document.importFiles([url], displayNames: [url: name], capturedFilm: film, capturedRecipes: [url: recipe], announceSuccess: false).value
                guard document.error == nil, let photo = document.current, photo.id != previous else {
                    throw MobileFailure.message(document.error ?? T("The captured photo could not be saved", "无法保存拍摄的照片", "無法儲存拍攝的照片"))
                }
                return photo
            }, developPhoto: { photo, animate in
                try await document.developCameraPhoto(photo, animate: animate)
            }, savePhoto: { photo in
                try await document.saveCameraPhotoToPhotos(photo)
            }, returnToLibrary: { id in
                if !filtered.contains(where: { $0.id == id }) {
                    rawOnly = false
                    minimumRating = 0
                    flagFilter = "all"
                    search = ""
                    showingSearch = false
                }
                cameraReturnPhotoID = id
                showingCamera = false
            })
        }
        .fullScreenCover(item: $editor, onDismiss: { document.closeEditor() }) { request in
            MobileEditor(document: document, batchIDs: request.ids, returnToLibrary: { editor = nil })
                .task {
                    document.openEditor(request.firstID, ids: request.ids ?? [request.firstID])
                }
        }
        .sheet(item: $copyRequest) { MobileCopySettingsSheet(document: document, request: $0) }
        .sheet(item: $exportRequest) { request in
            NavigationStack {
                ScrollView { MobileExportPanel(document: document, filteredIDs: request.ids, fixedIDs: request.ids) }
                    .mobilePageBackground()
                    .navigationTitle(T("Export Photos", "导出成片", "匯出成片")).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(T("Done", "完成", "完成")) { exportRequest = nil }.disabled(document.isInteractionLocked).accessibilityIdentifier("library.export-done") } }
                    .disabled(document.isInteractionLocked)
                    .overlay { notification(covered: document.exported != nil) }
                    .sheet(isPresented: shareBinding) { shareSheet }
            }
            .presentationBackground(MobileStyle.canvas)
            .interactiveDismissDisabled(document.isInteractionLocked)
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
                    if skipped > 0 { document.postNotification(T("Skipped \(skipped) unsupported or unreadable photos", "已跳过 \(skipped) 张不支持或无法读取的照片", "已跳過 \(skipped) 張不支援或無法讀取的照片"), style: .warning) }
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
        .mobileInformationPages(document: document, settings: $settings, about: $about)
        .sheet(item: $photoInfo) { photo in
            NavigationStack {
                Form {
                    LabeledContent(T("File name", "文件名", "檔案名"), value: photo.name)
                    LibraryFormatBadge(identifier: photo.sourceTypeIdentifier, original: document.url(for: photo))
                    if !photo.exifSummary.isEmpty { Text(photo.exifSummary).foregroundStyle(.secondary) }
                }
                .mobilePageBackground()
                .navigationTitle(T("Photo Info", "照片信息", "照片資訊"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button(T("Done", "完成", "完成")) { photoInfo = nil } }
                }
            }
            .presentationBackground(MobileStyle.canvas)
        }
        .alert(T("Remove from Library?", "从图库删除照片？", "從圖庫刪除照片？"), isPresented: Binding(get: { !deleting.isEmpty }, set: { if !$0 { deleting = [] } }),
               presenting: deleting.isEmpty ? nil : deleting) { ids in
            Button(T("Cancel", "取消", "取消"), role: .cancel) { deleting = [] }
            Button(T("Delete", "删除", "刪除"), role: .destructive) { document.removePhotos(ids); deleting = [] }
        } message: { ids in
            Text(T("This deletes the in-app originals and edit records for \(ids.count) photos. It cannot be undone; Photos and the sources you imported from are not affected.", "将删除 \(ids.count) 张照片的应用内原文件和编辑记录。此操作无法撤销，系统相册和导入来源不受影响。", "將刪除 \(ids.count) 張照片的應用內原檔案和編輯記錄。此操作無法還原，系統相簿和導入來源不受影響。"))
        }
        .overlay { notification(covered: showingCamera || editor != nil || exportRequest != nil || pickingPhotos || importing || settings != nil || about != nil || copyRequest != nil || photoInfo != nil) }
    }
    @ViewBuilder private var libraryTopBar: some View {
        if !document.isSelectingPhotos {
            VStack(alignment: .leading, spacing: EditorDesign.unit) {
                libraryHeader
                if showingSearch { searchBar }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var libraryHeader: some View {
        let photo = headerPhoto
        let day = photo.flatMap { legacyPhotoDates[$0.id]?.day ?? $0.libraryDay }
        return VStack(alignment: .leading, spacing: 2) {
            Text(T("Library", "图库", "圖庫"))
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            if photo != nil {
                Text(libraryDateText(day))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .modifier(AdjustmentNumberTransition(value: day.map(Double.init), fractionDigits: 0))
                    .accessibilityIdentifier("library.visible-date")
            }
        }
        .padding(.horizontal, EditorDesign.contentInset)
        .padding(.vertical, EditorDesign.unit)
    }

    private func libraryDateText(_ day: Int?) -> String {
        guard let day else { return T("Date unknown", "日期未知", "日期未知") }
        return T("\(day / 10000)-\(day / 100 % 100)-\(day % 100)", "\(day / 10000)年\(day / 100 % 100)月\(day % 100)日", "\(day / 10000)年\(day / 100 % 100)月\(day % 100)日")
    }

    private func loadLegacyPhotoDates() async {
        let originals = document.photos
            .filter { $0.libraryDate == nil && legacyPhotoDates[$0.id] == nil }
            .map { (id: $0.id, url: document.url(for: $0), day: $0.libraryDay) }
        guard !originals.isEmpty else { return }
        let reader = Task.detached(priority: .utility) {
            var dates: [UUID: (date: Date?, day: Int?)] = [:]
            for original in originals {
                guard !Task.isCancelled else { break }
                let result = autoreleasepool { MobileImageMetadata.libraryDate(forOriginal: original.url) }
                dates[original.id] = (result.date ?? original.day.flatMap(MobileImageMetadata.date(forDay:)),
                                      result.day ?? original.day)
            }
            return dates
        }
        let dates = await withTaskCancellationHandler {
            await reader.value
        } onCancel: {
            reader.cancel()
        }
        guard !Task.isCancelled else { return }
        legacyPhotoDates.merge(dates, uniquingKeysWith: { _, new in new })
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(T("Search file names", "搜索文件名", "搜尋檔案名"), text: $search)
                .focused($searchFocused)
                .submitLabel(.search)
            ChromeButton(title: T("Close search", "关闭搜索", "關閉搜尋"), symbol: "xmark") {
                search = ""
                showingSearch = false
            }
        }
        .padding(.leading, EditorDesign.contentInset)
        .onAppear { searchFocused = true }
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
        guard !document.isInteractionLocked, let first = photos.first else { return }
        editor = LibraryEditorRequest(firstID: first.id, ids: photos.count > 1 ? photos.map(\.id) : nil)
    }
    private func requestCopy(_ photo: MobilePhoto) {
        document.endParameterInteraction()
        copyRequest = MobileSettingsCopyRequest(source: photo, groups: document.copyGroups)
    }
    private func photoCell(_ photo: MobilePhoto) -> some View {
        let preview = document.libraryPreviewURL(photo)
        let hasPreview = FileManager.default.fileExists(atPath: preview.path)
        let sourceAspect = photo.sourceAspect.isFinite && photo.sourceAspect > 0 ? photo.sourceAspect : 1
        let size = CGSize(width: sourceAspect * 1000, height: 1000)
        let displayedSize = hasPreview ? photo.geometry.outputSize(for: size) : size
        let aspect = squareThumbnails ? 1 : displayedSize.width / max(1, displayedSize.height)
        return Button {
            if document.isSelectingPhotos { document.togglePhotoSelection(photo.id) }
            else { open([photo]) }
        } label: {
            Color.clear.aspectRatio(1, contentMode: .fit)
                .overlay {
                    GeometryReader { tile in
                        let side = tile.size.width
                        FilmstripThumbnail(url: hasPreview ? preview : document.url(for: photo), fillsFrame: squareThumbnails,
                                           version: document.libraryPreviewVersions[photo.id, default: 0])
                            .frame(width: side * min(1, aspect), height: side / max(1, aspect))
                            .background(MobileStyle.canvas)
                            .clipShape(.rect(cornerRadius: squareThumbnails ? 0 : EditorDesign.artworkRadius))
                            .overlay(alignment: .topTrailing) {
                                if document.isSelectingPhotos {
                                    let isSelected = document.selectedPhotoIDs.contains(photo.id)
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.title3).foregroundStyle(isSelected ? MobileStyle.accent : .white)
                                        .background(.black.opacity(0.65), in: Circle()).padding(6)
                                }
                            }
                            .overlay(alignment: .bottomLeading) {
                                HStack(spacing: EditorDesign.unit) {
                                    if isRAW(photo) { Text("RAW") }
                                    if photo.rating > 0 {
                                        Label("\(photo.rating)", systemImage: "star.fill").foregroundStyle(MobileStyle.accent)
                                    }
                                    if photo.flag != "none" {
                                        Image(systemName: photo.flag == "pick" ? "flag.fill" : "flag.slash")
                                    }
                                }
                                .font(EditorDesign.badge)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 3)
                                .background {
                                    if isRAW(photo) || photo.rating > 0 || photo.flag != "none" {
                                        RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.7))
                                    }
                                }
                                .padding(EditorDesign.unit)
                                .accessibilityHidden(true)
                            }
                            .frame(width: tile.size.width, height: tile.size.height)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if document.isSelectingPhotos {
                GeometryReader { proxy in
                    Color.clear.preference(key: LibraryCellFrames.self, value: [photo.id: proxy.frame(in: .named("library.grid"))])
                }
            }
        }
        .accessibilityLabel(photo.name)
        .accessibilityValue(document.selectedPhotoIDs.contains(photo.id) ? T("Selected", "已选择", "已選擇") : T("Not selected", "未选择", "未選擇"))
        .accessibilityIdentifier("library.photo." + photo.name)
        .contextMenu {
            Button(T("Photo Info", "照片信息", "照片資訊"), systemImage: "info.circle") { photoInfo = photo }
            Button(T("Edit", "编辑", "編輯"), systemImage: "slider.horizontal.3") { open([photo]) }
            Button(T("Select multiple", "选择多张", "選擇多張"), systemImage: "checkmark.circle") { document.beginPhotoSelection(photo.id) }
            Button(T("Copy edits", "复制编辑项", "複製編輯項"), systemImage: "doc.on.doc") { requestCopy(photo) }
            Button(T("Paste edits", "粘贴编辑项", "貼上編輯項"), systemImage: "doc.on.clipboard") { document.pasteSettings(to: [photo.id]) }.disabled(document.settingsClipboard == nil)
            Button(T("Export", "导出", "匯出"), systemImage: "square.and.arrow.up") { exportRequest = LibraryExportRequest(ids: [photo.id]) }
            ratingMenu(ids: [photo.id])
            Button(T("Remove from Library", "从图库删除", "從圖庫刪除"), systemImage: "trash", role: .destructive) { deleting = [photo.id] }
        }
    }
    private var usesProminentCamera: Bool {
        UIDevice.current.userInterfaceIdiom == .phone && phoneHingeClosed != true &&
            phoneWindowSize.height >= phoneWindowSize.width
    }

    private var verticalToolbar: Bool {
        if #available(iOS 27.1, *) { UIDevice.current.userInterfaceIdiom == .phone && !usesProminentCamera }
        else { false }
    }

    private func cameraButton(prominent: Bool = false) -> some View {
        Button(T("Take Photo", "拍照", "拍照"), systemImage: "camera") { showingCamera = true }
            .labelStyle(.iconOnly)
            .buttonStyle(LibraryCameraButtonStyle(prominent: prominent))
            .accessibilityIdentifier("library.camera")
            .disabled(document.libraryReadError != nil)
    }

    private func isRAW(_ photo: MobilePhoto) -> Bool {
        let type = photo.sourceTypeIdentifier.flatMap(UTType.init)
            ?? UTType(filenameExtension: URL(fileURLWithPath: photo.filename).pathExtension)
        return type?.conforms(to: .rawImage) == true
    }

    private var hasFilters: Bool { rawOnly || minimumRating > 0 || flagFilter != "all" }

    @ToolbarContentBuilder private var libraryToolbar: some ToolbarContent {
        if !document.isSelectingPhotos {
            MobileLibraryToolbarItem(placement: .topBarLeading, vertical: verticalToolbar) {
                Menu {
                    Button(T("Import from Photos", "从照片导入", "從照片導入"), systemImage: "photo.on.rectangle") { pickingPhotos = true }
                    Button(T("Import from Files", "从文件导入", "從檔案導入"), systemImage: "folder") { importing = true }
                } label: {
                    Label(T("Import", "导入", "導入"), systemImage: "plus")
                }
                .accessibilityIdentifier("library.import")
                .disabled(document.libraryReadError != nil)
            }
        }
        MobileLibraryToolbarItem(vertical: verticalToolbar) {
            Button {
                if document.isSelectingPhotos { document.endPhotoSelection() }
                else { document.beginPhotoSelection() }
            } label: {
                Label(document.isSelectingPhotos ? T("Done", "完成", "完成") : T("Select", "选择", "選擇"),
                      systemImage: document.isSelectingPhotos ? "checkmark" : "checkmark.circle")
            }
            .disabled(!document.isSelectingPhotos && filtered.isEmpty)
            .accessibilityIdentifier("library.select")
        }
        if document.isSelectingPhotos {
            MobileLibraryToolbarItem(vertical: verticalToolbar) {
                let all = selected.count == filtered.count && !filtered.isEmpty
                Button {
                    if all { document.clearPhotoSelection() }
                    else { document.selectAllPhotos(filtered.map(\.id)) }
                } label: {
                    Label(all ? T("Clear selection", "清空选择", "清空選擇") : T("Select all", "全选", "全選"), systemImage: all ? "xmark.square" : "checkmark.rectangle.stack")
                }
                .disabled(filtered.isEmpty).accessibilityIdentifier("library.select-all")
            }
            if !selected.isEmpty {
                ToolbarItemGroup(placement: .bottomBar) { selectionActions }
            }
        } else {
            MobileLibraryToolbarItem(vertical: verticalToolbar) {
                Menu {
                    Section {
                        Menu(T("Sort by capture date", "拍摄时间排序", "拍攝時間排序"), systemImage: "arrow.up.arrow.down") {
                            filterOption(T("Oldest first", "正序（最早在前）", "正序（最早在前）"), selected: !newestFirst) { newestFirst = false }
                            filterOption(T("Newest first", "倒序（最新在前）", "倒序（最新在前）"), selected: newestFirst) { newestFirst = true }
                        }
                        .accessibilityIdentifier("library.sort-order")
                        Menu(T("Photo shape", "照片比例", "照片比例"), systemImage: "aspectratio") {
                            filterOption(T("Square", "正方形", "正方形"), selected: squareThumbnails) { squareThumbnails = true }
                            filterOption(T("Original ratio", "原始比例", "原始比例"), selected: !squareThumbnails) { squareThumbnails = false }
                        }
                        Menu(T("Thumbnail size", "缩略图大小", "縮略圖大小"), systemImage: "square.grid.3x3") {
                            ForEach(LibraryThumbnailSize.allCases, id: \.self) { size in
                                filterOption(size.title, selected: thumbnailSize == size) { thumbnailSize = size }
                            }
                        }
                    }
                    Section {
                        Button(T("Search file names", "搜索文件名", "搜尋檔案名"), systemImage: "magnifyingglass") {
                            if showingSearch { searchFocused = true }
                            else { showingSearch = true }
                        }
                        Toggle(T("RAW only", "仅显示 RAW", "僅顯示 RAW"), isOn: $rawOnly)
                        Menu(T("Rating", "星级", "星級"), systemImage: "star") {
                            ForEach(0...5, id: \.self) { rating in
                                filterOption(rating == 0 ? T("All ratings", "全部星级", "全部星級") : T("At least \(rating) stars", "至少 \(rating) 星", "至少 \(rating) 星"), selected: minimumRating == rating) {
                                    minimumRating = rating
                                }
                            }
                        }.accessibilityIdentifier("library.rating-filter")
                        Menu(T("Flag", "旗标", "旗標"), systemImage: "flag") {
                            filterOption(T("All flags", "全部旗标", "全部旗標"), selected: flagFilter == "all") { flagFilter = "all" }
                            filterOption(T("Unflagged", "无旗标", "無旗標"), selected: flagFilter == "none") { flagFilter = "none" }
                            filterOption(T("Pick", "保留", "保留"), selected: flagFilter == "pick") { flagFilter = "pick" }
                            filterOption(T("Reject", "淘汰", "淘汰"), selected: flagFilter == "reject") { flagFilter = "reject" }
                        }.accessibilityIdentifier("library.flag-filter")
                        if hasFilters {
                            Button(T("Clear filters", "清除筛选", "清除篩選"), systemImage: "arrow.counterclockwise") {
                                rawOnly = false; minimumRating = 0; flagFilter = "all"
                            }
                        }
                    }
                    Section {
                        Button(T("Settings", "设置", "設定"), systemImage: "gearshape") { settings = .init(folded: phoneHingeClosed == true) }
                        Button(T("About Silverphase", "关于 Silverphase", "關於 Silverphase"), systemImage: "info.circle") { about = .init(folded: phoneHingeClosed == true) }
                    }
                } label: {
                    Label(T("Library menu", "图库菜单", "圖庫選單"), systemImage: hasFilters ? "ellipsis.circle.fill" : "ellipsis.circle")
                }
                .accessibilityValue(hasFilters ? T("Filtered", "已筛选", "已篩選") : "")
                .accessibilityIdentifier("library.menu")
            }
            if #available(iOS 27.1, *), verticalToolbar {
                ToolbarItem(placement: .bottomBar) { cameraButton() }
                    .axisBehavior(.verticalPreferred)
                    .sharedBackgroundVisibility(.hidden)
            } else if !usesProminentCamera {
                if #available(iOS 26, *) {
                    ToolbarItem(placement: .bottomBar) { cameraButton() }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .bottomBar) { cameraButton() }
                }
            }
        }
    }

    private func filterOption(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if selected { Label(title, systemImage: "checkmark") }
            else { Text(title) }
        }
    }

    @ViewBuilder private var selectionActions: some View {
        Button(T("Edit", "编辑", "編輯"), systemImage: "slider.horizontal.3") { open(selected) }
            .accessibilityIdentifier("library.edit-selected")
        Button(T("Export", "导出", "匯出"), systemImage: "square.and.arrow.up") {
            exportRequest = LibraryExportRequest(ids: selected.map(\.id))
        }.accessibilityIdentifier("library.export-selected")
        Menu {
            Button(T("Copy edits", "复制编辑项", "複製編輯項"), systemImage: "doc.on.doc") {
                if let photo = selected.first { requestCopy(photo) }
            }.disabled(selected.count != 1)
            Button(T("Paste to \(selected.count) selected", "粘贴到所选 \(selected.count) 张", "貼到所選 \(selected.count) 張"), systemImage: "doc.on.doc") { document.pasteSettings() }
                .disabled(document.settingsClipboard == nil)
            ratingMenu(ids: document.selectedPhotoIDs)
            Button(T("Remove from Library", "从图库删除", "從圖庫刪除"), systemImage: "trash", role: .destructive) { deleting = document.selectedPhotoIDs }
        } label: {
            Label(T("More batch actions", "更多批量操作", "更多批量操作"), systemImage: "ellipsis")
        }
        .accessibilityIdentifier("library.selection-menu")
    }

    private func ratingMenu(ids: Set<UUID>) -> some View {
        Group {
            Menu(T("Rating", "评分", "評分"), systemImage: "star") {
                ForEach(0...5, id: \.self) { rating in
                    Button(rating == 0 ? T("Clear rating", "清除评分", "清除評分") : T("\(rating) stars", "\(rating) 星", "\(rating) 星")) { document.markPhotos(ids, rating: rating) }
                }
            }
            Button(T("Pick", "保留", "保留"), systemImage: "flag.fill") { document.markPhotos(ids, flag: "pick") }
            Button(T("Reject", "淘汰", "淘汰"), systemImage: "flag.slash") { document.markPhotos(ids, flag: "reject") }
            Button(T("Clear flag", "清除旗标", "清除旗標")) { document.markPhotos(ids, flag: "none") }
        }
    }
}
private enum LibraryThumbnailSize: String, CaseIterable {
    case small = "小", medium = "中", large = "大"

    /// The stored `rawValue` stays as it was — it is what `@AppStorage` already
    /// holds for anybody who chose a size — so the menu asks for a title rather
    /// than drawing the raw value.
    @MainActor var title: String {
        switch self {
        case .small: T("Small", "小", "小")
        case .medium: T("Medium", "中", "中")
        case .large: T("Large", "大", "大")
        }
    }

    func minimumWidth(regular: Bool) -> CGFloat {
        switch self {
        case .small: regular ? 105 : 72
        case .medium: regular ? 138 : 96
        case .large: regular ? 190 : 146
        }
    }
}

private struct LibraryEditorRequest: Identifiable {
    let id = UUID()
    let firstID: UUID
    let ids: [UUID]?
}
private struct LibraryExportRequest: Identifiable { let id = UUID(); let ids: [UUID] }

/// Duo's shared rail owns vertical placement; iPad and older phones use the
/// same browsing and selection controls in their navigation toolbar.
private struct LibraryHeaderBar<Header: View>: ViewModifier {
    @ViewBuilder var header: () -> Header

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .scrollEdgeEffectStyle(.automatic, for: .top)
                .safeAreaBar(edge: .top, spacing: 0, content: header)
        } else {
            content.safeAreaInset(edge: .top, spacing: 0) {
                header().background(.ultraThinMaterial)
            }
        }
    }
}

private struct LibraryCameraButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent: Bool

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        let diameter: CGFloat = prominent ? 64 : 48
        let orange = LinearGradient(
            colors: [Color(red: 1, green: 0.29, blue: 0.02),
                     Color(red: 0.95, green: 0.55, blue: 0.17)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        let label = configuration.label
            .font(.system(size: prominent ? 27 : 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .opacity(isEnabled ? 1 : 0.45)
            .background(orange, in: Circle())
            .overlay {
                Circle().strokeBorder(LinearGradient(
                    colors: [Color(red: 1, green: 0.88, blue: 0.56).opacity(0.55),
                             .clear,
                             Color(red: 1, green: 0.81, blue: 0.42).opacity(0.45)],
                    startPoint: .top, endPoint: .bottom
                ), lineWidth: 1)
                .allowsHitTesting(false)
            }
            .contentShape(Circle())

        if #available(iOS 26, *) {
            label.glassEffect(.regular.interactive(isEnabled), in: .circle)
        } else {
            label
                .brightness(configuration.isPressed ? -0.08 : 0)
        }
    }
}

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

private struct LibraryFormatBadge: View {
    let identifier: String?
    let original: URL
    @State private var detectedIdentifier: String?

    var body: some View {
        LabeledContent(T("Original format", "原片格式", "原片格式"), value: MobileImageMetadata.formatBadge(for: identifier ?? detectedIdentifier) ?? T("Unknown", "未知", "未知"))
            .task(id: original) {
                guard identifier == nil else { return }
                detectedIdentifier = await Task.detached(priority: .utility) {
                    MobileImageMetadata.storedTypeIdentifier(original)
                }.value
            }
    }
}
