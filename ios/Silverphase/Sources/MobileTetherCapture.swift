#if SILVERPHASE_APP && DEBUG
import SwiftUI
import UniformTypeIdentifiers

/// One field workflow for direct cable arrivals and user-selected vendor
/// transfers. Original files go through the existing library transaction;
/// the film recipe is part of the new edit rather than baked into the file.
struct MobileTetherCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var document: MobileDocument
    let openEditor: (MobilePhoto) -> Void

    @State private var receiver = MobileTetherReceiver()
    @State private var filmID = MobileCameraRecipe.defaultFilmID
    @State private var choosingPhotos = false
    @State private var choosingFiles = false
    @State private var latest: MobilePhoto?
    @State private var preview: CGImage?
    @State private var receiving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(T("Film for new arrivals", "接收时套用的胶片", "接收時套用的膠片")) {
                    Picker(T("Film", "胶片", "膠片"), selection: $filmID) {
                        ForEach(StockCatalog.shared.filmsForPicker) { Text($0.displayName).tag($0.id) }
                    }
                    .disabled(receiver.isRunning || receiving || document.isInteractionLocked)
                    .accessibilityIdentifier("tether.film")
                }
                Section {
                    if receiver.isRunning {
                        Button(T("Stop USB Receive", "停止 USB 接收", "停止 USB 接收")) { receiver.stop() }
                    } else {
                        Button(T("Start USB Receive", "开始 USB 接收", "開始 USB 接收"), systemImage: "cable.connector") {
                            let film = filmID
                            error = nil
                            receiver.start { url, name in
                                await receive([url], names: [url: name], film: film)
                            }
                        }
                        .disabled(receiving || document.isInteractionLocked)
                        .accessibilityIdentifier("tether.usb-start")
                    }
                    Text(receiver.status).foregroundStyle(.secondary)
                } header: {
                    Text(T("Direct cable", "有线直连", "有線直連"))
                } footer: {
                    Text(T("Connect a compatible USB camera in photo-transfer mode. Shoot on the camera after it is ready; no remote shutter.",
                           "以照片传输模式连接兼容 USB 相机。显示就绪后在相机上按快门；手机不会遥控快门。",
                           "以照片傳輸模式連接相容的 USB 相機。顯示就緒後在相機上按快門；手機不會遙控快門。"))
                }
                Section {
                    Button(T("Choose from Photos", "从照片选择", "從照片選擇"), systemImage: "photo") { choosingPhotos = true }
                        .accessibilityIdentifier("tether.photos")
                    Button(T("Choose from Files", "从文件选择", "從檔案選擇"), systemImage: "folder") { choosingFiles = true }
                        .accessibilityIdentifier("tether.files")
                } header: {
                    Text(T("Wireless or vendor transfer", "无线或厂商应用传输", "無線或廠商 App 傳輸"))
                } footer: {
                    Text(T("Use the camera maker's app to send originals to Photos or Files, then select them here. This does not pair the camera over Wi-Fi.",
                           "先用相机厂商应用传送原片至「照片」或「文件」，再在这里选入。这里不会直接配对 Wi-Fi 相机。",
                           "先用相機廠商 App 傳送原片至「照片」或「檔案」，再在這裡選入。這裡不會直接配對 Wi-Fi 相機。"))
                }
                .disabled(receiver.isRunning || receiving || document.isInteractionLocked)
                if receiving { ProgressView(T("Importing original…", "正在导入原片…", "正在匯入原檔…")) }
                if let latest {
                    Section(T("Latest result", "最新成片", "最新成片")) {
                        if let preview {
                            Image(decorative: preview, scale: 1).resizable().scaledToFit()
                                .accessibilityLabel(T("Developed film preview", "胶片显影预览", "膠片顯影預覽"))
                        }
                        Button(T("Open in Editor", "在编辑器中打开", "在編輯器中開啟")) {
                            receiver.stop()
                            openEditor(latest)
                            dismiss()
                        }.disabled(receiving || document.isInteractionLocked)
                        Text(latest.name).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(T("Tethered Shooting", "联机拍摄", "連線拍攝"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(T("Done", "完成", "完成")) { receiver.stop(); dismiss() }
                        .disabled(receiving || document.isInteractionLocked)
                }
            }
        }
        .interactiveDismissDisabled(receiving || document.isInteractionLocked)
        .onDisappear { receiver.stop() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { receiver.stop() } }
        .task(id: latest?.id) {
            preview = nil
            guard let photo = latest else { return }
            do {
                let result = try await document.developCameraPhoto(photo, animate: false)
                guard !Task.isCancelled, latest?.id == photo.id else { return }
                preview = result.image
            } catch {
                guard !Task.isCancelled, latest?.id == photo.id else { return }
                self.error = T("Original saved, but preview failed: ", "原片已保存，但预览失败：", "原檔已儲存，但預覽失敗：") + error.localizedDescription
            }
        }
        .fileImporter(isPresented: $choosingFiles, allowedContentTypes: [.rawImage, .image], allowsMultipleSelection: true) { result in
            let film = filmID
            switch result {
            case .success(let urls): Task { await receive(urls, film: film) }
            case .failure(let error): self.error = error.localizedDescription
            }
        }
        .sheet(isPresented: $choosingPhotos) {
            LibraryPhotoPicker(isPresented: $choosingPhotos,
                onStart: { document.beginPhotoImport(total: $0) },
                onProgress: { document.photoImportProgress(index: $0, total: $1, name: $2) }) { files, skipped, errors in
                let film = filmID
                Task {
                    if files.isEmpty { document.finishPhotoImportWithoutFiles() }
                    else {
                        await receive(files.map(\.url), names: Dictionary(uniqueKeysWithValues: files.map { ($0.url, $0.name) }),
                                      film: film, picker: true)
                    }
                    if !errors.isEmpty { self.error = errors.joined(separator: "\n") }
                    else if skipped > 0 {
                        self.error = T("Skipped \(skipped) unavailable or unsupported items.", "跳过 \(skipped) 个不可读取或不支持的项目。", "略過 \(skipped) 個無法讀取或不支援的項目。")
                    }
                }
            }
        }
    }

    @MainActor private func receive(_ urls: [URL], names: [URL: String] = [:], film: String, picker: Bool = false) async {
        guard !urls.isEmpty else { return }
        guard let stock = StockCatalog.shared.stock(film), stock.isFilm else {
            if picker {
                document.finishPhotoImportWithoutFiles()
                for url in urls { try? FileManager.default.removeItem(at: url) }
            }
            error = T("The chosen film is unavailable.", "所选胶片已不可用。", "所選膠片已無法使用。")
            return
        }
        let previous = document.photos.count
        receiving = true; error = nil
        defer { receiving = false }
        document.error = nil
        await document.importFiles(urls, displayNames: names, removeSourcesAfterImport: picker,
                                   continuingPhotoSelection: picker, capturedFilm: stock, announceSuccess: false).value
        if document.photos.count > previous { latest = document.photos.last }
        if let problem = document.error { error = problem; document.error = nil }
        else if document.photos.count == previous {
            error = T("The original was not added to the library.", "原片没有加入图库。", "原檔沒有加入圖庫。")
        }
    }
}
#endif
