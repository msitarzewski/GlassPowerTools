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

## Taking a newer SwiftTerm

Replace this directory with the new release's tree (`git archive <tag>`), apply the changes above
again where the release still needs them, update the baseline here and the revision in
`Tools/Licenses/components.json`, and run `Tools/Licenses/generate-acknowledgements.py`.
`Tools/Packages/check-updates.py` lists newer SwiftTerm releases under "Vendored copies".

S1 is worth reporting upstream; once a release has it, S1 can go. 1.99.2 has the same 1.0 on
visionOS (2026-11-05), and there its Metal renderer draws the terminal at half size in a corner.
