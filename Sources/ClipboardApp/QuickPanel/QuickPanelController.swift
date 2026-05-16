import AppKit
import SwiftUI
import ClipboardCore

// MARK: - Trigger Source

/// Describes how the QuickPanel was asked to appear.
/// The trigger source determines which positioning strategy is used.
enum TriggerSource {
    /// Panel was summoned via the global hot key.
    case hotkey
    /// Panel was summoned by clicking the status-bar icon.
    /// - Parameter iconOrigin: Bottom-left corner of the icon in screen coordinates.
    case statusBarClick(iconOrigin: NSPoint)
}

// MARK: - QuickPanelController

@MainActor
final class QuickPanelController {
    private let state: QuickPanelState
    private let prepareForShow: @MainActor () async -> Void
    private let autoPasteEnabled: () -> Bool
    private let isAutoPasteAuthorized: () -> Bool
    private let requestAccessibilityAuthorizationAction: () -> Void
    private let openSelectionBehavior: () -> QuickPanelOpenSelectionBehavior
    private let activatePreviousApplication: (NSRunningApplication?) -> Void
    private var panel: NSPanel?
    private var previousApplication: NSRunningApplication?

    /// Bottom-left origin of the status-bar icon, updated by the menu-bar item
    /// before calling `toggle(trigger: .statusBarClick(...))`.
    var statusBarIconOrigin: NSPoint = .zero

    init(
        state: QuickPanelState,
        prepareForShow: @escaping @MainActor () async -> Void = {},
        autoPasteEnabled: @escaping () -> Bool = { ClipboardAppSettings.quickPanelAutoPasteEnabled() },
        isAutoPasteAuthorized: @escaping () -> Bool = { AccessibilityAuthorizationProbe.settingsTrusted() },
        requestAccessibilityAuthorization: @escaping () -> Void = { AccessibilityAuthorizationProbe.requestAuthorizationPrompt() },
        openSelectionBehavior: @escaping () -> QuickPanelOpenSelectionBehavior = { ClipboardAppSettings.quickPanelOpenSelectionBehavior() },
        activatePreviousApplication: @escaping (NSRunningApplication?) -> Void = { app in
            guard let app, !app.isTerminated else { return }
            app.activate(options: [.activateAllWindows])
        }
    ) {
        self.state = state
        self.prepareForShow = prepareForShow
        self.autoPasteEnabled = autoPasteEnabled
        self.isAutoPasteAuthorized = isAutoPasteAuthorized
        self.requestAccessibilityAuthorizationAction = requestAccessibilityAuthorization
        self.openSelectionBehavior = openSelectionBehavior
        self.activatePreviousApplication = activatePreviousApplication
    }

    func toggle(trigger: TriggerSource = .hotkey) {
        if panel?.isVisible == true {
            cancel()
        } else {
            show(trigger: trigger)
        }
    }

    func show(trigger: TriggerSource = .hotkey) {
        rememberPreviousApplication()
        let panel = panel ?? makePanel()
        self.panel = panel

        state.prepareForPresentation(openSelectionBehavior: openSelectionBehavior())
        position(panel, trigger: trigger)
        present(panel)

        Task { @MainActor in
            await prepareForShow()
            await state.refresh()
            guard panel.isVisible else { return }
            focusSearchField(in: panel)
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func cancel() {
        hide()
        activatePreviousApplication(previousApplication)
    }

    // MARK: - Private

    private func makePanel() -> NSPanel {
        let content = QuickPanelView(
            state: state,
            onClose: { [weak self] in self?.cancel() },
            onSubmit: { [weak self] in self?.submitSelection() },
            onCopyOnly: { [weak self] in self?.copySelectionOnly() },
            onRequestAccessibilityAuthorization: { [weak self] in self?.requestAccessibilityAuthorization() }
        )
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Clipboard QuickPanel"
        panel.contentView = NSHostingView(rootView: content)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        return panel
    }

    /// Positions the panel based on how it was triggered.
    /// - Status-bar clicks always use `statusBarClickOrigin`.
    /// - Hot-key invocations respect the user's `PanelPositionMode` preference.
    private func position(_ panel: NSPanel, trigger: TriggerSource) {
        let visibleFrame = PanelPositionCalculator.mouseScreen()?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900) // last resort fallback
        let size = panel.frame.size

        let origin: NSPoint
        switch trigger {
        case .statusBarClick(let iconOrigin):
            origin = PanelPositionCalculator.statusBarClickOrigin(
                iconOrigin: iconOrigin, panelSize: size, visibleFrame: visibleFrame
            )
        case .hotkey:
            let mode = ClipboardAppSettings.panelPositionMode()
            switch mode {
            case .center:
                origin = PanelPositionCalculator.centerOrigin(
                    panelSize: size, visibleFrame: visibleFrame
                )
            case .followMouse:
                origin = PanelPositionCalculator.followMouseOrigin(
                    panelSize: size, visibleFrame: visibleFrame
                )
            case .menuBar:
                // Use the last known status-bar icon position when available;
                // fall back to center when the origin has not been set yet.
                if statusBarIconOrigin != .zero {
                    origin = PanelPositionCalculator.statusBarClickOrigin(
                        iconOrigin: statusBarIconOrigin, panelSize: size, visibleFrame: visibleFrame
                    )
                } else {
                    origin = PanelPositionCalculator.centerOrigin(
                        panelSize: size, visibleFrame: visibleFrame
                    )
                }
            }
        }

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func present(_ panel: NSPanel) {
        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        focusSearchField(in: panel)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self, weak panel] in
            guard let self, let panel, panel.isVisible else { return }
            NSApp.activate(ignoringOtherApps: true)
            panel.orderFrontRegardless()
            panel.makeKeyAndOrderFront(nil)
            self.focusSearchField(in: panel)
        }
    }

    private func rememberPreviousApplication() {
        let front = NSWorkspace.shared.frontmostApplication
        previousApplication = front?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : front
    }

    func submitSelection() {
        let targetApplication = previousApplication
        let autoPaste = autoPasteEnabled()
        if autoPaste && !isAutoPasteAuthorized() {
            state.reportAutoPasteRequiresAccessibilityPermission()
            return
        }

        hide()
        activatePreviousApplication(targetApplication)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            await state.selectCurrent(autoPaste: autoPaste)
        }
    }

    func copySelectionOnly() {
        let targetApplication = previousApplication
        hide()
        activatePreviousApplication(targetApplication)
        Task { @MainActor in
            await state.selectCurrent(autoPaste: false)
        }
    }

    func requestAccessibilityAuthorization() {
        requestAccessibilityAuthorizationAction()
    }

    private func focusSearchField(in panel: NSPanel, attemptsRemaining: Int = 4) {
        guard attemptsRemaining > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak panel] in
            guard let panel else { return }
            if let tf = panel.contentView?.firstSubview(of: NSTextField.self) {
                panel.makeFirstResponder(tf)
            } else {
                self.focusSearchField(in: panel, attemptsRemaining: attemptsRemaining - 1)
            }
        }
    }
}

// MARK: - Private helpers

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private extension NSView {
    func firstSubview<T: NSView>(of type: T.Type) -> T? {
        if let v = self as? T { return v }
        for sub in subviews {
            if let match = sub.firstSubview(of: type) { return match }
        }
        return nil
    }
}
