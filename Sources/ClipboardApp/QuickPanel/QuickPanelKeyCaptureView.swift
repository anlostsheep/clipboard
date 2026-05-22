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
    case quit
    case deleteSelected
    case togglePinned
    case clearUnpinned
    case clearAll
    case cycleContentFilter(Int)
  }

  let onMove: (Int) -> Void
  let onSubmit: () -> Void
  let onCancel: () -> Void
  let onFocusSearch: () -> Void
  let onOpenSettings: () -> Void
  let onQuit: () -> Void
  let onDeleteSelected: () -> Void
  let onTogglePinned: () -> Void
  let onClearUnpinned: () -> Void
  let onClearAll: () -> Void
  let onCycleContentFilter: (Int) -> Void = { _ in }

  func makeCoordinator() -> Coordinator {
    Coordinator(
      onMove: onMove,
      onSubmit: onSubmit,
      onCancel: onCancel,
      onFocusSearch: onFocusSearch,
      onOpenSettings: onOpenSettings,
      onQuit: onQuit,
      onDeleteSelected: onDeleteSelected,
      onTogglePinned: onTogglePinned,
      onClearUnpinned: onClearUnpinned,
      onClearAll: onClearAll,
      onCycleContentFilter: onCycleContentFilter
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
    context.coordinator.onQuit = onQuit
    context.coordinator.onDeleteSelected = onDeleteSelected
    context.coordinator.onTogglePinned = onTogglePinned
    context.coordinator.onClearUnpinned = onClearUnpinned
    context.coordinator.onClearAll = onClearAll
    context.coordinator.onCycleContentFilter = onCycleContentFilter
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
    var onQuit: () -> Void
    var onDeleteSelected: () -> Void
    var onTogglePinned: () -> Void
    var onClearUnpinned: () -> Void
    var onClearAll: () -> Void
    var onCycleContentFilter: (Int) -> Void
    weak var observedView: KeyCaptureNSView?

    private var monitor: Any?

    init(
      onMove: @escaping (Int) -> Void,
      onSubmit: @escaping () -> Void,
      onCancel: @escaping () -> Void,
      onFocusSearch: @escaping () -> Void,
      onOpenSettings: @escaping () -> Void,
      onQuit: @escaping () -> Void,
      onDeleteSelected: @escaping () -> Void,
      onTogglePinned: @escaping () -> Void,
      onClearUnpinned: @escaping () -> Void,
      onClearAll: @escaping () -> Void,
      onCycleContentFilter: @escaping (Int) -> Void
    ) {
      self.onMove = onMove
      self.onSubmit = onSubmit
      self.onCancel = onCancel
      self.onFocusSearch = onFocusSearch
      self.onOpenSettings = onOpenSettings
      self.onQuit = onQuit
      self.onDeleteSelected = onDeleteSelected
      self.onTogglePinned = onTogglePinned
      self.onClearUnpinned = onClearUnpinned
      self.onClearAll = onClearAll
      self.onCycleContentFilter = onCycleContentFilter
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
      case .quit:
        onQuit()
        return nil
      case .deleteSelected:
        onDeleteSelected()
        return nil
      case .togglePinned:
        onTogglePinned()
        return nil
      case .clearUnpinned:
        onClearUnpinned()
        return nil
      case .clearAll:
        onClearAll()
        return nil
      case .cycleContentFilter(let delta):
        onCycleContentFilter(delta)
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
    if keyCode == UInt16(kVK_Tab) {
      if modifiers.isEmpty {
        return .cycleContentFilter(1)
      }
      if modifiers == [.shift] {
        return .cycleContentFilter(-1)
      }
      return nil
    }
    if keyCode == UInt16(kVK_Delete), modifiers == [.shift, .option, .command] {
      return .clearAll
    }
    if keyCode == UInt16(kVK_Delete), modifiers == [.option, .command] {
      return .clearUnpinned
    }
    if keyCode == UInt16(kVK_Delete), modifiers == [.option] {
      return .deleteSelected
    }
    if keyCode == UInt16(kVK_ANSI_P), modifiers == [.option] {
      return .togglePinned
    }
    if keyCode == UInt16(kVK_ANSI_F), modifiers.contains(.command) {
      return .focusSearch
    }
    if keyCode == UInt16(kVK_ANSI_Comma), modifiers.contains(.command) {
      return .openSettings
    }
    if keyCode == UInt16(kVK_ANSI_Q), modifiers == [.command] {
      return .quit
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
