# Maccy Replacement Privacy And Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the privacy controls, QuickPanel management actions, and benchmark evidence needed to judge Clipboard as a credible local Maccy replacement on the user's imported history dataset.

**Architecture:** Add narrow services around the existing capture, store, and QuickPanel boundaries. `CaptureControlService` gates captures before ingest, `HistoryMutationService` owns record mutations and payload cleanup, and `ClipboardBenchmarkProbe` measures the current dataset without changing it.

**Tech Stack:** Swift 5.10, Swift Package Manager, Swift Concurrency actors, SwiftUI, AppKit, XCTest, SQLite3, shell scripts.

---

## Scope Check

The approved spec covers three related surfaces: runtime privacy/capture control, QuickPanel history management, and performance comparison. They are in one plan because all three share the same completion goal: prove whether the current imported-history app can replace Maccy. Each task below is independently testable and commits a working slice.

## File Structure

- Create: `Sources/ClipboardCore/Capture/CaptureControlService.swift`
  - Owns pause/resume, ignore-next-copy, effective privacy policy, and skip diagnostics.
- Modify: `Sources/ClipboardCore/Ingest/ClipboardCaptureCoordinator.swift`
  - Calls `CaptureControlService` after `ClipboardMonitor.poll()` and before payload persistence.
- Modify: `Sources/ClipboardCore/Ingest/ClipboardIngestService.swift`
  - Stops owning immutable privacy policy decisions; keeps record construction and large-text classification.
- Modify: `Sources/ClipboardCore/Storage/HistoryStore.swift`
  - Adds a focused mutation protocol implemented by stores.
- Modify: `Sources/ClipboardCore/Storage/SQLite/SQLiteHistoryStore.swift`
  - Implements delete, pin toggle, and clear-unpinned on the SQLite index and table.
- Modify: `Sources/ClipboardCore/Storage/PayloadCleaningHistoryStore.swift`
  - Forwards mutation operations and deletes payload files for removed records.
- Create: `Sources/ClipboardCore/Storage/HistoryMutationService.swift`
  - Provides the app-facing mutation API for QuickPanel and future LibraryWindow.
- Modify: `Sources/ClipboardApp/AppSettings.swift`
  - Adds persistent keys and helpers for privacy lists and capture state.
- Modify: `Sources/ClipboardApp/AppServices.swift`
  - Wires capture control and history mutation into existing services.
- Modify: `Sources/ClipboardApp/Settings/PrivacySettingsView.swift`
  - Replaces static privacy text with editable Universal Clipboard, pasteboard type, and app bundle ID controls.
- Modify: `Sources/ClipboardApp/StatusBar/StatusBarController.swift`
  - Adds pause/resume and ignore-next-copy menu actions plus a visible paused state.
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelState.swift`
  - Adds delete, pin/unpin, clear-unpinned, clear-all request methods.
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelKeyCaptureView.swift`
  - Adds keyboard actions for management shortcuts.
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelView.swift`
  - Adds a discoverable action menu and clear-all confirmation.
- Modify: `Sources/ClipboardManualProbe/main.swift`
  - Adds probe commands for capture policy and app storage paths.
- Modify: `Package.swift`
  - Adds `ClipboardBenchmarkProbe` executable.
- Create: `Sources/ClipboardBenchmarkProbe/main.swift`
  - Emits JSON and readable benchmark summaries.
- Create: `Scripts/benchmark-maccy-replacement.sh`
  - Runs the benchmark probe and writes reports.
- Modify: `docs/manual-acceptance-checklist.md`
  - Adds acceptance items for this change.
- Tests:
  - Create: `Tests/ClipboardCoreTests/CaptureControlServiceTests.swift`
  - Create: `Tests/ClipboardCoreTests/HistoryMutationServiceTests.swift`
  - Create: `Tests/ClipboardCoreTests/BenchmarkComparisonTests.swift`
  - Modify: `Tests/ClipboardCoreTests/ClipboardCaptureCoordinatorTests.swift`
  - Modify: `Tests/ClipboardCoreTests/HistoryStoreConformanceTests.swift`
  - Modify: `Tests/ClipboardAppTests/QuickPanelKeyCaptureTests.swift`
  - Create: `Tests/ClipboardAppTests/PrivacySettingsViewTests.swift`
  - Modify: `Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift`

---

### Task 1: Capture Control Core

**Files:**
- Create: `Sources/ClipboardCore/Capture/CaptureControlService.swift`
- Modify: `Sources/ClipboardCore/Ingest/ClipboardCaptureCoordinator.swift`
- Modify: `Sources/ClipboardCore/Ingest/ClipboardIngestService.swift`
- Test: `Tests/ClipboardCoreTests/CaptureControlServiceTests.swift`
- Test: `Tests/ClipboardCoreTests/ClipboardCaptureCoordinatorTests.swift`

- [ ] **Step 1: Write failing capture-control tests**

Create `Tests/ClipboardCoreTests/CaptureControlServiceTests.swift`:

```swift
import XCTest
@testable import ClipboardCore

final class CaptureControlServiceTests: XCTestCase {
  func testPausedCaptureIsSkipped() async {
    let service = CaptureControlService(policy: .standard)
    await service.pauseCapture()

    let decision = await service.evaluate(.fixture(text: "paused"))

    XCTAssertEqual(decision, .skip(.paused))
  }

  func testResumeAllowsCapture() async {
    let service = CaptureControlService(policy: .standard)
    await service.pauseCapture()
    await service.resumeCapture()

    let decision = await service.evaluate(.fixture(text: "allowed"))

    XCTAssertEqual(decision, .allow)
  }

  func testIgnoreNextCopySkipsExactlyOneCapture() async {
    let service = CaptureControlService(policy: .standard)
    await service.ignoreNextCopy()

    let first = await service.evaluate(.fixture(text: "skip"))
    let second = await service.evaluate(.fixture(text: "allow"))

    XCTAssertEqual(first, .skip(.ignoreNextCopy))
    XCTAssertEqual(second, .allow)
  }

  func testUniversalClipboardSettingBlocksRemoteCapture() async {
    var policy = PrivacyPolicy.standard
    policy.recordsUniversalClipboard = false
    let service = CaptureControlService(policy: policy)

    let decision = await service.evaluate(.fixture(
      text: "remote",
      pasteboardTypes: ["public.utf8-plain-text", "com.apple.is-remote-clipboard"]
    ))

    XCTAssertEqual(decision, .skip(.privacy(.universalClipboard)))
  }

  func testIgnoredPasteboardTypeBlocksCapture() async {
    var policy = PrivacyPolicy.standard
    policy.ignoredPasteboardTypes.insert("com.example.secret")
    let service = CaptureControlService(policy: policy)

    let decision = await service.evaluate(.fixture(
      text: "secret",
      pasteboardTypes: ["com.example.secret"]
    ))

    XCTAssertEqual(decision, .skip(.privacy(.pasteboardType("com.example.secret"))))
  }

  func testIgnoredAppBundleIDBlocksCapture() async {
    var policy = PrivacyPolicy.standard
    policy.ignoredAppBundleIds.insert("com.example.SecretApp")
    let service = CaptureControlService(policy: policy)

    let decision = await service.evaluate(.fixture(
      text: "secret",
      sourceBundleID: "com.example.SecretApp"
    ))

    XCTAssertEqual(decision, .skip(.privacy(.sourceApp("com.example.SecretApp"))))
  }

  func testUpdatePolicyAffectsRunningService() async {
    let service = CaptureControlService(policy: .standard)
    var policy = PrivacyPolicy.standard
    policy.recordsUniversalClipboard = false
    await service.updatePolicy(policy)

    let decision = await service.evaluate(.fixture(
      text: "remote",
      pasteboardTypes: ["com.apple.is-remote-clipboard"]
    ))

    XCTAssertEqual(decision, .skip(.privacy(.universalClipboard)))
  }
}

private extension ClipboardCapture {
  static func fixture(
    text: String,
    pasteboardTypes: Set<String> = ["public.utf8-plain-text"],
    sourceBundleID: String? = nil
  ) -> ClipboardCapture {
    ClipboardCapture(
      payload: .text(text),
      pasteboardTypes: pasteboardTypes,
      sourceAppBundleId: sourceBundleID,
      sourceAppName: sourceBundleID.map { _ in "Fixture" },
      capturedAt: Date(timeIntervalSince1970: 1)
    )
  }
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
swift test --filter CaptureControlServiceTests
```

Expected: fails because `CaptureControlService` is not defined.

- [ ] **Step 3: Implement `CaptureControlService`**

Create `Sources/ClipboardCore/Capture/CaptureControlService.swift`:

```swift
import Foundation

public enum CapturePrivacySkipReason: Equatable, Sendable {
  case universalClipboard
  case pasteboardType(String)
  case sourceApp(String)
  case transientOnly
}

public enum CaptureSkipReason: Equatable, Sendable {
  case paused
  case ignoreNextCopy
  case privacy(CapturePrivacySkipReason)
}

public enum CaptureDecision: Equatable, Sendable {
  case allow
  case skip(CaptureSkipReason)
}

public actor CaptureControlService {
  private var policy: PrivacyPolicy
  private var isPaused = false
  private var ignoresNextCopy = false
  public private(set) var lastSkipReason: CaptureSkipReason?

  public init(policy: PrivacyPolicy) {
    self.policy = policy
  }

  public func pauseCapture() {
    isPaused = true
  }

  public func resumeCapture() {
    isPaused = false
  }

  public func ignoreNextCopy() {
    ignoresNextCopy = true
  }

  public func updatePolicy(_ policy: PrivacyPolicy) {
    self.policy = policy
  }

  public func capturePaused() -> Bool {
    isPaused
  }

  public func evaluate(_ capture: ClipboardCapture) -> CaptureDecision {
    if isPaused {
      lastSkipReason = .paused
      return .skip(.paused)
    }

    if ignoresNextCopy {
      ignoresNextCopy = false
      lastSkipReason = .ignoreNextCopy
      return .skip(.ignoreNextCopy)
    }

    if let reason = privacySkipReason(for: capture) {
      let skip = CaptureSkipReason.privacy(reason)
      lastSkipReason = skip
      return .skip(skip)
    }

    lastSkipReason = nil
    return .allow
  }

  private func privacySkipReason(for capture: ClipboardCapture) -> CapturePrivacySkipReason? {
    if capture.pasteboardTypes.contains("com.apple.is-remote-clipboard"),
       !policy.recordsUniversalClipboard {
      return .universalClipboard
    }

    if let sourceBundleID = capture.sourceAppBundleId,
       policy.ignoredAppBundleIds.contains(sourceBundleID) {
      return .sourceApp(sourceBundleID)
    }

    if let ignored = capture.pasteboardTypes
      .intersection(policy.ignoredPasteboardTypes)
      .sorted()
      .first {
      return .pasteboardType(ignored)
    }

    let nonTransientTypes = capture.pasteboardTypes.subtracting(policy.ignoredTransientTypes)
    if !capture.pasteboardTypes.isDisjoint(with: policy.ignoredTransientTypes),
       nonTransientTypes.isEmpty {
      return .transientOnly
    }

    return nil
  }
}
```

- [ ] **Step 4: Run capture-control tests**

Run:

```bash
swift test --filter CaptureControlServiceTests
```

Expected: all tests pass.

- [ ] **Step 5: Write failing coordinator integration test**

Modify `Tests/ClipboardCoreTests/ClipboardCaptureCoordinatorTests.swift` by adding:

```swift
func testCaptureControlSkipsBeforePayloadSave() async throws {
  let reader = StubPasteboardReader()
  reader.changeCount = 1
  reader.capture = .fixture(text: "ignored", pasteboardTypes: ["com.example.secret"])

  let monitor = ClipboardMonitor(reader: reader)
  var policy = PrivacyPolicy.standard
  policy.ignoredPasteboardTypes.insert("com.example.secret")
  let captureControl = CaptureControlService(policy: policy)
  let store = InMemoryHistoryStore()
  let payloadStore = CountingPayloadStore()
  let coordinator = ClipboardCaptureCoordinator(
    monitor: monitor,
    ingestService: ClipboardIngestService(store: store, privacyPolicy: .standard, largeTextPolicy: .default),
    payloadStore: payloadStore,
    failureHandler: NoopStorageFailureHandler(),
    captureControl: captureControl
  )

  let record = try await coordinator.captureLatestChange()

  XCTAssertNil(record)
  XCTAssertEqual(try await store.count(), 0)
  XCTAssertEqual(await payloadStore.saveCount, 0)
}
```

Add these helper types at the bottom of that file:

```swift
private final class StubPasteboardReader: PasteboardReading, @unchecked Sendable {
  var changeCount = 0
  var capture: ClipboardCapture?

  func currentChangeCount() async -> Int { changeCount }
  func readCurrentCapture() async -> ClipboardCapture? { capture }
}

private actor CountingPayloadStore: ClipboardPayloadStore {
  private(set) var saveCount = 0

  func save(_ payload: ClipboardPayload, for recordID: UUID) async throws {
    saveCount += 1
  }

  func loadPayload(for recordID: UUID) async throws -> ClipboardPayload? {
    nil
  }

  func delete(for recordID: UUID) async throws {}
}

private struct NoopStorageFailureHandler: StorageFailureHandler {
  func handleStorageFailure(_ error: StorageError, record: ClipboardRecord) async -> Bool { true }
  func reportSuccess() async {}
}
```

- [ ] **Step 6: Run coordinator test to verify failure**

Run:

```bash
swift test --filter ClipboardCaptureCoordinatorTests/testCaptureControlSkipsBeforePayloadSave
```

Expected: fails because `ClipboardCaptureCoordinator` does not accept `captureControl`.

- [ ] **Step 7: Wire capture control into coordinator**

Modify `Sources/ClipboardCore/Ingest/ClipboardCaptureCoordinator.swift`:

```swift
public struct ClipboardCaptureCoordinator: Sendable {
  private let monitor: ClipboardMonitor
  private let ingestService: ClipboardIngestService
  private let payloadStore: any ClipboardPayloadStore
  private let failureHandler: any StorageFailureHandler
  private let captureControl: CaptureControlService?

  public init(
    monitor: ClipboardMonitor,
    ingestService: ClipboardIngestService,
    payloadStore: any ClipboardPayloadStore,
    failureHandler: any StorageFailureHandler,
    captureControl: CaptureControlService? = nil
  ) {
    self.monitor = monitor
    self.ingestService = ingestService
    self.payloadStore = payloadStore
    self.failureHandler = failureHandler
    self.captureControl = captureControl
  }

  public func captureLatestChange() async throws -> ClipboardRecord? {
    guard let capture = await monitor.poll() else { return nil }
    if let captureControl {
      switch await captureControl.evaluate(capture) {
      case .allow:
        break
      case .skip:
        return nil
      }
    }
    return try await ingest(capture)
  }

  public func ingest(_ capture: ClipboardCapture) async throws -> ClipboardRecord? {
    guard let record = try ingestService.makeRecord(from: capture) else { return nil }
    try await payloadStore.save(capture.payload, for: record.id)
    var attempts = 0
    while true {
      do {
        let stored = try await ingestService.persist(record)
        await failureHandler.reportSuccess()
        return stored
      } catch let error as StorageError {
        attempts += 1
        let handled = await failureHandler.handleStorageFailure(error, record: record)
        if handled {
          try? await payloadStore.delete(for: record.id)
          return nil
        }
        if attempts >= 10 {
          try? await payloadStore.delete(for: record.id)
          return nil
        }
      }
    }
  }
}
```

- [ ] **Step 8: Run tests and commit**

Run:

```bash
swift test --filter CaptureControlServiceTests
swift test --filter ClipboardCaptureCoordinatorTests
```

Expected: both pass.

Commit:

```bash
git add Sources/ClipboardCore/Capture/CaptureControlService.swift \
  Sources/ClipboardCore/Ingest/ClipboardCaptureCoordinator.swift \
  Tests/ClipboardCoreTests/CaptureControlServiceTests.swift \
  Tests/ClipboardCoreTests/ClipboardCaptureCoordinatorTests.swift
git commit -m "feat: add capture control policy"
```

---

### Task 2: Runtime Privacy Settings And Capture UI

**Files:**
- Modify: `Sources/ClipboardApp/AppSettings.swift`
- Modify: `Sources/ClipboardApp/AppServices.swift`
- Modify: `Sources/ClipboardApp/Settings/PrivacySettingsView.swift`
- Modify: `Sources/ClipboardApp/StatusBar/StatusBarController.swift`
- Modify: `Sources/ClipboardManualProbe/main.swift`
- Test: `Tests/ClipboardAppTests/PrivacySettingsViewTests.swift`

- [ ] **Step 1: Write failing app-settings tests**

Create `Tests/ClipboardAppTests/PrivacySettingsViewTests.swift`:

```swift
import XCTest
@testable import ClipboardApp
@testable import ClipboardCore

final class PrivacySettingsViewTests: XCTestCase {
  func testPrivacyPolicyFromSettingsIgnoresUniversalClipboard() {
    let defaults = UserDefaults(suiteName: "PrivacySettingsViewTests-\(UUID().uuidString)")!
    defaults.set(true, forKey: ClipboardAppSettings.ignoreUniversalClipboardKey)

    let policy = ClipboardAppSettings.privacyPolicy(defaults: defaults)

    XCTAssertFalse(policy.recordsUniversalClipboard)
  }

  func testPrivacyPolicyFromSettingsAppendsTypesAndBundleIDs() {
    let defaults = UserDefaults(suiteName: "PrivacySettingsViewTests-\(UUID().uuidString)")!
    defaults.set(["com.example.secret"], forKey: ClipboardAppSettings.ignoredPasteboardTypesKey)
    defaults.set(["com.example.SecretApp"], forKey: ClipboardAppSettings.ignoredAppBundleIDsKey)

    let policy = ClipboardAppSettings.privacyPolicy(defaults: defaults)

    XCTAssertTrue(policy.ignoredPasteboardTypes.contains("com.example.secret"))
    XCTAssertTrue(policy.ignoredAppBundleIds.contains("com.example.SecretApp"))
    XCTAssertTrue(policy.ignoredPasteboardTypes.contains("org.nspasteboard.ConcealedType"))
  }
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
swift test --filter PrivacySettingsViewTests
```

Expected: fails because the new keys and helper are missing.

- [ ] **Step 3: Add settings helpers**

Modify `Sources/ClipboardApp/AppSettings.swift` inside `ClipboardAppSettings`:

```swift
static let ignoreUniversalClipboardKey = "privacy.ignoreUniversalClipboard"
static let ignoredPasteboardTypesKey = "privacy.ignoredPasteboardTypes"
static let ignoredAppBundleIDsKey = "privacy.ignoredAppBundleIds"
static let capturePausedKey = "capture.paused"

static func ignoredPasteboardTypes(defaults: UserDefaults = .standard) -> Set<String> {
    Set(defaults.stringArray(forKey: ignoredPasteboardTypesKey) ?? [])
}

static func ignoredAppBundleIDs(defaults: UserDefaults = .standard) -> Set<String> {
    Set(defaults.stringArray(forKey: ignoredAppBundleIDsKey) ?? [])
}

static func privacyPolicy(defaults: UserDefaults = .standard) -> PrivacyPolicy {
    var policy = PrivacyPolicy.standard
    if defaults.bool(forKey: ignoreUniversalClipboardKey) {
        policy.recordsUniversalClipboard = false
    }
    policy.ignoredPasteboardTypes.formUnion(ignoredPasteboardTypes(defaults: defaults))
    policy.ignoredAppBundleIds.formUnion(ignoredAppBundleIDs(defaults: defaults))
    return policy
}

static func capturePaused(defaults: UserDefaults = .standard) -> Bool {
    defaults.bool(forKey: capturePausedKey)
}

static func setCapturePaused(_ paused: Bool, defaults: UserDefaults = .standard) {
    defaults.set(paused, forKey: capturePausedKey)
}
```

- [ ] **Step 4: Run settings tests**

Run:

```bash
swift test --filter PrivacySettingsViewTests
```

Expected: pass.

- [ ] **Step 5: Wire `AppServices` to live capture control**

Modify `Sources/ClipboardApp/AppServices.swift`:

```swift
let captureControl: CaptureControlService
let historyMutationService: HistoryMutationService
@Published private(set) var capturePaused: Bool = false
```

In `init()` after storage is created and before `ClipboardCaptureCoordinator`:

```swift
self.captureControl = CaptureControlService(policy: ClipboardAppSettings.privacyPolicy())
self.capturePaused = ClipboardAppSettings.capturePaused()
if capturePaused {
  Task { await captureControl.pauseCapture() }
}
self.historyMutationService = HistoryMutationService(store: storeImpl, payloadStore: payloadImpl)
```

Change coordinator construction:

```swift
let coordinator = ClipboardCaptureCoordinator(
  monitor: monitor,
  ingestService: ingestService,
  payloadStore: payloadImpl,
  failureHandler: handler,
  captureControl: captureControl
)
```

Add methods:

```swift
func refreshPrivacyPolicyFromSettings() {
  Task {
    await captureControl.updatePolicy(ClipboardAppSettings.privacyPolicy())
  }
}

func pauseCapture() {
  ClipboardAppSettings.setCapturePaused(true)
  capturePaused = true
  Task { await captureControl.pauseCapture() }
}

func resumeCapture() {
  ClipboardAppSettings.setCapturePaused(false)
  capturePaused = false
  Task { await captureControl.resumeCapture() }
}

func ignoreNextCopy() {
  Task { await captureControl.ignoreNextCopy() }
}
```

- [ ] **Step 6: Update Privacy settings UI**

Modify `Sources/ClipboardApp/Settings/PrivacySettingsView.swift` to accept services and expose simple list editors:

```swift
struct PrivacySettingsView: View {
    @ObservedObject var services: AppServices

    @AppStorage(ClipboardAppSettings.ignoreUniversalClipboardKey)
    private var ignoreUniversalClipboard: Bool = false

    @AppStorage(ClipboardAppSettings.ignoredPasteboardTypesKey)
    private var ignoredPasteboardTypes: [String] = []

    @AppStorage(ClipboardAppSettings.ignoredAppBundleIDsKey)
    private var ignoredAppBundleIDs: [String] = []

    @State private var newPasteboardType = ""
    @State private var newBundleID = ""

    var body: some View {
        Form {
            Section("Universal Clipboard") {
                Toggle("忽略来自其他 Apple 设备的剪贴板内容", isOn: $ignoreUniversalClipboard)
                Text("开启后，带 com.apple.is-remote-clipboard 的内容不会被记录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("忽略 Pasteboard Type") {
                ForEach(ignoredPasteboardTypes, id: \.self) { type in
                    Text(type)
                }
                HStack {
                    TextField("com.example.secret", text: $newPasteboardType)
                    Button("添加") {
                        let value = newPasteboardType.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty, !ignoredPasteboardTypes.contains(value) else { return }
                        ignoredPasteboardTypes.append(value)
                        newPasteboardType = ""
                    }
                }
            }

            Section("忽略 App Bundle ID") {
                ForEach(ignoredAppBundleIDs, id: \.self) { bundleID in
                    Text(bundleID)
                }
                HStack {
                    TextField("com.example.SecretApp", text: $newBundleID)
                    Button("添加") {
                        let value = newBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty, !ignoredAppBundleIDs.contains(value) else { return }
                        ignoredAppBundleIDs.append(value)
                        newBundleID = ""
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: ignoreUniversalClipboard) { _, _ in services.refreshPrivacyPolicyFromSettings() }
        .onChange(of: ignoredPasteboardTypes) { _, _ in services.refreshPrivacyPolicyFromSettings() }
        .onChange(of: ignoredAppBundleIDs) { _, _ in services.refreshPrivacyPolicyFromSettings() }
    }
}
```

Modify `Sources/ClipboardApp/Settings/SettingsWindow.swift`:

```swift
case .privacy:
    PrivacySettingsView(services: services)
```

- [ ] **Step 7: Add status bar capture actions**

Modify `Sources/ClipboardApp/StatusBar/StatusBarController.swift` constructor to include:

```swift
private let onToggleCapture: () -> Void
private let onIgnoreNextCopy: () -> Void
private let isCapturePaused: () -> Bool
```

Add menu items before quit:

```swift
let pauseTitle = isCapturePaused() ? "恢复采集" : "暂停采集"
menu.addItem(NSMenuItem(title: pauseTitle, action: #selector(toggleCapture), keyEquivalent: ""))
menu.addItem(NSMenuItem(title: "忽略下一次复制", action: #selector(ignoreNextCopy), keyEquivalent: ""))
```

Add actions:

```swift
@objc private func toggleCapture() {
    onToggleCapture()
}

@objc private func ignoreNextCopy() {
    onIgnoreNextCopy()
}
```

Modify `Sources/ClipboardApp/App/AppDelegate.swift` status bar setup:

```swift
statusBarController = StatusBarController(
    onLeftClick: { [weak self] iconOrigin in
        guard let self else { return }
        self.services.quickPanelController.statusBarIconOrigin = iconOrigin
        self.services.quickPanelController.toggle(trigger: .statusBarClick(iconOrigin: iconOrigin))
    },
    onQuit: {
        NSApp.terminate(nil)
    },
    onToggleCapture: { [weak self] in
        guard let self else { return }
        if self.services.capturePaused {
            self.services.resumeCapture()
        } else {
            self.services.pauseCapture()
        }
    },
    onIgnoreNextCopy: { [weak self] in
        self?.services.ignoreNextCopy()
    },
    isCapturePaused: { [weak self] in
        self?.services.capturePaused ?? false
    }
)
```

- [ ] **Step 8: Extend manual probe**

Modify `Sources/ClipboardManualProbe/main.swift` usage to include:

```swift
usage: ClipboardManualProbe read-once|write-marker-text|accessibility|self-check|policy-universal-ignore|policy-ignore-type|policy-ignore-app
```

Add command cases:

```swift
case "policy-universal-ignore":
  var policy = PrivacyPolicy.standard
  policy.recordsUniversalClipboard = false
  let service = CaptureControlService(policy: policy)
  let decision = await service.evaluate(ClipboardCapture(
    payload: .text("remote"),
    pasteboardTypes: ["com.apple.is-remote-clipboard"],
    sourceAppBundleId: nil,
    sourceAppName: nil,
    capturedAt: Date()
  ))
  print("decision: \(decision)")
case "policy-ignore-type":
  let type = CommandLine.arguments.dropFirst(2).first ?? "com.example.secret"
  var policy = PrivacyPolicy.standard
  policy.ignoredPasteboardTypes.insert(type)
  let service = CaptureControlService(policy: policy)
  let decision = await service.evaluate(ClipboardCapture(
    payload: .text("secret"),
    pasteboardTypes: [type],
    sourceAppBundleId: nil,
    sourceAppName: nil,
    capturedAt: Date()
  ))
  print("decision: \(decision)")
case "policy-ignore-app":
  let bundleID = CommandLine.arguments.dropFirst(2).first ?? "com.example.SecretApp"
  var policy = PrivacyPolicy.standard
  policy.ignoredAppBundleIds.insert(bundleID)
  let service = CaptureControlService(policy: policy)
  let decision = await service.evaluate(ClipboardCapture(
    payload: .text("secret"),
    pasteboardTypes: ["public.utf8-plain-text"],
    sourceAppBundleId: bundleID,
    sourceAppName: "SecretApp",
    capturedAt: Date()
  ))
  print("decision: \(decision)")
```

- [ ] **Step 9: Run tests and commit**

Run:

```bash
swift test --filter PrivacySettingsViewTests
swift build --product ClipboardManualProbe
swift build --product ClipboardApp
swift run ClipboardManualProbe policy-universal-ignore
```

Expected:

```text
decision: skip(ClipboardCore.CaptureSkipReason.privacy(ClipboardCore.CapturePrivacySkipReason.universalClipboard))
```

Commit:

```bash
git add Sources/ClipboardApp/AppSettings.swift \
  Sources/ClipboardApp/AppServices.swift \
  Sources/ClipboardApp/Settings/PrivacySettingsView.swift \
  Sources/ClipboardApp/Settings/SettingsWindow.swift \
  Sources/ClipboardApp/StatusBar/StatusBarController.swift \
  Sources/ClipboardApp/App/AppDelegate.swift \
  Sources/ClipboardManualProbe/main.swift \
  Tests/ClipboardAppTests/PrivacySettingsViewTests.swift
git commit -m "feat: wire runtime capture privacy controls"
```

---

### Task 3: History Mutation Core

**Files:**
- Modify: `Sources/ClipboardCore/Storage/HistoryStore.swift`
- Modify: `Sources/ClipboardCore/Storage/SQLite/SQLiteHistoryStore.swift`
- Modify: `Sources/ClipboardCore/Storage/PayloadCleaningHistoryStore.swift`
- Create: `Sources/ClipboardCore/Storage/HistoryMutationService.swift`
- Test: `Tests/ClipboardCoreTests/HistoryStoreConformanceTests.swift`
- Test: `Tests/ClipboardCoreTests/HistoryMutationServiceTests.swift`

- [ ] **Step 1: Write failing mutation tests**

Create `Tests/ClipboardCoreTests/HistoryMutationServiceTests.swift`:

```swift
import XCTest
@testable import ClipboardCore

final class HistoryMutationServiceTests: XCTestCase {
  func testDeleteRecordRemovesRecordAndPayload() async throws {
    let store = InMemoryHistoryStore()
    let payloadStore = InMemoryPayloadStore()
    let record = makeRecord(hash: "delete", title: "delete me")
    _ = try await store.upsert(record)
    try await payloadStore.save(.text("delete me"), for: record.id)
    let service = HistoryMutationService(store: store, payloadStore: payloadStore)

    try await service.deleteRecord(id: record.id)

    XCTAssertEqual(try await store.count(), 0)
    XCTAssertNil(try await payloadStore.loadPayload(for: record.id))
  }

  func testTogglePinnedUpdatesRetentionExemption() async throws {
    let store = InMemoryHistoryStore()
    let payloadStore = InMemoryPayloadStore()
    let record = makeRecord(hash: "pin", title: "pin me")
    _ = try await store.upsert(record)
    let service = HistoryMutationService(store: store, payloadStore: payloadStore)

    let pinned = try await service.togglePinned(id: record.id)

    XCTAssertTrue(pinned.isPinned)
    XCTAssertTrue(pinned.retentionExempt)
  }

  func testClearUnpinnedPreservesPinnedRecords() async throws {
    let store = InMemoryHistoryStore()
    let payloadStore = InMemoryPayloadStore()
    let pinned = makeRecord(hash: "pinned", title: "pinned", isPinned: true, retentionExempt: true)
    let normal = makeRecord(hash: "normal", title: "normal")
    _ = try await store.upsert(pinned)
    _ = try await store.upsert(normal)
    try await payloadStore.save(.text("pinned"), for: pinned.id)
    try await payloadStore.save(.text("normal"), for: normal.id)
    let service = HistoryMutationService(store: store, payloadStore: payloadStore)

    let removed = try await service.clearUnpinned()

    XCTAssertEqual(removed, 1)
    XCTAssertEqual(try await store.fetchAll().map(\.title), ["pinned"])
    XCTAssertNotNil(try await payloadStore.loadPayload(for: pinned.id))
    XCTAssertNil(try await payloadStore.loadPayload(for: normal.id))
  }
}

private func makeRecord(
  hash: String,
  title: String,
  isPinned: Bool = false,
  retentionExempt: Bool = false
) -> ClipboardRecord {
  ClipboardRecord(
    id: UUID(),
    contentHash: hash,
    primaryType: .text,
    title: title,
    plainTextPreview: title,
    sourceAppBundleId: nil,
    sourceAppName: nil,
    sourceDeviceHint: .local,
    createdAt: Date(timeIntervalSince1970: 1),
    lastCopiedAt: Date(timeIntervalSince1970: 1),
    copyCount: 1,
    isPinned: isPinned,
    isFavorite: false,
    groupIds: [],
    retentionExempt: retentionExempt,
    metadata: nil,
    pasteboardTypes: ["public.utf8-plain-text"]
  )
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter HistoryMutationServiceTests
```

Expected: fails because `HistoryMutationService` and mutation methods are missing.

- [ ] **Step 3: Add mutation protocol and in-memory implementation**

Modify `Sources/ClipboardCore/Storage/HistoryStore.swift`:

```swift
public protocol HistoryMutationStore: HistoryStore {
  func deleteRecord(id: UUID) async throws -> ClipboardRecord?
  func replaceRecord(_ record: ClipboardRecord) async throws -> ClipboardRecord
  func clearUnpinned() async throws -> [ClipboardRecord]
}
```

Change:

```swift
public actor InMemoryHistoryStore: ImportWritableHistoryStore, HistoryMutationStore {
```

Add methods to `InMemoryHistoryStore`:

```swift
public func deleteRecord(id: UUID) async throws -> ClipboardRecord? {
  guard let record = recordsByHash.values.first(where: { $0.id == id }) else { return nil }
  recordsByHash.removeValue(forKey: record.contentHash)
  return record
}

public func replaceRecord(_ record: ClipboardRecord) async throws -> ClipboardRecord {
  recordsByHash[record.contentHash] = record
  return record
}

public func clearUnpinned() async throws -> [ClipboardRecord] {
  let removed = recordsByHash.values.filter { !$0.isPinned }
  for record in removed {
    recordsByHash.removeValue(forKey: record.contentHash)
  }
  return removed
}
```

- [ ] **Step 4: Add SQLite mutation implementation**

Modify `Sources/ClipboardCore/Storage/SQLite/SQLiteHistoryStore.swift` declaration:

```swift
public actor SQLiteHistoryStore: ImportWritableHistoryStore, RetentionPolicyUpdating, HistoryMutationStore {
```

Add public methods:

```swift
public func deleteRecord(id: UUID) async throws -> ClipboardRecord? {
  guard let record = indexByHash.values.first(where: { $0.id == id }) else { return nil }
  try deleteRecords(ids: [id])
  indexByHash.removeValue(forKey: record.contentHash)
  try connection.exec("PRAGMA incremental_vacuum")
  return record
}

public func replaceRecord(_ record: ClipboardRecord) async throws -> ClipboardRecord {
  try writeRecordForImport(record)
  indexByHash[record.contentHash] = record
  return record
}

public func clearUnpinned() async throws -> [ClipboardRecord] {
  let removed = indexByHash.values.filter { !$0.isPinned }
  try deleteRecords(ids: removed.map(\.id))
  for record in removed {
    indexByHash.removeValue(forKey: record.contentHash)
  }
  try connection.exec("PRAGMA incremental_vacuum")
  return removed
}
```

- [ ] **Step 5: Forward mutations through payload-cleaning wrapper**

Modify declaration:

```swift
public actor PayloadCleaningHistoryStore: ImportWritableHistoryStore, RetentionPolicyUpdating, HistoryMutationStore {
```

Add:

```swift
public func deleteRecord(id: UUID) async throws -> ClipboardRecord? {
  guard let mutating = underlying as? any HistoryMutationStore else { return nil }
  let removed = try await mutating.deleteRecord(id: id)
  if let removed {
    try? await payloadStore.delete(for: removed.id)
  }
  return removed
}

public func replaceRecord(_ record: ClipboardRecord) async throws -> ClipboardRecord {
  guard let mutating = underlying as? any HistoryMutationStore else {
    return try await importRecord(record)
  }
  return try await mutating.replaceRecord(record)
}

public func clearUnpinned() async throws -> [ClipboardRecord] {
  guard let mutating = underlying as? any HistoryMutationStore else { return [] }
  let removed = try await mutating.clearUnpinned()
  for record in removed {
    try? await payloadStore.delete(for: record.id)
  }
  return removed
}
```

- [ ] **Step 6: Implement `HistoryMutationService`**

Create `Sources/ClipboardCore/Storage/HistoryMutationService.swift`:

```swift
import Foundation

public enum HistoryMutationError: Error, Equatable {
  case mutationUnsupported
  case recordNotFound
}

public actor HistoryMutationService {
  private let store: any HistoryStore
  private let payloadStore: any ClipboardPayloadStore

  public init(store: any HistoryStore, payloadStore: any ClipboardPayloadStore) {
    self.store = store
    self.payloadStore = payloadStore
  }

  public func deleteRecord(id: UUID) async throws {
    guard let mutating = store as? any HistoryMutationStore else {
      throw HistoryMutationError.mutationUnsupported
    }
    guard let removed = try await mutating.deleteRecord(id: id) else {
      throw HistoryMutationError.recordNotFound
    }
    try? await payloadStore.delete(for: removed.id)
  }

  public func togglePinned(id: UUID) async throws -> ClipboardRecord {
    guard let mutating = store as? any HistoryMutationStore else {
      throw HistoryMutationError.mutationUnsupported
    }
    guard var record = try await store.fetchAll().first(where: { $0.id == id }) else {
      throw HistoryMutationError.recordNotFound
    }
    record.isPinned.toggle()
    record.retentionExempt = record.isPinned || record.isFavorite
    return try await mutating.replaceRecord(record)
  }

  public func clearUnpinned() async throws -> Int {
    guard let mutating = store as? any HistoryMutationStore else {
      throw HistoryMutationError.mutationUnsupported
    }
    let removed = try await mutating.clearUnpinned()
    for record in removed {
      try? await payloadStore.delete(for: record.id)
    }
    return removed.count
  }

  public func clearAll() async throws -> Int {
    let before = try await store.fetchAll()
    try await store.removeAll()
    for record in before {
      try? await payloadStore.delete(for: record.id)
    }
    return before.count
  }
}
```

- [ ] **Step 7: Extend conformance tests**

Modify `Tests/ClipboardCoreTests/HistoryStoreConformanceTests.swift` to require `HistoryMutationStore` for a new helper:

```swift
func assertHistoryMutationStoreConforms(
  _ makeStore: () async throws -> any HistoryMutationStore,
  file: StaticString = #filePath,
  line: UInt = #line
) async throws {
  let store = try await makeStore()
  let record = makeRecord(hash: "delete", title: "delete", lastCopiedAt: 1)
  _ = try await store.upsert(record)
  let removed = try await store.deleteRecord(id: record.id)
  XCTAssertEqual(removed?.id, record.id, file: file, line: line)
  XCTAssertEqual(try await store.count(), 0, file: file, line: line)
}
```

Add calls from `SQLiteHistoryStoreConformanceTests` and any in-memory conformance test.

- [ ] **Step 8: Run tests and commit**

Run:

```bash
swift test --filter HistoryMutationServiceTests
swift test --filter HistoryStoreConformanceTests
swift test --filter SQLiteHistoryStoreTests
swift test --filter PayloadCleaningHistoryStoreTests
```

Expected: all pass.

Commit:

```bash
git add Sources/ClipboardCore/Storage/HistoryStore.swift \
  Sources/ClipboardCore/Storage/SQLite/SQLiteHistoryStore.swift \
  Sources/ClipboardCore/Storage/PayloadCleaningHistoryStore.swift \
  Sources/ClipboardCore/Storage/HistoryMutationService.swift \
  Tests/ClipboardCoreTests/HistoryMutationServiceTests.swift \
  Tests/ClipboardCoreTests/HistoryStoreConformanceTests.swift \
  Tests/ClipboardCoreTests/SQLiteHistoryStoreTests.swift \
  Tests/ClipboardCoreTests/PayloadCleaningHistoryStoreTests.swift
git commit -m "feat: add history mutation service"
```

---

### Task 4: QuickPanel Management Actions

**Files:**
- Modify: `Sources/ClipboardApp/AppServices.swift`
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelState.swift`
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelKeyCaptureView.swift`
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelView.swift`
- Test: `Tests/ClipboardAppTests/QuickPanelKeyCaptureTests.swift`
- Test: `Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift`

- [ ] **Step 1: Write failing key-capture tests**

Modify `Tests/ClipboardAppTests/QuickPanelKeyCaptureTests.swift`:

```swift
func testOptionDeleteMapsToDeleteSelected() {
  XCTAssertEqual(
    QuickPanelKeyCaptureView.keyboardAction(
      keyCode: UInt16(kVK_Delete),
      modifierFlags: [.option]
    ),
    .deleteSelected
  )
}

func testOptionPMapsToTogglePinned() {
  XCTAssertEqual(
    QuickPanelKeyCaptureView.keyboardAction(
      keyCode: UInt16(kVK_ANSI_P),
      modifierFlags: [.option]
    ),
    .togglePinned
  )
}

func testOptionCommandDeleteMapsToClearUnpinned() {
  XCTAssertEqual(
    QuickPanelKeyCaptureView.keyboardAction(
      keyCode: UInt16(kVK_Delete),
      modifierFlags: [.option, .command]
    ),
    .clearUnpinned
  )
}

func testShiftOptionCommandDeleteMapsToClearAll() {
  XCTAssertEqual(
    QuickPanelKeyCaptureView.keyboardAction(
      keyCode: UInt16(kVK_Delete),
      modifierFlags: [.shift, .option, .command]
    ),
    .clearAll
  )
}
```

- [ ] **Step 2: Run key tests to verify failure**

Run:

```bash
swift test --filter QuickPanelKeyCaptureTests
```

Expected: fails because the new keyboard actions are missing.

- [ ] **Step 3: Add keyboard actions**

Modify `Sources/ClipboardApp/QuickPanel/QuickPanelKeyCaptureView.swift`:

```swift
enum KeyboardAction: Equatable {
  case cancel
  case submit
  case move(Int)
  case focusSearch
  case openSettings
  case deleteSelected
  case togglePinned
  case clearUnpinned
  case clearAll
}
```

Add closures:

```swift
let onDeleteSelected: () -> Void
let onTogglePinned: () -> Void
let onClearUnpinned: () -> Void
let onClearAll: () -> Void
```

Wire them through `Coordinator`, `makeCoordinator`, `updateNSView`, and `handle(_:)`.

Modify `keyboardAction`:

```swift
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
```

- [ ] **Step 4: Write failing state mutation tests**

Modify `Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift` by adding:

```swift
func testDeleteSelectedRefreshesItemsAndFooter() async throws {
  let store = InMemoryHistoryStore()
  let payloadStore = InMemoryPayloadStore()
  let record = makePanelRecord(hash: "delete", title: "delete", type: .text, lastCopiedAt: 1)
  _ = try await store.upsert(record)
  try await payloadStore.save(.text("delete"), for: record.id)
  let mutationService = HistoryMutationService(store: store, payloadStore: payloadStore)
  let state = makeState(store: store, payloadStore: payloadStore, mutationService: mutationService)
  await state.refresh()

  await state.deleteSelected()

  XCTAssertTrue(state.items.isEmpty)
  XCTAssertEqual(state.footerStatus, "Deleted 1 item")
}

func testTogglePinnedUpdatesVisibleItem() async throws {
  let store = InMemoryHistoryStore()
  let payloadStore = InMemoryPayloadStore()
  let record = makePanelRecord(hash: "pin", title: "pin", type: .text, lastCopiedAt: 1)
  _ = try await store.upsert(record)
  let mutationService = HistoryMutationService(store: store, payloadStore: payloadStore)
  let state = makeState(store: store, payloadStore: payloadStore, mutationService: mutationService)
  await state.refresh()

  await state.togglePinned()

  XCTAssertEqual(state.items.first?.isPinned, true)
  XCTAssertEqual(state.footerStatus, "Pinned item")
}
```

Update the existing `makeState` helper in the same test file during Step 5 so these tests compile:

```swift
@MainActor
private func makeState(
  store: InMemoryHistoryStore,
  payloadStore: InMemoryPayloadStore = InMemoryPayloadStore(),
  pasteboard: AppTestPasteboardWriter = AppTestPasteboardWriter(),
  mutationService: HistoryMutationService? = nil
) -> QuickPanelState {
  QuickPanelState(
    viewModel: QuickPanelViewModel(store: store, pageLimit: 20),
    payloadStore: payloadStore,
    pasteController: PasteController(
      pasteboard: pasteboard,
      eventPoster: AppTestPasteEventPoster()
    ),
    mutationService: mutationService ?? HistoryMutationService(store: store, payloadStore: payloadStore)
  )
}
```

- [ ] **Step 5: Add mutation service to QuickPanel state**

Modify `Sources/ClipboardApp/QuickPanel/QuickPanelState.swift` initializer:

```swift
private let mutationService: HistoryMutationService

init(
  viewModel: QuickPanelViewModel,
  payloadStore: any ClipboardPayloadStore,
  pasteController: PasteController,
  mutationService: HistoryMutationService
) {
  self.viewModel = viewModel
  self.payloadStore = payloadStore
  self.pasteController = pasteController
  self.mutationService = mutationService
}
```

Add helper:

```swift
private func currentRecordID() -> UUID? {
  selectedRecordID ?? (items.indices.contains(selectedIndex) ? items[selectedIndex].id : nil)
}
```

Add actions:

```swift
func deleteSelected() async {
  guard let id = currentRecordID() else {
    setUserActionFooterStatus("No clipboard item selected")
    return
  }
  do {
    try await mutationService.deleteRecord(id: id)
    await refresh()
    setUserActionFooterStatus("Deleted 1 item")
  } catch {
    setUserActionFooterStatus("Delete failed: \(error)")
  }
}

func togglePinned() async {
  guard let id = currentRecordID() else {
    setUserActionFooterStatus("No clipboard item selected")
    return
  }
  do {
    let record = try await mutationService.togglePinned(id: id)
    await refresh()
    setUserActionFooterStatus(record.isPinned ? "Pinned item" : "Unpinned item")
  } catch {
    setUserActionFooterStatus("Pin failed: \(error)")
  }
}

func clearUnpinned() async {
  do {
    let removed = try await mutationService.clearUnpinned()
    await refresh()
    setUserActionFooterStatus("Cleared \(removed) unpinned item\(removed == 1 ? "" : "s")")
  } catch {
    setUserActionFooterStatus("Clear failed: \(error)")
  }
}

func clearAll() async {
  do {
    let removed = try await mutationService.clearAll()
    await refresh()
    setUserActionFooterStatus("Cleared \(removed) item\(removed == 1 ? "" : "s")")
  } catch {
    setUserActionFooterStatus("Clear failed: \(error)")
  }
}
```

Modify `Sources/ClipboardApp/AppServices.swift` lazy state:

```swift
lazy var quickPanelState = QuickPanelState(
  viewModel: QuickPanelViewModel(store: store, pageLimit: 50),
  payloadStore: payloadStore,
  pasteController: pasteController,
  mutationService: historyMutationService
)
```

- [ ] **Step 6: Add QuickPanel UI action menu and confirmation**

Modify `Sources/ClipboardApp/QuickPanel/QuickPanelView.swift`:

Add:

```swift
@State private var confirmsClearAll = false
```

Add an action menu to `searchField` before the settings button:

```swift
Menu {
  Button("删除当前项") {
    Task { await state.deleteSelected() }
  }
  Button("置顶 / 取消置顶") {
    Task { await state.togglePinned() }
  }
  Divider()
  Button("清除未置顶项") {
    Task { await state.clearUnpinned() }
  }
  Button("清除全部历史", role: .destructive) {
    confirmsClearAll = true
  }
} label: {
  Image(systemName: "ellipsis.circle")
    .foregroundStyle(.secondary)
}
.menuStyle(.borderlessButton)
.help("历史操作")
```

Add confirmation to root view:

```swift
.confirmationDialog(
  "确定要清除全部剪贴板历史吗？此操作无法撤销。",
  isPresented: $confirmsClearAll,
  titleVisibility: .visible
) {
  Button("清除全部", role: .destructive) {
    Task { await state.clearAll() }
  }
}
```

Pass callbacks to `QuickPanelKeyCaptureView`:

```swift
onDeleteSelected: {
  Task { await state.deleteSelected() }
},
onTogglePinned: {
  Task { await state.togglePinned() }
},
onClearUnpinned: {
  Task { await state.clearUnpinned() }
},
onClearAll: {
  confirmsClearAll = true
}
```

- [ ] **Step 7: Show pinned state in row**

Modify `ContentPreviewView` text branch in `QuickPanelView.swift`:

```swift
if record.isPinned {
  Image(systemName: "pin.fill")
    .font(.caption.weight(.semibold))
    .foregroundStyle(isSelected ? .white.opacity(0.85) : .orange)
}
```

- [ ] **Step 8: Run tests and commit**

Run:

```bash
swift test --filter QuickPanelKeyCaptureTests
swift test --filter QuickPanelStateFilterTests
swift build --product ClipboardApp
```

Expected: all pass and app builds.

Commit:

```bash
git add Sources/ClipboardApp/AppServices.swift \
  Sources/ClipboardApp/QuickPanel/QuickPanelState.swift \
  Sources/ClipboardApp/QuickPanel/QuickPanelKeyCaptureView.swift \
  Sources/ClipboardApp/QuickPanel/QuickPanelView.swift \
  Tests/ClipboardAppTests/QuickPanelKeyCaptureTests.swift \
  Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift
git commit -m "feat: add quick panel history actions"
```

---

### Task 5: Benchmark Probe And Script

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ClipboardBenchmarkProbe/main.swift`
- Create: `Scripts/benchmark-maccy-replacement.sh`
- Create: `Tests/ClipboardCoreTests/BenchmarkComparisonTests.swift`

- [ ] **Step 1: Write benchmark classification tests**

Create `Tests/ClipboardCoreTests/BenchmarkComparisonTests.swift`:

```swift
import XCTest
@testable import ClipboardCore

final class BenchmarkComparisonTests: XCTestCase {
  func testClassifiesBetterWhenClipboardMedianIsTwentyPercentLower() {
    XCTAssertEqual(
      BenchmarkComparison.classify(clipboardMedian: 79, maccyMedian: 100, clipboardP95: 105, maccyP95: 110),
      .better
    )
  }

  func testClassifiesSameWithinTwentyPercent() {
    XCTAssertEqual(
      BenchmarkComparison.classify(clipboardMedian: 90, maccyMedian: 100, clipboardP95: 120, maccyP95: 110),
      .same
    )
  }

  func testClassifiesWorseWhenClipboardMedianIsTwentyPercentHigher() {
    XCTAssertEqual(
      BenchmarkComparison.classify(clipboardMedian: 121, maccyMedian: 100, clipboardP95: 130, maccyP95: 110),
      .worse
    )
  }

  func testClassifiesNotComparableWhenMaccyMetricMissing() {
    XCTAssertEqual(
      BenchmarkComparison.classify(clipboardMedian: 100, maccyMedian: nil, clipboardP95: 120, maccyP95: nil),
      .notComparable
    )
  }
}
```

- [ ] **Step 2: Add comparison types in core**

Create `Sources/ClipboardCore/Benchmark/BenchmarkComparison.swift`:

```swift
import Foundation

public enum BenchmarkComparisonResult: String, Codable, Equatable, Sendable {
  case better
  case same
  case worse
  case notComparable = "not_comparable"
}

public enum BenchmarkComparison {
  public static func classify(
    clipboardMedian: Double,
    maccyMedian: Double?,
    clipboardP95: Double,
    maccyP95: Double?
  ) -> BenchmarkComparisonResult {
    guard let maccyMedian, let maccyP95, maccyMedian > 0 else {
      return .notComparable
    }
    if clipboardMedian < maccyMedian * 0.8, clipboardP95 <= maccyP95 {
      return .better
    }
    if clipboardMedian > maccyMedian * 1.2 {
      return .worse
    }
    return .same
  }
}
```

- [ ] **Step 3: Run classification tests**

Run:

```bash
swift test --filter BenchmarkComparisonTests
```

Expected: pass.

- [ ] **Step 4: Add benchmark product target**

Modify `Package.swift` products:

```swift
.executable(name: "ClipboardBenchmarkProbe", targets: ["ClipboardBenchmarkProbe"])
```

Add target:

```swift
.executableTarget(
  name: "ClipboardBenchmarkProbe",
  dependencies: ["ClipboardCore", "ClipboardPlatform"],
  path: "Sources/ClipboardBenchmarkProbe"
)
```

- [ ] **Step 5: Implement benchmark probe**

Create `Sources/ClipboardBenchmarkProbe/main.swift`:

```swift
import ClipboardCore
import ClipboardPlatform
import Foundation

struct BenchmarkReport: Codable {
  var generatedAt: Date
  var dataset: DatasetSummary
  var metrics: [MetricSummary]
}

struct DatasetSummary: Codable {
  var recordCount: Int
  var payloadBytes: Int64
  var typeCounts: [String: Int]
  var pinnedCount: Int
}

struct MetricSummary: Codable {
  var name: String
  var samplesMs: [Double]
  var medianMs: Double
  var p95Ms: Double
}

@main
struct ClipboardBenchmarkProbe {
  static func main() async throws {
    let outputURL = outputURLFromArguments()
    let bundleID = bundleIDFromArguments()
    let paths = try ApplicationSupportPaths(bundleIdentifier: bundleID)
    let report = try await run(paths: paths)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(report)
    try data.write(to: outputURL, options: .atomic)
    printSummary(report)
  }

  private static func run(paths: ApplicationSupportPaths) async throws -> BenchmarkReport {
    let start = ContinuousClock.now
    let store = try SQLiteHistoryStore(databaseFile: paths.databaseFile)
    let loadMs = milliseconds(from: start, to: ContinuousClock.now)
    let records = try await store.fetchAll()
    let emptyFetch = try await measure(name: "quickpanel_fetch_empty_query_ms") {
      _ = try await store.fetchPage(HistoryQuery(), limit: 50)
    }
    let searches = try await measure(name: "quickpanel_search_ms") {
      _ = try await store.fetchPage(HistoryQuery(text: "http"), limit: 50)
    }
    let payloadBytes = directorySize(paths.payloadsDirectory)
    let dataset = DatasetSummary(
      recordCount: records.count,
      payloadBytes: payloadBytes,
      typeCounts: Dictionary(grouping: records, by: { $0.primaryType.rawValue }).mapValues(\.count),
      pinnedCount: records.filter(\.isPinned).count
    )
    return BenchmarkReport(
      generatedAt: Date(),
      dataset: dataset,
      metrics: [
        MetricSummary(name: "cold_start_store_load_ms", samplesMs: [loadMs], medianMs: loadMs, p95Ms: loadMs),
        emptyFetch,
        searches
      ]
    )
  }

  private static func measure(name: String, operation: () async throws -> Void) async throws -> MetricSummary {
    var samples: [Double] = []
    for _ in 0..<10 {
      let start = ContinuousClock.now
      try await operation()
      samples.append(milliseconds(from: start, to: ContinuousClock.now))
    }
    let sorted = samples.sorted()
    let median = sorted[sorted.count / 2]
    let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))]
    return MetricSummary(name: name, samplesMs: samples, medianMs: median, p95Ms: p95)
  }

  private static func milliseconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Double {
    let duration = start.duration(to: end)
    return Double(duration.components.seconds) * 1000 +
      Double(duration.components.attoseconds) / 1_000_000_000_000_000
  }

  private static func directorySize(_ url: URL) -> Int64 {
    guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
      return 0
    }
    var total: Int64 = 0
    for case let fileURL as URL in enumerator {
      let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
      total += Int64(values?.fileSize ?? 0)
    }
    return total
  }

  private static func outputURLFromArguments() -> URL {
    if let index = CommandLine.arguments.firstIndex(of: "--output"), CommandLine.arguments.indices.contains(index + 1) {
      return URL(fileURLWithPath: CommandLine.arguments[index + 1])
    }
    return URL(fileURLWithPath: "clipboard-benchmark-report.json")
  }

  private static func bundleIDFromArguments() -> String {
    if let index = CommandLine.arguments.firstIndex(of: "--bundle-id"), CommandLine.arguments.indices.contains(index + 1) {
      return CommandLine.arguments[index + 1]
    }
    return "com.local.clipboard-manager"
  }

  private static func printSummary(_ report: BenchmarkReport) {
    print("Clipboard benchmark")
    print("records: \(report.dataset.recordCount)")
    print("payloadBytes: \(report.dataset.payloadBytes)")
    for metric in report.metrics {
      print("\(metric.name): median=\(String(format: "%.2f", metric.medianMs))ms p95=\(String(format: "%.2f", metric.p95Ms))ms")
    }
  }
}
```

- [ ] **Step 6: Add script wrapper**

Create `Scripts/benchmark-maccy-replacement.sh`:

```bash
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

timestamp="$(date +%Y%m%d-%H%M%S)"
report_dir=".build/benchmark-reports"
mkdir -p "$report_dir"

bundle_id="${BUNDLE_IDENTIFIER:-com.local.clipboard-manager}"
json_report="$report_dir/${timestamp}-clipboard-benchmark.json"

swift run ClipboardBenchmarkProbe --bundle-id "$bundle_id" --output "$json_report"

echo "JSON report: $json_report"
echo "Maccy comparison: not_comparable until a matching Maccy sampling command is added or manually recorded."
```

Run:

```bash
chmod +x Scripts/benchmark-maccy-replacement.sh
```

- [ ] **Step 7: Run benchmark**

Run:

```bash
Scripts/benchmark-maccy-replacement.sh
```

Expected:

```text
Clipboard benchmark
records: a non-negative integer matching the current imported dataset
payloadBytes: a non-negative integer
cold_start_store_load_ms: median=a numeric millisecond value p95=a numeric millisecond value
JSON report: .build/benchmark-reports/YYYYMMDD-HHMMSS-clipboard-benchmark.json
Maccy comparison: not_comparable until a matching Maccy sampling command is added or manually recorded.
```

- [ ] **Step 8: Commit**

```bash
git add Package.swift \
  Sources/ClipboardCore/Benchmark/BenchmarkComparison.swift \
  Sources/ClipboardBenchmarkProbe/main.swift \
  Scripts/benchmark-maccy-replacement.sh \
  Tests/ClipboardCoreTests/BenchmarkComparisonTests.swift
git commit -m "feat: add clipboard benchmark probe"
```

---

### Task 6: Acceptance Checklist And Full Verification

**Files:**
- Modify: `docs/manual-acceptance-checklist.md`

- [ ] **Step 1: Update manual acceptance checklist**

Add this section to `docs/manual-acceptance-checklist.md`:

```markdown
## Maccy Replacement Privacy And Performance

- [ ] 暂停采集后复制 3 条内容，历史数量不增长
- [ ] 恢复采集后复制 1 条内容，历史数量增长
- [ ] 触发“忽略下一次复制”后，第一条复制不入库，第二条复制正常入库
- [ ] 开启忽略 Universal Clipboard 后，带 `com.apple.is-remote-clipboard` 的内容不入库
- [ ] 添加 ignored pasteboard type 后，对应 type 的 capture 不入库
- [ ] 添加 ignored app bundle id 后，对应来源 App 的 capture 不入库
- [ ] QuickPanel `Option+Delete` 删除当前项，列表刷新且 payload 清理
- [ ] QuickPanel `Option+P` 置顶/取消置顶当前项
- [ ] QuickPanel `Option+Command+Delete` 清除未置顶项，置顶项保留
- [ ] QuickPanel `Shift+Option+Command+Delete` 弹出确认，确认后清除全部历史
- [ ] `Scripts/benchmark-maccy-replacement.sh` 生成 JSON 报告和可读摘要
- [ ] 报告中的 Maccy 对比项只使用 `better` / `same` / `worse` / `not_comparable` 表述
```

- [ ] **Step 2: Run focused tests**

Run:

```bash
swift test --filter CaptureControlServiceTests
swift test --filter HistoryMutationServiceTests
swift test --filter QuickPanelKeyCaptureTests
swift test --filter BenchmarkComparisonTests
```

Expected: all pass.

- [ ] **Step 3: Run full verification**

Run:

```bash
swift test
Scripts/verify.sh
CODE_SIGN_IDENTITY=- Scripts/build-app-bundle.sh
Scripts/benchmark-maccy-replacement.sh
git diff --check
```

Expected:

- `swift test` passes.
- `Scripts/verify.sh` passes.
- App bundle builds at `.build/app-bundles/release/ClipboardApp.app`.
- Benchmark report is written under `.build/benchmark-reports/`.
- `git diff --check` produces no output.

- [ ] **Step 4: Commit docs and final verification evidence**

```bash
git add docs/manual-acceptance-checklist.md
git commit -m "docs: add maccy replacement acceptance checks"
```

---

## Plan Self-Review

- Spec coverage:
  - Capture pause/resume, ignore-next-copy, and privacy policy runtime decisions are covered by Tasks 1 and 2.
  - QuickPanel delete, pin/unpin, clear-unpinned, and clear-all are covered by Tasks 3 and 4.
  - Benchmark JSON and readable summary are covered by Task 5.
  - Manual acceptance and full verification are covered by Task 6.
- Placeholder scan:
  - No TBD, TODO, or undefined future-only sections are used.
  - Each code-writing step names exact files and includes concrete code or command snippets.
- Type consistency:
  - `CaptureControlService`, `HistoryMutationService`, `HistoryMutationStore`, `ClipboardBenchmarkProbe`, and `BenchmarkComparison` are introduced before downstream tasks use them.
  - QuickPanel keyboard action names match the methods added to `QuickPanelState`.
