# Disconnect in the database workspace — 2026-09-22

The user noticed there was no way to disconnect from or close a database and, pointing at the ⋯ in
the Databases screen on the phone, suggested that menu as the place for Close on the other
platforms (2026-09-21).

## What was true

The only deliberate way to end a database session was Active's row — swipe on a phone, the
context menu on the Mac. The workspace itself, on every platform, had nothing. **The 23:00
resume note said iOS already had Close in that ⋯ menu; it did not.** The menu the user pointed
at is the system overflow for the workspace's `.secondaryAction` group (Refresh Overview,
Settings) and `SchemaBrowserView.swift:320` is the per-*table* menu (Browse Data, Copy, Drop…).
The user was proposing a location, not describing an existing item. Corrected in the resume block.

## Reuse

- glassdb's library row had **"Disconnect"**, `xmark.circle`, no confirmation
  (`../glassdb/glassdb/ConnectionManagerView.swift:802`). Same label, same symbol.
- The verb is `DatabaseSessionManager.disconnect(sessionID:)`, the call Active's row makes
  (`GlassDatabaseCapability.swift:155`).
- Going back to the machine is `showConnections()`, the workspace's existing back control.
- Closing the window is `@Environment(\.dismiss)` at the window root, the desktop's pattern
  (`GlassDesktopScenes.swift:45`, `onClose: { dismiss() }`).

## What changed

| File | Change |
|---|---|
| `Sources/GlassDatabase/DatabaseWorkspaceView.swift` | `disconnectWorkspace()`: disconnect, `showConnections()`, then `dismiss()` where the workspace is a window (`closesWindowAfterDisconnect`: everywhere but a phone, where `platformRoot` drops the workspace once the session is gone). One `ToolbarItem` **Disconnect** at `disconnectPlacement`: the phone's `.secondaryAction` (the ⋯), the iPad's and headset's `databaseToolbarPlacement`, the Mac's `.primaryAction` beside the ⚡. Identifier `database-workspace-disconnect`. `disconnect` added to the command actions |
| `Sources/GlassDatabase/Constants.swift` | `DatabaseWorkspaceCommandActions.disconnect`; **Disconnect** in the Mac's File group after Close Active Tab, deliberately with no key (⌘W and ⇧⌘W are tabs) |
| `UITests/GlassDatabaseUITests.swift` | `testDisconnectFromTheToolbarEndsTheSessionAndClosesTheWindow` (macOS, live MySQL fixture): press Disconnect, the workspace window goes, connecting again gives a fresh one |

Why the window goes with the session: the "Connection Closed" card exists for a *dropped*
connection. Leaving it on screen after the user's own Disconnect would report their action back
to them as a fault.

## Validation

- `swift test`: **1,707 tests, 0 failing**. Release builds 0.4.200 succeeded on macOS, iOS and
  visionOS; **0.4.200 installed on the Mac and the phone**, versions read back off each bundle.
- The Mac UI test **could not run**: twice the runner died in its own start-up with *"Timed out
  while enabling automation mode"* before any test code — the screen was unlocked (probe read a
  protected file). No Mac UI test ran in this session before it, so nothing says the harness
  worked from this shell today. **Not run, not failed.** Run it from a shell that has run Mac
  UI tests before, or from Xcode. The test is written and compiles.
- A phone test is not possible yet: `--ui-testing-seed-local-services` pairs a database *link*
  with no configuration, so nothing connects on a simulator. That is item 3 (a seeded
  database configuration), and it would make this test runnable on every platform.
- **Not yet seen by a person:** Disconnect in the Mac toolbar and in the phone's ⋯ menu.

## Also closed today

**The Linux server is back on the Mac** (user, 2026-09-22 00:0x) after the phone published its merged
record on 0.4.199 and the Mac fetched it under D34. No rebuild from the backup was needed; the
local backup of the phone's records is no longer needed.

## Reversed, 06:40 — the window is the close button

The user asked whether the X was needed only on iPhone and iPad outside windowed mode, since
everything else has a real close button for the connection. Not quite: the desktop and the editor end their
session when their window closes, and the database did not — the red button flushed the drafts,
released the window request and left the session open, findable only in Active. That is the
actual defect; the Mac toolbar button papered over it.

So the rule is now the desktop's: **closing the last workspace window on a session ends the
session** (`DatabaseSessionManager.releaseWorkspace`, which returns the disconnect task so a
test can await it). A second window on the same session closing leaves it alone — glassdb's
"Open New Workspace Window", kept; note `.primary(sessionID:)` uses the session id as the
window id, so a second window is `.additional(...)`. A phone registers a workspace and never
releases it (leaving a screen is not closing it, D31), and its ⋯ menu keeps the one
deliberate **Disconnect**, now the only place it appears: `UIDevice.userInterfaceIdiom ==
.phone`, `.secondaryAction`. The Mac toolbar button, the File menu item and
`DatabaseWorkspaceCommandActions.disconnect` are gone.

Tests: `DatabaseWorkspaceLifetimeTests` (one window ends it; the first of two does not, the
second does; an unregistered window is inert). The Mac UI test is now
`testClosingTheWorkspaceWindowEndsTheSession`, witnessed through Active's
`active-session-database:` row — written, not run (the automation-mode timeout).

## Also: a terminal opened by Connect on a Mac was not in Active

Active listed workgroups (`openSessions()` walked `manager.workgroups`), and every terminal on
iOS and visionOS is in one (`presentTerminalWindow`). The Mac opens a workspace window with a
live-session ticket and the session belongs to nothing but its window — so the MySQL session on
The Linux server was listed and the terminal beside it was not (screenshot 06:32). Now
`GlassTerminalCapability.loneSessions` lists every live session in no workgroup as its own row
on its server's endpoint (`terminal-session:` ids), and on the Mac
`MacWorkspacePreviewRegistry` — the overview's registry of window controllers and their
windows — gains `reveal(sessionID:)` (select the tab, bring the window forward) and
`close(sessionID:sessionManager:)` (remove the pane so nothing dead stays on screen; close the
window if that was its last pane). `TerminalActiveListingTests`: a lone session is one row on
its endpoint; grouped, it is the workgroup's row once; closing the row ends the session.

## And the row says where you are (06:45)

The user asked for the Active list to reflect what is open: the database was open, but the view was
on a specific table (`shop.articles`). `DatabaseSession.workspaceFocus` — set by the workspace on every
change of its displayed tab (`DatabaseWorkspaceView.focus(for:queryTitle:)`: the database, the
table as "database › table", the SQL document's title, nil on the overview) — and
`GlassDatabaseCapability.subtitle(engine:state:focus:)` renders "MySQL · shop ›
articles" while connected. `DatabaseSession` is `@Observable` and Active computes its rows in
its body, so the panel redraws when the focus changes. With two windows on one session the
later change wins. `ActiveRowFocusTests`.

The terminal's rows do not say where they are yet (a workgroup's row says how many terminals;
a lone terminal's, its state). A terminal's "where" would be its title bar — the shell's
`OSC 0` title, which the emulator already tracks — and that is the next reflection to add.

## And the sidebar highlights it (07:25)

The user reported that Active did not stay highlighted when clicked. The sidebar is a native `List(selection:)`
typed `GlassLibraryScope?`, and every panel row — Active, SSH Keys, Workgroups, Projects — was a
tap gesture with no tag, so the list went on highlighting All Connections while a panel was
showing. One selection type now, `GlassLibrarySidebarSelection` (`.scope` or `.panel`):
`current(scope:openPanelID:)` is the highlighted row, `change(choosing:…)` says what a choice
changes (choosing the current scope while a panel is open closes the panel; the list clearing
its own selection changes nothing). `GlassLibraryNavigation` takes `openPanelID` and
`onOpenPanel`; category rows tag `.scope`, panel rows `.panel`; the taps stay for the compact
stack. `GlassLibrarySidebarSelectionTests`. The accessibility selected trait follows the same rule.

## And Active says 0 (07:50)

The user asked for Active to show 0, like the other rows, when nothing is connected. Yesterday's nil-when-empty
(`activeSessionCount() -> Int?`, "the same rule every panel count follows") was wrong on its
premise — Favorites and Workgroups say 0 — and is reversed: the count is an `Int`, the row shows
0, `emptyCountIsZero` replaces `emptyCountIsNil`.

## And the desktop (08:10)

The user reported that desktops were not showing in the Active section. The desktop capability had no
`openSessions()` at all, and nothing tracked its sessions: each window makes its own
`DesktopSessionModel`. Now `DesktopAppModel.liveSessions` holds them — a model joins in
`beginAttempt` and leaves in `close()`, so a dropped desktop stays listed with its state until
its window goes — and `GlassDesktopCapability.openSessions()` lists one row per desktop on its
service's endpoint ("the Linux server", "RDP" or "RDP · Disconnected"), `desktop:` ids. Activate is a new
`Request.show(connectionID:)`: the bootstrap opens the `desktop-session` window with the same
value the connect used, which on a Mac brings the existing window forward; on a phone it shows
the cover again. Close is `session.close()`, which the window follows. No snapshot yet.
`openSessionsListsLiveDesktops` in `GlassDesktopCapabilityTests`.

Also seen in the user's 08:06 screenshot: the Linux server login screen laid out at proper scale on
0.4.206 — gnome-remote-desktop honours the core-data desktopScaleFactor.

## Passwordless root through the tunnel (08:25)

*"Requested secure item was not found in Keychain."* — MySQL on the Mac, root with no
password, through the host's tunnel. Two paths, two rules: `DatabaseSessionManager.
storedCredentials` (reconnect) had taken the 2026-09-20 decision — nothing stored means no
password, a real configuration, because the secret store refuses to write an empty value
(`KeychainOperations.swift:24`) so a passwordless service *cannot* store an item — while
`GlassDatabaseScenes.storedPassword` (the first connect) still kept the older rule and threw
the Keychain's own words. Now one rule, `DatabaseSessionManager.storedDatabasePassword(for:
retrieve:)`, used by both: `notFound` → "", any other Keychain failure is reported, SQLite asks
nothing. `StoredDatabasePasswordTests`, with the retrieval injected so no test touches a
Keychain.

## A new machine's first connect always failed (14:20)

Adding a new server and connecting for the first time failed with "Connection Failed:
This terminal session is no longer active", Last Connected: Never. Only a machine whose host key is not yet trusted takes this path. The trust
alert's Confirm spawned a task that called `trustHostKey`, then `retryPendingConnection`, which
took the session out of the prompt state. But SwiftUI sets the alert's `isPresented` to false
right after the action returns, and that setter closes and unregisters any session still
pending — so by the time the task ran, `trustHostKey`'s `origin(for:)` threw
`sessionNotRegistered`. The earlier fix (`HostTrustRetryTests`) moved the take before the
*reconnect* and missed that `trustHostKey` looks the session up first. Now the Confirm action
takes the session synchronously, before the task; the retry helper is gone. The host key was
never saved by the failed attempt, so the next connect prompts again and should succeed.

No unit test reaches the ordering (it is inside an alert action); `HostTrustRetryTests` covers
the handoff itself. **Not seen working** — needs a machine whose key is not yet pinned.
The user also reported that settings were not saved — not yet understood; asked.

## Settings reported as not saved — not reproduced (2026-09-23)

The user clarified it was the terminal's whole set of settings (user name and the rest), on
a newly added server. Not reproduced. `NewHostTerminalSettingsTests` drives the real host sheet over a real catalog file
(key auth, port 2222): the settings are what Edit shows right after saving and after a relaunch.
Ruled out by reading: the sheet's link-then-record order and its rollback (only on a failed
commit, and then the host is deleted too); `replaceAll` against an unread catalog (guarded);
a second `ServerManager` (there is one); a stale list after sync (every `load()` re-reads the
terminal's servers); a sync merge restoring the link without its record (the record write bumps
`updatedAt`); the address-sync race on Edit (fires only when the address changes); the failed
trust path (deletes nothing). **Untested: password auth**, which writes the Keychain in the same
save. Asked the user which auth method, what Edit shows now, and whether they edited after the
failure.
