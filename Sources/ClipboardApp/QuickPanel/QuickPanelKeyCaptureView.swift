import AppKit
import Carbon
import SwiftUI

struct QuickPanelKeyCaptureView: NSViewRepresentable {
  enum KeyboardAction: Equatable {
    case cancel
    case submit
    case move(Int)
    case focusSearch
    case openSettings
    case togglePinned
  }

  let onMove: (Int) -> Void
  let onSubmit: () -> Void
  let onCancel: () -> Void
  let onFocusSearch: () -> Void
  let onOpenSettings: () -> Void
  let onTogglePinned: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(
      onMove: onMove,
      onSubmit: onSubmit,
      onCancel: onCancel,
      onFocusSearch: onFocusSearch,
      onOpenSettings: onOpenSettings,
      onTogglePinned: onTogglePinned
    )
  }

  func makeNSView(context: Context) -> KeyCaptureNSView {
    let view = KeyCaptureNSView()
    context.coordinator.observedView = view
    context.coordinator.installMonitor()
    return view
  }

  func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
    context.coordinator.observedView = nsView
    context.coordinator.onMove = onMove
    context.coordinator.onSubmit = onSubmit
    context.coordinator.onCancel = onCancel
    context.coordinator.onFocusSearch = onFocusSearch
    context.coordinator.onOpenSettings = onOpenSettings
    context.coordinator.onTogglePinned = onTogglePinned
    context.coordinator.installMonitor()
  }

  static func dismantleNSView(_ nsView: KeyCaptureNSView, coordinator: Coordinator) {
    coordinator.removeMonitor()
    coordinator.observedView = nil
  }

  final class Coordinator {
    var onMove: (Int) -> Void
    var onSubmit: () -> Void
    var onCancel: () -> Void
    var onFocusSearch: () -> Void
    var onOpenSettings: () -> Void
    var onTogglePinned: () -> Void
    weak var observedView: KeyCaptureNSView?

    private var monitor: Any?

    init(
      onMove: @escaping (Int) -> Void,
      onSubmit: @escaping () -> Void,
      onCancel: @escaping () -> Void,
      onFocusSearch: @escaping () -> Void,
      onOpenSettings: @escaping () -> Void,
      onTogglePinned: @escaping () -> Void
    ) {
      self.onMove = onMove
      self.onSubmit = onSubmit
      self.onCancel = onCancel
      self.onFocusSearch = onFocusSearch
      self.onOpenSettings = onOpenSettings
      self.onTogglePinned = onTogglePinned
    }

    func installMonitor() {
      guard monitor == nil else {
        return
      }

      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        self?.handle(event) ?? event
      }
    }

    func removeMonitor() {
      guard let monitor else {
        return
      }

      NSEvent.removeMonitor(monitor)
      self.monitor = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
      guard let observedView, observedView.window != nil, event.window === observedView.window else {
        return event
      }

      if event.window?.firstResponder?.hasMarkedTextInput == true {
        return event
      }

      switch QuickPanelKeyCaptureView.keyboardAction(keyCode: event.keyCode, modifierFlags: event.modifierFlags) {
      case .cancel:
        onCancel()
        return nil
      case .submit:
        onSubmit()
        return nil
      case .move(let delta):
        onMove(delta)
        return nil
      case .focusSearch:
        onFocusSearch()
        return nil
      case .openSettings:
        onOpenSettings()
        return nil
      case .togglePinned:
        onTogglePinned()
        return nil
      case nil:
        return event
      }
    }

    deinit {
      removeMonitor()
    }
  }

  static func keyboardAction(
    keyCode: UInt16,
    modifierFlags: NSEvent.ModifierFlags
  ) -> KeyboardAction? {
    let modifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
    if keyCode == UInt16(kVK_ANSI_P), modifiers == [.option] {
      return .togglePinned
    }
    if keyCode == UInt16(kVK_ANSI_F), modifiers.contains(.command) {
      return .focusSearch
    }
    if keyCode == UInt16(kVK_ANSI_Comma), modifiers.contains(.command) {
      return .openSettings
    }

    switch keyCode {
    case UInt16(kVK_Escape):
      return .cancel
    case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
      return .submit
    case UInt16(kVK_DownArrow):
      return .move(1)
    case UInt16(kVK_UpArrow):
      return .move(-1)
    default:
      return nil
    }
  }
}

final class KeyCaptureNSView: NSView {}

private extension NSResponder {
  var hasMarkedTextInput: Bool {
    (self as? NSTextInputClient)?.hasMarkedText() ?? false
  }
}
