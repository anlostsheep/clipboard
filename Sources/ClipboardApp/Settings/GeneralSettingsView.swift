import AppKit
import Carbon
import SwiftUI

struct GeneralSettingsView: View {
    let hotKeyManager: HotKeyManager

    @AppStorage(ClipboardAppSettings.hotkeyKeyCodeKey)
    private var storedKeyCode: Int = Int(kVK_ANSI_V)

    @AppStorage(ClipboardAppSettings.hotkeyModifiersKey)
    private var storedModifiers: Int = Int(cmdKey | shiftKey)

    @AppStorage(ClipboardAppSettings.panelPositionModeKey)
    private var positionModeRaw: String = PanelPositionMode.center.rawValue

    @AppStorage(ClipboardAppSettings.quickPanelReturnCopiesOnlyKey)
    private var returnCopiesOnly: Bool = false

    @State private var conflictMessage: String = ""
    @State private var isAuthorized: Bool = false

    private var positionMode: Binding<PanelPositionMode> {
        Binding(
            get: { PanelPositionMode(rawValue: positionModeRaw) ?? .center },
            set: { positionModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("辅助功能权限") {
                HStack {
                    if isAuthorized {
                        Label("已授权", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("未授权 — 自动粘贴功能不可用", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("授权辅助功能") {
                            requestAccessibilityPermission()
                        }
                    }
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
            }

            Section("粘贴行为") {
                Toggle("Return 仅复制，不自动粘贴", isOn: $returnCopiesOnly)
                Text("开启后，选择历史记录只写入剪贴板，需手动按 Command+V 粘贴。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { isAuthorized = AXIsProcessTrusted() }
    }

    /// Triggers the macOS native accessibility prompt. The system dialog's
    /// "Open System Settings" button pre-populates this app in the Accessibility
    /// list — no manual "+" step required.
    private func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
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
