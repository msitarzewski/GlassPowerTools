# Backlog inventory — 2026-10-12

**Owner's ask:** "a full inventory of all future state and future features and requests and backlogs", then
"we should also examine glassdb and glas.sh and glassdt — their lists may not have made it forward".
**State:** inventory complete; nothing in it is approved or scheduled by being listed. The owner picks.

## How it was taken

Eight read-only sweeps, each item checked against the current code and notes before being called open:
this project's `activeContext`, `progress`, `decisions` (D1–D68), all 91 task notes, code markers, public docs
and site, the private agent memory, and GitHub (no repository yet); then the three original apps (glas.sh,
glassdb, glassDT) and the three absorbed packages (GlassEditorKit, GlassConnectionKit, GlasSecretStore),
including their uncommitted and unpushed local branches. Spot-checked by hand: B-X1, B-X3, B-X25, B-F44,
B-H1, B-H9, and the rule 61 find below. Items found finished are left out; IDs are for picking ("do B-X1").

**Fixed during the sweep** (committed): the VNC setup warning (262ba7a); SECURITY.md's VNC paragraph; a real
database name in `GlassCommandPaletteTests.swift` (rule 61; it is still in history from 6425ac5).

**Only on this Mac:** glas.sh's and glassdb's last backlogs (2026-09-05/07) are uncommitted edits on their
`agent/keyboard-command-center` branches, and glas.sh's SSH-key backlog is the unpushed commit 634d97c on
`agent/ssh-key-source-backlog`. Their content is now in section 5.

## 0. Recommended first

1. **B-X1** — the editor reads any local file whole on the main thread (a FIFO hangs the app). A protection
   the editor kit had, bypassed by the new editor.
2. **B-F44** — iPhone Duo ships 2026-10-23 and the app refuses windows on a phone.
3. **B-H9** — the first weekly dependency check's three failures, unread.
4. **B-H1 – B-H3** — public pages that say less than the app does.

## 1. Waiting on the owner's decision

| ID | Question | Raised | Where |
|---|---|---|---|
| B-Q1 | D46 pinch gestures on Vision Pro desktops (palm-up pinch-drag scrolls, pinch-and-hold right-clicks) — "Shall I build it?" | 10-06 | decisions D46 |
| B-Q2 | D50 This Mac's terminals from other devices — needs the OK to add a key to `authorized_keys` | 10-08 | D50 |
| B-Q3 | D53 workgroups as tmux control-mode sessions, with a sessions browser per host — the spike was never run | 10-08 | D53 |
| B-Q4 | D63 light/dark on Vision Pro: a theme pair per window or by Focus; hide Canvas Material there (`SettingsView.swift:963`) | 10-11 | D63 |
| B-Q5 | Bonjour `_rfb._tcp` for availability (adds the Local Network prompt) | 10-11 | D65 |
| B-Q6 | New SSH tabs start in the remote folder (W37 did it for local terminals only) | 10-11 | 10-08 plan note |
| B-Q7 | Title ornament sizes: terminal ≈29 pt, desktop ≈37 pt | 10-10 | 10-08 plan note |
| B-Q8 | Desktop canvas corners rounded or square; desktop default Glass 25% or 100% | 10-10 | 10-08 plan note |
| B-Q9 | Database split view or own glass; the no-split treatment for Connections, editor and Files | 10-10 | activeContext |
| B-Q10 | Editor on the headset: ⌘S for Save off the Mac (the database owns it); 13 pt default size; text at Opacity 0 loses syntax colour | 10-09 | 10-08 plan note |
| B-Q11 | Delete the legacy `SFTPRemoteEditorView` sheet (recommended — but see B-X2 first) | 09-17 | activeContext |
| B-Q12 | Local editor projects listed on devices that cannot open them: hide or keep | 09-27 | help audit |
| B-Q13 | Headset tab bars expand together across windows: a segmented control for the database table tabs; file the Feedback | 09-29 | activeContext |
| B-Q14 | Undescribed: "desktops in Active a little wonky" (09-28); remote desktop slow on the headset — connecting or live (09-29) | 09-28 | activeContext |
| B-Q15 | "Settings not saved" on a new server — which sign-in method, what Edit shows | 09-23 | 09-22 note |
| B-Q16 | Should a restored SQL draft announce itself; should the audit log record primary-key values | 09-12 | 09-12 notes |
| B-Q17 | File ▸ Save beside Close (D37) | 09-25 | D37 |
| B-Q18 | glassDT parity leftovers: desktop window placement on visionOS; VNC shows size fields; RDP and VNC default names collide; do ⌘K/⌘O/⌘T reach the remote | 09-27 | parity audit |
| B-Q19 | "Paste Text" in the terminal's right-click menu — meaning to confirm (Paste Escaped Text?) | 10-09 | 10-08 plan note |
| B-Q20 | D29 Uninstall Glass Power Tools… (proposed, not approved) | 09-16 | D29 |
| B-Q21 | `.vnc` as its own service kind and credential record (a CloudKit schema change; password-only VNC uses a placeholder account) | 09-10 | D-header, remaining-work plan |
| B-Q22 | RD Gateway as a "Stage 4.6" — never answered | 09-13 | stage-4 plan |
| B-Q23 | The update zip: on the site or on GitHub Releases | 09-25 | D38 |
| B-Q24 | Screenshots: paused until the app is judged on the headset | 09-27 | screenshots note |
| B-Q25 | The "SFTP interface ideas to make editing shine" — never written down | 09-10 | decisions header |
| B-Q26 | The absorbed packages' folders and repositories: keep, archive or redirect (they still read as live packages) | 09-13 | — |
| B-Q27 | The pre-publication scrub: still wanted, given fc7653e/47b7df8/107f1be stay and 6425ac5, ca2e62b are in history | 10-12 | activeContext |
| B-Q28 | The weekly check's SwiftTerm v1.99 (Ghostty-based IO): follow it, or stay on 1.20 | 10-12 | B-H9 |

## 2. The owner's release steps

- **B-R1** Sparkle EdDSA key (`GPT_SPARKLE_PUBLIC_KEY` is empty; `release-mac.sh` refuses to run).
- **B-R2** Developer ID certificate and profile with the CloudKit container, App Group and Keychain group, and
  probably one for `<bundle id>.widgets`; `GPT_APS_ENVIRONMENT=production`; sync checked on a Developer ID build.
- **B-R3** The first `release-mac.sh` run (notarize, appcast).
- **B-R4** Deploy the site with the feed served uncached; one hosting-side change pending (private runbook).
- **B-R5** Create the GitHub repository; turn on private vulnerability reporting (SECURITY.md relies on it).
- **B-R6** The history rewrite (if wanted, B-Q27), then the first push.
- **B-R7** TestFlight, then the App Store, for iPhone, iPad and Vision Pro (D38 approved, not started): no
  tooling, no app privacy manifest, no `ITSAppUsesNonExemptEncryption`, no listing. **RDP and H.264/HEVC
  licensing clearance** before distribution (glassDT research; not on any list).
- **B-R8** Deprecate glas.sh, glassdb.app and the three package repositories with redirects; close glas.sh's
  draft PR #36.
- **B-R9** Upstream contributions drafted, not sent: swift-nio-ssh N1, N5, N6; Citadel advisory C11, C6.

## 3. Defects

- **B-X1** Local files are read whole with `Data(contentsOf:)` on the main actor
  (`Sources/GlassEditor/GlassEditorFileAccess.swift:90`): no non-regular-file refusal, no 8 MB ceiling. A FIFO
  in a project hangs the app; a link to `/dev/zero` reads until memory runs out. Remote reads are uncapped
  too (`SFTPSession.swift:226`). The kit's `DocumentLoader` fix (M-4) is used only by the legacy sheet.
- **B-X2** The new editor checks for an outside change only when saving, not when its window comes forward;
  only the legacy sheet does (deleting it, B-Q11, would lose the behaviour).
- **B-X3** A deleted SSH key quietly becomes the library's first key when the server's form opens, and a key
  added from the form is not selected (`ServerFormViews.swift:437`, `:597`).
- **B-X4** Drag-select stops at the screen in tmux history on the Mac (Select All takes the history, ec226f9).
- **B-X5** Losing a shared SSH connection marks one terminal lost; the others just see their shell end.
  Database and desktop tunnels connect outside W21's pool.
- **B-X6** Colour distortion during motion on RDP (AVC444 partial regions / LC1 path), reported by the owner on
  the GNOME host on 09-08 and never fixed or carried forward; glassDT's plan was expected-pixel tests and an
  AVC420/legacy picker (B-O9).
- **B-X7** RDP on Vision Pro asks for about twice the pixels (Automatic uses displayScale); every RDP frame is
  copied whole (only the Metal upload is partial).
- **B-X8** Regex find runs synchronously on the main actor with no limit (H-3; catastrophic backtracking).
- **B-X9** `AtomicSaver` parent-directory race (M-2; needs `O_DIRECTORY|O_NOFOLLOW` + `renameat`).
- **B-X10** The database breadcrumb is built from `tabState.displayed`, previews included — the owner's
  "weird stuff happens when navigating" (glassdb, 08-20), unchanged (`DatabaseWorkspaceView.swift:1089`).
- **B-X11** Table tabs leave Format, Execute, History and Saved Queries disabled (handlers come only from SQL
  documents; `DatabaseWorkspaceView.swift:1285`).
- **B-X12** Grid rows painted above the results header (glassdb screenshot, 09-02) — not rechecked here.
- **B-X13** Connect failure suggests Local Network access for any failure on a local-looking host.
- **B-X14** `configurations(ofKind:)` drops unreadable records without a log line; `replaceAll` per kind can
  still delete another device's record from a stale list.
- **B-X15** "FocusedValue update tried to update multiple times per frame" at Mac launch.
- **B-X16** Tab records lost after the crashes of 10-08 — partly explained, path B fixed.
- **B-X17** "display index not found 1/4" in the Mac agent's log on every 003.889 session.
- **B-X18** The ECDSA error text contradicts itself (`SSHTransportError.swift:44` vs `:77`).
- **B-X19** visionOS library search unreachable through accessibility; schema sidebar rows have no button trait.
- **B-X20** The database workspace window can shrink when its id is not found (`GlassDatabaseScenes.swift:35`).
- **B-X21** Vendored Citadel `DH-Helpers.swift:82,117,264` keep the `moveWriterIndex` placeholder pattern patch C2
  fixed elsewhere; C6 overloads drop options (the app does not use them). S6 (credentials not zeroed) and S7
  (Keychain read before the host key is checked) need a Citadel change.
- **B-X22** Remote listing never checks `hasSafeName`; project reach ignores pinned host keys (both low).
- **B-X23** Older device builds strip workgroups' tmux names when they re-save — keep devices on one build.
- **B-X24** Insert Path does not bring the Mac window forward; "Files failed once from a cold app" (never
  reproduced); the Mac app crashes on an accessibility snapshot after the connection-failure alert (XCTest only).
- **B-X25** No sleep or wake handling anywhere (`NSWorkspace` sleep/wake unobserved; scene phase only releases
  input). The lifecycle rule asks for it.
- **B-X26** The first terminal window opened too small on Vision Pro (glas.sh, 08-01) — look again on the headset.

## 4. Features: requests, approved and proposed

**Terminal and SSH**
- **B-F1** SSH agent sign-in and agent forwarding (deferred since glas.sh's v1.1; `.agent` throws).
- **B-F2** Keyboard-interactive (MFA) and SSH certificate sign-in (glas.sh's assessment target).
- **B-F3** ECDSA keys imported from a file (P-256 works only in the Secure Enclave).
- **B-F4** "Use from Disk on This Device" beside Import into Glass: a device-local key file reference that never
  syncs, with moved/missing/changed states (glas.sh 634d97c).
- **B-F5** SFTP folders: upload, download, drop; delete non-empty folders.
- **B-F6** Saved port forwards (today they last the session); SSH config import of Match, Include, negated and
  wildcard hosts.
- **B-F7** Recordings: a player, export and a retention policy (list and delete only today).
- **B-F8** Shell integration: OSC 133 command blocks, exit status, semantic history, file references.
- **B-F9** Apple Intelligence over scoped session data: explain selected output and session metadata through
  bounded tools; never read all scrollback, reveal credentials or run what it writes (owner's family backlog, 09-05).
- **B-F10** Large-history performance: bounded ring storage, optional disk history, a renderer audit per
  platform (Vision Pro is on Core Graphics), a shared benchmark matrix ("BBEdit-like").
- **B-F11** Terminal conformance corpus (vttest, ncurses, Vim, reflow, graphemes, RTL, OSC 8/52/133, mouse).
- **B-F12** Engine evaluation: SwiftTerm against libghostty — now concrete, SwiftTerm v1.99 is Ghostty-based (B-Q28).
- **B-F13** D44 stage 2: "open the same set here" on another device, databases included.
- **B-F14** Network/Tailscale as a library panel (the owner's pass-2 list, 09-13).
- **B-F15** A swipe switcher for iPhone workgroups ("swipe later"); Zellij as a second multiplexer (low).
- **B-F16** A saved workgroup reopens on the display and frame it last used; an idle policy for overview
  windows watched on a second display; on Vision Pro, the overview's activity glow and focus-on-output.

**Databases**
- **B-F17** Grounded Apple Intelligence Q&A over a database: read-only, bounded, cancellable investigation with
  supporting SQL and counts (owner's example: "Which errors in bravo are highest priority?", 09-05). Also:
  dialect-aware prompts, whole-schema context (freeform SQL gets none), surface the unused `summarizeQuery`.
- **B-F18** Large data: a million rows, rows and columns virtualised, bounded caches, keyset paging, spill to
  disk for export, benchmarks ("BBEdit-like responsiveness is an acceptance goal", 09-05); the grid's
  `NSTableView` option and the unmeasured 120 Hz target.
- **B-F19** Spreadsheet-style grid: inline cell edits with a staged-changes panel and SQL preview, rectangular
  selection and fill, a raw WHERE filter, state kept across refresh. (The 09-23 grid note wrongly lists some as existing.)
- **B-F20** Transaction controls: auto-commit, Begin/Commit/Rollback, an in-transaction badge, a warning on close.
- **B-F21** Multiple result sets for a script; find and replace in the SQL editor; alias-aware completion and
  unknown-name lint; Tab-completion on an iPad keyboard.
- **B-F22** Visual Explain plan (tree, costs, full-scan warnings, compare).
- **B-F23** Streaming results and export; export a whole table, database or server; `INSERT … ON DUPLICATE KEY UPDATE`.
- **B-F24** Schema work: Create Table, Create/Drop Database, rename table, views/functions/triggers (viewing
  first, glassdb's "Next Up"; MySQL views are not told apart from tables); PostgreSQL CREATE TABLE text;
  SQLite foreign keys by rebuild; other databases on a PostgreSQL server (today: schemas only).
- **B-F25** Server administration: variables, status, process list with Kill, users and roles; dashboard
  uptime, threads, slow queries, unindexed tables, growth.
- **B-F26** Schema comparison with migration SQL; backup and restore; test-data generation.
- **B-F27** Saved queries with folders and tags, bookmarks, and sync (saved queries and history are device-local).
- **B-F28** Run SQL documents from the editor (approved 09-10); a "run script" command; SQL-document writes in
  the Mutation Log; a warning that Cancel drops the connection while MySQL keeps running the statement (D11).
- **B-F29** Off the Mac: database menu commands on iPad, drag and drop (files into import, a table into its own
  window), the record editor as an inspector; workspace tabs kept on a phone (D31's named fix).
- **B-F30** Client-certificate TLS; an in-app log viewer; duplicate a connection; paste adding rows.

**Remote desktops**
- **B-F31** Remote background detected through the host's SSH (GNOME/KDE, Windows `IDesktopWallpaper`, macOS),
  feeding the existing mask; the manual picker as fallback. An owner requirement in glassDT ("pairing should
  automatically detect the remote background settings"), never carried; its blocker is gone.
- **B-F32** A graphics mode picker (Automatic / AVC420 / Legacy), the escape route for B-X6.
- **B-F33** Servers that cannot resize: offer Resize to Window, Scale to Fit and Actual Pixels honestly (both
  tested RDP servers advertise no display control).
- **B-F34** VNC and RDP through an SSH tunnel, with an encrypted/unencrypted indicator in the session; VeNCrypt.
- **B-F35** D42b RDP file clipboard; D42d VNC Extended Clipboard (non-Mac VNC is Latin-1 text only).
- **B-F36** High Performance gaps: live resize of the virtual display, a second virtual display, an H.264 fallback.
- **B-F37** RDP breadth: multi-monitor, microphone and camera, drive/printer/USB redirection, RD Gateway (B-Q22),
  AVD/Entra; dragging files onto a desktop; an `.rdp` document type.
- **B-F38** Desktop windows restored on relaunch (Mac, Vision Pro); a Domain field on the connect-time sheet;
  the VNC forward button; resolution change on multi-display VNC.
- **B-F39** VMs and containers as desktops on This Mac (D8, approved); Observe mode as a "watch" feature (idea).
- **B-F40** Remote desktops in Workgroups, with grid and carousel, never closing a session on a view change
  (glassDT's agreed contract) — the "terminal, database and desktop together" workspace AGENTS.md calls the
  differentiator; Workgroups are terminal-only today.

**Editor**
- **B-F41** A remote command seam: project-wide `rg`, git status in the tree, server-side LSP — with the kit's
  consent design (allowlist, ask per host, a command journal in Settings), never copied in.
- **B-F42** tree-sitter injection (Markdown inline, HTML script/style, PHP in HTML, JSX, fenced code); a real
  TypeScript grammar; CSS, Dockerfile, nginx configs.
- **B-F43** Highlighting off the main thread; TextKit 1 follow-ups (temporary attributes, 1.7 s re-wrap); the
  iPad/visionOS engine measured; the 8 MB/2M-character limits characterised and published.
- **B-F44** iPhone Duo (ships 10-23): `canOpenWindows` refuses `.phone`; compact stacks do not survive a size-class
  change; dragging out of Files is Mac-only.
- **B-F45** Each editor window remembers its size (owner, 09-17: "should persist, per editor window").
- **B-F46** Project-tree ignore list; editor preferences and per-project window settings synced; Close Project;
  Markdown preview that follows by heading, with highlighted code blocks; UTF-32.
- **B-F47** Editor accessibility: VoiceOver reading and selection, dictation, Look to Scroll; the iOS gutter
  starting from the first visible line (M-8; the Mac is fixed); ambient light on visionOS (passes `.unknown`).

**Library, shell and platforms**
- **B-F48** App Intents beyond the widgets: Siri, Shortcuts, Spotlight (opt-in), Handoff; entities for hosts,
  connections, saved queries and tables (planned in glassdb and glassDT, never carried).
- **B-F49** The command palette on iPad, iPhone and Vision Pro; typo tolerance; a configurable shortcut; AI tools.
- **B-F50** Resizable, remembered sidebars on iPad and Vision Pro (owner, 09-13); W33's split gave up resizing.
- **B-F51** Detach a key from a service in the key manager (owner, 09-14); type the name to delete a key in use.
- **B-F52** Files on This Mac; renaming This Mac; service tags; a more playful Active; library export.
- **B-F53** D40's remaining unwind on Vision Pro (`GlassSpatialMetrics` ×24, custom frames, hand-built ornaments);
  Interactive Glass and Material that do nothing on a headset terminal.
- **B-F54** Ideas from the promo video: a resolution readout in the desktop title, a "Host key trusted" pill, a
  "Committed · 1 row" toast, a "Saved to alpha" status, a crimson accent (the asset is empty), Connect-all in an
  arc on visionOS.
- **B-F55** Curved display and a remembered tilt — deferred by the owner when Apple confirmed no API; he asked
  for the decision to be preserved, and it was not carried. The prototype (`GlassSpatialDisplay*.swift`) has no
  product caller; a Feedback request was drafted, never sent. Also Compositor Services / foveated streaming.
- **B-F56** Cross-device credential lifecycle: rotation, revocation, recovery, iCloud sign-out or switch,
  version skew; "still syncing" told apart from "missing".
- **B-F57** Engines in XPC services; glas.sh's UI split into modules; a watchOS companion (deferred until others
  use the product; watchOS is excluded today).

## 5. From the original apps, carried here today

Already folded into the lists above, by source, so the record of where they came from survives:
- **glas.sh:** B-F1, B-F2, B-F4, B-F7–B-F12, B-F15, B-F16, B-F49, B-X3, B-X26; release checks B-T8.
- **glassdb:** B-F17–B-F30 (most), B-F48, B-F49, B-X10, B-X11, B-X12, B-T8.
- **glassDT:** B-F31–B-F33, B-F40, B-F48, B-F55, B-X6, B-R7 licensing, B-T8 (international input).
- **GlassEditorKit / GlasSecretStore:** B-X1, B-X2, B-X8, B-X9, B-F41–B-F43, B-F47, B-F56, B-T7 (CI), B-T9.
- glas.sh hid and retired SharePlay, auto-record, Tailscale auto-discovery and AI session summaries itself;
  nothing tracks them. Listed so they are not mistaken for lost.

## 6. Checks owed on devices and servers

- **Vision Pro:** the W39 orb; tab groups reopen and grid-card drags (W15); W26 title drop; W16 Files window;
  Keep Display Proportions under hand-resizing; High Performance's `hp-decoder-check`; the schema diagram
  volume; the results bar; the Settings ornament; Reduce Transparency; tilt and legibility; a remote project;
  SwiftTerm 1.20; tmux pan scrolling; W21 limits; arrow keys; widgets.
- **iPhone and iPad:** widgets placed and tapped; landscape with the keyboard and the Pro Max layout; tmux pan;
  W11 rename menus (compile-only); W27 sheets on iPad; the schema diagram sheet; a hardware keyboard on
  desktops; a VoiceOver pass on the library and service picker; the Open File security-scope fix.
- **Mac:** widget taps; High Performance, Apple scroll (0x17) and pasteboard with a real Mac; Automatic quality
  on a hotspot; the D64 probe; the database scroll edge; W9 menu bar; W8 multi-tab drag; W20/W27 settings;
  the screenshot-thumbnail drop; a Force Quit of the app while it hosts tmux; Open With from the Finder; the
  launchd host taking over from the pre-D66 server; the macOS 26.0 floor at run time (compile-only so far).
- **Across devices:** D26 two-device acceptance; Stage 3.5 #4/#6/#7 (offline convergence, re-auth, iCloud
  sign-out); favourites and workgroups syncing on real devices.
- **Servers:** RDP with an intermediate CA; resize against Windows; RDP audio on a device; Windows autodetect
  (the test account needs a reset); TightVNC and other VNC servers; a macOS RDP server; GNOME sign-out closing
  the window; Ubuntu Detail scale; PostgreSQL CA-only TLS and an intermediate chain; PostgreSQL arrays; SQLite
  row delete and foreign-key follow; local MySQL/PostgreSQL on This Mac; forwards (local, remote, SOCKS5),
  recording and Tailscale from the terminal UI; a jump-chain forward; the SQL assistant on Mac and headset;
  tmux `-u`/`-text` on an older tmux; the remote name claim from a non-login `sh`; the editor's contrast
  thresholds on a signed device; viewers on a remote file; measured latency, frame rate, energy and memory.

## 7. Known limits, accepted for now

Three database engines; a primary key to edit; a SQLite file opened as a private copy; local shell on the Mac
only; Mac workgroups refuse legacy-algorithm hosts; every "+" in tmux leaves a session running; typed keys in
tmux history act as copy-mode commands; dropped-file limits (`$XDG_CACHE_HOME`, `hardlink@openssh.com`); stale
branches for sessions no tab shows, none for reftable repositories; per-display VNC connections off; a Mac never
reports its own pointer; late clicks while a Mac pushes at interval 0; W33 gave up the system sidebar's
collapse, resizing and VoiceOver landmarks; headset logs unreachable except screen sharing's; synchronizable
Keychain untestable in unit tests; host trust at setup time when host and database are saved together; D22,
D32 and D34's pre-launch assumptions (to revisit when others use the product); no tab drag to a new window
outside every window; a save over a dropped connection cannot tell whether the file was replaced; RDP
excludes Kerberos, RemoteApp, smart cards and UDP by choice.

## 8. Housekeeping

**Stale public docs**
- **B-H1** "At most 1,000 rows" (`site/pages/databases.html:91`, `site/help/database-sql-editor.md:31`): a
  setting from 1 to 100,000.
- **B-H2** RDP clipboard "limited to text" (`desktop-sign-in-and-trust.md:63`, the ledger, `index.html:36`):
  it carries HTML, RTF and images.
- **B-H3** `why.html:56` names only GNOME for Linux RDP (xrdp was tested too); device-check dates disagree
  across the site's pages.

**Stale notes and comments**
- **B-H4** `progress.md`: the headset crash fixed by 32fa481, "Vision Pro runs 0.4.283", the default text
  editor as backlog (built, 28a0b6e), the weekly check "not yet seen". `techContext.md:324` release "not built";
  `systemPatterns.md:96` shortcut table (⌥⌘O gone; ⌘G, ⇧⌘G, ⌥⌘G, ⌃⌘T missing) and `:76` desktops in Active;
  `projectbrief.md:60` App Store as a non-goal (D38 says otherwise); D11 and D39 statuses; AGENTS.md's "must
  pick one floor"; `SQLDraftStore.swift:111`; the 09-23 grid note's feature list.

**Cleanup**
- **B-H5** D26 stage 5: about 1,073 preference keys — 743 `macWorkspaceRestoration.*` never pruned, 228
  `app.glassdb.grid*`, a dead `glassdb.connections`; the `glassdb.*` names; `Application Support/glassdb`; the
  `app.glassdb`/`app.glassdt` loggers; dead `ConnectionEditor.swift` and `createSFTPSession(sharing:)`; legacy
  migrations still running; `HostCatalogDeletionOutbox.swift`; the curved-display prototype (B-F55 first).
- **B-H6** Four session-card designs into `GlassSessionCard`; RDPKit's README, branch names, `ConnectionPreflight`.
- **B-H7** Test pollution: about 1,519 Keychain items and abandoned defaults suites from tests on the real Mac;
  test VM MySQL logging at verbosity 3 and leftover `gpt_live_*` tables.
- **B-H8** Dependencies blocked upstream: tree-sitter 0.27, swift-crypto 5; the mysql-nio fork (upstream PR closed).
- **B-H9** Weekly dependency check, 10-12: 9 of 30 pins behind; swift-log 1.16.1 does not build, swift-nio
  2.104.0 fails one test, SwiftTerm v1.99 (Ghostty-based IO, 250 commits) does not build. Report in
  `~/Library/Logs/GlassPowerTools/`.

**Testing and infrastructure**
- **B-T1** Seeded database and desktop configurations, so UI tests can reach them (none on iPhone, iPad or
  visionOS for databases; none at all for desktops); glassDT's 14 UI workflow tests; the 40-item parity sweep.
- **B-T2** 15 visionOS UI failures predating W33; `testAddServiceCollectsTheAddressOnTheHost` on device; the
  uncommitted `testArrowKeysReachTheTerminal`; the visionOS search test skipped.
- **B-T3** Mac UI tests written and never run (Files header, closing the workspace window, Settings tabs); the
  SSH key Choose File test; Follow Reference "needs a person"; live database reconnect tests disabled.
- **B-T4** Flaky: MockKRDP early authorization (3 in 4), the xrdp probe's resize (1 in 3), the trust broker's
  cancel, the live tmux find, output observation under load, two terminal tests in full runs.
- **B-T5** A full package run with the screen unlocked (last 09-27).
- **B-T6** Stage 3's security pass never recorded; glassDT's hardenings never re-checked.
- **B-T7** CI (GlasSecretStore had a workflow; nothing here — fine until the repository exists).
- **B-T8** Release QA none of the apps closed: OS 26 runtimes, Instruments leak/hang runs, an assistive-technology
  pass, IME/dictation/international layouts/dead keys, a TLS-failure and local-network-denial matrix, a
  dependency advisory scan (OSV).
- **B-T9** The C-scanner review of the nine grammars added after the kit's 08-11 review.
