# A paste is text; a closed terminal is freed (2026-11-08)

**Asked:** "yes" to fixing two defects found in a review of another terminal's published source (the review is kept
outside this repository, at his word). **Owner:** this session. **Authorization:** local fix, tests, build and
install on the Mac and iPhone; no commit or push without his word.

## 1. Closed terminals were never freed on iPhone, iPad and Vision Pro
- SwiftTerm's UIKit view makes a `CADisplayLink` with itself as the target
  (`Packages/SwiftTerm/Sources/SwiftTerm/iOS/iOSTerminalView.swift`, `setupDisplayUpdates`); a display link holds
  its target until it is invalidated, and only `updateUiClosed()` does that. Nothing in our tree called it, so
  `releaseRenderer` dropped our references and the link kept the view, its `Terminal` and its scrollback for the
  life of the process. The Mac's view has no display link.
- Fix: `SwiftTermEngine` (the view's owner) calls `updateUiClosed()` in its `isolated deinit`, which runs when the
  model drops the engine on close or the model itself goes. Status: see Validation.

## 2. Paste passed control characters through
- `SwiftTermPastePolicy.framedData` wrapped the raw text; every paste and drop goes through it (the iOS, Mac SSH and
  Mac local engines' `commitPaste`). A pasted `ESC [ 201 ~` ended bracketed paste early and the rest ran as typed;
  a Ctrl-O (bash's operate-and-get-next) in a one-line paste ran the line without a review.
- Fix: every C0 control but tab, LF and CR, plus DEL and C1 (U+0080–U+009F), is left out of every paste, bracketed
  or not. xterm's default is the same (`allowPasteControls` false: "Other C0 control characters are suppressed");
  Alacritty strips ESC and ETX in bracketed paste only. The model logs how many it left out
  (`event=paste-controls-left-out`, category `terminal-paste`). Snippets and commands are not pastes and are not
  filtered.

## 3. A dropped file's name with a format or C1 character was typed wrong
- `TerminalDroppedPaths.escaped` wrote such a character in `$'…'` as `\x` and its whole value: U+202E became
  `\x202e`, a space and "2e". Now its UTF-8 bytes, `\xHH` each (macOS's bash 3.2 has no `\u`).

## Validation
- New tests: `TerminalViewLifetimeTests` (a hosted terminal's SwiftTerm view freed after close, with the model kept
  and `releaseRenderer`, and with the model dropped; runs on the Mac too), `terminalPasteLeavesOutControlCharacters`
  (`glas_shTests`), and five more names in `TerminalDroppedPathsTests`' zsh and bash round trip plus two exact
  escapes.
- **Seen failing first.** iPhone simulator, before the engine's `deinit`: both lifetime cases failed at
  `view == nil` (the models were freed; the views were not), and passed with it. Mac, with the paste filter made a
  no-op and the old `\x%02x` of the scalar put back in one build: the paste test failed (3 expectations), the
  exact-escape test (U+202E) and the round trip (6: U+202E, U+200B, U+0085 in each shell). Both files restored from
  copies, `cmp` identical.
- `GlassTerminalTests` in full: Mac 1,243 passing (`swift test`, in a build folder of its own); visionOS simulator 845 and iOS
  simulator 845 passing (scheme `TerminalTests`).
- Not measured: how much memory a closed terminal held on a device.
- 0.4.610 installed and read back on the Mac and iPhone, no new crash reports. Committed at his word ("commit",
  2026-11-08) as `383a5379`, not pushed.
- Vision Pro, at his "push the latest to vision": 0.4.610 built (Release, `build-visionOS-610.log` in the working
  files, BUILD SUCCEEDED, Info.plist 0.4.610). The headset was unavailable for two hours of waiting; installed at
  his "vision is up" (22:59) and read back as 0.4.610. No Glass Power Tools crash reports on the headset; the
  newest memory reports name donotdisturbd and iconservicesagent, and the newest jetsam event ended agentstored.

## Docs (his "all related docs and help updated", 2026-11-08)
- Help, `site/help/terminal-sessions.md`: Paste says a paste is text and control characters are left out, pointing
  to the keyboard bar for Escape and Control; Drop files says how a name with a line break, a control character or
  an invisible formatting mark is typed. The site built locally (its link check passed); not deployed.
- `SECURITY.md` (Connections): pasting into a terminal sends text only. `RELEASE-NOTES.md` has 0.4.610.
- Memory bank: D103, `systemPatterns.md` (one place for paste bytes; whoever owns a UIKit `TerminalView` calls
  `updateUiClosed()`), `techContext.md` (the display link), `progress.md`.
