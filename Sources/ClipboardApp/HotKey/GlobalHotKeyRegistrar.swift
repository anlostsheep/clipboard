import AppKit
import Carbon

@MainActor
final class GlobalHotKeyRegistrar {
  private static let signature = OSType(0x434C4950)
  private static let hotKeyID = UInt32(1)
  private static let notHandledStatus = OSStatus(eventNotHandledErr)

  private var eventHandlerRef: EventHandlerRef?
  private var hotKeyRef: EventHotKeyRef?
  private var action: (() -> Void)?

  @discardableResult
  func registerCommandShiftV(action: @escaping () -> Void) -> OSStatus {
    unregister()

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

    let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    var installedHandlerRef: EventHandlerRef?
    let handlerStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard let event, let userData else {
          return GlobalHotKeyRegistrar.notHandledStatus
        }

        var hotKeyID = EventHotKeyID()
        let parameterStatus = GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &hotKeyID
        )

        guard
          parameterStatus == noErr,
          hotKeyID.signature == GlobalHotKeyRegistrar.signature,
          hotKeyID.id == GlobalHotKeyRegistrar.hotKeyID
        else {
          return GlobalHotKeyRegistrar.notHandledStatus
        }

        let registrar = Unmanaged<GlobalHotKeyRegistrar>
          .fromOpaque(userData)
          .takeUnretainedValue()
        Task { @MainActor in
          registrar.action?()
        }
        return noErr
      },
      1,
      &eventType,
      selfPointer,
      &installedHandlerRef
    )

    guard handlerStatus == noErr, let installedHandlerRef else {
      self.hotKeyRef = nil
      self.eventHandlerRef = nil
      self.action = nil
      return handlerStatus
    }

    let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.hotKeyID)
    var registeredHotKeyRef: EventHotKeyRef?
    let hotKeyStatus = RegisterEventHotKey(
      UInt32(kVK_ANSI_V),
      UInt32(cmdKey | shiftKey),
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &registeredHotKeyRef
    )

    guard hotKeyStatus == noErr, let registeredHotKeyRef else {
      RemoveEventHandler(installedHandlerRef)
      self.hotKeyRef = nil
      self.eventHandlerRef = nil
      self.action = nil
      return hotKeyStatus
    }

    self.eventHandlerRef = installedHandlerRef
    self.hotKeyRef = registeredHotKeyRef
    self.action = action
    return noErr
  }

  func unregister() {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
      self.hotKeyRef = nil
    }

    if let eventHandlerRef {
      RemoveEventHandler(eventHandlerRef)
      self.eventHandlerRef = nil
    }

    action = nil
  }

  deinit {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
    }

    if let eventHandlerRef {
      RemoveEventHandler(eventHandlerRef)
    }
  }
}
