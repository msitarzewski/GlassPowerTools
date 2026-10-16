# Progress

Current state, by area: what is verified and how, what is not, and what is known to be open.
Rewritten 2026-09-27 from the session-by-session log, which remains in git history; the monthly
task notes under `tasks/` carry each piece of work's evidence. Verification levels used below:
**unit** (package tests), **UI** (XCUITest on a simulator or the Mac), **device** (driven on real
hardware), **server** (against a real SSH, database or desktop server — always the disposable test
VM for SSH and databases).

## Built

All four capabilities and the shell are built and in daily use on the owner's Mac and iPhone:

| Area | State | Strongest evidence |
|---|---|---|
| Shell: library, hosts, services, one setup sheet, favorites, collections, tags, search, Active and the session switcher, settings, layers | built | unit, UI on Mac and iPhone simulator, device (Mac, iPhone) |
| Host library sync through CloudKit; credentials and host-key pins through iCloud Keychain (D18, D19, D21, D23) | built | unit; device (CloudKit delivering between Mac and iPhone). The two-device acceptance run of D26 has not been done |
| Terminal: SSH, host trust, keys (file and Secure Enclave), tabs, themes, workgroups, local shell on Mac, SFTP browser, port forwarding | built | unit, UI, server (OpenSSH 10.2: shell, SFTP, RSA and Ed25519 sign-in), device |
| Databases: MySQL, PostgreSQL, SQLite; TLS modes; host tunnel; browser, grid, record editor, query editor, Explain, history, read-only services | built | unit, server (MySQL 8, PostgreSQL: 21 live integration tests plus the engine's own), device |
| Remote desktops: RDP (RDPKit) and VNC (VNCKit), certificate policy, resize following the window, audio, clipboard | built | unit (RDPKit 1,015 tests), server (Windows 11 with NLA — 2026-09-14 and again 2026-09-27; GNOME Remote Desktop; xrdp 0.9.24 in the disposable Docker fixture, 6/6 checks 2026-09-27), device (Mac, iPhone) |
| Editor: documents, projects on this device and over SFTP, New File, first save into a project, viewers, Markdown preview with Mermaid, 16 grammars, TextKit 1 on the Mac (D36) | built | unit, UI on iPhone simulator, server (7 live remote-editing tests), device (Mac) |
| Acknowledgements and licence notices (generated, guarded by tests) | built | unit |
| Database through another machine, or to a private address through its own machine's Terminal (D45, 2026-10-05) | built | unit, server (scratch tunnel to a network address); owner's production server through its app server |
| RDP in-session bandwidth measurements answered with the bytes received (2026-10-05) | built | unit, server (Windows 11 VM: 0 bytes before, real counts after) |
| Trackpad scroll events drive the remote desktop on iPad and Vision Pro (2026-10-06) | built | device (owner, Vision Pro with a Mac's trackpad) |
| Terminals kept in tmux sessions; Active lists sessions running on hosts (D44 stage 1, 2026-10-01) | built | unit, server (scratch: create, leave, reattach, end; missing-tmux path); not yet on a device |
| Local terminals kept in tmux on the Mac (D47): reattach after a quit or install, close detaches, Active lists This Mac's sessions, windows reopen after a quit (2026-10-07/08) | built | unit (fake tmux server; policies mutation-checked), tmux commands live on tmux 3.7c, device (the owner's Mac: this session survived and reattached across installs) |
| SwiftTerm 1.20: answers XTVERSION, so TUIs use synchronized output (D48) | built | unit (`TerminalCapabilityProbeTests`; the XTVERSION test fails on 1.18), device (Mac, the owner using Claude Code) |
| Local shells get the Mac's environment and `TERM_PROGRAM=GlassPowerTools` | built | unit, device (Mac) |
| Dependency update check, on demand and weekly (D48) | built | survey live (8 of 30 pins behind); `--test swiftterm@1.18.0` fails as it should; the weekly LaunchAgent (Mondays 08:00) ran on 2026-10-12: 9 of 30 pins behind, three updates failing (B-H9) |
| Mac tabs: names from what runs in them, rename, activity wave, Finder drop, drag between windows and reorder (2026-10-07/08) | built | unit (naming, throttle, drop escaping with a zsh/bash round trip, drag rules), device (Mac: rename, drag between windows confirmed by the owner) |
| Scrolling in tmux: local and SSH on the Mac, a pan on iPhone, iPad and Vision Pro (2026-10-08) | built | unit, live (commands through `sh` against tmux 3.7c); Mac local confirmed by the owner; iOS/visionOS not yet seen |
| Vision Pro windows draw Apple's glass themselves at their Glass; terminal and remote desktop completely clear at 0 (D59, D60, 2026-10-10) | built | unit, visionOS simulator captures; the terminal's earlier form on device (0.4.336); split-view windows keep system glass (observed limit) |
| This Window sheets: ↺ reset beside changed settings, Opacity/Glass/Material, one sheet layout (W27, 2026-10-10) | built | unit, visionOS simulator; Mac/iPad not yet looked at |
| Connections idle orb with the Active count; one Connections window on visionOS (W29, 2026-10-10) | built | unit, 8 visionOS simulator UI tests; not yet on a device |
| VNC: a window per remote display, region-limited updates, Quality levels and the Connection readout (D61, 2026-10-10) | built | unit, server (TigerVNC fixture with two screens and a rate-limited proxy); not yet against a Mac |
| Library rows one height in every list; Workgroups on the shared row | built | unit (`GlassLibraryRowConsistencyTests`), device (Mac) |
| Favourites (D49) and workgroups (D51) sync across devices | built | unit (two devices over a shared in-memory store; each fails without its push); not yet seen across real devices |
| Vision Pro: Connections window as a value-keyed window group (no launch lockout) | built | device (launched cleanly after the lockout) |
| Terminal plan of 2026-10-08/09 (W1–W10, W12, W13): find in tmux (⌘G next, ⌥⌘G grid), folder button opens Finder at the shell's folder, "+" offers a choice again, Connect always makes a new tmux session (atomic name claim), workgroups keep tmux names, one editor window per project and one Open…, tab drags move rather than copy, no Workgroups window (D52), Show All Terminals (Exposé), windows reopened by the app with their places (D54), multi-select in Active | built | unit (each fix shown failing without it), device (Mac: Exposé, restored windows and the drag confirmed by the owner; Vision Pro: no layout crash since rule 64). Detail: `tasks/2026-10/2026-10-08_find-tabs-tmux-workgroups-editor-plan.md` |
| Repository and branch in terminal names; names and rename from the tmux session on iPhone, iPad and Vision Pro (W11, 2026-10-09) | built | unit (26 new tests, each failing without its fix; live repo reads and private `-S` tmux); iOS/visionOS compile-only until seen on the devices |
| Files and photos dropped on a remote terminal upload to the host and type its paths; Mac SSH panes the same; Insert Path in a terminal's Files browser (W14, 2026-10-09) | built | unit (9 tests over the real `SFTPClient` with an in-memory host, each failing without its fix; HEIC→JPEG on this Mac); device (iPhone: a photo dropped from Photos reached the host) |
| Editor on Vision Pro: toolbar as the system ornament (Preview with Mermaid, Save, Open…, New, Find), Projects + ▸ New Document / Open…, rule 64 deferrals (W17, 2026-10-09) | built | unit + visionOS simulator UI tests (each failing without its fix); device (owner: "the editor toolbar works on the headset") |
| Vision Pro/iPad/iPhone tab groups back after relaunch; tabs moved between Vision Pro windows (W15, D55) | built | unit (16 tests, each failing without its fix); not yet seen on a device |
| visionOS plain windows in the window shape; Files folder as window title (W16) | built | unit (shape inventory), visionOS simulator captures; not yet seen on a device |
| A terminal selection lasts through output (2026-10-09) | built | unit (3 tests through the real view, failing without the fix) |
| Desktop Keys menu, arrow pad, iPhone keyboard bar; thinned desktop toolbar; arrow keys as priority commands (2026-10-11/12) | built | unit; device (owner: arrow keys "working again") |
| Local tmux under a launchd-run Glass Power Tools host; ends with the last session; Settings ▸ Terminal ▸ tmux (D66, 2026-10-12) | built | unit + live private-server tests (coalition, exit-empty, host ends with tmux); owner's Dock Force Quit of a probe app under the host ended the probe alone; device (Mac) |
| Tests never touch the owner's tmux server: panes attach through `MacLocalTmux.server` (2026-10-12) | built | unit (fails without the fix); the owner's session list identical before and after full runs |
| Basic terminals (D67): ⌃⌘T, "+" ▸ New Terminal / New Basic Terminal / New Terminal on ▸, Open without tmux, Basic Terminal on a host, palette; machine names in those menus | built | unit (13 + naming tests; 7 fail with the core changes undone); device (Mac menu read back through accessibility; owner saw the "+" menu) |
| Widgets Machines and Active (D68) on iPhone/iPad, Vision Pro, Mac | built | unit (snapshot, store, requests); Mac: extension signed, intents in metadata, snapshot written and read, owner sees correct counts; iPhone and headset installed, not yet seen |
| Editor project connections reopen when dropped (2026-10-12) | built | unit + live (a real SSH connection ended under a project, scratch VM) |
| Wrap Long Lines off on iPhone/iPad/Vision Pro (2026-10-12) | built | iOS simulator (`GlassEditorUIKitTests`, 3 of 5 failed before the fix) |
| iPhone: tapping a workgroup opens its detail (2026-10-12) | built | unit (fails without the fix); device install |
| The busy tab's light: a soft cloud sweeping the row (2026-10-12) | built | unit (sweep timing), rendered images; owner approved on the Mac |
| Every terminal on a lost shared SSH connection says so (B-X5, 2026-10-13) | built | unit; gated live test through a relay that cuts the connection |
| Terminal windows (2026-10-13): SSH panes connect from "+" ▸ New Terminal on, in windows already open and in restored tabs; a pane's connection held by its controller (D70); Reconnect; Close Pane closes the tab with its last pane; a close box per tab; square panes where they fill the tab | built | unit (each fails without its fix; the D70 test reproduces the owner's CancellationError); device (owner, Mac: "it works", corners confirmed) |
| Show All Windows (2026-10-13): every kind of window, one button beside every ⚡, the pinch on terminal and desktop windows, Blur previews | built | unit (grouping; one owner of ⇧⌘\); device (owner's screenshots of the overview on the Mac) |
| One Command Palette owned by the shell; Check for Updates only when configured (2026-10-13) | built | unit (a menu-bar test finds two owners with the old declarations); device (Mac menu read back) |
| The app's own Light, Dark or System (D71); the command palette in the windows' glass; Blur previews on Settings ▸ Appearance at 1.5 pt (2026-10-13) | built | unit (the appearance test fails with `apply()` emptied); device (owner on the Mac, 0.4.402: "looks good"); iPhone/iPad styles not yet seen |
| Database connect errors (2026-10-13): one measured Local Network rule (`GlassLocalNetworkAccess`); PostgreSQL in the server's words; unknown hosts named | built | unit with the drivers' own errors; server (test VM: wrong password); the denial measured from a runner without Local Network access |
| Desktops on phones and iPad (2026-10-13): the system's unavailable view, sessions in place on phones, a bar and a working Close in iPad windows | built | iPhone, iPad and iPhone Duo simulators; desktop and library UI tests |
| Quick Look: a view per file (the 05:58 crash on 0.4.393) | built | not reproduced; the fix removes the only call that crashed; no crash since |
| All Windows off the Mac (2026-10-14): iPhone/iPad pull-down pane or hold ⚡, a window of its own on Vision Pro, Siri "Show all windows"; the Mac's layout everywhere: a group per machine, a card per tab, live pictures each second (the iPhone's only the terminal under the pane) | built | UI (`GlassAllWindowsPaneUITests` on the iOS 27.2 simulator; visionOS window); device (owner on iPhone and headset) |
| 28 AI agents marked on cards and tabs (`TerminalAgent`) | built | unit; device (owner's Mac: Hermes "nice!") |
| Desktop clipboard both ways with GNOME; Sync Automatically (4499937) | built | server (GNOME Remote Desktop); device (owner: "this is magic") |
| Command Palette lists services, terminal commands, projects, folders, saved queries, running tmux; terminal link/path menu (Mac right-click; Vision Pro hold); ⌘↩ sends a reviewed paste | built | unit; device (Mac); the headset's hold-on-path menu not yet seen by the owner |
| Editor: a new file's first save into a project on a server (8825846), ⌘S off the Mac asking where for a new document (e3ee5d7); SFTP errors in plain words | built | server (live SFTP tests on scratch, failing without the fix); iOS simulator UI test |
| Active: Open as Tab In ▸ for a running session, Open N as Tabs In for several; the + of a terminal window held off the Mac lists servers ▸ New Terminal and their running terminals; the Mac's + lists them (e9e38d7, 4a1cd6f, 2900dc9, 2facec6) | built | unit; device (owner, Mac: "Mac works great") |
| Vision Pro terminal (2026-10-15): selection by a hold that allows drift, double/triple pinch, Copy; one Tabs/Grid/Carousel toggle (hold lists Orb too); Auto-focus on activity in This Window (2a49a43, 1d63c66, 1011982) | built | unit; visionOS simulator UI tests; device install (the owner testing) |
| Vision Pro session orb (D74): terminal, desktop, database and editor windows shrink into a glass sphere with a live picture, the window's tabs as dots on a ring, a name on a look that stays while read (1011982, b72244d, f46f283, 6b8deb3) | built | `GlassSessionOrbUITests` (shrink and grow; two tabs on the ring, a dot grows the window back); device (owner on the headset, three rounds of his notes); the pulse not yet seen on a device |
| Vision Pro, 2026-10-15 (0.4.454): selection with tmux's mouse on (a drifting hold waits out tmux's drag; a pinch clears a selection; the keeper checks a selection output left in place) and on-device selection diagnostics (532a9d8); orb names as wide as their words against their dots, database and editor orbs showing the window, a desktop's shape re-held after its orb (30d6ca6); the Files window clipped to its corner (0c07f12) | built | 8 visionOS simulator UI tests (3 new for tmux, 1 for the desktop round trip; the tmux ones fail without their change); Mac keeper test fails with the old restore; terminal suite 846; captures of the ring, editor and database orbs |
| 2026-10-15/16 (0.4.455–0.4.462): Vision Pro pinch-drag scrolls when tmux has the mouse (2975ace; tmux 3.8 turns it on by default; `~/.tmux.conf` on his Mac now turns it off); selection as Apple's text does — hold selects the word, drag an end with no hold, trackpad click-drag selects (f2fde40); iPhone tab switcher readable in light mode and All Windows listing every tab (ce2dbf6, 3e101b8); iPhone desktop one bar at a time and light-mode title (f1ee5ba, d1198cb); Mac terminal file previews (D76: d733b3c, 7780201, e51e3ff) | built | visionOS selection suite 8 (new tests fail without their change); iPhone `DesktopOnIPhoneUITests`, All Windows 5; unit terminal 853, shell 300, editor 169; his headset log confirmed the tmux-mouse cause; hover/Space previews and headset selection are his to try |
| 2026-10-16 (0.4.463): terminals scale as well as resize (D75) — When Resized setting, This Window and Scale Text in the bar; the grid kept and the drawing scaled (iOS/visionOS scaler view, Mac scaled bounds); the window held to the grid's shape by the desktop's lock moved to GlassShell; ⌘+/⌘−/⌘0 size the window (394fb47, 3feb28a, 2914f3f) | built | `TerminalScaleTests` 7, `GlassWindowAspectLockTests` 2, When Resized profile/sync tests (each fails without its change); visionOS `testScaleTextIsInTheBarAndSwitchesTheWindow`; unit terminal 862, shell 302, desktop 222; the scaler on a resized headset or iPad window is his to try |
| 2026-10-16: a Mac terminal window's sidebar adds to the window (D77) — opened or closed, the window grows or shrinks and the terminal keeps its size and place; not for the sidebar it opens with, the overview, full screen | built | `GlassAdditiveSidebarsTests` 2, `MacTerminalSidebarTests` 3 (each fails without its change); the toolbar button in the running app is his to try |
| Database Local Network and tunnel limits closed: tunnels keep their own connections (D69) | decided | sshd_config(5); OpenSSH reports of multiplexing lag |

Suites run 2026-10-13 with the screen unlocked: terminal 781, shell 280, database 321, DBKit 28, all passing
(the whole package not re-counted that day). Earlier: about **1,790 tests**. The last full run with the screen unlocked passed (1,777, early
2026-09-27); the night's later runs were under a locked screen, where file-protected stores cannot be
read — they fail the same 137 tests before and after the night's changes, and every new test passes.
Vendored suites: swift-nio-ssh 363, Citadel 58, RDPKit 1,015. Release builds succeed for macOS, iOS
and visionOS.

## Release preparation (2026-09-26 → 27)

Done: privacy cleanup (rule 61); SSH stack re-vendored at upstream commits with documented patches;
licences and acknowledgements; dependency refresh (see `techContext.md`); the public-release audit's
fixes — a new built-in theme identifier with migration, the widget's dead links removed, one
`Config/Identity.xcconfig` for signing, a warning for unencrypted database connections, query
history redacted by default, MySQL metadata lookups bound rather than escaped (a real defect under
`NO_BACKSLASH_ESCAPES`, proven against a live server), editor UI tests isolated from the real
project list, RDP trust evaluated over the whole certificate chain, and VNC's lack of session
encryption stated in the setup form. Details in `tasks/2026-09/`.

Also done: README, SECURITY, CONTRIBUTING and a building guide; 35 help pages audited from the code,
the site and its generator (not deployed); Sparkle for the Mac with a release script (never run); and
the defects the help audit found (`tasks/2026-09/2026-09-27_help-site-and-updates.md`).

Remaining before a first public release: the owner's release steps (Sparkle key, Developer ID
profile, notarization, deploying the site), the behaviour findings listed in `activeContext.md`, and
— only on the owner's word — the history rewrite and the first push.

## Not verified

- **Widgets on iPhone and Vision Pro (D68):** installed, not yet placed or tapped. On the Mac, taps
  (connect, show machine, show Active) have not been reported either.
- **D66 in daily use:** the owner's tmux server predates it; the launchd host starts with the next
  server (after a reboot or End All Local Terminals).
- **Headset input (2026-10-13):** held delete and arrows repeating, and pinch-and-hold-then-drag selection, are
  built and installed (0.4.393 on) but not yet tried by the owner; UIKit keys and gestures are out of the package
  tests' reach.
- **The unfolded Duo tour** (the 12-pt content margin, host detail, Active, Settings, Workgroups) waits on the
  simulator being unfolded.
- **Vision Pro:** runs the same build as the Mac and the iPhone (0.4.400 on 2026-10-13); the owner has used
  desktops, trackpad scrolling and the editor's toolbar on it. Not every change since has been gone through on it
  (the inventory's B-V1 lists what is owed).
- **Database scroll edge on the Mac** (hard top edge so content does not print through the
  toolbar): built, not seen — no screen capture without screen-recording permission.
- **The D26 two-device acceptance run:** add a host with a key on one device, connect from another
  without re-approving trust.
- **UI tests cannot reach a database or desktop surface:** both need live fixtures that a simulator
  runner does not receive. A seeded configuration is the fix.
- **SwiftTerm 1.18** has not been looked at on screen.
- **RDP with a certificate from an intermediate authority** has not been tried against a real server.
- **The grid's timing harness** has not been re-run since the grid changes; the target is unmeasured.

## Known and open

- **Vision Pro (2026-10-08):** the SwiftUI stack-layout crash while a terminal showed a Mac's tmux
  session was fixed by `32fa481` (2026-10-09: the simulator stress harness crashed 17 of 30 before, 0 of 24
  after; none on the headset since — 2026-10-08 plan note, W10). Still open there: Active skips a machine
  it cannot sign in to without asking; one SSH tmux listing failed, cause unknown.
- A tab-to-new-window drag (outside any window) is not supported; "Move Tab to New Window" covers it.
- A database workspace's tabs do not survive leaving and returning on a phone; its session and SQL
  drafts do.
- Desktops are listed in Active (`GlassDesktopCapability.openSessions`); the D31 line saying they
  contribute none is superseded.
- `configurations(ofKind:)` skips undecodable records without logging.
- VNC is encrypted after sign-in only to a Mac signed in with a Mac account (its own revision, e7463ce);
  a password alone or a non-Mac server is not (no VeNCrypt, no tunnel). The setup form says which (262ba7a).
- tree-sitter 0.27 and swift-crypto 5 wait on upstream releases (`techContext.md`).
- **B-X27 (2026-10-13):** files written with complete protection fail while the Mac is locked (recordings, SFTP
  downloads, desktop captures; ~23 terminal tests). The protection class is the owner's decision.
- The database's own sidebar chrome removes UIKit's toggle off the Mac (`databaseSidebarChrome()`), as the library
  no longer does (D24, amended 2026-10-13). Looked at again 2026-10-13: no dead end — on an iPad (and any regular
  width) the database places the editor's `GlassSidebarToggle` instead (W32), a compact width is a stack with no
  sidebar, and the headset's header has its own. No change.
- The legacy `SFTPRemoteEditorView` sheet remains as a fallback; the owner has been asked whether to
  delete it (B-Q11). Nothing is lost by deleting it now: the editor checks for an outside change as its window
  comes forward too (B-X2, 2026-10-13).
- **Default text editor (owner, 2026-09-27):** built 2026-09-30 (`28a0b6e`) — an Alternate editor for plain
  text, source, JSON, XML, Markdown and YAML; not yet opened from the Finder (B-V3).
- glassDT parity audit findings: `tasks/2026-09/2026-09-27_glassdt-parity-audit.md`.
- Library sync (2026-09-28): whole-account fetch, deletions dated by statement, no set-up service can
  vanish through a merge, per-record apply with visible failures, dry-run mode. Proven on the Mac
  against the real account (0/0 after repair); the phone and headset received 0.4.249.
- visionOS: lists unwound to the platform's own (2026-09-28). D40 narrowed (2026-09-29): all window
  transparency stays; only list formats and non-Glass chrome change. The database results bar is
  done (icons + More); verified on the Mac, not yet on the headset.
- Two terminal tests fail intermittently in full-suite runs only (see `activeContext.md`).
- Schema diagram (D43, 2026-09-30): built; unit + live MySQL/PostgreSQL tests pass; in use on the
  Mac; seen in the visionOS and iPad simulators; not yet on the physical headset or the iPhone.
- Backlog run (2026-09-30): typed passwords on trial; startup tickets by the clock; imported desktop
  mobility; Rows per page and Settings ▸ Databases; RDP autodetect timed and answered in session; VNC
  pipelining and Tight+JPEG with adaptive quality; RDP clipboard chunking and rich content; Files ⌘C/⌘V
  with the Finder; library overview and availability dots; default text editor; trusted host keys;
  editor Find/close off the Mac. Unit-tested; VNC and RDP clipboard checked live against the Docker
  fixtures; Windows, the Finder's Open With and the headset not yet.
- Desktop glass on the Mac (2026-09-30): Opacity and Background Frost as on the headset; seen by the
  owner on 0.4.266. Settings on the Mac sizes itself to its ten tabs.
- **Vision Pro session orb (2026-10-15):** the pulse with Auto-focus on activity is not yet seen on a device. A
  desktop's shape hold after a round trip is re-asked (logged on the simulator), but the simulator never reports the
  hold itself, so it is the headset's to show. The Files shelf's corners are clipped but the demo can't show the
  shelf. The held + and the toggle's held menu are for the owner to try (the simulator's runner turns a held menu
  into a tap).
- **Vision Pro terminal selection (2026-10-15, 0.4.454):** the owner reported it "still broken wholly … with tmux"
  after 0.4.449's fix passed the simulator. Two defects found and fixed (a drifting hold became tmux's drag when tmux
  has the mouse; a pinch never cleared a selection then), but this Mac's tmux has the mouse off, so his failure may
  have another cause. Each hold, pinch and selection change is now written to the app's diagnostics file
  (`terminal-selection` lines in `screen-sharing.log`): copy it off the headset after he tries (see the
  headset-diagnostics memory) before changing anything else.
