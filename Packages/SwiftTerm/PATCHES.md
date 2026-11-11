# Glass Power Tools patches to SwiftTerm

This directory is a vendored copy of [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (MIT,
`LICENSE`) with the local changes below. Everything else is upstream, byte for byte. Vendored on
2026-11-05 (D101) for S1: SwiftPM cannot patch a dependency it fetches.

## Provenance

- **Upstream:** [migueldeicaza/SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), MIT.
- **Baseline:** release `v1.20.0`, commit `5d14406844143538cd8f8851d2d8a67c1fe443e5`, the version the
  app pinned from 2026-10-08.
- Left out: `.swiftpm/` (Xcode's test baselines for SwiftTerm's own tests; this repository ignores
  the folder).

To see exactly what differs from the baseline:

```sh
git clone https://github.com/migueldeicaza/SwiftTerm.git /tmp/swiftterm
git -C /tmp/swiftterm checkout v1.20.0
diff -ru --exclude=.git --exclude=.swiftpm /tmp/swiftterm Packages/SwiftTerm
```

## Changes

| # | Change | Files |
|---|---|---|
| S1 | **visionOS draws at its real scale.** `backingScaleFactor()` returned 1.0 on visionOS, half the headset's 2 pixels per point. The Metal renderer sized its drawable from it (bounds × 1), so the terminal was drawn at half resolution and scaled up: the soft text seen on the headset on 2026-10-29. Cells also snapped to whole points rather than pixels. It now returns the view's `traitCollection.displayScale`, or 2 before the view has a window. iOS and macOS are unchanged. | `Sources/SwiftTerm/iOS/iOSTerminalView.swift` |
| S2 | **No build-tool plugin.** The `SwiftTermBuildInfoPlugin` ran `git` on the package's folder to stamp the version into `SwiftTermBuildInfo`, which the XTVERSION answer reads. Inside this repository that would be the app's commit and branch. The plugin is removed from the manifest (its sources stay, unused) and `SwiftTermBuildInfo.swift` is written by hand for `v1.20.0`, marked modified: XTVERSION answers `SwiftTerm 1.20.0+v1.20.0-modified`. Xcode also no longer asks to trust a plugin. | `Package.swift`, `Sources/SwiftTerm/SwiftTermBuildInfo.swift` (new) |
| S3 | **Shell integration's marks reachable by the host** (D102, type-ahead, 2026-11-06). `Terminal.oscSemanticPrompt` is public, so the app can register its own OSC 133 handler (`parser.oscHandlers` is consulted before SwiftTerm's built-in codes) to follow the prompt and still pass each mark on to SwiftTerm's cell tagging. `Terminal.scrollInvariantCursorRow` (new) gives the cursor's row as `getScrollInvariantLine(row:)` counts rows, so where typing began at a prompt can be found again after the screen scrolls. `TerminalView.cursorCellFrame` (new) gives the cursor's cell in the view's coordinates, worked out from the buffer as `updateCursorPosition` places the caret, for drawing a suggestion beside the cursor (the caret itself moves only on the next display). No behaviour changes. | `Sources/SwiftTerm/Terminal.swift`, `Sources/SwiftTerm/Apple/AppleTerminalView.swift` |

| S4 | **A flick's coast keeps its place while output arrives** (2026-11-08). The UIKit view took its frozen row from the scroll position only while a finger or hand was down (`isTracking`). Through the coast after a flick the row stayed where the hand let go, and the next output (`scrolled` → `updateScroller`) put the view back there: in a terminal printing all the time, every flick that stopped short of the bottom was undone, so the latest lines couldn't be reached (the owner on Vision Pro, a tab with Codex at work). The row now follows the coast too, but only for a scroll the person made (`userScrolling`): a coast while following the bottom still never freezes the view, the case the upstream comment guards. Tested in `Tests/GlassTerminalTests/TerminalScrollCoastTests.swift` (60 rows back without it). iOS and visionOS; macOS is unchanged. | `Sources/SwiftTerm/iOS/iOSTerminalView.swift` |
| S5 | **Moving along the command line as a Mac moves along text** (2026-11-10). With Option not acting as Meta (the app's setting), AppKit turns ⌥← / ⌥→ into `moveWordLeft:` / `moveWordRight:`, ⌥⌫ into `deleteWordBackward:` and ⌘⌫ into `deleteToBeginningOfLine:`, none of which `doCommand` handled, so they sent nothing; ⌘← / ⌘→ (`moveToLeftEndOfLine:` / `moveToRightEndOfLine:`) sent a word back and forward. Now, as Apple's Terminal, iTerm2's Natural Text Editing and Ghostty's macOS defaults do: ⌥← / ⌥→ send Esc B / Esc F, ⌘← / ⌘→ ⌃A / ⌃E, and ⌥⌦ Esc D, caught at the top of `keyDown` so a program that asked for the kitty keyboard protocol gets the same, as Ghostty sends them; ⌥⌫ sends Esc DEL and ⌘⌫ ⌃U, or the protocol's encoding of Alt / Super + Backspace when a program asked for disambiguated keys. ⌥-click on the line being typed (the cursor's row and the rows soft-wrapped onto it) sends the arrows that take the cursor there, one per character; not on the alternate screen or while the program takes the mouse. Tested in `Tests/GlassTerminalTests/macOS/MacTerminalArrowKeysTests.swift` (12 checks fail without it), and against zsh and bash in a pseudo-terminal. macOS only. | `Sources/SwiftTerm/Mac/MacTerminalView.swift` |

## Taking a newer SwiftTerm

Replace this directory with the new release's tree (`git archive <tag>`), apply the changes above
again where the release still needs them, update the baseline here and the revision in
`Tools/Licenses/components.json`, and run `Tools/Licenses/generate-acknowledgements.py`.
`Tools/Packages/check-updates.py` lists newer SwiftTerm releases under "Vendored copies".

S1 is worth reporting upstream; once a release has it, S1 can go. 1.99.2 has the same 1.0 on
visionOS (2026-11-05), and there its Metal renderer draws the terminal at half size in a corner.
