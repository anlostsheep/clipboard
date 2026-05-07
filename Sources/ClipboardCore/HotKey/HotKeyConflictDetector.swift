import Carbon

/// Pure-logic conflict detector for global hotkey combinations.
///
/// Placed in ClipboardCore (no AppKit/Carbon event-loop dependency)
/// so it can be unit-tested independently of the ClipboardApp executable.
/// HotKeyManager (ClipboardApp) delegates to this type before registering
/// a Carbon hotkey, keeping registration logic and conflict logic decoupled.
public enum HotKeyConflictDetector {

    // MARK: - System Blacklist

    /// Returns true if the given key + modifier combination is reserved by macOS
    /// (e.g. Cmd+Q, Cmd+Tab, Cmd+Space) and therefore unsafe to register as a
    /// global hotkey.
    ///
    /// Only the standard modifier mask (cmd | shift | option | control) is
    /// compared; other bits (fn, numpad, etc.) are ignored.
    public static func isSystemBlacklisted(keyCode: UInt32, modifiers: UInt32) -> Bool {
        let mask = UInt32(cmdKey | shiftKey | optionKey | controlKey)
        let mods = modifiers & mask

        let cmdOnly   = UInt32(cmdKey)
        let cmdShift  = UInt32(cmdKey | shiftKey)
        let cmdOption = UInt32(cmdKey | optionKey)

        // Well-known macOS system shortcuts that must not be overridden.
        // References: Apple HIG "Keyboard Shortcuts" + empirical testing on macOS 14.
        let blacklist: [(keyCode: UInt32, modifiers: UInt32)] = [
            // App lifecycle
            (UInt32(kVK_ANSI_Q), cmdOnly),   // Cmd+Q  – Quit
            (UInt32(kVK_ANSI_H), cmdOnly),   // Cmd+H  – Hide
            (UInt32(kVK_ANSI_M), cmdOnly),   // Cmd+M  – Minimize

            // Window / document
            (UInt32(kVK_ANSI_W), cmdOnly),   // Cmd+W  – Close Window

            // Edit
            (UInt32(kVK_ANSI_Z), cmdOnly),   // Cmd+Z  – Undo
            (UInt32(kVK_ANSI_X), cmdOnly),   // Cmd+X  – Cut
            (UInt32(kVK_ANSI_C), cmdOnly),   // Cmd+C  – Copy
            (UInt32(kVK_ANSI_V), cmdOnly),   // Cmd+V  – Paste
            (UInt32(kVK_ANSI_A), cmdOnly),   // Cmd+A  – Select All
            (UInt32(kVK_ANSI_S), cmdOnly),   // Cmd+S  – Save

            // System
            (UInt32(kVK_Tab),   cmdOnly),    // Cmd+Tab    – App Switcher
            (UInt32(kVK_Space), cmdOnly),    // Cmd+Space  – Spotlight (alternative binding)
            (UInt32(kVK_Space), cmdOption),  // Cmd+Opt+Space – Finder Spotlight

            // Screenshot / system sheet
            (UInt32(kVK_ANSI_Q), cmdShift), // Cmd+Shift+Q – Log Out dialog
        ]

        return blacklist.contains { $0.keyCode == keyCode && $0.modifiers == mods }
    }
}
