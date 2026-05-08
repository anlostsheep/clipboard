# 剪贴板历史持久化存储 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `HistoryStore` / `ClipboardPayloadStore` 从内存实现迁移到 SQLite + 文件 blob，使剪贴板历史在应用退出后保留，并实现双堡垒淘汰、Layer 1 装饰器自愈、Layer 2 用户策略。

**Architecture:** 装饰器模式分离自愈逻辑：`SelfHealingHistoryStore`（包装任意 HistoryStore，处理 `StorageError.full` 重试）+ `SQLiteHistoryStore`（仅做 C API 翻译）。Payload 二进制走文件系统，元数据走 SQLite WAL。`AppServices` 启动失败时降级为 `InMemoryHistoryStore` 并显式提示用户。

**Tech Stack:** Swift 5.10、SwiftUI、AppKit、Swift Concurrency (actor/async)、`import SQLite3`（系统 module，零三方依赖）、XCTest、macOS 14+

**Spec:** `docs/superpowers/specs/2026-05-08-persistent-storage-design.md`

**Verification:** 每个 phase 末尾运行 `Scripts/verify.sh`；最终任务运行手工验收清单。

---

## Phase A：协议演进与基础测试

### Task 1: 扩展 HistoryStore 协议（StorageError、count、removeAll、evictOldest，全部 throws）

**Files:**
- Modify: `Sources/ClipboardCore/Storage/HistoryStore.swift`

**Spec ref:** §2 协议变更

- [ ] **Step 1: 在 HistoryStore.swift 顶部新增 StorageError 枚举**

打开 `Sources/ClipboardCore/Storage/HistoryStore.swift`，在 `import Foundation` 之后插入：

```swift
public enum StorageError: Error, Equatable {
  case full
  case fullAndCannotEvict
  case underlying(String)
}
```

- [ ] **Step 2: 重写 HistoryStore 协议（全部 throws + 新方法）**

替换协议定义：

```swift
public protocol HistoryStore: Sendable {
  func upsert(_ record: ClipboardRecord) async throws -> ClipboardRecord
  func fetchAll() async throws -> [ClipboardRecord]
  func fetchPage(query: String, limit: Int) async throws -> [ClipboardRecord]
  func count() async throws -> Int
  func removeAll() async throws
  /// 删除最旧 ceil(N * percent) 条非豁免记录（is_pinned=0 AND is_favorite=0 AND retention_exempt=0）。
  /// 返回实际删除数；若没有可删记录返回 0。
  func evictOldest(percent: Double) async throws -> Int
}
```

- [ ] **Step 3: 更新 InMemoryHistoryStore 同步签名 + 新方法**

替换整个 `InMemoryHistoryStore` actor 实现：

```swift
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

  public func fetchAll() async throws -> [ClipboardRecord] {
    recordsByHash.values.sorted { $0.lastCopiedAt > $1.lastCopiedAt }
  }

  public func fetchPage(query: String, limit: Int) async throws -> [ClipboardRecord] {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let all = try await fetchAll()
    let filtered = normalized.isEmpty ? all : all.filter { record in
      record.title.lowercased().contains(normalized) ||
        (record.plainTextPreview?.lowercased().contains(normalized) ?? false) ||
        (record.sourceAppName?.lowercased().contains(normalized) ?? false)
    }
    return Array(filtered.prefix(max(0, limit)))
  }

  public func count() async throws -> Int {
    recordsByHash.count
  }

  public func removeAll() async throws {
    recordsByHash.removeAll()
  }

  public func evictOldest(percent: Double) async throws -> Int {
    let candidates = recordsByHash.values
      .filter { !$0.isPinned && !$0.isFavorite && !$0.retentionExempt }
      .sorted { $0.lastCopiedAt < $1.lastCopiedAt }
    guard !candidates.isEmpty else { return 0 }
    let target = max(1, Int((Double(candidates.count) * percent).rounded(.up)))
    let toRemove = candidates.prefix(target)
    for record in toRemove {
      recordsByHash.removeValue(forKey: record.contentHash)
    }
    return toRemove.count
  }
}
```

- [ ] **Step 4: 编译验证**

Run: `swift build`

Expected: 编译错误若干，集中在调用 `fetchAll` / `fetchPage` 的位置缺 `try`。这是预期的，下一个 task 修复。

不要继续修复，先 commit 这一步的协议变更：

- [ ] **Step 5: Commit**

```bash
git add Sources/ClipboardCore/Storage/HistoryStore.swift
git commit -m "$(cat <<'EOF'
feat(storage): 扩展 HistoryStore 协议加入 throws 与淘汰能力

- 新增 StorageError 枚举（full / fullAndCannotEvict / underlying）
- fetchAll / fetchPage 升级为 throws
- 协议新增 count() / removeAll() / evictOldest(percent:)
- InMemoryHistoryStore 同步实现新增方法

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: 修复 throws 调用方的编译错误

**Files:**
- Modify: `Sources/ClipboardCore/UI/QuickPanelViewModel.swift:28`
- Modify: `Sources/ClipboardApp/Settings/HistorySettingsView.swift:35`
- Modify: `Tests/ClipboardCoreTests/ClipboardIngestServiceTests.swift:20,41`

**Spec ref:** §2 协议变更

- [ ] **Step 1: 修复 QuickPanelViewModel.refresh**

打开 `Sources/ClipboardCore/UI/QuickPanelViewModel.swift`，把 `refresh(query:)` 改为：

```swift
public func refresh(query: String) async {
  refreshGeneration += 1
  let generation = refreshGeneration
  let refreshedItems = (try? await store.fetchPage(query: query, limit: pageLimit)) ?? []

  guard generation == refreshGeneration else {
    return
  }

  items = refreshedItems
  selectedIndex = items.isEmpty ? 0 : min(selectedIndex, items.count - 1)
}
```

> 选 `try?` + `?? []` 而不是抛出错误，是因为 QuickPanel 的搜索路径不应该因为底层临时错误而中断 UI。错误已经在 store 内部记日志。

- [ ] **Step 2: 修复 HistorySettingsView**

打开 `Sources/ClipboardApp/Settings/HistorySettingsView.swift`，把 onAppear 内的 Task 改为：

```swift
.onAppear {
    Task { recordCount = (try? await store.count()) ?? 0 }
}
```

并在文件顶部 `let store: InMemoryHistoryStore` 暂时保留（task 19 才改协议）。

- [ ] **Step 3: 修复 ClipboardIngestServiceTests**

打开 `Tests/ClipboardCoreTests/ClipboardIngestServiceTests.swift`，第 20 和 41 行的 `await store.fetchAll()` 改为 `try await store.fetchAll()`，并确保所属 test 函数签名是 `async throws`（如果原本只是 `async`，加上 `throws`）。

- [ ] **Step 4: 编译并跑所有测试**

Run: `swift build && swift test`

Expected: 全部通过。

- [ ] **Step 5: Commit**

```bash
git add Sources/ClipboardCore/UI/QuickPanelViewModel.swift \
       Sources/ClipboardApp/Settings/HistorySettingsView.swift \
       Tests/ClipboardCoreTests/ClipboardIngestServiceTests.swift
git commit -m "$(cat <<'EOF'
fix(storage): 适配 HistoryStore throws 协议变更

- QuickPanelViewModel.refresh 用 try? 容错
- HistorySettingsView 通过 count() 获取条数
- ClipboardIngestServiceTests 加 throws 标注

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: 把 ClipboardPayloadStore 升级为 throws

**Files:**
- Modify: `Sources/ClipboardCore/Storage/HistoryStore.swift`（含 ClipboardPayloadStore / InMemoryPayloadStore）
- Modify: `Sources/ClipboardCore/Ingest/ClipboardCaptureCoordinator.swift:31`
- Modify: 任何调用 `payloadStore.save` / `loadPayload` 的位置

**Spec ref:** §2 模块边界（payloadStore 与 historyStore 同样需要支持失败）

- [ ] **Step 1: 修改协议定义**

在 `Sources/ClipboardCore/Storage/HistoryStore.swift` 找到 `ClipboardPayloadStore` 协议，改为：

```swift
public protocol ClipboardPayloadStore: Sendable {
  func save(_ payload: ClipboardPayload, for recordID: UUID) async throws
  func loadPayload(for recordID: UUID) async throws -> ClipboardPayload?
  /// 删除指定记录的 payload 文件，幂等，文件不存在不报错
  func delete(for recordID: UUID) async throws
}
```

- [ ] **Step 2: 更新 InMemoryPayloadStore**

```swift
public actor InMemoryPayloadStore: ClipboardPayloadStore {
  private var payloadsByRecordID: [UUID: ClipboardPayload] = [:]

  public init() {}

  public func save(_ payload: ClipboardPayload, for recordID: UUID) async throws {
    payloadsByRecordID[recordID] = payload
  }

  public func loadPayload(for recordID: UUID) async throws -> ClipboardPayload? {
    payloadsByRecordID[recordID]
  }

  public func delete(for recordID: UUID) async throws {
    payloadsByRecordID.removeValue(forKey: recordID)
  }
}
```

- [ ] **Step 3: 修复 ClipboardCaptureCoordinator**

打开 `Sources/ClipboardCore/Ingest/ClipboardCaptureCoordinator.swift`，把第 31 行 `await payloadStore.save(...)` 改为：

```swift
try await payloadStore.save(capture.payload, for: record.id)
```

- [ ] **Step 4: 修复 QuickPanelState**

打开 `Sources/ClipboardApp/QuickPanel/QuickPanelState.swift`，搜索 `loadPayload`。所有调用点改为 `try? await payloadStore.loadPayload(for: ...)`，保持原 nil 容错语义。

- [ ] **Step 5: 编译并跑所有测试**

Run: `swift build && swift test`

Expected: 通过。

- [ ] **Step 6: Commit**

```bash
git add Sources/ClipboardCore/Storage/HistoryStore.swift \
       Sources/ClipboardCore/Ingest/ClipboardCaptureCoordinator.swift \
       Sources/ClipboardApp/QuickPanel/QuickPanelState.swift
git commit -m "$(cat <<'EOF'
feat(storage): ClipboardPayloadStore 升级为 throws + 新增 delete

为 SQLite 文件落盘实现做准备；InMemoryPayloadStore 无副作用。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: 编写 HistoryStoreConformanceTests 协议契约套件

**Files:**
- Create: `Tests/ClipboardCoreTests/HistoryStoreConformanceTests.swift`

**Spec ref:** §8 Protocol-conformance 测试

- [ ] **Step 1: 创建 conformance 测试文件**

写入 `Tests/ClipboardCoreTests/HistoryStoreConformanceTests.swift`：

```swift
import XCTest
@testable import ClipboardCore

/// 通用契约测试。SQLiteHistoryStore 之后会有自己的 XCTestCase 子类调用 runHistoryStoreConformance(_:)。
final class InMemoryHistoryStoreConformanceTests: XCTestCase {
  func testInMemoryConformsToContract() async throws {
    try await runHistoryStoreConformance { InMemoryHistoryStore() }
  }
}

func runHistoryStoreConformance<S: HistoryStore>(
  _ makeStore: () async throws -> S,
  file: StaticString = #file,
  line: UInt = #line
) async throws {
  try await assertUpsertDeduplicatesByHash(makeStore, file: file, line: line)
  try await assertFetchPageReturnsByRecency(makeStore, file: file, line: line)
  try await assertFetchPageFiltersByQuery(makeStore, file: file, line: line)
  try await assertCountReflectsRecords(makeStore, file: file, line: line)
  try await assertRemoveAllClearsStore(makeStore, file: file, line: line)
  try await assertEvictOldestRespectsExemptions(makeStore, file: file, line: line)
  try await assertEvictOldestRoundsUp(makeStore, file: file, line: line)
}

private func makeRecord(
  id: UUID = UUID(),
  hash: String,
  title: String = "title",
  lastCopiedAt: TimeInterval = 0,
  isPinned: Bool = false,
  isFavorite: Bool = false,
  retentionExempt: Bool = false
) -> ClipboardRecord {
  ClipboardRecord(
    id: id,
    contentHash: hash,
    primaryType: .text,
    title: title,
    plainTextPreview: title,
    sourceAppBundleId: nil,
    sourceAppName: "App",
    sourceDeviceHint: .local,
    createdAt: Date(timeIntervalSince1970: lastCopiedAt),
    lastCopiedAt: Date(timeIntervalSince1970: lastCopiedAt),
    copyCount: 1,
    isPinned: isPinned,
    isFavorite: isFavorite,
    groupIds: [],
    retentionExempt: retentionExempt,
    metadata: nil,
    pasteboardTypes: ["public.utf8-plain-text"]
  )
}

private func assertUpsertDeduplicatesByHash<S: HistoryStore>(
  _ make: () async throws -> S, file: StaticString, line: UInt
) async throws {
  let store = try await make()
  _ = try await store.upsert(makeRecord(hash: "h", lastCopiedAt: 1))
  _ = try await store.upsert(makeRecord(hash: "h", lastCopiedAt: 2))
  let total = try await store.count()
  XCTAssertEqual(total, 1, "Same content_hash 应去重", file: file, line: line)
}

private func assertFetchPageReturnsByRecency<S: HistoryStore>(
  _ make: () async throws -> S, file: StaticString, line: UInt
) async throws {
  let store = try await make()
  _ = try await store.upsert(makeRecord(hash: "a", title: "older", lastCopiedAt: 1))
  _ = try await store.upsert(makeRecord(hash: "b", title: "newer", lastCopiedAt: 2))
  let page = try await store.fetchPage(query: "", limit: 10)
  XCTAssertEqual(page.map(\.title), ["newer", "older"], file: file, line: line)
}

private func assertFetchPageFiltersByQuery<S: HistoryStore>(
  _ make: () async throws -> S, file: StaticString, line: UInt
) async throws {
  let store = try await make()
  _ = try await store.upsert(makeRecord(hash: "a", title: "alpha", lastCopiedAt: 1))
  _ = try await store.upsert(makeRecord(hash: "b", title: "beta", lastCopiedAt: 2))
  let page = try await store.fetchPage(query: "alp", limit: 10)
  XCTAssertEqual(page.map(\.title), ["alpha"], file: file, line: line)
}

private func assertCountReflectsRecords<S: HistoryStore>(
  _ make: () async throws -> S, file: StaticString, line: UInt
) async throws {
  let store = try await make()
  let initial = try await store.count()
  XCTAssertEqual(initial, 0, file: file, line: line)
  _ = try await store.upsert(makeRecord(hash: "a"))
  _ = try await store.upsert(makeRecord(hash: "b"))
  XCTAssertEqual(try await store.count(), 2, file: file, line: line)
}

private func assertRemoveAllClearsStore<S: HistoryStore>(
  _ make: () async throws -> S, file: StaticString, line: UInt
) async throws {
  let store = try await make()
  _ = try await store.upsert(makeRecord(hash: "a"))
  try await store.removeAll()
  XCTAssertEqual(try await store.count(), 0, file: file, line: line)
}

private func assertEvictOldestRespectsExemptions<S: HistoryStore>(
  _ make: () async throws -> S, file: StaticString, line: UInt
) async throws {
  let store = try await make()
  _ = try await store.upsert(makeRecord(hash: "a", title: "old-pinned", lastCopiedAt: 1, isPinned: true))
  _ = try await store.upsert(makeRecord(hash: "b", title: "old-fav", lastCopiedAt: 2, isFavorite: true))
  _ = try await store.upsert(makeRecord(hash: "c", title: "old-exempt", lastCopiedAt: 3, retentionExempt: true))
  _ = try await store.upsert(makeRecord(hash: "d", title: "candidate-old", lastCopiedAt: 4))
  _ = try await store.upsert(makeRecord(hash: "e", title: "candidate-new", lastCopiedAt: 5))

  let removed = try await store.evictOldest(percent: 0.5)  // ceil(2 * 0.5) = 1
  XCTAssertEqual(removed, 1, file: file, line: line)

  let remaining = try await store.fetchAll().map(\.title).sorted()
  XCTAssertEqual(remaining, ["candidate-new", "old-exempt", "old-fav", "old-pinned"], file: file, line: line)
}

private func assertEvictOldestRoundsUp<S: HistoryStore>(
  _ make: () async throws -> S, file: StaticString, line: UInt
) async throws {
  let store = try await make()
  _ = try await store.upsert(makeRecord(hash: "a", lastCopiedAt: 1))
  // 1 candidate × 0.10 = 0.1 → ceil = 1，应删除唯一一条
  let removed = try await store.evictOldest(percent: 0.10)
  XCTAssertEqual(removed, 1, file: file, line: line)
  XCTAssertEqual(try await store.count(), 0, file: file, line: line)
}
```

- [ ] **Step 2: 跑测试验证 baseline**

Run: `swift test --filter InMemoryHistoryStoreConformanceTests`

Expected: 全部通过（验证 InMemoryHistoryStore 满足契约）。

- [ ] **Step 3: Commit**

```bash
git add Tests/ClipboardCoreTests/HistoryStoreConformanceTests.swift
git commit -m "$(cat <<'EOF'
test(storage): 新增 HistoryStore 协议契约测试套件

InMemoryHistoryStore 作为 baseline 验证；后续 SQLiteHistoryStore 复用同套断言。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase B：SelfHealingHistoryStore 装饰器

### Task 5: 实现 SelfHealingHistoryStore + 测试

**Files:**
- Create: `Sources/ClipboardCore/Storage/SelfHealingHistoryStore.swift`
- Create: `Tests/ClipboardCoreTests/SelfHealingHistoryStoreTests.swift`

**Spec ref:** §5 Layer 1 装饰器自愈

- [ ] **Step 1: 编写失败测试 (FakeHistoryStore + 三个分支断言)**

写入 `Tests/ClipboardCoreTests/SelfHealingHistoryStoreTests.swift`：

```swift
import XCTest
@testable import ClipboardCore

final class SelfHealingHistoryStoreTests: XCTestCase {
  func testSucceedsAfterEvictingOnce() async throws {
    let fake = FakeHistoryStore()
    await fake.scheduleUpsertResults([.failure(StorageError.full), .success(())])
    await fake.setEvictResult(5)

    let store = SelfHealingHistoryStore(underlying: fake, maxRounds: 3, evictPercent: 0.10)
    let record = makeRecord(hash: "x")
    let result = try await store.upsert(record)

    XCTAssertEqual(result.contentHash, "x")
    XCTAssertEqual(await fake.evictCallCount, 1)
    XCTAssertEqual(await fake.upsertCallCount, 2)
  }

  func testThrowsFullAndCannotEvictWhenEvictReturnsZero() async throws {
    let fake = FakeHistoryStore()
    await fake.scheduleUpsertResults([.failure(StorageError.full)])
    await fake.setEvictResult(0)

    let store = SelfHealingHistoryStore(underlying: fake, maxRounds: 3, evictPercent: 0.10)

    do {
      _ = try await store.upsert(makeRecord(hash: "x"))
      XCTFail("应抛错")
    } catch StorageError.fullAndCannotEvict {
      // OK
    }
    XCTAssertEqual(await fake.evictCallCount, 1)
  }

  func testGivesUpAfterMaxRounds() async throws {
    let fake = FakeHistoryStore()
    await fake.scheduleUpsertResults([
      .failure(StorageError.full),
      .failure(StorageError.full),
      .failure(StorageError.full),
      .failure(StorageError.full)
    ])
    await fake.setEvictResult(3)

    let store = SelfHealingHistoryStore(underlying: fake, maxRounds: 3, evictPercent: 0.10)
    do {
      _ = try await store.upsert(makeRecord(hash: "x"))
      XCTFail("应抛错")
    } catch StorageError.full {
      // OK：耗尽后原样抛出 .full，留给 Layer 2 处理
    }
    XCTAssertEqual(await fake.evictCallCount, 3)
    XCTAssertEqual(await fake.upsertCallCount, 4)  // 初次 + 3 重试
  }

  func testForwardsOtherErrorsUntouched() async throws {
    let fake = FakeHistoryStore()
    await fake.scheduleUpsertResults([.failure(StorageError.underlying("disk read"))])

    let store = SelfHealingHistoryStore(underlying: fake, maxRounds: 3, evictPercent: 0.10)
    do {
      _ = try await store.upsert(makeRecord(hash: "x"))
      XCTFail("应抛错")
    } catch StorageError.underlying {
      // OK
    }
    XCTAssertEqual(await fake.evictCallCount, 0)
  }
}

actor FakeHistoryStore: HistoryStore {
  private var upsertScript: [Result<Void, Error>] = []
  private var evictReturn: Int = 0
  private(set) var upsertCallCount = 0
  private(set) var evictCallCount = 0
  private var stored: [String: ClipboardRecord] = [:]

  func scheduleUpsertResults(_ results: [Result<Void, Error>]) { upsertScript = results }
  func setEvictResult(_ n: Int) { evictReturn = n }

  func upsert(_ record: ClipboardRecord) async throws -> ClipboardRecord {
    upsertCallCount += 1
    if !upsertScript.isEmpty {
      let next = upsertScript.removeFirst()
      if case .failure(let err) = next { throw err }
    }
    stored[record.contentHash] = record
    return record
  }

  func fetchAll() async throws -> [ClipboardRecord] { Array(stored.values) }
  func fetchPage(query: String, limit: Int) async throws -> [ClipboardRecord] {
    Array(stored.values.prefix(limit))
  }
  func count() async throws -> Int { stored.count }
  func removeAll() async throws { stored.removeAll() }
  func evictOldest(percent: Double) async throws -> Int {
    evictCallCount += 1
    return evictReturn
  }
}

private func makeRecord(hash: String) -> ClipboardRecord {
  ClipboardRecord(
    id: UUID(),
    contentHash: hash,
    primaryType: .text,
    title: hash,
    plainTextPreview: hash,
    sourceAppBundleId: nil,
    sourceAppName: nil,
    sourceDeviceHint: .local,
    createdAt: Date(timeIntervalSince1970: 0),
    lastCopiedAt: Date(timeIntervalSince1970: 0),
    copyCount: 1,
    isPinned: false,
    isFavorite: false,
    groupIds: [],
    retentionExempt: false,
    metadata: nil,
    pasteboardTypes: []
  )
}
```

- [ ] **Step 2: 跑测试验证失败**

Run: `swift test --filter SelfHealingHistoryStoreTests`

Expected: 编译失败 "cannot find 'SelfHealingHistoryStore' in scope"。

- [ ] **Step 3: 实现 SelfHealingHistoryStore**

写入 `Sources/ClipboardCore/Storage/SelfHealingHistoryStore.swift`：

```swift
import Foundation

/// 装饰器：监听底层 HistoryStore 的 StorageError.full，自动触发 evictOldest 重试。
/// 把"失败自愈"逻辑与 SQLite 实现解耦，便于测试与替换底层。
public actor SelfHealingHistoryStore: HistoryStore {
  private let underlying: any HistoryStore
  private let maxRounds: Int
  private let evictPercent: Double

  public init(underlying: any HistoryStore, maxRounds: Int = 3, evictPercent: Double = 0.10) {
    self.underlying = underlying
    self.maxRounds = maxRounds
    self.evictPercent = evictPercent
  }

  public func upsert(_ record: ClipboardRecord) async throws -> ClipboardRecord {
    var attempt = 0
    while true {
      do {
        return try await underlying.upsert(record)
      } catch StorageError.full {
        guard attempt < maxRounds else { throw StorageError.full }
        let removed = try await underlying.evictOldest(percent: evictPercent)
        if removed == 0 {
          throw StorageError.fullAndCannotEvict
        }
        attempt += 1
      }
    }
  }

  public func fetchAll() async throws -> [ClipboardRecord] {
    try await underlying.fetchAll()
  }

  public func fetchPage(query: String, limit: Int) async throws -> [ClipboardRecord] {
    try await underlying.fetchPage(query: query, limit: limit)
  }

  public func count() async throws -> Int {
    try await underlying.count()
  }

  public func removeAll() async throws {
    try await underlying.removeAll()
  }

  public func evictOldest(percent: Double) async throws -> Int {
    try await underlying.evictOldest(percent: percent)
  }
}
```

- [ ] **Step 4: 跑测试验证通过**

Run: `swift test --filter SelfHealingHistoryStoreTests`

Expected: 4 个测试全通过。

- [ ] **Step 5: 跑全量测试确保未引入回归**

Run: `swift test`

Expected: 全部通过。

- [ ] **Step 6: Commit**

```bash
git add Sources/ClipboardCore/Storage/SelfHealingHistoryStore.swift \
       Tests/ClipboardCoreTests/SelfHealingHistoryStoreTests.swift
git commit -m "$(cat <<'EOF'
feat(storage): 新增 SelfHealingHistoryStore 装饰器

Layer 1 自愈逻辑——遇到 StorageError.full 时调用底层 evictOldest 重试，
最多 maxRounds 轮。与 SQLite 实现解耦，可针对任意 HistoryStore 包装。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase C：SQLite 基础设施

### Task 6: ApplicationSupportPaths

**Files:**
- Create: `Sources/ClipboardCore/Storage/SQLite/ApplicationSupportPaths.swift`

**Spec ref:** §3 路径

- [ ] **Step 1: 创建路径解析模块**

写入 `Sources/ClipboardCore/Storage/SQLite/ApplicationSupportPaths.swift`：

```swift
import Foundation

/// 解析持久化数据存储位置。允许测试时注入临时目录。
public struct ApplicationSupportPaths: Sendable {
  public let baseDirectory: URL
  public let databaseFile: URL
  public let payloadsDirectory: URL

  public init(bundleIdentifier: String, customBase: URL? = nil) throws {
    let base: URL
    if let customBase {
      base = customBase
    } else {
      let support = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
      base = support.appendingPathComponent(bundleIdentifier, isDirectory: true)
    }
    self.baseDirectory = base
    self.databaseFile = base.appendingPathComponent("clipboard.sqlite", isDirectory: false)
    self.payloadsDirectory = base.appendingPathComponent("payloads", isDirectory: true)
  }

  /// 确保 baseDirectory 与 payloadsDirectory 存在；若不可写则抛错。
  public func prepare() throws {
    let fm = FileManager.default
    if !fm.fileExists(atPath: baseDirectory.path) {
      try fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }
    if !fm.fileExists(atPath: payloadsDirectory.path) {
      try fm.createDirectory(at: payloadsDirectory, withIntermediateDirectories: true)
    }
    // 探测可写性
    let probe = baseDirectory.appendingPathComponent(".write-probe", isDirectory: false)
    try Data().write(to: probe, options: .atomic)
    try fm.removeItem(at: probe)
  }
}
```

- [ ] **Step 2: 编译验证**

Run: `swift build`

Expected: 通过。

- [ ] **Step 3: Commit**

```bash
git add Sources/ClipboardCore/Storage/SQLite/ApplicationSupportPaths.swift
git commit -m "$(cat <<'EOF'
feat(storage): 新增 ApplicationSupportPaths 路径解析

封装 ~/Library/Application Support/<bundle>/ 目录与 payloads/ 子目录创建，
内置写探测；支持注入 customBase 便于测试。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: SQLiteConnection thin wrapper

**Files:**
- Create: `Sources/ClipboardCore/Storage/SQLite/SQLiteConnection.swift`

**Spec ref:** §4 SQLiteHistoryStore 并发

- [ ] **Step 1: 创建 SQLiteConnection**

写入 `Sources/ClipboardCore/Storage/SQLite/SQLiteConnection.swift`：

```swift
import Foundation
import SQLite3

/// 对 sqlite3 C API 的薄包装，仅暴露本项目实际需要的接口。
/// 所有方法都假定调用方在同一隔离域内（actor 串行）调用，不做内部锁。
final class SQLiteConnection {
  private var db: OpaquePointer?

  static let SQLITE_TRANSIENT = unsafeBitCast(
    OpaquePointer(bitPattern: -1)!,
    to: sqlite3_destructor_type.self
  )

  init(path: String) throws {
    var handle: OpaquePointer?
    let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
    let rc = sqlite3_open_v2(path, &handle, flags, nil)
    guard rc == SQLITE_OK, let handle else {
      if let handle { sqlite3_close(handle) }
      throw StorageError.underlying("sqlite3_open_v2 rc=\(rc)")
    }
    self.db = handle
  }

  deinit {
    if let db { sqlite3_close(db) }
  }

  /// 执行无返回值 SQL（CREATE / PRAGMA / BEGIN / COMMIT 等）。
  func exec(_ sql: String) throws {
    guard let db else { throw StorageError.underlying("connection closed") }
    var errMsg: UnsafeMutablePointer<CChar>?
    let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
    if rc != SQLITE_OK {
      let msg = errMsg.map { String(cString: $0) } ?? "rc=\(rc)"
      sqlite3_free(errMsg)
      throw Self.translate(rc, message: msg)
    }
  }

  /// 准备 statement，由调用方负责 finalize（一般用 defer）。
  func prepare(_ sql: String) throws -> Statement {
    guard let db else { throw StorageError.underlying("connection closed") }
    var stmt: OpaquePointer?
    let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
    guard rc == SQLITE_OK, let stmt else {
      throw Self.translate(rc, message: "prepare rc=\(rc) sql=\(sql)")
    }
    return Statement(handle: stmt)
  }

  /// 标量查询（如 SELECT changes()）
  func intScalar(_ sql: String) throws -> Int {
    let stmt = try prepare(sql)
    defer { stmt.finalize() }
    let rc = sqlite3_step(stmt.handle)
    guard rc == SQLITE_ROW else { throw Self.translate(rc, message: "intScalar step rc=\(rc)") }
    return Int(sqlite3_column_int64(stmt.handle, 0))
  }

  static func translate(_ rc: Int32, message: String) -> StorageError {
    switch rc {
    case SQLITE_FULL, SQLITE_IOERR_WRITE, SQLITE_IOERR_NOMEM:
      return .full
    default:
      return .underlying("sqlite rc=\(rc) \(message)")
    }
  }
}

/// Prepared statement 的 RAII 包装。调用方持有引用并最终调 finalize()。
final class Statement {
  let handle: OpaquePointer
  private var finalized = false

  init(handle: OpaquePointer) {
    self.handle = handle
  }

  deinit {
    if !finalized { sqlite3_finalize(handle) }
  }

  func finalize() {
    if !finalized {
      sqlite3_finalize(handle)
      finalized = true
    }
  }

  func reset() {
    sqlite3_reset(handle)
    sqlite3_clear_bindings(handle)
  }

  func bindText(_ index: Int32, _ value: String?) {
    if let value {
      sqlite3_bind_text(handle, index, value, -1, SQLiteConnection.SQLITE_TRANSIENT)
    } else {
      sqlite3_bind_null(handle, index)
    }
  }

  func bindInt(_ index: Int32, _ value: Int) {
    sqlite3_bind_int64(handle, index, Int64(value))
  }

  func bindBool(_ index: Int32, _ value: Bool) {
    sqlite3_bind_int(handle, index, value ? 1 : 0)
  }

  func bindDouble(_ index: Int32, _ value: Double) {
    sqlite3_bind_double(handle, index, value)
  }

  func step() throws -> Int32 {
    let rc = sqlite3_step(handle)
    guard rc == SQLITE_ROW || rc == SQLITE_DONE else {
      throw SQLiteConnection.translate(rc, message: "step rc=\(rc)")
    }
    return rc
  }

  func columnText(_ index: Int32) -> String? {
    guard let cstr = sqlite3_column_text(handle, index) else { return nil }
    return String(cString: cstr)
  }

  func columnInt(_ index: Int32) -> Int {
    Int(sqlite3_column_int64(handle, index))
  }

  func columnBool(_ index: Int32) -> Bool {
    sqlite3_column_int(handle, index) != 0
  }

  func columnDouble(_ index: Int32) -> Double {
    sqlite3_column_double(handle, index)
  }

  func columnIsNull(_ index: Int32) -> Bool {
    sqlite3_column_type(handle, index) == SQLITE_NULL
  }
}
```

- [ ] **Step 2: 编译验证**

Run: `swift build`

Expected: 通过。

- [ ] **Step 3: Commit**

```bash
git add Sources/ClipboardCore/Storage/SQLite/SQLiteConnection.swift
git commit -m "$(cat <<'EOF'
feat(storage): 新增 SQLiteConnection 与 Statement 薄包装

封装 sqlite3 C API 至 Swift；统一错误翻译（SQLITE_FULL / IO 错误 → StorageError.full）；
RAII finalize；prepared statement 复用。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: SQLiteSchema with v0→v1 migration

**Files:**
- Create: `Sources/ClipboardCore/Storage/SQLite/SQLiteSchema.swift`

**Spec ref:** §3 Schema v1 + 迁移框架

- [ ] **Step 1: 创建 schema 模块**

写入 `Sources/ClipboardCore/Storage/SQLite/SQLiteSchema.swift`：

```swift
import Foundation

enum SQLiteSchema {
  static let currentVersion: Int = 1

  static func migrate(connection: SQLiteConnection) throws {
    let version = try connection.intScalar("PRAGMA user_version")
    if version < 1 {
      try migrateToV1(connection: connection)
    }
    // 未来 v2: if version < 2 { try migrateToV2(connection: connection) }
  }

  static func setupPragmas(connection: SQLiteConnection) throws {
    try connection.exec("PRAGMA journal_mode = WAL")
    try connection.exec("PRAGMA synchronous = NORMAL")
    try connection.exec("PRAGMA foreign_keys = ON")
    try connection.exec("PRAGMA auto_vacuum = INCREMENTAL")
  }

  private static func migrateToV1(connection: SQLiteConnection) throws {
    try connection.exec("""
      CREATE TABLE IF NOT EXISTS records (
          id              TEXT PRIMARY KEY,
          content_hash    TEXT NOT NULL UNIQUE,
          primary_type    TEXT NOT NULL,
          title           TEXT NOT NULL,
          plain_preview   TEXT,
          source_bundle   TEXT,
          source_app      TEXT,
          source_device   TEXT NOT NULL,
          created_at      REAL NOT NULL,
          last_copied_at  REAL NOT NULL,
          copy_count      INTEGER NOT NULL,
          is_pinned       INTEGER NOT NULL,
          is_favorite     INTEGER NOT NULL,
          group_ids_json  TEXT NOT NULL,
          retention_exempt INTEGER NOT NULL,
          metadata_json   TEXT,
          pasteboard_types_json TEXT NOT NULL,
          payload_ref     TEXT
      )
    """)
    try connection.exec("CREATE INDEX IF NOT EXISTS idx_last_copied_at ON records(last_copied_at DESC)")
    try connection.exec("CREATE INDEX IF NOT EXISTS idx_pinned_favorite ON records(is_pinned, is_favorite)")
    try connection.exec("PRAGMA user_version = 1")
  }

  /// 备份损坏 DB 文件，返回备份路径。
  static func backupCorruptedDatabase(at path: URL) throws -> URL {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
    let suffix = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "")
    let backup = path.deletingLastPathComponent()
      .appendingPathComponent("clipboard.corrupt.\(suffix).sqlite")
    try FileManager.default.moveItem(at: path, to: backup)
    return backup
  }
}
```

- [ ] **Step 2: 编译验证**

Run: `swift build`

Expected: 通过。

- [ ] **Step 3: Commit**

```bash
git add Sources/ClipboardCore/Storage/SQLite/SQLiteSchema.swift
git commit -m "$(cat <<'EOF'
feat(storage): 新增 SQLiteSchema 与 v0→v1 迁移

定义 records 表结构、索引、PRAGMA 设置；提供 backupCorruptedDatabase 工具。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase D：SQLitePayloadStore

### Task 9: SQLitePayloadStore 实现 + 测试

**Files:**
- Create: `Sources/ClipboardCore/Storage/SQLite/SQLitePayloadStore.swift`
- Create: `Tests/ClipboardCoreTests/SQLitePayloadStoreTests.swift`

**Spec ref:** §3 路径 + §4 写入路径

- [ ] **Step 1: 编写失败测试**

写入 `Tests/ClipboardCoreTests/SQLitePayloadStoreTests.swift`：

```swift
import XCTest
@testable import ClipboardCore

final class SQLitePayloadStoreTests: XCTestCase {
  var tempDir: URL!

  override func setUp() async throws {
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipboard-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: tempDir)
  }

  func testRoundTripText() async throws {
    let store = try SQLitePayloadStore(payloadsDirectory: tempDir)
    let id = UUID()
    try await store.save(.text("hello"), for: id)
    let loaded = try await store.loadPayload(for: id)
    XCTAssertEqual(loaded, .text("hello"))
  }

  func testRoundTripImage() async throws {
    let store = try SQLitePayloadStore(payloadsDirectory: tempDir)
    let id = UUID()
    let data = Data([0xFF, 0xD8, 0xFF, 0xE0])  // JPEG magic bytes
    try await store.save(.image(data: data, uti: "public.jpeg"), for: id)
    let loaded = try await store.loadPayload(for: id)
    XCTAssertEqual(loaded, .image(data: data, uti: "public.jpeg"))
  }

  func testRoundTripRichText() async throws {
    let store = try SQLitePayloadStore(payloadsDirectory: tempDir)
    let id = UUID()
    let rtf = Data("rtf-bytes".utf8)
    try await store.save(.richText(plainText: "plain", rtfData: rtf), for: id)
    let loaded = try await store.loadPayload(for: id)
    XCTAssertEqual(loaded, .richText(plainText: "plain", rtfData: rtf))
  }

  func testRoundTripFileURLs() async throws {
    let store = try SQLitePayloadStore(payloadsDirectory: tempDir)
    let id = UUID()
    let urls = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")]
    try await store.save(.fileURLs(urls), for: id)
    let loaded = try await store.loadPayload(for: id)
    XCTAssertEqual(loaded, .fileURLs(urls))
  }

  func testDeleteRemovesFile() async throws {
    let store = try SQLitePayloadStore(payloadsDirectory: tempDir)
    let id = UUID()
    try await store.save(.text("x"), for: id)
    try await store.delete(for: id)
    let loaded = try await store.loadPayload(for: id)
    XCTAssertNil(loaded)
  }

  func testDeleteIsIdempotent() async throws {
    let store = try SQLitePayloadStore(payloadsDirectory: tempDir)
    try await store.delete(for: UUID())  // 不应抛错
  }
}
```

- [ ] **Step 2: 跑测试验证失败**

Run: `swift test --filter SQLitePayloadStoreTests`

Expected: 编译失败 "cannot find 'SQLitePayloadStore' in scope"。

- [ ] **Step 3: 实现 SQLitePayloadStore**

写入 `Sources/ClipboardCore/Storage/SQLite/SQLitePayloadStore.swift`：

```swift
import Foundation

public actor SQLitePayloadStore: ClipboardPayloadStore {
  private let payloadsDirectory: URL

  public init(payloadsDirectory: URL) throws {
    self.payloadsDirectory = payloadsDirectory
    let fm = FileManager.default
    if !fm.fileExists(atPath: payloadsDirectory.path) {
      try fm.createDirectory(at: payloadsDirectory, withIntermediateDirectories: true)
    }
  }

  public func save(_ payload: ClipboardPayload, for recordID: UUID) async throws {
    let envelope = PayloadEnvelope(payload: payload)
    let url = fileURL(for: recordID, extension: envelope.fileExtension)
    let tmpURL = url.appendingPathExtension("tmp")
    try envelope.encode().write(to: tmpURL, options: .atomic)
    if FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.removeItem(at: url)
    }
    try FileManager.default.moveItem(at: tmpURL, to: url)
  }

  public func loadPayload(for recordID: UUID) async throws -> ClipboardPayload? {
    let fm = FileManager.default
    let candidates = try fm.contentsOfDirectory(atPath: payloadsDirectory.path)
      .filter { $0.hasPrefix(recordID.uuidString) && !$0.hasSuffix(".tmp") }
    guard let name = candidates.first else { return nil }
    let url = payloadsDirectory.appendingPathComponent(name)
    let data = try Data(contentsOf: url)
    return try PayloadEnvelope.decode(data, filename: name)
  }

  public func delete(for recordID: UUID) async throws {
    let fm = FileManager.default
    let prefix = recordID.uuidString
    guard let entries = try? fm.contentsOfDirectory(atPath: payloadsDirectory.path) else { return }
    for entry in entries where entry.hasPrefix(prefix) {
      try? fm.removeItem(atPath: payloadsDirectory.appendingPathComponent(entry).path)
    }
  }

  /// 列出所有 payload 文件名（不含路径），供孤儿扫描使用。
  public func listAllFilenames() throws -> Set<String> {
    let fm = FileManager.default
    guard let entries = try? fm.contentsOfDirectory(atPath: payloadsDirectory.path) else {
      return []
    }
    return Set(entries.filter { !$0.hasSuffix(".tmp") })
  }

  /// 给定文件名集合，删除目录下不在集合中的文件（孤儿）。
  public func removeOrphans(keeping referenced: Set<String>) throws -> Int {
    let all = try listAllFilenames()
    let orphans = all.subtracting(referenced)
    let fm = FileManager.default
    var removed = 0
    for name in orphans {
      try? fm.removeItem(at: payloadsDirectory.appendingPathComponent(name))
      removed += 1
    }
    return removed
  }

  private func fileURL(for recordID: UUID, extension ext: String) -> URL {
    payloadsDirectory.appendingPathComponent("\(recordID.uuidString).\(ext)")
  }
}

/// 单一 payload 文件的封装格式。
private struct PayloadEnvelope: Codable {
  let kind: Kind
  let textPlain: String?
  let richTextPlain: String?
  let richTextRTF: Data?
  let imageData: Data?
  let imageUTI: String?
  let fileURLStrings: [String]?

  enum Kind: String, Codable { case text, richText, image, fileURLs }

  init(payload: ClipboardPayload) {
    switch payload {
    case .text(let s):
      kind = .text
      textPlain = s
      richTextPlain = nil; richTextRTF = nil; imageData = nil; imageUTI = nil; fileURLStrings = nil
    case .richText(let plain, let rtf):
      kind = .richText
      richTextPlain = plain; richTextRTF = rtf
      textPlain = nil; imageData = nil; imageUTI = nil; fileURLStrings = nil
    case .image(let data, let uti):
      kind = .image
      imageData = data; imageUTI = uti
      textPlain = nil; richTextPlain = nil; richTextRTF = nil; fileURLStrings = nil
    case .fileURLs(let urls):
      kind = .fileURLs
      fileURLStrings = urls.map(\.absoluteString)
      textPlain = nil; richTextPlain = nil; richTextRTF = nil; imageData = nil; imageUTI = nil
    }
  }

  var fileExtension: String {
    switch kind {
    case .text: return "txt"
    case .richText: return "rtf"
    case .image:
      switch imageUTI {
      case "public.jpeg": return "jpg"
      case "public.png": return "png"
      case "public.tiff": return "tiff"
      default: return "bin"
      }
    case .fileURLs: return "fileurls.json"
    }
  }

  func encode() throws -> Data {
    try JSONEncoder().encode(self)
  }

  static func decode(_ data: Data, filename: String) throws -> ClipboardPayload {
    let envelope = try JSONDecoder().decode(PayloadEnvelope.self, from: data)
    switch envelope.kind {
    case .text:
      return .text(envelope.textPlain ?? "")
    case .richText:
      return .richText(plainText: envelope.richTextPlain ?? "", rtfData: envelope.richTextRTF ?? Data())
    case .image:
      return .image(data: envelope.imageData ?? Data(), uti: envelope.imageUTI ?? "public.data")
    case .fileURLs:
      let urls = (envelope.fileURLStrings ?? []).compactMap(URL.init(string:))
      return .fileURLs(urls)
    }
  }
}
```

- [ ] **Step 4: 跑测试验证通过**

Run: `swift test --filter SQLitePayloadStoreTests`

Expected: 6 个测试全通过。

- [ ] **Step 5: Commit**

```bash
git add Sources/ClipboardCore/Storage/SQLite/SQLitePayloadStore.swift \
       Tests/ClipboardCoreTests/SQLitePayloadStoreTests.swift
git commit -m "$(cat <<'EOF'
feat(storage): 新增 SQLitePayloadStore 文件落盘实现

每条 payload → payloads/<uuid>.<ext>，原子 rename 写入；
PayloadEnvelope JSON 封装四种 ClipboardPayload；
listAllFilenames + removeOrphans 服务孤儿扫描。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase E：SQLiteHistoryStore

### Task 10: SQLiteHistoryStore 基础 CRUD + 内存索引

**Files:**
- Create: `Sources/ClipboardCore/Storage/SQLite/SQLiteHistoryStore.swift`
- Create: `Tests/ClipboardCoreTests/SQLiteHistoryStoreTests.swift`

**Spec ref:** §4 写入路径 + 内存索引

- [ ] **Step 1: 编写失败测试（基础 CRUD + 冷启动恢复）**

写入 `Tests/ClipboardCoreTests/SQLiteHistoryStoreTests.swift`：

```swift
import XCTest
@testable import ClipboardCore

final class SQLiteHistoryStoreTests: XCTestCase {
  var tempDir: URL!

  override func setUp() async throws {
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipboard-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: tempDir)
  }

  func makeStore() throws -> SQLiteHistoryStore {
    try SQLiteHistoryStore(databaseFile: tempDir.appendingPathComponent("test.sqlite"))
  }

  func testColdStartRecoversRecords() async throws {
    let storeA = try makeStore()
    _ = try await storeA.upsert(makeRecord(hash: "a", title: "alpha"))
    _ = try await storeA.upsert(makeRecord(hash: "b", title: "beta"))
    await storeA.close()

    let storeB = try makeStore()
    let titles = try await storeB.fetchAll().map(\.title).sorted()
    XCTAssertEqual(titles, ["alpha", "beta"])
  }

  func testCountReflectsInsertions() async throws {
    let store = try makeStore()
    XCTAssertEqual(try await store.count(), 0)
    _ = try await store.upsert(makeRecord(hash: "a"))
    XCTAssertEqual(try await store.count(), 1)
  }
}

private func makeRecord(hash: String, title: String = "title") -> ClipboardRecord {
  ClipboardRecord(
    id: UUID(),
    contentHash: hash,
    primaryType: .text,
    title: title,
    plainTextPreview: title,
    sourceAppBundleId: nil,
    sourceAppName: "App",
    sourceDeviceHint: .local,
    createdAt: Date(timeIntervalSince1970: 0),
    lastCopiedAt: Date(timeIntervalSince1970: 0),
    copyCount: 1,
    isPinned: false,
    isFavorite: false,
    groupIds: [],
    retentionExempt: false,
    metadata: nil,
    pasteboardTypes: ["public.utf8-plain-text"]
  )
}
```

- [ ] **Step 2: 跑测试验证失败**

Run: `swift test --filter SQLiteHistoryStoreTests`

Expected: 编译失败 "cannot find 'SQLiteHistoryStore' in scope"。

- [ ] **Step 3: 实现 SQLiteHistoryStore（基础部分）**

写入 `Sources/ClipboardCore/Storage/SQLite/SQLiteHistoryStore.swift`：

```swift
import Foundation
import SQLite3
import os.log

public actor SQLiteHistoryStore: HistoryStore {
  private let connection: SQLiteConnection
  private var indexByHash: [String: ClipboardRecord] = [:]
  private static let logger = Logger(subsystem: "clipboard.storage", category: "SQLiteHistoryStore")

  public init(databaseFile: URL) throws {
    let dir = databaseFile.deletingLastPathComponent()
    let fm = FileManager.default
    if !fm.fileExists(atPath: dir.path) {
      try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    self.connection = try SQLiteConnection(path: databaseFile.path)
    try SQLiteSchema.setupPragmas(connection: connection)
    try SQLiteSchema.migrate(connection: connection)
    Task { await self.loadIntoMemoryIndex() }
  }

  public func close() {
    // SQLiteConnection 持有的 db handle 在 deinit 时关闭；提前 close 仅用于测试驱动冷启动。
    indexByHash.removeAll()
  }

  public func upsert(_ record: ClipboardRecord) async throws -> ClipboardRecord {
    if let existing = indexByHash[record.contentHash] {
      var updated = existing
      updated.copyCount += 1
      updated.lastCopiedAt = record.lastCopiedAt
      try writeRecord(updated)
      indexByHash[updated.contentHash] = updated
      return updated
    }

    try writeRecord(record)
    indexByHash[record.contentHash] = record
    return record
  }

  public func fetchAll() async throws -> [ClipboardRecord] {
    indexByHash.values.sorted { $0.lastCopiedAt > $1.lastCopiedAt }
  }

  public func fetchPage(query: String, limit: Int) async throws -> [ClipboardRecord] {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let all = try await fetchAll()
    let filtered = normalized.isEmpty ? all : all.filter { record in
      record.title.lowercased().contains(normalized) ||
        (record.plainTextPreview?.lowercased().contains(normalized) ?? false) ||
        (record.sourceAppName?.lowercased().contains(normalized) ?? false)
    }
    return Array(filtered.prefix(max(0, limit)))
  }

  public func count() async throws -> Int {
    indexByHash.count
  }

  public func removeAll() async throws {
    try connection.exec("DELETE FROM records")
    indexByHash.removeAll()
  }

  public func evictOldest(percent: Double) async throws -> Int {
    // 占位：Task 11 实现真正逻辑
    return 0
  }

  // MARK: - Internal

  private func loadIntoMemoryIndex() async {
    do {
      let stmt = try connection.prepare("SELECT * FROM records")
      defer { stmt.finalize() }
      while try stmt.step() == SQLITE_ROW {
        let record = try decodeRecord(from: stmt)
        indexByHash[record.contentHash] = record
      }
      Self.logger.info("loaded \(self.indexByHash.count) records into memory index")
    } catch {
      Self.logger.error("loadIntoMemoryIndex failed: \(String(describing: error))")
    }
  }

  private func writeRecord(_ r: ClipboardRecord) throws {
    let sql = """
      INSERT INTO records (
        id, content_hash, primary_type, title, plain_preview,
        source_bundle, source_app, source_device,
        created_at, last_copied_at, copy_count,
        is_pinned, is_favorite, group_ids_json, retention_exempt,
        metadata_json, pasteboard_types_json, payload_ref
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(content_hash) DO UPDATE SET
        copy_count = copy_count + 1,
        last_copied_at = excluded.last_copied_at
    """
    let stmt = try connection.prepare(sql)
    defer { stmt.finalize() }
    stmt.bindText(1, r.id.uuidString)
    stmt.bindText(2, r.contentHash)
    stmt.bindText(3, r.primaryType.rawValue)
    stmt.bindText(4, r.title)
    stmt.bindText(5, r.plainTextPreview)
    stmt.bindText(6, r.sourceAppBundleId)
    stmt.bindText(7, r.sourceAppName)
    stmt.bindText(8, r.sourceDeviceHint.rawValue)
    stmt.bindDouble(9, r.createdAt.timeIntervalSince1970)
    stmt.bindDouble(10, r.lastCopiedAt.timeIntervalSince1970)
    stmt.bindInt(11, r.copyCount)
    stmt.bindBool(12, r.isPinned)
    stmt.bindBool(13, r.isFavorite)
    stmt.bindText(14, try Self.encodeJSON(r.groupIds))
    stmt.bindBool(15, r.retentionExempt)
    stmt.bindText(16, try Self.encodeJSONOptional(r.metadata))
    stmt.bindText(17, try Self.encodeJSON(Array(r.pasteboardTypes)))
    stmt.bindText(18, nil)  // payload_ref 留空，由 PayloadStore 单独管理
    _ = try stmt.step()
  }

  private func decodeRecord(from stmt: Statement) throws -> ClipboardRecord {
    guard let idString = stmt.columnText(0), let id = UUID(uuidString: idString) else {
      throw StorageError.underlying("invalid id column")
    }
    return ClipboardRecord(
      id: id,
      contentHash: stmt.columnText(1) ?? "",
      primaryType: ClipboardContentType(rawValue: stmt.columnText(2) ?? "text") ?? .text,
      title: stmt.columnText(3) ?? "",
      plainTextPreview: stmt.columnText(4),
      sourceAppBundleId: stmt.columnText(5),
      sourceAppName: stmt.columnText(6),
      sourceDeviceHint: ClipboardSourceDeviceHint(rawValue: stmt.columnText(7) ?? "local") ?? .local,
      createdAt: Date(timeIntervalSince1970: stmt.columnDouble(8)),
      lastCopiedAt: Date(timeIntervalSince1970: stmt.columnDouble(9)),
      copyCount: stmt.columnInt(10),
      isPinned: stmt.columnBool(11),
      isFavorite: stmt.columnBool(12),
      groupIds: try Self.decodeJSON([String].self, from: stmt.columnText(13) ?? "[]"),
      retentionExempt: stmt.columnBool(14),
      metadata: try Self.decodeJSONOptional(LargeTextMetadata.self, from: stmt.columnText(15)),
      pasteboardTypes: Set(try Self.decodeJSON([String].self, from: stmt.columnText(16) ?? "[]"))
    )
  }

  private static func encodeJSON<T: Encodable>(_ value: T) throws -> String {
    let data = try JSONEncoder().encode(value)
    return String(data: data, encoding: .utf8) ?? "null"
  }

  private static func encodeJSONOptional<T: Encodable>(_ value: T?) throws -> String? {
    guard let value else { return nil }
    return try encodeJSON(value)
  }

  private static func decodeJSON<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
    try JSONDecoder().decode(type, from: Data(text.utf8))
  }

  private static func decodeJSONOptional<T: Decodable>(_ type: T.Type, from text: String?) throws -> T? {
    guard let text else { return nil }
    return try JSONDecoder().decode(type, from: Data(text.utf8))
  }
}
```

> 注意：`init` 内调用 `Task { await loadIntoMemoryIndex() }` 是 fire-and-forget。冷启动测试为了规避竞态，先在 actor 内同步加载——下一步 Step 4 修复。

- [ ] **Step 4: 修复初始化竞态：把 loadIntoMemoryIndex 改为同步**

把 `loadIntoMemoryIndex` 改名为 `loadIntoMemoryIndexSync`，在 init 内 nonisolated 直接调用：

替换 `init`：

```swift
public init(databaseFile: URL) throws {
  let dir = databaseFile.deletingLastPathComponent()
  let fm = FileManager.default
  if !fm.fileExists(atPath: dir.path) {
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
  }
  self.connection = try SQLiteConnection(path: databaseFile.path)
  try SQLiteSchema.setupPragmas(connection: connection)
  try SQLiteSchema.migrate(connection: connection)
  self.indexByHash = try Self.loadInitialIndex(connection: connection)
}

private static func loadInitialIndex(connection: SQLiteConnection) throws -> [String: ClipboardRecord] {
  var index: [String: ClipboardRecord] = [:]
  let stmt = try connection.prepare("SELECT * FROM records")
  defer { stmt.finalize() }
  while try stmt.step() == SQLITE_ROW {
    let record = try decodeRecordStatic(from: stmt)
    index[record.contentHash] = record
  }
  logger.info("loaded \(index.count) records into memory index")
  return index
}

private static func decodeRecordStatic(from stmt: Statement) throws -> ClipboardRecord {
  // 重用 actor 内同名逻辑，复制粘贴避免 actor isolation 问题
  guard let idString = stmt.columnText(0), let id = UUID(uuidString: idString) else {
    throw StorageError.underlying("invalid id column")
  }
  return ClipboardRecord(
    id: id,
    contentHash: stmt.columnText(1) ?? "",
    primaryType: ClipboardContentType(rawValue: stmt.columnText(2) ?? "text") ?? .text,
    title: stmt.columnText(3) ?? "",
    plainTextPreview: stmt.columnText(4),
    sourceAppBundleId: stmt.columnText(5),
    sourceAppName: stmt.columnText(6),
    sourceDeviceHint: ClipboardSourceDeviceHint(rawValue: stmt.columnText(7) ?? "local") ?? .local,
    createdAt: Date(timeIntervalSince1970: stmt.columnDouble(8)),
    lastCopiedAt: Date(timeIntervalSince1970: stmt.columnDouble(9)),
    copyCount: stmt.columnInt(10),
    isPinned: stmt.columnBool(11),
    isFavorite: stmt.columnBool(12),
    groupIds: try decodeJSONStatic([String].self, from: stmt.columnText(13) ?? "[]"),
    retentionExempt: stmt.columnBool(14),
    metadata: try decodeJSONOptionalStatic(LargeTextMetadata.self, from: stmt.columnText(15)),
    pasteboardTypes: Set(try decodeJSONStatic([String].self, from: stmt.columnText(16) ?? "[]"))
  )
}

private static func decodeJSONStatic<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
  try JSONDecoder().decode(type, from: Data(text.utf8))
}

private static func decodeJSONOptionalStatic<T: Decodable>(_ type: T.Type, from text: String?) throws -> T? {
  guard let text else { return nil }
  return try JSONDecoder().decode(type, from: Data(text.utf8))
}
```

并把 `private func loadIntoMemoryIndex()` 整段删除（含 `Task { ... }` 调用）。

- [ ] **Step 5: 跑测试验证通过**

Run: `swift test --filter SQLiteHistoryStoreTests`

Expected: 2 个测试通过。

- [ ] **Step 6: Commit**

```bash
git add Sources/ClipboardCore/Storage/SQLite/SQLiteHistoryStore.swift \
       Tests/ClipboardCoreTests/SQLiteHistoryStoreTests.swift
git commit -m "$(cat <<'EOF'
feat(storage): 新增 SQLiteHistoryStore 基础 CRUD 与内存索引

upsert / fetchAll / fetchPage / count / removeAll 实现；
冷启动同步 SELECT * 重建 indexByHash；evictOldest 暂为占位（下一 task 实现）。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: 实现 evictOldest 与 enforceRetention

**Files:**
- Modify: `Sources/ClipboardCore/Storage/SQLite/SQLiteHistoryStore.swift`
- Modify: `Tests/ClipboardCoreTests/SQLiteHistoryStoreTests.swift`

**Spec ref:** §6 双堡垒 + evictOldest

- [ ] **Step 1: 在测试文件追加 retention 测试**

在 `Tests/ClipboardCoreTests/SQLiteHistoryStoreTests.swift` 内 `final class SQLiteHistoryStoreTests` 末尾追加：

```swift
  func testEnforceRetentionTrimsByCount() async throws {
    let store = try SQLiteHistoryStore(
      databaseFile: tempDir.appendingPathComponent("test.sqlite"),
      retentionPolicy: RetentionPolicy(maxCount: 3, maxAgeDays: 365)
    )
    for i in 1...5 {
      _ = try await store.upsert(makeRecord(hash: "h\(i)", title: "t\(i)"))
    }
    // 双堡垒应在最后一次 upsert 之后裁掉最旧 2 条
    let count = try await store.count()
    XCTAssertEqual(count, 3)
  }

  func testEnforceRetentionExemptsPinnedAndFavorite() async throws {
    let store = try SQLiteHistoryStore(
      databaseFile: tempDir.appendingPathComponent("test.sqlite"),
      retentionPolicy: RetentionPolicy(maxCount: 1, maxAgeDays: 365)
    )
    _ = try await store.upsert(makeRecord(hash: "pin", title: "p", isPinned: true))
    _ = try await store.upsert(makeRecord(hash: "fav", title: "f", isFavorite: true))
    _ = try await store.upsert(makeRecord(hash: "normal", title: "n"))
    // maxCount = 1 但豁免项不占配额：3 条全保留
    XCTAssertEqual(try await store.count(), 3)
  }

  func testEvictOldestReturnsCount() async throws {
    let store = try SQLiteHistoryStore(databaseFile: tempDir.appendingPathComponent("test.sqlite"))
    for i in 1...10 {
      _ = try await store.upsert(makeRecord(hash: "h\(i)", title: "t\(i)"))
    }
    let removed = try await store.evictOldest(percent: 0.20)
    XCTAssertEqual(removed, 2)  // ceil(10 * 0.2) = 2
    XCTAssertEqual(try await store.count(), 8)
  }
```

并把测试文件中的 `makeRecord(hash: title:)` helper 扩展为：

```swift
private func makeRecord(
  hash: String,
  title: String = "title",
  isPinned: Bool = false,
  isFavorite: Bool = false
) -> ClipboardRecord {
  ClipboardRecord(
    id: UUID(),
    contentHash: hash,
    primaryType: .text,
    title: title,
    plainTextPreview: title,
    sourceAppBundleId: nil,
    sourceAppName: "App",
    sourceDeviceHint: .local,
    createdAt: Date(timeIntervalSince1970: 0),
    lastCopiedAt: Date(timeIntervalSince1970: TimeInterval(hash.hashValue % 10000)),
    copyCount: 1,
    isPinned: isPinned,
    isFavorite: isFavorite,
    groupIds: [],
    retentionExempt: false,
    metadata: nil,
    pasteboardTypes: ["public.utf8-plain-text"]
  )
}
```

- [ ] **Step 2: 跑测试验证失败**

Run: `swift test --filter SQLiteHistoryStoreTests`

Expected: 编译失败 "RetentionPolicy not found" 或测试失败（count 不正确）。

- [ ] **Step 3: 在 SQLiteHistoryStore.swift 引入 RetentionPolicy + evictOldest 实现**

在 `Sources/ClipboardCore/Storage/SQLite/SQLiteHistoryStore.swift` 顶部新增：

```swift
public struct RetentionPolicy: Sendable {
  public let maxCount: Int
  public let maxAgeDays: Int

  public init(maxCount: Int = 5000, maxAgeDays: Int = 180) {
    self.maxCount = maxCount
    self.maxAgeDays = maxAgeDays
  }
}
```

修改 actor 定义增加 retention 字段并扩展 init：

```swift
public actor SQLiteHistoryStore: HistoryStore {
  private let connection: SQLiteConnection
  private let retentionPolicy: RetentionPolicy
  private var indexByHash: [String: ClipboardRecord] = [:]
  private static let logger = Logger(subsystem: "clipboard.storage", category: "SQLiteHistoryStore")

  public init(
    databaseFile: URL,
    retentionPolicy: RetentionPolicy = RetentionPolicy()
  ) throws {
    let dir = databaseFile.deletingLastPathComponent()
    let fm = FileManager.default
    if !fm.fileExists(atPath: dir.path) {
      try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    self.connection = try SQLiteConnection(path: databaseFile.path)
    self.retentionPolicy = retentionPolicy
    try SQLiteSchema.setupPragmas(connection: connection)
    try SQLiteSchema.migrate(connection: connection)
    self.indexByHash = try Self.loadInitialIndex(connection: connection)
  }
  // ... (其余保持不变)
}
```

- [ ] **Step 4: 实现 evictOldest 与 enforceRetention**

把 actor 内 `evictOldest` 占位实现替换为：

```swift
public func evictOldest(percent: Double) async throws -> Int {
  let candidates = indexByHash.values
    .filter { !$0.isPinned && !$0.isFavorite && !$0.retentionExempt }
    .sorted { $0.lastCopiedAt < $1.lastCopiedAt }
  guard !candidates.isEmpty else { return 0 }
  let target = max(1, Int((Double(candidates.count) * percent).rounded(.up)))
  let toRemove = Array(candidates.prefix(target))
  guard !toRemove.isEmpty else { return 0 }
  try deleteRecords(ids: toRemove.map(\.id))
  for record in toRemove {
    indexByHash.removeValue(forKey: record.contentHash)
  }
  try connection.exec("PRAGMA incremental_vacuum")
  return toRemove.count
}

private func deleteRecords(ids: [UUID]) throws {
  guard !ids.isEmpty else { return }
  try connection.exec("BEGIN IMMEDIATE")
  do {
    let stmt = try connection.prepare("DELETE FROM records WHERE id = ?")
    defer { stmt.finalize() }
    for id in ids {
      stmt.reset()
      stmt.bindText(1, id.uuidString)
      _ = try stmt.step()
    }
    try connection.exec("COMMIT")
  } catch {
    try? connection.exec("ROLLBACK")
    throw error
  }
}

private func enforceRetention() throws {
  // 双堡垒：(超天数) OR (超条数)
  let now = Date().timeIntervalSince1970
  let ageCutoff = now - Double(retentionPolicy.maxAgeDays * 86_400)
  let nonExempt = indexByHash.values
    .filter { !$0.isPinned && !$0.isFavorite && !$0.retentionExempt }
    .sorted { $0.lastCopiedAt > $1.lastCopiedAt }  // 新→旧

  var deathRow: [UUID] = []

  // 超天数
  for record in nonExempt where record.lastCopiedAt.timeIntervalSince1970 < ageCutoff {
    deathRow.append(record.id)
  }
  // 超条数（豁免不计入）
  if nonExempt.count > retentionPolicy.maxCount {
    let overflow = nonExempt.suffix(nonExempt.count - retentionPolicy.maxCount)
    for record in overflow where !deathRow.contains(record.id) {
      deathRow.append(record.id)
    }
  }

  guard !deathRow.isEmpty else { return }
  let removedHashes = indexByHash.values.filter { deathRow.contains($0.id) }.map(\.contentHash)
  try deleteRecords(ids: deathRow)
  for hash in removedHashes {
    indexByHash.removeValue(forKey: hash)
  }
}
```

修改 `upsert` 在写入 + 索引更新后调用 `try enforceRetention()`：

```swift
public func upsert(_ record: ClipboardRecord) async throws -> ClipboardRecord {
  if let existing = indexByHash[record.contentHash] {
    var updated = existing
    updated.copyCount += 1
    updated.lastCopiedAt = record.lastCopiedAt
    try writeRecord(updated)
    indexByHash[updated.contentHash] = updated
    try enforceRetention()
    return updated
  }

  try writeRecord(record)
  indexByHash[record.contentHash] = record
  try enforceRetention()
  return record
}
```

- [ ] **Step 5: 跑测试验证通过**

Run: `swift test --filter SQLiteHistoryStoreTests`

Expected: 全部通过（5 个测试）。

- [ ] **Step 6: Commit**

```bash
git add Sources/ClipboardCore/Storage/SQLite/SQLiteHistoryStore.swift \
       Tests/ClipboardCoreTests/SQLiteHistoryStoreTests.swift
git commit -m "$(cat <<'EOF'
feat(storage): SQLiteHistoryStore 实现双堡垒淘汰与 evictOldest

RetentionPolicy 配置 maxCount + maxAgeDays；
upsert 后同步触发 enforceRetention（豁免规则与 evictOldest 一致）；
PRAGMA incremental_vacuum 释放空间。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: 冷启动 integrity_check + 损坏备份 + 启动孤儿扫描

**Files:**
- Modify: `Sources/ClipboardCore/Storage/SQLite/SQLiteHistoryStore.swift`
- Modify: `Tests/ClipboardCoreTests/SQLiteHistoryStoreTests.swift`

**Spec ref:** §5 启动失败处理 + §6 启动孤儿扫描

- [ ] **Step 1: 在测试文件追加损坏检测测试**

```swift
  func testCorruptedDatabaseIsBackedUp() async throws {
    let dbPath = tempDir.appendingPathComponent("test.sqlite")
    // 写入垃圾内容
    try Data("not a sqlite file".utf8).write(to: dbPath)

    do {
      _ = try SQLiteHistoryStore(databaseFile: dbPath)
      XCTFail("应抛错或自动备份后成功")
    } catch StorageError.underlying(let msg) {
      XCTAssert(msg.contains("integrity") || msg.contains("rc="))
    }

    // 验证备份文件存在
    let entries = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
    XCTAssert(entries.contains(where: { $0.hasPrefix("clipboard.corrupt.") }))
  }
```

> 注：本测试断言"抛错并备份"。生产代码上层（AppServices）会捕获该错误并重新打开新 DB；store 自身只负责检测+备份，不自动重建。

- [ ] **Step 2: 修改 SQLiteHistoryStore.init 加 integrity_check + 损坏备份**

在 init 内、`SQLiteSchema.setupPragmas` 调用之前插入：

```swift
do {
  let result = try connection.intScalar("PRAGMA quick_check")
  // quick_check 在 OK 时返回 1 个 row 包含 "ok"，但 intScalar 拿不到 text；
  // 用更直接的：prepare PRAGMA quick_check，读 row 0 的 text。
  _ = result  // 占位避免 unused
  let stmt = try connection.prepare("PRAGMA quick_check")
  defer { stmt.finalize() }
  _ = try stmt.step()
  let status = stmt.columnText(0) ?? ""
  if status != "ok" {
    throw StorageError.underlying("integrity check failed: \(status)")
  }
} catch StorageError.underlying(let msg) {
  Self.logger.error("DB integrity check failed: \(msg)")
  let backup = try SQLiteSchema.backupCorruptedDatabase(at: databaseFile)
  Self.logger.error("backed up corrupted DB to \(backup.path)")
  throw StorageError.underlying("integrity check failed: \(msg) — backed up to \(backup.lastPathComponent)")
}
```

> 这个块整体替换原本"直接 setupPragmas + migrate"的连续调用，改成"check → setup → migrate"序列。

修订后的完整 init：

```swift
public init(
  databaseFile: URL,
  retentionPolicy: RetentionPolicy = RetentionPolicy()
) throws {
  let dir = databaseFile.deletingLastPathComponent()
  let fm = FileManager.default
  if !fm.fileExists(atPath: dir.path) {
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
  }
  let conn: SQLiteConnection
  do {
    conn = try SQLiteConnection(path: databaseFile.path)
    let stmt = try conn.prepare("PRAGMA quick_check")
    defer { stmt.finalize() }
    _ = try stmt.step()
    let status = stmt.columnText(0) ?? ""
    if status != "ok" {
      throw StorageError.underlying("integrity check failed: \(status)")
    }
  } catch let error as StorageError {
    if case .underlying = error, fm.fileExists(atPath: databaseFile.path) {
      let backup = try SQLiteSchema.backupCorruptedDatabase(at: databaseFile)
      Self.logger.error("backed up corrupted DB to \(backup.path)")
    }
    throw error
  }
  self.connection = conn
  self.retentionPolicy = retentionPolicy
  try SQLiteSchema.setupPragmas(connection: connection)
  try SQLiteSchema.migrate(connection: connection)
  self.indexByHash = try Self.loadInitialIndex(connection: connection)
}
```

- [ ] **Step 3: 添加孤儿扫描接口**

在 `SQLiteHistoryStore` actor 内追加：

```swift
/// 返回所有 record 的 payload 文件名（不含路径）。空 payload_ref 跳过。
public func referencedPayloadFilenames() async -> Set<String> {
  // 当前 schema 的 payload_ref 由 PayloadStore 管，HistoryStore 只能按 id 反推
  // payload 文件名约定：<uuid>.<ext>，所以以 uuid 前缀枚举即可（PayloadStore 端处理）
  Set(indexByHash.values.map { $0.id.uuidString })
}
```

> 实际孤儿扫描在 AppServices 端发起：调用 `historyStore.referencedPayloadFilenames()` 拿到所有有效 uuid 前缀，传给 `payloadStore.removeOrphans(keeping:)`。但 `removeOrphans` 当前接受文件名 Set。改为接受"前缀 Set"更直白：

修改 `Sources/ClipboardCore/Storage/SQLite/SQLitePayloadStore.swift` 的 `removeOrphans`：

```swift
public func removeOrphans(keepingPrefixes referenced: Set<String>) throws -> Int {
  let all = try listAllFilenames()
  let orphans = all.filter { name in
    !referenced.contains(where: { name.hasPrefix($0) })
  }
  let fm = FileManager.default
  var removed = 0
  for name in orphans {
    try? fm.removeItem(at: payloadsDirectory.appendingPathComponent(name))
    removed += 1
  }
  return removed
}
```

并删除原 `removeOrphans(keeping:)` 方法。

- [ ] **Step 4: 跑测试验证**

Run: `swift test --filter SQLiteHistoryStoreTests`

Expected: 通过（损坏检测 test 通过，原 5 个测试不退化）。

如果 PayloadStoreTests 因 removeOrphans 签名变化失败，更新对应测试调用点。

- [ ] **Step 5: Commit**

```bash
git add Sources/ClipboardCore/Storage/SQLite/SQLiteHistoryStore.swift \
       Sources/ClipboardCore/Storage/SQLite/SQLitePayloadStore.swift \
       Tests/ClipboardCoreTests/SQLiteHistoryStoreTests.swift
git commit -m "$(cat <<'EOF'
feat(storage): SQLiteHistoryStore 启动 integrity_check + 损坏备份

PRAGMA quick_check 失败 → 自动备份至 clipboard.corrupt.<ts>.sqlite 并抛错；
SQLitePayloadStore.removeOrphans 改为按 uuid 前缀匹配。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: 把 conformance 测试套用于 SQLiteHistoryStore

**Files:**
- Modify: `Tests/ClipboardCoreTests/HistoryStoreConformanceTests.swift`

**Spec ref:** §8 Protocol-conformance 测试

- [ ] **Step 1: 在 HistoryStoreConformanceTests.swift 末尾新增 SQLite test class**

```swift
final class SQLiteHistoryStoreConformanceTests: XCTestCase {
  var tempDir: URL!

  override func setUp() async throws {
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipboard-conformance-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: tempDir)
  }

  func testSQLiteConformsToContract() async throws {
    let counter = TestCounter()
    try await runHistoryStoreConformance {
      let n = await counter.next()
      let url = tempDir.appendingPathComponent("test-\(n).sqlite")
      return try SQLiteHistoryStore(databaseFile: url)
    }
  }
}

actor TestCounter {
  private var n = 0
  func next() -> Int {
    n += 1
    return n
  }
}
```

> 每次 makeStore() 给一个独立 DB 文件，避免不同断言之间共享状态。

- [ ] **Step 2: 跑测试验证**

Run: `swift test --filter ConformanceTests`

Expected: 两个 conformance test class 全部通过（InMemory + SQLite 共 14 个断言通过）。

- [ ] **Step 3: 跑全量测试**

Run: `swift test`

Expected: 全部通过。

- [ ] **Step 4: Commit**

```bash
git add Tests/ClipboardCoreTests/HistoryStoreConformanceTests.swift
git commit -m "$(cat <<'EOF'
test(storage): SQLiteHistoryStore 接入协议契约测试套件

InMemoryHistoryStore 与 SQLiteHistoryStore 现在共享同一组行为断言，
保证两个实现等价。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase F：应用层装配

### Task 14: AppSettings 新增 4 个 key

**Files:**
- Modify: `Sources/ClipboardApp/AppSettings.swift`

**Spec ref:** §7 AppSettings 新增 key

- [ ] **Step 1: 添加新 key 与读取函数**

打开 `Sources/ClipboardApp/AppSettings.swift`，在 `// MARK: - History` section 之后新增：

```swift
    // MARK: - Storage

    static let maxHistoryCountStorageKey = "history.maxCount"  // 沿用旧 key，调整默认值
    static let defaultStorageMaxHistoryCount = 5000

    static func storageMaxHistoryCount(defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: maxHistoryCountStorageKey)
        return stored > 0 ? stored : defaultStorageMaxHistoryCount
    }

    static let maxAgeDaysKey = "storage.maxAgeDays"
    static let defaultMaxAgeDays = 180

    static func storageMaxAgeDays(defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: maxAgeDaysKey)
        return stored > 0 ? stored : defaultMaxAgeDays
    }

    static let failureRecoveryStrategyKey = "storage.failureRecoveryStrategy"

    static func storageFailureStrategy(defaults: UserDefaults = .standard) -> StorageFailureStrategy {
        guard let raw = defaults.string(forKey: failureRecoveryStrategyKey),
              let strategy = StorageFailureStrategy(rawValue: raw) else {
            return .continueEvicting
        }
        return strategy
    }

    static let notifyOnAutoEvictKey = "storage.notifyOnAutoEvict"

    static func storageNotifyOnAutoEvict(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: notifyOnAutoEvictKey) == nil { return true }
        return defaults.bool(forKey: notifyOnAutoEvictKey)
    }
```

并在文件末尾追加：

```swift
// MARK: - Storage Failure Strategy

enum StorageFailureStrategy: String, CaseIterable {
    case continueEvicting
    case pauseMonitoring
    case skipRecord

    var displayName: String {
        switch self {
        case .continueEvicting: return "自动删除最旧记录直到能继续保存"
        case .pauseMonitoring:  return "暂停剪贴板监控"
        case .skipRecord:       return "跳过当前记录，不删除历史"
        }
    }
}
```

- [ ] **Step 2: 编译验证**

Run: `swift build`

Expected: 通过。

- [ ] **Step 3: Commit**

```bash
git add Sources/ClipboardApp/AppSettings.swift
git commit -m "$(cat <<'EOF'
feat(settings): 新增持久化存储相关 4 个 key

storage.maxAgeDays、storage.failureRecoveryStrategy、storage.notifyOnAutoEvict；
history.maxCount 默认值从 200 升至 5000。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 15: AppServices 装配 + 启动失败处理

**Files:**
- Modify: `Sources/ClipboardApp/AppServices.swift`

**Spec ref:** §2 模块边界 + §5 启动失败处理

- [ ] **Step 1: 重构 AppServices 引入降级路径**

完整替换 `Sources/ClipboardApp/AppServices.swift`：

```swift
import AppKit
import ClipboardCore
import ClipboardPlatform
import Foundation
import os.log

@MainActor
final class AppServices {
  enum StorageHealth {
    case ok
    case disabled(reason: String)
    case failing(reason: String)
  }

  let store: any HistoryStore
  let payloadStore: any ClipboardPayloadStore
  let systemClient: SystemPasteboardClient
  let ingestService: ClipboardIngestService
  let monitor: ClipboardMonitor
  let captureCoordinator: ClipboardCaptureCoordinator
  let pasteController: PasteController
  private(set) var storageHealth: StorageHealth = .ok

  lazy var quickPanelState = QuickPanelState(
    viewModel: QuickPanelViewModel(store: store, pageLimit: 50),
    payloadStore: payloadStore,
    pasteController: pasteController
  )
  lazy var quickPanelController = QuickPanelController(
    state: quickPanelState,
    prepareForShow: { [weak self] in
      await self?.prepareQuickPanelForShow()
    }
  )

  private static let logger = Logger(subsystem: "clipboard.app", category: "AppServices")

  init() {
    let bundleId = Bundle.main.bundleIdentifier ?? "com.local.clipboard-manager"
    let (storeImpl, payloadImpl, health) = AppServices.makeStorage(bundleId: bundleId)
    self.store = storeImpl
    self.payloadStore = payloadImpl
    self.storageHealth = health
    self.systemClient = SystemPasteboardClient()
    self.ingestService = ClipboardIngestService(
      store: storeImpl,
      privacyPolicy: .default,
      largeTextPolicy: LargeTextPolicy()
    )
    self.monitor = ClipboardMonitor(client: systemClient)
    self.captureCoordinator = ClipboardCaptureCoordinator(
      monitor: monitor,
      ingestService: ingestService,
      payloadStore: payloadImpl
    )
    self.pasteController = PasteController(
      pasteboardWriter: systemClient,
      pasteEventPoster: systemClient,
      payloadStore: payloadImpl,
      historyStore: storeImpl
    )
  }

  /// 把 SQLite 装配尝试封装；失败时返回 InMemory 降级实例 + .disabled health。
  private static func makeStorage(bundleId: String) -> (any HistoryStore, any ClipboardPayloadStore, StorageHealth) {
    do {
      let paths = try ApplicationSupportPaths(bundleIdentifier: bundleId)
      try paths.prepare()
      let policy = RetentionPolicy(
        maxCount: ClipboardAppSettings.storageMaxHistoryCount(),
        maxAgeDays: ClipboardAppSettings.storageMaxAgeDays()
      )
      let sqliteStore = try SQLiteHistoryStore(
        databaseFile: paths.databaseFile,
        retentionPolicy: policy
      )
      let healing = SelfHealingHistoryStore(underlying: sqliteStore)
      let payloads = try SQLitePayloadStore(payloadsDirectory: paths.payloadsDirectory)
      logger.info("storage initialized at \(paths.baseDirectory.path)")
      return (healing, payloads, .ok)
    } catch {
      logger.error("storage init failed: \(String(describing: error))")
      let reason = "无法访问存储位置：\(error.localizedDescription)"
      _ = AppServices.presentStartupFailure(reason: reason)
      return (InMemoryHistoryStore(), InMemoryPayloadStore(), .disabled(reason: reason))
    }
  }

  private static func presentStartupFailure(reason: String) -> Bool {
    let alert = NSAlert()
    alert.messageText = "无法持久化剪贴板历史"
    alert.informativeText = """
      剪贴板管理器无法访问存储位置。

      \(reason)

      可能原因：磁盘空间不足、文件夹权限异常、或应用从只读位置（如 DMG）运行。
      """
    alert.addButton(withTitle: "在 Finder 中显示")
    alert.addButton(withTitle: "重试")
    alert.addButton(withTitle: "仅本次会话运行")
    alert.addButton(withTitle: "退出")

    let response = alert.runModal()
    switch response {
    case .alertFirstButtonReturn:
      let support = (try? FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: false
      )) ?? URL(fileURLWithPath: NSHomeDirectory())
      NSWorkspace.shared.activateFileViewerSelecting([support])
      return false
    case .alertSecondButtonReturn:
      return true  // 调用方应再次尝试 makeStorage
    case .alertThirdButtonReturn:
      return false
    default:
      NSApp.terminate(nil)
      return false
    }
  }

  // 保留原有 prepareQuickPanelForShow 等方法（请勿删除原文件中的其他方法）
}
```

> 注意：原 `AppServices.swift` 可能包含 `prepareQuickPanelForShow` 等方法。本次替换仅覆盖 init / 类型字段 / 新方法 makeStorage / presentStartupFailure；其他方法在追加替换时**完整保留**。请先 Read 该文件确认所有需要保留的方法。

- [ ] **Step 2: 编译验证**

Run: `swift build`

Expected: 编译通过。如有 `PasteController.init` 参数不匹配（`historyStore:` 是新加的），打开 `Sources/ClipboardCore/Paste/PasteController.swift` 检查现有签名；若没有 `historyStore:` 参数，移除上面的 `historyStore: storeImpl` 这一行。

- [ ] **Step 3: 跑全量测试**

Run: `swift test`

Expected: 通过。

- [ ] **Step 4: 手动启动验证**

Run: `swift run ClipboardApp`

Expected: 应用启动后无 crash；可在 `~/Library/Application Support/<bundle-id>/clipboard.sqlite` 看到 DB 文件创建。复制几次后退出，再启动 → 历史保留。

- [ ] **Step 5: Commit**

```bash
git add Sources/ClipboardApp/AppServices.swift
git commit -m "$(cat <<'EOF'
feat(app): AppServices 装配 SQLite 持久化与启动失败降级

成功路径：SelfHealingHistoryStore(SQLiteHistoryStore) + SQLitePayloadStore；
失败路径：弹窗提示 + InMemoryHistoryStore 降级 + storageHealth 状态记录。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase G：UI 与通知

### Task 16: HistorySettingsView 重构（双堡垒 stepper + 存储 section）

**Files:**
- Modify: `Sources/ClipboardApp/Settings/HistorySettingsView.swift`

**Spec ref:** §7 HistorySettingsView 重构

- [ ] **Step 1: 重写 HistorySettingsView**

替换 `Sources/ClipboardApp/Settings/HistorySettingsView.swift` 全文：

```swift
import ClipboardCore
import SwiftUI

struct HistorySettingsView: View {
    let store: any HistoryStore
    let storageHealth: AppServices.StorageHealth
    let baseDirectory: URL?

    @AppStorage(ClipboardAppSettings.maxHistoryCountStorageKey)
    private var maxHistoryCount: Int = ClipboardAppSettings.defaultStorageMaxHistoryCount

    @AppStorage(ClipboardAppSettings.maxAgeDaysKey)
    private var maxAgeDays: Int = ClipboardAppSettings.defaultMaxAgeDays

    @AppStorage(ClipboardAppSettings.failureRecoveryStrategyKey)
    private var failureStrategyRaw: String = StorageFailureStrategy.continueEvicting.rawValue

    @AppStorage(ClipboardAppSettings.notifyOnAutoEvictKey)
    private var notifyOnAutoEvict: Bool = true

    @State private var recordCount: Int = 0
    @State private var showClearConfirmation = false

    private var failureStrategy: Binding<StorageFailureStrategy> {
        Binding(
            get: { StorageFailureStrategy(rawValue: failureStrategyRaw) ?? .continueEvicting },
            set: { failureStrategyRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("保留策略") {
                Stepper("最多保留 \(maxHistoryCount) 条历史记录",
                        value: $maxHistoryCount, in: 200...50000, step: 100)
                Stepper("超过 \(maxAgeDays) 天的记录自动删除（pinned / 收藏除外）",
                        value: $maxAgeDays, in: 7...365, step: 1)
                Text("修改后，下次新复制内容时生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("存储") {
                statusRow
                if let dir = baseDirectory {
                    HStack {
                        Text("位置：\(dir.path)")
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("在 Finder 中显示") {
                            NSWorkspace.shared.activateFileViewerSelecting([dir])
                        }
                    }
                }
                Picker("磁盘空间不足时", selection: failureStrategy) {
                    ForEach(StorageFailureStrategy.allCases, id: \.self) { strategy in
                        Text(strategy.displayName).tag(strategy)
                    }
                }
                Toggle("自愈成功时显示通知", isOn: $notifyOnAutoEvict)
            }

            Section("清除历史") {
                HStack {
                    Text("当前共 \(recordCount) 条记录")
                    Spacer()
                    Button("清除全部历史") {
                        showClearConfirmation = true
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshCount() }
        .confirmationDialog(
            "确定要清除所有剪贴板历史吗？此操作无法撤销。",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除全部", role: .destructive) {
                Task {
                    try? await store.removeAll()
                    refreshCount()
                }
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch storageHealth {
        case .ok:
            Label("持久化正常", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .disabled(let reason):
            Label("持久化已禁用：\(reason)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .failing(let reason):
            Label("写入失败：\(reason)", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }

    private func refreshCount() {
        Task { recordCount = (try? await store.count()) ?? 0 }
    }
}
```

- [ ] **Step 2: 更新 SettingsWindow 传入新参数**

打开 `Sources/ClipboardApp/Settings/SettingsWindow.swift`，找到 HistorySettingsView 的实例化处。改为：

```swift
HistorySettingsView(
    store: services.store,
    storageHealth: services.storageHealth,
    baseDirectory: try? ApplicationSupportPaths(
        bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.local.clipboard-manager"
    ).baseDirectory
)
```

> 如果 `services` 字段名不同，请按实际命名调整。

- [ ] **Step 3: 编译并跑测试**

Run: `swift build && swift test`

Expected: 通过。

- [ ] **Step 4: Commit**

```bash
git add Sources/ClipboardApp/Settings/HistorySettingsView.swift \
       Sources/ClipboardApp/Settings/SettingsWindow.swift
git commit -m "$(cat <<'EOF'
feat(settings): HistorySettingsView 接入双堡垒淘汰与存储状态

新增"保留策略"和"存储"section；显示三态健康徽标、存储位置；
失败策略选择器；依赖从 InMemoryHistoryStore 改为 any HistoryStore。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 17: StatusBarController 三态徽标

**Files:**
- Modify: `Sources/ClipboardApp/StatusBar/StatusBarController.swift`

**Spec ref:** §5 状态栏徽标三态 + §7

- [ ] **Step 1: 阅读现有 StatusBarController**

Run: 在编辑器内打开 `Sources/ClipboardApp/StatusBar/StatusBarController.swift`，找到 NSStatusItem 的 image / button 配置位置。

- [ ] **Step 2: 添加 storageHealth 字段与状态映射**

在类内添加：

```swift
private var storageHealth: AppServices.StorageHealth = .ok

func updateStorageHealth(_ health: AppServices.StorageHealth) {
  self.storageHealth = health
  refreshIcon()
}

private func refreshIcon() {
  guard let button = statusItem.button else { return }
  let baseImage = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard")
  switch storageHealth {
  case .ok:
    button.image = baseImage
    button.contentTintColor = nil
  case .disabled:
    button.image = baseImage
    button.contentTintColor = .systemOrange
  case .failing:
    button.image = baseImage
    button.contentTintColor = .systemRed
  }
}
```

并在 `init` / `setup` 末尾调用一次 `refreshIcon()`。

- [ ] **Step 3: 在 AppServices / AppDelegate 内连接 StatusBarController**

在 AppServices 装配后或 AppDelegate.applicationDidFinishLaunching 末尾：

```swift
statusBarController.updateStorageHealth(services.storageHealth)
```

- [ ] **Step 4: 编译验证**

Run: `swift build`

Expected: 通过。

- [ ] **Step 5: Commit**

```bash
git add Sources/ClipboardApp/StatusBar/StatusBarController.swift \
       Sources/ClipboardApp/App/AppDelegate.swift
git commit -m "$(cat <<'EOF'
feat(statusbar): 三态徽标反映存储健康状况

🟢 OK / 🟡 disabled (orange) / 🔴 failing (red)；启动时根据 AppServices.storageHealth 设置初始态。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 18: 通知节流 StorageHealthNotifier

**Files:**
- Create: `Sources/ClipboardApp/Storage/StorageHealthNotifier.swift`
- Modify: `Sources/ClipboardApp/AppServices.swift`

**Spec ref:** §5 通知节流 + 自愈成功通知

- [ ] **Step 1: 创建 StorageHealthNotifier**

写入 `Sources/ClipboardApp/Storage/StorageHealthNotifier.swift`：

```swift
import Foundation
import UserNotifications
import os.log

@MainActor
final class StorageHealthNotifier {
  enum Failure: String {
    case diskFull
    case permission
    case corruption
    case other
  }

  private var lastNotifiedFailure: Failure?
  private static let logger = Logger(subsystem: "clipboard.storage", category: "Notifier")

  func notifyFailure(_ failure: Failure, message: String) async {
    guard lastNotifiedFailure != failure else { return }
    lastNotifiedFailure = failure
    await sendNotification(title: "持久化写入失败", body: message)
  }

  func notifyAutoEvict(removed: Int, freed: String) async {
    guard ClipboardAppSettings.storageNotifyOnAutoEvict() else { return }
    await sendNotification(
      title: "已自动清理空间",
      body: "剪贴板自动清理了 \(removed) 条最旧记录，释放约 \(freed)。"
    )
  }

  func notifyRecovered() async {
    guard lastNotifiedFailure != nil else { return }
    lastNotifiedFailure = nil
    await sendNotification(title: "持久化已恢复", body: "剪贴板写入已恢复正常。")
  }

  private func sendNotification(title: String, body: String) async {
    let center = UNUserNotificationCenter.current()
    do {
      let granted = try await center.requestAuthorization(options: [.alert, .sound])
      guard granted else { return }
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = .default
      let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
      try await center.add(request)
    } catch {
      Self.logger.error("notification failed: \(String(describing: error))")
    }
  }
}
```

- [ ] **Step 2: 在 AppServices 添加 notifier 字段**

在 `AppServices` 内添加：

```swift
let storageNotifier = StorageHealthNotifier()
```

并在 `makeStorage` 失败分支调用：

```swift
Task { @MainActor in
  await storageNotifier.notifyFailure(.permission, message: reason)
}
```

> 注：`makeStorage` 是 `static`，无法直接访问实例。改造方式：让 `init` 内捕获 `health` 后再发通知。具体地，把 `presentStartupFailure` 调用之后追加 `Task { @MainActor in await self.storageNotifier.notifyFailure(.permission, message: reason) }`。

- [ ] **Step 3: 编译验证**

Run: `swift build`

Expected: 通过。

- [ ] **Step 4: Commit**

```bash
git add Sources/ClipboardApp/Storage/StorageHealthNotifier.swift \
       Sources/ClipboardApp/AppServices.swift
git commit -m "$(cat <<'EOF'
feat(app): StorageHealthNotifier 节流通知

按 Failure 类别去重；自愈成功通知遵循 storage.notifyOnAutoEvict 设置；
recovery 通知仅在曾经通知过失败后才发。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 19: Layer 2 策略接入 ingest 路径

**Files:**
- Modify: `Sources/ClipboardCore/Ingest/ClipboardCaptureCoordinator.swift`
- Modify: `Sources/ClipboardApp/AppServices.swift`
- Modify: `Sources/ClipboardCore/Monitor/ClipboardMonitor.swift`（如尚无 `pause()` 方法）

**Spec ref:** §5 Layer 2 用户策略

- [ ] **Step 1: 给 ClipboardMonitor 添加 pause/resume**

Read `Sources/ClipboardCore/Monitor/ClipboardMonitor.swift`，确认有无 `pause()`。若无，在 actor 内添加：

```swift
private var isPaused = false

public func pause() { isPaused = true }
public func resume() { isPaused = false }

// 修改 poll() 入口加上：
public func poll() async -> ClipboardCapture? {
  guard !isPaused else { return nil }
  // ... 其余原逻辑
}
```

- [ ] **Step 2: 定义 Layer 2 策略 handler 协议**

在 `Sources/ClipboardCore/Ingest/ClipboardCaptureCoordinator.swift` 顶部新增：

```swift
public protocol StorageFailureHandler: Sendable {
  /// 在底层 store 抛出 StorageError.full / .fullAndCannotEvict 时调用。
  /// 返回 true 表示已处理（如已 pauseMonitoring），调用方继续；
  /// 返回 false 表示策略要求继续重试（continueEvicting）→ 调用方负责再次尝试。
  func handleStorageFailure(_ error: StorageError, record: ClipboardRecord) async -> Bool
}
```

- [ ] **Step 3: 改造 ClipboardCaptureCoordinator.ingest 接入 handler**

```swift
public struct ClipboardCaptureCoordinator: Sendable {
  private let monitor: ClipboardMonitor
  private let ingestService: ClipboardIngestService
  private let payloadStore: any ClipboardPayloadStore
  private let failureHandler: any StorageFailureHandler

  public init(
    monitor: ClipboardMonitor,
    ingestService: ClipboardIngestService,
    payloadStore: any ClipboardPayloadStore,
    failureHandler: any StorageFailureHandler
  ) {
    self.monitor = monitor
    self.ingestService = ingestService
    self.payloadStore = payloadStore
    self.failureHandler = failureHandler
  }

  public func captureLatestChange() async throws -> ClipboardRecord? {
    guard let capture = await monitor.poll() else { return nil }
    return try await ingest(capture)
  }

  public func ingest(_ capture: ClipboardCapture) async throws -> ClipboardRecord? {
    var attempts = 0
    while true {
      do {
        guard let record = try await ingestService.ingest(capture) else { return nil }
        try await payloadStore.save(capture.payload, for: record.id)
        return record
      } catch let error as StorageError {
        attempts += 1
        let placeholder = ClipboardRecord(
          id: UUID(),
          contentHash: "",
          primaryType: .text,
          title: "",
          plainTextPreview: nil,
          sourceAppBundleId: nil,
          sourceAppName: nil,
          sourceDeviceHint: .local,
          createdAt: capture.capturedAt,
          lastCopiedAt: capture.capturedAt,
          copyCount: 0,
          isPinned: false,
          isFavorite: false,
          groupIds: [],
          retentionExempt: false,
          metadata: nil,
          pasteboardTypes: capture.pasteboardTypes
        )
        let handled = await failureHandler.handleStorageFailure(error, record: placeholder)
        if handled { return nil }   // pauseMonitoring / skipRecord 都返回 true
        if attempts >= 10 { return nil }  // 防意外死循环
      }
    }
  }
}
```

- [ ] **Step 4: 在 AppServices 实现具体 handler**

在 `Sources/ClipboardApp/AppServices.swift` 内新增（@MainActor）：

```swift
final class DefaultStorageFailureHandler: StorageFailureHandler {
  private let monitor: ClipboardMonitor
  private let store: any HistoryStore
  private let notifier: StorageHealthNotifier
  private let onHealthChange: @Sendable (AppServices.StorageHealth) async -> Void

  init(
    monitor: ClipboardMonitor,
    store: any HistoryStore,
    notifier: StorageHealthNotifier,
    onHealthChange: @escaping @Sendable (AppServices.StorageHealth) async -> Void
  ) {
    self.monitor = monitor
    self.store = store
    self.notifier = notifier
    self.onHealthChange = onHealthChange
  }

  func handleStorageFailure(_ error: StorageError, record: ClipboardRecord) async -> Bool {
    let strategy = await MainActor.run { ClipboardAppSettings.storageFailureStrategy() }
    let message = "磁盘空间不足：\(String(describing: error))"

    switch strategy {
    case .continueEvicting:
      // 持续删除直到成功；如果完全无可删则降级到 pause
      do {
        let removed = try await store.evictOldest(percent: 0.10)
        if removed == 0 {
          await monitor.pause()
          await notifier.notifyFailure(.diskFull, message: message + "（无可删记录，已暂停监控）")
          await onHealthChange(.disabled(reason: "磁盘满且无可删记录"))
          return true
        }
        return false  // 让上层重试
      } catch {
        await notifier.notifyFailure(.other, message: String(describing: error))
        return true
      }
    case .pauseMonitoring:
      await monitor.pause()
      await notifier.notifyFailure(.diskFull, message: message)
      await onHealthChange(.disabled(reason: "用户策略：暂停监控"))
      return true
    case .skipRecord:
      await notifier.notifyFailure(.diskFull, message: message)
      await onHealthChange(.failing(reason: "跳过当前记录"))
      return true
    }
  }
}
```

并在 `AppServices.init` 内装配（替换 captureCoordinator 初始化）：

```swift
let handler = DefaultStorageFailureHandler(
  monitor: monitor,
  store: storeImpl,
  notifier: storageNotifier,
  onHealthChange: { [weak self] newHealth in
    await MainActor.run { self?.storageHealth = newHealth }
  }
)
self.captureCoordinator = ClipboardCaptureCoordinator(
  monitor: monitor,
  ingestService: ingestService,
  payloadStore: payloadImpl,
  failureHandler: handler
)
```

- [ ] **Step 5: 编译并测试**

Run: `swift build && swift test`

Expected: 通过。可能需修复其他持有 `ClipboardCaptureCoordinator` 实例的测试（新增的 failureHandler 参数）。

- [ ] **Step 6: Commit**

```bash
git add Sources/ClipboardCore/Ingest/ClipboardCaptureCoordinator.swift \
       Sources/ClipboardCore/Monitor/ClipboardMonitor.swift \
       Sources/ClipboardApp/AppServices.swift
git commit -m "$(cat <<'EOF'
feat(storage): Layer 2 用户策略接入 ingest 路径

新增 StorageFailureHandler 协议与 DefaultStorageFailureHandler 实现：
continueEvicting 持续删除重试；pauseMonitoring 暂停 monitor；skipRecord 静默跳过。
ClipboardMonitor 新增 pause/resume。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase H：收尾

### Task 20: 手工验收清单 + 全量验证

**Files:**
- Modify: `docs/manual-acceptance-checklist.md`

**Spec ref:** §8 手工验收 + §11 验收标准

- [ ] **Step 1: 在 manual-acceptance-checklist.md 末尾追加新 section**

打开 `docs/manual-acceptance-checklist.md`，末尾追加：

```markdown
## 持久化存储（2026-05-08 引入）

### 基础持久化
- [ ] 首次启动 → 复制 5 条不同内容 → 退出应用 → 重启 → QuickPanel 应显示全部 5 条
- [ ] 退出后查看 `~/Library/Application Support/<bundle-id>/clipboard.sqlite` 文件存在
- [ ] 复制图片 → 退出 → 重启 → 选择该图片粘贴成功

### 双堡垒淘汰
- [ ] 设置 maxCount = 50 → 复制 60 条 → 重启 → count 应为 50（前 10 条最旧的被删）
- [ ] pin 一条 → 复制大量记录直至超 maxCount → pin 项保留
- [ ] 调整系统时间或 maxAgeDays = 1 → 复制内容 → 等 25 小时 / 改时间 → 该条应被删（除非 pinned）

### 启动失败降级
- [ ] 把 `~/Library/Application Support/<bundle-id>/` 目录权限改为 0444 → 启动应弹"无法持久化"alert
- [ ] 选择"仅本次会话运行" → 状态栏徽标变橙色 → 历史仅在内存
- [ ] 恢复权限后重启 → 状态栏恢复绿色

### 损坏检测
- [ ] 退出应用，把 clipboard.sqlite 替换为随机字节 → 重启 → 应弹错误提示并备份原文件为 clipboard.corrupt.<ts>.sqlite
- [ ] 重启后历史应为空（新建 DB）

### 设置项
- [ ] HistorySettingsView 显示绿色"持久化正常"徽标
- [ ] 修改 maxCount stepper → 下次复制时生效
- [ ] "在 Finder 中显示"按钮打开 Application Support 目录
- [ ] "清除全部历史" → DB 清空，count 归零
- [ ] 失败策略 picker 切换"暂停剪贴板监控" → 模拟磁盘满 → ClipboardMonitor 应停止

### 性能
- [ ] 持续重度复制 24 小时（>1000 条），观察 `du -sh` 应保持合理增长（每条平均 < 5KB 元数据）
- [ ] 27K 条记录场景下，QuickPanel 打开延迟 < 500ms（用 swift run ClipboardManualProbe 加压数据后实测）
- [ ] 单次复制 → 写入完成的端到端延迟 < 50ms 中位数（用 os_signpost 观察）
```

- [ ] **Step 2: 跑 verify.sh 全验证**

Run: `Scripts/verify.sh`

Expected: 全部通过。如有性能测试失败（PerformanceGuardTests），根据 spec §11 验收标准 4-6 条核对。

- [ ] **Step 3: 手工 sanity check**

Run: `swift run ClipboardApp`，复制几条内容，退出，再启动，确认历史保留。

Run: `ls ~/Library/Application\ Support/com.local.clipboard-manager/` 验证 `clipboard.sqlite`、`payloads/` 存在。

- [ ] **Step 4: 最终 Commit**

```bash
git add docs/manual-acceptance-checklist.md
git commit -m "$(cat <<'EOF'
docs(checklist): 添加持久化存储手工验收项

涵盖基础持久化、双堡垒淘汰、启动失败、损坏检测、设置项、性能六大类。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## 实施顺序总览

| Phase | Task | 关键产出 |
|---|---|---|
| A | 1-4 | HistoryStore 协议升级 + InMemoryHistoryStore 同步 + 契约测试 baseline |
| B | 5 | SelfHealingHistoryStore 装饰器 + Layer 1 自愈测试 |
| C | 6-8 | ApplicationSupportPaths + SQLiteConnection + Schema |
| D | 9 | SQLitePayloadStore 文件落盘 |
| E | 10-13 | SQLiteHistoryStore CRUD / retention / 损坏检测 / 契约测试 |
| F | 14-15 | AppSettings + AppServices 装配 + 启动失败弹窗 |
| G | 16-19 | HistorySettingsView + StatusBar + Notifier + Layer 2 策略 |
| H | 20 | 手工验收 + verify.sh |

预计总改动：10 新增 + 9 修改文件 = **19 个文件**（比 spec §9 多 3 个：StorageHealthNotifier、SettingsWindow、ClipboardMonitor.pause）。

每个 task 末尾都有独立 commit，便于细粒度 review 与必要时 revert。
