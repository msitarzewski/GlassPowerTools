# Moving along the command line as a Mac moves along text (2026-11-10)

## Task
- **Asked (the owner, 2026-11-10):** "A user requested that we allow our editing to behave like Apple's terminal -
  holding keys while using arrows affects how the cursor moves through the text. Is this already a feature?"
- **His choices:** ⌘← / ⌘→ to the line's start and end and ⌘⌫ to the start (asked; "Start / end of line"); the
  Dock count stays per terminal (asked alongside, after "the badge didn't clear on view of the window").
- **Scope:** the Mac. Not committed.

## What was there (a probe through the real view, offscreen, the app's settings)
| Keys | Sent | |
|---|---|---|
| ⌥← / ⌥→ | nothing | AppKit's `moveWordLeft:` / `moveWordRight:`, unhandled in SwiftTerm's `doCommand` |
| ⌘← / ⌘→ | Esc B / Esc F | `moveToLeftEndOfLine:` sent a word back ("Apple sends the Emacs back-word commands") |
| ⌥⌫, ⌘⌫ | nothing | `deleteWordBackward:`, `deleteToBeginningOfLine:` unhandled |
| ⌥-click | a selection | nothing moved the cursor (SwiftTerm's OSC 133 click route needs the shell to declare `cl=`) |
The app runs SwiftTerm with Option not acting as Meta, and offers no setting for it.

## What changed (SwiftTerm `PATCHES.md` S5, `Sources/SwiftTerm/Mac/MacTerminalView.swift`)
- ⌥← / ⌥→ Esc B / Esc F, ⌘← / ⌘→ ⌃A / ⌃E, ⌥⌦ Esc D: at the top of `keyDown`, whatever keyboard protocol a program
  asked for (Ghostty's macOS defaults do the same; iTerm2's Natural Text Editing sends the same bytes).
- ⌥⌫ Esc DEL, ⌘⌫ ⌃U, in `doCommand`; with the kitty protocol's disambiguation on, Alt / Super + Backspace as it
  encodes them.
- ⌥-click: the arrows to the clicked cell on the cursor's line (its row and the rows soft-wrapped onto it), one per
  character; not on the alternate screen or with the mouse reported.
- `keyDown` and `doCommand` are `public`, not `open`, in SwiftTerm, so the app's subclass couldn't do this.
- Type-ahead: ⌘→ now sends ⌃E, which it already took as "all of it" (fish's key).
- Help ("Move along the line you're typing (Mac)", Suggestions' ⌘→), registry, release notes 0.4.616.

## Validation
- **Unit, `MacTerminalArrowKeysTests`** (4 tests through the real view):
  - the keys;
  - the unchanged keys;
  - the kitty protocol;
  - ⌥-click on the line, off it, and in a full-screen program.
  - Against SwiftTerm without S5, 12 checks failed. The Mac `GlassTerminalTests`: 1,275 passing.
- **zsh and bash in a pseudo-terminal** (`~/Software/glass/tmp/shell-editing-check.py`): all 16 cases right.
  - The first run's two "BAD"s were my script: a wrong expectation for zsh's forward-word, and five arrows written as
    one Esc and five `[D`.
  - Forty more runs of the arrow burst: all right.
- **The real app in the macOS VM, a local zsh:** keys through System Events, through the app's menus and AppKit:
  - ⌥←⌥←, ⌘← then ⌥→, ⌘← then ⌘→, ⌥⌫, ⌥← then ⌥⌦ and ⌘⌫, each right in the picture.
  - ⌥-click not driven there: the VM tool can't click with ⌥ held.
- **Not done:** iPhone, iPad and Vision Pro with a hardware keyboard (SwiftTerm's UIKit path) not checked.

## Next
- 0.4.616 on the Mac; his try.

## Shipped (2026-11-11)
- Committed (`5bc77b45`) and pushed; released in 0.4.616: the Mac's ninth release (GitHub v0.4.616, notarized,
  downloads byte-identical to the build, feed entry); Mac only, TestFlight 616 carries the rest.
