---
name: macos-native-clipboard-manager
description: macOS 原生高性能剪贴板管理器一期设计
type: product-design
---

# macOS 原生剪贴板管理器设计

## 背景

目标是设计一款 macOS 原生剪贴板软件，要求高性能、可靠、原生 UI、兼容 Apple Silicon 与 Intel，支持 macOS 14+，并重点优化 macOS 26。产品不使用 Electron。一期采用官网/DMG/Homebrew Cask 的 Direct 发行方式，App Store 沙盒版本后置。

设计参考 `/Users/lostsheep/programing/projects/Maccy` 与 `/Users/lostsheep/programing/projects/Clipaste`。Maccy 提供轻量、键盘优先、NSPasteboard 监听、Universal Clipboard 类型识别、macOS 26 workaround 等经验；Clipaste 提供 SwiftUI/SwiftData、CloudKit 同步、导入迁移、热缓存、分组和 onboarding 权限引导等经验。本设计不直接 fork 任一项目，而是吸收其架构经验和 issue 教训。

## 目标

一期目标是 Direct 发行的 macOS 原生剪贴板管理器 MVP，但不是简化玩具版。硬目标有三项：

1. 高频操作速度接近 Paste/Maccy 级别。
2. 1 万条以上历史、大文本、图片/文件混合场景下仍稳定流畅。
3. YAML/JSON/log 等大文本复制进入历史后，快捷键呼出 QuickPanel 不能卡顿。

## 非目标

以下不进入一期：

- 应用自己的 CloudKit 历史同步。
- App Store 沙盒版。
- 跨平台。
- 团队共享。
- OCR、AI 摘要、浏览器扩展。
- 复杂规则引擎。
- 直接控制系统 Universal Clipboard。

## 产品边界

### 系统剪贴板采集

监听 `NSPasteboard.general.changeCount`，记录文本、富文本、链接、图片、文件路径。默认过滤临时、隐藏、自动生成、密码类 pasteboard type。

### Universal Clipboard 接入

识别 `com.apple.is-remote-clipboard` 等系统 Universal Clipboard 标记，把来自 iPhone/iPad/其他 Mac 的内容记录进历史，并在 UI 中标记来源。

Universal Clipboard 是隐私风险，不只是功能点。一期必须在首次隐私模板中提供“是否记录 Universal Clipboard”选项，并提供单独分组、单独清理、单独关闭。

### 双 UI 模式

- `QuickPanel`：快捷键呼出，负责搜索、上下选择、复制/粘贴等高频路径。
- `LibraryWindow`：完整历史窗口，负责浏览、预览、分组、批量管理、导入、设置和诊断。

### 粘贴行为

默认 `Enter` 复制并自动粘贴。设置里可切换为 `Enter` 只复制到系统剪贴板，用户再手动 `Cmd+V`。

辅助功能权限是默认自动粘贴体验的启动前置条件，不是普通降级项。无权限时不能进入“看似可用但粘贴失败”的主体验。

### 预览与分组

预览可在设置中开关，且必须懒加载。

固定智能分组包括：

- 全部
- 文本
- 链接
- 图片
- 文件
- Universal Clipboard
- 收藏/置顶

同时允许用户新建自定义分组。

### 导入

一期支持 Maccy + Clipaste 历史导入。导入过程做去重、类型映射、批处理写入、导入报告和失败项统计。

导入不把任一参考项目的数据结构当作长期契约。每个 importer 只负责把源库转换成统一 `ImportedRecord`。

### 保留策略

历史按数量 + 时间双上限清理，任一条件触发都可清理。收藏/置顶不参与自动清理。

## 架构选择

一期采用 Swift 分层原生架构：

- SwiftUI + AppKit 构建原生 UI 和窗口行为。
- SwiftData/SQLite 负责本地持久化。
- 核心模块先用 Swift 实现。
- `Storage`、`Search`、`Import`、`Preview`、`ClipboardMonitor` 等通过协议隔离，后续可替换 Rust core。

不选择 Swift UI + Rust core 作为一期方案，原因是 FFI、签名、调试、打包、双架构发布链路会提高第一版复杂度。不选择直接改造 Maccy/Clipaste，原因是产品边界容易被原项目结构限制，后续重构和品牌化成本不可控。

## 组件设计

### ClipboardMonitor

负责监听 `NSPasteboard.general.changeCount`，读取 pasteboard items，识别来源 App、pasteboard type、Universal Clipboard 标记，执行隐私过滤。

它只产出标准化 `ClipboardCapture`，不直接写数据库、不直接驱动 UI。

### ClipboardIngestService

负责把 `ClipboardCapture` 转成内部 `ClipboardRecord`：计算内容 hash、判断重复、抽取标题、识别链接/图片/文件、生成轻量预览元数据。

它是采集层和存储层之间的缓冲，后续可以加入队列、背压和分级任务。

### HistoryStore

存储层接口，底层一期用 SwiftData/SQLite。职责包括 upsert、分页查询、按类型/分组过滤、置顶/收藏、保留策略清理、导入批处理事务。

UI 不直接依赖 SwiftData 模型，避免后续迁移困难。

### SearchIndex

搜索接口，支持标题、摘要、App、类型、分组过滤。第一版使用 SQLite 索引 + Swift 内存热缓存组合。

QuickPanel 默认不搜索完整大文本 blob。全文搜索作为异步能力返回，不阻塞普通搜索。

### PreviewService

负责图片缩略图、富文本预览、文件图标、链接摘要、大文本片段的懒加载与缓存。

QuickPanel 只加载轻量标题和小图标。LibraryWindow 按可见区域加载预览。

### PasteController

负责复制回系统剪贴板和自动粘贴。它隔离辅助功能权限检查、模拟 `Cmd+V`、目标 App 还原、失败分类和“Enter 只复制”配置。

粘贴必须是可观测事务，而不是一次黑盒调用。

### ImportService

以插件式 importer 支持 Maccy 与 Clipaste。每个 importer 输出统一 `ImportedRecord`，由统一导入管线做去重、映射、批处理写入和报告。

### PrivacyPolicyService

管理首次启动模板、忽略 App、忽略 pasteboard type、transient type、暂停监听、只忽略下一次复制等策略。

隐私规则必须可演进，不能硬编码散落在 monitor 中。

### MacOSCompatibilityLayer

集中处理 macOS 14/15/26 的 UI 与系统行为差异，避免 `#available` 散落在业务逻辑。

### UI Layer

包含 `QuickPanel` 和 `LibraryWindow`。两者共享服务接口，但 QuickPanel 只订阅轻量列表和选中状态，LibraryWindow 承担管理、预览、导入、设置和诊断。

## 组件边界依据

这套组件按 macOS App 的系统边界拆分：剪贴板访问、持久化、搜索、窗口交互、权限粘贴、导入迁移、隐私策略分别隔离。后续新增能力不会反复冲击 UI 或剪贴板监听主链路。

符合 macOS 设计规范的依据：

- macOS HIG 强调 Mac App 应利用大屏、多窗口、菜单栏、键盘快捷键和个性化配置。这支持 `QuickPanel` + `LibraryWindow` 双模式，而不是把所有能力塞进一个弹窗。
- `NSPasteboard` 是 App 与 pasteboard server 交互的接口，`general` pasteboard 会参与 Universal Clipboard，但没有用于直接控制 Universal Clipboard 的公开 macOS API。因此 `ClipboardMonitor` 只负责读取、识别和标准化，不设计成 iCloud 剪贴板控制器。
- SwiftData/CloudKit 同步需要 iCloud capability、Background Modes 和兼容 schema。把 `HistoryStore` 抽成接口，能让一期本地 store 先闭环，后续再增加 CloudKit store 或双 store。

支持后续迭代的依据：

- CloudKit 历史同步：扩展 `HistoryStore` 和同步/冲突层，不改采集、粘贴和 UI 操作语义。
- Rust core：替换 `SearchIndex`、导入解析、hash/去重或存储后端，不动 SwiftUI/AppKit 层。
- 新增 Paste/PasteNow/iCopy 导入：新增 importer 即可。
- App Store 版：主要处理沙盒、文件访问、权限和自动更新差异，核心业务层保持一致。
- OCR/AI/链接摘要：挂在 `PreviewService` 或独立 enrichment pipeline，不阻塞剪贴板采集。
- 高级隐私规则：扩展 `PrivacyPolicyService`。
- macOS 26 优化：集中在 UI layer、兼容层、列表渲染和预览懒加载，不影响数据契约。

## 数据模型

### ClipboardRecord

保存一条历史的稳定身份和轻量字段：

- `id`
- `contentHash`
- `primaryType`: text / richText / link / image / file
- `title`
- `plainTextPreview`
- `sourceAppBundleId`
- `sourceAppName`
- `sourceDeviceHint`: local / universalClipboard / imported
- `createdAt`
- `lastCopiedAt`
- `copyCount`
- `isPinned`
- `isFavorite`
- `groupIds`
- `retentionExempt`
- `metadata`
- `byteSize`
- `lineCountEstimate`
- `contentClass`: json / yaml / log / plain / code
- `isLargeContent`
- `blobStoragePolicy`
- `indexingState`
- `previewExcerpt`
- `tailExcerpt`

### ClipboardBlob

保存大内容或原始内容：

- 富文本原始数据
- 图片原图
- 文件列表
- 大文本完整内容
- 导入源原始 payload

### PreviewCache

保存缩略图、dominant color、文件图标、链接摘要、大文本片段缓存。

### ClipboardGroup

保存自定义分组和固定智能分组的用户排序。

### UserSettings

保存隐私模板、粘贴行为、预览开关、保留策略、记录类型开关、Universal Clipboard 记录开关。

## 数据流

### 采集数据流

正常复制路径：

```text
NSPasteboard.general.changeCount 变化
-> ClipboardMonitor 读取 items 和 types
-> PrivacyPolicyService 判断是否忽略
-> 生成 ClipboardCapture
-> ClipboardIngestService 标准化、计算 hash、识别类型、生成轻量标题
-> HistoryStore.upsert
-> SearchIndex.update
-> UI 收到轻量列表刷新
```

Universal Clipboard 路径与普通复制一致，只是在识别到 `com.apple.is-remote-clipboard` 后，把 `sourceDeviceHint` 标为 `universalClipboard`。

### 粘贴数据流

用户在 QuickPanel 选中记录：

```text
QuickPanel selection
-> PasteController.copy(record)
-> HistoryStore 读取完整内容或 blob
-> 写回 NSPasteboard
-> 校验本次写入 marker/type
-> 还原目标 App 焦点
-> 模拟 Cmd+V
-> 记录 PasteTransaction 结果
```

必须使用本产品自己的 pasteboard marker，防止自写入再次被采集成新历史。

### 导入数据流

```text
ImportService 选择源：Maccy / Clipaste
-> 对应 importer 读取 SQLite/SwiftData store
-> 输出统一 ImportedRecord
-> 统一管线做 hash、类型映射、分组映射、批量 upsert
-> 生成导入报告
```

### 查询数据流

快捷弹窗默认只取轻量列表字段和必要 preview token：

```text
SearchQuery + Filter
-> SearchIndex.search
-> HistoryStore.fetchPage(ids)
-> QuickPanelItemViewModel
```

完整窗口按可见区域向 `PreviewService` 请求富预览。大图片、大文本、文件元数据都懒加载。

### 清理数据流

后台维护任务定期执行：

```text
RetentionPolicy
-> 找出超过数量或时间上限的非置顶/非收藏记录
-> 删除主记录
-> 延迟清理无引用 blob / preview cache
-> 写清理日志或统计
```

## 大文本策略

YAML/JSON/log 等大文本是一期硬指标。大文本复制和展示不能进入 QuickPanel 呼出路径。

### 大文本判定

一期定义内部阈值：

- `largeText >= 64KB`
- `hugeText >= 1MB`
- `oversizedText >= 10MB`
- `extremeText >= 100MB`

阈值可配置，但内部逻辑必须有硬保护。

### 复制进入时处理

复制事件到来后，不在主线程完整解析大文本。

处理流程：

```text
ClipboardMonitor
-> 读取必要 pasteboard type 和 size hint
-> ClipboardIngestService 快速生成轻量信息
-> 原文写入 blob store
-> 后台低优先级生成索引或结构摘要
```

轻量信息包括：

- 分块 hash
- 前 N 字符摘要
- 后 N 字符摘要
- 行数估算
- 字节大小
- 可能类型：JSON/YAML/log/plain/code
- blob 是否完整保存

100MB 级文本必须支持策略：

- 只保存摘要 + metadata。
- 或询问是否保存完整内容。
- 或按设置保存完整 blob 但不索引全文。

### QuickPanel 展示

QuickPanel 永远不能渲染完整大文本。列表项只显示：

- 类型 badge：JSON / YAML / LOG / TEXT
- 标题：第一行或智能标题，限制 1-2 行
- 大小
- 行数
- 来源 App
- 状态：Full text saved / Preview only / Not indexed

禁止：

- 对完整文本使用 SwiftUI `Text(...)`。
- 在列表行做全文高亮。
- 在首屏格式化 JSON/YAML。
- 在打开弹窗时计算语法高亮。

### 预览

预览分层：

1. Quick preview：只展示前 2KB 或前 200 行。
2. Full preview：独立窗口/面板，使用文本虚拟化或 `NSTextView` 分块加载。
3. Structured preview：JSON/YAML 格式化必须用户手动触发并有大小限制。
4. Log preview：按行分页/窗口化，支持前后跳转，不全量渲染。

JSON/YAML 格式化规则：

- 小于 1MB 可自动 pretty print。
- 1MB-10MB 手动格式化。
- 超过 10MB 默认不格式化，只做原文查看和搜索。

### 搜索

QuickPanel 默认搜标题、摘要、来源、类型、少量前缀，不搜完整大文本。

Full search 可异步搜 blob，显示“正在搜索大文本内容”，结果延迟返回，不阻塞弹窗。

搜索结果要标明来自摘要还是全文。

## UI 与交互

### QuickPanel

QuickPanel 是第一优先级，因为它承载最常用路径：快捷键呼出、输入搜索、上下选择、Enter 动作。

默认行为：

- 全局快捷键呼出。
- 输入即搜索。
- 上下键选择。
- `Enter` 默认复制并自动粘贴。
- 设置可切换为 `Enter` 只复制到剪贴板。
- 支持修饰键动作，例如纯文本粘贴、删除、收藏/置顶。
- 无辅助功能权限时阻断并引导授权，不静默改成只复制。

QuickPanel 首屏只加载轻量字段：标题、类型、来源 App、时间、Universal Clipboard 标记、小图标或 preview token。

### LibraryWindow

LibraryWindow 用于低频但复杂的管理工作：

- 浏览完整历史。
- 固定智能分组。
- 用户自定义分组。
- 开关预览。
- 查看富文本/图片/文件/大文本详情。
- 批量删除、移动分组、收藏/置顶。
- 导入 Maccy / Clipaste。
- 查看导入报告、粘贴失败诊断、清理统计。
- 打开设置。

完整窗口必须分页或虚拟列表渲染，不能一次性把所有历史塞进 SwiftUI 状态。

### macOS 26 性能策略

- 弹窗窗口用 AppKit 控制生命周期、焦点、层级和屏幕定位，SwiftUI 负责内容。
- 列表行高度稳定，避免动态预览撑开导致滚动抖动。
- 预览可开关且懒加载。
- 大文本只展示摘要，完整内容按需读取。
- 图片先使用缩略图缓存，避免主线程解码原图。
- 搜索结果分页或限制首屏数量。
- 采集、导入、预览生成、清理任务不能阻塞主线程。
- macOS 26 文本截断、hover、gesture、visual effect 差异集中适配。

## 权限、隐私与错误处理

### 权限策略

首次启动必须进入权限引导。未授权时，用户不能完成完整初始化，也不能进入“看似可用但粘贴失败”的主体验。

引导页提供：

- 为什么需要权限：用于全局快捷键可靠捕获、模拟 `Cmd+V` 自动粘贴。
- 打开系统设置入口。
- 重新检测权限按钮。
- 授权成功后继续 onboarding。

如果用户运行期撤销权限，QuickPanel 和 LibraryWindow 都显示明确阻断状态：自动粘贴不可用，需要重新授权。

“Enter 只复制到剪贴板，之后用户手动 `Cmd+V`”保留为用户主动配置项。它不是无权限 fallback。

### 隐私模板

首次启动选择隐私模板：

- 标准模板：记录常用类型，默认忽略临时、隐藏、自动生成、密码类 pasteboard type。
- 保守模板：除标准过滤外，默认忽略密码管理器、隐私浏览器、终端/SSH 类 App。
- 自定义模板：用户选择记录类型、忽略 App、忽略 pasteboard type、是否记录 Universal Clipboard。

运行中提供：

- 暂停监听。
- 只忽略下一次复制。
- 忽略当前 App。
- 清空全部历史。
- 清空非收藏历史。
- 单条删除。
- 删除单条原始 blob，仅保留轻量 metadata。

### PasteTransaction

粘贴事务必须标准化：

```text
preparePayload
-> writePasteboard
-> verifyPasteboard
-> restoreTargetApp
-> postCmdV
-> observeTimeout
-> complete / fail
```

失败类型：

- `recordMissing`
- `blobMissing`
- `fileUnavailable`
- `formatUnsupported`
- `pasteboardWriteFailed`
- `accessibilityRevoked`
- `targetAppFocusLost`
- `pasteEventFailed`
- `targetAppRejectedPaste`

失败反馈规则：

- 单次失败给轻提示。
- 同类失败 30-60 秒内只提示一次。
- 当前条目保留警告状态。
- 连续失败升级为可关闭状态条：“最近 N 次复制失败，查看原因”。
- 诊断页保留最近失败原因。
- 成功后清除对应 warning 状态。

富文本写入失败时可以尝试纯文本 fallback，但必须明确提示“已改用纯文本复制”，不能静默假装完整成功。

### 采集错误

- 单个 pasteboard item 解析失败时跳过该 item，记录诊断，不停止监听。
- 超大内容只保存摘要和 metadata，blob 延迟写入或按策略跳过。
- 文件路径不可访问时记录路径 metadata，不强行读取文件内容。

### 存储错误

- 主库打不开时进入阻断状态，提示修复、重建索引或导出诊断。
- 单条 blob 写入失败不阻断主记录，但标记 `blobMissing`。
- upsert 失败不反复重试刷屏，要有节流和诊断记录。
- 数据库损坏时不能 `fatalError`，应备份坏库并重建或进入修复流程。

### 搜索错误

- 索引损坏时回退到基础查询，并后台重建。
- 搜索超时优先返回前 N 条，保持 UI 可操作。

### 导入错误

- 批处理导入，单条失败不回滚整个导入。
- 报告成功、重复跳过、失败、降级记录。
- 未知 schema 明确提示“不支持此版本数据库”。

### 设置错误

所有设置项要有 schema validation。超出范围时当场提示并回滚或修正，不允许静默保存失败。

高风险确认框的“不要再问”必须独立测试。

## 从 Maccy issue 吸收的经验

### 自动粘贴失败不能静默

Maccy issue 显示自动粘贴存在多类失败：自动粘贴失效、选择后不再粘贴、第三方鼠标工具 click-through 干扰、点击条目不复制。

本产品必须把粘贴动作做成可观测事务，区分权限、剪贴板写入、目标 App 失焦、第三方工具干扰和目标 App 不响应。

### 大历史和预览是核心性能风险

Maccy 近期 PR 将大历史浏览、预览内存、全量 hydrate、搜索取消、缩略图缓存作为重点优化。相关 issue 涉及大内容弹窗慢、复制时 CPU 高、大文本冻结、内存高。

本产品从一期开始禁止 QuickPanel 全量 hydrate 历史，禁止大文本和原图进入首屏渲染。

### macOS 26 要专项适配

Maccy 已遇到 macOS 26 文本截断 100% CPU、文字翻转、并发崩溃、图片不入历史等问题。

本产品必须有 `MacOSCompatibilityLayer` 和 macOS 26 专项验收。

### Universal Clipboard 是隐私风险

Maccy issue 显示 Universal Clipboard 会把 iPhone/iPad 个人内容记录进工作 Mac 历史，也可能显示成奇怪文件路径。

本产品必须让 Universal Clipboard 进入隐私模板选择，UI 明确标记来源，并支持关闭和单独清理。

### 隐私过滤规则必须可演进

1Password 等密码管理器 pasteboard type 会变化。用户还需要自定义 transient types。

本产品必须支持用户添加/编辑 ignored pasteboard types、transient types、ignored apps，并且忽略 App 不限制 `/Applications`。

### 不允许设置静默失败

Maccy issue 显示历史数量设置和“Don't ask again”存在静默失败体验。

本产品设置保存必须有校验、错误提示和测试。

## 测试与验收

### 功能测试

- 纯文本、富文本、链接、图片、文件路径都能记录。
- Universal Clipboard 内容能识别并标记来源。
- 用户关闭 Universal Clipboard 记录后，不再进入历史。
- 自写入 marker 不会造成重复记录。
- `Enter` 默认自动粘贴。
- 配置为“仅复制”后，`Enter` 只写入剪贴板，不模拟 `Cmd+V`。
- 无辅助功能权限时，启动阶段阻断并引导授权。
- 运行期权限被撤销时，粘贴动作阻断并提示重新授权。
- 写入剪贴板失败、blob 缺失、文件不可访问、目标 App 不响应时，有节流提示和诊断记录。
- 同一失败类型短时间内不反复弹提示。
- Maccy 和 Clipaste 导入能映射到统一模型。
- 单条导入失败不回滚整个导入。
- 未知 schema 明确失败，不静默跳过。
- 忽略 App、忽略 pasteboard type、忽略 transient type 生效。
- 忽略 App 支持任意路径，不限 `/Applications`。
- 设置保存失败不静默。

### 性能验收

一期硬门槛：

- 快捷键呼出 QuickPanel：P95 <= 150ms，P99 <= 250ms。
- 输入搜索首批结果：P95 <= 100ms。
- 上下键移动选中：P95 <= 16ms。
- `Enter` 到剪贴板写入完成：P95 <= 80ms。
- 自动粘贴事件发出：写入成功后 <= 200ms。
- 1 万条历史启动后 warm idle 内存：目标 <= 150MB。
- 1 万条历史打开 QuickPanel：不全量 hydrate，内存增长 <= 50MB。
- 10MB JSON 复制后，App 主线程不可卡顿超过 100ms。
- 100MB log 复制后，QuickPanel 呼出 P95 仍 <= 150ms。
- QuickPanel 列表项渲染大文本记录时，不读取完整 blob。
- 大文本记录首次预览只加载 <= 2KB 或 <= 200 行。
- JSON/YAML pretty print 不在 QuickPanel 首帧执行。
- 大文本搜索不阻塞普通搜索结果返回。
- 100MB 文本不会导致 SwiftUI `Text` 渲染、CoreText 测量或高亮进入主列表路径。
- 图片历史 1000 条：首屏不解码原图，只使用缩略图。
- 导入 1 万条历史：UI 可取消，进度可见，失败项可报告。

### macOS 兼容测试

主测矩阵以当前可获得的实机为准：

- macOS 14.x Intel
- macOS 15.x Intel
- macOS 26.x Apple Silicon
- 外接显示器、多屏菜单栏位置
- 深色/浅色模式
- 减少动态效果
- 不同键盘布局，尤其 `Cmd+V` keyCode 处理

补充验证不作为一期阻断门槛：

- macOS 14.x Apple Silicon
- macOS 15.x Apple Silicon

发布产物按架构拆分为 Intel 包和 Apple Silicon 包，不发布单一 Universal Binary 包。两个包必须来自同一源码和同一版本号，下载页、更新清单与 Homebrew Cask 需要明确区分 `intel` / `apple-silicon` 产物，避免用户装错架构。

虽然发行包拆分，源码兼容目标不能收窄：Intel 包至少覆盖 macOS 14.x / 15.x Intel 主测矩阵，Apple Silicon 包至少覆盖 macOS 26.x Apple Silicon 主测矩阵。

macOS 26 专项：

- 文本截断不使用会触发异常测量的布局方式。
- hover/gesture 不依赖透明无背景区域。
- QuickPanel 打开关闭不出现 100% CPU。
- 图片复制、截图复制、Safari Copy Image 均能记录。
- Swift concurrency 任务取消和 UI 更新不触发崩溃。

### 可靠性测试

- 数据库损坏时不 `fatalError`。
- blob/cache 缺失时主记录仍可显示，并给出状态。
- 索引损坏时可重建。
- 导入中断后可恢复或重新导入。
- 设置文件损坏时回退默认值并提示。

### 手工验收场景

- 从 Safari、Chrome、微信、飞书、VS Code、Xcode、Finder、Terminal、Word、Pages、远程桌面复制。
- 从 iPhone Universal Clipboard 复制文本、图片、链接到 Mac。
- 开启/关闭 BetterMouse 或类似工具，验证自动粘贴失败提示。
- 粘贴到普通文本框、富文本编辑器、终端、浏览器地址栏、文件选择器。
- 同一内容多次复制不重复刷历史。
- 大文本、大图片、文件夹路径不会拖慢面板。

## 实施顺序建议

1. 建立 Swift 原生项目骨架、菜单栏 App、权限 onboarding、全局快捷键和 QuickPanel 空壳。
2. 实现 `ClipboardMonitor`、`PrivacyPolicyService`、基础文本采集和自写入 marker。
3. 实现 `HistoryStore`、轻量 `ClipboardRecord`、分页查询和保留策略。
4. 实现 `PasteController` 与 `PasteTransaction`，完成自动粘贴和失败反馈。
5. 实现大文本分层存储、摘要展示和 QuickPanel 性能保护。
6. 扩展图片、富文本、文件路径、Universal Clipboard。
7. 实现 `SearchIndex`、可取消搜索和轻量索引。
8. 实现 `PreviewService`、缩略图缓存和大文本 viewer。
9. 实现 LibraryWindow、分组、设置和诊断页。
10. 实现 Maccy / Clipaste 导入。
11. 完成 macOS 26 专项适配和性能压测。

## 风险与取舍

- 辅助功能权限是核心能力前置，会增加首次启动摩擦，但比无权限静默失败更符合产品目标。
- CloudKit 历史同步后置，会让“一期多 Mac 历史同步”缺席，但可以避免第一版同时承担 iCloud schema、冲突合并和签名配置复杂度。
- 大文本默认不进入全文索引，会牺牲一些搜索完整性，但换来 QuickPanel 呼出速度和复制主路径稳定性。
- Direct 发行优先能减少沙盒限制，但后续 App Store 版需要单独做权限和功能差异设计。

## 一期默认决策

- 100MB 级文本默认只保存摘要、首尾片段和 metadata，不默认保存完整 blob。用户可在设置中开启“保存极大文本原文”，但 QuickPanel 仍不得读取完整 blob。
- 一期默认体验要求完成辅助功能授权。“只复制模式”是授权完成后的交互偏好，不作为绕过权限 onboarding 的路径。
- 大文本全文搜索一期只保留接口和异步任务状态，不作为默认验收能力。QuickPanel 搜索只覆盖标题、摘要、来源、类型和轻量索引。
- Clipaste 导入只读取用户选择的本地数据源，不隐式读取或操作 CloudKit 私有缓存库。
- 分组显示顺序固定为：全部、类型智能分组、Universal Clipboard、收藏/置顶、自定义分组。自定义分组不改变智能分组归属，同一记录可以出现在多个分组。
