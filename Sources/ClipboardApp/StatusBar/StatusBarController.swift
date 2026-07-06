import AppKit

@MainActor
final class StatusBarController {
    enum ClickAction {
        case openPanel
        case showMenu
        case togglePause
        case ignoreNextCopy
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

    /// Call when capture-paused state changes outside this controller
    /// (settings toggle, programmatic pause) so the icon stays in sync.
    func captureStateDidChange() {
        refreshIcon()
    }

    private func refreshIcon() {
        guard let button = statusItem?.button else { return }
        let paused = isCapturePaused()
        // Shape communicates paused state; tint communicates storage health.
        let symbolName = paused ? "pause.circle" : "doc.on.clipboard"
        let description = paused ? "Clipboard（已暂停采集）" : "Clipboard"
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        button.image?.isTemplate = true
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
        let modifiers = currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        switch Self.clickAction(for: currentEvent?.type, modifiers: modifiers) {
        case .openPanel:
            onLeftClick(iconOrigin)
        case .showMenu:
            showContextMenu()
        case .togglePause:
            onToggleCapture()
            refreshIcon()
        case .ignoreNextCopy:
            onIgnoreNextCopy()
        }
    }

    nonisolated static func clickAction(
        for eventType: NSEvent.EventType?,
        modifiers: NSEvent.ModifierFlags
    ) -> ClickAction {
        guard let eventType else {
            return .openPanel
        }
        if eventType == .rightMouseUp {
            return .showMenu
        }
        if modifiers.contains(.option) && modifiers.contains(.shift) {
            return .ignoreNextCopy
        }
        if modifiers.contains(.option) {
            return .togglePause
        }
        return .openPanel
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
        refreshIcon()
    }

    @MainActor @objc private func ignoreNextCopy() {
        onIgnoreNextCopy()
    }
}
