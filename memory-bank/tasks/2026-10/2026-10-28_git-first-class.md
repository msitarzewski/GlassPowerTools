# 2026-10-28 — Git in the editor, end to end ("build git now, end to end, first class (diff viewer, all of it!)")

**Owner's ask (2026-10-28):** after "Did github get integrated 100% front to back?" was answered "not yet", he asked to
build git end to end, first class. **Authorization:** local edits, tests and builds; Mac build installed when ready.
Commit and push only at his word.

**Reuse:** builds on the 2026-10-23 editor git (`2026-10-23_editor-git.md`): the real `git` where the files are,
`GlassEditorGitRepository`, the parsers, the Changes tab, the gutter marks. Nothing in the obsolete source apps had git.

## What is built (local, not committed)
- **Runners** (`GlassEditorGit.swift`): standard input for `git apply -` (a Pipe here; `/usr/bin/printf '<octal>' |`
  over SSH, 192 KB ceiling); `GIT_EDITOR=true` locally and `env GIT_EDITOR=true` remotely for commands that must not
  open an editor; every new command's argv in `GlassEditorGitCommand`.
- **Models and parsers** (`GlassEditorGitRefs.swift`): branches (for-each-ref with upstream, ahead/behind, gone),
  tags (annotated vs light), stashes, remotes and their web pages (GitHub, GitLab: commit, file at line, branch,
  pull/merge request), commits (NUL fields, U+001E records) and graph lanes, blame porcelain, the operation under
  way (rebase-merge/apply, MERGE_HEAD, CHERRY_PICK_HEAD, REVERT_HEAD).
- **Patches, words, rows, conflicts** (`GlassEditorGitPatch.swift`): a hunk or chosen lines as a patch (forwards
  keeps unchosen removals as context and drops unchosen additions; reverse the other way about); word highlights
  (token LCS, skipped under 30 % in common); side-by-side rows; conflict markers (diff3 base too) and resolution.
- **Repository** (`GlassEditorGitRepository.swift`, `GlassEditorGitOperations.swift`): staged and unstaged diffs
  apart; context lines (3, 10, whole file) and ignore-whitespace; operation and its detail ("trunk: 1 of 1",
  MERGE_MSG's line); amend; hunk/line stage, unstage, discard; discard files (index restore, `clean` for new files);
  branches (switch, track a remote branch, create, rename, delete with the not-merged question, push/publish,
  delete on the remote); merge, rebase, pull merging or rebasing, cherry-pick, revert, reset soft/mixed/hard;
  Continue/Abort/Skip; conflicts read, resolved (write with the stat expectation, then stage) or taken whole;
  tags; stashes (with new files via `^3`); paged history, a file's history (`--follow`), a commit's diff; blame.
- **Workspace**: git tabs (`GlassEditorGitPage`: Source Control, Blame, History of a file), `showSourceControl`,
  `showGit`, `git(_:_:)` which re-reads open files a checkout/merge/stash/discard changed (clean ones reload, dirty
  ones keep their edits and are named).
- **UI**: Source Control tab (branch menu, remote buttons, Changes/History/Branches/Stashes/Tags, the operation
  banner with Abort/Skip/Continue, the problem line with Dismiss, every question in one alert); Changes with
  Conflicts / Staged / Changes groups, per-file box, Discard, context menu (Blame, File History, Open on GitHub,
  Copy Path), the diff body (unified or side by side, word highlights, hunk bar Stage/Unstage/Discard Hunk, line
  numbers choose lines, "Stage N Lines"), Amend; History with graph, refs, paging, details and actions; Branches,
  Stashes (with each one's diff), Tags; conflict resolver (Ours/Theirs/Both either order, Save and Mark Resolved);
  Blame tab (runs per commit, age shade, commit → History) and a file's History tab.

- **Also built:** the Mac **Git** menu (⌃⇧G moved there from Text; no new keys); Blame / File History / Show
  Changes in the tree's menu; Clone (File ▸ Clone Repository… with a progress panel, and Clone Repository Here… on
  any folder, local or remote, through the project's runner); a marks-only 8-pt gutter with line numbers off
  (`GlassEditorModel.showsChangeMarks`, set by the line marker; both engines).
- **Help:** a page of its own, `site/help/editor-git.md` (registered; the projects page points to it; the editor
  page's card and the README link it). Release notes: 0.4.549's entry, not released.

## Validation
- `swift test --filter GlassEditorGit`: 61 tests in 7 suites pass (19 reading tests without git, 17 real-git
  workflow tests incl. clone and a stash kept out of History, the earlier 24, the renders when asked).
  `GlassEditorTests|GlassEditorUITests`: 351 tests pass (a marks-only gutter test added to the AppKit suite).
- **Bites proven** by breaking each and restoring from saved copies: the chosen-lines rule, MERGE_HEAD, the reload
  after a checkout, the combined-diff guard, the remote GIT_EDITOR, the graph's lane reuse (a test added first),
  History without the stash, the marks-only gutter, the marker setting it.
- **Rendered** (`GlassEditorGitRenderTests`, run with `GLASS_GIT_RENDER=<dir>`, pictures in `<work>/git-render`):
  every part, a conflict, side by side, narrow, Blame, a file's History. Found and fixed from them: a file both
  staged and changed lost its second header (two ForEach lists shared ids), History showed the stash's commits
  (`--all` → `--branches --remotes --tags HEAD`), uneven graph widths, local `a/b` branches coloured as remote,
  Blame rows of uneven height, side by side cramped when narrow (falls back to unified under 700 pt).
- **Not verified:** the real app on a device; a project on a server (the remote runner's stdin is proven by the
  printf round trip, not against a server); iPhone/Vision Pro layout of Source Control.

## Installed
- **0.4.549** built for all three (Release, `build-install.zsh 549`) and installed on the Mac (reads 0.4.549 / 549,
  running), Vision Pro and iPhone (devicectl exit 0). No new crash report (the newest is 2026-10-25's).

## Remaining
- His look in the app, on the Mac and against a server project; iPhone and Vision Pro layout of Source Control.
- Commit and push at his word (scanned for private names: clean; a render fixture's `Scratch.swift` renamed).
