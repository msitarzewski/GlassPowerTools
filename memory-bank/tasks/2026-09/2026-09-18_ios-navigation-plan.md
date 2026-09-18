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

- **The current folder's name, large.** `sensor`, not `/home/ann/projects/sensor`.
- **The full path beneath it**, across the header's whole width, in a smaller secondary weight,
  **without the current folder repeated** — `/home/ann/projects`.
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

**What the user asked for:** an app-switcher, activated when a session is open — *"imagine swiping
through the open connections like the iOS app switcher view"*.

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
