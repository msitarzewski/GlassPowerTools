# 2026-11-20 — An SVG dragged onto a Mac terminal: the app quit on macOS 27 (0.4.632)

**Owner and authorization:** his question ("What happens when a user drags an svg into the terminal window?"), a crash
report and a log he pasted, and his answer on where the file came from ("downloads, but from the folder in the dock").
Local edits, tests, VM runs; the Mac install is standing. Not committed, not released: the release of 0.4.624 onward is
held at his word.

## The crash report and its log
- 0.4.623, macOS 27.2.1. `EXC_BAD_ACCESS` at 0x0 on the main thread, 33 s after launch: `NSWindow becomeKeyWindow` →
  hit-testing → the compiler's `@objc` thunk of `TmuxUnusedAreaView.hitTest(_:)` (symbolicated with `atos` against the
  released binary) → `swift_task_isCurrentExecutorWithFlagsImpl` → `isMainExecutor` → `_isSameExecutor` → a call to 0.
  The Swift 6 isolation check at the thunk's entry crashed before the view's code (`{ nil }`) ran.
- The same chain is reported by other Mac apps on macOS 27.0–27.2 with no cause found (quill #4, CodexBar #2250,
  redlamp #514, UTM #8006 on GitHub).
- The log, from the Dock's Downloads stack: `event=drop types=public.svg-image`, and 2 ms later AppKit's "Canceling
  drag because exception was raised during a dragging session. Exception: NSInternalInconsistencyException", twice: at
  11:28:24 (that launch ended 2 s later) and at 11:28:59.06, 90 ms before the crash. The crash report's other threads:
  AppKit's `_NSLegacyFilePromiseCoordinator` waiting, and HIServices' "swallowed at least one exception" thread.

## The cause
- `SFTPIncomingDrop` read the shared drag pasteboard (`NSPasteboard(name: .drag)`) and called the file promises it found
  in (`NSFilePromiseReceiver.receivePromisedFiles`) from the drop's task, after the drop. SwiftUI's `onDrop` had already
  called each promise in, into `~/Library/Caches/com.apple.SwiftUI.filePromises-<uuid>`.
- On macOS 27 that raises. The 0.4.623 drop code under a unit test on his Mac (macOS 27.3) dies with:
  `NSInternalInconsistencyException`, "receivePromisedFilesAtDestination:options:operationQueue:reader: can only be
  called during -prepareForDragOperation:, -performDragOperation:, and -concludeDragOperation:", thrown from
  `SFTPIncomingDrop.materialize`. In the app the drag session caught it, after it had unwound through a Swift task.
- **Inferred, not seen:** that exception left Swift's executor tracking pointing at a dead frame, and the next
  main-thread isolation check (the hit test) jumped to garbage. It fits the 90 ms, the null and varied addresses other
  apps report, and an Objective-C exception crossing Swift frames being undefined.
- On macOS 26 (the VM, 26.6.2) nothing raises: a modern promise called in again handed back SwiftUI's file, refused as
  not the drop's ("you don't have permission"); a legacy one waited 60 s and failed (`NSURLErrorDomain -1001`).
- Found on the way, in the VM: a Dock stack's drag isn't on the shared drag pasteboard, which still held the drag
  before. A Downloads-stack SVG typed `finder-like.svg`, a file dragged a minute earlier (read back with
  `tmp/svgdrag/dragboard.js`). The released code has the same flaw.

## Changed (0.4.632)
- `SFTPIncomingDrop` (`Sources/GlassTerminal/SFTPIncomingDrop.swift`): `init(providers:)` reads only the providers
  SwiftUI hands over, on every platform; no drag-pasteboard read, no `NSFilePromiseReceiver`, no `promiseReader`.
  `init(filesOn:)` for the Files browser's paste of Finder files (a promise there isn't taken: outside a drag macOS 27
  raises). On the Mac a provider's file URL (Finder's zip, folder) is used as it is (the app isn't sandboxed), and a
  file of a named type (SVG, text) is read in place (`loadInPlaceFileRepresentation`) and typed by its own path, unless
  it is held only for the drop (`isHeldOnlyForTheDrop`: the caches or temporary folder, where SwiftUI puts a promised
  file), which is copied into the drop's folder as before.
- `MacWorkspaceView.receiveDrop`: a drop that can't be read beeps (it failed silently).
- `SFTPBrowserView.pasteFilesFromFinder` uses `init(filesOn:)`.
- Help (`terminal-sessions.md`, Drop files on a terminal), RELEASE-NOTES 0.4.632.

## Checked
- Drop, remote-drop and SFTP suites: 118 tests pass. New tests, each seen failing with its piece undone
  (`tmp/drop-bite.py`, and the 0.4.623 file itself): a drop never takes the drag pasteboard's earlier file; Finder's
  files, a reference and a folder keep their own paths; a promised file held in place is copied; the held-folder rule;
  a pasted promise is neither taken nor called in. Against 0.4.623 the promise test dies of the exception above.
- VM (macOS 26.6.2, the Debug build), onto a local terminal: legacy and modern promises (test source
  `tmp/svgdrag/promisesrc.m`) type a copy in `~/Library/Caches/com.glasspowertools/Dropped/…`; Finder's SVG, text file,
  zip and folder in one drag type their own paths; the Dock's Downloads stack types its own file
  (`~/Downloads/archive.zip`), not the drag pasteboard's; no exception logged. What SwiftUI's items give for each kind
  was read with a probe (`tmp/svgdrag/DropProbe.swift`).
- Not tried: macOS 27 (no VM; his Mac is the check), an SSH pane's drop and the Files browser's drop live (same code,
  unit-tested), a screenshot thumbnail.

## Also found, and fixed at his word: 10 tmux tests failing since 0.4.622
- They failed alone too (not load). Since 66c3a29b (0.4.622, D111) every terminal rejoining a session it had or was
  given first checks the host lists it (then `tmuxSessionHasEnded`, `tmuxSessionGone` since 0.4.623); before, only one
  marked `tmuxJoinsOnly` did. These tests' fake hosts answered every command with "", which parses as no sessions, so
  each terminal closed. And Active's rows drop an agent's spinner since 0.4.621 (7b940e5a), which one still expected.
- Changed, tests only: `TerminalTmuxTests` (its `Host` lists what it runs, `listsWhatRuns`; a reconnect now lists once
  more and joins with `attach-session -t '=glass-1'`; a session from Active is joined, `-d` taking it over once),
  `TerminalFindTests.choosing`, `TerminalRepositoryTests.sshTab` and `MacLocalTmuxTests`' `HostSession` list their
  session; the W19 notes check leaves out the list; the This Mac test's Active titles have no spinner; one comment and
  one test name no longer say a reconnect makes a session again.
- Each was seen failing before (the reruns of 2026-11-20); the GlassTerminal module passes whole: 1,314 tests, 22.9 s
  (434 s while these waited out their 30 s checks). An eleventh, the sidebar test, failed once beside the VM build and
  passed alone and in the whole run.

## Next
- His Mac (0.4.632 installed 13:09): an SVG from the Dock's Downloads stack onto a terminal: the path typed, the app up.
