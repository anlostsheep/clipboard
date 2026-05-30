import AppKit
import Carbon
import SwiftUI

enum QuickPanelNumberShortcutMode: Equatable {
  case select
  case paste
}

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
    case selectNumber(Int)
    case selectPinnedShortcut(Int)
    case pasteNumber(Int)
    case pastePlainText
    case showDetailPreview
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
  var onCycleContentFilter: ((Int) -> Void)? = nil
  var onSelectNumber: ((Int) -> Void)? = nil
  var onSelectPinnedShortcut: ((Int) -> Void)? = nil
  var onPasteNumber: ((Int) -> Void)? = nil
  var onPastePlainText: (() -> Void)? = nil
  var onShowDetailPreview: (() -> Void)? = nil
  var onNumberShortcutModeChanged: (QuickPanelNumberShortcutMode?) -> Void = { _ in }
  var modifierTrackingResetToken = 0

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
      onCycleContentFilter: onCycleContentFilter,
      onSelectNumber: onSelectNumber,
      onSelectPinnedShortcut: onSelectPinnedShortcut,
      onPasteNumber: onPasteNumber,
      onPastePlainText: onPastePlainText,
      onShowDetailPreview: onShowDetailPreview,
      onNumberShortcutModeChanged: onNumberShortcutModeChanged
    )
  }

  func makeNSView(context: Context) -> KeyCaptureNSView {
    let view = KeyCaptureNSView()
    context.coordinator.observedView = view
    context.coordinator.resetModifierTrackingIfNeeded(token: modifierTrackingResetToken)
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
    context.coordinator.onSelectNumber = onSelectNumber
    context.coordinator.onSelectPinnedShortcut = onSelectPinnedShortcut
    context.coordinator.onPasteNumber = onPasteNumber
    context.coordinator.onPastePlainText = onPastePlainText
    context.coordinator.onShowDetailPreview = onShowDetailPreview
    context.coordinator.onNumberShortcutModeChanged = onNumberShortcutModeChanged
    context.coordinator.resetModifierTrackingIfNeeded(token: modifierTrackingResetToken)
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
    var onCycleContentFilter: ((Int) -> Void)?
    var onSelectNumber: ((Int) -> Void)?
    var onSelectPinnedShortcut: ((Int) -> Void)?
    var onPasteNumber: ((Int) -> Void)?
    var onPastePlainText: (() -> Void)?
    var onShowDetailPreview: (() -> Void)?
    var onNumberShortcutModeChanged: (QuickPanelNumberShortcutMode?) -> Void
    weak var observedView: KeyCaptureNSView?

    private var monitor: Any?
    private var modifierTracker = QuickPanelModifierTracker()

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
      onCycleContentFilter: ((Int) -> Void)?,
      onSelectNumber: ((Int) -> Void)?,
      onSelectPinnedShortcut: ((Int) -> Void)?,
      onPasteNumber: ((Int) -> Void)?,
      onPastePlainText: (() -> Void)?,
      onShowDetailPreview: (() -> Void)?,
      onNumberShortcutModeChanged: @escaping (QuickPanelNumberShortcutMode?) -> Void
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
      self.onSelectNumber = onSelectNumber
      self.onSelectPinnedShortcut = onSelectPinnedShortcut
      self.onPasteNumber = onPasteNumber
      self.onPastePlainText = onPastePlainText
      self.onShowDetailPreview = onShowDetailPreview
      self.onNumberShortcutModeChanged = onNumberShortcutModeChanged
    }

    func installMonitor() {
      guard monitor == nil else {
        return
      }

      monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
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
      guard let observedView,
            let observedWindow = observedView.window,
            event.window == nil || event.window === observedWindow else {
        return event
      }

      if event.type == .flagsChanged {
        modifierTracker.observe(event.modifierFlags)
        onNumberShortcutModeChanged(
          QuickPanelKeyCaptureView.numberShortcutMode(modifierFlags: modifierTracker.observedModifierFlags)
        )
        return event
      }

      let trackedModifierFlags = modifierTracker.trackedModifierFlags(
        eventModifierFlags: event.modifierFlags,
        globalModifierFlags: NSEvent.modifierFlags
      )
      let action = QuickPanelKeyCaptureView.keyboardAction(
        keyCode: event.keyCode,
        modifierFlags: event.modifierFlags,
        trackedModifierFlags: trackedModifierFlags
      )
      if QuickPanelKeyCaptureView.shouldDeferToMarkedTextInput(
        keyCode: event.keyCode,
        modifierFlags: event.modifierFlags,
        trackedModifierFlags: trackedModifierFlags,
        hasMarkedText: event.window?.firstResponder?.hasMarkedTextInput == true
      ) {
        return event
      }

      onNumberShortcutModeChanged(
        QuickPanelKeyCaptureView.numberShortcutMode(
          modifierFlags: event.modifierFlags,
          trackedModifierFlags: trackedModifierFlags
        )
      )

      switch action {
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
        guard let onCycleContentFilter else {
          return event
        }
        onCycleContentFilter(delta)
        return nil
      case .selectNumber(let number):
        guard let onSelectNumber else {
          return event
        }
        onSelectNumber(number)
        return nil
      case .selectPinnedShortcut(let slot):
        guard let onSelectPinnedShortcut else {
          return event
        }
        onSelectPinnedShortcut(slot)
        return nil
      case .pasteNumber(let number):
        guard let onPasteNumber else {
          return event
        }
        onPasteNumber(number)
        return nil
      case .pastePlainText:
        guard let onPastePlainText else {
          return event
        }
        onPastePlainText()
        return nil
      case .showDetailPreview:
        guard let onShowDetailPreview else {
          return event
        }
        onShowDetailPreview()
        return nil
      case nil:
        return event
      }
    }

    func resetModifierTrackingIfNeeded(token: Int) {
      guard modifierTracker.resetIfNeeded(token: token) else {
        return
      }

      onNumberShortcutModeChanged(nil)
    }

    deinit {
      removeMonitor()
    }
  }

  static func keyboardAction(
    keyCode: UInt16,
    modifierFlags: NSEvent.ModifierFlags
  ) -> KeyboardAction? {
    let modifiers = normalizedShortcutModifiers(modifierFlags)
    return keyboardAction(keyCode: keyCode, shortcutModifiers: modifiers)
  }

  static func keyboardAction(
    keyCode: UInt16,
    modifierFlags: NSEvent.ModifierFlags,
    trackedModifierFlags: NSEvent.ModifierFlags
  ) -> KeyboardAction? {
    let eventModifiers = normalizedShortcutModifiers(modifierFlags)
    let trackedModifiers = normalizedShortcutModifiers(trackedModifierFlags)

    if let number = number(for: keyCode) {
      return numberShortcutAction(
        number: number,
        modifiers: effectiveNumberShortcutModifiers(
          eventModifierFlags: modifierFlags,
          trackedModifierFlags: trackedModifierFlags
        )
      )
    }

    if let pinnedSlot = pinnedShortcutSlot(for: keyCode) {
      guard eventModifiers == [.command],
            trackedModifiers.intersection([.shift, .control, .option]).isEmpty else {
        return nil
      }
      return .selectPinnedShortcut(pinnedSlot)
    }

    return keyboardAction(keyCode: keyCode, modifierFlags: modifierFlags)
  }

  private static func keyboardAction(
    keyCode: UInt16,
    shortcutModifiers modifiers: NSEvent.ModifierFlags
  ) -> KeyboardAction? {
    if keyCode == UInt16(kVK_Tab) {
      if modifiers.isEmpty {
        return .cycleContentFilter(1)
      }
      if modifiers == [.shift] {
        return .cycleContentFilter(-1)
      }
      return nil
    }
    if let number = number(for: keyCode) {
      return numberShortcutAction(number: number, modifiers: modifiers)
    }
    if let pinnedSlot = pinnedShortcutSlot(for: keyCode), modifiers == [.command] {
      return .selectPinnedShortcut(pinnedSlot)
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
    if keyCode == UInt16(kVK_ANSI_Comma), modifiers.contains(.command) {
      return .openSettings
    }
    if keyCode == UInt16(kVK_ANSI_Q), modifiers == [.command] {
      return .quit
    }
    if keyCode == UInt16(kVK_Return), modifiers == [.shift, .option] {
      return .pastePlainText
    }
    if keyCode == UInt16(kVK_ANSI_Y), modifiers == [.command] {
      return .showDetailPreview
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

  static func numberShortcutMode(modifierFlags: NSEvent.ModifierFlags) -> QuickPanelNumberShortcutMode? {
    switch normalizedShortcutModifiers(modifierFlags) {
    case [.command]:
      .select
    case [.control, .command]:
      .paste
    default:
      nil
    }
  }

  static func numberShortcutMode(
    modifierFlags: NSEvent.ModifierFlags,
    trackedModifierFlags: NSEvent.ModifierFlags
  ) -> QuickPanelNumberShortcutMode? {
    switch effectiveNumberShortcutModifiers(
      eventModifierFlags: modifierFlags,
      trackedModifierFlags: trackedModifierFlags
    ) {
    case [.command]:
      .select
    case [.control, .command]:
      .paste
    default:
      nil
    }
  }

  static func shouldDeferToMarkedTextInput(
    keyCode: UInt16,
    modifierFlags: NSEvent.ModifierFlags,
    hasMarkedText: Bool
  ) -> Bool {
    hasMarkedText && keyboardAction(keyCode: keyCode, modifierFlags: modifierFlags) == nil
  }

  static func shouldDeferToMarkedTextInput(
    keyCode: UInt16,
    modifierFlags: NSEvent.ModifierFlags,
    trackedModifierFlags: NSEvent.ModifierFlags,
    hasMarkedText: Bool
  ) -> Bool {
    hasMarkedText && keyboardAction(
      keyCode: keyCode,
      modifierFlags: modifierFlags,
      trackedModifierFlags: trackedModifierFlags
    ) == nil
  }

  static func normalizedShortcutModifiers(_ modifierFlags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
    modifierFlags.intersection([.shift, .control, .option, .command])
  }

  private static func effectiveNumberShortcutModifiers(
    eventModifierFlags: NSEvent.ModifierFlags,
    trackedModifierFlags: NSEvent.ModifierFlags
  ) -> NSEvent.ModifierFlags {
    let eventModifiers = normalizedShortcutModifiers(eventModifierFlags)
    guard !eventModifiers.isEmpty else {
      return []
    }
    return eventModifiers.union(normalizedShortcutModifiers(trackedModifierFlags))
  }

  private static func numberShortcutAction(
    number: Int,
    modifiers: NSEvent.ModifierFlags
  ) -> KeyboardAction? {
    if modifiers == [.control, .command] {
      return .pasteNumber(number)
    }
    if modifiers == [.command] {
      return .selectNumber(number)
    }
    return nil
  }

  private static func number(for keyCode: UInt16) -> Int? {
    switch keyCode {
    case UInt16(kVK_ANSI_1): return 1
    case UInt16(kVK_ANSI_2): return 2
    case UInt16(kVK_ANSI_3): return 3
    case UInt16(kVK_ANSI_4): return 4
    case UInt16(kVK_ANSI_5): return 5
    case UInt16(kVK_ANSI_6): return 6
    case UInt16(kVK_ANSI_7): return 7
    case UInt16(kVK_ANSI_8): return 8
    case UInt16(kVK_ANSI_9): return 9
    default: return nil
    }
  }

  private static func pinnedShortcutSlot(for keyCode: UInt16) -> Int? {
    switch keyCode {
    case UInt16(kVK_ANSI_A): return 0
    case UInt16(kVK_ANSI_S): return 1
    case UInt16(kVK_ANSI_D): return 2
    case UInt16(kVK_ANSI_F): return 3
    case UInt16(kVK_ANSI_G): return 4
    case UInt16(kVK_ANSI_H): return 5
    case UInt16(kVK_ANSI_J): return 6
    case UInt16(kVK_ANSI_K): return 7
    case UInt16(kVK_ANSI_L): return 8
    default: return nil
    }
  }
}

final class KeyCaptureNSView: NSView {}

struct QuickPanelModifierTracker {
  private(set) var observedModifierFlags: NSEvent.ModifierFlags = []
  private var resetToken: Int?

  mutating func resetIfNeeded(token: Int) -> Bool {
    guard resetToken != token else {
      return false
    }

    resetToken = token
    observedModifierFlags = []
    return true
  }

  mutating func observe(_ modifierFlags: NSEvent.ModifierFlags) {
    observedModifierFlags = QuickPanelKeyCaptureView.normalizedShortcutModifiers(modifierFlags)
  }

  func trackedModifierFlags(
    eventModifierFlags: NSEvent.ModifierFlags,
    globalModifierFlags: NSEvent.ModifierFlags
  ) -> NSEvent.ModifierFlags {
    observedModifierFlags
      .union(eventModifierFlags)
      .union(globalModifierFlags)
  }
}

private extension NSResponder {
  var hasMarkedTextInput: Bool {
    (self as? NSTextInputClient)?.hasMarkedText() ?? false
  }
}
