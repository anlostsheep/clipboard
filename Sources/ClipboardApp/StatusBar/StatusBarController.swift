import AppKit

@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem?
    private let onLeftClick: (NSPoint) -> Void
    private let onQuit: () -> Void

    init(onLeftClick: @escaping (NSPoint) -> Void, onQuit: @escaping () -> Void) {
        self.onLeftClick = onLeftClick
        self.onQuit = onQuit
    }

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Clipboard")
        item.button?.image?.isTemplate = true
        item.button?.target = self
        item.button?.action = #selector(handleClick(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    var iconOrigin: NSPoint {
        statusItem?.button?.window?.frame.origin ?? .zero
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            onLeftClick(iconOrigin)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "退出 Clipboard",
            action: #selector(quitAction),
            keyEquivalent: "q"
        ))
        menu.items.last?.target = self

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func quitAction() {
        onQuit()
    }
}
