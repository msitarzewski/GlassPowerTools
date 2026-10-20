# 2026-10-18 — The iPhone Duo, every page, folded and unfolded

**Objective.** Land on the iPhone Duo on its first day (it ships 23 October; `tasks/2026-09/2026-09-20_iphone-duo.md`).
That means every page of the app, on the outer (folded) and inner (unfolded) displays, is checked and fixed.
**Authorization.** The owner, 2026-10-18: "let's not forget the iPhone Duo UX verification. Every app page in the
Duo. Front, and inside… We'd miss an opportunity not to land day 1 with Duo." For unfolding the simulator through
Device Hub: "Go for it".
**Owner.** The coordinating agent.

## How

- **Simulator:** "Duo probe", iOS 27.1, driven with Xcode 27.1. Xcode 27.2 beta's Device Hub does not drive a Duo
  properly (the owner). Unfolded with Device Hub's "Open" pose button.
- **Session windows** (terminal, database, desktop, editor, settings sheets; 36 surfaces): demo launches
  (`Tools/Screenshots/shoot.sh`, now with `SHOT_DISPLAY` to pick a display), captured per display.
- **The library and Settings:** `UITests/PhoneTourUITests.swift` (new). It walks every library section, a host's
  detail and editor, Add Host, and each Settings page, and photographs each. A page it cannot reach is recorded.
  It runs on any iOS simulator.
- **Comparison:** Apple's Settings on the folded Duo. iOS puts the time, Wi-Fi and the toolbar's buttons in a column
  at the right of the outer display. That column is the system's, not ours.

## Folded (outer display, 466 pt, compact)

36 session surfaces and 22 library and Settings pages were looked at. Most are right. Four problems:

1. **The editor's tab strip draws under iOS's status column.** The selected tab hides behind the clock. Cause: the
   shared `GlassWorkspaceTabBar` scroll view extends into the safe area along its axis. The database's two tabs
   happened to fit.
2. **A preview left beside the text stays beside after folding,** one word per line. `GlassEditorPreviewMode.next`
   already skips "beside" on a compact width, but a stored `.beside` is drawn as it is.
3. **Favorites and Recent say "No Connections — Add a saved host to begin."** with four saved hosts. Nothing is a
   favourite or recent yet. This is wording on every iPhone, not only the Duo.
4. **SSH Keys and Projects have no title** when pushed on a compact stack. Workgroups has one.

## Unfolded (inner display, 951 pt, regular, landscape)

The Duo was unfolded through Xcode 27.1's Device Hub, with "Open" clicked by AppleScript at the owner's word ("Go
for it"). 36 session surfaces, Add Host and every Settings page were looked at; the library's two columns came from
the demo surfaces. Most are right. New problems:

5. **The database's schema sidebar lies over the content.** "SELECT" shows as "ECT", and the grid's `#` and `id`
   columns are hidden. The same happens on an upright iPad.
6. **The Markdown preview's web view renders narrower than its pane.** The page is clipped part-way and the rest
   of the pane is black, folded and unfolded.
7. Item 1 (the tab strip under the status column) happens unfolded too.

In the tour, the library's sections are not reached when the sidebar column is hidden at 951 pt. XCUITest's screen
is the outer display, so elements on the inner one read as not hittable. Window captures come out turned a
quarter turn and are turned back on the host.

**Fixes:** a fork in its own worktree, 2026-10-18 (late), for items 1–6.

## Fixes

Made in a worktree and brought into the main tree on 2026-10-19 after review of the diff and the
before/after sheets; not yet committed. Built with Xcode 27.1 for the iOS simulator, the Mac and visionOS.

### The cause behind items 1 and 6

Measured, not inferred. A view whose edge lies on the safe area's edge inherits the inset beyond it:
- A horizontal **scroll view** scrolls into that inset.
- A **web view** lays its page out inside it.

On the Duo, iOS keeps a column at the right of each display for the time and the toolbar. The editor's
preview, beside that column, reported `innerWidth` **179** in a pane measured at 262 points (tinted
frames).
- **Ignoring the safe area:** the page grew to 347 and ran under the column.
- **Padding back to the pane's edge:** 179 again.
- **One point short of the edge:** **262**.

### Item 1: the tab strip under the status column

`GlassConnectionUI/GlassWorkspaceTabBar.swift`.
- The strip is padded one point horizontally, so its scroll view inherits no inset. Tabs stop at the
  column.
- A clip alone stopped the drawing, but scrolling to the selected tab still left it under the clock.
- The selected tab is scrolled into view once the strip is laid out (`.task(id: selection)`, after a
  yield; asked at once there was nothing to scroll to), and whenever it changes.
- Evidence, folded and unfolded: `duofix/before-after-1-tabs.jpg`. Before, the
  selected tab is under the clock; after, the whole tab is in view and ends before the column.

### Item 2: "beside" without room

`GlassEditorPreviewMode.shown(roomBeside:)` turns `.beside` into `.previewOnly` without room. The drawing and
the toolbar toggle both use it. The stored choice is kept, so it comes back when the room does.
- Test: `GlassEditorPreviewTests` "Beside without room is shown alone; the button steps from what is shown".
- With the rule returning `self`: **failed, 2 issues**. With the fix: **passed** (9 tests in the suite).

### Item 6 in the list above: the preview narrower than its pane

`GlassEditorPreviewView.swift`. The web view sits in a `GeometryReader` and is padded one point from any
safe-area edge it would touch.
- Evidence: `duo-unf-preview-tint.png` (before: red text pane, blue preview pane; the page 179 wide in a
  262 pane), `duo-unf-preview-H-small.png` (after: `innerWidth` 262, the page across the pane), and
  `before-after-3-preview.jpg` (the folded and unfolded passes, before and after).
- The width readout used to measure it was temporary and removed.

### Item 3: Favorites and Recent empty states

`GlassConnectionKit/GlassLibraryEmptyState.swift` (new, pure). `GlassLibraryResults` takes it, and
`GlassConnectionLibrary` passes `.of(scope, libraryIsEmpty:)`. Only an empty library asks for a first host:

| Scope | Title | Line |
|---|---|---|
| Favorites | No Favorites | "Choose Add Favorite on a host to keep it here." |
| Recent | Nothing Recent | "Hosts you connect to appear here." |
| A collection | No Hosts in This Collection | "Edit a host and add it under Also known as & Collections." |

- Test: `GlassLibraryEmptyStateTests`.
- With the old behaviour (every scope "No Connections"): **failed, 10 issues**. With the fix: **passed**.

### Item 4: SSH Keys and Projects without a title

`GlassConnectionLibrary.panelResults` gives a panel's list the panel's own title on iOS, in both the compact
stack and the two-column layout. A panel's own title, nearer, still wins: Workgroups sets the same one.

### Item 5: the database workspace under its sidebar

The cause was not the split view's style or the sidebar's width.
- Giving the sidebar the Mac's width range on iOS made it 340 points; the detail still began at about 250.
- The database and server overviews never overlapped; only a table's surface did.

The table's **full pager** is one long row that cannot shrink: counts, timing, Calculate Total…, page
buttons, Per page. In a column narrower than it, the split view slid the whole detail under the sidebar to
make room.
- Fix: `TableDetailView` offers the full pager or the phone's compact one through `ViewThatFits`.
- Evidence: `before-after-6-database.jpg`, and:
  - unfolded Duo `duo-unf-db-A-crop.png` (before) and `duo-unf-db-C-small.png` (after);
  - iPad Air 13-inch, iOS 26.5: `ipad265-db-before-after.jpg`;
  - the iOS 27.0 iPad had no overlap before (`ipad-db-A-crop.png`).

### Also

`App/GlassDemoMode.swift`: the `preview-only` demo surface, which shows the README's preview alone. It was
used to compare against "beside".

## Next

Commit at the owner's word; a TestFlight build with these fixes. Duo App Store
screenshots: the outer display is 1398×2034 and the inner 2007×2853. Apple requires them from April 2027 for apps
built with the iOS 27.1 SDK, and they can be supplied now.

### Rerun after the fixes

On the Duo, from the worktree's build:
- **Unfolded:** 36 surfaces and the tour (Add Host and every Settings page).
- **Folded:** 36 surfaces and the tour (all 22 pages, none missed).

The affected pictures are right, and nothing else changed. Pictures are in `duofix/` in the working-files folder, never in the repository
(`folded/`, `unfolded/`, `tour-folded/`, `tour-unfolded/`).

Other checks:
- **Package tests:** the GlassConnectionUI, GlassConnectionKit and GlassEditor targets passed (172, 53 and 25
  Swift Testing tests).
- **Builds:** the Mac and visionOS compiled.

