# 设计文档：菜单栏图标、快捷键配置、快捷面板位置配置

**日期**：2026-05-07
**状态**：已确认，待实施

## 概述

将剪贴板管理器从 WindowGroup 主窗口应用改造为纯菜单栏应用（Menu Bar App），同时新增三项核心功能：

1. **快捷键可配置**：用户可在设置窗口自定义全局快捷键（支持功能键、数字键等），含冲突检测
2. **快捷面板位置可配置**：居中、跟随鼠标、菜单栏图标下方，按触发方式分别处理
3. **菜单栏图标和导航改进**：新增菜单栏图标（左键打开快捷面板，右键显示菜单），快捷面板增加⚙️入口

## 范围

**本次设计包含：**
- 应用架构转型（纯菜单栏应用）
- HotKeyManager（快捷键管理器）
- QuickPanelController 位置配置
- StatusBarController（菜单栏控制器）
- SettingsWindow（独立设置窗口，使用 NavigationSplitView）
- 欢迎/权限引导窗口（首次启动）

**后续设计（不在本次范围内）：**
- 外观主题（跟随系统/明亮/暗黑）
- 主题色选择
- 开机启动
- 语言选择、复制提示音
- 布局模式、预览面板
- AI 功能、关于页面

## 整体架构

### 应用类型变更

从 `WindowGroup` 主窗口应用 → 纯菜单栏应用

- `Info.plist` 设置 `LSUIElement = true`（隐藏 Dock 图标）
- 移除现有主窗口 `WindowGroup`
- `AppDelegate` 替代 `@main ClipboardApp` 作为入口

### 组件依赖关系

```
AppDelegate (NSApplicationDelegate)
    ├─ StatusBarController     // 管理 NSStatusItem
    ├─ HotKeyManager           // 管理全局快捷键
    ├─ QuickPanelController    // 管理快捷面板（现有，扩展）
    └─ AppServices             // 依赖注入容器（保持不变）
```

### 启动流程

```
applicationDidFinishLaunching()
  ↓
初始化 AppServices（保持现有逻辑）
  ↓
创建 StatusBarController → 设置菜单栏图标
  ↓
创建 HotKeyManager → 从 UserDefaults 读取配置并注册快捷键
  ↓
创建 QuickPanelController
  ↓
检测是否首次启动（UserDefaults: "app.hasLaunched"）
  ↓
如果首次启动 → 显示欢迎窗口
否则 → 应用进入后台运行
```

## 核心组件

### 1. HotKeyManager

**职责**：管理全局快捷键的注册、注销、冲突检测、配置持久化。

```swift
actor HotKeyManager {
    private var currentHotKey: (keyCode: UInt32, modifiers: UInt32)?
    private var eventHandler: EventHandlerRef?

    // 注册快捷键（带冲突检测）
    func register(keyCode: UInt32, modifiers: UInt32) throws

    // 注销当前快捷键
    func unregister()

    // 冲突检测：尝试注册，成功后立即注销
    func checkConflict(keyCode: UInt32, modifiers: UInt32) -> Bool

    // 更新快捷键（注销旧的，注册新的）
    func update(keyCode: UInt32, modifiers: UInt32) throws
}
```

**冲突检测策略：**
1. 系统快捷键黑名单（Cmd+Q、Cmd+W、Cmd+Tab、Cmd+Space 等）
2. 调用 `RegisterEventHotKey()` 尝试注册，失败则冲突，成功则立即注销

**配置存储（UserDefaults）：**
- `"hotkey.keyCode"` → UInt32，默认 `kVK_ANSI_V`
- `"hotkey.modifiers"` → UInt32，默认 `cmdKey | shiftKey`

### 2. QuickPanelController（扩展）

**新增位置模式枚举：**

```swift
enum PanelPositionMode: String, CaseIterable {
    case center      = "居中"
    case followMouse = "跟随鼠标"
    case menuBar     = "菜单栏"
}

enum TriggerSource {
    case hotkey
    case statusBarClick(iconPosition: NSPoint)
}
```

**位置计算逻辑：**

| 触发方式 | 位置设置 | 实际位置 |
|---------|---------|---------|
| 菜单栏图标点击 | 任意 | 固定在图标下方 |
| 快捷键 | 居中 | 当前屏幕中心 + Y 轴偏移 |
| 快捷键 | 跟随鼠标 | 鼠标位置附近（避免遮挡） |
| 快捷键 | 菜单栏 | 菜单栏图标下方 |

**边界情况：**
- 窗口超出屏幕边界时自动 clamp 到可见区域
- 多显示器：使用鼠标所在屏幕
- 无法获取鼠标位置（权限）时降级为居中模式

**配置存储：**
- `"quickPanel.positionMode"` → String（enum raw value），默认 `"居中"`

### 3. StatusBarController

**职责**：管理 NSStatusItem，处理左键/右键点击。

**交互：**
- **左键点击**：调用 `QuickPanelController.toggle(trigger: .statusBarClick(iconPosition))`
- **右键点击**：显示上下文菜单（含"退出"选项）

**实现要点：**
```swift
// 右键菜单显示后清除，避免影响后续左键点击
func showContextMenu() {
    statusItem?.menu = buildContextMenu()
    statusItem?.button?.performClick(nil)
    statusItem?.menu = nil
}
```

### 4. SettingsWindow

**架构：**
- 使用 SwiftUI `Window(id: "settings")` 确保单例
- `NavigationSplitView`：左侧导航，右侧内容

**当前导航页面：**
- **通用**：快捷键配置（HotKeyRecorder）、位置模式（Picker）、"Return copies only" 开关、权限状态卡片
- **隐私**：排除的应用列表、Universal Clipboard 开关
- **历史记录**：清除历史按钮、最大保留数量设置

**导航结构预留扩展位（后续添加）：**
- 外观、高级、AI、关于

**窗口管理：**
- 重复点击⚙️时调用 `NSWindow.makeKeyAndOrderFront()` 置前
- `@AppStorage` 自动保存，无需手动保存按钮
- 例外：快捷键配置通过"应用"按钮确认（需先通过冲突检测）

### 5. WelcomeWindow（欢迎/权限引导窗口）

**触发条件：** `UserDefaults["app.hasLaunched"]` 为 false

**内容：**
1. 应用简介（一句话说明用途）
2. 辅助功能权限说明和状态（实时检测轮询）
3. "打开系统设置"按钮
4. "开始使用"按钮（权限已授权时高亮可点击）

**流程：**
```
显示欢迎窗口
  ↓
用户在系统设置中授权
  ↓
权限状态实时更新为"✅ 已授权"
  ↓
用户点击"开始使用"
  ↓
设置 hasLaunched = true，关闭欢迎窗口
  ↓
应用进入后台运行
```

**后续运行时权限撤销：**
- 粘贴操作失败时，快捷面板底部显示权限提示
- 设置窗口"通用"页面顶部始终显示权限状态卡片（含"重新授权"按钮）

## 数据流

### 快捷键配置流程

```
用户点击"录制快捷键" (HotKeyRecorder)
  ↓
监听键盘事件，捕获组合键
  ↓
HotKeyManager.checkConflict()
  ↓
冲突 → 显示红色警告，不保存
无冲突 → 用户点击"应用"
  ↓
HotKeyManager.update() → 注销旧的，注册新的
  ↓
保存到 UserDefaults
  ↓
UI 更新显示新快捷键
```

### 快捷面板触发流程

```
快捷键触发                    菜单栏图标触发
    ↓                              ↓
HotKeyManager                StatusBarController
    ↓                              ↓
toggle(trigger: .hotkey)    toggle(trigger: .statusBarClick(pos))
    ↓                              ↓
读取 positionMode            固定：图标下方
    ↓                              ↓
calculatePosition()          calculatePosition()
    ↓                              ↓
           显示快捷面板
```

## 配置存储（UserDefaults 键值设计）

```swift
enum AppSettings {
    // 现有
    static let returnCopiesOnly = "quickPanel.returnCopiesOnly"  // Bool

    // 新增
    static let hotkeyKeyCode    = "hotkey.keyCode"               // UInt32
    static let hotkeyModifiers  = "hotkey.modifiers"             // UInt32
    static let panelPositionMode = "quickPanel.positionMode"     // String
    static let hasLaunched      = "app.hasLaunched"              // Bool

    // 现有（隐私，后续完善 UI）
    static let ignoredBundleIDs          = "privacy.ignoredBundleIDs"          // [String]
    static let ignoreUniversalClipboard  = "privacy.ignoreUniversalClipboard"  // Bool

    // 新增（历史记录）
    static let maxHistoryCount  = "history.maxCount"             // Int，默认 200
}
```

**默认值：**
- 快捷键：Cmd+Shift+V
- 位置模式：居中
- Return copies only：false
- 最大历史记录：200 条

## 错误处理

| 场景 | 检测方式 | 处理策略 |
|------|---------|---------|
| 与系统快捷键冲突 | 黑名单检测 | 红色提示，不保存 |
| 与其他应用冲突 | `RegisterEventHotKey()` 失败 | 警告对话框，建议换键 |
| 快捷键注册失败 | 返回错误码 | 回退默认快捷键，显示通知 |
| 辅助功能权限缺失 | AXIsProcessTrusted() | 欢迎窗口引导 / 设置窗口卡片 |
| 鼠标位置获取失败 | CGEvent.location 失败 | 降级为居中模式 |
| 快捷面板超出屏幕 | 位置计算后检测 | Clamp 到可见区域 |
| 设置窗口已存在 | Window(id:) 单例 | makeKeyAndOrderFront() 置前 |
| 配置数据损坏 | 类型解析失败 | 重置为默认值 |

## 测试策略

### 单元测试（ClipboardCoreTests）

```swift
// HotKeyManager
func testConflictDetection_systemHotkey_returnsConflict()
func testConflictDetection_validHotkey_returnsNoConflict()
func testSaveHotkey_persistsToUserDefaults()
func testLoadHotkey_invalidData_returnsDefault()

// 位置计算
func testCalculatePosition_centerMode_returnsScreenCenter()
func testCalculatePosition_followMouseMode_returnsMousePosition()
func testCalculatePosition_nearScreenEdge_clampsToVisible()
func testCalculatePosition_multipleScreens_usesCorrectScreen()

// AppSettings
func testDefaultValues_allSettingsHaveDefaults()
func testPanelPositionMode_rawValueRoundTrip()
```

### 集成测试（ClipboardPlatformTests）

```swift
func testSetup_createsStatusItem()
func testLeftClick_triggersQuickPanel()
func testRightClick_showsContextMenu()
func testAccessibilityCheck_authorized_returnsTrue()
func testAccessibilityCheck_notAuthorized_returnsFalse()
```

### 手工验收（补充到 docs/manual-acceptance-checklist.md）

**菜单栏图标：**
- [ ] 启动后菜单栏出现图标
- [ ] 左键点击，快捷面板在图标下方弹出
- [ ] 右键点击，显示包含"退出"的菜单
- [ ] 点击"退出"应用正常退出

**快捷键配置：**
- [ ] 设置窗口可录制新快捷键
- [ ] 录制 Cmd+Q 时显示冲突提示
- [ ] 录制有效快捷键后立即生效
- [ ] 重启后自定义快捷键保持

**快捷面板位置：**
- [ ] 居中模式：快捷键触发时面板在屏幕中心
- [ ] 跟随鼠标模式：快捷键触发时面板在鼠标附近
- [ ] 菜单栏模式：快捷键触发时面板在图标下方
- [ ] 菜单栏图标点击时，无论位置设置如何，面板始终在图标下方

**欢迎窗口和权限：**
- [ ] 首次启动显示欢迎窗口
- [ ] 欢迎窗口实时显示权限状态
- [ ] 授权后状态自动更新为"✅ 已授权"
- [ ] 再次启动不再显示欢迎窗口
- [ ] 撤销权限后，粘贴操作显示权限提示

**设置窗口：**
- [ ] 快捷面板右上角⚙️可打开设置窗口
- [ ] 设置窗口只有一个实例（重复点击置前）
- [ ] 设置窗口左侧导航可切换页面
- [ ] 设置关闭后配置自动保存

### 测试优先级

| 优先级 | 测试项 |
|--------|--------|
| P0 | 快捷键注册/注销 |
| P0 | 菜单栏图标点击行为 |
| P0 | 权限检查和引导 |
| P1 | 快捷面板位置计算 |
| P1 | 设置持久化 |
| P2 | 多显示器边界情况 |
| P2 | 快捷键冲突检测 |
