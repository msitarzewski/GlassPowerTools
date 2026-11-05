# Vision Pro: which window has the keyboard, and hiding the mini keyboard (2026-11-03)

**Ask (the owner):** "Is there any way to detect when a window has keyboard focus? Better, and we disable the mini
keyboard in the app somehow?" ("the mini keyboard": the system's small bar shown with a hardware keyboard: suggestions
and the dictation mic.)
**Status:** his word 2026-11-05 ("yes, hide the mini keyboard. F that thing ... The only tension I'm going to have is voice
dictation and emoji selection"); built in 0.4.599 (below). Uncommitted.

## Which window has the keyboard
- **Within a window: known.** The terminal view that holds the keyboard is the first responder; the headset's file
  already records each change (`ReviewingTerminalView.becomeFirstResponder`/`resignFirstResponder`, "keyboard
  taken" / "keyboard given up"; `windowBecameKey`, "window became key holding=").
- **Across windows: no API.** Built against the iOS 15 SDK or later, `UIWindow.isKeyWindow` is true for the window that
  is key **in its own scene** (UIWindow.h, visionOS 27.2 SDK), and each Vision Pro window is its own scene, so every
  open window can be key at once. No UIKit or SwiftUI API names the scene the hardware keyboard types into (UIKit
  headers searched for key-scene/keyboard-focus API: none); forum threads found nothing either.
- **Proposed proxy:** the window that last got a key press, or the pinch that put the cursor in it, is the one with
  the keyboard; mark it app-wide. Unmeasured: whether we learn anything when he pinches into another app's window.

## Hiding the mini keyboard
- **No switch from Apple.** On iPad, apps empty the bar with `inputAssistantItem.leading/trailingBarButtonGroups = []`
  (SwiftTerm does, `iOSTerminalView.swift:1497`, guarded `#if !os(visionOS)`). On visionOS those are **unavailable**:
  the probe's first build failed ("'leadingBarButtonGroups' is unavailable in visionOS"). The terminal already turns
  every suggestion trait off (SwiftTerm `iOSTerminalView.swift:2068–2073`).
- **The standard avenue: an empty `inputView`.** Available on visionOS (UIResponder.h; `inputAccessoryView` is not).
  The RDP desktop already does it on iPhone and iPad (`DesktopMetalSurface.swift:544`, `#if os(iOS)` only).
- **Probe (visionOS 27.2 simulator, Debug, `terminal-typing` demo with `--demo-keyboard`):** without it, the system
  keyboard ("Text Preview", the mic) sits under the window; with `terminalView.inputView = UIView(frame: .zero)`, no
  keyboard appears and the terminal keeps the keyboard (the simulator's log: `keyboard taken=true`, never given up).
  Pictures: `~/Software/glass/tmp/kb-probe/crop-none.png`, `crop-empty.png`. The DEBUG switch
  (`--probe-keyboard empty`, in `SwiftTermHostView`'s setup) was removed afterwards; the source is as before.
- **Not proven:** that the headset's mini keyboard goes too with a Magic Keyboard, and that its keys still arrive (the
  simulator has no Magic Keyboard). Needs the headset.

## Proposal put to him (not approved)
- While a hardware keyboard is connected (`GCKeyboard.coalesced`, `GCKeyboardDidConnect`/`DidDisconnect`; GameController
  is in the visionOS SDK), terminals (and the RDP desktop on visionOS) use an empty input view; without one, the system
  keyboard as now.
- Trade-off: the mini keyboard holds dictation; a "Show Keyboard" item in the terminal's Keys menu could bring it back.
- Plus the "has the keyboard" mark on the window above.
- **His questions to answer:** build it for terminals and the desktop, with the mark? Should the editor hide it too, or
  keep the bar for its spelling and autocorrect (Settings ▸ Editor ▸ Spelling and Substitutions, off by default)?

## Sources
- UIKit headers in the visionOS 27.2 SDK: `UIWindow.h` (isKeyWindow per scene), `UIResponder.h` (inputView,
  inputAccessoryView unavailable, inputAssistantItem visionOS 2.0), `UITextInputTraits.h`; GameController `GCKeyboard.h`.
- https://developer.apple.com/forums/thread/788019 (iPadOS 26/27: the bar not always shown; no app-side fix)
- https://developer.apple.com/forums/thread/8039 (the bar off only by the user's Predictive and Shortcuts settings)

## Built (0.4.599, 2026-11-05)
- `GlassSystemKeyboard` (GlassShell, new): `hardwareKeyboardConnected` from GameController (`GCKeyboard.coalesced`,
  `GCKeyboardDidConnect`/`DidDisconnect`); `shownAnyway` (the person asked for the system keyboard, not kept between
  launches, ended when the hardware keyboard goes); `hidesSystemKeyboard`.
- **Terminals:** `SwiftTermHostModel.hidesSystemKeyboard` (visionOS), set by `TerminalWindowView` from the shared state;
  `ReviewingTerminalView.applySystemKeyboardChoice()` gives an empty `inputView` (one per view) or none, before taking
  the keys and at once while holding them (`reloadInputViews`); its change is noted in the headset's file
  (`system keyboard hidden|shown`). Keys menu: **Show Keyboard** / **Hide Keyboard** while a hardware keyboard is
  connected (for dictation and emoji).
- **Remote desktops:** `DesktopMTKView.hidesSystemKeyboard` (visionOS) and its `inputView`; a touch on the desktop takes
  the keys and had brought the small keyboard up each time. Dictation and emoji there: Keys ▸ Type Text….
- The editor unchanged (his answer on it not given; its suggestions are off by default).
- Tests: `GlassSystemKeyboardTests` (3): none connected keeps it; connecting hides, asking shows, putting away hides;
  disconnecting shows and ends the asking. Each seen failing on its own break; restored, compared. Package 3,353 pass.
- visionOS simulator (`terminal-typing --demo-keyboard`): the simulator reports a hardware keyboard; the log reads
  `keyboard taken=true`, `system keyboard hidden holding=true`, and no keyboard shows under the window
  (`~/Software/glass/tmp/kb-hide/terminal-s.png`; before, `kb-probe/typing-kb.png` had it).
- **Not proven:** Magic Keyboard keys reaching a terminal with the empty keyboard (UIKit sends hardware keys to the
  first responder whatever its input view, as the iPhone/iPad desktop relies on; the demo terminal discards input), and
  Show Keyboard bringing up dictation, on the headset.
- 0.4.599 installed and read back on the headset and iPhone.
