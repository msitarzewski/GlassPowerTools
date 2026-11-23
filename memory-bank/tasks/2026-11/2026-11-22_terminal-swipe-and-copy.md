# A program with the mouse: swipe on iPhone, ⌘C on the Mac (2026-11-22)

## Task
- **Ask (the owner, 2026-11-22):** a terminal tab wouldn't scroll on the iPhone; on the Mac, ⌘C wouldn't copy
  from it, while the right-click menu's Copy did. His screenshot showed Claude Code's "1 new message (click) ↓"
  pill.
- **Authorization:** fix and install as usual; no commit or push without his word.
- **Owner:** this session. Files: `Sources/GlassTerminalEmulator/SwiftTermHostView.swift`,
  `UITests/TerminalSwipeOnIPhoneUITests.swift`, `RELEASE-NOTES.md`, `site/help/terminal-tmux.md`.

## What the tab was running (read-only `ps`/`lsof`; his tmux servers untouched)
- Claude Code 2.1.329, started 2026-11-19, in a session of the app's own tmux server on his Mac; no SSH variables in
  its environment, so it counts itself local.
- **Its full-screen renderer, with the mouse.** In 2.1.329's bundle the "N new message(s) (click) ↓" pill is drawn
  only on macOS with its mouse tracking on ("full"). His user setting says `"tui": "default"`.
- **Why this tab alone (found 2026-11-23): it is a Claude Code background session.** On 2026-11-21 at 18:35
  local the tab's Claude Code started Claude Code's daemon (`claude daemon run`, its `spawned-by` naming that
  process) and the conversation moved into it: the old transcript stops that second, and the live one is served
  by a `bg-pty-host` in the daemon's own pseudo-terminal (`TERM=xterm-256color`, no `TMUX`). Since 2026-11-23
  05:03 the pane runs `claude agents` (the agent view), which shows it. Claude Code 2.1.330's own answer to
  `/tui classic`, in that session's log: "Background sessions always use the fullscreen renderer while attached;
  the classic renderer will apply to sessions started directly with `claude`." The other Claude Code tabs are
  plain `claude`/`claude -c`. Ways back (his call; his sessions untouched): resume the conversation directly
  with `claude` once the background one is stopped, or the `disableAgentView` setting
  (`CLAUDE_CODE_DISABLE_AGENT_VIEW=1`) to turn off agent view, `--bg`, `/background` and the daemon.
- In that mode Claude Code selects with the mouse itself, copies a selection when the mouse is let go
  (`copyOnSelect`, on unless set otherwise; `pbcopy` when local, tmux `load-buffer -w` and OSC 52 too), and copies
  on Ctrl+C or Super(⌘)+C while it has one. Its hint for native selection is Shift on terminals like ours.

## iPhone and iPad: a swipe now turns the program's wheel (0.4.643)
- **Cause.** `UIKitAlternateScreenScrollWatcher` began on iOS only with the mouse off; with it on, SwiftTerm's own
  pan (`panMouseGesture`, made in `mouseModeChanged`) sent the finger's drag as the mouse's, which Claude Code takes
  as a selection. Vision Pro has turned it into wheel steps since 2026-10-15.
- **Fix.** One rule on every UIKit platform: the watcher begins on the alternate screen when the session takes
  the scroll or a program has the mouse, and sends wheel steps (a step per three rows) where the session doesn't.
  On iPhone/iPad, SwiftTerm's new mouse pan takes only `indirectPointer` touches, and the watcher refuses those
  while a program has the mouse, so an iPad trackpad's click-drag stays the program's. A tap still clicks. The app
  doesn't set `UIApplicationSupportsIndirectInputEvents`; if pointer clicks arrive as direct touches, a vertical
  click-drag scrolls instead (not checked on an iPad).
- **Test that bites:** `TerminalSwipeOnIPhoneUITests` on an iPhone 17 Pro simulator (iOS 27.2), `--demo-open
  terminal-tmux` (mouse asked for, `DemoWheelAnswer` shows `[wheel up]`/`[wheel down]`). Before the fix: failed,
  "a swipe down didn't reach the program as its wheel" (screen drawn, no answer). After: see Validation.
  Runner: `~/Software/glass/tmp/uitest-swipe.zsh <tag>`.

## Mac ⌘C: explained, not changed
- With the drag the program's, the terminal has no selection; SwiftTerm validates Copy on its own selection, so ⌘C
  beeps. The right-click menu selects the word under the pointer first, so its Copy works on that word.
- ⌘ can't reach Claude Code as a key inside tmux: tmux 3.8 has no kitty keyboard protocol (its manual has only
  `extended-keys`), and in control mode the terminal's own answers are withheld, so Claude Code never turns it on.
- Asked of the owner: after a drag in that tab, does ⌘V paste it (Claude Code's own copy)? If so, ⌘C need only stop
  refusing there; if not, the copy isn't reaching the clipboard and that is traced next. Shift-drag (SwiftTerm's
  bypass) should select with the terminal; not yet checked against Claude Code.
- Not done, his call: a program's clipboard write (OSC 52), refused by the engine since it was written, is how a
  remote Claude Code's copy would reach the Mac.

## Validation
- iPhone simulator UI test: before failed (above); after passed (23 s): a swipe down showed `[wheel up]`, a swipe
  up `[wheel down]`, and nothing was selected. Vision Pro's path is the same code, now unconditional; it compiled
  in the 0.4.643 build, its own UI test wasn't re-run.

- 0.4.643 built for macOS, iOS and visionOS and installed on his Mac (running 0.4.643, no crash report), iPhone and
  headset, 2026-11-22 21:45.

## His answer (2026-11-23)
- ⌘V pastes after a plain drag, so Claude Code's own copy reaches the clipboard; ⌘C still beeps. Planned: ⌘C
  stops refusing when a program has the mouse and the clipboard has changed since the drag in that terminal;
  it still beeps when nothing was copied. After the tmux host work (his order).

## Next
- His try of the swipe on the iPhone; the ⌘C change above.
