# Clipboard Completion Design

## Scope

This change completes the three gaps identified in the current branch:

1. Capture clipboard changes continuously in the background, not only when QuickPanel opens.
2. Read richer pasteboard content by preserving RTF and classifying URL text as links.
3. Extend search so QuickPanel can filter by content type and group without replacing the existing storage layer.

## Design

Background capture remains built around `ClipboardMonitor.poll()` and `ClipboardCaptureCoordinator.captureLatestChange()`. A small lifecycle-owned capture loop repeatedly invokes the coordinator at a fixed interval. The loop is idempotent, cancellable, and ignores transient capture errors so one bad pasteboard item does not stop future captures. `AppServices` owns the loop and still keeps the QuickPanel pre-show capture as a cheap final synchronization point.

Pasteboard reading keeps the existing priority of image data over text metadata. If no image is present, RTF is read before plain text and stored as `.richText(plainText:rtfData:)`. Plain URL strings remain payload `.text`, but ingest classifies valid HTTP/HTTPS URL text as `primaryType == .link`, preserving paste behavior while making the record searchable and visually typed as a link.

Search adds a small `HistoryQuery` value used by stores and `QuickPanelViewModel`. The existing `fetchPage(query:limit:)` API remains as a compatibility wrapper. The new query supports free text, optional content types, and optional group IDs. Filtering is still in-memory over the hot index for this iteration, which matches the current SQLite store architecture and avoids a schema migration.

## Tests

Tests cover:

- Capture loop starts, repeats capture work, and stops cleanly.
- External RTF pasteboard items are captured as rich text.
- URL text ingests as link records.
- History queries can filter by type and group while preserving existing free-text behavior.

