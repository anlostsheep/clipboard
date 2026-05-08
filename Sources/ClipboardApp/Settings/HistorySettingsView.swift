import ClipboardCore
import SwiftUI

struct HistorySettingsView: View {
    let store: InMemoryHistoryStore

    @AppStorage(ClipboardAppSettings.maxHistoryCountKey)
    private var maxHistoryCount: Int = ClipboardAppSettings.defaultMaxHistoryCount

    @State private var recordCount: Int = 0
    @State private var showClearConfirmation = false

    var body: some View {
        Form {
            Section("保留数量") {
                Stepper("最多保留 \(maxHistoryCount) 条历史记录", value: $maxHistoryCount, in: 50...2000, step: 50)
                Text("超出上限时，最旧的记录将自动删除。重启应用后生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("清除历史") {
                HStack {
                    Text("当前会话共 \(recordCount) 条记录")
                    Spacer()
                    Button("清除全部历史") {
                        showClearConfirmation = true
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            Task { recordCount = (try? await store.count()) ?? 0 }
        }
        .confirmationDialog(
            "确定要清除所有剪贴板历史吗？此操作无法撤销。",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除全部", role: .destructive) {
                Task {
                    try? await store.removeAll()
                    recordCount = 0
                }
            }
        }
    }
}
