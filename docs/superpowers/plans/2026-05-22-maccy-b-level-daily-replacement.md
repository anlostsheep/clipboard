# Maccy B-Level Daily Replacement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Clipboard reach B-level daily Maccy replacement readiness by closing acceptance evidence gaps, adding Maccy-style plain-text paste and number shortcuts, and producing metric-scoped Maccy benchmark comparisons.

**Architecture:** Keep current `ClipboardCore`, `ClipboardPlatform`, and `ClipboardApp` boundaries. Benchmark comparison stays in `ClipboardBenchmarkProbe` and `ClipboardCore/Benchmark`; QuickPanel key mapping remains in `QuickPanelKeyCaptureView`; selection, paste, and detail semantics live in `QuickPanelState`; SwiftUI wiring stays in `QuickPanelView`.

**Tech Stack:** Swift 5.10, Swift Package Manager, SwiftUI, AppKit, Carbon key codes, XCTest, shell scripts, stable local code signing.

---

## Scope Check

The approved spec intentionally combines two tracks:

1. P0 replacement hardening: acceptance checklist, runtime privacy evidence, import evidence, benchmark baseline support, stable signed verification.
2. P1 high-frequency interaction parity: plain-text paste, number-key selection, number-key paste, pinned/history visual-order mapping, and detail preview.

This plan keeps them in one file but splits them into independently reviewable tasks. Phase 1 can ship evidence and benchmark improvements without waiting for Phase 2 UI interactions.

## File Structure

- Modify: `docs/manual-acceptance-checklist.md`
  - Add B-level acceptance items for paste matrix, privacy controls, benchmark baseline, plain-text paste, number shortcuts, and detail preview.
- Modify: `Sources/ClipboardCore/Benchmark/BenchmarkComparison.swift`
  - Add a per-metric comparison value that carries result, reason, and confidence.
- Modify: `Tests/ClipboardCoreTests/BenchmarkComparisonTests.swift`
  - Cover per-metric comparison reasons and confidence.
- Modify: `Sources/ClipboardBenchmarkProbe/main.swift`
  - Accept an optional Maccy baseline JSON file and emit per-metric comparisons.
- Modify: `Scripts/benchmark-maccy-replacement.sh`
  - Pass optional `MACCY_BASELINE_JSON` into the probe and stop printing a hard-coded `not_comparable`.
- Modify: `Tests/ClipboardAppTests/QuickPanelKeyCaptureTests.swift`
  - Add keyboard mapping coverage for plain-text paste, number selection, number paste, and detail preview.
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelKeyCaptureView.swift`
  - Add new keyboard actions and optional callbacks.
- Modify: `Tests/ClipboardCoreTests/PasteControllerTests.swift`
  - Add plain-text extraction coverage for text, link, rich text, image, and file payloads.
- Create: `Sources/ClipboardCore/Paste/PlainTextPastePayload.swift`
  - Provide a focused helper that extracts plain text from text-like payloads.
- Modify: `Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift`
  - Add state-level coverage for visible number selection, number paste, copy-only override, plain-text paste, unsupported format feedback, and detail preview.
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelState.swift`
  - Add number selection, number paste, plain-text paste, and detail preview state.
- Create: `Sources/ClipboardApp/QuickPanel/QuickPanelDetailPreviewView.swift`
  - Render selected-record detail preview without eager large-content rendering.
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelView.swift`
  - Wire new key callbacks and present detail preview.

## Phase 1: P0 Evidence And Benchmark Hardening

### Task 1: Add B-Level Acceptance Checklist Items

**Files:**
- Modify: `docs/manual-acceptance-checklist.md`

- [ ] **Step 1: Add unchecked checklist items**

Add this section after the existing `## Maccy Replacement Privacy And Performance` block and before `## 记录格式`:

```markdown
## Maccy B-Level Daily Replacement

- [ ] 普通文本框中，QuickPanel `Return` 自动粘贴当前选中项
- [ ] 普通文本框中，QuickPanel 双击自动粘贴当前记录
- [ ] 富文本编辑器中，QuickPanel `Return` 自动粘贴当前选中项
- [ ] Terminal 中，QuickPanel `Return` 自动粘贴当前选中项
- [ ] 浏览器地址栏中，QuickPanel `Return` 自动粘贴当前选中项
- [ ] 仅复制模式下，`Return` 和双击只写入系统剪贴板，不自动粘贴
- [ ] 仅复制模式下，随后手动 `Command+V` 能粘贴刚选中的记录
- [ ] `Option+Shift+Enter` 对富文本记录执行无格式粘贴
- [ ] `Option+Shift+Enter` 对文本和链接记录执行纯文本粘贴
- [ ] `Option+Shift+Enter` 对图片或文件记录显示不支持无格式粘贴的状态
- [ ] `Command+1...9` 选择当前可见列表中的第 N 条记录
- [ ] `Option+1...9` 自动粘贴当前可见列表中的第 N 条记录
- [ ] 开启仅复制模式后，`Option+1...9` 仍作为显式自动粘贴命令执行
- [ ] 搜索和类型过滤后，数字快捷键对应过滤后的可见顺序
- [ ] pinned/history 混排时，数字快捷键按视觉顺序定位记录
- [ ] 详情预览可查看安全大小文本记录的完整内容
- [ ] 详情预览对大文本保持摘要优先，不在 QuickPanel 首帧加载全文
- [ ] 暂停采集后复制 3 条内容，历史数量不增长
- [ ] 恢复采集后复制 1 条内容，历史数量增长
- [ ] 触发“忽略下一次复制”后，第一条复制不入库，第二条复制正常入库
- [ ] 添加 Maccy baseline 后，benchmark 报告输出 per-metric comparison
- [ ] benchmark comparison 只使用 `better` / `same` / `worse` / `not_comparable`
- [ ] 本轮真实 UI 验收使用的 app bundle 签名包含 `Authority=ClipboardApp Local Code Signing`
```

- [ ] **Step 2: Run docs whitespace check**

Run:

```bash
git diff --check -- docs/manual-acceptance-checklist.md
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add docs/manual-acceptance-checklist.md
git commit -m "docs: add maccy b-level acceptance checklist"
```

## Phase 1: Benchmark Baseline Support

### Task 2: Add Per-Metric Benchmark Comparison Model

**Files:**
- Modify: `Sources/ClipboardCore/Benchmark/BenchmarkComparison.swift`
- Modify: `Tests/ClipboardCoreTests/BenchmarkComparisonTests.swift`

- [ ] **Step 1: Write failing comparison value tests**

Append these tests to `Tests/ClipboardCoreTests/BenchmarkComparisonTests.swift`:

```swift
  func testMetricComparisonExplainsMissingMaccyBaseline() {
    let comparison = BenchmarkComparison.compareMetric(
      name: "fetch_recent_50_ms",
      clipboardMedian: 10,
      clipboardP95: 15,
      maccyMedian: nil,
      maccyP95: nil,
      maccySource: nil
    )

    XCTAssertEqual(comparison.name, "fetch_recent_50_ms")
    XCTAssertEqual(comparison.result, .notComparable)
    XCTAssertEqual(comparison.confidence, .missingBaseline)
    XCTAssertEqual(comparison.reason, "Maccy baseline is missing for fetch_recent_50_ms")
  }

  func testMetricComparisonRecordsBetterSameWorseWithReasons() {
    let better = BenchmarkComparison.compareMetric(
      name: "fetch_recent_50_ms",
      clipboardMedian: 79,
      clipboardP95: 100,
      maccyMedian: 100,
      maccyP95: 100,
      maccySource: "same-machine-json"
    )
    let same = BenchmarkComparison.compareMetric(
      name: "search_http_50_ms",
      clipboardMedian: 90,
      clipboardP95: 151,
      maccyMedian: 100,
      maccyP95: 150,
      maccySource: "same-machine-json"
    )
    let worse = BenchmarkComparison.compareMetric(
      name: "store_load_ms",
      clipboardMedian: 121,
      clipboardP95: 130,
      maccyMedian: 100,
      maccyP95: 150,
      maccySource: "same-machine-json"
    )

    XCTAssertEqual(better.result, .better)
    XCTAssertEqual(better.confidence, .sameMachineBaseline)
    XCTAssertEqual(better.reason, "Clipboard median is at least 20% lower than Maccy and p95 is not worse")
    XCTAssertEqual(same.result, .same)
    XCTAssertEqual(same.reason, "Clipboard median is within the 20% same range or p95 prevents a better result")
    XCTAssertEqual(worse.result, .worse)
    XCTAssertEqual(worse.reason, "Clipboard median is more than 20% higher than Maccy")
  }
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
swift test --filter BenchmarkComparisonTests
```

Expected: build fails because `BenchmarkComparison.compareMetric` and `BenchmarkMetricComparison` types do not exist.

- [ ] **Step 3: Add comparison value types**

Modify `Sources/ClipboardCore/Benchmark/BenchmarkComparison.swift` to include:

```swift
public enum BenchmarkComparisonConfidence: String, Codable, Equatable, Sendable {
  case sameMachineBaseline
  case missingBaseline
  case invalidBaseline
}

public struct BenchmarkMetricComparison: Codable, Equatable, Sendable {
  public let name: String
  public let result: BenchmarkComparisonResult
  public let confidence: BenchmarkComparisonConfidence
  public let reason: String
  public let clipboardMedianMs: Double
  public let clipboardP95Ms: Double
  public let maccyMedianMs: Double?
  public let maccyP95Ms: Double?
  public let maccySource: String?

  public init(
    name: String,
    result: BenchmarkComparisonResult,
    confidence: BenchmarkComparisonConfidence,
    reason: String,
    clipboardMedianMs: Double,
    clipboardP95Ms: Double,
    maccyMedianMs: Double?,
    maccyP95Ms: Double?,
    maccySource: String?
  ) {
    self.name = name
    self.result = result
    self.confidence = confidence
    self.reason = reason
    self.clipboardMedianMs = clipboardMedianMs
    self.clipboardP95Ms = clipboardP95Ms
    self.maccyMedianMs = maccyMedianMs
    self.maccyP95Ms = maccyP95Ms
    self.maccySource = maccySource
  }
}
```

Then add the new function inside `public enum BenchmarkComparison`:

```swift
  public static func compareMetric(
    name: String,
    clipboardMedian: Double,
    clipboardP95: Double,
    maccyMedian: Double?,
    maccyP95: Double?,
    maccySource: String?
  ) -> BenchmarkMetricComparison {
    guard let maccyMedian, let maccyP95 else {
      return BenchmarkMetricComparison(
        name: name,
        result: .notComparable,
        confidence: .missingBaseline,
        reason: "Maccy baseline is missing for \(name)",
        clipboardMedianMs: clipboardMedian,
        clipboardP95Ms: clipboardP95,
        maccyMedianMs: nil,
        maccyP95Ms: nil,
        maccySource: maccySource
      )
    }

    guard maccyMedian > 0, maccyP95 > 0 else {
      return BenchmarkMetricComparison(
        name: name,
        result: .notComparable,
        confidence: .invalidBaseline,
        reason: "Maccy baseline must have positive median and p95 for \(name)",
        clipboardMedianMs: clipboardMedian,
        clipboardP95Ms: clipboardP95,
        maccyMedianMs: maccyMedian,
        maccyP95Ms: maccyP95,
        maccySource: maccySource
      )
    }

    let result = classify(
      clipboardMedian: clipboardMedian,
      maccyMedian: maccyMedian,
      clipboardP95: clipboardP95,
      maccyP95: maccyP95
    )
    let reason: String = switch result {
    case .better:
      "Clipboard median is at least 20% lower than Maccy and p95 is not worse"
    case .same:
      "Clipboard median is within the 20% same range or p95 prevents a better result"
    case .worse:
      "Clipboard median is more than 20% higher than Maccy"
    case .notComparable:
      "Maccy baseline is not comparable for \(name)"
    }

    return BenchmarkMetricComparison(
      name: name,
      result: result,
      confidence: .sameMachineBaseline,
      reason: reason,
      clipboardMedianMs: clipboardMedian,
      clipboardP95Ms: clipboardP95,
      maccyMedianMs: maccyMedian,
      maccyP95Ms: maccyP95,
      maccySource: maccySource
    )
  }
```

- [ ] **Step 4: Run tests**

Run:

```bash
swift test --filter BenchmarkComparisonTests
```

Expected: all `BenchmarkComparisonTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClipboardCore/Benchmark/BenchmarkComparison.swift Tests/ClipboardCoreTests/BenchmarkComparisonTests.swift
git commit -m "feat: add benchmark metric comparisons"
```

### Task 3: Wire Optional Maccy Baseline Into Benchmark Probe

**Files:**
- Modify: `Sources/ClipboardBenchmarkProbe/main.swift`
- Modify: `Scripts/benchmark-maccy-replacement.sh`

- [ ] **Step 1: Extend probe argument parsing**

Modify `ProbeArguments` in `Sources/ClipboardBenchmarkProbe/main.swift`:

```swift
private struct ProbeArguments {
  let bundleID: String
  let outputURL: URL
  let maccyBaselineURL: URL?

  static func parse<S: Sequence>(_ rawArguments: S) throws -> ProbeArguments where S.Element == String {
    var bundleID = ClipboardBenchmarkProbe.defaultBundleID
    var outputPath: String?
    var maccyBaselinePath: String?
    var iterator = rawArguments.makeIterator()

    while let argument = iterator.next() {
      switch argument {
      case "--bundle-id":
        guard let value = iterator.next(), !value.isEmpty else {
          throw ProbeArgumentError.missingValue("--bundle-id")
        }
        bundleID = value
      case "--output":
        guard let value = iterator.next(), !value.isEmpty else {
          throw ProbeArgumentError.missingValue("--output")
        }
        outputPath = value
      case "--maccy-baseline":
        guard let value = iterator.next(), !value.isEmpty else {
          throw ProbeArgumentError.missingValue("--maccy-baseline")
        }
        maccyBaselinePath = value
      case "--help", "-h":
        throw ProbeArgumentError.help
      default:
        throw ProbeArgumentError.unknown(argument)
      }
    }

    guard let outputPath else {
      throw ProbeArgumentError.missingValue("--output")
    }

    return ProbeArguments(
      bundleID: bundleID,
      outputURL: URL(fileURLWithPath: outputPath),
      maccyBaselineURL: maccyBaselinePath.map(URL.init(fileURLWithPath:))
    )
  }
}
```

Update usage:

```swift
private static let usage = "usage: ClipboardBenchmarkProbe [--bundle-id BUNDLE_ID] [--maccy-baseline BASELINE_JSON] --output REPORT_JSON"
```

- [ ] **Step 2: Add baseline structures**

Add near the other private benchmark structs:

```swift
private struct MaccyBaselineReport: Decodable {
  let source: String
  let metrics: [MaccyBaselineMetric]
}

private struct MaccyBaselineMetric: Decodable {
  let name: String
  let medianMs: Double
  let p95Ms: Double
}
```

- [ ] **Step 3: Add report comparison fields**

Change `BenchmarkReport` from:

```swift
private struct BenchmarkReport: Encodable {
  let generatedAt: Date
  let bundleID: String
  let paths: BenchmarkPaths
  let dataset: DatasetSummary
  let metrics: [BenchmarkMetric]
  let maccyComparison: BenchmarkComparisonResult
}
```

to:

```swift
private struct BenchmarkReport: Encodable {
  let generatedAt: Date
  let bundleID: String
  let paths: BenchmarkPaths
  let dataset: DatasetSummary
  let metrics: [BenchmarkMetric]
  let comparisons: [BenchmarkMetricComparison]
}
```

- [ ] **Step 4: Load the optional baseline and compare metrics**

Change `main()` to pass the optional baseline:

```swift
let report = try await run(
  paths: paths,
  bundleID: arguments.bundleID,
  maccyBaselineURL: arguments.maccyBaselineURL
)
```

Change `run` signature:

```swift
private static func run(
  paths: ApplicationSupportPaths,
  bundleID: String,
  maccyBaselineURL: URL?
) async throws -> BenchmarkReport {
```

Inside `run`, before returning:

```swift
let metrics = [loadMetric, fetchRecent, fetchHTTP]
let baseline = try loadMaccyBaseline(from: maccyBaselineURL)
let comparisons = compare(metrics: metrics, baseline: baseline)
```

Return:

```swift
return BenchmarkReport(
  generatedAt: Date(),
  bundleID: bundleID,
  paths: BenchmarkPaths(
    databaseFile: paths.databaseFile.path,
    payloadsDirectory: paths.payloadsDirectory.path
  ),
  dataset: DatasetSummary(
    recordCount: records.count,
    payloadBytes: payloadBytes(in: paths.payloadsDirectory),
    typeCounts: typeCounts(records),
    pinnedCount: records.filter(\.isPinned).count
  ),
  metrics: metrics,
  comparisons: comparisons
)
```

Add helper functions:

```swift
private static func loadMaccyBaseline(from url: URL?) throws -> MaccyBaselineReport? {
  guard let url else { return nil }
  let data = try Data(contentsOf: url)
  return try JSONDecoder().decode(MaccyBaselineReport.self, from: data)
}

private static func compare(
  metrics: [BenchmarkMetric],
  baseline: MaccyBaselineReport?
) -> [BenchmarkMetricComparison] {
  let baselineByName = Dictionary(
    uniqueKeysWithValues: baseline?.metrics.map { ($0.name, $0) } ?? []
  )
  return metrics.map { metric in
    let maccy = baselineByName[metric.name]
    return BenchmarkComparison.compareMetric(
      name: metric.name,
      clipboardMedian: metric.medianMs,
      clipboardP95: metric.p95Ms,
      maccyMedian: maccy?.medianMs,
      maccyP95: maccy?.p95Ms,
      maccySource: baseline?.source
    )
  }
}
```

- [ ] **Step 5: Print per-metric comparison**

Replace the summary comparison print:

```swift
print("Maccy comparison: \(report.maccyComparison.rawValue)")
```

with:

```swift
print("Maccy comparisons:")
for comparison in report.comparisons {
  print("  \(comparison.name): \(comparison.result.rawValue) (\(comparison.reason))")
}
```

- [ ] **Step 6: Update benchmark script**

Modify `Scripts/benchmark-maccy-replacement.sh`:

```bash
args=(--bundle-id "$bundle_id" --output "$report_path")
if [[ -n "${MACCY_BASELINE_JSON:-}" ]]; then
  args+=(--maccy-baseline "$MACCY_BASELINE_JSON")
fi

swift run ClipboardBenchmarkProbe "${args[@]}"

echo "JSON report: $report_path"
if [[ -n "${MACCY_BASELINE_JSON:-}" ]]; then
  echo "Maccy baseline: $MACCY_BASELINE_JSON"
else
  echo "Maccy baseline: missing; report comparisons will be not_comparable per metric."
fi
```

- [ ] **Step 7: Run benchmark comparison tests and script smoke test**

Run:

```bash
swift test --filter BenchmarkComparisonTests
Scripts/benchmark-maccy-replacement.sh
```

Expected:

- `BenchmarkComparisonTests` pass.
- Script prints `JSON report: ...`.
- Script prints `Maccy baseline: missing; report comparisons will be not_comparable per metric.` when no baseline env var is set.

- [ ] **Step 8: Commit**

```bash
git add Sources/ClipboardBenchmarkProbe/main.swift Scripts/benchmark-maccy-replacement.sh
git commit -m "feat: accept maccy benchmark baseline"
```

## Phase 2: QuickPanel Key Mapping

### Task 4: Add Key Actions For Plain-Text Paste And Number Shortcuts

**Files:**
- Modify: `Tests/ClipboardAppTests/QuickPanelKeyCaptureTests.swift`
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelKeyCaptureView.swift`

- [ ] **Step 1: Write failing key mapping tests**

Append these tests to `Tests/ClipboardAppTests/QuickPanelKeyCaptureTests.swift`:

```swift
    func testOptionShiftReturnRequestsPlainTextPaste() {
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_Return),
                modifierFlags: [.option, .shift]
            ),
            .pastePlainText
        )
    }

    func testCommandNumberSelectsVisibleItem() {
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_1),
                modifierFlags: [.command]
            ),
            .selectNumber(1)
        )
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_9),
                modifierFlags: [.command]
            ),
            .selectNumber(9)
        )
    }

    func testOptionNumberPastesVisibleItem() {
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_1),
                modifierFlags: [.option]
            ),
            .pasteNumber(1)
        )
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_9),
                modifierFlags: [.option]
            ),
            .pasteNumber(9)
        )
    }

    func testCommandYRequestsDetailPreview() {
        XCTAssertEqual(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_Y),
                modifierFlags: [.command]
            ),
            .showDetailPreview
        )
    }

    func testNumberShortcutsRequireExactModifiers() {
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_1),
                modifierFlags: []
            )
        )
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_1),
                modifierFlags: [.shift, .command]
            )
        )
        XCTAssertNil(
            QuickPanelKeyCaptureView.keyboardAction(
                keyCode: UInt16(kVK_ANSI_1),
                modifierFlags: [.shift, .option]
            )
        )
    }
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
swift test --filter QuickPanelKeyCaptureTests
```

Expected: build fails because new `KeyboardAction` cases do not exist.

- [ ] **Step 3: Add keyboard action cases**

Modify `KeyboardAction` in `Sources/ClipboardApp/QuickPanel/QuickPanelKeyCaptureView.swift`:

```swift
    case cycleContentFilter(Int)
    case selectNumber(Int)
    case pasteNumber(Int)
    case pastePlainText
    case showDetailPreview
```

- [ ] **Step 4: Add optional callbacks to the representable**

Add stored properties:

```swift
  var onSelectNumber: ((Int) -> Void)? = nil
  var onPasteNumber: ((Int) -> Void)? = nil
  var onPastePlainText: (() -> Void)? = nil
  var onShowDetailPreview: (() -> Void)? = nil
```

Pass them into `Coordinator(...)`, update them in `updateNSView`, and add matching `Coordinator` properties and initializer parameters.

- [ ] **Step 5: Handle new actions in `Coordinator.handle(_:)`**

Add cases after `.cycleContentFilter`:

```swift
      case .selectNumber(let number):
        guard let onSelectNumber else {
          return event
        }
        onSelectNumber(number)
        return nil
      case .pasteNumber(let number):
        guard let onPasteNumber else {
          return event
        }
        onPasteNumber(number)
        return nil
      case .pastePlainText:
        guard let onPastePlainText else {
          return event
        }
        onPastePlainText()
        return nil
      case .showDetailPreview:
        guard let onShowDetailPreview else {
          return event
        }
        onShowDetailPreview()
        return nil
```

- [ ] **Step 6: Add key mapping helpers**

Add helper inside `QuickPanelKeyCaptureView`:

```swift
  private static func number(for keyCode: UInt16) -> Int? {
    switch keyCode {
    case UInt16(kVK_ANSI_1): return 1
    case UInt16(kVK_ANSI_2): return 2
    case UInt16(kVK_ANSI_3): return 3
    case UInt16(kVK_ANSI_4): return 4
    case UInt16(kVK_ANSI_5): return 5
    case UInt16(kVK_ANSI_6): return 6
    case UInt16(kVK_ANSI_7): return 7
    case UInt16(kVK_ANSI_8): return 8
    case UInt16(kVK_ANSI_9): return 9
    default: return nil
    }
  }
```

Add mapping near the top of `keyboardAction`, after the Tab branch:

```swift
    if let number = number(for: keyCode) {
      if modifiers == [.command] {
        return .selectNumber(number)
      }
      if modifiers == [.option] {
        return .pasteNumber(number)
      }
      return nil
    }
```

Add mappings for plain-text paste and detail preview before the final `switch keyCode`:

```swift
    if keyCode == UInt16(kVK_Return), modifiers == [.shift, .option] {
      return .pastePlainText
    }
    if keyCode == UInt16(kVK_ANSI_Y), modifiers == [.command] {
      return .showDetailPreview
    }
```

- [ ] **Step 7: Run key tests**

Run:

```bash
swift test --filter QuickPanelKeyCaptureTests
```

Expected: all `QuickPanelKeyCaptureTests` pass.

- [ ] **Step 8: Commit**

```bash
git add Tests/ClipboardAppTests/QuickPanelKeyCaptureTests.swift Sources/ClipboardApp/QuickPanel/QuickPanelKeyCaptureView.swift
git commit -m "feat: map maccy parity quick panel shortcuts"
```

## Phase 2: Plain-Text Paste Semantics

### Task 5: Add Plain-Text Payload Extraction

**Files:**
- Create: `Sources/ClipboardCore/Paste/PlainTextPastePayload.swift`
- Modify: `Tests/ClipboardCoreTests/PasteControllerTests.swift`

- [ ] **Step 1: Write failing payload extraction tests**

Append these tests to `Tests/ClipboardCoreTests/PasteControllerTests.swift`:

```swift
  func testPlainTextPastePayloadExtractsText() {
    XCTAssertEqual(ClipboardPayload.text("plain").plainTextForPaste, "plain")
  }

  func testPlainTextPastePayloadExtractsRichTextPlainText() {
    let payload = ClipboardPayload.richText(
      plainText: "rich plain",
      rtfData: Data("{\\rtf1 rich}".utf8)
    )

    XCTAssertEqual(payload.plainTextForPaste, "rich plain")
  }

  func testPlainTextPastePayloadRejectsImageAndFiles() {
    XCTAssertNil(ClipboardPayload.image(data: Data([1, 2, 3]), uti: "public.png").plainTextForPaste)
    XCTAssertNil(ClipboardPayload.fileURLs([URL(fileURLWithPath: "/tmp/a.txt")]).plainTextForPaste)
  }
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
swift test --filter PasteControllerTests
```

Expected: build fails because `ClipboardPayload.plainTextForPaste` does not exist.

- [ ] **Step 3: Add helper**

Create `Sources/ClipboardCore/Paste/PlainTextPastePayload.swift`:

```swift
import Foundation

public extension ClipboardPayload {
  var plainTextForPaste: String? {
    switch self {
    case .text(let value):
      return value
    case .richText(let plainText, _):
      return plainText
    case .image, .fileURLs:
      return nil
    }
  }
}
```

- [ ] **Step 4: Run test**

Run:

```bash
swift test --filter PasteControllerTests
```

Expected: all `PasteControllerTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClipboardCore/Paste/PlainTextPastePayload.swift Tests/ClipboardCoreTests/PasteControllerTests.swift
git commit -m "feat: extract plain text paste payloads"
```

### Task 6: Add QuickPanel State For Number Access And Plain-Text Paste

**Files:**
- Modify: `Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift`
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelState.swift`

- [ ] **Step 1: Write failing state tests for number selection**

Append these tests to `Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift`:

```swift
  func testSelectVisibleItemByNumberUsesOneBasedVisibleOrder() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(hash: "first", title: "First", type: .text, lastCopiedAt: 3))
    _ = try await store.upsert(makePanelRecord(hash: "second", title: "Second", type: .text, lastCopiedAt: 2))
    _ = try await store.upsert(makePanelRecord(hash: "third", title: "Third", type: .text, lastCopiedAt: 1))
    let state = makeState(store: store)

    await state.refresh()
    state.selectVisibleItem(number: 2)

    XCTAssertEqual(state.selectedIndex, 1)
    XCTAssertEqual(state.items[state.selectedIndex].title, "Second")
  }

  func testSelectVisibleItemByNumberIgnoresOutOfRangeNumbers() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(hash: "first", title: "First", type: .text, lastCopiedAt: 1))
    let state = makeState(store: store)

    await state.refresh()
    state.selectVisibleItem(number: 9)

    XCTAssertEqual(state.selectedIndex, 0)
    XCTAssertEqual(state.items[state.selectedIndex].title, "First")
  }

  func testNumberSelectionFollowsFilteredVisibleOrder() async throws {
    let store = InMemoryHistoryStore()
    _ = try await store.upsert(makePanelRecord(hash: "alpha-text", title: "Alpha Text", type: .text, lastCopiedAt: 3))
    _ = try await store.upsert(makePanelRecord(hash: "alpha-image", title: "Alpha Image", type: .image, lastCopiedAt: 2))
    _ = try await store.upsert(makePanelRecord(hash: "beta-text", title: "Beta Text", type: .text, lastCopiedAt: 1))
    let state = makeState(store: store)

    state.updateQuery("Alpha")
    await state.refresh()
    state.selectVisibleItem(number: 2)

    XCTAssertEqual(state.items.map(\.title), ["Alpha Text", "Alpha Image"])
    XCTAssertEqual(state.selectedIndex, 1)
    XCTAssertEqual(state.items[state.selectedIndex].title, "Alpha Image")
  }
```

- [ ] **Step 2: Write failing state tests for number paste and plain-text paste**

Append:

```swift
  func testPasteVisibleItemByNumberAutoPastesEvenWhenCopyOnlyWouldBeUsed() async throws {
    let store = InMemoryHistoryStore()
    let payloadStore = InMemoryPayloadStore()
    let pasteboard = AppTestPasteboardWriter()
    let poster = AppTestPasteEventPoster()
    let first = makePanelRecord(hash: "first", title: "First", type: .text, lastCopiedAt: 2)
    let second = makePanelRecord(hash: "second", title: "Second", type: .text, lastCopiedAt: 1)
    _ = try await store.upsert(first)
    _ = try await store.upsert(second)
    try await payloadStore.save(.text("first payload"), for: first.id)
    try await payloadStore.save(.text("second payload"), for: second.id)
    let state = makeState(store: store, payloadStore: payloadStore, pasteboard: pasteboard, eventPoster: poster)

    await state.refresh()
    await state.pasteVisibleItem(number: 2)

    XCTAssertEqual(pasteboard.lastText, "second payload")
    XCTAssertEqual(poster.postCount, 1)
    XCTAssertEqual(state.footerStatus, "Pasted text")
  }

  func testPastePlainTextUsesRichTextPlainText() async throws {
    let store = InMemoryHistoryStore()
    let payloadStore = InMemoryPayloadStore()
    let pasteboard = AppTestPasteboardWriter()
    let record = makePanelRecord(hash: "rich", title: "Rich", type: .richText, lastCopiedAt: 1)
    _ = try await store.upsert(record)
    try await payloadStore.save(.richText(plainText: "unstyled", rtfData: Data("{\\rtf1 styled}".utf8)), for: record.id)
    let state = makeState(store: store, payloadStore: payloadStore, pasteboard: pasteboard)

    await state.refresh()
    await state.pastePlainText()

    XCTAssertEqual(pasteboard.lastText, "unstyled")
    XCTAssertEqual(state.footerStatus, "Pasted plain text")
  }

  func testPastePlainTextReportsUnsupportedFormatForImage() async throws {
    let store = InMemoryHistoryStore()
    let payloadStore = InMemoryPayloadStore()
    let record = makePanelRecord(hash: "image", title: "Image", type: .image, lastCopiedAt: 1)
    _ = try await store.upsert(record)
    try await payloadStore.save(.image(data: Data([1, 2, 3]), uti: "public.png"), for: record.id)
    let state = makeState(store: store, payloadStore: payloadStore)

    await state.refresh()
    await state.pastePlainText()

    XCTAssertEqual(state.footerStatus, "Plain text paste is not supported for image")
  }
```

Then update the test helper signature:

```swift
private func makeState(
  store: InMemoryHistoryStore,
  payloadStore: InMemoryPayloadStore = InMemoryPayloadStore(),
  pasteboard: AppTestPasteboardWriter = AppTestPasteboardWriter(),
  eventPoster: AppTestPasteEventPoster = AppTestPasteEventPoster(),
  mutationService: HistoryMutationService? = nil
) -> QuickPanelState {
  QuickPanelState(
    viewModel: QuickPanelViewModel(store: store, pageLimit: 20),
    payloadStore: payloadStore,
    pasteController: PasteController(
      pasteboard: pasteboard,
      eventPoster: eventPoster
    ),
    mutationService: mutationService ?? HistoryMutationService(store: store, payloadStore: payloadStore)
  )
}
```

Update `AppTestPasteEventPoster`:

```swift
private final class AppTestPasteEventPoster: PasteEventPosting, @unchecked Sendable {
  private(set) var postCount = 0

  func isAccessibilityTrusted() -> Bool { true }

  func postCommandV() async -> Bool {
    postCount += 1
    return true
  }

  func postCommandV(marker: String, pasteboard: any PasteboardWriting) async -> PasteEventResult {
    postCount += 1
    return .posted
  }
}
```

- [ ] **Step 3: Run test to verify failure**

Run:

```bash
swift test --filter QuickPanelStateFilterTests
```

Expected: build fails because `selectVisibleItem(number:)`, `pasteVisibleItem(number:)`, and `pastePlainText()` do not exist.

- [ ] **Step 4: Implement number selection**

Add to `QuickPanelState` after `selectItem(at:)`:

```swift
  func selectVisibleItem(number: Int) {
    let index = number - 1
    selectItem(at: index)
  }
```

- [ ] **Step 5: Implement number paste and plain-text paste**

Add to `QuickPanelState` after `selectCurrent(autoPaste:)`:

```swift
  func pasteVisibleItem(number: Int) async {
    let index = number - 1
    guard items.indices.contains(index) else {
      return
    }

    selectItem(at: index)
    await selectCurrent(autoPaste: true)
  }

  func pastePlainText() async {
    let selectionQuery = query
    let recordID = currentRecordID
    await refresh()

    guard selectionQuery == query else {
      await refresh()
      setUserActionFooterStatus("Selection changed")
      return
    }

    guard let recordID else {
      setUserActionFooterStatus("No clipboard item selected")
      return
    }

    guard let record = items.first(where: { $0.id == recordID }) else {
      setUserActionFooterStatus("Selected item is no longer visible")
      return
    }

    guard let payload = try? await payloadStore.loadPayload(for: record.id) else {
      setUserActionFooterStatus("Payload is unavailable in this session")
      return
    }

    guard let plainText = payload.plainTextForPaste else {
      setUserActionFooterStatus("Plain text paste is not supported for \(record.primaryType.rawValue)")
      return
    }

    let transaction = await pasteController.paste(
      record: record,
      payload: .text(plainText),
      autoPaste: true
    )

    switch transaction.state {
    case .completed:
      actionPrompt = nil
      setUserActionFooterStatus("Pasted plain text")
    case let .failed(reason):
      setUserActionFooterStatus("Paste failed: \(reason.rawValue)")
    default:
      setUserActionFooterStatus("Paste transaction ended in \(transaction.state)")
    }
  }
```

- [ ] **Step 6: Run state tests**

Run:

```bash
swift test --filter QuickPanelStateFilterTests
```

Expected: all `QuickPanelStateFilterTests` pass.

- [ ] **Step 7: Commit**

```bash
git add Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift Sources/ClipboardApp/QuickPanel/QuickPanelState.swift
git commit -m "feat: add quick panel number and plain text paste state"
```

### Task 7: Add Detail Preview State And View Wiring

**Files:**
- Modify: `Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift`
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelState.swift`
- Create: `Sources/ClipboardApp/QuickPanel/QuickPanelDetailPreviewView.swift`
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelView.swift`
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelKeyCaptureView.swift`

- [ ] **Step 1: Add detail preview tests**

Append to `Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift`:

```swift
  func testShowDetailPreviewLoadsSafeTextPayload() async throws {
    let store = InMemoryHistoryStore()
    let payloadStore = InMemoryPayloadStore()
    let record = makePanelRecord(hash: "text", title: "Text", type: .text, lastCopiedAt: 1)
    _ = try await store.upsert(record)
    try await payloadStore.save(.text("full text"), for: record.id)
    let state = makeState(store: store, payloadStore: payloadStore)

    await state.refresh()
    await state.showDetailPreview()

    XCTAssertEqual(state.detailPreview?.title, "Text")
    XCTAssertEqual(state.detailPreview?.body, "full text")
    XCTAssertFalse(state.detailPreview?.isTruncated ?? true)
  }

  func testShowDetailPreviewKeepsLargeTextSummaryFirst() async throws {
    let store = InMemoryHistoryStore()
    let payloadStore = InMemoryPayloadStore()
    let largeText = String(repeating: "a", count: 25_000)
    let record = makePanelRecord(hash: "large", title: "Large", type: .text, lastCopiedAt: 1)
    _ = try await store.upsert(record)
    try await payloadStore.save(.text(largeText), for: record.id)
    let state = makeState(store: store, payloadStore: payloadStore)

    await state.refresh()
    await state.showDetailPreview()

    XCTAssertEqual(state.detailPreview?.body.count, 20_000)
    XCTAssertTrue(state.detailPreview?.isTruncated ?? false)
  }

  func testDismissDetailPreviewClearsPreview() async throws {
    let store = InMemoryHistoryStore()
    let payloadStore = InMemoryPayloadStore()
    let record = makePanelRecord(hash: "text", title: "Text", type: .text, lastCopiedAt: 1)
    _ = try await store.upsert(record)
    try await payloadStore.save(.text("full text"), for: record.id)
    let state = makeState(store: store, payloadStore: payloadStore)

    await state.refresh()
    await state.showDetailPreview()
    state.dismissDetailPreview()

    XCTAssertNil(state.detailPreview)
  }
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
swift test --filter QuickPanelStateFilterTests
```

Expected: build fails because `detailPreview`, `showDetailPreview()`, and `dismissDetailPreview()` do not exist.

- [ ] **Step 3: Add preview model and state methods**

Add near `QuickPanelItemRenderIdentity` in `QuickPanelState.swift`:

```swift
struct QuickPanelDetailPreview: Identifiable, Equatable {
  let id: UUID
  let title: String
  let source: String
  let body: String
  let isTruncated: Bool
}
```

Add published state:

```swift
  @Published private(set) var detailPreview: QuickPanelDetailPreview?
```

Add methods:

```swift
  func showDetailPreview() async {
    guard let recordID = currentRecordID,
          let record = items.first(where: { $0.id == recordID }) else {
      setUserActionFooterStatus("No clipboard item selected")
      return
    }

    guard let payload = try? await payloadStore.loadPayload(for: record.id) else {
      setUserActionFooterStatus("Payload is unavailable in this session")
      return
    }

    let body = detailBody(for: payload, fallback: record.plainTextPreview ?? record.title)
    detailPreview = QuickPanelDetailPreview(
      id: record.id,
      title: record.title,
      source: record.sourceAppName ?? record.primaryType.rawValue,
      body: body.text,
      isTruncated: body.isTruncated
    )
  }

  func dismissDetailPreview() {
    detailPreview = nil
  }

  private func detailBody(for payload: ClipboardPayload, fallback: String) -> (text: String, isTruncated: Bool) {
    let rawText: String = switch payload {
    case .text(let text):
      text
    case .richText(let plainText, _):
      plainText
    case .image:
      fallback.isEmpty ? "Image preview is available in the row." : fallback
    case .fileURLs(let urls):
      urls.map(\.path).joined(separator: "\n")
    }

    let limit = 20_000
    guard rawText.count > limit else {
      return (rawText, false)
    }
    return (String(rawText.prefix(limit)), true)
  }
```

- [ ] **Step 4: Create detail preview view**

Create `Sources/ClipboardApp/QuickPanel/QuickPanelDetailPreviewView.swift`:

```swift
import SwiftUI

struct QuickPanelDetailPreviewView: View {
  let preview: QuickPanelDetailPreview

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(preview.title)
          .font(.headline)
          .lineLimit(2)
        Text(preview.source)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      ScrollView {
        Text(preview.body)
          .font(.system(.body, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      if preview.isTruncated {
        Text("Preview truncated to keep QuickPanel responsive.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(16)
    .frame(minWidth: 560, minHeight: 360)
  }
}
```

- [ ] **Step 5: Wire key callbacks in `QuickPanelView`**

Add callback arguments to `QuickPanelKeyCaptureView(...)` after `onCycleContentFilter`:

```swift
      onSelectNumber: { number in
        state.selectVisibleItem(number: number)
        focusSearch()
      },
      onPasteNumber: { number in
        Task {
          await state.pasteVisibleItem(number: number)
        }
        focusSearch()
      },
      onPastePlainText: {
        Task {
          await state.pastePlainText()
        }
        focusSearch()
      },
      onShowDetailPreview: {
        Task {
          await state.showDetailPreview()
        }
        focusSearch()
      }
```

Add a sheet to `body`, after the existing confirmation dialog:

```swift
    .sheet(
      isPresented: Binding(
        get: { state.detailPreview != nil },
        set: { isPresented in
          if !isPresented {
            state.dismissDetailPreview()
          }
        }
      )
    ) {
      if let preview = state.detailPreview {
        QuickPanelDetailPreviewView(preview: preview)
      }
    }
```

- [ ] **Step 6: Run tests**

Run:

```bash
swift test --filter QuickPanelKeyCaptureTests
swift test --filter QuickPanelStateFilterTests
```

Expected: both test groups pass.

- [ ] **Step 7: Commit**

```bash
git add Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift Sources/ClipboardApp/QuickPanel/QuickPanelState.swift Sources/ClipboardApp/QuickPanel/QuickPanelDetailPreviewView.swift Sources/ClipboardApp/QuickPanel/QuickPanelView.swift Sources/ClipboardApp/QuickPanel/QuickPanelKeyCaptureView.swift
git commit -m "feat: add quick panel detail preview"
```

## Phase 2: Final Wiring And Verification

### Task 8: Final Verification, Stable Build, And Acceptance Notes

**Files:**
- Modify: `docs/manual-acceptance-checklist.md` only if manual acceptance is performed during execution.

- [ ] **Step 1: Run targeted tests**

Run:

```bash
swift test --filter QuickPanel
swift test --filter PasteControllerTests
swift test --filter CaptureControlServiceTests
swift test --filter BenchmarkComparisonTests
```

Expected: all targeted tests pass.

- [ ] **Step 2: Run full verification**

Run:

```bash
Scripts/verify.sh
```

Expected: all repository tests and builds pass.

- [ ] **Step 3: Run benchmark script without baseline**

Run:

```bash
Scripts/benchmark-maccy-replacement.sh
```

Expected:

- script exits 0,
- prints a JSON report path,
- report includes `comparisons`,
- comparisons are `not_comparable` per metric because no Maccy baseline was supplied.

- [ ] **Step 4: Run benchmark script with a sample Maccy baseline**

Create a temporary sample baseline:

```bash
cat > .build/benchmark-reports/sample-maccy-baseline.json <<'JSON'
{
  "source": "same-machine-sample",
  "metrics": [
    { "name": "store_load_ms", "medianMs": 100.0, "p95Ms": 150.0 },
    { "name": "fetch_recent_50_ms", "medianMs": 100.0, "p95Ms": 150.0 },
    { "name": "search_http_50_ms", "medianMs": 100.0, "p95Ms": 150.0 }
  ]
}
JSON
```

Run:

```bash
MACCY_BASELINE_JSON=.build/benchmark-reports/sample-maccy-baseline.json Scripts/benchmark-maccy-replacement.sh
```

Expected:

- script exits 0,
- report includes non-missing comparison fields,
- summary prints per-metric comparison lines.

- [ ] **Step 5: Build stable signed app bundle**

Run:

```bash
CODE_SIGN_KEYCHAIN="$HOME/Library/Keychains/clipboard-signing.keychain-db" \
LOCAL_CODE_SIGN_IDENTITY="ClipboardApp Local Code Signing" \
REQUIRE_STABLE_CODE_SIGNING=1 \
Scripts/build-app-bundle.sh
```

Expected output includes:

```text
signing with identity: 96C518DAFE2B21E278B4013FFCD988BF2FB236FE
.build/app-bundles/release/ClipboardApp.app
```

- [ ] **Step 6: Verify signature authority**

Run:

```bash
codesign -dv --verbose=4 .build/app-bundles/release/ClipboardApp.app
```

Expected output includes:

```text
Authority=ClipboardApp Local Code Signing
```

- [ ] **Step 7: Manual acceptance**

Use `.build/app-bundles/release/ClipboardApp.app` and verify the B-level checklist items added in Task 1. Do not mark checklist items complete unless the user confirms they passed in the real UI.

- [ ] **Step 8: Commit acceptance notes if manual acceptance was performed**

If the user confirms manual acceptance passed, update `docs/manual-acceptance-checklist.md`:

````markdown
## Maccy B-Level Daily Replacement 验收记录（2026-05-22）

```text
日期: 2026-05-22
机器: 本机 Apple Silicon
系统: macOS 26.5 (25F71)
架构: arm64
场景: Maccy B-Level Daily Replacement 真实 UI 验收
命令:
  - swift test --filter QuickPanel
  - swift test --filter PasteControllerTests
  - swift test --filter CaptureControlServiceTests
  - swift test --filter BenchmarkComparisonTests
  - Scripts/verify.sh
  - Scripts/benchmark-maccy-replacement.sh
  - MACCY_BASELINE_JSON=<baseline-json> Scripts/benchmark-maccy-replacement.sh
  - CODE_SIGN_KEYCHAIN="$HOME/Library/Keychains/clipboard-signing.keychain-db" LOCAL_CODE_SIGN_IDENTITY="ClipboardApp Local Code Signing" REQUIRE_STABLE_CODE_SIGNING=1 Scripts/build-app-bundle.sh
  - codesign -dv --verbose=4 .build/app-bundles/release/ClipboardApp.app
结果:
  - 自动化测试通过
  - benchmark 报告生成，comparison 按 metric 输出
  - app bundle 稳定签名通过
  - 用户真实 UI 验收通过
问题: 未发现问题
截图/录屏: 未采集；以用户真实 UI 验收反馈和自动化命令输出作为证据。
结论: PASS，Clipboard 达到 B 级日常 Maccy 替代标准。
```
````

Then commit:

```bash
git add docs/manual-acceptance-checklist.md
git commit -m "docs: record maccy b-level acceptance"
```

If manual acceptance is not performed during implementation, skip this commit and report the remaining manual acceptance gap.
