# 2026-11-22 — A Mac editor window opened at its smallest and could only grow (0.4.638)

**Owner and authorization:** his report, "I just notivced that I can't resize a text editor created with shift command
E?", with "What other things doesn't our editor do that it should?!?" (the survey is below). Local edits, tests, VM
checks; the Mac install is standing. Committed and pushed 2026-11-22 at his word, with 0.4.633–0.4.637.

## What was wrong (measured in the macOS VM, 26.6.2)
- **Every new editor window opened at its minimum**, 820 × 572 (820 × 520 of content below a 52-point toolbar), where
  it could only be made larger. ⇧⌘E and a second window alike.
- **Its size was never kept.** `GlassEditorWindowFrameMemory` set an AppKit autosave name; SwiftUI gives its windows
  names of its own (`editor-AppWindow-1`) and replaced it. Neither his Mac's preferences nor the VM's had a frame under
  the app's name. B-F45 (his 09-17 ask that the size persist) was open.
- **Cause of the shrink**, from a resize observer with call stacks (`tmp/editor-size/resizes.log`): SwiftUI makes the
  window at 1100 × 720 (`defaultSize`); `makeKeyAndOrderFront` → `_setUpFirstResponderBeforeBecomingVisible` →
  `NSWindow(NSConstraintBasedLayoutInternal) layoutIfNeeded` → `NSHostingView.windowDidLayout` →
  `updateAnimatedWindowSize` sets the window to the content's minimum, before the window is first drawn.
- **What it takes**, one launch per part left out (`tmp/editor-size/diag.log`, `diag2.log`): the title band's frost
  (`GlassWindowChrome.installTitlebarMaterial`, held in the window's frame view by constraints) together with the
  `NavigationSplitView`. Without either, or with the frost installed once the window is on screen, the window kept
  1100 × 720. Sidebar tracking (`followSidebarBoundary`), the orb modifier, the picture reader, the lifecycle, the
  toolbar, the bolt, the presenter and the opener made no difference. An ideal size on the content
  (`.frame(idealWidth:idealHeight:)`, the database empty window's B-X20 pattern) made none either, at seven sizes.
- Not found: why SwiftUI aims at the minimum there. An earlier theory (the autosave rename) was tested and wrong.

## Changed
- `Sources/GlassEditor/GlassEditorScenes.swift`: `GlassEditorWindowSize.minimum` 480 × 300 (was 820 × 520);
  `opening(remembered:screen:)` (screenshots' size, else kept, else 1100 × 720; within the minimum and the screen);
  `undoing(shrinkOf:to:)`; the scene's `defaultWindowPlacement` (macOS) at the opening size. The cause in its comment.
- `Sources/GlassEditor/GlassEditorWorkspaceView.swift`: `GlassEditorWindowFrameMemory` no longer sets an autosave name.
  While the window is not yet visible it puts a shrink back to the frame it was made at (three times at most; nothing
  once visible), synchronously from `didResizeNotification`, so the first frame drawn is the right size. It keeps the
  whole window's size at the end of a live resize and on close (not in full screen). Placement's size is the whole
  window's, measured: keeping the content's lost 52 points per reopen in the first try.
- `Sources/GlassEditor/GlassEditorPreferences.swift`: `windowSize`, `keepWindowSize`, key
  `com.glasspowertools.editor.windowSize`, on this device only; a stored value outside 100…20,000 is ignored.
- Chosen over deferring the frost until the window is visible (also proven): that changes every glass window and may
  draw a first frame without the frost, which he caught once in a recording (2026-10-17).
- Help `site/help/editor-opening.md`; RELEASE-NOTES 0.4.638.

## Checked
- `GlassEditorWindowSizeTests`, 6; the GlassEditorTests target, 249 pass.
- Each rule seen failing with it undone (`tmp/editor-size/bite.py`, `bite.log`): the old floor; the size never written;
  the kept size ignored; a shrink never undone; only a narrower window put back; a damaged stored size believed.
- **macOS VM**, Debug build of this tree (`tmp/editor-size/check.zsh`, `check2.log`; pictures in `tmp/editor-size/vm`
  and `.scratch/shots/macvm/editor-min.png`): ⇧⌘E opens 1100 × 720; dragged to 600 × 420; asked for 300 × 200 it stops
  at 480 × 352; left at 600 × 432 and closed, the next opens at 600 × 432, a second cascades beside it, and after a
  relaunch a new one opens at 600 × 432. At its smallest the toolbar folds into », and the title, text and status line
  fit. Without the undo (the same build, diagnostics on) the window opened at 480 × 352. VM stopped.
- Not tried: macOS 27 (his Mac; the VM is 26.6.2); a window opened from a project or a file (same scene and view);
  per-project sizes (B-F45's "per editor window": one size for the editor, since no editor window comes back).

## The editor's gaps, surveyed the same day (his second question)
An agent read the editor's source, help and records; a second agent checked the 24 features from raw source and agreed;
seven of the claims spot-checked by hand held. Missing on every platform: indentation kept on Return, block indent and
outdent, tab width and spaces; autosave and recovery; comment toggle and line operations; whole-word find in the bar
(the engine has it, `FindQuery.wholeWord`), other matches highlighted, find in selection and in a project; bracket
matching, auto-closing pairs, current-line highlight. Mac File menu short of TextEdit's: Save As/Duplicate, Rename,
Move To, Revert, Print, PDF, Share. The tree has no new folder, rename, delete or Reveal in Finder. No Open Quickly or
symbols; tabs not reorderable, no reopen-closed or next/previous keys. Encoding detected but never shown or changed;
line endings shown, not converted. 15 grammars; no font choice or themes. iPhone/iPad keyboard fixed to
`.asciiCapable` (`GlassTextViewIOS.swift:145`). No watching for changes on disk. Help claims to check:
`editor-files-and-tabs.md` (undo buttons, gestures, never tried by hand), `editor-languages.md` (keys listed while ⌘ is
held on iPad), Close Project (help says none by design; B-F46 lists it open).

## Next
- His look at ⇧⌘E on 0.4.638 on macOS 27.
- The first four gaps, at his word: `2026-11-22_editor-first-gaps.md`.
