# 2026-10-24 — A dropped terminal is listed once in Active

## Objective and authorization
The owner, on the iPhone, with a picture of Active under his Mac: "eventually the phone detaches from tmux
session, and so leaves two entries for the previously open connection … Thoughts on how to address this? It's
purely UX". The proposal (one row per session; the dropped tab's row says what the machine said; choosing it
reconnects; an ended session says so) and the swipe ("and the swipe to detach? … it just removes the detached
line item and shows the one below?" — yes, at once, the word kept as Detach) were answered "yes!".

## Cause
`runningReport` left out a host's tmux session only when a terminal here showing it was not `.disconnected`
(`TerminalRunningSessions.swift`, since D44 `8bf37933`). A tab iOS dropped stays, "Disconnected · in tmux
(Terminal 1)", and its session came back below it, named as the Mac's tab names it, "Open elsewhere" (the Mac's
own tab). Open there made a second tab on the same session. On his Mac all 28 `glass-N` sessions were running,
one client each (read-only `tmux list-sessions`), so every dropped tab was a duplicate.

## Changes (not committed)
- `GlassShell/GlassOpenSession.swift`: `GlassRunningSession.isHeldHere` (closure, default false), asked as Active
  draws.
- `GlassShell/GlassActiveConnections.swift`: `listedRunningSessions` (running less held); `activeMachines` uses it,
  so the count and the rows drop a held session and bring it back the moment the tab closes.
- `App/GlassPowerToolsApp.swift`: the + menu's running terminals are `listedRunningSessions` too.
- `GlassTerminal/Models.swift`: `TerminalSession.isDown` (disconnected or error; `connectsOnShow` uses it),
  `tmuxWhileDown: TerminalTmuxWhileDown?`, cleared when the terminal connects.
- `GlassTerminal/TerminalRunningSessions.swift`: `TerminalTmuxWhileDown { running(Session), ended }`; the report
  records it on each down terminal of a listed host and lists its session with `isHeldHere` (a terminal on that
  server holding the name); live terminals still leave their session out as before.
- `GlassTerminal/GlassTerminalCapability.swift`: `subtitle(for:)` for one down terminal: "Disconnected · <the
  session row's details>" or "Disconnected · its tmux session has ended"; `Request.reconnect(sessionID:)`;
  `reconnectIfDropped` on the workgroup row, a tab's card and a lone session (tmux, `connectsOnShow`, not an iPhone
  slot, which connects as shown).
- `GlassTerminal/TerminalConnectFlow.swift`: handles `.reconnect` with `SessionManager.reconnect`; a failure goes to
  the connect flow's alert.
- Docs: RELEASE-NOTES bullet; `site/help/terminal-tmux.md` (drops, and Active's paragraph).

## Validation
- New: `TerminalActiveListingTests` — a dropped tab stands for its session; an ended one says so and a reconnecting
  one is listed as before; choosing reconnects only a dropped tmux tab. `GlassActiveConnectionsTests` — a held
  session is not listed until released.
- Results: pending.

## Remaining
- Not tried on the phone yet.
