import AppKit
import Carbon
import ClipboardCore
import Foundation

// MARK: - Error

enum HotKeyError: Error {
    /// The requested combination is reserved by macOS (e.g. Cmd+Q, Cmd+Tab).
    case systemConflict(description: String)
    /// InstallEventHandler returned a non-zero OSStatus.
    case handlerInstallFailed(OSStatus)
    /// RegisterEventHotKey returned a non-zero OSStatus.
    case registrationFailed(OSStatus)
}

// MARK: - HotKeyManager

/// Manages a single global hotkey registration via Carbon Events.
///
/// Conflict detection is delegated to `HotKeyConflictDetector` (ClipboardCore)
/// so that the pure logic can be unit-tested without an event-loop dependency.
///
/// Usage:
/// ```swift
/// try manager.register(keyCode: UInt32(kVK_ANSI_V),
///                      modifiers: UInt32(cmdKey | shiftKey)) {
///     // fired on main actor when hotkey is pressed
/// }
/// ```
@MainActor
final class HotKeyManager {

    // "CLIP" encoded as OSType – identifies our event handler in the Carbon queue.
    private static let signature = OSType(0x434C4950)
    private static let hotKeyID  = UInt32(1)
    private static let notHandled = OSStatus(eventNotHandledErr)

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var action: (() -> Void)?

    // MARK: - Public API

    /// Registers a global hotkey. Unregisters any previously registered hotkey first.
    ///
    /// - Parameters:
    ///   - keyCode: Virtual key code (use `kVK_*` constants from Carbon).
    ///   - modifiers: Carbon modifier flags (e.g. `cmdKey | shiftKey`).
    ///   - action: Closure invoked on the main actor each time the hotkey fires.
    /// - Throws: `HotKeyError` if the combination is blacklisted or registration fails.
    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) throws {
        unregister()

        guard !HotKeyConflictDetector.isSystemBlacklisted(keyCode: keyCode, modifiers: modifiers) else {
            throw HotKeyError.systemConflict(
                description: "This key combination is reserved by macOS and cannot be used."
            )
        }

        // Install the Carbon event handler that receives kEventHotKeyPressed.
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
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
            1, &eventType, selfPtr, &installedRef
        )

        guard handlerStatus == noErr, let installedRef else {
            throw HotKeyError.handlerInstallFailed(handlerStatus)
        }

        // Register the actual hotkey with the system.
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

    /// Unregisters the current hotkey and removes the event handler. Safe to call
    /// when no hotkey is registered.
    func unregister() {
        if let ref = hotKeyRef   { UnregisterEventHotKey(ref); hotKeyRef = nil }
        if let ref = eventHandlerRef { RemoveEventHandler(ref); eventHandlerRef = nil }
        action = nil
    }

    deinit {
        // deinit is not isolated to @MainActor, so call Carbon APIs directly.
        if let ref = hotKeyRef   { UnregisterEventHotKey(ref) }
        if let ref = eventHandlerRef { RemoveEventHandler(ref) }
    }
}
