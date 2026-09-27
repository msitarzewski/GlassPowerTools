# Stage 5.2 — the editor stops looking like a different app

**Date** 2026-09-16 · **State** PLAN · **Owner** coordinating agent
**Authorization** the user's review of the shipped editor: *"I'd like to get the editor's project
file list to mirror the UI of the other lists we already have… I like the database the most, so
let's make that the template"*, plus five specific corrections and *"Projects should be treated the
same way as Workgroups."* Planning and building are authorized; committing is not, and is asked for
separately.

Related: [the remaining work](2026-09-14_remaining-work-plan.md) (*Stage 5 — what is left, in
order*), [D26 keys first class](2026-09-14_d26-keys-first-class.md) for the panel pattern,
[active context](../../activeContext.md).

---

## What is wrong, in the user's words

| # | Report | Where it lives |
|---|---|---|
| 1 | The project file list should mirror the family's lists — **the database's is the template** | `GlassEditorWorkspaceView.swift:214` vs `SchemaBrowserView.swift:336-412` |
| 2 | The header does not follow the connection/terminal/database pattern: **the `+` belongs left of the title**, and **search should be a field** | `GlassEditorWorkspaceView.swift:368` vs `GlassConnectionLibrary.swift:273-277`, `GlassLibraryResults.swift:101` |
| 3 | The `+` should **only add a new document** — File already owns Open and Open Project | `GlassEditorWorkspaceView.swift:369-378`, `GlassEditorScenes.swift` (`GlassEditorCommands`) |
| 4 | **Line numbers show through the footer** | `GlassEditorWorkspaceView.swift:266-336` |
| 5 | The **Open list should be tabs** — exactly the database SQL editor's tabs | `GlassEditorWorkspaceView.swift:168` vs `DatabaseWorkspaceView.swift:827-885` |
| 6 | A **gear** with text-editor settings — line numbers, force a language, and so on | nothing today; `GlassEditorConfiguration.swift:5-33` already has the switches |
| 7 | **Projects are Workgroups**: Projects ▸ list (machine/path) ▸ details ▸ Open, lower-left like Terminal/services — and it all syncs | `TerminalWorkgroupsView.swift:413-434`, `GlassTerminalCapability.swift:353-374` |

Everything above is one theme. The editor was built as its own window with its own vocabulary; the
rest of the product already agreed on one. **Nothing here needs inventing — every pattern asked for
exists in this repo and is running.** The work is to use it, and to extract it once where two
surfaces would otherwise carry two copies.

---

## A — Chrome (visible, cheap, first)

**A1. The toolbar, rebuilt on the library's pattern.** The library puts its own actions at
`placement: .navigation`, leading the content region past the divider — `+` to the *left* of the
title (`GlassConnectionLibrary.swift:273-277`, itself following glassdb's Add Connection). The
editor puts everything in `.primaryAction`, which is why it reads as a different app.

- `+` moves to `.navigation` and becomes a **plain button: New Document**. No menu.
- **Open…** and **Open Project…** leave the toolbar. They are already in File
  (`GlassEditorCommands`); **Open Project…** is added there with ⇧⌥⌘O, because today it exists only
  in the toolbar menu and the empty-state.
- The magnifier button goes. Search becomes a **field**: `.searchable(text:prompt:)` over the
  sidebar, filtering the project tree and the recents — the same call
  `GlassLibraryResults.swift:101` and `SchemaBrowserView.swift:114` make.
  **Stated assumption:** "search" here means *filter this list*, matching the two windows compared
  against. Find-in-document is a different thing and keeps the find bar, ⌥⌘F and the Text menu.
- **Save** stays where it is.

**A2. The footer, so nothing shows through it.** The status strip is a plain `HStack` in a `VStack`
with `glassActionBarSurface()`, which is deliberately *nothing* on every platform
(`GlassSpatialMetrics.swift:89-96` — `.bar` composited the desktop through the window and read as a
stripe of wallpaper). The family's answer for a bottom action bar is the workgroup detail's:
`safeAreaInset(edge: .bottom)` with `.background(.bar)` (`TerminalWorkgroupsView.swift:413-434`).
The editor adopts it, which fixes the bleed and matches the pattern in one move. **Verify by
screenshot on a document long enough to scroll**, not by reasoning — the strip is a compositing
result.

**A3. A gear, with what the engine already supports.** `GlassEditorConfiguration` carries
`showsLineNumbers`, `wrapsLines`, `fontName`, `fontSize` and the contrast floor. The gear sits
beside Save and offers: line numbers, wrap, font size, and **Language** for the selected document
(the status bar's language menu stays — it is a Mac convention and where the eye already goes).
Window-level settings persist in the editor's payload (C3) so they travel; the language override is
per document and per session, because a file's language is a fact about the file.

---

## B — The lists

**B1. The project tree becomes the database's tree.** `SchemaBrowserView.schemaTree`
(`:336-412`) is the shape to copy: `List(selection:)`, `DisclosureGroup` per container,
`Label(name, systemImage:)`, single click selects, double click opens, a context menu per row, and a
secondary trailing fact (row count there, file size here).

The editor's tree uses `OutlineGroup` and bare `Label`s with no selection, no context menu and no
double-click. It changes to the same construction.

**Extract the row, not the tree.** The trees are entangled with their own sessions and should stay
where they are; the *grammar* is what must not drift. A `glassTreeRow()` row modifier and a shared
row body go into `GlassConnectionUI`, and **both** the database and the editor adopt it in the same
change — otherwise the copy starts drifting the day after it is made.

**B2. The Open list becomes the database's tab strip.** `DatabaseWorkspaceView.workspaceTabBar`
(`:827-885`) is extracted to `GlassConnectionUI` as `GlassWorkspaceTabBar` — capsule tabs, a close
button on closable ones, horizontal scroll, `.regularMaterial` behind the strip, the same
accessibility labels — and used by the database workspace (unchanged behaviour, same look) and by
the editor for its open documents. The sidebar keeps **Projects** and **Recent**; the dirty dot
moves onto the tab, where a Mac user expects it.

---

## C — Projects become a library surface, exactly like Workgroups

This is the largest correction and it also closes an outstanding item: **the editor has no entry
point at all on iOS or visionOS.** A library panel is the entry point on every platform.

**C1. A Projects panel.** A new `GlassEditorCapability` conforming to `GlassCapability` returns one
`GlassLibraryPanel` (`GlassLibraryPanel.swift`, the mechanism Workgroups and SSH Keys already use):

- **results** — the list of projects. Each row: the project's name, its machine, its path, and the
  reach badge `GlassEditorProjectReach` already produces (*On this Mac* / *Over SSH · the Mac* /
  *the Mac — no terminal service*).
- **detail** — the project's facts in a grouped `Form`, with the workgroup detail's action bar:
  **Rename** lower-left, **Open in Editor** lower-right and prominent
  (`TerminalWorkgroupsView.swift:413-434`, copied in shape, not in code).
- **toolbar** — *Add Project…*: pick a machine from the catalog, then a folder. Local machine →
  the folder picker. Another machine → a path, browsable once D exists.

**C2. Projects persist and travel.** Today they live only in memory: `openProject` appends to an
array and nothing writes it down (`GlassEditorWorkspace.swift:178-203`). They need a store, and the
user asked for sync.

**Recommendation: the settings envelope, not the catalog.** `GlassSettingsSyncService` +
`GlassSettingsSyncPayload` (`GlassShellSettingsSync.swift`) is the shell's generic iCloud key-value
channel with a writer identity, a Lamport revision and a caller-supplied `converged(with:)`; the
terminal's whole portable settings payload rides it already. A project is a few hundred bytes of
`(id, hostID, path, displayName, openedAt)`. The catalog is for records with endpoints and
configuration behind them, and giving it a new record kind is CloudKit schema work for no gain.

- New `GlassEditorSettingsPayload`, store key `editor-settings-envelope-v1`.
- `converged` merges by id, newest `updatedAt` wins, and **closed projects leave a tombstone** —
  D19's lesson, learned the hard way: a merge without tombstones resurrects what you deleted, and a
  merge that throws on one tombstone stops the device publishing at all.
- The `hostID` is the catalog's, so a project names the same machine on every device for free. A
  project whose host is not in this device's catalog is listed and marked, never dropped.

**C3. The window follows the panel.** Opening a project from the panel opens the editor window with
that project's tree loaded — `openWindow(id: GlassEditorRuntime.windowID)` and a request on the
runtime, the same handoff `runtime.requestOpenWorkgroup(preset.id)` performs.

---

## D — The remote half (the outstanding item, now joined to this)

Unchanged in substance from the standing plan; restated here because C makes it visible. A project
on another machine will now be *listed* on every device, which makes it worse to leave unbrowsable.

**D1. A broker on the shell.** `GlassCapabilityHostAccess`: given a `HostID`, list a directory, read
a file's bytes, write a file's bytes. The terminal implements it over SFTP; the editor asks the
shell and never learns who served it (rule 6 — the editor must not import the terminal).

**D2. `GlassEditorDirectoryReader` becomes async.** It is synchronous today
(`GlassEditorProject.swift:128-131`) because a disk answers immediately; an SSH connection does not.
`loadChildrenIfNeeded` becomes a task with a loading state per node, and
`GlassEditorProjectTests.foldersAreReadOnlyWhenTheyAreExpanded` changes with it. **This ripple is
the real cost of D and the reason it is last.**

**D3. Open in Editor, from where the user is.** A context-menu item in the SFTP browser
(`SFTPBrowserView.swift:1119`, `:1284`) that opens the folder as a project on that host. Remote file
*editing* already exists — `SFTPRemoteEditorView.swift` — and is reused rather than re-implemented.

---

## Order, and why

1. **A** — the chrome. A day at most, every item visible, no model changes.
2. **B** — the lists. The extraction into `GlassConnectionUI` touches the database workspace, so it
   wants the suite and a look at both windows.
3. **C** — Projects as a panel, with persistence and sync. This is where the editor stops being a
   window nobody can find on a phone.
4. **D** — the remote half, with the async ripple.

A, B and C are each shippable on their own. D is not: half a remote reader is worse than none,
because the badge would promise something the tree cannot do.

---

## Validation

| Item | How it is proven |
|---|---|
| A1/A3 | Built, installed, and **read out of the running app's menu bar** (rule 34's lesson) |
| A2 | A screenshot of a scrolled document. Compositing is not provable by reading code |
| B1/B2 | The suite for the extraction; both windows looked at side by side |
| C1/C2 | Unit tests: merge with tombstones, a project whose host is absent, two devices writing at once. Then **two real devices** — the panel on the phone showing a project added on the Mac |
| D | A real folder on the Linux server, opened from the headset |

---

## What this does not change

The outstanding list stands and is not displaced: **Vision Pro at 0.4.123** (locked at every
attempt), the **D26 two-device acceptance run** (never done), and **test hygiene** — 1,519 keychain
items and the preference-file sprawl. After D: project-wide `rg` on the far machine, `git status
--porcelain=v2` in the tree, and server-side LSP, which is the differentiator and is two to three
weeks rather than an afternoon.

## Built 2026-09-16, ahead of A–D

Three defects reported while the plan was being written, all fixed before the staged work:

1. **⌘W closed nothing, anywhere.** Read out of the running app: File ▸ Close had **no key
   equivalent at all**, "Close Tab" held ⌘W and was disabled, "Close Active Tab" held ⇧⌘W. A
   declared shortcut does not add a candidate beside the standard Close — it takes the key off it.
   The shell owns one File ▸ Close item now (`GlassShellFileCommands`), never disabled, falling
   back to closing the window; the terminal workspace and the database workspace publish
   `\.glassCloseItem` to aim it. The database's AppKit interception
   (`MacDatabaseCommandWRouter`, ~200 lines that replaced the menu item's target and action) is
   deleted. `MenuBarPlacementTests.commandWHasASingleOwner` holds the line.
2. **"This Mac" drew clipped on load** — measured out of the running app at 24pt against a 51pt
   neighbour, with its Connect button sliced off at the separator. `load()` published
   `group(records)` *before* reading the device's own host, so the local row was inserted into a
   list that had already been laid out and kept the height it was first measured at. The library is
   published once, complete; and `GlassLibraryConnectionRow` has a height floor so no row is ever
   shorter than the control inside it.
3. **⌘W's fix took three attempts, and only the running app could tell them apart.** A contextual
   shell item like ⌘N's never reached the menu bar in either placement tried — in one it was
   dropped and Close kept the key, in the other Close lost the key to a disabled item. What works is
   intercepting the Close item itself: `GlassCloseCommandRouter` (glassdb's router, promoted to the
   shell and widened to find Close by `performClose:` rather than by the key it carries, and to put
   the key back if something stripped it). Verified live: ⌘W closes the editor window, and closes a
   terminal **tab** while leaving the window standing.
4. **The tree could not be selected**, which is why it had no keyboard. Rows are tagged and
   selectable, expansion moved to the model, and ↑↓ move, → ← open and close a folder, Return and
   ⌘↓ open. `OutlineGroup` owned its own expansion, so nothing outside the view could open a
   folder — the keyboard included. This is the first half of **B1** and the prerequisite for
   `currentFolder` below. Verified live: ↑↓ move the selection, Return opens a file and toggles a
   folder, ⌘↓ opens.

   **← and → open and close folders natively** — the user confirmed it from the keyboard. The list
   is an `NSOutlineView` underneath and it handles those keys itself, so the SwiftUI handlers
   written for them were redundant and are gone. (They looked broken under automation for a
   different reason: the synthetic click never selected a row, so there was nothing to expand. An
   accessibility press is not a mouse click, and neither is `click at` — a probe that cannot select
   a row cannot prove a key does nothing.)

5. **Open Project… is in the File menu** (⌥⌘O). It had been reachable only from the toolbar's menu
   and the empty state — which is also why nothing outside the app could open a project to check
   anything. Part of A1, brought forward because verification needed it.

## A and B, built 2026-09-16 (0.4.142)

**A1 — the header, on the library's pattern.** `+` at `.navigation`, left of the title, doing one
thing: New Document. Open… and Open Project… are File-menu acts (⇧⌘O, ⌥⌘O). The magnifier is gone
and search is a **field** — `.searchable(placement: .sidebar)`, the "Filter" field the connections
window shows; without that placement it collapses into a toolbar magnifying glass at this window
width, which is the button it was meant to replace. Find is still ⌥⌘F and the Text menu.

**A1 — a gear**: line numbers, wrap, text size and the selected document's language. Persisted in
the editor's defaults and applied to **every** document in the window, because a preference the
other tabs disagree with is a bug with a checkbox.

**A2 — the footer is a bar.** `safeAreaInset(edge: .bottom)` over `.background(.bar)`, the shape the
workgroup detail uses. The status line had been the last row of a `VStack` with no surface of its
own, which is what the gutter showed through.

**B1 — the rows read like the database's.** `rowSubtitleFont` is `.caption` on a Mac, which made a
file tree read like a footnote; the rows use the list's own font now, and span the full column
rather than the width of the filename.

**B2 — one tab strip, shared.** `GlassWorkspaceTabBar` in `GlassConnectionUI`, extracted from
`DatabaseWorkspaceView.workspaceTabBar`, now used by the database **and** by the editor's open
documents. The sidebar's "Open" section is gone; the strip replaces it. Extracted rather than copied
so the two cannot drift, which was the whole argument for doing it this way.

**A defect only the running app could show.** With three files open the editor kept rendering the
**first** one. `GlassEditorView` had no view identity, and the engine deliberately observes its model
rather than being pushed values through `updateNSView` — so handing the view a different model never
reached the text view already on screen. `.id(document.id)` per document. Every test passed
throughout, because the model was always right; this is rule 38 again, one layer lower.

**Still open, and it is the most-used language here: `.swift` shows "Plain Text".** There is no
tree-sitter grammar for Swift in the build — upstream ships no generated `parser.c` and generating
it produced 20.6 MB, which was refused. Options are to vendor it anyway, to write a lexer-based
highlighter the way `SQLHighlighter` already is, or to leave Swift uncoloured. **The user's call.**

## Swift, XML and SQL — 2026-09-17 (0.4.143)

The user reversed the 2026-09-16 refusal once the number was next to its neighbour: **Swift is
vendored with a generated 20 MB `parser.c`**, against a **41.6 MB** SQL grammar already in the tree.
`tree-sitter generate` from the pinned revision; `grammar.json` and `scanner.c` are upstream's.
**XML** came with a parser already generated, and brings `.plist`, `.entitlements`, `.xcscheme`,
`.storyboard`, `.xib` and `.svg` with it — the files a developer on this platform opens every day.

`CaptureMappingTests` earned its keep: six captures had no role. XML paints element names `@tag`,
which universally means *punctuation* — every element name in every document would have come out
bracket-coloured. Elements are keywords here, attributes are properties.

**SQL was already right, and there is evidence rather than an opinion.** Probed with a CTE, a join, a
window function and a predicate: `WITH`/`OVER`/`ORDER BY` keywords, `ROW_NUMBER`/`SUM` functions,
identifiers, strings, numbers, operators, comment — **379 of 379 UTF-16 units covered**. The
database's SQL editor drives the same engine with `language: .sql`. Asked the user what they are
seeing rather than changing colours on a guess.

**The suite, run unlocked: 1,568 tests, exit status 0.** It had first reported 104 failures against
a locked screen — every one of them a test that writes `.completeFileProtection` storage, failing as
EPERM. Rule 28 names the one-line `ioreg` check that settles that, and it was consulted only after
disk space and `TMPDIR` had been ruled out; reading the rule first would have cost a minute instead
of twenty.

## The folder the user is in — answered 2026-09-16

**We do not track one, and the tree cannot even be selected.** The sidebar's `List` binds
`selection: $workspace.selection`, typed `GlassEditorDocument.ID?`
(`GlassEditorWorkspace.swift:21`) — document ids and nothing else. Project rows carry no `.tag`,
and a file row is a `Button`, which swallows the click before selection sees it
(`GlassEditorWorkspaceView.swift:214-233`). So there is no selected folder, no current folder and
no way to express one. The `path` is on every node; only the selection is missing.

**B1 supplies it for free.** Adopting the database's tree means `List(selection:)` over tagged rows,
single click selects and double click opens — which is exactly the mechanism a current folder
needs. So:

- `GlassEditorWorkspace` gains `selectedNode` (a project node id) beside `selection`, and a derived
  **`currentFolder`**: the selected folder, or the *parent* of the selected file, or the root of the
  only open project, else nil. Picking a file and pressing `+` should make a sibling — that is what
  every file browser means by "here".
- It persists per project in the editor payload (C2), so reopening a project lands where you left.

**The `+` stays enabled, and says what it will do.** Rule 34 already settled this shape: ⌘N is one
contextual item whose *title* the focused window supplies through `\.glassNewItem`. So the item
reads **"New File in docs"** with a current folder and **"New Document"** without one, and the
toolbar `+` gets the same tooltip. Disabling it would take away the one thing an editor with no
project can still do — an untitled scratch buffer — and a disabled `+` in a window that plainly
could make a document is a dead end the user has to guess at. A control that renames itself is the
Apple answer; a control that greys out is the one that needs explaining.

*(Found while answering: a folder row calls `loadChildrenIfNeeded` from `onAppear`, so folders read
themselves as soon as they are drawn — one level ahead of being expanded. The model behaves as the
test says; the view asks early. Folded into B1.)*

## Open question, asked once

**The `+` when a project is open.** New Document makes an untitled buffer with no home. In a
project-shaped editor a user usually means *a new file in this folder*. The plan builds New Document
(what was asked for); if the intent was a file in the selected folder, that is a small change on top
and worth saying now rather than after.
