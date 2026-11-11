# A terminal without its connection says so in the window (2026-11-10)

## Task
- **Asked (the owner, 2026-11-10, with a screenshot of an SSH tab on the Mac):** "a disconnected terminal shows a red
  text under the name in the tab, but the window itself still shows what looks like a connected window. Let's reflect
  the status in the window's content itself. Dim the window, add a close or reconnect UI to the center of the window."
- **Scope and authorization:** local implementation, tests and documentation (his request). Commit, push, release:
  not asked.
- **State:** BUILD → QA.

## What was there
- The session's state (`SessionState` in `Sources/GlassTerminal/Models.swift`) reached the tab's red subtitle
  (`MacWorkspaceController.connectionSubtitle`: "— Connection failed"), a notice that fades, and the Tools menu's
  Reconnect / Close Terminal (`TerminalWindowView.bottomStatusBarContents`). The terminal view itself never read it:
  a dropped terminal looked live.
- The database's window (`DatabaseWorkspaceView.connectionRecoveryOverlay`: a dimmed workspace, a card with
  Reconnect) and the remote desktop's (`DesktopSessionView.connectionStatus`: the system's unavailable view with
  Reconnect and Close) already said so for theirs. The terminal follows them.
- On the Mac, the Tools menu's **Close Terminal** on a terminal without a connection went through
  `closeTerminalSession`, which is Disconnect's path: the Mac's `disconnectSSHPane` keeps the pane and shows
  "Connection Failed — The SSH session ended. Reconnect to continue." It didn't close.

## What changed
- `Sources/GlassTerminal/TerminalConnectionNotice.swift` (new): `TerminalConnectionNotice.make` decides what is said
  from the state and the session's history; `TerminalConnectionNoticePanel` is the panel.
  - Live, or not yet connected the first time (an iPhone's tab that connects when shown; a first connection, shown
    where it always was): nothing.
  - Dropped after connecting: **Connection Lost** and the reason (the transport's words, e.g. "The connection stopped
    answering — the device slept, or the network changed"); auto-reconnect off or cancelled: "The connection to
    <machine> ended."; a first connection that failed: **Couldn't Connect** and why. **Reconnect** and **Close
    Terminal**.
  - Auto-reconnect at work: a spinner, **Reconnecting…**, "Attempt 2 of 5 to reach <machine>.", **Cancel Reconnect**
    and Close Terminal. A Reconnect chosen: the spinner until it's back or fails.
  - An `exit` on a connection that stood: nothing (its window closes it).
- `TerminalWindowView`: the terminal's text and its look's backdrop at 35% under the panel, readable and still
  scrollable and selectable; the window's glass and colour untouched ("glass is the point"). The panel is outside the
  tap that focuses the terminal. Regular material on the Mac, iPhone and iPad; the system's glass on Vision Pro.
- `TerminalSession`: `hasConnected`, `hasFailedToConnect`, `isAutoReconnecting`, `autoReconnectAttempts` (the 5
  that was a literal in the task and its messages); `userInitiatedDisconnect` readable.
- Close Terminal (the panel's and the Tools menu's) goes the way a terminal whose shell ended goes
  (`closeTerminalWithoutConnection` → `onSessionEndedCleanly`): on the Mac its pane, and the tab with its last;
  elsewhere its tab, as before.
- Demo (DEBUG, `--ui-testing`): `--demo-connection-lost <seconds>` drops the demo window's first terminal with the
  transport's words; its Reconnect comes back connected after 1.5 s (`TerminalSession.demoReconnect`), as a demo has
  no server.

## Validation
- **Unit:** `TerminalConnectionNoticeTests` 8 of 8 on the Mac; with the session's `hasConnected` not set and the
  failed-first-connection case dropped, 4 failed. The whole Mac `GlassTerminalTests`: 1,257 passing.
- **UI:** `TerminalConnectionLostUITests` 2 of 2 on the Vision Pro (visionOS 27.2) and iPhone 17 Pro Max (iOS 27.2)
  simulators: no panel while connected; once the demo's connection drops, the panel with Connection Lost, the
  transport's words, Reconnect and Close Terminal; Reconnect takes it away; Close Terminal closes that terminal
  only (Vision Pro: the sidebar goes with one terminal left, and bravo stays). With the panel taken out, both
  failed on iPhone ("no Reconnect over the terminal once its connection dropped").
  - Two test mistakes found and fixed on the way: it waited for a **Tools** button Vision Pro doesn't have (the
    demo's drop came first), and expected one sidebar row where the sidebar goes.
  - Found in the pictures and fixed: on iPhone the reason line was not drawn (a selectable `Text` is UIKit's there,
    and drew nothing under the fade-in); it is plain text now.
- **Mac (macOS VM, Debug build, the same demo):** the panel over the dimmed text; the terminal text's brightest
  pixels 230 → 86 → 230 after Reconnect; Close Terminal closed alpha's tab and left bravo, with no "Connection
  Failed" pane behind. Found and fixed: the system's light material over the dark terminal came out mid grey and
  the reason was nearly unreadable; the panel takes the terminal theme's light or dark now (Mac and iPhone).
- **Not checked:** a real dropped connection (the demo drops with the transport's own words; the state path is the
  one `SSHConnection.connectionLost` takes); auto-reconnect's progress on screen (unit tested only); that the Mac's
  old Close Terminal left the pane (read from `disconnectSSHPane`, not seen).

## Next
- 0.4.613 on the Mac, iPhone and headset; then his other requests.

## Shipped (2026-11-11)
- Committed (`0e348599`) and pushed; released in 0.4.616: the Mac's ninth release (GitHub v0.4.616, notarized,
  downloads byte-identical to the build, feed entry), TestFlight 616 for iOS and visionOS in beta review; the headset not yet installed.
