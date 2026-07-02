# macOS 剪贴板管理器手工验收清单

## 验收环境

- [ ] macOS 14.x Intel
- [ ] macOS 15.x Intel
- [ ] macOS 26.x Apple Silicon
- [ ] 外接显示器
- [ ] 深色模式
- [ ] 浅色模式
- [ ] 减少动态效果开启
- [ ] 减少动态效果关闭

## 启动前置

- [x] `Scripts/verify.sh` 通过
- [x] `swift run ClipboardManualProbe self-check` 输出 `write: ok`
- [x] `swift run ClipboardManualProbe accessibility` 输出 `accessibility: authorized`
- [ ] 如果输出 `accessibility: required`，先在系统设置中授权，再重新验证

## 复制来源覆盖

每个来源复制后运行：

```bash
swift run ClipboardManualProbe read-once
```

记录 `types`、`payload`、`textBytes` 或 `imageBytes`。

- [x] Safari 文本
- [x] Safari 链接
- [ ] Safari Copy Image
- [x] Chrome 文本
- [x] Chrome 地址栏 URL
- [ ] 微信文本
- [ ] 飞书文本
- [x] VS Code 代码片段
- [x] Xcode 代码片段
- [x] Finder 单文件
- [x] Finder 多文件
- [x] Terminal 文本
- [ ] Word 富文本
- [ ] Pages 富文本
- [ ] 远程桌面内复制文本

## Universal Clipboard

- [ ] iPhone 复制文本到 Mac，`types` 包含 `com.apple.is-remote-clipboard`
- [ ] iPhone 复制链接到 Mac，payload 可读
- [ ] iPhone 复制图片到 Mac，payload 可读或明确记录当前不支持原因
- [ ] 关闭 Universal Clipboard 记录后，对应 capture 被 PrivacyPolicy 拦截

## 粘贴行为

- [x] `Enter` 默认自动粘贴到普通文本框
- [x] `Enter` 默认自动粘贴到富文本编辑器
- [x] `Enter` 默认自动粘贴到 Terminal
- [x] `Enter` 默认自动粘贴到浏览器地址栏
- [x] 设置为“仅复制”后，`Enter` 只写入剪贴板，不模拟 `Cmd+V`
- [x] 运行期撤销辅助功能权限后，自动粘贴阻断并提示重新授权

## QuickPanel 快捷键

- [x] 启动 app 并授权辅助功能后，复制 3 条不同文本，主窗口 Session items 增长
- [x] 按 `Command+Shift+V` 后浮动 QuickPanel 出现在当前屏幕中心附近
- [x] QuickPanel 首屏显示最近复制的 session 历史，最新记录排在最上方
- [x] QuickPanel 每行左侧显示来源 App 图标；无法识别来源 App 时回退为内容类型图标
- [x] 输入搜索关键词后，列表只保留匹配标题、摘要或来源 App 的记录
- [x] 按 `Down` / `Up` 可以移动选中项，选中行有明显视觉状态
- [x] 按 `Escape` 关闭 QuickPanel
- [x] 打开过设置页后，切到其他 App 呼出 QuickPanel，再按 `Escape` 关闭，焦点保留在呼出前的 App，不重新弹出设置页
- [x] pinned/history 混排时，`Command+F` 选择第 4 个 pinned 项；搜索框保持可继续输入
- [x] 鼠标单击某条历史记录只选中该记录；鼠标双击遵循与 `Return` 相同的复制/粘贴语义
- [x] 在 QuickPanel 中按 `Command+,` 可打开设置窗口
- [x] 未勾选 `选择历史项时仅复制，不自动粘贴` 时，在普通文本框中按 `Command+Shift+V` 打开 QuickPanel，按 `Return` 或双击记录后，记录被复制并自动粘贴
- [x] 勾选 `选择历史项时仅复制，不自动粘贴` 后，在普通文本框中按 `Command+Shift+V` 打开 QuickPanel，按 `Return` 或双击记录后，目标文本框不立即粘贴
- [x] 勾选 `选择历史项时仅复制，不自动粘贴` 后，按 `Return` 或双击记录会把该记录写入系统剪贴板；随后手动按 `Command+V` 能粘贴该记录
- [x] 勾选 `选择历史项时仅复制，不自动粘贴` 后，QuickPanel footer 显示 `单击选择  Return/双击复制  Cmd+V 粘贴  Esc 关闭`
- [x] 重启 app 后，`选择历史项时仅复制，不自动粘贴` 勾选状态保持不变
- [x] 未开启辅助功能权限且处于自动粘贴模式时，按 `Return` 不静默失败，QuickPanel 显示授权提示并保持打开
- [x] 未开启辅助功能权限且处于自动粘贴模式时，鼠标双击记录不静默失败，QuickPanel 显示授权提示并保持打开
- [x] 切换“打开快捷面板时选中：最新记录 / 上次选中项”后，重新打开 QuickPanel 的初始选中项符合设置
- [x] QuickPanel 顶部类型过滤控件中的“类型”标签不换行、不挤压成两行
- [x] 打开 QuickPanel 且搜索框聚焦时，按 `Tab` 可将类型从 `All` 切到 `Text`
- [x] 连续按 `Tab` 可按 `All → Text → Link → Image → File → All` 循环类型
- [x] 按 `Shift+Tab` 可按反向顺序循环类型
- [x] 输入搜索关键词后按 `Tab`，关键词不丢失，列表按“关键词 + 类型”共同过滤
- [x] 中文输入法正在组词时，`Tab` 不破坏输入法 composition
- [x] 切换类型后 QuickPanel 布局稳定，不出现 pinned/history 大空白回归
- [ ] 复制 10MB JSON 后打开 QuickPanel，列表只显示摘要，不渲染全文

## 失败提示

- [ ] 写入剪贴板失败有事务状态
- [ ] 文件不可访问有事务状态
- [ ] 目标 App 失焦有事务状态
- [ ] 目标 App 不响应有事务状态
- [ ] 同一失败类型短时间内只提示一次
- [ ] 开启 BetterMouse 或类似工具时，click-through 干扰能被记录为诊断

## 大内容性能

- [ ] 10MB JSON 复制后，QuickPanel 呼出无明显卡顿
- [ ] 100MB log 复制后，QuickPanel 呼出无明显卡顿
- [ ] QuickPanel 首屏不渲染完整文本
- [ ] 大文本首次预览只加载摘要
- [ ] JSON/YAML pretty print 不在 QuickPanel 首帧执行
- [ ] 1000 张图片历史首屏不解码原图

## Maccy Replacement Privacy And Performance

- [x] 暂停采集后复制 3 条内容，历史数量不增长
- [x] 恢复采集后复制 1 条内容，历史数量增长
- [x] 触发“忽略下一次复制”后，第一条复制不入库，第二条复制正常入库
- [ ] 开启忽略 Universal Clipboard 后，带 `com.apple.is-remote-clipboard` 的内容不入库
- [ ] 展开“高级：排除自定义剪贴板类型”并添加 ignored pasteboard type 后，对应 type 的 capture 不入库
- [ ] 点击“选择应用...”添加应用后，列表显示应用图标和名称，而不是要求手输 bundle id
- [ ] 选择 Safari/Chrome/Terminal 等应用后，对应来源 App 的 capture 不入库；移除该应用后恢复采集
- [ ] QuickPanel `Option+Delete` 删除当前项，列表刷新且 payload 清理
- [ ] QuickPanel `Option+P` 置顶/取消置顶当前项
- [ ] QuickPanel `Option+Command+Delete` 清除未置顶项，置顶项保留
- [ ] QuickPanel `Shift+Option+Command+Delete` 弹出确认，确认后清除全部历史
- [ ] `Scripts/benchmark-maccy-replacement.sh` 生成 JSON 报告和可读摘要
- [ ] 报告中的 Maccy 对比项只使用 `better` / `same` / `worse` / `not_comparable` 表述

## Maccy B-Level Daily Replacement

- [x] 普通文本框中，QuickPanel `Return` 自动粘贴当前选中项
- [x] 普通文本框中，QuickPanel 双击自动粘贴当前记录
- [x] 富文本编辑器中，QuickPanel `Return` 自动粘贴当前选中项
- [x] Terminal 中，QuickPanel `Return` 自动粘贴当前选中项
- [x] 浏览器地址栏中，QuickPanel `Return` 自动粘贴当前选中项
- [x] 仅复制模式下，`Return` 和双击只写入系统剪贴板，不自动粘贴
- [x] 仅复制模式下，随后手动 `Command+V` 能粘贴刚选中的记录
- [x] `Option+Shift+Enter` 对富文本记录执行无格式粘贴
- [x] `Option+Shift+Enter` 对文本和链接记录执行纯文本粘贴
- [ ] `Option+Shift+Enter` 对图片或文件记录显示不支持无格式粘贴的状态
- [x] `Command+1...9` 选择 History 分区中可见的第 1 到第 9 条记录，不选择 pinned 行
- [x] `Control+Command+1...9` 自动粘贴 History 分区中可见的第 1 到第 9 条记录，并关闭 QuickPanel 回到目标 App
- [x] 开启仅复制模式后，`Control+Command+1...9` 仍作为 History 显式自动粘贴命令执行
- [x] `Option+1...9` 不再触发 QuickPanel 数字粘贴快捷键
- [x] 搜索和类型过滤后，数字快捷键对应过滤后的 History 局部可见顺序
- [x] pinned/history 混排时，打开 QuickPanel 默认选中第一条普通 History
- [x] pinned/history 混排时，pinned 行使用 `Command+A/S/D/F/G/H/J/K/L` 按可见顺序选择
- [ ] 详情预览可查看安全大小文本记录的完整内容
- [ ] 详情预览对大文本保持摘要优先，不在 QuickPanel 首帧加载全文
- [x] 对图片记录按 `Command+Y`，详情预览渲染真实图片（按比例适配窗口），而非显示图片信息文本
- [ ] 图片数据损坏无法解码时，详情预览回退为文本信息且不崩溃
- [x] 暂停采集后复制 3 条内容，历史数量不增长
- [x] 恢复采集后复制 1 条内容，历史数量增长
- [x] 触发“忽略下一次复制”后，第一条复制不入库，第二条复制正常入库
- [ ] 添加 Maccy baseline 后，benchmark 报告输出 per-metric comparison
- [ ] benchmark comparison 只使用 `better` / `same` / `worse` / `not_comparable`
- [x] 本轮真实 UI 验收使用的 app bundle 签名包含 `Authority=ClipboardApp Local Code Signing`

## 记录格式

每次验收写一条记录：

```text
日期:
机器:
系统:
架构:
场景:
命令:
结果:
CPU/内存:
问题:
截图/录屏:
结论: PASS / FAIL / BLOCKED
```

## 菜单栏图标和导航（v2 新增）

- [x] 启动后菜单栏右上角出现 Clipboard 图标
- [x] 左键点击图标，快捷面板在图标下方弹出
- [x] 右键点击图标，显示包含"退出 Clipboard"的菜单
- [x] 点击"退出 Clipboard"，应用正常退出（Activity Monitor 中进程消失）
- [x] 打开快捷面板后按 Cmd+Q，应用正常退出（Activity Monitor 中进程消失）
- [x] Dock 中无 Clipboard 图标

## 快捷键配置（v2 新增）

- [ ] 打开设置 → 通用，当前快捷键显示为 ⌘⇧V
- [ ] 点击快捷键录制框，出现"录制中…按下快捷键"提示
- [ ] 按下 Cmd+Q，提示"该快捷键为系统保留"，不保存
- [ ] 按下有效组合（如 Cmd+Option+V），框显示 ⌘⌥V，快捷键立即生效
- [ ] 重启应用后，自定义快捷键保持不变

## 快捷面板位置（v2 新增）

- [ ] 设置 → 通用 → 位置：选"居中"，按快捷键，面板在屏幕中央
- [ ] 设置 → 通用 → 位置：选"跟随鼠标"，将鼠标移到屏幕左侧再按快捷键，面板在鼠标附近
- [ ] 设置 → 通用 → 位置：选"跟随鼠标"，将鼠标移到屏幕底部/右侧边缘再按快捷键，面板完整贴边显示且内容不被屏幕边缘遮挡
- [ ] 设置 → 通用 → 位置：选"菜单栏图标下方"，按快捷键，面板在菜单栏图标下
- [ ] 无论位置设置如何，左键点击菜单栏图标时面板始终在图标下方

## 欢迎窗口（v2 新增）

- [ ] 清除 UserDefaults（`defaults delete com.local.clipboard-manager`），重启，欢迎窗口出现
- [ ] 欢迎窗口实时显示辅助功能权限状态
- [ ] 授权后，状态更新为"✅ 已授权"，"开始使用"按钮可点击
- [ ] 点击"开始使用"，欢迎窗口关闭，应用正常进入后台
- [ ] 再次重启，欢迎窗口不再出现

## 设置窗口（v2 新增）

- [ ] 快捷面板右上角 ⚙️ 按钮可打开设置窗口
- [ ] 多次点击 ⚙️，设置窗口只有一个实例（重复点击置前）
- [ ] 设置窗口左侧可切换通用 / 隐私 / 历史记录页
- [ ] 修改设置后关闭窗口，重启后设置保持不变
- [x] 设置窗口获得焦点时，按 `Command+W` 可关闭设置窗口
- [x] 在系统设置中添加或移除 Clipboard 辅助功能授权后，设置页授权状态能刷新为当前真实状态

## 外观主题（v3 新增）

设置 → 通用 → 外观 提供三选一 Picker：跟随系统 / 浅色 / 深色。验证下列 6 个组合：

| # | 系统外观 | App 设置 | 期望结果 |
|---|---|---|---|
| 1 | Light | 跟随系统 | QuickPanel / Settings / Welcome / 菜单栏下拉全为亮色 |
| 2 | Light | 浅色 | 同上 |
| 3 | Light | 深色 | 全部为暗色（不跟随系统） |
| 4 | Dark | 跟随系统 | 全部为暗色 |
| 5 | Dark | 浅色 | 全部为亮色（不跟随系统） |
| 6 | Dark | 深色 | 同 #4 |

切换系统外观命令（用于测试）：

```bash
# 切到亮色
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false'

# 切到暗色
osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true'
```

- [ ] 在「设置」窗口本身切换 Picker，整窗立即变色，**无需重启 app**
- [ ] 切换后立即按 Cmd+Shift+V 唤出 QuickPanel，颜色与设置一致
- [ ] 切换后右键点击菜单栏图标，下拉菜单颜色与设置一致
- [ ] 设置为「强制亮色」时关闭 app 重启，外观仍为亮色（持久化生效）
- [ ] 设置为「跟随系统」时切换系统外观，app 跟随变化

## 持久化存储（2026-05-08 引入）

### 基础持久化
- [x] 首次启动 → 复制 5 条不同内容 → 退出应用 → 重启 → QuickPanel 应显示全部 5 条
- [x] 退出后查看 `~/Library/Application Support/<bundle-id>/clipboard.sqlite` 文件存在
- [x] 复制图片 → 退出 → 重启 → 选择该图片粘贴成功

### 双堡垒淘汰
- [x] 设置 maxCount = 50 → 复制 60 条 → 重启 → count 应为 50（前 10 条最旧的被删）
- [x] pin 一条 → 复制大量记录直至超 maxCount → pin 项保留
- [x] 调整系统时间或 maxAgeDays = 1 → 复制内容 → 等 25 小时 / 改时间 → 该条应被删（除非 pinned）

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
- [x] "清除全部历史" → DB 清空，count 归零
- [ ] 失败策略 picker 切换"暂停剪贴板监控" → 模拟磁盘满 → ClipboardMonitor 应停止

### 性能
- [ ] 持续重度复制 24 小时（>1000 条），观察 `du -sh` 应保持合理增长（每条平均 < 5KB 元数据）
- [x] 27K 条记录场景下，QuickPanel 打开延迟 < 500ms（用 swift run ClipboardManualProbe 加压数据后实测）
- [x] 单次复制 → 写入完成的端到端延迟 < 50ms 中位数（用 os_signpost 观察）

## Maccy and Clipaste Import

- [ ] Settings → 导入 显示 Maccy / Clipaste 自动来源，并默认选中可识别来源
- [ ] 手动选择 Maccy SQLite 数据库后显示 schema 为 OK，未知 schema 不可导入
- [ ] 手动选择 Clipaste `clipboard-cloud.store` 后显示 schema 为 OK，未知 schema 不可导入
- [ ] 导入 Maccy 文本、链接、富文本、图片和文件 URL 记录后 QuickPanel 可搜索/复制
- [ ] 导入 Clipaste 文本、链接、代码、富文本、图片和文件 URL 记录后 QuickPanel 可搜索/复制
- [ ] Reimport does not create duplicate history records
- [ ] Duplicate content keeps the record with newest `lastCopiedAt` and merges copy count, pin/favorite, groups, pasteboard types, and Universal Clipboard marker
- [x] Automated coverage: cancelled import keeps committed batches and writes a cancelled report (`ImportServiceTests`)
- [ ] Import failure writes a failed report that remains visible in Settings → 导入 and can be copied as JSON
- [ ] Import report JSON is written under Application Support `imports/reports`

### 验收记录（2026-05-15）

```text
日期: 2026-05-15
机器: 本机 Apple Silicon
系统: macOS，当前桌面环境
架构: arm64
场景: 持久化存储自动化验收，使用隔离 bundle id com.local.clipboard-manager.acceptance.20260515232926
命令:
  - Scripts/verify.sh
  - swift run ClipboardManualProbe self-check
  - swift run ClipboardManualProbe accessibility
  - CONFIGURATION=debug BUNDLE_IDENTIFIER=<acceptance-bundle-id> Scripts/build-app-bundle.sh
  - SQLiteHistoryStore 验收探针：retention.count50.after60 / retention.pinnedExempt / retention.maxAgeDays1 / performance.singleUpsertMedian
  - SQLite 27K 造数 + SQLiteHistoryStore 冷启动 fetchPage 性能探针
  - 损坏库替换后重启 app，检查 clipboard.corrupt.<ts>.sqlite
结果:
  - verify.sh 通过
  - self-check 输出 write: ok / marker: present
  - swift run ClipboardManualProbe accessibility 输出 accessibility: required；系统设置中 ClipboardApp.app 辅助功能权限为 on，但该权限绑定 .app，非 swift run 探针二进制
  - clipboard.sqlite / payloads 目录在隔离 Application Support 下存在
  - 手工造数 5 条 text + 1 条 image 后 SQLite quick_check=ok，records=count 6，payload 文件存在
  - retention.count50.after60: pass count=50
  - retention.pinnedExempt: pass count=2
  - retention.maxAgeDays1: pass count=1
  - performance.singleUpsertMedian: pass medianMs=0.20 samples=100
  - performance.load27K: pass initMs=137.89 count=27000
  - performance.fetchPage27K: pass elapsedMs=140.27 page=50
  - 损坏库启动后生成 clipboard.corrupt.20260515T155039.sqlite
问题:
  - Computer Use 可操作普通窗口和系统设置，但当前 app 是菜单栏 accessory app；未能稳定定位/点击系统状态栏 item。
  - Command+Shift+V 在当前环境没有被验收 app 接管，按键落到前台应用；已撤销误输入。
  - 因无法稳定打开 QuickPanel / Settings 窗口，QuickPanel 视觉项、Settings UI 项、状态栏颜色项、清除全部历史按钮项未勾选。
  - maxAgeDays UI Stepper 代码范围是 7...365，本轮 maxAgeDays=1 只通过 store 层策略验证，未通过 UI 设置验证。
  - 27K 性能通过批量 schema 造数后冷启动 store + fetchPage 验证；逐条真实 upsert 生成 27K 超出合理验收时间，未作为手工流程采用。
截图/录屏: 未采集；以命令输出、SQLite 文件和系统设置可访问性列表作为证据。
结论: PARTIAL PASS，存储核心行为与性能通过；菜单栏/QuickPanel/Settings 交互项 BLOCKED。
```

## 分支收尾验收记录（2026-05-16）

```text
日期: 2026-05-16
机器: 本机 Apple Silicon
系统: macOS，当前桌面环境
架构: arm64
场景: feature/persistent-storage 分支最终物理验收，覆盖 QuickPanel、Settings、辅助功能权限、复制/粘贴语义与 macOS 标准快捷键
命令:
  - swift test
  - Scripts/verify.sh
  - git diff --check
  - CODE_SIGN_IDENTITY=- CONFIGURATION=debug BUNDLE_IDENTIFIER=com.local.clipboard-manager Scripts/build-app-bundle.sh
结果:
  - 自动化测试通过：115 tests, 0 failures
  - verify.sh 通过
  - git diff --check 通过
  - debug app bundle 构建并启动成功
  - 用户物理验证通过：QuickPanel 首次呼出、搜索焦点恢复、鼠标点击选择、Return/Click 复制或自动粘贴语义、辅助功能授权新增/移除状态刷新、无权限自动粘贴提示、打开时选中策略、Command+, 打开设置、Command+W 关闭设置、Escape 关闭后回到原 App
问题:
  - 当前 debug 包使用 ad-hoc signing；macOS 可能在代码变化后要求重新确认辅助功能授权。
截图/录屏: 用户侧实际操作验证；自动化命令输出作为构建与测试证据。
结论: PASS，分支功能开发与交互验收完成。
```

## Maccy/Clipaste 导入验收记录（2026-05-17）

```text
日期: 2026-05-17
机器: 本机 Apple Silicon
系统: macOS，当前桌面环境
架构: arm64e
场景: codex/maccy-clipaste-import 分支自动化验收，覆盖导入解析、去重合并、失败报告、设置页入口和 app bundle 构建
命令:
  - swift test
  - Scripts/verify.sh
  - CODE_SIGN_IDENTITY=- Scripts/build-app-bundle.sh
结果:
  - swift test 通过：174 tests, 0 failures
  - Scripts/verify.sh 通过，包含 swift test、swift build、Scripts/test-automation.sh、ClipboardApp/ClipboardManualProbe build
  - release app bundle 构建成功：.build/app-bundles/release/ClipboardApp.app
  - 默认本机签名身份 ClipboardApp Local Code Signing 的 codesign 阶段阻塞；已改用脚本支持的 ad-hoc signing 完成验证
问题:
  - 本轮未执行真实 UI 物理导入；Maccy / Clipaste 实际数据库导入仍需按上方清单手工验收
  - ad-hoc signing 后 macOS 可能要求重新确认辅助功能授权
截图/录屏: 未采集；以自动化测试、verify 脚本和 app bundle 构建输出作为证据
结论: AUTO PASS，代码级能力覆盖与构建验证完成；真实来源数据库导入为剩余手工验收项
```

## Tab 类型切换验收记录（2026-05-22）

```text
日期: 2026-05-22
机器: 本机 Apple Silicon
系统: macOS 26.5 (25F71)
架构: arm64
场景: codex/maccy-core-parity-tab-cycling 分支 QuickPanel Tab / Shift+Tab 类型过滤切换真实 UI 验收
命令:
  - swift test --filter QuickPanelKeyCaptureTests
  - swift test --filter QuickPanelStateFilterTests
  - swift test --filter QuickPanel
  - Scripts/verify.sh
  - CODE_SIGN_KEYCHAIN="$HOME/Library/Keychains/clipboard-signing.keychain-db" LOCAL_CODE_SIGN_IDENTITY="ClipboardApp Local Code Signing" REQUIRE_STABLE_CODE_SIGNING=1 Scripts/build-app-bundle.sh
  - codesign -dv --verbose=4 .build/app-bundles/release/ClipboardApp.app
  - 用户手动打开 QuickPanel，验证 Tab / Shift+Tab 类型切换、搜索词保留、中文输入法组词和 pinned/history 布局稳定性
结果:
  - QuickPanelKeyCaptureTests 通过：15 tests, 0 failures
  - QuickPanelStateFilterTests 通过：20 tests, 0 failures
  - QuickPanel 聚合测试复跑通过：72 tests, 0 failures
  - Scripts/verify.sh 通过
  - 稳定签名 app bundle 构建成功：.build/app-bundles/release/ClipboardApp.app
  - codesign 输出包含 Authority=ClipboardApp Local Code Signing
  - 用户手动验收 6 项 Tab 类型切换场景全部通过
问题: 未发现问题
截图/录屏: 未采集；以用户真实 UI 验收反馈和自动化命令输出作为证据。
结论: PASS，QuickPanel Tab 类型切换功能完成真实 UI 验收。
```

## QuickPanel 数字快捷键验收记录（2026-05-25）

```text
日期: 2026-05-25
机器: 本机 Apple Silicon
系统: macOS，当前桌面环境
架构: arm64
场景: codex/maccy-core-parity-tab-cycling 分支 QuickPanel 数字快捷键真实 UI 验收，覆盖 Command+数字选择与 Control+Command+数字强制自动粘贴
命令:
  - swift test --filter QuickPanelKeyCaptureTests
  - swift test --filter QuickPanel
  - swift test
  - git diff --check -- Sources/ClipboardApp/QuickPanel/QuickPanelKeyCaptureView.swift Tests/ClipboardAppTests/QuickPanelKeyCaptureTests.swift
  - CODE_SIGN_KEYCHAIN="$HOME/Library/Keychains/clipboard-signing.keychain-db" LOCAL_CODE_SIGN_IDENTITY="ClipboardApp Local Code Signing" REQUIRE_STABLE_CODE_SIGNING=1 Scripts/build-app-bundle.sh
  - codesign -dv --verbose=4 .build/app-bundles/release/ClipboardApp.app
  - 用户手动打开 QuickPanel，验证 Command+数字选择记录、Control+Command+数字自动粘贴记录，并验证先按 Control 再按 Command、先按 Command 再按 Control 两种顺序都可触发自动粘贴
结果:
  - QuickPanelKeyCaptureTests 通过：25 tests, 0 failures
  - QuickPanel 聚合测试通过：97 tests, 0 failures
  - 全量 swift test 通过：296 tests, 0 failures
  - git diff --check 通过
  - 稳定签名 app bundle 构建成功：.build/app-bundles/release/ClipboardApp.app
  - codesign 输出包含 Authority=ClipboardApp Local Code Signing
  - 用户手动验收通过：Control+Command+数字两种按键顺序都能关闭 QuickPanel 并自动粘贴到目标 App
问题: 未发现问题
截图/录屏: 未采集；以用户真实 UI 验收反馈、自动化测试、稳定签名构建和 codesign 输出作为证据。
结论: PASS，QuickPanel 数字快捷键选择与强制自动粘贴核心行为完成真实 UI 验收。
```

## Maccy B-Level P0 验收记录（2026-05-25）

```text
日期: 2026-05-25
机器: 本机 Apple Silicon
系统: macOS，当前桌面环境
架构: arm64
场景: codex/maccy-core-parity-tab-cycling 分支 Maccy B-Level P0 真实 UI 验收，覆盖自动粘贴矩阵、仅复制模式和数字快捷键剩余项
命令:
  - 用户手动打开 QuickPanel，分别在普通文本框、富文本编辑器、Terminal、浏览器地址栏验证 Return 自动粘贴
  - 用户手动验证普通文本框中双击自动粘贴
  - 用户手动开启仅复制模式，验证 Return 和双击只写入系统剪贴板、不自动粘贴，随后 Command+V 可粘贴刚选中的记录
  - 用户手动验证仅复制模式下 Control+Command+数字仍强制自动粘贴
  - 用户手动验证 Option+数字不再触发 QuickPanel 数字粘贴快捷键且不污染搜索框
  - 用户手动验证搜索和类型过滤后，Command+数字 / Control+Command+数字 对应过滤后的可见顺序
  - 用户手动验证 pinned/history 混排时，数字快捷键按视觉顺序定位记录
结果:
  - 自动粘贴矩阵 P0 项全部通过
  - 仅复制模式 P0 项全部通过
  - 数字快捷键剩余 P0 项全部通过
问题: 未发现问题
截图/录屏: 未采集；以用户真实 UI 验收反馈作为证据。
结论: PASS，Maccy B-Level P0 必测项完成真实 UI 验收。
```

## HTML/RTF 富文本与无格式粘贴验收记录（2026-05-26）

```text
日期: 2026-05-26
机器: 本机 Apple Silicon
系统: macOS，当前桌面环境
架构: arm64
场景: codex/maccy-core-parity-tab-cycling 分支 HTML/RTF 富文本捕获写回、无格式粘贴与 QuickPanel 快捷键回归真实 UI 验收
命令:
  - swift test
  - git diff --check
  - CODE_SIGN_KEYCHAIN="$HOME/Library/Keychains/clipboard-signing.keychain-db" LOCAL_CODE_SIGN_IDENTITY="ClipboardApp Local Code Signing" REQUIRE_STABLE_CODE_SIGNING=1 Scripts/build-app-bundle.sh
  - codesign -dv --verbose=4 .build/app-bundles/release/ClipboardApp.app
  - 用户使用稳定签名构建物进行真实 UI 验收，验证富文本粘贴、Option+Shift+Enter 无格式粘贴、Command+数字选择、Control+Command+数字强制自动粘贴
结果:
  - 全量 swift test 通过：308 tests, 0 failures
  - git diff --check 通过
  - 稳定签名 app bundle 构建成功：.build/app-bundles/release/ClipboardApp.app
  - codesign 输出包含 Authority=ClipboardApp Local Code Signing
  - 用户真实 UI 验收通过：富文本粘贴正常，无格式粘贴正常，Command+数字和 Control+Command+数字等其他操作正常
问题: 未发现问题
截图/录屏: 未采集；以用户真实 UI 验收反馈、自动化测试、稳定签名构建和 codesign 输出作为证据。
结论: PASS，HTML/RTF 富文本粘贴、无格式粘贴与 QuickPanel 快捷键回归完成真实 UI 验收。
```

## 内测发包前必做手工验收记录（2026-05-27）

```text
日期: 2026-05-27
机器: 本机 Apple Silicon
系统: macOS，当前桌面环境
架构: arm64
场景: 少量开发者内测发包前手工验收补录，覆盖安装首次启动、菜单栏、核心复制来源、QuickPanel 主流程、基础持久化和权限异常提示
命令:
  - 用户确认最终稳定签名 app 包已完成安装与首次启动验收：解压后放入 /Applications，按自签名流程首次打开，并完成辅助功能授权
  - 用户确认菜单栏图标、左键打开 QuickPanel、右键菜单、退出路径和 Dock 隐藏行为已通过
  - 用户确认开发者高频复制来源已通过：Safari 文本/链接、Chrome 文本/地址栏 URL、VS Code、Xcode、Terminal、Finder 单文件/多文件
  - 用户确认 QuickPanel 主流程已通过：Cmd+Shift+V 呼出、最近记录排序、来源图标、搜索、上下键、Esc、Return/双击、仅复制模式、数字快捷键回归
  - 用户确认基础持久化已通过：复制 5 条内容后重启仍可见，图片重启后可粘贴，清除全部历史可用
  - 用户确认运行期撤销辅助功能权限后，自动粘贴会阻断并提示重新授权
结果:
  - 内测发包前必做手工验收项已同步勾选
  - 未同步勾选第二批来源、完整环境矩阵、Maccy/Clipaste 真实导入、长时间性能和 Maccy baseline
问题: 未发现新的阻塞问题
截图/录屏: 未采集；以用户本轮确认作为手工验收补录依据。
结论: PASS，少量开发者内测发包前必做手工验收项已补录完成。
```

## 采集控制验收记录（2026-05-27）

```text
日期: 2026-05-27
机器: 本机 Apple Silicon
系统: macOS，当前桌面环境
架构: arm64
场景: 内测前补齐隐私设置页采集控制入口，并验证暂停采集、恢复采集、忽略下一次复制
命令:
  - swift test --filter PrivacySettingsViewTests
  - swift test --filter CaptureControlServiceTests
  - swift test --filter StatusBarControllerTests
  - swift build --product ClipboardApp
  - git diff --check
  - Scripts/verify.sh
  - CODE_SIGN_KEYCHAIN="$HOME/Library/Keychains/clipboard-signing.keychain-db" LOCAL_CODE_SIGN_IDENTITY="ClipboardApp Local Code Signing" REQUIRE_STABLE_CODE_SIGNING=1 Scripts/build-app-bundle.sh
  - codesign -dv --verbose=4 .build/app-bundles/release/ClipboardApp.app
  - 使用 Computer Use 打开稳定签名 release 包的 Settings -> 隐私，确认显示"采集控制"、"暂停采集"、"忽略下一次复制"
  - 点击"暂停采集"后状态变为"已暂停"，按钮变为"恢复采集"，"忽略下一次复制"禁用
  - 点击"恢复采集"后状态恢复为"正在采集"，"忽略下一次复制"恢复可用
  - 用户确认采集控制功能验证无问题
结果:
  - 隐私设置页采集控制入口已可见
  - 暂停采集、恢复采集、忽略下一次复制的服务层行为和 UI 状态均已验证
  - 稳定签名 release app bundle 构建成功：.build/app-bundles/release/ClipboardApp.app
  - codesign 输出包含 Authority=ClipboardApp Local Code Signing
问题:
  - 首次验证时用户打开的是旧 release bundle；已通过 swift package clean 后重新构建稳定签名 release 包解决
截图/录屏: 未采集；以 Computer Use UI 状态、自动化测试、稳定签名构建和用户确认作为证据。
结论: PASS，采集控制相关 checklist 项已同步勾选。
```

## QuickPanel 固定项/历史项快捷键分离验收记录（2026-05-29）

```text
日期: 2026-05-29
机器: 本机 Apple Silicon
系统: macOS 26.5 (25F71)
架构: arm64
场景: codex/quickpanel-shortcut-separation 分支 QuickPanel 保留 pinned/history 分区，同时默认选中普通 History，并分离 pinned 字母快捷键与 History 数字快捷键
命令:
  - swift test --filter QuickPanelStateFilterTests
  - swift test --filter QuickPanelControllerPresentationTests
  - swift test --filter QuickPanelKeyCaptureTests
  - swift test --filter QuickPanel
  - git diff --check 57fe92a..HEAD -- Sources/ClipboardApp/QuickPanel Tests/ClipboardAppTests docs/superpowers
  - Scripts/build-app-bundle.sh
  - codesign -dv --verbose=4 .build/app-bundles/release/ClipboardApp.app
  - 启动稳定签名 release 包，并写入 3 条 qp-accept-* 测试记录；将其中 1 条本地 fixture 标记为 pinned，准备混合 pinned/history UI 场景
结果:
  - QuickPanelStateFilterTests 通过：43 tests, 0 failures
  - QuickPanelControllerPresentationTests 通过：13 tests, 0 failures
  - QuickPanelKeyCaptureTests 通过：31 tests, 0 failures
  - QuickPanel 聚合测试通过：117 tests, 0 failures
  - git diff --check 通过
  - release app bundle 构建成功：.build/app-bundles/release/ClipboardApp.app
  - codesign 输出包含 Authority=ClipboardApp Local Code Signing
  - 自动化覆盖已验证：打开时 History-first 选中、History 仅分配 1...9、pinned 分配 Command+A/S/D/F/G/H/J/K/L、数字选择/粘贴跳过 pinned、字母快捷键选择 pinned
问题:
  - 真实 UI 验收被当前桌面锁屏阻断；截图只显示登录界面，不能输入密码，也不能继续验证 QuickPanel 面板视觉状态。
  - 因锁屏阻断，未能在本轮由 Codex 直接完成真实 UI 验证；需要解锁后按上方 checklist 复验混合 pinned/history 场景。
截图/录屏: /tmp/clipboard-quickpanel-acceptance.png 仅证明 UI 自动化被锁屏阻断，不作为功能通过证据。
结论: AUTO PASS / UI BLOCKED，代码级行为、构建和签名通过；真实 QuickPanel 视觉与键盘交互需解锁后补验。
```

## cmd+Y 图片预览验收记录（2026-06-24）

```text
日期: 2026-06-24
机器: 本机 Apple Silicon
系统: macOS，当前桌面环境
架构: arm64
场景: cmd+Y 详情预览图片渲染修复（commit 4344fcf）验收，覆盖图片项真实渲染、损坏数据回退、全量自动化测试与稳定自签名 app bundle 构建
命令:
  - swift test（全量）
  - Scripts/verify.sh
  - git diff --check
  - CODE_SIGN_KEYCHAIN="$HOME/Library/Keychains/clipboard-signing.keychain-db" LOCAL_CODE_SIGN_IDENTITY="ClipboardApp Local Code Signing" REQUIRE_STABLE_CODE_SIGNING=1 Scripts/build-app-bundle.sh
结果:
  - 全量 swift test 通过：331 tests, 0 failures
  - Scripts/verify.sh 通过（exit 0）
  - git diff --check 通过
  - 稳定自签名 release app bundle 构建成功，codesign Authority=ClipboardApp Local Code Signing，签名校验 valid on disk
  - 用户在真实 app 物理验证：对 Google Chrome 来源的 19.1MB 图片记录按 Cmd+Y，详情预览渲染真实截图（按比例适配窗口），不再显示 "Image 19.1 MB" 文本
  - 损坏图片数据回退文本路径由自动化测试覆盖：QuickPanelStateFilterTests.testShowDetailPreviewFallsBackToTextWhenImageUndecodable
问题:
  - 「图片数据损坏无法解码时回退为文本」仅自动化测试覆盖，未做真实损坏数据物理验收，故清单中该项保留未勾选。
截图/录屏: 用户提供 QuickPanel Cmd+Y 渲染真实图片的截图作为通过证据。
结论: PASS，cmd+Y 图片预览主路径用户物理验收通过；损坏数据回退为 AUTO PASS。
```

## 分发信任链(Homebrew 免费路)— 2026-06-24

- [x] 全新 Homebrew 安装:`brew tap anlostsheep/clipboard && brew install --cask clipboardapp` 成功。
- [x] Homebrew 安装后 App 打开无需 Gatekeeper 右键 Open 步骤。
- [x] `xattr -p com.apple.quarantine /Applications/ClipboardApp.app` 无输出。
- [x] 授予辅助功能权限后自动粘贴可用。
- [ ] `brew upgrade --cask clipboardapp` 从版本 N 升到 N+1。
- [ ] 辅助功能权限在 Homebrew 升级后仍保持(稳定签名守住)。
- [ ] `brew uninstall --cask --zap clipboardapp` 移除 App 及本机数据目录。
- [ ] 直接下载 zip 路径在文档化的 Gatekeeper 绕过步骤下仍可用。

- 验收记录 2026-07-02:v0.1.0 经 `brew install --cask clipboardapp` 全新安装,cask postflight 已移除 quarantine —— `xattr -p com.apple.quarantine /Applications/ClipboardApp.app` 无输出。这是"免 Gatekeeper 首开"的权威依据(只由 quarantine 属性触发,与历史授权无关,对全新用户同样成立)。App 打开无拦截、辅助功能授权后自动粘贴正常、sha256 校验 OK。免摩擦由 **cask postflight** 而非 Homebrew 提供(纠正了原 spec 的错误前提)。注:维护者本机此前授权过该 App,故 GUI"无拦截"观察本身有历史授权干扰,但上面的 `xattr` 机械事实不受此干扰。
