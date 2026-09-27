# Finding your way around on iOS — planned 2026-09-18

**Owner:** coordinating agent. **State:** PLAN.
**Authorization:** the user asked for a plan covering the iOS file surfaces, the SFTP header, a
session switcher, and everything still outstanding. Building starts on their word.

The editor now opens a project and renders a document on a phone. What it cannot do is let anyone
**find their way around** — and neither can the rest of the app. Four of the five pieces below are
navigation; the fifth is that there is no way to move between open sessions at all.

---

## A. Opening a folder should land on the files, not on an empty editor

**Reported with a screenshot:** opening the `sensor` project shows the editor's empty state —
*"Choose a file from the project to start editing"* — with the file list behind a toolbar toggle.
The user has just chosen a folder; the next thing they want is what is in it.

**Change.** On a compact width, opening a *project* pushes the **directory list** as the screen,
and choosing a file pushes the editor. Opening a *file* (Edit in the Files browser, a recent) still
goes straight to the editor, because there the file is what was chosen.

Opening a project from the library's Projects panel keeps showing the project's detail first —
that part is right and stays.

**Where.** `GlassEditorWorkspaceView.compactLayout` currently makes the document the root and hangs
the tree off a `Files` button. Invert it: a `NavigationStack` whose root is the tree when the
window was opened with a project and no document, and whose pushed view is the editor. The
existing `GlassEditorTreeRows` is the list; nothing about the tree itself changes.

## B. The file and folder views stop being modals

The tree is a `.sheet` and the editor on a phone is a `.fullScreenCover`. A sheet over a cover is
two dismissals to think about, and neither reads as a place you *are*.

**Change.** One navigation stack, pushes rather than presentations, mirroring `SFTPBrowserView` —
which already uses the whole interface and is the surface people will compare it to. The back
button and tapping a folder are the only navigation; no toggle, no modal.

This also removes the `Files` toolbar button added yesterday: with the tree as a real screen, a
control to reveal it is a control for something that is no longer hidden.

## C. A header that says where you are — in both browsers

`SFTPBrowserView` sets `.navigationTitle(currentPath)`, so the title is the whole path and reads as
a string of text rather than a place. The editor's tree has no header of its own at all.

**One header, used by both:**

- **The current folder's name, large.** `sensor`, not `~/projects/sensor`.
- **The full path beneath it**, across the header's whole width, in a smaller secondary weight,
  **without the current folder repeated** — `~/projects`.
- **Truncated from the front** when it does not fit (`…/michael/projects`), because the end of a
  path is the part that locates you and the beginning is the part you can infer.

**Where.** A shared view in `GlassConnectionUI` — both consumers are outside `GlassTerminal`, and
the family rule is that a surface two capabilities share belongs in the kit. `SFTPBrowserView`
drops `.navigationTitle(currentPath)` for it; the editor's tree adopts it at the same time.

## D. Switching between open sessions — the big one

**There is no way to do it.** Connected to a terminal and a VNC desktop, wanting a database on a
third host, a phone user has no route between them: every session is presented full-screen in the
primary scene, and the only way back to the library is to close what they are looking at. On a Mac
these are windows and the problem does not exist; on a phone it is the whole of the product's
navigation model, missing.

**What the user asked for:** an app-switcher, activated when a session is open — swiping through the
open connections the way the iOS app switcher works.

### D1. One list of what is open

No capability can answer this alone, and the shell must not learn the four session models. The seam
is the one `GlassLibraryPanel` and `registerSettingsPage` already established:

```swift
protocol GlassCapability {
    /// Sessions this capability has open, newest first. Default: none.
    func openSessions() -> [GlassOpenSession]
}

struct GlassOpenSession: Identifiable {
    let id: String
    let kind: HostServiceKind
    let title: String          // the machine
    let subtitle: String?      // the service, and its state
    let symbolName: String
    let activate: @MainActor () -> Void
    let close: @MainActor () -> Void
    /// A still of the session, when the capability can cheaply make one. Optional by design:
    /// a card with a name on it is useful, and a card waiting for a screenshot is not.
    let snapshot: (@MainActor () -> Image?)?
}
```

Each capability already has the state: `SessionManager.sessions`, the database's workspaces, the
desktop's connections, the editor's `workspaces`. Each already knows how to bring one forward,
because each has a router that does it on iPhone today.

### D2. Reaching the switcher from inside a session

A session covers the screen, so the control has to be part of the session's own chrome. One
implementation, contributed by the shell, adopted by all four: a **Sessions** control beside each
session's existing back control, showing the count. On visionOS and macOS it is not offered —
windows already do this.

### D3. The switcher itself, in two stages

**Stage 1 — a list that works.** A full-screen presentation with one row per open session, grouped
by machine, showing kind, name and state, with a swipe to close. Plain, correct, and it makes the
product navigable on a phone for the first time.

**Stage 2 — the carousel.** Cards in a horizontal `ScrollView` with `.scrollTargetBehavior(.viewAligned)`,
one per session, the card carrying the snapshot when there is one and the machine's name when there
is not. Swipe up to close, tap to activate — the iOS app switcher's vocabulary, which is what was
asked for and what the gesture already means to everyone.

Stage 1 first, because it is the half that removes the dead end; the carousel is the half that
makes it pleasant.

### D4. What a snapshot costs

The desktop has frames already. The terminal can render its buffer. The editor can show the first
lines of the front document. The database is a grid and probably shows its query. **All of it is
optional**: the protocol returns `nil` and the card falls back to a name and an icon, so the
switcher ships before any of them are written.

---

## E. Carried, and not to be lost

| | |
|---|---|
| **The Mac is on 0.4.170** | 0.4.171 is built; the app was running. One copy when it is quit |
| **The Vision Pro is on 0.4.123** | Locked every time it has been tried. Nothing from the editor's four rounds, Projects, or stage D has ever been seen in the headset |
| **Only the editor has been driven on a phone** | The terminal, database and desktop have the same shape and nobody has watched them. Rule 46 |
| **The desktop has no UI test** and cannot have one | It needs a seed for a desktop *configuration*, the way `--ui-testing-seed-project` gave the editor one |
| **`replaceAll` is a whole-kind reconcile** | Freshness is every capability's duty rather than a property of the call. A per-record write, or a reconcile that refuses to delete records it has never seen, makes the class impossible |
| **`configurations(ofKind:)` skips undecodable records silently** | Correct for one bad record; it also means a shape mismatch between builds looks exactly like the configuration loss of 2026-09-17, with nothing logged |
| **The remote editing route through the UI is unproven** | Edit → a tab → save has never been run against a real server; the transport under it has |
| **`SFTPRemoteEditorView` is still there** | The second editor, kept as the fallback for "nothing can take the file". It goes once the new route has been used in anger |
| **The gutter has never been confirmed by eye** | Its frame is asserted by a test; whether the strip stops at the tabs has not been looked at since the change |
| **D26's two-device acceptance run** | Still never done, and it would have caught the configuration loss |
| **Test hygiene** | 1,519 keychain items and the preference sprawl, from suites using the real Mac as scratch space |

---

## Order

1. **A, B and C together.** They are one change to one set of views, and doing them separately
   would mean building the header twice.
2. **D1 and D2** — the session list and the control that reaches it. This is the dead end.
3. **D3 stage 2** — the carousel.
4. **The desktop configuration seed**, then drive the terminal, database and desktop on a phone
   the way the editor was driven. Expect defects; four came out of the first surface watched.
5. The carried items, worst first: `replaceAll`, then the Vision Pro, then D26.

---

# Built — A, B and C, 2026-09-18

**State:** BUILD complete for sections A, B and C; D is untouched. **1,632 tests / exit status 0**
(1,623 before, plus nine for the header), Release builds for macOS, iOS and visionOS, and the
iPhone walkthrough driven twice with a screenshot at every step.

## What changed

| File | Change |
|---|---|
| `Sources/GlassConnectionUI/GlassPathHeader.swift` | **New.** `GlassPathLocation` splits a path into the folder and what leads to it; `GlassPathHeader` draws them; `glassPathHeader(_:)` attaches the header. `GlassPathLocation.abbreviatingHome` is the one `~` rule |
| `Sources/GlassTerminal/SFTPBrowserView.swift` | `.navigationTitle(currentPath)` → `.glassPathHeader(currentPath)` |
| `Sources/GlassEditor/GlassEditorWorkspaceView.swift` | The compact layout is a `NavigationStack` over `GlassEditorCompactRoute`; `GlassEditorFolderList` is the phone's list; `GlassEditorFileRow` is the row both lists share; `projectFooter` extracted so both show it; `toolbar` became `toolbarContent(includingDismissal:)` |
| `UITests/EditorOnIPhoneUITests.swift` | Walks the new route: lands on the files, no `Files` toggle, header present, a folder pushes, back returns, a file opens the editor |
| `UITests/GlassTerminalUITests.swift` | `testFilesBrowserHeaderNamesTheFolder` — the same header over a real listing on `192.0.2.6` |

## The two defects the first run photographed

1. **The name was said twice** — the navigation bar's inline title sat half an inch above a header
   showing the same word. The header keeps `.navigationTitle` on **macOS only**, where a window
   needs one and the title bar is a different surface.
2. **`~F/Documents`.** The editor's private `abbreviated(_:)` dropped `home.count - 1` characters,
   keeping home's last character instead of the separator after it. It is now
   `GlassPathLocation.abbreviatingHome`, shared with the Files browser and covered by two tests —
   one of which also refuses `/Users/anna` as "inside" `/Users/ann`.

## What is proven, and what is not

| Claim | Evidence |
|---|---|
| Opening a project lands on its files | `EditorOnIPhoneUITests`, iPhone 17 Pro simulator, screenshot `04-project-files` |
| The `Files` toggle is gone | The same test asserts its absence |
| A folder pushes; back returns | Screenshot `05-folder-pushed`, then `README.md` found again |
| A file opens the editor with its text | Screenshot `06-file-open` |
| The header names the folder, path beneath, front-truncated | Nine unit tests, and photographed on the editor's folder screens |
| **The header in the Files browser** | **NOT RUN.** `testFilesBrowserHeaderNamesTheFolder` exists and is gated on `GPT_SSH_TEST_*`. macOS UI automation on this machine currently fails to start for *every* test — "Timed out while enabling automation mode", reproduced with `LaunchSmokeUITests` — and the simulator runner does not receive `TEST_RUNNER_GPT_SSH_TEST_*`, so it skips |
| Anything on a Mac screen | Not looked at. The Mac is still on 0.4.170 with the app running |

## Next

D1 and D2 — the session list and the Sessions control — are the dead end and are next. Everything
in section E still stands, plus: the Files browser's header wants one look on a real listing, and
macOS UI automation wants a reason.

---

# D1 and D2 — the seam surveyed, 2026-09-20

**State PLAN, nothing built yet.** Before writing `openSessions()`, the question the plan left
open was answered by reading the code: *where does each capability's session actually live on a
phone, and who can bring it forward?* The four answers are not the same, and one of them changes
what the switcher can honestly offer.

| Capability | Where the session lives on iPhone | Survives leaving? | What `activate` can call |
|---|---|---|---|
| Terminal | `IOSAppRouter.terminalWorkgroupID` swaps the library root (`GlassTerminalCapability.swift:467`) | **Yes** — `showConnections()` only clears the id; the session stays live in `SessionManager` | needs one new `Request` case |
| Database | `DatabaseIOSRouter.workspaceRequest` swaps the root (`GlassDatabaseScenes.swift:136`) | **Yes** — `showConnections()` clears the request, not the session | **`Request.openQueryEditor(sessionID:)` already does exactly this** |
| Editor | `runtime.requestWindow(id:)` → `fullScreenCover` (`GlassEditorScenes.swift:272`) | **Yes** — workspaces are held by id in `GlassEditorRuntime` | already there |
| Desktop | `@State activeDesktop` → `fullScreenCover` (`GlassDesktopScenes.swift:118`) | **No** | nothing to activate |

## The desktop has no session to switch to, and that is the honest answer

`DesktopSessionView.swift:244` is `.onDisappear { alerts = …; session.close() }`. On a phone,
leaving a desktop **ends** it — there is no backgrounded RDP or VNC session for a switcher to
return to. So `GlassDesktopCapability` takes the protocol's default `[]` rather than inventing a
row, and the switcher never offers a machine it cannot actually go back to.

Whether a desktop session *should* survive being left is a separate decision with a real cost
behind it (a live RDP stream on cellular), and it is not taken here. Recorded so the empty list
reads as a finding rather than an omission.

## Two design consequences, both toward less machinery

1. **No router moves.** `IOSAppRouter` and `DatabaseIOSRouter` are `@State` inside their
   bootstraps, so a capability object cannot reach them — which first looked like a reason to
   move both onto their runtimes. It is not: every capability already has a request queue its
   bootstrap drains, and that is the path every other cross-capability call in this app takes.
   The database needs **no new case at all**. Moving the routers would have been a refactor of
   two working files to reach something already reachable.
2. **The list is built inside `body`, never cached.** `openSessions()` reads each runtime's
   observed state (`SessionManager.sessions`, the editor's `workspaces`), so an `@Observable`
   wrapper holding a snapshot would reproduce the stale sidebar count of 2026-09-18 exactly —
   a stored answer to a question whose inputs keep changing. The switcher calls the registry
   during body evaluation so SwiftUI records the dependency.

Also settled: the editor contributes through a `registerSessionProvider` escape hatch, the same
one `registerSettingsPage` and `registerLibraryPanel` already exist for, because a file is not a
service and the editor is not a `GlassCapability`.

---

# Built — D1 and D2, 2026-09-21

**State BUILD complete for D1, D2 and D3 stage 1.** The carousel (D3 stage 2) is not built and
does not need to be: the seam beneath it is what the list and the cards share.

## What changed

| File | Change |
|---|---|
| `Sources/GlassShell/GlassOpenSession.swift` | **New.** `GlassOpenSession` (id, title, subtitle, symbol, `activate`, `close`); `GlassCapability.openSessions()`'s default; the registry aggregate and `openSessions(excluding:)`; `GlassSessionsToolbarModifier` / `.glassSessionsToolbar(…)`; `GlassSessionSwitcher`, the list |
| `Sources/GlassShell/GlassCapability.swift` | `openSessions()` as a **protocol requirement** (see below); `registerSessionProvider(id:_:)` and `standaloneSessions()` beside the panel and page hooks |
| `Sources/GlassTerminal/GlassTerminalCapability.swift` | `openSessions()` — one row per workgroup with a live session, newest first; `sessionID(workgroupID:)`; `Request.showWorkgroup` |
| `Sources/GlassTerminal/TerminalConnectFlow.swift` | Drains `.showWorkgroup` — `iOSRouter.showTerminal` on a phone, `openWindow` elsewhere |
| `Sources/GlassTerminal/VisionTerminalWorkgroupView.swift` | The **Sessions** control on both phone layouts |
| `Sources/GlassDatabase/GlassDatabaseCapability.swift` | `openSessions()` — one row per live session, ordered by name then session id; `subtitle(engine:state:)` |
| `Sources/GlassDatabase/DatabaseWorkspaceView.swift` | The control on the split and both compact screens |
| `Sources/GlassEditor/GlassEditorScenes.swift` | `closesWorkspaceWithItsWindow`, `closeWorkspace`, `openSessions()`, `sessionTitle`/`sessionSubtitle` |
| `Sources/GlassEditor/GlassEditorWorkspaceView.swift` | The control on the split layout and both compact screens, with the cover's dismissal |
| `Sources/GlassEditor/GlassEditorProjectLibrary.swift` | `--ui-testing-seed-second-project`, so a test can have two sessions |
| `Sources/GlassDesktop/GlassDesktopScenes.swift` | The control inside the desktop's cover |
| `App/GlassPowerToolsApp.swift` | Registers the editor's provider; puts the registry in the environment |

## The defect this uncovered, which was the bigger half

**Leaving the editor on a phone threw the documents away.** `GlassEditorWorkspaceView.onDisappear`
calls `forget`, and `forget` did `workspaces[id] = nil`. On a Mac that is right — closing a window
closes the editor. On a phone `onDisappear` fires every time the full-screen cover is dismissed,
which is what the **Connections** button does, so tapping it discarded the workspace: open
documents gone, unsaved edits gone, nothing said, and reopening built a fresh empty one because
`frontmostWindowID` was nil by then.

Two verbs now. `forget` gives up frontmost and keeps the workspace where there are no windows;
`closeWorkspace` always discards and is what the switcher's swipe calls. The policy is the
settable `closesWorkspaceWithItsWindow` rather than a call to `GlassWindowPresentation` inside the
method — the suite's own machine always answers "Mac", so the phone's behaviour would never have
been tested. Rule 54.

## Two things the tests caught before a device did

1. **A protocol default in an extension is invisible through `any`** (rule 53). `openSessions()`
   started life only in `public extension GlassCapability`; the registry holds
   `[any GlassCapability]`, dispatched statically, and called the default for all of them. The
   terminal's and the database's implementations were correct and never ran. Now a requirement.
2. **A database session id is not its connection id.** `connect` mints a fresh `UUID()`; the
   first version keyed the rows on `connectionConfig.id`, which would have activated nothing and
   collapsed two sessions of one saved connection into one row.

## What is deliberately not offered

- **The desktop contributes no rows.** Its session ends in `onDisappear` and nothing survives to
  return to. It still *shows* the control, because being inside a desktop with no way to a
  terminal is the dead end; leaving by it ends the session exactly as the chevron already does.
- **A database workspace's tabs do not survive the round trip.** The *session* does — the
  connection stays open and the SQL drafts are on disk — but `DatabaseWorkspaceView`'s tab state
  is `@State` and the view is destroyed when the root swaps. Hoisting it onto the session manager
  is a bigger change than this one and is not made here.
- **No snapshots, so no cards.** D4's `snapshot` is not in the struct: nothing supplies one yet,
  and a field that is always nil is a promise with nothing behind it. It goes in with the carousel.

## What is proven, and what is not

| Claim | Evidence |
|---|---|
| The seam lists what every contributor has open, in kind order, standalones last | `GlassOpenSessionTests`, 7 tests. Two of them were **red** first: the aggregate returned nothing until `openSessions()` became a protocol requirement |
| A provider is asked again every time | Its own test — a stored list is the 2026-09-18 stale count again |
| The session you are in is never offered | `openSessions(excluding:)`, tested including the "id belongs to no session" case |
| Leaving an editor on a phone keeps its documents, its unsaved edits **and its project** | `GlassEditorSessionLifetimeTests`, 10 tests. Seen **red** against the old `forget`, and the project half seen red against `onDisappear { closeAllProjects() }` |
| A Mac still closes the editor with its window | Same suite, the other direction |
| **Two editors on an iPhone, and the way between them** | `EditorOnIPhoneUITests.testTheSessionSwitcherReachesTheOtherEditor` on an iPhone 17 Pro simulator: no control with one session open, the control with two, exactly one row in the switcher, and README.md back on screen after tapping it. Screenshots `10`–`13` |
| All three platforms build | `xcodebuild` Release for macOS, iOS and visionOS |
| The terminal's and the database's rows | **NOT RUN.** Both need a live connection, and no simulator test can make one (`TEST_RUNNER_*` never reaches a simulator runner). Their `openSessions()` is unit-tested only through the registry's stub |
| The whole package suite | **1,685 tests, exit status 0** — see the locked-screen note below |

## The locked screen, on 2026-09-21

For part of this session around 35 tests failed with `EPERM` and `GlassShellTests` crashed, and
the diagnosis written here first — a machine fault to confirm on a second Mac — was **wrong**.
**The screen was locked.** `FileProtectionType.complete` means "unreadable while the device is
locked", which is exactly what was observed, including from a twelve-line Foundation script.
Unlocking it and re-running gives **1,685 tests, exit status 0**.

Nine places in `Sources` write protected files (`SessionRecorder`'s index and casts, three in
`SFTPBrowserView`, `SQLDraftStore`). Nothing is wrong with any of them and no data-protection
entitlement is missing — the protection did its job. Recorded as rule 56 because the symptom
reads like a permissions bug or a broken toolchain and cost an afternoon.

| Claim | Evidence |
|---|---|
| The whole package suite | **1,685 tests, exit status 0**, screen unlocked |

---

# D3 stage 2 — the gallery already exists, 2026-09-21

The user pointed out that glas.sh already had a prototype of this in its terminal grid and gallery
view. It is not a prototype and it is not only in glas.sh — it came across in the merge and
ships today. **D3 stage 2 is a reuse job, not a design job.**

| What exists | Where | What it gives the switcher |
|---|---|---|
| `LayoutPreset.OpeningView` — `tabs, grid, carousel` | `Sources/GlassTerminal/Models.swift:1797` | The vocabulary, already persisted per workgroup (`openingView`, `gridCardWidth`) |
| `MacTerminalOverviewGrid` | `Sources/GlassTerminal/macOS/MacTerminalOverview.swift:149` | **Pure layout maths** — count + size + preferred width → columns and card width, fitting rows to the height. Already covered by `Tests/GlassTerminalTests/macOS/MacWorkspaceTests.swift` |
| `MacTerminalOverview` | same file, `:199` | Grid ⇄ carousel picker, `LazyVGrid`, carousel cards, scroll-to-selected, arrow-key navigation by row and column, a card-width slider |
| `MacTerminalActivitySelection` | same file, `:178` | "Only fresh output attracts attention", with a manual-browsing grace period — the rule a live gallery needs to avoid yanking selection around |
| `spatialOverview` / `overviewCard` | `Sources/GlassTerminal/VisionTerminalWorkgroupView.swift:414` | The visionOS grid and a real carousel: 3D rotation, scale by distance, only ±1 card rendered |
| `VisionTerminalPreview` → `terminalHostModel.previewImage(maxPixelWidth: 800)` | same file, `:61` | **D4's snapshot, already implemented.** The card is a live terminal image with the session's own frost material |

**Two things it is not, which is the whole gap.** Both are *within one workgroup's terminals* —
they switch between sessions of one capability — and **neither is built for a phone**:
`MacTerminalOverview` is macOS and `spatialOverview` is inside `#if os(visionOS)`.

So the work is: lift the card and the layout maths to the shell beside `GlassSessionSwitcher`,
let them show `GlassOpenSession` rather than `TerminalSession`, and add the `snapshot` the struct
deliberately left out in stage 1 — the terminal can supply one now, the desktop has frames, and
the editor and database fall back to a name and an icon as designed.

**Do not re-derive the grid maths.** `MacTerminalOverviewGrid` already solves "how many columns
fit, at what card width, so the rows fit the height", it is tested, and a second copy would be
the third place in this product that answers one question (rule 43).

---

# Built — D3 stage 2, the gallery, 2026-09-21

Built **on** the existing overview rather than beside it, which is the point of the inventory
above. What is new is small; what moved is the useful part.

| File | Change |
|---|---|
| `Sources/GlassShell/GlassSessionGallery.swift` | **New.** `GlassGalleryLayout` (the solver, **moved** from `MacTerminalOverviewGrid`), `GlassSessionCard`, `GlassSessionGallery` |
| `Sources/GlassTerminal/macOS/MacTerminalOverview.swift` | Its solver deleted; `typealias MacTerminalOverviewGrid = GlassGalleryLayout` so the Mac overview asks the one implementation |
| `Tests/GlassShellTests/GlassGalleryLayoutTests.swift` | **New**, but the two solver tests inside it **moved** out of `MacWorkspaceTests` (macOS-fenced) and now run on every platform, plus the card contract and the degenerate sizes |
| `Sources/GlassShell/GlassOpenSession.swift` | `snapshot` restored — it was left out of stage 1 on the false grounds that nothing could supply one; the switcher gained a Gallery ⇄ List picker, remembered |
| `Sources/GlassTerminal/GlassTerminalCapability.swift` | Supplies the snapshot: the workgroup's selected terminal, at 800px, the overview's own figure |
| `Sources/GlassTerminalEmulator/SwiftTermHostView.swift` | `previewImage` unfenced from `os(visionOS)` to `canImport(UIKit)` |

## Three things this turned up

1. **A terminal could not draw itself on a phone.** `previewImage` was fenced `#if os(visionOS)`
   although every call in it — `UIGraphicsImageRenderer`, `layer.render(in:)` — is ordinary
   UIKit. The fence was around the *feature that wanted it first* (the spatial overview), not the
   API. Rule 52, again, and it would have left the gallery with nothing to show on the device it
   was built for.
2. **The gallery crashed the app the first time it opened.** `GeometryReader` reports a
   degenerate size on its first pass inside a sheet, `cardWidth` collapsed to 1, and a
   `GridItem(.flexible(maximum: 1))` is below SwiftUI's own default minimum of 10 — `LazyVGrid`
   traps in `HVGrid.minorGeometry`. Read out of the crash report rather than guessed. Fixed in
   the solver (`minimumCardWidth`), so the Mac overview is covered by the same clamp, with four
   degenerate sizes as regression tests.
3. **Four card treatments now exist** and should become one. See the drift note in
   `systemPatterns.md`.

## What is proven

| Claim | Evidence |
|---|---|
| The gallery opens, shows one card per other session, and the list is still reachable | `EditorOnIPhoneUITests.testTheSessionSwitcherReachesTheOtherEditor`, iPhone 17 Pro simulator, screenshots `12-gallery` and `12b-list`; tapping through still arrives |
| The solver answers sanely for sizes a real screen gives it | `GlassGalleryLayoutTests`, including the four degenerate sizes that crashed it |
| A session with no picture of itself is still a session, and a snapshot is asked for rather than stored | `GlassSessionCardContractTests` |
| The Mac overview still lays out as it did | Its two tests, unchanged in content, now running on every platform |
| **The carousel** | **NOT BUILT.** `OpeningView` has three modes and this is two of them. The spatial carousel in `VisionTerminalWorkgroupView` is the model to follow when it is wanted |
| **A real terminal snapshot on a phone** | **NOT SEEN.** The gallery's picture path needs a live SSH session, which no simulator test can have. The fallback path is what the screenshots show |

---

# The Mac's overview joins the seam, and the title band stops leaking — 2026-09-21

Reported from the running app, standing in the Terminal Overview: the title settings appeared to be
lost again, and the Linux server's database connection was expected to show up in this carousel.

## The overview shows every open session

`MacTerminalOverview` drew `controller.tabs` — this window's terminals — and nothing else. The
plan had said windows are the switcher on a Mac, so the cross-capability seam reached only the
phone. The screenshot was the counter-argument, and the seam already existed, so:

| File | Change |
|---|---|
| `Sources/GlassTerminal/GlassTerminalCapability.swift` | `GlassTerminalRuntime.openSessions` — the registry's list, supplied by the composition root exactly as `openFolderAsProject` is, because a capability must not hold the shell |
| `App/GlassPowerToolsApp.swift` | Wires it to `model.registry.openSessions()` |
| `Sources/GlassTerminal/macOS/MacTerminalOverview.swift` | `MacOverviewItem` — a live tab of this window *or* a session open elsewhere — browsed as one row. `MacOverviewSessions.others` drops the workgroups this window already previews. Sessions draw as `GlassSessionCard`, the phone gallery's card, with the overview's selection ring and hover. `MacTerminalOverviewNavigation.moved` is generic over the id. Return, Space, arrows, the carousel counter and "This workgroup" scope all cover the whole row |
| `Tests/GlassTerminalTests/macOS/MacWorkspaceTests.swift` | Own tabs are not shown twice; arrow keys walk off the last tab onto the first card and stop at the ends |

## The title band

In overview mode the window swapped its title-band material to `.underWindowBackground` — the
material *designed* to show what is behind the window, blurred. With the database window behind
the terminal, its "MySQL on the Linux server" header floated through the terminal's own title. glas.sh did
the same swap, which is the "again". The overview now keeps the family's title band; the test that
asserted the swap was rewritten to assert its absence and seen **red** against the old code.
Rule 50, one level up: chrome that says where you are does not become see-through because a
mode changed.

## What is proven

| Claim | Evidence |
|---|---|
| Other sessions appear in the overview, own tabs once | `overviewShowsSessionsOpenElsewhereButNotItsOwnTabsTwice` |
| Arrow navigation crosses from tabs into session cards | `overviewNavigationCrossesFromTabsIntoSessionsElsewhere` |
| The title band keeps its material in overview | `transparencyAndBlurRemainIndependentAtEveryEndpoint`, rewritten, red against the swap |
| Package suite | **1,692 tests, exit status 0** |
| The overview with a real database row, by eye | **NOT YET SEEN.** 0.4.192 is installed on the Mac; the user is driving it |
