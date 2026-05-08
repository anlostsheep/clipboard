# 剪贴板历史持久化存储设计

- 文档创建：2026-05-08
- 范围：把 `HistoryStore` / `ClipboardPayloadStore` 从内存实现迁移到磁盘 SQLite + 文件 blob，使剪贴板历史在应用退出后保留
- 关联背景：原始设计 `docs/superpowers/specs/2026-04-30-macos-native-clipboard-manager-design.md` 第 109-113 行已规划"一期用 SwiftData/SQLite"，本迭代兑现该计划

## 1. 目标与非目标

### 目标

1. 应用退出/重启后，全部剪贴板历史（含图片、富文本、文件引用）完整恢复
2. 兑现并强化 `maxHistoryCount` 设置：超条数或超天数任一触发自动淘汰
3. 持久化失败（磁盘满、权限缺失等）必须**显式可见**，并提供用户可选恢复策略；不接受沉默丢数据
4. 6 个月保留场景下（重度用户 ~27K 条）QuickPanel 搜索响应 < 50ms、冷启动加载 < 200ms
5. ClipboardCore 保持零三方依赖（仅引用系统 module `SQLite3`）

### 非目标（本期不做）

- QuickPanel / Library 单条删除、pin/favorite UI 切换（保留协议字段，UI 后续迭代）
- 全文索引 / FTS 搜索（沿用现有子串扫描语义）
- 加密存储（依赖现有 `PrivacyPolicy` 过滤敏感来源 + FileVault 盘级加密）
- iCloud / 设备间同步
- 历史导入/导出

## 2. 模块边界

```
ClipboardCore (无平台依赖)
  Storage/
    HistoryStore.swift                  协议（小幅扩展）
    InMemoryHistoryStore.swift          保留供测试与降级
    SelfHealingHistoryStore.swift       新增装饰器，封装 Layer 1 自愈
    SQLite/
      SQLiteHistoryStore.swift          actor，实现 HistoryStore，仅做 C API 翻译
      SQLitePayloadStore.swift          actor，实现 ClipboardPayloadStore，文件落盘
      SQLiteConnection.swift            thin wrapper：open/exec/prepare/bind/step/finalize
      SQLiteSchema.swift                schema + PRAGMA user_version 迁移
      ApplicationSupportPaths.swift     路径解析
```

**关键架构决策**：

- 通过 `import SQLite3` 引用系统 module，**Package.swift 不变、ClipboardCore 仍零三方依赖**
- Layer 1 失败自愈逻辑提取为装饰器 `SelfHealingHistoryStore`，与 SQLite 实现解耦——它包装任意 `HistoryStore` 并在底层抛 `StorageError.full` 时执行批量淘汰重试
- 测试通过 `FakeHistoryStore`（按脚本抛错）覆盖 Layer 1 全部分支，不需要 mock C API、不引入 `#if DEBUG` 注入点
- `AppServices` 装配：`SelfHealingHistoryStore(underlying: SQLiteHistoryStore(...))`；启动失败时降级为 `InMemoryHistoryStore` 并通过状态栏 + 设置面板显式提示

### `HistoryStore` 协议变更

```swift
public protocol HistoryStore: Sendable {
  func upsert(_ record: ClipboardRecord) async throws -> ClipboardRecord
  func fetchAll() async throws -> [ClipboardRecord]
  func fetchPage(query: String, limit: Int) async throws -> [ClipboardRecord]

  // 新增
  func count() async throws -> Int
  func removeAll() async throws
  func evictOldest(percent: Double) async throws -> Int
}

public enum StorageError: Error, Equatable {
  case full                      // 可通过删除非豁免记录恢复
  case fullAndCannotEvict        // 全部记录均豁免，无可删
  case underlying(String)        // 包装其他错误，String 用于日志/错误码
}
```

`fetchAll` / `fetchPage` 升级为 `throws` 是为了让 SQLite 实现能传播错误；`InMemoryHistoryStore` 同步签名（永不抛错）。

## 3. 磁盘布局与 schema

### 路径

```
~/Library/Application Support/<bundle-id>/
├── clipboard.sqlite
├── clipboard.sqlite-wal
├── clipboard.sqlite-shm
└── payloads/
    ├── <uuid>.txt              text 内容（UTF-8）
    ├── <uuid>.rtf              richText 的 rtfData
    ├── <uuid>.<imgExt>         image data（扩展名按 uti 解析，未知则 .bin）
    └── <uuid>.fileurls.json    fileURLs 列表
```

`<bundle-id>` 取自 `Bundle.main.bundleIdentifier`，回退常量 `com.local.clipboard-manager`（与 `Scripts/build-app-bundle.sh` 的默认值一致）。`payloads/` 路径相对位置存入 DB 列 `payload_ref`。

### Schema v1

```sql
CREATE TABLE records (
    id              TEXT PRIMARY KEY,        -- UUID
    content_hash    TEXT NOT NULL UNIQUE,
    primary_type    TEXT NOT NULL,
    title           TEXT NOT NULL,
    plain_preview   TEXT,
    source_bundle   TEXT,
    source_app      TEXT,
    source_device   TEXT NOT NULL,
    created_at      REAL NOT NULL,           -- Date.timeIntervalSince1970
    last_copied_at  REAL NOT NULL,
    copy_count      INTEGER NOT NULL,
    is_pinned       INTEGER NOT NULL,        -- 0/1
    is_favorite     INTEGER NOT NULL,
    group_ids_json  TEXT NOT NULL,           -- JSON 数组
    retention_exempt INTEGER NOT NULL,
    metadata_json   TEXT,                    -- LargeTextMetadata JSON, nullable
    pasteboard_types_json TEXT NOT NULL,     -- JSON 数组
    payload_ref     TEXT                     -- payloads/<uuid>.<ext> 相对路径，nullable
);

CREATE INDEX idx_last_copied_at ON records(last_copied_at DESC);
CREATE INDEX idx_pinned_favorite ON records(is_pinned, is_favorite);

PRAGMA user_version = 1;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA foreign_keys = ON;
PRAGMA auto_vacuum = INCREMENTAL;
```

**设计权衡**：

- `Set<String>` / `[String]` 直接 JSON 编码进列；当前没有按类型/分组的查询需求，建 join 表收益不抵其复杂度
- `metadata` 是嵌套结构，使用现有 `Codable` 编码；保留扩展余地
- 大对象统一走文件不入 BLOB 列，遵守 SQLite 官方对 >10KB 数据的建议
- 时间用 `REAL`（Unix epoch 秒）与 `Date.timeIntervalSince1970` 1:1
- `auto_vacuum = INCREMENTAL` 以便淘汰后释放空间（自愈路径会主动 `PRAGMA incremental_vacuum`）

### 迁移框架

`SQLiteSchema.migrate()` 在 store 启动时执行：
1. `PRAGMA user_version` 读取
2. 0 → v1：执行上述 CREATE 脚本，写入 `user_version = 1`
3. 未来 v2/v3 在同一 switch 内增量迁移

每次 schema 变更必须配测试覆盖该路径。v1 当前没有需要迁移的旧数据（in-memory 实现无持久化）。

## 4. 写入路径与并发模型

### `SQLiteHistoryStore` 并发

- actor 串行所有公开方法
- 内部持有单一 `sqlite3*` 连接（WAL 模式下高效）
- 启动一次 `prepare` 关键 statement，运行期 `reset` + `bind` + `step` 复用，避免重复解析
- C API 错误统一翻译为 `StorageError`：`SQLITE_FULL` → `.full`，其他非 OK 码 → `.underlying`

### `upsert` 路径

```
1. payload 写文件：payloads/<uuid>.<ext>.tmp
2. fsync + rename → payloads/<uuid>.<ext>     （原子）
3. BEGIN IMMEDIATE
4. INSERT … ON CONFLICT(content_hash) DO UPDATE SET copy_count=copy_count+1, last_copied_at=excluded.last_copied_at
5. enforceRetention()                          （见 §5）
6. COMMIT
7. 同步更新 inMemoryIndex（见 §6）
```

任何步骤失败：
- payload 写失败 → 不进入 DB 阶段
- DB 失败 → ROLLBACK，`try? FileManager.removeItem(payload.tmp)`，错误向上传播

### 内存索引

`SQLiteHistoryStore` 启动一次性 `SELECT *` 加载全部记录到 `private var inMemoryIndex: [String: ClipboardRecord]`（按 contentHash），以避免 `LIKE '%xxx%'` 的全表扫描。

- 27K × ~1KB ≈ 27MB 常驻内存，macOS 上可接受
- 冷启动加载约 50–150ms，发生在 app 启动早期，QuickPanel 默认隐藏不阻塞
- `fetchPage` 使用内存子串过滤，延迟 < 1ms
- 写入路径在 DB 提交后同步更新内存索引；不一致时以 DB 为准（下次冷启动自然修复）
- payload **不预加载**：仅 `loadPayload(for:)` 时按需读盘

## 5. 失败处理：Layer 1 自愈 + Layer 2 用户策略

### Layer 1：装饰器自愈（`SelfHealingHistoryStore`）

底层抛 `StorageError.full` 时：

```
重试循环（最多 maxRounds 轮，默认 3）：
  evicted = underlying.evictOldest(percent: 0.10)
  若 evicted == 0 → 抛 .fullAndCannotEvict
  否则：重试 underlying.upsert
若耗尽重试次数仍失败 → 控制权交给 Layer 2
```

豁免规则：`is_pinned = 1 OR is_favorite = 1 OR retention_exempt = 1`。这与正常淘汰使用同一豁免集，行为一致。

### Layer 2：用户可选策略（设置 `storage.failureRecoveryStrategy`）

| 策略 | Layer 1 耗尽后行为 |
|---|---|
| **continueEvicting**（默认推荐） | 在 Layer 1 之后继续按 10% 步进删除直至成功；剩余全部豁免时降级到 pause + 通知 |
| **pauseMonitoring** | `ClipboardMonitor.pause()`，状态栏标示"已暂停"，等待用户清磁盘后手动恢复 |
| **skipRecord** | 当前条记录跳过（不进 DB，仅留在内存索引），下次复制再次尝试；适合不希望任何旧历史被自动删的用户 |

### 启动失败处理

启动尝试 open DB 失败 → 弹 `NSAlert`（modal）：

```
⚠️ 无法持久化剪贴板历史

剪贴板管理器无法访问存储位置：
~/Library/Application Support/<bundle-id>/

可能原因：磁盘空间不足、文件夹权限异常、或应用从只读位置（如 DMG）运行。

[ 在 Finder 中显示 ]   [ 重试 ]   [ 仅本次会话运行 ]   [ 退出 ]
```

选 "仅本次会话运行" → `AppServices` 装配 `InMemoryHistoryStore`，状态栏徽标黄色，设置面板显示状态与"立即重试"按钮。

启动时若 `PRAGMA integrity_check` 失败：备份 `clipboard.sqlite` → `clipboard.corrupt.<timestamp>.sqlite`，新建空 DB，弹一次性提示（不静默删数据）。

### 通知节流

维护内存中 `lastNotifiedErrorKind`（满磁盘 / 权限 / 损坏 / 其他）：
- 第一次该类失败 → `UNUserNotification` 发一次
- 同类后续失败 → 仅状态栏徽标变红，不再通知
- 一次成功写入 → 清空 `lastNotifiedErrorKind`，徽标恢复，发"已恢复"通知

### 状态栏徽标三态

- 🟢 绿：持久化正常
- 🟡 黄：持久化已禁用（启动失败 + 会话模式 / pauseMonitoring）
- 🔴 红：运行期写入失败中

### 可观测性

每次 Layer 1 触发写一条结构化 `os_log`，subsystem `clipboard.storage`，包含：删除条数、释放字节、剩余空间、触发原因。用户可在 Console.app 查看，便于开源用户提 issue 时定位"是 clipboard 自身还是其他应用占用空间"。

## 6. 淘汰策略

### 双堡垒（任一超限触发）

设置项：
- `storage.maxHistoryCount`：默认 5000，范围 200–50000（沿用现有 `history.maxCount` key 但调整范围）
- `storage.maxAgeDays`：默认 180，范围 7–365（新增）

`enforceRetention()` 在每次 upsert 提交后、同事务内执行：

```sql
DELETE FROM records
 WHERE id IN (
   SELECT id FROM records
    WHERE is_pinned = 0 AND is_favorite = 0 AND retention_exempt = 0
      AND (
        last_copied_at < :ageCutoff
        OR id IN (
          SELECT id FROM records
           WHERE is_pinned = 0 AND is_favorite = 0 AND retention_exempt = 0
           ORDER BY last_copied_at DESC
           LIMIT -1 OFFSET :maxCount
        )
      )
 );
```

`ageCutoff = now - maxAgeDays * 86400`。

**配额豁免规则**：豁免项不占用 `maxCount` 配额（与 Maccy 一致）。即上限是"非豁免记录的最大数量"。

被删除记录的 payload 文件在事务提交后异步删除（不影响写入延迟）。

### `evictOldest(percent:)`

供 Layer 1 装饰器调用：删除最旧 `ceil(N * percent)` 条非豁免记录及其 payload，返回实际删除数。同时执行 `PRAGMA incremental_vacuum` 释放页空间。

### 启动孤儿扫描

启动后 5s 延迟（避免与 UI 启动竞争）在 `Task.detached(priority: .background)` 内执行一次：
1. `let dbRefs = SELECT payload_ref FROM records WHERE payload_ref IS NOT NULL`
2. `let fileRefs = FileManager` 列出 `payloads/` 全部文件
3. 删除 `fileRefs - dbRefs` 的孤儿
4. `dbRefs - fileRefs` 的丢失 → `UPDATE records SET payload_ref = NULL`（保留元数据，粘贴时返回 `PasteFailureReason.blobMissing`）

## 7. UI / 设置变更

### `HistorySettingsView` 重构

- 依赖类型从 `InMemoryHistoryStore` 改为 `any HistoryStore`
- 调用 `count()` 替代直接访问 `fetchAll().count`
- 新增 section：

```
保留策略
├── 最多保留 [stepper 200-50000] 条历史记录
└── 超过 [stepper 7-365] 天的记录自动删除（pinned / 收藏除外）

存储
├── 状态：✓ 正常 / ⚠️ 已禁用 [立即重试] / ⚠️ 写入失败 (磁盘已满)
├── 存储位置：~/Library/...   [在 Finder 中显示]
├── 磁盘空间不足时：
│   ◉ 自动删除最旧记录直到能继续保存（推荐）
│   ○ 暂停剪贴板监控，等待手动处理
│   ○ 跳过当前记录，不删除历史
├── ☑ 自愈成功时显示通知
└── [立即检查存储健康]   ← 触发 PRAGMA integrity_check
```

### `AppSettings` 新增 key

| key | 类型 | 默认 |
|---|---|---|
| `storage.maxHistoryCount`（沿用 `history.maxCount`） | Int | 5000 |
| `storage.maxAgeDays` | Int | 180 |
| `storage.failureRecoveryStrategy` | String enum | `continueEvicting` |
| `storage.notifyOnAutoEvict` | Bool | true |

### `StatusBarController` 三态徽标

新增显式状态属性 `storageHealth: .ok / .disabled / .failing`，根据状态切换菜单栏 icon overlay。

## 8. 测试策略

### Protocol-conformance 测试

新建 `Tests/ClipboardCoreTests/HistoryStoreConformanceTests.swift`，定义所有协议契约的断言：upsert 去重、fetchPage 分页/搜索、count 准确、removeAll 清空、retention 双堡垒、豁免项保留、evictOldest 行为。通过 generic helper 同时跑 `InMemoryHistoryStore` 与 `SQLiteHistoryStore`。

```swift
func runHistoryStoreConformance<S: HistoryStore>(_ makeStore: () async throws -> S) async throws {
  // ... 共享 assertions
}
```

### `SelfHealingHistoryStore` 测试

`SelfHealingHistoryStoreTests.swift`，使用 `FakeHistoryStore`（按脚本抛错）：
- 第 1 次 upsert 抛 `.full`，evictOldest 返回 5 → 第 2 次成功
- 连续 3 轮均抛 `.full`，evictOldest 返回 0 → 抛 `.fullAndCannotEvict`
- 通知节流：连续 3 次同类失败仅观察到 1 次通知；恢复后再失败应再次通知

### `SQLiteHistoryStore` 测试

`SQLiteHistoryStoreTests.swift`：
- 临时目录路径，每个测试 `tearDown` 清理
- 冷启动恢复：写入 → 关闭 → 重新打开 → 数据完整
- Schema migration：从 v0（空 DB）到 v1
- WAL 崩溃恢复：写入半事务 → 模拟未 commit → 重开 → 数据应为上一致状态
- 错误码翻译：注入受控错误的 connection（通过把 DB 文件设为只读 / 写满临时分区）
- 孤儿清理：手动放置垃圾文件 → 启动 → 确认被清

### `ClipboardApp` 层测试

`Tests/ClipboardAppTests/`：
- `AppServices` 启动失败路径：mock 一个永远 open 失败的 store factory → 验证降级到 `InMemoryHistoryStore` + 状态栏徽标变黄
- `HistorySettingsView` 渲染各种存储状态徽标

### 手工验收（追加到 `docs/manual-acceptance-checklist.md`）

- 首次启动 → 复制几条 → 退出应用 → 重启 → 历史记录应保留
- maxCount = 50 → 复制 60 条 → 旧 10 条被删，pinned 保留
- pin 一条 → 调整 maxAgeDays / 系统时间至超过窗口 → pin 项保留
- `du -sh ~/Library/Application\ Support/<bundle-id>/` 持续观察 DB 增长
- 模拟磁盘满（小型 disk image 装 SQLite）→ 验证 Layer 1 自愈与 Layer 2 通知
- DB 文件删除后启动 → 应自动重建空 DB，无 crash
- DB 文件改为损坏的随机字节 → 应 backup 并新建，弹一次性提示

## 9. 改动清单

### 新增（10 个）

- `Sources/ClipboardCore/Storage/SelfHealingHistoryStore.swift`
- `Sources/ClipboardCore/Storage/SQLite/ApplicationSupportPaths.swift`
- `Sources/ClipboardCore/Storage/SQLite/SQLiteConnection.swift`
- `Sources/ClipboardCore/Storage/SQLite/SQLiteSchema.swift`
- `Sources/ClipboardCore/Storage/SQLite/SQLiteHistoryStore.swift`
- `Sources/ClipboardCore/Storage/SQLite/SQLitePayloadStore.swift`
- `Tests/ClipboardCoreTests/HistoryStoreConformanceTests.swift`
- `Tests/ClipboardCoreTests/SelfHealingHistoryStoreTests.swift`
- `Tests/ClipboardCoreTests/SQLiteHistoryStoreTests.swift`
- `Tests/ClipboardCoreTests/SQLitePayloadStoreTests.swift`

### 修改（6 个）

- `Sources/ClipboardCore/Storage/HistoryStore.swift` — 协议加 `count() / removeAll() / evictOldest()`，全部 `throws`，`InMemoryHistoryStore` 同步签名
- `Sources/ClipboardCore/Ingest/ClipboardIngestService.swift` — 适配 `throws` 签名（已是 throws，签名兼容）
- `Sources/ClipboardApp/AppServices.swift` — 装配 `SelfHealingHistoryStore(SQLiteHistoryStore)`，加启动失败降级路径
- `Sources/ClipboardApp/AppSettings.swift` — 加 4 个新 key
- `Sources/ClipboardApp/Settings/HistorySettingsView.swift` — 改依赖到 `any HistoryStore`，新增"保留策略"+"存储"section
- `Sources/ClipboardApp/StatusBar/StatusBarController.swift` — 三态徽标

### `Package.swift`

不变。`import SQLite3` 是系统 module，无需 link 配置。

## 10. 风险与缓解

| 风险 | 缓解 |
|---|---|
| SQLite C API 边界 bug（生命周期、参数绑定） | `SQLiteConnection` 严格用 `defer` 管理 statement / 连接；测试覆盖错误码翻译 |
| 27K 条冷启动加载阻塞 UI | 加载在 actor 内异步，QuickPanel 默认隐藏；首次显示前若未加载完，显示加载占位 |
| 内存索引与 DB 不一致 | DB 为唯一 source of truth；冷启动重建；写路径在 commit 后同步更新 |
| WAL 文件意外删除 | 启动时如果只剩 main DB 文件，WAL 缺失不影响打开（SQLite 自动恢复） |
| 用户手动改 DB 导致 schema 不匹配 | `PRAGMA integrity_check` + migration 检测；不匹配走 corruption 备份流程 |
| Layer 1 删除豁免项的 race condition | 在 actor 内单事务；evictOldest 只看豁免标志，不需要锁 |
| 6 个月内 payloads 目录文件数过多（>10K 文件） | macOS APFS 处理百万级文件的目录无问题；arrival 后期可加二级 hash 子目录（v2 优化项） |

## 11. 验收标准

1. `Scripts/verify.sh` 全部通过
2. `swift test --filter ClipboardCoreTests` 包含 conformance / self-healing / SQLite / payload 全部测试通过
3. `du -sh ~/Library/Application\ Support/<bundle-id>/` 在重度使用 1 周后保持 < 100MB（预期）
4. 手工验收清单所有项 ✓
5. 冷启动到 QuickPanel 可响应键盘事件 < 500ms（27K 条记录）
6. 单次复制写入到磁盘的端到端延迟 < 50ms（中位数）
