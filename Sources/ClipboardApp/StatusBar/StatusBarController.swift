import AppKit

@MainActor
final class StatusBarController {
    enum ClickAction {
        case openPanel
        case showMenu
    }

    private var statusItem: NSStatusItem?
    private let onLeftClick: (NSPoint) -> Void
    private let onQuit: () -> Void
    private let onOpenSettings: () -> Void
    private let onToggleCapture: () -> Void
    private let onIgnoreNextCopy: () -> Void
    private let isCapturePaused: () -> Bool
    private var storageHealth: AppServices.StorageHealth = .ok

    init(
        onLeftClick: @escaping (NSPoint) -> Void,
        onQuit: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void = {},
        onToggleCapture: @escaping () -> Void = {},
        onIgnoreNextCopy: @escaping () -> Void = {},
        isCapturePaused: @escaping () -> Bool = { false }
    ) {
        self.onLeftClick = onLeftClick
        self.onQuit = onQuit
        self.onOpenSettings = onOpenSettings
        self.onToggleCapture = onToggleCapture
        self.onIgnoreNextCopy = onIgnoreNextCopy
        self.isCapturePaused = isCapturePaused
    }

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard")
        item.button?.image?.isTemplate = true
        item.button?.target = self
        item.button?.action = #selector(handleClick(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        refreshIcon()
    }

    // MARK: - Storage Health Badge

    /// Updates the status bar icon tint to reflect storage health state.
    /// - ok: default tint (nil)
    /// - disabled: orange tint
    /// - failing: red tint
    func updateStorageHealth(_ health: AppServices.StorageHealth) {
        storageHealth = health
        refreshIcon()
    }

    private func refreshIcon() {
        guard let button = statusItem?.button else { return }
        switch storageHealth {
        case .ok:
            button.contentTintColor = nil
        case .disabled:
            button.contentTintColor = .systemOrange
        case .failing:
            button.contentTintColor = .systemRed
        }
    }

    var iconOrigin: NSPoint {
        statusItem?.button?.window?.frame.origin ?? .zero
    }

    @MainActor @objc private func handleClick(_ sender: NSStatusBarButton) {
        let currentEvent = NSApp.currentEvent
        switch Self.clickAction(for: currentEvent?.type) {
        case .openPanel:
            onLeftClick(iconOrigin)
        case .showMenu:
            showContextMenu()
        }
    }

    nonisolated static func clickAction(for eventType: NSEvent.EventType?) -> ClickAction {
        guard let eventType else {
            return .openPanel
        }
        return eventType == .rightMouseUp ? .showMenu : .openPanel
    }

    @MainActor
    func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        let pauseTitle = isCapturePaused() ? "恢复采集" : "暂停采集"
        let pauseItem = NSMenuItem(title: pauseTitle, action: #selector(toggleCapture), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)

        let ignoreNextCopyItem = NSMenuItem(title: "忽略下一次复制", action: #selector(ignoreNextCopy), keyEquivalent: "")
        ignoreNextCopyItem.target = self
        menu.addItem(ignoreNextCopyItem)

        let settingsItem = NSMenuItem(title: "设置...", action: #selector(openSettingsAction), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 Clipboard", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    private func showContextMenu() {
        statusItem?.menu = makeContextMenu()
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @MainActor @objc private func openSettingsAction() {
        onOpenSettings()
    }

    @MainActor @objc private func quitAction() {
        onQuit()
    }

    @MainActor @objc private func toggleCapture() {
        onToggleCapture()
    }

    @MainActor @objc private func ignoreNextCopy() {
        onIgnoreNextCopy()
    }
}
