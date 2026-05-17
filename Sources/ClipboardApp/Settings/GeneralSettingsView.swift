import AppKit
import Carbon
import SwiftUI

struct GeneralSettingsView: View {
    let hotKeyManager: HotKeyManager
    private let accessibilityRefreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    @AppStorage(ClipboardAppSettings.hotkeyKeyCodeKey)
    private var storedKeyCode: Int = Int(kVK_ANSI_V)

    @AppStorage(ClipboardAppSettings.hotkeyModifiersKey)
    private var storedModifiers: Int = Int(cmdKey | shiftKey)

    @AppStorage(ClipboardAppSettings.panelPositionModeKey)
    private var positionModeRaw: String = PanelPositionMode.center.rawValue

    @AppStorage(ClipboardAppSettings.quickPanelOpenSelectionBehaviorKey)
    private var openSelectionBehaviorRaw: String = QuickPanelOpenSelectionBehavior.latestRecord.rawValue

    @AppStorage(ClipboardAppSettings.quickPanelReturnCopiesOnlyKey)
    private var returnCopiesOnly: Bool = false

    @AppStorage(ClipboardAppSettings.appearanceModeKey)
    private var appearanceModeRaw: String = AppearanceMode.system.rawValue

    @State private var conflictMessage: String = ""
    @StateObject private var accessibilityPermission = AccessibilityPermissionState()

    private var positionMode: Binding<PanelPositionMode> {
        Binding(
            get: { PanelPositionMode(rawValue: positionModeRaw) ?? .center },
            set: { positionModeRaw = $0.rawValue }
        )
    }

    private var appearanceMode: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceModeRaw) ?? .system },
            set: { appearanceModeRaw = $0.rawValue }
        )
    }

    private var openSelectionBehavior: Binding<QuickPanelOpenSelectionBehavior> {
        Binding(
            get: { QuickPanelOpenSelectionBehavior(rawValue: openSelectionBehaviorRaw) ?? .latestRecord },
            set: { openSelectionBehaviorRaw = $0.rawValue }
        )
    }

    private var selectionBehavior: Binding<QuickPanelSelectionBehavior> {
        Binding(
            get: { QuickPanelSelectionBehavior(returnCopiesOnly: returnCopiesOnly) },
            set: { returnCopiesOnly = $0.returnCopiesOnly }
        )
    }

    var body: some View {
        Form {
            Section("外观") {
                Picker("色系", selection: appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearanceModeRaw) { _, newRaw in
                    let mode = AppearanceMode(rawValue: newRaw) ?? .system
                    AppearanceController.apply(mode)
                }
            }

            Section("辅助功能权限") {
                HStack {
                    if accessibilityPermission.isAuthorized {
                        Label("已授权", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("未授权 — 自动粘贴功能不可用", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("授权辅助功能") {
                            accessibilityPermission.requestAuthorizationPrompt()
                        }
                    }
                }
                Text("辅助功能权限只用于自动粘贴。仅复制模式不需要此权限。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !accessibilityPermission.isAuthorized && accessibilityPermission.usesAdHocSignature {
                    Text("当前运行的是临时签名构建。系统设置里同名 ClipboardApp.app 可能指向旧构建；重新构建后请移除旧条目并重新授权当前 App，或使用稳定签名重新构建。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("全局快捷键") {
                HStack {
                    Text("呼出快捷面板")
                    Spacer()
                    HotKeyRecorderView(
                        keyCode: UInt32(storedKeyCode),
                        modifiers: UInt32(storedModifiers),
                        onCommit: { newKC, newMods in
                            storedKeyCode = Int(newKC)
                            storedModifiers = Int(newMods)
                            reRegisterHotKey(keyCode: newKC, modifiers: newMods)
                        },
                        onConflict: { msg in conflictMessage = msg }
                    )
                }
                if !conflictMessage.isEmpty {
                    Text(conflictMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section("快捷面板位置") {
                Picker("触发方式为快捷键时", selection: positionMode) {
                    ForEach(PanelPositionMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text("通过菜单栏图标点击时，面板始终在图标下方显示。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("打开时默认选中", selection: openSelectionBehavior) {
                    ForEach(QuickPanelOpenSelectionBehavior.allCases) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                }
                .pickerStyle(.segmented)

                Text((QuickPanelOpenSelectionBehavior(rawValue: openSelectionBehaviorRaw) ?? .latestRecord).settingsDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("粘贴行为") {
                Picker("选择历史项后的行为", selection: selectionBehavior) {
                    ForEach(QuickPanelSelectionBehavior.allCases) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                }
                .pickerStyle(.segmented)

                Text(QuickPanelSelectionBehavior(returnCopiesOnly: returnCopiesOnly).settingsDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !returnCopiesOnly && !accessibilityPermission.isAuthorized {
                    HStack {
                        Label("自动粘贴当前不可用：请授权辅助功能，或切换为仅复制。", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("授权辅助功能") {
                            accessibilityPermission.requestAuthorizationPrompt()
                        }
                    }
                    .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { accessibilityPermission.refresh() }
        .onReceive(accessibilityRefreshTimer) { _ in
            accessibilityPermission.refresh()
        }
    }

    private func reRegisterHotKey(keyCode: UInt32, modifiers: UInt32) {
        Task { @MainActor in
            do {
                try hotKeyManager.register(keyCode: keyCode, modifiers: modifiers) {
                    AppDelegate.shared.services.quickPanelController.toggle(trigger: .hotkey)
                }
                conflictMessage = ""
            } catch {
                conflictMessage = "注册快捷键失败: \(error.localizedDescription)"
            }
        }
    }
}
