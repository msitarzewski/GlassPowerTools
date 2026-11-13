# The small defects: B-X11, B-X19, B-X20, B-X24 (2026-11-13, 0.4.618)

## Task
- **Asked (the owner):** "do the defects": the five offered from the backlog status
  (`2026-11-13_backlog-status.md`) as needing nothing from him. Not committed.
- **B-X7 left out**, and he was told why: whether Automatic should ask a Vision Pro for twice the pixels is judged
  by looking on the headset (the 2026-10-13 note: "needs the headset to measure and to judge"); and the
  whole-frame copy is by design (`FrameConverter.copy` in `GlassRDPSession.swift` makes one BGRA copy per frame, and
  `DesktopMetalRenderer` uploads the window's whole visible region per new frame), so changing it is a performance
  rework to measure on the headset, not a small fix.

## What changed
- **B-X11, a table tab's Query menu** (`Constants.swift`, `DatabaseWorkspaceView.swift`, `TableDetailView.swift`,
  `QueryEditorView.swift`). Format SQL, Query History and Saved Queries were off on a table tab, though its SQL pane
  runs queries (Execute already worked; the inventory overstated that part). `DatabaseQueryMenuAvailability` says
  what the menu can do for the tab in front: a table tab formats its pane (with SQL in it, connected or not) and
  fills it from History or Saved Queries (the SQL editor's own sheets, now shared); Explain stays a SQL document's.
  `SQLRunAvailability.hasText` carries "has SQL" up from the active pane.
  **Found on the way and fixed with it:** the menu's verbs were posted to the *session*, so a second workspace
  window on the same connection with a table tab in front ran Execute too. They now go to the window's own scope
  (`databaseQueryMenuScope`, an environment value the workspace sets).
- **B-X19, schema rows for assistive technology** (`SchemaBrowserView.swift`). A database or table row's click
  (its statistics) was a tap gesture: VoiceOver read it as text and could only open a tab (measured 2026-09-12).
  The rows are now one element with the button trait and the click as their default action.
- **B-X20, a database window with no workspace** (`GlassDatabaseScenes.swift`). `DatabaseWorkspaceNotFoundView`
  keeps a database window's size (at least 480 × 320, ideally its 1400 × 900 default); a bare
  `ContentUnavailableView` let the window be made a sliver. Glass of its own on Vision Pro, where the window is
  plain. Reached on the Mac from a database window's tab bar "+"; no caller in the app opens it without a value.
- **B-X24, Insert Path on the Mac** (`SFTPBrowserView.swift`, `MacTerminalOverview.swift`). The Files window stayed in
  front of the terminal it had typed into. Now `MacWorkspacePreviewRegistry.reveal(sessionID:)` brings the terminal's
  window forward on its tab, and now also focuses the pane the session is in (Active's Show uses it too).
- Help: `terminal-files.md` (Insert Path on Mac), `database-data-grid.md` (the Query menu on a table tab).
  `RELEASE-NOTES.md` 0.4.618.

## Validation
- New tests: `DatabaseQueryMenuTests` (4), `DatabaseWorkspaceNotFoundTests` (1), `MacRevealSessionTests` (1), all
  passing. **Each seen failing with its fix taken out** (one run, all four undone, then restored):
  the table rules as before (3 issues), the preference keeping only a pane that can run (1), the not-found frame
  removed (2: width and height), the pane focus removed (1).
- Database suite (macOS): 357 tests passed, 25 of them live tests skipped (no test database configured).
- Terminal suites: Mac 1,280 (1 new), iOS and visionOS simulators 869 each, all passed; the corrupt-file decode lines
  as in earlier runs.
- Built 0.4.618 (618) for the Mac, iOS and visionOS (Release, development signed).
- **In the macOS VM** (Debug build, the demo shop database on its orders table; `tmp/vm-check-618.zsh`): the Query menu
  read Run Statement, Format SQL, Query History and Saved Queries on, Explain Plan off; Format SQL changed the pane's
  text; Query History and Saved Queries opened their sheets (Done closed them); choosing the history entry put its SQL
  in the table pane. Every one of those went through the window's own scope, so it reaches the pane. The schema rows
  read `AXButton` with their names (`db-schema-database-main`, `db-schema-table-orders`, …), where 2026-09-12 measured
  `StaticText`.
- **Not exercised:** two windows on one connection (the scripted right-click to Open in New Window could not reach
  the row's menu in the VM); Insert Path's one-line call on a real Mac (the reveal it calls is tested); the not-found
  window opened for real.
- **Installed:** the Mac 06:53, read back 0.4.618 (618), running, no crash reports; the headset and the iPhone 06:53,
  each read back 0.4.618 (618).

## Remaining
- Commit and release only at his word.
