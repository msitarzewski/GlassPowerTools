# 2026-11-19 — After a restart: tabs come back empty, terminals keep old names (D111)

**Owner and authorization:** the owner, 2026-11-19: "we have two large, related problems to solve asap", then the
answer below. Local edits, tests and VM runs. Not committed, not released; release at his word.

## What happened (his report, and the code)
- His Mac ran out of memory (swap 100 GB of 100 GB at 10:20; the app was 610 MB of it; a macOS test VM left running
  after the 11-17 workup was among the large ones) and he force-restarted it with ~29 local tabs in tmux.
- **The Mac:** every tab came back. The reopen list (`MacLocalTmux.reopenKey`) is kept while the app runs, so a forced
  restart reopens every window; each local pane ran `tmux new-session -A -s glass-N -c <folder it was opened in>`, which
  makes the session again when it's gone: empty shells, mostly in `~`, no startup commands (a Workgroup's is a one-shot
  ticket, `MacStartupCommandBroker`), no names (`@glass-name` lived in the session). Closing a window detaches, so the
  empties stayed running; he `exit`ed each. Opening a Workgroup only brought the empty windows forward
  (`MacWorkspacePreviewRegistry.reveal(workgroup:)`).
- **The iPhone (621):** terminals were matched to sessions by name only (`byName[name]`). After the restart, the three
  tabs he opened on the Mac took `glass-1`… (lowest free), so the iPhone's terminals with those names stayed, shown by
  their old given names (a project's name over a new session). Reconnecting attached with `new-session -A` too, which would
  either make the session again or join the new one.

## His decision
"I'd rather close it, or rather not reopen it, if it was a tmux session. Wouldn't that be easier to explain than getting
it wrong?" Agent resume was weighed and set aside (`claude -c` takes the folder's latest conversation; exact resume needs
an id the app knows only for agents it started). D111.

## Changed
- `TerminalTmux`: `#{session_created}` in `listFormat` (17 fields) and `contextFormat` (9); `Session.created`,
  `isSession(_:created:)`; `PaneState.sessionCreated`; `attachLine(joining:)` (`attach-session -t '=name'`);
  `TerminalTmuxAttachment.created`.
- `Models.swift` (`TerminalSession`): `tmuxSessionCreated`, `tmuxHasAttached`; the attach path joins only for any session
  it was handed or had; `tmuxSessionHasEnded` uses the identity.
- `TerminalRunningSessions`: matching and `isHeldHere` by identity; Active's Open passes `created`.
- `TerminalWorkgroupsToReopen`: the record keeps `tmuxSessionCreated`; reopen hands it back.
- Mac: `MacWorkspacePaneIntent.localTmuxSessionCreated`/`sshTmuxSessionCreated` (kept from reads, cleared when the
  name changes); `MacWorkspacePaneContext.sessionCreated`; `MacLocalTmux.reopens`, `withoutEndedSessions`,
  `joinArguments`; `MacWindowsToReopen(localSessions:)` (a test never reads the owner's server);
  `MacWorkspaceWindowController.forgetTabs`, `MacWorkspaceController.forgetSavedTab`, `joinsLocalTmuxSession`;
  `MacLocalTerminalConfiguration.resolve(joining:)` from both start paths (`startLocalPanes`, `MacLocalTerminalPaneView`).
- Tests: `MacReopenEndedSessionsTests` (new), `TerminalActiveListingTests.aLaterSessionByTheSameNameIsNotItsOwn`,
  `TerminalTmuxTests.rejoinsOnlyItsOwn` and the join lines, the reopen record round trip; stand-in hosts that list the
  session a terminal joins; `MacLocalTmuxTests` (a `parse` that stopped compiling at 621's `requireComplete`).
- Docs: RELEASE-NOTES 0.4.622, `site/help/terminal-tmux.md`, D111.

## Validation
- On his Mac, pure tests only (`TMUX` set: live tests skip): 82 in 13 suites passed (`swift test --scratch-path
  ~/Software/glass/tmp/spm-1119`). Each new piece seen failing with it undone (Active's identity, the join path, the
  relaunch check, the reopen record).
- In the macOS VM (tmux 3.7c): `session_created` in both formats; a session made again under a name gets a new time;
  `attach-session` to a missing session exits 1 ("can't find session") and makes nothing, `-C` too.
- In the VM app (`--ui-testing`, which skips CloudKit, the VM build having no iCloud entitlement): three tmux tabs
  saved their sessions' times; quit and relaunch with tmux running: the window came back, each tab rejoined its own
  session (same times, nothing made). The first restart run used `tmux kill-server`, which left the VM's launchd tmux
  half-alive (list: "server exited unexpectedly"): with the listing unreadable the window was kept, and the pane view's
  own start path still used `new-session -A` — found there and fixed (`MacLocalTerminalPaneView.tmuxSessionJoins`).
- The restart, with the fixed build: three tmux tabs open, then `sudo reboot -q` (ungraceful, the app running, as his
  forced restart). After it tmux had no server and the reopen list still named the window. Relaunched: only All
  Connections opened; no terminal window, no tmux server, session or client made; the reopen list and the window's
  record gone. Control again with this build: quit and relaunch with tmux running brought the window back, both tabs
  joined (`attach-session` ×2, `new-session` ×0), same sessions and times. The VM was stopped after.
- iPhone and Vision Pro simulator builds (app and tests, `build-for-testing`) pass. Their test suites weren't run.

## Shipping 0.4.622 (his "Ship it", 2026-11-19)
- `66c3a29b` pushed. Built from a clean worktree at it (`tmp/release-622-tree`, the package cache cloned from 619's):
  app and disk image notarized, stapled, Gatekeeper-accepted (Notarized Developer ID). GitHub v0.4.622 (Latest) with
  dmg, zip and checksums, downloaded back byte-identical, the tag at `66c3a29b`. Feed entry `4b61a63e` pushed. The
  Mac's thirteenth release.
- TestFlight 622: uploaded for iOS and visionOS; What to Test set, in Testers, both `WAITING_FOR_REVIEW`.
- Site built at `4b61a63e` (111 files) and staged on the server, 111 of 111 matching; provisioning is his step.
- Devices: development-signed Release builds of 0.4.622 for the iPhone and the headset; both were unreachable
  (`unavailable`) at install time, and a watcher installs each when it is reachable.

## Saying why (0.4.623)
- His word, with 0.4.622 released but the site not yet live: "We should let the user know that we lost the tmux session
  if we try to restore sessions and they're not available … Maybe check uptime, or check how long the tmux daemon has
  been running?" He held the site; the device install watcher was stopped; 623 supersedes 622.
- Built: `TerminalTmux.EndedReason` (machine restarted, tmux restarted, tmux not running, ended) with its sentence;
  `whyEnded` from the listing's server `#{start_time}`; on the Mac `MacLocalTmux.whyEnded` adds `kern.boottime`, and
  `takeOnce` keeps `endedNotice` (`EndedTabs`: tabs, windows closed, Workgroups, newest session's time), shown by
  `MacLaunchReopen` as an alert before the running-sessions offer. Off the Mac a terminal closing because its session
  ended — Active's close or its own rejoin (`tmuxSessionGone`) — is counted per machine in `SessionManager`,
  reported (`GlassRunningReport.closed`) and said under the machine in Active until dismissed.
- Checked: 96 pure tests (85 terminal, 11 shell); each new piece seen failing without it. In the VM, two tmux tabs and
  `reboot -q`: the relaunch said "2 tabs weren't reopened — Your Mac restarted at 1:19 AM, which ended their tmux
  sessions and everything running in them." (the VM keeps UTC); quit and relaunch with tmux running reopened both
  tabs, no alert. VM stopped. The Active note on iPhone/Vision Pro is unit-tested, not seen on a device.

## Shipping 0.4.623
- `1fecb42f` pushed; Mac v0.4.623 built from the release worktree moved to it: notarized, stapled, Gatekeeper-accepted;
  GitHub Latest, downloads byte-identical, tag at `1fecb42f`; feed `48fd04ed` pushed. The Mac's fourteenth release.
- Site built from `48fd04ed`, staged 111/111; he provisioned; live: 111 of 111 match, the feed `no-cache` with 623
  first, its zip the advertised length and the release's SHA-256, its EdDSA signature verified against the app's
  `SUPublicEDKey`, which 0.4.621 carries too. The home page downloads v0.4.623.
- TestFlight 623: iOS uploaded and submitted; the visionOS upload was cut off when the session ended, re-uploaded from
  its archive (`xcodebuild -exportArchive`), then submitted. Both `WAITING_FOR_REVIEW`. 622's two are in review too.
- His Mac: 0.4.623 installed at his word from the released zip (quit, swapped, relaunched): both windows reopened
  ("2 listed, 2 reopening"), no crash report. His test: a session killed by hand gave the notice as expected.
- His iPhone and headset: not yet (unreachable earlier; a 623 device build is next).

## Next
- Get Info (0.4.624, his ask); the iPhone and headset on 623; the records commit.
- His current iPhone terminals from before the restart never learnt their sessions' times (621 didn't read them): the
  two still standing over his new Mac tabs go by the name alone until closed by hand.
