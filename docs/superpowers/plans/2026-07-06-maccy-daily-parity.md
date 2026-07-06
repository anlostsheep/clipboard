# Maccy Daily Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 补齐日常自用达到 Maccy 水平的 5 个体验缺口：开机自启、模糊搜索+命中高亮、排序选项、菜单栏 Option+点击、粘贴后保留面板。

**Architecture:** 每个切片独立可发布。模糊搜索与排序全部落在 `QuickPanelViewModel`（现有实现是 `store.fetchAll()` + 内存过滤排序，SQLite store 持有全量内存索引，**没有 SQL 层文本过滤**——不改任何 store 或 `HistoryQuery`）。开机自启走 `SMAppService`，状态栏交互扩展现有 `ClickAction` 纯函数，keep-open 扩展 `QuickPanelController` 注入闭包模式。

**Tech Stack:** Swift 5.10+ / SwiftUI + AppKit / ServiceManagement / XCTest / SwiftPM

**Spec:** `docs/superpowers/specs/2026-07-06-maccy-daily-parity-design.md`

## Global Constraints

- macOS 14+，Apple Silicon 为主要验证平台；不新增任何第三方依赖；零网络调用。
- 代码注释用英文；UI 文案用中文（与现有 `AppSettings.swift` / 各 SettingsView 一致）。
- 所有新设置项默认值 = 当前行为（自启默认关、排序默认 `lastCopied`、keep-open 默认关）。
- 每个任务完成必须过 `Scripts/verify.sh`；用户可见行为变更必须在 `docs/manual-acceptance-checklist.md` 增补**未勾选**条目（物理验收后才勾选）。
- Core 文件 2 空格缩进；App 层文件遵循所在文件现状（`AppSettings.swift`/`StatusBarController.swift`/`GeneralSettingsView.swift` 为 4 空格，`QuickPanelState.swift` 为 2 空格）。
- 提交信息遵循 conventional commits（近期风格：`feat:` / `fix:` / `docs:` / `test:`）。
- 不在 actor 外部访问其可变状态；UI 状态在 `@MainActor` 更新。

---

### Task 1: 开机自启（LoginItemManager + 设置 UI）

**Files:**
- Create: `Sources/ClipboardApp/Settings/LoginItemManager.swift`
- Modify: `Sources/ClipboardApp/Settings/GeneralSettingsView.swift`（在外观 Section 附近新增「启动」Section）
- Test: `Tests/ClipboardAppTests/LoginItemManagerTests.swift`
- Modify: `docs/manual-acceptance-checklist.md`

**Interfaces:**
- Produces: `protocol LoginItemManaging`（`currentStatus() -> LoginItemStatus`、`setEnabled(Bool) throws`、`openSystemLoginItemsSettings()`）；`enum LoginItemStatus: Equatable`（`.enabled/.notRegistered/.requiresApproval/.unsupported(reason: String)`）；`struct LoginItemSettingPresentation`（`isOn/isToggleEnabled/hint/showsOpenSettingsButton`，`static func make(from:)`）。仅本任务内使用，后续任务不依赖。

- [ ] **Step 1: 写失败测试**

新建 `Tests/ClipboardAppTests/LoginItemManagerTests.swift`：

```swift
import XCTest
@testable import ClipboardApp

final class LoginItemManagerTests: XCTestCase {
    func testEnabledStatusPresentsToggleOnWithoutHint() {
        let p = LoginItemSettingPresentation.make(from: .enabled)
        XCTAssertTrue(p.isOn)
        XCTAssertTrue(p.isToggleEnabled)
        XCTAssertNil(p.hint)
        XCTAssertFalse(p.showsOpenSettingsButton)
    }

    func testNotRegisteredStatusPresentsToggleOffWithoutHint() {
        let p = LoginItemSettingPresentation.make(from: .notRegistered)
        XCTAssertFalse(p.isOn)
        XCTAssertTrue(p.isToggleEnabled)
        XCTAssertNil(p.hint)
        XCTAssertFalse(p.showsOpenSettingsButton)
    }

    func testRequiresApprovalStatusShowsHintAndSettingsButton() {
        let p = LoginItemSettingPresentation.make(from: .requiresApproval)
        XCTAssertFalse(p.isOn)
        XCTAssertTrue(p.isToggleEnabled)
        XCTAssertNotNil(p.hint)
        XCTAssertTrue(p.showsOpenSettingsButton)
    }

    func testUnsupportedStatusDisablesToggleWithReason() {
        let p = LoginItemSettingPresentation.make(from: .unsupported(reason: "not an app bundle"))
        XCTAssertFalse(p.isOn)
        XCTAssertFalse(p.isToggleEnabled)
        XCTAssertEqual(p.hint, "not an app bundle")
        XCTAssertFalse(p.showsOpenSettingsButton)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift test --filter LoginItemManagerTests`
Expected: 编译失败（`LoginItemSettingPresentation` 未定义）。

- [ ] **Step 3: 实现 LoginItemManager.swift**

```swift
import Foundation
import ServiceManagement

enum LoginItemStatus: Equatable {
    case enabled
    case notRegistered
    case requiresApproval
    case unsupported(reason: String)
}

@MainActor
protocol LoginItemManaging {
    func currentStatus() -> LoginItemStatus
    func setEnabled(_ enabled: Bool) throws
    func openSystemLoginItemsSettings()
}

/// Real implementation backed by SMAppService. Status is always read live from
/// the system (never cached in UserDefaults) because users can change login
/// items directly in System Settings.
@MainActor
final class SMAppServiceLoginItemManager: LoginItemManaging {
    func currentStatus() -> LoginItemStatus {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return .unsupported(reason: "当前不是从 .app 包运行（例如 swift run），无法注册登录项。")
        }
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound:
            return .notRegistered
        @unknown default:
            return .notRegistered
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    func openSystemLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Pure presentation mapping so the settings UI logic is unit-testable
/// without SwiftUI or the real SMAppService.
struct LoginItemSettingPresentation: Equatable {
    let isOn: Bool
    let isToggleEnabled: Bool
    let hint: String?
    let showsOpenSettingsButton: Bool

    static func make(from status: LoginItemStatus) -> LoginItemSettingPresentation {
        switch status {
        case .enabled:
            return LoginItemSettingPresentation(
                isOn: true, isToggleEnabled: true, hint: nil, showsOpenSettingsButton: false)
        case .notRegistered:
            return LoginItemSettingPresentation(
                isOn: false, isToggleEnabled: true, hint: nil, showsOpenSettingsButton: false)
        case .requiresApproval:
            return LoginItemSettingPresentation(
                isOn: false, isToggleEnabled: true,
                hint: "系统尚未批准登录项，请在「系统设置 › 通用 › 登录项」中允许。",
                showsOpenSettingsButton: true)
        case .unsupported(let reason):
            return LoginItemSettingPresentation(
                isOn: false, isToggleEnabled: false, hint: reason, showsOpenSettingsButton: false)
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift test --filter LoginItemManagerTests`
Expected: 4 个测试 PASS。

- [ ] **Step 5: 在 GeneralSettingsView 新增「启动」Section**

在 `GeneralSettingsView` struct 内新增属性（与现有 `@AppStorage` 属性并列）：

```swift
    private let loginItemManager: LoginItemManaging = SMAppServiceLoginItemManager()
    @State private var loginItemStatus: LoginItemStatus = .notRegistered
```

在 Form 中（外观 Section 之后）新增 Section：

```swift
            Section("启动") {
                let presentation = LoginItemSettingPresentation.make(from: loginItemStatus)
                Toggle("登录时自动启动", isOn: Binding(
                    get: { presentation.isOn },
                    set: { newValue in
                        try? loginItemManager.setEnabled(newValue)
                        loginItemStatus = loginItemManager.currentStatus()
                    }
                ))
                .disabled(!presentation.isToggleEnabled)

                if let hint = presentation.hint {
                    HStack {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(.orange)
                        if presentation.showsOpenSettingsButton {
                            Spacer()
                            Button("打开系统设置") {
                                loginItemManager.openSystemLoginItemsSettings()
                            }
                        }
                    }
                }
            }
```

并在现有 `.onAppear { accessibilityPermission.refresh() }` 中追加 `loginItemStatus = loginItemManager.currentStatus()`。

- [ ] **Step 6: 更新手工验收清单**

在 `docs/manual-acceptance-checklist.md` 增补未勾选条目：

```markdown
- [ ] 设置「通用 › 启动」开启"登录时自动启动"后，重启 macOS，ClipboardApp 自动出现在菜单栏（稳定自签名构建验证）。
- [ ] 关闭"登录时自动启动"后，系统设置「登录项」中对应条目消失，重启后不再自动启动。
- [ ] 系统设置中手动移除登录项后，重新打开设置页，开关正确显示为关闭状态。
- [ ] `swift run` 场景（非 .app 包）下开关禁用并显示原因说明。
```

- [ ] **Step 7: 全量门禁 + 提交**

Run: `Scripts/verify.sh`
Expected: 三步全部通过。

```bash
git add Sources/ClipboardApp/Settings/LoginItemManager.swift Sources/ClipboardApp/Settings/GeneralSettingsView.swift Tests/ClipboardAppTests/LoginItemManagerTests.swift docs/manual-acceptance-checklist.md
git commit -m "feat: add launch-at-login via SMAppService with live status in settings"
```

---

### Task 2: FuzzyMatcher（Core 纯逻辑）

**Files:**
- Create: `Sources/ClipboardCore/Search/FuzzyMatcher.swift`
- Test: `Tests/ClipboardCoreTests/FuzzyMatcherTests.swift`

**Interfaces:**
- Produces: `FuzzyMatcher.match(query: String, in candidate: String) -> FuzzyMatch?`；`struct FuzzyMatch: Equatable, Sendable { let score: Int; let matchedOffsets: [Int] }`（offsets 是 candidate 的 0-based **Character** 偏移）。Task 3 依赖此签名。

- [ ] **Step 1: 写失败测试**

新建 `Tests/ClipboardCoreTests/FuzzyMatcherTests.swift`：

```swift
import XCTest
@testable import ClipboardCore

final class FuzzyMatcherTests: XCTestCase {
    func testSubstringMatchReturnsContiguousOffsets() {
        let match = FuzzyMatcher.match(query: "board", in: "clipboard manager")
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.matchedOffsets, [4, 5, 6, 7, 8])
    }

    func testSubstringMatchIsCaseInsensitive() {
        XCTAssertNotNil(FuzzyMatcher.match(query: "BOARD", in: "Clipboard"))
    }

    func testSubstringScoreBeatsAnySubsequenceScore() {
        let substring = FuzzyMatcher.match(query: "clip", in: "clipboard")!
        let subsequence = FuzzyMatcher.match(query: "cb", in: "clipboard")!
        XCTAssertGreaterThan(substring.score, subsequence.score)
    }

    func testSubsequenceMatchFindsNonContiguousCharacters() {
        let match = FuzzyMatcher.match(query: "cbm", in: "clipboard manager")
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.matchedOffsets, [0, 4, 10])
    }

    func testConsecutiveHitsScoreHigherThanScatteredHits() {
        // "ab" in "xabx" is consecutive; "ab" in "xaxb" is scattered.
        let consecutive = FuzzyMatcher.match(query: "ab", in: "xabx")!
        let scattered = FuzzyMatcher.match(query: "ab", in: "xaxb")!
        XCTAssertGreaterThan(consecutive.score, scattered.score)
    }

    func testCJKSubsequenceMatches() {
        let match = FuzzyMatcher.match(query: "剪板", in: "剪贴板历史")
        XCTAssertNotNil(match)
        XCTAssertEqual(match?.matchedOffsets, [0, 2])
    }

    func testCJKSubstringMatches() {
        let match = FuzzyMatcher.match(query: "剪贴板", in: "系统剪贴板历史")
        XCTAssertEqual(match?.matchedOffsets, [2, 3, 4])
    }

    func testNoMatchReturnsNil() {
        XCTAssertNil(FuzzyMatcher.match(query: "zzz", in: "clipboard"))
    }

    func testMissingOneCharacterReturnsNil() {
        // All query characters must be present in order.
        XCTAssertNil(FuzzyMatcher.match(query: "cbz", in: "clipboard"))
    }

    func testEmptyOrWhitespaceQueryReturnsNil() {
        XCTAssertNil(FuzzyMatcher.match(query: "", in: "clipboard"))
        XCTAssertNil(FuzzyMatcher.match(query: "   ", in: "clipboard"))
    }

    func testEmptyCandidateReturnsNil() {
        XCTAssertNil(FuzzyMatcher.match(query: "a", in: ""))
    }

    func testEarlierSubstringStartScoresHigher() {
        let early = FuzzyMatcher.match(query: "clip", in: "clipboard")!
        let late = FuzzyMatcher.match(query: "clip", in: "my clipboard")!
        XCTAssertGreaterThan(early.score, late.score)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift test --filter FuzzyMatcherTests`
Expected: 编译失败（`FuzzyMatcher` 未定义）。

- [ ] **Step 3: 实现 FuzzyMatcher.swift**

```swift
import Foundation

/// Result of a fuzzy match. `matchedOffsets` are 0-based Character offsets
/// into the candidate string, used by the UI to highlight hits.
public struct FuzzyMatch: Equatable, Sendable {
  public let score: Int
  public let matchedOffsets: [Int]

  public init(score: Int, matchedOffsets: [Int]) {
    self.score = score
    self.matchedOffsets = matchedOffsets
  }
}

/// Character-based fuzzy matcher. Works on Characters (not scalars) so CJK
/// text matches naturally without any word-boundary concept.
///
/// Scoring tiers:
/// - Full substring hit: top tier (`substringBaseScore` minus a small
///   start-offset penalty) so existing substring-search habits keep ranking first.
/// - In-order subsequence hit: per-character score plus bonuses for
///   consecutive runs and prefix hits. No hit for any query character → nil.
public enum FuzzyMatcher {
  public static let substringBaseScore = 10_000
  public static let subsequenceCharScore = 10
  public static let consecutiveBonus = 15
  public static let prefixBonus = 20

  public static func match(query: String, in candidate: String) -> FuzzyMatch? {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !candidate.isEmpty else { return nil }
    let queryChars = Array(trimmed.lowercased())
    let candidateChars = Array(candidate.lowercased())

    if let start = substringStart(of: queryChars, in: candidateChars) {
      let offsets = Array(start..<(start + queryChars.count))
      return FuzzyMatch(score: substringBaseScore - min(start, 100), matchedOffsets: offsets)
    }
    return subsequenceMatch(queryChars, in: candidateChars)
  }

  private static func substringStart(of query: [Character], in candidate: [Character]) -> Int? {
    guard candidate.count >= query.count else { return nil }
    for start in 0...(candidate.count - query.count) {
      var matched = true
      for i in 0..<query.count where candidate[start + i] != query[i] {
        matched = false
        break
      }
      if matched { return start }
    }
    return nil
  }

  private static func subsequenceMatch(_ query: [Character], in candidate: [Character]) -> FuzzyMatch? {
    var offsets: [Int] = []
    var searchIndex = 0
    for ch in query {
      var found: Int?
      var i = searchIndex
      while i < candidate.count {
        if candidate[i] == ch {
          found = i
          break
        }
        i += 1
      }
      guard let hit = found else { return nil }
      offsets.append(hit)
      searchIndex = hit + 1
    }

    var score = offsets.count * subsequenceCharScore
    if offsets.first == 0 {
      score += prefixBonus
    }
    for pair in zip(offsets, offsets.dropFirst()) where pair.1 == pair.0 + 1 {
      score += consecutiveBonus
    }
    return FuzzyMatch(score: score, matchedOffsets: offsets)
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift test --filter FuzzyMatcherTests`
Expected: 12 个测试 PASS。

- [ ] **Step 5: 提交**

```bash
git add Sources/ClipboardCore/Search/FuzzyMatcher.swift Tests/ClipboardCoreTests/FuzzyMatcherTests.swift
git commit -m "feat: add character-based FuzzyMatcher with substring top-tier scoring"
```

---

### Task 3: QuickPanelViewModel 接入模糊搜索并暴露命中偏移

**Files:**
- Modify: `Sources/ClipboardCore/UI/QuickPanelViewModel.swift`
- Test: `Tests/ClipboardCoreTests/QuickPanelViewModelTests.swift`（追加到现有文件，复用其中已有的 record fixture helper）
- Modify: `docs/manual-acceptance-checklist.md`

**Interfaces:**
- Consumes: `FuzzyMatcher.match(query:in:) -> FuzzyMatch?`（Task 2）；`QuickPanelRowPresentation.primaryContentText(for:)`（已存在）。
- Produces: `QuickPanelViewModel.refresh(query:contentTypes:groupIDs:)` 语义变更（非空 query 走 fuzzy）；新增 `public private(set) var searchMatches: [UUID: QuickPanelSearchMatch]`；`public struct QuickPanelSearchMatch: Equatable, Sendable { let score: Int; let primaryTextOffsets: [Int] }`。Task 4 依赖 `searchMatches`。

- [ ] **Step 1: 写失败测试**

先给该文件底部已有的 `makeRecord(id:title:primaryType:lastCopiedAt:groupIds:isPinned:pinnedAt:)` helper 补三个带默认值的参数（透传给 `ClipboardRecord` 对应字段，替换原先写死的值）：

```swift
    sourceAppName: String = "Terminal",
    createdAt: TimeInterval = 1,
    copyCount: Int = 1
```

然后追加测试（helper 的 `title` 同时写入 `plainTextPreview` 与 `contentHash`，断言直接用 `.title`）：

```swift
  func testFuzzyQueryMatchesNonContiguousCharacters() async throws {
    // "cbm" is not a substring of either title, but is an in-order
    // subsequence of "clipboard manager" only.
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makeRecord(id: UUID(), title: "clipboard manager", lastCopiedAt: 1))
    _ = try await store.upsert(makeRecord(id: UUID(), title: "unrelated", lastCopiedAt: 2))
    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)

    await viewModel.refresh(query: "cbm")

    let titles = await viewModel.items.map(\.title)
    XCTAssertEqual(titles, ["clipboard manager"])
  }

  func testSubstringMatchRanksAboveSubsequenceMatch() async throws {
    // "clip" is a substring of "my clip notes" but only a scattered
    // subsequence of "cool lion iron plate". The substring hit must rank
    // first even though the subsequence record is more recent.
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makeRecord(id: UUID(), title: "my clip notes", lastCopiedAt: 100))
    _ = try await store.upsert(makeRecord(id: UUID(), title: "cool lion iron plate", lastCopiedAt: 200))
    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)

    await viewModel.refresh(query: "clip")

    let titles = await viewModel.items.map(\.title)
    XCTAssertEqual(titles.first, "my clip notes")
  }

  func testSearchMatchesExposesPrimaryTextOffsets() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makeRecord(id: UUID(), title: "clipboard", lastCopiedAt: 1))
    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)

    await viewModel.refresh(query: "board")

    let items = await viewModel.items
    let matches = await viewModel.searchMatches
    XCTAssertEqual(items.count, 1)
    XCTAssertEqual(matches[items[0].id]?.primaryTextOffsets, [4, 5, 6, 7, 8])
  }

  func testEmptyQueryClearsSearchMatchesAndKeepsRecencyOrder() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makeRecord(id: UUID(), title: "older", lastCopiedAt: 100))
    _ = try await store.upsert(makeRecord(id: UUID(), title: "newer", lastCopiedAt: 200))
    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)

    await viewModel.refresh(query: "old")
    await viewModel.refresh(query: "")

    let matches = await viewModel.searchMatches
    let titles = await viewModel.items.map(\.title)
    XCTAssertTrue(matches.isEmpty)
    XCTAssertEqual(titles, ["newer", "older"])
  }

  func testPinnedRecordsStayFirstDuringFuzzySearch() async throws {
    // A pinned weak (subsequence) match must still be listed before an
    // unpinned strong (substring) match.
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(
      makeRecord(id: UUID(), title: "capable item board", lastCopiedAt: 1, isPinned: true, pinnedAt: 1))
    _ = try await store.upsert(makeRecord(id: UUID(), title: "cab", lastCopiedAt: 2))
    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)

    await viewModel.refresh(query: "cab")

    let items = await viewModel.items
    XCTAssertEqual(items.count, 2)
    XCTAssertTrue(items[0].isPinned)
  }

  func testFuzzyQueryStillMatchesSourceAppName() async throws {
    // The query hits only the source app name, not the content.
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(
      makeRecord(id: UUID(), title: "hello world", lastCopiedAt: 1, sourceAppName: "Safari"))
    _ = try await store.upsert(
      makeRecord(id: UUID(), title: "other", lastCopiedAt: 2, sourceAppName: "Xcode"))
    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)

    await viewModel.refresh(query: "safari")

    let items = await viewModel.items
    XCTAssertEqual(items.count, 1)
    XCTAssertEqual(items.first?.sourceAppName, "Safari")
  }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift test --filter QuickPanelViewModelTests`
Expected: 新增测试编译失败（`searchMatches` 未定义）或断言失败。

- [ ] **Step 3: 实现 ViewModel 改动**

在 `QuickPanelViewModel.swift` 顶部（`QuickPanelSelectionIntent` 之后）新增：

```swift
public struct QuickPanelSearchMatch: Equatable, Sendable {
  public let score: Int
  public let primaryTextOffsets: [Int]

  public init(score: Int, primaryTextOffsets: [Int]) {
    self.score = score
    self.primaryTextOffsets = primaryTextOffsets
  }
}
```

actor 内新增存储属性：

```swift
  public private(set) var searchMatches: [UUID: QuickPanelSearchMatch] = [:]
```

将 `refresh` 整体替换为：

```swift
  @discardableResult
  public func refresh(
    query: String,
    contentTypes: Set<ClipboardContentType> = [],
    groupIDs: Set<String> = []
  ) async -> Bool {
    refreshGeneration += 1
    let generation = refreshGeneration
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    // Type/group scoping still goes through HistoryQuery; text matching is
    // handled by FuzzyMatcher below because substring pre-filtering would
    // drop non-contiguous subsequence hits.
    let scopeQuery = HistoryQuery(text: "", contentTypes: contentTypes, groupIDs: groupIDs)
    let scoped = ((try? await store.fetchAll()) ?? []).filter { scopeQuery.matches($0) }

    let refreshedItems: [ClipboardRecord]
    var matches: [UUID: QuickPanelSearchMatch] = [:]
    if trimmedQuery.isEmpty {
      refreshedItems = scoped.sorted(by: Self.quickPanelSort)
    } else {
      let scored: [(record: ClipboardRecord, match: QuickPanelSearchMatch)] = scoped.compactMap { record in
        let primaryText = QuickPanelRowPresentation.primaryContentText(for: record)
        let primaryMatch = FuzzyMatcher.match(query: trimmedQuery, in: primaryText)
        let titleMatch = FuzzyMatcher.match(query: trimmedQuery, in: record.title)
        let sourceMatch = record.sourceAppName.flatMap {
          FuzzyMatcher.match(query: trimmedQuery, in: $0)
        }
        guard let best = [primaryMatch, titleMatch, sourceMatch].compactMap({ $0?.score }).max() else {
          return nil
        }
        return (
          record,
          QuickPanelSearchMatch(score: best, primaryTextOffsets: primaryMatch?.matchedOffsets ?? [])
        )
      }
      let ranked = scored.sorted { lhs, rhs in
        if lhs.record.isPinned != rhs.record.isPinned {
          return lhs.record.isPinned
        }
        if lhs.match.score != rhs.match.score {
          return lhs.match.score > rhs.match.score
        }
        if lhs.record.lastCopiedAt != rhs.record.lastCopiedAt {
          return lhs.record.lastCopiedAt > rhs.record.lastCopiedAt
        }
        return lhs.record.id.uuidString < rhs.record.id.uuidString
      }
      refreshedItems = ranked.map(\.record)
      for entry in ranked {
        matches[entry.record.id] = entry.match
      }
    }

    guard generation == refreshGeneration else {
      return false
    }

    items = QuickPanelListPolicy.limitedItems(refreshedItems, limit: pageLimit)
    searchMatches = matches
    selectedIndex = items.isEmpty ? 0 : min(selectedIndex, items.count - 1)
    return true
  }
```

`quickPanelSort` 保持不动（本任务不引入排序选项）。

- [ ] **Step 4: 跑测试确认通过（含既有测试）**

Run: `swift test --filter QuickPanelViewModelTests && swift test --filter QuickPanelStateFilterTests`
Expected: 全部 PASS。既有断言"搜索结果按 lastCopiedAt 排"的测试若失败，是排名语义的**预期变化**（同为 substring 命中时，命中起始位置更靠前的记录得分更高）；把这些断言更新为新语义，并在提交信息里注明。

- [ ] **Step 5: 更新手工验收清单**

```markdown
- [ ] QuickPanel 搜索输入非连续字符（如对"clipboard manager"输入"cbm"）能命中记录。
- [ ] 搜索中文时按字符子序列命中（如对"剪贴板历史"输入"剪史"）。
- [ ] 完整子串命中的记录排在纯模糊命中的记录之前。
- [ ] 搜索激活时置顶记录仍显示在 Pinned 区且位于最上方。
```

- [ ] **Step 6: 全量门禁 + 提交**

Run: `Scripts/verify.sh`
Expected: 通过。

```bash
git add Sources/ClipboardCore/UI/QuickPanelViewModel.swift Tests/ClipboardCoreTests/QuickPanelViewModelTests.swift docs/manual-acceptance-checklist.md
git commit -m "feat: fuzzy search in QuickPanelViewModel with per-record match offsets"
```

---

### Task 4: 搜索命中高亮渲染

**Files:**
- Create: `Sources/ClipboardApp/QuickPanel/QuickPanelHighlight.swift`
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelState.swift`（透传 `searchMatches` → `@Published var matchOffsets`）
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelView.swift`（行内主文本改用高亮 AttributedString）
- Test: `Tests/ClipboardAppTests/QuickPanelHighlightTests.swift`
- Modify: `docs/manual-acceptance-checklist.md`

**Interfaces:**
- Consumes: `QuickPanelViewModel.searchMatches: [UUID: QuickPanelSearchMatch]`（Task 3）。
- Produces: `QuickPanelHighlight.attributed(text: String, highlightOffsets: [Int]) -> AttributedString`；`QuickPanelState.matchOffsets: [UUID: [Int]]`。

- [ ] **Step 1: 写失败测试**

新建 `Tests/ClipboardAppTests/QuickPanelHighlightTests.swift`：

```swift
import XCTest
@testable import ClipboardApp

final class QuickPanelHighlightTests: XCTestCase {
    private func emphasizedCharacterOffsets(in attributed: AttributedString) -> [Int] {
        var offsets: [Int] = []
        var offset = 0
        var index = attributed.startIndex
        while index < attributed.endIndex {
            let next = attributed.index(afterCharacter: index)
            if attributed[index..<next].inlinePresentationIntent == .stronglyEmphasized {
                offsets.append(offset)
            }
            index = next
            offset += 1
        }
        return offsets
    }

    func testHighlightsExactOffsets() {
        let result = QuickPanelHighlight.attributed(text: "clipboard", highlightOffsets: [4, 5, 6])
        XCTAssertEqual(emphasizedCharacterOffsets(in: result), [4, 5, 6])
        XCTAssertEqual(String(result.characters), "clipboard")
    }

    func testEmptyOffsetsProducePlainText() {
        let result = QuickPanelHighlight.attributed(text: "clipboard", highlightOffsets: [])
        XCTAssertEqual(emphasizedCharacterOffsets(in: result), [])
    }

    func testOutOfRangeOffsetsAreIgnored() {
        let result = QuickPanelHighlight.attributed(text: "abc", highlightOffsets: [-1, 2, 99])
        XCTAssertEqual(emphasizedCharacterOffsets(in: result), [2])
    }

    func testCJKOffsetsHighlightWholeCharacters() {
        let result = QuickPanelHighlight.attributed(text: "剪贴板历史", highlightOffsets: [0, 2])
        XCTAssertEqual(emphasizedCharacterOffsets(in: result), [0, 2])
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift test --filter QuickPanelHighlightTests`
Expected: 编译失败（`QuickPanelHighlight` 未定义）。

- [ ] **Step 3: 实现 QuickPanelHighlight.swift**

```swift
import SwiftUI

/// Builds the highlighted primary-content text for a QuickPanel row.
/// Offsets are 0-based Character offsets produced by FuzzyMatcher against
/// the same string; out-of-range offsets are ignored defensively because
/// the displayed text and the matched text are derived independently.
enum QuickPanelHighlight {
    static func attributed(text: String, highlightOffsets: [Int]) -> AttributedString {
        var result = AttributedString(text)
        guard !highlightOffsets.isEmpty else { return result }

        let characterCount = text.count
        let valid = Set(highlightOffsets.filter { $0 >= 0 && $0 < characterCount })
        guard !valid.isEmpty else { return result }

        var offset = 0
        var index = result.startIndex
        while index < result.endIndex {
            let next = result.index(afterCharacter: index)
            if valid.contains(offset) {
                result[index..<next].inlinePresentationIntent = .stronglyEmphasized
                result[index..<next].foregroundColor = Color.accentColor
            }
            index = next
            offset += 1
        }
        return result
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift test --filter QuickPanelHighlightTests`
Expected: 4 个测试 PASS。

- [ ] **Step 5: QuickPanelState 透传命中偏移**

在 `QuickPanelState`（class，`Sources/ClipboardApp/QuickPanel/QuickPanelState.swift:162` 起）新增 published 属性：

```swift
  @Published private(set) var matchOffsets: [UUID: [Int]] = [:]
```

在 `applyRefresh()`（约 :680，调用 `viewModel.refresh(...)` 之后同步 `items`/sections 的位置）追加同步：

```swift
    matchOffsets = await viewModel.searchMatches.mapValues(\.primaryTextOffsets)
```

- [ ] **Step 6: 行渲染接入高亮**

在 `QuickPanelView.swift` 中找到行主文本渲染处（`quickPanelSection` → 行视图内，当前为 `Text(QuickPanelRowPresentation.primaryContentText(for: <record>))` 形式；仅 `contentVisual == .text` 的分支），替换为：

```swift
Text(QuickPanelHighlight.attributed(
    text: QuickPanelRowPresentation.primaryContentText(for: row.record),
    highlightOffsets: state.matchOffsets[row.record.id] ?? []
))
```

保留原有的 `lineLimit`/字体等修饰符不变。

- [ ] **Step 7: 更新手工验收清单**

```markdown
- [ ] QuickPanel 搜索命中时，列表行内命中字符以强调色+加粗显示；清空搜索后高亮消失。
- [ ] 中文命中高亮逐字符正确（无错位、无半个字符高亮）。
```

- [ ] **Step 8: 全量门禁 + 提交**

Run: `Scripts/verify.sh`
Expected: 通过。

```bash
git add Sources/ClipboardApp/QuickPanel/QuickPanelHighlight.swift Sources/ClipboardApp/QuickPanel/QuickPanelState.swift Sources/ClipboardApp/QuickPanel/QuickPanelView.swift Tests/ClipboardAppTests/QuickPanelHighlightTests.swift docs/manual-acceptance-checklist.md
git commit -m "feat: highlight fuzzy match hits in QuickPanel rows"
```

---

### Task 5: 排序选项（HistorySortOrder）

**Files:**
- Create: `Sources/ClipboardCore/UI/HistorySortOrder.swift`
- Modify: `Sources/ClipboardCore/UI/QuickPanelViewModel.swift`（`refresh` 增加 `sortOrder` 参数、`quickPanelSort` 分支）
- Modify: `Sources/ClipboardApp/AppSettings.swift`（key + 访问器 + displayName）
- Modify: `Sources/ClipboardApp/Settings/HistorySettingsView.swift`（新增 Picker）
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelState.swift`（`applyRefresh` 传入设置值）
- Test: `Tests/ClipboardCoreTests/QuickPanelViewModelTests.swift`（追加）
- Modify: `docs/manual-acceptance-checklist.md`

**Interfaces:**
- Produces: `public enum HistorySortOrder: String, CaseIterable, Sendable { case lastCopied, firstCopied, copyCount }`（Core）；`QuickPanelViewModel.refresh(query:contentTypes:groupIDs:sortOrder:)`（`sortOrder` 默认 `.lastCopied`，既有调用方兼容）；`ClipboardAppSettings.historySortOrder(defaults:) -> HistorySortOrder` 与 `historySortOrderKey = "history.sortOrder"`。

- [ ] **Step 1: 写失败测试**

在 `Tests/ClipboardCoreTests/QuickPanelViewModelTests.swift` 追加（`createdAt`/`copyCount`/`sourceAppName` helper 参数已在 Task 3 补充）：

```swift
  func testDefaultSortOrderIsLastCopiedDescending() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makeRecord(id: UUID(), title: "old", lastCopiedAt: 100))
    _ = try await store.upsert(makeRecord(id: UUID(), title: "new", lastCopiedAt: 200))
    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)

    await viewModel.refresh(query: "")

    let titles = await viewModel.items.map(\.title)
    XCTAssertEqual(titles, ["new", "old"])
  }

  func testCopyCountSortOrderRanksMostCopiedFirst() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makeRecord(id: UUID(), title: "frequent", lastCopiedAt: 100, copyCount: 9))
    _ = try await store.upsert(makeRecord(id: UUID(), title: "recent", lastCopiedAt: 200))
    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)

    await viewModel.refresh(query: "", sortOrder: .copyCount)

    let titles = await viewModel.items.map(\.title)
    XCTAssertEqual(titles.first, "frequent")
  }

  func testFirstCopiedSortOrderUsesCreatedAtDescending() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(
      makeRecord(id: UUID(), title: "created-early", lastCopiedAt: 900, createdAt: 100))
    _ = try await store.upsert(
      makeRecord(id: UUID(), title: "created-late", lastCopiedAt: 600, createdAt: 500))
    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)

    await viewModel.refresh(query: "", sortOrder: .firstCopied)

    let titles = await viewModel.items.map(\.title)
    XCTAssertEqual(titles, ["created-late", "created-early"])
  }

  func testSortOrderDoesNotAffectPinnedSectionOrder() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(
      makeRecord(id: UUID(), title: "pinned-low", lastCopiedAt: 100, isPinned: true, pinnedAt: 100, copyCount: 1))
    _ = try await store.upsert(
      makeRecord(id: UUID(), title: "unpinned-high", lastCopiedAt: 200, copyCount: 50))
    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)

    await viewModel.refresh(query: "", sortOrder: .copyCount)

    let items = await viewModel.items
    XCTAssertTrue(items[0].isPinned)
  }

  func testSortOrderIsIgnoredDuringActiveSearch() async throws {
    // Fuzzy score ranking wins while a query is active: the substring hit
    // outranks the scattered subsequence hit despite a huge copyCount.
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(
      makeRecord(id: UUID(), title: "cxxlxxixxp", lastCopiedAt: 100, copyCount: 99))
    _ = try await store.upsert(makeRecord(id: UUID(), title: "clip", lastCopiedAt: 50))
    let viewModel = QuickPanelViewModel(store: store, pageLimit: 20)

    await viewModel.refresh(query: "clip", sortOrder: .copyCount)

    let titles = await viewModel.items.map(\.title)
    XCTAssertEqual(titles.first, "clip")
  }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift test --filter QuickPanelViewModelTests`
Expected: 编译失败（`sortOrder` 参数不存在）。

- [ ] **Step 3: 实现 Core 改动**

新建 `Sources/ClipboardCore/UI/HistorySortOrder.swift`：

```swift
/// User-selectable ordering for the QuickPanel history section when no
/// search query is active. Matches Maccy's sort options.
public enum HistorySortOrder: String, CaseIterable, Sendable {
  case lastCopied
  case firstCopied
  case copyCount
}
```

`QuickPanelViewModel.refresh` 签名增加参数（放在 `groupIDs` 之后）：

```swift
    groupIDs: Set<String> = [],
    sortOrder: HistorySortOrder = .lastCopied
```

空 query 分支改为：

```swift
      refreshedItems = scoped.sorted { Self.quickPanelSort($0, $1, sortOrder: sortOrder) }
```

`quickPanelSort` 整体替换为：

```swift
  private static func quickPanelSort(
    _ lhs: ClipboardRecord,
    _ rhs: ClipboardRecord,
    sortOrder: HistorySortOrder
  ) -> Bool {
    if lhs.isPinned != rhs.isPinned {
      return lhs.isPinned && !rhs.isPinned
    }
    if lhs.isPinned && rhs.isPinned {
      let lhsPinnedAt = lhs.pinnedAt ?? lhs.lastCopiedAt
      let rhsPinnedAt = rhs.pinnedAt ?? rhs.lastCopiedAt
      if lhsPinnedAt != rhsPinnedAt {
        return lhsPinnedAt > rhsPinnedAt
      }
    }
    switch sortOrder {
    case .lastCopied:
      if lhs.lastCopiedAt != rhs.lastCopiedAt {
        return lhs.lastCopiedAt > rhs.lastCopiedAt
      }
    case .firstCopied:
      if lhs.createdAt != rhs.createdAt {
        return lhs.createdAt > rhs.createdAt
      }
    case .copyCount:
      if lhs.copyCount != rhs.copyCount {
        return lhs.copyCount > rhs.copyCount
      }
      if lhs.lastCopiedAt != rhs.lastCopiedAt {
        return lhs.lastCopiedAt > rhs.lastCopiedAt
      }
    }
    return lhs.id.uuidString < rhs.id.uuidString
  }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `swift test --filter QuickPanelViewModelTests`
Expected: 全部 PASS。

- [ ] **Step 5: App 层设置接线**

`AppSettings.swift` 的 `// MARK: - Storage` 区块追加：

```swift
    static let historySortOrderKey = "history.sortOrder"

    static func historySortOrder(defaults: UserDefaults = .standard) -> HistorySortOrder {
        guard let raw = defaults.string(forKey: historySortOrderKey),
              let order = HistorySortOrder(rawValue: raw) else {
            return .lastCopied
        }
        return order
    }
```

文件底部追加 displayName 扩展：

```swift
// MARK: - History Sort Order display

extension HistorySortOrder {
    var displayName: String {
        switch self {
        case .lastCopied:  return "最近复制"
        case .firstCopied: return "首次复制"
        case .copyCount:   return "复制次数"
        }
    }
}
```

`HistorySettingsView.swift` 在保留记录数设置附近新增（对齐该文件既有 `@AppStorage` + Picker 写法）：

```swift
    @AppStorage(ClipboardAppSettings.historySortOrderKey)
    private var sortOrderRaw: String = HistorySortOrder.lastCopied.rawValue
```

```swift
                Picker("历史排序", selection: $sortOrderRaw) {
                    ForEach(HistorySortOrder.allCases, id: \.rawValue) { order in
                        Text(order.displayName).tag(order.rawValue)
                    }
                }
                Text("影响快捷面板浏览时的历史区排序；搜索时按匹配度排序，置顶区不受影响。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
```

`QuickPanelState.swift` 的 `applyRefresh()` 中，把 `viewModel.refresh(query: ..., contentTypes: ...)` 调用追加参数 `sortOrder: ClipboardAppSettings.historySortOrder()`。

- [ ] **Step 6: 更新手工验收清单**

```markdown
- [ ] 「历史」设置切到"复制次数"后，QuickPanel 空搜索浏览时高频记录排前。
- [ ] 切回"最近复制"后恢复现状排序；置顶区顺序在三种排序下都不变。
- [ ] 排序为"复制次数"时数字快捷键 Cmd+1~9 跟随新的可视顺序。
```

- [ ] **Step 7: 全量门禁 + 提交**

Run: `Scripts/verify.sh`
Expected: 通过。

```bash
git add Sources/ClipboardCore/UI/HistorySortOrder.swift Sources/ClipboardCore/UI/QuickPanelViewModel.swift Sources/ClipboardApp/AppSettings.swift Sources/ClipboardApp/Settings/HistorySettingsView.swift Sources/ClipboardApp/QuickPanel/QuickPanelState.swift Tests/ClipboardCoreTests/QuickPanelViewModelTests.swift docs/manual-acceptance-checklist.md
git commit -m "feat: user-selectable history sort order (last copied / first copied / copy count)"
```

---

### Task 6: 菜单栏 Option+点击快捷操作 + 暂停态图标

**Files:**
- Modify: `Sources/ClipboardApp/StatusBar/StatusBarController.swift`
- Modify: `Sources/ClipboardApp/App/AppDelegate.swift`（订阅 capturePaused 变化刷新图标）
- Test: `Tests/ClipboardAppTests/StatusBarControllerTests.swift`（扩展现有文件）
- Modify: `docs/manual-acceptance-checklist.md`

**Interfaces:**
- Produces: `StatusBarController.ClickAction` 新增 `.togglePause`、`.ignoreNextCopy`；纯函数签名变更为 `clickAction(for eventType: NSEvent.EventType?, modifiers: NSEvent.ModifierFlags) -> ClickAction`；新增 `func captureStateDidChange()`。

- [ ] **Step 1: 写失败测试**

在 `Tests/ClipboardAppTests/StatusBarControllerTests.swift` 追加（既有对 `clickAction(for:)` 的调用改为传 `modifiers: []`）：

```swift
    func testLeftClickWithoutModifiersOpensPanel() {
        XCTAssertEqual(
            StatusBarController.clickAction(for: .leftMouseUp, modifiers: []),
            .openPanel)
    }

    func testRightClickShowsMenuRegardlessOfModifiers() {
        XCTAssertEqual(
            StatusBarController.clickAction(for: .rightMouseUp, modifiers: [.option]),
            .showMenu)
    }

    func testOptionLeftClickTogglesPause() {
        XCTAssertEqual(
            StatusBarController.clickAction(for: .leftMouseUp, modifiers: [.option]),
            .togglePause)
    }

    func testOptionShiftLeftClickIgnoresNextCopy() {
        XCTAssertEqual(
            StatusBarController.clickAction(for: .leftMouseUp, modifiers: [.option, .shift]),
            .ignoreNextCopy)
    }

    func testOtherModifierCombinationsOpenPanel() {
        XCTAssertEqual(
            StatusBarController.clickAction(for: .leftMouseUp, modifiers: [.command]),
            .openPanel)
        XCTAssertEqual(
            StatusBarController.clickAction(for: .leftMouseUp, modifiers: [.shift]),
            .openPanel)
    }

    func testNilEventTypeDefaultsToOpenPanel() {
        XCTAssertEqual(
            StatusBarController.clickAction(for: nil, modifiers: [.option]),
            .openPanel)
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `swift test --filter StatusBarControllerTests`
Expected: 编译失败（新 case 与新签名不存在）。

- [ ] **Step 3: 实现 StatusBarController 改动**

`ClickAction` 扩展：

```swift
    enum ClickAction {
        case openPanel
        case showMenu
        case togglePause
        case ignoreNextCopy
    }
```

纯函数替换（保持 `nonisolated static`）：

```swift
    nonisolated static func clickAction(
        for eventType: NSEvent.EventType?,
        modifiers: NSEvent.ModifierFlags
    ) -> ClickAction {
        guard let eventType else {
            return .openPanel
        }
        if eventType == .rightMouseUp {
            return .showMenu
        }
        if modifiers.contains(.option) && modifiers.contains(.shift) {
            return .ignoreNextCopy
        }
        if modifiers.contains(.option) {
            return .togglePause
        }
        return .openPanel
    }
```

`handleClick` 替换：

```swift
    @MainActor @objc private func handleClick(_ sender: NSStatusBarButton) {
        let currentEvent = NSApp.currentEvent
        let modifiers = currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        switch Self.clickAction(for: currentEvent?.type, modifiers: modifiers) {
        case .openPanel:
            onLeftClick(iconOrigin)
        case .showMenu:
            showContextMenu()
        case .togglePause:
            onToggleCapture()
            refreshIcon()
        case .ignoreNextCopy:
            onIgnoreNextCopy()
        }
    }
```

暂停态图标：`refreshIcon` 改为同时决定符号与色调（`setup()` 中原有的两行 `item.button?.image = ...` 设置删除，收敛到 `refreshIcon()`）：

```swift
    private func refreshIcon() {
        guard let button = statusItem?.button else { return }
        let paused = isCapturePaused()
        // Shape communicates paused state; tint communicates storage health.
        let symbolName = paused ? "pause.circle" : "doc.on.clipboard"
        let description = paused ? "Clipboard（已暂停采集）" : "Clipboard"
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        button.image?.isTemplate = true
        switch storageHealth {
        case .ok:
            button.contentTintColor = nil
        case .disabled:
            button.contentTintColor = .systemOrange
        case .failing:
            button.contentTintColor = .systemRed
        }
    }
```

新增公开刷新入口，并在右键菜单的 `toggleCapture()` 内也调用：

```swift
    /// Call when capture-paused state changes outside this controller
    /// (settings toggle, programmatic pause) so the icon stays in sync.
    func captureStateDidChange() {
        refreshIcon()
    }
```

```swift
    @MainActor @objc private func toggleCapture() {
        onToggleCapture()
        refreshIcon()
    }
```

- [ ] **Step 4: AppDelegate 订阅设置页触发的暂停变化**

在 `AppDelegate` 创建 `StatusBarController` 的位置之后，订阅 `AppServices` 的 `@Published capturePaused`（需要 `import Combine` 与一个 `private var cancellables: Set<AnyCancellable> = []` 属性；若已存在则复用）：

```swift
        services.$capturePaused
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.statusBarController?.captureStateDidChange()
            }
            .store(in: &cancellables)
```

（属性名以 AppDelegate 实际持有的 status bar controller 命名为准。）

- [ ] **Step 5: 跑测试确认通过**

Run: `swift test --filter StatusBarControllerTests`
Expected: 全部 PASS。

- [ ] **Step 6: 更新手工验收清单**

```markdown
- [ ] Option+点击菜单栏图标切换暂停/恢复采集，图标在暂停时变为 pause 形态。
- [ ] Option+Shift+点击菜单栏图标后，下一次复制不入历史，再下一次恢复正常。
- [ ] 从设置页切换"暂停采集"时菜单栏图标同步更新。
- [ ] 暂停态与存储健康色（橙/红）可同时呈现，互不覆盖。
```

- [ ] **Step 7: 全量门禁 + 提交**

Run: `Scripts/verify.sh`
Expected: 通过。

```bash
git add Sources/ClipboardApp/StatusBar/StatusBarController.swift Sources/ClipboardApp/App/AppDelegate.swift Tests/ClipboardAppTests/StatusBarControllerTests.swift docs/manual-acceptance-checklist.md
git commit -m "feat: option-click status bar shortcuts and paused-state icon"
```

---

### Task 7: 粘贴后保留面板

**Files:**
- Modify: `Sources/ClipboardApp/AppSettings.swift`（新 key + 访问器）
- Modify: `Sources/ClipboardApp/Settings/GeneralSettingsView.swift`（QuickPanel 行为区新增 Toggle）
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelController.swift`（注入 `keepOpenAfterPaste` 闭包；submit/copy/number/plain-text 路径条件化 `hide()`；`show()` 时按设置调整 `hidesOnDeactivate`）
- Test: `Tests/ClipboardAppTests/QuickPanelControllerPresentationTests.swift`（扩展现有 harness）
- Modify: `docs/manual-acceptance-checklist.md`

**Interfaces:**
- Produces: `ClipboardAppSettings.quickPanelKeepOpenAfterPaste(defaults:) -> Bool`、`quickPanelKeepOpenAfterPasteKey = "quickPanel.keepOpenAfterPaste"`；`QuickPanelController.init` 新增 `keepOpenAfterPaste: @escaping () -> Bool = { ClipboardAppSettings.quickPanelKeepOpenAfterPaste() }` 参数（带默认值，既有调用方兼容）。

- [ ] **Step 1: 写失败测试**

在 `Tests/ClipboardAppTests/QuickPanelControllerPresentationTests.swift` 追加。该文件已有 `makePresentationState(store:payloadStore:pasteboard:eventPoster:)`、`makePresentationRecord()`、`InMemoryPayloadStore`、`waitUntil` 等 helper，panel 可见性断言先例为 `NSApp.windows.contains { $0.title == "Clipboard QuickPanel" && $0.isVisible }`：

```swift
    func testSubmitSelectionHidesPanelByDefault() async throws {
        let store = InMemoryHistoryStore()
        let payloadStore = InMemoryPayloadStore()
        let record = makePresentationRecord()
        _ = try await store.upsert(record)
        try await payloadStore.save(.text("keep-open default payload"), for: record.id)
        let state = makePresentationState(store: store, payloadStore: payloadStore)
        let controller = QuickPanelController(
            state: state,
            autoPasteEnabled: { false },
            keepOpenAfterPaste: { false }
        )

        controller.show()
        defer { controller.hide() }
        await state.refresh()
        controller.submitSelection()

        XCTAssertFalse(
            NSApp.windows.contains { $0.title == "Clipboard QuickPanel" && $0.isVisible },
            "Default behavior must hide the panel on submit.")
    }

    func testSubmitSelectionKeepsPanelVisibleWhenKeepOpenEnabled() async throws {
        let store = InMemoryHistoryStore()
        let payloadStore = InMemoryPayloadStore()
        let pasteboard = PresentationTestPasteboardWriter()
        let record = makePresentationRecord()
        _ = try await store.upsert(record)
        try await payloadStore.save(.text("keep-open submit payload"), for: record.id)
        let state = makePresentationState(store: store, payloadStore: payloadStore, pasteboard: pasteboard)
        let controller = QuickPanelController(
            state: state,
            autoPasteEnabled: { false },
            keepOpenAfterPaste: { true }
        )

        controller.show()
        defer { controller.hide() }
        await state.refresh()
        controller.submitSelection()
        try await waitUntil("submit selection to write the pasteboard") {
            pasteboard.lastText != nil
        }

        XCTAssertTrue(
            NSApp.windows.contains { $0.title == "Clipboard QuickPanel" && $0.isVisible },
            "Keep-open must leave the panel visible after submit completes.")
    }

    func testCopySelectionOnlyKeepsPanelVisibleWhenKeepOpenEnabled() async throws {
        let store = InMemoryHistoryStore()
        let payloadStore = InMemoryPayloadStore()
        let pasteboard = PresentationTestPasteboardWriter()
        let record = makePresentationRecord()
        _ = try await store.upsert(record)
        try await payloadStore.save(.text("keep-open copy payload"), for: record.id)
        let state = makePresentationState(store: store, payloadStore: payloadStore, pasteboard: pasteboard)
        let controller = QuickPanelController(
            state: state,
            keepOpenAfterPaste: { true }
        )

        controller.show()
        defer { controller.hide() }
        await state.refresh()
        controller.copySelectionOnly()
        try await waitUntil("copy-only selection to write the pasteboard") {
            pasteboard.lastText != nil
        }

        XCTAssertTrue(
            NSApp.windows.contains { $0.title == "Clipboard QuickPanel" && $0.isVisible },
            "Keep-open must leave the panel visible after copy-only completes.")
    }
```

（`keepOpenAfterPaste` 参数在 init 中带默认值，插入位置放在 `isAutoPasteAuthorized` 之后即可；若 init 参数顺序不同，按实际顺序传参，断言不变。）

- [ ] **Step 2: 跑测试确认失败**

Run: `swift test --filter QuickPanelControllerPresentationTests`
Expected: 编译失败（`keepOpenAfterPaste` 参数不存在）或新断言 FAIL。

- [ ] **Step 3: 实现设置项**

`AppSettings.swift` 的 `// MARK: - Existing` 区块追加：

```swift
    static let quickPanelKeepOpenAfterPasteKey = "quickPanel.keepOpenAfterPaste"

    static func quickPanelKeepOpenAfterPaste(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: quickPanelKeepOpenAfterPasteKey)
    }
```

`GeneralSettingsView.swift` 在粘贴行为 Section 内追加：

```swift
                Toggle("粘贴后保留面板", isOn: $keepOpenAfterPaste)
                Text("开启后，选择记录粘贴/复制完成时快捷面板保持打开，便于连续粘贴多条；Esc 随时关闭。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
```

配套属性：

```swift
    @AppStorage(ClipboardAppSettings.quickPanelKeepOpenAfterPasteKey)
    private var keepOpenAfterPaste: Bool = false
```

- [ ] **Step 4: 实现 QuickPanelController 改动**

init 新增注入闭包（对齐既有 `autoPasteEnabled` 等闭包属性的模式）：

```swift
    private let keepOpenAfterPaste: () -> Bool
```

init 参数 `keepOpenAfterPaste: @escaping () -> Bool = { ClipboardAppSettings.quickPanelKeepOpenAfterPaste() }`，赋值 `self.keepOpenAfterPaste = keepOpenAfterPaste`。

`show(trigger:)` 中 `self.panel = panel` 之后追加（设置可运行期变更，每次展示时重新应用）：

```swift
        panel.hidesOnDeactivate = !keepOpenAfterPaste()
```

`submitSelection()` 替换为：

```swift
    func submitSelection() {
        let targetApplication = previousApplication
        let autoPaste = autoPasteEnabled()
        if autoPaste && !isAutoPasteAuthorized() {
            state.reportAutoPasteRequiresAccessibilityPermission()
            return
        }

        let keepOpen = keepOpenAfterPaste()
        if !keepOpen {
            hide()
        }
        activatePreviousApplication(targetApplication)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            await state.selectCurrent(autoPaste: autoPaste)
            if keepOpen {
                await state.refresh()
            }
        }
    }
```

`copySelectionOnly()`、`pasteHistoryShortcut(number:)`、`pastePlainTextSelection()` 中的 `hide()` 同样改为 `if !keepOpenAfterPaste() { hide() }`（各自的 `activatePreviousApplication` 与 sleep 逻辑保持不变；keep-open 时同样在粘贴完成后 `await state.refresh()`）。

- [ ] **Step 5: 跑测试确认通过**

Run: `swift test --filter QuickPanelControllerPresentationTests`
Expected: 全部 PASS（含既有 presentation 测试）。

- [ ] **Step 6: 更新手工验收清单（含降级路径验证项）**

```markdown
- [ ] 开启"粘贴后保留面板"后：自动粘贴模式下 Return 粘贴成功，目标 App 收到内容且面板保持可见。
- [ ] 同设置下"仅复制"模式：选择后面板保持可见，手动 Cmd+V 粘贴成功。
- [ ] 关闭该设置后恢复现状：粘贴后面板关闭。
- [ ] 保留面板时 Esc 关闭面板并归还焦点。
- [ ] （风险验证）自动粘贴 + 保留面板在 Terminal / 浏览器地址栏均能正确投递 Cmd+V；若不可靠，按 spec 降级为仅"仅复制"模式生效并在 spec 追记。
```

- [ ] **Step 7: 全量门禁 + 提交**

Run: `Scripts/verify.sh`
Expected: 通过。

```bash
git add Sources/ClipboardApp/AppSettings.swift Sources/ClipboardApp/Settings/GeneralSettingsView.swift Sources/ClipboardApp/QuickPanel/QuickPanelController.swift Tests/ClipboardAppTests/QuickPanelControllerPresentationTests.swift docs/manual-acceptance-checklist.md
git commit -m "feat: optional keep-panel-open-after-paste behavior"
```

---

### Task 8: 性能验证 + 稳定签名构建 + 整体验收准备

**Files:**
- Modify: `docs/manual-acceptance-checklist.md`（如有遗漏条目补齐）
- 产物: `dist/` 或 `.build/app-bundles/release/ClipboardApp.app`（稳定签名构建）

**Interfaces:**
- Consumes: Tasks 1–7 的全部产出。

- [ ] **Step 1: 搜索性能基准**

Run: `Scripts/benchmark-maccy-replacement.sh`
Expected: 报告生成；搜索相关指标相对上一次报告无量级退化（fuzzy 打分为纯内存 Character 数组操作）。若搜索指标明显退化（>2x），按 spec 降级路径把 fuzzy 候选集限制为最近 1 万条，并在 spec `切片 2` 追记取舍后重跑。

- [ ] **Step 2: 全量门禁**

Run: `Scripts/verify.sh && git diff --check`
Expected: 全部通过，无空白错误。

- [ ] **Step 3: 稳定签名构建**

```bash
CODE_SIGN_KEYCHAIN="$HOME/Library/Keychains/clipboard-signing.keychain-db" \
LOCAL_CODE_SIGN_IDENTITY="ClipboardApp Local Code Signing" \
REQUIRE_STABLE_CODE_SIGNING=1 \
Scripts/build-app-bundle.sh
codesign -dv --verbose=4 .build/app-bundles/release/ClipboardApp.app
```

Expected: `Authority=ClipboardApp Local Code Signing`。

- [ ] **Step 4: 提示用户执行手工验收**

汇总 Tasks 1–7 在 `docs/manual-acceptance-checklist.md` 新增的全部未勾选条目，请用户用稳定签名构建逐项物理验收（开机自启需真实重启一次）。用户确认后逐项勾选并记录日期，单独提交：

```bash
git add docs/manual-acceptance-checklist.md
git commit -m "docs: record manual acceptance for Maccy daily parity slices"
```
