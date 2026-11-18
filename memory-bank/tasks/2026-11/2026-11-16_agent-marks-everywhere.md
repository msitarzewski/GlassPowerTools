# A terminal's agent wherever its icon shows; every row's bell beneath (2026-11-16, 0.4.621, D109)

## Task
- **His report, 0.4.620 on the iPhone** (the bell round trip from the Mac worked): "the glow is different on iOS
  (haven't checked vision). And the terminals don't reflect the coding agent like the tabs do. That should be a
  constant when a terminal icon is shown. Do we need to centralize that code?"
- **Asked, he chose:** every row's bell as a glow beneath, as the Mac's sidebar, at the Mac's strength on every device
  (Active's rows had turned the icon orange, which Claude Code's mark already is); the iPhone's name menu showing an
  agent's mark, else the dot. Not committed.

## Found
- The terminal side was one mark already (`TerminalTabMark`, `TerminalSessionMark`), and the shell had one seam to it
  (`GlassOpenSession.icon`), used only by the orb dock for a window's tabs. Active drew `symbolName` itself: windows
  gave no `icon`, running sessions had no field for one, and the listing couldn't tell most agents: tmux names Claude
  Code's installer's program for its version (`2.1.318`) and its title holds the task, so only the command line says
  it (seen on this Mac's sessions: Codex by name, every Claude Code by a version).
- The row glow was 0.42 on the Mac, 0.7 elsewhere.

## What changed
- `GlassSessionMarkPlacement` (`.alone(side:)`, `.row`): who shows the bell. `GlassOpenSession.icon` takes it;
  `GlassRunningSession.icon` is new. `GlassSessionRowIcon` draws a row's icon (the mark, else the symbol); Active's
  two rows use it and glow beneath (`glassBellGlow`); `GlassBellGlow.rowOpacity` 0.42 everywhere.
- Terminal: `TerminalSessionMark.placed`, `TerminalTabMark.placed(_:listed:)` (no pulse: Active's listing is up to
  five minutes old); a window's icon is the terminal it shows; the Mac's lone terminals (not SFTP) too
  (`loneIcon`; inline as a ternary it crashed the type checker: "failed to produce diagnostic").
- `TerminalTmux.programsScript`: after the listing, one `ps -A -o pid= -o tpgid= -o args=` joined to each session's
  `pane_pid` by `awk` on the host; `parse` keeps `TerminalAgent.identifyingWords` of it as
  `Session.programArguments`; `GlassTerminalCapability.agent(of: listed)`.
- iPhone name menu: the bell, else the agent's mark, else the dot.
- Demo `--demo-open active`: Claude Code and Codex on two made-up sessions. Help: `library-connect.md`,
  `terminal-sessions.md`. RELEASE-NOTES 0.4.621.

## Validation
- (running) `TerminalTmuxTests.listingPrograms`, `listedAgents`, live `listingProgramsLive` (a copy of `sleep` named
  `2.1.318` run through a link `claude` on a private tmux server); `UITests/ActiveAgentMarksUITests` and
  `ActiveBellUITests` on a simulator made for the run, pictures judged by eye.
- iPhone simulator, first run: the name menu drew Claude Code's mark as a dot. A menu draws an image at its own size,
  and each mark's SVG says `1em` (one point); every other use resizes it. Now `TerminalAgent.menuImage` (UIKit: the
  mark drawn at 20 points, template), used by the name menu. `ActiveAgentMarksUITests.testRunningSessionsShowTheirAgents`
  failed with "Nothing Is Open": `--demo-open active` lists its sessions under the library's machines, and the test's
  library had none; it now seeds alpha, build and nas (`--ui-testing-seed-hosts`).
- `listingProgramsLive` failed on this Mac: macOS kills a copy of `/bin/sleep` run from a temporary folder (137), so
  the shell stayed in front. It needs another stand-in program, and runs in the VM, not here (below).

## Live tests run in the VM or a simulator (2026-11-16)
- **His rule:** "From now on run test shell stuff in a VM/sim." A probe script run from this agent's shell, which has
  `TMUX` set, reached his own tmux server instead of a private one: tmux prefers `$TMUX`'s socket over
  `TMUX_TMPDIR`. The Swift live tests were not involved: they start tmux with a replaced environment and an explicit
  `-S`.
- **Safeguard, at his word:** `LiveTestGuard` (`Tests/GlassTerminalTests/LiveProcess.swift`): with `TMUX` set, the
  three tmux lookups the live tmux tests are gated on are nil, and the real-shell and local-agent suites are off
  (`LiveTestGuard.refusal`). `TerminalTmuxTests.liveTestsRefuseInsideTmux` checks it; seen failing with the guard off
  one lookup. Not yet seen: the live tests running in the VM, where `TMUX` isn't set.

## Ended terminals close off the Mac (D110)
- **His report, the iPhone's Active:** ~30 windows named after the machine, each "its tmux session has ended" —
  "this is less than useful". Asked, he chose closing them.
- **Changed:** `runningReport(local:hosts:closingEnded:)` closes a down terminal whose session the machine's listing
  leaves out, off the Mac (`closesEndedTerminals`), and its window when it was the last; not a skipped machine, a
  reconnecting terminal, or one that claims its session (`tmuxClaimsGivenName`: a saved Workgroup's slot not yet
  connected). Active's names drop an agent's spinner (`TerminalSessionNaming.steady`), drawn on iOS as a green emoji.
  Help: `terminal-tmux.md`, `terminal-sessions.md`. RELEASE-NOTES 0.4.621.
- **Validation:** `TerminalActiveListingTests.endedTerminalsClose` and `namesWithoutTheSpinner` pass (13/13 in the
  suite); each seen failing with its piece taken out (the close, the Workgroup guard, the spinner in a window's and a
  running session's title).

## Local builds and simulator validation (2026-11-18)

- Owner: Codex. Scope: build 0.4.621 (621) locally for macOS, iOS and visionOS and test on Apple simulators.
- A standalone fixture showed that `TerminalTmux.parse` could accept a mixed listing after dropping an unreadable
  row. The existing Active listing path now asks for a complete parse where absence can close a disconnected tab.
  The list command marks completed replies, including a confirmed empty server. The stricter parser rejects an
  unfinished reply or one with an unreadable row. Other callers keep the tolerant parser behavior.
- Reused the existing parser, host listing failure path and tmux test suite. Replaced the failing live agent
  fixture's relocated system executable with a symlink to the original executable. Updated the building guide
  with the existing VM or simulator rule for terminal tests that start shells or tmux.
- Six standalone assertions against the production parser passed. The site build
  validated 41 Help articles. `git diff --check` passed. Both Apple simulators booted under Xcode 27.2.
- The macOS Release bundle built as 0.4.621 (621); arm64 and its signature verified. Five iPhone simulator
  UI tests passed, including Select and tab movement. Captures show agent marks in both Active row types and
  the terminal menu, with the bell glow clearing after the terminal comes into view.
- Vision Pro simulator terminal suites passed 65/65, including real tmux listing and agent detection. The
  first run found a legacy wording test relying on retaining ended tabs off the Mac. The test now explicitly
  exercises the retained-tab policy; the separate automatic-cleanup test passed in both runs.
- Vision Pro simulator app UI tests passed 4/4 for the terminal renderer, reconnect, closing a lost terminal,
  and the Tailscale-off message. All three device Release bundles are staged in `build/0.4.621/`, with build
  logs and simulator result bundles beside them. Verified platform, 0.4.621 (621), arm64 and signatures on
  all three staged copies. The simulator runs used iOS and visionOS 27.2 with zero skipped tests.

## Distribution release (2026-11-18)

- The owner approved the same release sequence as 0.4.619. The source, README, release notes and site were
  prepared in `7b940e5a`. Both distribution jobs used clean worktrees of that commit.
- Mac `v0.4.621` published from `7b940e5a`. App and DMG passed notarization, stapling and Gatekeeper. The
  three published files match their local copies and the Sparkle signature verifies against the app's key.
- Feed commit `fe00d199` pushed after the GitHub assets were verified. The site build passed its Help checks,
  and 111 of 111 files in staging match. The owner runs the provisioning step. The previous public feed
  offered 0.4.619 before this release.
- Both TestFlight builds uploaded and processed as valid. App Store Connect confirmed What to Test and
  Testers membership on both. Vision Pro went to beta review first while iOS was processing. Both then
  read back `WAITING_FOR_REVIEW`.
- Deployment follow-up: the initial staging check used a different route. The owner identified the
  deployment host and its private runbook. Refreshed the 13 stale files there and checked all 111 hashes.
  Read the installed static-site script and gave the owner the command for the live update.
