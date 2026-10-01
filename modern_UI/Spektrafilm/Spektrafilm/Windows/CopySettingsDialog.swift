import SwiftUI

/// Select at copy time; paste always applies the last confirmed clipboard.
struct CopySettingsDialog: View {
    @Bindable var session: Session
    let request: SettingsCopyRequest
    @State private var groups: Set<ClipboardGroup>
    @Environment(\.dismiss) private var dismiss

    init(session: Session, request: SettingsCopyRequest) {
        self.session = session
        self.request = request
        _groups = State(initialValue: request.groups)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Metric.space20) {
            VStack(alignment: .leading, spacing: Theme.Metric.space4) {
                Text(T("Copy Settings", "复制设置"))
                    .font(Theme.Font.railTitle).foregroundStyle(Theme.Ink.primary)
                Text(T("Copy the following settings from \(request.sourceName).",
                       "从 \(request.sourceName) 复制以下设置。")).font(Theme.Font.caption)
                    .foregroundStyle(Theme.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: Theme.Metric.space12) {
                HStack(spacing: Theme.Metric.space12) {
                    Text(T("Select Settings", "选择设置"))
                        .font(Theme.Font.modernSectionTitle).foregroundStyle(Theme.Ink.primary)
                    Spacer()
                    Button(T("Select All", "全选")) { groups = Set(ClipboardGroup.offered) }
                        .buttonStyle(.plain).font(Theme.Font.label).foregroundStyle(Theme.accent)
                    Rectangle().fill(Theme.ruleSoft)
                        .frame(width: Theme.Metric.rule, height: Theme.Metric.gridControl)
                    Button(T("Clear", "清除")) { groups.removeAll() }
                        .buttonStyle(.plain).font(Theme.Font.label).foregroundStyle(Theme.Ink.secondary)
                }
                Rectangle().fill(Theme.ruleSoft).frame(height: Theme.Metric.rule)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Metric.space20),
                                    GridItem(.flexible())],
                          alignment: .leading, spacing: Theme.Metric.space8) {
                    ForEach(ClipboardGroup.offered) { group in
                        option(group)
                    }
                }
            }
            Rectangle().fill(Theme.ruleSoft).frame(height: Theme.Metric.rule)
            HStack(spacing: Theme.Metric.space12) {
                Text(T("\(groups.count) selected", "已选 \(groups.count) 项"))
                    .font(Theme.Font.caption).foregroundStyle(Theme.Ink.tertiary)
                Spacer()
                Button(T("Cancel", "取消")) { dismiss() }
                    .buttonStyle(.surface)
                    .keyboardShortcut(.cancelAction)
                Button(L(.clipCopy)) {
                    session.confirmCopySettings(requestID: request.id, groups: groups)
                }
                .buttonStyle(.primarySurface)
                .keyboardShortcut(.defaultAction)
                .disabled(groups.isEmpty || session.batchExporting)
            }
        }
        .padding(Theme.Metric.space20)
        .frame(width: Theme.Metric.copySettingsDialogWidth)
    }

    private func option(_ group: ClipboardGroup) -> some View {
        HStack(spacing: Theme.Metric.space8) {
            CheckBox(isOn: Binding(
                get: { groups.contains(group) },
                set: { on in
                    if on { groups.insert(group) } else { groups.remove(group) }
                }))
                .accessibilityLabel(group.title)
                .accessibilityValue(groups.contains(group) ? T("Selected", "已选") : T("Not selected", "未选"))
            Button {
                if groups.contains(group) { groups.remove(group) } else { groups.insert(group) }
            } label: {
                Text(group.title).font(Theme.Font.label).foregroundStyle(Theme.Ink.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .frame(height: Theme.Metric.rowHeight)
        .help(group.help)
    }
}
