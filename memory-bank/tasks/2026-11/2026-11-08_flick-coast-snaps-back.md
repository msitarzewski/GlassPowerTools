# A flick's coast was undone by the next output (2026-11-08)

**Asked:** "Why would scrolling in the terminal be jumpy on vision pro. Look at the [one project's] session in particular.
I can't scroll to the latest lines... it jumps and stutters." Then: "may be related to the keyboard?", "The keyboard
showing solves the stutter", "Not holds it... but shows it", and "it's when that's enable (hiding) that stuttering
happens" (the hide-the-system-keyboard choice, `GlassSystemKeyboard`). **Owner:** this session. **Authorization:**
local fix, tests, build and installs; no commit or push without his word.

## What the tab was
- A tmux tab of a session on his Mac running Codex (named for one of his projects, 138×44, main screen, its history at
  tmux's limit), printing all the time while it worked. The headset's client set the window's size.

## Cause found
- SwiftTerm's UIKit view (`Packages/SwiftTerm/Sources/SwiftTerm/iOS/iOSTerminalView.swift`,
  `syncYDispFromContentOffset`) takes its frozen row from the scroll position only while `isTracking`. Through the
  coast after a flick the row stayed where the hand let go; nothing synced it when the coast stopped (no
  `scrollViewDidEndDecelerating`). The next output scrolls the terminal (`Terminal.scroll` → `scrolled` →
  `updateScroller`), which sets the offset from that row: the view jumped back. In a terminal printing all the time,
  every flick that stopped short of the bottom was undone.
- **Seen failing first:** `TerminalScrollCoastTests.coastKeepsItsPlace` (visionOS simulator): "the view moved 60.0 rows
  from where the coast stopped". The two companion cases (a coast while following keeps following; a coast to the
  bottom follows again) passed before and after.
- Fix: S4 in `Packages/SwiftTerm/PATCHES.md`: the guard is `isTracking || (userScrolling && isDecelerating)`, so a
  coast moves the frozen row too, and a coast while following never freezes. 3 of 3 pass with it.

## Not explained yet
- Why showing the system keyboard made scrolling smooth for him. The fix doesn't depend on the keyboard. The headset's
  log lines now carry `top=`, `of=` and `keyboard=system|none`, and a `coast ended` line, so his next try shows
  whether anything is left and whether it follows the keyboard. In the log copied before the fix, the stuttering
  scrolls were made with the terminal not holding the keys (`first=false`), where the hidden keyboard's empty
  `inputView` has no effect UIKit could apply.

## Validation
- `GlassTerminalTests` on the visionOS and iOS simulators: 848 passing each (the 845 of 0.4.610 and the three new).
- 0.4.611 built (Release) and installed on the headset, iPhone and Mac, each read back as 0.4.611; the Mac app
  relaunched, no new crash reports.
- Not yet: his try on the headset with the keyboard hidden, and the log it leaves.
