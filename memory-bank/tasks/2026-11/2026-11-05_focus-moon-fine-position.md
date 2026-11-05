# Vision Pro: Fine Position missing from the moon (0.4.598, 2026-11-05)

**Report (the owner):** "The fine tune option is not in my moon?" (after I'd told him Fine Position is in the moon's
pinch-and-hold menu while Focus Mode is open), then "What do you mean from one tab? In vision, aren't Windows treated as
entities?"
**Status:** fixed, tested; 0.4.598. Uncommitted.

## Cause
- Focus Mode is one immersive space for the app (`ImmersiveSpace(id: "focus-environment")`), and
  `FocusEnvironmentStage.shared.isOpen` says whether it is open. But the moon (`TerminalWindowView`'s toolbar button)
  read `isImmersiveFocusActive`, a `@State` of each terminal's view, true only in the view that opened it. A window's
  terminals (its sidebar rows) each have a `TerminalWindowView`; so on another terminal of the window, or in another
  window, the moon read Focus Mode closed: hollow, no Fine Position in its menu, and a pinch tried to open it again.

## Fix
- `focusModeOpen` (`isImmersiveFocusActive || FocusEnvironmentStage.shared.isOpen`) for the moon's symbol, label, the
  menu's Fine Position, the toggle (closes it from any moon) and choosing an environment.

## Validation
- New UI test `FocusEnvironmentUITests.testEveryTabsMoonOffersFinePositionWhileFocusModeIsOpen` (`terminal-tabs`,
  `--demo-focus night-sky`; the other sidebar row shown; its moon says Exit Focus Mode and its hold offers Fine
  Position…). With the fix switched off it fails at once: the tab on show read Focus Mode closed (the demo's other tab
  had opened it); with the fix it passes, beside the existing `testFinePositionStepsTurnsRaisesAndKeepsTheSpot`.
- Not yet on the headset.
