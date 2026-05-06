# macOS 原生剪贴板管理器实现计划（中文版）

> **给执行代理的要求：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 按任务逐步执行本计划。所有步骤使用复选框（`- [ ]`）跟踪状态。

**目标：** 构建 macOS 原生剪贴板管理器的第一阶段可运行切片：权限引导、剪贴板采集归一化、本地历史存储、大文本保护、可观测粘贴事务，以及最小 QuickPanel ViewModel。

**架构：** 在 `macos-clipboard-manager/` 下创建新的 Swift package，包含可测试的 `ClipboardCore` library 和最小 `ClipboardApp` executable。AppKit/SwiftUI 适配层保持轻薄，策略、接入、存储、大文本和粘贴事务行为都放在协议边界之后，便于后续把同一套 core 迁移到 Xcode app target。

**技术栈：** Swift 5.10+、Swift Package Manager、XCTest、SwiftUI、AppKit、ApplicationServices、Foundation，以及通过 CryptoKit 使用兼容 SHA256。

**对应 Spec：** [2026-04-30-macos-native-clipboard-manager-design.md](../specs/2026-04-30-macos-native-clipboard-manager-design.md)

---

## 范围检查

已确认的设计覆盖多个子系统：QuickPanel、LibraryWindow、导入器、发行打包、兼容性测试和诊断。本计划只实现第一阶段可运行切片：

- 包含：Swift package 工程骨架、核心模型、隐私策略、内存历史存储、剪贴板接入、大文本策略、粘贴事务、剪贴板监听适配器、QuickPanel ViewModel、最小 SwiftUI/AppKit shell、聚焦测试。
- 不包含：Maccy/Clipaste 导入器、完整 LibraryWindow、持久化 SwiftData/SQLite store、缩略图缓存、DMG/Cask 发行、Intel/Apple Silicon 双架构分包。这些需要在第一阶段切片测试通过后单独制定实现计划。

---

## 文件结构

- 创建： `macos-clipboard-manager/Package.swift`
  - 定义 `ClipboardCore`、`ClipboardApp` 和 `ClipboardCoreTests`。
- 创建： `macos-clipboard-manager/Sources/ClipboardCore/Models/ClipboardTypes.swift`
  - 负责内容类型枚举、来源提示、大内容分类、粘贴事务状态和失败原因。
- 创建： `macos-clipboard-manager/Sources/ClipboardCore/Models/ClipboardRecord.swift`
  - 负责 `ClipboardRecord`、`ClipboardCapture`、`ClipboardPayload`、`LargeTextMetadata` 和轻量记录构造。
- 创建： `macos-clipboard-manager/Sources/ClipboardCore/Privacy/PrivacyPolicy.swift`
  - 负责隐私模板、忽略的 pasteboard type、忽略 app 规则，以及 Universal Clipboard 记录策略。
- 创建： `macos-clipboard-manager/Sources/ClipboardCore/Storage/HistoryStore.swift`
  - 定义 `HistoryStore` 协议和第一阶段使用的 `InMemoryHistoryStore`。
- 创建： `macos-clipboard-manager/Sources/ClipboardCore/Ingest/LargeTextPolicy.swift`
  - 负责文本大小阈值、摘要截取、行数估算和 blob 存储决策。
- 创建： `macos-clipboard-manager/Sources/ClipboardCore/Ingest/ClipboardIngestService.swift`
  - 将 capture 转换为 record，计算 hash，应用大文本策略，并写入/更新 store。
- 创建： `macos-clipboard-manager/Sources/ClipboardCore/Paste/PasteInterfaces.swift`
  - 定义 pasteboard 写入和粘贴事件发送协议。
- 创建： `macos-clipboard-manager/Sources/ClipboardCore/Paste/PasteController.swift`
  - 负责可观测粘贴事务执行和失败分类。
- 创建： `macos-clipboard-manager/Sources/ClipboardCore/Monitor/ClipboardMonitor.swift`
  - 负责基于协议的 pasteboard 轮询和 capture 输出，不直接写 UI 或 store。
- 创建： `macos-clipboard-manager/Sources/ClipboardCore/UI/QuickPanelViewModel.swift`
  - 负责轻量查询、选中项和粘贴意图行为。
- 创建： `macos-clipboard-manager/Sources/ClipboardApp/ClipboardApp.swift`
  - 最小 SwiftUI app shell，用于组装服务并显示紧凑面板窗口。
- 创建： `macos-clipboard-manager/Sources/ClipboardApp/SystemPasteboardClient.swift`
  - `NSPasteboard` 读写和 `CGEvent` 粘贴事件发送的 AppKit 桥接。
- 创建： `macos-clipboard-manager/Tests/ClipboardCoreTests/*.swift`
  - 针对每个 core 边界的聚焦单元测试。

---

### 任务 1：Swift Package 工程骨架

**涉及文件：**
- 创建： `macos-clipboard-manager/Package.swift`
- 创建： `macos-clipboard-manager/Sources/ClipboardCore/ClipboardCore.swift`
- 创建： `macos-clipboard-manager/Sources/ClipboardApp/ClipboardApp.swift`
- 创建： `macos-clipboard-manager/Tests/ClipboardCoreTests/ClipboardCoreSmokeTests.swift`

- [x] **步骤 1：创建 package 文件**

创建 `macos-clipboard-manager/Package.swift`，内容为：

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

- [x] **步骤 2：创建 core 启动文件**

创建 `macos-clipboard-manager/Sources/ClipboardCore/ClipboardCore.swift`，内容为：

```swift
public enum ClipboardCoreBootstrap {
  public static let version = "0.1.0"
}
```

- [x] **步骤 3：创建最小 app shell**

创建 `macos-clipboard-manager/Sources/ClipboardApp/ClipboardApp.swift`，内容为：

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

- [x] **步骤 4：创建 smoke test**

创建 `macos-clipboard-manager/Tests/ClipboardCoreTests/ClipboardCoreSmokeTests.swift`，内容为：

```swift
import XCTest
@testable import ClipboardCore

final class ClipboardCoreSmokeTests: XCTestCase {
  func testBootstrapVersionIsStable() {
    XCTAssertEqual(ClipboardCoreBootstrap.version, "0.1.0")
  }
}
```

- [x] **步骤 5：运行测试**

运行：

```bash
cd macos-clipboard-manager
swift test
```

预期：

```text
Test Suite 'All tests' passed
```

- [x] **步骤 6：提交**

```bash
git add macos-clipboard-manager
git commit -m "feat: scaffold native clipboard manager package"
```

---

### 任务 2：核心模型

**涉及文件：**
- 创建： `macos-clipboard-manager/Sources/ClipboardCore/Models/ClipboardTypes.swift`
- 创建： `macos-clipboard-manager/Sources/ClipboardCore/Models/ClipboardRecord.swift`
- 创建： `macos-clipboard-manager/Tests/ClipboardCoreTests/ClipboardRecordTests.swift`

- [x] **步骤 1：编写模型测试**

创建 `macos-clipboard-manager/Tests/ClipboardCoreTests/ClipboardRecordTests.swift`，内容为：

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

- [x] **步骤 2：运行模型测试并确认失败**

运行：

```bash
cd macos-clipboard-manager
swift test --filter ClipboardRecordTests
```

预期：构建失败，因为 `ClipboardRecord`、`ClipboardCapture` 和相关类型尚未定义。

- [x] **步骤 3：添加共享类型定义**

创建 `macos-clipboard-manager/Sources/ClipboardCore/Models/ClipboardTypes.swift`，内容为：

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

- [x] **步骤 4：添加 record 和 capture 模型**

创建 `macos-clipboard-manager/Sources/ClipboardCore/Models/ClipboardRecord.swift`，内容为：

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

- [x] **步骤 5：运行测试**

运行：

```bash
cd macos-clipboard-manager
swift test --filter ClipboardRecordTests
```

预期：

```text
Test Suite 'ClipboardRecordTests' passed
```

- [x] **步骤 6：提交**

```bash
git add macos-clipboard-manager/Sources/ClipboardCore/Models macos-clipboard-manager/Tests/ClipboardCoreTests/ClipboardRecordTests.swift
git commit -m "feat: define clipboard core models"
```

---

### 任务 3：隐私策略服务

**涉及文件：**
- 创建： `macos-clipboard-manager/Sources/ClipboardCore/Privacy/PrivacyPolicy.swift`
- 创建： `macos-clipboard-manager/Tests/ClipboardCoreTests/PrivacyPolicyTests.swift`

- [x] **步骤 1：编写隐私策略测试**

创建 `macos-clipboard-manager/Tests/ClipboardCoreTests/PrivacyPolicyTests.swift`，内容为：

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

- [x] **步骤 2：运行隐私策略测试并确认失败**

运行：

```bash
cd macos-clipboard-manager
swift test --filter PrivacyPolicyTests
```

预期：构建失败，因为 `PrivacyPolicy` 尚未定义。

- [x] **步骤 3：实现隐私策略**

创建 `macos-clipboard-manager/Sources/ClipboardCore/Privacy/PrivacyPolicy.swift`，内容为：

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

- [x] **步骤 4：运行隐私策略测试**

运行：

```bash
cd macos-clipboard-manager
swift test --filter PrivacyPolicyTests
```

预期：

```text
Test Suite 'PrivacyPolicyTests' passed
```

- [x] **步骤 5：提交**

```bash
git add macos-clipboard-manager/Sources/ClipboardCore/Privacy macos-clipboard-manager/Tests/ClipboardCoreTests/PrivacyPolicyTests.swift
git commit -m "feat: add privacy policy filtering"
```

---

### 任务 4：大文本策略与剪贴板接入

> 执行修正：code quality review 后，实际实现把 content class 检测与行数估算改为有界扫描，文本 hash 改为完整 UTF-8 的连续存储/分块处理，并补充 `plainTextPreview` 截断与 metadata 断言，避免 QuickPanel 路径暴露大文本全文。

**涉及文件：**
- 创建： `macos-clipboard-manager/Sources/ClipboardCore/Ingest/LargeTextPolicy.swift`
- 创建： `macos-clipboard-manager/Sources/ClipboardCore/Storage/HistoryStore.swift`
- 创建： `macos-clipboard-manager/Sources/ClipboardCore/Ingest/ClipboardIngestService.swift`
- 创建： `macos-clipboard-manager/Tests/ClipboardCoreTests/LargeTextPolicyTests.swift`
- 创建： `macos-clipboard-manager/Tests/ClipboardCoreTests/ClipboardIngestServiceTests.swift`

- [x] **步骤 1：编写大文本策略测试**

创建 `macos-clipboard-manager/Tests/ClipboardCoreTests/LargeTextPolicyTests.swift`，内容为：

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

- [x] **步骤 2：编写接入测试**

创建 `macos-clipboard-manager/Tests/ClipboardCoreTests/ClipboardIngestServiceTests.swift`，内容为：

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

- [x] **步骤 3：运行测试并确认失败**

运行：

```bash
cd macos-clipboard-manager
swift test --filter LargeTextPolicyTests
swift test --filter ClipboardIngestServiceTests
```

预期：构建失败，因为 `LargeTextPolicy`、`InMemoryHistoryStore` 和 `ClipboardIngestService` 尚未定义。

- [x] **步骤 4：实现大文本策略**

创建 `macos-clipboard-manager/Sources/ClipboardCore/Ingest/LargeTextPolicy.swift`，内容为：

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

- [x] **步骤 5：实现内存 store**

创建 `macos-clipboard-manager/Sources/ClipboardCore/Storage/HistoryStore.swift`，内容为：

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

- [x] **步骤 6：实现接入服务**

创建 `macos-clipboard-manager/Sources/ClipboardCore/Ingest/ClipboardIngestService.swift`，内容为：

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

- [x] **步骤 7：运行接入和大文本测试**

运行：

```bash
cd macos-clipboard-manager
swift test --filter LargeTextPolicyTests
swift test --filter ClipboardIngestServiceTests
```

预期：

```text
Test Suite 'LargeTextPolicyTests' passed
Test Suite 'ClipboardIngestServiceTests' passed
```

- [x] **步骤 8：提交**

```bash
git add macos-clipboard-manager/Sources/ClipboardCore/Ingest macos-clipboard-manager/Sources/ClipboardCore/Storage macos-clipboard-manager/Tests/ClipboardCoreTests/LargeTextPolicyTests.swift macos-clipboard-manager/Tests/ClipboardCoreTests/ClipboardIngestServiceTests.swift
git commit -m "feat: ingest clipboard captures with large text protection"
```

---

### 任务 5：可观测粘贴事务

**涉及文件：**
- 创建： `macos-clipboard-manager/Sources/ClipboardCore/Paste/PasteInterfaces.swift`
- 创建： `macos-clipboard-manager/Sources/ClipboardCore/Paste/PasteController.swift`
- 创建： `macos-clipboard-manager/Tests/ClipboardCoreTests/PasteControllerTests.swift`

- [x] **步骤 1：编写粘贴控制器测试**

创建 `macos-clipboard-manager/Tests/ClipboardCoreTests/PasteControllerTests.swift`，内容为：

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

- [x] **步骤 2：运行粘贴测试并确认失败**

运行：

```bash
cd macos-clipboard-manager
swift test --filter PasteControllerTests
```

预期：构建失败，因为粘贴协议和 `PasteController` 尚未定义。

- [x] **步骤 3：实现粘贴接口**

创建 `macos-clipboard-manager/Sources/ClipboardCore/Paste/PasteInterfaces.swift`，内容为：

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

- [x] **步骤 4：实现粘贴控制器**

创建 `macos-clipboard-manager/Sources/ClipboardCore/Paste/PasteController.swift`，内容为：

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

- [x] **步骤 5：运行粘贴测试**

运行：

```bash
cd macos-clipboard-manager
swift test --filter PasteControllerTests
```

预期：

```text
Test Suite 'PasteControllerTests' passed
```

- [x] **步骤 6：提交**

```bash
git add macos-clipboard-manager/Sources/ClipboardCore/Paste macos-clipboard-manager/Tests/ClipboardCoreTests/PasteControllerTests.swift
git commit -m "feat: add observable paste transactions"
```

---

### 任务 6：剪贴板监听适配器

**涉及文件：**
- 创建： `macos-clipboard-manager/Sources/ClipboardCore/Monitor/ClipboardMonitor.swift`
- 创建： `macos-clipboard-manager/Tests/ClipboardCoreTests/ClipboardMonitorTests.swift`

- [x] **步骤 1：编写监听器测试**

创建 `macos-clipboard-manager/Tests/ClipboardCoreTests/ClipboardMonitorTests.swift`，内容为：

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

- [x] **步骤 2：运行监听器测试并确认失败**

运行：

```bash
cd macos-clipboard-manager
swift test --filter ClipboardMonitorTests
```

预期：构建失败，因为 `ClipboardMonitor` 和 `PasteboardReading` 尚未定义。

- [x] **步骤 3：实现监听器**

创建 `macos-clipboard-manager/Sources/ClipboardCore/Monitor/ClipboardMonitor.swift`，内容为：

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

- [x] **步骤 4：运行监听器测试**

运行：

```bash
cd macos-clipboard-manager
swift test --filter ClipboardMonitorTests
```

预期：

```text
Test Suite 'ClipboardMonitorTests' passed
```

- [x] **步骤 5：提交**

```bash
git add macos-clipboard-manager/Sources/ClipboardCore/Monitor macos-clipboard-manager/Tests/ClipboardCoreTests/ClipboardMonitorTests.swift
git commit -m "feat: add protocol driven clipboard monitor"
```

---

### 任务 7：QuickPanel ViewModel

**涉及文件：**
- 创建： `macos-clipboard-manager/Sources/ClipboardCore/UI/QuickPanelViewModel.swift`
- 创建： `macos-clipboard-manager/Tests/ClipboardCoreTests/QuickPanelViewModelTests.swift`

- [x] **步骤 1：编写 QuickPanel ViewModel 测试**

创建 `macos-clipboard-manager/Tests/ClipboardCoreTests/QuickPanelViewModelTests.swift`，内容为：

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

- [x] **步骤 2：运行 QuickPanel 测试并确认失败**

运行：

```bash
cd macos-clipboard-manager
swift test --filter QuickPanelViewModelTests
```

预期：构建失败，因为 `QuickPanelViewModel` 尚未定义。

- [x] **步骤 3：实现 QuickPanel ViewModel**

创建 `macos-clipboard-manager/Sources/ClipboardCore/UI/QuickPanelViewModel.swift`，内容为：

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

- [x] **步骤 4：运行 QuickPanel 测试**

运行：

```bash
cd macos-clipboard-manager
swift test --filter QuickPanelViewModelTests
```

预期：

```text
Test Suite 'QuickPanelViewModelTests' passed
```

- [x] **步骤 5：提交**

```bash
git add macos-clipboard-manager/Sources/ClipboardCore/UI macos-clipboard-manager/Tests/ClipboardCoreTests/QuickPanelViewModelTests.swift
git commit -m "feat: add lightweight quick panel view model"
```

---

### 任务 8：AppKit 系统适配器

> 执行修正：code quality review 后，实际实现改为使用 `NSPasteboardItem` 写入 marker 和 payload，避免文件 URL 写入时 marker 与 payload 分离；多文件 URL 每个 item 都携带 marker，`containsMarker` 会检查所有 pasteboard item。

**涉及文件：**
- 创建： `macos-clipboard-manager/Sources/ClipboardApp/SystemPasteboardClient.swift`
- 修改： `macos-clipboard-manager/Sources/ClipboardApp/ClipboardApp.swift`

- [x] **步骤 1：创建系统 pasteboard 适配器**

创建 `macos-clipboard-manager/Sources/ClipboardApp/SystemPasteboardClient.swift`，内容为：

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

- [x] **步骤 2：用服务组装替换 app shell**

修改 `macos-clipboard-manager/Sources/ClipboardApp/ClipboardApp.swift`，改为：

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

- [x] **步骤 3：构建 app target**

运行：

```bash
cd macos-clipboard-manager
swift build
```

预期：

```text
Build complete!
```

- [x] **步骤 4：提交**

```bash
git add macos-clipboard-manager/Sources/ClipboardApp
git commit -m "feat: add appkit pasteboard adapters"
```

---

### 任务 9：验证脚手架

**涉及文件：**
- 创建： `macos-clipboard-manager/Scripts/verify.sh`
- 创建： `macos-clipboard-manager/Tests/ClipboardCoreTests/PerformanceGuardTests.swift`

- [x] **步骤 1：添加性能保护测试**

创建 `macos-clipboard-manager/Tests/ClipboardCoreTests/PerformanceGuardTests.swift`，内容为：

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

- [x] **步骤 2：添加验证脚本**

创建 `macos-clipboard-manager/Scripts/verify.sh`，内容为：

```bash
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift test
swift build
```

运行：

```bash
chmod +x macos-clipboard-manager/Scripts/verify.sh
```

- [x] **步骤 3：运行完整验证**

运行：

```bash
macos-clipboard-manager/Scripts/verify.sh
```

预期：

```text
Test Suite 'All tests' passed
Build complete!
```

- [x] **步骤 4：提交**

```bash
git add macos-clipboard-manager/Tests/ClipboardCoreTests/PerformanceGuardTests.swift macos-clipboard-manager/Scripts/verify.sh
git commit -m "test: add clipboard manager verification harness"
```

---

### 任务 10：第一阶段切片验收复核

**涉及文件：**
- 读取：`docs/superpowers/specs/2026-04-30-macos-native-clipboard-manager-design.md`
- 读取：`macos-clipboard-manager/Sources/ClipboardCore`
- 读取：`macos-clipboard-manager/Tests/ClipboardCoreTests`

- [x] **步骤 1：运行完整验证**

运行：

```bash
macos-clipboard-manager/Scripts/verify.sh
```

预期：

```text
Test Suite 'All tests' passed
Build complete!
```

- [x] **步骤 2：确认第一阶段切片覆盖**

运行：

```bash
rg -n "ClipboardMonitor|ClipboardIngestService|PrivacyPolicy|LargeTextPolicy|PasteController|PasteTransaction|QuickPanelViewModel" macos-clipboard-manager/Sources macos-clipboard-manager/Tests
```

预期：输出中能在源码或测试中匹配到每个列出的组件。

- [x] **步骤 3：确认 QuickPanel ViewModel 不存在全文渲染路径**

运行：

```bash
rg -n "Text\\(|plainTextPreview|metadata|previewExcerpt" macos-clipboard-manager/Sources/ClipboardCore/UI macos-clipboard-manager/Sources/ClipboardApp
```

预期：`QuickPanelViewModel` 不直接渲染 SwiftUI `Text`；App shell 只允许包含简单静态 `Text` 标签。

- [x] **步骤 4：如有源码调整则提交复核说明**

如果验证过程中需要修改代码，则提交这些修改：

```bash
git add macos-clipboard-manager
git commit -m "fix: close first clipboard manager slice gaps"
```

如果不需要修改代码，不创建空提交。

本次验收复核不需要源码调整，因此不创建空提交；仅提交计划文件中的验收状态更新。

---

## 后续计划

第一阶段切片验证通过后，单独创建以下后续计划：

1. `2026-05-01-macos-clipboard-library-window.md`
   - SwiftData/SQLite persistent store, LibraryWindow, groups, settings, diagnostics.
2. `2026-05-01-macos-clipboard-importers.md`
   - Maccy importer, Clipaste importer, import report, schema version handling.
3. `2026-05-01-macos-clipboard-release.md`
   - Intel package, Apple Silicon package, update manifests, Homebrew Cask split.
4. `2026-05-01-macos-clipboard-compatibility.md`
   - macOS 14 Intel, macOS 15 Intel, macOS 26 Apple Silicon test matrix and performance harness.
