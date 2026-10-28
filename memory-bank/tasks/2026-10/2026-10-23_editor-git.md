# Git and diffs in the editor (2026-10-23)

`<work>` is the working-files folder outside the repository (scripts, logs, captures).

## Task
- **Ask (the owner, 2026-10-23):** "We really, really need git support and diffs in the editor now. I'd like to be
  able to see 'this' instead of having to open Zed or something just to see it." He reviews changes in another
  editor today; the editor should show them.
- **Authorization:** local edits, tests, builds and installs, as for every ask while he tests. No commit, no push.
- **Owner:** this session. Files: `Sources/GlassEditor/Git/*` (new), `GlassEditorFileAccess.swift`,
  `GlassEditorWorkspace.swift`, `GlassEditorWorkspaceView.swift`, `GlassEditorDocument.swift`,
  `Sources/GlassShell/GlassCapability.swift` (the lister's command), `Sources/GlassSSHTransport/SSHTransport.swift`
  (`run`), `Sources/GlassTerminal` listers, `App/GlassPowerToolsApp.swift` (wiring).

## Reuse check
- No git code existed. `GlassEditorProjectOverview` only notes a `.git` folder, and says why it did not run
  `git status`: the editor reached a project through `GlassEditorFileAccess`, which could not run a command, and a
  status that worked only for local folders would disappear over SSH.
- The terminal already runs commands on a host: `SSHTransport.execute` (Citadel exec channels, W21 permits), used for
  tmux. The editor's remote projects already ride `GlassHostDirectoryLister` on the terminal's own connection
  (`GlassTerminalCapability.openDirectoryLister`), which holds the `SSHTransport`.
- The Mac app is not sandboxed (`App/GlassPowerTools.entitlements`), so it can run `git` itself.
- `TerminalTmux.quoted` is the POSIX quoting that also reads in fish.

## Decision
Run the real `git` where the files are, rather than reading `.git` in Swift: one exec per refresh, and git's own
rules (ignores, renames, attributes, worktrees, index versions) instead of a reimplementation of them. Zed and VS
Code both shell out to the git binary for this. A project gets its runner from its file access: the Mac's `git` for
a local folder, an exec channel for a remote one, on every device. A local folder on an iPhone, iPad or Vision Pro
has no `git` to run, so it shows no git UI.

## What was built (not committed)
- **Transport:** Citadel F12 `executeCommandCollecting` (exit status, stdout and stderr apart; F10's limits;
  `PATCHES.md`), because `executeCommand` throws on the first byte of stderr and git warns there.
  `SSHTransport.run` → `SSHCommandOutput`. `GlassHostDirectoryLister.runCommand` (default: unavailable), on the
  terminal's lister (`transport.run`, 60 s, 32 MB) and the reconnecting lister (a command on a gone connection is
  made again; `SSHTransportError.notConnected` now counts as gone).
- **Editor, `Sources/GlassEditor/Git/`:** `GlassEditorGit.swift` (runner protocol; `GlassEditorLocalGit`, macOS
  only, Homebrew's git or `/usr/bin/git` only with developer tools installed, both streams read at once, 60 s,
  32 MB; `GlassEditorRemoteGit`, `git -C dir args` with POSIX quoting; the commands, every output-shaping setting
  on the command line); `GlassEditorGitStatus.swift` (porcelain v2 `-z`); `GlassEditorGitDiff.swift` (unified
  diff, hunks read by their counts, C-quoted names); `GlassEditorGitRepository.swift` (per project: prefix once,
  status, diffs while Changes is open, untracked files read whole up to 100 × 512 KB, the tree's maps, coalesced
  refresh, errors that say the fix: no git, `safe.directory`, git too old); `GlassEditorChangesView.swift` (the
  Changes tab, `GlassEditorGitMark`, `GlassEditorBranchButton`).
- **Wiring:** `GlassEditorFileAccess.gitRunner` (local: macOS only; remote: `command:`), the workspace's
  `repositories`, `showChanges`, `openChangedFile`, refresh after saves and on coming forward; a Changes document
  (`changesOfProject`, `isText`); the footer's branch button; tree marks; Text ▸ Show Changes (⌃⇧G); the app's
  remote access passes `lister.runCommand`.
- **Docs:** RELEASE-NOTES Next, `site/help/editor-projects.md` "See what changed (git)", the registry summary and
  the editor page's card.

## Validation
- Editor target: 187 tests pass, with 3 git suites (parsing, repository against a scripted runner, this Mac's git
  in repositories made for the test: modified, untracked, deleted, no commit yet, no repository). Shown failing
  when broken: hunk counting (a removed "-- a/x" line), the subfolder prefix, the `notConnected` reconnect.
- Citadel `WithExecTests` 12 pass (3 new F12). Terminal lister tests 11 pass. Shell 356, SSH transport 86 pass.
- The full terminal suite ran while the machine's load average was near 800 (another VM at ~300% CPU for
  38 h): the live tmux search test and three editor local-read tests timed out; the local-read tests pass
  alone (0.4 s). The terminal suite's other issues were not read (output filtered); rerun when the load is lower.
- The macOS VM never got an address (three starts): no virtual network bridge was made on the host at all, and no
  vmnet messages were logged; the host's lease for its MAC dates from 00:02. Not fixed: it is the Mac's network
  service, not the project's. Instead the real `GlassEditorWorkspaceView` was drawn offscreen in a scratch test
  (an `NSHostingView` in a window never shown), on a demo repository in `<work>/gitdemo` with the
  real git: the tree's marks and folder dots, the footer's "main 4", the overview's "main, 4 changed files",
  and the Changes tab. **It caught a defect:** rows identified by position in nested `ForEach`es drew blank in a
  `LazyVStack` wherever a later file repeated an earlier one's positions (a hunk's heading and first lines, a new
  file's lines). Fixed with one row list per file with ids unique across the tab (`DiffRow`); drawn again, every
  row shows. Pictures: `.scratch/shots/editor-changes.png`, `editor-changes-overview.png`. The marks' colours
  were not seen: a never-key offscreen window draws its sidebar without colour (the folder icons grey too).
- Afterwards: a line opens its file in the provisional tab; "Git" rather than "No commits" while first asking;
  no "+0"/"−0"; local git runs on a dispatch queue, not the concurrency pool; the overview's git row opens Changes.

## State
0.4.519 installed 2026-10-23 19:20: the Mac reads 0.4.519 and runs, no new crash report; the iPhone has it; the
Vision Pro was unreachable (CoreDeviceError 4016). Not committed. Terminal suite rerun at a lower load: 986 tests,
two failed in the full run (`MacLocalPaneScaleTests`, `LiveTmuxControlResizeTests`, both a live local shell's or
tmux's timing) and pass alone (3 tests, 2.7 s). Open: his use of it on the Mac; gutter marks in the text and
stage/commit if he wants them.

## Gutter marks and stage/commit (his "add gutter marks and stage/commit too", 2026-10-23)

**Decided here (his ask names the features; the shape is the usual one):** marks compare the *buffer*, not the
saved file, with HEAD — VS Code's and Zed's behaviour, and the Changes tab's base. Staging is per file (Zed's box:
ticked, dash for partly staged, empty); no hunk staging yet. Commit commits the index; with nothing staged it is
"Commit All" (VS Code's smart commit), which stages everything listed except nested repositories. A project below
its repository's root asks before committing files staged outside its folder, which Changes cannot show.

- **Core:** `GlassEditorCore/Document/LineChanges.swift` — Myers over lines numbered by content, the shared top
  and bottom set aside first; past 2,000 differences the middle is one "modified" change (the trace is O(D²),
  kept in 32-bit). Lines split as `LineIndex` does (LF, CR, CRLF) on the bytes: Swift's `Character` makes CRLF one
  character, so splitting at "\n" left a Windows file one line (caught by its test).
- **UI:** `GlassEditorModel.lineChanges`; `GutterLineNumbers.drawChangeMarks` (a 3 pt bar in the gap after the
  numbers, from a line's top to the next line's top so wrapped rows are covered; a wedge for a removal);
  colours from the theme (`AttributedAssembly.changeMarkColor`: string green, number amber, error red — the
  package rule is no literal colours); both engines observe `lineChanges` and refresh the gutter.
- **Editor:** `GlassEditorLineMarker` per open text document in a project with git (workspace
  `updateLineMarkers`, called on open, close, save-as, save-new, project open/close): reads the base once per
  HEAD commit and file status (`repository.committedText`, `git cat-file --filters HEAD:<path>`, a rename's old
  name, "" for untracked/added, nil for ignored), compares 150 ms after typing pauses, off the main thread.
- **Repository:** `stage`, `unstage`, `stageAll`, `unstageAll`, `commit(includingOutside:)` → `CommitOutcome`,
  one at a time (`isWorking`), each followed by a refresh; pathspecs `:(top,literal)`; nested repositories
  excluded with `:(exclude,top,literal)`; `reset -q --` to unstage (works before a first commit, unlike
  `restore --staged`); `commit --quiet -m`. Refusals say the fix: no identity, `index.lock`, nothing staged, a
  hook's first line from either stream. `commitMessage`, `actionProblem`, `lastCommit`.
- **Changes tab:** a commit bar (message 1–6 lines, Commit/Commit All on ⌘↩, Stage All/Unstage All with a box,
  "N of M staged", the last commit), a box per file with accessibility actions, the "outside the folder" alert.
  ⌘↩ is also the Query menu's Run Statement (disabled outside a database window); a window's own key equivalent
  is offered before the menu's, as the terminal's paste sheet's ⌘↩ already relies on — not yet tried in the app.
- **Tests:** `LineChangesTests` (10), `ChangeMarkGutterTests` (real engine in an unshown window, both text
  systems, pixels read back), `GlassEditorGitCommitTests` (5, scripted), and 3 more against this Mac's git
  (stage/unstage/commit/commit all; the outside-the-folder question; marks following typing, save and commit,
  an untracked file all green, marks cleared on close). Shown failing when broken: CRLF splitting, no drawing
  call, no observer (TextKit 2's redraw check — a layer-backed view keeps the request on its layer), no marker
  started on open, no outside check. Editor core 328, UI 120, editor 195 pass.
- **Seen:** drawn offscreen on the demo repository: the bars beside typed and changed lines, and the commit bar
  with one file staged. Pictures `<work>/git-gutter.png`, `git-commit-bar.png`.
- **Not done:** hunk staging or reverting from the gutter; marks while line numbers are hidden (the gutter is 0
  wide then); push and pull.
- **State:** 0.4.520 built for all three (21:35): the Mac reads 0.4.520 and runs, no new crash report; the iPhone
  has it; the Vision Pro was unreachable again (CoreDeviceError 4016). Not committed. Next: his use of it; ⌘↩ in
  the running app beside the Query menu's ⌘↩.

## Push, pull and fetch (the owner, 2026-10-28: "build the git integration into the editor as we'd planned")
What was left from 10-23: push and pull (hunk staging, reverting from the gutter and marks with line numbers hidden
are still not done).
- **Commands** (`GlassEditorGitCommand`): `fetch --quiet`; `pull --no-rebase --ff-only --quiet` (a merge or a rebase
  is a terminal's decision; `--no-rebase` sets a configured `pull.rebase` aside); `push --quiet`; a branch with no
  upstream published with `push --set-upstream` to `origin`, or the only remote; `remote`; `diff --name-only -z` between
  the commits a pull moved across. Ten minutes for these (`networkTimeLimit`): the runners take a time limit now
  (`GlassEditorGitRunner.git(_:in:timeLimit:)`; the shell's `GlassHostDirectoryLister.runCommand(_:timeLimit:)`, the
  one-argument form a minute as before).
- **Repository:** `fetch`, `pull` (answers the files changed, as project paths), `push`, `networkAction`, `canPush`,
  `canPull`; push and pull ask git for the status first. Refusals in words that say what to do
  (`networkProblem`): a host key not known yet, the remote not letting the machine in, the remote unreachable, a push
  the remote is ahead of ("Pull first"), a pull that can't fast-forward ("both moved on"), local changes or untracked
  files a pull would overwrite, no upstream, no remote, ten minutes up.
- **Workspace:** `pull(_:)` reads again every open file the pull changed: one with no unsaved edits takes it at once;
  one with edits keeps them and says so (its save asks which to keep).
- **UI:** the Changes tab's top line has Pull N, Push N (only past zero) and Fetch, or Publish Branch; "Pulling…" and
  the like while one runs; a problem shows under the top line even with nothing left to commit. The footer's branch
  button stays a button (a click shows Changes) with ↑N ↓N beside the count, and Pull, Push, Fetch or Publish Branch
  on a right-click or a hold. As a `Menu` its label lost the count and the arrows: a Mac draws a menu's label as one
  title (seen drawn offscreen, then fixed).
- **Tests:** against this Mac's git with a bare repository as the remote: published, pushed, fetched, pulled, and an
  open file taking the pull; a push the remote is ahead of and a pull that can't fast-forward, both refused in words,
  nothing merged. Scripted: no remote, a refused key, an unknown host key, an unreachable host, ten minutes up. Each
  seen failing with its part broken (the reload alone too). Editor 198, core 325, UI 115, shell 371, terminal 1038.
- **Seen:** the editor window drawn offscreen (a throwaway test, removed) with a repository one ahead and one behind:
  "main ↓ Pull 1 ↑ Push 1" and Fetch on the top line, "main 1 ↑1 ↓1" in the footer (`<work>/git-remote.png`).
- **Installed (2026-10-28):** 0.4.544 on all three devices, each read back; the Mac runs it with no new crash report.
- **Not seen:** a push or a pull over a server's SSH connection (the same commands through the exec channel); the
  headset.
