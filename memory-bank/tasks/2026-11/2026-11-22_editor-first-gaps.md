# 2026-11-22 — The editor's first gaps: Whole Word, indentation, ⌘/ and line commands, autosave

**Owner and authorization:** his word after the survey in `2026-11-22_editor-window-size.md`: the four recommended
fixes, each checked off as it is completed. Local edits, tests, builds and installs on his Mac, iPhone and headset (the
standing install). Commit and push at his word.

## Checklist
- [x] 1. Whole Word in the find bar (the engine has `FindQuery.wholeWord`; the bar never set it). **0.4.639**, installed
      2026-11-22 17:02 on his Mac (read back, running, no crash report), the iPhone and the headset.
- [x] 2. Indentation: Return keeps the line's indent; indent and outdent a selection (⌘] and ⌘[; Tab and ⇧Tab over
      lines); tab width and spaces. **0.4.640**, installed 2026-11-22 17:37 on his Mac (read back, running, no crash
      report), the iPhone and the headset.
- [x] 3. ⌘/ comments lines out and back in, by the language; line commands: duplicate, move up and down, delete, join,
      sort. **0.4.641**, installed 2026-11-22 17:58 on his Mac (read back, running, no crash report), the iPhone and the
      headset.
- [x] 4. Autosave and recovery: unsaved edits survive a crash, a quit and the system ending the app. **0.4.642**,
      installed 2026-11-22 18:24 on his Mac (read back, running, no crash report), the iPhone and the headset. (A quit
      that asks still asks; Quit Without Saving lets the changes go, as it says.)

## Notes

### 1. Whole Word (0.4.639)
- `GlassEditorWorkspace.findMatchesWholeWords` into `findQueryValue`; the bar's third switch, "ab" underlined (VS Code's
  sign), between Match Case and Regular Expression; all three now named for VoiceOver (Match Case, Whole Words, Regular
  Expression). Find, the count and Replace/All follow it, through `findQueryValue`.
- Test `GlassEditorWorkspaceTests.wholeWordsInTheFindBar` ("red" not in "bored", "reddish" or "red_x"; found in
  "(red)"); seen failing with the switch not passed on (`<work>/editor-gaps/1-whole-word.log`). GlassEditorWorkspaceTests
  21 pass. Help `editor-languages.md`; RELEASE-NOTES 0.4.639.

### 2. Indentation (0.4.640)
- **Core** (`Sources/GlassEditorCore/Editing/`): `Indentation` (tabs or spaces, width 1–16, `unit`, `statusName`),
  `Indentation.detect` (tab-led lines against lines led by two or more spaces; the commonest step 2/3/4/8 between a
  line and a deeper next one, ties to 4 then 2; blank and single-space lines say nothing; first 2,000 lines, by bytes),
  `IndentationSource` (settings, file, chosen) and `following(_:from:)`; `LineEditing` (`lines(in:covering:)` — a
  selection ending at a line's start leaves that line out; `newline`, `tab`, `visualColumn`, `selectionSpansLines` — a
  whole line with its break counts, so Tab over a triple-clicked line indents rather than deleting it; `indent`,
  `outdent`), each one `TextEdit` over whole lines and the selection after.
- **Configuration**: `indentation`, `indentationSource`; the model detects at init when the source is settings.
  `GlassEditorPreferences.indentation` (persisted in the appearance dictionary as `indentsWithTabs`, `indentWidth`);
  `configuration(basedOn:)` applies `following`: all of it for settings, only a tab's width for a file's tabs, nothing
  for a file's spaces or a chosen one. The window re-applies on a change (`onChange(of: preferences.indentation)`).
- **Drawing**: `AttributedAssembly.baseAttributes` carries a paragraph style with `defaultTabInterval` = width × the
  font's space, no tab stops; both coordinators refresh it in the typing attributes; both engines repaint when the
  width changes.
- **Mac** (`GlassTextView`): `insertNewline`, `insertTab` (lines → `indentLines`), `insertBacktab` → `outdentLines`;
  `indentLines(_:)`/`outdentLines(_:)` through `shouldChangeText` → storage → `didChangeText`, `pendingIntent =
  .indentation`, so only the lines change and it is one "Undo Indentation". Text menu Indent ⌘], Outdent ⌘[ sent to
  the first responder, as Transformations are.
- **UIKit**: Return and Tab in the delegate (`GlassEditorUICoordinator.typedReturnOrTab`, from `shouldChangeTextIn`,
  which every keyboard asks first): the document as one step, then the view's storage under the guard with the input
  delegate told, the caret, `textViewDidChange`; answers false. **An override of `insertText` was tried first and was
  wrong:** on the simulator `UITextView.insertText` changed the view without asking the delegate, so the document
  never had the indent, and on a device the keyboard would have told the document "\n" and the view "\n    ". Key
  commands ⌘], ⌘[ and ⇧Tab (priority over the system's) on `GlassTextViewIOS`, titled for the ⌘ overlay;
  `performLineEdit` as Change Case does it (model, then sync); the selection menu's **Lines** ▸ Indent, Outdent, at a
  caret too.
- **Editor**: Settings ▸ Editor ▸ Indentation (Indent Using, Width) with a footer; the status bar's menu (Spaces: 4 /
  Tab Width: 4), which sets the document's indentation as chosen.
- Tests: `LineEditingTests` 6 (core); `AppKitIndentationTests` 5 (a real `NSTextView` in a window never shown:
  Return, Tab by the file, Tab and ⇧Tab over lines with undo titles, the menu actions up the responder chain, tab
  stops); `GlassEditorWorkspaceTests.indentationFollowsTheFileThenSettings`; `UIKitIndentationTests` 4 on the iPhone 17
  simulator (indent/outdent with undo, the key commands, Lines at a caret, tab stops). `UIKitUndoTests.transformations`
  changed: at a caret the menu now holds Lines, still no Transformations. Found on the way: a first test crashed the
  process because `NSWindow` released itself on close and ARC again (`isReleasedWhenClosed = false`).
- `UIKitIndentationTests` 5 with Return and Tab asked of the delegate as a keyboard asks it (16 UIKit tests pass).
- Each rule seen failing undone (`<work>/editor-gaps/2-indentation.log`, `2b-recheck.log`, `2c-uikit.log`): 13 on the
  Mac and core, 4 on the simulator. The tool first misread two as not compiling: a failure's dump held
  `TokenRole.error:`; it now looks for a compiler's `.swift:N:N: error:`.
- Whole targets after: GlassEditorCoreTests 331, GlassEditorUITests 126, GlassEditorTests 251, GlassDatabaseTests 357
  (the SQL editor shares the text view and its Return).
- Not tried: a real keyboard on a device (the delegate path is the one the keyboard asks; a person's Return on the
  iPhone and headset is his check).

### 3. ⌘/ and the line commands (0.4.641)
- **Core** (`Sources/GlassEditorCore/Editing/LineCommands.swift`): `LineCommand` (comment, duplicate, moveUp, moveDown,
  delete, join, sort; `undoName`); `LanguageID.lineComment` (`//` Swift, JS, Go, Rust, C, PHP; `#` shell, YAML, TOML,
  Python; `--` SQL; none for JSON, Markdown, XML, HTML, plain text) and `blockComment` (`<!-- -->` for HTML, XML,
  Markdown); `LineEditing.Splice` and `moved(_:through:keepsBefore:)` for offsets through a change;
  `toggleComment` (uncomment only when every line with text is commented; comment at the shallowest indent, token and
  a space; blank lines left alone; block comments in UTF-16 throughout), `duplicate` (the copy selected; the last line
  takes the file's own break), `move` (breaks stay in their slots, so the file's last line keeps having none; a
  selection's end at a line's start belongs to the line before), `delete` (the last line takes the break before it),
  `join` (one space, the next line's indent gone; a caret joins its line and the next), `sort`
  (`localizedStandardCompare`, nil when already in order). Every command clamps the selection to the text first.
- **Undo**: `EditIntent.lineCommand(LineCommand)`, its own unit; Undo Comment, Undo Duplicate Lines, Undo Move Lines,
  Undo Delete Lines, Undo Join Lines, Undo Sort Lines.
- **Mac**: `GlassTextView` actions (`toggleLineComments(_:)` … `sortLines(_:)`) through `performLineEdit`; Text menu:
  Comment or Uncomment Lines ⌘/, Move Lines Up ⌃⌘↑, Move Lines Down ⌃⌘↓, Duplicate Lines, Delete Lines ⇧⌘K, Join
  Lines, Sort Lines. **UIKit**: the same actions on `GlassTextViewIOS`, key commands with the Mac's keys, and the
  selection menu's Lines (Indent, Outdent, Comment or Uncomment, Move Up, Move Down, Duplicate, Delete, Join, Sort).
- Tests: `LineCommandTests` 7; `AppKitIndentationTests.lineCommands`; `UIKitIndentationTests.lineCommands` and
  `lineCommandKeys` (18 UIKit tests pass on the iPhone 17 simulator); `MenuBarPlacementTests.editorLineKeysHaveOneMacOwner`
  (⌘], ⌘/, ⇧⌘K and ⌃⌘↑/↓ the Text menu's alone; ⌘['s other declaration Vision Pro only; ⌥⌘] still the terminal's).
  Found by a test: a selection past the end crashed a helper, so commands clamp (and a test feeds one).
- Each rule seen failing undone (`<work>/editor-gaps/3-lines.log`, `3b-clamp.log`, `3c-uikit.log`): 12 on the Mac and
  core, 2 on the simulator; the tool now counts a crashed test process as a failure.
- Whole targets after: GlassEditorCoreTests 338, GlassEditorUITests 127, GlassEditorTests 251, GlassDatabaseTests 357,
  GlassShellTests 446.
- Not tried: the running app's menu bar read back (the guard reads declarations; his look at the Text menu, or the VM).

### 4. Autosave and recovery (0.4.642)
- **Store** (`Sources/GlassEditor/GlassEditorRecovery.swift`): one JSON per text document with unsaved changes in
  `Application Support/GlassPowerTools/EditorRecovery` (a UI test run's in `uitests-<run>`); `Record` holds the text,
  name, local path (nil for untitled and remote), machine, language, its window, when kept; written atomically, with
  complete-until-first-unlock protection off the Mac. `sweep` writes a document whose revision moved since its last
  copy and removes the copies this run wrote of documents no longer unsaved or open; an earlier run's copies are never
  swept (`recordsFromEarlierRuns`). The SQL editor's `SQLDraftStore` was the pattern.
- **Runtime** (`GlassEditorRuntime`): `recovery`; `startKeepingUnsavedText` (every 2 s), `keepUnsavedTextNow` (also on
  any scene phase but active, from `GlassEditorBootstrap`), `discardUnsavedText` (Quit Without Saving, through
  `MacTerminalAppDelegate.discardUnsavedDocuments`; nothing kept after it), `recoverUnsavedDocuments` (once, from the
  bootstrap's `.task`; records grouped by their old window into new windows; each old copy removed; the recovered
  documents kept again at once; windows shown with `show(_:with:)`). `closeWorkspace` forgets its documents;
  `GlassEditorWorkspace.close` forgets the document.
- **Workspace**: `adoptRecovered` — a readable local file opens bound to itself with the text over it as one
  programmatic edit (Undo returns to the file; closed again when the file already says it); otherwise an untitled
  document with the record's name and language. The window says "Recovered unsaved changes to … from when Glass Power
  Tools last closed. Save to keep them, or close without saving to let them go." once it is on screen
  (`noticeOnAppear`, `sayNoticeOnAppear`), "(from <machine>)" for a remote one.
- Tests: `GlassEditorRecoveryTests` 5 (kept while unsaved, following the text, gone when saved or closed; recovered
  after a crash into two windows, bound, unsaved, Undo to the file, said once, kept again; gone and remote files come
  back untitled, a damaged file ignored; Quit Without Saving keeps nothing after, a file already as the copy not
  reopened; this run's copies never taken for an earlier run's). Each of 10 rules seen failing undone
  (`<work>/editor-gaps/4-recovery.log`).
- **macOS VM** (`<work>/editor-gaps/recovery-vm.zsh`, `quit-vm.zsh`): text pasted into a new editor, kept within the
  sweep; `kill -9`; relaunched with the same run: the window back, 1100 × 720, the text, Edited, and the notice
  (`<work>/editor-gaps/vm/recovery.png`); kept again under its new identity. **Found there:** Quit Without Saving left
  the copy, because the app going inactive on its way out kept the document again, and the relaunch brought it back;
  fixed (`lettingGo`), and seen: no copies left, no window at the relaunch. My first VM run also pressed the notice's
  OK itself (the script's OK for Connections' own notice); the notice is held for the window's appearance either way.
- Whole targets after: GlassEditorCoreTests 338, GlassEditorUITests 127, GlassEditorTests 256, GlassDatabaseTests 357,
  GlassShellTests 446, GlassTerminalTests 1,324.
- Not tried: iPhone, iPad and Vision Pro (the same code path, from `GlassEditorBootstrap`; the system ending the app is
  his check); a project's file on another machine reopened over SSH (it comes back untitled, by design for now).

### Keys chosen for 2 and 3 (checked against every declared shortcut, 2026-11-22)
- Free: ⌘] and ⌘[ (the ⌘[ in `GlassSpatialColumns` is a Vision Pro view's, in another window), ⌘/, ⇧⌘K, ⌃⌘↑ and ⌃⌘↓.
- Taken: ⌥⌘] is the terminal's Focus Next Pane, so not Xcode's Move Line Down; ⌘D and ⇧⌘D are its Split Right and
  Split Down, so Duplicate Lines has no key yet (a contextual ⌘D, as ⌘N is, would give it one).
