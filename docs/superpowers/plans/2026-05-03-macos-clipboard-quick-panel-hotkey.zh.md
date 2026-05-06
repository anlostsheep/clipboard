# macOS Clipboard QuickPanel Hotkey Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the next usable product slice: a global-hotkey QuickPanel that shows the current session clipboard history, supports search and keyboard selection, and copies or pastes the selected item.

**Architecture:** Keep `ClipboardCore` responsible for testable state and payload lookup, keep AppKit-specific hotkey/panel code in `ClipboardApp`, and keep `ClipboardPlatform` limited to system pasteboard and accessibility bridges. This plan still uses in-memory session storage; persistent SwiftData/SQLite, LibraryWindow, importers, and release packaging remain separate plans.

**Tech Stack:** Swift 5.10+, Swift Package Manager, XCTest, SwiftUI, AppKit, Carbon hot keys, ApplicationServices.

**Spec:** [2026-04-30-macos-native-clipboard-manager-design.md](../specs/2026-04-30-macos-native-clipboard-manager-design.md)

---

## Scope Check

This plan implements the smallest complete high-frequency interaction path:

- Global shortcut opens a floating QuickPanel.
- QuickPanel lists current session history from `InMemoryHistoryStore`.
- Search filters by title, preview, and source app through existing `HistoryStore.fetchPage`.
- Up/Down changes selected item.
- Escape closes the panel.
- Enter copies the selected item back to the system pasteboard and posts `Cmd+V` when accessibility is authorized.

This plan intentionally does not implement:

- SwiftData/SQLite persistent history.
- LibraryWindow.
- Maccy/Clipaste importers.
- Thumbnail cache or full PreviewService.
- User-configurable hotkey UI.
- Full rich text/image/file payload persistence across app restarts.

Because the current `ClipboardRecord` does not retain the original payload, this plan adds a session-only payload cache. That makes Enter work for items captured while this app instance is running. Persistent payload storage is part of the later persistent-store plan.

---

## File Structure

- Modify: `macos-clipboard-manager/Sources/ClipboardCore/Storage/HistoryStore.swift`
  - Add `ClipboardPayloadStore` and `InMemoryPayloadStore` for session payload lookup by `ClipboardRecord.id`.
- Modify: `macos-clipboard-manager/Tests/ClipboardCoreTests/ClipboardIngestServiceTests.swift`
  - Add focused payload-store tests.
- Create: `macos-clipboard-manager/Sources/ClipboardApp/AppServices.swift`
  - Owns shared store, payload store, system client, ingest service, monitor, paste controller, and panel controller dependencies.
- Create: `macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelState.swift`
  - Main-actor observable adapter around `QuickPanelViewModel`, payload lookup, and paste execution.
- Create: `macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelView.swift`
  - SwiftUI popup UI: search field, result list, selected row state, status footer.
- Create: `macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelKeyCaptureView.swift`
  - AppKit-backed key capture for Up, Down, Return, and Escape.
- Create: `macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelController.swift`
  - Owns `NSPanel` lifecycle, window sizing, screen positioning, and show/hide behavior.
- Create: `macos-clipboard-manager/Sources/ClipboardApp/HotKey/GlobalHotKeyRegistrar.swift`
  - Owns Carbon `RegisterEventHotKey` and dispatches the configured shortcut to the app.
- Modify: `macos-clipboard-manager/Sources/ClipboardApp/ClipboardApp.swift`
  - Replace direct service construction with `AppServices`, store payloads during ingest, and register the global hotkey.
- Modify: `macos-clipboard-manager/Docs/manual-acceptance-checklist.md`
  - Add QuickPanel hotkey and keyboard-flow manual acceptance rows.

---

### Task 1: Add Session Payload Store

**Files:**
- Modify: `macos-clipboard-manager/Sources/ClipboardCore/Storage/HistoryStore.swift`
- Modify: `macos-clipboard-manager/Tests/ClipboardCoreTests/ClipboardIngestServiceTests.swift`

- [ ] **Step 1: Add payload-store tests**

Append these tests inside `ClipboardIngestServiceTests`:

```swift
  func testPayloadStoreSavesAndLoadsPayloadByRecordID() async throws {
    let store = InMemoryPayloadStore()
    let id = UUID(uuidString: "00000000-0000-0000-0000-000000000060")!

    await store.save(.text("hello"), for: id)
    let payload = await store.loadPayload(for: id)

    XCTAssertEqual(payload, .text("hello"))
  }

  func testPayloadStoreReturnsNilForMissingRecordID() async throws {
    let store = InMemoryPayloadStore()
    let id = UUID(uuidString: "00000000-0000-0000-0000-000000000061")!

    let payload = await store.loadPayload(for: id)

    XCTAssertNil(payload)
  }
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
cd macos-clipboard-manager
swift test --filter ClipboardIngestServiceTests
```

Expected:

```text
error: cannot find 'InMemoryPayloadStore' in scope
```

- [ ] **Step 3: Implement payload store**

Append this code to `macos-clipboard-manager/Sources/ClipboardCore/Storage/HistoryStore.swift`:

```swift
public protocol ClipboardPayloadStore: Sendable {
  func save(_ payload: ClipboardPayload, for recordID: UUID) async
  func loadPayload(for recordID: UUID) async -> ClipboardPayload?
}

public actor InMemoryPayloadStore: ClipboardPayloadStore {
  private var payloadsByRecordID: [UUID: ClipboardPayload] = [:]

  public init() {}

  public func save(_ payload: ClipboardPayload, for recordID: UUID) async {
    payloadsByRecordID[recordID] = payload
  }

  public func loadPayload(for recordID: UUID) async -> ClipboardPayload? {
    payloadsByRecordID[recordID]
  }
}
```

- [ ] **Step 4: Run tests and verify pass**

Run:

```bash
cd macos-clipboard-manager
swift test --filter ClipboardIngestServiceTests
```

Expected:

```text
Test Suite 'ClipboardIngestServiceTests' passed
```

- [ ] **Step 5: Commit**

```bash
git add macos-clipboard-manager/Sources/ClipboardCore/Storage/HistoryStore.swift macos-clipboard-manager/Tests/ClipboardCoreTests/ClipboardIngestServiceTests.swift
git commit -m "feat: add session clipboard payload store"
```

---

### Task 2: Add App Service Container

**Files:**
- Create: `macos-clipboard-manager/Sources/ClipboardApp/AppServices.swift`
- Modify: `macos-clipboard-manager/Sources/ClipboardApp/ClipboardApp.swift`

- [ ] **Step 1: Create service container**

Create `macos-clipboard-manager/Sources/ClipboardApp/AppServices.swift`:

```swift
import ClipboardCore
import ClipboardPlatform
import Foundation

@MainActor
final class AppServices {
  let store: InMemoryHistoryStore
  let payloadStore: InMemoryPayloadStore
  let systemClient: SystemPasteboardClient
  let ingestService: ClipboardIngestService
  let monitor: ClipboardMonitor
  let pasteController: PasteController
  lazy var quickPanelState = QuickPanelState(
    viewModel: QuickPanelViewModel(store: store, pageLimit: 50),
    payloadStore: payloadStore,
    pasteController: pasteController
  )
  lazy var quickPanelController = QuickPanelController(state: quickPanelState)

  init(
    store: InMemoryHistoryStore = InMemoryHistoryStore(),
    payloadStore: InMemoryPayloadStore = InMemoryPayloadStore(),
    systemClient: SystemPasteboardClient = SystemPasteboardClient()
  ) {
    self.store = store
    self.payloadStore = payloadStore
    self.systemClient = systemClient
    self.ingestService = ClipboardIngestService(
      store: store,
      privacyPolicy: .standard,
      largeTextPolicy: .default
    )
    self.monitor = ClipboardMonitor(reader: systemClient)
    self.pasteController = PasteController(pasteboard: systemClient, eventPoster: systemClient)
  }
}
```

This step will not compile until `QuickPanelState` and `QuickPanelController` are added in later tasks.

- [ ] **Step 2: Wire services into app shell**

Modify the top of `ClipboardApp.swift` so `ClipboardApp` owns `AppServices`:

```swift
@main
struct ClipboardApp: App {
  @State private var services = AppServices()

  var body: some Scene {
    WindowGroup("Clipboard") {
      ClipboardRootView(services: services)
    }
  }
}
```

Change `ClipboardRootView` stored properties and initializer to:

```swift
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
```

Replace existing references:

```swift
systemClient -> services.systemClient
ingestService -> services.ingestService
monitor -> services.monitor
store -> services.store
```

Do not run build yet; later tasks define the missing quick panel types.

- [ ] **Step 3: Commit**

```bash
git add macos-clipboard-manager/Sources/ClipboardApp/AppServices.swift macos-clipboard-manager/Sources/ClipboardApp/ClipboardApp.swift
git commit -m "refactor: centralize clipboard app services"
```

---

### Task 3: Add QuickPanel State Adapter

**Files:**
- Create: `macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelState.swift`

- [ ] **Step 1: Create QuickPanelState**

Create `macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelState.swift`:

```swift
import ClipboardCore
import Foundation

@MainActor
final class QuickPanelState: ObservableObject {
  @Published private(set) var query = ""
  @Published private(set) var items: [ClipboardRecord] = []
  @Published private(set) var selectedIndex = 0
  @Published private(set) var footerStatus = "Ready"

  private let viewModel: QuickPanelViewModel
  private let payloadStore: InMemoryPayloadStore
  private let pasteController: PasteController

  init(
    viewModel: QuickPanelViewModel,
    payloadStore: InMemoryPayloadStore,
    pasteController: PasteController
  ) {
    self.viewModel = viewModel
    self.payloadStore = payloadStore
    self.pasteController = pasteController
  }

  func updateQuery(_ query: String) {
    self.query = query
    Task {
      await refresh()
    }
  }

  func refresh() async {
    await viewModel.refresh(query: query)
    items = await viewModel.items
    selectedIndex = await viewModel.selectedIndex
    footerStatus = items.isEmpty ? "No matching clipboard items" : "\(items.count) item\(items.count == 1 ? "" : "s")"
  }

  func moveSelection(delta: Int) {
    Task {
      await viewModel.moveSelection(delta: delta)
      selectedIndex = await viewModel.selectedIndex
    }
  }

  func selectCurrent(autoPaste: Bool) async {
    guard let intent = await viewModel.selectedIntent(autoPaste: autoPaste) else {
      footerStatus = "No clipboard item selected"
      return
    }

    guard let record = items.first(where: { $0.id == intent.recordID }) else {
      footerStatus = "Selected item is no longer visible"
      return
    }

    guard let payload = await payloadStore.loadPayload(for: record.id) else {
      footerStatus = "Payload is unavailable in this session"
      return
    }

    let transaction = await pasteController.paste(
      record: record,
      payload: payload,
      autoPaste: intent.autoPaste
    )

    switch transaction.state {
    case .completed:
      footerStatus = intent.autoPaste ? "Pasted \(record.primaryType.rawValue)" : "Copied \(record.primaryType.rawValue)"
    case let .failed(reason):
      footerStatus = "Paste failed: \(reason)"
    default:
      footerStatus = "Paste transaction ended in \(transaction.state)"
    }
  }
}
```

- [ ] **Step 2: Build and verify current expected failure**

Run:

```bash
cd macos-clipboard-manager
swift build --product ClipboardApp
```

Expected failure:

```text
cannot find 'QuickPanelController' in scope
```

- [ ] **Step 3: Commit**

```bash
git add macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelState.swift
git commit -m "feat: add quick panel state adapter"
```

---

### Task 4: Add QuickPanel SwiftUI View and Keyboard Capture

**Files:**
- Create: `macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelKeyCaptureView.swift`
- Create: `macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelView.swift`

- [ ] **Step 1: Create key capture view**

Create `macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelKeyCaptureView.swift`:

```swift
import AppKit
import SwiftUI

struct QuickPanelKeyCaptureView: NSViewRepresentable {
  let onMove: (Int) -> Void
  let onSubmit: () -> Void
  let onCancel: () -> Void

  func makeNSView(context: Context) -> KeyCaptureNSView {
    let view = KeyCaptureNSView()
    view.onMove = onMove
    view.onSubmit = onSubmit
    view.onCancel = onCancel
    DispatchQueue.main.async {
      view.window?.makeFirstResponder(view)
    }
    return view
  }

  func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
    nsView.onMove = onMove
    nsView.onSubmit = onSubmit
    nsView.onCancel = onCancel
    DispatchQueue.main.async {
      nsView.window?.makeFirstResponder(nsView)
    }
  }
}

final class KeyCaptureNSView: NSView {
  var onMove: ((Int) -> Void)?
  var onSubmit: (() -> Void)?
  var onCancel: (() -> Void)?

  override var acceptsFirstResponder: Bool {
    true
  }

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 53:
      onCancel?()
    case 36:
      onSubmit?()
    case 125:
      onMove?(1)
    case 126:
      onMove?(-1)
    default:
      super.keyDown(with: event)
    }
  }
}
```

- [ ] **Step 2: Create QuickPanelView**

Create `macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelView.swift`:

```swift
import ClipboardCore
import SwiftUI

struct QuickPanelView: View {
  @ObservedObject var state: QuickPanelState
  let onClose: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(.secondary)
        TextField("Search clipboard", text: Binding(
          get: { state.query },
          set: { state.updateQuery($0) }
        ))
        .textFieldStyle(.plain)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)

      Divider()

      if state.items.isEmpty {
        ContentUnavailableView(
          "No Clipboard Items",
          systemImage: "doc.on.clipboard",
          description: Text("Copy something while Clipboard is running.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollViewReader { proxy in
          List(Array(state.items.enumerated()), id: \.element.id) { index, record in
            QuickPanelRow(record: record, isSelected: index == state.selectedIndex)
              .id(record.id)
              .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
          }
          .listStyle(.plain)
          .onChange(of: state.selectedIndex) { _, selectedIndex in
            guard state.items.indices.contains(selectedIndex) else {
              return
            }
            proxy.scrollTo(state.items[selectedIndex].id, anchor: .center)
          }
        }
      }

      Divider()

      HStack {
        Text(state.footerStatus)
          .foregroundStyle(.secondary)
        Spacer()
        Text("Return Paste  Esc Close")
          .foregroundStyle(.secondary)
      }
      .font(.caption)
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
    }
    .frame(width: 620, height: 420)
    .background(.regularMaterial)
    .overlay(
      QuickPanelKeyCaptureView(
        onMove: { state.moveSelection(delta: $0) },
        onSubmit: {
          Task {
            await state.selectCurrent(autoPaste: true)
          }
        },
        onCancel: onClose
      )
      .frame(width: 0, height: 0)
    )
    .task {
      await state.refresh()
    }
  }
}

private struct QuickPanelRow: View {
  let record: ClipboardRecord
  let isSelected: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: iconName)
        .frame(width: 22)
        .foregroundStyle(isSelected ? .white : .cyan)

      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(record.title)
            .font(.headline)
            .lineLimit(1)
          if record.isLargeContent {
            Text("Large")
              .font(.caption.weight(.semibold))
              .foregroundStyle(isSelected ? .white.opacity(0.85) : .orange)
          }
        }

        if let preview = record.plainTextPreview, !preview.isEmpty {
          Text(preview)
            .font(.caption)
            .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
            .lineLimit(2)
        }

        Text(record.sourceAppName ?? "Unknown App")
          .font(.caption2)
          .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
      }

      Spacer()
    }
    .padding(.vertical, 6)
    .padding(.horizontal, 8)
    .background(isSelected ? Color.accentColor : Color.clear)
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private var iconName: String {
    switch record.primaryType {
    case .text, .richText:
      return "doc.text"
    case .link:
      return "link"
    case .image:
      return "photo"
    case .file:
      return "doc"
    }
  }
}
```

- [ ] **Step 3: Build and verify current expected failure**

Run:

```bash
cd macos-clipboard-manager
swift build --product ClipboardApp
```

Expected failure:

```text
cannot find 'QuickPanelController' in scope
```

- [ ] **Step 4: Commit**

```bash
git add macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelKeyCaptureView.swift macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelView.swift
git commit -m "feat: add quick panel view"
```

---

### Task 5: Add Floating NSPanel Controller

**Files:**
- Create: `macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelController.swift`

- [ ] **Step 1: Create QuickPanelController**

Create `macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelController.swift`:

```swift
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
    let panel = NSPanel(
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
```

- [ ] **Step 2: Build and verify pass**

Run:

```bash
cd macos-clipboard-manager
swift build --product ClipboardApp
```

Expected:

```text
Build of product 'ClipboardApp' complete!
```

- [ ] **Step 3: Commit**

```bash
git add macos-clipboard-manager/Sources/ClipboardApp/QuickPanel/QuickPanelController.swift
git commit -m "feat: add floating quick panel controller"
```

---

### Task 6: Add Global Hotkey Registrar

**Files:**
- Create: `macos-clipboard-manager/Sources/ClipboardApp/HotKey/GlobalHotKeyRegistrar.swift`
- Modify: `macos-clipboard-manager/Sources/ClipboardApp/ClipboardApp.swift`

- [ ] **Step 1: Create hotkey registrar**

Create `macos-clipboard-manager/Sources/ClipboardApp/HotKey/GlobalHotKeyRegistrar.swift`:

```swift
import AppKit
import Carbon

@MainActor
final class GlobalHotKeyRegistrar {
  private var eventHandlerRef: EventHandlerRef?
  private var hotKeyRef: EventHotKeyRef?
  private var action: (() -> Void)?

  func registerCommandShiftV(action: @escaping () -> Void) {
    unregister()
    self.action = action

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

    let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard let event, let userData else {
          return noErr
        }

        var hotKeyID = EventHotKeyID()
        GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &hotKeyID
        )

        guard hotKeyID.signature == OSType(0x434C4950) else {
          return noErr
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
      &eventHandlerRef
    )

    var hotKeyID = EventHotKeyID(signature: OSType(0x434C4950), id: UInt32(1))
    RegisterEventHotKey(
      UInt32(kVK_ANSI_V),
      UInt32(cmdKey | shiftKey),
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )
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
```

- [ ] **Step 2: Register hotkey from the app**

Modify `ClipboardApp.swift`:

Add this property to `ClipboardApp`:

```swift
  @State private var hotKeyRegistrar = GlobalHotKeyRegistrar()
```

Attach this modifier to `ClipboardRootView` inside `WindowGroup`:

```swift
      ClipboardRootView(services: services)
        .task {
          hotKeyRegistrar.registerCommandShiftV {
            services.quickPanelController.toggle()
          }
        }
```

The top of `ClipboardApp` should be:

```swift
@main
struct ClipboardApp: App {
  @State private var services = AppServices()
  @State private var hotKeyRegistrar = GlobalHotKeyRegistrar()

  var body: some Scene {
    WindowGroup("Clipboard") {
      ClipboardRootView(services: services)
        .task {
          hotKeyRegistrar.registerCommandShiftV {
            services.quickPanelController.toggle()
          }
        }
    }
  }
}
```

- [ ] **Step 3: Build and verify pass**

Run:

```bash
cd macos-clipboard-manager
swift build --product ClipboardApp
```

Expected:

```text
Build of product 'ClipboardApp' complete!
```

- [ ] **Step 4: Commit**

```bash
git add macos-clipboard-manager/Sources/ClipboardApp/HotKey/GlobalHotKeyRegistrar.swift macos-clipboard-manager/Sources/ClipboardApp/ClipboardApp.swift
git commit -m "feat: register quick panel global hotkey"
```

---

### Task 7: Store Payloads During Capture

**Files:**
- Modify: `macos-clipboard-manager/Sources/ClipboardApp/ClipboardApp.swift`

- [ ] **Step 1: Save payloads after ingest**

Modify `ClipboardRootView.ingest(_:summaryPrefix:)` so successful ingests store the payload:

```swift
  private func ingest(_ capture: ClipboardCapture, summaryPrefix: String) async {
    do {
      if let record = try await services.ingestService.ingest(capture) {
        await services.payloadStore.save(capture.payload, for: record.id)
        lastCaptureSummary = "\(summaryPrefix) \(record.primaryType.rawValue) from \(record.sourceAppName ?? "unknown app")."
      } else {
        lastCaptureSummary = "Clipboard capture was ignored by the privacy policy."
      }
      await refreshRecords()
    } catch {
      lastCaptureSummary = "Failed to ingest clipboard item: \(error.localizedDescription)"
    }
  }
```

- [ ] **Step 2: Build and verify pass**

Run:

```bash
cd macos-clipboard-manager
swift build --product ClipboardApp
```

Expected:

```text
Build of product 'ClipboardApp' complete!
```

- [ ] **Step 3: Commit**

```bash
git add macos-clipboard-manager/Sources/ClipboardApp/ClipboardApp.swift
git commit -m "feat: cache captured payloads for quick panel actions"
```

---

### Task 8: Add QuickPanel Manual Acceptance Checks

**Files:**
- Modify: `macos-clipboard-manager/Docs/manual-acceptance-checklist.md`

- [ ] **Step 1: Add manual acceptance section**

Add this section after `## 粘贴行为`:

```markdown
## QuickPanel 快捷键

- [ ] 启动 app 并授权辅助功能后，复制 3 条不同文本，主窗口 Session items 增长
- [ ] 按 `Command+Shift+V` 后浮动 QuickPanel 出现在当前屏幕中心附近
- [ ] QuickPanel 首屏显示最近复制的 session 历史，最新记录排在最上方
- [ ] 输入搜索关键词后，列表只保留匹配标题、摘要或来源 App 的记录
- [ ] 按 `Down` / `Up` 可以移动选中项，选中行有明显视觉状态
- [ ] 按 `Escape` 关闭 QuickPanel
- [ ] 在普通文本框中按 `Command+Shift+V` 打开 QuickPanel，选中记录后按 `Return`，记录被复制并自动粘贴
- [ ] 撤销辅助功能权限后，按 `Return` 不静默失败，footer 显示失败原因
- [ ] 复制 10MB JSON 后打开 QuickPanel，列表只显示摘要，不渲染全文
```

- [ ] **Step 2: Commit**

```bash
git add macos-clipboard-manager/Docs/manual-acceptance-checklist.md
git commit -m "docs: add quick panel acceptance checklist"
```

---

### Task 9: Full Verification and App Bundle Smoke Test

**Files:**
- Read: `macos-clipboard-manager/Scripts/verify.sh`
- Read: `macos-clipboard-manager/Scripts/build-app-bundle.sh`
- Read: `macos-clipboard-manager/Docs/manual-acceptance-checklist.md`

- [ ] **Step 1: Run full automated verification**

Run:

```bash
cd macos-clipboard-manager
Scripts/verify.sh
```

Expected:

```text
Test Suite 'All tests' passed
Build complete!
```

- [ ] **Step 2: Build and launch app bundle**

Run:

```bash
cd macos-clipboard-manager
pkill -f "ClipboardApp.app/Contents/MacOS/ClipboardApp" || true
app_path="$(Scripts/build-app-bundle.sh)"
open -n "$app_path"
```

Expected:

```text
signing with identity: ClipboardApp Local Code Signing
```

- [ ] **Step 3: Run clipboard smoke setup**

Run:

```bash
printf 'quick-panel-alpha' | pbcopy
sleep 1
printf 'quick-panel-beta' | pbcopy
sleep 1
printf 'quick-panel-gamma' | pbcopy
```

Expected:

```text
No terminal output.
```

- [ ] **Step 4: Manual hotkey verification**

Perform these actions manually:

```text
1. Click any normal text input in another app.
2. Press Command+Shift+V.
3. Confirm the QuickPanel opens.
4. Type beta.
5. Confirm only quick-panel-beta remains or is the top visible match.
6. Press Return.
7. Confirm quick-panel-beta is pasted into the text input.
8. Press Command+Shift+V again.
9. Press Escape.
10. Confirm the panel closes.
```

Expected:

```text
QuickPanel opens, filters, pastes, and closes without crashing.
```

- [ ] **Step 5: Confirm working tree and review**

Run:

```bash
git status --short --branch --untracked-files=all
```

Expected:

```text
Only intended files are modified or untracked before final commit.
```

- [ ] **Step 6: Final commit**

```bash
git add macos-clipboard-manager/Sources/ClipboardCore/Storage/HistoryStore.swift \
  macos-clipboard-manager/Tests/ClipboardCoreTests/ClipboardIngestServiceTests.swift \
  macos-clipboard-manager/Sources/ClipboardApp \
  macos-clipboard-manager/Docs/manual-acceptance-checklist.md
git commit -m "feat: add quick panel hotkey flow"
```

---

## Self-Review

- Spec coverage: This plan covers the design's high-frequency QuickPanel path: shortcut, lightweight list, search, selection, copy/paste, failure status, and no full large-text rendering.
- Deliberate gaps: Persistent storage, LibraryWindow, importers, configurable hotkey UI, thumbnail cache, and full PreviewService are excluded and need separate plans.
- Type consistency: The plan uses existing `QuickPanelViewModel`, `InMemoryHistoryStore`, `ClipboardPayload`, `PasteController`, `SystemPasteboardClient`, and `ClipboardRecord` names from current source.
- Verification: The plan includes unit tests for new payload storage, product build checks after UI/hotkey steps, full `Scripts/verify.sh`, signed app launch, and manual hotkey acceptance.
