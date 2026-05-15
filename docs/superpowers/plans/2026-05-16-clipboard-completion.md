# Clipboard Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete background capture, rich/link content recognition, and practical search filters for the clipboard manager.

**Architecture:** Add a small capture loop around the existing coordinator, preserve pasteboard payload contracts, and extend the store query API with typed filters. Keep SQLite's current in-memory hot index and avoid schema migration.

**Tech Stack:** Swift 5.10, Swift Concurrency, AppKit `NSPasteboard`, XCTest, existing `ClipboardCore` / `ClipboardPlatform` / `ClipboardApp` targets.

---

### Task 1: Background Capture Loop

**Files:**
- Create: `Sources/ClipboardCore/Ingest/ClipboardCaptureLoop.swift`
- Modify: `Sources/ClipboardApp/AppServices.swift`
- Test: `Tests/ClipboardCoreTests/ClipboardCaptureLoopTests.swift`

- [x] Write a failing test showing that a capture loop invokes its capture closure repeatedly and stops after cancellation.
- [x] Implement a cancellable, idempotent `ClipboardCaptureLoop`.
- [x] Start the loop from `AppServices.init()` after `captureCoordinator` is initialized.
- [x] Run `swift test --filter ClipboardCaptureLoopTests`.

### Task 2: Rich Text and Link Classification

**Files:**
- Modify: `Sources/ClipboardPlatform/SystemPasteboardClient.swift`
- Modify: `Sources/ClipboardCore/Ingest/ClipboardIngestService.swift`
- Test: `Tests/ClipboardPlatformTests/SystemPasteboardClientTests.swift`
- Test: `Tests/ClipboardCoreTests/ClipboardIngestServiceTests.swift`

- [x] Write a failing pasteboard test for external RTF capture.
- [x] Write a failing ingest test for HTTP/HTTPS URL text becoming `.link`.
- [x] Read RTF before plain text when no image payload exists.
- [x] Add URL classification in ingest without adding a new payload case.
- [x] Run targeted platform and ingest tests.

### Task 3: Search Filters

**Files:**
- Modify: `Sources/ClipboardCore/Storage/HistoryStore.swift`
- Modify: `Sources/ClipboardCore/Storage/SelfHealingHistoryStore.swift`
- Modify: `Sources/ClipboardCore/Storage/SQLite/SQLiteHistoryStore.swift`
- Modify: `Sources/ClipboardCore/UI/QuickPanelViewModel.swift`
- Test: `Tests/ClipboardCoreTests/HistoryStoreConformanceTests.swift`
- Test: `Tests/ClipboardCoreTests/QuickPanelViewModelTests.swift`

- [x] Write failing store contract tests for content type and group filtering.
- [x] Add `HistoryQuery` with text, content types, and group IDs.
- [x] Keep `fetchPage(query:limit:)` as a wrapper for compatibility.
- [x] Add `QuickPanelViewModel.refresh(query:contentTypes:groupIDs:)`.
- [x] Run store and QuickPanel view model tests.

### Task 4: Full Verification

**Files:**
- Existing verification scripts only.

- [x] Run `swift test`.
- [x] Run `Scripts/verify.sh`.
- [x] Inspect `git diff --stat` and `git status --short`.
