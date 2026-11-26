#if SILVERPHASE_APP && DEBUG
import SwiftUI
import UIKit
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
    @State private var ftp: SilverphaseFTPReceiver?
    @State private var ftpHost: String?
    @State private var ftpInbox: URL?
    @State private var ftpGeneration = UUID()
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
                    .disabled(receiver.isRunning || ftp != nil || receiving || document.isInteractionLocked)
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
                        .disabled(ftp != nil || receiving || document.isInteractionLocked)
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
                    if let ftp, let ftpHost {
                        LabeledContent(T("IPv4 address", "IPv4 地址", "IPv4 位址"), value: ftpHost)
                        LabeledContent(T("Port", "端口", "連接埠"), value: "2121")
                        LabeledContent(T("Username", "用户名", "使用者名稱"), value: "silverphase")
                        LabeledContent(T("Session password", "本次密码", "本次密碼"), value: ftp.password)
                        Button(T("Stop FTP Receive", "停止 FTP 接收", "停止 FTP 接收")) { stopFTP() }
                    } else {
                        Button(T("Start FTP Receive", "开始 FTP 接收", "開始 FTP 接收"), systemImage: "wifi") {
                            startFTP()
                        }
                        .disabled(receiver.isRunning || receiving || document.isInteractionLocked || scenePhase != .active)
                        .accessibilityIdentifier("tether.ftp-start")
                    }
                } header: {
                    Text(T("Wi-Fi direct · Sony ARW", "Wi-Fi 直传 · Sony ARW", "Wi-Fi 直傳 · Sony ARW"))
                } footer: {
                    Text(T("Configure the camera for passive FTP and automatic RAW upload on the same trusted Wi-Fi network. FTP is not encrypted. Keep this screen open and update the camera password on each start.",
                           "相机和手机连接同一个可信 Wi-Fi，打开相机的被动 FTP 和 RAW 自动传输。FTP 不加密，请保持此页面在前台，每次启动后在相机里更新密码。",
                           "相機與手機連到同一個可信 Wi-Fi，開啟相機的被動 FTP 和 RAW 自動傳輸。FTP 不加密，請讓此頁面保持在前景，每次啟動後在相機裡更新密碼。"))
                }
                Section {
                    Button(T("Choose from Photos", "从照片选择", "從照片選擇"), systemImage: "photo") { choosingPhotos = true }
                        .accessibilityIdentifier("tether.photos")
                    Button(T("Choose from Files", "从文件选择", "從檔案選擇"), systemImage: "folder") { choosingFiles = true }
                        .accessibilityIdentifier("tether.files")
                } header: {
                    Text(T("Vendor app handoff", "厂商应用接力", "廠商 App 接力"))
                } footer: {
                    Text(T("Use the camera maker's app to send originals to Photos or Files, then select them here. This does not pair the camera over Wi-Fi.",
                           "先用相机厂商应用传送原片至「照片」或「文件」，再在这里选入。这里不会直接配对 Wi-Fi 相机。",
                           "先用相機廠商 App 傳送原片至「照片」或「檔案」，再在這裡選入。這裡不會直接配對 Wi-Fi 相機。"))
                }
                .disabled(receiver.isRunning || ftp != nil || receiving || document.isInteractionLocked)
                if receiving { ProgressView(T("Importing original…", "正在导入原片…", "正在匯入原檔…")) }
                if let latest {
                    Section(T("Latest result", "最新成片", "最新成片")) {
                        if let preview {
                            Image(decorative: preview, scale: 1).resizable().scaledToFit()
                                .accessibilityLabel(T("Developed film preview", "胶片显影预览", "膠片顯影預覽"))
                        }
                        Button(T("Open in Editor", "在编辑器中打开", "在編輯器中開啟")) {
                            receiver.stop(); stopFTP()
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
                    Button(T("Done", "完成", "完成")) { receiver.stop(); stopFTP(); dismiss() }
                        .disabled(receiving || document.isInteractionLocked)
                }
            }
        }
        .interactiveDismissDisabled(receiving || document.isInteractionLocked)
        .onDisappear { receiver.stop(); stopFTP() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { receiver.stop(); stopFTP() } }
        .task(id: ftpGeneration) { await drainFTP() }
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

    @MainActor private func startFTP() {
        error = nil
        do {
            let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true)
            var inbox = base.appendingPathComponent("TetherFTP", isDirectory: true)
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.complete])
            var settings = URLResourceValues()
            settings.isExcludedFromBackup = true
            try inbox.setResourceValues(settings)
            let candidate = SilverphaseFTPReceiver(directory: inbox, film: filmID)
            guard let host = candidate.start() else {
                error = T("FTP could not start. Connect to a private Wi-Fi network and check port 2121.",
                          "FTP 无法启动。请连接私有 Wi-Fi，并确认 2121 端口未被占用。",
                          "FTP 無法啟動。請連線至私人 Wi-Fi，並確認 2121 連接埠未被使用。")
                return
            }
            ftpInbox = inbox; ftpHost = host; ftp = candidate; ftpGeneration = UUID()
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor private func stopFTP() {
        ftp?.stop(); ftp = nil; ftpHost = nil
    }

    private struct FTPArrival: Decodable {
        let name: String
        let film: String
    }

    @MainActor private func drainFTP() async {
        guard let active = ftp, let inbox = ftpInbox else { return }
        let fm = FileManager.default
        var attempted: Set<URL> = []
        while !Task.isCancelled, ftp === active {
            if active.publicationError != nil {
                stopFTP()
                error = T("FTP stopped. Check Local Network access in Settings, then start again.",
                          "FTP 已停止。请在设置中检查「本地网络」权限，再重新启动。",
                          "FTP 已停止。請在設定中檢查「區域網路」權限，再重新啟動。")
                return
            }
            if scenePhase == .active, !receiving, !document.isInteractionLocked {
                let files = (try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: [.creationDateKey])) ?? []
                let arrivals = files.filter { $0.pathExtension == "ARW" && !attempted.contains($0) }
                    .map { url in (url, (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
                    .sorted { $0.1 < $1.1 }
                for (file, _) in arrivals {
                    guard !Task.isCancelled, ftp === active, scenePhase == .active,
                          !receiving, !document.isInteractionLocked else { break }
                    attempted.insert(file)
                    let record = file.appendingPathExtension("json")
                    let receipt = file.appendingPathExtension("done")
                    guard !fm.fileExists(atPath: receipt.path) else { continue }
                    guard let payload = try? Data(contentsOf: record),
                          let arrival = try? JSONDecoder().decode(FTPArrival.self, from: payload) else {
                        error = T("A staged RAW is retained, but its import record could not be read.",
                                  "一张 RAW 已保留，但无法读取它的导入记录。",
                                  "一張 RAW 已保留，但無法讀取其匯入記錄。")
                        continue
                    }
                    if await receive([file], names: [file: arrival.name], film: arrival.film) {
                        guard document.save() else {
                            error = document.error
                            document.error = nil
                            break
                        }
                        do {
                            // Write the receipt before removing the staged RAW. A retransmit
                            // always finds the photo or its receipt, never a hole between them.
                            try fm.moveItem(at: record, to: receipt)
                            try fm.removeItem(at: file)
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    // Give the newest image's preview a chance to start before another import.
                    break
                }
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    @discardableResult @MainActor private func receive(_ urls: [URL], names: [URL: String] = [:], film: String, picker: Bool = false) async -> Bool {
        guard !urls.isEmpty else { return false }
        guard let stock = StockCatalog.shared.stock(film), stock.isFilm else {
            if picker {
                document.finishPhotoImportWithoutFiles()
                for url in urls { try? FileManager.default.removeItem(at: url) }
            }
            error = T("The chosen film is unavailable.", "所选胶片已不可用。", "所選膠片已無法使用。")
            return false
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
        return document.photos.count > previous
    }
}
#endif
