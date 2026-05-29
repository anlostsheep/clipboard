# QuickPanel Pinned/History Shortcut Separation Design

## Goal

Make QuickPanel easier to operate when pinned items exist, without removing the existing pinned/history section structure.

The current panel correctly keeps pinned items visible above normal history, but that also means pinned rows take the initial selection and consume the existing `Command+1...9` row shortcuts. The new behavior keeps pinned items visually prominent while making normal history the default keyboard target.

## Current Code Facts

- `QuickPanelViewModel.refresh` sorts pinned records before unpinned records.
- `QuickPanelListPolicy.limitedItems` preserves some unpinned history when pinned items exceed the page limit.
- `QuickPanelItemSection.make` splits the already sorted `items` array into `.pinned` and `.history` sections while preserving each row's global item index.
- `QuickPanelState.prepareForPresentation` and `QuickPanelState.applyRefresh` own the open-time selected index behavior.
- `QuickPanelKeyCaptureView` maps `Command+1...9` to visible-row selection and `Control+Command+1...9` to visible-row paste.
- `QuickPanelView.numberShortcut(for:)` currently displays number badges by global row index, so pinned rows can take the first number badges.

## Chosen Direction

Keep two visual sections:

1. Pinned section remains above History.
2. History section remains below Pinned.
3. Opening the panel prefers selecting the first History row.
4. Pinned and History use separate keyboard spaces.

This avoids a larger layout rewrite while fixing the main interaction problem: pinned rows should be visible and reachable, but they should not displace the high-frequency recent-history keyboard flow.

## Interaction Rules

### Open Selection

When QuickPanel opens:

- If at least one unpinned History item is visible, select the first visible History row.
- If no History item is visible and pinned items exist, select the first pinned row.
- If the user setting is "previous selection", keep the previous-selection behavior when the previous selected record is still visible.
- If the previous selected record is no longer visible, fall back to the same History-first rule above.

This means "latest record" becomes "latest normal history when normal history exists" for the mixed pinned/history case. Pinned-only lists still work naturally.

### History Shortcuts

History rows use numeric shortcuts only:

- `Command+1...9` selects the first through ninth visible History rows.
- `Control+Command+1...9` pastes the first through ninth visible History rows.
- Numeric shortcuts do not select or paste pinned rows.
- The design intentionally does not add `Command+0` for the tenth History row in this iteration.

The visible shortcut badges in History should show `1...9` based on History-local row order, not global list order.

### Pinned Shortcuts

Pinned rows use letter shortcuts:

- `Command+A`
- `Command+S`
- `Command+D`
- `Command+F`
- `Command+G`
- `Command+H`
- `Command+J`
- `Command+K`
- `Command+L`

The mapping is automatic by pinned row order. The first visible pinned row gets `A`, the second gets `S`, and so on.

If there are more visible pinned rows than available letters, the extra pinned rows remain selectable by mouse and arrow navigation but do not receive a letter shortcut in this iteration.

Pinned rows should show a compact `⌘A`-style badge where the numeric badge currently appears. If a pinned row has no assigned shortcut, it can keep the existing pin icon.

### Search And Filtering

Shortcut assignment follows the current visible filtered sections:

- Searching or changing type filter recomputes visible Pinned and History sections.
- History numbers apply to the filtered History section.
- Pinned letters apply to the filtered Pinned section.
- A shortcut for a missing local index does nothing.

This keeps behavior consistent with the current filtered visible-row shortcut model, but splits the index space by section.

## Non-Goals

- Do not redesign QuickPanel into a single unified list.
- Do not introduce custom per-pinned-item shortcut assignment yet.
- Do not add `Command+0` for the tenth History item yet.
- Do not add pinned direct-paste letter shortcuts yet.
- Do not change persistence schema for pinned records.
- Do not change global QuickPanel open hotkey behavior.
- Do not change Return, double-click, copy-only mode, or plain-text paste semantics.

## Implementation Shape

### Section-Local Shortcut Mapping

Introduce a small section-local mapping layer near QuickPanel presentation/state code:

- History local index `0...8` maps to numbers `1...9`.
- Pinned local index `0...8` maps to letters `A/S/D/F/G/H/J/K/L`.

This mapping should be deterministic and testable without depending on SwiftUI rendering.

### Keyboard Capture

Extend `QuickPanelKeyCaptureView.KeyboardAction` with pinned letter selection actions, for example:

- `selectPinnedShortcut(Int)`

For this iteration, keep the modifier model aligned with existing shortcuts:

- `Command+letter` selects the pinned item.
- Do not add `Control+Command+letter` pinned direct paste yet. The existing `Control+Command+1...9` direct paste remains History-only.

### State Semantics

`QuickPanelState` should resolve shortcuts by section-local order rather than global row order:

- `selectHistoryShortcut(number:)`
- `pasteHistoryShortcut(number:)`
- `selectPinnedShortcut(slot:)`

These methods should refresh before user actions using the existing stale-query guard pattern where necessary.

### View Rendering

`QuickPanelView` should pass section-local shortcut metadata into row rendering instead of deriving numeric badges from global `row.index`.

Rows should remain compact. App icon and source app name can stay as-is for this iteration unless verification shows the panel cannot display enough History rows after shortcut separation. The first implementation should avoid combining row-density changes with shortcut behavior changes.

## Testing

Focused tests should cover:

- Mixed pinned/history list opens with the first History row selected under latest-record behavior.
- Pinned-only list still opens with the first pinned row selected.
- Previous-selection behavior keeps a visible previous selection.
- Previous-selection fallback uses History-first when the previous record is gone.
- `Command+1...9` maps only to History local order.
- `Control+Command+1...9` pastes only History local order.
- `Command+A/S/D...` maps to Pinned local order.
- Search/type filtering recomputes section-local shortcut assignments.
- Out-of-range number or letter shortcuts do nothing and do not crash.
- Existing QuickPanel keyboard tests for Return, Escape, Tab, destructive shortcuts, plain-text paste, and detail preview still pass.

Recommended verification command:

```bash
swift test --filter QuickPanel
```

If implementation touches keyboard capture broadly, also run:

```bash
swift test --filter QuickPanelKeyCaptureTests
```

## Manual Acceptance

Add or update a dated entry in `docs/manual-acceptance-checklist.md` after a signed or locally runnable build is verified:

- With both pinned and normal history visible, opening QuickPanel selects the first normal History row.
- `Command+1...9` selects normal History rows only.
- `Control+Command+1...9` pastes normal History rows only.
- `Command+A/S/D...` selects pinned rows in visible order.
- Searching or type filtering preserves the same section-local shortcut behavior.
- Existing Return, double-click, copy-only mode, and plain-text paste behavior still work.

## Risks

- `Command+H` is a common macOS hide shortcut. Because QuickPanel captures local events only while focused, this is acceptable for the initial left-hand mapping, but implementation should verify it does not hide the app unexpectedly.
- Letter shortcuts may conflict with text input expectations. They must only fire with exact `Command` modifiers and only inside QuickPanel.
- Changing default selection can surprise users who intentionally use pinned items as the first target. The fallback keeps pinned-only behavior, and the existing previous-selection preference gives users a way to keep a pinned item selected across opens.
- Row-density concerns are real but should be handled as a separate iteration after shortcut semantics are stable.
