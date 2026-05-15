import ClipboardCore
import SwiftUI

struct HistorySettingsView: View {
    @ObservedObject var services: AppServices
    let baseDirectory: URL?

    private var store: any HistoryStore { services.store }
    private var storageHealth: AppServices.StorageHealth { services.storageHealth }

    @AppStorage(ClipboardAppSettings.maxHistoryCountStorageKey)
    private var maxHistoryCount: Int = ClipboardAppSettings.defaultStorageMaxHistoryCount

    @AppStorage(ClipboardAppSettings.maxAgeDaysKey)
    private var maxAgeDays: Int = ClipboardAppSettings.defaultMaxAgeDays

    @AppStorage(ClipboardAppSettings.failureRecoveryStrategyKey)
    private var failureStrategyRaw: String = StorageFailureStrategy.continueEvicting.rawValue

    @AppStorage(ClipboardAppSettings.notifyOnAutoEvictKey)
    private var notifyOnAutoEvict: Bool = true

    @State private var recordCount: Int = 0
    @State private var showClearConfirmation = false

    private var failureStrategy: Binding<StorageFailureStrategy> {
        Binding(
            get: { StorageFailureStrategy(rawValue: failureStrategyRaw) ?? .continueEvicting },
            set: { failureStrategyRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("保留策略") {
                Stepper("最多保留 \(maxHistoryCount) 条历史记录",
                        value: $maxHistoryCount, in: 200...50000, step: 100)
                Stepper("超过 \(maxAgeDays) 天的记录自动删除（pinned / 收藏除外）",
                        value: $maxAgeDays, in: 7...365, step: 1)
                Text("修改后会立即应用到当前历史记录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("存储") {
                statusRow
                if let dir = baseDirectory {
                    HStack {
                        Text("位置：\(dir.path)")
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("在 Finder 中显示") {
                            NSWorkspace.shared.activateFileViewerSelecting([dir])
                        }
                    }
                }
                Picker("磁盘空间不足时", selection: failureStrategy) {
                    ForEach(StorageFailureStrategy.allCases, id: \.self) { strategy in
                        Text(strategy.displayName).tag(strategy)
                    }
                }
                Toggle("自愈成功时显示通知", isOn: $notifyOnAutoEvict)
            }

            Section("清除历史") {
                HStack {
                    Text("当前共 \(recordCount) 条记录")
                    Spacer()
                    Button("清除全部历史") {
                        showClearConfirmation = true
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshCount() }
        .onChange(of: maxHistoryCount) { _, _ in applyRetentionPolicyChange() }
        .onChange(of: maxAgeDays) { _, _ in applyRetentionPolicyChange() }
        .confirmationDialog(
            "确定要清除所有剪贴板历史吗？此操作无法撤销。",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除全部", role: .destructive) {
                Task {
                    try? await store.removeAll()
                    refreshCount()
                }
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch storageHealth {
        case .ok:
            Label("持久化正常", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .disabled(let reason):
            Label("持久化已禁用：\(reason)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .failing(let reason):
            Label("写入失败：\(reason)", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }

    private func refreshCount() {
        Task { recordCount = (try? await store.count()) ?? 0 }
    }

    private func applyRetentionPolicyChange() {
        Task {
            await services.updateRetentionPolicyFromSettings()
            refreshCount()
        }
    }
}
