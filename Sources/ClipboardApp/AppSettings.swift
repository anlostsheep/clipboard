import Foundation

enum ClipboardAppSettings {
  static let quickPanelReturnCopiesOnlyKey = "quickPanel.returnCopiesOnly"

  static func quickPanelReturnCopiesOnly(defaults: UserDefaults = .standard) -> Bool {
    defaults.bool(forKey: quickPanelReturnCopiesOnlyKey)
  }

  static func quickPanelAutoPasteEnabled(defaults: UserDefaults = .standard) -> Bool {
    !quickPanelReturnCopiesOnly(defaults: defaults)
  }
}
