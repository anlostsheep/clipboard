# Maccy 日常自用差距补全设计（Daily Parity）

## 背景与目标

前几轮对标（2026-05-16 lightweight gaps、2026-05-22 core parity、2026-05-22 B-level daily replacement）已完成核心体验：搜索、类型筛选（Tab 循环）、置顶、删除/清空、数字快捷键、无格式粘贴、详情预览、自动粘贴/仅复制、隐私忽略体系、Maccy/Clipaste 导入、面板位置、外观模式、保留策略、Homebrew 分发。

本设计的目标定位是**日常自用达到 Maccy 水平**，补齐剩余的 5 个体验缺口。不面向公开发布的完整性项（本地化、菜单栏图标自定义）本轮不做。

## 范围：5 个独立切片（按优先级排序）

| # | 切片 | 价值 | 规模 |
|---|------|------|------|
| 1 | 开机自启（SMAppService） | 不自启无法当日常工具，最硬缺口 | 小 |
| 2 | 模糊搜索 + 命中高亮 | 搜索体感的最大差距 | 中 |
| 3 | 排序选项 | copyCount 已在存储层，激活它 | 小 |
| 4 | 菜单栏 Option+点击快捷操作 | 对齐 Maccy 暂停/忽略下一次交互 | 小 |
| 5 | 粘贴后面板行为（可选保留面板） | 连续粘贴多条的场景 | 小 |

切片彼此独立：任一切片完成即为可发布状态，中途可停。

## 非目标

- 搜索模式设置项（exact/regexp 切换）——只做模糊匹配为默认行为，不加设置。
- 轮询间隔可调。
- 本地化 / i18n。
- 菜单栏图标样式自定义、菜单栏显示最近一条。
- Sparkle 自动更新（维持零网络 + Homebrew 分发决策）、OCR、云同步、Library Window。
- 对完整 payload 大文本的深度搜索（维持只搜索索引字段：title / plainTextPreview / sourceAppName）。

## 切片 1：开机自启

### 设计

- 使用 `SMAppService.mainApp`（macOS 13+，项目最低要求 14+ 满足）。
- 设置页「通用」新增"登录时自动启动"开关，默认关闭，不做首启弹窗推销。
- **状态真源是 `SMAppService.mainApp.status`，不落 UserDefaults**：用户可能在系统设置里直接修改登录项，设置页每次出现时读取真实状态展示。
- `status == .requiresApproval` 时，开关旁展示提示与"打开系统设置"按钮（`SMAppService.openSystemSettingsLoginItems()`）。
- 新增小协议 `LoginItemManaging`（status 查询 + register/unregister + 打开系统设置），注入 mock 供测试；具体实现留在 ClipboardApp 层。
- 仅在从 .app bundle 运行时启用该开关；`swift run` 等非 bundle 场景禁用开关并说明原因。

### 已知限制

ad-hoc 签名的开发构建签名身份不稳定，SMAppService 注册可能失效或产生重复登录项。验收以稳定自签名构建（`ClipboardApp Local Code Signing`）为准，`docs/install.md` 或设置页提示中注明。

## 切片 2：模糊搜索 + 命中高亮

### 核心组件：FuzzyMatcher

新增 `FuzzyMatcher`（ClipboardCore，纯逻辑、零依赖、可单测）：

- 按字符子序列匹配（case-insensitive），按字符处理所以中文天然可用。
- 打分规则：连续命中加分、前缀命中加分（不依赖词边界概念，对 CJK 同样成立）；**substring 完整命中给最高档分**，保证现有搜索习惯的结果仍排最前。
- 返回 `(score, 命中区间 [Range<String.Index>])`，供列表高亮。

### 查询路径（不改存储层协议）

- **Plan 阶段修正**：现有实现中 `QuickPanelViewModel.refresh` 走 `store.fetchAll()` + 内存内 `HistoryQuery.matches` 过滤 + 内存内排序，SQLite store 本身持有全量内存索引（`indexByHash`），不存在 SQL 层文本过滤。因此模糊搜索直接落在 ViewModel：
  - query 为空 → 走现有路径，完全不变（排序见切片 3）。
  - query 非空 → 仍用 `fetchAll()` 拿全量，类型/分组过滤沿用 `HistoryQuery`（文本置空），文本匹配改用 FuzzyMatcher 对 title / plainTextPreview / sourceAppName 打分、过滤、排序。
- 候选集天然为全量内存索引（最高 5 万条轻量元数据字段，纯 Swift 打分预期毫秒级，输入侧已有 debounce）。合入前用仓库 benchmark 流程验证；若实测退化，降级为"最近 1 万条"并在本文档追记取舍。

### 排序语义（搜索激活时）

- Pinned 区仍固定在最上（保住 `Cmd+A~L` 映射稳定）。
- Pinned 与 History 两个分区内部各自按 fuzzy 得分降序，同分按 lastCopiedAt 降序。

### 高亮

- 行内 title/preview 用 AttributedString 渲染命中区间（加粗 + 着色）。
- 只对可见行计算高亮富文本；空 query 无高亮。

## 切片 3：排序选项

- 新枚举 `HistorySortOrder`：`lastCopied`（默认，现状）/ `firstCopied` / `copyCount`。
- **Plan 阶段修正**：排序真实发生在 `QuickPanelViewModel.quickPanelSort`（内存内），不在 SQL。因此不改 `HistoryQuery` 与两个 store，`QuickPanelViewModel.refresh` 增加 `sortOrder` 参数（带默认值，调用方兼容），排序比较器按其分支。`firstCopied` 使用已存在的 `createdAt` 列（schema 已确认，无迁移）。
- 设置项放「历史」页。
- 作用范围：只影响**空 query 浏览**时 History 区的排序；Pinned 区仍按 pinnedAt；搜索激活时按 fuzzy 得分（切片 2 语义）。数字快捷键跟随可视顺序（现有行为自动继承）。
- `firstCopied` 依赖首次复制时间列；plan 阶段确认现有 schema，若只有 createdAt 则直接用，不引入迁移。

## 切片 4：菜单栏 Option+点击快捷操作

- 状态栏左键点击处理器读取 `NSEvent.modifierFlags`：
  - 无修饰键：打开 QuickPanel（现状）。
  - **Option+点击：暂停/恢复采集**。
  - **Option+Shift+点击：忽略下一次复制**。
- 右键菜单不动，作为可发现性入口保留（菜单项已显示当前状态）。
- 暂停态图标反馈：换用带斜杠的 SF Symbol 表示暂停；与现有存储健康色（橙/红）叠加不冲突——形状表达暂停、颜色表达健康。
- 修饰键 → 动作的映射逻辑抽成可单测的纯函数；NSEvent 只在薄壳中读取。

## 切片 5：粘贴后面板行为

- 设置项"粘贴后保留面板"，**默认关**（= 现状，也是 Maccy 默认）。
- 开启时：选择粘贴/复制成功后面板不关闭、保持选中项，footer 显示结果；Esc 仍随时关闭。
- **风险与降级路径**：自动粘贴依赖"目标 App 在前台"才能投递 Command-V，现有流程是先关面板再恢复焦点。保留面板时必须验证焦点恢复仍可靠；若实测不可靠，该选项降级为只在"仅复制"模式下生效，并在本文档与验收清单中写明取舍。

## 测试与验收

### 自动化测试（每片独立）

- 切片 1：`LoginItemManaging` mock 各状态（enabled / notRegistered / requiresApproval / notFound）下的开关状态与提示逻辑。
- 切片 2：FuzzyMatcher 打分与命中区间（连续加分、前缀加分、substring 最高档、中文、不命中）；ViewModel 空 query 路径不变、fuzzy 路径过滤排序、分区语义；高亮区间传递。
- 切片 3：两个 store 的 `sortOrder` 行为对齐（lastCopied / firstCopied / copyCount）；默认值兼容。
- 切片 4：修饰键映射纯函数（无修饰 / Option / Option+Shift / 其它组合不响应）。
- 切片 5：keep-open 状态流转（成功粘贴后面板状态、选中保持、Esc 关闭）。

### 门禁与手工验收

- 每片完成过 `Scripts/verify.sh`。
- 每片在 `docs/manual-acceptance-checklist.md` 增补未勾选条目，物理验收通过后勾选并记日期。
- 切片 2 合入前跑 `Scripts/benchmark-maccy-replacement.sh` 确认搜索无退化。
- 全部切片完成后：以 `REQUIRE_STABLE_CODE_SIGNING=1` 出稳定自签名构建，按清单过整体手工矩阵；开机自启需真实重启机器验证一次。

## 完成标准

1. 5 个切片全部实现，各自针对性测试通过。
2. `Scripts/verify.sh` 通过。
3. `docs/manual-acceptance-checklist.md` 反映真实验收状态。
4. 稳定签名构建通过整体手工验收（含重启验证自启）。
5. 若切片 5 触发降级路径，取舍已在本文档追记。
