# Vision Pro: a window's terminals come back when it is shown (2026-11-01)

- **Owner and report:** "I'm still concerned about the dock, active connections, and reliability. I'd named a window
  [name], but both connections show 'disconnected' and didn't reconnect when I opened it." The same shape as his
  2026-10-31 report ("two disconnected terminals in a window with no way to close them"), when Close Tab was added
  but the cause was not looked for.
- **Authorization:** a defect report on his device; local fix, tests, builds and installs are within the standing
  authorization. Commit, push and TestFlight wait on his word.

## Evidence
- The headset's diagnostics file (copied with `devicectl`): the app was active until 22:13 UTC, suspended until
  04:36 UTC, when he opened it. It recorded drawing and keyboard events only; nothing about connections.
- Crash and Jetsam reports: no crash; every Jetsam report that day lists the app as `suspended`, not killed (the
  same resident size from 16:40 to 19:27 local, one process).
- "Disconnected" is `SessionState.disconnected` exactly; a connection whose retries ran out reads "Error: …". So the
  tabs either never connected after a relaunch, or their shell ended in a way read as an exit (`handleCleanRemoteExit`).
- A race in that reading (a dying connection still reporting itself up) was tested and ruled out: the gated
  `SSHSharedConnectionLossTests` relay-cut test passed 40 of 40 runs against the test VM.

## Cause (from the code; an agent mapped it independently and agreed)
- On Vision Pro nothing connected a terminal that was down when its window was shown: `connectShownSlot` was
  iOS-only ("Vision Pro keeps every terminal connected"), and the only retry was the five tries after a live
  connection is lost. Not on opening, not out of the dock (a new scene), not grown from the orb, not on return.
- A relaunched window's terminals are slots (`isWorkgroupSlot`), connected once at launch; Active's
  `reconnectIfDropped` skipped every slot, which was meant for iPhone's lazily connected ones.
- A shell that ended while its window was in the dock (no `TerminalWindowView` alive) bumped `closeWindowNonce` with
  nothing watching: the tab stayed "Disconnected", never closed, never retried.
- A connect-on-show whose sign-in preparation threw left the tab "Disconnected" with nothing said.

## Fix (reuse: the existing connect-on-show and machine-by-machine connect)
- `TerminalWorkgroupOpening.connectDropped(inWorkgroup:)` shares `connectReopened`'s machine-by-machine connect
  (now `connect(_:)`), for every terminal that `connectsOnShow`.
- `VisionTerminalWorkgroupView.connectShownTerminals()` (was `connectShownSlot`): on Vision Pro, closes terminals whose
  shell ended while away, then connects the dropped ones; called on appear (opened, out of the dock), on a tab
  chosen, and by `VisionTerminalShownAgain` (grown back from the orb, the app back in front).
- `TerminalSession.shellEnded`: set by a clean end, cleared by `connect()`; `connectsOnShow` excludes it, so neither
  showing nor Active resurrects an ended tmux session.
- `reconnectIfDropped` skips slots only where they connect as shown (`slotsConnectWhenShown`, iOS).
- `SessionManager.connectWhenShown` signs in as Reconnect does (saved or transient, one `preparation(for:context:)`
  helper shared with `reconnect`) and says why in the terminal when it can't.
- Diagnostics (`noteConnection`): each state change and cause — lost and what auto-reconnect did, ended on a live
  connection, disconnected by hand, connect on show, the wake check — into the headset's file. States only.

## Validation
- `ShownTerminalsReconnectTests` (4) and `WorkgroupTmuxSessionsTests` (7) pass; each new test fails with its piece
  broken (connectDropped emptied; `!shellEnded` removed; the reset in `connect()` removed; the error report removed;
  the old slot rule), and each file was restored byte-identical (`cmp`).
- Not tested on a simulator or the headset by an agent: the window-shown triggers are SwiftUI (`onAppear`, the orb's
  `isWindow`, `scenePhase`); the owner's headset is the check. The `slotsConnectWhenShown` test runs on the Mac,
  where its value is the Vision Pro's.
- Help: `terminal-connect.md` ("When a connection drops"); release notes 0.4.576.

## Status
- 0.4.576 installed and read back on the Mac, iPhone and Vision Pro; no new Mac crash reports.
- Committed and pushed at his word (2026-11-02, "commit and push 0.4.576"). His check on the headset is next; TestFlight
  on his word.
