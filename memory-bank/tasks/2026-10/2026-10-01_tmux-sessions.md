# tmux sessions and Active across devices (D44)

- **Authorization:** owner, 2026-10-01 ("Let's knock out that amazing tmux vision!"). Commit only when asked.
- **Choices (agent's recommendations, owner said go):** names `glass-N`, title shown in Glass; Active
  lists every tmux session on the host, Glass's marked; tmux + Active first, synced sets later.

## Findings (code map)
- A terminal always opens a PTY + `shell`; a workgroup startup command is *typed* once
  (`TerminalSession.dispatchStartupCommandIfNeeded`, Models.swift) and never again on reconnect.
- `SSHConnection.executeRemoteCommand` opens an exec channel on the live transport (no PTY).
- `ServerConfiguration` is synthesized Codable: a new optional field decodes absent as nil.
- Active is built from `openSessions()` only; no per-machine hook existed.

## Design
1. `TerminalTmux` (new): commands and parsing, all through `sh -c` so fish/zsh/bash agree.
   List: `tmux list-sessions -F …` or a marker when tmux is missing. Attach (typed, leading space
   keeps it out of history): `command -v tmux >/dev/null && exec tmux new-session -A [-D] -s '<name>'`
   — `-A` attaches or creates, `-D` takes over, `exec` makes a detach end the terminal cleanly.
2. `TerminalSession`: on every transition to connected, a tmux terminal (server setting, or a name
   given by Active) picks a name the first time (lists, first free `glass-N`, names reserved in this
   process) and types the attach line; a reconnect re-attaches the same name. Missing tmux → plain
   shell and a notice. The startup command (workgroups) runs once, after the attach.
3. `ServerConfiguration.tmux: Bool?`; toggle under Advanced in the terminal service form.
4. Shell: `GlassRunningSession` + `GlassCapability.runningSessions()` (default empty); Active merges
   them under each machine. Terminal lists tmux-enabled servers over a live connection or a silent
   short-lived one (no prompts; a server needing a password typed is skipped).
5. Tests: pure command/parse tests, session tests with a fake runner, live test on scratch.

## Built (2026-10-01, uncommitted)
- `Sources/GlassTerminal/TerminalTmux.swift` — commands, parsing, naming, quoting; `TerminalTmuxAttachment`.
- `Models.swift` — `ServerConfiguration.tmux`; `TerminalSession` tmux attach on every connect,
  `Purpose.probe`; `SessionManager`/`TerminalConnectFlow`/`Request.connect` carry an attachment;
  probes never stamp "last connected".
- `ServerFormViews.swift` — Advanced toggle "Keep Sessions Running with tmux".
- `TerminalRunningSessions.swift` — `runningSessions()`: live terminal or silent probe per server.
- Shell: `GlassRunningSession`, `GlassCapability.runningSessions()` (requirement), model
  `runningSessions`/`refreshRunningSessions()`, Active rows (open, Take Over, End with confirm,
  Check Machines, pull to refresh).
- Help: `site/help/terminal-tmux.md`, registry, Active paragraph in `library-connect.md`.

## Validation
- Unit: `TerminalTmuxTests` (9), `GlassActiveConnectionsTests` (+1); terminal 415 and shell 201 pass.
- Live (scratch): `LiveTmuxTests` passed both paths — without tmux the typed attach line leaves a
  working shell; with tmux 3.6 (installed via the passwordless `apt-get` sudo rule) it creates,
  leaves (detached), reattaches (no duplicate) and ends a session, leaving nothing behind.
- Builds: macOS, visionOS, iOS Release 0.4.269 succeed. Not yet run on a device.

## Availability check and the offer (owner, 2026-10-01: "verify that tmux is available and disable
that option if it's not. If it is, notify the user when they're first connecting to it")
- Every terminal connect checks the host (the list command over exec; nothing typed) and records
  `ServerConfiguration.tmuxAvailable`; the form's switch is enabled only when it is true (always
  free to turn off), with a footnote for never-checked / missing / available.
- The first connect that finds tmux where the setting is off and `tmuxOffered` is unset asks in the
  terminal window (`TerminalWindowView` alert): Turn On / Not Now; the answer syncs, so once only.
  Turn On applies from the next terminal — nothing is typed into the live one.
- Found while testing it: server metadata writes (last connected, favorite, now tmux) each copied
  the list, awaited the save and set it, so two in flight overwrote each other. They now run one at
  a time from current state (`ServerManager.updateMetadata`); `TerminalTmuxOfferTests` failed before.

## Closing (owner, 2026-10-02: "Does this need to change now that we've added tmux?")
- One rule, `TerminalSession.closeStopsWork` (connected/connecting and not `survivesClose`), now
  drives all four questions: Mac window close (`closeConfirmationMessage`, wording names tmux when
  the window has some), Mac pane close, Quit, and Disconnect in the terminal. Local shells and
  panes still opening still ask.
- The offer test's fixed sleep flaked under load; `noteTmuxAvailability` returns its save task.

## Words (owner on iPhone, 2026-10-02: Active showed a tmux terminal with "Close" — "It should
recognise the connection type and present the correct action words, even if they do the same
technical thing")
- `GlassOpenSession.closeTitle`/`closeSymbolName` (default Close/xmark). Terminal rows say
  "in tmux (Terminal N)" and Detach/eject when every terminal in the row is in tmux; mixed rows
  stay Close. The tools menu says Detach instead of Disconnect. After a detach Active re-asks the
  machines (after 1 s, once the client has left) so the session appears as Detached.
- First real-device use: iPhone, over Tailscale, worked.

## Known limits / next
- An Active attachment survives the password, legacy-algorithm and trust prompts
  (`pendingTmuxAttachment`; the trust path reconnects the same session).
- Mac window restoration does not remember a pane's tmux name yet (a relaunch makes new sessions).
- Stage 2 (synced "open the same set here", databases included) not started.
