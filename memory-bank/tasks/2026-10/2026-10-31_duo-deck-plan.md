# The iPhone Duo half open: the work above the fold, a deck below (2026-10-31)

**Ask (the owner):** "we also have no images for the iPhone Duo. I'd like for the folded (in half) versions of our
tools to leverage the two screens to perfection … the top screen a remote desktop, then the bottom a keyboard and a
toggleable trackpad … A terminal gets the keyboard on the bottom … The database with a keyboard on the bottom … take a
look at some of the really cool implementations for iPhone Duo, and let's create a plan".
**Status:** Approved 2026-10-31 ("go with your recommendations", D93); nothing built. The plan is the owner's doc "Glass Power Tools on the iPhone Duo" (a private
Claude Docs link, not recorded here). Earlier Duo work: `tasks/2026-09/2026-09-20_iphone-duo.md`,
`2026-10-18_duo-day-one.md` (every page folded and flat), `2026-10-21_looks-duo-keys.md` (the terminal half open).

## Today
- Only the terminal reads the fold (`GlassDeviceFold`, `TerminalWindowView.laptopBar`). The desktop, database and
  editor draw across it.
- Laptop pose, measured 2026-10-21 (Xcode 27.1): window 669×951 pt, fold y456–496, keys from about y556 with the
  keyboard up, leaving a 60 pt strip that is ours when there is no prediction row.
- Reusable: the desktop's `TrackpadPointerController` (relative pointer, tap, tap-drag, two-finger right click),
  `DesktopAccessoryKeys`, the remote size following the window; the SQL editor's `SQLEditorCompletionProvider`; the
  record editor; the editor's preview modes and diff viewer; Show All Windows' cards; Watch Log File. The terminal's
  file preview is visionOS-only (`VisionTerminalPathPreviewer`).

## Research (a research agent's report, checked against its sources)
- Apple: content above the fold, controls below; no pose-only features; lay out from reserved regions, not the hinge
  (tech talks 111462–111466, HIG "Designing for iPhone Duo"). The SDK has no keyboard docking and no system trackpad.
- UTM 5.0.7: half open, the bottom half is a keyboard or a touchpad with a switch; keyboard only on a fresh fold;
  re-reads the fold 0, 0.5, 1.5, 3 s after a hinge change. Secure ShellFish, Working Copy, rootshell, Conduit (RDP
  resizes to the screen), Samsung Flex Mode's touchpad, Surface Duo's companion pane and dual view.
- Known limits: keyboard extensions get no reserved regions (forum thread 847963); Split View is a fixed 50/50.

## The plan (proposed)
One shared deck in `GlassConnectionUI`: a strip under the fold (the tool's keys and a keyboard-or-panel switch), then
the system keyboard or the tool's panel. Desktop: screen above, trackpad panel. Terminal: tabs as chips and cards, or
a second tab live. Database: query or results above, completions in the strip, the selected row below. Editor: key
strip, preview or diff below. Book pose: nothing on the fold, two pages. Steps 0–7: check Device Hub on Xcode 27.2;
the deck; desktop; terminal; editor; database; book pose; help, site pictures and App Store Duo screenshots.

## Two services side by side (the owner, same day)
"I'd argue that we should allow two of any of our services in fold like a book mode. A terminal the left, a database
on the right (or whatever)." Added to the plan as step 2, right after the deck:
- Held like a book or open flat on its side, the shell shows any two sessions as two pages (about 455 pt each, near
  the outer display's 466, where every tool was checked on 2026-10-18).
- **Inside one window**, so the 2026-10-13 rule (a phone presents sessions in place, `GlassWindowPresentation`)
  still holds; the system's Split View of two Glass windows may already work (`UIApplicationSupportsMultipleScenes`
  is on, the app just never opens a window itself on a phone) and is checked in step 0.
- New: the shell's page pair, and each tool handing over its session view by id instead of swapping the whole root
  (the terminal's iPhone root, `GlassTerminalBootstrap.platformRoot`, swaps the library for its workgroup today).
- Open on the Other Page, Swap Pages, Close Page; the focused page takes the keyboard; folded, the focused page
  alone; laptop pose, the focused page above its deck. The Mac's crossings (SQL from a terminal, Open in Editor for a
  printed path) land on the other page; on iPhone they are new work.

## Open (the owner's)
The desktop's size half open (follow the top half, recommended); what comes up on a fresh fold; the terminal's
panel; the half-open picture (Apple's image or a Blender render); two terminal tabs side by side later; whether a
physical Duo is available to test on.

## Step 0 — done 2026-10-31
- **Device Hub on Xcode 27.2 drives the Duo simulator.** Select the device by setting `selected` on the AXRow whose
  cell's text is "Duo probe" in Device Hub's sidebar (`~/Software/glass/tmp/duo/dh-select.applescript`); the window
  then reads "Duo probe – iOS 27.2". Pose buttons as before (`duo/partial/dh.applescript "Partially Open"`, then
  "Rotate Right" for the laptop pose). Captures in `~/Software/glass/tmp/duo/step0/`.
- **The 21 October layouts hold on the 27.2 runtime:** held like a book, the bar's halves stay off the middle;
  stood like a laptop, the terminal above the fold, its bar just under it, and with the keyboard away the lower
  half empty (where the panel goes).
- The system's Split View of two Glass windows is left for step 2's checks.

## Step 1 — the shared deck, built 2026-10-31
- `Sources/GlassConnectionUI/GlassFoldDeck.swift`: `GlassFoldDeck` (work above the fold; a strip under it with the
  keyboard switch and the tool's keys; the keyboard or the tool's panel below) and `GlassFoldDeckPolicy` (pure: the
  keyboard on a fresh fold only, put away stays away, unfolding restores). The keyboard is measured in the window
  (`GlassKeyboardPresence`), and a fresh fold's request is repeated at 0.8 and 2.5 s until the keyboard appears.
- `GlassDeviceFold` re-reads 0.5, 1.5 and 3 s after a hinge change (UTM's), not 250 ms and 1 s.
- The terminal's iPhone layout (`TerminalWindowView.phoneFoldLayout`) uses it; only the terminal in front acts.
- Tests: `GlassFoldDeckPolicyTests` (5; seen failing without the fresh-fold guard), GlassConnectionUI 65 pass.
- Seen on the Duo simulator, stood like a laptop: the layout as before, and with Device Hub's "Simulate Hardware
  Keyboard" off, the keyboard comes up by itself on the fold (`~/Software/glass/tmp/duo/step1/`).
- Order changed (mine): the remote desktop (step 3) before two pages (step 2), the owner's first ask and the
  deck's simplest proof; two pages next.

## Step 3 — the remote desktop, built 2026-10-31
- Stood like a laptop: the remote screen above the fold (sized to it, as any window), the strip with the deck's
  switch, the connection's state, Keys and the arrow pad; below, **the trackpad** (`DesktopTrackpadPad`), which a
  fresh fold brings up. It steers the same pointer as a finger on the picture (`DesktopMTKView.padBegan…`): one
  finger points, a tap clicks, tap-drag drags, two fingers tap for a right click or move to scroll; a click is felt.
- Found on the way: the desktop kept the keys with an empty stand-in keyboard, which on the Duo stood like a laptop
  still reported the whole lower half; so half open the surface lets go of the keys while the keyboard is put away,
  the deck takes the tool's word (`keyboardWanted`), and the desktop's keyboard has no suggestions row (spell
  checking, smart insert/delete and inline predictions off, as SwiftTerm has them).
- Tests: `UITests/DuoDeckUITests` (3, skip without a Duo stood like a laptop): the trackpad moves the pointer (seen
  failing with the pad's movement cut), the switch trades trackpad and keyboard (failed before the fix above), a
  terminal's fold brings up the keyboard.

## Step 4 — the terminal's panel, built 2026-10-31
- With the keyboard put away, the deck's panel is the window's tabs as live pictures (`TerminalFoldTabsPanel`),
  the others first, redrawn each second; tap one to bring it up. Up to two tabs, one column (so with two, the other
  fills the panel: a log followed in it stays in sight); more, two columns. New Terminal Tab at the end. Handed down
  by the iPhone's tab stack (`VisionTerminalWorkgroupView.compactTerminalTabs`, `\.terminalFoldTabs`).
- Seen on the Duo simulator with `--demo-open terminal-tabs` (`~/Software/glass/tmp/duo/step4/tabs.png`).
- Not yet: the file preview brought over from Vision Pro, and SQL and paths opening beside (with step 2's pages).

## Step 5 — the editor, built 2026-10-31
- Stood like a laptop: the code (or code and preview, as chosen) above the fold; the strip has Tab, brackets and
  quotes (scrolling), Left/Right, Undo, Redo and Find (`GlassEditorFoldStrip`, each key one undoable edit at the
  cursor via `GlassEditorModel.apply` and `reveal`); with the keyboard put away, the file's preview below when it
  has one and isn't already shown. The bar above the keyboard is withheld (`keyboardAccessoryWithheld`, observed by
  `GlassEditorUIKitEngine`); a fresh fold closes the project's files, which are drawn over the strip's first keys.
- Test: `DuoDeckUITests.testTheEditorsStripTypesAtTheCursor` (seen failing with the insert cut).

## Step 6 — the database, built 2026-10-31
- Stood like a laptop: the query and its results above the fold; the strip has Run (the toolbar's own menu,
  `SQLRunControl`) and Explain, lent by the query editor (`\.databaseFoldActions`), and SQL's keys (`DatabaseFoldStrip`,
  typing through `SQLEditorController.type`, which now holds the editor model weakly); with the keyboard put away,
  the selected row in the record editor below, saving through the same review as the record sheet.
- A table's own tab (no query editor around it) has the keys, and Run stays in the top bar.
- Test: `DuoDeckUITests.testTheDatabasesStripTypesIntoTheQuery` (seen failing with typing cut). All six Duo tests
  pass on the Duo simulator stood like a laptop.

## Step 2 — two pages, built 2026-10-31
- Held like a book, or open flat on its side, the window shows two pages (`Sources/GlassShell/GlassLibraryPages.swift`):
  each is the whole stack the window draws (every tool's bootstrap around a library), split at the fold read from the
  window (`GlassDeviceFold`), each told it is compact width. Two pages when the window is a phone's, regular width,
  on its side, at least 760 × 560 (867 × 635 inside the system's column, measured). One `ForEach` for one page or
  two, so the first page keeps what it shows when the second appears (unfolding with a session open).
- **The page in use** (`GlassPageFocus.focused`, `\.glassPageIsFocused`) is the last one touched: a window recognizer
  that never claims a touch, deciding by the fold's middle, and only for touches on the pages (not a sheet or menu
  drawn over both). Each tool's request drain runs on the page in use only, and drains again when its page gains it.
- **One session, one page** (`glassShownOnPage`, keyed per tool: terminal workgroup, database session, desktop,
  editor window): chosen on the other page, a session moves there and the page it left goes back to its library.
  A page counts as moved away only from a session it had already claimed (without that, both pages put it away).
- **On the other page:** Connect on the Other Page (a host row's menu), On the Other Page (Connect's chevron menu),
  Show on the Other Page (an Active session row's menu). `GlassPageFocus.openBeside` asks the other page to put away
  what it shows (otherwise a terminal there hides the database's handler and the request waits), puts it in use, then
  opens. It names the page outright: a menu's own touch lands wherever the menu is drawn.
- **In-page covers:** the desktop and the editor were full-screen covers, over both pages. On the Duo
  (`GlassWindowPresentation.presentsInPages`: a phone that answers yes to multiple scenes) they present inside their
  page (`glassSessionCover`), the library kept under them as a cover keeps it; every other iPhone keeps the cover.
- **A terminal on a page was wider than it** (640 pt from x −92): its bar, kept right of the fold for a terminal across
  both halves, was padded past the page. `GlassDeviceFold.crosses(_:)`; the bar moves only for a fold inside the
  terminal, and the keyboard's accessory still keeps off the middle, the keyboard spanning the window.
- Found and fixed on the way: pages are placed by `.offset`, so frames read after it were the page's place before it
  moved; the touch rule had matched no page on the second one.
- Tests: `GlassDeviceFoldTests` "two pages" (seen failing with `crosses` always true). `UITests/DuoPagesUITests` (3,
  skip without the Duo held like a book): a terminal fits its page (seen failing at 640 pt without the fix), a session
  moves to the page that asks (seen failing without the terminal's page record), Show on the Other Page (seen failing
  without the put-away request). `DuoDeckUITests` 5/5 still pass stood like a laptop; folded, the desktop and editor
  open in place (captures in `~/Software/glass/tmp/duo/step2/`).
- Demo surfaces: `pages`, `pages-desktop`, `pages-editor` (the monitor on one page, the other tool on the other).
- Not done: Swap Pages; the system's Split View of two Glass windows (unchecked); "Open on the Other Page" in Show All
  Windows and in a session's own menu; the remote desktop's and editor's controls sit in the system's column at the
  window's edge (the system's placement for a bar beside it, as full-window on 2026-10-18).

## Step 7 — a tool alone, held like a book, built 2026-10-31
- The plan's book column: a tool alone uses both pages for its own two things. With step 2's pages always split,
  that needs one page across both: **Use Both Pages** (`GlassPageFocus.useBothPages`), with **Swap Pages** and back to
  two from a handle of three dots above each page (iPad's idiom, in the band above the bar; `GlassPageHandle`). The
  spread page takes the window's regular width; the other page waits under it, kept.
- What each tool does across both, seen on the simulator (`--demo-spread`; captures `step2/spread-*.png`): the library's
  list beside the detail, the editor's files beside the code, the database's databases beside the query and results,
  the desktop across both halves, the terminal at 100 columns with its bar right of the fold. The split's column edge
  falls inside the fold (x ≈ 472, fold 456–496), so nothing sits on it; no per-tool code was needed.
- Tests: `DuoPagesUITests.testUseBothPages`, `testSwapPages` (seen failing with the spread and the swap cut).
- Not done: the editor's "code and its preview as two pages" (it shows files beside code instead); Show All Windows'
  cards in even columns with the gap at the fold.

## The desktop's keys and trackpad at once, built 2026-10-31
- The owner, after DuoScreen (a Mac-control app for the Duo): "Take a look at this for inspiration for Desktop mode",
  then chose **"Keys + trackpad at once (Recommended)"** of three offered. Below the fold: the desktop's own keyboard
  (`DesktopFoldKeyboard`, US layout, five rows of 14.5 key widths; each key its set-1 scancode; ctrl, alt/opt,
  win/⌘ and shift armed for the next key through the existing sticky modifiers; fn for F1–F12 and Home, End, Page
  Up, Page Down; Delete and the arrows repeat), and under it three shortcut buttons (Ctrl+C/Z/A on RDP, ⌘C/Z/A on VNC;
  held, the next key typed with what is armed becomes the shortcut, kept per device and per protocol, a UI test
  run's apart), Escape, and the trackpad (`DesktopFoldKeysPanel`). The iPhone's keyboard is the deck's switch.
- Not built from the mockup: a microphone button (on-device dictation would need speech and microphone permission,
  and the App Privacy answers looked at again: his call); the iPhone keyboard's own dictation is one tap away.
- Tests: `DesktopFoldKeyboardTests` 6 (every key against the USB HID usage table's scancode, fn, modifiers, row
  widths, chords and titles, the store; each seen failing when broken); `DuoDeckUITests.testAShortcutRecordsFromTheKeys`
  (seen failing with recording cut); the deck's six pass stood like a laptop. Not tried against a real RDP or VNC
  server: the demo desktop has no connection behind it.

## Step 8 — pictures, App Store screenshots, and Apple's resizability check (2026-10-31, night)
- **Apple's rules for device pictures** (developer.apple.com/app-store/marketing/guidelines, Product Images): use
  Apple's own product bezels, as is; "rendering in 3D or creating any simulation of an Apple product" is not
  permitted, so D93's Blender fallback is dropped. The owner accepted Apple's Design Resources licence for the iPhone
  Duo, iPhone 18, iPad Pro (M5) and MacBook Pro (M5) bezels (identical licence text). Bezel files stay outside the
  repository; `THIRD-PARTY-NOTICES.md` ("Artwork") says the frames are Apple's and not under this project's licences.
- **Duo pictures:** Apple's partly open Duo bezels are PSDs with a warped smart object; PhotoCraft's CLI (0.18.0,
  installed and registered as an MCP server for this project) fills them with `photocraft-cli run … --cmd
  layer.smartObjects.replaceContents` (its `serve`, MCP and the app's control port refuse the warp filter). Contents
  at 400 % (11412 × 8028); laptop pose turned 90° clockwise. Seven composites; two on the home page's new "iPhone Duo"
  section (`duo-laptop-desktop.webp`, `duo-book-terminal-database.webp`), checked at desktop and phone widths.
- **Bezels for the iPhone, iPad and Mac pictures** (the owner chose "iPhone, iPad and Mac"): `Tools/Screenshots/bezel.py`
  places a screenshot under a front-facing bezel's opening (flood-filled from its middle; a capture of another size is
  an error). `device_shots.sh` frames the iPad Pro 13-inch and iPhone 18 Pro Max pictures (`*-bezel.webp`, new names so
  cached old shapes aren't squeezed); `site_shots.sh` takes the Mac's whole-screen pictures at a 14-inch MacBook Pro's
  1512 × 982 points (the VM's tart display set to that, `macvm.sh` default too) and frames them Space Black (dark) and
  Silver (light) as `macbook-<shot>-<theme>.webp`. `BEZELS` names the folder of Apple's PNGs.
- **App Store:** Apple has an iPhone Duo screenshot class (inner 2853 × 2007 / 2007 × 2853, outer 2034 × 1398 /
  1398 × 2034, no alpha); submitting earns the product page's "optimized for iPhone Duo" badge, and from April 2027 it
  is required for apps built with the iOS 27.1 SDK or later. A set of 12 (7 inner, 5 outer) is prepared outside the
  repository; uploading waits for the owner's word and a TestFlight build with the Duo work.
- **Apple's app-resizability skill** (`xcrun agent skills export`): prerequisites pass (launch screen declared, iPad
  all four orientations, no `UIRequiresFullScreen`). No `UIScreen.main`. Findings left for a tested pass of their own,
  as they change phone and iPad behaviour: 17 `UIDevice.current.userInterfaceIdiom` checks in 12 files (layout choices
  in the terminal, database, editor and shell; Apple's guidance is to decide by size class or space, and to read
  idiom from the trait collection when it is needed at all), one `interfaceOrientations` request (the DEBUG demo's
  `--demo-landscape`), and safe-area reads in the All Windows pane and the editor's preview to check against an
  asymmetric (Duo) safe area.

## Step 9 — finishing (2026-11-01, the owner: "finish the duo, then workgroups … reuse is essential. DRY, and KISS")
- **Apple's resizability findings, settled.** Of the 17 device-type checks, the database's three were the question
  `GlassWindowPresentation.canOpenWindows` already answers (`GlassDatabaseScenes.present` says so: "rather than the
  idiom … one answer"): Disconnect where there is no window, This Window's settings where there is one, and back to
  Connections in place. They ask it now, which also covers an iPad with multiwindow off; the route enum that wrapped
  the idiom is gone. The terminal's "no height to spare" (Tools moves to the top bar) is decided by compact height,
  any device, not by phone (`hasNoHeightToSpare`); its lazy workgroup slots ask the phone navigation they exist for
  (`VisionTerminalWorkgroupView.usesCompactPhoneNavigation`) rather than a second idiom check; two pages ask
  `GlassWindowPresentation.presentsInPages`. Kept as they are, each for a stated reason: the phone's navigation model
  (one terminal at a time, in place), "This iPhone"/"This iPad", the long-line preview on a phone (its text view
  draws nothing), Scale offered where windows resize, corner radii, the iPad's This Window. The safe-area reads
  each take one edge, so the Duo's lopsided safe area is read correctly. `--demo-landscape`'s geometry request is
  DEBUG only.
- **All Windows over two pages.** A card chosen there opened on whatever screen was registered last, which could be
  on the other page, and a terminal on the page in use then hid the database's handler: the database never came
  (`testAllWindowsOpensOnThePageInUse`, failing with the old path, passing now). With two pages the pane now opens
  through `GlassPageFocus.openOnPage(focused)` (what `openBeside` was, named for its page), and a card's menu has Show
  on the Other Page (`testAllWindowsShowsOnTheOtherPage`). One control, `GlassShowOnOtherPageButton`, for the card
  and the Active row.
- **Not built, on purpose (KISS):** Show on the Other Page in each session's own menu — the page handle's Swap Pages
  already moves a session to the other side, keeping what each page shows; the editor's "code and its preview as two
  pages" — the spread is regular width, so the Preview button already offers code and preview beside each other;
  All Windows' cards with a gap at the fold — its Mission Control packing centres groups across the width, and a
  fold-aware packing is a layout change for the owner's eye, not a fix.
- **The system's Split View: not reachable here.** In the Duo simulator SpringBoard shows no multitasking control
  over the app, and a swipe up from the bottom goes home (a throwaway probe test, removed). By the code: a Split View
  half is compact, so it shows one page; tool requests are taken once (`takeRequests`), so two Glass windows could
  not both open one.
- **The desktop's deck could spin the main thread forever** (found by this pass's full UI run: one desktop test in
  each run "main thread busy for 30.0s", a different one each time). Caught by relaunching the desktop demo stood
  like a laptop until a launch sat at 100% CPU (about one in five), sampled (`GlassFoldDeck.frame.setter` inside a
  layout loop) and logged: the deck's measured frame alternated between minY 139.97389848344642 and …636 (height
  838.6666666666665 and …667), each laying the deck out to give the other, two thousand times a second. A layout
  that follows its own frame now ignores a change under half a point: `glassGlobalFrame` (`GlassDeviceFold.swift`),
  used by the deck and by the terminal's `stackFrame`, which had the same shape. Test: `GlassDeviceFoldTests`
  "a frame that moved by less than half a point is the same frame" with the two measured frames (fails with exact
  equality). On the simulator, launching the desktop demo stood like a laptop: before, about one launch in five sat
  at 100% CPU (4 of about 20); after, none in 40.
