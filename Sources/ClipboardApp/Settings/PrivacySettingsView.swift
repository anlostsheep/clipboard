import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PrivacySettingsView: View {
    struct CaptureControlPresentation: Equatable {
        let statusText: String
        let statusSystemImage: String
        let toggleButtonTitle: String
        let toggleButtonSystemImage: String
        let ignoreNextCopyButtonTitle: String
        let ignoreNextCopyButtonSystemImage: String
    }

    struct IgnoredEntryPresentation: Equatable {
        let accessibilityLabel: String
        let inputStyle: IgnoredEntryInputStyle
        let placeholder: String
        let caption: String
    }

    struct IgnoredAppsSectionPresentation: Equatable {
        let title: String
        let chooseButtonTitle: String
        let caption: String
    }

    struct IgnoredAppPresentation: Equatable {
        let bundleID: String
        let displayName: String
        let detail: String
        let isResolved: Bool
    }

    struct AdvancedPasteboardTypePresentation: Equatable {
        let title: String
        let isExpandedByDefault: Bool
    }

    enum IgnoredEntryInputStyle: Equatable {
        case inlinePlain
    }

    @ObservedObject var services: AppServices

    @AppStorage(ClipboardAppSettings.ignoreUniversalClipboardKey)
    private var ignoreUniversalClipboard: Bool = false

    @State private var ignoredPasteboardTypes: [String] = []
    @State private var ignoredAppBundleIDs: [String] = []
    @State private var newPasteboardType = ""
    @State private var isAdvancedPasteboardTypesExpanded = false
    @State private var ignoredAppSelectionMessage: String?

    var body: some View {
        Form {
            Section("采集控制") {
                HStack {
                    Label(
                        captureControlPresentation.statusText,
                        systemImage: captureControlPresentation.statusSystemImage
                    )
                    .foregroundStyle(services.capturePaused ? Color.orange : Color.green)

                    Spacer()

                    Button {
                        toggleCapture()
                    } label: {
                        Label(
                            captureControlPresentation.toggleButtonTitle,
                            systemImage: captureControlPresentation.toggleButtonSystemImage
                        )
                    }
                }

                Button {
                    services.ignoreNextCopy()
                } label: {
                    Label(
                        captureControlPresentation.ignoreNextCopyButtonTitle,
                        systemImage: captureControlPresentation.ignoreNextCopyButtonSystemImage
                    )
                }
                .disabled(services.capturePaused)
            }

            Section("Universal Clipboard") {
                Toggle("忽略来自其他 Apple 设备的剪贴板内容", isOn: $ignoreUniversalClipboard)
                Text("开启后，通过 Universal Clipboard 从 iPhone/iPad 复制的内容不会被记录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(Self.ignoredAppsSectionPresentation().title) {
                ForEach(ignoredAppBundleIDs, id: \.self) { bundleID in
                    IgnoredAppRow(
                        presentation: resolvedIgnoredAppPresentation(for: bundleID),
                        icon: resolvedIgnoredAppIcon(for: bundleID)
                    ) {
                        removeIgnoredAppBundleID(bundleID)
                    }
                }

                Button {
                    chooseIgnoredApplication()
                } label: {
                    Label(Self.ignoredAppsSectionPresentation().chooseButtonTitle, systemImage: "plus")
                }

                Text(Self.ignoredAppsSectionPresentation().caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let ignoredAppSelectionMessage {
                    Text(ignoredAppSelectionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                DisclosureGroup(
                    Self.advancedPasteboardTypePresentation().title,
                    isExpanded: $isAdvancedPasteboardTypesExpanded
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(ignoredPasteboardTypes, id: \.self) { type in
                            HStack {
                                Text(type)
                                Spacer()
                                Button("移除") {
                                    removeIgnoredPasteboardType(type)
                                }
                            }
                        }

                        IgnoredEntryInputRow(
                            presentation: Self.ignoredPasteboardTypeEntryPresentation(),
                            text: $newPasteboardType,
                            canAdd: Self.canAddIgnoredEntry(newPasteboardType),
                            onSubmit: addIgnoredPasteboardType,
                            onAdd: addIgnoredPasteboardType
                        )

                        Text(Self.ignoredPasteboardTypeEntryPresentation().caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadSettings)
        .onChange(of: ignoreUniversalClipboard) { _, _ in
            services.refreshPrivacyPolicyFromSettings()
        }
    }

    static func captureControlPresentation(isPaused: Bool) -> CaptureControlPresentation {
        CaptureControlPresentation(
            statusText: isPaused ? "已暂停" : "正在采集",
            statusSystemImage: isPaused ? "pause.circle.fill" : "record.circle",
            toggleButtonTitle: isPaused ? "恢复采集" : "暂停采集",
            toggleButtonSystemImage: isPaused ? "play.circle" : "pause.circle",
            ignoreNextCopyButtonTitle: "忽略下一次复制",
            ignoreNextCopyButtonSystemImage: "forward.end.circle"
        )
    }

    static func ignoredPasteboardTypeEntryPresentation() -> IgnoredEntryPresentation {
        IgnoredEntryPresentation(
            accessibilityLabel: "排除的剪贴板类型",
            inputStyle: .inlinePlain,
            placeholder: "输入 pasteboard type",
            caption: "例如 com.example.secret。标准隐藏类型会继续自动过滤；这里用于额外排除自定义 pasteboard type。"
        )
    }

    static func ignoredAppsSectionPresentation() -> IgnoredAppsSectionPresentation {
        IgnoredAppsSectionPresentation(
            title: "不记录这些应用",
            chooseButtonTitle: "选择应用...",
            caption: "选择应用后，来自这些应用的剪贴板内容不会进入历史记录。"
        )
    }

    static func ignoredAppPresentation(bundleID: String, resolvedAppName: String?) -> IgnoredAppPresentation {
        let trimmedBundleID = trimmedValue(bundleID)
        let trimmedAppName = trimmedValue(resolvedAppName ?? "")

        guard !trimmedAppName.isEmpty else {
            return IgnoredAppPresentation(
                bundleID: trimmedBundleID,
                displayName: trimmedBundleID.isEmpty ? "未知应用" : trimmedBundleID,
                detail: "未找到应用",
                isResolved: false
            )
        }

        return IgnoredAppPresentation(
            bundleID: trimmedBundleID,
            displayName: trimmedAppName,
            detail: trimmedBundleID,
            isResolved: true
        )
    }

    static func advancedPasteboardTypePresentation() -> AdvancedPasteboardTypePresentation {
        AdvancedPasteboardTypePresentation(
            title: "高级：排除自定义剪贴板类型",
            isExpandedByDefault: false
        )
    }

    static func canAddIgnoredEntry(_ value: String) -> Bool {
        !trimmedValue(value).isEmpty
    }

    private var captureControlPresentation: CaptureControlPresentation {
        Self.captureControlPresentation(isPaused: services.capturePaused)
    }

    private func toggleCapture() {
        if services.capturePaused {
            services.resumeCapture()
        } else {
            services.pauseCapture()
        }
    }

    private func loadSettings() {
        ignoredPasteboardTypes = ClipboardAppSettings.ignoredPasteboardTypes().sorted()
        ignoredAppBundleIDs = ClipboardAppSettings.ignoredAppBundleIDs().sorted()
        isAdvancedPasteboardTypesExpanded = Self.advancedPasteboardTypePresentation().isExpandedByDefault
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

    private func chooseIgnoredApplication() {
        let settingsWindow = NSApp.keyWindow ?? NSApp.mainWindow
        let panel = NSOpenPanel()
        panel.title = "选择不记录的应用"
        panel.message = "来自所选应用的剪贴板内容不会进入历史记录。"
        panel.prompt = "选择"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.application]

        defer {
            ClipboardSettingsWindow.restoreAfterExternalAuthorizationPrompt(settingsWindow)
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        addIgnoredApplication(at: url)
    }

    private func addIgnoredApplication(at url: URL) {
        guard let bundleID = Bundle(url: url)?.bundleIdentifier,
              !trimmed(bundleID).isEmpty
        else {
            ignoredAppSelectionMessage = "无法读取所选应用。"
            return
        }

        ignoredAppBundleIDs = adding(trimmed(bundleID), to: ignoredAppBundleIDs)
        UserDefaults.standard.set(ignoredAppBundleIDs, forKey: ClipboardAppSettings.ignoredAppBundleIDsKey)
        ignoredAppSelectionMessage = "已添加 \(Self.applicationDisplayName(at: url) ?? url.deletingPathExtension().lastPathComponent)"
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

    private func resolvedIgnoredAppPresentation(for bundleID: String) -> IgnoredAppPresentation {
        let value = trimmed(bundleID)
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: value) else {
            return Self.ignoredAppPresentation(bundleID: value, resolvedAppName: nil)
        }

        return Self.ignoredAppPresentation(
            bundleID: value,
            resolvedAppName: Self.applicationDisplayName(at: appURL)
        )
    }

    private func resolvedIgnoredAppIcon(for bundleID: String) -> NSImage? {
        let value = trimmed(bundleID)
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: value) else {
            return nil
        }

        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 24, height: 24)
        return icon
    }

    private static func applicationDisplayName(at url: URL) -> String? {
        let bundle = Bundle(url: url)
        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        let fileName = url.deletingPathExtension().lastPathComponent
        return [displayName, bundleName, fileName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private func trimmed(_ value: String) -> String {
        Self.trimmedValue(value)
    }

    private static func trimmedValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct IgnoredEntryInputRow: View {
    let presentation: PrivacySettingsView.IgnoredEntryPresentation
    @Binding var text: String
    let canAdd: Bool
    let onSubmit: () -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(presentation.placeholder)
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }

                PlainInlineTextField(
                    text: $text,
                    accessibilityLabel: presentation.accessibilityLabel,
                    onSubmit: onSubmit
                )
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .contentShape(Rectangle())

            Button("添加", action: onAdd)
                .disabled(!canAdd)
        }
    }
}

private struct IgnoredAppRow: View {
    let presentation: PrivacySettingsView.IgnoredAppPresentation
    let icon: NSImage?
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.displayName)
                Text(presentation.detail)
                    .font(.caption)
                    .foregroundStyle(presentation.isResolved ? Color.secondary : Color.orange)
            }

            Spacer()

            Button("移除", action: onRemove)
        }
    }
}

private struct PlainInlineTextField: NSViewRepresentable {
    @Binding var text: String
    let accessibilityLabel: String
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .left
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.wraps = false
        field.delegate = context.coordinator
        field.setAccessibilityLabel(accessibilityLabel)
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.setAccessibilityLabel(accessibilityLabel)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private var parent: PlainInlineTextField

        init(_ parent: PlainInlineTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }

            return false
        }
    }
}
