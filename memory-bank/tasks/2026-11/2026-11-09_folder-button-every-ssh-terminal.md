# The folder button on every SSH terminal (2026-11-09)

**Asked:** "Where is my folder icon for this connection!?", with a picture of a Mac window whose SSH tab (not in tmux)
to an Ubuntu 24.04 server had no Open Folder Here in its toolbar. Its title was the Ubuntu prompt's
`user@host: /var/www/…`. **Owner:** this session. **Authorization:** local fix, tests, build and installs; no commit or
push without his word.

## Cause found
- `TerminalWindowView` drew Open Folder Here only when `reportedFolder != nil || session.survivesClose`, and
  `reportedFolder` took the terminal's OSC 7 value only when it began with `/`. Shells send OSC 7 as
  `file://host/path` (the app's own shell integration does too, `TerminalShellIntegration`), so outside tmux the
  button never appeared. Since 1f5f74ba (2026-09-13), whose note said "A remote shell already reports its directory
  over OSC 7".
- The demo that the UI tests drive (`--demo-open terminal-tabs`, `App/GlassDemoMode.swift`) reported a bare path,
  which no shell sends, so the tests saw the button.
- And bash on a Linux server sends no OSC 7 at all: Ubuntu's prompt names the folder in the window title instead
  (`\u@\h: \w` in `/etc/skel/.bashrc`; Fedora's and Arch's `%s@%s:%s`).

## Fix
- The button is always there on an SSH terminal. What it opens is found when it is pressed
  (`TerminalSession.workingDirectory`): tmux's answer in tmux; else `shellFolder`, which takes the OSC 7 URL as a path
  (`TerminalRepository.path(fromReported:)`, already used by the repository lookup), else the folder the last
  prompt's title named, `~` made the account's home (asked as `locate` asks, now `homeFolder()`). A shell that says
  nothing opens Files at home; Open Folder in Editor opens home then too.
- `TerminalShellTitle` (GlassTerminalEmulator): reads `user@host: folder` / `user@host:folder` only; not a program's
  title, a chroot's `(name)…`, or bash's shortened `~/.../src`. Another account's `~` is not resolved.
- `SwiftTermHostModel.titleFolder` keeps the last prompt's folder while a program's title (Codex, vim) stands in
  front of it. Not published, as the title isn't.
- Callers that wrapped `workingDirectory` in `path(fromReported:)` no longer need to (Watch Log File, path actions,
  the Mac workspace's repository lookup). That lookup now gets the title's folder too, so an SSH tab outside tmux
  may show its repository and branch in the Mac's tab list; not checked.
- The demo reports `file://alpha/home/ann/shop`, as a shell would.

## Validation
- `TerminalShellFolderTests` (6; the hosted-terminal case on the Mac only). **Seen failing first:** with the old
  pass-through of the OSC 7 value, "file://box/home/ann/my%20app" stayed a URL; with the title's folder replaced on
  every title, Codex's title lost `/srv/app`. Both pass with the fix.
- The test VM's Ubuntu 26.04 prompt, live over SSH: titles `user@host: ~`, `…: /var/log`, `…: ~/.config`, the
  shapes read (its `/etc/skel/.bashrc` line 69 sets `\e]0;…\u@\h: \w\a`).
- `GlassTerminalTests`: Mac 1,249, iPhone and Vision Pro simulators 853 each, all passing.
- 0.4.612 (Release) built for all three; on the headset and iPhone (read back 0.4.612) and the Mac (09:17, read
  back, running, no crash reports).
- **His look on the Mac: "It worked!"** (2026-11-09, the SSH tab to his server reopened on 0.4.612).
- UI tests that press the button, run before the release commit (Debug, `<work>/uitest-612/`):
  `GlassTerminalOrnamentUITests` on the Vision Pro simulator (27.2), 13 of 13 passing, the press-and-hold menu among
  them; `GlassTerminalToolsIPhoneUITests` on the iPhone 17 Pro Max simulator (27.2): `testOpenFolderInEditorShowsTheEditor`
  failed in the first run, then passed 3 of 3 alone and 2 of 2 in the class's order, and failed again 1 of 1 in the
  next class run. See below.

## Found: a tap on Tools sends the app to the home screen (iPhone simulator, open)
- **What fails:** the test taps Tools and never finds Session. The run's screen recording shows the terminal, then
  the home screen in the next frame (no animation) as Tools is tapped; the app keeps running (its screen tree answers
  every query, the same process is ended at teardown), and the later taps go to a window no one sees. No crash report.
- **Not from this work:** `64b4fa1d` (0.4.610), built in a worktree and run the same way, failed 3 of 5 class runs,
  twice in this test and once in `testToolsRowsSayWhatTheyDoAndReachSettings` (no Open Folder Here in the menu), with
  the same recording: the terminal, then the home screen.
- **What the simulator's log shows at the tap (11:49:29):** the touch reached the app's window and SpringBoard sent
  gesture actions for it too; SpringBoard was launching its wallpaper (poster) extensions in the same 100 ms, as it
  does after a boot. xcodebuild boots the simulator for each run and shuts it down after.
- **Cause not found.** Next: the log from the app's scene (`UIScene` activation state) through a failing run, and the
  same tap on a simulator left booted between runs; then whether a phone ever does it.

## Help and docs (2026-11-09, his "update the memory bank, docs, help, etc. commit. Ship it!")
- `site/help/terminal-sessions.md`: Open Folder Here (it said "once the remote shell reports its current directory")
  and Open Folder in Editor (home when the shell doesn't say); the Paste section said a Mac pastes text only, wrong
  since ⌘V of a picture (0.4.607); a new "Suggestions as you type": type-ahead (D102, 0.4.607–0.4.609) had no help.
- `site/help/terminal-settings.md`: four pages, and a Suggestions section from `TerminalTypeAheadSettingsView`;
  `registry.json`'s two summaries.
- RELEASE-NOTES (what it holds at 0.4.612, suggestions in it, the eighth release line), README (0.4.612,
  suggestions), the site's pages at 0.4.612, a Suggestions card and a limit on the terminal page. The site built;
  every internal link and anchor resolves.
