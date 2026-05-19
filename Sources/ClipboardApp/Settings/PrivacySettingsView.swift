import SwiftUI

struct PrivacySettingsView: View {
    @ObservedObject var services: AppServices

    @AppStorage(ClipboardAppSettings.ignoreUniversalClipboardKey)
    private var ignoreUniversalClipboard: Bool = false

    @State private var ignoredPasteboardTypes: [String] = []
    @State private var ignoredAppBundleIDs: [String] = []
    @State private var newPasteboardType = ""
    @State private var newBundleID = ""

    var body: some View {
        Form {
            Section("Universal Clipboard") {
                Toggle("忽略来自其他 Apple 设备的剪贴板内容", isOn: $ignoreUniversalClipboard)
                Text("开启后，通过 Universal Clipboard 从 iPhone/iPad 复制的内容不会被记录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("排除的剪贴板类型") {
                ForEach(ignoredPasteboardTypes, id: \.self) { type in
                    HStack {
                        Text(type)
                        Spacer()
                        Button("移除") {
                            removeIgnoredPasteboardType(type)
                        }
                    }
                }

                HStack {
                    TextField("例如 com.example.secret", text: $newPasteboardType)
                    Button("添加") {
                        addIgnoredPasteboardType()
                    }
                    .disabled(trimmed(newPasteboardType).isEmpty)
                }

                Text("标准隐藏类型会继续自动过滤；这里用于额外排除自定义 pasteboard type。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("排除的应用") {
                Text("密码管理器等敏感应用的内容已自动过滤，不会被记录。")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)

                ForEach(ignoredAppBundleIDs, id: \.self) { bundleID in
                    HStack {
                        Text(bundleID)
                        Spacer()
                        Button("移除") {
                            removeIgnoredAppBundleID(bundleID)
                        }
                    }
                }

                HStack {
                    TextField("例如 com.example.Passwords", text: $newBundleID)
                    Button("添加") {
                        addIgnoredAppBundleID()
                    }
                    .disabled(trimmed(newBundleID).isEmpty)
                }

                Text("输入 bundle identifier 后，该应用来源的剪贴板内容不会被记录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadSettings)
        .onChange(of: ignoreUniversalClipboard) { _, _ in
            services.refreshPrivacyPolicyFromSettings()
        }
    }

    private func loadSettings() {
        ignoredPasteboardTypes = ClipboardAppSettings.ignoredPasteboardTypes().sorted()
        ignoredAppBundleIDs = ClipboardAppSettings.ignoredAppBundleIDs().sorted()
    }

    private func addIgnoredPasteboardType() {
        let value = trimmed(newPasteboardType)
        guard !value.isEmpty else { return }
        ignoredPasteboardTypes = adding(value, to: ignoredPasteboardTypes)
        UserDefaults.standard.set(ignoredPasteboardTypes, forKey: ClipboardAppSettings.ignoredPasteboardTypesKey)
        newPasteboardType = ""
        services.refreshPrivacyPolicyFromSettings()
    }

    private func removeIgnoredPasteboardType(_ value: String) {
        ignoredPasteboardTypes.removeAll { $0 == value }
        UserDefaults.standard.set(ignoredPasteboardTypes, forKey: ClipboardAppSettings.ignoredPasteboardTypesKey)
        services.refreshPrivacyPolicyFromSettings()
    }

    private func addIgnoredAppBundleID() {
        let value = trimmed(newBundleID)
        guard !value.isEmpty else { return }
        ignoredAppBundleIDs = adding(value, to: ignoredAppBundleIDs)
        UserDefaults.standard.set(ignoredAppBundleIDs, forKey: ClipboardAppSettings.ignoredAppBundleIDsKey)
        newBundleID = ""
        services.refreshPrivacyPolicyFromSettings()
    }

    private func removeIgnoredAppBundleID(_ value: String) {
        ignoredAppBundleIDs.removeAll { $0 == value }
        UserDefaults.standard.set(ignoredAppBundleIDs, forKey: ClipboardAppSettings.ignoredAppBundleIDsKey)
        services.refreshPrivacyPolicyFromSettings()
    }

    private func adding(_ value: String, to values: [String]) -> [String] {
        Array(Set(values + [value])).sorted()
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
