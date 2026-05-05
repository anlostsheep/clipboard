import AppKit
import SwiftUI

@MainActor
final class QuickPanelController {
  private let state: QuickPanelState
  private var panel: NSPanel?
  private var previousApplication: NSRunningApplication?

  init(state: QuickPanelState) {
    self.state = state
  }

  func toggle() {
    if panel?.isVisible == true {
      hide()
    } else {
      show()
    }
  }

  func show() {
    rememberPreviousApplication()
    let panel = panel ?? makePanel()
    self.panel = panel

    position(panel)

    Task {
      await state.refresh()
    }

    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    focusSearchField(in: panel)
  }

  func hide() {
    panel?.orderOut(nil)
  }

  private func makePanel() -> NSPanel {
    let content = QuickPanelView(
      state: state,
      onClose: { [weak self] in
        self?.hide()
      },
      onSubmit: { [weak self] in
        self?.submitSelection()
      }
    )
    let hostingView = NSHostingView(rootView: content)
    let panel = KeyablePanel(
      contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
      styleMask: [.titled, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    panel.title = "Clipboard QuickPanel"
    panel.contentView = hostingView
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = true
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isReleasedWhenClosed = false

    return panel
  }

  private func position(_ panel: NSPanel) {
    let targetFrame = NSApp.keyWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
    guard let frame = targetFrame else {
      panel.center()
      return
    }

    let size = panel.frame.size
    let origin = NSPoint(
      x: frame.midX - size.width / 2,
      y: frame.midY - size.height / 2 + 80
    )
    panel.setFrame(NSRect(origin: origin, size: size), display: true)
  }

  private func rememberPreviousApplication() {
    let frontmostApplication = NSWorkspace.shared.frontmostApplication
    if frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier {
      previousApplication = nil
    } else {
      previousApplication = frontmostApplication
    }
  }

  private func submitSelection() {
    let targetApplication = previousApplication
    hide()

    if let targetApplication, !targetApplication.isTerminated {
      targetApplication.activate(options: [.activateAllWindows])
    }

    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 120_000_000)
      await state.selectCurrent(autoPaste: true)
    }
  }

  private func focusSearchField(in panel: NSPanel, attemptsRemaining: Int = 4) {
    guard attemptsRemaining > 0 else {
      return
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak panel] in
      guard let panel else {
        return
      }

      if let textField = panel.contentView?.firstSubview(of: NSTextField.self) {
        panel.makeFirstResponder(textField)
      } else {
        self.focusSearchField(in: panel, attemptsRemaining: attemptsRemaining - 1)
      }
    }
  }
}

private final class KeyablePanel: NSPanel {
  override var canBecomeKey: Bool {
    true
  }

  override var canBecomeMain: Bool {
    true
  }
}

private extension NSView {
  func firstSubview<T: NSView>(of type: T.Type) -> T? {
    if let view = self as? T {
      return view
    }

    for subview in subviews {
      if let match = subview.firstSubview(of: type) {
        return match
      }
    }

    return nil
  }
}
