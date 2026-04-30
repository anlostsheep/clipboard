import SwiftUI
import ClipboardCore

@main
struct ClipboardApp: App {
  private let store = InMemoryHistoryStore()
  private let systemClient = SystemPasteboardClient()

  var body: some Scene {
    WindowGroup("Clipboard") {
      ClipboardRootView(store: store, systemClient: systemClient)
    }
  }
}

private struct ClipboardRootView: View {
  let store: InMemoryHistoryStore
  let systemClient: SystemPasteboardClient
  @State private var status = "Ready"

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Clipboard Manager")
        .font(.headline)
      Text(status)
        .font(.caption)
        .foregroundStyle(.secondary)
      Button("Check Accessibility") {
        status = systemClient.isAccessibilityTrusted() ? "Accessibility authorized" : "Accessibility required"
      }
    }
    .padding(20)
    .frame(width: 360)
  }
}
