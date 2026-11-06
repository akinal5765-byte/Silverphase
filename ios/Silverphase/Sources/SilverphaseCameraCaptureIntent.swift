import AppIntents

struct SilverphaseCameraCaptureIntent: CameraCaptureIntent {
    static let title: LocalizedStringResource = "打开 Silverphase 相机"

    @MainActor func perform() async throws -> some IntentResult {
#if SILVERPHASE_APP
        MobileCameraLaunch.shared.pending = true
#endif
        return .result()
    }
}

enum SilverphaseCameraDestination: String, AppEnum {
    case camera

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Silverphase 页面")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .camera: "相机",
    ]
}

struct OpenSilverphaseCameraControlIntent: OpenIntent {
    static let title: LocalizedStringResource = "打开 Silverphase 相机"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "页面", default: .camera)
    var target: SilverphaseCameraDestination

    @MainActor func perform() async throws -> some IntentResult {
#if SILVERPHASE_APP
        MobileCameraLaunch.shared.pending = true
#endif
        return .result()
    }
}
