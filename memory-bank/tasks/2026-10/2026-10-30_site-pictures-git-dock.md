# The site's pictures: Git in the editor, the orb dock, SQL from a terminal — 2026-10-30

**Owner and authorization:** "we don't have screen shots of the amazing dock on the website!", "we don't show the
new editor or databases, do we?", then "go ahead with all three". Local work: demo surfaces, pictures, page edits.
Deploying the site and committing are his word.

## Found
- Every editor and database picture on the site dates from 2026-10-18 (059df2a6), before Git in the editor (about
  8,100 lines since). Databases changed less (about 550 lines): the new visible piece is SQL from a terminal in the
  query editor; the table view's changes are text sizes and a literal-quoting fix. The dock (D88) had no picture.

## Built (DEBUG-only demo, `--ui-testing` runs)
- `App/GlassDemoGit.swift`: the made-up shop as a real repository — six commits over six weeks by two made-up
  authors, a merged branch, `release/2.15`, tag `v2.14.1`, a stash, and today's changes (the relay staged; the
  address checks and README changed; a file new, one deleted). Made with the Mac's `git` through `posix_spawn`: in
  the app on a Mac, and in the iPhone/iPad/Vision Pro simulators, which run on the Mac (checked: `simctl spawn` runs
  `/usr/bin/git` there). `GlassEditorLocalFileAccess.demoGitRunner` (DEBUG) gives a simulator's local folder that git.
  Surfaces `editor-git` (Changes), `editor-history`, `editor-blame`.
- `--demo-editor-size w,h` (`GlassEditorWindowSize`): a taller editor window, as a person could resize it.
- `dock` surface (Vision Pro): Into the Dock on; three coding agents in one window, btop on build, the shop
  database and the editor each dock 4 s after opening (`GlassSessionOrbDemo.shrinksNext`); `--demo-dock-alone`
  skips the window opened after them (a window opened then is placed above the dock, over it, off the top).
  `DEMO_ORB_NAME` in `shoot.sh` passes one orb name, spaces and all.
- `database-sql` surface and `DemoStart.sql`: SQL queued as Open in SQL Editor queues it, the orders table beside.
- `device_shots.sh [name …]` takes only the named pictures; `vision-editor-git`, `vision-dock`, `vision-dock-name`
  added; a close-up framing for the dock (found in the upper half, framed from its left edge).

## Pictures and pages
- `site/static/shots/vision-editor-git.webp`, `vision-dock.webp`, `vision-dock-name.webp` (from the final source).
- Home page: a section "The orb dock" with both dock pictures; Git named in the Mac editor caption and the editor
  card. Editor page: the Git picture under the Vision Pro one, captioned honestly (on the headset Git runs for a
  project on a server; the simulator uses the Mac's git behind the same Changes view), and a Git card.
- `build_site.py` passes (links, anchors, addresses); previewed in my own tab.

## The Mac pictures (after Parallels was quit, his "It's quit.")
- **Parallels was not why the VM had no address.** With it quit (and its bridges gone), `glasspowertools-mac26`
  still got none: its guest never finishes booting (one core at 100%, the guest agent silent, and no `bridge100`,
  which the host makes only when the guest's network comes up). A copy of `glasspowertools-mac26-clean`
  (`macvm.sh reset`) booted and had an address within seconds, so the Mac's network is fine; the 10-23 and 10-28
  failures were probably this VM too. The pictures came from `glasspowertools-mac26-run`. Recreating the main VM from
  clean (delete it, clone clean) is his call.
- **`macvm.sh` said "no VM named …" at random** (the known quirk): `tart list --quiet | grep -qx` under
  `pipefail` — grep stops at the match, tart dies of SIGPIPE (141), pipefail calls it a miss. Shown 2 misses in 6;
  fixed (grep reads the whole list), 12 of 12 after.
- **`vmtool drag` / `click`** (CGEvent, the same Accessibility trust as `press`): a person's drag of the query
  editor's divider and a click on the sidebar's disclosure, for the SQL picture.
- **Keyboard navigation off in the VM** (`site_shots.sh` prepare): the Cirrus image sets `AppleKeyboardUIMode` 3, and
  every editor picture since 10-18 had a focus ring on its first tab (the site's `mac-editor-*` too). With 0, as a
  Mac ships, the commit Message box holds the focus instead, as on a Mac.
- **`editor-git`** (`site_shots.sh editor-git`): the Changes tab on the shop repository in `~/Documents/shop`, made
  with the VM's own git (Apple Git-157). `mac-editor-git-dark/light.webp`, 2480 × 1560.
- **`sql`** (`site_shots.sh sql`): `database-sql` now opens alpha's terminal first with `sqlTranscript` (a coding
  agent printing `demoSQL`, the cursor back in its answer box), then the database. The script places both windows,
  opens `main`, drags the divider down 65 points so all eight lines show, presses Run Statement: 25 rows, Fay
  Fischer first (the same as `sqlite3` gives on `make-demo-db.py`'s file). `mac-sql-dark/light.webp`, 2880 × 1346.
- **Pages:** the editor page pairs the Mac Git picture (a folder on the Mac) with the Vision Pro one, whose caption
  now says only that there, and on iPhone and iPad, Git works for a project on a server. The databases page has the
  SQL picture after the Vision Pro one. `build_site.py` passes; both pages looked at in my own tab, dark and light.
- Both new shots are in `site_shots.sh`'s default set.

## Whole screens on Apple's wallpaper (his "yes to all three", then the look, 2026-10-30)
His three yeses: recreate the main VM from clean; retake the Mac pictures without the focus ring; commit and deploy
"when you're happy with the pictures" (his word still to come on the new ones). Then: "I'd love it if we could shoot
all of these with the default Apple background visible … For Mac of course. Vision Pro with the default living room
as they are", and, of a library picture half empty, "There's a balance that needs to be had between showing the
product and chaotic display … Use a landscape iPad image to show the same screen, just more full."
- **The main VM recreated** (`tart delete` + `tart clone …-clean`): it boots and had an address at once.
- **The wallpaper** (`macvm/wallpaper.py`, rewritten): macOS 27's default, the "macOS" dynamic wallpaper (Golden Gate
  graphic), which the VM's macOS 26.6.2 doesn't have (its default is Tahoe Day). Still frames of the light and dark
  landscape videos macOS keeps in `~/Library/Application Support/com.apple.wallpaper/aerials/videos`, at 64.5 s (his
  screenshot matched frame by frame, stretched as macOS draws it: `videoGravity` "resize"). Apple's artwork: made at
  shot time, never in the repository.
- **The screen** is 1504 × 940 points (the VM has no 1440 × 900 mode; about a 13-inch MacBook Air), 3008 × 1880 px.
  `site_shots.sh` captures all of it (`screen`): menu bar, clock set to 9:41 (`sudo date`, network time off),
  Dock hidden (from the GUI session: from SSH alone it stayed), scroll bars only while scrolling
  (`AppleShowScrollBars`; the VM has no trackpad, so macOS drew them always). Windows keep 1240 × 780; the library
  1200 × 740, Active 1100 × 720. `looks` are still cut-out windows (their gallery's pictures are small).
- **A lived-in library** (`GlassDemoMode.fillLibrary`, for `library-history` and `active`): nine machines in four
  collections (`Tools/Screenshots/demo-hosts.sh`, `#` in the seed, shared by all three scripts), a month of
  connections and minutes in use (Time in Use is what the overview opens on; the demo had none), Recent from each
  machine's last connection, three favourites, four tmux sessions, two workgroups, three key records held in memory
  (no key material) and four project folders. New DEBUG helpers: `demoRecordMinutes`, `demoMarkFavorites`,
  `demoOtherDevices` minutes, `demoLibraryExtras`.
- **No empty columns:** the terminal's sidebar is closed (his own is; open it listed one terminal) — `vmtool press`
  takes a window title now, because the SQL picture's two windows each have a Hide Sidebar. The editor opens
  `Sources` and its four folders, and its plain project is the shop's last commit plus the pictured files. The SQL
  pair is laid out again for the smaller screen. The made-up remote screen's clock says today, not "Mon".
- **iPad in landscape** (`UITests/SiteShotsUITests.swift`, run by `device_shots.sh` with `IOS_XCTESTRUN`): iPadOS 26
  ignored `--demo-landscape` (`requestGeometryUpdate`), and the Simulator app's rotate would open on his screen; a UI
  test turns the simulator headless (`XCUIDevice.orientation`), waits for the overview and Most used, and captures.
  The capture is the portrait framebuffer, turned upright afterwards. `ipad-landscape.webp` is 1600 × 1200 (a new name: browsers keep the site's files a week, and an old portrait copy would be squeezed into the new frame). Shown to
  bite: with no history it failed "the overview has no Most used" — and still wrote a picture, so it now stops at the
  first failure (`continueAfterFailure = false`).
- **`--demo-close-connections` left no window at all** after the full run (btop: not even the library window, for a
  moment; without the flag both windows opened, every time). Not cancellation (that guard is in now, and the launch
  still failed) and not the moved clock (it failed at the real time too); not understood. The same failure was seen
  with a look on 10-20. The Mac shots now minimise Connections (`connections_away`), as the looks already did.
- **The first Hide Sidebar press missed:** the terminal window's accessibility title is "alpha – ann@192.0.2.10:22",
  so `vmtool press … <window>` matches the title before " – " too. Checked: Show Sidebar after the press.
- **Looked at** every new picture, then the built pages in my own tab (home dark, editor light), images and CSS
  reloaded past the browser's cache: the iPad and iPhone stand the same height (500 and 498 px).
- **Site:** Mac pictures are `img.screen` (a rounded frame, as the Vision Pro room's), 3008 × 1880; the iPad and iPhone
  pair's columns are 1.33 : 0.46 for the landscape iPad; the library's and iPad's descriptions say what is in them now.

## Then his five asks (2026-10-30, afternoon)
"fix the error to say something like "Connect iCloud to enable syncing"? less errory and more informative. keep them.
add blueprint! can we add a spatial environment for vision pro? the two made by claude? … also update all docs to
mention animation in the environments and sounds. take a run around the changes and update the features to include
whats missing both on the site, help, and readme!" Asked what "add" the rooms meant: "screen shots for the site is what
i meant", and the meadow one is the Ridge Studio ("the field view one. big glass windows overlooking a meadow"), not
the Rain Garden. Then: "shoumd have a digital clock above the window (nyc loft)".
- **The library's iCloud footer** (`GlassCatalogSyncStatus.unavailable(_, short:)`): signed out says **Sign in to
  iCloud to sync** (Apple's verb, not "Connect"), needs attention **Check iCloud to sync**, restricted **iCloud is
  restricted here**, all in the footer's grey; only a failed sync is red. A build with no iCloud (from source, a UI
  test) says **On this device only**, and its description says the App Store and TestFlight builds sync. The demo
  library shows the signed-out footer (`demoSignedOutOfICloud`), true of the screenshot VM, which has no Apple Account.
  Tests: the signed-out short line, and the no-iCloud words; both seen failing with the words changed, sources
  restored byte for byte.
- **Looks kept** as cut-out windows; **Blueprint added** to the terminal page's gallery and list (its picture is from
  10-2x, in the same style as the other looks).
- **Focus Mode pictures** (`vision-focus-loft`, `vision-focus-ridge`, on the home page and in the README): the
  owner's Loft (with its sounds and events) and Ridge Studio from `ENVIRONMENTS_DIR` (his Downloads; never named in
  the repo), copied by `shoot.sh` (`DEMO_ENVIRONMENTS`) into the simulator app's Focus Environments folder after
  install. `--demo-teleport` couldn't move past the loft's desk (its ray lands on the desk: "not the floor"), so a new
  DEBUG flag, `--demo-nudge ahead,right,turn°`, takes Fine Position's step: the loft 1.2 m on, its digital clock above
  the terminal (1.8 m cut it off); the studio turned 70° right, to its glass and the hills. The clock shows the
  simulator's real time, not 9:41.
- **Docs pass:** an audit agent listed what the site, help and README were missing; two writers took the help pages
  (terminal ones; library, editor and database ones), and I took the site pages, README, PRIVACY, SECURITY and the
  help registry. Every "what the app connects to" statement now includes the Mac's git reaching a repository's
  remote, which none did.
- **The room how-to stays** (terminal-sessions, "Make a room of your own"). The owner first said "Let's leave the room
  how tos until we build i intentionlly.", reading it as a plan; told it describes what the app already reads (living
  rooms, 0.4.540, his Loft): "If it was there already maybe it should have stayed." Restored, with an opening line
  saying it works today; its names and limits checked against `FocusRoomLife.swift`.

## Not done
- On Vision Pro the SQL picture was dropped: the query editor takes focus, so visionOS shows the keyboard's text
  bar, and the unrun query leaves the results empty. The Mac picture shows it.
- A docked agents window's orb is dark (its live picture is the terminal's own; a look doesn't reach it).
- Deploying the site and committing: his word.
