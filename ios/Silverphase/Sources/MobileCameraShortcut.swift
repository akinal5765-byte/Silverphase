import AppIntents
import Observation

@MainActor @Observable final class MobileCameraLaunch {
    static let shared = MobileCameraLaunch()
    var pending = false
}

struct OpenSilverphaseCameraIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Camera"
    static let description = IntentDescription("Open the film camera in Silverphase.")
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        MobileCameraLaunch.shared.pending = true
        return .result()
    }
}

struct SilverphaseAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenSilverphaseCameraIntent(),
                    phrases: ["Open the camera in \(.applicationName)", "Take a photo with \(.applicationName)"],
                    shortTitle: "Open Camera", systemImageName: "camera")
    }
}
