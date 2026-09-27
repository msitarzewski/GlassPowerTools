# The database grid's scroll cost — measured, 2026-09-23

The user asked whether we should study other editors that claim real-time rendering, expecting the
same cost to surface in the database and terminal too, and then, stepping away, asked for a look
around. Investigation only; the grid is unchanged.

## Terminal — already on the state-of-the-art path

SwiftTerm's Metal renderer (a GPU glyph atlas, `Apple/Metal/MetalTerminalRenderer.swift` in the
dependency) is the default on the Mac and iPhone (`SwiftTermRendererPreference.platformDefault`,
`SwiftTermHostView.swift:20-33`). Vision Pro stays on CoreGraphics on purpose until Metal
presentation is validated there. Not measured today.

## Database grid — measured on the real view

`GridScrollTimingTests` (gated by `GPT_GRID_TIMING`; `GPT_GRID_PAGE`, `GPT_GRID_STEPS`): the real
`TableDetailView`, the real `DatabaseSessionManager`, a real SQLite file of 10,000 rows × 20 columns
created in the app's managed SQLite folder and deleted afterwards; release build; frames include one
run-loop turn. Document height checked (30 pt a row) and scroll position checked, per rule 59.

| Page | Load | 120 frames of 40 pt: median / p95 / max | Over 16.7 ms |
|---|---|---|---|
| 100 rows | 0.21 s | 5.8 / 9.7 / 10.9 ms | 0 |
| 1,000 rows | 0.24 s | 8.4 / 10.6 / 11.0 ms | 0 |
| 10,000 rows | 0.59 s | 8.4 / 10.5 / 11.0 ms | 0 |
| 1,000 rows, 1,500 frames (the whole page) | 0.29 s | 3.5 / 19.3 / **358 ms** | **161** |

At 60 Hz the short scroll is fine; the user's Mac is 120 Hz (8.3 ms budget), where the median alone
misses half the frames. Scrolling through the whole page stutters whenever SwiftUI builds rows it has
not shown yet. Sampled: `LazySubviewPlacements.placeSubviews` → per-**cell** view construction:
`TapGestureModifier` (two per cell: single and double tap) the largest share, then
`AccessibilityViewModifier`, `VisualEffectModifier` (every cell carries the frozen-column offset
effect, frozen or not), then text resolution. 20 cells × ~4 modifiers per row.

Also seen in the code, not yet measured: the row-number cell of every row (and every filler row)
has an `.ultraThinMaterial` background — a live blur per row (`databaseCanvasPinnedSurface`,
`Constants.swift:276`); `displayedRowIndices` re-filters and re-sorts all rows on every body
evaluation, including a selection click.

## Options (proposed, none approved)

1. **Cheap, in SwiftUI:** gestures at the row, the column found from the tap's x; the visual effect
   only on frozen cells; one material behind the row-number column instead of one per row; the
   displayed-row indices cached until the data, filters or sorts change. Likely halves row
   construction; measure with the same harness.
2. **The state of the art for a Mac data grid:** a view-based `NSTableView` (cell reuse — a
   screen's worth of views, never 20 per row), which is what native database tools use. A
   substantial change to the most feature-dense view in the app (selection rectangles, frozen
   columns, inline edit, context menus, accessibility); iOS and visionOS would keep SwiftUI.

## Option 1, partly built — 2026-09-25

In the tree (uncommitted), shipped in 0.4.218 onward: the displayed-row indices memoized
(`GridDisplayedRowsMemo`, keyed on result id, row count, filters, sorts, dialect, context; tests
prove every key part invalidates); the scroll-driven offset only on frozen cells (`gridFrozen`); one
tap gesture per cell on the Mac, the click count choosing select or open (`gridTap`; touch keeps two).
Not done: one material behind the row-number column.

**Observed by the user** on 0.4.223, the real `shop` database on the Linux server: 10,000 rows rendered
effortlessly, and the user was pleased. Not yet re-measured with `GridScrollTimingTests` (needs the Mac to itself);
the 8.3 ms-per-frame target is unverified by numbers.
