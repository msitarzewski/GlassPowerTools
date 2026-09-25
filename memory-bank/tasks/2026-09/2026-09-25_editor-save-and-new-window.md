# Editor: ⇧⌘E opens a blank document, ⌘S saves, the title follows — 2026-09-25

The user, making a new `.env` in a new project: ⇧⌘E, then ⌘N, typed, ⌘S → the system beep; File ▸
Save Document worked, and afterwards the title bar still said "Untitled". *"Shift-command-e should
open a new blank text document, ready to edit. The user can then use the File menu, or command keys
to open a project or folder."* Authorized by that report; local changes only.

## Causes (from the source)

1. **⌘S beeped in an editor.** ⌘S was the database's "Save SQL Document…" (`Constants.swift`),
   disabled unless a database workspace is focused. The editor's Save was "Save Document" on ⌥⌘S.
2. **The title stayed "Untitled".** The save panel is SwiftUI's `fileExporter`, whose `isPresented`
   setter cleared `exportingDocument`; the completion read that same state to learn which document to
   adopt the file for. Dismissal first → nothing adopted: the file written, the tab still untitled
   and dirty. Inferred from the code, to be confirmed in the running app.
3. **⇧⌘E opened an empty editor**, needing ⌘N before it was any use.

## Changes

- `GlassShellFileCommands.swift`: `GlassSaveItemAction` / `\.glassSaveItem`, and the shell's one
  File ▸ Save on ⌘S, **inside the shell's New group** — ⌘N's pattern. Read out of the running app:
  from the shell's commands (attached to the library scene), `replacing: .saveItem` (0.4.218) and
  `after: .saveItem` (0.4.219) both drew nothing; the editor's own `after: .saveItem` item had
  drawn, from the editor's scene (the user: *"Save WAS in there before you started looking for it"*).
  0.4.220, beside New: present.
- `GlassEditorWorkspaceView.swift`: publishes Save ("Save…" when untitled, enabled for an untitled
  document or a dirty one, none for a viewer); `exportTarget` holds the panel's document apart from
  the presentation state.
- `DatabaseWorkspaceView.swift`: publishes "Save SQL Document…"; the database's own ⌘S item remains
  only off the Mac (`#if !os(macOS)`), where the shell's item does not exist.
- `GlassEditorScenes.swift`: ⌥⌘S "Save Document" removed; `GlassEditorActions` loses `canSave`/`save`;
  New Editor Window makes the workspace, adds an untitled document, then opens the window.
- `MenuBarPlacementTests.swift`: `saveItem` recorded; ⌘S single-menu-owner and publisher guards.

## Validation

- `swift test`: 1,760 tests passed (8 menu-placement tests among them).
- 0.4.220 installed on the Mac and relaunched (version read back). Menu bar read through System
  Events: File ▸ Save ⌘S present, disabled with the library in front; New Editor Window ⇧⌘E.
- Not yet verified in the running app: Save… enabled in an editor, ⇧⌘E's blank document taking
  typing at once, and the tab and title following a Save…. Left to the user, who is at the Mac.
- Observed in the running menu bar: **Explain Plan had no ⇧⌘E** — New Editor Window held the key and
  the Query menu's item lost it. The user agreed: Explain Plan moved to ⌥⌘E (Query menu and the SQL
  editor's toolbar button); `shiftCommandEHasASingleOwner` guards it.

## ⌘W on the last document closes the window

The user: *"Command w means I'm done here. Not looking for a prompt to do something else."* ⌘W on
the window's last document used to leave "No Document" and its three buttons. Now
`MacEditorWindowBehaviour` marks the close and, once the document count reaches zero (after the
unsaved-changes question, if any), closes **its own window** — held by `GlassEditorWindowHolder`
through the frame-memory view, not `NSApp.keyWindow`, which a dismissing sheet can still be. Cancel,
or Save to a new file, clears the mark. A window with a project open stays on its tree.

## Installed

0.4.222 on the Mac, relaunched, version read back. Menu bar read: Save ⌘S, New Editor Window ⇧⌘E,
Explain Plan ⌥⌘E. 1,761 unit tests pass. The click-through (⇧⌘E → type → ⌘S → title; ⌘W on the last
document) is the user's, at the Mac.


## "The save button said Export?" — 0.4.223

SwiftUI's `fileExporter` on a Mac is an export panel ("Export As:", Export) and, typed as plain
text, offered `Untitled.txt` — a `.env` would have been `.env.txt`. On the Mac, a never-saved
document now goes through `GlassEditorSavePanel` (`NSSavePanel`, a sheet on the main window, no
content types so no extension is added); the document writes the file once. The unsaved-changes
question's Save uses it too, then closes the document (and the window, when ⌘W began it); Cancel in
either place calls the close off (`closeCancellations`). iPhone, iPad and headset keep
`fileExporter`. 1,761 tests pass; 0.4.223 installed and relaunched, version read back. Click-through
is the user's.
