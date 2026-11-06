import ExtensionKit
import LockedCameraCapture
import OSLog
import SwiftUI

@main
struct SilverphaseLockedCamera: LockedCameraCaptureExtension {
    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            LockedCameraContent(session: session)
        }
    }
}

private struct LockedCameraContent: View {
    let session: LockedCameraCaptureSession
    @State private var launchError: String?
    @State private var hingeClosed: Bool?

    var body: some View {
        MobileCameraView(storeCapture: storeCapture, openLibrary: openLibrary, lockedHingeClosed: hingeClosed)
            .background {
                LockedCameraHostProbe { hingeClosed = $0 }
                    .allowsHitTesting(false)
            }
        .alert("无法打开图库", isPresented: Binding(get: { launchError != nil }, set: { if !$0 { launchError = nil } })) {
            Button("好") { launchError = nil }
        } message: {
            Text(launchError ?? "")
        }
    }

    private func storeCapture(_ data: Data, format: MobileCaptureFormat) async throws {
        let destination = session.sessionContentURL
            .appendingPathComponent("Silverphase-" + UUID().uuidString)
            .appendingPathExtension(format.fileExtension)
        try await Task.detached(priority: .userInitiated) {
            // Stage inside the session directory so a partial write is never
            // handed off as a photo. Publish with a same-directory rename.
            let staging = destination.deletingLastPathComponent()
                .appendingPathComponent("." + destination.lastPathComponent + ".partial")
            defer { try? FileManager.default.removeItem(at: staging) }
            // The system may move this original before the phone is unlocked
            // again, after the extension has closed the file.
            try data.write(to: staging, options: [.withoutOverwriting, .completeFileProtectionUntilFirstUserAuthentication])
            try FileManager.default.moveItem(at: staging, to: destination)
        }.value
    }

    private func openLibrary() {
        Task {
            do {
                try await session.openApplication(for: NSUserActivity(activityType: NSUserActivityTypeLockedCameraCapture))
            } catch {
                launchError = error.localizedDescription
            }
        }
    }
}

// Observe host geometry without using it to resize or offset the camera.
private struct LockedCameraHostProbe: UIViewRepresentable {
    let update: (Bool?) -> Void

    func makeUIView(context: Context) -> Probe { Probe(update: update) }
    func updateUIView(_ view: Probe, context: Context) {
        view.update = update
        view.scheduleMeasurement()
    }

    final class Probe: UIView {
        var update: (Bool?) -> Void
        private var folded: Bool?
        private var lastFolded: Bool?
        private var pending = false
        private var lastGeometry = ""

        init(update: @escaping (Bool?) -> Void) {
            self.update = update
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            if #available(iOS 27.1, *) {
                addInteraction(UIHingeInteraction { [weak self] _, change in
                    self?.folded = change.hinge.map { $0.status == .closed || $0.status == .unknown }
                    self?.scheduleMeasurement()
                })
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            scheduleMeasurement()
            guard window != nil else { return }
            // A host transition can translate the window without relaying
            // a size change to the root view.
            for delay in [0.25, 0.75, 1.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.scheduleMeasurement()
                }
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            scheduleMeasurement()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            scheduleMeasurement()
        }

        func scheduleMeasurement() {
            guard !pending else { return }
            pending = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pending = false
                guard let window = self.window, !self.bounds.isEmpty else { return }
                let safeArea = window.safeAreaLayoutGuide.layoutFrame
                let screenSpace = window.windowScene?.screen.coordinateSpace
                let screenFrame = screenSpace.map { window.convert(window.bounds, to: $0) }
                let geometry = "folded=\(String(describing: self.folded)) root=\(self.convert(self.bounds, to: window)) window=\(window.bounds) safe=\(safeArea) screenFrame=\(String(describing: screenFrame))"
                if geometry != self.lastGeometry {
                    self.lastGeometry = geometry
                    Logger(subsystem: "com.silverphase.editor", category: "LockedCamera")
                        .notice("Host geometry: \(geometry, privacy: .public)")
                }
                if self.folded != self.lastFolded {
                    self.lastFolded = self.folded
                    self.update(self.folded)
                }
            }
        }
    }
}
