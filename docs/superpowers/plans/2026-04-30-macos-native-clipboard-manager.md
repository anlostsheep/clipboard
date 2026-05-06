# macOS Native Clipboard Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first working slice of a native macOS clipboard manager: permission onboarding, clipboard capture normalization, local history storage, large-text protection, observable paste transactions, and a minimal QuickPanel view model.

**Architecture:** Create a new Swift package at `macos-clipboard-manager/` with a testable `ClipboardCore` library and a minimal `ClipboardApp` executable. Keep AppKit/SwiftUI adapters thin and place policy, ingestion, storage, large-text, and paste transaction behavior behind protocols so the same core can later move into an Xcode app target.

**Tech Stack:** Swift 5.10+, Swift Package Manager, XCTest, SwiftUI, AppKit, ApplicationServices, Foundation CryptoKit-compatible SHA256 via CryptoKit.

**Spec:** [2026-04-30-macos-native-clipboard-manager-design.md](../specs/2026-04-30-macos-native-clipboard-manager-design.md)

---

## Scope Check

The approved design covers multiple subsystems: QuickPanel, LibraryWindow, importers, release packaging, compatibility testing, and diagnostics. This plan intentionally implements the first working slice only:

- Included: Swift package scaffold, core models, privacy policy, in-memory history store, ingestion, large-text policy, paste transaction, pasteboard monitor adapter, QuickPanel view model, minimal SwiftUI/AppKit shell, focused tests.
- Excluded from this plan: Maccy/Clipaste importers, full LibraryWindow, persistent SwiftData/SQLite store, thumbnail cache, release DMG/Cask, dual architecture packaging. These require separate implementation plans after the first slice passes tests.

---

## File Structure

- Create: `macos-clipboard-manager/Package.swift`
  - Defines `ClipboardCore`, `ClipboardApp`, and `ClipboardCoreTests`.
- Create: `macos-clipboard-manager/Sources/ClipboardCore/Models/ClipboardTypes.swift`
  - Owns content type enums, source hints, large content classes, paste transaction states, and failure reasons.
- Create: `macos-clipboard-manager/Sources/ClipboardCore/Models/ClipboardRecord.swift`
  - Owns `ClipboardRecord`, `ClipboardCapture`, `ClipboardPayload`, `LargeTextMetadata`, and lightweight record construction.
- Create: `macos-clipboard-manager/Sources/ClipboardCore/Privacy/PrivacyPolicy.swift`
  - Owns privacy templates, ignored pasteboard types, ignored app rules, and Universal Clipboard record policy.
- Create: `macos-clipboard-manager/Sources/ClipboardCore/Storage/HistoryStore.swift`
  - Defines `HistoryStore` protocol and `InMemoryHistoryStore` for first-slice behavior.
- Create: `macos-clipboard-manager/Sources/ClipboardCore/Ingest/LargeTextPolicy.swift`
  - Owns text-size thresholds, excerpts, line estimates, and blob storage decisions.
- Create: `macos-clipboard-manager/Sources/ClipboardCore/Ingest/ClipboardIngestService.swift`
  - Converts captures to records, computes hashes, applies large-text policy, and upserts store.
- Create: `macos-clipboard-manager/Sources/ClipboardCore/Paste/PasteInterfaces.swift`
  - Defines pasteboard writing and paste event posting protocols.
- Create: `macos-clipboard-manager/Sources/ClipboardCore/Paste/PasteController.swift`
  - Owns observable paste transaction execution and failure classification.
- Create: `macos-clipboard-manager/Sources/ClipboardCore/Monitor/ClipboardMonitor.swift`
  - Owns protocol-driven pasteboard polling and capture emission without direct UI or store writes.
- Create: `macos-clipboard-manager/Sources/ClipboardCore/UI/QuickPanelViewModel.swift`
  - Owns lightweight query, selection, and paste intent behavior.
- Create: `macos-clipboard-manager/Sources/ClipboardApp/ClipboardApp.swift`
  - Minimal SwiftUI app shell that wires services and shows a compact panel window.
- Create: `macos-clipboard-manager/Sources/ClipboardApp/SystemPasteboardClient.swift`
  - AppKit bridge for `NSPasteboard` reads/writes and `CGEvent` paste posting.
- Create: `macos-clipboard-manager/Tests/ClipboardCoreTests/*.swift`
  - Focused unit tests for each core boundary.

---

### Task 1: Swift Package Scaffold

**Files:**
- Create: `macos-clipboard-manager/Package.swift`
- Create: `macos-clipboard-manager/Sources/ClipboardCore/ClipboardCore.swift`
- Create: `macos-clipboard-manager/Sources/ClipboardApp/ClipboardApp.swift`
- Create: `macos-clipboard-manager/Tests/ClipboardCoreTests/ClipboardCoreSmokeTests.swift`

- [ ] **Step 1: Create the package file**

Create `macos-clipboard-manager/Package.swift` with:

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "macos-clipboard-manager",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "ClipboardCore", targets: ["ClipboardCore"]),
    .executable(name: "ClipboardApp", targets: ["ClipboardApp"])
  ],
  targets: [
    .target(
      name: "ClipboardCore",
      dependencies: [],
      path: "Sources/ClipboardCore"
    ),
    .executableTarget(
      name: "ClipboardApp",
      dependencies: ["ClipboardCore"],
      path: "Sources/ClipboardApp"
    ),
    .testTarget(
      name: "ClipboardCoreTests",
      dependencies: ["ClipboardCore"],
      path: "Tests/ClipboardCoreTests"
    )
  ]
)
```

- [ ] **Step 2: Create the bootstrap core file**

Create `macos-clipboard-manager/Sources/ClipboardCore/ClipboardCore.swift` with:

```swift
public enum ClipboardCoreBootstrap {
  public static let version = "0.1.0"
}
```

- [ ] **Step 3: Create the minimal app shell**

Create `macos-clipboard-manager/Sources/ClipboardApp/ClipboardApp.swift` with:

```swift
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
```

- [ ] **Step 4: Create the smoke test**

Create `macos-clipboard-manager/Tests/ClipboardCoreTests/ClipboardCoreSmokeTests.swift` with:

```swift
import XCTest
@testable import ClipboardCore

final class ClipboardCoreSmokeTests: XCTestCase {
  func testBootstrapVersionIsStable() {
    XCTAssertEqual(ClipboardCoreBootstrap.version, "0.1.0")
  }
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
cd macos-clipboard-manager
swift test
```

Expected:

```text
Test Suite 'All tests' passed
```

- [ ] **Step 6: Commit**

```bash
git add macos-clipboard-manager
git commit -m "feat: scaffold native clipboard manager package"
```

---

### Task 2: Core Models

**Files:**
- Create: `macos-clipboard-manager/Sources/ClipboardCore/Models/ClipboardTypes.swift`
- Create: `macos-clipboard-manager/Sources/ClipboardCore/Models/ClipboardRecord.swift`
- Create: `macos-clipboard-manager/Tests/ClipboardCoreTests/ClipboardRecordTests.swift`

- [ ] **Step 1: Write model tests**

Create `macos-clipboard-manager/Tests/ClipboardCoreTests/ClipboardRecordTests.swift` with:

```swift
import XCTest
@testable import ClipboardCore

final class ClipboardRecordTests: XCTestCase {
  func testRecordKeepsLargeTextMetadataOutOfTitle() {
    let metadata = LargeTextMetadata(
      byteSize: 10_485_760,
      lineCountEstimate: 42_000,
      contentClass: .json,
      previewExcerpt: "{\"items\": [",
      tailExcerpt: "]}"
    )

    let record = ClipboardRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
      contentHash: "abc123",
      primaryType: .text,
      title: "Large JSON",
      plainTextPreview: "{\"items\": [",
      sourceAppBundleId: "com.apple.Terminal",
      sourceAppName: "Terminal",
      sourceDeviceHint: .local,
      createdAt: Date(timeIntervalSince1970: 1),
      lastCopiedAt: Date(timeIntervalSince1970: 1),
      copyCount: 1,
      isPinned: false,
      isFavorite: false,
      groupIds: [],
      retentionExempt: false,
      metadata: metadata,
      pasteboardTypes: ["public.utf8-plain-text"]
    )

    XCTAssertEqual(record.title, "Large JSON")
    XCTAssertTrue(record.isLargeContent)
    XCTAssertEqual(record.metadata?.contentClass, .json)
  }

  func testCaptureMarksUniversalClipboard() {
    let capture = ClipboardCapture(
      payload: .text("hello"),
      pasteboardTypes: ["public.utf8-plain-text", "com.apple.is-remote-clipboard"],
      sourceAppBundleId: nil,
      sourceAppName: nil,
      capturedAt: Date(timeIntervalSince1970: 2)
    )

    XCTAssertTrue(capture.isUniversalClipboard)
  }
}
```

- [ ] **Step 2: Run model tests and verify failure**

Run:

```bash
cd macos-clipboard-manager
swift test --filter ClipboardRecordTests
```

Expected: build fails because `ClipboardRecord`, `ClipboardCapture`, and related types are not defined.

- [ ] **Step 3: Add shared type definitions**

Create `macos-clipboard-manager/Sources/ClipboardCore/Models/ClipboardTypes.swift` with:

```swift
import Foundation

public enum ClipboardContentType: String, Codable, Equatable, Sendable {
  case text
  case richText
  case link
  case image
  case file
}

public enum ClipboardSourceDeviceHint: String, Codable, Equatable, Sendable {
  case local
  case universalClipboard
  case imported
}

public enum LargeTextContentClass: String, Codable, Equatable, Sendable {
  case json
  case yaml
  case log
  case plain
  case code
}

public enum BlobStoragePolicy: String, Codable, Equatable, Sendable {
  case full
  case summaryOnly
  case skipped
}

public enum IndexingState: String, Codable, Equatable, Sendable {
  case notIndexed
  case excerptIndexed
  case fullTextQueued
  case fullTextIndexed
  case failed
}

public enum PasteFailureReason: String, Codable, Equatable, Sendable {
  case recordMissing
  case blobMissing
  case fileUnavailable
  case formatUnsupported
  case pasteboardWriteFailed
  case accessibilityRevoked
  case targetAppFocusLost
  case pasteEventFailed
  case targetAppRejectedPaste
}
```

- [ ] **Step 4: Add record and capture models**

Create `macos-clipboard-manager/Sources/ClipboardCore/Models/ClipboardRecord.swift` with:

```swift
import Foundation

public enum ClipboardPayload: Equatable, Sendable {
  case text(String)
  case richText(plainText: String, rtfData: Data)
  case image(data: Data, uti: String)
  case fileURLs([URL])
}

public struct LargeTextMetadata: Codable, Equatable, Sendable {
  public let byteSize: Int
  public let lineCountEstimate: Int
  public let contentClass: LargeTextContentClass
  public let previewExcerpt: String
  public let tailExcerpt: String
  public let blobStoragePolicy: BlobStoragePolicy
  public let indexingState: IndexingState

  public init(
    byteSize: Int,
    lineCountEstimate: Int,
    contentClass: LargeTextContentClass,
    previewExcerpt: String,
    tailExcerpt: String,
    blobStoragePolicy: BlobStoragePolicy = .summaryOnly,
    indexingState: IndexingState = .excerptIndexed
  ) {
    self.byteSize = byteSize
    self.lineCountEstimate = lineCountEstimate
    self.contentClass = contentClass
    self.previewExcerpt = previewExcerpt
    self.tailExcerpt = tailExcerpt
    self.blobStoragePolicy = blobStoragePolicy
    self.indexingState = indexingState
  }
}

public struct ClipboardCapture: Equatable, Sendable {
  public let payload: ClipboardPayload
  public let pasteboardTypes: Set<String>
  public let sourceAppBundleId: String?
  public let sourceAppName: String?
  public let capturedAt: Date

  public init(
    payload: ClipboardPayload,
    pasteboardTypes: Set<String>,
    sourceAppBundleId: String?,
    sourceAppName: String?,
    capturedAt: Date
  ) {
    self.payload = payload
    self.pasteboardTypes = pasteboardTypes
    self.sourceAppBundleId = sourceAppBundleId
    self.sourceAppName = sourceAppName
    self.capturedAt = capturedAt
  }

  public var isUniversalClipboard: Bool {
    pasteboardTypes.contains("com.apple.is-remote-clipboard")
  }
}

public struct ClipboardRecord: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public var contentHash: String
  public var primaryType: ClipboardContentType
  public var title: String
  public var plainTextPreview: String?
  public var sourceAppBundleId: String?
  public var sourceAppName: String?
  public var sourceDeviceHint: ClipboardSourceDeviceHint
  public var createdAt: Date
  public var lastCopiedAt: Date
  public var copyCount: Int
  public var isPinned: Bool
  public var isFavorite: Bool
  public var groupIds: [String]
  public var retentionExempt: Bool
  public var metadata: LargeTextMetadata?
  public var pasteboardTypes: Set<String>

  public init(
    id: UUID,
    contentHash: String,
    primaryType: ClipboardContentType,
    title: String,
    plainTextPreview: String?,
    sourceAppBundleId: String?,
    sourceAppName: String?,
    sourceDeviceHint: ClipboardSourceDeviceHint,
    createdAt: Date,
    lastCopiedAt: Date,
    copyCount: Int,
    isPinned: Bool,
    isFavorite: Bool,
    groupIds: [String],
    retentionExempt: Bool,
    metadata: LargeTextMetadata?,
    pasteboardTypes: Set<String>
  ) {
    self.id = id
    self.contentHash = contentHash
    self.primaryType = primaryType
    self.title = title
    self.plainTextPreview = plainTextPreview
    self.sourceAppBundleId = sourceAppBundleId
    self.sourceAppName = sourceAppName
    self.sourceDeviceHint = sourceDeviceHint
    self.createdAt = createdAt
    self.lastCopiedAt = lastCopiedAt
    self.copyCount = copyCount
    self.isPinned = isPinned
    self.isFavorite = isFavorite
    self.groupIds = groupIds
    self.retentionExempt = retentionExempt
    self.metadata = metadata
    self.pasteboardTypes = pasteboardTypes
  }

  public var isLargeContent: Bool {
    metadata != nil
  }
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
cd macos-clipboard-manager
swift test --filter ClipboardRecordTests
```

Expected:

```text
Test Suite 'ClipboardRecordTests' passed
```

- [ ] **Step 6: Commit**

```bash
git add macos-clipboard-manager/Sources/ClipboardCore/Models macos-clipboard-manager/Tests/ClipboardCoreTests/ClipboardRecordTests.swift
git commit -m "feat: define clipboard core models"
```

---

### Task 3: Privacy Policy Service

**Files:**
- Create: `macos-clipboard-manager/Sources/ClipboardCore/Privacy/PrivacyPolicy.swift`
- Create: `macos-clipboard-manager/Tests/ClipboardCoreTests/PrivacyPolicyTests.swift`

- [ ] **Step 1: Write privacy tests**

Create `macos-clipboard-manager/Tests/ClipboardCoreTests/PrivacyPolicyTests.swift` with:

```swift
import XCTest
@testable import ClipboardCore

final class PrivacyPolicyTests: XCTestCase {
  func testStandardPolicyIgnoresConcealedAndTransientTypes() {
    let policy = PrivacyPolicy.standard
    XCTAssertTrue(policy.shouldIgnore(pasteboardTypes: ["org.nspasteboard.ConcealedType"], sourceBundleId: nil))
    XCTAssertTrue(policy.shouldIgnore(pasteboardTypes: ["org.nspasteboard.TransientType"], sourceBundleId: nil))
    XCTAssertFalse(policy.shouldIgnore(pasteboardTypes: ["public.utf8-plain-text"], sourceBundleId: nil))
  }

  func testUniversalClipboardCanBeDisabled() {
    var policy = PrivacyPolicy.standard
    policy.recordsUniversalClipboard = false
    XCTAssertTrue(policy.shouldIgnore(pasteboardTypes: ["public.utf8-plain-text", "com.apple.is-remote-clipboard"], sourceBundleId: nil))
  }

  func testIgnoredAppsAreNotLimitedToApplicationsFolder() {
    var policy = PrivacyPolicy.standard
    policy.ignoredAppBundleIds.insert("com.example.ToolOutsideApplications")
    XCTAssertTrue(policy.shouldIgnore(pasteboardTypes: ["public.utf8-plain-text"], sourceBundleId: "com.example.ToolOutsideApplications"))
  }
}
```

- [ ] **Step 2: Run privacy tests and verify failure**

Run:

```bash
cd macos-clipboard-manager
swift test --filter PrivacyPolicyTests
```

Expected: build fails because `PrivacyPolicy` is not defined.

- [ ] **Step 3: Implement privacy policy**

Create `macos-clipboard-manager/Sources/ClipboardCore/Privacy/PrivacyPolicy.swift` with:

```swift
import Foundation

public struct PrivacyPolicy: Equatable, Sendable {
  public var ignoredPasteboardTypes: Set<String>
  public var ignoredTransientTypes: Set<String>
  public var ignoredAppBundleIds: Set<String>
  public var recordsUniversalClipboard: Bool

  public init(
    ignoredPasteboardTypes: Set<String>,
    ignoredTransientTypes: Set<String>,
    ignoredAppBundleIds: Set<String>,
    recordsUniversalClipboard: Bool
  ) {
    self.ignoredPasteboardTypes = ignoredPasteboardTypes
    self.ignoredTransientTypes = ignoredTransientTypes
    self.ignoredAppBundleIds = ignoredAppBundleIds
    self.recordsUniversalClipboard = recordsUniversalClipboard
  }

  public static let standard = PrivacyPolicy(
    ignoredPasteboardTypes: [
      "org.nspasteboard.ConcealedType",
      "org.nspasteboard.TransientType",
      "org.nspasteboard.AutoGeneratedType",
      "com.agilebits.onepassword",
      "BUA8C4S2C.com.1password"
    ],
    ignoredTransientTypes: [
      "org.chromium.web-custom-data"
    ],
    ignoredAppBundleIds: [],
    recordsUniversalClipboard: true
  )

  public static let conservative = PrivacyPolicy(
    ignoredPasteboardTypes: standard.ignoredPasteboardTypes,
    ignoredTransientTypes: standard.ignoredTransientTypes,
    ignoredAppBundleIds: [
      "com.1password.1password",
      "com.agilebits.onepassword7",
      "com.apple.Terminal",
      "com.googlecode.iterm2"
    ],
    recordsUniversalClipboard: false
  )

  public func shouldIgnore(pasteboardTypes: Set<String>, sourceBundleId: String?) -> Bool {
    if pasteboardTypes.contains("com.apple.is-remote-clipboard") && !recordsUniversalClipboard {
      return true
    }

    if let sourceBundleId, ignoredAppBundleIds.contains(sourceBundleId) {
      return true
    }

    if !pasteboardTypes.isDisjoint(with: ignoredPasteboardTypes) {
      return true
    }

    if !pasteboardTypes.isDisjoint(with: ignoredTransientTypes) {
      return true
    }

    return false
  }
}
```

- [ ] **Step 4: Run privacy tests**

Run:

```bash
cd macos-clipboard-manager
swift test --filter PrivacyPolicyTests
```

Expected:

```text
Test Suite 'PrivacyPolicyTests' passed
```

- [ ] **Step 5: Commit**

```bash
git add macos-clipboard-manager/Sources/ClipboardCore/Privacy macos-clipboard-manager/Tests/ClipboardCoreTests/PrivacyPolicyTests.swift
git commit -m "feat: add privacy policy filtering"
```

---

### Task 4: Large Text Policy and Ingestion

**Files:**
- Create: `macos-clipboard-manager/Sources/ClipboardCore/Ingest/LargeTextPolicy.swift`
- Create: `macos-clipboard-manager/Sources/ClipboardCore/Storage/HistoryStore.swift`
- Create: `macos-clipboard-manager/Sources/ClipboardCore/Ingest/ClipboardIngestService.swift`
- Create: `macos-clipboard-manager/Tests/ClipboardCoreTests/LargeTextPolicyTests.swift`
- Create: `macos-clipboard-manager/Tests/ClipboardCoreTests/ClipboardIngestServiceTests.swift`

- [ ] **Step 1: Write large text policy tests**

Create `macos-clipboard-manager/Tests/ClipboardCoreTests/LargeTextPolicyTests.swift` with:

```swift
import XCTest
@testable import ClipboardCore

final class LargeTextPolicyTests: XCTestCase {
  func testExtremeTextUsesSummaryOnlyPolicy() {
    let policy = LargeTextPolicy(largeTextBytes: 64, extremeTextBytes: 128, excerptLimit: 32)
    let text = String(repeating: "line: value\n", count: 20)
    let result = policy.classify(text: text)

    XCTAssertTrue(result.isLarge)
    XCTAssertEqual(result.metadata?.blobStoragePolicy, .summaryOnly)
    XCTAssertEqual(result.metadata?.indexingState, .excerptIndexed)
    XCTAssertLessThanOrEqual(result.metadata?.previewExcerpt.count ?? 0, 32)
    XCTAssertLessThanOrEqual(result.metadata?.tailExcerpt.count ?? 0, 32)
  }

  func testJsonContentClassIsDetectedFromPrefix() {
    let text = "{\"items\":[1,2,3]}"
    let result = LargeTextPolicy.default.classify(text: text)

    XCTAssertEqual(result.contentClass, .json)
  }
}
```

- [ ] **Step 2: Write ingestion tests**

Create `macos-clipboard-manager/Tests/ClipboardCoreTests/ClipboardIngestServiceTests.swift` with:

```swift
import XCTest
@testable import ClipboardCore

final class ClipboardIngestServiceTests: XCTestCase {
  func testIngestSkipsIgnoredCapture() async throws {
    let store = InMemoryHistoryStore()
    var policy = PrivacyPolicy.standard
    policy.ignoredAppBundleIds.insert("com.secret.App")
    let service = ClipboardIngestService(store: store, privacyPolicy: policy, largeTextPolicy: .default)

    let capture = ClipboardCapture(
      payload: .text("secret"),
      pasteboardTypes: ["public.utf8-plain-text"],
      sourceAppBundleId: "com.secret.App",
      sourceAppName: "Secret",
      capturedAt: Date(timeIntervalSince1970: 10)
    )

    let record = try await service.ingest(capture)

    XCTAssertNil(record)
    XCTAssertEqual(await store.fetchAll().count, 0)
  }

  func testIngestCreatesLargeJsonRecordWithoutFullTitle() async throws {
    let store = InMemoryHistoryStore()
    let service = ClipboardIngestService(store: store, privacyPolicy: .standard, largeTextPolicy: .default)
    let json = "{" + String(repeating: "\"key\":\"value\",", count: 10_000) + "\"end\":true}"

    let capture = ClipboardCapture(
      payload: .text(json),
      pasteboardTypes: ["public.utf8-plain-text"],
      sourceAppBundleId: "com.apple.Terminal",
      sourceAppName: "Terminal",
      capturedAt: Date(timeIntervalSince1970: 11)
    )

    let record = try XCTUnwrap(await service.ingest(capture))

    XCTAssertTrue(record.isLargeContent)
    XCTAssertLessThanOrEqual(record.title.count, 120)
    XCTAssertEqual(await store.fetchAll().count, 1)
  }
}
```

- [ ] **Step 3: Run tests and verify failure**

Run:

```bash
cd macos-clipboard-manager
swift test --filter LargeTextPolicyTests
swift test --filter ClipboardIngestServiceTests
```

Expected: build fails because `LargeTextPolicy`, `InMemoryHistoryStore`, and `ClipboardIngestService` are not defined.

- [ ] **Step 4: Implement large text policy**

Create `macos-clipboard-manager/Sources/ClipboardCore/Ingest/LargeTextPolicy.swift` with:

```swift
import Foundation

public struct LargeTextClassification: Equatable, Sendable {
  public let isLarge: Bool
  public let contentClass: LargeTextContentClass
  public let metadata: LargeTextMetadata?
}

public struct LargeTextPolicy: Equatable, Sendable {
  public let largeTextBytes: Int
  public let extremeTextBytes: Int
  public let excerptLimit: Int

  public static let `default` = LargeTextPolicy(
    largeTextBytes: 64 * 1024,
    extremeTextBytes: 100 * 1024 * 1024,
    excerptLimit: 2_048
  )

  public func classify(text: String) -> LargeTextClassification {
    let bytes = text.utf8.count
    let contentClass = detectContentClass(text)

    guard bytes >= largeTextBytes else {
      return LargeTextClassification(isLarge: false, contentClass: contentClass, metadata: nil)
    }

    let preview = String(text.prefix(excerptLimit))
    let tail = String(text.suffix(excerptLimit))
    let lineEstimate = max(1, text.reduce(0) { $1 == "\n" ? $0 + 1 : $0 })
    let policy: BlobStoragePolicy = bytes >= extremeTextBytes ? .summaryOnly : .full

    let metadata = LargeTextMetadata(
      byteSize: bytes,
      lineCountEstimate: lineEstimate,
      contentClass: contentClass,
      previewExcerpt: preview,
      tailExcerpt: tail,
      blobStoragePolicy: policy,
      indexingState: .excerptIndexed
    )

    return LargeTextClassification(isLarge: true, contentClass: contentClass, metadata: metadata)
  }

  private func detectContentClass(_ text: String) -> LargeTextContentClass {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
      return .json
    }
    if trimmed.hasPrefix("---") || trimmed.contains(":\n") || trimmed.contains(": ") {
      return .yaml
    }
    if trimmed.contains("\n") && (trimmed.contains("ERROR") || trimmed.contains("INFO") || trimmed.contains("WARN")) {
      return .log
    }
    return .plain
  }
}
```

- [ ] **Step 5: Implement in-memory store**

Create `macos-clipboard-manager/Sources/ClipboardCore/Storage/HistoryStore.swift` with:

```swift
import Foundation

public protocol HistoryStore: Sendable {
  func upsert(_ record: ClipboardRecord) async throws -> ClipboardRecord
  func fetchAll() async -> [ClipboardRecord]
  func fetchPage(query: String, limit: Int) async -> [ClipboardRecord]
}

public actor InMemoryHistoryStore: HistoryStore {
  private var recordsByHash: [String: ClipboardRecord] = [:]

  public init() {}

  public func upsert(_ record: ClipboardRecord) async throws -> ClipboardRecord {
    if var existing = recordsByHash[record.contentHash] {
      existing.copyCount += 1
      existing.lastCopiedAt = record.lastCopiedAt
      recordsByHash[record.contentHash] = existing
      return existing
    }

    recordsByHash[record.contentHash] = record
    return record
  }

  public func fetchAll() async -> [ClipboardRecord] {
    recordsByHash.values.sorted { $0.lastCopiedAt > $1.lastCopiedAt }
  }

  public func fetchPage(query: String, limit: Int) async -> [ClipboardRecord] {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let all = await fetchAll()
    let filtered = normalized.isEmpty ? all : all.filter { record in
      record.title.lowercased().contains(normalized) ||
      (record.plainTextPreview?.lowercased().contains(normalized) ?? false) ||
      (record.sourceAppName?.lowercased().contains(normalized) ?? false)
    }
    return Array(filtered.prefix(limit))
  }
}
```

- [ ] **Step 6: Implement ingestion service**

Create `macos-clipboard-manager/Sources/ClipboardCore/Ingest/ClipboardIngestService.swift` with:

```swift
import CryptoKit
import Foundation

public enum ClipboardIngestError: Error, Equatable {
  case unsupportedPayload
}

public struct ClipboardIngestService: Sendable {
  private let store: any HistoryStore
  private let privacyPolicy: PrivacyPolicy
  private let largeTextPolicy: LargeTextPolicy

  public init(store: any HistoryStore, privacyPolicy: PrivacyPolicy, largeTextPolicy: LargeTextPolicy) {
    self.store = store
    self.privacyPolicy = privacyPolicy
    self.largeTextPolicy = largeTextPolicy
  }

  public func ingest(_ capture: ClipboardCapture) async throws -> ClipboardRecord? {
    guard !privacyPolicy.shouldIgnore(
      pasteboardTypes: capture.pasteboardTypes,
      sourceBundleId: capture.sourceAppBundleId
    ) else {
      return nil
    }

    let record = try makeRecord(from: capture)
    return try await store.upsert(record)
  }

  private func makeRecord(from capture: ClipboardCapture) throws -> ClipboardRecord {
    switch capture.payload {
    case let .text(text):
      return makeTextRecord(text: text, capture: capture)
    case let .richText(plainText, _):
      return makeTextRecord(text: plainText, capture: capture, primaryType: .richText)
    case let .image(data, _):
      return ClipboardRecord(
        id: UUID(),
        contentHash: hash(data),
        primaryType: .image,
        title: "Image \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))",
        plainTextPreview: nil,
        sourceAppBundleId: capture.sourceAppBundleId,
        sourceAppName: capture.sourceAppName,
        sourceDeviceHint: capture.isUniversalClipboard ? .universalClipboard : .local,
        createdAt: capture.capturedAt,
        lastCopiedAt: capture.capturedAt,
        copyCount: 1,
        isPinned: false,
        isFavorite: false,
        groupIds: [],
        retentionExempt: false,
        metadata: nil,
        pasteboardTypes: capture.pasteboardTypes
      )
    case let .fileURLs(urls):
      let joined = urls.map(\.absoluteString).joined(separator: "\n")
      return makeTextRecord(text: joined, capture: capture, primaryType: .file)
    }
  }

  private func makeTextRecord(
    text: String,
    capture: ClipboardCapture,
    primaryType: ClipboardContentType = .text
  ) -> ClipboardRecord {
    let classification = largeTextPolicy.classify(text: text)
    let preview = classification.metadata?.previewExcerpt ?? String(text.prefix(2_048))
    let titleSource = preview.split(separator: "\n").first.map(String.init) ?? "Text"
    let title = String(titleSource.prefix(120))

    return ClipboardRecord(
      id: UUID(),
      contentHash: hash(Data(text.utf8)),
      primaryType: primaryType,
      title: title.isEmpty ? "Text" : title,
      plainTextPreview: preview,
      sourceAppBundleId: capture.sourceAppBundleId,
      sourceAppName: capture.sourceAppName,
      sourceDeviceHint: capture.isUniversalClipboard ? .universalClipboard : .local,
      createdAt: capture.capturedAt,
      lastCopiedAt: capture.capturedAt,
      copyCount: 1,
      isPinned: false,
      isFavorite: false,
      groupIds: [],
      retentionExempt: false,
      metadata: classification.metadata,
      pasteboardTypes: capture.pasteboardTypes
    )
  }

  private func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
```

- [ ] **Step 7: Run ingestion and large text tests**

Run:

```bash
cd macos-clipboard-manager
swift test --filter LargeTextPolicyTests
swift test --filter ClipboardIngestServiceTests
```

Expected:

```text
Test Suite 'LargeTextPolicyTests' passed
Test Suite 'ClipboardIngestServiceTests' passed
```

- [ ] **Step 8: Commit**

```bash
git add macos-clipboard-manager/Sources/ClipboardCore/Ingest macos-clipboard-manager/Sources/ClipboardCore/Storage macos-clipboard-manager/Tests/ClipboardCoreTests/LargeTextPolicyTests.swift macos-clipboard-manager/Tests/ClipboardCoreTests/ClipboardIngestServiceTests.swift
git commit -m "feat: ingest clipboard captures with large text protection"
```

---

### Task 5: Observable Paste Transactions

**Files:**
- Create: `macos-clipboard-manager/Sources/ClipboardCore/Paste/PasteInterfaces.swift`
- Create: `macos-clipboard-manager/Sources/ClipboardCore/Paste/PasteController.swift`
- Create: `macos-clipboard-manager/Tests/ClipboardCoreTests/PasteControllerTests.swift`

- [ ] **Step 1: Write paste controller tests**

Create `macos-clipboard-manager/Tests/ClipboardCoreTests/PasteControllerTests.swift` with:

```swift
import XCTest
@testable import ClipboardCore

final class PasteControllerTests: XCTestCase {
  func testPasteFailsWhenAccessibilityIsMissing() async {
    let pasteboard = FakePasteboardWriter(writeResult: true)
    let poster = FakePasteEventPoster(accessibilityTrusted: false, postResult: true)
    let controller = PasteController(pasteboard: pasteboard, eventPoster: poster)
    let record = Self.record(text: "hello")

    let transaction = await controller.paste(record: record, payload: .text("hello"), autoPaste: true)

    XCTAssertEqual(transaction.state, .failed(.accessibilityRevoked))
    XCTAssertEqual(pasteboard.writtenPayloads.count, 0)
  }

  func testCopyOnlyWritesPasteboardWithoutPostingPasteEvent() async {
    let pasteboard = FakePasteboardWriter(writeResult: true)
    let poster = FakePasteEventPoster(accessibilityTrusted: true, postResult: true)
    let controller = PasteController(pasteboard: pasteboard, eventPoster: poster)
    let record = Self.record(text: "hello")

    let transaction = await controller.paste(record: record, payload: .text("hello"), autoPaste: false)

    XCTAssertEqual(transaction.state, .completed)
    XCTAssertEqual(pasteboard.writtenPayloads.count, 1)
    XCTAssertEqual(poster.postCount, 0)
  }

  func testPasteboardWriteFailureIsReported() async {
    let pasteboard = FakePasteboardWriter(writeResult: false)
    let poster = FakePasteEventPoster(accessibilityTrusted: true, postResult: true)
    let controller = PasteController(pasteboard: pasteboard, eventPoster: poster)
    let record = Self.record(text: "hello")

    let transaction = await controller.paste(record: record, payload: .text("hello"), autoPaste: true)

    XCTAssertEqual(transaction.state, .failed(.pasteboardWriteFailed))
    XCTAssertEqual(poster.postCount, 0)
  }

  private static func record(text: String) -> ClipboardRecord {
    ClipboardRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
      contentHash: "hash",
      primaryType: .text,
      title: text,
      plainTextPreview: text,
      sourceAppBundleId: nil,
      sourceAppName: nil,
      sourceDeviceHint: .local,
      createdAt: Date(timeIntervalSince1970: 1),
      lastCopiedAt: Date(timeIntervalSince1970: 1),
      copyCount: 1,
      isPinned: false,
      isFavorite: false,
      groupIds: [],
      retentionExempt: false,
      metadata: nil,
      pasteboardTypes: ["public.utf8-plain-text"]
    )
  }
}

private final class FakePasteboardWriter: PasteboardWriting {
  let writeResult: Bool
  private(set) var writtenPayloads: [ClipboardPayload] = []

  init(writeResult: Bool) {
    self.writeResult = writeResult
  }

  func write(payload: ClipboardPayload, marker: String) async -> Bool {
    writtenPayloads.append(payload)
    return writeResult
  }

  func containsMarker(_ marker: String) async -> Bool {
    writeResult
  }
}

private final class FakePasteEventPoster: PasteEventPosting {
  let accessibilityTrusted: Bool
  let postResult: Bool
  private(set) var postCount = 0

  init(accessibilityTrusted: Bool, postResult: Bool) {
    self.accessibilityTrusted = accessibilityTrusted
    self.postResult = postResult
  }

  func isAccessibilityTrusted() -> Bool {
    accessibilityTrusted
  }

  func postCommandV() async -> Bool {
    postCount += 1
    return postResult
  }
}
```

- [ ] **Step 2: Run paste tests and verify failure**

Run:

```bash
cd macos-clipboard-manager
swift test --filter PasteControllerTests
```

Expected: build fails because paste protocols and `PasteController` are not defined.

- [ ] **Step 3: Implement paste interfaces**

Create `macos-clipboard-manager/Sources/ClipboardCore/Paste/PasteInterfaces.swift` with:

```swift
import Foundation

public protocol PasteboardWriting: AnyObject, Sendable {
  func write(payload: ClipboardPayload, marker: String) async -> Bool
  func containsMarker(_ marker: String) async -> Bool
}

public protocol PasteEventPosting: AnyObject, Sendable {
  func isAccessibilityTrusted() -> Bool
  func postCommandV() async -> Bool
}

public enum PasteTransactionState: Equatable, Sendable {
  case prepared
  case pasteboardWritten
  case pasteEventPosted
  case completed
  case failed(PasteFailureReason)
}

public struct PasteTransaction: Equatable, Sendable {
  public let id: UUID
  public let recordId: UUID
  public let startedAt: Date
  public var completedAt: Date?
  public var state: PasteTransactionState

  public init(id: UUID, recordId: UUID, startedAt: Date, completedAt: Date?, state: PasteTransactionState) {
    self.id = id
    self.recordId = recordId
    self.startedAt = startedAt
    self.completedAt = completedAt
    self.state = state
  }
}
```

- [ ] **Step 4: Implement paste controller**

Create `macos-clipboard-manager/Sources/ClipboardCore/Paste/PasteController.swift` with:

```swift
import Foundation

public struct PasteController: Sendable {
  private let pasteboard: PasteboardWriting
  private let eventPoster: PasteEventPosting
  private let markerPrefix = "com.local.clipboard-manager.transaction"

  public init(pasteboard: PasteboardWriting, eventPoster: PasteEventPosting) {
    self.pasteboard = pasteboard
    self.eventPoster = eventPoster
  }

  public func paste(record: ClipboardRecord, payload: ClipboardPayload, autoPaste: Bool) async -> PasteTransaction {
    var transaction = PasteTransaction(
      id: UUID(),
      recordId: record.id,
      startedAt: Date(),
      completedAt: nil,
      state: .prepared
    )

    if autoPaste && !eventPoster.isAccessibilityTrusted() {
      transaction.state = .failed(.accessibilityRevoked)
      transaction.completedAt = Date()
      return transaction
    }

    let marker = "\(markerPrefix).\(transaction.id.uuidString)"
    guard await pasteboard.write(payload: payload, marker: marker) else {
      transaction.state = .failed(.pasteboardWriteFailed)
      transaction.completedAt = Date()
      return transaction
    }

    guard await pasteboard.containsMarker(marker) else {
      transaction.state = .failed(.pasteboardWriteFailed)
      transaction.completedAt = Date()
      return transaction
    }

    transaction.state = .pasteboardWritten

    guard autoPaste else {
      transaction.state = .completed
      transaction.completedAt = Date()
      return transaction
    }

    guard await eventPoster.postCommandV() else {
      transaction.state = .failed(.pasteEventFailed)
      transaction.completedAt = Date()
      return transaction
    }

    transaction.state = .completed
    transaction.completedAt = Date()
    return transaction
  }
}
```

- [ ] **Step 5: Run paste tests**

Run:

```bash
cd macos-clipboard-manager
swift test --filter PasteControllerTests
```

Expected:

```text
Test Suite 'PasteControllerTests' passed
```

- [ ] **Step 6: Commit**

```bash
git add macos-clipboard-manager/Sources/ClipboardCore/Paste macos-clipboard-manager/Tests/ClipboardCoreTests/PasteControllerTests.swift
git commit -m "feat: add observable paste transactions"
```

---

### Task 6: Clipboard Monitor Adapter

**Files:**
- Create: `macos-clipboard-manager/Sources/ClipboardCore/Monitor/ClipboardMonitor.swift`
- Create: `macos-clipboard-manager/Tests/ClipboardCoreTests/ClipboardMonitorTests.swift`

- [ ] **Step 1: Write monitor tests**

Create `macos-clipboard-manager/Tests/ClipboardCoreTests/ClipboardMonitorTests.swift` with:

```swift
import XCTest
@testable import ClipboardCore

final class ClipboardMonitorTests: XCTestCase {
  func testPollReturnsNilWhenChangeCountIsUnchanged() async {
    let reader = FakePasteboardReader(changeCount: 1, capture: nil)
    let monitor = ClipboardMonitor(reader: reader)

    _ = await monitor.poll()
    let second = await monitor.poll()

    XCTAssertNil(second)
  }

  func testPollReturnsCaptureWhenChangeCountChanges() async {
    let capture = ClipboardCapture(
      payload: .text("hello"),
      pasteboardTypes: ["public.utf8-plain-text"],
      sourceAppBundleId: nil,
      sourceAppName: nil,
      capturedAt: Date(timeIntervalSince1970: 1)
    )
    let reader = FakePasteboardReader(changeCount: 1, capture: capture)
    let monitor = ClipboardMonitor(reader: reader)

    let first = await monitor.poll()

    XCTAssertEqual(first, capture)
  }
}

private final class FakePasteboardReader: PasteboardReading {
  var changeCount: Int
  let capture: ClipboardCapture?

  init(changeCount: Int, capture: ClipboardCapture?) {
    self.changeCount = changeCount
    self.capture = capture
  }

  func currentChangeCount() async -> Int {
    changeCount
  }

  func readCurrentCapture() async -> ClipboardCapture? {
    capture
  }
}
```

- [ ] **Step 2: Run monitor tests and verify failure**

Run:

```bash
cd macos-clipboard-manager
swift test --filter ClipboardMonitorTests
```

Expected: build fails because `ClipboardMonitor` and `PasteboardReading` are not defined.

- [ ] **Step 3: Implement monitor**

Create `macos-clipboard-manager/Sources/ClipboardCore/Monitor/ClipboardMonitor.swift` with:

```swift
import Foundation

public protocol PasteboardReading: AnyObject, Sendable {
  func currentChangeCount() async -> Int
  func readCurrentCapture() async -> ClipboardCapture?
}

public actor ClipboardMonitor {
  private let reader: PasteboardReading
  private var lastChangeCount: Int?

  public init(reader: PasteboardReading) {
    self.reader = reader
  }

  public func poll() async -> ClipboardCapture? {
    let current = await reader.currentChangeCount()
    defer { lastChangeCount = current }

    guard lastChangeCount != current else {
      return nil
    }

    return await reader.readCurrentCapture()
  }
}
```

- [ ] **Step 4: Run monitor tests**

Run:

```bash
cd macos-clipboard-manager
swift test --filter ClipboardMonitorTests
```

Expected:

```text
Test Suite 'ClipboardMonitorTests' passed
```

- [ ] **Step 5: Commit**

```bash
git add macos-clipboard-manager/Sources/ClipboardCore/Monitor macos-clipboard-manager/Tests/ClipboardCoreTests/ClipboardMonitorTests.swift
git commit -m "feat: add protocol driven clipboard monitor"
```

---

### Task 7: QuickPanel View Model

**Files:**
- Create: `macos-clipboard-manager/Sources/ClipboardCore/UI/QuickPanelViewModel.swift`
- Create: `macos-clipboard-manager/Tests/ClipboardCoreTests/QuickPanelViewModelTests.swift`

- [ ] **Step 1: Write QuickPanel view model tests**

Create `macos-clipboard-manager/Tests/ClipboardCoreTests/QuickPanelViewModelTests.swift` with:

```swift
import XCTest
@testable import ClipboardCore

final class QuickPanelViewModelTests: XCTestCase {
  func testRefreshLoadsLightweightRecords() async throws {
    let store = InMemoryHistoryStore()
    let record = ClipboardRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
      contentHash: "hash",
      primaryType: .text,
      title: "hello",
      plainTextPreview: "hello",
      sourceAppBundleId: nil,
      sourceAppName: "Terminal",
      sourceDeviceHint: .local,
      createdAt: Date(timeIntervalSince1970: 1),
      lastCopiedAt: Date(timeIntervalSince1970: 1),
      copyCount: 1,
      isPinned: false,
      isFavorite: false,
      groupIds: [],
      retentionExempt: false,
      metadata: nil,
      pasteboardTypes: ["public.utf8-plain-text"]
    )
    _ = try await store.upsert(record)

    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)
    await viewModel.refresh(query: "hel")

    XCTAssertEqual(await viewModel.items.map(\.title), ["hello"])
  }
}
```

- [ ] **Step 2: Run QuickPanel tests and verify failure**

Run:

```bash
cd macos-clipboard-manager
swift test --filter QuickPanelViewModelTests
```

Expected: build fails because `QuickPanelViewModel` is not defined.

- [ ] **Step 3: Implement QuickPanel view model**

Create `macos-clipboard-manager/Sources/ClipboardCore/UI/QuickPanelViewModel.swift` with:

```swift
import Foundation

public actor QuickPanelViewModel {
  private let store: any HistoryStore
  private let pageLimit: Int
  public private(set) var items: [ClipboardRecord] = []
  public private(set) var selectedIndex: Int = 0

  public init(store: any HistoryStore, pageLimit: Int = 50) {
    self.store = store
    self.pageLimit = pageLimit
  }

  public func refresh(query: String) async {
    items = await store.fetchPage(query: query, limit: pageLimit)
    selectedIndex = items.isEmpty ? 0 : min(selectedIndex, items.count - 1)
  }

  public func moveSelection(delta: Int) {
    guard !items.isEmpty else {
      selectedIndex = 0
      return
    }
    selectedIndex = max(0, min(items.count - 1, selectedIndex + delta))
  }

  public func selectedRecord() -> ClipboardRecord? {
    guard items.indices.contains(selectedIndex) else {
      return nil
    }
    return items[selectedIndex]
  }
}
```

- [ ] **Step 4: Run QuickPanel tests**

Run:

```bash
cd macos-clipboard-manager
swift test --filter QuickPanelViewModelTests
```

Expected:

```text
Test Suite 'QuickPanelViewModelTests' passed
```

- [ ] **Step 5: Commit**

```bash
git add macos-clipboard-manager/Sources/ClipboardCore/UI macos-clipboard-manager/Tests/ClipboardCoreTests/QuickPanelViewModelTests.swift
git commit -m "feat: add lightweight quick panel view model"
```

---

### Task 8: AppKit System Adapters

**Files:**
- Create: `macos-clipboard-manager/Sources/ClipboardApp/SystemPasteboardClient.swift`
- Modify: `macos-clipboard-manager/Sources/ClipboardApp/ClipboardApp.swift`

- [ ] **Step 1: Create system pasteboard adapter**

Create `macos-clipboard-manager/Sources/ClipboardApp/SystemPasteboardClient.swift` with:

```swift
import AppKit
import ApplicationServices
import ClipboardCore
import Foundation

final class SystemPasteboardClient: PasteboardReading, PasteboardWriting, PasteEventPosting {
  private let pasteboard = NSPasteboard.general

  func currentChangeCount() async -> Int {
    pasteboard.changeCount
  }

  func readCurrentCapture() async -> ClipboardCapture? {
    guard let item = pasteboard.pasteboardItems?.first else {
      return nil
    }

    let types = Set(item.types.map(\.rawValue))
    let app = NSWorkspace.shared.frontmostApplication
    let now = Date()

    if let string = item.string(forType: .string), !string.isEmpty {
      return ClipboardCapture(
        payload: .text(string),
        pasteboardTypes: types,
        sourceAppBundleId: app?.bundleIdentifier,
        sourceAppName: app?.localizedName,
        capturedAt: now
      )
    }

    if let data = item.data(forType: .png) {
      return ClipboardCapture(
        payload: .image(data: data, uti: NSPasteboard.PasteboardType.png.rawValue),
        pasteboardTypes: types,
        sourceAppBundleId: app?.bundleIdentifier,
        sourceAppName: app?.localizedName,
        capturedAt: now
      )
    }

    if let fileString = item.string(forType: .fileURL),
       let url = URL(string: fileString) {
      return ClipboardCapture(
        payload: .fileURLs([url]),
        pasteboardTypes: types,
        sourceAppBundleId: app?.bundleIdentifier,
        sourceAppName: app?.localizedName,
        capturedAt: now
      )
    }

    return nil
  }

  func write(payload: ClipboardPayload, marker: String) async -> Bool {
    pasteboard.clearContents()
    pasteboard.setString(marker, forType: NSPasteboard.PasteboardType("com.local.clipboard-manager.marker"))

    switch payload {
    case let .text(text):
      return pasteboard.setString(text, forType: .string)
    case let .richText(plainText, rtfData):
      let wroteText = pasteboard.setString(plainText, forType: .string)
      let wroteRTF = pasteboard.setData(rtfData, forType: .rtf)
      return wroteText || wroteRTF
    case let .image(data, uti):
      return pasteboard.setData(data, forType: NSPasteboard.PasteboardType(uti))
    case let .fileURLs(urls):
      return pasteboard.writeObjects(urls as [NSURL])
    }
  }

  func containsMarker(_ marker: String) async -> Bool {
    pasteboard.string(forType: NSPasteboard.PasteboardType("com.local.clipboard-manager.marker")) == marker
  }

  func isAccessibilityTrusted() -> Bool {
    AXIsProcessTrustedWithOptions(nil)
  }

  func postCommandV() async -> Bool {
    guard isAccessibilityTrusted() else {
      return false
    }

    let source = CGEventSource(stateID: .combinedSessionState)
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
    keyDown?.flags = .maskCommand
    keyUp?.flags = .maskCommand
    keyDown?.post(tap: .cgSessionEventTap)
    keyUp?.post(tap: .cgSessionEventTap)
    return keyDown != nil && keyUp != nil
  }
}
```

- [ ] **Step 2: Replace app shell with service wiring**

Modify `macos-clipboard-manager/Sources/ClipboardApp/ClipboardApp.swift` to:

```swift
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
```

- [ ] **Step 3: Build app target**

Run:

```bash
cd macos-clipboard-manager
swift build
```

Expected:

```text
Build complete!
```

- [ ] **Step 4: Commit**

```bash
git add macos-clipboard-manager/Sources/ClipboardApp
git commit -m "feat: add appkit pasteboard adapters"
```

---

### Task 9: Verification Harness

**Files:**
- Create: `macos-clipboard-manager/Scripts/verify.sh`
- Create: `macos-clipboard-manager/Tests/ClipboardCoreTests/PerformanceGuardTests.swift`

- [ ] **Step 1: Add performance guard tests**

Create `macos-clipboard-manager/Tests/ClipboardCoreTests/PerformanceGuardTests.swift` with:

```swift
import XCTest
@testable import ClipboardCore

final class PerformanceGuardTests: XCTestCase {
  func testTenMegabyteJsonClassificationDoesNotExposeFullPreview() {
    let json = "{" + String(repeating: "\"message\":\"hello\",", count: 600_000) + "\"end\":true}"

    measure {
      let result = LargeTextPolicy.default.classify(text: json)
      XCTAssertTrue(result.isLarge)
      XCTAssertLessThanOrEqual(result.metadata?.previewExcerpt.count ?? 0, 2_048)
      XCTAssertLessThanOrEqual(result.metadata?.tailExcerpt.count ?? 0, 2_048)
    }
  }
}
```

- [ ] **Step 2: Add verification script**

Create `macos-clipboard-manager/Scripts/verify.sh` with:

```bash
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift test
swift build
```

Run:

```bash
chmod +x macos-clipboard-manager/Scripts/verify.sh
```

- [ ] **Step 3: Run full verification**

Run:

```bash
macos-clipboard-manager/Scripts/verify.sh
```

Expected:

```text
Test Suite 'All tests' passed
Build complete!
```

- [ ] **Step 4: Commit**

```bash
git add macos-clipboard-manager/Tests/ClipboardCoreTests/PerformanceGuardTests.swift macos-clipboard-manager/Scripts/verify.sh
git commit -m "test: add clipboard manager verification harness"
```

---

### Task 10: First-Slice Acceptance Review

**Files:**
- Read: `docs/superpowers/specs/2026-04-30-macos-native-clipboard-manager-design.md`
- Read: `macos-clipboard-manager/Sources/ClipboardCore`
- Read: `macos-clipboard-manager/Tests/ClipboardCoreTests`

- [ ] **Step 1: Run full verification**

Run:

```bash
macos-clipboard-manager/Scripts/verify.sh
```

Expected:

```text
Test Suite 'All tests' passed
Build complete!
```

- [ ] **Step 2: Confirm first-slice coverage**

Run:

```bash
rg -n "ClipboardMonitor|ClipboardIngestService|PrivacyPolicy|LargeTextPolicy|PasteController|PasteTransaction|QuickPanelViewModel" macos-clipboard-manager/Sources macos-clipboard-manager/Tests
```

Expected: output contains matches for each listed component in both source or tests.

- [ ] **Step 3: Confirm no full-text rendering path exists in QuickPanel view model**

Run:

```bash
rg -n "Text\\(|plainTextPreview|metadata|previewExcerpt" macos-clipboard-manager/Sources/ClipboardCore/UI macos-clipboard-manager/Sources/ClipboardApp
```

Expected: `QuickPanelViewModel` does not render SwiftUI `Text`; app shell may contain simple static `Text` labels only.

- [ ] **Step 4: Commit review notes if any source changes were needed**

If verification required code edits, commit them:

```bash
git add macos-clipboard-manager
git commit -m "fix: close first clipboard manager slice gaps"
```

If no edits were needed, do not create an empty commit.

---

## Follow-Up Plans

Create separate plans after this first slice is verified:

1. `2026-05-01-macos-clipboard-library-window.md`
   - SwiftData/SQLite persistent store, LibraryWindow, groups, settings, diagnostics.
2. `2026-05-01-macos-clipboard-importers.md`
   - Maccy importer, Clipaste importer, import report, schema version handling.
3. `2026-05-01-macos-clipboard-release.md`
   - Intel package, Apple Silicon package, update manifests, Homebrew Cask split.
4. `2026-05-01-macos-clipboard-compatibility.md`
   - macOS 14 Intel, macOS 15 Intel, macOS 26 Apple Silicon test matrix and performance harness.
