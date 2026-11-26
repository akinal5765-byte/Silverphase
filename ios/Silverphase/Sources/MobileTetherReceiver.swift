#if SILVERPHASE_APP && DEBUG
// Foreground USB still-photo receiver. The photographer presses the camera's
// own shutter. This does not send PTP control commands or delete camera files.
import CoreGraphics
import Foundation
import ImageCaptureCore
import Observation
import UniformTypeIdentifiers

// ImageCaptureCore camera callbacks are normally delivered on the main
// thread. Transfer a delegate event to main if an adapter invokes us off-main;
// the framework objects inside the event are inspected only on main.
private struct TetherMainEvent<Value>: @unchecked Sendable {
    let value: Value

    nonisolated static func deliver(_ value: Value, _ body: @escaping @MainActor @Sendable (Value) -> Void) {
        let event = Self(value: value)
        if Thread.isMainThread {
            MainActor.assumeIsolated { body(event.value) }
        } else {
            DispatchQueue.main.async { body(event.value) }
        }
    }
}

@MainActor
@Observable
final class MobileTetherReceiver: NSObject, ICDeviceBrowserDelegate, ICCameraDeviceDelegate {
    private(set) var status = T("USB receive is off.", "USB 接收已关闭。", "USB 接收已關閉。")
    private(set) var isRunning = false

    private struct Download {
        let id: UUID
        let generation: UUID
        let cameraID: ObjectIdentifier
        let folder: URL
        let localName: String
        let originalName: String
        let expectedBytes: Int64
    }

    @ObservationIgnored private var browser: ICDeviceBrowser?
    @ObservationIgnored private var camera: ICCameraDevice?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var catalogReady = false
    @ObservationIgnored private var seen: Set<String> = []
    @ObservationIgnored private var pending: [ICCameraFile] = []
    @ObservationIgnored private var transfer: Download?
    @ObservationIgnored private var downloadProgress: Progress?
    @ObservationIgnored private var deadline: Task<Void, Never>?
    @ObservationIgnored private var onFile: (@MainActor (URL, String) async -> Void)?
    @ObservationIgnored private var received = 0

    func start(onFile: @escaping @MainActor (URL, String) async -> Void) {
        guard !isRunning else { return }
        generation = UUID()
        received = 0
        let id = generation
        self.onFile = onFile
        isRunning = true
        status = T("Requesting access to the connected camera…", "正在请求访问连接的相机…", "正在要求存取連接的相機…")

        let browser = ICDeviceBrowser()
        self.browser = browser
        browser.delegate = self
        // Objective-C models this combined mask as an enum, not an OptionSet.
        if let mask = ICDeviceTypeMask(rawValue: ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue) {
            browser.browsedDeviceTypeMask = mask
        }
        browser.requestContentsAuthorization { [weak self] authorization in
            let allowed = authorization == .authorized
            Task { @MainActor in
                guard let self, self.isRunning, self.generation == id else { return }
                if allowed {
                    self.status = self.waitingStatus
                    self.browser?.start()
                } else {
                    self.stop()
                    self.status = T("Camera access was not granted. Check iOS Settings.",
                                    "未获准访问相机，请检查 iOS 设置。",
                                    "未獲准存取相機，請檢查 iOS 設定。")
                }
            }
        }
    }

    func stop() {
        generation = UUID()
        isRunning = false
        onFile = nil
        downloadProgress?.cancel()
        releaseCamera()
        let stopping = browser
        browser = nil
        stopping?.delegate = nil
        stopping?.stop()
        // iOS has no cancelDownload. The outstanding transfer keeps its own
        // staging directory until the callback or watchdog cleans it. A
        // caller already opening the staged file also owns its time to read.
        status = T("USB receive is off.", "USB 接收已关闭。", "USB 接收已關閉。")
    }

    private var waitingStatus: String {
        T("Connect a camera with a data cable and select its photo transfer mode.",
          "请用数据线连接相机，并进入照片传输模式。",
          "請用傳輸線連接相機，並進入照片傳輸模式。")
    }

    private func connects(_ device: ICDevice, from source: ICDeviceBrowser) {
        guard isRunning, source === browser, camera == nil, let device = device as? ICCameraDevice,
              device.usbVendorID != 0 else { return }
        camera = device
        catalogReady = false
        seen = []
        pending = []
        device.delegate = self
        status = T("Reading the camera catalog…", "正在读取相机照片目录…", "正在讀取相機照片目錄…")
        device.requestOpenSession()
    }

    private func releaseCamera() {
        let old = camera
        camera = nil
        catalogReady = false
        pending = []
        seen = []
        old?.delegate = nil
        old?.requestCloseSession()
    }

    private func disconnected(_ device: ICDevice) {
        guard camera === device else { return }
        releaseCamera()
        if isRunning {
            status = T("Camera disconnected. Reconnect it to keep receiving.",
                       "相机已断开，重新连接即可继续接收。",
                       "相機已中斷連線，重新連接即可繼續接收。")
        }
    }

    private static func filename(_ file: ICCameraFile) -> String? {
        guard let name = file.originalFilename ?? file.name else { return nil }
        let basename = URL(fileURLWithPath: name).lastPathComponent
        let ext = URL(fileURLWithPath: basename).pathExtension.lowercased()
        let fallbackRAW = ["arw", "nef", "nrw", "dng", "cr2", "cr3", "raf", "rw2", "orf", "pef", "srw", "3fr", "iiq"]
        let type = UTType(filenameExtension: ext)
        guard fallbackRAW.contains(ext) || type?.conforms(to: .rawImage) == true || type?.conforms(to: .image) == true else { return nil }
        return basename
    }

    private static func key(_ file: ICCameraFile) -> String {
        if file.ptpObjectHandle != 0 { return "ptp:\(file.ptpObjectHandle)" }
        // Some devices don't expose an object handle. This key includes
        // capture time and byte count so a camera can reuse a filename.
        return "file:\(file.originalFilename ?? file.name ?? ""):\(file.creationDate?.timeIntervalSince1970 ?? 0):\(file.fileSize)"
    }

    private func markCatalogReady(_ device: ICCameraDevice) {
        guard isRunning, device === camera, !catalogReady else { return }
        // Do not replay older card contents when connecting or reconnecting.
        seen = Set((device.mediaFiles ?? []).compactMap { ($0 as? ICCameraFile).map(Self.key) })
        catalogReady = true
        status = T("Connected. Use the camera’s shutter to receive new photos.",
                   "已连接。按相机快门即可接收新照片。",
                   "已連接。按相機快門即可接收新照片。")
        downloadNext()
    }

    private func receive(_ items: [ICCameraItem], from device: ICCameraDevice) {
        guard isRunning, catalogReady, device === camera else { return }
        for case let file as ICCameraFile in items {
            guard Self.filename(file) != nil, seen.insert(Self.key(file)).inserted else { continue }
            pending.append(file)
        }
        downloadNext()
    }

    private func downloadNext() {
        guard isRunning, catalogReady, transfer == nil, let camera else { return }
        while !pending.isEmpty {
            let file = pending.removeFirst()
            guard let name = Self.filename(file) else { continue }
            let id = UUID()
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("silverphase-usb-\(id)", isDirectory: true)
            let ext = URL(fileURLWithPath: name).pathExtension
            let target = "capture.\(ext)"
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            } catch {
                status = T("Could not reserve local space for the camera file.",
                           "无法为相机原片准备本地存储空间。",
                           "無法為相機原片準備本機儲存空間。")
                continue
            }
            transfer = Download(id: id, generation: generation, cameraID: ObjectIdentifier(camera),
                                folder: folder, localName: target, originalName: name, expectedBytes: file.fileSize)
            status = T("Receiving \(name)…", "正在接收 \(name)…", "正在接收 \(name)…")
            deadline = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(120)) } catch { return }
                guard let self else {
                    try? FileManager.default.removeItem(at: folder)
                    return
                }
                guard let download = self.transfer, download.id == id else { return }
                self.downloadProgress?.cancel()
                self.downloadProgress = nil
                self.transfer = nil
                self.deadline = nil
                if self.generation == download.generation, self.camera.map(ObjectIdentifier.init) == download.cameraID {
                    self.stop()
                    self.status = T("Camera transfer timed out. Reconnect and start receiving again.",
                                    "相机传输超时，请重新连接并开始接收。",
                                    "相機傳輸逾時，請重新連接並開始接收。")
                }
                try? FileManager.default.removeItem(at: download.folder)
                self.downloadNext()
            }
            let options: [ICDownloadOption: Any] = [
                .downloadsDirectoryURL: folder, .saveAsFilename: target,
                .overwrite: false, .deleteAfterSuccessfulDownload: false
            ]
            downloadProgress = file.requestDownload(options: options) { [weak self] savedName, error in
                let failure = error?.localizedDescription
                Task { @MainActor in
                    guard let self else {
                        try? FileManager.default.removeItem(at: folder)
                        return
                    }
                    self.finishDownload(id: id, savedName: savedName, error: failure)
                }
            }
            return
        }
    }

    private func finishDownload(id: UUID, savedName: String?, error: String?) {
        guard let download = transfer, download.id == id else { return }
        deadline?.cancel()
        deadline = nil
        downloadProgress = nil
        let actual = savedName.map { URL(fileURLWithPath: $0).lastPathComponent } ?? download.localName
        let url = download.folder.appendingPathComponent(actual)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        let values = try? url.resourceValues(forKeys: keys)
        let bytes = Int64(values?.fileSize ?? 0)
        let isCurrent = generation == download.generation && isRunning
            && camera.map(ObjectIdentifier.init) == download.cameraID
        guard isCurrent, let onFile, error == nil, values?.isRegularFile == true,
              values?.isSymbolicLink == false, bytes > 0,
              download.expectedBytes <= 0 || download.expectedBytes == bytes else {
            if isCurrent {
                status = T("Could not receive the complete file \(download.originalName).",
                           "未能完整接收 \(download.originalName)。",
                           "未能完整接收 \(download.originalName)。")
            }
            retire(download)
            return
        }
        Task { @MainActor [weak self] in
            // A Stop between the camera callback and this scheduled task
            // rejects the file, but a callback already reading it may finish.
            if let self, self.generation == download.generation, self.isRunning,
               self.camera.map(ObjectIdentifier.init) == download.cameraID {
                await onFile(url, download.originalName)
                if self.generation == download.generation, self.isRunning,
                   self.camera.map(ObjectIdentifier.init) == download.cameraID {
                    self.received += 1
                    self.status = T("Received \(self.received) photos. Ready for the next shot.",
                                    "已接收 \(self.received) 张照片，可以继续拍摄。",
                                    "已接收 \(self.received) 張照片，可以繼續拍攝。")
                }
            }
            if let self { self.retire(download) }
            else { try? FileManager.default.removeItem(at: download.folder) }
        }
    }

    private func retire(_ download: Download) {
        try? FileManager.default.removeItem(at: download.folder)
        guard transfer?.id == download.id else { return }
        transfer = nil
        downloadNext()
    }

    // MARK: ImageCaptureCore delegates

    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        TetherMainEvent.deliver((browser, device)) { [weak self] event in self?.connects(event.1, from: event.0) }
    }

    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        TetherMainEvent.deliver((browser, device)) { [weak self] event in
            guard let self, self.browser === event.0 else { return }
            self.disconnected(event.1)
        }
    }

    nonisolated func didRemove(_ device: ICDevice) {
        TetherMainEvent.deliver(device) { [weak self] in self?.disconnected($0) }
    }

    nonisolated func device(_ device: ICDevice, didOpenSessionWithError error: (any Error)?) {
        guard error != nil else { return }
        TetherMainEvent.deliver(device) { [weak self] device in
            guard let self, self.camera === device else { return }
            self.releaseCamera()
            self.status = T("Could not open the camera. Check its USB mode or reconnect.",
                            "无法打开相机，请检查 USB 模式或重新连接。",
                            "無法開啟相機，請檢查 USB 模式或重新連接。")
        }
    }

    nonisolated func device(_ device: ICDevice, didCloseSessionWithError error: (any Error)?) {
        TetherMainEvent.deliver(device) { [weak self] in self?.disconnected($0) }
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        TetherMainEvent.deliver((camera, items)) { [weak self] event in self?.receive(event.1, from: event.0) }
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    nonisolated func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: (any Error)?) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: (any Error)?) {}

    nonisolated func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        TetherMainEvent.deliver(device) { [weak self] in self?.markCatalogReady($0) }
    }

    nonisolated func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {}
    nonisolated func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {}
}

#endif
