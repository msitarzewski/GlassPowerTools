# The gutter, the devices, and Projects as a library panel — 2026-09-17 (afternoon)

**Owner:** coordinating agent. **State:** PLAN → BUILD.
**Authorization:** the user asked for a plan across the outstanding queue and for the work to
start. Local implementation, tests and documentation are in scope; committing is not.

The queue is the one recorded in the [2026-09-17 RESUME HERE block](../../activeContext.md). This
note says *how*, and every item below names the thing it reuses rather than what it invents.

---

## 1. The gutter — stop using `NSRulerView`, mirror the UIKit backend

**The defect.** The line-number strip reaches into the title bar. `NSRulerView` spans its scroll
view and is not inset by the scroll view's content insets, so nothing done at the scroll view's
level moves it. Three patches at three links in that chain missed. Rule: change the shape.

**What already exists, and is the answer.** `GlassLineNumberGutterIOS` is a plain `UIView` laid
out **beside** the text view inside a container, and `GlassEditorUIKitEngine.installViews()` is
eleven lines of constraints. Its own doc comment says why: drawing beside the text makes the offset
arithmetic explicit and one-directional. The line-number mapping is already shared —
`GutterLineNumbers` is used verbatim by both platforms — so this is not a rewrite of the gutter. It
is **the same structure on the other backend**, and it removes a type rather than adding one.

| Edit | File |
|---|---|
| `NSRulerView` → `NSView`, flipped, `draw(_:)` mirroring the UIKit one | `GlassEditorUI/AppKit/GlassLineNumberGutter.swift` |
| `containerView: NSView` holding gutter + scroll view; `installViews()` mirroring UIKit's; clip-view bounds observation to repaint on scroll | `GlassEditorUI/AppKit/GlassEditorAppKitEngine.swift` |
| `makeNSView` returns the container | `GlassEditorUI/Shared/GlassEditorView.swift` |
| The SQL editor returns the container too — it gets the same fix for free | `GlassDatabase/GlassEditorAdapters.swift` |

**Why this can only ever occupy the text's bounds:** the gutter is a sibling pinned to the scroll
view's own top and bottom, inside a container SwiftUI places. There is no ruler spanning anything,
no `contentInsets` compensation to keep in step, and no second scroll view. The single remaining
piece of per-platform arithmetic is the vertical offset, which on macOS is
`clip.bounds.origin.y - textContainerOrigin.y - contentInsets.top` against UIKit's
`contentOffset.y - textContainerInset.top`.

**Validation.** A test that bites on the old shape: the gutter is a subview of the container, the
scroll view has no ruler, and after layout the gutter's frame matches the scroll view's vertically.
Then look at it — geometry is not provable from this shell (the unified log stopped answering for
this process and the sandbox container is closed).

## 2. The phone and the headset

The phone (`00008150`) is paired and available at 0.4.143. The Vision Pro (`00008112`) reports
**unavailable** to `devicectl` and has to be awake and unlocked before it can take a build. Build
once, install to whatever is reachable, read the version back off the device (rule 16).

## 3. Stage C — Projects as a library panel, persisted and synced

**Contributed exactly like SSH Keys.** `GlassKeyManagerPanel.libraryPanels()` returns a
`GlassLibraryPanel`; `GlassCapability.libraryPanels()` is the protocol seam and already has a
default. The editor capability contributes one the same way. That is also, for free, the editor's
**only entry point on iOS and visionOS**, which today has none.

**Persisted through the sync service that already exists.** `GlassShellSettingsSync` is generic
over its payload by design — its own header says a capability supplies a `GlassSettingsSyncPayload`
and its store key, so every capability syncs through one shell service. A project is
`(hostID, path, displayName, openedAt)`; the list of them is small metadata and fits that payload
exactly. **No new store, no new transport, no CloudKit code.** The host catalog is not the place:
it stores `HostProfile`s, and a project is not a host.

`GlassEditorProject` is already `Codable`, already normalizes its path, and already carries the
`hostID` that makes a project travel between devices. `converged(with:)` merges by project id,
newest `openedAt` winning.

Closing a window stops losing its projects as a consequence, not as a separate fix.

## 4. Stage D — the editor's remote half

**The tree half is built** (below). Reading and writing a remote *file* is what remains.

## 5. Carried

The D26 two-device acceptance run, and test hygiene (1,519 keychain items, preference sprawl).

---

## Progress

**Planned and built, 2026-09-17 afternoon.** 1,592 tests, exit status 0. macOS, iOS and visionOS
all build. Installed **0.4.160** on the Mac and the iPhone, version read back off each (rule 16).

### 1. The gutter — done, and wants looking at

`GlassLineNumberGutter` is an `NSView` beside the scroll view inside
`GlassEditorAppKitEngine.containerView`, laid out by eleven lines of constraints that mirror
`GlassEditorUIKitEngine.installViews()`. Both representables return the container:
`GlassEditorView` and the database's `SQLEditorRepresentable`, so the SQL editor gets the same
gutter without a second implementation.

The drawing itself moved **up** into `GutterLineNumbers.draw(in:offsetY:layoutManager:model:)` and
both platforms now call it. Right alignment, the trailing gap and top alignment with the first
visual line of a wrapped logical line were written twice and are written once; the only
per-platform value left is `offsetY`.

- macOS: `clip.bounds.origin.y - textContainerOrigin.y - contentInsets.top`
- UIKit: `contentOffset.y - textContainerInset.top`

Turning line numbers off collapses the width to zero and hides the view rather than tearing it
down, so the transition is one constant and the gutter keeps its scroll observation (the clip
view's `boundsDidChangeNotification`, registered target/selector so it deregisters itself).

**The test bites, checked rather than assumed.** `gutterIsBesideTheText` asserts the gutter is a
subview of the container, that the scroll view has no ruler, and that after layout the gutter's
frame matches the scroll view's band exactly. Pinning its top 28 points above the scroll view
fails it on `gutter.frame.maxY == engine.scrollView.frame.maxY`; that edit was reverted.

**What no test here can say:** whether it *looks* right. The app's own geometry cannot be measured
from this shell. Open a file with line numbers on and see whether the strip stops at the tabs.

### 2. The devices

| Platform | Version | |
|---|---|---|
| macOS | **0.4.160** | installed, read back off the bundle |
| iPhone `00008150` | **0.4.160** | installed, read back off the device |
| Vision Pro `00008112` | 0.4.123 | paired but **locked** — `needs to be unlocked to enable development services`. Unlock it and the same build installs |

### 3. Stage C — Projects in the library

Built, and it compiles on all three platforms; **not yet used against a real second device.**

- `GlassEditorProjectsPayload` — records with `modifiedAt`/`deletedAt`, `validate()` and
  `converged(with:)`, conforming to `GlassSettingsSyncPayload`. The terminal's theme payload is the
  shape it follows, tombstones included.
- `GlassEditorProjectLibrary` — the list that outlives a window. `UserDefaults` locally (the shape
  `GlassEditorPreferences` uses for recents), iCloud through `GlassSettingsSyncService` when a store
  is attached. **No new store and no new transport.**
- `GlassEditorProjectsPanel` — contributed through `GlassLibraryPanel`, registered with the new
  `GlassCapabilityRegistry.registerLibraryPanel`, which is the exact seam
  `registerSettingsPage` already was and for the same reason. **This is the editor's first entry
  point on iOS and visionOS.**
- `GlassEditorRuntime.openProject` now records into the library, so opening a folder is what puts
  it there and the two cannot disagree.

Reach is answered by the composition root, because the catalog is what knows whether a machine is
this one. Pinned host keys are **not** consulted yet: D8's local record is what "this machine"
means today, and the key comparison becomes load-bearing when stage D can open a folder over SSH.
A project on another machine says so in words rather than being a disabled button with no reason.

**13 new tests** over the payload and the library: tombstones survive a stale device, a later edit
beats a tombstone, merges are order-independent, the same folder twice is one project, the same
path on two machines is two, unreadable storage yields an empty list rather than a crash.

### Still open

- The Vision Pro, on an unlock.
- Stage D, the remote reader — `GlassEditorDirectoryReader` is the seam, and the panel already
  names what it cannot do without it.
- The D26 two-device run; test hygiene.

---

## Stage D, the tree half — built 2026-09-17

**1,600 tests, exit status 0.** All three platforms build. macOS and iPhone on **0.4.161**.

### The reader had to become async first

`GlassEditorDirectoryReader.contents(ofDirectory:)` was synchronous, and an SFTP listing is not.
The protocol is `async` now, `GlassEditorProjectNode.loadChildrenIfNeeded` with it, and a second
form — `beginLoadingChildrenIfNeeded` — exists for the callers that cannot await, which are the
SwiftUI `Binding` setters a disclosure triangle is made of. A read already in flight is not started
twice: over a network that would be a second round trip for an answer already on its way.

The tree therefore **fills in after** the call that asked for it. That is a real behavioural change
and the existing tests were updated to await it rather than have their assertions weakened. A row
now shows a spinner while its folder is being read and a warning with the reason if it could not be.

### One listing, two transports

Everything after the listing — the machinery folders nobody wants to see, *a child's path is its
parent's path plus its name*, folders-first ordering — was written twice and is now
`GlassEditorProject.nodes(in:from:)`, called by both readers. The path rule matters more remotely
than locally: an SFTP server is as free to answer in its own spelling as `contentsOfDirectory` is.

### The borrow

`GlassHostDirectoryLister` on `GlassCapability`, the exact shape of `GlassHostPortForward` and for
the same reason: the editor must not learn to make an SSH connection, resolve a credential or judge
a host key. `GlassTerminalCapability.openDirectoryLister(host:)` mirrors `openPortForward` line for
line, D14 trust prompt included, and holds the session open for as long as the project is.
**Closing the project closes the connection** — a local reader's `close()` does nothing, so there is
no branch at the call site.

### Making one

*Open in Editor* on a folder in the Files browser, offered only when something can actually open
one. The terminal knows the server the browser is connected through; `GlassShellModel
.host(owningEndpoint:)` turns that into the machine's id, which is what makes it the **same project
on another device**. The closure crosses through the environment, the mirror of
`GlassEditorRuntime.remoteReader` going the other way.

**Nothing here has met a real server.** The tests drive a fake one that records what it was asked
for; the borrow itself is the proven port-forward path with `openSFTP()` in place of `forward()`.
The Ubuntu VM at `192.0.2.6` is where this gets its first real listing.

---

## Stage D, the file half — one path for both machines

**1,607 tests, exit status 0.** All three platforms build. macOS and iPhone on **0.4.162**.

A remote project's files open, edit and save. The point of the change is that **they do it through
the same methods a local file does** — there is no remote document path to keep in step with the
local one, because there is one path.

### The seam

`GlassEditorDirectoryReader` became **`GlassEditorFileAccess`**: list a folder, read a file, write
one back, say what a file looks like now, close. One object per project, chosen when the project
opens, and the only thing in the editor that knows which machine a project is on.

A name that said "directory reader" while it also read and wrote files would have been a lie, so
the type was renamed rather than extended in place. `GlassEditorLocalFileAccess` is the file
system; `GlassEditorRemoteFileAccess` is five injected closures, which is what keeps SFTP in the
capability that owns the connection and keeps a remote project testable with no server.

### What that made possible, and what it exposed

`GlassEditorDocument.open(path:through:machine:)` and `save(through:)` are the only forms. Where
the bytes came from is an argument; the encoding replay, the line endings, the language sniff, the
dirty flag and the baseline for the next save are the same code for both.

**Local files got conflict detection as a consequence, not as a feature.** `RemoteDocumentSession`
and `ConflictDetector` were written for the SFTP editor, but they hold a size, a modification time
and a digest, which mean the same thing on a disk. A checkout, a build or another editor changes a
local file underneath this one exactly as a colleague changes a remote one, and the editor now
stops and asks either way. That was not the goal; it is what sharing the path turned out to mean,
and it is the half that was previously missing.

Both tiers are used the way the detector intends: the stat comparison on every save, and the digest
**only when the stat says something might have changed**. Without tier 2 the detector reports
`.indeterminate` for a dirty buffer rather than guessing — correct, and it would have put a
question in front of the user every time a build touched a file it had not changed.

### The atomic write, kept on both

Locally `AtomicSaver.writeAtomically` — temporary file, rename. Remotely the same promise the same
way: write a temporary beside the real file, `fsync` it, then `posix-rename@openssh.com` over the
destination. A server without that extension has to have the destination removed first, which is
the one moment the file does not exist; that is said in the code rather than papered over.

### Found while doing it

`deletingLastPathComponent().path` leaves a trailing separator, so a document's folder read as
`/srv/app/` and did not match the project root `/srv/app`. The same trailing-slash class that
opened duplicate projects, in a second place. Normalized.

### Still not met a real server

Seven new tests drive a fake machine that answers all four questions and records what it was asked.
The local half is tested against real files on disk, including a real one-second-apart rewrite. The
first real listing and the first real remote save are still owed, against `192.0.2.6`.

---

## The verified write, and Edit into the editor — proven on a real server

**1,617 tests, exit status 0**, plus **7 live tests against `192.0.2.6`**. All three platforms
build. macOS and iPhone on **0.4.164**.

### Why this was needed

Two remote save paths existed, and the newer one was worse. The Files browser's **Edit** went to
`SFTPRemoteEditorView` and saved through a commit that stages the bytes, verifies what landed,
carries the original permissions across, and reports an ambiguous commit as ambiguous. The editor's
remote save — written the day before this — was a temporary file and a rename. It looked
equivalent. It was not:

- it verified nothing about what landed
- it could not notice the file changing *during* the upload
- a dropped connection mid-commit was indistinguishable from a failure
- **it dropped the file's mode**, so saving a shell script removed its executable bit

### The contract, not just the implementation

```swift
func write(_ data: Data, to path: String, expecting: RemoteStat?) async throws -> RemoteStat?
```

*Write this, only if the file is still what I last saw, and tell me exactly what you committed.*

The expectation closes the window between the conflict check and the bytes arriving — a check that
has already finished cannot speak for the moment of the write, and only the machine can. The
returned stat is the new baseline, so the next check compares against **what was written** rather
than a hopeful re-`stat` afterwards.

**What is expected is what the check observed, not what was opened.** That distinction was found by
two failing tests and is the same idea as the old path's `authorizedObservation`: a build touching
a file moves its timestamp, the digest proves nothing changed, the user is not asked — and
expecting the *opened* stat would then have refused the save anyway. Answering "save anyway"
authorises replacing the version the question was about; a third version arriving while the dialog
is open is refused rather than silently overwritten.

`GlassTerminalDirectoryLister.write` now calls `SFTPBrowserView.uploadRemoteEditorBytes` — the same
commit, not a second one that resembles it. Reachable without moving any of that careful code:
`SFTPClient` wraps the `SFTPSession` the lister already holds, so it was a constructor and three
`private` → `internal`.

### Edit opens the editor

Every entry point — toolbar, row button, context menu, detail pane — goes through
`beginRemoteEdit`, so one place decides. A file on a machine opens as a **tab** in the real editor,
with the project tree, the gutter and one conflict vocabulary, and saves back over the same
connection. `GlassEditorWorkspace` remembers the access per document, because a file opened this
way has no project to look it up from and falling through to the local disk would write it to the
wrong machine.

`SFTPRemoteEditorView` is still there as the answer to "what if nothing can take the file". It goes
once the end-to-end flow has been clicked once by a person; the live tests prove the transport
below it, not the route through the UI.

### Proven against `192.0.2.6`

`Tests/GlassTerminalTests/LiveRemoteEditingTests.swift`, gated on `GPT_SSH_TEST_HOST` /
`GPT_SSH_TEST_USER` / `GPT_SSH_TEST_KEY_PATH`, printing **NOT RUN** rather than passing quietly
when unconfigured:

| Claim | Evidence |
|---|---|
| A real listing tells folders from files | `mkdir Sources`, `README.md`, both classified correctly |
| A real file reads back whole | 200 KB base64 file, byte-identical — past the 32 KiB read window where a loop that stops at the first short answer truncates |
| The server answers the fields the check needs | size **and** modification time present; a missing file is `nil`, not a zero |
| A save lands and describes itself | content on the machine, and a committed size of 6 |
| **Mode survives a save** | `chmod 755`, saved, still `755`. This is the one that proves the verified commit is really being used — the old temp-and-rename fails it |
| A changed file is not overwritten | rewritten a second later by another writer; the write is refused and the other writer's content is intact |
| Nothing is left behind | the directory holds one file after a save, no staging litter |

**The tests bite**: pointed at `192.0.2.199` they fail on a 30-second connect timeout rather than
passing.

**The first run left a directory on the VM** — `defer` cannot await, and a `Task` inside one is
cleanup that races the end of the test and loses. Replaced with a `withLiveServer` wrapper that
tears down on both paths; the VM is verified clean afterwards.

### Still not proven

The **route through the UI**: Edit → a tab in the editor → save. The transport underneath it is
proven; the click is not.

---

## Edit opened nothing after the window closed — 0.4.165

Reported: repeated Edit did not open a new window. Right-click ▸ Edit worked, but after closing the
windows, right-click ▸ Edit on a different file failed to open an editor.

### The runtime did not know whether a window existed

`noteWindowOpened()` and `noteWindowClosed()` were **declared and never called**, and
`hasOpenWindow` was never read — dead bookkeeping. So "is a window up?" was inferred from the
`workspaces` dictionary, which is populated as a *side effect of SwiftUI rendering*: a workspace
exists the first time a window **asks** for one, and goes on existing afterwards. A workspace with
no window in front of it therefore read as a window, the runtime decided one was already up, and
the file was opened into something nobody was looking at.

`liveWindows` is the set of windows that have actually appeared, maintained by the same lifecycle
that already ran (`noteFrontmost` on appear, `forget` on disappear). `frontmostWorkspace` and
`hasOpenWindow` both answer from it.

### And a file that joined an existing window was never brought forward

`open` answered **nil** for "an existing window took it", which left the caller nothing to show.
The file became a tab in a window behind the Files browser, and the click looked like it had done
nothing — the first half of the report. It now always names the window, and showing one that
already exists focuses it rather than making a second.

Two tests, both reproducing the reported sequence: a third file after the window closes gets a
window of its own, and a workspace made without a window is not mistaken for one.

## No sidebar without a project

Asked: could the sidebar be hidden entirely unless there is a file tree to examine?

The sidebar is the project's file tree and holds nothing else — open documents are tabs. With no
project, the toggle offered to reveal a column that could only ever be blank, so **the toggle goes
with the column**: `.toolbar(removing: .sidebarToggle)` while `projects.isEmpty`. The column also
now follows the projects in both directions — it arrives with the first and leaves with the last,
where closing the only project used to leave the tree open and empty.

Nobody is stranded: Open Project… is File ▸ Open Project… (⌥⌘O) and a button on the empty document
view, neither of which lives in the sidebar.

**The alternative, not taken:** keep the toggle and give the empty sidebar a `ContentUnavailableView`
with an "Open a Project…" button, the way Xcode shows an empty navigator. Worth revisiting if the
disappearing toggle reads as broken rather than as tidy — it is one line either way.

---

## Desktop opened nothing on the iPhone — 0.4.166

Reported: a desktop did not open on the iPhone; nothing happened.

### The same defect a third time

`openWindow` does nothing on an iPhone, silently. There is one scene, so a capability that answers
a connect request by opening a window answers it by doing nothing at all — no window, no error, no
log line. `GlassDesktopBootstrap.drain()` had exactly that as its only path for `.connect`.

Three surfaces had it: the editor's Projects panel, the editor's window-after-close, and now the
desktop's session. **The database did not** — it has routed iPhone work inside the primary scene
through `DatabaseIOSRouter` since before the merge, on `userInterfaceIdiom == .phone`. It was the
one capability that knew, and the knowledge was not written anywhere the others would find it.

It is written down now: `GlassWindowPresentation.canOpenWindows`, in the shell, asked by all three.

### Both signals, deliberately

    UIApplication.shared.supportsMultipleScenes && UIDevice.current.userInterfaceIdiom != .phone

`supportsMultipleScenes` is the precise question and also catches an iPad with multiwindow switched
off. The idiom check is the blunt one and is the half **already proven in production** by the
database. Requiring both means an iPhone is excluded by either — the direction to be wrong in,
because presenting in place where a window was possible is cosmetic, and opening a window where
none is possible is the user tapping and nothing happening.

The desktop session now covers the library on a phone, with a Done button, which is what a window
is there anyway. iPad and Mac keep `openWindow` untouched.

### Verified on the iPhone 17 Pro simulator

| | |
|---|---|
| Builds for the simulator | ✓ |
| Installs, launches | ✓ |
| `LaunchSmokeUITests` | ✓ passed — the startup path is not regressed by the shared check |
| The full package suite, three platforms | ✓ |

**Not verified: the session actually appearing.** A desktop needs a saved configuration to open at
all, and `--ui-testing-seed-hosts` creates services without one — so there is no way for a UI test
to reach this capability's only surface. An attempt to add `--ui-testing-seed-desktops` was backed
out: the store exposes configurations, not the services that lack them, so seeding one would have
meant new production API for a test. **The desktop has no UI test at all, and cannot have one until
that seed exists.** Worth building; it is the same gap that let this ship.

The fastest check available is the phone itself, which has a configured desktop on it.

### Confirmed working, then shaped to match glassDT — 0.4.167

**0.4.166 worked on the real iPhone** (the user confirmed the build installed on their own
phone worked). The diagnosis was right and the cover was the fix.

Then, told that glassDT had worked perfectly and to solve it the same way, the right move was to read what glassDT actually
did rather than keep a guess that happened to work. `LibraryScene` in
`../glassDT/App/glassDTApp.swift:107-143` is the same `fullScreenCover` + `NavigationStack`, with
two differences worth taking:

1. **It presents the resolved `DesktopConnection`, not an id.** The merged version handed the cover
   an `EndpointID` and let `DesktopSessionHost` look the desktop up a second time — and *that
   second lookup is the one that failed earlier today*: `catalogDidLoad()` defers the read, so a
   view asking in the first moments after launch finds nothing and reports the configuration as
   missing. The capability has already resolved it before enqueuing, so the answer is carried
   instead of re-derived. A resolution that fails now says so rather than presenting nothing.
2. **A chevron, not "Done".** glassDT's comment says why: *"so the machine's name is the only
   wording in the bar"*. Kept, comment included.

The lesson is the ordinary one and it was skipped: `../glassDT` is a historical record to **read**,
and it had already answered this. Two of the three defects in this class — the desktop's and the
editor's — were solved there years before they were reintroduced here.
