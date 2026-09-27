# The iOS round, day two — 2026-09-19

**Owner:** coordinating agent. **State:** DOCS.
**Authorization:** the user reported each item from the running app and asked for it fixed;
builds and installs were requested explicitly. Versions **0.4.177 → 0.4.184**, every one installed
on the Mac and the iPhone and read back off the installed bundle.

The pattern of the day, again: **the phone is where the defects are, and the user is the only one
driving it.** Nine reports, seven of them defects, one of them mine.

---

## What was built

| | |
|---|---|
| **The provisional tab** | One click shows a file, the next click takes the same tab, and committing keeps it — a double click, a deliberate open, an edit or a save. Italic in the strip, "previewing" to VoiceOver. Seven tests |
| **HTML** | The sixteenth grammar, pinned at `tree-sitter/tree-sitter-html@73a3947`. `<script>`/`<style>` bodies read as embedded code; `<!DOCTYPE html>` is sniffed before the XML prolog |
| **The keyboard hides and returns** | `GlassEditorModel.requestKeyboard`, a bar above the keyboard, and a toggle in the status bar that follows the *system's* notifications |
| **The database on a phone** | A compact layout at last — see below |
| **One grid everywhere** | The card-per-row list is gone; `dataGrid` scrolls in both directions and is what a table is |
| **Pinned chrome occludes** | A material under the header and the row-number gutter, so data stops scrolling through them |
| **Back goes to the machine** | `GlassShellModel.hostToShow`: leaving a database returns to *that host*, not to the top of the list |

## The database had the editor's disease

`DatabaseWorkspaceView` is a `NavigationSplitView`, and on a compact width SwiftUI collapses one
into a single stack showing its **sidebar**. So on a phone the workspace *was* the schema browser:
Browse Data, a table and the SQL Editor button each selected a destination in a column that was
never on screen — as the user reported, Browse Data in the database on iOS swallowed the tap too.

It is the same defect the editor had on 2026-09-17, and it survived two days because **nobody had
driven the database on a phone** (rule 46, and it was item 2 of the carried list in the navigation
plan). Everything the SQL surface needs — `QueryEditorView`, `TableDetailView`,
`DatabaseDetailView`, `ConnectionOverviewView` — was already cross-platform. Only the route was
missing.

Three consequences, all reported within the hour:

1. **No back button.** The control existed at `ToolbarItemPlacement.navigation`, which iOS drops
   in a collapsed split view. `.topBarLeading` now.
2. **The footer was three things in one strip** — the schema browser's floating bottom search, a
   `.bottomBar` toolbar group, and the list rows behind both. On a compact width the SQL editor
   moves to the top bar and the rest into the overflow menu; the bottom belongs to the search.
3. **The databases could no longer be tapped** — my own regression, below.

## The regression I caused

My compact stack used a **typed** path: `NavigationStack(path:)` over `[DatabaseCompactRoute]`.
The schema browser has had its own compact navigation since glassdb — `compactDatabaseList`
pushes a `CompactSchemaDatabaseDestination` for a database's tables — and **a typed path accepts
only its own type**, so every one of those links silently did nothing.

`NavigationPath` takes both. The detail's depth is tracked separately, because a `NavigationPath`
will not say what is in it.

**The lesson is rule 48:** before wrapping a view in a navigation container, find out whether it
already navigates.

## What the tests caught, and what they could not

- **`testAProjectThatRefusesToOpenDoesNotBlockTheNextOne` passes on iOS 27.2**, and was seen
  **red** against the old `hasSelection: Bool`. That is the phone-side verification the panel fix
  was owed.
- Getting there, both iPhone tests failed by matching the panel row's *image*: an identifier on an
  `HStack` reaches its children, and which child XCUITest picks changes between OS versions. One
  `.accessibilityElement(children: .combine)` fixed the row and its VoiceOver reading at once
  (**rule 49**).
- **No test reaches any database surface.** The fixtures are gated on `GPT_DB_TEST_*` and a
  simulator runner does not receive `TEST_RUNNER_*` on this toolchain. That gap is now
  load-bearing: it is why a regression of mine reached the user rather than a test.

## The toolchain moved under us

**Xcode 27.2 (27B5019j)** arrived overnight. Every build failed with *"cannot execute tool
'metal'"* (SwiftTerm has a `.metal` shader) until `xcodebuild -downloadComponent MetalToolchain`
— 839 MB. The simulator was gone entirely until the user ran `sudo xcodebuild -runFirstLaunch`;
`/Library/Developer/PrivateFrameworks/CoreSimulator.framework` did not exist. Yesterday's
"macOS UI automation cannot start" was very probably the same update, mid-flight.

## Still true at the end of the day

- **The session switcher is not built.** Sections D1–D3 of the navigation plan, and the user's
  own question about the terminal — whether an SSH session is still connected after leaving it — is
  the argument for it.
  It is: leaving only clears `router.terminalWorkgroupID`, and the way back is the Workgroups
  panel, which nobody would think to open.
- **The terminal and the desktop have still never been driven on a phone.** The database's three
  defects are what that costs.
- A **seeded database or desktop configuration** is what would let either have a UI test at all.
