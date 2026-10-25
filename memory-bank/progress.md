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
| Shell: library, hosts, services, one setup sheet, favorites, collections, tags, search, Active (the ⚡; the session switcher it replaced is gone, D33), settings, layers | built | unit, UI on Mac and iPhone simulator, device (Mac, iPhone) |
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
| Terminal plan of 2026-10-08/09 (W1–W10, W12, W13): find in tmux (⌘G next, ⌥⌘G grid), folder button opens Finder at the shell's folder, "+" offers a choice again, Connect always makes a new tmux session (atomic name claim), workgroups keep tmux names, one editor window per project and one Open…, tab drags move rather than copy, no Workgroups window (D52), Show All Terminals (Exposé; Show All Windows since 2026-10-13), windows reopened by the app with their places (D54), multi-select in Active | built | unit (each fix shown failing without it), device (Mac: Exposé, restored windows and the drag confirmed by the owner; Vision Pro: no layout crash since rule 64). Detail: `tasks/2026-10/2026-10-08_find-tabs-tmux-workgroups-editor-plan.md` |
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
| 2026-10-16: 3D models (D78) — USDZ/USD/Reality decided by their bytes; RealityKit viewer on Mac/iPhone/iPad (AR Quick Look on touch), Model3D and Apple's Quick Look volume on Vision Pro; editor viewer, Files, Mac hover preview; model links downloaded and shown in 3D | built | `FileKindTests` +2, `ModelFileTests` 3, `TerminalModelLinkTests` 4, `GlassModelLoadingTests` 1 (each fails without its change); iPhone and visionOS simulators and a Mac probe seen; 0.4.467 on all three, his to try |
| 2026-10-16: iPad under Scale — ⌘+ grows the window (the scene's minimum raised for a moment; ⌘− can't shrink one), scaled text drawn with Core Graphics for the pixels shown (fa7b8b6, 6fd8fc2) | built | `GlassTerminalScaleIPadUITests` 2 on an iPadOS 27.2 simulator in Windowed Apps (each fails without its change); no iPad device; hardware ⌘+ through the Tools menu unverified |
| 2026-10-16 (0.4.466): a Mac terminal window's sidebar adds to the window (D77) — opened or closed, the window grows or shrinks and the terminal keeps its size and place; the app moves the window (AppKit doesn't for a SwiftUI window scene); not for the sidebar it opens with, the overview, full screen | built | `GlassAdditiveSidebarsTests` 2, `MacTerminalSidebarTests` 3 (each fails without its change); `GlassAdditiveSidebarsTests` 5, `MacTerminalSidebarTests` 4 incl. the real window; a window-scene probe app measured ≤1 pt drift; snapped for him on 0.4.464 and 0.4.465, his to try on 0.4.466 |
| 2026-10-17 (0.4.468): with the sidebar opening and closing, "+" and the window title stay where they are (D77, his "keep the + and title fixed"), and no frame shows the window behind the toolbar | the see-through fix built; the held space reverted in 0.4.470 at his word ("let's close the space") | `WindowChromeTests.materialWaitsForTheSidebarToOpen` (fails without its change); a scene probe filmed 0 see-through frames in 5 runs (the original 3 of 3); `MacTerminalSidebarTests.toolbarStays` went with the reverted hold; his to try |
| 2026-10-17 (0.4.469): no gray line at a terminal window's sidebar edge (AppKit's divider transparent, our hairline hidden; other windows unchanged) | built | `WindowChromeTests.sidebarEdgeDrawsNoLine` (fails without); probe pictures: no line at rest or in any animation frame, nothing see-through, the edge still drags; his to try |
| 2026-10-16: a file dropped on a terminal has its path typed, or the drop says why not; a waiting paste review no longer turns drops away; every drop step logged (`terminal-drop`) (389e1f9) | built | unit (fails without its change); the owner's own check of his running app not yet made |
| 2026-10-17 (0.4.471): every sidebar move of a terminal window, and the terminal width held meanwhile, written to the log (`com.glasspowertools`/`sidebar`) for the open 6 pt strip | built | log lines read back on the Mac; the strip itself is open (Known and open) |
| 2026-10-17 (0.4.472): a deleted machine and a removed service stay that way across devices — found documenting sync: the merge's second pass revived every set-up service no live record held, so a deletion was never sent (the deleting device adopted the account's older copy) and a device that heard of one sent the machine back; Remove Service the same. Now a service a tombstone names went with its machine (`deleteHost` keeps them on it; a fold moves them out), and a copy is revived only from a record that ended deleted (d61271a) | built | `GlassCatalogMergeTests` +5, `D19SyncPublishTests` +2 through the model and catalog (each fails on the old merge); shell 314; the 2026-09-21/28 fold cases unchanged; not yet seen across two devices |
| 2026-10-17 (0.4.472): unsaved editor changes never lost without asking — a Mac window asks about each changed document before it closes (`GlassWindowCloseGate`, the terminal's delegate-forwarding technique, in GlassConnectionUI); a Mac quit asks "Quit without saving?" and Cancel goes to them; iPad and Vision Pro keep a dismissed window's workspace with its changes, listed in Active; Active, All Windows and the Mac's overview ask before ending a session with unsaved changes (`GlassOpenSession.unsavedChanges`) | built | `GlassWindowCloseGateTests` 2 (a real window, SwiftUI's delegate forwarded), `GlassEditorSessionLifetimeTests` +2, `GlassOpenSessionTests` +1, `MacQuitWithUnsavedChangesTests` 3; each behaviour fails with its fix undone; the Mac's walk through several documents is his to try |
| 2026-10-17 (0.4.473): All Windows in light mode on iPhone and iPad — a terminal's card on its theme's own canvas (the window's opaque page), its name, × and mark in the theme's light or dark (`GlassOpenSession.backdrop`); his screenshot showed green text on the white sheet | built | `TerminalActiveListingTests` +1 (fails with the scheme dropped); iOS 27.2 simulator captures, light before and after, dark after; on his iPhone, his to look at |
| 2026-10-17 (0.4.474): Your Library counts connections on all devices (D81) — each device's name and per-day counts per machine and kind through iCloud's key-value store, All Devices then a device menu, Settings ▸ General ▸ This Device | built | `GlassUsageSyncTests` 6 (two fail with their change undone); shell 321; iPad Pro 13-inch simulator capture ("145 connections on 3 devices"); not yet seen across his devices |
| 2026-10-17 (0.4.475): no gray line in database and desktop windows either, at his word — a database window's sidebar edge as a terminal's (AppKit's divider transparent, the hairline hidden), and a desktop window, which has no sidebar, without the hairline down its leading edge (929a183) | built | `DatabaseWindowEdgeTests`, `DesktopWindowEdgeTests` (5 and 2 issues with the fix taken out); connection UI 53, layers 53, desktop 223, database 327; the screenshot VM's pictures: no divider or hairline, only the system glass sidebar's rim (as in a terminal) and the window border; Mac on 0.4.475; iPhone and headset unreachable that night (CoreDevice 4016), and on 0.4.475 from 2026-10-18 (installed, `devicectl` reads 0.4.475 on both) |
| 2026-10-18: the site's pictures at his word — Vision Pro above the fold ("we can't claim vision pro first and feature a mac interface"), every window at Opacity 78%, Glass 50%, Medium with Connections closed, all four services on Vision Pro and the Mac (the Mac's four-at-once picture taken, then dropped at his word: it repeated the four service pictures below it), tmux session transfer (Active) and workgroups that come back, and btop in the terminals (a demo screen drawn for the window's size) | built (DEBUG-only demo code; no shipped change) | `swift test` for GlassShellTests and GlassTerminalTests passes (877 and 321 tests); each picture looked at; the site builds and its pages checked in the browser; the visionOS four-window arrangement tried and dropped (techContext, "The macOS screenshot VM"); not deployed |
| 2026-10-18: the first TestFlight upload, 0.4.479 (479) for iPhone/iPad and Vision Pro (`Tools/Release/release-testflight.sh`), built with the released Xcode 27.1 after App Store Connect refused Xcode-beta's | uploaded | both uploads "succeeded" per xcodebuild; the dry run's checks passed for the app and its widget on both platforms (App Store profiles, production push and iCloud); processing, the encryption answer and internal testers are the owner's in App Store Connect; not yet installed from TestFlight |
| 2026-10-18 (0.4.478): GPLv3 with a contributor agreement (D82), chosen before the first publication; Settings ▸ About, the notices, the README, the guides and the site say so; a sweep of every tracked file, the memory folders, the built, staged and live site and the promo's source left only third-party MIT credits and dated notes | built | installed on the Mac, iPhone and headset, each reads 0.4.478; the Mac binary carries "GPLv3 · © 2026" and no "MIT ·"; no new Mac crash reports; the Mac's sync reads 25 records from production, nothing to change; the promo's rendered videos still show "MIT licensed" until re-rendered |
| 2026-10-18 (0.4.477): every build uses iCloud's production database (`com.apple.developer.icloud-container-environment` from `GPT_ICLOUD_ENVIRONMENT`, Production), so the owner's devices and a released copy share one library; the owner deployed the `Host` record type to production first; the release script refuses a build that isn't Production. The Mac carries its Sparkle key | built; the Mac moved | the Mac's first sync on 0.4.477 published all 25 records (8 machines, 15 services, 17 deleted) and its next read 25 back with nothing to apply or send (the catalog-sync log); a backup of the library from before is in the owner's working folder; installed on the Mac, iPhone and headset, each reads 0.4.477; no new Mac crash reports; the iPhone's and headset's first syncs against production are his to open |
| 2026-10-18 (0.4.476): a crash in database and diagram windows on the Mac — `MacDatabaseWorkspaceWindowPolicy.apply` runs on every workspace update and set window properties to the values they had, which still notifies observers; in the screenshot VM one notice reached SwiftUI's hosting view mid-teardown and crashed in AttributeGraph (`LazyPreventsWindowDragFeature`, from `isMovableByWindowBackground`). It now sets only what differs (5c567dd) | built | `DatabaseWindowEdgeTests.applyingAgainTellsNoOne` (six properties notified again without the change); GlassDatabaseTests 328; installed on the Mac, iPhone and headset, each reads 0.4.476; no new Mac crash reports |
| 2026-10-17: the site in the family's look (AudioPaper's, as Glass Project and AutoPaper use it) — warm dark first, the icon's red, pill buttons and nav, the icon over the name and tagline, a facts line; the real app in pictures: six Mac windows in dark and light from a headless macOS VM (`Tools/Screenshots/macvm`, `site_shots.sh`), Vision Pro, iPad and iPhone from the simulators (`device_shots.sh`) | built | site builds (7 pages, 39 help pages, links checked); looked at in a browser in dark, light and at phone width (no sideways scroll); every picture looked at for anything personal; not deployed (his step) |
| Database Local Network and tunnel limits closed: tunnels keep their own connections (D69) | decided | sshd_config(5); OpenSSH reports of multiplexing lag |
| 2026-10-18/19 (0.4.481–483): the iPhone Duo pass (six fixes), the accessibility audit (five naming fixes), the largest text sizes (rows stack, bars one line with the Large Content Viewer, names wrap), the terminal's maximum 28 pt, grid and terminal text following the system size (a switch each, this device's), the iPad editor's wider file list | built | unit (`GlassSystemTextSizeTests`, `DatabaseGridMetricsTests`, settings sync), UI (`LargeTextUITests`, `AccessibilityAuditUITests`) on iPhone and iPad simulators; Duo simulator; the iPad terminal-size UI test's measure is unreliable |
| A paste of text a terminal program wrapped is joined again; "Join Wrapped Lines" in the paste review, remembered; one joined line skips the review (2026-10-19) | built | unit (`TerminalWrappedPasteTests` 14); `TerminalPasteUITests` not yet passing (iPhone step 2, iPad step 3) |
| Mac Terminal Overview no longer lists a window's own Connect terminals as "open elsewhere" (2026-10-19) | built | unit (`MacWorkspaceTests`, red without the fix); device (Mac, 0.4.481) |
| tmux tabs as control-mode clients (D83, 2026-10-19): the terminal keeps every line, its own scrollback, selection and mouse; remote `-CC` on the SSH PTY, local `-C` on pipes; history read back on attach; tmux < 3.2 attaches as before; `terminalTmuxControlMode` NO turns it off | built | unit (`TmuxControlClientTests`, `TerminalTmuxControlSessionTests`), live (tmux 3.8 on the Mac, PTY and pipes; the app's local runtime: 900-row burst, 2,000-line reattach; the Linux test VM's tmux 3.6 over SSH, 2,150 of 2,150 lines); device (Mac 0.4.483: 26 local tabs reattached as control clients). The app's interface against tmux on iPhone not yet seen |
| Reattaching tmux tabs is quick again (0.4.483): the screen reader's text read the whole buffer at every scrolled line, O(n²) in the history (15.3 s for 2,000 lines; the Mac's 26 tabs held the app ~15 s after launch) | built | unit (`TerminalBufferTextTests` against the whole-buffer read), live (`reattachWithHistory`, 15.3 s without the fix); device (Mac: 27% CPU 8 s after launch, 9–14% idle, against 100% then 20–30%) |
| Mac terminal renderer measured: Core Graphics kept (2026-10-19) | decided | Release benchmark of SwiftTerm 1.20's Mac view (`techContext.md`, Terminal renderer): Metal saves 3–31% CPU energy on the current Space, costs more with other GPU work, executes 32–40% more instructions; its GPU time unmeasurable per process |
| Terminal looks (D84, 2026-10-20): backgrounds behind the text (picture with blur/pixelate/tone, Digital Rain that quickens with output, Synthwave, Phosphor Screen), phosphor text palettes (a colour filter, so 24-bit colours follow), text glow, Start From looks, a readability scrim and a per-pixel brightness ceiling; Mac Exposé and overview pictures carry the look | built (experiment) | unit (`TerminalLooksTests` 13), macOS VM captures of every look, the runtime palette switch and an amber Exposé card; device (Mac, 0.4.484–487: the owner); iPhone/iPad/Vision Pro built, not looked at |
| 2026-10-20 (0.4.490): Your Library counts time in use (D87) — each minute with input or output counts for its machine and kind (terminal output and typing, database queries and table changes, desktop input; a Mac tab's local shells too), kept 90 days, synced per day with D81's counts under the library's ids; the overview opens on hours per day, Most Used by time, Connections beside it | built | `GlassTimeInUseTests` 9, `GlassUsageSyncTests` +2, `TerminalActivityTests` 1 (a real hosted terminal), `ActiveRowFocusTests` +1, `DesktopActivityTests` 1; five fixes seen failing undone; shell 341, terminal 953, database 335, desktop 224, editor 172; his to see on the Mac |
| 2026-10-20 (0.4.491): a new local tmux tab's cursor on its prompt — the pane restore counts the cursor up from the screen's last line, a resize during the start reaches tmux, and so does a font size change | built | `TmuxControlClientTests` +2, `LiveTmuxControlResizeTests` 1 (live, private server), each red without its fix; terminal 956; his to see on the Mac |
| 2026-10-20: the first Mac release, 0.4.491 — Developer ID, notarized, Sparkle feed live; GitHub release v0.4.491; TestFlight 491 for iPhone/iPad and Vision Pro; site and help current with D83–D87 and six looks pictures | released | the dmg passed Gatekeeper ("Notarized Developer ID") and ran from a quarantined download in the VM; published files match their checksums; 90 site files match the build; TestFlight has no tester group yet |
| 2026-10-20 (0.4.492 – 0.4.494, released as 0.4.494): Scale Text on the Mac's own terminals; the folder button's Open in Editor (the machine's project holding the folder, else a new editor), on the Mac a split button with an arrow as + has (0.4.493), since a Mac toolbar never shows `.contextMenu`; iCloud signed out says so | released (Mac 0.4.494, TestFlight 494) | `GlassCatalogSyncWordingTests` 3, `MacLocalPaneScaleTests` 1 (a real pane and shell), `LiveTmuxControlResizeTests` +1, `GlassEditorProjectLibraryTests` +1; each red without its change; the arrow's menu, Open in Editor and Scale in the VM; shell 344, terminal 961, editor 173 |
| 2026-10-21 (0.4.495): four more looks (Coding Agent — the running agent's mark in its colour, with AutoPaper's smoke while it works; Aurora; Starfield; Blueprint); Keys on Vision Pro (no keyboard accessory there); the iPhone Duo half open — laptop pose: terminal above the fold, its bar in the strip above the keys, the accessory withheld; book pose: controls off the fold | built | unit (`TerminalLooksTests` +4, `TerminalAgentBackdropRenderTests` 2, `GlassDeviceFoldTests` 5; each new rule seen failing when broken); visionOS UI (`GlassTerminalOrnamentUITests` 5, Keys sending ESC and ESC [ A, seen in a temporary log); the Duo simulator, every pose, by XCUITest taps (five rounds; three defects found and fixed: a late fold, controls' identifiers, the fold read in a view the keyboard shortened); the VM's pictures; terminal suite 964 (six timing tests failed under load, all pass alone) |
| SQL in a terminal opens in the query editor (D85, 2026-10-20): Mac right-click, statement extent, the machine's databases (a menu when several), table found and opened beside the SQL | built | unit (`TerminalSQLDetectorTests` 6, `MacTerminalContextMenuTests` +4 through the real view, `SQLTableReferencesTests` 4); not driven against a real database yet |
| Mac tab rows show each terminal's tmux session, machine, program and folder as a tooltip (2026-10-20) | built | unit (`MacWorkspaceSessionHelpTests` 3); not hovered on screen |
| This Mac knows its own library machine (D86, 2026-10-20): linked by its pinned SSH host key, offered by an address, or set in the machine's editor; one row; its Terminal opens a local shell; its databases are This Mac's (SQL from a local tab); Active lists its sessions once; no Screen Sharing to itself | built | unit (`GlassThisMacLinkTests` 6, `GlassThisMacTests` 3, `TerminalActiveListingTests` +1; fold and Connect seen failing without); device (his Mac linked itself by host key on 0.4.488) |

**Test audit, 2026-10-24 – 25** (`tasks/2026-10/2026-10-24_test-audit.md`): the whole package, 3,113 pass, twice,
with the live servers; 14 skips, each a decision listed for the owner. Vendored: swift-nio-ssh 367, Citadel 62,
RDPKit 1,030. UI: every UI test on the iPhone 17 Pro and the folded iPhone Duo simulators (79 each); the full runs'
only failures were faults in the tests, fixed and each shown failing first. Not run: the iPad on the latest build,
the unfolded Duo, the Mac UI tests.

Suites run 2026-10-17 with the screen unlocked: connection UI 51, terminal 873, shell 307, all passing; on
2026-10-16 editor 169 and desktop 222. On 2026-10-13: database 321, DBKit 28 (the whole package not re-counted since). Earlier: about **1,790 tests**. The last full run with the screen unlocked passed (1,777, early
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

Also done: README, SECURITY, CONTRIBUTING and a building guide; 35 help pages audited from the code (39 by
2026-10-17, when all of them, the README and the memory bank were checked against the code again and RELEASE-NOTES.md added),
the site and its generator (live since 2026-10-18); Sparkle for the Mac with a release script (never run); and
the defects the help audit found (`tasks/2026-09/2026-09-27_help-site-and-updates.md`).

Remaining before a first public release: the owner's release steps (the Developer ID
profile, CloudKit's production schema, the first release run; the Sparkle key and the site are done), the behaviour findings listed in `activeContext.md`, and
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
- **Vision Pro:** runs the same build as the Mac and the iPhone (0.4.471 on 2026-10-17); the owner has used
  desktops, trackpad scrolling and the editor's toolbar on it. Not every change since has been gone through on it
  (the inventory's B-V1 lists what is owed).
- **Database scroll edge on the Mac** (hard top edge so content does not print through the
  toolbar): built, not seen — no screen capture without screen-recording permission.
- **The D26 two-device acceptance run:** add a host with a key on one device, connect from another
  without re-approving trust.
- **UI tests cannot reach a desktop surface:** it needs a live fixture the simulator runner does not
  receive. Database UI tests do now: on iOS they run against the test VM's MySQL and PostgreSQL, with the
  settings from a file kept outside the repository (2026-10-24).
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
- **A server file over 64 MB can't be opened (found 2026-10-17):** the SFTP reader stops at 64 MiB and throws
  `GlassPortForwardError.unavailable` (`GlassTerminalCapability.swift:1242,1345`), so Download and View never
  succeeds and the message blames a missing Terminal service (`GlassCapability.swift:194`).
- **Smaller editor, database and desktop defects found for the help (2026-10-17):** bare dotfiles (`.bashrc`,
  `.zshrc`, `.profile`) get no Shell colour (no path extension, `GlassEditorModel.swift:194`); a timed-out regex
  shows "Invalid pattern" (`GlassEditorWorkspaceView.swift:976`); the 64 MB limit prints as "67.1 MB"
  (`GlassEditorViewer.swift:91`); the database Tunnel row says "this machine's Terminal service" for another
  machine's tunnel (`DatabaseDetailView.swift:229`) and reconnect failures skip the plain-words rewrite
  (`DatabaseSessionManager.swift:435`); the desktop size message leaves out the pixel total
  (`DesktopServiceDraft.swift:165-169`). Reported by audit agents, not re-read: a missing file reported as "is a
  folder" (`GlassEditorWorkspace.swift:353-360`); F2 and F4 absent from `MacKeyboardMapping.swift:240-249`.
- **A Mac local terminal doesn't scale (D75 gap):** `TerminalScaling` is applied only in `TerminalWindowView`
  (`TerminalWindowView.swift:278`), which the Mac's SSH panes use; `MacLocalTerminalPaneView` never scales.
- **Found reading the code for the help (2026-10-17), small:** jump-host progress and reconnect attempts go to
  `session.output`, which no view reads (`SSHConnection.swift:371-376`); the service row's More menu is always empty
  (`GlassShellLibraryView.swift:540-556`); the Add sheet's title follows the first kind, not the chosen tab; Delete
  Workgroup says "this device" though the deletion syncs (`TerminalWorkgroupsView.swift:113-124`); Settings ▸ General
  says "reset them in Settings" but nothing calls `resetPreferences()` (`GlassShellPreferences.swift:88`); Vision
  Pro's empty Collections says "in its details" where collections are set in Edit
  (`GlassConnectionLibrary.swift:489-490`).
- **Release script and the Mac's newer extensions (found 2026-10-17, documentation pass):**
  `Tools/Release/release-mac.sh` checks the widget extension's signature, hardened runtime, sandbox and App Group
  (lines 100–119) but not the Finder, Quick Action, Share or File Provider extensions added on 2026-10-13. The File
  Provider spike's `GlassPowerToolsFiles.appex` is embedded in every Mac build, inert, with network and keychain-group
  entitlements: keep it inert, or remove it, before the first release (`2026-10-13_file-provider-spike.md`).
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
- **Vision Pro terminal selection (2026-10-15):** the owner's "still broken wholly … with tmux" was tmux 3.8 turning
  its mouse on by default; with it off he confirmed selection works. 0.4.455 on (2975ace, f2fde40) makes the headset
  independent of it: a pinch-drag scrolls when tmux has the mouse, and selection works as Apple's text does. Not yet
  tried by him on the headset; each hold, pinch and selection change is written to the app's diagnostics file
  (`terminal-selection` lines in `screen-sharing.log`) — copy it off the headset after he tries.
- **A 6 pt see-through strip between a terminal window's sidebar and its terminal as the sidebar opens**
  (2026-10-17, the owner: "it's what causes the shift"): not reproduced by the scene probe; 0.4.471 logs each move.
  Read his toggles' log before changing anything (`tasks/2026-10/2026-10-16_additive-sidebars.md`, last section).
- **The sidebar edge without a line** is the terminal window's only; the database and desktop windows keep theirs
  (offered to the owner, unanswered).
