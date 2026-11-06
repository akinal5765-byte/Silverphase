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
                Label("Silverphase 相机", systemImage: "camera")
            }
        }
        .displayName("Silverphase 相机")
        .description("解锁后直接打开 Silverphase 相机。")
    }
}
