# Active context

Where the work is now. Rewritten 2026-09-27; the session-by-session log it replaces is in git
history, and each piece of work's evidence is in its task note under `tasks/2026-09/`.

## State: release preparation, no new features

The owner decided on 2026-09-26 to stop adding features and prepare the first public release.
All four capabilities (terminal, databases, remote desktops, editor) and the shell are built; see
`progress.md` for what is verified and how.

**Authorization in force:** local edits, tests, builds and local commits for release preparation and for
what the owner asks while testing ("go with your recommendations, commit each piece as it lands"). Mac builds
are installed over the running app when ready (the owner, 2026-10-08: "install mac builds when ready since we
have tmux"), except while he says he is working in it.
**Not authorized without the owner's explicit word:** pushing, opening pull requests or issues
upstream, deploying the site, the git history rewrite, anything touching real servers (SSH and database tests
use the disposable test VM only).

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

## 2026-10-14 (~11:30) — RESUME HERE

**State:** 0.4.437 on the Mac and iPhone (14:46); the Vision Pro has been locked (CoreDevice 4016)
since 0.4.423 — retry `devicectl device install app` with `$SP/dd-vision` when it is worn. No crash reports since
2026-10-13 18:47. Everything committed, nothing pushed. The owner said he was packing up (~11:10). **Mac installs go when
ready, never held on our judgement** (the owner: "No need to hold on quitting right now. All tmux all day."); devices too.

**Waiting on the owner:**
- **Desktop clipboard vs GNOME — cause found (4499937, 0.4.428).** The 0.4.425 drops were ours: 4346ef8's logging
  named them "server did not confirm RDPGFX capabilities". Before the first frame RDPKit read at most 16 packets
  waiting for RDPGFX's caps confirm, and clipboard/sound/device packets counted; with our Format List at Monitor Ready
  (MS-RDPECLIP 3.2.5.1.2; FreeRDP's client sends one too, empty included) GNOME answers at once and the 16 ran out.
  Now those packets don't count (own bound 4,096) and the Monitor Ready list is back. Mock test with 24 clipboard
  messages reproduces the owner's exact error without the fix. On 0.4.427 the owner: "sending worked!" (Mac → GNOME,
  via a copy's list). **Next:** on 0.4.428, GNOME → Mac (needs the Monitor Ready list) and that sessions stay up.
  The ~4 s second redirects on 0.4.425 are explained by the same failure only if hop 1 also ran out — watch for a
  `redirect-accepted` on hop 1 in the new logs. Workaround no longer needed.
- **GNOME clipboard works both ways on 0.4.428** (the owner: "sending worked! :)", then "this is magic"). He asked for
  "an auto clipboard toggle somewhere": **Sync Automatically** (2998d20, 0.4.429) at the top of the desktop's
  Clipboard menu, saved per desktop (`DesktopConnection.clipboardSyncsAutomatically`, default on, old records on), also
  "Sync clipboard automatically" in the service's settings; off, Send Clipboard / Copy Remote Clipboard still work.
  Not yet seen by him.
- **Hermes unmarked on another machine (14:35, his picture) — open.** Nothing local runs it. 0f0c837 (0.4.437) reads
  launchers: `python -m <module>` (`hermes_cli`, `hermes_agent`), `uv run`/`uv tool run`/`uvx`/`pipx run`/`npx`/
  `bunx`/`pnpm dlx`/`yarn dlx`, and shell-script launchers; inline `-c`/`-e` code never kept. Asked him for, on that
  machine: `tmux list-panes -a -F '#{pane_current_command} #{pane_pid}'; pgrep -af hermes || pgrep -lf hermes`. If
  the terminal is not in tmux, nothing tells the program. Also 91b5b2b (0.4.436): ⌘↩ sends a reviewed paste.
  Offered, unanswered: All Windows cards refreshing about once a second, and a left terminal keeping its last picture.
- **Command Palette, done this round** (cf237ab, fdc871c, 4690038; 0.4.430): every library service as "Connect: …"
  (desktops included; the database's old entries connected nothing); the terminal's commands from any window (New
  Connection, local terminals, a machine's Files and no-tmux terminal, saved workgroups); every project, Favorites'
  folders, saved queries ("Open Query: …", via Siri's request) and tmux sessions running with no window ("Attach: …").
  The three capabilities drain queued requests when a Connections window appears (`onChange(initial: true)`). Not yet
  seen by him.
- **All Windows off the Mac — decided and in progress (13:15–14:00).** The owner's answers, in order: Mac unchanged
  (keeps its own Show All Windows button, ⇧⌘\\, pinch on terminal/desktop windows); **iPhone, iPad and Vision Pro hold
  the ⚡** ("everything other than Mac can still use the lightning bolt hold pattern"); Vision Pro also **a Siri
  action**; on iPhone/iPad a gesture too — two-finger pinch conflicts with desktop/image/diagram zoom; three-finger
  pinch (his "index and middle, with a thumb") rejected because iOS's three-finger text gestures (copy/cut/paste/undo)
  matter to people who use them ("less about me and more about people who do"); **pull down from the empty part of
  any top bar**, the pane sliding in "like a separate transparent pane". Cards: "only show connected services, like
  Mac. transparent previews, the whole 9" — open sessions only (running tmux is Active's), previews on the glass with
  no plate, Blur previews honoured, agent marks (still to do: SVGs as assets, `GlassOpenSession` gains a mark).
  Done: 45de160 (hold ⚡ → overview, 0.4.432); e6f998d (pull-down pane, 0.4.433: window-level pan judged by the
  bars' frames — on iOS 26 a touch in a bar's empty part can pass to the list underneath, so a hit-test check
  failed on the simulator — and the list waits for the pull; 3 iPhone-simulator UI tests: pull, hold, ⚡ tap still
  Active); 77c6506 (agent marks: the 8 SVGs in `Resources/AgentMarks.xcassets`, byte-equal to `logoSVG` by test;
  `GlassOpenSession.mark`). d4d0eda (0.4.434): Vision Pro — hold ⚡ (pinch held) brings Connections forward with All Windows as a sheet
  (`GlassAllWindowsSheet`); Siri/Shortcuts "Show all windows in Glass Power Tools" (`GlassShowAllWindowsIntent`) on
  every platform. 30c5c83 (0.4.435): 20 more agents (the owner: "detect hermes, openclaw, and as many as we can...
  agency agents installer has a good list") — OpenClaw, Hermes Agent, Mistral Vibe, ZCode, Aider, DeepSeek Harness
  (by npm package only; `dsh` is also the distributed shell), Amp, Goose, Cline, Kilo Code, OpenHands, Grok CLI, Kiro,
  Trae Agent, Qoder (Lobe Icons 1.95.1 marks, paths written out), Crush, Droid, Auggie, Plandex, iFlow (no Lobe mark:
  `sparkles`). Windsurf, Antigravity, Osaurus are desktop apps. Vision Pro parts compiled only (headset locked).
  iPhone's Select-by-pinch fixed (389b7ce).
- **Links and paths in the terminal's right-click menu; Watch Log File (af433a3, 0.4.426).** Not yet seen by him.
- **Agent marks (0.4.424):** "Codex looks great." Whether the softer look is quiet enough is still open.

**Built 2026-10-13 evening and 2026-10-14** (evidence: `tasks/2026-10/2026-10-13_tier-3-evening.md`; decisions D73):
- B-X2 (editor looks again on coming forward), B-X22's second half (this Mac's projects from the disk), B-F32 (Graphics
  per Desktop service), saved queries for Siri and Shortcuts, Favorites beyond machines (D73: sections by kind; stars
  on services, projects, workgroups and Files' folder), a whole-row right-click on a machine's service rows.
- Black backgrounds show the glass (`TerminalClearBlacks`): btop's black is the terminal's empty background.
- Desktop clipboard waits for the server (above). Markdown preview escapes text (`GlassEditorMarkdownHTML`; the
  "Blocked Plug-in" pill). Error suggestions can be paused per terminal or turned off (Settings ▸ Terminal).
- AI agents marked in Show All Windows (`TerminalAgent`, `TerminalProcessTable`, Lobe Icons MIT @05a9b8c): tmux's
  `#{pane_current_command}` in the shared pane query, read every 5 s while output runs and when the overlay opens;
  an interpreter's or a version-named program's command line, first words only (Claude Code's installer runs
  `2.1.296`). tmux does not announce program changes; control mode (D53, proposed) would.
- 0.4.410 onwards embeds the inert File Provider extension (no domain registered).

**His test list** (also the 19:35 list below): the editor asking on coming forward; a Desktop's Graphics setting (try
H.264 (4:2:0) on the GNOME host for B-X6); "Open the ‹query› query"; Favorites of each kind, and on other devices.

**Next for an agent:** B-X7 (needs the headset). Phase 5's File Provider domain trial waits for him.

**Rules in force:** rule 61 (never his machine, tab, window or workgroup names — his screenshots show several); prove
each test fails without its fix; compare `tmux list-sessions` md5 around terminal tests; check
`CGSSessionScreenIsLocked` before blaming a red suite; build with `$SP/build-install-4NN.zsh` (copy the last with sed).

## 2026-10-13 (~19:35) — the owner's test list

**State:** 0.4.409 on the Mac, Vision Pro and iPhone (19:31); no new crash reports since 18:47 (fixed); working
tree clean; everything committed, nothing pushed. The owner is out and will test when back. **His instruction:
"Go ahead with 5"**: the File Provider spike.

**Built today under D72** (plan: `tasks/2026-10/2026-10-13_system-integration-plan.md`; patterns in
`systemPatterns.md` "The system's ways in"; facts in `techContext.md` "System integration facts"):
- **Phase 1:** entities, ten intents, App Shortcuts, `GlassWindowOpener`, and the Machine widget.
- **Phase 2:** Finder Services, Open With a folder or `.command` file, the Dock menu, `ssh://`, a Finder Sync
  toolbar button, and a Quick Action.
- **Phase 3:**
  - Send Files to a Machine (Shortcuts).
  - Drag a terminal or desktop out into its own window (Vision Pro, and iPad for desktops).
  - Handoff, continuing a terminal in its tmux session.
  - **The Mac share extension** (the owner chose "1 mac only").
- **Phase 4:** controls, opt-in search (Settings ▸ Privacy), and the "What's Open" snippet.
- **Mac extension targets in the hand-written project:** Finder, QuickActions and Share. Add more with
  `$SP/add_mac_extension.py <hexpair> <Target> <Folder> <entitlements> "<display>" <bundle-suffix>`.

**Owner reports today, all fixed:**
- Open With brought up a Connections window: the Mac now takes opens in its app delegate.
- Handoff made a new tmux session: it now attaches by name.
- Handoff missed the open tab: it now finds this Mac's local tab, via `SSHHostKeyIdentity`.
- Two Quick Look crashes (fixed 0.4.398 and 0.4.408).

**Owner to test when back:**
1. Handoff from the iPhone into a tmux session on this Mac (0.4.409).
2. Services, the Quick Action, the toolbar button (switch it on in System Settings ▸ General ▸ Login Items &
   Extensions), and the Dock menu.
3. Share ▸ Send to a Machine, and Send Files from Shortcuts. Neither has sent to a real machine yet.
4. Siri and Spotlight phrases; controls; the Machine widget.
5. Vision Pro: drag a Terminal or Desktop row out of a host's detail into the room.
6. The opt-in search setting.

**Phase 5 spike, done as far as it can go unattended (22:10; `tasks/2026-10/2026-10-13_file-provider-spike.md`):**
- A macOS File Provider extension (`GlassPowerToolsFiles`) links the SSH stack (31 MB) and signs with the Keychain
  group through the team profile. Pinned-only trust and SFTP reading already exist.
- **The owner's call:** register one scratch-VM domain with him present, to prove it at run time, then decide on
  read-only browsing per machine.
- The target is inert (no domain) and embedded in Mac builds. Nothing from the spike has been installed.

**Phase 5 (original plan):** a spike, read-only. Present a machine's SFTP home as a location in the Finder and Files
sidebars with an `NSFileProviderReplicatedExtension` (macOS 11, iOS 16, visionOS 1; a visionOS App Store block
is reported, forum 802442).
- **Measure first:** can a sandboxed File Provider extension reach the SSH stack and the Keychain access group,
  and enumerate one folder?
- **Hard questions:** credentials in the extension (unavoidable here); host trust cannot be prompted inside the
  extension, so only already-pinned keys are accepted; sync semantics.
- **Deliver:** a written spike note with measurements and a recommendation, and a Mac-only proof of concept
  behind a debug flag if it works. Nothing is shipped as working until the owner has seen it.

**Standing:**
- "Go with your recommendations, commit each piece as it lands"; install Mac builds when ready.
- Build and install with `$SP/build-install-4NN.zsh` (copy the last one with `sed`).
- Prove each test fails without its fix; compare `tmux list-sessions` md5 before and after terminal tests.
- Rule 61: never write the owner's machine or tab names.
- `$SP` = the session scratchpad.

## 2026-10-13 (~16:15) — where things stand

**State:** **0.4.402 on the Mac, Vision Pro and iPhone** (14:05); no new crash reports; working tree clean;
everything committed, nothing pushed. The day's record, with every commit and its evidence, is
`tasks/2026-10/2026-10-13_owner-testing-day.md`. Decisions: D24 amended (the library keeps UIKit's sidebar toggle
on iPhone and iPad), D69 (tunnels keep their own SSH connections), D70 (a connection belongs to its controller,
never to a view's task), D71 (the app's own Light, Dark or System).

**Authorization in force today:** "go with your recommendations, commit each piece as it lands"; Mac builds
installed when ready unless the owner says he is working (he accepted every install today); iPhone and Vision Pro
installed with them to keep one build everywhere.

**Confirmed by the owner today:**
- 0.4.402: the lighter Show All Windows blur, Settings ▸ Appearance ▸ System/Light/Dark and the palette in the
  windows' glass: "Yeah, this looks good."
- Square SSH panes where they fill the tab (0.4.399).
- "+" ▸ New Terminal on connects (0.4.400: "it works"). It had failed twice with a `CancellationError`, because the
  connection ran in a view's task: first the placeholder's, then the pane's. D70 records the rule.

**Built today, not yet confirmed on a device:**
- Headset: held delete and arrows repeat; pinch and hold, then drag, selects.
- Desktops on phones and iPad: the system's unavailable view; sessions in place on phones; an iPad window's bar
  and Close.
- Show All Windows across every kind of window, with Blur previews. The toggle sat on the terminal's Connections
  page, where the owner could not find it; it moved to Settings ▸ Appearance ▸ Show All Windows at his word (0.4.401).
  He loved the blur but found it too strong; it went from 5 to 1.5 pt, so lines show and letters do not (0.4.402).
- **App appearance (D71, 0.4.402):** Settings ▸ Appearance ▸ System, Light or Dark, on the Mac, iPhone and iPad.
  The command palette now has the windows' glass and no white list.
- One Command Palette.
- The Quick Look crash fix.
- Database connect errors: the shared Local Network rule; PostgreSQL in the server's words.

**Waiting on the owner:**
- B-X27: the protection class for files written while the Mac may be locked. Recommended complete-unless-open
  for recordings and downloads.
- Unfold the Duo simulator for the tour re-run (content margin; the unfolded-window and "N Views Open" items).
- B-X10/B-X11: a design call.
- B-X4: Mac drag-select in tmux history.
- Headset input to try on the device.
- B-V4 two-device run; B-R1–R7; B-Q28.
- A desktop's clipboard: Share clipboard is off by default per Desktop service, as he was told.

**Next (the owner, 16:10): system integration** — "Let's get a finder integration going … they should be available on
all of the platforms that support them. App intents, all of the modern stuff … Be sure visionOS is well represented!"
(his screenshot: Finder's Services submenu with other apps' New Tab/Window Here and Open in). Plan:
`tasks/2026-10/2026-10-13_system-integration-plan.md`. **Approved (D72): "Do all of the things."**
- **Phase 1 done, 0.4.403 on all three (16:52):**
  - Entities for machines, services and workgroups, read from the widget snapshot.
  - Ten intents and seven App Shortcuts; the built metadata was checked.
  - `GlassWindowOpener`, which every kind of window registers. Requests used to run only from the Connections
    window, so a widget's Connect waited with only terminal windows open.
  - A configurable Machine widget.
  - Not yet seen by the owner.
- **Phase 2 (the Finder) built, 0.4.404:**
  - Services (Tab Here, Window Here, Open in), declared as Ghostty, iTerm2 and CotEditor declare theirs.
  - Open With a folder or a `.command` file, a drop on the Dock icon, and the Dock menu.
  - `ssh://` links: a saved machine connects; another fills in the new-server form.
  - A Finder Sync toolbar button and a Quick Action, as two new macOS extension targets
    (`GlassPowerToolsFinder`, `GlassPowerToolsQuickActions`). They hand off through `GlassExternalRequests`.
  - The owner's report "Open with opens a new connections window" is fixed: the Mac takes opened URLs in its
    app delegate.
  - **To verify on the owner's Mac:**
    - Services show without being switched on.
    - The toolbar button after it is switched on.
    - The Quick Action.
    - A sandboxed extension waking the app.
  - **Release script:** it must sign the two new extensions with Developer ID (B-R2).
- **Phase 3 built (0.4.405–0.4.406):**
  - Send Files to a Machine, a Shortcuts action, so it reaches the share sheet through a shortcut. It uses the
    W14 never-replace upload and a shared `openSFTPConnection`. Not yet sent to a real machine.
  - Drag a terminal or desktop out of a host's detail into its own window: Vision Pro (in the room) and iPad
    (desktops). A dragged `NSUserActivity` is claimed with `handlesExternalEvents`; a headset terminal reserves a
    workgroup.
  - Handoff for the terminal, database or desktop in front. The activity carries only the endpoint, and the Mac
    takes it in the app delegate.
  - **Share extension, the Mac only (the owner chose "1 mac only"), 0.4.407:** Share ▸ Send to a Machine. The
    extension copies the files into the App Group and opens the app, which sends them and shows an alert. No
    credentials ever enter the extension.
  - **Handoff fixed (0.4.407).** The owner, continuing an iPhone terminal on the Mac: "it opened a new terminal
    window, with tmux, in my home directory … left a detached tmux session in Active". Now the activity names
    the tmux session. The receiving device brings forward the tab showing that session, even a background tab,
    or attaches to it by name, never a new session. The owner's leftover detached session is his to End in
    Active.
  - **Handoff of this Mac's own session (0.4.409).** The owner, on 0.4.407: "It found the right tmux session,
    but created a new window and tab when the tab with that session was already open". The phone was SSH'd into
    this Mac; the log showed a new SSH route at the hand-off. Now, when the machine named is this Mac (a pinned
    host key matches this Mac's own, via `SSHHostKeyIdentity` in GlasSecretStore, shared with the editor), its
    local tab comes forward, or a local terminal attaches. This relies on the iPhone's pin of the Mac's key
    having synced by iCloud Keychain; without it, it falls back to SSH.
  - **A second Quick Look crash (0.4.406, 18:47), fixed in 0.4.408:** SwiftUI's dismantle closed a `QLPreviewView`
    that had already closed itself on leaving its window, and Quick Look aborted on the second close.
    Reproduced in a separate process: both teardown orders abort by default and survive with
    `shouldCloseWithWindow = false`, which is now set.
- **Phase 4 built (0.4.406):**
  - Controls on the Mac 26, iPhone and iPad: Open Terminal on a chosen machine, Active Connections, and New
    Terminal Window on the Mac.
  - Machines and workgroups in search, **off until Settings ▸ Privacy ▸ Show Machines in Search**.
  - "What's open in Glass Power Tools?" answered in place with a card.
- **Phase 5 next:** a spike of the File Provider (machines in the Finder and Files sidebars), read-only first.
  Then the owner's devices check all of the above.

**Then, for an agent:** tier 3 from the inventory's section 0: B-X2 with B-Q11, B-X6 with B-F32, B-X7, and
B-X22's second half. Also the database's own `databaseSidebarChrome()`, which still removes the toggle off the
Mac (D24's amendment).

**Rule 61:** the messages of 998a225 and 1da944b quote two of the owner's names. They are left under his earlier
ruling (no history rewrite for messages); files were neutralised. Never quote his tab, host or machine names in
code, notes or messages: use "an SSH tab of the owner's" or "a desktop".

## 2026-10-12 (late) — before the second compaction: the iPhone Duo on its simulator

**Installed: 0.4.391 on Mac, iPhone and Vision Pro** (with the swift-nio-ssh CVE fix). Committed since, not yet
built for devices: swift-log 1.16.1 / swift-nio 2.104.0, the fold-aware window gate, the alignment work below. HEAD =
this notes commit; nothing pushed. (Corrected 2026-10-13: the README space and `testArrowKeysReachTheTerminal` were
not the owner's — the test was an agent's probe, 2026-10-11 — and both were discarded at his word.)

- **Duo simulator works here:** iOS 27.1 runtime downloaded (`xcodebuild -downloadPlatform iOS -buildVersion 27.1`);
  Xcode 27.2 beta's own runtime cannot run a Duo. Simulator **"Duo probe"** (`828A54FB-…`, iOS 27.1); Device Hub's pose
  buttons (folded / half / open, along the bottom) appeared after the owner updated Components. `XCUIScreen.main` is the
  *outer* display — capture `app.windows.firstMatch.screenshot()` (it comes out rotated: rotate −90°).
- **Measured on it:** a Duo reports `supportsMultipleScenes` yes + phone idiom, folded and unfolded; folded (466 pt,
  compact) a scene request *succeeds* and covers the library with no way back but the switcher → gate = scenes AND (not a
  phone OR regular width) (fac5ead, rule 43). Unfolded is regular width (two columns).
- **Alignment (owner: "fix the header and content alignments across the app for Duo", then chose the large-title
  line):** Your Library raised to All Connections' line (132007c); detail columns via `glassDetailColumnTitle`
  (GlassConnectionUI; host detail uses it; iOS 27 puts detail titles in the toolbar row and `.toolbar(removing: .title)`
  does not remove it, so the modifier owns the navigation title). **Unverified:** the 12-pt content margin (needs an
  unfolded run). Other detail panels (Workgroups, SSH Keys, Collections, Active) not yet given the modifier.
- **Done after the compaction — Active's empty detail** (owner: "Terminal > [machines with terminals], Database >
  […]"): the Mac, an iPad in landscape and the headset all showed the same "Nothing Is Open". Now the detail page lists
  the library's machines under Terminal, Database, Desktop (setup tab order); a row connects that service; on a compact
  stack the same sections follow "Nothing Is Open" in the list (`GlassActiveLauncher.swift`, `glassLibraryIsStacked` —
  an iPad's list column is compact in landscape too, so the width class could not decide). Seen on the folded Duo and an
  iPad Pro 11-inch landscape; the Mac not yet on screen (comes with 0.4.392).
- **Seen on the Duo, to fix:** ~~two "Tools" buttons in a folded terminal~~ and ~~the bottom bar white under a black
  terminal~~ — fixed 2026-10-13 (the keyboard accessory reports itself on screen; the terminal paints under it; seen on
  the Duo). Still open: unfolded, a connection opened as its own window that took the screen (needs the unfolded Duo);
  folded, the system's "N Views Open" chip covers the start of the library's large title — it is iOS's own chrome (not
  in our code; nothing published about it): compare an Apple app with several windows on the Duo before changing ours.
- **0.4.392 (2026-10-13 ~00:00):** built for all three from a53f2e3 (the Duo work, Active's machines, the terminal
  fix, the workgroup titles); **Mac installed**; iPhone and Vision Pro were locked, and a retry loop in the session
  scratchpad installs each when it unlocks. The tree-sitter match limit landed after this build: it goes in the next.
- **Scratch and Windows 11 are in the Duo probe's library** (added by a temporary UI test, not committed). How to reach
  both machines is in the agent memory runbook (`test-machines-runbook`): Parallels VMs; Windows account `gptrdp`,
  password reset per need into a 0700 file, never printed; tunnels on port 2223, never 2222 (Citadel's tests bind it).
- **Temporary UI tests** (tour + demo) live only in the scratchpad (`GlassTerminalUITests.tour.swift`) — swap in to
  run, restore after, never commit. (The "owner-backup" copy beside it held an agent's probe, discarded 2026-10-13.)
- **Done 2026-10-13:** workgroup details use `glassDetailColumnTitle` (host, keys, projects already had it through
  `GlassLibraryDetail`); tier 3's tree-sitter overflow — the highlight cursor's match limit, not vendoring.
- **Next:** unfold the Duo and re-run the tour (content margin; host detail, Active, Settings, Workgroups) — the owner
  was asked to unfold it; the two Duo items left above; tier 3 from B-X5 (shared SSH connection loss).

## 2026-10-12 — end of the session (before a compaction)

**Installed: 0.4.391 on Mac, iPhone and Vision Pro** (with the CVE fix; the Mac at the owner's word, 20:32). 0.4.391
predates the swift-log/nio bump; the next build carries it. Nothing pushed. (A one-space README edit and an
uncommitted agent probe, `testArrowKeysReachTheTerminal`, were wrongly called the owner's here; both discarded at
his word, 2026-10-13.) **Next: the owner brings a new list after the compaction.**

Shipped today, each committed with its evidence (task notes: `2026-10-12_tmux-under-launchd.md`,
`2026-10-12_widgets-machines-and-active.md`):
- **D66, local tmux in a background Glass Power Tools process.** A Force Quit of an app run from a pane ended every
  local terminal: the panes shared a resource coalition whose app had quit (reproduced with a probe and the owner's
  Dock clicks). launchd now runs the app's own executable as `--tmux-host`, which starts tmux, so panes keep the app's
  privacy permissions; `exit-empty` is turned on so tmux and the host end with the last session; Settings ▸ Terminal ▸
  tmux shows it and can end it. **The owner's own server (started 00:44) predates D66** and keeps running as before
  until it ends (a reboot, or End All Local Terminals).
- **Rule 63 leak fixed (8ce39c3):** test windows' panes attached with this Mac's tmux and made six sessions on the
  owner's server. Every tmux call now goes through `MacLocalTmux.server`; stand-ins name an inert tmux.
- **D67, Basic terminals:** any terminal can be opened outside tmux (File ▸ New Basic Terminal Tab ⌃⌘T; "+" ▸ New
  Terminal, New Basic Terminal, New Terminal on ▸ every host by machine name; Connect Saved Host's "Open without
  tmux"; Basic Terminal beside Files on a host on every device; palette). The local tmux toggle moved to Settings ▸
  Terminal ▸ tmux.
- **D68, widgets:** Machines and Active on iPhone/iPad, Vision Pro and now the Mac, from a snapshot the app writes,
  taps as App Intents. On the Mac the snapshot is in a team-prefixed App Group (the wildcard-signed extension could not
  be given `group.sh.glas.shared`). The owner sees correct counts on the Mac; iPhone and headset not yet reported.
- **Editor:** a project's SFTP connection reopens itself when dropped (fc7653e; live test kills a real connection);
  Wrap Long Lines off works on iPhone/iPad/Vision Pro (8b444a9; simulator tests in `GlassEditorUIKitTests`).
- **iPhone:** tapping a workgroup opens its detail (276117e).
- **The busy tab's light:** the activity wave became a soft cloud of light sweeping the row (d45529e, the owner's
  choices at each step).
- Overnight (before the session's first compaction): arrow keys as priority commands, the desktop Keys menu, arrow pad
  and iPhone keyboard bar, the thinned desktop toolbar, push pacing, High Performance mode (D65).

**Open:** D46 pinch gestures (asked "Shall I build it?", unanswered); High Performance tried with a real Mac; the W39
orb on the headset; Bonjour availability (owner's call); widgets placed and tapped on iPhone and Vision Pro; the next
Mac release must sign the widget with Developer ID (see `Tools/Release/release-mac.sh`). **Rule 61:** the messages of
fc7653e, 47b7df8 and 107f1be quote the owner's machine and host names (the code and tests were neutralised). The owner:
leave them, no history rewrite for them, rule 61 unchanged — "just keep moving forward". No IP address of his is in
any file or commit message (scanned 2026-10-12). **Docs (2908a18, the site commit
after it):** release script checks the Mac widget before notarizing (never run; the Developer ID export may need a
profile for `<bundle id>.widgets`); BUILDING.md and SECURITY.md current; site and help current, three stale desktop
claims corrected. **Done after the compaction (the owner's first ask):** the VNC setup warning follows the user name (262ba7a): with a
Mac user name it says a Mac is encrypted after sign-in and other servers protect only the password; without one it
keeps the orange warning and names adding the Mac's user name as the fix. Help page `desktop-add-service.md` matches.
**Then the backlog inventory** (`tasks/2026-10/2026-10-12_backlog-inventory.md`): every open item, with IDs, including
the original apps' lists that never came forward. **Its section 0 is the order of importance** (the owner asked for
it): tier 1 protects machines and data (B-X1 FIFO/huge local reads on the main actor, B-X9 save race, B-X21 Citadel
writer, B-X3 key substitution, B-X14 silent record loss, B-X8 regex hang); tier 2 is dated or release-gating (B-F44
iPhone Duo 10-23, B-H9 dependency failures, B-X25 sleep/wake, stale docs, B-V4 two-device acceptance). Work from it.
**Tier 1 done** (the owner: "knock out all of 1"): B-X1 e56a57f, B-X9 b90327f, B-X21 f2c1950 (Citadel C12), B-X3
9d4fc68, B-X14 77e5523, B-X8 aaf3799, B-X23 (all three devices on 0.4.390). Each test was shown failing without its
fix. B-X1's "FIFO hangs" was wrong (Foundation refuses at once, as "no permission"); B-X3 was worse than listed (a key
not yet synced was swapped too).
**Tier 2 local work done** (`tasks/2026-10/2026-10-12_backlog-tier-2.md`): CVE-2026-43798 in swift-nio-ssh fixed first
(2ddc207, critical, found by the advisory scan); B-X25 wake (fd729b1), B-F44 Duo (aa06f51), B-H1–H4 docs (2aed1f7),
DOMPurify record (b29917a), swift-log/nio taken and the full suite passing (B-H9, B-T5). **Waiting on the owner:**
B-V4 two-device run (checklist in the note), B-T8's device QA, B-R7 a lawyer, B-Q28 SwiftTerm v1.99 (recommend stay on
1.20), the release path B-R1–B-R6, and the Mac install. **Next after that: tier 3**, with the tree-sitter overflow crash
added (vendor 0.25.10 with the fix backported; no SwiftTreeSitter release reaches 0.26).

## 2026-10-11 (late night) — High Performance built; quality-switch crash fixed

**Installed: 0.4.367 on Mac, Vision Pro and iPhone** (19:58–20:05; headset and iPhone were locked, not launched).
Since 93d5f88: High Performance mode (6211b12, f53eb38, 963d0de, 02453cc, fabb375, c2ed00c — D65), the Quality-change
decode crash on the hotspot (1f2a01c). **Next:** owner tries High Performance on the headset (Desktop window settings ▸
Mac Screen Sharing ▸ High Performance, then reconnect) with the Mac at hand; first pull the headset log and read
`event=hp-decoder-check`; then the `hp-*` / `media-*` lines of a session. Then: live resize of the virtual display,
two virtual displays, the W39 orb check on the headset, scroll/clipboard check.

## 2026-10-11 (night) — after the compaction

**Installed: Mac 0.4.364; Vision Pro + iPhone still 0.4.361** (off-network all evening; install 0.4.364 when `devicectl`
shows them, then verify the W39 orb). Since d495e42: **8b9f39d** Automatic quality watches lateness (slow updates, TCP
queueing over base RTT; a Mac's Automatic stops at Balanced; W36 scale refusal only for the Mac's own ending, 10 min);
**e5912f5** availability dots skip connected services and probe VNC every 10 min (a probe launches the Mac's
screensharingd + agent for 15 s). Details in the screen-sharing task note. Next: devices → install + orb + headset log
(look for `event=automatic`, `roundTripMs`, `queuedMs`, `server-scale`); then High Performance mode behind a switch
(probe first); owner to try Automatic on the hotspot and scroll/clipboard on the Mac.

## 2026-10-11 (evening) — where things stand

**HEAD = this notes commit (after 7fc7be3). Installed: 0.4.362 on the Mac; 0.4.361 on Vision Pro and iPhone** (they were
off-network for 0.4.362 — install it when reachable). Full story: `tasks/2026-10/2026-10-11_apple-screen-sharing-protocol.md`.
- **Screen sharing speaks Apple's revision (003.889)** on account connections to a Mac: record layer (encrypted after
  sign-in — 3.8 never was), arming `AutoFrameBufferUpdate` at 0 after each layout (pictures come only by pushes on 889;
  33,333 starved/blackened display 2), ViewerInfo required (without it the Mac hangs), Apple pointer shapes, pointer
  echoes ignored within 1 s of a local move, scroll by distance (0x17), clipboard via Apple pasteboard (0x15/0x0b/0x1f),
  3.8 fallback if the prelude fails. Per-display connections off (a Mac serves one scale at a time); a scaled Mac is
  asked for the whole framebuffer (region requests broke its scaled readback). Fast native ZRLE path; renderer uploads
  only its window's region on new frames. A Mac never reports its own mouse to a controlling viewer (PointerPos −232
  tried; matches codevisor/Jump/Splashtop).
- **Orb (W39, c23a6b6):** the Connections window becomes its orb in place (pushWindow broke after force-quit). UI 9/9 on
  simulator; NOT yet on the headset. If the orb jumps when it comes forward, drop the openWindow in `becomeOrb`.
- **Hotspot test (owner in his car, 380/52):** Balanced at full Retina = 64–74 Mbit/s from the Mac, seconds of lag
  (cellular queueing + the Mac reads input only between pushes). Data Saver (16-bit) "much more responsive"; Lowest
  "somewhat useful". No SetServerScaling was sent all session — probably `scalingRefusals` from a test session.
- **Next:** (1) install 0.4.362, verify orb; pull the headset log (server-scale-refused? flow on the hotspot);
  (2) latency-aware Automatic quality; make the W36 scale refusal less blunt; (3) Service Availability probe: skip hosts
  with a live session, lighter check for a Mac's 5900 (each connect starts screensharingd + agent, once a minute all day);
  (4) High Performance mode (HEVC media stream, virtual displays, AAC-ELD) from remotex `vnc_apple_media.rs` (clone in
  the scratchpad `ext/remotex`), behind a switch, probe first; (5) owner to verify scroll and clipboard with the Mac.
  Older open items: drag-select past the screen in tmux (Select All takes history, ec226f9); light/dark theme pair;
  title capsule sizes; SSH new tabs in the remote folder (scratch only).

## 2026-10-11 (midday) — where things stand

**HEAD = latest notes commit after 5651ae3. Installed: 0.4.350 on Mac, Vision Pro and iPhone.** Two-display screen sharing
works (D61); W38 (D64) adds Retina at 1x / Keep Display Proportions / pointer. **Open bug, top priority:** on the headset
the main connection fails 0.9 s after SetServerScaling 0.5 with "The ZRLE rectangle has trailing data" (log via
VNCDiagnostics, fetched with devicectl — see the task note); the failure then wrongly disables the Apple layout. Then:
drag-select can't reach tmux history in Mac local terminals; the Mac sends no cursor messages to our RFB 3.8 client
(pointer likely drawn into the picture); open questions (light/dark theme pair, title capsule sizes, SSH new tabs in
the remote folder). Probe outputs/logs live only in the scratchpad (`.gitignore` covers Tests/LiveDesktop/*.txt,
*.logarchive).

## 2026-10-11 (morning) — where things stand

**HEAD 606c174+notes.** Installed: **0.4.349 on Mac, Vision Pro and iPhone** (11:45). Since the evening: W34 orb fix (a display
window's ⚡ opened a second Connections window), W35 appearance audit (D63 proposed: no colorScheme light mode on Vision
Pro), UI-test isolation (`GlassUITestRun`), right-click Copy fixed (NSObject `perform(_:)` collision), probe with a
hidden password prompt, W36 Apple display layout (1101+1105) — **owner: "Dual screen works!!!"**, W37 new local terminals
start in the current folder, W38 Retina at 1x / Keep Display Proportions / the Mac's pointer (D64).
**Waiting on the owner:** `Tests/LiveDesktop/.build/release/GlassVNCProbe 127.0.0.1 5900 <user> - --retina-1x
--second-session --cursor 20`, then `--display <retina id> --retina-1x --pointer-check`.
**Open questions for him:** a light/dark terminal theme pair (D63 plan item 1); title capsule sizes (terminal ≈29 pt vs
desktop ≈37 pt); SSH new tabs in the remote folder (testable on scratch).

## 2026-10-10 (evening) — where things stand

**Committed today, after the 0.4.336 install:** 6eafdfd (D59, Vision Pro terminal fully clear: plain window drawing
Apple's glass at its Glass), c981da3 (W26, combine one-terminal windows: Move Tab To in the tools menu, draggable title),
aa9f9fe (W27, This Window: ↺ beside changed settings, Opacity/Glass/Material, one sheet), 3c3661d (W28/D60, shared
window glass; remote desktop fully clear; split-view windows paint only their content), f213d4a (W29, Connections idle
orb with the Active count), 928baaa (one Connections window on visionOS), ed8f09e (tunnel-hop test coin toss fixed),
2b4f75f (W30/D61, a window per remote display, region-limited fetching, Quality and the Connection page).
**Installed:** iPhone and Vision Pro 0.4.336; Mac 0.4.329. The owner is away from the devices (remote); install the
current HEAD on both when reachable, the Mac at his word.
**Validation limits:** the Mac's screen was locked for the last three commits: every touched suite passes except the Mac
title-bar layout test (`workspaceUsesNativeTitle`), which fails the same way on pre-merge code while locked — rerun
unlocked. W30 is unverified against a real Mac; his checklist is in the task note (2026-10-08 plan note, W30 entry).
**Owner's open choices:** database split view vs own glass (`DatabaseSpatialLayout.ownGlass`); desktop canvas corners
rounded vs square; desktop default Glass 25% vs 100%; the no-split treatment for Connections/editor/Files.

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
**iPhone and Vision Pro on 0.4.336** (W22–W25 per-window settings for terminal, editor, database and desktop windows;
Apple's window back with nested corners), Mac on 0.4.329. **Next round, first: full transparency on visionOS
terminals was lost with Apple's default window (cfd5094) — see the task note's last entry.**
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
