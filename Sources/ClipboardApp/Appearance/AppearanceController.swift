import AppKit

/// Applies an `AppearanceMode` to the current `NSApplication`. Setting
/// `NSApp.appearance` is synchronous and broadcasts to all open windows
/// and to subsequent NSMenu instances.
@MainActor
enum AppearanceController {
    static func apply(_ mode: AppearanceMode) {
        NSApp.appearance = mode.nsAppearance
    }
}
