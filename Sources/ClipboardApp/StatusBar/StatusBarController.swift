import AppKit

@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem?
    private let onLeftClick: (NSPoint) -> Void
    private let onQuit: () -> Void
    private var storageHealth: AppServices.StorageHealth = .ok

    init(onLeftClick: @escaping (NSPoint) -> Void, onQuit: @escaping () -> Void) {
        self.onLeftClick = onLeftClick
        self.onQuit = onQuit
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
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            onLeftClick(iconOrigin)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let quitItem = NSMenuItem(title: "退出 Clipboard", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @MainActor @objc private func quitAction() {
        onQuit()
    }
}
