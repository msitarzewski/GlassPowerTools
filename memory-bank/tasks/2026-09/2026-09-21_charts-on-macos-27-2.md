# The overview's bar charts on macOS 27.2 — 2026-09-21

**Reported:** *"The database names here and the bar chart overlap for some reason."* Screenshot
of the connection overview's *Largest by Rows* and *Storage Distribution* cards: each name drawn
inside the plot at the top of its band, each bar at the bottom of its band, so every name sat on
the bar below it.

**The reason was the OS.** The chart code (`DatabaseDetailView.swift`) had not changed since
Stage 3. The Mac had moved from macOS 27.0 to **27.2 beta (26B5091g)** during the day, and Swift
Charts there draws a categorical y-axis differently: labels default to *inside* the plot, and
under every outside preset (`.aligned`, `.extended`) the label is anchored at the **top edge** of
its band with `AxisValueLabel(centered:)` ignored. The bar is where it always was; the label is
not.

**How it was found without an install per attempt.** A throwaway macOS binary rendering the same
`Chart` through `ImageRenderer` to a PNG — `Tools/ChartProbe/main.swift`, kept in the repo — reproduced the
defect on the first run and let five variants be compared in minutes. Worth keeping as a pattern:
Swift Charts layout can be measured headless on this machine.

**The fix.** Stop asking the axis to place the names. Each `BarMark` carries its name as an
`.annotation(position: .leading, alignment: .trailing)`, which is positioned by the mark itself
and cannot drift from it; the y-axis is hidden and the chart is padded on the leading side by the
label width so the card does not clip the names. One helper pair — `overviewBarName(_:)` and
`overviewBarChartAxes()` — shared by all four charts (databases and tables, rows and bytes). Long
names truncate in the middle at 150pt, so `cv_3263493d-…70f01223b2ec` no longer sets the axis
width for everyone.

| Claim | Evidence |
|---|---|
| The defect reproduces headless on 27.2 with the old code | `chart-default.png` from the probe |
| Names sit centred on their bars with the fix | `chart-annotation.png` from the probe |
| The four charts share one helper | `DatabaseDetailView.swift`, `OverviewBarChart` |
| Database suite | 276 tests, exit 0 |
| Seen in the running app | pending 0.4.193 |

## Follow-up: the rows axis — *"let's make sure exponents are useful"*

Seen in 0.4.193: the rows charts' x-axis read `5.0E6 · 1.0E7` — the default label for a large
integer axis is scientific notation. Now `.number.notation(.compactName)`: `0 · 5M · 10M`,
rendered in the probe before install. Both axis blocks moved into helpers beside the name
helper — `overviewRowsAxis()` and `overviewBytesAxis()` — so the four charts share three
functions and no chart carries its own axis code any more.
