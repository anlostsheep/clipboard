import AppKit
import SwiftUI

struct QuickPanelKeyCaptureView: NSViewRepresentable {
  let onMove: (Int) -> Void
  let onSubmit: () -> Void
  let onCancel: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onMove: onMove, onSubmit: onSubmit, onCancel: onCancel)
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
    weak var observedView: KeyCaptureNSView?

    private var monitor: Any?

    init(onMove: @escaping (Int) -> Void, onSubmit: @escaping () -> Void, onCancel: @escaping () -> Void) {
      self.onMove = onMove
      self.onSubmit = onSubmit
      self.onCancel = onCancel
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

      switch event.keyCode {
      case 53:
        onCancel()
        return nil
      case 36:
        onSubmit()
        return nil
      case 125:
        onMove(1)
        return nil
      case 126:
        onMove(-1)
        return nil
      default:
        return event
      }
    }

    deinit {
      removeMonitor()
    }
  }
}

final class KeyCaptureNSView: NSView {}
