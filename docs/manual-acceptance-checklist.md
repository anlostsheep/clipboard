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
