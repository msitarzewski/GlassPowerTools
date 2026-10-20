# 2026-10-19 — The app at the largest text sizes

**Objective.** Usable at the five accessibility text sizes, toward the App Store's Larger Text label
(`2026-10-18_accessibility-audit.md`, P1 and P2).
**Authorization.** The owner, 2026-10-19, of three remedies proposed with the audit's screenshots
("C is it. Yes!"):
1. rows stack at accessibility sizes;
2. bars go icon-only, with the Large Content Viewer;
3. names wrap instead of being cut.

Still open, for the owner: whether the data grid's and terminal's own text sizes should follow the
system size by default (item 4), and the terminal's 24-point maximum (P3).
**Owner.** The coordinating agent.

## What was wrong

At the largest size (AccessibilityXXXL), on iPhone and iPad:
- a machine's services: the name and kind cut to "T…" and "…", beside Connect, Edit and More, which
  kept their width; the icon, grown, ran under the name;
- a table's bar: "Filter" and "More" broke a letter or two to a line on iPhone; on iPad the pager
  broke "Cal-culate Total…" and pushed the workspace under the sidebar;
- the workspace tabs: "Ov…ew", "co…aml";
- the status bars: the editor's "Line 1,…", the desktop's "Conn…", the library's "Not synced on t…".

## The remedies

`Sources/GlassConnectionUI/GlassLargeText.swift` (new), one place for each:
- **`GlassLargeTextRow`:** the row as its caller lays it out, or at an accessibility size the identity
  on lines of its own and the buttons under it, leading.
- **`glassLargeTextWraps()`:** one line, or as many as the name needs at an accessibility size.
- **`glassBar()` and `glassBarItem()`:** a bar's text stops growing at xxxLarge, the largest ordinary
  size, as Apple's bars do. Past it, a bar's labels show their icon, and a long press shows an item's
  name in the Large Content Viewer.

Where:
- `GlassShell/GlassShellLibraryView.swift`: a service's row stacks; service and tool names wrap; their
  icon column grows with the text (`@ScaledMetric`, 20 points at the default size).
- `GlassDatabase/TableDetailView.swift`: the phone's and the iPad's bars over the rows, and the pager.
- `GlassEditor/GlassEditorWorkspaceView.swift`: the status bar.
- `GlassDesktop/DesktopSessionView.swift`: the status bar.
- `GlassConnectionUI/GlassWorkspaceTabBar.swift`: the tab strip; each tab's whole name in the Large
  Content Viewer.
- `GlassShell/GlassICloudStatus.swift`: the library's iCloud footer.
- `GlassShell/GlassLibraryOverview.swift` (found on the iPad run, not in the audit's list): Your Library's
  four figures go one to a row where two do not fit, and the services' counts one under another; the
  space before a figure's word grows with its symbol. Before, "Ma-chines" lay under its symbol and
  "1 Desktop" broke a letter or two to a line.

At the default size nothing moves.

## Validation

`UITests/LargeTextUITests.swift` (new, iOS), at AccessibilityXXXL unless said:
- a service's Connect is under its name, at the leading edge;
- at the default size, it is beside the name, at the trailing edge (nothing changed);
- the phone's Filter and More are on one line, each under 64 points tall;
- Xcode's audit finds no clipped text in the editor's position, the desktop's state or the iCloud
  footer;
- on an iPad, the overview's Services figure is under Machines, and "1 Desktop" is one line.

Results (simulators; "without" is the audit's worktree, which has everything but these remedies, with the
same test file):

| | iPhone 17 Pro Max, with | iPhone, without | iPad Pro 13-inch, with | iPad, without |
|---|---|---|---|---|
| Service row stacks | pass | fail (Connect at y 318 beside an icon ending at 368) | pass | fail (y 304 beside 354; x 747 past the icon's 591) |
| Row unchanged at default size | pass | pass | pass | pass |
| Filter and More one line (phone only) | pass | fail (187 points tall) | skipped | skipped |
| Editor status not clipped | pass | fail ("Line 1, Column 1") | pass | pass (an iPad's bar had room) |
| Desktop status not clipped | pass | fail ("Connected") | pass | pass (as above) |
| iCloud footer not clipped | pass | fail ("Not synced on this build") | pass | fail (the same) |
| Overview figures whole (where shown) | skipped (the phone shows the list) | skipped | pass | fail (Services beside Machines; "1 Desktop" 311 points tall) |

The default-size test passes both ways, as it should: it is the check that nothing moved.

Other checks:
- **Xcode's audit, iPhone, largest size, all 17 screens:** clipped text 33 → 27. Left: the navigation bar's own
  buttons (the system's, with its own Large Content Viewer) and the library's category rows, which are whole
  on screen. "Doesn't scale" rose 32 → 44: the bars now stop at xxxLarge, which the audit reports, as it does
  for the system's own Done, Cancel and Settings. Apple's Larger Text criteria allow it: "some features, like
  Tab Bars, don't grow with dynamic text … Consider other ways to make those elements accessible, such as the
  Large Content Viewer", and "prioritize scaling the main content areas before repeated, predictable
  navigational elements". The bars' text measured 1.45 times the default, at xxxLarge.
- **Hit areas** the audit now reports at the largest size: a tab's close button, the desktop's Keys and
  Keyboard, the editor's keyboard toggle. These are the audit's P7 at the default size; capped, they no longer
  grow past it. The owner's P7 decision covers them.
- **Package tests:** GlassShell 321, GlassConnectionUI 172, GlassConnectionKit 53, GlassEditor 25: all pass.
- **Builds:** iOS simulator, Mac and visionOS compile.
- **Pictures** (working folder, not the repository): `a11y/largetext-before-after.jpg` (iPhone),
  `a11y/ipad-largetext-after.jpg`, `a11y/ipad-overview-before-after.jpg`.

## Part two: the owner's three "yes"es

**Authorization.** The owner, 2026-10-19, "Continue with that work, yes", to the three questions left
open above:
1. a wider editor file list at accessibility sizes;
2. the terminal's largest font size raised to at least 28 points (the audit's P3);
3. the grid's and terminal's text following the system's text size by default (item 4).

Committing and TestFlight 0.4.481 still wait for his "commit".

**What changed.**
- **`GlassConnectionUI/GlassLargeText.swift`:**
  - `GlassSystemTextSize.scaled(_:for:within:)` scales a size the way the system scales body text
    (`UIFontMetrics`). The size picked is the size at the standard text size. At Large, and on a Mac,
    which has no system text size, the size is unchanged.
  - `glassNavigationColumnWidth()` gives a sidebar the library's widths (240/340/480). At an
    accessibility size it uses 360/480/600 (new constants in `GlassLibraryColumnLayout`).
- **Editor** (`GlassEditorWorkspaceView.splitLayout`, the Mac and iPad): the file list uses
  `glassNavigationColumnWidth()`.
- **Terminal, 28 points:** `TerminalTheme.maximumFontSize` is 28 (was 24). The two Settings sliders
  and This Window's slider read the limits instead of literals, and so does the sync refusal's
  message. Theme import accepts up to 28.
  - **Compatibility:** a build before this one refuses a synced theme over 24 points and keeps its
    own settings, with "Update … on each device". It can't overwrite the newer payload, because a
    push validates the stored envelope first (`GlassShellSettingsSync.decodeStoredEnvelopeIfPresent`).
  - ⌘+ and ⌘− still reach 10–72 (`SwiftTermHostModel.zoomRange`, now named).
- **Terminal follows the system size:**
  - New setting `fontFollowsSystemTextSize`, on by default. It stays on the device, outside the
    portable iCloud preferences.
  - `TerminalWindowView.defaultFontSize` scales the theme's size, or the window's own, with the
    system's text size. ⌘+ and ⌘− step from it.
  - Settings ▸ Terminal ▸ Font has the toggle "Scale with System Text Size" and a line of
    explanation, on iPhone, iPad and Vision Pro.
- **Grid follows the system size:**
  - New setting `dataGridFollowsSystemTextSize`, on by default and kept on the device. Its toggle,
    "Scale grid with system text size", sits under "Results grid text".
  - `TableDetailView.gridFontSize` scales the grid's text.
  - `DatabaseGridMetrics` derives the rows, header and row-number column from the text size. At
    13 points they're 30/36/50, as before. A fixed 30-point row had already clipped the setting's
    own 32-point maximum.
  - Automatic column widths keep 80–400 points at 13-point text and grow in proportion past it.
- **Why there's a switch:** at the largest size a 14-point terminal becomes 44 points, about 9
  columns on an iPhone. Someone who wants a small terminal while using large system text can turn
  scaling off.

**Validation:**
- Unit tests:
  - `DatabaseGridMetricsTests` (new);
  - `GlassSystemTextSizeTests` (new; the Mac case runs under `swift test`, the UIKit case compiles
    for iOS);
  - `PortableSettingsSyncTests`: 28 points syncs and 29 is refused; the switch defaults on, persists
    and doesn't travel;
  - `TerminalWindowSettingsTests`: a window's size clamps to 28;
  - the database window and settings-page suites.
  - All pass.
- UI tests (`LargeTextUITests`, run with and without these changes):
  - a grid row at least 60 points tall at the largest size, and 30 at the default size;
  - the terminal's size at 28 points or more at the largest size, and 14 at the default (iPad);
  - "compose.yaml" in the file list on one line (iPad).
  - Results are below.

## Left for the owner

- Not committed; at his word.
