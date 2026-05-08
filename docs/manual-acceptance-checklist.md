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

- [ ] `Scripts/verify.sh` 通过
- [ ] `swift run ClipboardManualProbe self-check` 输出 `write: ok`
- [ ] `swift run ClipboardManualProbe accessibility` 输出 `accessibility: authorized`
- [ ] 如果输出 `accessibility: required`，先在系统设置中授权，再重新验证

## 复制来源覆盖

每个来源复制后运行：

```bash
swift run ClipboardManualProbe read-once
```

记录 `types`、`payload`、`textBytes` 或 `imageBytes`。

- [ ] Safari 文本
- [ ] Safari 链接
- [ ] Safari Copy Image
- [ ] Chrome 文本
- [ ] Chrome 地址栏 URL
- [ ] 微信文本
- [ ] 飞书文本
- [ ] VS Code 代码片段
- [ ] Xcode 代码片段
- [ ] Finder 单文件
- [ ] Finder 多文件
- [ ] Terminal 文本
- [ ] Word 富文本
- [ ] Pages 富文本
- [ ] 远程桌面内复制文本

## Universal Clipboard

- [ ] iPhone 复制文本到 Mac，`types` 包含 `com.apple.is-remote-clipboard`
- [ ] iPhone 复制链接到 Mac，payload 可读
- [ ] iPhone 复制图片到 Mac，payload 可读或明确记录当前不支持原因
- [ ] 关闭 Universal Clipboard 记录后，对应 capture 被 PrivacyPolicy 拦截

## 粘贴行为

- [ ] `Enter` 默认自动粘贴到普通文本框
- [ ] `Enter` 默认自动粘贴到富文本编辑器
- [ ] `Enter` 默认自动粘贴到 Terminal
- [ ] `Enter` 默认自动粘贴到浏览器地址栏
- [ ] 设置为“仅复制”后，`Enter` 只写入剪贴板，不模拟 `Cmd+V`
- [ ] 运行期撤销辅助功能权限后，自动粘贴阻断并提示重新授权

## QuickPanel 快捷键

- [ ] 启动 app 并授权辅助功能后，复制 3 条不同文本，主窗口 Session items 增长
- [ ] 按 `Command+Shift+V` 后浮动 QuickPanel 出现在当前屏幕中心附近
- [ ] QuickPanel 首屏显示最近复制的 session 历史，最新记录排在最上方
- [ ] QuickPanel 每行左侧显示来源 App 图标；无法识别来源 App 时回退为内容类型图标
- [ ] 输入搜索关键词后，列表只保留匹配标题、摘要或来源 App 的记录
- [ ] 按 `Down` / `Up` 可以移动选中项，选中行有明显视觉状态
- [ ] 按 `Escape` 关闭 QuickPanel
- [ ] 未勾选 `Return copies only` 时，在普通文本框中按 `Command+Shift+V` 打开 QuickPanel，选中记录后按 `Return`，记录被复制并自动粘贴
- [ ] 勾选 `Return copies only` 后，在普通文本框中按 `Command+Shift+V` 打开 QuickPanel，选中记录后按 `Return`，目标文本框不立即粘贴
- [ ] 勾选 `Return copies only` 后，`Return` 选择记录会把该记录写入系统剪贴板；随后手动按 `Command+V` 能粘贴该记录
- [ ] 勾选 `Return copies only` 后，QuickPanel footer 显示 `Return Copy  Cmd+V Paste  Esc Close`
- [ ] 重启 app 后，`Return copies only` 勾选状态保持不变
- [ ] 撤销辅助功能权限后，按 `Return` 不静默失败，footer 显示失败原因
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

- [ ] 启动后菜单栏右上角出现 Clipboard 图标
- [ ] 左键点击图标，快捷面板在图标下方弹出
- [ ] 右键点击图标，显示包含"退出 Clipboard"的菜单
- [ ] 点击"退出 Clipboard"，应用正常退出（Activity Monitor 中进程消失）
- [ ] Dock 中无 Clipboard 图标

## 快捷键配置（v2 新增）

- [ ] 打开设置 → 通用，当前快捷键显示为 ⌘⇧V
- [ ] 点击快捷键录制框，出现"录制中…按下快捷键"提示
- [ ] 按下 Cmd+Q，提示"该快捷键为系统保留"，不保存
- [ ] 按下有效组合（如 Cmd+Option+V），框显示 ⌘⌥V，快捷键立即生效
- [ ] 重启应用后，自定义快捷键保持不变

## 快捷面板位置（v2 新增）

- [ ] 设置 → 通用 → 位置：选"居中"，按快捷键，面板在屏幕中央
- [ ] 设置 → 通用 → 位置：选"跟随鼠标"，将鼠标移到屏幕左侧再按快捷键，面板在鼠标附近
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
