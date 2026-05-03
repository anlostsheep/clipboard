import SwiftUI
import ClipboardCore
import ClipboardPlatform

@main
struct ClipboardApp: App {
  @State private var services = AppServices()

  var body: some Scene {
    WindowGroup("Clipboard") {
      ClipboardRootView(services: services)
    }
  }
}

private struct ClipboardRootView: View {
  let services: AppServices
  @Environment(\.scenePhase) private var scenePhase
  @State private var isAuthorized = false
  @State private var isPollingClipboard = false
  @State private var status = "Checking accessibility"
  @State private var records: [ClipboardRecord] = []
  @State private var lastCaptureSummary = "No clipboard item captured in this session."
  private let authorizationTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
  private let clipboardTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

  var body: some View {
    Group {
      if isAuthorized {
        dashboard
      } else {
        permissionGate
      }
    }
    .padding(20)
    .frame(minWidth: 760, minHeight: 480)
    .task {
      refreshAuthorization()
      await refreshRecords()
    }
    .onReceive(authorizationTimer) { _ in
      guard !isAuthorized else {
        return
      }
      refreshAuthorization(unauthorizedStatus: status)
    }
    .onReceive(clipboardTimer) { _ in
      guard isAuthorized, !isPollingClipboard else {
        return
      }
      Task {
        await pollClipboardChanges()
      }
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else {
        return
      }
      refreshAuthorization(unauthorizedStatus: status)
    }
  }

  private var permissionGate: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Clipboard Manager")
        .font(.title2.weight(.semibold))
      Text("Accessibility permission is required before automatic paste behavior can be tested.")
        .foregroundStyle(.secondary)
      Text(status)
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack(spacing: 10) {
        Button("Request Permission") {
          requestAccessibilityPermission()
        }
        .keyboardShortcut(.defaultAction)

        Button("Recheck") {
          refreshAuthorization()
        }
      }
      Text("After enabling ClipboardApp in System Settings, this screen will switch automatically. If it does not, click Recheck or restart the app.")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text("During local development, rebuilding an ad-hoc signed app can invalidate the previous Accessibility grant. If this screen still says required while System Settings is enabled, remove the old ClipboardApp entry and request permission again.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: 420, alignment: .leading)
  }

  private var dashboard: some View {
    HStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 16) {
        Text("Clipboard")
          .font(.title2.weight(.semibold))
        statusLine("Accessibility", value: "Authorized")
        statusLine("Session items", value: "\(records.count)")

        Divider()

        Button("Capture Current Clipboard") {
          Task {
            await captureCurrentClipboard()
          }
        }
        .keyboardShortcut("r")

        Button("Recheck Accessibility") {
          refreshAuthorization()
        }

        Spacer()

        Text(lastCaptureSummary)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(width: 220, alignment: .topLeading)
      .padding(.trailing, 20)

      Divider()

      VStack(alignment: .leading, spacing: 14) {
        Text("Integration Test Console")
          .font(.title3.weight(.semibold))
        Text("Copied items are captured automatically while the app is running. Use manual capture only as a fallback for inspection.")
          .font(.subheadline)
          .foregroundStyle(.secondary)

        if records.isEmpty {
          ContentUnavailableView(
            "No Captured Items",
            systemImage: "doc.on.clipboard",
            description: Text("Copy text, an image, or a file in another app and it will appear here automatically.")
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List(records) { record in
            VStack(alignment: .leading, spacing: 5) {
              HStack {
                Text(record.primaryType.rawValue.capitalized)
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.cyan)
                if record.isLargeContent {
                  Text("Large")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                }
                Spacer()
                Text(record.sourceAppName ?? "Unknown App")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }

              Text(record.title)
                .font(.headline)
                .lineLimit(1)

              if let preview = record.plainTextPreview, !preview.isEmpty {
                Text(preview)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
              }
            }
            .padding(.vertical, 4)
          }
        }
      }
      .padding(.leading, 20)
    }
  }

  private func statusLine(_ label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.headline)
    }
  }

  private func refreshAuthorization(unauthorizedStatus: String = "Accessibility required") {
    isAuthorized = services.systemClient.isAccessibilityTrusted()
    status = isAuthorized ? "Accessibility authorized" : unauthorizedStatus
  }

  private func requestAccessibilityPermission() {
    let trusted = services.systemClient.requestAccessibilityTrustPrompt()
    if trusted {
      isAuthorized = true
      status = "Accessibility authorized"
      return
    }

    services.systemClient.openAccessibilitySettings()
    isAuthorized = false
    status = "Permission requested. Enable ClipboardApp in System Settings, then click Recheck."
  }

  private func captureCurrentClipboard() async {
    refreshAuthorization()
    guard isAuthorized else {
      lastCaptureSummary = "Accessibility permission is not available."
      return
    }

    guard let capture = await services.systemClient.readCurrentCapture() else {
      lastCaptureSummary = "Clipboard is empty, unsupported, or was written by this app."
      return
    }

    await ingest(capture, summaryPrefix: "Captured")
  }

  private func pollClipboardChanges() async {
    isPollingClipboard = true
    defer {
      isPollingClipboard = false
    }

    guard let capture = await services.monitor.poll() else {
      return
    }

    await ingest(capture, summaryPrefix: "Auto-captured")
  }

  private func ingest(_ capture: ClipboardCapture, summaryPrefix: String) async {
    do {
      if let record = try await services.ingestService.ingest(capture) {
        lastCaptureSummary = "\(summaryPrefix) \(record.primaryType.rawValue) from \(record.sourceAppName ?? "unknown app")."
      } else {
        lastCaptureSummary = "Clipboard capture was ignored by the privacy policy."
      }
      await refreshRecords()
    } catch {
      lastCaptureSummary = "Failed to ingest clipboard item: \(error.localizedDescription)"
    }
  }

  private func refreshRecords() async {
    records = await services.store.fetchAll()
  }
}
