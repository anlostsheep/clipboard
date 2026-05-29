# QuickPanel 固定项/历史项快捷键分离设计

## 目标

在保留现有 pinned/history 分区结构的前提下，让存在固定项时的 QuickPanel 更容易操作。

当前面板会正确地把固定项展示在普通历史上方，但这也导致固定项拿走打开面板时的初始选中位置，并占用现有的 `Command+1...9` 行快捷键。新行为应继续让固定项保持可见和靠前，同时把普通历史作为默认键盘目标。

## 当前代码事实

- `QuickPanelViewModel.refresh` 会先按 pinned 状态排序，再排列未固定记录。
- `QuickPanelListPolicy.limitedItems` 会在固定项超过页限制时保留一部分未固定历史。
- `QuickPanelItemSection.make` 会把已经排序后的 `items` 拆成 `.pinned` 和 `.history` 两个 section，同时保留每一行的全局 item index。
- `QuickPanelState.prepareForPresentation` 和 `QuickPanelState.applyRefresh` 负责打开面板时的选中索引行为。
- `QuickPanelKeyCaptureView` 当前把 `Command+1...9` 映射为可见行选择，把 `Control+Command+1...9` 映射为可见行粘贴。
- `QuickPanelView.numberShortcut(for:)` 当前按全局行索引显示数字 badge，因此 pinned 行会拿到前几个数字 badge。

## 已确认方向

保留两个视觉分区：

1. Pinned section 继续位于 History 上方。
2. History section 继续位于 Pinned 下方。
3. 打开面板时优先选中第一条 History 行。
4. Pinned 和 History 使用两套独立的键盘空间。

这个方向避免较大的布局重写，同时解决主要交互问题：固定项应该保持可见和可访问，但不应该挤占高频普通历史的键盘流程。

## 交互规则

### 打开时选中

QuickPanel 打开时：

- 如果至少有一条可见的未固定 History 项，选中第一条可见 History 行。
- 如果没有可见 History 项，但存在 pinned 项，选中第一条 pinned 行。
- 如果用户设置为“上次选中项”，且上次选中的记录仍然可见，则保留现有 previous-selection 行为。
- 如果上次选中的记录已经不可见，则回退到同一套 History-first 规则。

这意味着在 pinned/history 混合场景下，“最新记录”语义会变成“存在普通历史时选中最新普通历史”。只有 pinned 的列表仍然自然选中 pinned 第一项。

### History 快捷键

History 行只使用数字快捷键：

- `Command+1...9` 选择可见 History 的第 1 到第 9 行。
- `Control+Command+1...9` 粘贴可见 History 的第 1 到第 9 行。
- 数字快捷键不选择、也不粘贴 pinned 行。
- 本轮设计刻意不增加 `Command+0` 作为第 10 条 History 的快捷键。

History 中可见的快捷键 badge 应按 History 局部顺序显示 `1...9`，不再按全局列表顺序显示。

### Pinned 快捷键

Pinned 行使用字母快捷键：

- `Command+A`
- `Command+S`
- `Command+D`
- `Command+F`
- `Command+G`
- `Command+H`
- `Command+J`
- `Command+K`
- `Command+L`

映射按 pinned 行可见顺序自动分配。第一条可见 pinned 行使用 `A`，第二条使用 `S`，依此类推。

如果可见 pinned 行多于可用字母，超出的 pinned 行仍然可以通过鼠标和方向键选择，但本轮不分配字母快捷键。

Pinned 行应在当前数字 badge 的位置显示紧凑的 `⌘A` 样式 badge。如果某条 pinned 行没有分配快捷键，可以继续显示现有 pin 图标。

### 搜索和过滤

快捷键分配跟随当前可见且已过滤后的 section：

- 搜索或切换类型过滤后，重新计算可见的 Pinned 和 History section。
- History 数字应用到过滤后的 History section。
- Pinned 字母应用到过滤后的 Pinned section。
- 缺失局部索引对应的快捷键不执行任何动作。

这保持了现有“按过滤后的可见顺序触发快捷键”的行为，只是把索引空间按 section 拆开。

## 非目标

- 不把 QuickPanel 重设计为单一统一列表。
- 暂不引入每条 pinned 项自定义快捷键。
- 暂不增加 `Command+0` 作为第 10 条 History 的快捷键。
- 暂不增加 pinned 字母直接粘贴快捷键。
- 不修改 pinned 记录的持久化 schema。
- 不修改 QuickPanel 的全局呼出快捷键行为。
- 不修改 Return、双击、仅复制模式或无格式粘贴语义。

## 实现形态

### Section 局部快捷键映射

在 QuickPanel presentation/state 代码附近引入一个小的 section 局部映射层：

- History 局部索引 `0...8` 映射为数字 `1...9`。
- Pinned 局部索引 `0...8` 映射为字母 `A/S/D/F/G/H/J/K/L`。

该映射应是确定性的，并且可以在不依赖 SwiftUI 渲染的情况下测试。

### 键盘捕获

扩展 `QuickPanelKeyCaptureView.KeyboardAction`，增加 pinned 字母选择动作，例如：

- `selectPinnedShortcut(Int)`

本轮保持与现有快捷键一致的 modifier 模型：

- `Command+letter` 选择 pinned 项。
- 暂不增加 `Control+Command+letter` pinned 直接粘贴；现有 `Control+Command+1...9` 直接粘贴保持为 History-only。

### State 语义

`QuickPanelState` 应按 section 局部顺序解析快捷键，而不是按全局行顺序解析：

- `selectHistoryShortcut(number:)`
- `pasteHistoryShortcut(number:)`
- `selectPinnedShortcut(slot:)`

这些方法在用户动作前应沿用现有 stale-query guard 模式，必要时先 refresh 再执行。

### View 渲染

`QuickPanelView` 应把 section 局部快捷键信息传给 row rendering，而不是继续从全局 `row.index` 推导数字 badge。

本轮行样式保持紧凑即可。App 图标和来源 App 名称先保持现状，除非验证发现快捷键分离后面板仍无法展示足够多的 History 行。第一轮实现应避免把行密度调整和快捷键语义调整混在一起。

## 测试

重点测试应覆盖：

- pinned/history 混合列表在 latest-record 行为下打开时选中第一条 History 行。
- pinned-only 列表打开时仍选中第一条 pinned 行。
- previous-selection 行为在上次选中记录仍可见时保持该选择。
- previous-selection 在上次记录不可见时按 History-first 规则回退。
- `Command+1...9` 只按 History 局部顺序映射。
- `Control+Command+1...9` 只按 History 局部顺序粘贴。
- `Command+A/S/D...` 按 Pinned 局部顺序映射。
- 搜索和类型过滤后会重新计算 section 局部快捷键分配。
- 超出范围的数字或字母快捷键不执行动作、不崩溃。
- 现有 QuickPanel 键盘测试中 Return、Escape、Tab、危险操作快捷键、无格式粘贴、详情预览仍然通过。

推荐验证命令：

```bash
swift test --filter QuickPanel
```

如果实现广泛触碰键盘捕获，也需要单独运行：

```bash
swift test --filter QuickPanelKeyCaptureTests
```

## 手工验收

在已签名或本地可运行构建验证后，向 `docs/manual-acceptance-checklist.md` 增加或更新带日期的记录：

- 同时存在 pinned 和普通 history 时，打开 QuickPanel 选中第一条普通 History 行。
- `Command+1...9` 只选择普通 History 行。
- `Control+Command+1...9` 只粘贴普通 History 行。
- `Command+A/S/D...` 按可见顺序选择 pinned 行。
- 搜索或类型过滤后仍保持同样的 section 局部快捷键行为。
- 现有 Return、双击、仅复制模式和无格式粘贴行为仍然正常。

## 风险

- `Command+H` 是常见 macOS 隐藏快捷键。由于 QuickPanel 只在自身聚焦时捕获本地事件，初版左手映射可以接受，但实现后应验证它不会意外隐藏应用。
- 字母快捷键可能和文本输入预期冲突。它们必须只在 QuickPanel 内部、且只在精确 `Command` modifier 下触发。
- 默认选中行为变化可能影响习惯把 pinned 项作为第一目标的用户。pinned-only 场景保留原有自然行为，现有 previous-selection 偏好也能让用户在多次打开时保持 pinned 选择。
- 行密度问题确实存在，但应在快捷键语义稳定后作为独立迭代处理。
