# 2026-11-21 — One layout on every device: windows, tabs, databases, desktops (Proposed)

**Status:** plan written 2026-11-22 (below, "Plan"), from his decisions; not approved to build. Supersedes the shape
of B-F13 / D44 stage 2 ("open the same set here"), which offered another device's set to open by hand.

## His words
- Asked: "should we consider a global sync of windows/tabs/etc where when I add a new tab on mac it appears available
  on ViionOS etc."
- Offered "listed, ready to open, never opened by itself"; he answered: "Show plain shells, but I don't think we should
  open them somehow. We never knwo what's in then and running. Maybe an observe mode without tmux somehow in the
  future? Auto open is what made me want this feature. If the machine manages the windows/workgroups/tabs/DB/desktops...
  then other devices would simply read the layout. If I add a tab to a window on my mac with Vision Pro, then it should
  show on the Mac, too. Same window and tab. Agree re desktops. Can than handoff happen without close and reopen!?"
- "Agree re desktops": listed, and a desktop asks before taking over a Windows (RDP) session.

## Restated (sent to him to confirm, 2026-11-21)
One layout for the account, kept in iCloud: windows, their tabs in order, what each tab is. Every device shows it and
every device can change it: a tab added to a Mac window from the headset appears in that window on the Mac, in the same
place. A window's position and size are each device's own. Plain shells (not in tmux) are shown where they are, never
opened elsewhere; a read-only "observe" of one is a later idea.

## What exists
- Active lists each reachable machine's tmux sessions, at most five minutes stale
  (`GlassActiveConnections.runningSessionsMaxAge`, `Sources/GlassShell/GlassActiveConnections.swift:165`).
- Handoff (D72) offers the front window; continuing joins the same tmux session.
- Workgroups sync (D51) through iCloud key-value storage, which shares 1 MB with themes.
- The library syncs through CloudKit (D19, D26).

## Checked
- tmux's manual (3.8): `attach-session -f ignore-size` ("the client does not affect the size of other clients");
  `refresh-client -f` sets client flags on an attached client, a leading `!` turns one off; `window-size latest` sizes
  a window to "the client that had the most recent activity". So the device in use can be the only one that sizes a
  session. Each new size makes Claude Code print its conversation again (see the 0.4.633 resize-hold note), so a switch
  between devices showing different sizes costs one reprint unless every device shows the session at one size.

## Open decisions (asked 2026-11-21)
1. Closing: does closing a tab or window on one device close it everywhere? visionOS and iPadOS also close windows
   themselves, which must not end sessions.
2. Size: the device you type in sizes the session (one reprint per switch), or one size everywhere, scaled to fit.
3. The iPhone: same windows, one on screen at a time, or Active only.

## His answers, 2026-11-22
- Closing: "how would you re open the closed window? Do we then have a list of windows in the Active list?"
- Size: "Why can't 2 stay the way it is now with the currently focused window setting the size?" It already does:
  the focus claim (2026-10-22, `TmuxControlClient.claim`, `Sources/GlassTerminalEmulator/TmuxControlClient.swift:363`)
  switches the focused terminal's client to its session so tmux sizes the window to it; another device shows that
  grid, dotted past it (`SwiftTermHostView.showTmuxGrid`). Keep it. Question 2 should not have been asked.
- iPhone: "There's a dropdown on the terminal window a the top." Those windows are **sets** (help
  `terminal-sessions.md`): a shared window is a set, its tabs the menu at the top, the other sets in Active.
- Connections: "does that lose our working status pulsing?" Yes for an unconnected tab: the pulse comes from output on
  the tab's own connection. iPhone and iPad already connect only the terminal on screen after a relaunch, so theirs
  don't pulse until visited. 27 tabs have been fine on his Mac; the headset with ~30 is unmeasured. Each terminal opens
  its own SSH connection today (`Models.swift:1823`); one connection per machine carrying every tab is the fix if one
  is needed.

- 2026-11-22, his word: "Nobody has measured about 30 on the headset" "I have. lol. It's fine." Tabs stay
  connected as today.

## A window with tabs on different machines (his question, 2026-11-22)
"What if a window has a tab that's a session from another server … a window with mixed sessions (tmux and a shell
into [a server]). What happens in Vision Pro?" A Vision Pro window already holds tabs from different machines (help
`terminal-sessions.md`, Windows and tabs). Proposed: each device opens each tab straight to its own machine.
- The Mac's local tab in tmux: over SSH to the library machine linked as this Mac (D86, `thisMacHostID`), as the
  iPhone's Active reaches the Mac's sessions now.
- An SSH tab in tmux: straight to that server, joining the session; the Mac isn't in between.
- A plain shell, local or SSH: shown in its place, not opened (it lives only in the Mac's own process or connection);
  for an SSH one, offer that server's tmux setting.
- It can still fail to open where tmux would allow it: a key that can't leave the Mac (Secure Enclave keys never
  sync), a password, Tailscale off (D104), a network only the Mac reaches. The tab stays in place and says why.
- New question: a Mac tab split into panes has no equal off the Mac.

## His decisions, 2026-11-22
"Let have windows that aren't already open on each device open into the app's dock by default. Closing a window
closes everywhere, and we add a "repopen last closed window" in active in case it's closed by accident?"
- A window from another device arrives in this device's orb dock (Mac; Vision Pro), by default. iPad and iPhone have
  no dock: it arrives as a set, in Active. Proposed default: on Vision Pro the dock opens for it even with Shrink to
  Orb set to stand in place.
- Close closes the window everywhere. Putting a window away (Shrink to Orb) stays this device's own.
- Active gets Reopen Last Closed Window: its tabs in order, tmux tabs rejoining sessions still running (join only,
  D111), databases and desktops reconnecting; a plain shell ended with the window and is said to be gone.
- Split tabs: not answered; the plan takes the proposal (each pane its own tab off the Mac, kept together, marked as
  one split) and says so.

## Facts for closing
- Closing a terminal in tmux leaves its session running (help `terminal-tmux.md`), and Active lists a machine's
  running sessions and gathers them into one window. So a close everywhere loses no work in tmux.
- To check on the headset: telling a window the person closed from one visionOS closed itself (UIKit discards a scene
  session the person closed; a disconnected one is kept).

## What the code has (three read-only maps, 2026-11-22; key points re-read)
- **Mac.** Window `MacWorkspaceWindowController{windowID, tabs, selectedTabID, placement, windowSettings}`
  (`macOS/MacWorkspaceController.swift:1946-1980`); tab `MacWorkspaceRestorationState{id, root, focusedPaneID}`, a split
  tree of `MacWorkspacePane{id, intent}` (`macOS/MacWorkspaceState.swift:167-311`). IDs survive relaunch (UserDefaults
  `macWorkspaceRestoration.*`); a Workgroup launch makes new ones. A pane's intent holds kind, `serverID` (the
  Terminal service's EndpointID), tmux name and created time; title and agent are runtime only. A local pane doesn't
  record which machine the Mac is; Workgroups do (`macServerID`, from D86's `thisMacServerID`, a synced endpoint ID;
  the link itself stays on the Mac). Code can add a tab to a window, docked too (`MacWorkspacePreviewRegistry
  .tabAdder(windowID:)`, `macOS/MacTerminalOverview.swift:69`) and open one (`GlassWindowOpener`). Nothing opens a
  window straight into the dock: the dock needs an NSWindow and orders it out (`GlassMacOrbDock.swift:99`), and the
  last-run path shows it first (`:468-479`). Closing a window detaches its tmux panes and ends plain shells
  (`closeAllSessions`); quitting is told apart (`isQuitting`). Closed windows' records are never removed (D26 item 4
  counted 263 such keys).
- **Vision Pro, iPad, iPhone.** A window (Vision Pro) or set (iPad, iPhone) is a `TerminalWorkgroup{id, name,
  givenName, colorTag, sessionIDs, selectedSessionID, windowSettings}` (`Models.swift:2594-2610`), at most 32 terminals
  (`:2669`); no splits. `TerminalSession.id` never persists; a terminal is known by server, tmux name and created time.
  Scenes: `WindowGroup(id: "terminal", for: UUID.self)` keyed by the workgroup ID, restoration off; the app's own
  record reopens tmux windows not closed by hand. A window docked with no scene, its terminals connected, already
  happens at relaunch (`TerminalConnectFlow.swift:826-857`). Closed by hand = disappeared while the app isn't in the
  background and not docked (`TerminalWorkgroupsToReopen.swift:510-525`); today such a window's workgroup stays live
  in Active until quit. Code adds a terminal with `SessionManager.appendSession(_:toWorkgroup:)` (`:630-643`).
  iPhone/iPad connect only the shown set's selected terminal after a relaunch.
- **Databases, desktops.** A database window's ID is a new UUID per connect (`DatabaseSessionManager.swift:142`), a
  desktop's is its endpoint (`GlassDesktopScenes.swift:28`); neither is reopened at launch.
- **Sync.** CloudKit: private database, zone `GlassHostCatalog`, one `Host` record per host (whole profile as JSON),
  writes overwrite (`.changedKeys`, no server-tag check), merge in the app by `updatedAt` with final tombstones
  (`GlassCatalogSync.swift:133-234`), tombstones never deleted, every sync reads the whole zone on purpose. A
  `CKRecordZoneSubscription` sends a silent push; `GlassRemoteChangeReceiver` posts a notice and the model syncs
  (`GlassShellModel.swift:517-534`). Key-value store: envelopes with revisions, 384 KB a key, Workgroups as one key.
  Per-device identity: `preferences.writerID` and an editable device name (usage sync, `GlassShellUsageSync.swift`).

## Plan (proposed 2026-11-22; his word needed to build)
**One layout.** The account's open windows, synced: terminal windows with their tabs in order, database windows and
desktop windows. Synced per window: kind, name, colour, look (`windowSettings`), tabs. Synced per tab: what it is
(machine endpoint + tmux name + created time; or a plain shell, with the device it lives on; or a split group).
Each device's own: where a window is and its size, whether it's put away in the dock, the selected tab, focus.

**Records and transport.** A new zone in the same private CloudKit database (`GlassLayout`), with the catalog's
subscription and push path. One record per window and one per tab, so two devices adding tabs at once both land; a tab
holds its window's ID and an order key that two inserts can't collide on; a move changes both. Tombstones as the catalog
has them, but removed after a set time, and a device away longer than that drops its unsent layout instead of
publishing it again. Saves checked against the server's copy (a stale device's save is refused and merged), schema
versions skipped when unknown, so an older build can't write the layout at all. CKSyncEngine is the alternative to the
hand-made fetch; the catalog's path is reused first, as the project's rule asks.

**Each device publishes and follows.**
- **Mac:** a window is its `windowID`; a tab with one pane is one layout tab; a split tab is one layout tab per pane in
  a split group, with its arrangement, so another Mac shows the same split. Local panes are published on the machine
  linked as this Mac (`thisMacServerID`); with no link, as plain shells, and the Mac's library offers the link.
- **Vision Pro, iPad, iPhone:** a window or set is its workgroup ID; each terminal gets a layout tab ID that persists.
  A split group shows as adjacent tabs marked as one split.
- **A window from another device** lands put away: in the Mac's dock (new: a window that starts ordered out, never
  shown), in Vision Pro's dock (the relaunch path; the dock opens for it even with Shrink to Orb set to stand in place),
  or as a set in Active on iPad and iPhone. Its terminals connect as a docked window's do; iPhone and iPad keep
  connecting only what is shown.
- **A tab added on any device** appears in that window everywhere. The device that adds it makes the tmux session
  (D111's claim); every other device joins only. A tab on the Mac's own machine joins locally on the Mac, not over SSH
  to itself.
- **Plain shells** are shown in place, named, "on <device>, not in tmux", never opened elsewhere; an SSH one offers that
  server's tmux setting. When their device relaunches, its ended shells leave the layout; a shell whose device never
  returns can be removed by hand.
- **Can't open here** (a key that can't leave a device, a password, Tailscale off, a network only one device reaches):
  the tab stays in place and says why.
- **Databases** connect when opened, not as they arrive (a password or a tunnel through another machine may be needed).
  **Desktops** never connect as they arrive: opening one asks before taking over the Windows session.

**Closing.** Closing a tab or a window closes it everywhere: tmux sessions keep running, as a close does now; a plain
shell ends, so a window holding any, on any device, asks first wherever it's closed. Not a close: quitting, the system
taking a window from an app in the background, putting a window away. The Vision Pro test already in use for closed by
hand decides there; checked on the headset.

**Reopen Last Closed Window, in Active**, on every device: the last window closed anywhere, with its name. It comes back
everywhere with its tabs in order: tmux tabs rejoin sessions still running, databases and desktops as above, and
what can't come back (ended sessions, plain shells) is said.

**Active** lists the layout's windows (where each is open or put away) with the running sessions outside any window, as
now. **Handoff** names the window and tab (IDs only) and brings that window forward; nothing reconnects.

**Settings.** iCloud Sync: "Same windows on every device", on. Per device: windows from other devices Into the Dock
(default), Open, or Only in Active.

**First sync.** Each device publishes what it has. A tmux session already in a layout window stays there: another
device's window holding the same sessions takes that window instead of a second copy, said once.

**Limits to settle while building:** Vision Pro and iOS hold 32 terminals a window, and the Mac has its own cap
(`MacWorkspaceWindowRestorationState.maximumTabCount`); a window beyond the smaller one. Push is best effort: a device
also syncs the layout when it comes to the front.

**Phases** (each a build he tries; commit at his word):
1. The layout records and sync, published from every device, shown in Active only: nothing opens by itself.
2. Following: windows arrive into the dock, tabs added anywhere appear in the same window, plain-shell placeholders,
   split groups.
3. Closing everywhere, and Reopen Last Closed Window.
4. Databases and desktops in the layout.
5. Handoff as bringing the window forward.

**Validation.** Unit tests on the merge (two devices adding at once, a close racing an add, a stale device, expiry,
unknown schema), on each platform's mapping, close vs quit vs system, and reopen; each seen failing first. Two devices
live: the macOS VM and a visionOS simulator on a test iCloud account if one can be set up, else only on his Mac,
headset and iPhone, said as such.

## Found along the way (not this feature)
- **Fixed in 0.4.635, his word ("fix both defects, then start phase 1"):** Active's "closed, and why" note (D111,
  0.4.623) never appeared: the registry's `runningReport()` passed on `sessions` and `unchecked` and dropped `closed`
  (`Sources/GlassShell/GlassOpenSession.swift`), after the terminal had drained its counts. It sums `closed` now; the
  Mac's Active says it too, for SSH tabs whose rejoin found the session gone (help `terminal-tmux.md` updated). Test
  `GlassActiveConnectionsTests.closedTerminalsReachActive`, seen failing first (nothing reached Active).
- **Fixed in 0.4.635:** Handoff opened a second tab for a session already in a terminal here that was down:
  `revealOpenTerminal` skipped every disconnected terminal, as an iPhone's unshown ones are after a relaunch. The
  match is `SessionManager.terminalToReveal` now, shared by every platform: up, or down but not disconnected by hand
  or ended. Test `TerminalHandoffTests.revealsADownTerminal`, seen failing first.
- GlassShellTests 433 and GlassTerminalTests 1,319 pass. 0.4.635 built with Xcode-beta 27.3 for macOS, iOS and
  visionOS; installed 2026-11-22 08:05 on his Mac (read back 0.4.635/635, running, no crash report), the iPhone and
  the headset. Not seen on a device. Committed and pushed 2026-11-22 at his word, with phase 1.
- The Mac keeps closed windows' and tabs' records for good (above); not fixed.

## Phase 1 built (2026-11-22, 0.4.636), D113
- **Shell:** `GlassLayout.swift` (window and tab records, `GlassLayoutItem`, `GlassLayout.take`/`openTabs`,
  `GlassLayoutMerge.wins`, `GlassLayoutSnapshot`, `GlassLayoutPublishing.outcome`/`expired`),
  `GlassCloudKitLayoutBackend.swift` (zone `GlassLayout`, record type `LayoutItem` with `item` Bytes and `updatedAt`,
  subscription `glass-layout-changes`, whole zone read), `GlassLayoutSync.swift` (one pass at a time; reads before it
  first publishes; saves, then marks published; a failed pass waits 30 s doubling to 15 min, a read always runs),
  `GlassShellModel+Layout.swift` (enable, snapshot from every capability, observation with a 1 s debounce, push
  listener, Active's `layoutOnOtherDevices`), `GlassActiveOtherDevices.swift` (Active's "On <device>" groups).
  `GlassShellPreferences.layoutPublished` (this device's published IDs, never synced). `GlassCapability.layoutSnapshot`
  (a requirement; default none, ready) and the registry's sum (nil while any capability can't say). Settings ▸ Privacy
  ▸ Same Windows on Every Device (on), with the layout's sync status. Library view reads the layout at launch and on
  return to the front. App: `enableLayoutSync(GlassCloudKitLayoutBackend())` beside the catalog's.
- **Terminal:** `TerminalLayoutSnapshot.swift`: off the Mac each workgroup a window, each terminal a tab under
  `TerminalSession.layoutTabID` (kept in the reopen record, `Terminal.layoutID`); a terminal in tmux once it has its
  session, a shell here outside tmux, nothing while it is getting its session. On the Mac each window on screen or in
  the dock, each pane a tab (a split tab's panes in a group, `workspaceID`); local panes in tmux on the machine linked
  as this Mac, else a shell here. Ready: `TerminalWorkgroupsToReopen.hasSettled` (set in `keepCurrent`), the Mac's
  `MacWorkspacePreviewRegistry.layoutReady` (each reopened window registered, or 20 s; `awaitReopening` from
  `MacLaunchReopen`); nothing while the Mac quits.
- **Help:** `library-connect.md` (What your other devices have open), `library-sync.md` (a row). RELEASE-NOTES 0.4.636.
- **Tests:** `GlassLayoutTests` (8) and `GlassLayoutSyncTests` (4) in GlassShellTests; `TerminalLayoutSnapshotTests`;
  `TerminalWorkgroupReopenTests` expect the layout ID and its return. Each rule seen failing with it undone
  (`tmp/layout-draft/bite.zsh`, `bite.log`: the tie, unknown schema, a session twice, titles at once, never closed,
  never expiring, published before the save, published before the first read; and separately the pause, the restored
  tab ID, the settled guard, a tab getting its session). GlassShellTests 445, GlassTerminalTests 1,320 pass.
- **Not done yet:** his CloudKit Console deploy of `LayoutItem` (Development schema: record type `LayoutItem`, fields
  `item` Bytes, `updatedAt` Date/Time; then Deploy Schema Changes to Production). Until then each save is refused and
  Settings says so. Two devices live: not yet seen. The Mac's snapshot (`layoutTabs`) has no unit test (it needs live
  windows); seen only when the layout syncs.

- **0.4.636 installed 2026-11-22 08:29** on his Mac (read back 0.4.636/636, running, no crash report), the iPhone and the
  headset (Xcode-beta 27.3). The Mac's first pass, its log: "Layout: 32 of 32 record(s) refused … Cannot create new
  type LayoutItem in production schema" at 08:29:36, then "trying again in 30 s", a read 2 s later refused the same,
  "trying again in 60 s"; the library's own sync went on as before ("29 local, 29 incoming").

## Next
His deploy, then the layout seen on two devices (his Mac and headset; or the VM and a simulator); then phase 2.
