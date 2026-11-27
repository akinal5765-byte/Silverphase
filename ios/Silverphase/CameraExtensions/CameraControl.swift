import SwiftUI
import WidgetKit

@main
struct SilverphaseCameraControlBundle: WidgetBundle {
    var body: some Widget {
        SilverphaseCameraControl()
    }
}

struct SilverphaseCameraControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.silverphase.editor.camera") {
            ControlWidgetButton(action: OpenSilverphaseCameraControlIntent()) {
                Label("Silverphase Camera", systemImage: "camera")
            }
        }
        .displayName("Silverphase Camera")
        .description("Open the Silverphase camera after unlocking your device.")
    }
}
