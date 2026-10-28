import SwiftUI
import UIKit

struct MobileOperationProgress: Identifiable, Equatable, Sendable {
    enum Kind: Sendable { case importing, exporting }
    enum Stage: String, Sendable {
        case receiving = "读取原始文件"
        case copying = "导入文件"
        case preview = "生成首张预览"
        case preparing = "准备导出"
        case rendering = "处理照片"
        case color = "转换输出色彩"
        case writing = "写入文件"
        case photos = "保存到照片"
        var outputOrder: Int {
            switch self {
            case .preparing: 0
            case .rendering: 1
            case .color: 2
            case .writing: 3
            case .photos: 4
            default: -1
            }
        }
    }
    let id = UUID()
    let kind: Kind
    var stage: Stage
    var index: Int = 1
    var total: Int
    var filename = ""
    var title: String { kind == .importing ? "正在导入" : "正在导出" }
    var count: String { total > 0 ? "\(min(index, total)) / \(total)" : "" }
    static func exportStage(_ phase: String) -> Stage? {
        switch phase {
        case "export.prepare", "decoded": .preparing
        case "before-render", "rendered", "engine-released", "host-copy": .rendering
        case "before-output-conversion", "after-output-conversion": .color
        case "before-jpeg-write", "file-ready": .writing
        default: nil
        }
    }
}

/// Shared payload for transient messages and current/future progress producers.
/// An unknown fraction stays indeterminate; file counts are not render percentages.
struct MobileNotification: Identifiable, Equatable, Sendable {
    enum Style: Sendable { case information, success, warning, failure, progress }
    var id = UUID()
    var style: Style
    var title: String
    var detail = ""
    var fraction: Double?
    var duration: Duration? = nil
    var lifetime: Duration? {
        if style == .progress { return nil }
        return duration ?? (style == .failure ? .seconds(8) : style == .warning ? .seconds(5) : .seconds(3))
    }
    var symbol: String {
        switch style {
        case .information: "info.circle"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "exclamationmark.circle.fill"
        case .progress: "arrow.trianglehead.2.clockwise.rotate.90"
        }
    }
    static func operation(_ progress: MobileOperationProgress) -> Self {
        Self(id: progress.id, style: .progress, title: progress.title,
             detail: [progress.stage.rawValue, progress.count, progress.filename].filter { !$0.isEmpty }.joined(separator: " · "))
    }
}

/// One top-of-workspace surface, outside the locked editor subtree. No dismissal
/// button or full-screen scrim; operation ownership still controls interaction.
struct MobileNotificationCenter: View {
    let notification: MobileNotification?
    var excludedFrame: CGRect? = nil
    var isCovered = false
    private struct LifetimeKey: Equatable { let id: UUID?; let covered: Bool }
    let dismiss: (UUID) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    var body: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .global)
            let trailing = excludedFrame.map { max(0, frame.maxX - $0.minX) } ?? 0
            VStack(spacing: 0) {
                if let notification {
                    card(notification)
                        .id(notification.id)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.trailing, trailing)
            .padding(.top, 32)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.3), value: notification?.id)
        }
        .allowsHitTesting(false)
        .task(id: LifetimeKey(id: notification?.id, covered: isCovered)) {
            guard !isCovered, let notification else { return }
            if voiceOver {
                UIAccessibility.post(notification: .announcement, argument: [notification.title, notification.detail].filter { !$0.isEmpty }.joined(separator: "，"))
            }
            guard let lifetime = notification.lifetime else { return }
            do {
                // Give spoken notifications time to finish without manual dismissal.
                try await Task.sleep(for: voiceOver ? max(lifetime, .seconds(8)) : lifetime)
                try Task.checkCancellation()
                dismiss(notification.id)
            } catch { }
        }
    }
    private func card(_ notification: MobileNotification) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if notification.style == .progress {
                    ProgressView().tint(.primary).controlSize(.regular)
                } else {
                    Image(systemName: notification.symbol)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(notification.style == .failure || notification.style == .warning ? MobileStyle.accent : .primary)
                }
            }.frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(notification.title).font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if !notification.detail.isEmpty {
                    Text(notification.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                        .lineLimit(notification.style == .failure ? 5 : 2).truncationMode(.middle)
                }
                if notification.style == .progress, let fraction = notification.fraction {
                    ProgressView(value: min(1, max(0, fraction))).tint(MobileStyle.accent)
                        .padding(.top, 4)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: 420, alignment: .leading)
        .modifier(ChromeSurface(radius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier(notification.style == .progress ? "editor.operation-progress" : notification.style == .failure ? "delivery.error" : "editor.notification")
    }
}
