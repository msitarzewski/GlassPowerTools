# Undo in the Editor, first class "like say TextEdit" (2026-11-03)

**Ask (the owner):** "Up next is making sure that all of the expected text editor functions work in the... Editor.
Like, for example, UNDO! LOL. It must be first class.. like say TextEdit :D"
**Status:** undo and redo fixed on every platform (0.4.594); the Mac's Edit menu brought to TextEdit's (0.4.595, his "go
ahead with the rest of the Edit menu"); iPad, iPhone and Vision Pro keys, Transformations and the Settings switches
(0.4.596, his "go ahead with iPad and Vision Pro"). Mac on 0.4.596; headset and iPhone not installed. Uncommitted.

## What was wrong
- The editor has one undo authority, `UndoCoordinator` (GlassEditorCore), reached by `GlassEditorModel.undo()/redo()`
  and the engines' `undo()/redo()`. Nothing in the app called them but the iPhone Duo's fold strip.
- Both text views returned `nil` for `undoManager` and the Mac's set `allowsUndo = false`, on purpose, so that AppKit's
  and UIKit's own undo would not keep a second, disagreeing record. With nothing put in its place, Edit ▸ Undo stayed
  grey and ⌘Z did nothing in the Mac editor; on iPhone, iPad and Vision Pro neither ⌘Z nor any system undo did
  anything. A test (`canvasAndUndoOwnership`) asserted the `nil`.
- A cut had no intent: inferred as a backspace, it coalesced with neighbouring deletions.

## Fix
- `GlassEditorUndoManager` (GlassEditorUI/Shared): an `UndoManager` that records nothing (registration disabled, so
  UIKit's own typing records add nothing) and answers from the editor — `canUndo`, `undo()`, names ("Undo Typing",
  "Undo Paste", "Undo Cut", "Undo Replace All"; unnamed: "Undo", trimmed of Foundation's trailing space). Set by each
  engine as its text view's `undoManager`.
- **Mac:** `NSWindow` answers `undo:`/`redo:` with its own manager and never asks the first responder's (measured: a
  probe in `~/Software/glass/tmp/undo-probe` and the tests). So `GlassTextView` answers `undo:`/`redo:` itself and
  validates and titles the items (`validateMenuItem`, `validateUserInterfaceItem`), first in the chain while it has
  the keyboard; a window's own undo is never reached from the editor.
- **iPhone, iPad, Vision Pro:** UIKit has no undo action; ⌘Z, the menu bar's Undo, shake, the three-finger swipe and the
  keyboard's buttons use the first responder's `undoManager`, which is now the editor's.
- `EditIntent.cut`, its own unit; both platforms' `cut(_:)` tag it. `UndoCoordinator.newestRedoIntent` and
  `GlassEditorModel.newestRedoIntent` for "Redo Typing".

## Validation
- Mac (`AppKitEngineTests`, 35 pass): the editor is the first responder answering `undo:`; the item enabled and titled
  "Undo Typing"; `undo:`/`redo:` sent up the chain undo and redo; nothing to undo disables it and leaves the window's
  own undo untouched; a cut is its own step named Cut. Seen failing with the text view's actions removed (6 issues);
  restored, compared.
- iOS simulator (`EditorUITests` scheme, 10 pass, 3 new in `UIKitUndoTests`): the text view's manager is the editor's;
  undo and redo through it, named; a UIKit-style registration adds nothing; backspace and paste named. Edits made as
  UIKit makes them (delegate, then text): a test host has no keyboard session for `insertText`. Seen failing with the
  `nil` manager put back; restored, compared.
- macOS VM, real keystrokes in the demo editor (`~/Software/glass/tmp/editor-audit`): typed "AUDIT ", ⌘Z took it back,
  ⇧⌘Z brought it back, Edit ▸ Undo took it back; the open menu read "Undo Typing ⌘Z", Redo grey.
- Package tests: 3,341 pass.
- Not yet: the system gestures on a device or simulator by hand (shake, three-finger swipe, the keyboard bar).

## TextEdit's Edit menu against the editor's (Mac, read from the running app in the VM)
- Present and working: Undo, Redo, Cut, Copy, Paste, Delete, Select All, Find (Find…, Find Next, Find Previous;
  the shell's own group, `GlassShellFindCommands`), AutoFill, Start Dictation, Emoji & Symbols.
- **Missing:** Paste and Match Style (⌥⇧⌘V; a plain-text view pastes plain anyway), Find ▸ Find and Replace… (⌥⌘F; the
  editor's find bar has Replace and Replace All, but not from the menu), Use Selection for Find (⌘E), Jump to
  Selection (⌘J), Spelling and Grammar, Substitutions, Transformations (Make Upper Case, Make Lower Case,
  Capitalize), Speech. SwiftUI's `TextEditingCommands` would add most of them, with a Find group that fights the
  shell's for ⌘F and ⌘G (why it was left out), so they need adding another way.
- Next: add them, then the same audit for iPad and Vision Pro with a keyboard.

## The rest of the Edit menu (0.4.595)
- **Find:** `GlassFindItemAction` takes optional `findAndReplace` (⌥⌘F: the bar, keyboard in Replace),
  `useSelection` (⌘E: the selection as the term, escaped for a pattern search; nothing selected keeps the term) and
  `jumpToSelection` (⌘J: reveal). The editor gives them (`GlassEditorWorkspace`); the terminal doesn't, so they're
  grey there. The find bar gains **Replace** (TextEdit's Replace & Find: the selected match, else the next, then the
  next selected; Return in the Replace field too), recorded as the new `EditIntent.replace` ("Undo Replace";
  `replaceNext` had recorded "Replace All").
- **Paste and Match Style** (⌥⇧⌘V, `pasteAsPlainText:`), **Spelling and Grammar**, **Substitutions**,
  **Transformations**, **Speech** in `GlassEditorCommands`: buttons send AppKit's standard actions to the first
  responder (`NSApp.sendAction(_:to: nil, …)`), as TextEdit's items do; enabled while an editor window is in front.
  `CommandGroup(after: .textEditing)` and `(after: .pasteboard)` — not `replacing:` (the menu placement guard,
  `MenuBarPlacementTests`, caught a first `replacing:`). Not SwiftUI's `TextEditingCommands`, whose Find group fights
  the shell's for ⌘F/⌘G. Paste and Match Style lands after Find, not straight after Paste: only replacing the
  pasteboard group could put it there, which would lose the system's own validation of Cut/Copy/Paste.
- **Switches** (spelling, grammar, autocorrection, smart copy/paste, quotes, dashes, links, data detectors, text
  replacement): `GlassTextChecking` (GlassEditorUI), app-wide and remembered (UserDefaults `editor.*`), off by default.
  Applied by each engine to its text view when `GlassEditorConfiguration.followsTextChecking` (new, default false):
  the Editor's documents set it (`GlassEditorPreferences.configuration`); the database's SQL and record editors never,
  where a smart quote breaks a query. UIKit gets what it has (spelling, autocorrection, quotes, dashes, insert/delete).
- Tests: `textEditsFindItems` (workspace), `textCheckingFollowsTheMenu` (AppKit engine; seen failing with the opt-in
  ignored: the SQL view got spelling and smart quotes); package 3,343 pass; UIKit editor tests 10 pass.
- macOS VM, the running app: the Edit menu as TextEdit's, every item enabled in the editor with its key; Make Lower
  Case turned "AUDIT" to "audit" and ⌘Z restored it; ⌘E put "AUDIT" in the find field; Check Spelling While Typing
  ticked on screen and still ticked after a relaunch. (Menu state read by accessibility is stale until the menu
  opens.) The VM's GUI session had dropped once (launch error -10810, "could not create image from display"):
  `macvm.sh stop` / `start` brought it back.
- Installed: Mac 0.4.595. Headset and iPhone refused (asleep or locked): to install.
- **Not yet:** iPad and Vision Pro have no menu for the switches or the new Find items (the Mac's menu only); their
  keyboards' ⌘Z/⇧⌘Z work through the undo manager. Next: Settings ▸ Editor for the switches there, and ⌥⌘F/⌘E/⌘J as key
  commands in the editor.

## iPad, iPhone and Vision Pro (0.4.596, his "go ahead with iPad and Vision Pro")
- **Keys:** `EditorKeyCommands` (GlassEditorWorkspaceView, `#if !os(macOS)`): unseen buttons in the editor window with
  the Mac's Edit ▸ Find and Text menu keys — ⌥⌘F, ⌘G, ⇧⌘G, ⌘E, ⌘J, ⌥⌘L, ⌘+/⌘=, ⌘−, ⌘0. ⌘F stays the toolbar Find
  button's. View-level keys belong to their window, so the terminal's ⌘+/⌘− are untouched. The shortcut guard
  (`MenuBarPlacementTests`) now allows the editor's ⌘G/⇧⌘G only inside `#if !os(macOS)` (`editorDeclaresOnTheMac`),
  as its ⌘S; seen failing with a ⌘G placed where the Mac compiles.
- **Transformations** in the selection's menu (`GlassEditorUICoordinator.textView(_:editMenuForTextIn:…)`): Make Upper
  Case, Make Lower Case, Capitalize, each one model edit (`EditIntent.changeCase`, "Undo Change Case"), the change left
  selected. The Mac's Transformations tag the same intent (`GlassTextView` overrides).
- **Settings ▸ Editor ▸ Spelling and Substitutions** (`GlassEditorSettingsView`, every platform): the
  `GlassTextChecking` switches; UIKit's subset off the Mac.
- Tests: `UIKitUndoTests.transformations` (simulator; fails with the menu removed); `EditorKeyboardUITests` (new UI
  test, real key presses): **iPad simulator passes** — ⌘Z took typing back, ⇧⌘Z restored it, ⌘E then ⌥⌘F opened the
  bar with the selection in Find and the Replace field; fails with the text view's manager `nil` and the keys removed
  (⌘Z and ⌥⌘F both). **Vision Pro simulator:** ⌘Z and ⇧⌘Z pass; ⌥⌘F fails, and so does ⌘F, the toolbar key that
  already worked — the visionOS runner doesn't deliver SwiftUI shortcuts (memory: visionOS UI runner limits). The
  find keys on Vision Pro are for the headset.
- Package tests 3,343 pass; UIKit editor tests 11 pass (iPhone simulator).
- **Installed:** 0.4.596 on all three, read back: Mac (no crash reports, 2026-11-03), iPhone and headset (2026-11-05,
  after `devicectl` had them "unavailable", error 4016).
- **For him to try on the headset:** ⌘G, ⌘E, ⌥⌘F with a keyboard; Transformations in the selection menu; Settings ▸
  Editor ▸ Spelling and Substitutions. Not yet: shake, three-finger swipe, the keyboard bar's undo, by hand.
- Uncommitted (with 0.4.592–0.4.595).

