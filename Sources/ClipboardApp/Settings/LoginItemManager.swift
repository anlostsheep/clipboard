import Foundation
import ServiceManagement

enum LoginItemStatus: Equatable {
    case enabled
    case notRegistered
    case requiresApproval
    case unsupported(reason: String)
}

@MainActor
protocol LoginItemManaging {
    func currentStatus() -> LoginItemStatus
    func setEnabled(_ enabled: Bool) throws
    func openSystemLoginItemsSettings()
}

/// Real implementation backed by SMAppService. Status is always read live from
/// the system (never cached in UserDefaults) because users can change login
/// items directly in System Settings.
@MainActor
final class SMAppServiceLoginItemManager: LoginItemManaging {
    func currentStatus() -> LoginItemStatus {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return .unsupported(reason: "当前不是从 .app 包运行（例如 swift run），无法注册登录项。")
        }
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound:
            return .notRegistered
        @unknown default:
            return .notRegistered
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    func openSystemLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Pure presentation mapping so the settings UI logic is unit-testable
/// without SwiftUI or the real SMAppService.
struct LoginItemSettingPresentation: Equatable {
    let isOn: Bool
    let isToggleEnabled: Bool
    let hint: String?
    let showsOpenSettingsButton: Bool

    static func make(from status: LoginItemStatus) -> LoginItemSettingPresentation {
        switch status {
        case .enabled:
            return LoginItemSettingPresentation(
                isOn: true, isToggleEnabled: true, hint: nil, showsOpenSettingsButton: false)
        case .notRegistered:
            return LoginItemSettingPresentation(
                isOn: false, isToggleEnabled: true, hint: nil, showsOpenSettingsButton: false)
        case .requiresApproval:
            return LoginItemSettingPresentation(
                isOn: false, isToggleEnabled: true,
                hint: "系统尚未批准登录项，请在「系统设置 › 通用 › 登录项」中允许。",
                showsOpenSettingsButton: true)
        case .unsupported(let reason):
            return LoginItemSettingPresentation(
                isOn: false, isToggleEnabled: false, hint: reason, showsOpenSettingsButton: false)
        }
    }
}
