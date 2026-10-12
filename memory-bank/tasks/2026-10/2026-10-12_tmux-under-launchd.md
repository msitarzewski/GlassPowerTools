# 2026-10-12 — This Mac's tmux server under launchd (D66)

**Owner:** coordinating agent. **Authorization:** the owner asked for both the cleanup and the
launchd server ("both please"); standing "commit each piece as it lands" and install when ready.

## What happened

The owner force quit a scratch app (a W7a resize reproducer an agent built on 10-08 and ran from a
shell inside a local tmux session, then left running four days). Every local terminal ended in the
same second: the Dock logged `force quit (caller responsible for termination)` and `calling back to
client to terminate`, about a dozen pane processes and the tmux server exited, and the app's three
tmux windows closed within 250 ms. The app itself kept running. The reproducer's folder had no saved
state and was deleted.

## What ties them together: the coalition, not the process group

tmux daemonizes, so any server already has launchd for a parent and a process group of its own.
Measured with `proc_pidinfo(PROC_PIDCOALITIONINFO)` and `responsibility_get_pid_responsible_for_pid`:

- The app, the tmux server it started, every pane and the shells inside them share the app's
  resource coalition, and the app answers for all of them.
- After the app quits (every install quits it; D47 keeps the server running), the server and panes
  stay in that coalition and each answers for itself.
- A server launchd runs is a coalition of its own and answers for itself; its panes, and anything run
  from them, are the server's.

## Experiments (owner did the Force Quit from the Dock both times)

A probe app (`ForceQuitProbe`, scratch) run directly as a pane's process of a private tmux server
(test label, private socket), with two bystander panes running `sleep`:

| Server | Probe's coalition answers to | After Force Quit |
|---|---|---|
| launchd job (`tmux -D`, the new arrangement) | the live server | probe ended; server and both bystanders alive |
| started by a launchd starter that then exited (the 10-12 state) | itself (starter gone) | probe, server and both bystanders all ended |

Same Dock log lines both times. The control reproduces the incident; the first row is the fix.

## Changes (committed)

- `86815ed` Tests: the nine suites that swap `MacLocalTmux.server` nested in one serialized suite
  (`LocalTmuxServerSuites`); three cross-suite failures gone; terminal suite 746/746 three times.
- `1e89b18` `MacTmuxService`: when no server answers (`tmux -N list-sessions`), write a job to
  Application Support (not LaunchAgents), boot out a stale one, bootstrap it into `gui/<uid>`, wait up
  to 3 s; a running server is left alone; failure leaves the claim to start tmux as before. Called
  from `MacLocalTmux.Server.live.claim` and before a pane attaches, at most once per 10 s.
- `0619569` The live test checks coalitions (old-way server shares the test's; launchd's server and its
  pane share one of their own); header states what was measured.

## Validation

- `MacTmuxServiceTests` 3/3; terminal suite 746/746 (before the coalition test change; the change is
  test-only).
- Installed **0.4.373** on the Mac 01:29; version verified; no crash report. The running server was
  left alone and no job was written (expected: a server was running).
- Not built for iOS or visionOS: the changes are macOS-only; devices stay at 0.4.372.

## Remaining

- The owner's current server (started 00:44 by the previous app) is in the quit app's coalition, as
  every install has left it. The launchd server takes over only when that server ends (a reboot, or
  the owner ending it at a time of his choosing — it ends every session, this agent's included).
- Until then: launch a test app with `open`, never by running its binary from a pane.
- Not tested: a Force Quit of Glass Power Tools itself while it owns the server.

## Found after: test panes on the owner's tmux server (rule 63), fixed

The owner's app reopened six tabs titled with a test's awkward folder name: sessions glass-7, 8, 9,
11, 12, 13 on his default server, made during this session's terminal runs (01:08–01:11). Cause:
`MacLocalTerminalConfiguration.resolve` took tmux from the static `MacLocalTmux.executablePath()`
while everything else asks `MacLocalTmux.server`, so a test window's pane ran this Mac's tmux
(`new-session -A` makes the session, or joins the owner's of that name); the stand-ins also named
`/opt/homebrew/bin/tmux`. Fixed in `8ce39c3`: resolve and `Lookups.live` ask the server; a new
`Server.ensureRunning` carries the launchd check (stand-ins: nothing); `ensureDefaultServer` acts
only for this Mac's own tmux; stand-ins name `TmuxStandIn.path`, which is no tmux. A test fails both
ways without the fix. Terminal suite 747/747 on four runs with the owner's session list identical
before and after. `df5bfea` fixes a timing-flaky output test seen once in those runs. The six
sessions are left for the owner (he had typed in two while looking into them). No reinstall: the
app's behaviour is unchanged.

## Background mode: the app hosts tmux (9b62ebf, installed 0.4.374)

Permissions check: under a tmux launchd ran directly, a pane listing the Desktop raised "tmux would
like to access files in your Desktop folder" (the owner allowed it; tmux now holds that grant); a
pane of the app-started server read it silently with the app's permission. The owner chose the
host design and asked that it end with its last session and that Settings > Terminal can end it.

- The job runs the app's executable with `--tmux-host` (`MacTmuxHost`; new `@main` entry chooses it
  before SwiftUI); it spawns `tmux -u -D` (only stdout/stderr inherited) and waits.
- `tmux -D` turns `exit-empty` off (measured: an empty -D server stays up); the host turns it on at
  the first session and kills a server that gets none in 60 s. The host ends with tmux.
- Settings > Terminal > Local Terminals in the Background: status and End All Local Terminals...
  (`MacLocalTmux.Server.endServer`, live: `MacTmuxService.stopDefaultServer`).
- Measured with the Release build, private socket, test label: panes answer to the host, own
  coalition, no LaunchServices entry, ~35 MB; Downloads listed with no dialog; the owner's Dock
  Force Quit of a probe run from a pane ended the probe alone (host, tmux, two bystanders alive).
- Installer script (scratchpad) ignores `--tmux-host` when waiting for the app to quit.
- Tests 752/752 twice; owner's sessions unchanged. Installed 0.4.374 07:46, no crash report; his
  20 sessions (13 his own from 07:23–07:42) reattached. The server of 00:44 still predates D66.

## Terminals without tmux (130c879, D67)

Owner: "build both. we need to allow remote sessions without tmux too even if it's been selected as
default." A terminal carries `withoutTmux` (session, Mac pane intent, workgroup intent, reopen
record); it claims and attaches nothing and is not offered tmux. Entry points: File > New Plain
Terminal Tab (⌃⌘T, free per the running app's menus read through accessibility), "+" menu, empty
tab's Plain Local Terminal (only with local tmux on), Connect Saved Host's "Open without tmux",
palette entries, and a Plain Terminal row beside Files in the host detail on every device (hosts
that keep terminals in tmux). Settings > Terminal > tmux holds the local toggle (moved from
Connections), the background status and End All. Tests: 13 new; 7 fail with the core changes
undone. Terminal 763/763 twice; every module passes; owner's sessions unchanged.


## "+" menu and the name "Basic" (737fa43, 0.4.376 on all three devices)

Owner: "a cascading menu for all defined hosts with terminals", then "new terminal, new basic terminal, new
terminal on...". "+" now reads New Terminal, New Basic Terminal, New Terminal on ▸ (saved hosts by name, in tmux as
each says). A terminal outside tmux is "Basic" everywhere it is named (File ▸ New Basic Terminal Tab ⌃⌘T, read back
from the running menu; Basic Local Terminal; Basic Terminal on a host; palette; Settings). No "basic on host" submenu,
per his list; offered.
