# Your Library counts time in use (D87, 2026-10-20)

**His report:** "this show half truths! The number of connections is true... but I've had tmux sessions running for
days in a row now and that's not reflected in the data here." The overview counted one connection per library
Connect, however long the session stayed open.

**His answers:**
- What counts as "in use": **Activity**, meaning a minute with input or output.
- The chart opens on: **Time in use**, with connections a choice beside it.

**Authorization:** build it; commits on his word.

## Built (0.4.490)

**Counting** (`GlassShellModel.startUsageClock`, `countMinuteInUse`):
- Once a minute, each machine and kind of service whose sessions had activity since the last count gets one minute.
  - Activity before a sleep counts as one minute, not as the hours between.
  - Two sessions on one machine through one kind still count one minute.
- **Sources:**
  - `GlassOpenSession.lastActivity`, from each capability:
    - **Terminal:** `SwiftTermHostModel.lastActivityAt`, unpublished. Stamped by output (`noteOutputActivity`) and
      by input: each engine's `recordInput`, and `TerminalSession.writeInput` for the keyboard bar.
    - **Database:** `DatabaseSession.lastActivityAt`, `@ObservationIgnored`. Stamped by `executeQuery`, which table
      browsing uses too, and by a change of `workspaceFocus`, the table or tab shown.
    - **Desktop:** `DesktopSessionModel.lastActivityAt`. Stamped by every key, click, move, scroll or text through
      `DesktopInput.onActivity`, and by `sendInput`.
  - A window's tabs count each, for their own machine, and the window itself not again.
  - `GlassCapability.usageActivity()`, a new requirement with a default of none. The terminal answers with a Mac
    tab's local shells, which are not open sessions.
    - They are attributed to the Local Shell, which is This Mac's, or the linked machine's under D86.
    - This is where his tmux time is.
- **Storage:**
  - `GlassShellPreferences.usageMinutes` (day → "host|kind" → minutes), kept 90 days on the device.
  - Saved every 5 minutes, and when the app goes to the background or quits.
- **Sync:**
  - `GlassUsagePayload.Count.minutes` is optional, so builds before it read the counts. At most 1,440 minutes a day,
    and validated.
  - Sent under the id the library shows each machine by, so This Mac's own id never travels. Once linked, its
    minutes are the machine's.

**The overview** (`GlassLibraryOverview`):
- A **Time in Use | Connections** control, Time in Use first.
- The chart shows hours per day by kind.
- Most Used ranks machines by time ("41 h", "2.5 h", "45 min").
- The caption reads "N hours in use on M devices".
- Connections view: minute-only rows count for neither the connection figures nor the device count.

**Tests:**
- `GlassTimeInUseTests` (9):
  - once per machine and kind; idle sessions not counted;
  - since the last count, not twice;
  - tabs;
  - the local shell, This Mac's then the linked machine's;
  - another device gets it under the machine's id;
  - kept across a relaunch;
  - the overview's figures; time-only machines;
  - wording.
- `GlassUsageSyncTests` +2: minutes travel and are capped; an older payload reads; too many minutes is refused.
- `TerminalActivityTests` (1): output and typing through a real hosted terminal.
- `ActiveRowFocusTests` +1: database focus.
- `DesktopActivityTests` (1).
- **Each fix seen failing with it undone:** the since-last-count rule, the tab walk, the synced id, the local-shell
  source, the terminal's input stamp.
- **Suites:** shell 341, terminal 953, database 335, desktop 224, editor 172.

**Not done:**
- **Connects from every path** (restores, reconnects, the terminal's own connects) still don't count as connections.
  - Doing it needs telling a connect he made from a restore. The seams: `SessionManager.recordSuccessfulConnection`,
    local `onProcessReady`, `GlassDatabaseScenes.connect`, `recordFirstDesktopIfReady`.
  - It also needs the library report's double count removed.
  - Time in use is the part he reported.
- **Earlier minutes:** none exist before 0.4.490, so the chart fills from today.
