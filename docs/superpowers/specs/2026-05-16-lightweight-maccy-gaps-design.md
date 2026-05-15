# Lightweight Maccy Gap Closure Design

## Scope

This change closes four remaining gaps that still affect the app's ability to act as a lightweight Maccy replacement:

1. Retention policy changes from Settings must affect the running store.
2. Evicted or removed history records must release payload files promptly.
3. QuickPanel must expose user-operable content type filters, not only store-level filtering.
4. Paste diagnostics must distinguish focus loss, rejected paste, and event posting failures.

## Design

Retention updates use a small `RetentionPolicyUpdating` capability. `SQLiteHistoryStore` owns mutable retention policy state and applies the policy immediately when updated. `SelfHealingHistoryStore` forwards the capability to the wrapped store when available. `AppServices` exposes an async method used by `HistorySettingsView` after `@AppStorage` changes.

Payload cleanup is handled through a new store/payload coordinator instead of making SQLite know about the filesystem. A `PayloadCleaningHistoryStore` wraps any `HistoryStore`, snapshots IDs before `removeAll` and `evictOldest`, delegates the record deletion, then deletes payload files for records no longer referenced. Startup orphan scan remains a fallback, not the primary cleanup path.

QuickPanel type filtering stays compact: add a segmented picker for common content types (`all`, `text`, `link`, `image`, `file`) above the list. State owns the selected filter and passes it to `QuickPanelViewModel.refresh`.

Paste diagnostics extend `PasteEventPosting` with a structured result. The platform implementation checks focused app before and after posting Command-V, waits briefly, and reports reliable platform failures such as event posting failure or target focus loss. Target rejection is represented in the core protocol and controller mapping for future platform-specific detection, but the macOS pasteboard marker is not used as rejection evidence because it can survive successful paste operations. The existing boolean `postCommandV()` remains as a compatibility wrapper.

## Tests

Tests cover live retention updates, payload cleanup after `removeAll` and `evictOldest`, QuickPanel filter state propagation, and PasteController mapping structured paste results to failure reasons.
