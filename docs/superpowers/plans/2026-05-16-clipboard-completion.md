# Clipboard Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete background capture, rich/link content recognition, practical search filters, and the QuickPanel interaction polish required for a lightweight Maccy-style daily workflow.

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

### Task 5: QuickPanel and Settings Interaction Polish

**Files:**
- Modify: `Sources/ClipboardApp/AppSettings.swift`
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelController.swift`
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelKeyCaptureView.swift`
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelState.swift`
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelView.swift`
- Modify: `Sources/ClipboardApp/Settings/GeneralSettingsView.swift`
- Modify: `Sources/ClipboardApp/Settings/SettingsWindow.swift`
- Modify: `Sources/ClipboardApp/StatusBar/StatusBarController.swift`
- Test: `Tests/ClipboardAppTests/QuickPanelControllerPresentationTests.swift`
- Test: `Tests/ClipboardAppTests/QuickPanelKeyCaptureTests.swift`
- Test: `Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift`
- Test: `Tests/ClipboardAppTests/SettingsWindowShortcutTests.swift`
- Test: `Tests/ClipboardAppTests/StatusBarControllerTests.swift`

- [x] Make hot-key and status-bar invocations present QuickPanel on the first trigger across common foreground apps.
- [x] Support `Command+F` to return focus to the QuickPanel search field after keyboard navigation.
- [x] Make mouse row selection use the same select action as `Return`.
- [x] Clarify copy-only versus auto-paste labels and footer hints.
- [x] Add `Command+,` handling from QuickPanel to open Settings.
- [x] Add `Command+W` handling for the Settings window.
- [x] Make `Escape` cancellation restore the previously frontmost app instead of surfacing an already-open Settings window.
- [x] Add a setting for QuickPanel open selection behavior: latest record or previous selection.
- [x] Keep the type-filter control compact so the "类型" label does not wrap.

### Task 6: Accessibility Permission UX

**Files:**
- Create: `Sources/ClipboardApp/Settings/AccessibilityPermissionState.swift`
- Modify: `Sources/ClipboardApp/App/AppDelegate.swift`
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelController.swift`
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelState.swift`
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelView.swift`
- Modify: `Sources/ClipboardApp/Settings/GeneralSettingsView.swift`
- Test: `Tests/ClipboardAppTests/AccessibilityPermissionStateTests.swift`
- Test: `Tests/ClipboardAppTests/QuickPanelControllerPresentationTests.swift`
- Test: `Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift`

- [x] Resolve Accessibility authorization with a fresh helper-process check so add/remove in System Settings updates the Settings page.
- [x] Block auto-paste when Accessibility is missing and keep QuickPanel open with a visible action prompt.
- [x] Show the same permission prompt for both mouse click and keyboard `Return`.
- [x] Keep copy-only mode independent of Accessibility permission.

### Task 7: Branch Completion

**Files:**
- Modify: `docs/manual-acceptance-checklist.md`
- Modify: `docs/superpowers/plans/2026-05-16-clipboard-completion.md`
- Modify: `CLAUDE.md`

- [x] Record the completed feature set and physical validation coverage.
- [x] Run `swift test`.
- [x] Run `Scripts/verify.sh`.
- [x] Run `git diff --check`.
- [x] Build and launch `.build/app-bundles/debug/ClipboardApp.app` for final manual verification.
