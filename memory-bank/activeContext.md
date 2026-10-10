# Active context

Where the work is now. Rewritten 2026-09-27; the session-by-session log it replaces is in git
history, and each piece of work's evidence is in its task note under `tasks/2026-09/`.

## State: release preparation, no new features

The owner decided on 2026-09-26 to stop adding features and prepare the first public release.
All four capabilities (terminal, databases, remote desktops, editor) and the shell are built; see
`progress.md` for what is verified and how.

**Authorization in force:** local edits, tests, builds and local commits for release preparation.
**Not authorized without the owner's explicit word:** pushing, opening pull requests or issues
upstream, deploying the site, the git history rewrite, installing over a running copy of the app,
anything touching real servers (SSH and database tests use the disposable test VM only).

## Release-prep checklist

| # | Item | State |
|---|---|---|
| 1 | Licences and acknowledgements | done (`2026-09-26_licensing-and-acknowledgements.md`) |
| 2 | Dependency refresh | done within reach: point releases, SwiftTerm 1.18; tree-sitter 0.27 and swift-crypto 5 blocked upstream (`techContext.md`) |
| 3 | Public-release audit fixes | done (`2026-09-27_release-audit-fixes.md`) |
| 4 | Memory bank curated | done; quotes paraphrased; `.brain/` untracked |
| 5 | README, SECURITY, CONTRIBUTING, building guide | done |
| 6 | Upstream contributions (swift-nio-ssh, Citadel) | drafted locally for the owner's review; nothing sent |
| 7 | Help, site and the Mac release path (D38, D39) | built (`2026-09-27_help-site-and-updates.md`); the owner's steps remain: the Sparkle key, the Developer ID profile, deploying the site |
| 8 | History rewrite, then the first push | only on the owner's word |

## 2026-10-09 — where things stand

**Installed:** Mac **0.4.326** (2026-10-09 23:43: everything through W15; 4 windows reopened, 16/16 sessions, no
crash). Before that 0.4.320 (13:10: closed-window crash fix, Active count at launch, terminal right-click menu). Earlier: all three on 0.4.328 (00:08) (a28dc68: Active
names a Connect workgroup's row by its terminal; 54a66d5: Active asks nothing until the library has loaded; d5b7d2f:
Open Folder Here opens the shell's folder in Files, not home; 1c7c65c: Open in Editor on the folder button's pinch and
hold and in the tools menu). The Mac has none of these since 0.4.320 (its 0.4.322 is
built in `$SP/dd-mac`), to install at the owner's word (he was working).
W15 merged (`6394fc6`, D55): tab groups back after a relaunch on Vision Pro, iPad and iPhone; tabs move between
Vision Pro windows by dragging grid cards or Move Tab To ▸. ef88118: a terminal's selection lasts through output.
W17 merged (`f70da14`): the editor on Vision Pro — its toolbar (was on the split view, which visionOS does not
draw), Markdown preview reachable, Projects + ▸ New Document / Open…, rule 64 deferrals for the editor view and SQL focus.
W16 merged (`02711b3`): visionOS `.plain` windows paint in the window shape (46 pt; 24 pt inset card,
`GlassWindowShape`); Files names its folder in the system window title with an ancestors menu. W20 merged (`d274577`, D57): a terminal window owns its look; local tab gear opens Terminal Settings.
**iPhone and Vision Pro on 0.4.333** (W22 per-window terminal settings), Mac on 0.4.329.
**All three on 0.4.329** (2026-10-10 09:36: W18 settings sync, W19 Mac names, W20 window look, W21 SSH limits). Mac:
4 windows reopened, 16/16 sessions, no crash; no settings-sync failure logged after relaunch (first time since 09-27);
pool log lines (`sh.glas`/`ssh`) present.
**Owner (2026-10-10 ~00:35): "install all three when W21 lands"** — Mac, iPhone and Vision Pro, one build with W18 + W21.
W18 merged (`6293e69`, D56): settings sync was blocked since 09-27 by a duplicate built-in theme when combining with
an older writer's copy; fixed. The first launch with it applies iCloud's frozen terminal preferences once more. W19 merged (`1e80498`): Mac tabs follow names given elsewhere; Mac SSH tabs in tmux show the program title.
W16 (agent `w16-vision-framing`): dark square corners on visionOS `.plain` windows (Files first) and the Files
window's header to match the Mac's modern one. W17 (agent `w17-vision-editor`): the editor fully working on visionOS.
W15 (agent `w15-vision-windows`, worktree): Vision Pro/iPad tab groups back on relaunch; moving tabs between windows
on Vision Pro by drag and drop in the grid view (owner's idea), with Move to New Window / Move to ▸ menus as fallback.
The Mac reopened its 4 listed windows once (`Reopen: 4 listed … 4 reopening`; later asks "already taken"), 15 of 15
tmux sessions attached, no crash. Places were not yet recorded by the 0.4.317 that quit, so positions come back from
the next quit on. Everything committed; nothing pushed. Current task note:
`tasks/2026-10/2026-10-08_find-tabs-tmux-workgroups-editor-plan.md` (W1–W14; backlog at its end).

Earlier, 2026-10-08: Mac 0.4.308, iPhone and Vision Pro 0.4.305.
**The owner works in Claude Code inside a local tmux tab in the app** (`glass-1`): a Mac install no
longer ends the session, and the app reopens tmux windows after a quit. **Standing permission: install
Mac builds as soon as they are built** (detached installer); iPhone and Vision Pro on the owner's word.

Built and committed 2026-10-07 → 08 (task note `tasks/2026-10/2026-10-07_terminal-tabs-and-local-tmux.md`):
- Library rows keep one height in every list; Workgroups use the shared row.
- Mac tabs: named after what runs in them (program title, else a folder other than home, else the
  workgroup, the tmux session as Active shows it, or the shell); rename by double-click, Return, the
  menu or the window title; an activity wave; Finder drops type escaped paths; **drag tabs between
  windows** (drop anywhere on the window; a window whose last tab leaves closes) or within one to
  reorder.
- **D47 local terminals in tmux:** a Mac setting; tabs reattach after a quit or install; closing
  detaches; Active lists This Mac's sessions (open, take over, end); scrolling scrolls tmux's history.
- **D48 SwiftTerm 1.20** (answers XTVERSION, so Claude Code draws in whole frames) and a weekly
  dependency check (`Tools/Packages/check-updates.py`, LaunchAgent). xcodebuild needs
  `-skipPackagePluginValidation`.
- Local shells get the Mac's environment and `TERM_PROGRAM=GlassPowerTools`.
- Scrolling in tmux over SSH on every device (Mac scroll events; a pan on iPhone, iPad and Vision Pro).
- A new SSH terminal never joins a running tmux session by guess (list retried; unlisted names high).
- Vision Pro: the Connections window is a value-keyed window group (a saved-session pair made every
  launch fatal).
- **D49 favourites** and **D51 workgroups** sync across devices.
- Help and the site describe all of it.

Earlier in October, each in `tasks/2026-10/README.md`: D44 tmux on servers and Active's running
sessions, desktop passwords kept through merges, connected dots, iPhone landscape, D45 a database
through another machine, RDP bandwidth reports, the bolt on the right, trackpad scrolling on desktops.

**In progress (2026-10-08, owner's go: recommendations taken, commit each piece as it lands, do not relaunch or install the Mac app until the owner says — it is in use):** eight reports — terminal find, the local
folder button, "+" opening a blank panel, Connect always new, workgroups and tmux, a second editor,
⌘O for folders, a dragged tab copying its tmux session. Plan, root causes, five parallel workstreams,
and decisions: `tasks/2026-10/2026-10-08_find-tabs-tmux-workgroups-editor-plan.md`. Found on the way:
D51's `modifiedAt` is never saved (`Models.swift:2338`); tmux runs without a UTF-8 locale, which turns its listings into "no sessions" (the folder button opening Home, Connect joining `glass-1`, an empty This Mac in Active). Owner's answers and the revised plan are in the note.

**Open, owner's call:**
- **Vision Pro SwiftUI layout crash** while a terminal shows this Mac's tmux session running Claude
  Code (Release builds only; an ASan debug build did not crash in 20+ minutes; xrOS 27.2 beta).
- **Active on the headset does not list the Mac until connected**, and **why a new SSH terminal
  dropped into `glass-1`**: cause found on 2026-10-08. tmux run without a UTF-8 locale (SSH exec on
  a macOS host, and the Mac app itself) prints its listing's tabs as `_`, and the listing reads that
  as "no sessions". Fix planned as W0 in the 2026-10-08 plan note.
- **D50 (Proposed):** reach This Mac's terminals from other devices — needs the owner's OK to add a
  key to `~/.ssh/authorized_keys`.
- **D46 (Proposed): palm-up pinch-drag = scroll, pinch-and-hold = right-click on Vision Pro.**
  Measured: palm direction is the pinch pose's `up` (right hand) / `−up` (left), z toward the viewer;
  away ≈ −0.8, toward +0.68 (right) / +0.40 (left); threshold +0.2. The pose comes only from a SwiftUI
  `SpatialEventGesture`, which takes all input and carries no mouse buttons, so the trackpad's
  two-finger right-click would be lost. Proposed fix: switch between a hands mode and a trackpad
  mode on what is in use. Pending: does trackpad hover still reach UIKit while the gesture is on?
- The slow production query (100 rows, 9.5 s): our tunnel and MySQL path measured fast on scratch
  (50 MB of rows in 0.2 s); the owner was given two queries to split data volume from the server.
- Vision Pro tab bars expanding together across windows; release steps (Sparkle key, Developer ID
  profile, site deploy, scrub, history rewrite and first push — owner's word only).

**Headset connection:** it was unreachable for days because a full-tunnel VPN on the Mac blocked local
network discovery; once LAN access was allowed it appeared. Installing over a running app on the
headset does not restart it — relaunch with `devicectl device process launch --terminate-existing`.

## Paused 2026-09-28 (evening) — where to pick up

All work below is committed locally (nothing pushed). Mac 0.4.266, iPhone 0.4.249, Vision Pro 0.4.254
(the headset was unreachable; its next build must be cut fresh — 0.4.264 predates Mac glass).
Detail: `tasks/2026-09/2026-09-27_glassdt-parity-audit.md` (desktop parity, sync repairs, list sweep).

**Next, in the owner's order when they return:**
1. **visionOS unwind, pass 2** — **approved (D40), narrowed 2026-09-28:** all window transparency stays; only list formats and non-Glass custom chrome change; database: only the results tool bar (in progress: icon buttons + More menu). Owner's direction (2026-09-28):
   *leave it to Apple to define what spatial is best.* The list rows are done (`glassSpatialList`,
   `glassSpatialListRow`; rows never add gaze highlight or padding). Still ours: `GlassSpatialMetrics`
   type/size scale (24 uses), custom window frames (`GlassNativeWindowFrame`, `GlassCanvasBackdrop`,
   `GlassLayeredWindow`/`Panel`, 8 `.windowStyle(.plain)` scenes), 4 hand-built ornaments, 7 custom
   glass backgrounds, the split Connect capsule. Keep: terminal/desktop transparency and the desktop's
   colour key, and the desktop control bar. Proposed order: library window first, judged on the headset.
2. **Stats in the empty library detail** (total machines, services per machine, connection timeline,
   availability) and **status dots as an option** — **approved (D41): counts + timeline from
   on-device history; dots a setting, off by default, TCP connect only.**
3. **Richer clipboard** — **approved (D42), in order:** RDP text/rich text/images, RDP files,
   Files (SFTP) ⌘C/⌘V and drag with Finder, VNC Extended Clipboard.
4. Desktops in Active "a little wonky" — cause not yet described by the owner.

**2026-09-29 (Mac 0.4.253, committed):** database results bar as icon buttons + a More menu (not the
iPhone's pager); "Statement Completed" fills the pane so the pager stays at its foot; the Mac gutter's
offset is a view conversion (the SQL pane's "1" sat a line low); a sync request arriving mid-pass
waits for the pass; ⌘W → Discard on an editor's last document hides the window at once and closes it
once the sheet has gone — the owner confirmed it on the Mac. Flaky only in full-suite runs, not
investigated (terminal, outside the owner's scope): `macImportedThemeAndPortableAppearanceApplyAfterICloudMerge`,
`abandonedStartupCommandTicketExpires`; both pass alone.

**2026-09-29, headset round (Vision Pro 0.4.254):** the editor's panel has square corners; Files hides
its selection circles until Select… or a swipe (as on iOS); the library's iCloud row is plain text
with only the cloud as a button. **Open:** looking at one window's tab bar expanded the library's and
the database table's tab bars too (owner's capture). Nothing documented explains it (HIG says a tab
bar expands for its own window). Proposed, awaiting the owner's go: the database table's
Data/Structure/DDL/Indexes/Foreign Keys as a segmented control on visionOS, leaving the library as
the only tab bar; test with the windows apart to tell our setup from a visionOS bug. Also open: the
remote desktop is slow on the headset (connecting vs live session not yet described).

**2026-09-30:** D43 schema diagram built (task note `2026-09-30_schema-diagram.md`); one
Connections window on visionOS; every ⚡ opens Active; five help pages corrected; README and the
databases page list the diagram. Committed on the owner's word.

**Backlog run, 2026-09-30 (owner: "create a plan and build your list"):** all eleven items built and
committed — see `tasks/2026-09/2026-09-30_backlog-run.md` for each commit and its evidence. Owed: an
install on the Mac and headset, RDP autodetect against Windows, Open With from the Finder.

**After the run (owner on the Mac, 0.4.265–0.4.266):** Settings on the Mac sizes itself to its tabs
(Editor was lost in the toolbar's overflow); desktop glass (Opacity, Background Frost) now on the
Mac too — glassDT had it on the headset only. README and the desktops page list both, with adaptive
streaming.

**Before letting any device with an old install sync:** dry-run the Mac first
(`GLASS_SYNC_DRY_RUN=1`, see the audit note's sync sections).

## Open questions for the owner

- Delete the legacy `SFTPRemoteEditorView` sheet? (Recommended.)
- Behaviour and design findings from the help audit, not changed: the widget reads data the app no
  longer writes (fix or drop for 1.0?); local editor projects sync to devices that cannot open them;
  the Editor off the Mac has no Find, no way to close a lone document, no blank editor; the database settings page may be unreachable (the desktop's is fixed); the database "Rows per page" field does nothing; the terminal
  password, trusted host keys, imported-desktop mobility, Rows per page, the database settings page
  and the editor's Find/close were fixed on 2026-09-30.

## Working rules that matter right now

- Privacy (rule 61): no real machine names, addresses, device identifiers, hosting details or code
  names in tracked files.
- Every shortcut has one owner (D37, rule 60); read the running app's menu bar after changing one.
- Prove a test fails without its fix before trusting it.
- After `swift package update`, run `Tools/Packages/sync-xcode-pins.py`; `PackagePinAgreementTests`
  fails if Xcode's pins and the package's differ.
