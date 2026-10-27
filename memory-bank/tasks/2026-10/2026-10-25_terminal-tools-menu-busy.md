# 2026-10-25 — The terminal's tools menu works while its agents work

## Objective and authorization
The owner, on Vision Pro: "settings (the gear menu in Terminal) doesn't work when the Terminal window is busy. It
shows, but using doesn't work." His report authorizes the fix, its tests and a build for his devices.

## Cause (measured in the visionOS simulator)
- A terminal window is drawn again with every read of its program's title (`TerminalSession.tmuxPane`, read at most
  every 5 s while output runs, so often with several agents at work): its title ornament names it by that title.
- The tools menu was part of the window's body, so its contents were rebuilt each time. With the busy demo (two
  windows, each agent's title spinner turning ten times a second) the menu's contents were built three to five times
  a second per window while it was open, counted with a temporary log line.
- **Move Tab To** named the other windows by their titles, Claude Code's spinner glyph included (`✳ Tandem…`; the green
  ✳ in his dock capture), so its rows changed with every turn of the spinner.
- With the menu open, the runner's Search row had no place on screen when it pinched (`{inf, inf}`): the row had been
  replaced. A one-window busy terminal, with nothing in its menu changing, kept the menu working.

## Built
- `TerminalSteadyMenu` (`TerminalWindowView.swift`): the tools menu drawn again only when `TerminalToolsMenuKey`
  (what it shows that it does not watch itself) changes, not whenever the window is drawn. Measured after: no
  rebuild while open.
- `TerminalTabMoveActions` draws its rows through `TerminalTabMoveRows`, equatable on the rows, so a read of the other
  windows with nothing new in it draws nothing.
- `TerminalSessionNaming.steady`: Move Tab To's names without an agent's spinner (Claude Code's `· ✢ ✳ ✶ ✻ ✽`, a braille
  frame, at the start, before a space); a name's own first mark ("★ prod") stays.
- Demo `agent-busy` (`--demo-open agent-busy`): two windows on one machine, each writing ten times a second with its
  pane title's spinner turning (`TerminalSession.demoPaneTitle`, the replay's `ticks`, `titles` and `every`).

## Validation
- `TerminalTabMovesTests`: Move Tab To's names hold while the spinner turns (eight frames, one result), and only a
  spinner goes from a name. Seen failing with `steady` taken out of `destinations` (source restored byte for byte).
- The menu's rebuilds counted before and after with a temporary log (removed).
- **No UI test.** The busy demo never goes idle, so the runner waited 60 s before every step, about two minutes passed
  between opening the menu and the pinch, and it could not pinch even a steady row ("Activation point invalid"). A
  test that cannot pass was not kept. In a Debug build Settings, the menu's last row, is below its fold (HTML Preview
  adds a row), so a test cannot pinch Settings either.
- The owner's headset is the check: Tools, and Settings in it, with Claude Code at work in several windows.
- Around it: the visionOS ornament suite 10 of 11 (below), the iPhone Tools suite 3 of 3, terminal 992 and shell 361
  unit tests. 0.4.527 installed on the Mac, iPhone and Vision Pro (versions read back; no new crash report).

## Not fixed on the headset (0.4.527, the owner, 2026-10-26)
"The settings menu still doesn't work either … I still can't select an item." The rebuilds above were real and are
gone, but they were not his fault. My simulator evidence for "busy" was also weaker than written: the two-window test
may have opened the Tools menu of the window behind, whose rows the runner cannot reach. Not reproduced in the
simulator: a demo terminal never takes the keyboard (`--demo-open`); with `--demo-keyboard` it does, and Search in Tools
still worked on a quiet one.

Next, evidence from the headset (0.4.528): the diagnostics file (`headset-diagnostics` memory) now has `tools built`,
`tools chose search|clear|settings`, `tools settings sheet asked for|on screen|closed`, `tools bar drawn N times in
2s`, and the terminal's `keyboard taken|given up` and `window became key` beside its pinches (`tap1`). One try with
the time it was made says whether a pinch reached the menu, went through to the terminal, or reached neither.

## Found on the way: the diagram mark on Vision Pro (fixed, 0.4.528)
`GlassTerminalOrnamentUITests.testADiagramHasAMarkThatShowsIt` failed on the visionOS simulator, at `03a86e9c` too. The
mark was drawn but absent from the app's accessibility: a walk of the tree from inside the app, with the runner
attached, found "Terminal" and "Find" and no "Show Diagram", so VoiceOver could not reach it either. Variants in one
run: no popover, a default or borderless button style, no background, or glass each brought it back; a material or a
colour fill behind the plain button's label, with the popover, took it out. Vision Pro's mark now sits on
`glassBackgroundEffect`; iPhone and Mac keep the material. Ruled out on the way: the UI-test grid mark, the hover
effect and `.help`, the overlay's place, an empty container, and a new identity for the marks. The diagram test
passes on the visionOS simulator (the ornament suite 11 of 11); 0.4.528 installed on the Mac, iPhone and Vision Pro.

## Open
- Other menus that read a program's title while open (a tab's own menu with Move Tab To) use the same steady rows; not
  measured separately.

## 2026-10-26 13:05 — the headset's log after a morning on 0.4.530
Copied to `<work>/headset/screen-sharing-1305.log`. One choice from the tools menu, and it worked: Settings at 11:54:53
local (the sheet on screen 60 ms later, closed 5 s after), on a quiet terminal (the bar drawn 6 times in 34 s). No try
on a busy terminal is recorded. "tools built" is not an opening: every terminal's menu is built two to four times as
the app starts (11:51), and one terminal's five times at 12:51 with the bar drawn 40 times in 2 s, after half an hour
idle (likely the headset put back on), with no choice after it. Next: his try on a busy terminal, with the time.
