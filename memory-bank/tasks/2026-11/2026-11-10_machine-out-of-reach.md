# A machine out of reach, and Tailscale off (2026-11-10)

## Task
- **Asked (the owner, 2026-11-10):** "I primarily use Glass Power tools with tmux sessions on my MacBook Pro.
  Sometimes, as a laptop, it goes into my bag, and is unavailable to sessions from my iPhone or Vision OS. That state
  (unavailable) doesn't behave well from those devices. They try to connect, but time out, some show detached, as if
  they could be reattached. Take a look at what happens when dozens (literally) of tmux sessions are unable to resume
  due to the host being down/unavailable. We should also recognize tailscale IP ranges and notify the user (like the
  last feature) when tailscale is required to be enabled before connecting. This is different from the tailscale
  integration (direct)."
- **Scope and authorization:** investigation, local implementation, tests, documentation; device installs (standing
  word). Commit and push: not asked.
- **State:** BUILD → QA.

## What happened (read from the code by an agent, the claims the design rests on re-read)
- No connect timeout was passed, so Citadel's 30 s applied (`Packages/Citadel/Sources/Citadel/Client.swift:300`).
- Nothing remembered that a machine was down. A pass over a window's terminals (Vision Pro relaunch, every window
  shown, a saved workgroup opened on iPad or Vision Pro) went one terminal after another
  (`TerminalWorkgroupOpening.connect`): thirty terminals, thirty timeouts, a quarter of an hour.
- Terminals reconnecting together took turns two sign-ins at a time (`SSHTransportPool`, W21); a sign-in that
  failed woke the waiting ones to open fresh connections to the same dead machine: thirty took five rounds.
- Active kept what an earlier listing said of a down terminal's session ("Detached", "Open elsewhere") after a
  listing of that machine failed: the "as if they could be reattached" he saw (`tmuxWhileDown`, set only by a
  successful listing).
- Each auto-reconnect run put seven **Connection Error** banners over the terminal in front, and gave up with
  "Reconnect failed after 5 attempts", the reason gone.

## What changed
- `SSHTransport.connectTimeout` 15 s, passed to both direct connects.
- `SSHTransportError.isMachineNotAnswering`: a connect timeout, ETIMEDOUT, EHOSTDOWN, EHOSTUNREACH, ENETUNREACH,
  ENETDOWN, a name that didn't resolve; not a refused port, a reset or a rejected sign-in.
- `SSHTransportPool.lease`: a lease waiting for a turn when a sign-in failed that way takes its error. The count is
  kept apart from `routes`, which is pruned as the waiters wake (the first version kept it there, and the test
  still saw five connects). A lease made afterwards tries again: a Reconnect, a window shown.
- `TerminalConnectFailure` (`TerminalMachineReach.swift`, new) on each session: `needsTailscale`, `notAnswering`,
  `other`. `TerminalWorkgroupOpening.connect` stops dialling a machine at its first terminal that found either, and
  gives the rest that failure (`takeFailure(from:)`), said once; the saved-workgroup open on iPad and Vision Pro
  (`TerminalConnectFlow.launchTerminals`) likewise, the alert saying "*n* more of its terminals weren't opened".
- Words: "*name* at *host:port* didn't answer. It may be asleep, or off the network." Auto-reconnect's give-up
  keeps the last reason and adds "Tried 5 times."
- Active: a machine it couldn't list clears its down terminals' `tmuxWhileDown`; new reasons "it didn't answer…"
  and "it's on your tailnet, and Tailscale is off on this …".
- The panel's error and disconnect banners removed (`handleSessionStateNotification`): the panel says it.
- **Tailscale** (`GlassShell/GlassTailscaleReach.swift`, new): a tailnet host is 100.64.0.0/10,
  fd7a:115c:a1e0::/48 or `.ts.net` (Tailscale's reference pages, cited in the file); this device is on a tailnet
  when a `utun` interface holds a tailnet address (`getifaddrs`; seen on the owner's Mac: utun5). A 100.x host is
  not said to need Tailscale where this device's own network is in 100.64.0.0/10 (carriers' NAT). Checked before
  dialling by the terminal (`TerminalSession.connect`, the first hop it dials), the remote desktop
  (`DesktopSessionModel.establish`, no sign-in prompt for it) and a database reached directly; the panel's title
  **Tailscale Is Off**; auto-reconnect stops at it. No documented URL opens the Tailscale app, so there is no button
  for it. `GlassLocalNetworkAccess.isLikelyLocalHost` no longer takes fd7a:115c:a1e0::/48 for the local network.

## Validation
- Unit, Mac:
  - `GlassTailscaleReachTests` 7: ranges, on-tailnet, carriers' NAT, this Mac's own interfaces, the local-network
    fix. Three fail with the tunnel check or the IPv6 exclusion taken out.
  - `SSHConnectionLimitsTests` +3: thirty leases on a machine that never answers make 2 connects, not 5 (seen
    failing, 5, before the count moved out of `routes`); a later lease tries again; what counts.
  - `TerminalMachineReachTests` 7: one dial for thirty terminals (each told why, another machine untouched); a
    terminal's own failure stops nothing; Tailscale off stops a pass and titles the panel; a tailnet host with
    Tailscale off fails at once; words; Active forgets "Detached". Five fail with the pass stop, the Tailscale check,
    the clearing and the wording taken out.
- **Real network, nothing doubled:**
  - `SSHMachineNotAnsweringTests`: 192.0.2.1 (RFC 5737) fails after 15.003 s, counted as not answering; a closed
    loopback port counts as answering.
  - `TerminalMachineReachTests.realPassOverAMachineNothingAnswers`: ten terminals on 192.0.2.10 through the session
    manager, each terminal's connect, the pool and the engine took **15.07 s**. With the pass stop taken out it ran
    past its 120 s limit (ten 15 s timeouts).
- **iPhone and Vision Pro simulators (2026-11-10, before the release):** the full real pass failed there, quickly, with
  `SecretStoreError`: a simulator's test process can't keep the password in the Keychain, so it never reached the
  network. It is Mac-only now, and `thisPlatformsNetworkFailure` dials 192.0.2.1 through the real SSH engine without
  the Keychain on every platform: on the iPhone simulator, 15.06 s and counted as not answering, with its words.
- Suites: Mac `GlassTerminalTests` 1,263 (before the real pass test); `GlassSSHTransportTests`, `GlassShellTests`,
  `GlassDesktopTests`, `GlassDatabaseTests` 230 / 352 / 416 / 89, all passing.
- UI: `TerminalConnectionLostUITests` 3 of 3 on the Vision Pro and iPhone simulators, `testTailscaleOffSaysToTurnItOn`
  new (`--demo-needs-tailscale`): the panel titled Tailscale Is Off, "alpha is on your tailnet (100.92.10.12), and
  Tailscale is off on this iPhone / Apple Vision Pro. Turn it on, then try again.", Reconnect; pictures looked at;
  no banner over it now.
- **Not checked:** his laptop really asleep, from his iPhone and headset; the wake path (`SSHWakeWatcher`) with
  dozens of terminals; databases through a tunnel and RD Gateway hosts (the Tailscale check covers the host dialled
  directly only).

## Next
- UI tests on the simulators, 0.4.614 on the Mac, iPhone and headset; then his try with the laptop in the bag.

## Shipped (2026-11-11)
- Committed (`5bc77b45`) and pushed; released in 0.4.616: the Mac's ninth release (GitHub v0.4.616, notarized,
  downloads byte-identical to the build, feed entry), TestFlight 616 (beta review approved visionOS on 2026-11-11 and iOS on 2026-11-12); the headset not yet installed.
