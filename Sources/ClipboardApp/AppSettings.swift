import AppKit
import Foundation
import Carbon

enum ClipboardAppSettings {
    // MARK: - Existing
    static let quickPanelReturnCopiesOnlyKey = "quickPanel.returnCopiesOnly"

    static func quickPanelReturnCopiesOnly(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: quickPanelReturnCopiesOnlyKey)
    }

    static func quickPanelAutoPasteEnabled(defaults: UserDefaults = .standard) -> Bool {
        !quickPanelReturnCopiesOnly(defaults: defaults)
    }

    // MARK: - Hotkey
    static let hotkeyKeyCodeKey = "hotkey.keyCode"
    static let hotkeyModifiersKey = "hotkey.modifiers"

    static func hotkeyKeyCode(defaults: UserDefaults = .standard) -> UInt32 {
        let stored = defaults.integer(forKey: hotkeyKeyCodeKey)
        return stored > 0 ? UInt32(stored) : UInt32(kVK_ANSI_V)
    }

    static func hotkeyModifiers(defaults: UserDefaults = .standard) -> UInt32 {
        let stored = defaults.integer(forKey: hotkeyModifiersKey)
        return stored > 0 ? UInt32(stored) : UInt32(cmdKey | shiftKey)
    }

    static func saveHotkey(keyCode: UInt32, modifiers: UInt32, defaults: UserDefaults = .standard) {
        defaults.set(Int(keyCode), forKey: hotkeyKeyCodeKey)
        defaults.set(Int(modifiers), forKey: hotkeyModifiersKey)
    }

    // MARK: - Panel Position
    static let panelPositionModeKey = "quickPanel.positionMode"

    static func panelPositionMode(defaults: UserDefaults = .standard) -> PanelPositionMode {
        guard let raw = defaults.string(forKey: panelPositionModeKey),
              let mode = PanelPositionMode(rawValue: raw) else {
            return .center
        }
        return mode
    }

    // MARK: - Launch
    static let hasLaunchedKey = "app.hasLaunched"

    static func hasLaunched(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: hasLaunchedKey)
    }

    static func markLaunched(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: hasLaunchedKey)
    }

    // MARK: - Storage

    static let maxHistoryCountStorageKey = "history.maxCount"  // 沿用旧 key，调整默认值
    static let defaultStorageMaxHistoryCount = 5000

    static func storageMaxHistoryCount(defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: maxHistoryCountStorageKey)
        return stored > 0 ? stored : defaultStorageMaxHistoryCount
    }

    static let maxAgeDaysKey = "storage.maxAgeDays"
    static let defaultMaxAgeDays = 180

    static func storageMaxAgeDays(defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: maxAgeDaysKey)
        return stored > 0 ? stored : defaultMaxAgeDays
    }

    static let failureRecoveryStrategyKey = "storage.failureRecoveryStrategy"

    static func storageFailureStrategy(defaults: UserDefaults = .standard) -> StorageFailureStrategy {
        guard let raw = defaults.string(forKey: failureRecoveryStrategyKey),
              let strategy = StorageFailureStrategy(rawValue: raw) else {
            return .continueEvicting
        }
        return strategy
    }

    static let notifyOnAutoEvictKey = "storage.notifyOnAutoEvict"

    static func storageNotifyOnAutoEvict(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: notifyOnAutoEvictKey) == nil { return true }
        return defaults.bool(forKey: notifyOnAutoEvictKey)
    }

    // MARK: - Appearance
    static let appearanceModeKey = "appearance.mode"

    static func appearanceMode(defaults: UserDefaults = .standard) -> AppearanceMode {
        guard let raw = defaults.string(forKey: appearanceModeKey),
              let mode = AppearanceMode(rawValue: raw) else {
            return .system
        }
        return mode
    }
}

// MARK: - Panel Position Mode
enum PanelPositionMode: String, CaseIterable {
    case center      = "center"
    case followMouse = "followMouse"
    case menuBar     = "menuBar"

    var displayName: String {
        switch self {
        case .center:      return "居中"
        case .followMouse: return "跟随鼠标"
        case .menuBar:     return "菜单栏图标下方"
        }
    }
}

// MARK: - Appearance Mode

enum AppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "浅色"
        case .dark:   return "深色"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Storage Failure Strategy

enum StorageFailureStrategy: String, CaseIterable {
    case continueEvicting
    case pauseMonitoring
    case skipRecord

    var displayName: String {
        switch self {
        case .continueEvicting: return "自动删除最旧记录直到能继续保存"
        case .pauseMonitoring:  return "暂停剪贴板监控"
        case .skipRecord:       return "跳过当前记录，不删除历史"
        }
    }
}
