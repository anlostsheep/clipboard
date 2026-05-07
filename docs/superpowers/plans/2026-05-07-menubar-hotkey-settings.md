# Menu Bar App + Hotkey Config + Panel Position Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform ClipboardApp from a WindowGroup app into a pure menu bar app with configurable global hotkey, configurable quick panel position, and a settings window accessed via a ⚙️ button.

**Architecture:** AppDelegate replaces `@main ClipboardApp`; NSStatusItem handles left/right click; HotKeyManager actor replaces the hardcoded GlobalHotKeyRegistrar; QuickPanelController gains TriggerSource-aware position logic; a SwiftUI NavigationSplitView settings window replaces the main window.

**Tech Stack:** Swift 5.10+, SwiftUI, AppKit, Carbon Events API, Swift Concurrency (actor/async/await), UserDefaults / @AppStorage

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Sources/ClipboardApp/App/AppDelegate.swift` | **Create** | NSApplicationDelegate entry point; owns StatusBarController, HotKeyManager, QuickPanelController |
| `Sources/ClipboardApp/App/ClipboardApp.swift` | **Delete** | Replaced by AppDelegate |
| `Sources/ClipboardApp/App/AppSettings.swift` | **Modify** | Add hotkey, position, hasLaunched keys |
| `Sources/ClipboardApp/StatusBar/StatusBarController.swift` | **Create** | NSStatusItem, left/right click handling |
| `Sources/ClipboardApp/HotKey/HotKeyManager.swift` | **Create** | Actor: register, unregister, conflict detection, persistence |
| `Sources/ClipboardApp/HotKey/GlobalHotKeyRegistrar.swift` | **Delete** | Superseded by HotKeyManager |
| `Sources/ClipboardApp/QuickPanel/QuickPanelController.swift` | **Modify** | Add PanelPositionMode, TriggerSource, new position logic |
| `Sources/ClipboardApp/QuickPanel/QuickPanelView.swift` | **Modify** | Add ⚙️ button in top-right corner |
| `Sources/ClipboardApp/Settings/SettingsWindow.swift` | **Create** | SwiftUI Window(id: "settings") + NavigationSplitView shell |
| `Sources/ClipboardApp/Settings/GeneralSettingsView.swift` | **Create** | Hotkey recorder, position picker, return-copies-only toggle, permission card |
| `Sources/ClipboardApp/Settings/PrivacySettingsView.swift` | **Create** | Excluded apps list, Universal Clipboard toggle |
| `Sources/ClipboardApp/Settings/HistorySettingsView.swift` | **Create** | Max history count stepper, clear history button |
| `Sources/ClipboardApp/Settings/HotKeyRecorderView.swift` | **Create** | NSViewRepresentable keyboard capture component |
| `Sources/ClipboardApp/Welcome/WelcomeView.swift` | **Create** | First-launch permission guidance window |
| `Sources/ClipboardApp/App/Info.plist` | **Modify** | Add LSUIElement = YES |
| `Tests/ClipboardCoreTests/HotKeyManagerTests.swift` | **Create** | Unit tests for conflict detection and persistence |
| `Tests/ClipboardCoreTests/PanelPositionTests.swift` | **Create** | Unit tests for position calculation logic |

---

## Task 1: Extend AppSettings with New Keys

**Files:**
- Modify: `Sources/ClipboardApp/App/AppSettings.swift`

- [ ] **Step 1: Replace the file contents**

```swift
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
        let stored = defaults.object(forKey: hotkeyKeyCodeKey)
        return (stored as? UInt32) ?? UInt32(kVK_ANSI_V)
    }

    static func hotkeyModifiers(defaults: UserDefaults = .standard) -> UInt32 {
        let stored = defaults.object(forKey: hotkeyModifiersKey)
        return (stored as? UInt32) ?? UInt32(cmdKey | shiftKey)
    }

    static func saveHotkey(keyCode: UInt32, modifiers: UInt32, defaults: UserDefaults = .standard) {
        defaults.set(keyCode, forKey: hotkeyKeyCodeKey)
        defaults.set(modifiers, forKey: hotkeyModifiersKey)
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

    // MARK: - History
    static let maxHistoryCountKey = "history.maxCount"
    static let defaultMaxHistoryCount = 200

    static func maxHistoryCount(defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: maxHistoryCountKey)
        return stored > 0 ? stored : defaultMaxHistoryCount
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
```

- [ ] **Step 2: Build to verify no errors**

```bash
swift build --product ClipboardApp 2>&1 | head -30
```

Expected: build errors about missing AppDelegate (we'll fix that next) but NO type errors in AppSettings.swift itself.

- [ ] **Step 3: Commit**

```bash
git add Sources/ClipboardApp/App/AppSettings.swift
git commit -m "feat(settings): add hotkey, panel position, hasLaunched, history keys"
```

---

## Task 2: Create HotKeyManager Actor

**Files:**
- Create: `Sources/ClipboardApp/HotKey/HotKeyManager.swift`
- Create: `Tests/ClipboardCoreTests/HotKeyManagerTests.swift`

The existing `GlobalHotKeyRegistrar` is a hardcoded, single-use registrar. `HotKeyManager` replaces it as an actor that supports dynamic re-registration and conflict detection.

- [ ] **Step 1: Write failing tests first**

Create `Tests/ClipboardCoreTests/HotKeyManagerTests.swift`:

```swift
import XCTest
import Carbon
@testable import ClipboardCore

// NOTE: HotKeyManager uses Carbon Events which requires a running app event loop.
// These tests cover the logic that can be tested without Carbon:
// conflict detection via system blacklist, and UserDefaults persistence.

final class HotKeyManagerTests: XCTestCase {

    func testSystemBlacklist_cmdQ_isBlacklisted() {
        let isBlacklisted = HotKeyManager.isSystemBlacklisted(
            keyCode: UInt32(kVK_ANSI_Q),
            modifiers: UInt32(cmdKey)
        )
        XCTAssertTrue(isBlacklisted, "Cmd+Q must be in the system blacklist")
    }

    func testSystemBlacklist_cmdShiftV_isNotBlacklisted() {
        let isBlacklisted = HotKeyManager.isSystemBlacklisted(
            keyCode: UInt32(kVK_ANSI_V),
            modifiers: UInt32(cmdKey | shiftKey)
        )
        XCTAssertFalse(isBlacklisted, "Cmd+Shift+V should not be in the system blacklist")
    }

    func testSystemBlacklist_cmdW_isBlacklisted() {
        let isBlacklisted = HotKeyManager.isSystemBlacklisted(
            keyCode: UInt32(kVK_ANSI_W),
            modifiers: UInt32(cmdKey)
        )
        XCTAssertTrue(isBlacklisted, "Cmd+W must be in the system blacklist")
    }

    func testSystemBlacklist_cmdTab_isBlacklisted() {
        let isBlacklisted = HotKeyManager.isSystemBlacklisted(
            keyCode: UInt32(kVK_Tab),
            modifiers: UInt32(cmdKey)
        )
        XCTAssertTrue(isBlacklisted, "Cmd+Tab must be in the system blacklist")
    }
}
```

- [ ] **Step 2: Run to verify tests fail**

```bash
swift test --filter HotKeyManagerTests 2>&1 | tail -20
```

Expected: compile error — `HotKeyManager` not found.

- [ ] **Step 3: Create HotKeyManager**

Create `Sources/ClipboardApp/HotKey/HotKeyManager.swift`:

```swift
import AppKit
import Carbon
import Foundation

enum HotKeyError: Error {
    case systemConflict(description: String)
    case registrationFailed(OSStatus)
    case handlerInstallFailed(OSStatus)
}

@MainActor
final class HotKeyManager {
    private static let signature = OSType(0x434C4950) // "CLIP"
    private static let hotKeyID  = UInt32(1)
    private static let notHandled = OSStatus(eventNotHandledErr)

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var action: (() -> Void)?

    // MARK: - Public API

    /// Registers a new hotkey, replacing any currently registered one.
    /// Throws HotKeyError if the key is blacklisted or registration fails.
    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) throws {
        unregister()

        if Self.isSystemBlacklisted(keyCode: keyCode, modifiers: modifiers) {
            throw HotKeyError.systemConflict(
                description: "This key combination is reserved by the system."
            )
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        var installedRef: EventHandlerRef?

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else {
                    return HotKeyManager.notHandled
                }
                var hkID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                guard err == noErr,
                      hkID.signature == HotKeyManager.signature,
                      hkID.id == HotKeyManager.hotKeyID else {
                    return HotKeyManager.notHandled
                }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in manager.action?() }
                return noErr
            },
            1, &eventType, selfPointer, &installedRef
        )

        guard handlerStatus == noErr, let installedRef else {
            throw HotKeyError.handlerInstallFailed(handlerStatus)
        }

        let hkID = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
        var registeredRef: EventHotKeyRef?
        let hotKeyStatus = RegisterEventHotKey(
            keyCode, modifiers, hkID,
            GetApplicationEventTarget(), 0, &registeredRef
        )

        guard hotKeyStatus == noErr, let registeredRef else {
            RemoveEventHandler(installedRef)
            throw HotKeyError.registrationFailed(hotKeyStatus)
        }

        self.eventHandlerRef = installedRef
        self.hotKeyRef = registeredRef
        self.action = action
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        if let ref = eventHandlerRef { RemoveEventHandler(ref); eventHandlerRef = nil }
        action = nil
    }

    // MARK: - Conflict Detection (static, testable without Carbon event loop)

    /// Returns true if the key combination is in the known system shortcut blacklist.
    static func isSystemBlacklisted(keyCode: UInt32, modifiers: UInt32) -> Bool {
        // Normalise: only look at Cmd/Shift/Option/Control bits
        let mods = modifiers & UInt32(cmdKey | shiftKey | optionKey | controlKey)
        let cmdOnly    = UInt32(cmdKey)
        let cmdShift   = UInt32(cmdKey | shiftKey)
        let cmdOption  = UInt32(cmdKey | optionKey)

        let blacklist: [(keyCode: UInt32, modifiers: UInt32)] = [
            // Application lifecycle
            (UInt32(kVK_ANSI_Q), cmdOnly),   // Cmd+Q  Quit
            (UInt32(kVK_ANSI_H), cmdOnly),   // Cmd+H  Hide
            (UInt32(kVK_ANSI_M), cmdOnly),   // Cmd+M  Minimise
            (UInt32(kVK_ANSI_W), cmdOnly),   // Cmd+W  Close Window
            // Standard edit
            (UInt32(kVK_ANSI_Z), cmdOnly),   // Cmd+Z  Undo
            (UInt32(kVK_ANSI_X), cmdOnly),   // Cmd+X  Cut
            (UInt32(kVK_ANSI_C), cmdOnly),   // Cmd+C  Copy
            (UInt32(kVK_ANSI_V), cmdOnly),   // Cmd+V  Paste
            (UInt32(kVK_ANSI_A), cmdOnly),   // Cmd+A  Select All
            (UInt32(kVK_ANSI_S), cmdOnly),   // Cmd+S  Save
            // System-level
            (UInt32(kVK_Tab),    cmdOnly),            // Cmd+Tab  App Switcher
            (UInt32(kVK_Space),  cmdOnly),            // Cmd+Space  Spotlight
            (UInt32(kVK_Space),  cmdOption),          // Cmd+Option+Space  Spotlight (alt)
            (UInt32(kVK_ANSI_Q), cmdShift),           // Cmd+Shift+Q  Log Out
        ]

        return blacklist.contains { $0.keyCode == keyCode && $0.modifiers == mods }
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = eventHandlerRef { RemoveEventHandler(ref) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter HotKeyManagerTests 2>&1 | tail -20
```

Expected: all 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClipboardApp/HotKey/HotKeyManager.swift \
        Tests/ClipboardCoreTests/HotKeyManagerTests.swift
git commit -m "feat(hotkey): add HotKeyManager actor with conflict detection"
```

---

## Task 3: Add Panel Position Logic to QuickPanelController

**Files:**
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelController.swift`
- Create: `Tests/ClipboardCoreTests/PanelPositionTests.swift`

- [ ] **Step 1: Write failing position tests**

Create `Tests/ClipboardCoreTests/PanelPositionTests.swift`:

```swift
import XCTest
import AppKit
@testable import ClipboardCore

// Tests the pure position-clamping logic (no Carbon, no UI).
final class PanelPositionTests: XCTestCase {

    private let panelSize = CGSize(width: 620, height: 420)

    func testClamp_originFitsInsideFrame_unchanged() {
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: 400, y: 300)
        let result = PanelPositionCalculator.clampToVisible(
            origin: origin, panelSize: panelSize, visibleFrame: frame
        )
        XCTAssertEqual(result, origin)
    }

    func testClamp_originOffLeftEdge_clampsToMinX() {
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: -100, y: 300)
        let result = PanelPositionCalculator.clampToVisible(
            origin: origin, panelSize: panelSize, visibleFrame: frame
        )
        XCTAssertEqual(result.x, frame.minX)
    }

    func testClamp_originOffRightEdge_clampsToMaxXMinusPanelWidth() {
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: 1400, y: 300)
        let result = PanelPositionCalculator.clampToVisible(
            origin: origin, panelSize: panelSize, visibleFrame: frame
        )
        XCTAssertEqual(result.x, frame.maxX - panelSize.width)
    }

    func testCenter_returnsFrameMidpoint() {
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let result = PanelPositionCalculator.centerOrigin(
            panelSize: panelSize, visibleFrame: frame
        )
        let expectedX = frame.midX - panelSize.width / 2
        let expectedY = frame.midY - panelSize.height / 2 + 80
        XCTAssertEqual(result.x, expectedX)
        XCTAssertEqual(result.y, expectedY)
    }

    func testStatusBarClick_originBelowIcon() {
        // Status bar icon at top-right, macOS coords (y=0 at bottom)
        let iconOrigin = NSPoint(x: 1300, y: 780)
        let frame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let result = PanelPositionCalculator.statusBarClickOrigin(
            iconOrigin: iconOrigin, panelSize: panelSize, visibleFrame: frame
        )
        // Panel y should be below the icon (icon.y - panelHeight - gap)
        XCTAssertLessThan(result.y, iconOrigin.y)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
swift test --filter PanelPositionTests 2>&1 | tail -10
```

Expected: compile error — `PanelPositionCalculator` not found.

- [ ] **Step 3: Replace QuickPanelController.swift**

```swift
import AppKit
import SwiftUI

// MARK: - Trigger / Position types

enum TriggerSource {
    case hotkey
    case statusBarClick(iconOrigin: NSPoint)
}

// MARK: - Pure position calculator (testable without UI)

enum PanelPositionCalculator {

    static func centerOrigin(panelSize: CGSize, visibleFrame: NSRect) -> NSPoint {
        NSPoint(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.midY - panelSize.height / 2 + 80
        )
    }

    static func followMouseOrigin(panelSize: CGSize, visibleFrame: NSRect) -> NSPoint {
        let mouseLocation = NSEvent.mouseLocation
        let raw = NSPoint(
            x: mouseLocation.x - panelSize.width / 2,
            y: mouseLocation.y - panelSize.height / 2
        )
        return clampToVisible(origin: raw, panelSize: panelSize, visibleFrame: visibleFrame)
    }

    static func statusBarClickOrigin(
        iconOrigin: NSPoint, panelSize: CGSize, visibleFrame: NSRect
    ) -> NSPoint {
        let gap: CGFloat = 5
        let raw = NSPoint(
            x: iconOrigin.x - panelSize.width / 2,
            y: iconOrigin.y - panelSize.height - gap
        )
        return clampToVisible(origin: raw, panelSize: panelSize, visibleFrame: visibleFrame)
    }

    static func clampToVisible(
        origin: NSPoint, panelSize: CGSize, visibleFrame: NSRect
    ) -> NSPoint {
        let clampedX = max(visibleFrame.minX,
                           min(origin.x, visibleFrame.maxX - panelSize.width))
        let clampedY = max(visibleFrame.minY,
                           min(origin.y, visibleFrame.maxY - panelSize.height))
        return NSPoint(x: clampedX, y: clampedY)
    }

    // Screen containing the mouse cursor (falls back to main screen)
    static func mouseScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}

// MARK: - QuickPanelController

@MainActor
final class QuickPanelController {
    private let state: QuickPanelState
    private let prepareForShow: @MainActor () async -> Void
    private var panel: NSPanel?
    private var previousApplication: NSRunningApplication?

    // Set by AppDelegate after StatusBarController is created
    var statusBarIconOrigin: NSPoint = .zero

    init(
        state: QuickPanelState,
        prepareForShow: @escaping @MainActor () async -> Void = {}
    ) {
        self.state = state
        self.prepareForShow = prepareForShow
    }

    func toggle(trigger: TriggerSource = .hotkey) {
        if panel?.isVisible == true {
            hide()
        } else {
            show(trigger: trigger)
        }
    }

    func show(trigger: TriggerSource = .hotkey) {
        rememberPreviousApplication()
        let panel = panel ?? makePanel()
        self.panel = panel

        position(panel, trigger: trigger)

        Task { @MainActor in
            await prepareForShow()
            await state.refresh()
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            focusSearchField(in: panel)
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - Private

    private func makePanel() -> NSPanel {
        let content = QuickPanelView(
            state: state,
            onClose: { [weak self] in self?.hide() },
            onSubmit: { [weak self] in self?.submitSelection() }
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

    private func position(_ panel: NSPanel, trigger: TriggerSource) {
        let screen: NSScreen
        switch trigger {
        case .hotkey:
            screen = PanelPositionCalculator.mouseScreen()
        case .statusBarClick:
            screen = PanelPositionCalculator.mouseScreen()
        }
        let visibleFrame = screen.visibleFrame
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
                origin = PanelPositionCalculator.statusBarClickOrigin(
                    iconOrigin: statusBarIconOrigin, panelSize: size, visibleFrame: visibleFrame
                )
            }
        }

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func rememberPreviousApplication() {
        let front = NSWorkspace.shared.frontmostApplication
        previousApplication = front?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : front
    }

    private func submitSelection() {
        let targetApplication = previousApplication
        let autoPaste = ClipboardAppSettings.quickPanelAutoPasteEnabled()
        hide()
        if let app = targetApplication, !app.isTerminated {
            app.activate(options: [.activateAllWindows])
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            await state.selectCurrent(autoPaste: autoPaste)
        }
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
```

- [ ] **Step 4: Run position tests**

```bash
swift test --filter PanelPositionTests 2>&1 | tail -20
```

Expected: all 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClipboardApp/QuickPanel/QuickPanelController.swift \
        Tests/ClipboardCoreTests/PanelPositionTests.swift
git commit -m "feat(panel): add TriggerSource-aware position logic and PanelPositionCalculator"
```

---

## Task 4: Create StatusBarController

**Files:**
- Create: `Sources/ClipboardApp/StatusBar/StatusBarController.swift`

- [ ] **Step 1: Create the directory**

```bash
mkdir -p Sources/ClipboardApp/StatusBar
```

- [ ] **Step 2: Create StatusBarController.swift**

```swift
import AppKit

@MainActor
final class StatusBarController {
    private var statusItem: NSStatusItem?
    private let onLeftClick: (NSPoint) -> Void   // passes icon origin
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

    /// Returns the screen-coordinate origin of the status bar button window.
    var iconOrigin: NSPoint {
        statusItem?.button?.window?.frame.origin ?? .zero
    }

    // MARK: - Private

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
        statusItem?.menu = nil  // clear so left-click works next time
    }

    @objc private func quitAction() {
        onQuit()
    }
}
```

- [ ] **Step 3: Build to verify no errors**

```bash
swift build --product ClipboardApp 2>&1 | grep -E "error:|StatusBar" | head -20
```

Expected: build errors from missing AppDelegate only; no errors in StatusBarController.swift.

- [ ] **Step 4: Commit**

```bash
git add Sources/ClipboardApp/StatusBar/StatusBarController.swift
git commit -m "feat(statusbar): add StatusBarController with left/right click handling"
```

---

## Task 5: Create AppDelegate and Convert to Menu Bar App

**Files:**
- Create: `Sources/ClipboardApp/App/AppDelegate.swift`
- Delete: `Sources/ClipboardApp/App/ClipboardApp.swift`
- Modify: Info.plist (add LSUIElement)

- [ ] **Step 1: Check if Info.plist exists, create if not**

```bash
ls Sources/ClipboardApp/App/ 2>/dev/null || echo "directory missing"
```

If the App/ directory doesn't exist yet:
```bash
mkdir -p Sources/ClipboardApp/App
```

- [ ] **Step 2: Create AppDelegate.swift**

Create `Sources/ClipboardApp/App/AppDelegate.swift`:

```swift
import AppKit
import SwiftUI
import ClipboardCore
import ClipboardPlatform

@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var services: AppServices!
    private var statusBarController: StatusBarController!
    private var hotKeyManager: HotKeyManager!
    private var welcomeWindowController: NSWindowController?

    // Kept as a stored property so ARC doesn't release it
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

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
            }
        )
        statusBarController.setup()
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
        try? hotKeyManager.register(keyCode: defaultKeyCode, modifiers: defaultModifiers) { [weak self] in
            self?.services.quickPanelController.toggle(trigger: .hotkey)
        }
        ClipboardAppSettings.saveHotkey(keyCode: defaultKeyCode, modifiers: defaultModifiers)
    }

    // MARK: - First Launch / Welcome

    private func checkFirstLaunch() {
        guard !ClipboardAppSettings.hasLaunched() else { return }
        showWelcomeWindow()
    }

    private func showWelcomeWindow() {
        let welcomeView = WelcomeView {
            ClipboardAppSettings.markLaunched()
            self.welcomeWindowController?.close()
            self.welcomeWindowController = nil
        }
        let hostingController = NSHostingController(rootView: welcomeView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "欢迎使用 Clipboard"
        window.styleMask = [.titled, .closable]
        window.setFrame(NSRect(x: 0, y: 0, width: 480, height: 360), display: true)
        window.center()
        window.isReleasedWhenClosed = false
        let wc = NSWindowController(window: window)
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindowController = wc
    }

    // MARK: - Settings Window

    func openSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let settingsView = SettingsRootView(services: services, hotKeyManager: hotKeyManager)
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "设置"
        window.styleMask = [.titled, .closable, .resizable]
        window.setFrame(NSRect(x: 0, y: 0, width: 660, height: 480), display: true)
        window.minSize = NSSize(width: 560, height: 380)
        window.center()
        window.isReleasedWhenClosed = false
        settingsWindow = window
        let wc = NSWindowController(window: window)
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - App-level helper accessed from views

extension AppDelegate {
    static var shared: AppDelegate {
        NSApp.delegate as! AppDelegate
    }
}
```

- [ ] **Step 3: Delete old ClipboardApp.swift**

```bash
rm Sources/ClipboardApp/ClipboardApp.swift
git rm Sources/ClipboardApp/ClipboardApp.swift
```

- [ ] **Step 4: Move AppSettings to App/ subdirectory if needed**

Check where AppSettings.swift currently lives:
```bash
find Sources/ClipboardApp -name "AppSettings.swift"
```

If it's at `Sources/ClipboardApp/AppSettings.swift`, move it:
```bash
mkdir -p Sources/ClipboardApp/App
git mv Sources/ClipboardApp/AppSettings.swift Sources/ClipboardApp/App/AppSettings.swift
```

If it's already in `App/`, skip this step.

- [ ] **Step 5: Build (expect failures for missing WelcomeView, SettingsRootView)**

```bash
swift build --product ClipboardApp 2>&1 | grep "error:" | head -20
```

Expected errors:
- `cannot find type 'WelcomeView'`
- `cannot find type 'SettingsRootView'`

No other errors. If other errors appear, fix them before continuing.

- [ ] **Step 6: Commit what compiles so far**

```bash
git add Sources/ClipboardApp/App/AppDelegate.swift
git commit -m "feat(app): add AppDelegate, StatusBarController wiring, menu bar app entry point"
```

---

## Task 6: Create WelcomeView

**Files:**
- Create: `Sources/ClipboardApp/Welcome/WelcomeView.swift`

- [ ] **Step 1: Create directory**

```bash
mkdir -p Sources/ClipboardApp/Welcome
```

- [ ] **Step 2: Create WelcomeView.swift**

```swift
import AppKit
import SwiftUI

struct WelcomeView: View {
    let onComplete: () -> Void

    @State private var isAuthorized = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("欢迎使用 Clipboard")
                    .font(.title.weight(.semibold))
                Text("Clipboard 运行在菜单栏中，随时通过快捷键或点击菜单栏图标访问剪贴板历史。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Label("辅助功能权限", systemImage: "hand.raised")
                    .font(.headline)

                Text("自动粘贴功能需要辅助功能权限，用于模拟 Command+V 按键。")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    if isAuthorized {
                        Label("已授权", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("需要授权", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    }

                    Spacer()

                    if !isAuthorized {
                        Button("打开系统设置") {
                            openAccessibilitySettings()
                        }
                    }
                }
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            Spacer()

            HStack {
                Spacer()
                Button("开始使用") {
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isAuthorized)
                .help(isAuthorized ? "" : "请先在系统设置中授权辅助功能权限")
            }
        }
        .padding(24)
        .frame(width: 480, height: 360)
        .onAppear { checkAuthorization() }
        .onReceive(timer) { _ in checkAuthorization() }
    }

    private func checkAuthorization() {
        isAuthorized = AXIsProcessTrusted()
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 3: Build — should now only error on missing SettingsRootView**

```bash
swift build --product ClipboardApp 2>&1 | grep "error:" | head -20
```

Expected: only `cannot find type 'SettingsRootView'` errors.

- [ ] **Step 4: Commit**

```bash
git add Sources/ClipboardApp/Welcome/WelcomeView.swift
git commit -m "feat(welcome): add first-launch permission guidance window"
```

---

## Task 7: Create Settings Window

**Files:**
- Create: `Sources/ClipboardApp/Settings/SettingsWindow.swift`
- Create: `Sources/ClipboardApp/Settings/HotKeyRecorderView.swift`
- Create: `Sources/ClipboardApp/Settings/GeneralSettingsView.swift`
- Create: `Sources/ClipboardApp/Settings/PrivacySettingsView.swift`
- Create: `Sources/ClipboardApp/Settings/HistorySettingsView.swift`

- [ ] **Step 1: Create directory**

```bash
mkdir -p Sources/ClipboardApp/Settings
```

- [ ] **Step 2: Create SettingsWindow.swift (navigation shell)**

```swift
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case general  = "通用"
    case privacy  = "隐私"
    case history  = "历史记录"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .general: return "gear"
        case .privacy: return "hand.raised"
        case .history: return "clock"
        }
    }
}

struct SettingsRootView: View {
    let services: AppServices
    let hotKeyManager: HotKeyManager

    @State private var selectedPage: SettingsPage? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $selectedPage) { page in
                Label(page.rawValue, systemImage: page.systemImage)
                    .tag(page)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch selectedPage {
            case .general:
                GeneralSettingsView(hotKeyManager: hotKeyManager)
            case .privacy:
                PrivacySettingsView()
            case .history:
                HistorySettingsView(store: services.store)
            case nil:
                GeneralSettingsView(hotKeyManager: hotKeyManager)
            }
        }
        .navigationTitle(selectedPage?.rawValue ?? "设置")
    }
}
```

- [ ] **Step 3: Create HotKeyRecorderView.swift**

```swift
import AppKit
import Carbon
import SwiftUI

/// A control that captures keyboard input and displays a hotkey combination.
struct HotKeyRecorderView: View {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    var onConflict: (String) -> Void

    @State private var isRecording = false
    @State private var pendingKeyCode: UInt32 = 0
    @State private var pendingModifiers: UInt32 = 0

    var displayText: String {
        if isRecording { return "录制中…按下快捷键" }
        return Self.humanReadable(keyCode: keyCode, modifiers: modifiers)
    }

    var body: some View {
        HStack {
            Text(displayText)
                .frame(minWidth: 160, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(isRecording ? .accentColor : .primary)
                .onTapGesture { isRecording = true }

            if isRecording {
                Button("取消") { isRecording = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .background(KeyRecordingNSView(
            isRecording: isRecording,
            onKeyDown: { kc, mods in
                let conflictMsg = checkConflict(keyCode: kc, modifiers: mods)
                if let msg = conflictMsg {
                    onConflict(msg)
                    isRecording = false
                } else {
                    keyCode = kc
                    modifiers = mods
                    isRecording = false
                    ClipboardAppSettings.saveHotkey(keyCode: kc, modifiers: mods)
                }
            }
        ).frame(width: 0, height: 0))
    }

    private func checkConflict(keyCode: UInt32, modifiers: UInt32) -> String? {
        if HotKeyManager.isSystemBlacklisted(keyCode: keyCode, modifiers: modifiers) {
            return "该快捷键为系统保留，请选择其他组合"
        }
        return nil
    }

    static func humanReadable(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        let m = modifiers
        if m & UInt32(controlKey) != 0 { parts.append("⌃") }
        if m & UInt32(optionKey)  != 0 { parts.append("⌥") }
        if m & UInt32(shiftKey)   != 0 { parts.append("⇧") }
        if m & UInt32(cmdKey)     != 0 { parts.append("⌘") }

        let keyName: String
        switch Int(keyCode) {
        case kVK_ANSI_A: keyName = "A"
        case kVK_ANSI_B: keyName = "B"
        case kVK_ANSI_C: keyName = "C"
        case kVK_ANSI_D: keyName = "D"
        case kVK_ANSI_E: keyName = "E"
        case kVK_ANSI_F: keyName = "F"
        case kVK_ANSI_G: keyName = "G"
        case kVK_ANSI_H: keyName = "H"
        case kVK_ANSI_I: keyName = "I"
        case kVK_ANSI_J: keyName = "J"
        case kVK_ANSI_K: keyName = "K"
        case kVK_ANSI_L: keyName = "L"
        case kVK_ANSI_M: keyName = "M"
        case kVK_ANSI_N: keyName = "N"
        case kVK_ANSI_O: keyName = "O"
        case kVK_ANSI_P: keyName = "P"
        case kVK_ANSI_Q: keyName = "Q"
        case kVK_ANSI_R: keyName = "R"
        case kVK_ANSI_S: keyName = "S"
        case kVK_ANSI_T: keyName = "T"
        case kVK_ANSI_U: keyName = "U"
        case kVK_ANSI_V: keyName = "V"
        case kVK_ANSI_W: keyName = "W"
        case kVK_ANSI_X: keyName = "X"
        case kVK_ANSI_Y: keyName = "Y"
        case kVK_ANSI_Z: keyName = "Z"
        case kVK_F1:  keyName = "F1"
        case kVK_F2:  keyName = "F2"
        case kVK_F3:  keyName = "F3"
        case kVK_F4:  keyName = "F4"
        case kVK_F5:  keyName = "F5"
        case kVK_F6:  keyName = "F6"
        case kVK_F7:  keyName = "F7"
        case kVK_F8:  keyName = "F8"
        case kVK_F9:  keyName = "F9"
        case kVK_F10: keyName = "F10"
        case kVK_F11: keyName = "F11"
        case kVK_F12: keyName = "F12"
        case kVK_ANSI_0...kVK_ANSI_9:
            keyName = String(Int(keyCode) - kVK_ANSI_0)
        default: keyName = "Key(\(keyCode))"
        }
        parts.append(keyName)
        return parts.joined()
    }
}

// NSViewRepresentable that steals keyboard events when recording
private struct KeyRecordingNSView: NSViewRepresentable {
    let isRecording: Bool
    let onKeyDown: (UInt32, UInt32) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onKeyDown: onKeyDown) }

    func makeNSView(context: Context) -> RecorderNSView {
        let view = RecorderNSView()
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ nsView: RecorderNSView, context: Context) {
        context.coordinator.onKeyDown = onKeyDown
        if isRecording {
            context.coordinator.installMonitor()
        } else {
            context.coordinator.removeMonitor()
        }
    }

    static func dismantleNSView(_ nsView: RecorderNSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var onKeyDown: (UInt32, UInt32) -> Void
        weak var view: RecorderNSView?
        private var monitor: Any?

        init(onKeyDown: @escaping (UInt32, UInt32) -> Void) {
            self.onKeyDown = onKeyDown
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.view?.window != nil else { return event }
                // Map NSEvent modifierFlags to Carbon modifier bits
                var mods: UInt32 = 0
                let flags = event.modifierFlags
                if flags.contains(.command) { mods |= UInt32(cmdKey) }
                if flags.contains(.shift)   { mods |= UInt32(shiftKey) }
                if flags.contains(.option)  { mods |= UInt32(optionKey) }
                if flags.contains(.control) { mods |= UInt32(controlKey) }
                self.onKeyDown(UInt32(event.keyCode), mods)
                return nil  // consume the event
            }
        }

        func removeMonitor() {
            guard let m = monitor else { return }
            NSEvent.removeMonitor(m)
            monitor = nil
        }

        deinit { removeMonitor() }
    }
}

final class RecorderNSView: NSView {}
```

- [ ] **Step 4: Create GeneralSettingsView.swift**

```swift
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
            // Permission status card
            Section("辅助功能权限") {
                HStack {
                    if isAuthorized {
                        Label("已授权", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("未授权 — 自动粘贴功能不可用", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("前往系统设置") {
                            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            // Hotkey
            Section("全局快捷键") {
                HStack {
                    Text("呼出快捷面板")
                    Spacer()
                    HotKeyRecorderView(
                        keyCode: Binding(
                            get: { UInt32(storedKeyCode) },
                            set: { newKC in
                                storedKeyCode = Int(newKC)
                                reRegisterHotKey(keyCode: newKC, modifiers: UInt32(storedModifiers))
                            }
                        ),
                        modifiers: Binding(
                            get: { UInt32(storedModifiers) },
                            set: { newMods in
                                storedModifiers = Int(newMods)
                                reRegisterHotKey(keyCode: UInt32(storedKeyCode), modifiers: newMods)
                            }
                        ),
                        onConflict: { msg in conflictMessage = msg }
                    )
                }
                if !conflictMessage.isEmpty {
                    Text(conflictMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            // Panel position
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

            // Paste behaviour
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

    private func reRegisterHotKey(keyCode: UInt32, modifiers: UInt32) {
        Task { @MainActor in
            do {
                try hotKeyManager.register(keyCode: keyCode, modifiers: modifiers) {
                    AppDelegate.shared.services.quickPanelController.toggle(trigger: .hotkey)
                }
            } catch {
                conflictMessage = "注册快捷键失败: \(error.localizedDescription)"
            }
        }
    }
}
```

- [ ] **Step 5: Create PrivacySettingsView.swift**

```swift
import SwiftUI

struct PrivacySettingsView: View {
    @AppStorage("privacy.ignoreUniversalClipboard")
    private var ignoreUniversalClipboard: Bool = false

    var body: some View {
        Form {
            Section("Universal Clipboard") {
                Toggle("忽略来自其他 Apple 设备的剪贴板内容", isOn: $ignoreUniversalClipboard)
                Text("开启后，通过 Universal Clipboard 从 iPhone/iPad 复制的内容不会被记录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("排除的应用") {
                Text("密码管理器等敏感应用的内容已自动过滤，不会被记录。")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)

                Text("当前隐私策略过滤以下类型应用的剪贴板内容：密码管理器、银行 App、证券 App。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 6: Create HistorySettingsView.swift**

```swift
import ClipboardCore
import SwiftUI

struct HistorySettingsView: View {
    let store: InMemoryHistoryStore

    @AppStorage(ClipboardAppSettings.maxHistoryCountKey)
    private var maxHistoryCount: Int = ClipboardAppSettings.defaultMaxHistoryCount

    @State private var recordCount: Int = 0
    @State private var showClearConfirmation = false

    var body: some View {
        Form {
            Section("保留数量") {
                Stepper("最多保留 \(maxHistoryCount) 条历史记录", value: $maxHistoryCount, in: 50...2000, step: 50)
                Text("超出上限时，最旧的记录将自动删除。重启应用后生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("清除历史") {
                HStack {
                    Text("当前会话共 \(recordCount) 条记录")
                    Spacer()
                    Button("清除全部历史") {
                        showClearConfirmation = true
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            Task { recordCount = await store.fetchAll().count }
        }
        .confirmationDialog(
            "确定要清除所有剪贴板历史吗？此操作无法撤销。",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除全部", role: .destructive) {
                Task {
                    await store.removeAll()
                    recordCount = 0
                }
            }
        }
    }
}
```

- [ ] **Step 7: Build to verify everything compiles**

```bash
swift build --product ClipboardApp 2>&1 | grep "error:" | head -20
```

Expected: build succeeds (no errors). If `InMemoryHistoryStore` doesn't have `removeAll()`, the error will show here — fix in Step 8.

- [ ] **Step 8: Add removeAll() to InMemoryHistoryStore if missing**

Check if `removeAll()` exists:
```bash
grep -n "removeAll" Sources/ClipboardCore/Storage/InMemoryHistoryStore.swift
```

If not found, add it to `InMemoryHistoryStore.swift`:
```swift
// Add inside the actor
func removeAll() {
    records.removeAll()
    payloadsByID.removeAll()
}
```

Then rebuild:
```bash
swift build --product ClipboardApp 2>&1 | grep "error:" | head -10
```

Expected: no errors.

- [ ] **Step 9: Commit**

```bash
git add Sources/ClipboardApp/Settings/ Sources/ClipboardApp/App/AppDelegate.swift
git commit -m "feat(settings): add SettingsWindow with General/Privacy/History pages and HotKeyRecorder"
```

---

## Task 8: Add ⚙️ Button to QuickPanelView

**Files:**
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelView.swift`

- [ ] **Step 1: Add ⚙️ button to the search field HStack**

Find the `searchField` computed property in `QuickPanelView.swift`. Replace it:

```swift
private var searchField: some View {
    HStack(spacing: 10) {
        Image(systemName: "magnifyingglass")
            .foregroundStyle(.secondary)

        TextField(
            "Search clipboard",
            text: Binding(
                get: { state.query },
                set: { state.updateQuery($0) }
            )
        )
        .textFieldStyle(.plain)
        .focused($isSearchFocused)

        Button {
            AppDelegate.shared.openSettings()
        } label: {
            Image(systemName: "gearshape")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("打开设置")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
}
```

- [ ] **Step 2: Build and verify**

```bash
swift build --product ClipboardApp 2>&1 | grep "error:" | head -10
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/ClipboardApp/QuickPanel/QuickPanelView.swift
git commit -m "feat(panel): add gear button to QuickPanel search field"
```

---

## Task 9: Delete GlobalHotKeyRegistrar and Final Cleanup

**Files:**
- Delete: `Sources/ClipboardApp/HotKey/GlobalHotKeyRegistrar.swift`

- [ ] **Step 1: Verify nothing references GlobalHotKeyRegistrar**

```bash
grep -r "GlobalHotKeyRegistrar" Sources/ Tests/
```

Expected: no output (no references remaining).

- [ ] **Step 2: Delete the file**

```bash
git rm Sources/ClipboardApp/HotKey/GlobalHotKeyRegistrar.swift
```

- [ ] **Step 3: Full build and tests**

```bash
Scripts/verify.sh 2>&1 | tail -30
```

Expected: all tests pass, build succeeds.

- [ ] **Step 4: Commit**

```bash
git commit -m "chore: remove GlobalHotKeyRegistrar, superseded by HotKeyManager"
```

---

## Task 10: Manual Acceptance Testing

**Files:**
- Modify: `docs/manual-acceptance-checklist.md`

- [ ] **Step 1: Append new checklist section**

Add the following section to the end of `docs/manual-acceptance-checklist.md`:

```markdown
## 菜单栏图标和导航（v2 新增）

- [ ] 启动后菜单栏右上角出现 Clipboard 图标
- [ ] 左键点击图标，快捷面板在图标下方弹出
- [ ] 右键点击图标，显示包含"退出 Clipboard"的菜单
- [ ] 点击"退出 Clipboard"，应用正常退出（Activity Monitor 中进程消失）
- [ ] Dock 中无 Clipboard 图标

## 快捷键配置（v2 新增）

- [ ] 打开设置 → 通用，当前快捷键显示为 ⌘⇧V
- [ ] 点击快捷键录制框，出现"录制中…按下快捷键"提示
- [ ] 按下 Cmd+Q，提示"该快捷键为系统保留"，不保存
- [ ] 按下有效组合（如 Cmd+Option+V），框显示 ⌘⌥V，快捷键立即生效
- [ ] 重启应用后，自定义快捷键保持不变

## 快捷面板位置（v2 新增）

- [ ] 设置 → 通用 → 位置：选"居中"，按快捷键，面板在屏幕中央
- [ ] 设置 → 通用 → 位置：选"跟随鼠标"，将鼠标移到屏幕左侧再按快捷键，面板在鼠标附近
- [ ] 设置 → 通用 → 位置：选"菜单栏图标下方"，按快捷键，面板在菜单栏图标下
- [ ] 无论位置设置如何，左键点击菜单栏图标时面板始终在图标下方

## 欢迎窗口（v2 新增）

- [ ] 清除 UserDefaults（`defaults delete com.local.clipboard-manager`），重启，欢迎窗口出现
- [ ] 欢迎窗口实时显示辅助功能权限状态
- [ ] 授权后，状态更新为"✅ 已授权"，"开始使用"按钮可点击
- [ ] 点击"开始使用"，欢迎窗口关闭，应用正常进入后台
- [ ] 再次重启，欢迎窗口不再出现

## 设置窗口（v2 新增）

- [ ] 快捷面板右上角 ⚙️ 按钮可打开设置窗口
- [ ] 多次点击 ⚙️，设置窗口只有一个实例（重复点击置前）
- [ ] 设置窗口左侧可切换通用 / 隐私 / 历史记录页
- [ ] 修改设置后关闭窗口，重启后设置保持不变
```

- [ ] **Step 2: Commit**

```bash
git add docs/manual-acceptance-checklist.md
git commit -m "docs: add v2 acceptance tests for menubar, hotkey, position, welcome, settings"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Covered by task |
|-----------------|----------------|
| 应用架构转型（移除 WindowGroup） | Task 5 |
| AppDelegate + NSStatusItem | Task 4, 5 |
| HotKeyManager actor + conflict detection | Task 2 |
| QuickPanelController position modes | Task 3 |
| StatusBarController left/right click | Task 4 |
| SettingsWindow NavigationSplitView | Task 7 |
| HotKeyRecorderView | Task 7 |
| GeneralSettingsView (hotkey, position, return-copies-only, permission card) | Task 7 |
| PrivacySettingsView | Task 7 |
| HistorySettingsView | Task 7 |
| WelcomeView first-launch | Task 6 |
| ⚙️ button in QuickPanel | Task 8 |
| AppSettings new keys | Task 1 |
| Delete GlobalHotKeyRegistrar | Task 9 |
| Manual acceptance checklist | Task 10 |
| Unit tests: HotKeyManager blacklist | Task 2 |
| Unit tests: position clamping | Task 3 |

All spec requirements covered. ✅
