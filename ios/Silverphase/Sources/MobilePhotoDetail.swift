import SwiftUI
import ImageIO
import UIKit

/// The viewer owns browsing state, not the editor's selected image or render session.
struct MobilePhotoDetail: View {
    let document: MobileDocument
    let photoIDs: [UUID]
    let initialDuo: Bool
    @Binding var photoID: UUID
    let onBack: () -> Void
    let onEdit: (MobilePhoto) -> Void
    let onExport: (MobilePhoto) -> Void
    let onInfo: (MobilePhoto) -> Void
    let onCopy: (MobilePhoto) -> Void
    let onDelete: (MobilePhoto) -> Void

    @State private var preview: CGImage?
    @State private var previewLoading = true
    @State private var previewID: UUID?
    @State private var showingFilm = false
    @State private var hingeDetected = false

    private var photo: MobilePhoto? { document.photos.first { $0.id == photoID } }
    private var strip: [MobilePhoto] {
        let index = photoIDs.firstIndex(of: photoID) ?? 0
        guard !photoIDs.isEmpty else { return [] }
        let indexed = Dictionary(uniqueKeysWithValues: document.photos.map { ($0.id, $0) })
        return photoIDs[max(0, index - 16)...min(photoIDs.count - 1, index + 16)].compactMap { indexed[$0] }
    }

    var body: some View {
        GeometryReader { _ in
            let ipad = UIDevice.current.userInterfaceIdiom == .pad
            let duo = UIDevice.current.userInterfaceIdiom == .phone && (initialDuo || hingeDetected)
            if let photo {
                if duo {
                    HStack(spacing: 10) {
                        VStack(spacing: 8) {
                            header(photo)
                            picture(photo)
                            filmstrip
                        }
                        VStack(spacing: 12) {
                            tool(T("Export", "导出", "匯出"), "square.and.arrow.up", id: "photo-detail.export") { onExport(photo) }
                            tool(T("Information", "信息", "資訊"), "info.circle", id: "photo-detail.info") { onInfo(photo) }
                            Divider().frame(width: 28)
                            tool(T("Edit", "编辑", "編輯"), "slider.horizontal.3", id: "photo-detail.edit") { onEdit(photo) }
                        }
                        .padding(6).background(.regularMaterial, in: Capsule())
                    }.padding(10)
                } else {
                    VStack(spacing: 10) {
                        header(photo)
                        if ipad { horizontalTools(photo, top: true) }
                        picture(photo)
                        filmstrip
                        if !ipad { horizontalTools(photo, top: false) }
                    }.padding(.vertical, 8)
                }
            } else {
                Button(T("Back to Library", "返回图库", "返回圖庫"), action: onBack)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(MobileStyle.canvas.ignoresSafeArea())
        .task(id: photo.map { document.libraryPreviewURL($0) }) {
            preview = nil; previewID = nil; previewLoading = true
            defer { if !Task.isCancelled { previewLoading = false } }
            guard let photo else { return }
            let cached = document.libraryPreviewURL(photo)
            if let rendered = await Self.loadPreview(cached), !Task.isCancelled {
                preview = rendered; previewID = photo.id
                return
            }
            let fallback = await Self.loadPreview(document.url(for: photo))
            guard !Task.isCancelled else { return }
            preview = fallback; previewID = photo.id
            if let result = try? await document.developCameraPhoto(photo, animate: false), !Task.isCancelled {
                preview = result.image; previewID = photo.id
            }
        }
        .sheet(isPresented: $showingFilm) {
            NavigationStack {
                List(StockCatalog.shared.filmsForPicker) { film in
                    Button(film.displayName) {
                        if let photo { document.setLibraryFilm(film, for: photo.id) }
                        showingFilm = false
                    }
                }
                .navigationTitle(T("Choose Film", "切换胶片", "切換膠片"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(T("Cancel", "取消", "取消")) { showingFilm = false }
                    }
                }
            }
        }
        .background {
            if UIDevice.current.userInterfaceIdiom == .phone {
                ProcessBarGeometryProbe(hingeChanged: { hingeDetected = $0 != nil }).allowsHitTesting(false)
            }
        }
    }

    private static nonisolated func loadPreview(_ url: URL) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                          kCGImageSourceCreateThumbnailWithTransform: true,
                                          kCGImageSourceThumbnailMaxPixelSize: 2240]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
    }

    private func header(_ photo: MobilePhoto) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 12) {
                tool(T("Back to Library", "返回图库", "返回圖庫"), "chevron.left", id: "photo-detail.back", action: onBack)
                Spacer(minLength: 5)
                VStack(spacing: 2) {
                    if let date = photo.libraryDate {
                        Text(date.formatted(date: .abbreviated, time: .omitted)).font(.subheadline.weight(.semibold))
                        Text(date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(photo.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    }
                }.padding(.horizontal, 16).padding(.vertical, 6).background(.regularMaterial, in: Capsule())
                Spacer(minLength: 5)
                Menu {
                    Button(T("Copy edits", "复制编辑项", "複製編輯項"), systemImage: "doc.on.doc") { onCopy(photo) }
                    Button(T("Paste edits", "粘贴编辑项", "貼上編輯項"), systemImage: "doc.on.clipboard") {
                        document.pasteSettings(to: [photo.id])
                    }.disabled(document.settingsClipboard == nil)
                    Button(T("Remove from Library", "从图库删除", "從圖庫刪除"), systemImage: "trash", role: .destructive) { onDelete(photo) }
                } label: {
                    icon("ellipsis")
                }.accessibilityLabel(T("More", "更多", "更多")).accessibilityIdentifier("photo-detail.menu")
            }
            HStack(spacing: 8) {
                Spacer()
                Menu {
                    ForEach(0...5, id: \.self) { value in
                        Button(value == 0 ? T("Clear rating", "清除星标", "清除星標") : "\(value) ★") {
                            document.markPhotos([photo.id], rating: value)
                        }
                    }
                } label: { chip(photo.rating > 0 ? "\(photo.rating)" : nil, symbol: photo.rating > 0 ? "star.fill" : "star") }
                .accessibilityLabel(T("Rating", "星标", "星標"))
                .accessibilityValue(photo.rating > 0 ? "\(photo.rating) / 5" : T("Unrated", "尚未评分", "尚未評分"))
                .accessibilityIdentifier("photo-detail.rating")
                Menu {
                    Button(T("Pick", "保留", "保留"), systemImage: "flag.fill") { document.markPhotos([photo.id], flag: "pick") }
                    Button(T("Reject", "淘汰", "淘汰"), systemImage: "flag.slash") { document.markPhotos([photo.id], flag: "reject") }
                    Button(T("Clear flag", "清除旗标", "清除旗標")) { document.markPhotos([photo.id], flag: "none") }
                } label: { chip(nil, symbol: photo.flag == "pick" ? "flag.fill" : photo.flag == "reject" ? "flag.slash" : "flag") }
                .accessibilityLabel(T("Flag", "旗标", "旗標")).accessibilityIdentifier("photo-detail.flag")
                Button { showingFilm = true } label: {
                    let id = photo.recipe["film_stock"]?.stringValue ?? MobileProcessContract.defaults["film_stock"]?.stringValue
                    chip(id.flatMap { StockCatalog.shared.stock($0)?.displayName }, symbol: "film")
                }.accessibilityLabel(T("Choose Film", "切换胶片", "切換膠片")).accessibilityIdentifier("photo-detail.film")
            }
        }.padding(.horizontal, 10)
    }

    private func picture(_ photo: MobilePhoto) -> some View {
        GeometryReader { proxy in
            Group {
                if let preview, previewID == photo.id {
                    Image(decorative: preview, scale: 1).resizable().scaledToFit()
                } else if previewLoading {
                    ProgressView()
                } else {
                    Label(T("Preview unavailable", "无法显示预览", "無法顯示預覽"), systemImage: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(photo.name)
            .accessibilityIdentifier("photo-detail.image")
            .gesture(DragGesture(minimumDistance: 18).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height),
                      abs(value.translation.width) > 45,
                      let index = photoIDs.firstIndex(of: photoID) else { return }
                let next = index + (value.translation.width < 0 ? 1 : -1)
                if photoIDs.indices.contains(next) { photoID = photoIDs[next] }
            })
        }
    }

    private var filmstrip: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 5) {
                    ForEach(strip) { item in
                        Button { photoID = item.id } label: {
                            let cached = document.libraryPreviewURL(item)
                            FilmstripThumbnail(url: FileManager.default.fileExists(atPath: cached.path) ? cached : document.url(for: item),
                                               fillsFrame: true, version: document.libraryPreviewVersions[item.id, default: 0])
                                .frame(width: item.id == photoID ? 49 : 32, height: 44)
                                .clipShape(.rect(cornerRadius: 5))
                                .overlay { if item.id == photoID { RoundedRectangle(cornerRadius: 5).strokeBorder(.primary, lineWidth: 1.5) } }
                        }.buttonStyle(.plain).id(item.id).accessibilityLabel(item.name)
                    }
                }.padding(.horizontal, 12)
            }.scrollIndicators(.hidden)
                .onChange(of: photoID, initial: true) { _, id in
                    reader.scrollTo(id, anchor: .center)
                }
        }.frame(height: 46)
    }

    private func horizontalTools(_ photo: MobilePhoto, top: Bool) -> some View {
        HStack(spacing: 12) {
            if top { Spacer(minLength: 0) }
            tool(T("Export", "导出", "匯出"), "square.and.arrow.up", id: "photo-detail.export") { onExport(photo) }
            if !top { Spacer(minLength: 0) }
            HStack(spacing: 7) {
                tool(T("Information", "信息", "資訊"), "info.circle", id: "photo-detail.info") { onInfo(photo) }
                tool(T("Edit", "编辑", "編輯"), "slider.horizontal.3", id: "photo-detail.edit") { onEdit(photo) }
            }.padding(.horizontal, 5).background(.regularMaterial, in: Capsule())
        }
        .padding(.horizontal, 14)
    }

    private func tool(_ label: String, _ symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { icon(symbol) }
            .buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier(id)
    }

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 18, weight: .medium))
            .frame(width: 44, height: 44)
            .background(.regularMaterial, in: Circle()).foregroundStyle(.primary)
    }

    private func chip(_ title: String?, symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            if let title { Text(title).lineLimit(1) }
            Image(systemName: "chevron.down").font(.system(size: 8))
        }
        .font(.caption.weight(.semibold)).padding(.horizontal, 8)
        .frame(minHeight: 44).contentShape(Rectangle())
        .background(alignment: .center) { Capsule().fill(.thinMaterial).frame(height: 26) }
        .foregroundStyle(.primary)
    }
}
