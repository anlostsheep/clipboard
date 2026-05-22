# Maccy B-Level Daily Replacement Design

## Scope

This design defines the B-level daily replacement target for Clipboard against Maccy. The target is not to clone every Maccy feature. The target is to make Clipboard reliable enough for the user's daily Maccy replacement workflow while preserving Clipboard's own stronger boundaries around Universal Clipboard handling, import fidelity, privacy controls, stable signing, and evidence-based performance claims.

This design combines two tracks:

1. Replacement capability hardening: prove the existing core capabilities with automated verification, real UI acceptance, runtime privacy checks, import UI acceptance, paste behavior acceptance, stable signing, and same-machine benchmark evidence.
2. High-frequency interaction parity: add the Maccy-style interactions that materially affect daily speed, especially plain-text paste and number-key access.

Public Maccy references used for the parity target:

- https://github.com/p0deje/Maccy
- https://maccy.app/

## Goals

1. Close the remaining evidence gaps that prevent a defensible "daily replacement" claim.
2. Add Maccy-level high-frequency QuickPanel interactions:
   - Plain-text paste from text-like records.
   - Number-key selection for visible records.
   - Number-key direct paste for visible records.
   - Stable number access for pinned records when pinned and history records are mixed.
   - Full or detail preview for selected records without regressing large-content performance.
3. Keep the implementation aligned with existing `ClipboardCore`, `ClipboardPlatform`, and `ClipboardApp` boundaries.
4. Keep performance claims metric-scoped. Clipboard must not claim to be faster than Maccy unless the relevant same-machine, same-metric benchmark supports that claim.
5. Keep all new manual acceptance state synchronized in `docs/manual-acceptance-checklist.md`.

## Non-Goals

- OCR.
- Shortcuts integration.
- Notifications.
- Complex automation rules.
- Full Library Window browsing.
- CloudKit or other cross-device app sync.
- DMG, notarization, Homebrew Cask, or broader distribution packaging.
- Replacing the current SQLite storage architecture.
- Replacing QuickPanel with a separate browser-style history window.

## Capability Matrix

### P0: Replacement Capability Hardening

These are required before Clipboard can be called a B-level daily Maccy replacement.

- Paste matrix:
  - Return and double-click auto-paste into a normal text field.
  - Return and double-click auto-paste into a rich text editor.
  - Return and double-click auto-paste into Terminal.
  - Return and double-click auto-paste into a browser address bar.
  - Copy-only mode writes the selected record to the system pasteboard without posting Command-V.
  - Copy-only mode allows a later manual Command-V paste.
- Runtime privacy and capture controls:
  - Pause capture.
  - Resume capture.
  - Ignore next copy exactly once.
  - Ignore Universal Clipboard records.
  - Ignore configured pasteboard types.
  - Ignore configured source app bundle IDs.
  - Changes affect the running capture path without restart.
- QuickPanel management actions:
  - Delete selected item.
  - Pin and unpin selected item.
  - Clear unpinned items while preserving pinned records.
  - Clear all history only after confirmation.
  - Payload files are cleaned when records are removed.
- Import acceptance:
  - Settings import page discovers installed Maccy and Clipaste sources.
  - Manual source selection validates schema before import.
  - Imported text, link, rich text, image, and file records are searchable and usable in QuickPanel.
  - Duplicate imports merge copy count, pin/favorite state, groups, pasteboard types, and Universal Clipboard markers.
  - Import reports are written and visible after success, cancellation, or failure.
- Benchmark evidence:
  - Clipboard benchmark JSON and readable summary exist.
  - Maccy same-machine baseline exists for comparable metrics where feasible.
  - Each comparison is labeled `better`, `same`, `worse`, or `not_comparable`.
  - Any `not_comparable` metric states why it cannot be compared fairly.
- Stable signed verification:
  - `Scripts/verify.sh` passes.
  - `swift test --filter QuickPanel` passes.
  - Stable app bundle build passes using `ClipboardApp Local Code Signing`.
  - `codesign` output includes `Authority=ClipboardApp Local Code Signing`.

### P1: High-Frequency Interaction Parity

These items make Clipboard feel close to Maccy for daily keyboard-driven use.

- Plain-text paste:
  - `Option+Shift+Enter` pastes the selected text-like record without formatting.
  - Text, link, and rich text records support this mode.
  - Rich text uses the stored plain text.
  - Image and file records return `formatUnsupported` and show a footer message.
- Number-key visible record access:
  - `Command+1...9` selects the visible record at index 1...9.
  - `Option+1...9` directly auto-pastes the visible record at index 1...9.
  - `Option+1...9` is an explicit paste command and does not inherit the copy-only Return/double-click setting.
  - Number mapping follows current visual order after search and type filtering.
  - Number mapping remains predictable when pinned and history sections are both visible.
- Pinned record access:
  - Pinned rows remain reachable by number shortcuts before history rows.
  - The mapping should not depend on offscreen records.
  - If the UI limits visible pinned rows to preserve history visibility, shortcuts follow the visible rows only.
- Detail preview:
  - A keyboard action such as `Space` or `Command+Y` opens a selected-record detail preview.
  - Detail preview can show full text for safe-size records.
  - Large text remains summary-first and requires explicit detail loading.
  - Image preview should not decode large images during the QuickPanel first frame.

### P2: Experience Completion

These items turn the feature set into a maintainable product surface.

- Settings surfaces expose the relevant defaults:
  - Auto-paste versus copy-only mode.
  - Hotkey recording and validation.
  - Privacy ignored apps and pasteboard types.
  - Universal Clipboard capture toggle.
  - Retention policy.
  - Import status and reports.
- Failure states are visible and specific:
  - Pasteboard write failure.
  - Accessibility permission missing or revoked.
  - Target app focus lost.
  - Paste event failure.
  - Unsupported format for plain-text paste.
  - Missing payload or inaccessible file payload.
- Manual acceptance remains up to date:
  - New checklist items are added before implementation is considered complete.
  - User-confirmed physical validation is recorded immediately.

## Architecture

This design uses the current boundaries.

### QuickPanel Interaction Layer

`QuickPanelKeyCaptureView` remains the only place that maps key events into typed actions. It should gain only narrow actions:

- `selectNumber(Int)`
- `pasteNumber(Int)`
- `pastePlainText`
- `showDetailPreview`

`QuickPanelView` wires these actions to state callbacks and keeps search focus when appropriate.

`QuickPanelState` owns the semantics:

- Resolve visible record by number.
- Select by number.
- Submit by number.
- Request plain-text paste for the selected record.
- Request detail preview for the selected record.
- Refresh items and footer after mutations or failed actions.

`QuickPanelViewModel` remains responsible for query and content filtering. It should not learn about key combinations.

### Paste Semantics

Plain-text paste should be modeled as a paste mode, not as UI-local payload rewriting.

```text
QuickPanel key action
-> QuickPanelState plain-text paste request
-> payloadStore.loadPayload(recordID)
-> extract plain text from text/link/richText
-> PasteController writes .text(...)
-> PasteEventPosting.postCommandV(...)
-> footer status or action prompt
```

Expected extraction rules:

- `.text(value)`: paste `value`.
- `.richText(plainText, _)`: paste `plainText`.
- Link records stored as text: paste the URL text.
- `.image` and `.fileURLs`: fail with `formatUnsupported`.

Plain-text paste must not change the default Return or double-click behavior.

### Runtime Privacy And Capture Controls

The model already exists in `CaptureControlService`, `PrivacyPolicy`, and `AppSettings.privacyPolicy`. This design requires proof and UI wiring:

```text
Settings or status-bar action
-> AppServices
-> live CaptureControlService state
-> ClipboardCaptureCoordinator.captureLatestChange()
-> allow ingest or skip with diagnostic reason
```

Pause, resume, ignore-next-copy, ignored app, ignored type, and Universal Clipboard ignore must be observable without restarting the app.

### Benchmark Evidence

Benchmarking continues through `Scripts/benchmark-maccy-replacement.sh` and `ClipboardBenchmarkProbe`, but the report must include comparable Maccy baselines where feasible.

```text
Clipboard metrics
-> optional Maccy baseline metrics
-> dataset description
-> comparison confidence
-> per-metric result
```

Required report fields:

- Dataset size and record counts by type.
- Pinned count.
- Payload directory size.
- Clipboard cold store load.
- QuickPanel fetch with empty query.
- QuickPanel search samples.
- Representative pasteboard write times.
- Large text classification times.
- Maccy baseline source and measurement method.
- Per-metric comparison result.

The benchmark may still return `not_comparable`, but only per metric and only with a reason.

### Acceptance Documentation

`docs/manual-acceptance-checklist.md` is part of the product contract for this work. Every new user-facing behavior must have:

- An unchecked checklist item before or during implementation.
- A checked item only after the user or a reliable physical acceptance path confirms it.
- A dated acceptance record when the feature reaches final validation.

## Data Flows

### Number Selection

```text
Command+N
-> QuickPanelKeyCaptureView.keyboardAction
-> .selectNumber(N)
-> QuickPanelState.selectVisibleItem(number: N)
-> selectedIndex updates if visible item exists
-> footer remains non-noisy
```

### Number Paste

```text
Option+N
-> QuickPanelKeyCaptureView.keyboardAction
-> .pasteNumber(N)
-> QuickPanelState.submitVisibleItem(number: N)
-> QuickPanelViewModel selected intent for that record
-> PasteController
-> auto-paste, because Option+N is an explicit paste command
```

### Plain-Text Paste

```text
Option+Shift+Enter
-> QuickPanelKeyCaptureView.keyboardAction
-> .pastePlainText
-> QuickPanelState.pastePlainText()
-> payload extraction
-> PasteController plain-text paste
-> success footer or specific failure
```

### Runtime Privacy Validation

```text
User toggles setting or status action
-> AppServices updates live control state
-> next ClipboardCaptureCoordinator capture
-> CaptureControlService decision
-> allowed ingest or skipped diagnostic
-> probe/test/manual acceptance records result
```

## Error Handling

Number shortcuts that refer to a non-visible item should no-op and avoid noisy alerts. The footer can remain unchanged.

Plain-text paste failures should be visible:

- Unsupported image/file payload: `formatUnsupported`.
- Missing record: `recordMissing`.
- Missing payload: `blobMissing`.
- Pasteboard write failure: `pasteboardWriteFailed`.
- Accessibility missing or revoked: existing authorization prompt.
- Target focus lost or event failure: existing paste diagnostics.

Benchmark failures should produce a partial report when possible. A failed Maccy metric must not invalidate Clipboard's own metrics, but it must prevent a misleading comparison claim.

Capture skips are normal control-flow and should be diagnosable without being noisy in the UI.

## Tests

### Automated Tests

Add or extend tests for:

- `QuickPanelKeyCaptureTests`
  - `Option+Shift+Enter` maps to plain-text paste.
  - `Command+1...9` maps to visible item selection.
  - `Option+1...9` maps to visible item paste.
  - Number shortcuts do not conflict with existing Tab, delete, pin, settings, search, and quit mappings.
- QuickPanel state tests
  - Number selection updates `selectedIndex`.
  - Number selection follows current visible order after query and type filtering.
  - Number paste targets the intended visible record.
  - Number paste requests auto-paste even when Return/double-click copy-only mode is enabled.
  - Pinned/history mixed sections preserve visual-order mapping.
  - Out-of-range number shortcuts do not crash and do not select hidden records.
- Paste tests
  - Text plain-text paste writes text and posts paste.
  - Link plain-text paste writes URL text and posts paste.
  - Rich text plain-text paste writes plain text and posts paste.
  - Image and file plain-text paste return `formatUnsupported`.
  - Missing accessibility still follows the current permission prompt path.
- Capture and privacy tests
  - Pause/resume affects active capture.
  - Ignore-next-copy skips exactly one capture.
  - Ignored Universal Clipboard, pasteboard type, and app bundle settings affect the live policy.
- Benchmark tests
  - Missing Maccy baseline yields `not_comparable`.
  - Thresholds produce `better`, `same`, and `worse`.
  - Report serialization includes comparison reason and confidence fields.

### Verification Commands

At minimum, run:

```bash
swift test --filter QuickPanel
swift test --filter PasteControllerTests
swift test --filter CaptureControlServiceTests
swift test --filter BenchmarkComparisonTests
Scripts/verify.sh
CODE_SIGN_KEYCHAIN="$HOME/Library/Keychains/clipboard-signing.keychain-db" \
LOCAL_CODE_SIGN_IDENTITY="ClipboardApp Local Code Signing" \
REQUIRE_STABLE_CODE_SIGNING=1 \
Scripts/build-app-bundle.sh
codesign -dv --verbose=4 .build/app-bundles/release/ClipboardApp.app
```

The signing verification must show:

```text
Authority=ClipboardApp Local Code Signing
```

## Manual Acceptance

Manual acceptance must cover:

- Return and double-click auto-paste in:
  - normal text field,
  - rich text editor,
  - Terminal,
  - browser address bar.
- Copy-only mode:
  - Return and double-click do not auto-paste.
  - The selected item is written to the system pasteboard.
  - A later manual Command-V pastes that item.
- Plain-text paste:
  - Rich text source pastes without style.
  - Text and link sources paste as plain text.
  - Image/file sources show a clear unsupported-format state.
- Number shortcuts:
  - `Command+1...9` selects the visible row.
  - `Option+1...9` auto-pastes the visible row.
  - `Option+1...9` still auto-pastes when Return/double-click copy-only mode is enabled.
  - Search and content-type filters change the visible mapping correctly.
  - Pinned/history mixed sections follow the visual order.
- Privacy and capture:
  - Pause capture prevents history growth.
  - Resume capture allows history growth.
  - Ignore-next-copy skips one item and then resets.
  - Ignored Universal Clipboard, pasteboard type, and app bundle ID prevent capture.
- Import:
  - Settings import page finds Maccy/Clipaste sources.
  - Manual source selection validates schemas.
  - Imported records are searchable and usable in QuickPanel.
  - Import reports are visible and copyable.
- Benchmark:
  - Clipboard report is generated.
  - Maccy baseline is generated for comparable metrics.
  - Comparison language stays per metric.
- Stable app bundle:
  - The physically tested app bundle is stable signed.

## Completion Criteria

This B-level parity target is complete when:

1. P0 replacement capability hardening has automated or real UI evidence.
2. P1 high-frequency interactions include at least plain-text paste and number-key visible record access.
3. `swift test --filter QuickPanel` passes.
4. The targeted paste, capture, and benchmark tests pass.
5. `Scripts/verify.sh` passes.
6. The stable signing build passes and `codesign` shows `Authority=ClipboardApp Local Code Signing`.
7. Benchmark output includes Clipboard metrics and Maccy baselines for comparable metrics.
8. No overall performance superiority claim is made without matching per-metric evidence.
9. `docs/manual-acceptance-checklist.md` reflects the actual acceptance state.
10. OCR, Shortcuts, notifications, Library Window, cloud sync, and distribution packaging remain outside the completion claim.

## Implementation Phases

### Phase 1: P0 Evidence And Runtime Hardening

Close the current replacement evidence gaps:

- Finish paste behavior acceptance.
- Finish privacy/capture acceptance.
- Finish QuickPanel management acceptance.
- Finish import UI acceptance.
- Extend benchmark reporting with Maccy baseline support.
- Verify stable signing.

### Phase 2: P1 Interaction Parity

Implement the high-frequency workflow improvements:

- Plain-text paste.
- Number selection.
- Number direct paste.
- Pinned/history number mapping.
- Detail preview.

The implementation plan may split these phases into separate commits or even separate execution batches, but they remain one design target.

## Risks

- Maccy UI metrics may not be fully automatable. The benchmark must label comparison confidence instead of forcing comparability.
- Number shortcuts can conflict with text entry. They must only be captured inside QuickPanel and only for the exact modifier combinations.
- `Option+Shift+Enter` may interact with system keyboard layouts. Tests should verify modifier normalization.
- Detail preview can regress large-content performance if it loads full payloads eagerly. It must be explicit and lazy.
- Manual acceptance can lag actual state. The checklist must be updated immediately when the user confirms physical validation.
