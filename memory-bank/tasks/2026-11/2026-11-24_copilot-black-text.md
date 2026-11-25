# GitHub Copilot's replies in black, in tmux (0.4.649)

**Owner:** Claude (coordinator). **Authorization:** the owner's report (2026-11-24, a screenshot of GitHub Copilot's
CLI in a local tmux terminal: its replies unreadable on the dark glass), a defect to fix locally; build, VM test and
installs under the standing authorization. Committed and pushed at his word (2026-11-24, "update the memory bank,
commit, and push. Ship it!"); released in 0.4.650 (Mac, TestFlight 650), 2026-11-24.

## The defect

In a local terminal kept in tmux, GitHub Copilot's CLI (1.0.115, its default theme "github") wrote its replies'
prose in pure black: measured in the owner's screenshot, those glyphs are #000000, while its secondary text is
#9198A1 and its inline code white on #262C36, both exact values from the theme's *dark* half.

## Cause (measured, then read in both sources)

- **Copilot asks the terminal for its colours** (OSC 10 and 11, then OSC 4 for the palette, two seconds each) and
  builds its theme from the answers: dark when the background is no lighter than the text, and its replies' prose
  in the reported text colour itself (`markdownText: t(9)`, the end of a ramp from background to text). Read in
  its bundled script (`~/Library/Caches/copilot/pkg/darwin-arm64/1.0.115/cli-main.js`; functions `eJe`, `Zlr`,
  `jkt`, `f7r`). With "github" it also sets the terminal's background and text to GitHub's (#0D1117 and #F0F6FC,
  or #ffffff and #1f2328) with OSC 11 and 10, and on leaving asks for them back with OSC 111 and 110.
- **In tmux, tmux answers, not the terminal**, and this app drops its emulator's own answers while it is tmux's
  control-mode client (D83, `SwiftTermHostView.swift` `send(source:data:)`).
- **tmux 3.4 to 3.8 answer black for both** when a pane is shown only by control-mode clients: such a client never
  runs `tty_init`, so its `tty.fg` and `tty.bg` stay at calloc's zero, and `window_pane_get_fg`/`_bg` return
  colour 0 instead of skipping it. tmux issue 5843 (PR, closed 2026-11-04; issue 5842), fixed upstream in
  `e6211b411e4e` (2026-11-09, `c->tty.fg = c->tty.bg = -1` in `server_client_create`), after 3.8 (2026-10-08).
  The owner's server runs Homebrew's 3.8 (read with `lsof`, read-only); the VM has 3.7c, the same code.
- So Copilot saw black on black, chose dark, and wrote its prose in black.

## Fix

**This app tells tmux the terminal's colours for each pane it follows** (`refresh-client -r`, tmux 3.5+, made for
exactly this: "for control mode clients to provide OSC 10 and 11 responses", CHANGES 3.4→3.5). tmux then answers a
program with the control client's colours first (`window_pane_get_fg_control_client`), whatever its version's
default.

- `TmuxControlClient` (`Sources/GlassTerminalEmulator/TmuxControlClient.swift`): `TerminalColors`; the colours given
  at creation or by `setColors`; `reportColors()` sends `refresh-client -r "%N:\033]10;rgb:…\007"` and the same
  for 11 on a line of their own (a tmux before 3.5 refuses `-r`, and an error ends the rest of a line) when the
  pane becomes known, when the window's active pane changes, and when the colours change. Only a pane id of `%`
  and ASCII digits goes inside the quotes.
- The colours are the theme's text and background (`SwiftTermTheme.answeredColors`), SwiftTerm's own answer
  outside tmux. Each engine's `applyTheme` notes them on `SwiftTermHostModel.answeredColors`; the local Mac engine
  passes them to its client directly, and an SSH session's model (`Models.swift`) seeds its client from the host
  model and follows `onAnsweredColorsChange` (told after the view update, never inside it).
- tmux 3.2 and 3.3 never answered at all (Copilot falls back to the terminal's own colours); 3.4 answers black and
  has no `-r`: the one version this can't fix.

## Second defect, found in the VM: the glass went solid and stayed so

Copilot's start (OSC 11 #0D1117, OSC 10 #F0F6FC) turned the glass terminal solid #0D1117, and its quit (OSC 111,
OSC 110) changed nothing: SwiftTerm's `setBackgroundColor(source:color:)` set the colour opaque, dropping the alpha
that carries the view's opacity, and SwiftTerm has no handler for 110 or 111 at all. So after Copilot the
terminal stayed solid with GitHub's text colour until the theme was applied again.

- **S6** (vendored SwiftTerm, `PATCHES.md`): a program's background is taken at the view's own alpha. Every theme
  the app applies has alpha 0 (the window's canvas draws the theme and its opacity), so a program's background
  no longer covers the glass.
- **`TerminalColorReset`** (`SwiftTermHostView.swift`): OSC 110 and 111 handlers, installed by each engine (iOS
  and visionOS, the Mac's SSH, the Mac's local), put the applied theme's text or background back
  (`SwiftTermTheme.nativeText`, `.nativeBackground`).

## VM (glasspowertools-mac26-run, macOS 26.6.2, SIP on, tmux 3.7c)

- **Before** (0.4.649 built from the code before this fix): a local terminal in tmux, `~/probe/osc-probe.sh`
  (asks OSC 10 and 11 as Copilot does): `ESC ]10;rgb:0000/0000/0000 ESC \ ESC ]11;rgb:0000/0000/0000 ESC \`. The
  defect reproduced. `osc-paint.sh` (Copilot's bytes): `black` line barely visible on the glass and gone on the
  painted dark; `paint` turned the terminal solid #0D1117; `reset` left it so (`.scratch/shots/macvm/ct-before-*`).
- **After** (0.4.649 with the fix, installed over the running session, the app reopened onto it): the same probe
  in the reattached pane: `ESC ]10;rgb:e6e6/e6e6/e6e6 … ]11;rgb:0000/0000/0000`, the default theme's text and
  background (it is black at 30%). A new terminal (`glass-2`): the same. Pixels measured in the shots: `paint`
  text #F0F6FC on the glass (#47494A seen through, as before it); `reset` text #E6E6E6, the theme's, on the glass.
  Old build for comparison: #F0F6FC on solid #0D1117, both before and after the reset. No crash reports. VM
  stopped.

## Validation

- Unit: `TmuxControlClientTests` 29 passed, six new (told for the pane before it is read; refused by an old tmux
  and the pane still drawn; known before the pane, changed after, unchanged not resent; told for a new pane; the
  report's text; pane ids). Bites: dropping the report at the pane, at a pane change, or the unchanged check each
  failed its tests.
- Unit: `TerminalProgramColorsTests` (a real terminal view in an offscreen window, fed Copilot's bytes): the
  background stays clear with the program's colour, and 111/110 bring back the theme's. Bites: S6 undone failed it
  on the alpha; the reset handlers not installed failed it on both colours. The first run of it crashed in
  SwiftTerm: S6 read the view's colour during the terminal's setup, before the view has one; it now reads
  `_nativeBg` optionally (opaque until then).
- The terminal suite: 1,348 passed.

## Changed files

`Sources/GlassTerminalEmulator/TmuxControlClient.swift`, `Sources/GlassTerminalEmulator/SwiftTermHostView.swift`,
`Sources/GlassTerminal/Models.swift`, `Packages/SwiftTerm/Sources/SwiftTerm/Apple/AppleTerminalView.swift`,
`Packages/SwiftTerm/PATCHES.md` (S6), `Tests/GlassTerminalTests/TmuxControlClientTests.swift`,
`Tests/GlassTerminalTests/macOS/TerminalProgramColorsTests.swift` (new), `RELEASE-NOTES.md`,
`site/help/terminal-tmux.md`.

## Installed

0.4.649 at 18:08 (2026-11-24) on his Mac (running 0.4.649 after the relaunch, no crash reports), the iPhone, and
the headset (its first install failed with "Connection interrupted"; the retry installed). A Copilot already
running keeps the colours it read at its start (it caches them): it needs a restart to read the new answer.
His first look (18:31) was the Copilot started at 15:48, still #000000 as expected; after `copilot --continue`
he confirmed: "Yep, looks good!" Seen on his Mac with tmux 3.8.

## Limits

- tmux 3.4 has no `refresh-client -r`: programs there are still told black. tmux 3.2 and 3.3 never answer.
- tmux answers OSC 10/11 with the reported colours even after a program set its own (the control client's come
  first in tmux's lookup); a real terminal would answer the program's. No program seen depends on it.
- A program's background colour is not drawn at all on the glass (alpha 0); tinting the canvas with it is a
  possible follow-up, not done.
- Not seen on the owner's Mac yet with Copilot itself: Copilot isn't signed in in the VM, so its own bytes were
  replayed. Its terminals pick up the report when the app reopens onto them.
