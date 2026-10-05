# iPhone landscape terminal, and AI fixes that are advice (2026-10-04)

- **Authorization:** owner — "Fix it then, good catch. While we're here we need to address the UX
  on a landscape terminal on iPhone" (two photos: keyboard up, keyboard down, on a Pro Max).

## Found
- AI error card offered Review & Run for a FIX that was a sentence ("Install the LX Terminal package
  …"), i.e. it would type prose into the shell.
- Landscape on a Pro Max reports a regular width, so the workgroup switched to the iPad
  `TabView` (`sidebarAdaptable`) — its tab bar put a session pill under the terminal, and every
  rotation rebuilt the screen.
- The bottom Tools band used `.background(.bar)`: light grey under a dark terminal, in both
  orientations, costing ~15% of the landscape height.
- `TerminalGeometry` clamps to 8...300 rows; the measured view size went through it, so with the
  keyboard up in landscape (~4 rows visible) the host drew 8 and the prompt was off screen.

## Changed
- `AIResponseParser.isRunnableCommand`; the card shows prose as advice (no Run); the prompt asks
  for a bare command in FIX:. Card lifted clear of tmux's status line. Tests: `AIFixAdviceTests`.
- `usesCompactPhoneNavigation` = any iPhone. In compact height, Tools moves to the top bar
  (`terminal-landscape-tools`) and the bottom band is not drawn. The band elsewhere takes the
  terminal theme's colour and light/dark (automatic follows the system).
- `TerminalGeometry(measuredRows:columns:)` (2...300 × 10...500) for measured sizes; the 8-row
  floor stays for configured sizes. Tests: `TerminalMeasuredGeometryTests`.
- Demo mode `--demo-landscape` (DEBUG) and `DEMO_ARGS` in `shoot.sh`, to capture landscape
  without driving the Simulator app.
- `exitedLocalPTYRestartsInTheExistingTerminal` failed in full parallel runs even at 10 s: the local
  shell starts when SwiftUI first builds the view, and an off-screen window was not always laid out
  in time, so the shell never started. The test now lays the view out itself and reports how many
  times it started on failure; six full runs clean.

## Validation
- Simulator (iPhone 17 Pro) landscape and portrait captures before/after; terminal and shell suites.
- Not verified: keyboard-up landscape on a device (the simulator shows no software keyboard here),
  and the Pro Max layout itself — both for the owner's phone.
