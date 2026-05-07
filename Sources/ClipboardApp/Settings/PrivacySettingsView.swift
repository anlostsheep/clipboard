import SwiftUI

struct PrivacySettingsView: View {
    @AppStorage("privacy.ignoreUniversalClipboard")
    private var ignoreUniversalClipboard: Bool = false

    var body: some View {
        Form {
            Section("Universal Clipboard") {
                Toggle("忽略来自其他 Apple 设备的剪贴板内容", isOn: $ignoreUniversalClipboard)
                Text("开启后，通过 Universal Clipboard 从 iPhone/iPad 复制的内容不会被记录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("排除的应用") {
                Text("密码管理器等敏感应用的内容已自动过滤，不会被记录。")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)

                Text("当前隐私策略过滤以下类型应用的剪贴板内容：密码管理器、银行 App、证券 App。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
