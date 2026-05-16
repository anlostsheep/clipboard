import AppKit
import Carbon
import XCTest
@testable import ClipboardApp

@MainActor
final class SettingsWindowShortcutTests: XCTestCase {
    func testCommandWClosesSettingsWindow() throws {
        let window = ClipboardSettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        var didClose = false
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: nil
        ) { _ in
            didClose = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        window.makeKeyAndOrderFront(nil)

        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_W)
        ))

        XCTAssertTrue(window.performKeyEquivalent(with: event))
        XCTAssertTrue(didClose)
        XCTAssertFalse(window.isVisible)
    }
}
