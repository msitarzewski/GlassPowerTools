# 2026-10-14 (late): All Windows as the Mac lays it out; the headset's window; two headset fixes

**Owner:** the coordinating agent. **Authorization:** the owner's standing "go with your recommendations, commit each
piece as it lands"; installs on the Mac, iPhone and Vision Pro with every build. Nothing pushed.

## What the owner asked (on the headset, 0.4.444)

- Live previews on the cards: "Agree on iPhone, but let's fix the other platforms."
- "In the session cards view, please mirror the Mac layout. Grouped by machine, but show each tab as a card. The view
  should adjust itself based on the number of sessions showing."
- "Right now it's a modal, will that work for larger workloads?" (the Vision Pro sheet)
- "I'd also like to revisit the width of the connections window, it should be wider by default."
- "The Editor window's bottom corners show a square background." (a headset screenshot)

## What changed

| Commit | Change |
|---|---|
| ca3f897 | Connections on Vision Pro opens at 1180 × 700, the Mac's width (was W29's 960). An open window keeps its size. |
| 7538a54 | The editor's window contents are clipped to the 46-point glass corner on the headset; the status bar's square `.bar` had filled the bottom corners. |
| 321a625 | `MacTerminalExposeLayout` moved unchanged to GlassShell as `GlassAllWindowsLayout`; the Mac keeps the old name as a typealias. |
| b5df704 | `GlassOpenSession.tabs`; a terminal workgroup lists each live terminal as a tab card (named as its tab, on its own server's machine; choosing selects the tab and shows the window; closing closes the tab). `GlassShellModel.allWindowsMachines()` groups them; Active still shows one row per window. |
| 3b0b6e5 | The cards view (`GlassShowAllWindowsOverview`) packs groups and cards with the Mac's layout, shows each card's name and state over its picture, and retakes each picture once a second (`TimelineView(.animation(minimumInterval: 1, paused:))`) while it's on screen and the scene is active. `--demo-open all-windows` (DEBUG). |
| 1558bd6 | Vision Pro: All Windows is a `Window` scene of its own (`GlassShowAllWindows.windowID`, 1280 × 800, `.restorationBehavior(.disabled)`) inside every capability's bootstrap, so a chosen card's request is carried out with no Connections window open. It leaves 300 ms after the choice. The sheet on Connections is gone. |

**Reuse:** the Mac's layout solver (moved, not rewritten); the terminal's existing `selectSession(_:inWorkgroup:)`,
`closeSession(_:inWorkgroup:)`, `TerminalWorkgroupOpening.label` (new `.allWindows` surface) and preview; the Mac
tile's caption shape; the bootstraps Connections already composes.

## Validation

- Unit: the Mac's 14 layout tests pass against the moved type; two new tests (the terminal's tabs; the shell's
  grouping) each fail without their half; shell suite 297 pass; terminal listing/names tests pass; tmux md5 unchanged.
- iPhone: `GlassAllWindowsPaneUITests` (5) pass on the iOS 27.2 simulator; the demo shows three tab cards under their
  machine and the editor under the device; only a terminal that has been on screen has a picture there (as agreed).
- Vision Pro simulator (27.2): the demo editor's status bar ends in the window's rounded corner and its toolbar
  ornament is whole; the All Windows window opens with three live tab cards.
- The editor's bottom-left corner, under the Files sidebar's bar, is rounded too (demo project).
- 0.4.445 installed on the Mac, iPhone and Vision Pro (23:59); each reads 0.4.445; no new crash reports.
- Not shown by the demo: a desktop's card (the demo desktop is built outside the desktop list). Real desktops are
  listed, as on the Mac.

## For the owner to check on the headset

The ⚡ held (or Siri) opens the window; resize it and the cards grow; choose a tab's card and that window comes back on
that tab; the cards' pictures move. Connections is wider only when opened new (close it and open it again). The
editor's bottom corners.

## Remaining

Other headset windows draw square `.bar` backgrounds at their bottom (Files' bar, `SFTPBrowserView`) and may show the
same corners; not looked at yet.
