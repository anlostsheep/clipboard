# Lightweight Maccy Gap Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the four runtime and UI gaps that remain after the initial clipboard capture/search completion.

**Architecture:** Add narrow capabilities around existing stores and paste protocols rather than replacing the storage or QuickPanel architecture. Keep behavior testable through focused wrappers and protocol extensions.

**Tech Stack:** Swift 5.10, SwiftUI, AppKit, Swift Concurrency actors, XCTest, existing ClipboardCore/ClipboardPlatform/ClipboardApp targets.

---

### Task 1: Runtime Retention Policy Updates

**Files:**
- Modify: `Sources/ClipboardCore/Storage/HistoryStore.swift`
- Modify: `Sources/ClipboardCore/Storage/SQLite/SQLiteHistoryStore.swift`
- Modify: `Sources/ClipboardCore/Storage/SelfHealingHistoryStore.swift`
- Modify: `Sources/ClipboardApp/AppServices.swift`
- Modify: `Sources/ClipboardApp/Settings/HistorySettingsView.swift`
- Test: `Tests/ClipboardCoreTests/SQLiteHistoryStoreTests.swift`
- Test: `Tests/ClipboardCoreTests/SelfHealingHistoryStoreTests.swift`

- [x] Write failing tests for applying a stricter retention policy after store initialization.
- [x] Add `RetentionPolicyUpdating` and implement it in SQLite and SelfHealing stores.
- [x] Expose `AppServices.updateRetentionPolicyFromSettings()`.
- [x] Call it when Settings steppers change and update the help text.
- [x] Run targeted retention tests.

### Task 2: Prompt Payload Cleanup

**Files:**
- Create: `Sources/ClipboardCore/Storage/PayloadCleaningHistoryStore.swift`
- Modify: `Sources/ClipboardApp/AppServices.swift`
- Test: `Tests/ClipboardCoreTests/PayloadCleaningHistoryStoreTests.swift`

- [x] Write failing tests proving `removeAll` and `evictOldest` delete payloads for removed records.
- [x] Implement `PayloadCleaningHistoryStore` as a wrapper over `HistoryStore` + `ClipboardPayloadStore`.
- [x] Wrap the self-healing SQLite store in AppServices before exposing it to ingest and UI.
- [x] Run payload cleanup tests.

### Task 3: QuickPanel Type Filter UI

**Files:**
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelState.swift`
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelView.swift`
- Test: `Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift`

- [x] Write failing state/view-model level tests for content type filtering.
- [x] Add QuickPanel filter state and pass selected content types into refresh.
- [x] Add a compact segmented picker to QuickPanel search row.
- [x] Run QuickPanel tests.

### Task 4: Paste Diagnostics

**Files:**
- Modify: `Sources/ClipboardCore/Paste/PasteInterfaces.swift`
- Modify: `Sources/ClipboardCore/Paste/PasteController.swift`
- Modify: `Sources/ClipboardPlatform/SystemPasteboardClient.swift`
- Test: `Tests/ClipboardCoreTests/PasteControllerTests.swift`

- [x] Write failing tests for focus-lost and target-rejected paste results.
- [x] Add structured `PasteEventResult` with compatibility wrapper.
- [x] Map structured results in `PasteController`.
- [x] Implement best-effort platform diagnostics around focused app and protocol result mapping.
- [x] Run paste controller and platform tests.

### Task 5: Verification and Delivery

**Files:**
- Existing project scripts only.

- [x] Run `swift test`.
- [x] Run `Scripts/verify.sh`.
- [x] Commit scoped changes and push `feature/persistent-storage`.

### Task 6: Post-Verification Interaction Fixes

**Files:**
- Modify: `Sources/ClipboardApp/AppSettings.swift`
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelController.swift`
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelKeyCaptureView.swift`
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelState.swift`
- Modify: `Sources/ClipboardApp/QuickPanel/QuickPanelView.swift`
- Modify: `Sources/ClipboardApp/Settings/GeneralSettingsView.swift`
- Modify: `Sources/ClipboardApp/Settings/SettingsWindow.swift`
- Modify: `Sources/ClipboardApp/StatusBar/StatusBarController.swift`
- Test: `Tests/ClipboardAppTests/AccessibilityPermissionStateTests.swift`
- Test: `Tests/ClipboardAppTests/QuickPanelControllerPresentationTests.swift`
- Test: `Tests/ClipboardAppTests/QuickPanelKeyCaptureTests.swift`
- Test: `Tests/ClipboardAppTests/QuickPanelStateFilterTests.swift`
- Test: `Tests/ClipboardAppTests/SettingsWindowShortcutTests.swift`
- Test: `Tests/ClipboardAppTests/StatusBarControllerTests.swift`

- [x] Fix first-trigger QuickPanel presentation from hot key and status-bar icon.
- [x] Preserve search recovery via `Command+F` after arrow-key selection.
- [x] Enable mouse click selection with the same copy/paste semantics as `Return`.
- [x] Add actionable Accessibility permission prompts when auto-paste cannot run.
- [x] Add live Accessibility authorization refresh after System Settings changes.
- [x] Add QuickPanel open-selection preference: latest record or previous selection.
- [x] Add macOS-standard `Command+,` for Settings and `Command+W` for closing Settings.
- [x] Make `Escape` cancellation restore the originating app rather than reactivating an existing Settings window.
- [x] Run full automated verification and user physical acceptance.
