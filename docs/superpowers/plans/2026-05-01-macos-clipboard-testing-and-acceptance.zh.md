# macOS 剪贴板管理器自动化测试与手工验收计划

> **给执行代理的要求：** 必须使用 `superpowers:subagent-driven-development`（推荐）或 `superpowers:executing-plans` 按任务逐步执行本计划。所有步骤使用复选框（`- [ ]`）跟踪状态。

**目标：** 在继续实现 LibraryWindow、导入器和发行包之前，先把真实 macOS 剪贴板行为纳入自动化测试和手工验收流程。

**架构：** 当前第一阶段已经有 `ClipboardCore` 和最小 `ClipboardApp`，但 AppKit 剪贴板适配器还在 executable target 内，不能被 XCTest 稳定导入。本计划先把 AppKit 适配层拆成 `ClipboardPlatform` library target，再补 `ClipboardPlatformTests`、测试脚本、手工验收清单和性能采样脚本。

**技术栈：** Swift 5.10+、Swift Package Manager、XCTest、AppKit `NSPasteboard`、ApplicationServices、shell scripts、macOS 14+。

**对应 Spec：** [2026-04-30-macos-native-clipboard-manager-design.md](../specs/2026-04-30-macos-native-clipboard-manager-design.md)

---

## 范围检查

本计划只处理测试与验收基础设施：

- 包含：AppKit pasteboard adapter 可测试化、真实 `NSPasteboard` 自动化测试、self-write marker 防重复测试、权限 gate 测试、自动化验证脚本、手工验收清单、大文本性能采样脚本。
- 不包含：完整 QuickPanel UI、LibraryWindow、Maccy/Clipaste 导入器、DMG/Cask 发行、真正的全局快捷键注册。这些仍由后续功能计划实现。

当前可自动化覆盖的重点：

- 纯文本、富文本 fallback、图片 data、文件 URL 的写入和读取。
- marker 写入与识别。
- 自写入 marker 不进入采集历史。
- Universal Clipboard pasteboard type 能进入 capture，并由 core 策略识别。
- 无辅助功能权限时 `PasteController` 阻断自动粘贴。
- 大文本不会进入 QuickPanel 首屏全文渲染路径。

当前必须手工验收的重点：

- 从不同 App 复制的真实 pasteboard type。
- 自动粘贴到目标 App 的焦点与权限行为。
- iPhone/iPad Universal Clipboard。
- macOS 14 Intel、macOS 15 Intel、macOS 26 Apple Silicon 实机表现。
- BetterMouse 或类似工具导致的粘贴失败提示。

---

## 文件结构

新增或修改：

```text
macos-clipboard-manager/
  Package.swift
  Sources/
    ClipboardApp/
      ClipboardApp.swift
    ClipboardPlatform/
      SystemPasteboardClient.swift
    ClipboardManualProbe/
      main.swift
  Tests/
    ClipboardPlatformTests/
      SystemPasteboardClientTests.swift
  Scripts/
    verify.sh
    test-automation.sh
    perf-large-text.sh
  Docs/
    manual-acceptance-checklist.md
```

责任边界：

- `ClipboardCore`：仍只放领域模型、策略、monitor、paste transaction 和 ViewModel，不依赖 AppKit。
- `ClipboardPlatform`：只放 AppKit/ApplicationServices 适配器，可被 App 和测试共同导入。
- `ClipboardApp`：只负责 UI 壳层和依赖组装。
- `ClipboardPlatformTests`：使用命名 `NSPasteboard` 做真实 macOS pasteboard 测试，避免污染用户当前系统剪贴板。
- `ClipboardManualProbe`：给手工验收提供命令行探针，用于读取当前 `NSPasteboard.general` 状态和执行自检。

---

### 任务 1：拆出可测试的 ClipboardPlatform target

**涉及文件：**
- 修改：`macos-clipboard-manager/Package.swift`
- 移动：`macos-clipboard-manager/Sources/ClipboardApp/SystemPasteboardClient.swift`
- 创建：`macos-clipboard-manager/Sources/ClipboardPlatform/SystemPasteboardClient.swift`
- 修改：`macos-clipboard-manager/Sources/ClipboardApp/ClipboardApp.swift`

- [x] **步骤 1：修改 Package.swift**

把 `macos-clipboard-manager/Package.swift` 改为：

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "macos-clipboard-manager",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "ClipboardCore", targets: ["ClipboardCore"]),
    .library(name: "ClipboardPlatform", targets: ["ClipboardPlatform"]),
    .executable(name: "ClipboardApp", targets: ["ClipboardApp"]),
    .executable(name: "ClipboardManualProbe", targets: ["ClipboardManualProbe"])
  ],
  targets: [
    .target(
      name: "ClipboardCore",
      dependencies: [],
      path: "Sources/ClipboardCore"
    ),
    .target(
      name: "ClipboardPlatform",
      dependencies: ["ClipboardCore"],
      path: "Sources/ClipboardPlatform"
    ),
    .executableTarget(
      name: "ClipboardApp",
      dependencies: ["ClipboardCore", "ClipboardPlatform"],
      path: "Sources/ClipboardApp"
    ),
    .executableTarget(
      name: "ClipboardManualProbe",
      dependencies: ["ClipboardCore", "ClipboardPlatform"],
      path: "Sources/ClipboardManualProbe"
    ),
    .testTarget(
      name: "ClipboardCoreTests",
      dependencies: ["ClipboardCore"],
      path: "Tests/ClipboardCoreTests"
    ),
    .testTarget(
      name: "ClipboardPlatformTests",
      dependencies: ["ClipboardCore", "ClipboardPlatform"],
      path: "Tests/ClipboardPlatformTests"
    )
  ]
)
```

- [x] **步骤 2：移动并公开 SystemPasteboardClient**

创建 `macos-clipboard-manager/Sources/ClipboardPlatform/SystemPasteboardClient.swift`，并删除原来的 `macos-clipboard-manager/Sources/ClipboardApp/SystemPasteboardClient.swift`。

新文件内容：

```swift
import AppKit
import ApplicationServices
import ClipboardCore
import Foundation

public final class SystemPasteboardClient: @unchecked Sendable, PasteboardReading, PasteboardWriting, PasteEventPosting {
  private let pasteboard: NSPasteboard
  private let markerType: NSPasteboard.PasteboardType

  public init(
    pasteboard: NSPasteboard = .general,
    markerType: NSPasteboard.PasteboardType = NSPasteboard.PasteboardType("com.local.clipboard-manager.marker")
  ) {
    self.pasteboard = pasteboard
    self.markerType = markerType
  }

  public func currentChangeCount() async -> Int {
    pasteboard.changeCount
  }

  public func readCurrentCapture() async -> ClipboardCapture? {
    guard let items = pasteboard.pasteboardItems,
          let item = items.first,
          !items.contains(where: containsSelfWriteMarker) else {
      return nil
    }

    let types = Set(items.flatMap { $0.types.map(\.rawValue) })
    let app = NSWorkspace.shared.frontmostApplication
    let now = Date()

    if let string = item.string(forType: .string), !string.isEmpty {
      return ClipboardCapture(
        payload: .text(string),
        pasteboardTypes: types,
        sourceAppBundleId: app?.bundleIdentifier,
        sourceAppName: app?.localizedName,
        capturedAt: now
      )
    }

    if let data = item.data(forType: .png) {
      return ClipboardCapture(
        payload: .image(data: data, uti: NSPasteboard.PasteboardType.png.rawValue),
        pasteboardTypes: types,
        sourceAppBundleId: app?.bundleIdentifier,
        sourceAppName: app?.localizedName,
        capturedAt: now
      )
    }

    let fileURLs = items.compactMap { item -> URL? in
      guard let fileString = item.string(forType: .fileURL) else {
        return nil
      }
      return URL(string: fileString)
    }
    if !fileURLs.isEmpty {
      return ClipboardCapture(
        payload: .fileURLs(fileURLs),
        pasteboardTypes: types,
        sourceAppBundleId: app?.bundleIdentifier,
        sourceAppName: app?.localizedName,
        capturedAt: now
      )
    }

    return nil
  }

  public func write(payload: ClipboardPayload, marker: String) async -> Bool {
    guard let items = makePasteboardItems(payload: payload, marker: marker) else {
      return false
    }

    pasteboard.clearContents()
    return pasteboard.writeObjects(items)
  }

  public func containsMarker(_ marker: String) async -> Bool {
    pasteboard.pasteboardItems?.contains { item in
      item.string(forType: markerType) == marker
    } ?? false
  }

  public func isAccessibilityTrusted() -> Bool {
    AXIsProcessTrustedWithOptions(nil)
  }

  public func postCommandV() async -> Bool {
    guard isAccessibilityTrusted() else {
      return false
    }

    let source = CGEventSource(stateID: .combinedSessionState)
    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
    keyDown?.flags = .maskCommand
    keyUp?.flags = .maskCommand
    keyDown?.post(tap: .cgSessionEventTap)
    keyUp?.post(tap: .cgSessionEventTap)
    return keyDown != nil && keyUp != nil
  }

  private func makePasteboardItems(payload: ClipboardPayload, marker: String) -> [NSPasteboardItem]? {
    switch payload {
    case let .text(text):
      let item = NSPasteboardItem()
      guard setMarker(marker, on: item),
            item.setString(text, forType: .string) else {
        return nil
      }
      return [item]
    case let .richText(plainText, rtfData):
      let item = NSPasteboardItem()
      guard setMarker(marker, on: item) else {
        return nil
      }
      let wroteText = item.setString(plainText, forType: .string)
      let wroteRTF = item.setData(rtfData, forType: .rtf)
      return wroteText || wroteRTF ? [item] : nil
    case let .image(data, uti):
      let item = NSPasteboardItem()
      guard setMarker(marker, on: item),
            item.setData(data, forType: NSPasteboard.PasteboardType(uti)) else {
        return nil
      }
      return [item]
    case let .fileURLs(urls):
      let items = urls.compactMap { url -> NSPasteboardItem? in
        let item = NSPasteboardItem()
        guard setMarker(marker, on: item),
              item.setString(url.absoluteString, forType: .fileURL) else {
          return nil
        }
        return item
      }
      return items.count == urls.count && !items.isEmpty ? items : nil
    }
  }

  private func setMarker(_ marker: String, on item: NSPasteboardItem) -> Bool {
    item.setString(marker, forType: markerType)
  }

  private func containsSelfWriteMarker(_ item: NSPasteboardItem) -> Bool {
    item.string(forType: markerType) != nil
  }
}
```

- [x] **步骤 3：更新 ClipboardApp import**

修改 `macos-clipboard-manager/Sources/ClipboardApp/ClipboardApp.swift`，顶部 import 变为：

```swift
import SwiftUI
import ClipboardCore
import ClipboardPlatform
```

其余代码保持不变。

- [x] **步骤 4：运行构建验证**

运行：

```bash
macos-clipboard-manager/Scripts/verify.sh
```

预期：

```text
Test Suite 'All tests' passed
Build complete!
```

- [x] **步骤 5：提交**

```bash
git add macos-clipboard-manager/Package.swift macos-clipboard-manager/Sources/ClipboardApp macos-clipboard-manager/Sources/ClipboardPlatform
git commit -m "refactor: split appkit clipboard platform target"
```

---

### 任务 2：添加真实 NSPasteboard 自动化测试

**涉及文件：**
- 创建：`macos-clipboard-manager/Tests/ClipboardPlatformTests/SystemPasteboardClientTests.swift`

- [x] **步骤 1：添加 ClipboardPlatformTests**

创建 `macos-clipboard-manager/Tests/ClipboardPlatformTests/SystemPasteboardClientTests.swift`：

```swift
import AppKit
import XCTest
@testable import ClipboardCore
@testable import ClipboardPlatform

final class SystemPasteboardClientTests: XCTestCase {
  func testTextWriteAddsMarkerAndIsNotCapturedAsExternalClipboardChange() async throws {
    let pasteboard = try makePasteboard()
    let client = SystemPasteboardClient(pasteboard: pasteboard)

    let wrote = await client.write(payload: .text("hello from test"), marker: "test-marker")

    XCTAssertTrue(wrote)
    XCTAssertTrue(await client.containsMarker("test-marker"))
    XCTAssertNil(await client.readCurrentCapture())
  }

  func testExternalTextCanBeCaptured() async throws {
    let pasteboard = try makePasteboard()
    let client = SystemPasteboardClient(pasteboard: pasteboard)

    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.setString("external text", forType: .string))

    let capture = try XCTUnwrap(await client.readCurrentCapture())

    XCTAssertEqual(capture.payload, .text("external text"))
    XCTAssertTrue(capture.pasteboardTypes.contains(NSPasteboard.PasteboardType.string.rawValue))
  }

  func testUniversalClipboardTypeIsPreservedInCapture() async throws {
    let pasteboard = try makePasteboard()
    let client = SystemPasteboardClient(pasteboard: pasteboard)
    let item = NSPasteboardItem()

    XCTAssertTrue(item.setString("from phone", forType: .string))
    XCTAssertTrue(item.setString("1", forType: NSPasteboard.PasteboardType("com.apple.is-remote-clipboard")))
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.writeObjects([item]))

    let capture = try XCTUnwrap(await client.readCurrentCapture())

    XCTAssertEqual(capture.payload, .text("from phone"))
    XCTAssertTrue(capture.isUniversalClipboard)
  }

  func testRichTextWritePreservesPlainTextAndRTF() async throws {
    let pasteboard = try makePasteboard()
    let client = SystemPasteboardClient(pasteboard: pasteboard)
    let rtf = Data("{\\rtf1\\ansi hello}".utf8)

    let wrote = await client.write(payload: .richText(plainText: "hello", rtfData: rtf), marker: "rtf-marker")

    XCTAssertTrue(wrote)
    let item = try XCTUnwrap(pasteboard.pasteboardItems?.first)
    XCTAssertEqual(item.string(forType: .string), "hello")
    XCTAssertEqual(item.data(forType: .rtf), rtf)
    XCTAssertTrue(await client.containsMarker("rtf-marker"))
  }

  func testFileURLWriteCreatesOnePasteboardItemPerURL() async throws {
    let pasteboard = try makePasteboard()
    let client = SystemPasteboardClient(pasteboard: pasteboard)
    let first = URL(fileURLWithPath: "/tmp/clipboard-test-a.txt")
    let second = URL(fileURLWithPath: "/tmp/clipboard-test-b.txt")

    let wrote = await client.write(payload: .fileURLs([first, second]), marker: "file-marker")

    XCTAssertTrue(wrote)
    let items = try XCTUnwrap(pasteboard.pasteboardItems)
    XCTAssertEqual(items.count, 2)
    XCTAssertEqual(items.compactMap { $0.string(forType: .fileURL) }, [first.absoluteString, second.absoluteString])
    XCTAssertTrue(await client.containsMarker("file-marker"))
  }

  func testExternalImageCanBeCapturedWithoutTextHydration() async throws {
    let pasteboard = try makePasteboard()
    let client = SystemPasteboardClient(pasteboard: pasteboard)
    let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    let item = NSPasteboardItem()

    XCTAssertTrue(item.setData(pngData, forType: .png))
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.writeObjects([item]))

    let capture = try XCTUnwrap(await client.readCurrentCapture())

    XCTAssertEqual(capture.payload, .image(data: pngData, uti: NSPasteboard.PasteboardType.png.rawValue))
    XCTAssertTrue(capture.pasteboardTypes.contains(NSPasteboard.PasteboardType.png.rawValue))
  }

  private func makePasteboard(file: StaticString = #filePath, line: UInt = #line) throws -> NSPasteboard {
    let name = NSPasteboard.Name("com.local.clipboard-manager.tests.\(UUID().uuidString)")
    let pasteboard = NSPasteboard(name: name)
    pasteboard.clearContents()
    return pasteboard
  }
}
```

- [x] **步骤 2：运行平台测试**

运行：

```bash
cd macos-clipboard-manager
swift test --filter SystemPasteboardClientTests
```

预期：

```text
Test Suite 'SystemPasteboardClientTests' passed
```

- [x] **步骤 3：运行完整验证**

运行：

```bash
macos-clipboard-manager/Scripts/verify.sh
```

预期：

```text
Test Suite 'All tests' passed
Build complete!
```

- [x] **步骤 4：提交**

```bash
git add macos-clipboard-manager/Tests/ClipboardPlatformTests/SystemPasteboardClientTests.swift
git commit -m "test: cover appkit pasteboard adapter"
```

---

### 任务 3：添加手工验收命令行探针

**涉及文件：**
- 创建：`macos-clipboard-manager/Sources/ClipboardManualProbe/main.swift`

- [x] **步骤 1：添加 ClipboardManualProbe**

创建 `macos-clipboard-manager/Sources/ClipboardManualProbe/main.swift`：

```swift
import AppKit
import ClipboardCore
import ClipboardPlatform
import Darwin
import Foundation

@main
struct ClipboardManualProbe {
  static func main() async {
    let command = CommandLine.arguments.dropFirst().first ?? "read-once"
    let client = SystemPasteboardClient()

    switch command {
    case "read-once":
      await readOnce(client: client)
    case "write-marker-text":
      let text = CommandLine.arguments.dropFirst(2).first ?? "clipboard-manager-manual-probe"
      let wrote = await client.write(payload: .text(text), marker: "manual-probe-marker")
      print(wrote ? "write-marker-text: ok" : "write-marker-text: failed")
    case "accessibility":
      print(client.isAccessibilityTrusted() ? "accessibility: authorized" : "accessibility: required")
    case "self-check":
      let wrote = await client.write(payload: .text("clipboard-manager-self-check"), marker: "manual-probe-marker")
      let hasMarker = await client.containsMarker("manual-probe-marker")
      print("write: \(wrote ? "ok" : "failed")")
      print("marker: \(hasMarker ? "present" : "missing")")
      print(client.isAccessibilityTrusted() ? "accessibility: authorized" : "accessibility: required")
    default:
      print("usage: ClipboardManualProbe read-once|write-marker-text|accessibility|self-check")
      Darwin.exit(2)
    }
  }

  private static func readOnce(client: SystemPasteboardClient) async {
    guard let capture = await client.readCurrentCapture() else {
      print("capture: empty-or-self-write")
      return
    }

    print("capture: ok")
    print("types: \(capture.pasteboardTypes.sorted().joined(separator: ","))")
    print("sourceApp: \(capture.sourceAppName ?? "unknown")")
    print("universalClipboard: \(capture.isUniversalClipboard)")

    switch capture.payload {
    case let .text(text):
      print("payload: text")
      print("textBytes: \(text.utf8.count)")
      print("textPreview: \(String(text.prefix(120)))")
    case let .richText(plainText, rtfData):
      print("payload: richText")
      print("plainTextBytes: \(plainText.utf8.count)")
      print("rtfBytes: \(rtfData.count)")
    case let .image(data, uti):
      print("payload: image")
      print("uti: \(uti)")
      print("imageBytes: \(data.count)")
    case let .fileURLs(urls):
      print("payload: fileURLs")
      print("fileCount: \(urls.count)")
      print("files: \(urls.map(\\.path).joined(separator: "|"))")
    }
  }
}
```

- [x] **步骤 2：构建并运行探针**

运行：

```bash
cd macos-clipboard-manager
swift build --product ClipboardManualProbe
swift run ClipboardManualProbe self-check
swift run ClipboardManualProbe read-once
swift run ClipboardManualProbe accessibility
```

预期：

```text
write: ok
marker: present
capture: empty-or-self-write
accessibility: authorized
```

如果本机尚未给当前运行产物辅助功能权限，`accessibility` 允许输出：

```text
accessibility: required
```

但必须记录到手工验收清单，不允许把它当作自动粘贴已通过。

- [x] **步骤 3：提交**

```bash
git add macos-clipboard-manager/Sources/ClipboardManualProbe
git commit -m "test: add clipboard manual probe"
```

---

### 任务 4：添加自动化测试脚本

**涉及文件：**
- 创建：`macos-clipboard-manager/Scripts/test-automation.sh`
- 修改：`macos-clipboard-manager/Scripts/verify.sh`

- [x] **步骤 1：创建 test-automation.sh**

创建 `macos-clipboard-manager/Scripts/test-automation.sh`：

```bash
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift test --filter ClipboardCoreTests
swift test --filter ClipboardPlatformTests
swift build --product ClipboardApp
swift build --product ClipboardManualProbe
```

- [x] **步骤 2：更新 verify.sh**

把 `macos-clipboard-manager/Scripts/verify.sh` 改为：

```bash
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

swift test
swift build
Scripts/test-automation.sh
```

- [x] **步骤 3：授权脚本**

运行：

```bash
chmod +x macos-clipboard-manager/Scripts/test-automation.sh
chmod +x macos-clipboard-manager/Scripts/verify.sh
```

预期：

```text
无输出
```

- [x] **步骤 4：运行自动化测试**

运行：

```bash
macos-clipboard-manager/Scripts/test-automation.sh
macos-clipboard-manager/Scripts/verify.sh
```

预期：

```text
Test Suite 'All tests' passed
Build complete!
```

- [x] **步骤 5：提交**

```bash
git add macos-clipboard-manager/Scripts/test-automation.sh macos-clipboard-manager/Scripts/verify.sh
git commit -m "test: add clipboard automation script"
```

---

### 任务 5：添加大文本性能采样脚本

**涉及文件：**
- 创建：`macos-clipboard-manager/Scripts/perf-large-text.sh`

- [x] **步骤 1：创建 perf-large-text.sh**

创建 `macos-clipboard-manager/Scripts/perf-large-text.sh`：

```bash
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

json_10mb="$tmp_dir/large-10mb.json"
log_100mb="$tmp_dir/large-100mb.log"

python3 - <<'PY' "$json_10mb" "$log_100mb"
import sys
json_path, log_path = sys.argv[1], sys.argv[2]
with open(json_path, "w", encoding="utf-8") as f:
    f.write("{")
    for i in range(560000):
        f.write(f'"message{i}":"hello",')
    f.write('"end":true}')
with open(log_path, "w", encoding="utf-8") as f:
    line = "2026-04-30T00:00:00Z INFO clipboard-manager performance sample line\n"
    while f.tell() < 100 * 1024 * 1024:
        f.write(line)
PY

echo "10MB json bytes: $(wc -c < "$json_10mb")"
echo "100MB log bytes: $(wc -c < "$log_100mb")"

echo "Running PerformanceGuardTests"
swift test --filter PerformanceGuardTests

echo "Copying 10MB JSON to system pasteboard"
/usr/bin/time -p sh -c 'pbcopy < "$1"' sh "$json_10mb"
swift run ClipboardManualProbe read-once | sed -n '1,12p'

echo "Copying 100MB log to system pasteboard"
/usr/bin/time -p sh -c 'pbcopy < "$1"' sh "$log_100mb"
swift run ClipboardManualProbe read-once | sed -n '1,12p'
```

- [x] **步骤 2：授权并运行性能采样**

运行：

```bash
chmod +x macos-clipboard-manager/Scripts/perf-large-text.sh
macos-clipboard-manager/Scripts/perf-large-text.sh
```

预期：

```text
10MB json bytes: 大于 10000000
100MB log bytes: 大于 104857600
Test Suite 'PerformanceGuardTests' passed
capture: ok
payload: text
```

验收记录要求：

- 记录 `pbcopy` 的 `real/user/sys` 时间。
- 记录 `ClipboardManualProbe read-once` 输出的 `textBytes`。
- 如果复制 100MB log 后 iStat CPU 长时间 100%，记录 PID 排名，不直接标记通过。

- [x] **步骤 3：提交**

```bash
git add macos-clipboard-manager/Scripts/perf-large-text.sh
git commit -m "test: add large clipboard performance probe"
```

---

### 任务 6：添加手工验收清单

**涉及文件：**
- 创建：`macos-clipboard-manager/Docs/manual-acceptance-checklist.md`

- [x] **步骤 1：创建手工验收清单**

创建 `macos-clipboard-manager/Docs/manual-acceptance-checklist.md`：

```markdown
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

- [ ] `macos-clipboard-manager/Scripts/verify.sh` 通过
- [ ] `swift run ClipboardManualProbe self-check` 输出 `write: ok`
- [ ] `swift run ClipboardManualProbe accessibility` 输出 `accessibility: authorized`
- [ ] 如果输出 `accessibility: required`，先在系统设置中授权，再重新验证

## 复制来源覆盖

每个来源复制后运行：

```bash
cd macos-clipboard-manager
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
```

- [x] **步骤 2：提交**

```bash
git add macos-clipboard-manager/Docs/manual-acceptance-checklist.md
git commit -m "docs: add clipboard manual acceptance checklist"
```

---

### 任务 7：最终测试计划验收

**涉及文件：**
- 读取：`macos-clipboard-manager/Scripts`
- 读取：`macos-clipboard-manager/Tests`
- 读取：`macos-clipboard-manager/Docs/manual-acceptance-checklist.md`

- [x] **步骤 1：运行完整自动化验证**

运行：

```bash
macos-clipboard-manager/Scripts/verify.sh
macos-clipboard-manager/Scripts/test-automation.sh
```

预期：

```text
Test Suite 'All tests' passed
Build complete!
```

- [x] **步骤 2：运行结构覆盖检查**

运行：

```bash
rg -n "ClipboardPlatform|ClipboardPlatformTests|ClipboardManualProbe|manual-acceptance|perf-large-text" macos-clipboard-manager docs/superpowers/plans
```

预期：

```text
输出包含 ClipboardPlatform、ClipboardPlatformTests、ClipboardManualProbe、manual-acceptance、perf-large-text
```

- [x] **步骤 3：确认没有误提交构建产物**

运行：

```bash
git status --short --untracked-files=all
git check-ignore -v macos-clipboard-manager/.build/.lock
```

预期：

```text
git status 无源码外未提交项
.gitignore:...:.build/ macos-clipboard-manager/.build/.lock
```

- [x] **步骤 4：提交计划状态**

如果执行本计划后只剩计划文件勾选变化：

```bash
git add docs/superpowers/plans/2026-05-01-macos-clipboard-testing-and-acceptance.zh.md
git commit -m "docs: mark clipboard testing plan verified"
```

如果执行中还有源码修正，和对应任务一起提交，不创建空提交。

---

## 执行顺序建议

1. 先执行任务 1 和任务 2，确保真实 `NSPasteboard` 行为可以自动化测试。
2. 再执行任务 3 和任务 4，把手工探针接入自动化验证。
3. 然后执行任务 5 和任务 6，形成大文本采样和人工验收矩阵。
4. 最后执行任务 7，确认测试基础设施可重复运行。

## 阻断标准

以下任一情况出现时，不继续进入 LibraryWindow 或导入器计划：

- `SystemPasteboardClientTests` 无法稳定通过。
- 自写入 marker 仍会被采集为外部历史。
- `ClipboardManualProbe read-once` 无法识别真实文本 pasteboard。
- 10MB JSON 或 100MB log 复制后出现持续 CPU 100%，且无法定位到外部 App。
- 无辅助功能权限时仍允许用户进入“看似可以自动粘贴”的主流程。
- `verify.sh` 运行后产生未忽略的构建产物或临时文件。

## 后续衔接

本计划完成后，再进入以下计划：

1. `2026-05-01-macos-clipboard-library-window.zh.md`
   - 持久化 store、LibraryWindow、分组、设置、诊断页。
2. `2026-05-01-macos-clipboard-importers.zh.md`
   - Maccy/Clipaste 导入器、导入报告、schema 版本处理。
3. `2026-05-01-macos-clipboard-release.zh.md`
   - Intel 包、Apple Silicon 包、更新清单、Homebrew Cask 拆分。
4. `2026-05-01-macos-clipboard-compatibility.zh.md`
   - macOS 14 Intel、macOS 15 Intel、macOS 26 Apple Silicon 测试矩阵和性能压测。
