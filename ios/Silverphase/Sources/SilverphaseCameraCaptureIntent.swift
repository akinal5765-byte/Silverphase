import AppIntents

struct SilverphaseCameraCaptureIntent: CameraCaptureIntent {
    typealias AppContext = MobileCameraRecipe
    static let title: LocalizedStringResource = "Open Silverphase Camera"

    @MainActor func perform() async throws -> some IntentResult {
#if SILVERPHASE_APP
        MobileCameraLaunch.shared.pending = true
#endif
        return .result()
    }
}

enum SilverphaseCameraDestination: String, AppEnum {
    case camera

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Silverphase Screen")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .camera: "Camera",
    ]
}

struct OpenSilverphaseCameraControlIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Silverphase Camera"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Screen", default: .camera)
    var target: SilverphaseCameraDestination

    @MainActor func perform() async throws -> some IntentResult {
#if SILVERPHASE_APP
        MobileCameraLaunch.shared.pending = true
#endif
        return .result()
    }
}
