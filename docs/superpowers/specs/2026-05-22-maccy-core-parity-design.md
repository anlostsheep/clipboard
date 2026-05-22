# Maccy Core Parity Design

## Scope

This design defines the next parity target for Clipboard against Maccy. The target is not to clone every Maccy feature. The target is to make Clipboard's core experience no worse than Maccy for the user's high-frequency workflow:

1. QuickPanel search, navigation, filtering, selection, paste, pin, and delete.
2. History persistence, import, cleanup, and large-history behavior.
3. Reliable handling of text, rich text, links, images, files, and Universal Clipboard.
4. Fast panel opening, fast search, and safe large-content preview.
5. macOS integration through menu bar, global hotkey, accessibility permission handling, focus restore, and stable signing.

The first concrete enhancement in this parity line is keyboard cycling through QuickPanel content types with `Tab` and `Shift+Tab`.

## Goals

- Define a core parity matrix that separates must-have Maccy-level behavior from optional product enhancements.
- Add a keyboard-first type switching interaction to QuickPanel:
  - `Tab`: `All -> Text -> Link -> Image -> File -> All`.
  - `Shift+Tab`: reverse order.
  - Search text remains intact.
  - Search focus remains active.
  - The list refreshes immediately.
- Keep the implementation narrow and aligned with existing QuickPanel state, keyboard capture, and filter refresh boundaries.
- Preserve existing QuickPanel keyboard behavior for arrows, Return, Escape, `Command+F`, `Option+P`, delete shortcuts, and settings shortcuts.

## Non-Goals

- OCR.
- Shortcuts integration.
- Notifications.
- A full Library Window.
- Complex rule automation.
- A claim that Clipboard is faster than Maccy without same-machine, same-metric Maccy baseline evidence.
- Replacing the current QuickPanel picker or search architecture.

## Core Parity Matrix

### Must Match

QuickPanel must remain keyboard-first. Search, Up/Down selection, Return copy/paste, Escape close, pin/unpin, delete, clear, settings access, and type filtering must all work without leaving the panel.

History management must preserve the current behavior: SQLite-backed persistence, retention policy, pinned-record protection, payload cleanup, Maccy/Clipaste import, duplicate merging, and large-history loading.

Content handling must cover text, rich text, links, images, files, and Universal Clipboard. Universal Clipboard records must use neutral source presentation instead of stale foreground app metadata.

Performance must stay bounded: opening the panel, fetching recent records, searching, and rendering large text should not visibly block the UI. Large content should keep summary-first rendering.

System integration must keep global hotkey support, menu-bar access, accessibility permission diagnostics, focus restoration, and stable signing as required behavior.

### First Enhancement Batch

- Tab-based content type cycling in QuickPanel.
- Footer or help text can mention Tab type switching if the text remains compact and does not crowd the panel.
- Benchmark reports can continue to describe Clipboard's own metrics, but Maccy comparison remains `not_comparable` until a fair baseline exists.

### Explicitly Deferred

OCR, Shortcuts, notification workflows, advanced automation rules, and full Library Window browsing remain outside the parity gate. They can become separate product enhancements after the core parity line is complete.

## Tab Type Switching Interaction

When QuickPanel is open, the search field remains the primary focus target.

Pressing `Tab` cycles to the next content filter:

```text
All -> Text -> Link -> Image -> File -> All
```

Pressing `Shift+Tab` cycles backward:

```text
All -> File -> Image -> Link -> Text -> All
```

The active query is preserved. The active filter changes immediately and the list refreshes using the existing `QuickPanelState.updateContentFilter` path. After refresh:

- If the previous selected record is still present, preserve it.
- If it is no longer present, select the first visible record.
- If no record matches, show the existing empty state and footer text.

The search field should remain focused after cycling so the user can continue typing. This makes the interaction feel like a command palette rather than a form with focus traversal.

The key capture layer must not intercept Tab while the first responder has marked text input, so Chinese input method composition is not broken.

## Architecture

The change should pass through three existing units only:

- `QuickPanelKeyCaptureView`: add a keyboard action for content-filter cycling.
- `QuickPanelState`: add a state method that computes the next `QuickPanelContentFilter` and delegates to `updateContentFilter`.
- `QuickPanelView`: wire the key action to state and restore search focus.

No storage, pasteboard, import, or panel-position logic should change for this enhancement.

## Data Flow

```text
Tab or Shift+Tab keyDown
-> QuickPanelKeyCaptureView.keyboardAction
-> .cycleContentFilter(delta)
-> QuickPanelView keyCapture callback
-> QuickPanelState.cycleContentFilter(delta)
-> QuickPanelState.updateContentFilter(nextFilter)
-> scheduleRefresh()
-> QuickPanelViewModel.refresh(query, contentTypes)
-> list and footer update
-> focusSearch()
```

## Keyboard Mapping Rules

- Plain `Tab` maps to `.cycleContentFilter(1)`.
- `Shift+Tab` maps to `.cycleContentFilter(-1)`.
- `Command+Tab`, `Option+Tab`, `Control+Tab`, and combinations other than plain or shift-only should not be captured.
- Existing QuickPanel keyboard mappings keep their current behavior.

## Error Handling

Cycling filters is a non-destructive UI state change. If the refresh fails, the existing QuickPanel refresh behavior applies. The feature should not introduce alerts or new failure states.

If the current filter list is empty or contains only one value in the future, cycling should become a no-op instead of crashing. With the current five-case filter enum, cycling always has a next value.

## Tests

Add or extend automated tests for:

- Plain `Tab` maps to forward filter cycling.
- `Shift+Tab` maps to reverse filter cycling.
- Modified Tab combinations are not captured.
- `QuickPanelContentFilter` cycles forward with wraparound.
- `QuickPanelContentFilter` cycles backward with wraparound.
- Cycling preserves the current search query.
- Cycling triggers the same refresh behavior as selecting a filter from the segmented picker.
- If the selected record disappears after filtering, selection falls back to the first visible record.
- Existing key mappings still pass.

## Manual Acceptance

Add manual checklist items:

- Open QuickPanel and press `Tab`; type changes from `All` to `Text`.
- Press `Tab` repeatedly; type cycles through all filters and returns to `All`.
- Press `Shift+Tab`; type cycles backward.
- Type a query, press `Tab`, and confirm the query remains while results are filtered by both query and type.
- While using a Chinese input method with active composition, Tab does not break composition.
- QuickPanel layout stays stable after cycling filters.

## Completion Criteria

This parity slice is complete when:

1. The design is accepted.
2. The implementation plan is written from this design.
3. The Tab cycling enhancement is implemented with targeted tests.
4. `swift test --filter QuickPanel` passes.
5. `Scripts/verify.sh` passes.
6. A stable signed app bundle is produced using the repo's stable signing flow, not ad-hoc signing.
7. Manual acceptance confirms Tab and `Shift+Tab` filter cycling in the running app.

## Risks

- Tab is traditionally a focus traversal key. In QuickPanel, the command-palette interaction is more important, but this should remain local to the panel.
- Search text input and IME composition can conflict with shortcut interception. The existing marked-text guard must remain active.
- The footer already carries several hints. Any new hint must stay compact or be omitted if it causes crowding.
