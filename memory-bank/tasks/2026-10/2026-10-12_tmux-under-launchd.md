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
