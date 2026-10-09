# 2026-10-08 — Terminal find, new tabs, tmux names, workgroups and editor windows: plan

**Owner:** the owner. **State:** BUILD (owner, 2026-10-08: "go with your recommendations, commit each piece as it lands, but do not relaunch the app yet. Using it for real work right now"). Every open decision below is taken as recommended. **Mac builds are built but not installed until the owner says so.** Research is done, read-only, by five agents. tmux was tried
only on isolated `-L` servers, which were killed afterwards. Nothing has been built yet.
**Authorization:** local edits, tests and builds once the owner says go. Mac builds install when
ready (standing). iPhone and Vision Pro installs, commits, pushes and history rewrites need the
owner's word. SSH checks run against the scratch VM only.

## What the owner asked (2026-10-08)

1. Find in the terminal is "weak/doesn't work at all" (tested in tmux).
2. The toolbar's folder button on a local pane should open a Finder window in the shell's folder.
3. "New terminal with the + brings up a blank panel."
4. Connect (the play icon, by click, tap or pinch) "should always surface a new terminal
   connection" — "ping tmux to see what the next int is".
5. Workgroups don't account for tmux.
6. Only one editor can be open; opening a second "dies in a silent whisper".
7. ⌘O in the editor should choose a file or a folder.
8. (Added mid-turn) Dragging a tab to another window "makes a copy of the tmux session instead of
   moving it".

## Findings

### 1. Find
- **Wiring:** there are two find bars that have drifted apart:
  - the local Mac pane: `macOS/MacLocalTerminalPaneView.swift:293-331`;
  - SSH and every other platform: `TerminalWindowView.swift:1565-1625`.

  Both call SwiftTerm's `findNext/findPrevious` through `SwiftTermHostModel`
  (`GlassTerminalEmulator/SwiftTermHostView.swift:654-673`). On the Mac, ⌘F is "Find in Pane…"
  (`MacWorkspaceCommands.swift:227`). On iPhone, iPad and Vision Pro, find is only in the tools
  menu. Escape does not close either bar. ⌘G belongs to Terminal Grid (`MacWorkspaceCommands.swift:127`).
- **Cause A — output erases the hit.** SwiftTerm's `feedPrepare` clears the selection on every chunk
  while `allowMouseReporting` is on, which is its default (`AppleTerminalView.swift:2744-2750`). The
  selection is both the highlight and the place the next search starts from, so after any output,
  Next starts again from the oldest line.
- **Cause B — search starts from the oldest line.** The first hit is the oldest match, not the
  newest.
- **Cause C — tmux.** Attached under `TERM=xterm-256color`, tmux runs on the alternate screen.
  SwiftTerm searches only that screen's rows, including tmux's status line, and its scroll-to-hit
  returns early there (`TerminalViewSearch.swift:106`). tmux redraws its status line every 15 s,
  which triggers cause A as well. So in tmux, find effectively never works.
- **Verified on tmux 3.7c:** `copy-mode ; send-keys -X search-backward-text -- T ; display -p
  '#{search_present} #{search_count} #{scroll_position} #{copy_cursor_y}'` works as one call. tmux
  scrolls to the hit and highlights it itself (current match magenta, others cyan, "(N results)"),
  and its redraws keep that highlight. Quirks found:
  - `--` is needed before a term that starts with `-`;
  - a trailing `;` must be escaped as `\;`;
  - in emacs `mode-keys` (the default), reversing direction lands on the same match, so the step
    has to be sent once more;
  - a miss leaves the pane in copy mode, so it must be cancelled.

### 2. Folder button
- This is already built and shipped in 0.4.300: "Open Folder Here" runs `NSWorkspace.open` on the
  shell's folder (`MacLocalTerminalPaneView.swift:170-174, 550-560`). The system log shows Finder
  coming forward at 11:32 today after a click. The Mac app is not sandboxed.
- **Likely defect:** when the tmux question gets no answer, the pane silently uses the tmux
  *client's* folder, which is where the session started and never moves (`:496-501`). Failing that,
  it uses Home. A folder that has since been deleted does nothing at all. This breaks commit
  967749f's own rule: no answer means unknown, never the stale value.
- **Open question for the owner:** what did they see — nothing, Home, the wrong folder, or Finder
  behind other windows?

### 3. The "+" blank panel
- **Most likely cause:** the toolbar "+" and ⌘T create a deliberately empty tab
  (`MacWorkspaceTabRequest(startsEmpty: true)`, `MacWorkspaceController.swift:1171`). It shows the
  chooser "New Terminal — Choose how to start this terminal tab" (`MacWorkspaceView.swift:746-770`),
  and nothing starts until a button is clicked. This was inherited from glas.sh. ⌘N, by contrast,
  opens a shell straight away.
- **Latent cause (read, not reproduced):** panes added after the window opens are started only by
  their view, once. `SwiftTermLocalProcessHostView.makeNSView` starts the engine only when that call
  created it (`SwiftTermHostView.swift:4012-4048`). If the first host view is torn down before its
  deferred start runs, the process never starts and no error shows: a terminal with no prompt.

### 4. Connect and the "next int"
- **Connect already opens something new every time,** on every platform
  (`GlassTerminalCapability.swift:441-457`, `SessionManager.swift:391-430`, `TerminalConnectFlow.swift:318, 492-525`).
- **Root cause of landing in an existing session:** naming happens in two steps — list the sessions,
  pick the lowest free `glass-N`, then `new-session -A -s NAME` — and `-A` silently *joins* a session
  that already has that name (`TerminalTmux.swift:107-109`, `MacLocalTmux.swift:155-157`). Verified:
  - `-A` on an existing name attached a second client;
  - `new-session -d -s NAME` exits 1 with "duplicate session";
  - eight concurrent claim loops got eight different names.
- **On the Mac it is worse:**
  - a failed `list-sessions` reads as "no sessions" (`MacLocalTmux.swift:68-82, 214`);
  - a name restored from a saved tab or opened from Active is never reserved (`:58-61`).

  So a new local tab can be given the running `glass-1`, the session the owner works in.
- **Also:**
  - a second Connect while the first is still connecting is dropped (`TerminalConnectFlow.swift:541`);
  - the SSH reserved-names set is never released (`Models.swift:864`).

### 5. Workgroups and tmux
- `LayoutPreset.SessionIntent` has no tmux name (`Models.swift:2040-2160`). Opening a workgroup
  therefore makes fresh sessions every time and leaves the old ones in Active, on the Mac
  (`MacWorkspaceState.swift:775`) and on iPhone and Vision Pro (`TerminalConnectFlow.swift:426`).
- Mac SSH panes cannot hold a tmux name at all: the decoder rejects one (`MacWorkspaceState.swift:96-99`).
- The workgroup editor rebuilds every intent (`WorkgroupEditorView.swift:98-118`), so a new field
  would be lost on edit.
- **Hazard:** `attachTmux` always types the startup command after attaching (`Models.swift:872`). A
  reattach would type it into whatever is running, such as Claude Code.
- **D51 defect (verified):** `LayoutPreset.modifiedAt` is missing from `CodingKeys` and `encode`
  (`Models.swift:2338-2389`), so it is never saved. After a relaunch the sync clock falls back to
  `createdAt` (`SettingsManager.swift:1721`). An edit that has not been sent yet can lose to an older
  copy.

### 6–7. Editor windows and ⌘O
- **The scene is fine.** It is a value-keyed `WindowGroup(id: "editor", for: UUID.self)`
  (`GlassEditor/GlassEditorScenes.swift:427-434`).
- **Cause:** every project opens into `frontmostWindowID ?? UUID()` (`:205-237, 291-310`). The second
  project is appended to the first window's workspace (`GlassEditorWorkspace.swift:544-596`), where
  nothing shows it: the title, footer, overview and switcher read only `projects.first`, and the tree
  has no section header. That is the "silent whisper".
- **A second silent path, inferred:** only the Connections window listens for "present this editor"
  (`App/GlassPowerToolsApp.swift:356`). With Connections closed, the Files browser's Open in Editor
  may show nothing.
- **⌘O** is files only, and ⌥⌘O Open Project… is folders only (`GlassEditorScenes.swift:486-489, 542-559`).
  iPad and Vision Pro have two separate importers and no ⌘O. There, folder access is released
  while the tree is still loading (`GlassEditorProjectsPanel.swift:302`), and the window's folder
  importer never starts it (`GlassEditorWorkspaceView.swift:139`).

### 8. Dragging a tab copies its tmux session
- **The move itself is clean.** The same tab controller moves, carrying its `localTmuxSession` and
  its runtime. Nothing on the drop path allocates a name or copies an intent
  (`MacWorkspaceController.swift:1234-1288`, and `MacWorkspaceTabDragTests.moving` asserts it).
- **Likely cause (verified in code, not reproduced):** `MacWorkspaceView.init` builds a new
  `MacWorkspaceWindowController` on every init (`MacWorkspaceView.swift:51`), and `@State` keeps
  only the first. Every controller adds itself to the weak `live` table (`:1049`). The drop then
  finds its source with `live(windowID:)`, which takes whichever match comes first (`:1238`).
  - A scratch probe showed SwiftUI keeps the last discarded object alive, so the table can hold a
    twin. The twin restores the same tabs, pane ids and session names from defaults, but has no
    runtimes.
  - If the drop takes the twin's tab, the window on screen keeps its tab and its tmux client. The
    destination builds a new runtime and runs `new-session -A` on the same name, which makes a
    second client: two windows mirroring one session.
  - The twin's init also persists the window and lists tmux sessions, which are side effects of a
    view init.
- **Not verified:** when the app re-runs that init for an open window. A parent re-render with an
  unchanged request did not, in the probe. Candidates are a window opened twice with one id (the
  reopen-after-quit path beside SwiftUI's own restoration) or a changed request value.
- **Question for the owner:** after the drop, is the tab still in the first window, with typing in
  one appearing in the other? Or does the destination show a fresh prompt under another
  "Terminal N"? The first answer confirms the twin; the second points outside the drag.

## The owner's answers (2026-10-08, after the first plan)

1. **Find "returns nothing today".** ⌘G should be Find Next. Terminal Grid moves to ⌥⌘G — "that was
   my call before, but it needs to be option command g now" — so Carousel, which holds ⌥⌘G today,
   needs a new shortcut. **Decided.**
2. **Folder:** retested with tmux on, the button opens Home. The cause is in how the folder is
   found; research is reopened.
3. **"+":** the chooser is what used to show, but now the empty tab draws nothing at all. That is a
   regression; research is reopened. Whether "+" should open a shell at once is not answered yet
   (the recommendation stands).
4. **Connect:** "Connecting to [a server] from the iPhone joins an existing session. If I want an
   existing session, I should choose one from the 'Active' connections in the left side bar with a
   disclosure that shows active tmux sessions or terminals. Otherwise, I want a new session … when I
   click connect." **Decided:** Connect always opens a new session, and existing sessions are chosen
   from Active. The iPhone's join is now an observed defect; research is reopened.
5. **Workgroups:** "this needs a solution… but opening a workgroup on iPhone would be a challenge."
   The iPhone's presentation is being researched.
6. **Editor:** "Each new project should appear in its own editor window." **Decided:** one project per
   window.
7. **⌘O:** "why do we have that distinction … we've just asked the user to remember something that
   can be decided at selection time." **Decided:** one Open… for files and folders, and ⌥⌘O goes.
8. **Drag:** "I've confirmed it several times … Maybe just tmux though." The copy is real and
   repeatable; finding its trigger is reopened.

## Root causes found after the answers

- **Over SSH, the same locale bug makes Connect join an existing session** (verified on tmux 3.7c,
  isolated servers). This is the iPhone's join, the headset's landing in `glass-1` (open since
  2026-10-08), and very likely why Active lists a Mac host's sessions only after a manual Connect.
  - The app sends environment requests only on the PTY channel (`SSHShellChannel.swift:69-74`). Exec
    commands get the host's default locale, which on a macOS host is none.
  - `listCommand` ends `2>/dev/null; exit 0` (`TerminalTmux.swift:63-68`), so any failure, or a reply
    turned to `_`, comes back as a successful empty list.
  - `nextName` then picks `glass-1`, and the typed `new-session -A` joins it. `unlistedName` is never
    reached.
  - **Fix (W0):**
    - `-u` on every tmux command the app builds: list, current path, scroll, kill, the attach line,
      Mac `run` and the pane's launch arguments;
    - a UTF-8 `LANG` for local runs;
    - a listing that fails, or prints lines that don't parse, is a failure, never "no sessions".
- **The folder opens Home because the app runs tmux without a UTF-8 locale** (verified).
  - The app is started by launchd with no `LANG`, `LC_ALL` or `LC_CTYPE`.
  - `MacLocalTmux.run` passes that environment to tmux unchanged (`MacLocalTmux.swift:207`).
  - In a non-UTF-8 locale, tmux replaces the tabs in its `-F`/`-p` output with `_`. Coordinator check,
    read-only, against the live server: `glass-1_1` without a locale, `glass-1→1` with
    `LANG=en_US.UTF-8`.
  - `parseContext` needs four tab-separated fields (`:113`), so the context is nil. The pane then falls
    back to the tmux client's folder, which is the session's `-c` folder (Home)
    (`MacLocalTerminalPaneView.swift:500`).
  - **The same failure also explains, in the installed app:**
    - Active's This Mac list is empty, because `TerminalTmux.parse` drops every line;
    - `allocateName` and `isRunning` see no sessions, so a new tab can be given a running `glass-N` and
      join it;
    - tab names from tmux never arrive.

    Tests missed it because they run from a terminal that has a locale.
  - **Fix (now W0, first):** tmux is always spawned with a UTF-8 locale. This is the same rule the
    pane's own client already follows (`MacLocalTerminalPaneView.swift:688`). A reply that is not
    empty but cannot be parsed is a failure, never "no sessions". A tmux pane never falls back to
    the client's folder.
- **Find "returns nothing"** (verified with SwiftTerm 1.20 alone): visible text on the alternate
  screen is found, but one spinner frame clears the hit before it is drawn. `findNext` returned true,
  so no "No match" appears either. Text that has scrolled into tmux's history is genuinely not found.
- **Shortcuts:** ⇧⌘G is free; Carousel moves to ⇧⌥⌘G (free; the overview's picker also reaches it).
  Find, Find Next and Find Previous should belong to the shell and go to the focused window, the
  same way ⌘S does (D37), because the editor wants ⌘G too. ⌘G with the bar closed opens it with the
  last term, from the pane or the system find pasteboard. The command-centre labels at
  `MacWorkspaceView.swift:349,351` and `site/help/terminal-sessions.md` must change with it.

- **The empty "+" tab is invisible, not missing** (mechanism shown by an offscreen probe; the owner's
  setup is inferred).
  - The chooser (`MacWorkspaceView.swift:746-770`) has not changed since it was written. Its text and
    buttons use system colours, which follow the window's appearance, but it sits on the terminal
    theme's canvas.
  - With a dark theme under Light appearance, it draws 0 visible pixels: icon, title and both buttons
    all vanish.
  - **Fix:** the empty state takes the theme's colour scheme, reusing `themeColorScheme` from
    `TerminalWindowView.swift:1276-1282`. Test: render it offscreen under `.aqua` with a dark theme
    and count the bright pixels; today there are 0.
- **The drag's twin controller comes from SwiftUI** (shown by a probe; not yet observed in the app).
  - When a scene update hands `MacWorkspaceSceneRoot` an *equal* request that has been through a JSON
    round trip (`GlassTerminalScenes.swift:48-56`; a `WindowGroup(for:)` value is Codable because
    SwiftUI encodes it), `MacWorkspaceView.init` runs again. It builds a second controller, which
    stays alive beside the `@State` one and joins `live`.
  - The drop then sometimes takes the twin's tab. The twin's `detachTabForMove` also persists its
    stale tab list, or deletes the window's saved record if that was its last tab.
  - **Not tmux-specific in the code:** a plain tab would arrive as a fresh shell, and an SSH tab as a
    second connection. Only tmux mirrors the original, so only tmux reads as "a copy".
  - **Fix:** one controller per window id, from a cache asked first in `MacWorkspaceView.init` and
    dropped on close. Drag sources are resolved through `MacWorkspacePreviewRegistry`, and `live`
    goes.
  - **Tests:**
    - two constructions from one request give one instance;
    - a hosted `MacWorkspaceSceneRoot` re-rendered with a round-tripped equal request leaves one
      controller for the id (2 today);
    - the drag identity test.

## Principles

- **tmux is always asked in UTF-8, and a reply it cannot read is a failure.** It is never "no
  sessions", and never a fallback to a stale value such as the client's folder or Home.
- **New means new.** Connect, "+", ⇧⌘T and a workgroup pane with no saved name *take* a name with an
  atomic claim: `new-session -d -s`, which fails on a duplicate, then the next number. The claim
  answers *created* or *exists*, and only *created* runs a startup command. Joining an existing
  session happens only when the owner asks for it: Active's Open or Take Over, or a workgroup's saved
  name.
- **For a tmux pane, tmux is the truth.** Scroll (done), find, folder and tab name all ask tmux.
- **One find bar, two sources:** SwiftTerm's buffer, or tmux's own search. Find, Find Next and Find
  Previous belong to the shell and go to the focused window, as ⌘S does (D37).
- **One controller per terminal window, and one project per editor window.**

## Workstreams

Each workstream is one agent in its own git worktree, branched from the latest commit. Agents never
commit. The coordinator brings each tested diff over, runs every suite, and owns the memory bank.

| W | Items | Owns | Shared files (region only) |
|---|---|---|---|
| **W0 tmux locale and honest listing** — first | 2, 4, Active | tests in `TerminalTmuxTests` and `MacLocalTmuxTests` | `TerminalTmux.swift` (every command builder, `parse`, `listCommand`); `MacLocalTmux.swift` (`run`, its environment, `arguments`, `sessions`); `Models.swift` (`listTmuxSessionsRetryingOnce`'s handling of a failure) |
| **W1 Find and its shortcuts** | 1 | new `TerminalFind.swift` (sources, controller, the SSH runner as an extension), new `TerminalFindBar.swift`, new `TerminalFindTests.swift` | `SwiftTermHostView.swift` (find section and the engines' find methods); `MacLocalTerminalPaneView.swift` (`localSearchBar`); `TerminalWindowView.swift` (`terminalSearchOverlay`, tools-menu Search); `MacWorkspaceCommands.swift` (⌘G/⇧⌘G Find Next/Previous; Grid → ⌥⌘G; Carousel → ⇧⌥⌘G) and the shell's find routing; `MacWorkspaceView.swift:349-351` (labels); `MenuBarPlacementTests.swift` (one-owner checks); `MacLocalTmux.swift` and `TerminalTmux.swift` (one appended builder each) |
| **W2 Folder** | 2 | new `macOS/MacLocalShellFolder.swift` and its tests | `MacLocalTerminalPaneView.swift` (`shellDirectory`, `openFolderHere`, the button) |
| **W3 New tabs and one controller per window** | 3, 8 | new `MacWorkspaceNewTabTests.swift`; `MacTerminalOverview.swift` (registry) | `MacWorkspaceController.swift` (window controller: `addTab`, `live`, tab moves); `MacWorkspaceView.swift` (`init`, `addTab`, drop handlers, the empty state's colour scheme); `MacWorkspaceCommands.swift` (⌘T fallback); `MacLocalTmux.swift` (reopen record); `SwiftTermHostView.swift` (`SwiftTermLocalProcessHostView` start); `MacWorkspaceTabDragTests.swift` |
| **W4a Claiming names** | 4 | — | `TerminalTmux.swift` (claim script); `Models.swift` (`attachTmux`, `LayoutPreset` coding of `modifiedAt`); `MacLocalTmux.swift` (`allocateName`, `session(saved:…)`); `MacWorkspaceController.swift` (the `allocate:` call) |
| **W4b Workgroups keep their sessions; lazy on iPhone** — wave 2 | 5 | `WorkgroupEditorView.swift`, `TerminalWorkgroupsView.swift`, `WorkgroupRestoration.swift`, `MacWorkspaceState.swift`, `VisionTerminalWorkgroupView.swift` | `Models.swift` (`SessionIntent`, a session that starts disconnected); `TerminalConnectFlow.swift` (`openVisionWorkgroup`); `SessionManager.swift` (create without connecting); `MacWorkspaceController.swift` (`capturePreset`, `prepareSSHPaneIfNeeded`); `SettingsManager.swift` |
| **W5 Editor** | 6, 7 | `GlassEditorScenes.swift`, `GlassEditorWorkspace.swift`, `GlassEditorWorkspaceView.swift`, `GlassEditorProjectsPanel.swift`, new `GlassEditorWindowRoutingTests.swift` | `MenuBarPlacementTests.swift` (⌥⌘O goes); `GlassTerminalScenes.swift` (a presenter on the Files window) |
| **W6 Active shows what runs** — wave 2, after the owner looks | 4 | `GlassShell/GlassActiveConnections.swift`, `TerminalRunningSessions.swift` | `GlassConnectionUI/GlassConnectionLibrary.swift` |

**Order.**
1. **W0 first.** It is small, it unblocks the diagnosis for 2, 4 and Active, and the Mac install
   follows at once, so the owner sees Active, the folder button and tab names working.
2. **Wave 1, in parallel from W0's tree:** W1, W2, W3, W4a, W5.
3. **Integration order:** W4a → W3 → W2 → W1 → W5. After each one, the terminal, shell and editor
   suites run.
4. **Wave 2:** W4b, then W6 once the owner has looked at Active with W0 in place.
5. **After each wave:** Release builds for macOS, iOS and visionOS and a Mac install (standing).
   Device installs are on the owner's word.

## Proposed changes

**W0 — tmux in UTF-8, and listings that tell the truth** (all platforms)
- `-u` on every tmux command the app builds. Local `run` also gets `LANG=en_US.UTF-8` when no locale
  is set, the rule the pane's own client already follows.
- `listCommand` stops turning a failure into an empty success: it reports tmux's exit status and
  whether tmux is missing. A listing that fails, or whose lines don't parse, is a failure and falls
  back to the unlisted high name.
- The Mac's `run` tells "no server running" from a failure.
- Only "no server running" (on 3.7c, "error connecting to …") counts as empty. Any other error
  prints a failure marker. A non-empty reply with no parsable line becomes a new `Listing` case,
  `.failed`, which `attachTmux` treats as unlisted (`unlistedName`, never `nextName`).
  `MacLocalTmux.sessions(from:)` and `allocateName` follow the same rule.
- Test: a `TerminalSession` whose `tmuxCommandRunner` answers `glass-1_1_1_1700000000` connects to a
  name of `glass-100` or above. Today it gets `glass-1`.

**W1 — Find** (macOS, iOS, visionOS)
- **One `TerminalFindBar` replaces both bars:**
  - field, older and newer buttons, an "n of N" count, and close;
  - Escape closes it, and Return searches toward older output;
  - ⌘F on iPad and Vision Pro hardware keyboards.
- **Shortcuts on the Mac:** ⌘G and ⇧⌘G are Find Next and Previous, owned by the shell and sent to the
  focused window, so the editor can use them too. Terminal Grid moves to ⌥⌘G and Carousel to ⇧⌥⌘G.
  ⌘G with the bar closed opens it with the last term, taken from the pane or the system find
  pasteboard.
- **SwiftTerm source** (plain shell):
  - the first search finds the newest match;
  - the hit is re-applied after each output chunk while the bar is open, and cleared if the
    scrollback trims past it;
  - the count comes from `searchMatchSummary`;
  - on the alternate screen without app-managed tmux, the bar says only the visible screen is
    searched.
- **tmux source** (local `glass-N` and SSH tmux panes):
  - one chained `copy-mode` / `search-*-text` / `display -p` call per step;
  - `--` before the term, `\;` escaped, the step repeated once in emacs `mode-keys` when the
    direction reverses;
  - cancel on a miss, and on close, which returns to the live prompt;
  - one request in flight, latest wins.

**W2 — Folder** (macOS; SSH keeps the Files browser)
- A testable resolver gives `.folder`, `.missing` or `.unknown`, from tmux's `pane_current_path`, else
  `proc_pidinfo` on the shell, else OSC 7. It never falls back to the client's folder or Home.
- `NSWorkspace.open` is kept and its result checked. *Missing* or *unknown* shows a plain message
  saying what to do.

**W3 — New tabs and one controller per window** (macOS)
- "+" and ⌘T open a local shell at once, in tmux when that is on. They start it with
  `startLocalPanes`, not the view's one-shot.
- A view starts any engine that has never started, so a torn-down host can't strand it.
- The empty state, which is still used for any otherwise-empty tab, takes the theme's colour scheme
  (`themeColorScheme`).
- **One controller per window id,** from a cache asked first in `MacWorkspaceView.init` and dropped
  on close.
  - Drag sources and the reopen record resolve through `MacWorkspacePreviewRegistry`, and `live`
    goes.
  - A window never starts a second client for a session this app already shows; it logs the attempt
    instead.

**W4a — Claiming names** (all platforms)
- `TerminalTmux.claimScript(candidates:directory:command:)` is a POSIX `sh` loop. For each candidate
  it runs `tmux -u new-session -d -s C …`. On failure, `has-session` tells a duplicate (try the next
  candidate) from an error (stop). It prints `created C` or `exists`.
- Candidates are the lowest unused numbers, skipping names saved workgroups hold.
- **SSH:** the claim replaces list-then-`nextName`. The startup command runs only on *created*.
  `reservedTmuxNames` goes.
- **Mac local:** the claim runs with the pane's environment, folder and shell. Restored and
  Active-opened names are reserved.
- `LayoutPreset` saves `modifiedAt`.
- A second Connect press while still connecting stays ignored.

**W4b — Workgroups keep their sessions; lazy on iPhone**
- **`SessionIntent.tmuxSession`:**
  - optional and validated, written with `encodeIfPresent`, no schema bump;
  - travels with D51;
  - Mac SSH pane intents accept a name too.
- **Opening a workgroup claims each saved name.** *Exists* attaches without the startup command;
  *created* runs it. A pane without a name claims one on its first open and writes it back once.
- **Save from a window** captures the live names. The editor draft keeps them, and changing a tab's
  server clears its name.
- **iPhone: lazy slots.**
  - Opening makes one slot per pane, in order, and connects only the one shown.
  - Choosing a slot connects and claims it.
  - Slots already connected stay connected; after the app is suspended, only the visible one
    reconnects.
  - The switcher is labelled with the pane's label, else "Terminal N · server", plus a connected
    dot.
  - The password check stays up front.
- iPad and Vision Pro open every pane as now; the grid and carousel previews need live sessions.
- **Reopening after a quit covers SSH tmux tabs too.** The owner held off a relaunch, "uncertain of
  how the two workgroups I have open would resurface". Today `rememberWindowsToReopen` notes only
  windows with *local* tmux tabs (`MacLocalTmux.swift:166-174`). With "Close windows when quitting"
  on, which is the default here, a window of SSH tabs doesn't come back at all. A mixed window comes
  back, but its SSH tabs start new sessions. Once SSH pane intents carry their names, the reopen
  record uses `hasTerminalsInTmux`, and an SSH pane reattaches to its own session.
- This Mac's panes on another device keep the substitution sheet until D50.

**W5 — Editor** (macOS, iPad, iPhone, Vision Pro)
- **One project per window:** a project already open brings its window forward; otherwise a blank
  front window takes it; otherwise it opens a new window. Loose files open as tabs in the front
  window. The routing is one testable function, `open(urls:)`.
- **One Open… (⌘O) for files and folders,** decided at selection; ⌥⌘O goes. iPad and Vision Pro get
  one importer (`[.folder, .data]`) with ⌘O on its toolbar button. Scoped access is held while a
  project is open, and a per-device bookmark lets a Files folder reopen.
- A presenter on the Files window, so Open in Editor works with Connections closed.
- Blank editor windows are not restored.

**W6 — Active shows what runs** (all platforms; after the owner looks with W0 installed)
- Today Active already shows each machine as an expanded disclosure: open sessions plus running tmux
  sessions, with Open, Take Over and End. It sits in the results column on the Mac and iPad, behind a
  push on iPhone, and in a tab on Vision Pro. W0 alone should make the Mac hosts' sessions appear.
- **Gaps:**
  - the sidebar badge counts open sessions only, so it can read 0 while sessions run;
  - a machine skipped because it would ask for a password is not explained;
  - rows say only "Terminal N", without the tab or workgroup name.

## Tests that must fail before each fix

- **W0 (done, 2026-10-08):**
  - `parse` of `_`-separated output is a failure, not "no sessions";
  - live: `listCommand` through `env -i sh -c` against a private tmux (`TMUX_TMPDIR`) holding
    `glass-1` lists `glass-1`;
  - Mac `run` with no locale lists a private server's sessions and reads its context;
  - every builder's command contains `-u`.
- **W1:**
  - a host model fed "needle 1", filler, then "needle 2": the first find selects the newest, and the
    hit survives one spinner frame;
  - exact builder strings;
  - the reply parser;
  - live tmux in emacs and vi `mode-keys`: walking older and newer reaches each match once, and a
    miss and close leave `pane_in_mode` 0;
  - the source choice;
  - one owner each for ⌘G, ⇧⌘G and ⌥⌘G.
- **W2:** tmux answers → that path; tmux fails → unknown; deleted → missing; no tmux → the process's
  folder; odd names reach the opener exactly.
- **W3:**
  - "+" gives a selected local tab;
  - with the fake server, a `glass-N` no tab holds;
  - a host view rebuilt before its first start still starts `/bin/sh`;
  - the empty state rendered under `.aqua` with a dark theme has visible pixels;
  - two constructions from one request give one controller;
  - a hosted scene root re-rendered with a round-tripped equal request leaves one controller (2
    today);
  - the drag keeps the tab, runtime and session name, and the shown count does not rise.
- **W4a:**
  - a name taken between listing and attaching is skipped;
  - *exists* types only the attach line;
  - a Mac create that fails moves on;
  - eight concurrent live claims give distinct names;
  - `modifiedAt` survives a relaunch.
- **W4b:**
  - `SessionIntent` round-trips, rejects bad names and decodes old JSON;
  - the editor draft keeps the name;
  - the launcher and `capturePreset` carry names;
  - two-device sync carries them;
  - an iPhone workgroup connects only the slot shown.
- **W5:**
  - A then B → two windows; A again → A's window;
  - a file plus a project → a new window;
  - `open(urls: [file, folder])` routes each;
  - `open(folder)` → a project.

**By hand:**
- **Mac:** every item; read the running app's menu bar after the shortcut changes (rule 39); after a
  drag, `tmux list-clients` shows one client.
- **iPhone and Vision Pro**, on the owner's word:
  - Connect twice to a Mac host → two new sessions, `glass-1` untouched;
  - Active lists the Mac's sessions;
  - find over SSH tmux on the scratch VM;
  - a workgroup reopened → the same sessions, the startup command not repeated;
  - two editor panels; the mixed picker.

## Decisions

**Made by the owner:**
- ⌘G Find Next, with Terminal Grid moving to ⌥⌘G;
- Connect always opens a new session, and existing sessions are chosen from Active;
- one project per editor window;
- one Open… for files and folders.

**Taken as recommended by the owner's go (2026-10-08):**
1. "+" and ⌘T: **open a local shell at once** / a tab on the current tab's machine / keep the chooser.
2. Find:
   - Return searches **older**;
   - closing in tmux **returns to the live prompt**;
   - **plain text only**;
   - Carousel on **⇧⌥⌘G**.
3. Folder: a deleted folder **shows a message**.
4. Active, after W0 is installed:
   - the disclosure **stays in the results column** / or becomes an outline under Active in the
     sidebar;
   - the badge **counts running sessions**;
   - skipped machines **are explained**;
   - rows **carry the tab or workgroup name**.
5. Workgroups:
   - one already open here **comes forward**;
   - a second device **joins**;
   - saving **captures live names**;
   - the first open **may write names back** (amends D51's "opening sends nothing");
   - on iPhone, **lazy slots, no cap, a menu switcher** (swipe later);
   - iPad and Vision Pro **unchanged**.
6. Editor: Open Recent **lists folders**; a window with loose files **does not take** a project;
   **bookmarks** for Files folders on iPad.
7. Commits: **commit each workstream as it lands**, in logical pieces, so the next wave's worktrees
   start from it.

## Risks

- **Older installs:** iPhone and Vision Pro (0.4.296) drop a workgroup's tmux names when they rewrite
  it. Update every device together, and dry-run sync first.
- **`-u` and the `-text` searches** are verified on tmux 3.7c only. An older server must give a plain
  failure, never stay in copy mode.
- **A claim that starts a remote tmux server** from a non-login exec `sh` may have a different
  environment. Verify on the scratch VM.
- **A re-applied find hit** at the scrollback limit may point at the wrong row. It needs a test at
  the limit.
- **With tmux on, every "+" leaves a session running** (close detaches), so sessions collect in
  Active.

## Progress (2026-10-08)

| Piece | Commit | Evidence |
|---|---|---|
| W0 tmux in UTF-8, honest listings | eca44d1 | 8 new tests, each proven to fail without the fix. Live tests run on private servers; teardown names its socket with `-S`, because a missing `TMUX_TMPDIR` folder makes tmux fall back to the default server (a first draft of a test reached the owner's server this way, read-only). |
| W3 one controller per window; "+" opens a shell; visible empty tab | 1bfa70e | 9 new tests (twin reproduced in a hosted scene root: 2 controllers before the fix, 1 after) |
| W2 Open Folder Here | 3c1876e | 8 tests with fakes; the mutation table is in the agent's report |
| W5 editor: one project per window, one Open… | 50f6cae | 15 routing tests plus menu-owner checks; iOS and visionOS compile |
| W4a claimed tmux names; startup command only when created; D51 `modifiedAt` | 7054c63 | 11 new tests, including 8 concurrent live claims giving 8 names; iOS compiles |

| W1 find: one bar, tmux's own search, Edit ▸ Find with ⌘F/⌘G/⇧⌘G; Grid ⌥⌘G, Carousel ⌥⇧⌘G | a2a3d6f | 14 tests, including live tmux in emacs and vi `mode-keys`; iOS and visionOS compile |
| Live tests spawn without leaking descriptors (rule 63) | fa3a746 | terminal suite back from 87 s to 11 s; the "known flaky" theme test now passes every run |
| W7b layouts survive a crash; running sessions offered back at launch | ca5af94 | 16 restoration tests; six loss paths reproduced and fixed |
| W7c a tmux pane detached from elsewhere stays and offers Reattach | 5cc28db | policy test proven to fail without it |
| W7a no Workgroups window (D52); SwiftUI alone owns split views (rule 62) | fde5940 | crash not reproduced in a stand-in or the real window under programmatic resizing; the exception is SwiftUI removing a toolbar observer twice inside a re-entered layout |

Installed: 0.4.301 (W0) at 13:08, then **0.4.304** at 14:12 (everything up to W7c), on the owner's
word: "I can't use the app... the windows won't load at all". At launch it offered the 14 running
sessions back, and the owner reopened them all: "They may not be organized the way I had them
(workgroups and so on) but they're OPEN!" **0.4.305** (W7a) is built and waits for the owner's word.
All suites pass: terminal 531, shell 221, editor 132, editor UI 114, database 307, connection UI 30,
connection kit 23.

**State loss, the owner's answers:** no tabs closed by themselves; no Take Over from another
device; Move Tab to New Window was used today. That matches W7b's path B: the window lost its moved
tab after a crash and saved itself empty. It does not account for every tab record having gone.
Nothing in the installed build deletes tab records, so the remainder is unexplained. The new
logging would show it next time.

**In progress:** W4b, workgroups keep their sessions (owner's next step: arrange windows, then save
them as workgroups). **Then:** W6 (Active shows what runs; sessions browser), and D53's spike if
approved. **Seen at 0.4.304's launch, not yet looked at:** "FocusedValue update tried to update
multiple times per frame". W1's `\.glassFindItem` publishes a focused value, so check it first.

**Crash, 13:01–13:05 (0.4.300, four reports, same stack).** An `NSRangeException` came from AppKit when SwiftUI removed a window's toolbar (`setToolbar:` → `_showHideToolbar`) inside a constraint pass. The toolbar's removal handed the first responder back, so a layout ran inside the constraint update. The owner's trigger: Window ▸ Workgroups, then resizing that window. That is a `NavigationSplitView` with a searchable sidebar, whose split view our column autosave also renames on every update, so it has two owners. **W7a:** reproduce outside the owner's app, give each split view one owner, and fold the standalone Workgroups window into Connections. The owner: "It's weird that we have a separate window for that anyway… It's inline in the connections window".

**State loss.** After the crashes, every saved tab record was `{"id","schemaVersion"}` with no root. Each window opened as "New Terminal". The 14 sessions kept running; workgroups (`layoutPresets`) were intact. **W7b:** trace which path wrote empty records over full ones; never overwrite an undecodable or full record by side effect; keep one previous good generation; offer running sessions back at launch.

**Proposed (not approved):** workgroups as tmux sessions through control mode (`tmux -CC`), as iTerm2 does: tmux windows as native tabs, panes as splits, and the layout kept on the host. Also a sessions browser per host (W6). The owner asked whether tmux windows can back workgroup tabs; answered with the two routes and the one-host-per-session limit.

## Second round (2026-10-08 afternoon)

| Piece | Commit | Evidence |
|---|---|---|
| W4b workgroups remember their tmux sessions; Replace or Keep Both; iPhone lazy slots; SSH tabs reattach after a quit | e6476b6 | 17 tests, 22 reverted fixes caught; iOS and visionOS compile |
| W8 select several tabs; Move N Tabs to New Window; Close N Tabs | 247f613 | 9 tests; not yet tried by hand: single-click reliability, multi-tab drag, ⌘W closing only the shown tab |
| W6 Active names sessions as tabs do (one rule, `TerminalSessionNaming`); `@glass-name` on the session carries a tab's given name to every device; this Mac recognised by its tmux server identity (pid, start time, socket), its sessions "Open here"; badge counts running sessions; skipped machines say why | 828300b | 22 reverted fixes caught; live listing on a private server; iOS and visionOS compile |
| W9 Show All Terminals: every window's tabs as live previews, filter, arrows, drag a tile to another window, "Not in a window"; ⇧⌘\, a two-finger pinch in, Window menu, toolbar buttons in Connections and terminal windows | 64418bd | 14 tests; offscreen screenshots checked. **Seen working by the owner on 0.4.308 (2026-10-09): four windows, live tiles, the blur, the selection caption — "Holy smokes. Great job!"** Menu bar and pinch threshold not yet reported on |

Owner's asks behind them: "command click multiple tabs … 'move to new window' with a right click"; "the available
terminal list has default names, not what's showing in the actual tabs"; "Mission Control / Exposé for Terminal
windows *and their tabs*". Three-finger swipes are macOS's own on this Mac (`TrackpadThreeFingerVertSwipeGesture=2`),
so the overview opens with a pinch, as Safari's tab overview does.

Installed: Mac **0.4.308** (2026-10-08 15:34; windows and all 14 sessions came back on their own); iPhone and Vision
Pro **0.4.305**. Older builds strip a workgroup's tmux names when they re-save it, so the next device install should
put all three on the same build. Suites at 64418bd: terminal 585, shell 224, editor 132, connection UI 30.

**Vision Pro crash (W10, in progress).** Two Release crashes at 14:55 on connecting to a server's tmux session:
an over-release inside SwiftUI stack layout (`StackLayout` → `ViewLayoutEngine3D`), main thread, none of our frames,
other threads idle. It is the same signature as 0.4.288–0.4.295. W10's stress harness reproduced it in the visionOS
simulator (15:33; the simulator's crash reports land in the Mac's DiagnosticReports with parent `launchd_sim`).
W10 was interrupted by a connection error and resumed.

**Two tests seen hanging once under heavy parallel load** (W8's report; both passed in every later run):
`TerminalHostTrustBrokerTests` "Cancelling everything resumes every waiting caller" (one `Task.yield()` may be too
little), and W1's live tmux find test. Watch for them.
