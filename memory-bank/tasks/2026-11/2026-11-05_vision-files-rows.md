# Vision Pro: the Files window shows the names (0.4.597, 2026-11-05)

**Ask (the owner, with a photo from the headset: a Files window from a terminal's folder button, every file's name
"…"):** "Let's fix this default when clicking the Folder icon in the toolbar in terminal on Vision Pro. It should be
wider, and allow the names of the files to be shown by default. If we need to hide rows for responsiveness, hide
permissions and put the 'Actions' under a drop down menu?"
**Status:** built and checked in the visionOS simulator; 0.4.597. Uncommitted.

## Cause
- The headset's Files window opened at 700 × 500 (`GlassTerminalScenes`, `WindowGroup(id: "sftp")`). Its row
  (`SFTPBrowserView.fileRow`, visionOS) gave size, modified and permissions fixed columns (90, 150, 108) beside three
  buttons; the name took what was left, which was nothing.
- Folder rows had no buttons column, so their size and date stood a column further along than the files'; and file
  rows were indented 18 points on the left (for the Mac's leading disclosure triangle) while the headset's chevron is
  on the right, 32 points (measured), so names and columns were out of line too.

## Fix
- **Wider:** the Files window opens at 1100 × 500 on Vision Pro.
- **`SFTPFileRowLayout`** (new, GlassTerminal): the row's columns from the list's width. The name keeps 240 points; the
  row gives way in his order: permissions, then the three buttons fold into one ⋯ menu (Edit, Get Info, Download, the
  context menu's words), then the date. Widths: list − 108 (the plain list's margins 48, row insets 16 + 12, the
  chevron 32; measured in the visionOS 27.2 simulator: list 1100, row 1024, folder label 992).
- The name truncates in the middle (the extension stays) with layout priority; each button is 44 points wide; every row
  has the buttons column (a folder's empty); file rows keep the chevron's 32 points on the right instead of 18 on the
  left (visionOS only; the Mac and iOS unchanged).
- DEBUG only: `--demo-files-listing` gives the browser a fixed listing with no server (`SFTPBrowserView.demoListing`),
  with `--demo-open files`.

## Validation
- `SFTPFileRowLayoutTests` (4): wide shows everything; the order of giving way at each threshold; at every width
  200–1400 the name keeps its minimum when any layout can; the buttons column widths. Seen failing: the order swapped
  (1 test); then the minimum ignored, the full layout skipped and the menu width wrong (the other 3); restored, compared.
- visionOS simulator (`~/Software/glass/tmp/files-rows/run.sh`): at 1100 every column, full names, folders' and files'
  columns in line (`wide2.png`); a temporary 760-point build (reverted, compared): permissions hidden, ⋯ menu, a long
  name truncated in the middle (`narrow-crop.png`). The menu's items were not opened (the simulator can't be tapped
  from here).
- Package tests: 3,347 pass (4 new). Builds for Mac, iPhone and Vision Pro succeed (Release).
- **Installed 0.4.597 on all three, read back** (2026-11-05): Mac (no new crash reports), iPhone, headset.
- **For him to check on the headset:** the folder button's window opens wide with names; narrowed by its corner, the
  permissions go, then the ⋯ menu (its items unopened by me).

## 0.4.598: the size kept, a narrower first size (his "it should also remember the user's preference for sizing. It opens a little too wide now")
- `SFTPBrowserWindowSize` (new, GlassTerminal): the size a Files window is left at (its content's geometry, kept as
  "WxH" in the settings defaults, `com.glasspowertools.files.windowSize`, through `GlassConnectionsWindowSize.stored`)
  is where the next opens, by `defaultWindowPlacement`; 960 × 500 until then (a 940-point list fits every column).
- **Found:** beside `defaultSize`, visionOS ignored `WindowPlacement(size:)` (asked 760 × 640, given 960 × 500, the log
  in the placement showing the ask); without it, the placement's size was given. Recorded in `techContext.md`.
- DEBUG only: `--demo-files-window-size WxH` keeps a size as if a window had been left at it (the simulator can't
  resize a window).
- Tests: `SFTPBrowserWindowSizeTests` (3): standard fits every column and is under 1100; a kept size is the next; a zero
  size leaves the kept one. Each seen failing alone (standard 1100; kept ignored; the zero guard removed); restored,
  compared.
- Simulator: opened fresh, the window was 960 × 500 and kept that; with 760 × 640 kept, it opened 760 × 640 (taller,
  the ⋯ menu layout) and kept it (`size-kept-s.png`).
- Not seen: a resize by hand kept (the simulator can't drag a corner); for the headset.
