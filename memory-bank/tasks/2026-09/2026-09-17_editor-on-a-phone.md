# The editor on a phone — 2026-09-17 (late)

**Owner:** coordinating agent. **State:** BUILD.
**Reported:** the editor did not work at all on the phone — the file title showed, but no content.

## Two defects, and neither was in the editor's text view

### 1. A phone is not a narrow Mac

`GlassEditorWorkspaceView` is a `NavigationSplitView` and was used unconditionally. On a **compact
width SwiftUI collapses one of those into a single stack showing its sidebar first** — so an editor
opened on a file arrived as the sidebar, which for a file with no project is an empty list, under a
navigation bar carrying the file's name. The title was there. The document was one push away,
behind a column with nothing in it.

`GlassConnectionLibrary` has branched on `horizontalSizeClass` since before the merge
(`if horizontalSizeClass == .compact { compactNavigation } else { regularNavigation }`). The editor
never did — it was written on a Mac, for a Mac, and compiled everywhere.

**Fixed:** `compactLayout` shows the document in a `NavigationStack`, with the project's files
behind a **Files** toolbar button presenting the tree as a sheet. A column on a 390-point screen is
the whole screen, which is exactly what the collapse turned it into. The sheet dismisses itself
when a file is chosen, because choosing one is why it was opened.

### 2. No contributed panel's detail was reachable on a phone

Found while driving the simulator rather than by reading: selecting a project in the Projects panel
did nothing at all. The library pushes `.detail` onto its compact path when **its own** selection
changes, and a panel owns its selection privately — so a panel's detail had no way to be pushed.

**Every panel had it.** SSH Keys has shipped like this: listable, never openable on an iPhone. And
it is most of "the editor doesn't work on the phone", because Open lives in the project's detail.

**Fixed:** `GlassLibraryPanel.hasSelection` — an optional closure the panel supplies, read inside
the library's body so the panel's `@Observable` model registers the dependency, with the compact
stack pushing `.detail` when it turns true. A panel that supplies nothing keeps the old behaviour
rather than pushing an empty detail.

## How it was found: the simulator, driven

Not by reading. The app was installed on an iPhone 17 Pro simulator with a project planted in its
container and seeded into its `UserDefaults`, then walked by an XCUITest that photographs each
step — `UITests/EditorOnIPhoneUITests.swift`.

That is what turned "the split view probably collapses" into a screenshot of a Projects panel whose
rows did nothing, which was not the defect being looked for.

**The seeding recipe**, because it is the thing that made this possible and there is no other way
in without the system file picker:

```sh
CONTAINER=$(xcrun simctl get_app_container <device> com.glasspowertools data)
mkdir -p "$CONTAINER/Documents/DemoProject/Sources"      # a project to open
# then write a GlassEditorProjectsPayload as JSON into
# $CONTAINER/Library/Preferences/com.glasspowertools.plist
# under "com.glasspowertools.editor.projects", dates in milliseconds
```

Screenshots come out of the result bundle:

```sh
xcrun xcresulttool export attachments --path <bundle>.xcresult --output-path <dir>
```

### 3. Errors were shown in a column the phone was not displaying

`open()` on a project whose folder had gone set `panel.message` — and the alert carrying it was
attached to the **results** column, which is not in the hierarchy once the detail has been pushed
on a compact stack. A correct refusal, correctly worded, arrived as a tap that did nothing.

**Fixed:** two messages. One for the list, one for the selected project, each shown in the column
that raised it. Confirmed by screenshot: the alert now reads *"There is no folder at … any more."*

### 4. Opening a file from the tree was macOS-only

```swift
.onTapGesture { workspace.sidebarSelection = .node(node.id) }
#if os(macOS)
.simultaneousGesture(TapGesture(count: 2).onEnded { open(node) })
#endif
```

A double click is a mouse idiom and there is nothing to double-tap on a phone, so the tree's only
gesture was selection — **a file could be chosen and never opened, on the one platform where the
tree is the only way to open anything.** The file list did exactly what it was told, and looked
like an editor that does nothing. This is the heart of the report.

**Fixed:** one tap opens a file on a touch screen; the Mac keeps single-select and double-open. A
folder is left to its disclosure triangle on both, because a tap that selects *and* toggles fights
itself.

## Verified

`README.md` open on an iPhone 17 Pro simulator, with content, line numbers, Markdown highlighting
and a footer reading `Line 1, Column 1 · Markdown · LF`. Every step photographed
(`UITests/EditorOnIPhoneUITests.swift`), and each of the four defects confirmed by a screenshot
before and after.

## What this cost, and the traps

Four of the evening's measurements were the harness rather than the app, and each produced a
confident wrong conclusion:

1. **A project seeded from the host died with its container.** The simulator gives the data
   container a new identifier when the app is reinstalled, so an absolute path recorded before an
   install points at a directory that is gone. The app refused to open it — correctly — and the
   refusal was invisible, which is how this one hid.
2. **`test-without-building` ran a stale test bundle**, because the second command did not carry
   `-derivedDataPath`. It printed markers from source that no longer existed.
3. **Result bundles stopped finalising**, so `xcresulttool export attachments` failed and the
   screenshots could not be read at all.
4. **`UserDefaults` survives a reinstall while the container does not**, so a seeding guard of
   "only when the list is empty" seeded nothing and left a dead record in place.

The answer to all four is the same and is now in the app: **`--ui-testing-seed-project`** makes the
project *inside the app's own container*, replacing whatever was there, so nothing is recorded on
the host and nothing can go stale. Screenshots are written to the runner's `NSTemporaryDirectory()`
as well as attached, because an attachment that cannot be opened is not evidence.

The lesson is the ordinary one: the seeding argument should have been built when the testability
gap was first named, hours earlier, instead of being worked around three times.
