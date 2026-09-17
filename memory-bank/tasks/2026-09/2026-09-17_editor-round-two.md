# The editor, round two — 2026-09-17

**State** PLAN → BUILD · **Owner** coordinating agent · **Authorization** the user's test pass on
0.4.143, item by item. Committing is still not authorized and is asked for separately.

Round one is in [the stage 5.2 plan](2026-09-16_editor-stage-5.2-plan.md). Confirmed working by the
user: ⌘W in a database workspace, Swift highlighting, tab switching, the `+` and Filter header, the
footer bar, the tree's keyboard. What follows is what use turned up next.

| # | Report | Where |
|---|---|---|
| 1 | **The whole tab should be clickable**, not just its title | `GlassWorkspaceTabBar` |
| 2 | **A vertical rule shows through** the tab strip and the header | the split divider behind a translucent strip |
| 3 | **The gear should open Settings**, not a menu; **⌘+ / ⌘−** should change text size as the terminal's do | `GlassEditorWorkspaceView`, `MacWorkspaceCommands` for the precedent |
| 4 | **⇧⌘O opens a second editor window**, then a picker that will not take a folder; **cancelling leaves the empty window behind** | `GlassEditorCommands` |
| 5 | **⌘W closes the whole editor window**, not the tab | the editor registers nothing with `GlassCloseCommandRouter` |
| 6 | **The window forgets its size** — should persist, per editor window | scene storage / frame autosave |
| 7 | **Language belongs in the footer only**, and should be the best guess | it is in both the footer and the gear |
| 8 | **The light system theme is not honoured** — the chrome goes light and the text pane stays dark | `EditorTheme.glassDark`, hard-coded |

---

## 1. The whole tab is the target

The tab's `Button` wraps only its `Label`, so the capsule's padding is dead space. The button takes
the whole capsule, with the close control layered above it — one `contentShape`, one hit test.

## 2. The rule showing through

The strip sits in the detail column with `.regularMaterial` behind it, and the split view's own
divider is drawn behind that — a material composites what is behind it, so the line reads straight
through. Same family of mistake as the footer's: a bar with nothing solid under it. The strip gets a
surface that stops at its own bounds, and the divider is left to the columns where it belongs.

## 3. The gear opens Settings, and ⌘+ / ⌘− work

Two separate things went into one menu, and neither belongs there.

- **Settings.** Every capability contributes pages to the one settings surface
  (`GlassCapabilitySettingsPage`); the editor contributes none. It gets a page — line numbers, wrap,
  text size, and later the tree's ignore list — and the gear opens **Settings**, so there is one
  place for a preference and the toolbar button is a shortcut to it, not a second home.
- **Text size on the keyboard.** The terminal already owns this shape
  (`MacWorkspaceCommands`: Increase/Decrease Font Size on ⌘+ and ⌘−, with a hidden ⌘= alternate so
  the unshifted key works). The editor gets the same three items in its Text menu, aimed at the
  focused editor window through `\.glassEditorActions`, and Actual Size on ⌘0.

## 4. Opening a file, and opening a folder

**The panel comes first; a window appears only on a successful pick.** (Corrected by the user
mid-plan: ⇧⌘O is meant to be a file picker, and the only defect is the window.)

The command calls `openWindow` and *then* asks the focused window to present a `fileImporter`, so a
new editor window appears before the panel — and if the panel is cancelled that window stays,
empty. The ordering is backwards, and the `fileImporter` is why: it is a modifier on a view, so a
view has to exist before the panel can be shown.

So the panel stops being a view modifier for this path. `NSOpenPanel` runs from the command itself,
which needs no window at all:

- **Open…** (⇧⌘O) — files, `canChooseDirectories` off. On a successful pick, open the document in
  the focused editor window if there is one, otherwise open a window for it. On cancel **nothing
  happens at all** — no window, no trace.
- **Open Project…** (⌥⌘O) — the same, with directories on and files off.

The in-window importers stay for the empty state's buttons, which already have a window by
definition.

## 5. ⌘W closes the tab

The shell's router is in place and the terminal and database register with it; the editor does not,
so ⌘W falls through to closing the window. The editor registers the same way: close the selected
document, and when there are none, let the window close. An unsaved document still asks first —
that path already exists (`requestClose`).

## 6. The window remembers its size

Per editor window, not one size for all of them: `NSWindow.setFrameAutosaveName` through a window
reader, keyed by the scene's id, in the same shape `glassLibraryColumnAutosave` already uses for the
sidebar width. A second editor window opened deliberately at a different size should stay that way.

## 7. Language in the footer, best-guess first

The footer already has the picker; the gear grew a second one, which is how two controls for one
fact start disagreeing. The gear's goes.

"Best guess" today means the file extension, which is right whenever there is one. It should also
read the **content** when there is not: a `#!` line names its interpreter, `<?xml` is XML, a leading
`{` or `[` that parses is JSON. An explicit choice by the user always wins and sticks to that
document.

## 8. The light theme

`EditorTheme` has had `glassLight` beside `glassDark` all along; `GlassEditorModel` defaults to the
dark one and nothing ever changes it, so in Light mode the window's chrome turns light and the text
sits in a dark rectangle in the middle of it (reported with a screenshot, 2026-09-17).

The model takes the theme it is given, which is right — the engine should not reach for the
environment. So the **view** follows `colorScheme` and sets the model's theme when it changes, for
every open document, the same way the appearance settings already apply to all of them. That covers
a system change while the app is running, not only at launch.

The database and SFTP editors construct their own models and have the same gap; they are fixed with
the same one-line follow, and the SQL editor's surface condition stays as it is.

---

## Order

5 and 1 first (both small, both in the way), then 4, then 3, then 7, then 6 and 2 — 2 wants the
running app and a screenshot to settle, which is how the footer's twin was settled.

## Built — 0.4.145, 1,571 tests, exit 0

All eight, in one pass. Worth keeping from each:

- **4** — the `fileImporter` was the reason the window came first: it is a view modifier, so a view
  had to exist before a panel could be shown. `NSOpenPanel` from the command needs no window, so
  cancel now leaves nothing behind.
- **6** — `WindowGroup` restores a frame through state restoration, which does not run for a scene
  marked `.defaultLaunchBehavior(.suppressed)`. The editor deliberately never opens at launch, so it
  was always built fresh at the default size. One autosave name, so a second window opens at the
  last one's size and AppKit cascades it; per-window memory would need value-based scenes.
- **7** — content sniffing only where it is conclusive: a shebang, an XML prolog, a brace that
  actually **parses** as JSON. `ambiguousContentStaysPlaintext` is the test that matters, because a
  wrong grammar colours worse than none does.
- **8** — `glassLight` existed all along; nothing ever selected it. The view follows `colorScheme`,
  so a system switch while the app runs reaches every open document.
- **2** — the rule was `NSRulerView`'s own trailing hairline. The ruler is as tall as the scroll
  view, and in a window with a full-size content view that reaches up behind the title bar, which is
  why it ran from the top of the window through the toolbar and the tab strip. The gutter paints its
  own background and the numbers, and no rule.
- The Mac window's modifiers had to be collected into one `ViewModifier`: the type checker gave up
  on the chain and said so as a timeout rather than an error anyone could read.

## Round three — 2026-09-17 (0.4.147)

Asked for from use, built in one pass:

- **Recents moved to File ▸ Open Recent**, with Clear Menu. The sidebar is a project's tree; what
  you were in lately is a File-menu fact on this platform.
- **The sidebar has a footer**: the project's own gear and its refresh, on a bar. The `…` menu on
  the section header is gone.
- **Two gears, two scopes.** The toolbar's opens the app's settings (line numbers, text size —
  true of every document); the sidebar's opens **this project's** (name, machine, folder).
- **No Close Project.** Closing the window closes the project — *"I'm done with this project"* —
  and open documents stay open, because a file in a tab is work and a folder is a view.
- **Opening a file with no project collapses the tree**, because a project column with no project
  in it is a stripe of empty space beside the text.
- **Title and subtitle, family-wide.** The terminal's shape — *"Terminal on oscar"* over
  `michael@192.0.2.10:22` — now in the editor (file name over `project — ~/path`) **and the
  database**, where a table was previously `database · table` glued onto one line, truncating the
  useful half first. It is the table's name over `connection · database` now.

**Two platform breaks from one change, both invisible to a Mac build** (rule 32):
`homeDirectoryForCurrentUser` does not exist on iOS or visionOS, and `navigationSubtitle` does not
exist on visionOS — a title bar there is an ornament, not a bar. Caught by building all three,
which is the only thing that catches them.

## Round four — 0.4.152

From a morning of use, each found by using the thing:

- **The desktop's configuration looked lost.** `catalogDidLoad()` defers the read to a `Task`, so
  for a moment after launch the in-memory list is empty while the catalog is not — and editing the
  service in that window reported the link as having nothing behind it, which is what a *lost*
  service looks like. The user deleted a working service because of it. `setupDraft(for:)` asks the
  catalog now, because the catalog is the record (D26). Three tests, including one that fails
  without the fix; and the desktop's existing tests could never have seen this, because they use an
  in-memory store that answers "loaded" from birth.
- **⌘W was inert in an empty editor.** The close router *consumes* Close whenever a window has a
  registration, enabled or not — deliberate, so a database's permanent Overview tab cannot be shut
  by accident. The editor registers as always-enabled and closes the window when there is no tab.
- **⌘O did nothing** because the database's Open SQL Document… already held it. Opening *a file* is
  the general act, so the editor owns ⌘O and the database's moved to ⇧⌘O.
  `commandOHasASingleOwner` joins the ⌘T, ⌘N and ⌘W guards — **four** separate collisions now, each
  one found by a person pressing a key and nothing happening.
- **The tab strip ate half the window.** A horizontal `ScrollView` accepts whatever height it is
  offered; with two tabs and the sidebar closed it took the space and centred the tabs in it.
  `fixedSize(vertical:)` asks it for its content height instead.
- **⌘O spawned a second window** beside the empty one ⇧⌘E had just made. Every editor window is a
  view of the same workspace, so the chosen file belongs in the window already open — the windows
  count themselves on the runtime now, because SwiftUI will not say what scenes exist.
- Title, sidebar and footers: the project's name full size until a file is open, no project row over
  the file list, the sidebar's footer in the sidebar's glass rather than an opaque bar, and one
  `footerHeight` for both bars.

## One workspace per window — 0.4.153

*"⇧⌘E opened the same window with the same docs? I'd expect a new empty editor."* Right, and it was
a design error rather than a slip: the editor kept **one workspace for the whole app**, so every
window was a view of the same documents. That is a panel pretending to be a window. A Mac editor is
the other way round — a window *is* a set of tabs.

- **`GlassEditorPreferences`** (new): text size, line numbers, wrapping, recents. True of the
  editor, shared by every window. Text set larger in one window is larger in both; a file opened
  anywhere is recent everywhere.
- **`GlassEditorWorkspace`**: documents, projects, selection, find state. **One per window**, keyed
  by the window's id, with the scene now value-based — `WindowGroup(id:for: UUID.self)`.
- ⇧⌘E makes a new id, so it is an empty editor. ⌘O goes to the window **in front**, tracked through
  `controlActiveState`, and only creates a window when there is none.
- Tests: `aSecondWindowStartsEmpty`, `preferencesAreSharedBetweenWindows`,
  `openingAFileUsesTheWindowInFront`.

**Four platform breaks in one refactor, none visible to the Mac build being iterated against:**
`controlActiveState` is macOS-only; the view body tipped the type checker over on iOS and visionOS
first, because those platforms carry a settings sheet the Mac does not; the extracted dialogs
modifier declared its own `@State isShowingSettings`, which would have made the iOS gear button a
control that does nothing; and that sheet still used the old `workspace:` label. Three of the four
were in code that **only exists off macOS** — rule 32, four times in one sitting.

## Validation

The suite for the model halves — language sniffing and the close target have honest unit tests.
Everything else is read out of the running app: the menu bar for ⌘+ / ⌘− and the Open items, a
screenshot for the rule, and the window's frame across a relaunch for 6.
