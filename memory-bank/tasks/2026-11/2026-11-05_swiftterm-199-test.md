# SwiftTerm 1.99.2 tested against the app (B-Q28, B-F12)

**Asked (2026-11-05):** after Termius moved its iOS terminal to libghostty, "Anything to learn from this here?";
then, to the offer of a bounded test of SwiftTerm 1.99.2, "yes, run the 1.99.2 test".
**Owner:** this session. **Authorization:** the test, locally; nothing pinned, committed or installed.

## Result: does not build; the port is large

- `Tools/Packages/check-updates.py --test swiftterm@v1.99.2 --keep` → **FAILED** at "build and tests compile".
  Resolve passed. Report and logs: `<work>/swiftterm-199/`.
- **Correction to earlier notes:** 1.99's `unsafeFlags` (`-Werror EmbeddedRestrictions`, `-parse-as-library`, wasm
  linker flags) are only switched on by SwiftTerm's own embedded and WebAssembly builds (an environment variable or
  a trait), and `swift-png` (with its dependency `h`) only on Linux, Windows, WASI and Android with the
  `PortableGraphics` trait. Neither stops an Apple build. The failure, on 10-26 (1.99.1) and now, is our code
  against 1.99's API. And 1.99 ports Ghostty's IO design (PR #627); it does not link libghostty.
- SwiftTerm's LICENSE gained a copyright line (Powerline Extra Symbols, MIT). `generate-acknowledgements.py` wants
  entries for `swift-png` and `h` once they are pinned, linked or not.

## What 1.99.2 changed under us

| Ours (1.20) | Uses | 1.99.2 |
|---|---|---|
| `TerminalView.getTerminal()` | 78 (76 in Sources) | Gone. The `Terminal` sits behind a lock, parsed off the main thread; `withTerminal` is internal. |
| Dimensions, bracketed paste, application cursor, mouse mode, alternate buffer, kitty flags | ~20 of the 78 | `terminalDimensions`, `terminalInputStateSnapshot()`, `keyboardEnhancementFlags` |
| Buffer rows (Find, screen reader, diagrams, SQL, row fingerprints) | most of the rest | `terminalContentSnapshot(region:)`, `visibleRowsText(_:)`, `getBufferAsData` (copies) |
| `cursor style`, `resetToInitialState`, `resize` | 5 | methods on the view |
| `view.selection` (`SelectionService`) | ~117 references to selection | internal. Public: `selectionActive`, `getSelection()`, `selectNone()`, iOS `setSelectionRange` |
| `SwiftTermSelectionKeeper` (selection dropped at each chunk) | 25 | upstream now keeps valid selections during output (#656); probably deletable |
| Link at a cell (`Terminal.link(at:mode:)`): path previews, context menu | 6 | **no public view API** |
| `parser.oscHandlers[52]` (clipboard backstop) | 4 | **parser not reachable**; whether the clipboard delegates cover it is unchecked |
| Mac `performKeyEquivalent` (⌘A Select All) | 2 | `public override`, not `open` |
| Mac `LocalProcessTerminalView.dataReceived` (clear-blacks filter, Find timing) | 1 | unavailable; output is parsed on the I/O thread. `setProcessOutputHandler` only signals; filtering bytes needs our own `LocalProcess` feeding a plain view |
| iOS `selectionChanged` / `mouseModeChanged` overrides | 2 | `nonisolated` now |
| The Mac proxy's two delegate protocols | 1 | both give defaults for `kittyClipboardCapabilities` and `programStatusChanged`: name them (done in the worktree) |

**Vision Pro drawing:** with Core Graphics, 1.99.2 still repaints the whole view (`requestDisplay` →
`setNeedsDisplay(bounds)`), now paced by a frame driver from a snapshot. It adds an opt-in Metal renderer on iOS
and visionOS (`setUseMetal(true)`; Metal is the Mac's default). Our row-band repaint (`setNeedsDisplay` override,
`TerminalRowFingerprints`) reads `getTerminal()` and would be redone or replaced by Metal.

## State

- Worktree `<work>/swiftterm-199/worktree` (detached at `b28c27aa`): Package.swift at `exact: "1.99.2"`, resolved;
  exploratory stubs only (`PORT_` renames of the three closed overrides, the proxy's two methods). Not a port.
- Weekly check: no report for Monday 2026-11-02 (the job is loaded, last exit 0, the Mac was awake); not looked into.

## The engine alone on Vision Pro (his "yes, build the test app", same day)

- **Test app** `<work>/swiftterm-bench/` (outside the repo): a visionOS app hosting SwiftTerm's iOS view on glass,
  light text, Menlo 15, 138×28 cells. Five workloads made before the clock starts: typing echoed at 10 keys/s;
  a Claude Code-like synchronized frame every 100 ms; full-screen truecolour at 60/s; a build log at 3,000
  lines/s; scrolling 5,000 lines. It measures process and main-thread CPU, Core Graphics draws, display-link
  frames dropped, and key-to-screen time (end of the next CG draw, or 1.99's `onFramePresented`; 1.20's Metal
  has no hook). Results in Caches/termbench.jsonl. Four builds from one source (XcodeGen specs): 1.20.0,
  1.99.2, and each with the scale fix below. Scripts: `build-sim.sh`, `run-sim.sh`, `build-device.sh`,
  `fetch-device.sh`, `table.py`, `zoom.py`.
- **Found: SwiftTerm's `backingScaleFactor()` returns 1.0 on visionOS** (`iOSTerminalView.swift`, both versions).
  1.20's Metal sets its drawable to bounds × 1, half the real resolution, which the system scales up: the blur
  he saw on 2026-10-29 ("like a jpg vs png"), reproduced in the simulator. 1.99.2 lays out at 1.0 but no longer
  forces the drawable, so its Metal draws the terminal at half size in a corner. Returning
  `traitCollection.displayScale` (local patch, `<work>/SwiftTerm-120-scale`, `SwiftTerm-199-scale`) makes both
  Metal renderers full size and as sharp as Core Graphics at 4× zoom. 1.99.2's Core Graphics looked slightly
  softer with the patch: unconfirmed, to check on the headset.
- **Simulator (visionOS 27.2 on the M5 Max, so a ranking, not headset figures)**, typical of two runs:
  - Dropped frames: 1.99.2 none in any workload except full-screen Core Graphics (57 of 772); 1.20 in all
    (typing CG 110 of 976, full screen CG 401 of 416).
  - Key to screen p50: 1.99.2 10–12 ms; 1.20 Core Graphics 24–25 ms.
  - CPU: typing 1.20 CG 12% / 1.99.2 Metal 3%; agent 11–13% / 4–5%; full screen 97% / 25%; build log 33% /
    20%; scroll 42% / 15%. 1.20's Metal sits between (typing 7%, full screen 89%).
  - Run-to-run spread is real (1.20 CG typing read 7% and 12% in two runs); the ordering held in both.
- **Headset:** all four installed 2026-11-05. He asked to decide from the simulator rather than run them ("This
  is a lot. Can you not test this in the emulator and present options?"), so no headset run is pending.
- **Options given him (2026-11-05), awaiting his choice:** (1) keep 1.20, carry the one-line scale fix in a local
  copy of SwiftTerm and turn Metal on for Vision Pro (the existing "Draw with Metal" setting); (2) port to 1.99
  now; (3) change nothing until 2.0. Recommended: 1 now, 2 when 2.0 ships, and report the scale bug upstream at
  his word.

## Recommendation (given to him)

Not a port now: 1.99 is a pre-2.0 preview whose API still moves (1.99.2 itself made `dataReceived` unavailable).
First measure the engine alone on Vision Pro: a small standalone harness app hosting SwiftTerm's view, replaying
recorded output and typing, against 1.20 and 1.99.2 (Core Graphics and Metal), in the simulator and on the headset.
Port when 2.0 ships if that shows a win; the missing pieces (link at a cell, an OSC 52 hook, an output filter) are
worth asking upstream for before 2.0, at his word.
