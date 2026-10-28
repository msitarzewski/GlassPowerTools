# 2026-10-28 — A menu in the empty space of a Vision Pro terminal window's sidebar

## Objective and authorization
The owner, 2026-10-27 (late): "there's no context menu in the empty space in a tab sidebar in visionOS." The report
authorizes the fix, its tests and a build for his devices. Not committed until he says so.

## What the Mac does (reused)
A Mac terminal window's sidebar offers, in its empty space, what the toolbar's + offers (`MacWorkspaceView.tabMenu`,
the owner, 2026-10-21: "a right click ... in the empty space in the left sidebar ... looking for a 'new terminal'
option that mimics the top toolbar"). On Vision Pro the bar's + is `TerminalNewTabMenu`: a pinch opens the saved-host
picker; held, each saved server with New Terminal and the terminals running there.

## Built
- `TerminalNewTabMenuItems` (`TerminalNewTabMenu.swift`): the + menu's servers and their terminals, now one view that
  the + and the sidebar both use.
- `VisionTerminalWorkgroupView.terminalSidebar`: below the rows, a space reaching the sidebar's foot (measured: a
  scroll view stretches nothing) that, held, offers New Terminal Tab… (the picker) and the + menu's servers. A plain
  button with no look highlight: a pinch does nothing, as a click there on a Mac does. VoiceOver hears it as New
  Terminal Tab; activating it opens the picker, and the menu's choices are its actions.

## Validation
- `GlassTerminalOrnamentUITests.testTheSidebarsEmptySpaceOffersANewTerminal`: the space reaches the foot (taller than
  300 pt with two rows) and, held, shows New Terminal Tab…; it fails with the menu taken out (source restored byte for
  byte). The whole suite, 12 of 12; terminal unit tests 1037.
- **Found on the way, the runner:** a hold at a point of the sidebar ornament (`coordinate(withNormalizedOffset:)`)
  opened nothing, so five ways of attaching the menu all looked broken; holding a row (a known-good control) opened its
  menu, and the same space held as an element opened its menu in every way tried. The test holds the element.
- Not seen: the headset.
