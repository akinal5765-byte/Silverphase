import AppIntents
import Observation

@MainActor @Observable final class MobileCameraLaunch {
    static let shared = MobileCameraLaunch()
    var pending = false
}

struct OpenSilverphaseCameraIntent: AppIntent {
    static let title: LocalizedStringResource = "打开相机"
    static let description = IntentDescription("直接打开 Silverphase 的胶片相机。")
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        MobileCameraLaunch.shared.pending = true
        return .result()
    }
}

struct SilverphaseAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenSilverphaseCameraIntent(),
                    phrases: ["打开\(.applicationName)相机", "用\(.applicationName)拍照"],
                    shortTitle: "打开相机", systemImageName: "camera")
    }
}
