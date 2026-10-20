# After the first release: Scale on local tabs, the folder button's Open in Editor, iCloud's words (2026-10-20)

**His words:** "fix that, and also allow a right on the folder icon in the terminal toolbar to Open in Editor which
either opens the Project with the same server/path or it opens a new Editor with pwd at the working directory."
"That" was two things found after 0.4.491: Scale Text ignored by the Mac's own terminals (his question, "Why is
this?"), and the signed-out iCloud wording seen running the release in the VM.

**Authorization:** build it; commits and releases on his word.

## Built (for 0.4.492)

- **Scale Text on local tabs:** `MacLocalTerminalPaneView` gets what `TerminalWindowView` has:
  - `TerminalScaling` (the window's When Resized), once the terminal has measured its grid;
  - the bar's Scale Text (`TerminalScaleToggle`), in the toolbar and the tools menu;
  - the window held to the grid's shape unless split;
  - ⌘+/⌘−/⌘0 sizing the window under Scale (`TerminalScaling.zoomStep`, moved there from `TerminalWindowView`).
  - The engine (`MacLocalProcessEngine.setScaling`) and the PTY proxy's kept-grid guard were already there.
- **Open in Editor on the folder button:**
  - `GlassEditorProjectLibrary.project(containing:on:)` returns the project at that folder, else the nearest one
    holding it, on any of a machine's ids.
  - `GlassTerminalRuntime.openWorkingFolderInEditor(serverID?, path)` is wired in the app. With no project, a
    folder on this Mac opens in a new editor window (`open(urls:)`), and one on another machine opens as a project
    (`openFolderAsProject`).
  - This Mac counts as nil, `GlassLocalHost.id` and its library machine (D86).
  - The local pane's folder button gets a right-click menu: Open in Finder and Open in Editor. Its problems are
    worded as Open Folder Here's (`MacLocalShellFolder.open`).
  - The SSH pane's existing menu uses the new rule.
  - **A Mac toolbar never shows a button's own right-click menu.** On macOS 26 the toolbar answers with Icon and Text
    / Icon Only before any item's view hears the click. A probe app in the VM showed this for `.contextMenu`, an
    overlay view and an AppKit `NSButton` with its own menu. The SSH folder button's `.contextMenu` (2026-10-09) never
    worked on a Mac.
  - First answer (0.4.492): `MacToolbarItemMenu`, a local event monitor that answered the right-click itself. It
    worked in the VM.
  - **His call** (seeing 0.4.492): "it should be a regular drop down like … new terminal, not a right click. That will
    remove custom overrides."
  - **0.4.493:** on the Mac both folder buttons are `Menu { … } primaryAction:`, the split button **+** uses. A click
    opens Finder or Files; the arrow opens Open in Finder/Files and Open in Editor. `MacToolbarItemMenu` and its
    tests are deleted. iPad and Vision Pro keep `.contextMenu` (pinch and hold).
  - **In the VM:** the folder is its own capsule with an arrow, as **+** is; the arrow's menu and Open in Editor
    worked.
- **iCloud:** `GlassCatalogSyncStatus.after(_:)` turns CloudKit's errors into a status:
  - `.notAuthenticated`, `.accountTemporarilyUnavailable` and `.managedAccountRestricted` become `.unavailable`,
    in words that say what to do;
  - anything else is `.failed` as before.
  - The `.unavailable` state existed and nothing set it.

## Tests (each seen failing without its change)

- `GlassCatalogSyncWordingTests` (3): signed out, restricted, other failures.
- `MacLocalPaneScaleTests` (1): a real pane running `/bin/sh` with the window set to Scale. Half the window, and
  `stty size` is unchanged. Without the hook, the pane never started scaling.
- `LiveTmuxControlResizeTests` +1: under Scale a smaller window leaves tmux's window size alone. Without Scale, it
  changes.
- `GlassEditorProjectLibraryTests` +1: exact, holding, nearest, the same machine, a name that only starts the same,
  This Mac as nil.
- **In the VM, with real right-clicks** (`~/Software/glass/tmp/rclick`):
  - With 0.4.492's monitor, the local tab's folder showed Open in Finder and Open in Editor (before: Icon and Text).
  - Open in Editor opened the home folder in a new editor window, "On this Mac".
  - After `cd Desktop`, it brought that project forward with no new window.
  - Scale Text on the local tab kept 105 × 41 (`tput`) as the window shrank.
- **Suites:** shell 344, terminal 961, editor 173.

## Docs

- `terminal-sessions.md` and `library-sync.md` updated.
- The terminal page's limit is removed.
- `RELEASE-NOTES.md` has a 0.4.492 section, "not yet released".
- The live site still describes 0.4.491 until the next release.
