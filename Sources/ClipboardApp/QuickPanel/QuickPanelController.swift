import AppKit
import SwiftUI

@MainActor
final class QuickPanelController {
  private let state: QuickPanelState
  private var panel: NSPanel?

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
    let panel = panel ?? makePanel()
    self.panel = panel

    position(panel)

    Task {
      await state.refresh()
    }

    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
  }

  func hide() {
    panel?.orderOut(nil)
  }

  private func makePanel() -> NSPanel {
    let content = QuickPanelView(state: state) { [weak self] in
      self?.hide()
    }
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
}

private final class KeyablePanel: NSPanel {
  override var canBecomeKey: Bool {
    true
  }

  override var canBecomeMain: Bool {
    true
  }
}
