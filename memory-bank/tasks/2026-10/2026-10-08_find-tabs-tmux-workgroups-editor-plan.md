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

## 2026-10-09 morning

| Piece | Commit | Evidence |
|---|---|---|
| A screenshot's floating thumbnail (a file promise) drops on a terminal and types its path; promised files and bare image data go to `~/Library/Caches/com.glasspowertools/Dropped`, cleared after a week | 5a64360 | 3 tests proven to fail without the fix; the owner's by-hand check pending |
| Two ticket-expiry tests wait for the event, not 30 ms | 4e752f8 | full suite twice |
| macOS window restoration tried (`56f9ce5`, `bcb355a`) and reverted for terminal windows (D54) | 5722124 | a source check that the scene declines restoration |
| **W10 Vision Pro crash fixed** (rule 64): the terminal's UIKit view is built after SwiftUI's layout | 32fa481 | simulator stress harness: old build 17/30 runs crashed, fixed 0/24; two 10-minute soaks; **on the headset, connected to the same kind of session: no crash so far (owner, 2026-10-09)** |

Installed: **0.4.313** on Mac, iPhone and Vision Pro (2026-10-09 ~10:35). The owner regrouped 14 tabs into four windows
with W8's multi-select; two restarts during the restoration detour reopened them empty or not at all; recovered by
putting the four windows back on the reopen list between quit and launch. Positions are not yet kept.

**Owner's asks this morning, in progress:** W11 repo and branch in tab names ("it would be super helpful to have the repo
in there, and branch"); W12 window positions, a reopen list read by whichever window appears first and kept current
while running; W13 multi-select in Active, opening several sessions together in one new window ("like the tab view").
**Answered:** tmux's own overview is `prefix s` / `prefix w` (choose-tree with live previews). **Open question:** sidebar
resizing on visionOS (Mac sidebars are resizable within their ranges; visionOS has no drag handle as far as known).
**Process slip:** a commit went in after a test run with a failure, because the command's result filter always
succeeded; commits are now gated on the run's "passed" lines.

## Backlog and work in flight (2026-10-09, late morning)

**Mac windows, the rest of the restart story.** 69fd170 and 659a820: AppKit neither saves nor replays the app's window
state (the delegate answers no, and `ApplePersistenceIgnoreState` is registered, because under SwiftUI's own delegate the
answers alone did not stop a leftover state from being replayed). 0c89503 logs the reopen list. The log showed the
list is read every time the Connections window's content appears, not once per launch, so a leftover list reopened
windows whose sessions were already shown; their panes were refused as second clients, hence "many … empty" windows.
Leftover list deleted by hand; W12 makes the read once per launch, app-wide, and keeps the list current. Installed:
Mac 0.4.316 (14/14 sessions attached), iPhone and Vision Pro 0.4.313.

| W | What | State |
|---|---|---|
| W11 | repo and branch in tab names, Active, Show All Terminals | running |
| W12 | window positions in the app's records; the reopen list read once per launch by whichever window appears first, kept current while running (a crash reopens the same windows) | running |
| W13 | Active: select several sessions, open them together in one new window (owner on the headset: "Multiselect from the Active would be stellar") | running |
| W14 | files into terminals on Vision Pro, iPad and iPhone: drag from Photos and Files, upload over SFTP to `~/.cache/glass-power-tools/dropped/` on the host, type the remote path; HEIC to JPEG; the same for Mac SSH terminals; Insert Path in the Files browser | running |
| — | sidebar resizing on visionOS (Mac sidebars resize within their ranges) | to check against the SDK |
| — | the screenshot drop on the Mac (5a64360): owner's by-hand check | pending |
| — | "Failed to synchronize portable settings" (`GlassSettingsSyncError` 3) logged at every launch | to look at |
| D53 | tmux control mode spike | proposed |

The owner, from the Vision Pro: "I'm in vision pro, just like I'd envisioned when all of this started." No headset crash
since 0.4.313.

## Status when the owner closed the laptop (2026-10-09, ~11:30)

- Landed since the backlog note: d68056e (a screenshot thumbnail drop trapped: the file-promise block was main-actor code
  called on AppKit's queue; now nonisolated and Sendable, test proven to SIGTRAP without it), 29f016d W13 (multi-select in
  Active, open together), and the W12 commit (window places in records; reopen list taken once per launch by any window,
  kept current while running; `isRestorable = true` in `MacTerminalWindowPolicy` had undone the scene's opt-out — the real
  cause of the empty restored windows). Suites: terminal 610, shell 231.
- Installed: Vision Pro and iPhone **0.4.318** (W13); Mac **0.4.317** (the W12 build not yet installed: the owner was
  about to close the laptop). Next Mac install should be the first with W12; check the `Reopen:` log lines after it.
- Running: W11 (repo and branch; also names across devices via `@glass-name` on iOS/visionOS), W14 (drops into terminals
  off the Mac, SSH uploads, Insert Path).
- Note: crash reports for the app stopped being saved on this Mac after ~25 in a day (simulator crashes count); use the
  log (`launchd` "exited due to SIGTRAP") when no report appears.

## W11 and W14 landed (2026-10-09, afternoon)

Both merged onto main by patch (`git apply -3 --index`, clean), built, and committed only after every test run passed
(terminal 647 tests in 50 suites, shell 231 in 46).

- **50e56dc, W14 — files into terminals off the Mac.** On Vision Pro, iPad and iPhone a terminal takes drops from Files,
  Photos and other apps (SwiftUI `.onDrop`, so nothing UIKit is built in an update: rule 64). Each item goes up through
  the Files browser's own verified, no-clobber upload to `~/.cache/glass-power-tools/dropped/<yyyy-MM-dd>/` on the host
  (folders 0700; a taken name becomes `name-2.ext`, so typed paths need no escaping for parentheses). The host's
  absolute paths are typed, escaped, never run; a file that did not arrive types nothing. HEIC/HEIF goes as full-size,
  upright JPEG (orientation applied to the pixels); if conversion fails, the original goes and the terminal says so.
  Status and plain-word failures show in the terminal's bottom-right corner; a disconnected terminal refuses the drop.
  Day folders older than a week are cleared once per connection (real directories only, `lstat`, links never
  followed). A Mac SSH pane uploads and types the host's path; a local pane is unchanged. The Files browser of a
  terminal gains Insert Path (context menu; Insert for a selection). `SFTPIncomingDrop` now accepts any content or data
  type that arrives as one file (a zip from Files was refused), which also widens the browser's own drops.
  New: `TerminalRemoteDrop.swift`, `TerminalRemoteDropTests` (9 tests, each shown failing under a mutation that removes
  its fix). Not yet seen on a device: the drop on visionOS, Photos' item providers, Insert Path bringing the terminal
  forward. Limits: `$XDG_CACHE_HOME` not honoured; the host needs OpenSSH's `hardlink@openssh.com`, as the browser does;
  Mac Insert Path does not bring the window forward.
- **dc7aa67, W11 — repo and branch in names; names on every device.** A terminal in a git repository is named by it:
  the repository stands in for the folder and the second line reads `app · main · Sources`, in Mac tab rows, the window
  title, Active and Show All Terminals (typing a branch or repository finds the tile). On the Mac the repository is read
  from the files (`.git` folder or `gitdir:` file, worktrees named by their main repository), never by running git,
  never at or above home, never on a non-local volume (mount table read with `MNT_NOWAIT`). Over SSH the host is asked
  once per folder change with one `sh -c` (no git, no developer tools: no answer, no install prompt). Each tab keeps
  `@glass-repo`/`@glass-branch` on its tmux session; the listing is now **15 fields**. On iPhone, iPad and Vision Pro a
  terminal in tmux reads `@glass-name`, the pane title, folder and repository in one command after attaching and when
  output settles (at most every 5 s, never while idle); every headset label (tab ornament, tab bar, grid, carousel,
  connection ornament) and the iPhone switcher use one rule (`TerminalWorkgroupOpening.label(_:on:)`). Rename Tab… and
  Use Automatic Name are there too and set `@glass-name`. Finding: tmux 3.7c's `display-message` answers a missing
  session with empty fields and exit 0, so the read checks `has-session` first. New: `TerminalRepository.swift`,
  `TerminalRepositoryTests` (18), `TerminalSessionNamesTests` (8), 2 in `MacLocalTmuxTests`, each shown failing without
  its fix. Limits: a Mac tab adopts `@glass-name` once, when it attaches (a later rename elsewhere shows after it
  reopens); Mac SSH-in-tmux tabs don't show the pane's program title yet; other devices can show a stale branch for a
  session no tab shows; reftable repositories show no branch on the local reader. Rename menus on iOS/visionOS are
  compile-only until seen on the devices.
- **Test notes.** `TerminalOutputObservationTests` "output coming to rest is announced once per burst" fails only under
  heavy parallel load (load average 30–40, its 10 ms sleeps stretch to 20–37 s); it also failed so at 0c89503, passes
  alone and passed in both merge runs here (load 7–11). `TerminalTmuxTests.claimingLive` leaves its private `-S` tmux
  server alive until its `sleep 600` ends (never the default server, rule 63).
- **Installed 0.4.319** (W11 + W12 + W14) on the Mac and iPhone, 12:19. The Mac's first W12 launch: `Reopen: 4 listed,
  0 already open, 0 not saved, 4 reopening`, then each terminal window's ask "already taken at this launch"; 15 of 15
  tmux sessions attached; no crash report or launchd exit line. Vision Pro refused the install while asleep (CoreDevice
  error 4016); it stays on 0.4.318 until the retry.

## After 0.4.319 (2026-10-09, afternoon)

The owner, using 0.4.319: W14 works on the iPhone (a screenshot dropped from Photos reached Claude Code over SSH).

- **6065016 — the crash after `exit`.** `exit` ended a window's last terminal (tmux over SSH); the window closed, then
  SwiftUI's next update of its views ran the window reader's `configure` again: the closed window went back into
  `MacWorkspacePreviewRegistry` and the reader's coordinator became its delegate again, with SwiftUI's delegate gone.
  Show All Terminals offered it ("New Terminal", "Empty tab"); choosing it brought the torn-down, transparent window
  forward ("an invisible window"), `windowDidBecomeKey:` sent to the forwarding coordinator raised "unrecognized
  selector" (twice, caught by AppKit, from `MacTerminalExpose.choose` and `.close`), and the next window update trapped
  (PAC failure) in `Coordinator.observedWindowDidUpdate`. Report `Glass Power Tools-2026-10-09-124250.ips`, 0.4.319.
  Fix: `MacTerminalWindowReader.closedWindows` (weak) is filled at `willClose`; a closed window is never configured,
  observed, delegated or registered again, and the registry's entries never return a closed window. Coordinator
  `deinit` removes its observers. `MacTerminalWindowCloseTests` (2 tests) fail without it (5 expectations).
- **deb5d2f — Active's count at launch.** Only Active asked the machines, so the sidebar said 0 at launch ("once you
  go in it updates to 15"). The library asks as it appears and when the app returns to the front, unless answered in
  the last 5 minutes (`refreshRunningSessionsIfDue`). Test fails without the throttle.
- **b390920 — right-click menu in Mac terminals** (owner: "we don't have any contextual menus in terminal"):
  `MacTerminalContextMenu` — word under the pointer selected unless inside the selection, Look Up, Copy, Paste (the
  view's own reviewed paste), Select All; `validRequestor`/`writeSelection` hand the selection to Services (send only).
  `MacTerminalContextMenuTests` (5) through the real remote view, each failing without its override. Not verified:
  whether macOS adds a Services submenu to this context menu by itself (a probe popping the menu in a test hung);
  the owner's "Paste Text" is not built yet (Terminal's "Paste Escaped Text" is the likely meaning, to confirm).
- Suites: terminal 654 tests in 52 suites, shell 232 in 46, all passed. Building 0.4.320.
- **Installed 0.4.320 on the Mac** (13:10): `Reopen: quitting with 4 windows listed`, then 4 reopened once; 15 of 15
  sessions attached; no crash report or exception. The iPhone refused it while locked (CoreDevice 4016).
- **a28dc68 — Active's name for a terminal on the headset.** Owner, on the Vision Pro (0.4.320): Active's row said
  "Terminal on <host>" while the window had the terminal's name. Connect on iOS/visionOS makes a workgroup named after
  the server, and Active titled the row with it. A workgroup with one terminal and the server's name is now titled by
  `TerminalWorkgroupOpening.label(_:on: .active)`; a named workgroup, or several terminals, keeps its name. Test fails
  without it. 0.4.321 installed on the iPhone and Vision Pro (relaunched); Mac stays on 0.4.320 for now.
- **54a66d5 — Active empty at launch on the headset.** Owner: "the Active didn't auto populate... I had to refresh it"
  (Vision Pro, relaunched with Active showing). A capability's saved machines come from the catalog, readable only
  after the library loads (`catalogDidLoad`); Active asked first, got nothing, and deb5d2f's 5-minute throttle then
  kept the library's own ask from running. `refreshRunningSessions` now asks nothing before `isLoaded`. Test
  reproduces the empty answer and fails without the fix. 0.4.322 on iPhone and Vision Pro.
- **W15 started** (agent, worktree): tab groups restored on relaunch on Vision Pro and iPad (app-owned records, W12's
  pattern, W13's open-together path), and tabs moved between windows on Vision Pro — the owner: "maybe we do that with
  grid view? drag and drop" — drag a grid card onto another window; Move to New Window / Move to ▸ as fallback.
- **d5b7d2f — Files opened at home.** Owner, on the Vision Pro: the folder button opened Files at the home folder.
  `SFTPBrowserView.connectAndLoad` set home after `initialPath` had been applied (every platform). Now
  `startingFolder(requested:client:)` keeps the requested folder when the host says it is one. Test over the real
  `SFTPClient` and W14's in-memory host fails without it; the one wiring line in `connectAndLoad` is not under test.
  0.4.323 on iPhone and Vision Pro.
- **W16 and W17 started** (agents, worktrees). W16: visionOS `.plain` windows paint square and dark at the corners —
  `GlassLayeredWindow` → `GlassNativeWindowFrame` adds no glass or clip and `GlassLayerBackground(cornerRadius: 0)`
  fills square; plus the Files window's header to match the Mac's modern format (owner). W17: the editor fully
  functional on visionOS (owner: "markdown preview, syntax highlighting etc."), parity audit first.
- **1c7c65c — Open in Editor from a terminal.** Owner: "an Open in Editor option on pinch and hold on the folder icon
  and an open in Editor in the context toolbar item". The folder button's context menu offers Open in Files and Open in
  Editor; the tools ("…") menu has Open Folder in Editor; both use `runtime.openFolderAsProject` (read from the
  environment, optional) with the folder from `workingDirectory(reported:)`. UI only, no unit test; suites passed.
  0.4.324 on iPhone and Vision Pro.
- **ef88118 — selection lost to output.** Owner: "I can't select text in terminals... it seems to be deselected with a
  refresh of screen". SwiftTerm's `feedPrepare` sets `selection.active = false` on every chunk while mouse reporting
  is allowed (`AppleTerminalView.swift:2744`, SwiftTerm 1.20). `SwiftTermSelectionKeeper` takes the selection before
  each feed and puts it back after Find's hit is reapplied, where its text still is (rows shifted by trimmed lines).
  3 tests through the real remote view; mutations (no restore; no text check) fail them. The first full run caught the
  keeper moving Find's hit before Find reapplied it (`TerminalFindTests` scrollback test) — order fixed. 0.4.325 on
  iPhone and Vision Pro.
- **6394fc6 — W15 merged** (D55): tab groups back after relaunch on Vision Pro/iPad/iPhone; tabs move between Vision Pro
  windows (grid card drag, Move Tab to New Window, Move Tab To ▸; iPad menus; iPhone switcher). 16 tests, each failed
  under its mutation (M1–M16 in the agent's report). Suites after merge: terminal 674, shell 234. Untried on a device:
  the drag, menus on the tab ornament, reopen at launch, iPad's new-window handoff. Behaviour change: a Vision Pro
  window whose workgroup disappears now closes. Log: subsystem `sh.glas`, category `reopen`.
- **Mac 0.4.326** installed at the owner's word (23:43): 4 windows reopened once, 16/16 sessions attached, no crash.
- **f70da14 — W17 merged: the editor on Vision Pro.** The editor's toolbar was attached to the `NavigationSplitView`,
  which visionOS does not draw (a column's toolbar it does; the database recorded the same,
  `DatabaseWorkspaceView.swift:722-724`), so Preview, Save, Open…, New, Find, Close, Text Settings and ⚡ were
  unreachable. Highlighting was never excluded (16 grammars and queries ship). Now the detail column's toolbar, as a
  bottom ornament on visionOS. Also: Projects + ▸ New Document / Open… (iPad and Vision Pro had no way in without a
  project; Mac's ⇧⌘E shares `prepareNewEditorWindow`), status-line location, preview background transparent, editor
  text view and SQL focus deferred a turn (rule 64). Suites after merge: terminal 674, shell 234, editor core 117 /
  editor 134 / editor UI 310 (1 known issue), database 307. Open for the owner: ⌘S for the editor's Save off the Mac
  (the database owns ⌘S there, rule 39); 13 pt default text size at headset distance. The agent kept re-sending its
  report with background work running and was stopped. Simulator "W17 Editor Vision Pro" left shut down.
- 0.4.327 on the iPhone; the Vision Pro's battery died (install refused, 4016). Owner: "Keep building while it charges?"
  Started **W18** (settings sync error Code=3 at every launch; never write the real iCloud store) and **W19** (open Mac
  tabs pick up `@glass-name` given elsewhere; Mac SSH tabs in tmux show the pane's program title). W16 still running.
- **02711b3 — W16 merged.** visionOS `.plain` windows (Files, editor) painted a square theme plate
  (`GlassLayeredWindow` `cornerRadius: 0`); now the window's shape: 46 pt measured against the system glass, 24 pt for
  the inset card (`GlassConnectionUI/GlassWindowShape.swift`); Mac/iPad unchanged. Dropping `.plain` made Files and the
  editor nearly black (theme over the window glass), so `.plain` stays. Files on the headset: folder as navigation
  title (system title ornament) with `toolbarTitleMenu` of ancestors; breadcrumb kept off the visionOS bar (it hides the
  title). Untried on the device: the title menu, the 70 pt empty band under the Files toolbar (pre-existing), Reduce
  Transparency. Owner's calls: plain windows show a lighter tint than the library at the same opacity; round the remote
  desktop image or not. Frost does nothing in visionOS plain windows (pre-existing).
- **W20 started** (owner, on the Mac: "a way to give a color/tint to the tab group… It should inherit the settings of the
  first one in the order yes?"; asked, he chose "the window owns it"): one look per terminal window/tab group, set from
  any tab's Settings ▸ Overrides, taken by new and moved tabs, saved with the window and saved workgroups. The local
  tab's gear Settings was a `SettingsLink` to app Settings since Stage 2 — it opens Terminal Settings in W20.
- **Device check, 0.4.328 (2026-10-10):** the owner, on the Vision Pro: "the editor toolbar works on the headset" (W17).
- **SSH limits (2026-10-10, owner on the Vision Pro):** "I think we've hit a cap on open tmux sessions... trying to open
  the same sets of windows here and get an error about not being able to connect". On the SSH server (the owner's Mac,
  default OpenSSH): one `sshd-session` from the headset carrying 8 PTYs — every terminal to a host shares one connection
  (`SessionManager.reusableConnection`), and `MaxSessions 10` counts shells plus the app's short exec channels; when a
  set opens with nothing connected, each terminal starts its own connection and `MaxStartups 10:30:100` drops those past
  10. **W21 started** (agent): coalesce connection setup per route, cap terminals per connection, limit concurrent exec
  channels, retry a refused channel on a new connection and a dropped connect with backoff, plain-words errors.
- **6293e69 — W18 merged (D56).** Code=3 is `invalidPayload` (payload cases are numbered first). Terminal settings had
  not synced from any current build since bf178ce (2026-09-27): the shared KVS store holds a copy from glas.sh or an
  older build with the old built-in theme id; combining before a send made two built-in themes. Fixed by canonicalising
  both sides first. Logging names the case and detail; Settings caption in plain words. Suites: terminal 676, shell 238.
  Not installed yet (waiting to ship with W21). A stray README.md edit (a trailing space on "What it does", 00:14,
  likely the owner trying the editor) is left uncommitted and untouched.
- **1e80498 — W19 merged.** Open Mac tabs follow `@glass-name` given or removed elsewhere (local: one batched
  `list-sessions` for every local tab, ≤ every 2 s, when output settles; SSH: the tab's own pane read). When a tab
  meets its session, the session's name wins; a nameless session gets the tab's (pre-W6 names now reach other devices).
  Mac SSH tabs in tmux name themselves from the pane (`readsTmuxPane` on for them). Suites: terminal 685, shell 238.
- **d274577 — W20 merged (D57):** window-owned look; local tab gear ▸ Settings opens Terminal Settings; sidebar icons
  and waves take the window's tint; iPad "Window Appearance". Tint now a fixed 12%. Suites: terminal 705, shell 238.
  To check: sidebar selection highlight with `.tint` (unverified), 12% legibility, Vision Pro Overrides on a tab.
- Waiting for W21 (SSH limits); then one build on all three (owner: "install all three when W21 lands").
- **W21 committed** after the screen was unlocked (locked, the file-protected stores refused writes: ~270 tests and a
  SIGTRAP in the shell suite, environment only). Suites: terminal 707, shell 238, SSH transport 82. 6 terminals per
  connection, 2 handshakes and 2 commands per connection at once, retries, plain-words MaxStartups/MaxSessions errors.
  Found, not changed: on a shared connection's loss only one terminal gets `.lost` (the others see their shell end);
  database/desktop tunnels still connect outside the pool.
- **0.4.329 on all three** (09:36): Mac reopened 4 windows, 16/16 sessions attached, no crash; the settings category
  shows only `kvs/synchronize` after launch — no "Failed to synchronize" for the first time since 2026-09-27 (W18). The
  SSH pool logs one line per decision. To confirm on the Vision Pro: opening the usual sets connects every terminal
  (W21), at most 6 ttys per headset `sshd-session` on the Mac.
- **a0310df — This Window first.** Owner, on the Vision Pro (0.4.329): "we still don't have terminal level or window
  level controls. They all change transparency in color and on." The Settings sheet opened on "Terminal" (the global
  settings: tint) with the window's look second as "Overrides"; and the window's outer glass on visionOS comes from the
  app-wide Appearance layers (`GlassLayeredWindow`, `runtime.layers`), which W20's look does not reach — the look sets
  the terminal canvas (opacity, tint, frost/material, blur). Sections are now This Window / All Terminals / Port
  Forwarding, opening on This Window; captions say what each changes. Open question for the owner: should a window's
  outer glass (Appearance's frost/opacity) be per window too on Vision Pro? 0.4.330 to iPhone and Vision Pro.
- **Owner, 2026-10-10, on the Vision Pro:** "I do not want borders.... I like it just the way it is" (a voice-control ask
  I misread as "add beveled glass"; the edit was reverted, nothing committed). "the mismatched radii bothers me" →
  **9b9fc26**: the terminal canvas corner is concentric with the window paint (24−10 = 14 with ornaments, 46−10 = 36
  without; `GlassWindowShape.concentricCornerRadius`, tests fail with the old fixed 18). 0.4.331 to iPhone and Vision Pro.
- **"the original idea was that anything in the system settings could be overridden per window"** — asked the scope, he
  chose **every kind of window now**. **W22 started** (agent): the shared per-window overlay contract, Appearance (glass
  layers) per window, and every terminal setting per window (W20's look migrated). Then W23–W25 adopt it for the editor,
  database and desktop windows.
- **672d32a — corner fits the rows.** Owner, on the headset, of 9b9fc26's 14/36-point corners: "it should be smaller to
  fit in the corner" (a square tmux status line 10 points in; the window edge isn't drawn, so concentric with it meant
  nothing visible). The canvas corner is now concentric with the rows inside it: `visionRowsInset` = 10. 0.4.332 on the
  Vision Pro. W22 told to leave that region alone.
- **Corners, three levels (owner's annotated screenshot, 11:46):** window (the grey frosted paint: inset 22 with a
  24-pt corner — not Apple's shape), output area (black canvas, 10 pt), terminal text (square; 20 pt in at the sides,
  10 at top/bottom). Diagnosed in the visionOS simulator with temporary coloured outlines (never committed): yellow
  window edge 46, red canvas. Proposed to the owner: frosted area fills the window at 46; canvas an even 16 in (30);
  text an even 12 in (18), and whether to round the text area's corners. **Awaiting his answer.**
- **eac2ee7 — W22 merged (D58).** Suites: terminal 720, shell 238, layers 42, connection UI 39. W23 (editor), W24
  (database), W25 (desktop) started on its contract.
- **cfd5094 — Apple's window back, three levels nested.** The owner (annotated capture, 11:46; then "Let's get apple's
  default window back in this mix. It will help me a lot."): the terminal scene drops `.plain` so Apple's window draws
  its glass in its own corner (46); the canvas sits an even 34 pt inside the window edge on every side whatever the
  ornaments (no more jump on focus), corner 46 − 34 = 12; rows an even 12 pt inside, square. The frosted backdrop (the
  grey card he marked, `GlassCanvasBackdrop`, was a 24-pt card around the canvas, shown when the window sets blur) now
  fills the window in the window's corner. Diagnosed with temporary coloured outlines in the visionOS simulator (never
  committed); clean capture sent before install. Earlier "I do not want borders" was about my added glass border; this
  is Apple's default window, which he asked for. 0.4.334 on Vision Pro and iPhone.
- **0788d12 — continuous corner, square rows.** Owner (0.4.334, annotated): black area "too small and still uneven";
  remove the terminal's own radius at tmux's bar. Apple's window corner is continuous (blends over ~1.528 × radius);
  the circular rule (46 − 34 = 12) left the diagonal gap wider (simulator: 64 px vs 46 px at the side). Now
  `GlassWindowShape.continuousConcentricCornerRadius`: 46 − 34 / 1.528 ≈ 24; SwiftTerm view's layer corner 0 on visionOS
  (`SwiftTermHostView.terminalViewCornerRadius`; iPad keeps 18). Side-by-side simulator crop sent; owner on 0.4.335:
  "Yep, I like this much better... good work!" Settled.
- **9e4d304 — W23 merged (editor windows, D58).** This Window in the editor's Settings (gear): opacity (+ frost and
  material off visionOS), text size, line numbers, wrapping; file/project text settings still win over the window;
  ⌘+/⌘−/⌘0 change the window's own size when it has one. Editor windows aren't restored, so settings are kept per
  project on this device (`com.glasspowertools.editor.projects.device-windows`), not synced. Fixed along the way:
  reopening a local project created a fresh record and synced its bare name over the list's record. Suites: editor
  150, editor UI 310 (1 known), editor core 117, shell 238, layers 42, terminal 721. To do once W24/W25 land: the
  `GlassLayerControls` footer and `site/help/library-settings.md` still say only terminal windows keep their own
  settings. Agent stopped after merge (it kept background work running).
- **8574c75 — W25 merged (desktop windows).** This Window in the desktop's settings sheet: opacity (fades the image,
  own key `desktop.opacity`), background frost, presentation/key colour/tolerance/softness, Detail (RDP), Pointer
  (iPad/iPhone); zoom/pan/tilt stay the session's; kept per desktop on this device (`desktop.windows`). Before, that
  sheet wrote device-wide settings, so one window changed every desktop. Suites: desktop 185.
- **a3b35fb — W24 merged (database windows).** This Window: opacity, frost (database draws its own, also visionOS), row
  limit, SQL/grid text sizes, line numbers, JSON formatting; kept per database on this device (`glassdb.windowSettings`).
  The gear did nothing on iPad/iPhone before. Shared Appearance footer + library-settings help now name terminal,
  editor and database windows. Suites: database 317, DBKit 27, plus all others green. Merge conflicts were only demo
  surfaces in `App/GlassDemoMode.swift` and the `shoot.sh` comment (kept both sides).
- Agents' notes left for later: the "This window only" caption (W22's `GlassWindowSettingSource`, `.foregroundStyle(.tint)`)
  is low-contrast blue on the headset's grey glass; detached database results/diagram windows have no This Window.
- **REGRESSION, top of the next round (owner, 2026-10-10 ~13:00):** "We've lost complete transparency... 100% transparent
  glass (the whole point of the app)... when the window is focused... when it's in the background on visionOS it will
  go 100% transparent." Cause: cfd5094 dropped `.plain` from the visionOS terminal scene, so Apple's window glass is
  always behind a focused terminal; the corners now nest inside it. To decide next round: keep Apple's window shape
  but let the glass go when the window's opacity/blur are 0 (e.g. `.glassBackgroundEffect(displayMode:)` on the root,
  `.never` for a clear window — verify on visionOS 27 that it removes the default window's glass), or return to
  `.plain` and keep the nested 34-pt/24-pt geometry with no visible outer edge. Check with the owner before changing
  the look (memory: confirm visual asks).
- **Owner's diagnosis (13:10):** "we're assigning transparency to the terminal (the black part), not the Apple provided
  window on vision OS so the most transparent it gets is Apple's light glass texture." Proposed (awaiting his yes):
  terminal scene back to `.plain`, and draw Apple's glass ourselves (`.glassBackgroundEffect(in: GlassWindowShape.spatialWindow)`,
  same material and bevel, 46-pt shape), driven by the window's **Blur**: 0 → no glass (fully clear), up → Apple's glass
  (faded if visionOS allows; else on/off); **Opacity** stays the black canvas's paint. Opacity 0 + Blur 0 = 100% clear,
  as the help already says. Check in the simulator (fade vs on/off, background-window behaviour) and send a capture
  before installing.
- **Compacting (13:15).** Owner: "Yeah" to the transparency proposal; "i also want to address the settings... we have some
  UX issue in there now." Next session: transparency first (simulator capture before install), then ask what the Settings
  UX issues are, then the Mac install at his word.
- **Transparency restored (D59, 2026-10-10 ~13:40).** Terminal scene `.plain` again; `VisionTerminalWorkgroupView` draws
  `VisionTerminalWindowGlass` (glassBackgroundEffect, 46-pt continuous) once behind the window at `TerminalLook.windowGlass`
  = resolved Blur (Reduce Transparency → 1). `TerminalLook.windowBlur` and the window-frost path removed; the corner
  params added in cfd5094 to `GlassCanvasBackdrop`/`GlassWindowBackground` reverted. Demo arg `--demo-glass <opacity>,<frost>`.
  Simulator captures at Blur 0 / 50% / 100% (opacity 0) and 0.7/1, 0.7/0: fade is smooth; 0 is completely clear; nested
  corners unchanged. Suites: terminal 722 (serial; one tmux naming test flaked in the parallel run, passed serially and
  in the first run), connection UI 40, layers 42, desktop 185. Install waits for the owner's look at the captures.
- **Owner (13:40):** "we still don't have a way to combine two independent terminal windows there's no tab to drag
  between." Confirmed: one terminal → tab bar hidden, no grid, and Move to… lives only on tabs and grid cards. Next.
- **W26 merged (combine Vision Pro windows).** Tools menu ▸ **Move Tab To** (one row; **New Window** inside it — two rows
  pushed Settings below the menu's 640-pt fold at 1200×800) on visionOS and iPad (iPad's tab menu only shows in the
  sidebar, per the SDK); the title ornament is `.draggable(TerminalTabTransfer)`, dropped back on its own window it is
  ignored (`TerminalTabMoves.arriving`). Moves handed down as `\.terminalTabMoving`. Demo surface `terminal-move`.
  Simulator: menu move combined two one-terminal windows, the emptied one closed; title drag lifts, but a cross-window
  drop can't be driven by XCUITest — check on the headset. Suites: terminal 724 (serial), connection UI 40; visionOS +
  iOS simulator builds pass. To check: W15's help line "touch and hold its tab" on Vision Pro may not work either.
- **Owner remote (~14:10); devices unavailable; 0.4.338 built (transparency + W26), install when he's back.**
- **Settings UX decided (owner, ~14:15)**, from a 2×2 capture of the four This Window sheets: "We're literally in a tab
  that says 'This window' ... remove those labels. Move the revert to a tiny icon with a tooltip next to the field's
  label: 'Opacity (r)'"; and of my list (one vocabulary Opacity/Glass/Material; hide rows that do nothing on the headset;
  one sheet layout; bigger sheets on Vision Pro; even footers): "I think the rest is fine, and overdue." → **W27**.
- **Window appearance (owner, ~14:15):** "rebuild all window appearances to match the new terminal. So screen sharing,
  database, etc." → **W28** (visionOS: plain windows drawing the shared glass at their Glass strength, Opacity on the
  content area, the terminal's nested 34-pt / ≈23.75 continuous corners; split views' own system glass is the open
  question). W27 owns settings sheets/rows/help; W28 owns scenes/backgrounds and reports help wording. Captures of both
  go to the owner before anything installs.
- **Owner (~14:30):** "The connections window on vision pro is pretty large and doesn't honor transparency apparently.
  It would be super cool to have it detect idle and minimize itself into an orb ... activates when looked at - restores to
  the full window size." Transparency → added to **W28**. Idle → orb, restore, default size → **W29** (reuses the existing
  `minimized` window and `GlassWindowRecoveryManager`). visionOS gives apps no gaze: the orb can respond visibly when
  looked at (system hover effect), restoring takes a pinch.
- **W28 finding (~14:45):** on visionOS 27 a NavigationSplitView/NavigationStack in a `.plain` window always draws its own
  system glass (UIKit columns report `preferredContainerBackgroundStyle = .automatic`); no public modifier removes it
  (`glassBackgroundEffect(displayMode:)`, toolbar/scroll backgrounds, split styles, TabView wrapping tried;
  `containerBackground(for: .navigation)` unavailable on visionOS). Evidence: `$SP/w28/evidence-navigation-glass.png`.
  Plan approved: shared glass in GlassLayers; desktop full match; split-view windows (database, editor, Files,
  Connections) keep system navigation (D40) with Opacity in the nested canvas; a Database prototype without the split
  view, behind one switch, for the owner to compare.
- **Owner on the orb (~14:40):** "This is a good outcome, much better than auto anything. highlight is th business. can we
  put the active connection count in there?" → W29: count on the orb, required.
- **Owner (~14:55), Vision Pro on a mobile link, sharing a Mac:** "no scaling or bandwidth streaming control / quality
  setting. I see one window with both screens proportionally displayed. I'd like two screens, independently controllable
  like a real desktop setup ... Solve it?" Found: VNCKit always requests the whole framebuffer; `RFBLinkQualityGovernor`
  only moves Tight JPEG quality (nothing adapts if the Mac never sends Tight); `selectedScreenID` shows one display but
  fetches all. → **W30**: one window per display sharing one RFB session, input offset per display, region-limited update
  requests, Quality (Automatic/Best/Balanced/Data Saver: JPEG, colour depth, frame pacing), a live throughput readout;
  proven against the TigerVNC Docker fixture with two screens and a rate-limited proxy; never his real machines.
- **W27 merged (Settings sheets).** Captions gone; `GlassSettingTitle` + `glassSettingReset` environment draw a tiny ↺
  (tooltip "Reset to <source>", id `window-setting-reset.<key>`) beside a set row's name; `GlassSettingLabeled` for system
  controls. Vocabulary: Opacity / Glass (key `appearance.frost`) / Material; Material and Interactive Glass hidden on
  visionOS (keys kept); section headers "Appearance" (This Window) and "Windows" (Settings ▸ Appearance). One
  `GlassSettingsSheet`: Done `.confirmationAction`; visionOS 820×860 (was 760×560), Mac 760×560, iOS `.large`. Desktop's
  "Original" → This Window ▸ Background Removal ▸ Show Original. Shared footers. Suites on main: layers 43, connection UI
  40, terminal 724, editor 150, database 317, desktop 185. Mac/iPad layouts built but not looked at.
- **W28 merged (window appearance, D60).** Shared `GlassSpatialWindowGlass` / `GlassWindowGlass` / nested canvas in
  GlassLayers; terminal uses it (look unchanged); remote desktop matches the terminal (own glass at its Glass, screen as
  the 34-pt canvas, ≈23.75 corner); editor/Files/Connections/database: Opacity on the content column only, system glass
  stays. Database without a split view behind `DatabaseSpatialLayout.ownGlass` (off; `--demo-database-own-glass`).
  Suites on main after W27+W28: layers 48, connection UI 43, terminal 724, editor 150, database 317, desktop 185, shell
  238; visionOS sim build passes. Help: Vision Pro glass wording applied (library, desktop-vision-pro, editor,
  database). Owner's choices pending: database split vs own glass; desktop rounded vs square corners; desktop default
  Glass 25% vs 100%; same treatment for Connections/editor/Files. Editor text view still paints opaque at Opacity 0.
- **W29 applied to main, staged, NOT committed (~16:00): the Mac's screen is locked**, so GlassShell/GlassTerminal/
  GlassDesktop protected-file tests fail with EPERM (desktop's 4 failures are exactly that). Passing now: layers 48,
  connection UI 43, database 317, editor 150; visionOS sim build passes. Commit after the shell, terminal and desktop
  suites pass unlocked. Orb: `>_` in Apple's glass, "⚡ N" from `activeSessionCount()`, hover grows 8% + "Connections";
  idle via `pushWindow` (hidden, not closed), holds for sheets/menus/editing/drag/connecting (10-min cap)/only window;
  Settings ▸ General "Shrink Connections when idle" (Never/1/2/5/10, default 2); Connections 960×700 (was 1280×720).
  Found: `openWindow(id: "main")` with no value opens a SECOND Connections window on visionOS → W29 follow-up (w29b):
  `GlassConnectionsWindow` moved to a shared module + `openConnections()` helper for every caller, with a UI test.
- **W30 applied to main on top of W29, staged, NOT committed (screen locked) — D61.** Conflicts (7 files, one block each)
  resolved: DesktopSessionView keeps W27's `GlassSettingsSheet` (W30's old toolbar dropped; Original is Show Original);
  W27's two new lines in DesktopWindowSettingsView repointed from `session.windowSettings` to `viewport.windowSettings`;
  plain-window inventory gains `DesktopDisplayWindowValue.windowID` with W28's glass/canvas snippets. Passing: VNCKit 54,
  VNC transport 8, layers 48, connection UI 43, database 317, editor 150; desktop 195 with 4 lock-only failures (the
  wallpaper one fails identically on pre-W30 code in W28's worktree). visionOS sim build passes; captures sent.
  **To commit when unlocked:** run shell/terminal/desktop suites; then `git reset -q`, `git apply --cached
  $SP/w29-onmain.patch` → commit W29 (+ w29b if landed), then `git add -A ':!README.md'` → commit W30.
  **Owner's checklist on his Mac over mobile** (W30): Connection ▸ Encoding reads ZRLE (Raw = report); a Displays
  control and a second window, correct crops, clicks land, pointer in the right window (else Console
  `event=apple-display-layout`); Data Saver → Color 16-bit with correct colours; closing display 2 → Fetching "Only the
  displays on screen" and Receiving drops; which level Automatic settles on; Mac menus (rule 34) after the new window group.
- **Committed (~17:00, screen still locked):** f213d4a W29 orb; 928baaa one Connections window (w29b: `GlassConnectionsWindow`
  in GlassConnectionUI, `openConnections()`; 8 orb UI tests pass; the orb's own second-window handling removed);
  ed8f09e tunnel-hop tests given explicit creation dates (were a coin toss: equal dates read back, tie broken by random
  ids; 30/30 alone, 4/4 full after); 2b4f75f W30. Split from one index with `$SP/w29-onmain.patch` and `w29b.patch`
  applied `--cached`. All touched suites pass except `workspaceUsesNativeTitle` (fails identically on pre-merge code
  while locked; no Mac terminal file changed) — rerun when unlocked.
- **Installed 0.4.339 (HEAD b0822da) on iPhone and Vision Pro (~17:20)**, both exit 0; Vision Pro relaunched. Screen
  unlocked 17:18: GlassTerminalTests 724/724 pass, including `workspaceUsesNativeTitle` — the locked-screen caveat on
  f213d4a/928baaa/2b4f75f is cleared. Mac still 0.4.329, at the owner's word.
