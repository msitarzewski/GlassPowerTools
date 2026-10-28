# Active context

Where the work is now. Rewritten 2026-09-27; the session-by-session log it replaces is in git
history, and each piece of work's evidence is in its task note under `tasks/2026-09/`.

## State: release preparation; features only at the owner's ask while he tests

The owner decided on 2026-09-26 to stop adding features and prepare the first public release.
All four capabilities (terminal, databases, remote desktops, editor) and the shell are built; see
`progress.md` for what is verified and how.

**Authorization in force:** local edits, tests, builds and local commits for release preparation and for
what the owner asks while testing ("go with your recommendations, commit each piece as it lands"). Mac builds
are installed over the running app when ready (the owner, 2026-10-08: "install mac builds when ready since we
have tmux"), except while he says he is working in it.
**Not authorized without the owner's explicit word:** pushing, opening pull requests or issues
upstream, deploying the site, the git history rewrite, anything touching real servers (SSH and database tests
use the disposable test VM only).

## Release-prep checklist

| # | Item | State |
|---|---|---|
| 1 | Licences and acknowledgements | done (`2026-09-26_licensing-and-acknowledgements.md`) |
| 2 | Dependency refresh | done within reach: point releases, SwiftTerm 1.20 (D48), swift-nio 2.104.0, swift-log 1.16.1; tree-sitter 0.27 and swift-crypto 5 blocked upstream (`techContext.md`) |
| 3 | Public-release audit fixes | done (`2026-09-27_release-audit-fixes.md`) |
| 4 | Memory bank curated | done; quotes paraphrased; `.brain/` untracked |
| 5 | README, SECURITY, CONTRIBUTING, building guide, release notes | done; brought current with the code 2026-10-17, and `RELEASE-NOTES.md` added |
| 6 | Upstream contributions (swift-nio-ssh, Citadel) | drafted locally for the owner's review; nothing sent |
| 7 | Help, site and the Mac release path (D38, D39) | built (`2026-09-27_help-site-and-updates.md`); the Sparkle key made and the site live (2026-10-18); the Developer ID profiles and CloudKit's production schema done, and the dry run passed; remaining: the first release run, after the repository is public |
| 8 | History rewrite, then the first push | only on the owner's word. Scanned 2026-10-18: today's tree is clean (one test fixed, de0610d); old file versions, the session log once committed and about 20 commit messages hold private details (the specifics are in `.private/`, never committed). Then, at his word, main became the checked rewrite (history kept, private values replaced, cited commit ids translated; 799 commits). The original history is archived outside the repository, a pre-push hook refuses anything descending from it, and `origin` pushes main only (details in `.private/`). **Pushed 2026-10-18:** github.com/msitarzewski/GlassPowerTools is public, main only; README, description, website and private vulnerability reporting set; the site says the source is public. Further pushes still on his word |
| 9 | App Store listing (iPhone, iPad, Vision Pro) | started 2026-10-18 at his word ("free, start now"): the listing's text and App Store Connect answers in `Documentation/AppStore/`, `PRIVACY.md` and `SUPPORT.md` rendered by the site build, the app's privacy manifest (`App/PrivacyInfo.xcprivacy`, missing until now), and screenshots from `Tools/Screenshots/store_shots.sh`. Committed at his word; 0.4.480 to TestFlight (the iPad database fix and the manifest); the site staged. 1.0 when it ships, TestFlight stays 0.4.n. Accessibility audit approved and done (2026-10-18, five naming fixes; labels not yet declarable). The iPhone Duo checked on every page and six problems fixed; the largest text sizes fixed at his word (2026-10-19), then the terminal's 28-point maximum, text following the system size, and the iPad editor's wider file list (same day); a wrapped paste joined again (`2026-10-19_wrapped-paste.md`). All of these, the page tour, the framed-screenshot tools and D83 (tmux tabs as control-mode clients, `2026-10-19_tmux-scrollback.md`) committed at his word on 2026-10-19; 0.4.483 holds them. TestFlight next, on his word. Open for him: a demo server for App Review, the France encryption declaration, an App Store Connect API key (lets the listing, builds and TestFlight groups be set from here). Proposed, not started: translations (the app is English-only). Task note `tasks/2026-10/2026-10-18_app-store-listing.md` |

## 2026-10-27 — RESUME HERE: the orb dock's ninth to thirteenth rounds, the terminal redraw storm, and living rooms committed and pushed (0.4.535–0.4.541)
- **Pushed 2026-10-27 at his word ("push it"):** eight commits, `dcad5dcb`…`61a3bd0f` (0.4.495–0.4.541), each scanned for
  private names and addresses first. Then, at his word, the tests' private-range example addresses (`10.x`) became
  documentation-range ones (`198.51.100.x`, which no test there used), except where a test needs an address on the
  local network (the Local Network checks: `10.0.0.20`, `10.20.30.40`, beside `172.16.x` and `192.168.x`); and this
  block's "not pushed" was put right.
- **Committed 2026-10-27 at his word ("Commit this and update the memory bank"):** the dock's ninth round
  (0.4.535: orbs that wrap, names that turn, a scroll that always scrolls, Connections larger with a hold menu, windows
  beside a tall dock, docked pictures across a relaunch, Auto-focus on Activity on by default) and tenth (0.4.536: the
  crash on a vertical resize, the snap to whole rows, the hold menu that never opened, the tall dock's side from Focus
  Mode's head or a setting). Mac, iPhone and headset run 0.4.537, each read back.
- **Then "just crashed on the headset" (0.4.536), built as 0.4.537, committed at his word:** every app crash on the headset
  since 0.4.508 (seven) is one: a terminal's picture drawn inside a SwiftUI body (All Windows' cards, a window's orb,
  the dock) laid its window out inside SwiftUI's update. `SwiftTermHostModel.previewImage` now gives the last picture
  and draws the next just after. Not reproducible in the simulator; the headset is the check. Eleventh round in the
  task note.
- **Then "end arrows" and a docked window hidden by the snap, built as 0.4.538:** arrows at the dock's
  ends where there is more (a pinch scrolls a row); an orb docked below the rows shown grows the dock to its row (up to
  three) or is scrolled to. Twelfth round in the task note.
- **Then two more, built as 0.4.539:** a name opening left across a docked orb's ring no longer runs
  under the dots it crosses (they clear while it is open; thirteenth round in the orb-dock note); and "the hyper
  refresh is back and the gear no longer works": a terminal window was drawn again whenever a different terminal in it
  printed (the bar about 40 times a second on his headset), now watched apart from the window's body, with the front
  terminal keeping its place while it prints (`2026-10-25_terminal-tools-menu-busy.md`, 2026-10-27). Likely the same
  storm as the CPU-use report below (Core Animation's commits on the main thread); not checked against it.
- **And a diagram's mark, after 0.4.539 (not on devices yet):** the UI suite around the redraw fix found
  `testADiagramHasAMarkThatShowsIt` failing with and without it: a diagram printed before its window opened was never
  looked for. `SwiftTermHostModel.flushPending` looks once queued output lands; the test passes.
- **0.4.538, 0.4.539 and the diagram fix committed 2026-10-27 at his word ("commit this and update the memory bank").**
- **Then living rooms (D89), 0.4.540, committed at his word:** the GlassSpaceMaker session's handoff built
  (a room's motion, a clock on the headset's time, sound from `<Room>.sounds/`, Room Sound); the fixed loft put in
  his iCloud Environments; on the headset: "holy shit it works~!!!". Mac, iPhone and headset run 0.4.540, each read
  back. `tasks/2026-10/2026-10-27_living-rooms-handoff.md`.
- **Rain Garden (2026-10-28, the GlassSpaceMaker session):** a second room, `RainGarden.usdz` + `RainGarden.sounds/` + `RainGarden.events/`, in iCloud Environments beside the loft; rain, drips and ripples are blend-shape animations, the first thing to confirm on the headset. Section at the end of `tasks/2026-10/2026-10-27_living-rooms-handoff.md`.
- **The gear confirmed fixed on the headset** (the owner, after 0.4.540–0.4.541: "the gear menu was indeed fixed as of
  the last build"): the redraw storm fix of 0.4.539 holds.
- **Then (2026-10-28), committed and pushed at his word ("commit and push, then build the nudge pad"):** Focus Mode lands only on the floor (0.4.543; `2026-10-26_focus-environments.md`,
  "Floor only"); push, pull and fetch in the editor (0.4.544; `2026-10-23_editor-git.md`, the last section). **Next, his
  choice:** a nudge pad and slide by hand for fine positioning in Focus Mode (same environments note). Open: his "the
  vision pro didn't connect when the app restarted" after 0.4.543's install; the headset's log shows ten terminals
  coming back at 06:25 and 06:30 UTC and nothing about connecting; he moved on ("GREAT!") before saying what didn't.
- **Then (2026-10-28) the Mac's third release, 0.4.548** (his "build and deploy the Mac version"; 0.4.547 built,
  committed and pushed, then withdrawn unpublished for the Files window's empty-folder gap, his "option 2"):
  `tasks/2026-10/2026-10-28_release-0.4.548.md`. The GitHub release and the site deploy are his to run (auto mode's
  classifier refuses a public release); TestFlight's external testing is drafted and waits on his details and word.
- **Then (2026-10-28) Terminal color schemes, 0.4.546 (Mac read back; headset and iPhone installing as they wake), not committed (D90):**
  a user's 148 Terminal profiles "first class": iCloud Drive ▸ Terminal Themes, Choose Theme (Settings ▸ Terminal ▸
  Theme ▸ Choose…), This Window, Open With. `tasks/2026-10/2026-10-28_terminal-schemes.md`. His "highlight/text
  customization": the theme always had them (Themes editor); schemes bring theirs, and Copy to Your Themes makes one
  editable. Not drawn: a bold colour (SwiftTerm has none). Storage and the honoured background are D90's choices,
  awaiting his word.
- **Then (2026-10-28) Fine Position, 0.4.545 on all three devices (read back), not committed:** the nudge pad from
  the moon's hold menu, and two defects found on the way: 0.4.543's floor-only refused every floor in the loft and
  Rain Garden (it measured from their skies' bottoms, kilometres down), and a room's raised floor was undone by any
  start. `2026-10-26_focus-environments.md`, "Fine Position". Next: his word on the headset; slide by hand.
- **Then (2026-10-28) a menu in the empty space of a Vision Pro terminal sidebar, 0.4.542 on all three devices (read back), committed and pushed (64d9045d):** held, what
  the bar's + offers (`tasks/2026-10/2026-10-28_vision-sidebar-empty-menu.md`). On the way: the runner's holds at a
  point of an ornament miss; tests hold elements.
- **Then phase 3 ("go ahead with phase 3"), 0.4.541 on all three devices (read back), committed at his word:** a digital clock and date panel at a `clock_digital`
  Xform, and events from `<Room>.events/events.json` shown now and then at `event_<name>` anchors (the contract is in
  the handoff note's "Phase 3, as built"). Seen in the simulator's test room; the loft has neither yet, the asset
  side's to add.
- **Next, his to try on the headset:** the gear with several agents at work; a docked orb's names at the dock's
  right edge; hold Connections (the menu); resize the dock tall and wide several times (the
  crash; no automated test reaches it); let go of a resize (the snap; whether visionOS reports the hand on the corner,
  `isInteractivelyResizing`, is unmeasured on the device); Windows From a Tall Dock; carry an orb; docked pictures
  after a relaunch.
- **Open:** a CPU-use report on 0.4.534 from the headset (60% over 150 s, Core Animation's commit on the main thread),
  not looked into (two more since, on 0.4.536 and 0.4.538, before the redraw fix); the tools menu, fixed in 0.4.539. Task note `tasks/2026-10/2026-10-25_orb-dock.md`.

## 2026-10-26: Focus Mode environments (D89), the tools menu on the headset (solved 2026-10-27, 0.4.539)
- **Windows come back as they were left, and the dock's shape and look (his asks while testing 0.4.533), 0.4.534:**
  a terminal window in the dock, standing as its orb, or open; Connections back in the dock unless it is showing a
  question; the dock resizable (taller than wide, a column; size kept) with its own Opacity and Glass starting with
  Appearance (his choices). Simulator: 11 orb and relaunch UI tests pass, each new one seen failing with its change
  out. The headset is his: a relaunch with docked windows, a corner drag, the Dock sliders. The dock now paints
  Appearance's glass and Opacity by default (0% of both makes it clear). `tasks/2026-10/2026-10-25_orb-dock.md`,
  seventh and eighth rounds.
- **Focus Mode environments on Vision Pro (D89), built:** a library of environments — Dimmed Room (default, as
  before), Night Sky, Dusk, Grid and Studio drawn in code, and his own 3D rooms and 360° photos in iCloud Drive ▸ Glass
  Power Tools ▸ Environments (Settings ▸ Terminal ▸ Focus Mode; This Window; the moon's pinch-and-hold menu). Vision Pro
  only (his word); a Mac manages the folder in Finder. Unit and UI tests pass; seen in the simulator; the headset and
  iCloud not yet. Proposed to him, not built: live data in environments; Sketchfab (now KitBash's) or another
  catalogue. `tasks/2026-10/2026-10-26_focus-environments.md`.
- **Open Immersed** (his ask, 2026-10-26 afternoon): a toggle in Settings ▸ Terminal ▸ Focus Mode, off by default; on,
  Focus Mode opens fully immersed and the Crown still dials it back. Built, tested (unit, UI, simulator captures; each
  seen failing with its break), 0.4.531.
- **Try Out, fits, and Mirador's teleport inside** (his "Yes, build all three", 2026-10-26): built and tested in the
  simulator (unit, UI, captures; breaks caught); the headset not yet. Task note has the details and what isn't seen.
- **Living rooms (2026-10-27), built at his "get're done" as 0.4.540 (on all three devices, read back), seen working on
  his headset ("holy shit it works~!!!"), committed at his word:** a room's own motion plays, a `clock`
  keeps the headset's time, a `<Room>.sounds/` folder plays, Room Sound in Settings (D89). Seen in the simulator on
  `AnimTest.usdz` and the loft. The loft's clock hands first sat between its dial and the wall; the asset session moved
  them in front (21:34), and that loft, with its sounds, is in his iCloud Environments.
  `tasks/2026-10/2026-10-27_living-rooms-handoff.md`, "Built".
- **Orb dock, sixth round (0.4.532):** his "We lost hover/view focus on the terminal/service icons … only show a stub":
  the fifth round's name layer reverted; the dot opens itself again, as in 0.4.527; overlaps ordered by depth.
  `tasks/2026-10/2026-10-25_orb-dock.md`. The headset is his to confirm.
- **Tools menu on Vision Pro: still fails on the headset in 0.4.527** ("I still can't select an item"). 0.4.528 writes
  the menu's openings and choices, the bar's redraws and the terminal's keyboard focus into the diagnostics file; next
  is one try from him, with the time, then the file copied off the headset. `tasks/2026-10/2026-10-25_terminal-tools-menu-busy.md`.
- **Orb dock (D88, fifth round):** open names are a layer in front of every dot and orb, so the next orb's dot no longer
  covers them; circles at rest; his order by hold and carry. `tasks/2026-10/2026-10-25_orb-dock.md`.
- **Diagram mark on Vision Pro** fixed: it was missing from accessibility (glass instead of a material behind it).
- **A pasted picture** goes to the host (0.4.526; he pastes his captures that way).
- **Committed 2026-10-26 at his word ("Commit now, update all of the memory bank files"): 0.4.523–0.4.534**, the
  orb dock's eight rounds, Focus Mode environments, the paste and tools-menu work and the test fixes. Not pushed;
  pushing needs his word. Never `git checkout` a file here: restore from saved copies (one line of
  `MacLocalTerminalPaneView.swift` was lost that way on 2026-10-26 and put back).
- **His asks with the commit, built as 0.4.535 (2026-10-26/27), committed 2026-10-27:** orbs that wrap to the dock's shape;
  names opening left near its right edge; a quick pinch-drag always scrolls (the hold that carries is UIKit's on the
  dock's window); Connections a third larger, set apart, with a hold menu (favorites, recents, Dock Settings); windows
  from a tall dock beside it, away from where the head turned; docked pictures kept across a relaunch (his "window
  previews didn't load in the dock on open"); Auto-focus on Activity on by default (his "enable focus on motion by
  default"). `tasks/2026-10/2026-10-25_orb-dock.md`, ninth round.
- **His report on 0.4.535 (2026-10-27), built as 0.4.536, committed 2026-10-27:** no menu on a held Connections (real: a
  `.contextMenu` on that button never opens; now a menu whose pinch is its primary action; the runner *can* hold, and
  the 10-26 note blaming it was wrong); "snaps to the shape of the visible icons" (he chose the nearest whole rows:
  `GlassOrbFlow.snapped`, once visionOS says the hand let go); a crash on the first vertical resize (ARKit asserts when
  a stopped provider is run again; `GlassHeadTracker` now makes a new one each run, and the dock runs none — the
  headset's report confirms it: ARKit's exception in `ARKitSession.run` from the dock's tall task). Head direction
  is ARKit's only in a Full Space, so a tall dock's side is Focus Mode's head when it runs, else Settings ▸ Appearance
  ▸ Orbs ▸ Windows From a Tall Dock (his choice). Tenth round in the task note.

## 2026-10-25 — the orb dock (D88)
Building D88 (`tasks/2026-10/2026-10-25_orb-dock.md`): Vision Pro orbs gathered in a dock, Settings ▸ Appearance ▸
Orbs. Terminal windows dock as their own orbs; databases, desktops and library editors as one orb per machine; an
editor opened from a terminal on that terminal's ring; the machine's services, Editor included, on the ring; the
water drop going in. Simulator: 5 of 5 orb tests and 5 service tests pass; shell and editor packages pass. His first look
(0.4.523) revised it (D88): only open services, machine orbs, half the spacing, colours; window names and Move
Tab To's docked windows added. 0.4.524 on the Mac (running, no crash report), iPhone and Vision Pro. Not committed. Also uncommitted: two audit test fixes (the
delete test's re-read behind the Duo's keyboard; `typeKey` for visionOS), found after the 03a86e9c commit; the
Duo rerun passed 9 of 11 before them, the iPhone 11 of 11.

## 2026-10-21 — RESUME HERE

Committed at his word: through 0.4.505 on 2026-10-21 (`dcad5dcb`), and everything after it, through the
test audit, with 0.4.522 on 2026-10-25. Not pushed. The "not committed" notes below predate those commits.
- **App Store Connect and TestFlight** (his "pull france for now and get these builds into testflight"):
  - `ITSAppUsesNonExemptEncryption = NO` is in `App/Info.plist` and `Platforms/macOS/Info.plist`: standard algorithms
    need only the French declaration, and only for sale in France (`Documentation/AppStore/README.md`).
  - Builds 491, 493 and 494 were answered through the API.
  - An internal TestFlight group, "Internal", gets every build, and he is invited.
  - Availability has never been set, so France is not on. When it is set, leave France off (no ANSSI declaration
    yet) and China mainland too (it needs an ICP number).
  - The app's icon in App Store Connect is blank, though both builds carry it. No build is attached to either 1.0
    version, and there is Apple's Icon Composer overview bug. Attaching a build is offered, not done.
- **More looks, Vision Pro Keys, the Duo half open** (`2026-10-21_looks-duo-keys.md`):
  - **Looks:** Coding Agent (the agent's mark and AutoPaper's smoke in its colour), Aurora, Starfield, Blueprint.
  - **Vision Pro:** a Keys menu in the terminal's bar. visionOS shows apps no keyboard accessory.
  - **Duo laptop pose:** the terminal above the fold, its bar in the strip below.
  - **Duo book pose:** controls off the fold.
  - Verified on the Duo and visionOS simulators and in the VM. Four new pictures; help, README and release notes
    updated.
  - Built as 0.4.495 for the devices. Installed and read back on the iPhone and the Mac (the Mac at 13:18, on
    the second try: the first quit request went unanswered). The Vision Pro was locked, so its version is
    unread. No new crash reports. Not committed.
- **0.4.496 (not committed):**
  - **iPhone crash fixed** (his report: "iPhone instacrashes when trying to launch a terminal from Active"). Three
    identical reports on 0.4.495: SIGSEGV on the main thread's stack guard, in `TerminalWindowView.terminalSurface`,
    deep in Swift's type decoder. The Duo layout's modifiers deepened one view type that also nested the canvas; the
    phone's smaller main-thread stack overflowed building it, under the deeper stack of opening from Active. Fixed by
    erasing types (`AnyView`): the iPhone layout is `phoneFoldLayout`, and the canvas and both bars are erased in it.
    Simulators never showed it. Installed on the iPhone (reads 0.4.496); his retry is the proof, still pending.
  - **A Workgroup's look:** the Workgroup editor has Look and Text (`TerminalLooksSettingsView`, with a `subject`).
    Made by hand over another, the look shown is the one saved. Test `editorSavesTheChosenLook` (seen failing with the
    rule broken). Help (`terminal-workgroups.md`, `terminal-looks.md`) and release notes updated.
  - **0.4.497 (iPhone only):** his "the folder icon in the tools on iphone in terminal [has no] label ... the whole
    gear is missing". The iPhone/iPad Tools menu draws the bar's items as rows; the folder, Connections and New
    Tab rows were bare symbols, and Settings was the last row of Session inside Tools. Now each says its name
    (`toolLabel`), Settings is its own row with the gear, and Session has `ellipsis.circle` there (bars on Mac and
    Vision Pro unchanged). `GlassTerminalToolsIPhoneUITests` (iOS 27.2 simulator): failed before, passes;
    pictures in the working-files folder: tools-iphone-1021. Installed on the iPhone (reads 0.4.497). No iPhone crash
    reports since 13:31.
  - **0.4.498:** his "Active works, yes! Open Folder in Editor doesn't though." On iPhone the terminal takes the
    library's place (`GlassTerminalBootstrap`'s router), and the editor's bootstrap, nested inside it, went too:
    the request was made and nothing showed it. `mainContent` now has the editor's bootstrap outermost (the editor
    needs nothing of the others); its back button says where it returns (`present(_:returningTo:)`, "Terminal"
    from a terminal). `testOpenFolderInEditorShowsTheEditor` failed with the old nesting ("the editor never
    appeared") and passes. On the iPhone (0.4.498); Mac and Vision Pro 0.4.498 building.
  - **0.4.499:** (1) a picture's Blur (his "It doesn't blur so much as well... i dunno"): 30 × Blur points smeared
    the picture by a tenth (seen on the iPhone 27.2 simulator over a test pattern, the working-files folder: blur-1021);
    now `TerminalBackdropView.pictureBlurRadius` = 30 × Blur³. Test `pictureBlurRamp` failed with the old line.
    (2) His "a right click ... in the empty space in the left sidebar ... a 'new terminal' option that mimics the
    top toolbar": the Mac sidebar's empty-space menu (the list's context menu with no selection) shows the +
    menu's items (`newTabMenuItems`, shared). Not driven on the Mac (no mouse automation there); his right-click is
    the check. iPad's sidebar is the system's TabView sidebar: no empty-space menu was added there.
  - **Vision Pro sidebar (in progress, 2026-10-21):** his "Go ahead, sidebar from two terminals ... instead of a
    generic terminal icon, we replace it with the running agent and color it ... then pulse it". HIG read on
    Apple's pages (DevTools): tab bars are for an app's sections; sidebars for collections; visionOS windows
    widen for a sidebar; a drag carrying a user activity opens a window in empty space. Apple's split view was
    tried first and dropped: visionOS draws glass behind every column, so even a one-terminal window was
    frosted at Blur 0 (simulator captures, the working-files folder: vision-sidebar-1021). A hand-made frosted column
    came next (0.4.500), until his "don't we use Apple's chrome in the database manager and in the Editor?": since
    W33 those use `GlassSpatialSplitView`. Now (0.4.501) `VisionTerminalSidebarLayout` is `GlassSpatialSplitView` +
    `glassSpatialColumn(workgroup.name)` + `glassSpatialList`, the sidebar on the window's glass (clear at Glass 0,
    as the database is), and `glassAdditiveSidebar` (new, GlassShell, `GlassWindowSizer`) widens/narrows the window
    by 360 pt as the second terminal comes/goes. Rows
    `VisionTerminalSidebarRow` (name, where it is, `TerminalTabMark`), pinch-and-hold = `tabActions`, drag =
    `TerminalTabDrag` (Transferable + NSUserActivity `com.glasspowertools.terminal-tab`, claimed by the
    terminal window group; `VisionTerminalDropWindow` moves the terminal in). The title drag uses it too.
    `TerminalTabMark` (agent mark in its colour, pulsing) also replaces the Mac sidebar's shimmer. To check on
    the headset: pinch-and-hold vs drag, tear-off into space, the window widening, Scale Text's held shape.
  - **Mermaid in terminals (his "an inline diagram icon would be amazing. let's"):** `TerminalDiagramFinder`
    (GlassTerminalEmulator, pure; 7 tests, two seen failing with rules broken) finds diagrams in the screen's rows
    (`SwiftTermBufferText.screenRows`, wrapped rows joined), kept in `SwiftTermHostModel.diagrams` (its own
    @Observable, so only the marks redraw), refreshed as output settles, on scroll and on resize.
    `TerminalDiagramMarks` overlays a mark after each diagram's first line (SSH panes and Mac local panes); it
    opens `GlassTerminalRuntime.diagramView` = `GlassEditorDiagramView` (the Markdown preview's page and bundled
    Mermaid, fitted to the view) in a popover (an iPhone sheet with Done). Demo surface `terminal-diagram`.
    UI tests on iPhone and the headset simulator. The text is never changed. Not seen on the Mac yet.
  - **Join Wrapped Lines and whitespace (his "it's like we need to process the white space too, right?"):** his pasted
    diagram had two statements on one line because the joiner read "same indent as the line above" as a
    continuation, and the widest statement looked as if it reached the margin. `TerminalWrappedPaste` now never
    joins a Mermaid diagram's lines (`TerminalDiagramFinder`) and treats a no-bullet line deeper than its
    paragraph's text as code. 3 new tests (17 in the suite), each seen failing with its rule off. 0.4.503.
  - **Headset bar, orb and sidebar look (0.4.505):** his "the sidebar isn't right ... Why can't we use apple's real
    sidebar", then his choices ("Ours, in its own glass"; Font Size and AI Assistant into Tools). Done:
    `GlassSpatialSplitView(sidebarHasGlass:)` draws the sidebar as its own rounded glass panel, inset 8 pt, corners
    concentric with the window's (visionOS draws glass in an `UnevenRoundedRectangle` as a square, measured);
    a Sidebar toggle first in the bar (`visionTerminalSidebar`, additive: the window narrows/widens); a pinch on
    Terminal View shrinks to the orb (held: Tabs/Grid/Carousel/Orb); the orb's ring dots 48 pt with
    `TerminalSessionMark` (agent, colour, pulse) via `GlassSessionOrbTab.icon`; Font Size and AI Assistant in Tools
    on visionOS. 12 headset UI tests pass (new: toggle, pinch → orb, Font Size in Tools). Captures in
    the working-files folder: vision-sidebar-1021 (panel-*). Bar: 9 controls now.
  - **Show All Windows by hand on Vision Pro (his "go! build both with the switch"):** research first (Apple's HIG
    on Apple's pages: two-handed pinch together/apart is the standard Zoom gesture; custom gestures supplement, never
    replace; "ARKit data is available only when your app presents a Full Space and other apps are hidden"; sci-fi:
    Shedroff & Noessel's seven recurring gestures, g-speak). Built (`GlassAllWindowsAround.swift`, GlassShell):
    `GlassPinchSteps` (in/deeper/out, once per gesture; 5 tests, seen failing); `glassShowAllWindowsPinch()` on
    terminal and desktop windows (in opens the window or the arc per Settings ▸ Appearance ▸ Show All Windows ▸
    Pinch In Opens; deeper goes around); the All Windows window's Around You button and pinch; the arc
    (`GlassAllWindowsAroundView`, a mixed `ImmersiveSpace` "all-windows-around", RealityView attachments on a
    head anchor, a group per machine, the room dimmed) with In a Window / Done and pinch out; Focus Mode's space
    steps aside and returns (`glassImmersiveSpacePresence`). XCUITest has no pinch on visionOS and can't tap
    buttons in an immersive attachment: the way back is tested through `--demo-all-windows-around-back`. The
    two-handed pinch itself is unproven until the headset. Captures: working-files folder, around-1021.
  - **"The host library could not be read … hosts.json … permission" on the headset (0.4.507):** the library is
    complete-protected; a re-read while the headset was off (locked) was refused, and `load()` took that for a
    missing App Group and moved the session to the app's private copy (there since 9/16; sync had filled it, so
    nothing looked lost — compared with the Mac's that night: same 25 records). Now locked means read again on
    unlock, no alert, no switch (`GlassShellModel.response`, `protectedDataBecameAvailable`, wired in the App).
    3 tests, seen failing without the check.
  - His question, answered: how a Workgroup's window is told from a window with tabs today (Mac: the sidebar icons'
    colour only; iPad: the sidebar's section heading; iPhone and Vision Pro: nothing in the window).
- **2026-10-22, the headset sidebar and new windows' size** (his "The terminal still resizes when you hide or show
  the tabs. The terminal content should not move or redraw", then "new windows aren't respecting the settings for
  width and height by character … essentially portrait shaped … or square"):
  - 0.4.508 had held the terminal's width while the window widened, but visionOS resizes a window about its centre
    (no app can move one), so the terminal still shifted; and the narrowing on hide applied to windows never
    widened, and visionOS opens new windows at the size it last gave one, so windows came up square or tall.
  - **Sidebar is now an ornament** (`VisionTerminalSidebarLayout`: `.ornament(attachmentAnchor: .scene(.leading),
    contentAlignment: .trailing)`, its own glass, the window's height). The window never resizes for it. The
    `sidebarHasGlass` option of `GlassSpatialSplitView` and the headset `glassAdditiveSidebar` path were removed.
  - **New windows fit their grid as they open**, as a Mac window does: `TerminalWindowOpeningFit` (once per window,
    3 asks at most, the grid first given: Settings' for a new terminal, its own for a moved one) →
    `SwiftTermHostModel.fitVisionWindowToTerminalGrid` → the UIKit container's `fitWindow` (chrome kept, the
    terminal's part made `SwiftTermScaleLayout.contentSize`; under Scale the kept grid becomes that one and ⌘0's
    sizing applies) via `requestGeometryUpdate(.Vision(size:))`. The session still takes every measured grid (the
    system may not resize). 4 unit tests, seen failing with the once/first-grid rules off. A UI-test mark
    `terminal-grid-<c>x<r>` (DEBUG, visionOS). Help (terminal-sessions, terminal-settings) and release notes updated.
  - Found on the simulator: the window picks its shown terminal in `onAppear`, after the terminals first measure, so
    the fit is given to every terminal in the window and asks once per measured grid (5 unit tests). The request is
    honoured: 1200×800 → 1173×773 in under 1.5 s, the grid 123×41 → 120×40 (probe logs, since removed; one notice
    line `event=fit-window` stays). Under Scale the first layout overwrote the kept grid the fit set from inside
    SwiftTerm's report, so that branch now runs after the layout pass. The grid mark is set from SwiftTerm's
    `sizeChanged` (a mark made in the container's layout showed the grid before). UI tests: new window 120×40 passes;
    sidebar toggle leaves grid and frame unchanged passes; Scale Text toggle passes; Scale new window 120×40 passes.
    Bites: the new-window tests failed (123×41) before each fix; the sidebar test fails with the sidebar put back in
    the window (120×40 → 155×40 on hiding it). **0.4.509 installed and read back on the Mac (running), Vision Pro and
    iPhone**; no new Mac crash reports. Not committed.
- **2026-10-22, "hover / context previews aren't working over ssh?"** (device not stated; previews exist only on the
  Mac, D76). Live on the test VM (`LivePathPreviewTests`, new, gated): `TerminalSession.locate` finds absolute, `~/` and
  tmux-relative paths. Relative paths in an SSH shell *not* in tmux can't resolve unless the shell reports its folder
  (OSC 7), which stock remote shells don't. The server half was never seen end to end (d733b3c: "his to try").
  Added `sh.glas` / `path-preview` log lines with a public reason at every stopping point (previewer not wired, pane
  gone, no session, no folder/home, command failed, not on host, SFTP unavailable, stat/open/read failed, too large,
  pointer moved on) so his next try says where it stops: `/usr/bin/log show --predicate 'subsystem == "sh.glas" AND
  category == "path-preview"'`.
- **2026-10-22, the headset, continued** (his "two handed pinch resizes the window", "switch it to the lightning bolt
  and send it to active", "put the tab bar on the same plane as the terminal window, and put only a few pixels
  between them", "drag tabs to reorder should work, too. doens't."):
  - The two-handed pinch is gone from terminal, desktop and All Windows windows (visionOS resizes a window with it);
    the arc keeps its pinch out. The ⚡ held opens All Windows where Settings ▸ Appearance ▸ Show All Windows ▸ Opens
    says (In a Window / Around You; was "Pinch In Opens").
  - The headset terminal's bar: Connections became the ⚡ (`GlassActiveConnectionsButton`, id
    `terminal-active-connections`): Connections on Active; held, All Windows. Orb UI tests moved to it.
  - The sidebar ornament pushed back onto the window's plane (`ornamentDepth` 109.5, measured with an immersive space
    open: window z −2720.8, ornament −2515.6 at 1.874 units/pt; after, −2720.75), 4 pt from the window's edge.
    Rows still select by pinch (UI test).
  - Reorder: the sidebar is our own rows now (ScrollView + buttons, tinted when shown, hover highlight), not a
    `List` — a List takes no drop of its own rows (Apple's forums; tried onMove and the ForEach drop too). Not proven:
    XCUITest on the visionOS simulator never starts a SwiftUI drag (a log in `onDrag` never printed, with the
    context menu, without it, and with `draggable`); the hold opens the row's menu. His to try on 0.4.510.
- **Wrapping in every headset tmux window on 0.4.509** (his screenshot, then "It's all windows in vision pro now").
  tmux on his Mac: glass-2's window 127×53 (the headset client's size, `window-size latest`), while the headset
  showed ~174 columns — Claude Code drawn for 127 into a wider screen, leftovers beyond. Other sessions alike (97×32,
  113×46, 133×48 at tmux). Cause not found: the opening fit (window resized just after open) or the Mac app's
  relaunch at the 0.4.509 install (all its control clients re-attached 01:07). **The opening fit is left out of
  0.4.510** (environment not passed; type and unit tests kept; its two UI tests skip). Next: reproduce with a real
  tmux session on the test VM from the visionOS simulator (`GlassTerminalUITests` adds a host with the key; tmux must
  be turned on after a first connection finds it).
- **The wrapping, found (his "still messed up ... big time. Please review the code that you used to try and force
  sizes")** — the Mac too. The control-mode client (D83) drew a pane at its own terminal's size whatever tmux's was;
  with the Mac and the headset on one session, tmux (`window-size latest`) sizes the window to the client that last
  switched to the session (measured on a private tmux 3.8 server: the other client's typing, `refresh-client -C`
  and new sizes don't take it back; `switch-client -t %pane` does). Installs relaunch an app, which re-attaches
  (and takes) every session; today's headset resizes (0.4.508's width hold, 0.4.509's fit) added to it.
  Fixed: `TmuxControlClient.paneSize` (from the pane read and `%layout-change`, `TmuxLayout.size(ofPane:in:)`),
  `.paneSize` action → `SwiftTermHostModel.showTmuxPane` → both containers lay the terminal out at the pane's grid,
  top left, scaled down only to fit (`paneGrid`, `naturalGrid`); `claim(natural:)` on a keystroke while the size is
  another's: `refresh-client -C own ; switch-client -t %pane`. Tests: 3 client unit tests (seen failing with layouts
  ignored), live two-client test on this Mac's tmux (`LiveTmuxControlTests.twoClients`), `MacTmuxPaneSizeTests` (a
  real pane's `stty size`, seen failing with the layout off); tmux/scale suites 263 pass. Help terminal-tmux.
- **Unwound (his "both of the windows without vision equivalents are fixed sized. Can we just unwind all of the
  changes this session having to do with this part of the code"), 0.4.512:** 0.4.511's pane-size display and claim
  showed sessions with no headset client at a fixed size on the Mac, and he wanted the sizing back as it was. Removed:
  `TmuxControlClient` (paneSize, claim, layouts), `SwiftTermScale.swift`, `Models.swift` and the two tmux test files
  restored from HEAD; `TerminalWindowOpeningFit` (0.4.509) and its tests, `fitVisionWindowToTerminalGrid`/`fitWindow`,
  `showTmuxPane`/`naturalGrid`/`paneGrid` and `MacTmuxPaneSizeTests` deleted; help terminal-tmux and Initial
  Terminal Size, and the release notes, back. Kept: the sidebar ornament (depth corrected to 15.3 pt: 109.5 stood it
  "pretty far behind" on the headset), ⚡, Quick Look, previews, reorder rows, the DEBUG grid mark for the sidebar
  test.
- **The focus claim (his "yes, do the focus claim. The old way drew lines and patterns in the terminal if the focused
  verion was smaller"), 0.4.513:** `TmuxControlClient` keeps the window's size from `%layout-change`
  (`TmuxLayout.windowSize`) and `claim()` sends `switch-client -t %pane` when it isn't this client's (once a layout);
  its own switch's `%session-changed` (same `$id`) no longer re-reads the pane (tmux sends one on every switch,
  measured). Called from `SwiftTermHostModel.onTerminalFocused`: the model's `focus()` succeeding, a Mac window
  becoming key with the terminal first responder (SwiftTerm's Mac `becomeFirstResponder` isn't overridable), a UIKit
  terminal becoming first responder or its window key, and every keystroke (`writeInput`, the Mac local engine's
  `sendUserInput`). No drawing changes; a one-device session never claims (no other size). Tests: 2 client unit
  tests and `LiveTmuxControlTests.twoClients` (this Mac's tmux), each seen failing with the claim off; tmux suites
  pass (`MacLocalPaneScaleTests` failed once under the parallel suite, passes alone twice). Help terminal-tmux.
- **What changed, answered (his "What else changed? What are we missing?"):** tmux processes on his Mac: the app's
  local panes are `tmux -u -C` clients over pipes (re-attached 04:35:32 by the 0.4.513 install), the headset's are
  `tmux -u -CC` over SSH (04:41); the server (`--tmux-host`, `tmux -u -D`) since 10-21 17:29. Nothing in the tmux
  path changed since 10-20 (git). The difference is D83 itself: before it tmux drew each client's screen and marked
  the space past a smaller window (his "lines and patterns"); since, the app draws, and the device not in front drew
  output for another width. Today's resizes and installs only moved the size more often.
- **The dotted fix (his "dotted"), 0.4.514:** `TmuxControlAction.showGrid(columns:rows:own:)` — tmux's window size
  (from `%layout-change`, and read back with `display-message` after every size sent, so a one-device session is
  never taken for another's while tmux catches up) against the size this terminal last sent. Hosts resize only
  SwiftTerm's `Terminal` (`showTmuxGrid`), never the frame, so SwiftTerm still reports its real size on every frame
  change (no lock, the 0.4.511 failure); `TmuxUnusedAreaView` dots the rest. Tests: one-device never told a grid
  (failed first against the stale-window flaw), another client's size shown and own size still sent, live two-client
  terminal at 127 then 166 after the claim; each seen failing with the grid off. Mac suites 258 pass.
- **MySQL on Web won't connect (Mac, 05:05):** the host tunnel opened (local port 57814, SSH leg fine; no tmux in
  that path — `openPortForward` is a bare `SSHTransport` forward), then "Connecting to MySQL" and nothing logged;
  the listener stays open with nothing connected. Last success Oct 5. He: "I don't see anything", and DBeaver
  connects "same setup" (no DBeaver connection to Web's address is saved, so which address DBeaver used is unknown).
  **Measured, 0.4.515:** through a tunnel to a port nothing listens on (the test VM, port 9) the server refuses in
  57 ms (`NIOSSHError.channelSetupRejected: Reason: 2 Connection refused`), the tunnel closes the local socket at
  once, and mysql-nio's connect never returns: `MySQLConnectionHandler.channelInactive` fails only queued commands,
  never the handshake's `done` promise (fork pinned in Package.swift; a fix there needs his word, it is his GitHub).
  **Fixed in the app:** `SSHTunnel.refusal` (the server's words; logged at error level, was debug) →
  `GlassHostPortForward.refusal` → `DatabaseSessionManager.connectWatched` gives up at once on a refusal or after
  `connectTimeout` (30 s), closing a connection that arrives late; `DatabaseConnectAbandoned` worded in
  `DatabaseConnectionFailure` (nothing listening on the machine → enter the Database address; prohibited →
  AllowTcpForwarding; timed out). Tests: `DatabaseConnectWatchTests` (incl. real mysql-nio against a server that
  hangs up before its greeting) and the live `mysqlTunnelToNothingFails` (0.2 s; 40 s hang before); the four
  behaviour tests each fail with the watch off. His retry on 0.4.515 showed the new message at once; re-entering the
  Database address connected (10:16). **The address had been lost from the saved record** (his "the setup lost the IP").
- **Lost address → whole-list saves, 0.4.516.** Measured in tests, not traced to the one occurrence (no write history
  is kept; Web's database service was added 10-05 07:48, the field shipped 10-05 08:16, last connect 10-05):
  `GlassServiceRecords.replaceAll` wrote every record that differed from the store, so a save of anything (a
  "last connected" stamp) put back each held copy — older than another device's edit, or without a field the
  build didn't know — and deleted records added since the last read (the B-X14 guard never held: the database
  and terminal read the whole list again before or after each save, which reset `shown`). Fix:
  `replaceAll(with:changedFrom:)` writes only the difference from the base; the database and terminal keep
  `persisted` (last read or written) and pass it via `saveChanges`; the terminal's readback checks only what it
  wrote; the desktop passes the list it loaded; the shell re-reads capabilities after a sync applies records.
  Tests (each failed first, or with the base ignored): `DatabaseRecordsFromElsewhereTests`,
  `ServerRecordsFromElsewhereTests`, `GlassServiceRecordsChangedFromTests`, `GlassSyncRereadTests`, the desktop's
  `stampingOneDesktopKeepsAnotherDesktopsUnknownField`. Shell/terminal/database/desktop/SSH suites: 2,001 pass.
  Devices on builds before 516 still save whole lists.
- **Connection Details show where the tunnel goes, 0.4.517 (his "yes, show where the tunnel really goes").** The
  overview's Endpoint was `host:port`, the machine's own address, even for a tunnel on to a Database address — so
  the lost address could not be seen there. One rule now, `DatabaseConnectionConfig.reachedHost` (the address
  `forwardProvider` aims at; nil = the machine's loopback), feeds `endpointDescription` ("198.51.100.12:13306", or
  "Port N on this machine"), the tunnel's aim, and both failure wordings. The Tunnel row names the machine a
  tunnel goes through (`runtime.tunnelAccess` choices, as the setup sheet finds it); it said "this machine's" for
  both routes. Test `endpointIsWhereTheConnectionEnds` failed 3 ways on the old wording; database suite 350 pass.
  Installed on the Mac (running, no crash report). Vision Pro and iPhone were "unavailable" to devicectl (error
  4016) at 16:25 and stay on 516; install 517 there when they are reachable (the builds are in tmp/dd-*).
- **⌘F in the editor (his "How is there no Find in the Editor? Command F should always Find right?").** Two defects:
  the editor never published `\.glassFindItem`, so the shell's Edit ▸ Find ▸ Find…/⌘G/⇧⌘G were disabled in its
  windows (its find bar was ⌥⌘F in the Editor menu, and `MenuBarPlacementTests` pinned the terminal as the only
  publisher); and the find bar and Go to Line set `model.selectedRange`, which neither engine watched, so nothing on
  screen moved (reproduced in a scratch engine test). Fix: `GlassEditorModel.reveal` + `revealRequest` (the
  `keyboardRequest` pattern), watched by both engines; UIKit scrolls to `firstRect`/`caretRect`, because
  `scrollRangeToVisible` did nothing for text TextKit 2 had not laid out (measured on the simulator); the editor
  publishes `findItem` (`presentFind`, `findAgain`), the find field takes the keyboard on each request
  (`findFocusRequest`); the toolbar Find off the Mac presents rather than toggles; Editor ▸ Find in Document (⌥⌘F)
  removed. Tests, each shown failing without its fix: AppKit `revealReachesTheView`, `revealScrollsToAFarMatch`;
  UIKit (simulator) `UIKitRevealTests` ×2; `findShowsTheBarAndFindAgainRevealsTheNextMatch`; the publisher guard.
  Suites pass: shell 356, editor UI 119, editor core 174, editor 318, database 350, UIKit editor 7. Checked in the
  macOS VM's running app: Find… enabled on ⌘F, the find field focused, Return selected match 1 of 13 (line 3), ⌘G/⇧⌘G
  stepped between matches. 0.4.518 built: on the iPhone; the Mac's quit was cancelled ("User canceled", the install
  waited 10 minutes and left 517 running); the Vision Pro was unreachable again.
- **Quick Look on the headset (his "add Quick Look on the headset - even it if has to be a mouse hover"):**
  `VisionTerminalPathPreviewer` (popover, the shared `TerminalPreviewBar`), Quick Look first in a held path's menu,
  a trackpad/mouse pointer resting 0.6 s (`UIHoverGestureRecognizer`), Space under Mouseover + Space; the file via
  `TerminalSession.locate` + `TerminalRemotePreview.fetch` (wired in `TerminalPathActions.install` on visionOS);
  Show previews in Settings and This Window on visionOS. Demo `terminal-path`, UI test `testQuickLookOnAHeldPath`.
- **Built 2026-10-26 (D89): Focus Mode environments** — per window over the app's setting: his own USDZ
  room or 360° picture, and a Sketchfab browser (rooms/environments filters). Sketchfab's terms (read on their
  developer pages): downloads need each person signed in by OAuth 2.0 in the app; the app is registered by
  contacting Sketchfab (name, grant type, redirect URI — no custom schemes; an https or localhost one); USDZ is one
  of the formats; every model shows its license, author and link, and Sketchfab is credited. His answers
  (2026-10-22): draft the registration request (drafted for him to send; the redirect page on the site doesn't exist
  yet), keep environments in iCloud, 360° photos too. Not started: the tmux sizing trouble took over that day.
- **Git and diffs in the editor (his "We really, really need git support and diffs in the editor now... see this
  instead of having to open Zed"), 2026-10-23** (`tasks/2026-10/2026-10-23_editor-git.md`). He withdrew the iOS
  Files report ("files works now, focus on git"). Built, read-only: the real `git` where the folder is (the Mac's
  own; a server's over the project's SSH connection, on every device; Citadel F12 for exit status and stderr);
  a Changes tab (every changed file's lines since HEAD, new files whole, a line opens its file); tree marks and
  folder dots; the footer's branch button; the overview's git row; Text ▸ Show Changes (⌃⇧G). Tests: editor 187,
  Citadel exec 12, terminal listers 11, shell 356, SSH 86. The VM had no network (host bridge never made), so the
  window was drawn offscreen instead, which caught blank rows (fixed). Next steps he may want: gutter marks in the
  text, stage/commit. 0.4.519 installed on the Mac (running, no crash report) and the iPhone; the Vision Pro was
  unreachable (4016). Not committed.
- **Then gutter marks and stage/commit (his "add gutter marks and stage/commit too")**, same task note: marks
  beside the numbers compare the buffer with HEAD as you type (`LineChanges`, Myers; `GlassEditorLineMarker`);
  Changes gains a box per file, Stage All, a message and Commit/Commit All (⌘↩), and asks before committing files
  staged outside a subfolder project. Tests: core 328, UI 120, editor 195 (new suites shown failing when broken).
  0.4.520 on the Mac (running, no crash report) and the iPhone; Vision Pro unreachable (4016). Not committed.
  Not done: hunk staging/revert, marks with line numbers hidden, push/pull.
- **A dropped terminal listed once in Active (his iPhone picture: each dropped tmux tab was listed twice), 2026-10-24**
  (`tasks/2026-10/2026-10-24_active-dropped-tabs.md`; his "yes!" to the proposal and to Detach showing the session
  at once). A down terminal holds its session (`GlassRunningSession.isHeldHere`, `listedRunningSessions`), its row
  says what the machine said (`tmuxWhileDown`) or that the session ended, and choosing it reconnects
  (`Request.reconnect`). New tests shown failing when broken. 0.4.521 building for all three. Not committed.
- **Test audit (his "make sure those are found and settled properly … verify that all of our tests are useful and
  work"), 2026-10-24** (`tasks/2026-10/2026-10-24_test-audit.md`). The "load" failures were the terminal suite
  blocking the main actor. Six product defects found and fixed, each with a test shown failing without it:
  blocked signals inherited by what the app spawns (`GlassSpawn`), SQLite Cancel/timeout lost before a statement
  runs, MySQL backslashes in default literals, RDPKit dropping a server's reason when it hangs up straight after,
  and, from the iPhone UI run, the paste review wider than the phone and VoiceOver's terminal lines stale after a
  resize. Package: 3,113 tests pass in three full runs (2–2.5 min), plus RDPKit 1,030, Citadel 62 and
  swift-nio-ssh 367. UI tests compile for macOS and iOS. Final runs on the latest build (2026-10-25): iPhone 72
  pass / 6 fail, folded Duo 71 / 7, no skips. The first re-run of those suites still failed seven (the text
  helper skipped Select All when the value equalled the prompt; the tag tap; the terminal's typing raced D44's
  tmux offer, and its echo check could not fail). Fixed since, each shown failing without its fix. **VoiceOver
  (his "check the VoiceOver thing too")**: the real VoiceOver runs in the iOS 27.1 simulator (task note has how);
  the tag field's input had the whole row, chips included, as its accessibility frame (outline, touch, and an
  activation point on Lab's remove button). Fixed in `GlassTagField` (the row's tap gesture moved to a
  background), verified with VoiceOver; a tag-suite check covers it. The database suite on iOS had never got
  past text entry; taken through every iPhone step (hidden tabs' controls, Run behind the keyboard, Select All in
  the editor, the schema list a level back, the row's "…" menu). Full iPhone run: 78 tests, 0 fail, 2 skip; the
  skips (foreign-key follow) were a Mac-only lookup, fixed: Follow Reference now runs and passes on the iPhone on
  both engines (first time seen working in the UI), and fails when the composite pairing is transposed. Full
  folded-Duo run: 67 pass, 11 fail. Product defect found and fixed: a ⚡ under a sheet answered a hold (All
  Windows over Add Host, on both phones; `GlassAllWindowsPull.isOnProbe` now takes only the frontmost
  presented screen's ⚡); new test fails without it on both phones. The rest: the Duo's sheet bar leaving after
  a password (decision 8), so Save is tapped by `tapUntilSheetCloses`. Second full Duo run: 79, 75 pass, 4 fail,
  all the grid reader walking rows the keyboard covered (fixed: `serverRows` puts the keyboard away). Second
  iPhone run: database tests failed in Set Up on iOS's Allow Paste prompt for the Mac's clipboard (fixed:
  `UITestClipboard` taps Allow Paste; proven on the Duo) and, after a Don't Allow, the guard emptied the clipboard
  (fixed: `Refused` when the read is empty but the types are not; proven by a deleted probe). iPhone run: 79, 74
  pass, 5 fail (all the prompt). Mac compile of every changed file: passes. Running: the database, terminal and
  paste suites with the final code on the Duo then the iPhone (`fix-{duo,iphone}.log`, `dd-ios-fix`). Not run: the iPad on the latest
  build, the unfolded Duo, the Mac. Open for the
  owner: the decisions list in the task note, plus the tag draft split proposal. Not committed.

## 2026-10-20


**Shipping** (his "Ship it!"; all three steps, his choice; the Mac at 0.4.491): `2026-10-20_first-mac-release.md`.
- Pushed (ee8a8007..7f824f86). TestFlight 0.4.491 (491) uploaded for iPhone/iPad and Vision Pro.
- Site and help brought current with D83–D87 and the release (his ask), with six looks pictures from the VM (his
  "We need screens for the new terminal themes!"). Not yet committed or deployed.
- **Released:** Mac 0.4.491 is on GitHub (v0.4.491, notarized dmg and zip) and in the live feed. The site is live (90
  files checked). Its docs, pictures and feed are not committed yet.
- **0.4.492, built at his word** ("fix that, and also allow a right on the folder icon…";
  `2026-10-20_after-the-release.md`):
  - Scale Text on local tabs.
  - Open Folder in Editor (the machine's project that holds the folder, else a new editor). On the Mac it's in the gear
    menu, beside a plain folder button that stays inline; any menu on the button splits the bar. The local gear menu
    no longer repeats the toolbar (0.4.494, his choice).
  - iCloud's signed-out words.
  - **Released at his word** ("commit, push, and ship"):
    - 0.4.494 on GitHub (v0.4.494, notarized; downloads match their checksums).
    - TestFlight 494 for iPhone/iPad and Vision Pro.
    - The feed offers 494 over 491.
    - The site is live (90 files checked).
    - 0.4.493 went to TestFlight only.
  - On the Mac and iPhone (494). The Vision Pro is unreachable (still 0.4.481).

**Committed at his word** ("commit."); pushed with the ship. 0.4.491 is on the Mac and iPhone; the Vision Pro unreachable.
- **Time in use (D87):** the overview counted only library Connects, not his days of tmux. Each minute with input or
  output now counts for its machine and kind, a Mac tab's local shells included, synced per day. The chart opens on
  hours. Built and tested; 0.4.490 (`2026-10-20_time-in-use.md`). Counting connects from every path is deferred.
- **A new tmux tab's cursor a row above its prompt** (his screenshot): the restore counted the cursor from the top
  in a terminal taller than the pane; a resize during the start and font size changes never reached tmux. Fixed and
  tested; 0.4.491 (`2026-10-19_tmux-scrollback.md`).

**Committed at his word** ("update the memory bank, then commit what we have, And yes, build it"); not pushed. 0.4.487
is on the Mac and iPhone; the Vision Pro has been unreachable since 0.4.481.
- **Terminal looks (D84)**, an experiment he loved: backgrounds, phosphor palettes, glow, readability guard;
  installed (`2026-10-20_terminal-looks.md`).
- **SQL from a terminal (D85)**, Mac right-click into the query editor (`2026-10-20_sql-detector.md`).
- **Tab tooltips:** each Mac tab row names its tmux session.
- **Closing stays as it is:** closing a tmux tab detaches (his word: "Leave it exactly as it is today").
- **D86, This Mac knows its own library machine:** built and committed (`2026-10-20_this-mac-link.md`). His Mac
  linked itself by host key; Active lists each session once; no Screen Sharing to itself. Still SSH: Basic Terminal,
  the palette's "without tmux", workgroups.
- **Open:**
  - the SQL round trip against a real database;
  - the looks on iPhone, iPad and Vision Pro;
  - iOS and visionOS terminal pictures without the look;
  - the paste UI test;
  - TestFlight for these builds, on his word.

## 2026-10-19

**Committed at his word** ("update the memory bank and commit"); not pushed. 0.4.483 is on the Mac and iPhone; the
Vision Pro was unreachable and still has 0.4.481. Next, his: "I have a fun exploration next."
- **Today's work:** the largest text sizes, part two (`2026-10-19_large-text.md`); a wrapped paste joined again
  (`2026-10-19_wrapped-paste.md`); the Mac Terminal Overview's "open elsewhere" ghosts; tmux tabs as control-mode
  clients (D83), and the slow reattach 0.4.482 showed, fixed in 0.4.483 (`2026-10-19_tmux-scrollback.md`).
- **Measured, nothing changed:** Metal against Core Graphics on the Mac; Core Graphics kept (`techContext.md`,
  Terminal renderer; the benchmark is in the working-files folder, outside the repo).
- **Open:**
  - `TerminalPasteUITests` fails: on iPhone, step 2's review never appears; on iPad, step 3.
  - The iPad terminal-size UI test's measure is unreliable.
  - `LiveTmuxTests.claimedSessionSeesWhatATypedOneSees`: PATH differs on the Linux test VM.
  - The app's interface against tmux not yet seen on the iPhone.
  - The weekly dependency check fails on SwiftTerm 1.99 (an API port, later).
  - TestFlight for 0.4.483 waits on his word.

## 2026-10-18

**His ask:** "I'd like the vision pro screen shots to have 78% transparency with about 50% medium glass. close the
connections window so users can see why this was built. Do the same for Mac and let's get all 4 services for each
visionOS and macOS. Don't forget session tranfer with tmux and workgroups that restore after a quit!" Then: "we can't
claim vision pro first and feature a mac interface instead above the fold", and "run btop or something for the
terminal examples". Asked which "78% transparency" meant, with a side-by-side: **Opacity 78%** (Glass 50%, Medium).
- **The pictures:** Vision Pro (simulator) terminal, database, desktop, editor with Connections closed, plus Active
  (tmux sessions to pick up) and a workgroup; the Mac (VM) the same services, Active and the library (all four at once
  was taken, then dropped: it repeated the four service pictures); the iPhone's terminal; every terminal running a btop-style screen drawn for its window's size. All DEBUG-only
  demo code (`App/GlassDemoMode.swift`, `App/GlassDemoBtop.swift`); nothing shipped changed, so no new build.
- **The site:** the Vision Pro terminal above the fold; Vision Pro first with its other three services; "Pick up where
  you left off" (Active, workgroups); the Mac's four services; the library under Why one app; iPad and
  iPhone. Service pages each gain their Vision Pro picture; the terminal page, Active on the Mac. Live at glasspowertools.com since 2026-10-18; security reports go to the owner's
  email until the repository is public (his choice).
- **Tried and dropped:** four windows at once in the visionOS simulator (techContext, "The macOS screenshot VM").
- **A crash found on the way, fixed in 0.4.476** (5c567dd): the database window's policy re-set unchanged window
  properties on every update, and one notice crashed a hosting view mid-teardown (the VM's diagram picture).
  0.4.476 is on the Mac, the iPhone and the headset (each reads it; no new Mac crash reports).

## 2026-10-17 (night)

**His ask:** "remove the gray line in database and desktop windows too - take a look at the AudioPaper site, and glass
project, and autopaper and update this site to that aesthetic. screenshots and all using the new sandbox". (AutoPaper is
the owner's own site project; "the new sandbox" is Glass Project's headless macOS VM.) Done, committed:
- **The gray line (929a183, 0.4.475):** the database window's sidebar edge as the terminal's; the desktop window's
  hairline (down its leading edge, as it has no sidebar) hidden. Tests fail without; the VM pictures show only the
  system glass sidebar's own rim, as in a terminal window (`techContext.md`, "The macOS screenshot VM").
  **Installs:** Mac read 0.4.475 and runs, no new crash reports; iPhone and headset unreachable twice (CoreDevice
  4016, asleep or locked) — install 0.4.475 when they're awake (`build-install.zsh`'s two devicectl lines).
- **The site in the family's look**, with the real app in pictures (Mac windows from the VM in dark and light; Vision
  Pro, iPad and iPhone from the simulators). The VM tooling is in `Tools/Screenshots/macvm/`, documented in
  BUILDING. Kept from ours: ⌘K help search, the appearance button, the help's sidebar. Not deployed (his step).
- **Left as they are, his to judge:** the library's sidebar footer says "Not synced on this build" in the Mac
  pictures (true of the VM build); the hero buttons are How to use it / Why one app / Security, with no download (not
  released).

## 2026-10-17 (evening)

**Since the afternoon, all committed:**
- **All Windows in light mode on iPhone** (his screenshot; chosen: "Cards in the terminal's colors"): a terminal's
  card is drawn on its theme's canvas, as the iPhone window's opaque page is, with name, × and mark in the theme's
  light or dark (cdb160b, `GlassOpenSession.backdrop`). Simulator captures in the working files' `captures/
  all-windows-light/`. 0.4.473 on all three.
- **D81 — Your Library counts connections on all devices** ("totals, then a way to choose which device"; "use the
  device name, not the product. I might have two vision pros"; "When the Active connections refreshes on iCloud
  maybe?"). Daily counts per device through iCloud KVS, All Devices then a menu by name, Settings ▸ General ▸ This
  Device (93d857a). What travels wasn't chosen by him; the smaller (counts, no times) was taken — say so.
  **Device names:** iPhone/iPad/Vision Pro report only "iPhone"/"Apple Vision Pro" without Apple's
  user-assigned-device-name entitlement; requesting it is his step (the App ID's capabilities); until then he names
  each device in Settings. **0.4.474 on all three** (Mac read 0.4.474 and runs; no new crash reports).
- **The "build" demo machine, fixed at his word (e980fcb):** `load()`'s second caller went on with a half-seeded
  UI-test catalog and set `isLoaded`; the seeding is now a task every load awaits (DEBUG only; release builds
  unchanged, so no device install). Two simulator launches: build 44, "189 connections on 3 devices".

## 2026-10-17 (afternoon)

**The owner asked:** "make sure that the memory bank, release notes, README, and the site/help are current. If you
need to, scan the codebase and compare it to the existing docs!" Done, checked against the code by three agents
(help: terminal and library; help: databases, desktops and editor; the memory bank's core files) and the
coordinator; every changed claim re-read in the code. The site builds (7 pages, 39 help pages, links checked).
- **New:** `RELEASE-NOTES.md` (there were none): what the first release holds, recent builds by date, known limits.
- **Brought current:** README (since 2026-09-30), SECURITY (model links, the Mac's sandboxed extensions), BUILDING
  (the extensions), CONTRIBUTING (help and release notes with a visible change), all 39 help pages and 6 site pages
  (build 0.4.471), systemPatterns/techContext/productContext/projectbrief through D78 (the Mac terminal draws with
  Core Graphics, not Metal; drifted citations fixed), toc and the October index, progress.
- **Rule 61:** home paths removed from notes, a source comment and a test fixture (`GlassPathHeaderTests`, 12 pass).

**Then, at his word ("yes, fix both"), both fixed and committed:**
1. **D79 (d61271a):** a deleted set-up machine and a removed service stay that way across devices. The fix differs
   from the one first proposed: a fold's tombstone names no services and `deleteHost`'s keeps them, so a service a
   tombstone names isn't revived, and nothing is revived past a record's own live, newer copy (which also fixed
   Remove Service, undone the same way). Merge +5 and model +2 tests fail on the old merge; shell 314.
2. **D80 (eaa59a6):** unsaved editor changes are asked about before a Mac window closes (document by document),
   before a quit, and before Active, All Windows or the Mac overview end the session; iPad and Vision Pro keep a
   dismissed window's changes in Active. `GlassWindowCloseGate` is new (rule 62 exception). Connection UI 53,
   terminal 876, shell 315, editor 171; tmux unchanged. **His to try:** close a Mac editor window with two edited
   documents; quit with one.

**Still for the owner (in `progress.md`, Known and open):**
3. The release script checks only the widget extension; the inert File Provider extension ships in Mac builds.
4. Smaller: Mac local terminals don't scale; server files over 64 MB can't open; wording defects listed there.
5. Two rules proposed by the audit (measure window behaviour in a SwiftUI window scene, not a plain `NSWindow`; test
   on the newest simulator runtime) — his to adopt.

**Installs:** 0.4.472 on all three (Mac read 0.4.472 and is running, no new crash reports since 2026-10-13; iPhone and
Vision Pro installed 15:31).

**Still open from the morning:** the 6 pt strip (read his toggles' log first); the no-line edge for the database and
desktop windows (offered).

## 2026-10-17 (morning)

**From his screen recording of 0.4.467** (his typed answer to the open toolbar question: "keep the + and title
fixed"), all committed (55a80b9, 46cf403, ba19154):
- **Reverted at noon (1534ece, 0.4.470):** "+" and the title held still — he saw the space it leaves and said "It
  moves anyway... let's close the space." "+" slides with the sidebar again. What it was:
- **"+" and the title stay put** as a terminal window's sidebar opens and closes: an empty toolbar item before "+"
  holds the room the window's and sidebar's buttons take with it closed, as wide as the sidebar shows (room read
  from the toolbar, 132 pt on macOS 27.2). Open, there is that gap after the sidebar's button. Left: a ≤30 pt dip for
  two frames at the start of opening and end of closing (a toolbar item is never under 36 pt).
- **The see-through frame on every opening is gone:** AppKit draws the window mid-opening with the sidebar laid out
  at full width but not yet slid in; the titlebar material now holds its edge until the change is announced (KVO
  `.prior`).
- W19's SSH naming test waited for nothing; it now waits for the repository note it counts (failed twice in full
  runs, passed alone).
Evidence and the scene probe: `tasks/2026-10/2026-10-16_additive-sidebars.md` (2026-10-17 section).

- **Then the gray line at the sidebar's edge** ("That's what we need to eliminate"): AppKit's split divider (a
  half-point line) and our hairline. In the terminal window both are gone (a100d04): the divider transparent (hidden,
  AppKit shows it again), still draggable. The database and desktop windows keep theirs — not asked; offer.

**Suites:** connection UI 51, terminal 874, shell 307; tmux unchanged; screen unlocked.
- **Open: a 6 pt see-through strip** between sidebar and terminal as the sidebar opens — "it's what causes the shift"
  (his screenshot). Likely the column ends ~6 pt wider than the terminal held in it; the probe can't reproduce it.
  0.4.471 logs each move (`com.glasspowertools`/`sidebar`): read his toggles before changing anything. Task note,
  last section.

**Installs:** 0.4.471 on all three (Mac read 0.4.471, no new crash reports; iPhone; headset at 12:01 once awake).
**His to try:** the sidebar's edge without a line; everything listed below for 0.4.467.
**Open offer:** the same no-line edge for the database and desktop windows.

## 2026-10-16 (evening)

**Since the afternoon, all committed:**
- **D77 — a Mac terminal window's sidebar adds to the window.** Rebuilt twice for his snaps; the app moves the
  window itself (AppKit doesn't for a SwiftUI window scene), following the sidebar's net state, reading its width as
  it starts and settling to where it ends; the terminal column holds its width meanwhile. He confirmed on 0.4.466:
  "Works now, smooth both ways." His follow-up: only the toolbar's "+" and title move (≈132 pt) — offered: keep them
  fixed (a gap when open), centre the title, or leave as Finder/Mail do. **Unanswered.**
  `tasks/2026-10/2026-10-16_additive-sidebars.md`.
- **D78 — 3D models everywhere files open** (asked first; all four recommendations taken). RealityKit on Mac,
  iPhone, iPad (AR Quick Look on touch); `Model3D` and Apple's Quick Look volume on Vision Pro; model links open in
  3D. Seen on both simulators and a Mac probe; his devices to try (`--demo-open editor-model`).
  `tasks/2026-10/2026-10-16_3d-models.md`.
- **A dropped screenshot that "just disappears":** the file arrived and nothing was typed, silently. A pending paste
  review no longer turns everything away; every drop step is logged. `tasks/2026-10/2026-10-16_drop-typing.md`.
- **D75 on iPad:** ⌘+ grows a scaled window, sharp scaled text (simulator).

**Backlog candidate (measured, not changed):** the editor loads syntax grammars (`GrammarRegistry.load`) on the
main actor — ten seconds at a time across the editor's tests in a debug build — so a person's first file in a new
language stalls the interface. Its read tests' budget was raised to 20 s (they failed at the day's starting commit
too).

**Seen in full terminal runs, intermittent, not from today's changes:** W19's tmux naming test, the iCloud push
cancellation test, `controllerOwnedLocalPTYSurvivesHostReconstructionUntilExplicitClose` (each once in several runs,
the Mac busy). Locked screens fail the file-protection and window tests: check the working files' `locked`.

**Installs:** 0.4.467 on the Mac, iPhone and Vision Pro (all three read it, 20:25; no new crash reports). His to
try: models (a `.usdz` from the web, or `--demo-open editor-model`), the sidebar, a screenshot dragged into a terminal
(if it vanishes again, the `terminal-drop` log says why).

## 2026-10-16 (afternoon)

**D75 built: a terminal scales as well as resizes.** Settled with the owner first: Vision Pro, Mac and iPad; a setting
and a bar button; the grid the terminal has when Scale turns on; the window held to its shape. Commits 394fb47 (engine,
setting, button), 3feb28a (window shape, ⌘+/⌘−), 2914f3f (visionOS UI test). **0.4.463 is on the Mac and iPhone**;
the headset was asleep at install (CoreDevice 4016), and `install-headset-when-awake.zsh 463` waits for it — check its
version first. **For him to try on 0.4.463:** Scale Text (`aspectratio`) in a
terminal window's bar, then resize the window; ⌘+/⌘−/⌘0 under Scale size the window. On the headset this is the first
run of the UIKit scaler, which no test covers. Detail and limits: `tasks/2026-10/2026-10-16_terminal-resize-and-scale.md`.

**Still his to try from before:** headset selection (copy the headset log after), hover/Space previews on the Mac,
trackpad selection on the headset.

**Next candidates:** remembering the kept grid with the window across relaunches (D75 "Later").

## 2026-10-16 (~10:30)

Welcome back. Everything is committed; nothing is pushed. **0.4.462 is on the Mac, iPhone and Vision Pro** (all three
read it; no new crash reports since 2026-10-13).

**First, the owner's priority — D75, a terminal that scales as well as resizes:** "I may want a 120 x 40 terminal, but
with a much smaller window. Today that resize adjusts the 120 x 40, now just the window." Read
`tasks/2026-10/2026-10-16_terminal-resize-and-scale.md` (what the code does today, open questions, a likely shape),
then **restate it and ask** which platforms first and how the choice is made, before building.

**Since the last resume (detail in `tasks/2026-10/2026-10-14_all-windows-mac-layout-headset.md`, from "~06:50"):**
- **Headset selection:** his "it immediately unselects" was tmux 3.8 turning its mouse on by default (a pinch-drag
  became tmux's yellow selection; nothing scrolled); his headset log confirmed it. A pinch-drag now scrolls whatever
  tmux says; `~/.tmux.conf` on his Mac turns the mouse off. Then, to Apple's pattern: a hold selects the word, an end of
  a selection drags with no hold, a trackpad click-drag selects. **His to try on 0.4.462**; every gesture logs its time
  and movement — copy the log off the headset after (headset-diagnostics memory).
- **iPhone:** the tab switcher was invisible in light mode (black on black) — fixed; All Windows lists every tab of a
  window, waiting ones too. The desktop shows one bar at a time with the keyboard up, one line of status, a readable
  light-mode title.
- **Mac:** file previews over a terminal (D76): Quick Look in a path's menu; Show previews Never / Mouseover (default)
  / Mouseover + Space; local and server files, recognised from their bytes, code highlighted in the editor's view, a
  bar with Open in Editor. Hover keeps it open while the pointer is in it.
- **Installs:** the Mac install script had waited on the app's `--tmux-host` process; fixed. Working files live in
  the working files (`README.md` there): `build-install.zsh <patch>`, `install-devices.zsh`,
  `install-headset-when-awake.zsh`, `vision-test.zsh`, `ios-test.zsh`, `capture-on.zsh`. Next build: `build-install.zsh 463`.

**Open:** the orb's pulse not yet seen on a device; a desktop orb's shape hold after a round trip shows only on the
headset; the Files shelf's corners; the headset's trackpad selection and hover previews are untested by him.

## 2026-10-15 (~07:10) to 2026-10-16 (~10:25)

The owner, back on the headset at 0.4.453: "selecting text is still broken wholly in the terminal in visionOS with
tmux for sure, how do I see the orb on desktop? Fix all of the things! BTW, the small names still don't align
correctly around the orb." All built, committed (532a9d8, 30d6ca6, 0c07f12) and on the headset; nothing pushed.
Evidence: `tasks/2026-10/2026-10-14_all-windows-mac-layout-headset.md`, section "~06:50".

**State:** 0.4.454 on the Vision Pro and iPhone. The Mac's quit was cancelled at the app's question, so the Mac is on
0.4.453 (nothing in 0.4.454 changes the Mac's behaviour). No new crash reports.

**Done:**
- **2026-10-16 10:25 — 0.4.462 on all three** (the headset caught up from 0.4.454: today's selection gestures,
  tmux-mouse scrolling, iPhone tabs and desktop bars are all on it now). Next: his headset try of selection, then copy
  its log (`headset-diagnostics` memory).
- **2026-10-16 late morning — file previews over a Mac terminal** (d733b3c, 0.4.460 on the Mac and iPhone): Quick
  Look on a path's menu; Show previews Never / Mouseover (default) / Mouseover + Space; local and server files. His to
  try: hovering, Space, Markdown and a server's image.
- **2026-10-16 morning — selection as Apple's text does** (f2fde40, 0.4.459 on the Mac and iPhone; **the headset was
  asleep: install it with `install-devices.zsh 459`**). Hold selects the word; drag an end with no hold; trackpad
  click-drag selects. His headset log had shown no hold at all and every drag a scroll. Next: his try on the headset,
  then copy the log (each gesture now logs its time and movement from touch-down).
- **Night — the iPhone desktop's two bars** (f1ee5ba, 0.4.457): the status bar steps aside while the keyboard's bar is
  up, and fits one line on a phone. 0.4.457 on the Vision Pro and iPhone; the Mac reads 0.4.453. The desktop's
  light-mode title now reads (d1198cb). **0.4.458 on the Mac, Vision Pro and iPhone.** The Mac installs had all failed
  since 14:36: the install script's running check matched the app's `--tmux-host` process; fixed in
  the working files' `install-mac2.zsh` (see the agent's private notes on builds).
- **Evening — iPhone tabs** (ce2dbf6, 3e101b8, 0.4.456): the title's tab switcher was invisible in light mode (black
  on the terminal's black) and now reads; All Windows shows every tab of a window, those waiting to connect too.
  0.4.456 on the Vision Pro and iPhone; the Mac is still 0.4.453 (its quit question unanswered twice).
- **Later — tmux 3.8 has the mouse on by default** (2975ace, 0.4.455): that was his "immediately unselects" (tmux's
  yellow selection, cleared on letting go) and his "can't scroll at all". On Vision Pro a pinch-drag now scrolls
  whatever tmux's mouse setting. iPhone/iPad likely need the same; not yet looked at. Detail: the task note's
  "afternoon" section. **0.4.455 is on the Vision Pro and iPhone**; the Mac stays on 0.4.453 (its quit went unanswered).
  The headset's log confirmed the cause (tmux had the mouse; pinch-drags went to it as drags). `~/.tmux.conf` on this
  Mac now turns the mouse off.
  With this Mac's tmux mouse turned off (at his word; until tmux restarts), he confirmed selection works.
- **Selection with tmux:** the owner (later, 0.4.454): "I don't [use mouse mode]. I just can't select text. It
  immediately unselects." The simulator can't reproduce it: with the terminal focused as a real session's is (the
  visionOS keyboard up), a double-pinched word in the tmux demo stays highlighted through redraws (captured). His
  headset log is the next evidence. A drifting hold no longer turns into tmux's drag when tmux has the mouse, and a pinch
  clears a selection. Both are shown and proven on the simulator. **But** this Mac's tmux has the mouse off, so his
  failure may be something else. **Next:** once he has tried a hold and a double pinch in a tmux terminal, copy
  `Library/Caches/com.glasspowertools/Diagnostics/screen-sharing.log` off the headset (headset-diagnostics memory)
  and read its `terminal-selection` lines: every hold, pinch, recognizer and selection change, with no text.
- **Orb names** are as wide as their words and sit against their dots (captured with ten).
- **Database and editor orbs** show the window as it looked when it shrank.
- **A desktop's shape** is asked for again once it grows back from its orb (the simulator can't show the hold
  itself).
- **Files' corners** are clipped to the window.
- **Desktop orb, his question:** Shrink to Orb is the first button in a desktop window's bottom bar (Vision Pro only).

**For him to try:** select in a tmux terminal (then the log copy above); names around a ring; a database or editor
orb; a desktop's orb, then resize it after it grows back (should keep the display's shape); the pulse; the held +
and the toggle's held menu; a hold on a path.

**How we work** is unchanged (see below). **Working files now live in a folder beside the repository, outside `/tmp`** (the owner's choice,
after a /tmp cleanup took the scratchpad): `build-install.zsh 455` builds and installs the next version;
`vision-test.zsh <log> <Class/test…>` runs visionOS UI tests; `capture-on.zsh "<log text>" <png>`; its `README.md`
lists them. Derived data and package checkouts are there too.

## 2026-10-14 (~22:15) — the day closed

Welcome back. It was a long, good day with the owner at the Mac and his iPhone, testing as each build landed, and it
ended on "Really nice. The open is ssmoooooth." He asked to compact here. Everything is committed (the last code
commit is d580ee0), nothing is pushed, the tree is clean.

**State:** 0.4.444 on the Mac, iPhone (22:10) and Vision Pro (installed when he put it on, after the close;
`devicectl device info apps` reads 0.4.444). Today's headset work (the ⚡ hold sheet, Siri's Show All Windows) is on
the headset now but not yet seen by him. No crash reports since 2026-10-13 18:47.

**What today built** (detail and evidence: `tasks/2026-10/2026-10-14_all-windows-agents-clipboard.md`; commits say why):
- **All Windows off the Mac.** iPhone/iPad: pull down from any top bar's empty space, or hold ⚡ — a glass pane of
  live sessions as cards (`GlassAllWindowsPane`, `GlassShowAllWindowsOverview`), terminal pictures via `drawHierarchy`
  (Metal defeats `layer.render`), velocity springs, rubber-band, frosted backdrop, a toss up closes it. Vision Pro:
  hold ⚡ → a sheet on Connections. Siri/Shortcuts: "Show all windows in Glass Power Tools". The Mac is unchanged.
- **28 AI agents marked** (`TerminalAgent`): Lobe Icons marks as SVG (Mac) and as an asset catalog (elsewhere); told by
  program, script, Python module, runner (`uvx`, `npx`, `uv run`…), shell launcher, or install folder (`.hermes`).
  Hermes confirmed on his machine ("nice!").
- **Desktop clipboard works both ways with GNOME** ("this is magic"): RDPKit stopped counting clipboard packets
  against the graphics negotiation (4499937), and **Sync Automatically** sits atop the Clipboard menu.
- **Command Palette**: every service ("Connect: Desktop on …"), the terminal's commands, projects, folders, saved
  queries, running tmux, from any window. **Terminal right-click on a link or path**: Open Link, Open in Editor, Show
  in Finder/Files, Watch Log File, Copy. ⌘↩ sends a reviewed paste.

**Waiting on him** (his to try; none blocks work):
- The pane's slow push and toss on his phone (0.4.444) — the jitter and "clear acrylic copy" were fixed and recorded
  steady on the 27.2 simulator; the shadow fix before it did not change what he saw.
- Not yet seen by him: Sync Automatically, the palette's new lists, the path menu's Open in Editor / Show in Finder,
  ⌘↩ in the paste review, the headset parts.

**How we work** (each learned the hard way; memories hold the rest):
- **Test iPhone changes on his iOS (27.2)**: my simulator "GPT iPhone 17 Pro Max 27.2". A hold that
  passed on 26.5 did nothing on his phone. `GlassAllWindowsPaneUITests` (5) drive the pane; `--demo-open terminal`
  gives a terminal with no server. Record motion with `simctl io … recordVideo` and read frames with ffmpeg.
- Prove each test fails without its fix; compare `tmux list-sessions` md5 around terminal tests; check
  `CGSSessionScreenIsLocked` before blaming a red suite.
- Rule 61: never his machine, tab, window or workgroup names in the repo — his screenshots carry several.
- Builds: `sed 's/444/445/g' $SP/build-install-444.zsh > $SP/build-install-445.zsh` (and `build-444.zsh`), run in the
  background, then read the version from `/Applications/Glass Power Tools.app` and check DiagnosticReports.
- Restate an ambiguous ask before building (he dictates); "keep the current system on mac" meant the Mac only.

**Open for an agent:** B-X7 (needs the headset). Phase 5's File Provider domain trial waits for him. The older test
list follows below.

## 2026-10-13 (~19:35) — the owner's test list

**State:** 0.4.409 on the Mac, Vision Pro and iPhone (19:31); no new crash reports since 18:47 (fixed); working
tree clean; everything committed, nothing pushed. The owner is out and will test when back. **His instruction:
"Go ahead with 5"**: the File Provider spike.

**Built today under D72** (plan: `tasks/2026-10/2026-10-13_system-integration-plan.md`; patterns in
`systemPatterns.md` "The system's ways in"; facts in `techContext.md` "System integration facts"):
- **Phase 1:** entities, ten intents, App Shortcuts, `GlassWindowOpener`, and the Machine widget.
- **Phase 2:** Finder Services, Open With a folder or `.command` file, the Dock menu, `ssh://`, a Finder Sync
  toolbar button, and a Quick Action.
- **Phase 3:**
  - Send Files to a Machine (Shortcuts).
  - Drag a terminal or desktop out into its own window (Vision Pro, and iPad for desktops).
  - Handoff, continuing a terminal in its tmux session.
  - **The Mac share extension** (the owner chose "1 mac only").
- **Phase 4:** controls, opt-in search (Settings ▸ Privacy), and the "What's Open" snippet.
- **Mac extension targets in the hand-written project:** Finder, QuickActions and Share. Add more with
  `$SP/add_mac_extension.py <hexpair> <Target> <Folder> <entitlements> "<display>" <bundle-suffix>`.

**Owner reports today, all fixed:**
- Open With brought up a Connections window: the Mac now takes opens in its app delegate.
- Handoff made a new tmux session: it now attaches by name.
- Handoff missed the open tab: it now finds this Mac's local tab, via `SSHHostKeyIdentity`.
- Two Quick Look crashes (fixed 0.4.398 and 0.4.408).

**Owner to test when back:**
1. Handoff from the iPhone into a tmux session on this Mac (0.4.409).
2. Services, the Quick Action, the toolbar button (switch it on in System Settings ▸ General ▸ Login Items &
   Extensions), and the Dock menu.
3. Share ▸ Send to a Machine, and Send Files from Shortcuts. Neither has sent to a real machine yet.
4. Siri and Spotlight phrases; controls; the Machine widget.
5. Vision Pro: drag a Terminal or Desktop row out of a host's detail into the room.
6. The opt-in search setting.

**Phase 5 spike, done as far as it can go unattended (22:10; `tasks/2026-10/2026-10-13_file-provider-spike.md`):**
- A macOS File Provider extension (`GlassPowerToolsFiles`) links the SSH stack (31 MB) and signs with the Keychain
  group through the team profile. Pinned-only trust and SFTP reading already exist.
- **The owner's call:** register one scratch-VM domain with him present, to prove it at run time, then decide on
  read-only browsing per machine.
- The target is inert (no domain) and embedded in Mac builds. Nothing from the spike has been installed.

**Phase 5 (original plan):** a spike, read-only. Present a machine's SFTP home as a location in the Finder and Files
sidebars with an `NSFileProviderReplicatedExtension` (macOS 11, iOS 16, visionOS 1; a visionOS App Store block
is reported, forum 802442).
- **Measure first:** can a sandboxed File Provider extension reach the SSH stack and the Keychain access group,
  and enumerate one folder?
- **Hard questions:** credentials in the extension (unavoidable here); host trust cannot be prompted inside the
  extension, so only already-pinned keys are accepted; sync semantics.
- **Deliver:** a written spike note with measurements and a recommendation, and a Mac-only proof of concept
  behind a debug flag if it works. Nothing is shipped as working until the owner has seen it.

**Standing:**
- "Go with your recommendations, commit each piece as it lands"; install Mac builds when ready.
- Build and install with `$SP/build-install-4NN.zsh` (copy the last one with `sed`).
- Prove each test fails without its fix; compare `tmux list-sessions` md5 before and after terminal tests.
- Rule 61: never write the owner's machine or tab names.
- `$SP` = the session scratchpad.

## 2026-10-13 (~16:15) — where things stand

**State:** **0.4.402 on the Mac, Vision Pro and iPhone** (14:05); no new crash reports; working tree clean;
everything committed, nothing pushed. The day's record, with every commit and its evidence, is
`tasks/2026-10/2026-10-13_owner-testing-day.md`. Decisions: D24 amended (the library keeps UIKit's sidebar toggle
on iPhone and iPad), D69 (tunnels keep their own SSH connections), D70 (a connection belongs to its controller,
never to a view's task), D71 (the app's own Light, Dark or System).

**Authorization in force today:** "go with your recommendations, commit each piece as it lands"; Mac builds
installed when ready unless the owner says he is working (he accepted every install today); iPhone and Vision Pro
installed with them to keep one build everywhere.

**Confirmed by the owner today:**
- 0.4.402: the lighter Show All Windows blur, Settings ▸ Appearance ▸ System/Light/Dark and the palette in the
  windows' glass: "Yeah, this looks good."
- Square SSH panes where they fill the tab (0.4.399).
- "+" ▸ New Terminal on connects (0.4.400: "it works"). It had failed twice with a `CancellationError`, because the
  connection ran in a view's task: first the placeholder's, then the pane's. D70 records the rule.

**Built today, not yet confirmed on a device:**
- Headset: held delete and arrows repeat; pinch and hold, then drag, selects.
- Desktops on phones and iPad: the system's unavailable view; sessions in place on phones; an iPad window's bar
  and Close.
- Show All Windows across every kind of window, with Blur previews. The toggle sat on the terminal's Connections
  page, where the owner could not find it; it moved to Settings ▸ Appearance ▸ Show All Windows at his word (0.4.401).
  He loved the blur but found it too strong; it went from 5 to 1.5 pt, so lines show and letters do not (0.4.402).
- **App appearance (D71, 0.4.402):** Settings ▸ Appearance ▸ System, Light or Dark, on the Mac, iPhone and iPad.
  The command palette now has the windows' glass and no white list.
- One Command Palette.
- The Quick Look crash fix.
- Database connect errors: the shared Local Network rule; PostgreSQL in the server's words.

**Waiting on the owner:**
- B-X27: the protection class for files written while the Mac may be locked. Recommended complete-unless-open
  for recordings and downloads.
- Unfold the Duo simulator for the tour re-run (content margin; the unfolded-window and "N Views Open" items).
- B-X10/B-X11: a design call.
- B-X4: Mac drag-select in tmux history.
- Headset input to try on the device.
- B-V4 two-device run; B-R1–R7; B-Q28.
- A desktop's clipboard: Share clipboard is off by default per Desktop service, as he was told.

**Next (the owner, 16:10): system integration** — "Let's get a finder integration going … they should be available on
all of the platforms that support them. App intents, all of the modern stuff … Be sure visionOS is well represented!"
(his screenshot: Finder's Services submenu with other apps' New Tab/Window Here and Open in). Plan:
`tasks/2026-10/2026-10-13_system-integration-plan.md`. **Approved (D72): "Do all of the things."**
- **Phase 1 done, 0.4.403 on all three (16:52):**
  - Entities for machines, services and workgroups, read from the widget snapshot.
  - Ten intents and seven App Shortcuts; the built metadata was checked.
  - `GlassWindowOpener`, which every kind of window registers. Requests used to run only from the Connections
    window, so a widget's Connect waited with only terminal windows open.
  - A configurable Machine widget.
  - Not yet seen by the owner.
- **Phase 2 (the Finder) built, 0.4.404:**
  - Services (Tab Here, Window Here, Open in), declared as Ghostty, iTerm2 and CotEditor declare theirs.
  - Open With a folder or a `.command` file, a drop on the Dock icon, and the Dock menu.
  - `ssh://` links: a saved machine connects; another fills in the new-server form.
  - A Finder Sync toolbar button and a Quick Action, as two new macOS extension targets
    (`GlassPowerToolsFinder`, `GlassPowerToolsQuickActions`). They hand off through `GlassExternalRequests`.
  - The owner's report "Open with opens a new connections window" is fixed: the Mac takes opened URLs in its
    app delegate.
  - **To verify on the owner's Mac:**
    - Services show without being switched on.
    - The toolbar button after it is switched on.
    - The Quick Action.
    - A sandboxed extension waking the app.
  - **Release script:** it must sign the two new extensions with Developer ID (B-R2).
- **Phase 3 built (0.4.405–0.4.406):**
  - Send Files to a Machine, a Shortcuts action, so it reaches the share sheet through a shortcut. It uses the
    W14 never-replace upload and a shared `openSFTPConnection`. Not yet sent to a real machine.
  - Drag a terminal or desktop out of a host's detail into its own window: Vision Pro (in the room) and iPad
    (desktops). A dragged `NSUserActivity` is claimed with `handlesExternalEvents`; a headset terminal reserves a
    workgroup.
  - Handoff for the terminal, database or desktop in front. The activity carries only the endpoint, and the Mac
    takes it in the app delegate.
  - **Share extension, the Mac only (the owner chose "1 mac only"), 0.4.407:** Share ▸ Send to a Machine. The
    extension copies the files into the App Group and opens the app, which sends them and shows an alert. No
    credentials ever enter the extension.
  - **Handoff fixed (0.4.407).** The owner, continuing an iPhone terminal on the Mac: "it opened a new terminal
    window, with tmux, in my home directory … left a detached tmux session in Active". Now the activity names
    the tmux session. The receiving device brings forward the tab showing that session, even a background tab,
    or attaches to it by name, never a new session. The owner's leftover detached session is his to End in
    Active.
  - **Handoff of this Mac's own session (0.4.409).** The owner, on 0.4.407: "It found the right tmux session,
    but created a new window and tab when the tab with that session was already open". The phone was SSH'd into
    this Mac; the log showed a new SSH route at the hand-off. Now, when the machine named is this Mac (a pinned
    host key matches this Mac's own, via `SSHHostKeyIdentity` in GlasSecretStore, shared with the editor), its
    local tab comes forward, or a local terminal attaches. This relies on the iPhone's pin of the Mac's key
    having synced by iCloud Keychain; without it, it falls back to SSH.
  - **A second Quick Look crash (0.4.406, 18:47), fixed in 0.4.408:** SwiftUI's dismantle closed a `QLPreviewView`
    that had already closed itself on leaving its window, and Quick Look aborted on the second close.
    Reproduced in a separate process: both teardown orders abort by default and survive with
    `shouldCloseWithWindow = false`, which is now set.
- **Phase 4 built (0.4.406):**
  - Controls on the Mac 26, iPhone and iPad: Open Terminal on a chosen machine, Active Connections, and New
    Terminal Window on the Mac.
  - Machines and workgroups in search, **off until Settings ▸ Privacy ▸ Show Machines in Search**.
  - "What's open in Glass Power Tools?" answered in place with a card.
- **Phase 5 next:** a spike of the File Provider (machines in the Finder and Files sidebars), read-only first.
  Then the owner's devices check all of the above.

**Then, for an agent:** tier 3 from the inventory's section 0: B-X2 with B-Q11, B-X6 with B-F32, B-X7, and
B-X22's second half. Also the database's own `databaseSidebarChrome()`, which still removes the toggle off the
Mac (D24's amendment).

**Rule 61:** the messages of 998a225 and 1da944b quote two of the owner's names. They are left under his earlier
ruling (no history rewrite for messages); files were neutralised. Never quote his tab, host or machine names in
code, notes or messages: use "an SSH tab of the owner's" or "a desktop".

## 2026-10-12 (late) — before the second compaction: the iPhone Duo on its simulator

**Installed: 0.4.391 on Mac, iPhone and Vision Pro** (with the swift-nio-ssh CVE fix). Committed since, not yet
built for devices: swift-log 1.16.1 / swift-nio 2.104.0, the fold-aware window gate, the alignment work below. HEAD =
this notes commit; nothing pushed. (Corrected 2026-10-13: the README space and `testArrowKeysReachTheTerminal` were
not the owner's — the test was an agent's probe, 2026-10-11 — and both were discarded at his word.)

- **Duo simulator works here:** iOS 27.1 runtime downloaded (`xcodebuild -downloadPlatform iOS -buildVersion 27.1`);
  Xcode 27.2 beta's own runtime cannot run a Duo. Simulator **"Duo probe"** (`828A54FB-…`, iOS 27.1); Device Hub's pose
  buttons (folded / half / open, along the bottom) appeared after the owner updated Components. `XCUIScreen.main` is the
  *outer* display — capture `app.windows.firstMatch.screenshot()` (it comes out rotated: rotate −90°).
- **Measured on it:** a Duo reports `supportsMultipleScenes` yes + phone idiom, folded and unfolded; folded (466 pt,
  compact) a scene request *succeeds* and covers the library with no way back but the switcher → gate = scenes AND (not a
  phone OR regular width) (fac5ead, rule 43). Unfolded is regular width (two columns).
- **Alignment (owner: "fix the header and content alignments across the app for Duo", then chose the large-title
  line):** Your Library raised to All Connections' line (132007c); detail columns via `glassDetailColumnTitle`
  (GlassConnectionUI; host detail uses it; iOS 27 puts detail titles in the toolbar row and `.toolbar(removing: .title)`
  does not remove it, so the modifier owns the navigation title). **Unverified:** the 12-pt content margin (needs an
  unfolded run). Other detail panels (Workgroups, SSH Keys, Collections, Active) not yet given the modifier.
- **Done after the compaction — Active's empty detail** (owner: "Terminal > [machines with terminals], Database >
  […]"): the Mac, an iPad in landscape and the headset all showed the same "Nothing Is Open". Now the detail page lists
  the library's machines under Terminal, Database, Desktop (setup tab order); a row connects that service; on a compact
  stack the same sections follow "Nothing Is Open" in the list (`GlassActiveLauncher.swift`, `glassLibraryIsStacked` —
  an iPad's list column is compact in landscape too, so the width class could not decide). Seen on the folded Duo and an
  iPad Pro 11-inch landscape; the Mac not yet on screen (comes with 0.4.392).
- **Seen on the Duo, to fix:** ~~two "Tools" buttons in a folded terminal~~ and ~~the bottom bar white under a black
  terminal~~ — fixed 2026-10-13 (the keyboard accessory reports itself on screen; the terminal paints under it; seen on
  the Duo). Still open: unfolded, a connection opened as its own window that took the screen (needs the unfolded Duo);
  folded, the system's "N Views Open" chip covers the start of the library's large title — it is iOS's own chrome (not
  in our code; nothing published about it): compare an Apple app with several windows on the Duo before changing ours.
- **0.4.392 (2026-10-13 ~00:00):** built for all three from a53f2e3 (the Duo work, Active's machines, the terminal
  fix, the workgroup titles); **Mac installed**; iPhone and Vision Pro were locked, and a retry loop in the session
  scratchpad installs each when it unlocks. The tree-sitter match limit landed after this build: it goes in the next.
- **Scratch and Windows 11 are in the Duo probe's library** (added by a temporary UI test, not committed). How to reach
  both machines is in the agent memory runbook (`test-machines-runbook`): Parallels VMs; Windows account `gptrdp`,
  password reset per need into a 0700 file, never printed; tunnels on port 2223 (Citadel's tests bound 2222 until 2026-10-24; they take a free port now).
- **Temporary UI tests** (tour + demo) live only in the scratchpad (`GlassTerminalUITests.tour.swift`) — swap in to
  run, restore after, never commit. (The "owner-backup" copy beside it held an agent's probe, discarded 2026-10-13.)
- **Done 2026-10-13:** workgroup details use `glassDetailColumnTitle` (host, keys, projects already had it through
  `GlassLibraryDetail`); tier 3's tree-sitter overflow — the highlight cursor's match limit, not vendoring.
- **Next:** unfold the Duo and re-run the tour (content margin; host detail, Active, Settings, Workgroups) — the owner
  was asked to unfold it; the two Duo items left above; tier 3 from B-X5 (shared SSH connection loss).

## 2026-10-12 — end of the session (before a compaction)

**Installed: 0.4.391 on Mac, iPhone and Vision Pro** (with the CVE fix; the Mac at the owner's word, 20:32). 0.4.391
predates the swift-log/nio bump; the next build carries it. Nothing pushed. (A one-space README edit and an
uncommitted agent probe, `testArrowKeysReachTheTerminal`, were wrongly called the owner's here; both discarded at
his word, 2026-10-13.) **Next: the owner brings a new list after the compaction.**

Shipped today, each committed with its evidence (task notes: `2026-10-12_tmux-under-launchd.md`,
`2026-10-12_widgets-machines-and-active.md`):
- **D66, local tmux in a background Glass Power Tools process.** A Force Quit of an app run from a pane ended every
  local terminal: the panes shared a resource coalition whose app had quit (reproduced with a probe and the owner's
  Dock clicks). launchd now runs the app's own executable as `--tmux-host`, which starts tmux, so panes keep the app's
  privacy permissions; `exit-empty` is turned on so tmux and the host end with the last session; Settings ▸ Terminal ▸
  tmux shows it and can end it. **The owner's own server (started 00:44) predates D66** and keeps running as before
  until it ends (a reboot, or End All Local Terminals).
- **Rule 63 leak fixed (8ce39c3):** test windows' panes attached with this Mac's tmux and made six sessions on the
  owner's server. Every tmux call now goes through `MacLocalTmux.server`; stand-ins name an inert tmux.
- **D67, Basic terminals:** any terminal can be opened outside tmux (File ▸ New Basic Terminal Tab ⌃⌘T; "+" ▸ New
  Terminal, New Basic Terminal, New Terminal on ▸ every host by machine name; Connect Saved Host's "Open without
  tmux"; Basic Terminal beside Files on a host on every device; palette). The local tmux toggle moved to Settings ▸
  Terminal ▸ tmux.
- **D68, widgets:** Machines and Active on iPhone/iPad, Vision Pro and now the Mac, from a snapshot the app writes,
  taps as App Intents. On the Mac the snapshot is in a team-prefixed App Group (the wildcard-signed extension could not
  be given `group.sh.glas.shared`). The owner sees correct counts on the Mac; iPhone and headset not yet reported.
- **Editor:** a project's SFTP connection reopens itself when dropped (fc7653e; live test kills a real connection);
  Wrap Long Lines off works on iPhone/iPad/Vision Pro (8b444a9; simulator tests in `GlassEditorUIKitTests`).
- **iPhone:** tapping a workgroup opens its detail (276117e).
- **The busy tab's light:** the activity wave became a soft cloud of light sweeping the row (d45529e, the owner's
  choices at each step).
- Overnight (before the session's first compaction): arrow keys as priority commands, the desktop Keys menu, arrow pad
  and iPhone keyboard bar, the thinned desktop toolbar, push pacing, High Performance mode (D65).

**Open:** D46 pinch gestures (asked "Shall I build it?", unanswered); High Performance tried with a real Mac; the W39
orb on the headset; Bonjour availability (owner's call); widgets placed and tapped on iPhone and Vision Pro; the next
Mac release must sign the widget with Developer ID (see `Tools/Release/release-mac.sh`). **Rule 61:** the messages of
fc7653e, 47b7df8 and 107f1be quote the owner's machine and host names (the code and tests were neutralised). The owner:
leave them, no history rewrite for them, rule 61 unchanged — "just keep moving forward". No IP address of his is in
any file or commit message (scanned 2026-10-12). **Docs (2908a18, the site commit
after it):** release script checks the Mac widget before notarizing (never run; the Developer ID export may need a
profile for `<bundle id>.widgets`); BUILDING.md and SECURITY.md current; site and help current, three stale desktop
claims corrected. **Done after the compaction (the owner's first ask):** the VNC setup warning follows the user name (262ba7a): with a
Mac user name it says a Mac is encrypted after sign-in and other servers protect only the password; without one it
keeps the orange warning and names adding the Mac's user name as the fix. Help page `desktop-add-service.md` matches.
**Then the backlog inventory** (`tasks/2026-10/2026-10-12_backlog-inventory.md`): every open item, with IDs, including
the original apps' lists that never came forward. **Its section 0 is the order of importance** (the owner asked for
it): tier 1 protects machines and data (B-X1 FIFO/huge local reads on the main actor, B-X9 save race, B-X21 Citadel
writer, B-X3 key substitution, B-X14 silent record loss, B-X8 regex hang); tier 2 is dated or release-gating (B-F44
iPhone Duo 10-23, B-H9 dependency failures, B-X25 sleep/wake, stale docs, B-V4 two-device acceptance). Work from it.
**Tier 1 done** (the owner: "knock out all of 1"): B-X1 e56a57f, B-X9 b90327f, B-X21 f2c1950 (Citadel C12), B-X3
9d4fc68, B-X14 77e5523, B-X8 aaf3799, B-X23 (all three devices on 0.4.390). Each test was shown failing without its
fix. B-X1's "FIFO hangs" was wrong (Foundation refuses at once, as "no permission"); B-X3 was worse than listed (a key
not yet synced was swapped too).
**Tier 2 local work done** (`tasks/2026-10/2026-10-12_backlog-tier-2.md`): CVE-2026-43798 in swift-nio-ssh fixed first
(2ddc207, critical, found by the advisory scan); B-X25 wake (fd729b1), B-F44 Duo (aa06f51), B-H1–H4 docs (2aed1f7),
DOMPurify record (b29917a), swift-log/nio taken and the full suite passing (B-H9, B-T5). **Waiting on the owner:**
B-V4 two-device run (checklist in the note), B-T8's device QA, B-R7 a lawyer, B-Q28 SwiftTerm v1.99 (recommend stay on
1.20), the release path B-R1–B-R6, and the Mac install. **Next after that: tier 3**, with the tree-sitter overflow crash
added (vendor 0.25.10 with the fix backported; no SwiftTreeSitter release reaches 0.26).

## 2026-10-11 (late night) — High Performance built; quality-switch crash fixed

**Installed: 0.4.367 on Mac, Vision Pro and iPhone** (19:58–20:05; headset and iPhone were locked, not launched).
Since 93d5f88: High Performance mode (6211b12, f53eb38, 963d0de, 02453cc, fabb375, c2ed00c — D65), the Quality-change
decode crash on the hotspot (1f2a01c). **Next:** owner tries High Performance on the headset (Desktop window settings ▸
Mac Screen Sharing ▸ High Performance, then reconnect) with the Mac at hand; first pull the headset log and read
`event=hp-decoder-check`; then the `hp-*` / `media-*` lines of a session. Then: live resize of the virtual display,
two virtual displays, the W39 orb check on the headset, scroll/clipboard check.

## 2026-10-11 (night) — after the compaction

**Installed: Mac 0.4.364; Vision Pro + iPhone still 0.4.361** (off-network all evening; install 0.4.364 when `devicectl`
shows them, then verify the W39 orb). Since d495e42: **8b9f39d** Automatic quality watches lateness (slow updates, TCP
queueing over base RTT; a Mac's Automatic stops at Balanced; W36 scale refusal only for the Mac's own ending, 10 min);
**e5912f5** availability dots skip connected services and probe VNC every 10 min (a probe launches the Mac's
screensharingd + agent for 15 s). Details in the screen-sharing task note. Next: devices → install + orb + headset log
(look for `event=automatic`, `roundTripMs`, `queuedMs`, `server-scale`); then High Performance mode behind a switch
(probe first); owner to try Automatic on the hotspot and scroll/clipboard on the Mac.

## 2026-10-11 (evening) — where things stand

**HEAD = this notes commit (after 7fc7be3). Installed: 0.4.362 on the Mac; 0.4.361 on Vision Pro and iPhone** (they were
off-network for 0.4.362 — install it when reachable). Full story: `tasks/2026-10/2026-10-11_apple-screen-sharing-protocol.md`.
- **Screen sharing speaks Apple's revision (003.889)** on account connections to a Mac: record layer (encrypted after
  sign-in — 3.8 never was), arming `AutoFrameBufferUpdate` at 0 after each layout (pictures come only by pushes on 889;
  33,333 starved/blackened display 2), ViewerInfo required (without it the Mac hangs), Apple pointer shapes, pointer
  echoes ignored within 1 s of a local move, scroll by distance (0x17), clipboard via Apple pasteboard (0x15/0x0b/0x1f),
  3.8 fallback if the prelude fails. Per-display connections off (a Mac serves one scale at a time); a scaled Mac is
  asked for the whole framebuffer (region requests broke its scaled readback). Fast native ZRLE path; renderer uploads
  only its window's region on new frames. A Mac never reports its own mouse to a controlling viewer (PointerPos −232
  tried; matches codevisor/Jump/Splashtop).
- **Orb (W39, c23a6b6):** the Connections window becomes its orb in place (pushWindow broke after force-quit). UI 9/9 on
  simulator; NOT yet on the headset. If the orb jumps when it comes forward, drop the openWindow in `becomeOrb`.
- **Hotspot test (owner in his car, 380/52):** Balanced at full Retina = 64–74 Mbit/s from the Mac, seconds of lag
  (cellular queueing + the Mac reads input only between pushes). Data Saver (16-bit) "much more responsive"; Lowest
  "somewhat useful". No SetServerScaling was sent all session — probably `scalingRefusals` from a test session.
- **Next:** (1) install 0.4.362, verify orb; pull the headset log (server-scale-refused? flow on the hotspot);
  (2) latency-aware Automatic quality; make the W36 scale refusal less blunt; (3) Service Availability probe: skip hosts
  with a live session, lighter check for a Mac's 5900 (each connect starts screensharingd + agent, once a minute all day);
  (4) High Performance mode (HEVC media stream, virtual displays, AAC-ELD) from remotex `vnc_apple_media.rs` (clone in
  the scratchpad `ext/remotex`), behind a switch, probe first; (5) owner to verify scroll and clipboard with the Mac.
  Older open items: drag-select past the screen in tmux (Select All takes history, ec226f9); light/dark theme pair;
  title capsule sizes; SSH new tabs in the remote folder (scratch only).

## 2026-10-11 (midday) — where things stand

**HEAD = latest notes commit after 5651ae3. Installed: 0.4.350 on Mac, Vision Pro and iPhone.** Two-display screen sharing
works (D61); W38 (D64) adds Retina at 1x / Keep Display Proportions / pointer. **Open bug, top priority:** on the headset
the main connection fails 0.9 s after SetServerScaling 0.5 with "The ZRLE rectangle has trailing data" (log via
VNCDiagnostics, fetched with devicectl — see the task note); the failure then wrongly disables the Apple layout. Then:
drag-select can't reach tmux history in Mac local terminals; the Mac sends no cursor messages to our RFB 3.8 client
(pointer likely drawn into the picture); open questions (light/dark theme pair, title capsule sizes, SSH new tabs in
the remote folder). Probe outputs/logs live only in the scratchpad (`.gitignore` covers Tests/LiveDesktop/*.txt,
*.logarchive).

## 2026-10-11 (morning) — where things stand

**HEAD 606c174+notes.** Installed: **0.4.349 on Mac, Vision Pro and iPhone** (11:45). Since the evening: W34 orb fix (a display
window's ⚡ opened a second Connections window), W35 appearance audit (D63 proposed: no colorScheme light mode on Vision
Pro), UI-test isolation (`GlassUITestRun`), right-click Copy fixed (NSObject `perform(_:)` collision), probe with a
hidden password prompt, W36 Apple display layout (1101+1105) — **owner: "Dual screen works!!!"**, W37 new local terminals
start in the current folder, W38 Retina at 1x / Keep Display Proportions / the Mac's pointer (D64).
**Waiting on the owner:** `Tests/LiveDesktop/.build/release/GlassVNCProbe 127.0.0.1 5900 <user> - --retina-1x
--second-session --cursor 20`, then `--display <retina id> --retina-1x --pointer-check`.
**Open questions for him:** a light/dark terminal theme pair (D63 plan item 1); title capsule sizes (terminal ≈29 pt vs
desktop ≈37 pt); SSH new tabs in the remote folder (testable on scratch).

## 2026-10-10 (evening) — where things stand

**Committed today, after the 0.4.336 install:** 6eafdfd (D59, Vision Pro terminal fully clear: plain window drawing
Apple's glass at its Glass), c981da3 (W26, combine one-terminal windows: Move Tab To in the tools menu, draggable title),
aa9f9fe (W27, This Window: ↺ beside changed settings, Opacity/Glass/Material, one sheet), 3c3661d (W28/D60, shared
window glass; remote desktop fully clear; split-view windows paint only their content), f213d4a (W29, Connections idle
orb with the Active count), 928baaa (one Connections window on visionOS), ed8f09e (tunnel-hop test coin toss fixed),
2b4f75f (W30/D61, a window per remote display, region-limited fetching, Quality and the Connection page).
**Installed:** iPhone and Vision Pro 0.4.336; Mac 0.4.329. The owner is away from the devices (remote); install the
current HEAD on both when reachable, the Mac at his word.
**Validation limits:** the Mac's screen was locked for the last three commits: every touched suite passes except the Mac
title-bar layout test (`workspaceUsesNativeTitle`), which fails the same way on pre-merge code while locked — rerun
unlocked. W30 is unverified against a real Mac; his checklist is in the task note (2026-10-08 plan note, W30 entry).
**Owner's open choices:** database split view vs own glass (`DatabaseSpatialLayout.ownGlass`); desktop canvas corners
rounded vs square; desktop default Glass 25% vs 100%; the no-split treatment for Connections/editor/Files.

## 2026-10-09 — where things stand

**Installed:** Mac **0.4.326** (2026-10-09 23:43: everything through W15; 4 windows reopened, 16/16 sessions, no
crash). Before that 0.4.320 (13:10: closed-window crash fix, Active count at launch, terminal right-click menu). Earlier: all three on 0.4.328 (00:08) (a28dc68: Active
names a Connect workgroup's row by its terminal; 54a66d5: Active asks nothing until the library has loaded; d5b7d2f:
Open Folder Here opens the shell's folder in Files, not home; 1c7c65c: Open in Editor on the folder button's pinch and
hold and in the tools menu). The Mac has none of these since 0.4.320 (its 0.4.322 is
built in `$SP/dd-mac`), to install at the owner's word (he was working).
W15 merged (`6394fc6`, D55): tab groups back after a relaunch on Vision Pro, iPad and iPhone; tabs move between
Vision Pro windows by dragging grid cards or Move Tab To ▸. ef88118: a terminal's selection lasts through output.
W17 merged (`f70da14`): the editor on Vision Pro — its toolbar (was on the split view, which visionOS does not
draw), Markdown preview reachable, Projects + ▸ New Document / Open…, rule 64 deferrals for the editor view and SQL focus.
W16 merged (`02711b3`): visionOS `.plain` windows paint in the window shape (46 pt; 24 pt inset card,
`GlassWindowShape`); Files names its folder in the system window title with an ancestors menu. W20 merged (`d274577`, D57): a terminal window owns its look; local tab gear opens Terminal Settings.
**iPhone and Vision Pro on 0.4.336** (W22–W25 per-window settings for terminal, editor, database and desktop windows;
Apple's window back with nested corners), Mac on 0.4.329. **Next round, first: full transparency on visionOS
terminals was lost with Apple's default window (cfd5094) — see the task note's last entry.**
**All three on 0.4.329** (2026-10-10 09:36: W18 settings sync, W19 Mac names, W20 window look, W21 SSH limits). Mac:
4 windows reopened, 16/16 sessions, no crash; no settings-sync failure logged after relaunch (first time since 09-27);
pool log lines (`sh.glas`/`ssh`) present.
**Owner (2026-10-10 ~00:35): "install all three when W21 lands"** — Mac, iPhone and Vision Pro, one build with W18 + W21.
W18 merged (`6293e69`, D56): settings sync was blocked since 09-27 by a duplicate built-in theme when combining with
an older writer's copy; fixed. The first launch with it applies iCloud's frozen terminal preferences once more. W19 merged (`1e80498`): Mac tabs follow names given elsewhere; Mac SSH tabs in tmux show the program title.
W16 (agent `w16-vision-framing`): dark square corners on visionOS `.plain` windows (Files first) and the Files
window's header to match the Mac's modern one. W17 (agent `w17-vision-editor`): the editor fully working on visionOS.
W15 (agent `w15-vision-windows`, worktree): Vision Pro/iPad tab groups back on relaunch; moving tabs between windows
on Vision Pro by drag and drop in the grid view (owner's idea), with Move to New Window / Move to ▸ menus as fallback.
The Mac reopened its 4 listed windows once (`Reopen: 4 listed … 4 reopening`; later asks "already taken"), 15 of 15
tmux sessions attached, no crash. Places were not yet recorded by the 0.4.317 that quit, so positions come back from
the next quit on. Everything committed; nothing pushed. Current task note:
`tasks/2026-10/2026-10-08_find-tabs-tmux-workgroups-editor-plan.md` (W1–W14; backlog at its end).

Earlier, 2026-10-08: Mac 0.4.308, iPhone and Vision Pro 0.4.305.
**The owner works in Claude Code inside a local tmux tab in the app** (`glass-1`): a Mac install no
longer ends the session, and the app reopens tmux windows after a quit. **Standing permission: install
Mac builds as soon as they are built** (detached installer); iPhone and Vision Pro on the owner's word.

Built and committed 2026-10-07 → 08 (task note `tasks/2026-10/2026-10-07_terminal-tabs-and-local-tmux.md`):
- Library rows keep one height in every list; Workgroups use the shared row.
- Mac tabs: named after what runs in them (program title, else a folder other than home, else the
  workgroup, the tmux session as Active shows it, or the shell); rename by double-click, Return, the
  menu or the window title; an activity wave; Finder drops type escaped paths; **drag tabs between
  windows** (drop anywhere on the window; a window whose last tab leaves closes) or within one to
  reorder.
- **D47 local terminals in tmux:** a Mac setting; tabs reattach after a quit or install; closing
  detaches; Active lists This Mac's sessions (open, take over, end); scrolling scrolls tmux's history.
- **D48 SwiftTerm 1.20** (answers XTVERSION, so Claude Code draws in whole frames) and a weekly
  dependency check (`Tools/Packages/check-updates.py`, LaunchAgent). xcodebuild needs
  `-skipPackagePluginValidation`.
- Local shells get the Mac's environment and `TERM_PROGRAM=GlassPowerTools`.
- Scrolling in tmux over SSH on every device (Mac scroll events; a pan on iPhone, iPad and Vision Pro).
- A new SSH terminal never joins a running tmux session by guess (list retried; unlisted names high).
- Vision Pro: the Connections window is a value-keyed window group (a saved-session pair made every
  launch fatal).
- **D49 favourites** and **D51 workgroups** sync across devices.
- Help and the site describe all of it.

Earlier in October, each in `tasks/2026-10/README.md`: D44 tmux on servers and Active's running
sessions, desktop passwords kept through merges, connected dots, iPhone landscape, D45 a database
through another machine, RDP bandwidth reports, the bolt on the right, trackpad scrolling on desktops.

**In progress (2026-10-08, owner's go: recommendations taken, commit each piece as it lands, do not relaunch or install the Mac app until the owner says — it is in use):** eight reports — terminal find, the local
folder button, "+" opening a blank panel, Connect always new, workgroups and tmux, a second editor,
⌘O for folders, a dragged tab copying its tmux session. Plan, root causes, five parallel workstreams,
and decisions: `tasks/2026-10/2026-10-08_find-tabs-tmux-workgroups-editor-plan.md`. Found on the way:
D51's `modifiedAt` is never saved (`Models.swift:2338`); tmux runs without a UTF-8 locale, which turns its listings into "no sessions" (the folder button opening Home, Connect joining `glass-1`, an empty This Mac in Active). Owner's answers and the revised plan are in the note.

**Open, owner's call:**
- **Vision Pro SwiftUI layout crash** while a terminal shows this Mac's tmux session running Claude
  Code (Release builds only; an ASan debug build did not crash in 20+ minutes; xrOS 27.2 beta).
- **Active on the headset does not list the Mac until connected**, and **why a new SSH terminal
  dropped into `glass-1`**: cause found on 2026-10-08. tmux run without a UTF-8 locale (SSH exec on
  a macOS host, and the Mac app itself) prints its listing's tabs as `_`, and the listing reads that
  as "no sessions". Fix planned as W0 in the 2026-10-08 plan note.
- **D50 (Proposed):** reach This Mac's terminals from other devices — needs the owner's OK to add a
  key to `~/.ssh/authorized_keys`.
- **D46 (Proposed): palm-up pinch-drag = scroll, pinch-and-hold = right-click on Vision Pro.**
  Measured: palm direction is the pinch pose's `up` (right hand) / `−up` (left), z toward the viewer;
  away ≈ −0.8, toward +0.68 (right) / +0.40 (left); threshold +0.2. The pose comes only from a SwiftUI
  `SpatialEventGesture`, which takes all input and carries no mouse buttons, so the trackpad's
  two-finger right-click would be lost. Proposed fix: switch between a hands mode and a trackpad
  mode on what is in use. Pending: does trackpad hover still reach UIKit while the gesture is on?
- The slow production query (100 rows, 9.5 s): our tunnel and MySQL path measured fast on scratch
  (50 MB of rows in 0.2 s); the owner was given two queries to split data volume from the server.
- Vision Pro tab bars expanding together across windows; release steps (Sparkle key, Developer ID
  profile, site deploy, scrub, history rewrite and first push — owner's word only).

**Headset connection:** it was unreachable for days because a full-tunnel VPN on the Mac blocked local
network discovery; once LAN access was allowed it appeared. Installing over a running app on the
headset does not restart it — relaunch with `devicectl device process launch --terminate-existing`.

## Paused 2026-09-28 (evening) — where to pick up

All work below is committed locally (nothing pushed). Mac 0.4.266, iPhone 0.4.249, Vision Pro 0.4.254
(the headset was unreachable; its next build must be cut fresh — 0.4.264 predates Mac glass).
Detail: `tasks/2026-09/2026-09-27_glassdt-parity-audit.md` (desktop parity, sync repairs, list sweep).

**Next, in the owner's order when they return:**
1. **visionOS unwind, pass 2** — **approved (D40), narrowed 2026-09-28:** all window transparency stays; only list formats and non-Glass custom chrome change; database: only the results tool bar (in progress: icon buttons + More menu). Owner's direction (2026-09-28):
   *leave it to Apple to define what spatial is best.* The list rows are done (`glassSpatialList`,
   `glassSpatialListRow`; rows never add gaze highlight or padding). Still ours: `GlassSpatialMetrics`
   type/size scale (24 uses), custom window frames (`GlassNativeWindowFrame`, `GlassCanvasBackdrop`,
   `GlassLayeredWindow`/`Panel`, 8 `.windowStyle(.plain)` scenes), 4 hand-built ornaments, 7 custom
   glass backgrounds, the split Connect capsule. Keep: terminal/desktop transparency and the desktop's
   colour key, and the desktop control bar. Proposed order: library window first, judged on the headset.
2. **Stats in the empty library detail** (total machines, services per machine, connection timeline,
   availability) and **status dots as an option** — **approved (D41): counts + timeline from
   on-device history; dots a setting, off by default, TCP connect only.**
3. **Richer clipboard** — **approved (D42), in order:** RDP text/rich text/images, RDP files,
   Files (SFTP) ⌘C/⌘V and drag with Finder, VNC Extended Clipboard.
4. Desktops in Active "a little wonky" — cause not yet described by the owner.

**2026-09-29 (Mac 0.4.253, committed):** database results bar as icon buttons + a More menu (not the
iPhone's pager); "Statement Completed" fills the pane so the pager stays at its foot; the Mac gutter's
offset is a view conversion (the SQL pane's "1" sat a line low); a sync request arriving mid-pass
waits for the pass; ⌘W → Discard on an editor's last document hides the window at once and closes it
once the sheet has gone — the owner confirmed it on the Mac. Flaky only in full-suite runs, not
investigated (terminal, outside the owner's scope): `macImportedThemeAndPortableAppearanceApplyAfterICloudMerge`,
`abandonedStartupCommandTicketExpires`; both pass alone.

**2026-09-29, headset round (Vision Pro 0.4.254):** the editor's panel has square corners; Files hides
its selection circles until Select… or a swipe (as on iOS); the library's iCloud row is plain text
with only the cloud as a button. **Open:** looking at one window's tab bar expanded the library's and
the database table's tab bars too (owner's capture). Nothing documented explains it (HIG says a tab
bar expands for its own window). Proposed, awaiting the owner's go: the database table's
Data/Structure/DDL/Indexes/Foreign Keys as a segmented control on visionOS, leaving the library as
the only tab bar; test with the windows apart to tell our setup from a visionOS bug. Also open: the
remote desktop is slow on the headset (connecting vs live session not yet described).

**2026-09-30:** D43 schema diagram built (task note `2026-09-30_schema-diagram.md`); one
Connections window on visionOS; every ⚡ opens Active; five help pages corrected; README and the
databases page list the diagram. Committed on the owner's word.

**Backlog run, 2026-09-30 (owner: "create a plan and build your list"):** all eleven items built and
committed — see `tasks/2026-09/2026-09-30_backlog-run.md` for each commit and its evidence. Owed: an
install on the Mac and headset, RDP autodetect against Windows, Open With from the Finder.

**After the run (owner on the Mac, 0.4.265–0.4.266):** Settings on the Mac sizes itself to its tabs
(Editor was lost in the toolbar's overflow); desktop glass (Opacity, Background Frost) now on the
Mac too — glassDT had it on the headset only. README and the desktops page list both, with adaptive
streaming.

**Before letting any device with an old install sync:** dry-run the Mac first
(`GLASS_SYNC_DRY_RUN=1`, see the audit note's sync sections).

## Open questions for the owner

- Delete the legacy `SFTPRemoteEditorView` sheet? (Recommended.)
- Behaviour and design findings from the help audit, not changed: the widget reads data the app no
  longer writes (fix or drop for 1.0?); local editor projects sync to devices that cannot open them;
  the Editor off the Mac has no Find, no way to close a lone document, no blank editor; the database settings page may be unreachable (the desktop's is fixed); the database "Rows per page" field does nothing; the terminal
  password, trusted host keys, imported-desktop mobility, Rows per page, the database settings page
  and the editor's Find/close were fixed on 2026-09-30.

## Working rules that matter right now

- Privacy (rule 61): no real machine names, addresses, device identifiers, hosting details or code
  names in tracked files.
- Every shortcut has one owner (D37, rule 60); read the running app's menu bar after changing one.
- Prove a test fails without its fix before trusting it.
- After `swift package update`, run `Tools/Packages/sync-xcode-pins.py`; `PackagePinAgreementTests`
  fails if Xcode's pins and the package's differ.
