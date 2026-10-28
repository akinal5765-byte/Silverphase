// Wratten names match the unchanged upstream camera_filters.hpp table.
import Foundation

enum CameraFilterChoice: String, CaseIterable, Codable, Sendable {
    case off = ""
    case yellow = "w8", yellowGreen = "w11", deepYellow = "w12", darkYellow = "w15"
    case orange = "w21", red = "w25", blue = "w47", green = "w58"

    @MainActor var title: String {
        switch self {
        case .off: T("Off", "关闭")
        case .yellow: T("No. 8 · Yellow", "8号 · 黄")
        case .yellowGreen: T("No. 11 · Yellow Green", "11号 · 黄绿")
        case .deepYellow: T("No. 12 · Deep Yellow", "12号 · 深黄")
        case .darkYellow: T("No. 15 · Deep Yellow", "15号 · 深黄")
        case .orange: T("No. 21 · Orange", "21号 · 橙")
        case .red: T("No. 25 · Red", "25号 · 红")
        case .blue: T("No. 47 · Blue", "47号 · 蓝")
        case .green: T("No. 58 · Green", "58号 · 绿")
        }
    }
}
