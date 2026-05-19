import AppKit
import Combine
import SwiftUI
import ClipboardCore
import ClipboardPlatform
import Carbon

@MainActor
@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    var services: AppServices!
    private var statusBarController: StatusBarController!
    private var hotKeyManager: HotKeyManager!
    private var welcomeWindowController: NSWindowController?
    private var settingsWindowController: NSWindowController?
    private var settingsWindow: NSWindow?
    private var healthSubscriber: AnyCancellable?

    // Explicit entry point: Swift's default `@main` synthesis on an
    // NSApplicationDelegate class does not set this instance as the application
    // delegate, so `applicationDidFinishLaunching` would never fire. We wire it
    // up manually here before starting the run loop.
    nonisolated static func main() {
        if CommandLine.arguments.contains(AccessibilityAuthorizationProbe.checkArgument) {
            let trusted = AccessibilityAuthorizationProbe.currentProcessTrusted()
            print(trusted ? "true" : "false")
            exit(0)
        }

        MainActor.assumeIsolated {
            let delegate = AppDelegate()
            NSApplication.shared.delegate = delegate
        }
        NSApplication.shared.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppearanceController.apply(ClipboardAppSettings.appearanceMode())
        services = AppServices()
        setupStatusBar()
        setupHotKey()
        checkFirstLaunch()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager.unregister()
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusBarController = StatusBarController(
            onLeftClick: { [weak self] iconOrigin in
                guard let self else { return }
                self.services.quickPanelController.statusBarIconOrigin = iconOrigin
                self.services.quickPanelController.toggle(trigger: .statusBarClick(iconOrigin: iconOrigin))
            },
            onQuit: {
                NSApp.terminate(nil)
            },
            onOpenSettings: { [weak self] in
                self?.openSettings()
            },
            onToggleCapture: { [weak self] in
                guard let self else { return }
                if self.services.capturePaused {
                    self.services.resumeCapture()
                } else {
                    self.services.pauseCapture()
                }
            },
            onIgnoreNextCopy: { [weak self] in
                self?.services.ignoreNextCopy()
            },
            isCapturePaused: { [weak self] in
                self?.services.capturePaused ?? false
            }
        )
        statusBarController.setup()
        statusBarController.updateStorageHealth(services.storageHealth)

        // Keep the status bar icon in sync with runtime health changes.
        healthSubscriber = services.$storageHealth.sink { [weak self] health in
            self?.statusBarController.updateStorageHealth(health)
        }
    }

    // MARK: - Hot Key

    private func setupHotKey() {
        hotKeyManager = HotKeyManager()
        let keyCode = ClipboardAppSettings.hotkeyKeyCode()
        let modifiers = ClipboardAppSettings.hotkeyModifiers()

        do {
            try hotKeyManager.register(keyCode: keyCode, modifiers: modifiers) { [weak self] in
                guard let self else { return }
                let iconOrigin = self.statusBarController.iconOrigin
                self.services.quickPanelController.statusBarIconOrigin = iconOrigin
                self.services.quickPanelController.toggle(trigger: .hotkey)
            }
        } catch {
            NSLog("Failed to register hotkey: \(error). Retrying with default Cmd+Shift+V.")
            tryRegisterDefaultHotKey()
        }
    }

    private func tryRegisterDefaultHotKey() {
        let defaultKeyCode = UInt32(kVK_ANSI_V)
        let defaultModifiers = UInt32(cmdKey | shiftKey)
        do {
            try hotKeyManager.register(keyCode: defaultKeyCode, modifiers: defaultModifiers) { [weak self] in
                self?.services.quickPanelController.toggle(trigger: .hotkey)
            }
            ClipboardAppSettings.saveHotkey(keyCode: defaultKeyCode, modifiers: defaultModifiers)
        } catch {
            NSLog("Failed to register default hotkey Cmd+Shift+V: \(error). Hotkey unavailable.")
        }
    }

    // MARK: - First Launch

    private func checkFirstLaunch() {
        guard !ClipboardAppSettings.hasLaunched() else { return }
        showWelcomeWindow()
    }

    private func showWelcomeWindow() {
        let welcomeView = WelcomeView { [weak self] in
            ClipboardAppSettings.markLaunched()
            self?.welcomeWindowController?.close()
            self?.welcomeWindowController = nil
        }
        let hostingController = NSHostingController(rootView: welcomeView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "欢迎使用 Clipboard"
        window.styleMask = NSWindow.StyleMask([.titled, .closable])
        window.setFrame(NSRect(x: 0, y: 0, width: 480, height: 360), display: true)
        window.center()
        window.isReleasedWhenClosed = false
        let wc = NSWindowController(window: window)
        wc.showWindow(nil as AnyObject?)
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindowController = wc
    }

    // MARK: - Settings Window

    func openSettings() {
        // Dismiss the QuickPanel first: NSPanel.hidesOnDeactivate only fires
        // when the entire NSApplication deactivates, so opening another window
        // within the same app would otherwise leave the QuickPanel visible.
        services.quickPanelController.hide()

        if let existing = settingsWindow, existing.isVisible || existing.isMiniaturized {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let settingsView = SettingsRootView(services: services, hotKeyManager: hotKeyManager)
        let hostingController = NSHostingController(rootView: settingsView)
        let window = ClipboardSettingsWindow(contentViewController: hostingController)
        window.title = "设置"
        window.styleMask = NSWindow.StyleMask([.titled, .closable, .resizable])
        window.setFrame(NSRect(x: 0, y: 0, width: 660, height: 480), display: true)
        window.minSize = NSSize(width: 560, height: 380)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        settingsWindow = window
        let wc = NSWindowController(window: window)
        wc.showWindow(nil as AnyObject?)
        settingsWindowController = wc
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension AppDelegate {
    static var shared: AppDelegate {
        NSApp.delegate as! AppDelegate
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        settingsWindow = nil
        settingsWindowController = nil
    }
}
