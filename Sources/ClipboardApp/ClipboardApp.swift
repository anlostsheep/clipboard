import SwiftUI
import ClipboardCore

@main
struct ClipboardApp: App {
  var body: some Scene {
    WindowGroup("Clipboard") {
      VStack(alignment: .leading, spacing: 12) {
        Text("Clipboard Manager")
          .font(.headline)
        Text("Core \(ClipboardCoreBootstrap.version)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(20)
      .frame(width: 320)
    }
  }
}
