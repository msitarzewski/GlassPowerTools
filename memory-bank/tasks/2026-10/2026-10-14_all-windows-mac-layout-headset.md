# 2026-10-14 (late): All Windows as the Mac lays it out; the headset's window; two headset fixes

**Owner:** the coordinating agent. **Authorization:** the owner's standing "go with your recommendations, commit each
piece as it lands"; installs on the Mac, iPhone and Vision Pro with every build. Nothing pushed.

## What the owner asked (on the headset, 0.4.444)

- Live previews on the cards: "Agree on iPhone, but let's fix the other platforms."
- "In the session cards view, please mirror the Mac layout. Grouped by machine, but show each tab as a card. The view
  should adjust itself based on the number of sessions showing."
- "Right now it's a modal, will that work for larger workloads?" (the Vision Pro sheet)
- "I'd also like to revisit the width of the connections window, it should be wider by default."
- "The Editor window's bottom corners show a square background." (a headset screenshot)

## What changed

| Commit | Change |
|---|---|
| ca3f897 | Connections on Vision Pro opens at 1180 × 700, the Mac's width (was W29's 960). An open window keeps its size. |
| 7538a54 | The editor's window contents are clipped to the 46-point glass corner on the headset; the status bar's square `.bar` had filled the bottom corners. |
| 321a625 | `MacTerminalExposeLayout` moved unchanged to GlassShell as `GlassAllWindowsLayout`; the Mac keeps the old name as a typealias. |
| b5df704 | `GlassOpenSession.tabs`; a terminal workgroup lists each live terminal as a tab card (named as its tab, on its own server's machine; choosing selects the tab and shows the window; closing closes the tab). `GlassShellModel.allWindowsMachines()` groups them; Active still shows one row per window. |
| 3b0b6e5 | The cards view (`GlassShowAllWindowsOverview`) packs groups and cards with the Mac's layout, shows each card's name and state over its picture, and retakes each picture once a second (`TimelineView(.animation(minimumInterval: 1, paused:))`) while it's on screen and the scene is active. `--demo-open all-windows` (DEBUG). |
| 1558bd6 | Vision Pro: All Windows is a `Window` scene of its own (`GlassShowAllWindows.windowID`, 1280 × 800, `.restorationBehavior(.disabled)`) inside every capability's bootstrap, so a chosen card's request is carried out with no Connections window open. It leaves 300 ms after the choice. The sheet on Connections is gone. |

**Reuse:** the Mac's layout solver (moved, not rewritten); the terminal's existing `selectSession(_:inWorkgroup:)`,
`closeSession(_:inWorkgroup:)`, `TerminalWorkgroupOpening.label` (new `.allWindows` surface) and preview; the Mac
tile's caption shape; the bootstraps Connections already composes.

## Validation

- Unit: the Mac's 14 layout tests pass against the moved type; two new tests (the terminal's tabs; the shell's
  grouping) each fail without their half; shell suite 297 pass; terminal listing/names tests pass; tmux md5 unchanged.
- iPhone: `GlassAllWindowsPaneUITests` (5) pass on the iOS 27.2 simulator; the demo shows three tab cards under their
  machine and the editor under the device; only a terminal that has been on screen has a picture there (as agreed).
- Vision Pro simulator (27.2): the demo editor's status bar ends in the window's rounded corner and its toolbar
  ornament is whole; the All Windows window opens with three live tab cards.
- The editor's bottom-left corner, under the Files sidebar's bar, is rounded too (demo project).
- 0.4.445 installed on the Mac, iPhone and Vision Pro (23:59); each reads 0.4.445; no new crash reports.
- Not shown by the demo: a desktop's card (the demo desktop is built outside the desktop list). Real desktops are
  listed, as on the Mac.

## For the owner to check on the headset

The ⚡ held (or Siri) opens the window; resize it and the cards grow; choose a tab's card and that window comes back on
that tab; the cards' pictures move. Connections is wider only when opened new (close it and open it again). The
editor's bottom corners.

## Remaining

Other headset windows draw square `.bar` backgrounds at their bottom (Files' bar, `SFTPBrowserView`) and may show the
same corners; not looked at yet.

## 2026-10-15 (after midnight): a new file's save over SFTP, ⌘S off the Mac, Open as Tab In

The owner, on the headset (0.4.445):
- "a new file can't be saved" — a never-saved document saved into a project on a server said "The operation
  couldn't be completed. (Citadel.SFTPMessage.Status error 1.)"; "I'd like to just hit command s on an unsaved text
  file to get the location prompt."
- "The context menu for active but detached terminals should show existing tab groups. So I can open a new session
  into a group."

| Commit | Change |
|---|---|
| 8825846 | The editor's SFTP write (`GlassTerminalDirectoryLister.write`) read the destination first and failed for a file not there, so every first save and New File on a server failed. Missing + nothing expected → created through the verified upload with a new `createFromEditor` policy (no-clobber hard link, no resume record, committed stat from the verified handle); missing + expected → "changed while saved". `GlassSSHTransport` now turns Citadel's `SFTPMessage.Status` into `SFTPSessionError.refused(SFTPRefusal, …)` with plain words (editor and Files browser alike). |
| e3ee5d7, 05b1dab | Off the Mac the editor's toolbar Save takes ⌘S (inside `#if !os(macOS)`; the Mac's owner stays File ▸ Save) and is enabled for a never-saved document. The single-owner test now expects it and checks it stays off the Mac. |
| e9e38d7 | Active's running-session menu: **Open as Tab In ▸** the terminal windows here with room (`GlassTabGroup`, `GlassCapability.tabGroups`, `openRunningSessions(_:inTabGroup:)`). Off the Mac a workgroup (iPad/headset connect each through `launchTerminals`, moved out of `openVisionWorkgroup`; iPhone adds slots); on the Mac the window's tab adder. A closed window → a new window; too little room → what fits, and says the rest. |

**Validation:** an in-memory OpenSSH-like `SFTPSession` drives the real commit (new file created, nothing left behind;
a file that went reported changed; an existing file replaced as before; refusals in words), the first two failing
without the fix; Open as Tab In's windows, room rule and Active routing tested, each failing without its change.
Transport 86, editor 164, shell 298, terminal 838 pass; tmux unchanged by the runs. Live, against the scratch VM's
OpenSSH (`LiveRemoteEditingTests`, 11 pass): a new file is created and described with nothing left behind, and a
file that went is reported changed; without the fix the real server answers "no such file", the owner's error. The SFTP Files window's own bottom-bar corners are still unchecked.

0.4.446 (00:29) is on the Mac, iPhone and Vision Pro; each reads 0.4.446; no new crash reports.

## 2026-10-15 (~00:50): Open N as Tabs In; the + held

The owner: "add Open as Tab In for multiple selected sessions too and the plus in the toolbar should all[ow] a pinch
and hold > servers > terminals list to open in the current window."

| Commit | Change |
|---|---|
| 4a1cd6f | Several running sessions chosen in Active: a chosen row's menu and the selection toolbar offer **Open N as Tabs In ▸** (`GlassShellModel.open(_:inTabGroup:)` for many, `GlassActiveSelection.openChosen(in:inTabGroup:)`), one request in Active's order; open-here ones stay. |
| 2900dc9 | The + of a terminal window off the Mac (`TerminalNewTabMenu`: the headset's bar, the iPhone/iPad toolbar) is a menu with the picker as its tap; held, every saved server ▸ New Terminal and its running terminals (Active's cached list, via `GlassTerminalRuntime.runningSessions` / `refreshRunningSessionsIfDue` from the composition root), opened in this window by the window's own add with a tmux attachment — no Connections window needed. |

**Validation:** the batch test (one request, order, open-here kept) fails when sent one by one; the menu's entries test
fails when an open-here terminal is listed; the headset's 3 bar UI tests pass with the + once; shell 299, terminal 841;
tmux unchanged. The held menu itself is not driven by a test (no saved servers in the demo); the owner checks it.

0.4.447 (01:04) is on the Mac, iPhone and Vision Pro; each reads 0.4.447; no new crash reports.

## 2026-10-15 (~01:30): the Mac's + lists running terminals; headset selection and link menu

The owner: "yes, add running terminals to the Mac + menu too. But also look at vision pro text selection and context
data detectors. It's not working as I'd expect (I have to triple pinch or click with the trackpad) to get it to select
at all." Then: "Mac works great the vision pro needs the data detector and selection work."

- **2facec6 (0.4.448):** the Mac's + menu: Running on This Mac ▸, and a host with running terminals is a submenu (New
  Terminal, Running). Confirmed by the owner.
- **Headset selection (research by a read-only helper, then verified in source):** SwiftTerm's iOS view is a scroll
  view; its double/triple taps go to the program when it has the mouse (tmux `mouse on`: tmux's double-click copies
  into its own buffer and clears), and its Copy menu (`UIMenuController`) never shows on visionOS. Our hold allowed
  UIKit's default 10 points, so a drifting hand became a scroll; after a triple tap the selection mode stayed `.row`.
  Links open on a pinch only when hover highlighted them, and visionOS gives apps no gaze hover.
- **Changes:** `ReviewingTerminalView` (visionOS): hold allows 40 points and every pan waits for it; a hold resets the
  mode to characters; our own double and triple pinch replace SwiftTerm's (local word / row, Copy menu); a hold that
  lets go without moving on a link offers its actions through `UIEditMenuInteraction`'s delegate. Shared
  `TerminalLinkLookup` (lookup + actions; the Mac's menu now uses it). Off the Mac, each terminal in a workgroup window
  gets Open in Editor, Show in Files (`TerminalSession.locate`, moved from the Mac's `locatePath`) and Watch Log File (a
  plain-shell `tail -F` tab of that window). Demo `--demo-open terminal-links`; `GlassTerminalSelectionUITests`.

**Selection results (2a49a43, 0.4.449):** on the visionOS 27.2 simulator a double pinch offers Copy and a hold on an
address offers Copy Link (`GlassTerminalSelectionUITests`). The runner presses at an element's middle whatever point it
is given, reached a hold on the path demo once in three, and turns a held SwiftUI menu (the +, the layout toggle) into a
tap — those are the owner's to check. Each hold and double pinch logs where it landed (`sh.glas` / `terminal-selection`).
b1935a9 fixed the iOS build (the workgroup view imports GlassTerminalEmulator everywhere).

## 2026-10-15 (~03:30): the layout toggle, the session orb, Auto-focus on activity (Vision Pro only)

The owner: the tabs/grid/carousel selector "a toggle like we have for the markdown preview … Is an eyeball appropriate
there or is there something better?"; "a persistent system level session/service icon that shrinks a window into a small
preview. When activity is enabled, the preview/orb should pulse"; "Both of these requests a vision pro only"; his
choices: an orb with a tiny live picture, pulse switched by Auto-focus on activity, the control first in the bottom bar,
every session window; then "add Auto-focus on activity to This Window".

- **1d63c66:** `VisionTerminalPresentationPicker` is a Menu with a primary action: the glyph is the current layout
  (`rectangle.topthird.inset.filled`, `square.grid.2x2`, `rectangle.stack`), a pinch cycles, a hold lists the three.
- **1011982:** `glassSessionOrb` (GlassShell): the window keeps its content out of sight and asks for the orb's size
  (`GlassConnectionsWindowLayout`, now shared; `GlassWindowSizer`, moved out of the Connections probe); the orb is a glass
  circle with the session's picture each second, name on a look, a pulse ring while busy. `GlassSessionOrbButton` first
  in the bottom ornament (added by the modifier). `glassWindowOutOfSight` hides `GlassNativeWindowFrame`'s title and
  controls. Wired: terminal (front terminal's picture, `TerminalWindowActivity` from `onOutputActivity`), desktop (remote
  screen; freeform resize, so the W38 hold lapses after a round trip), database and editor (symbols). Auto-focus on
  activity: `TerminalWindowSettings.autoFocusOnActivity` in This Window (visionOS), unset following the saved Workgroup;
  drives the pulse and brings the printing terminal forward in grid/carousel.
- **f278bf9:** two Connections orb tests found the desktop by an Input button the bar no longer has; now by Settings.

**Validation:** `GlassSessionOrbUITests` (shrink, bar and title gone, pinch grows back) and Connections' 9 orb tests pass
on the visionOS 27.2 simulator; shell 299, terminal 845, connection UI 49. **Open:** the pulse is unchecked (no saved
workgroup or live output in the demo); the terminal's own tab ornament stays beside the orb (it shows beside the window
too); a database or document orb shows a symbol, not a picture.

0.4.450 (03:31) is on the Mac, iPhone and Vision Pro; each reads 0.4.450; no new crash reports.

## 2026-10-15 (~04:20): the orb as a sphere with its tabs on a ring (b72244d)

The owner: "redraw the tabs around the orb evenly distributed with a preview in the orb on hover? The name should never
cover the orb, it should grow away from the orb. Make the orb shaped more like an orb, and have it grow slightly when
interacted with." Choices: small glass dots; a pinch on a dot grows the window back on that tab; the orb shows "front
tab, or whichever is active".

- `GlassSessionOrbTab` / `GlassSessionOrbFace.tabs`; `GlassOrbRingLayout` (dots evenly from the top, names anchored
  toward the orb so they grow outward, the orb's name below); `GlassOrbSphereShading` (cut to the circle itself — the
  orb's clip let its gradients' square show); press grows (1.06). Previews on a look via shared `HoverEffectGroup`s
  (the app is never told where a person looks). `glassHiddenWhileOrb` removes the terminal's tab ornament while orb.
  `GlassConnectionsWindowLayout(library:orb:orbContent:)`: 480×340 with a ring.
- Verified on the visionOS 27.2 simulator: the ring with two tabs, a dot pinch grows the window back (UI test), the
  sphere captured clean with `--demo-session-orb`. Looks (names, previews) can't be driven there. Simulator notes: a
  restart leaves Home in front of app windows for `simctl io` captures (launch the app directly to bring it forward);
  another app's window (a markup tool) can cover the scene; the bar's grid test flaked once in sequence, passed alone.

0.4.451 (04:21) is on the iPhone and Vision Pro; the Mac's quit was cancelled at the app's question, so it stays on 0.4.450 until he's ready.

## 2026-10-15 (~04:50): names on a look, beside their dots; the orb in the view menu (f46f283)

The owner, on the headset with ten terminals in one window: dots a little further out; "only show the label when
focused.... all of them at once is a lot"; "the titles are aligned incorrectly to the dots"; "is the orb view just one
more option for the view menu in terminal mode?"

- Cause of all names at once: each tab's picture inside the orb was in its tab's `HoverEffectGroup` with the default
  `.activatesGroup`, so a look at the orb started every group. Pictures and names now `.followsGroup`.
- Names: placed beside their own dot (level on the sides, centred above/below at top and bottom), not by the angle's
  fraction of their size. Dots 22 pt from the rim; ringed window 560×380.
- Orb is the 4th item in the terminal view menu (Toggles for Tabs/Grid/Carousel + Orb); the terminal bar shows Shrink to
  Orb only with one terminal (`GlassSessionOrbFace.showsButton`).
- Simulator checks: orb tests pass (ring test shrunk by `--demo-session-orb`); `--demo-open terminal-ring
  --demo-orb-names` shows ten names level with their dots.

0.4.452 (04:44) is on the Mac, iPhone and Vision Pro; each reads 0.4.452; no new crash reports.

## 2026-10-15 (~05:00): a name stays while it is read (6b8deb3)

The owner, with a headset capture of a ten-dot ring: "The labels disappear when you try to read them becuuse the dot
lose focus". A tab's name showed only while its dot was looked at, so moving the eyes onto the name hid it.

- Each name beside a dot is now a `Button` in its dot's `HoverEffectGroup` with its own capsule hover shape: a look at
  the name keeps the group active, and a pinch on it grows the window back on that tab, as the dot does. The orb's own
  name is a button in the orb's group. `GlassOrbName` is hit-testable (it was `.allowsHitTesting(false)`).
- Checked: visionOS simulator Debug build; `GlassSessionOrbUITests` both pass. The look itself can't be driven on the
  simulator: the owner's eyes are the test.

0.4.453 (05:01) is on the Mac, iPhone and Vision Pro; each reads 0.4.453; no new crash reports.

**Help and site (3b62177):** an agent working only in `site/` added Show All Windows on every device (replacing the stale
Show All Terminals), Shrink to Orb, the layout toggle, selection, links and paths, Open as Tab In, the held +,
the palette's lists, ⌘↩, the editor's saves, and a new `library-siri-and-system` article for D72. Reviewed by the
coordinator: specific claims checked against the code (12 dots, state tints, `tail -F`, ⌘K, the beep), a scan for
private names, and `build_site.py`: 7 pages and 39 help pages, no broken links. Not deployed.

## 2026-10-15 (~06:50): selection with tmux, the orb's names and pictures, a desktop's shape, Files' corners (0.4.454)

The owner, on the headset (0.4.453): "selecting text is still broken wholly in the terminal in visionOS with tmux for
sure, how do I see the orb on desktop? Fix all of the things! BTW, the small names still don't align correctly around
the orb."

**Selection (532a9d8).** First suspect, SwiftTerm dropping the selection at every write (`feedPrepare`), was already
handled by `SwiftTermSelectionKeeper` (ef88118); a proof run showed the new redraw test passing without any change. Two
real defects, each shown with `--demo-open terminal-tmux` (alternate screen, mouse mode 1000/1002/1006, a status line
fed every 0.4 s through the demo's new `tick`):
- SwiftTerm makes its mouse-drag pan only when a program asks for the mouse (`mouseModeChanged`), after
  `installHoldToSelect` ran, so it never waited for the hold: a drifting hold became tmux's drag (`pan(-) began` in the
  log). `pansWaitForTheHold()` now runs on install and on every mouse-mode change.
- With the mouse taken, SwiftTerm's single tap went to tmux as a click and left the selection. `selectionChanged` now
  sets `allowMouseReporting = !selection.active`, so a pinch clears it. Since output then no longer clears a selection,
  the keeper's `restore` also checks one left in place (text changed → gone; trimmed rows → moved).
- **Not proven to be his failure:** this Mac's tmux has `mouse off` (default config), so his headset failure may be
  something else. Each hold, double/triple pinch, every other recognizer's start and end (`tap1`, `scroll`, `pan(-)`,
  `pan(UIKitAlternateScreenScrollWatcher)`), mouse-mode changes and selection made/cleared (with `alt`, `mouse`,
  `selection`, `first` state, never text) now go to the system log and, through `glassTerminalRecordSelection`, to
  `VNCDiagnostics`' file as `terminal-selection` lines. Copy `screen-sharing.log` off the headset after he tries.
- Tests: `GlassTerminalSelectionUITests` +3 (drifting hold selects; word stays through redraws; pinch clears); the
  drift and pinch tests fail without their change (proof runs B, C). `TerminalSelectionTests` +1 on the Mac (mouse
  reporting off, rewritten text drops the selection), failing with the old restore. All 5 selection UI tests pass
  (the two link tests had failed once when the runner never reached the terminal — nothing logged — and pass on
  rerun). Terminal suite 846; tmux md5 unchanged.

**Orbs (30d6ca6).**
- Names: `GlassOrbName` had `.fixedSize().frame(maxWidth: 150)` under a 150 proposal, so every name's frame was 150
  wide with its capsule centred: a short name sat up to ~60 pt off its dot. `GlassOrbRingLayout.place` proposes
  `min(ideal, widest)`. Captured on the simulator with ten names (`terminal-ring --demo-session-orb --demo-orb-names`):
  each starts 8 pt from its dot.
- Pictures: `GlassWindowSizer.picture()` draws the window (`drawHierarchy`) at the moment of shrinking, for a face
  with no picture of its own (`lastLook`). Captured: the demo editor's code and the demo database's table in their orbs.
- Desktop shape: `GlassSessionOrbControl.isWindow` (not orb, not growing back; growing ends in the sizer's `afterward`,
  which now also runs when no window is found); `DesktopWindowAspectLock` pauses while it's false and asks again
  after. `testADesktopShrinksIntoItsOrbAndGrowsBack` drives it; the log shows `aspect-lock` again right after
  `session-window-geometry`. The simulator reports `uniform=false` even on a desktop's first open.
- "How do I see the orb on a desktop": **Shrink to Orb** is the first button in a desktop window's bottom bar (the
  new test finds it there); Vision Pro only, as he chose.

**Files (0c07f12).** The Files window's contents are clipped to the 46-point window corner, as the editor's (7538a54):
its bottom shelf is a square `.bar`. The demo window keeps its corners; the shelf itself needs a live selection, so its
corners are the headset's to confirm.

Help: `terminal-sessions.md` (both ways of selecting work with tmux's mouse on; a pinch clears), `library-connect.md`
(database and editor orbs show the window).

0.4.454 (07:06) is on the iPhone and Vision Pro (`devicectl` reads 0.4.454). The Mac's quit was cancelled at the app's
question, so the Mac stays on 0.4.453 until he's ready; today's changes are the headset's (the keeper's change leaves
the Mac's behaviour as it was). No new crash reports.

## 2026-10-15 (afternoon): the yellow selection, and no scrolling — tmux 3.8's mouse (2975ace, 0.4.455)

The owner, on the headset in a tmux terminal on this Mac: "I just can't select text. It immediately unselects", then
"what's the yellow vs. blue selections?", "Does it set things on its own?", "Now I can't scroll at all in visionpro".

- **Cause:** this Mac's tmux server restarted at 14:36 under tmux 3.8, which turns `mouse` **on** with no configuration
  (a private server, `tmux -L … -f /dev/null`, reports `mouse on`; the morning's server reported off). The app sets no
  tmux mouse option (it sets only its own session options: given name, repository, branch). With the mouse taken,
  SwiftTerm sent a pinch-drag to tmux as a drag: tmux selected in copy mode (`mode-style` bg yellow) and copied to its
  own buffer and cleared on letting go — the "immediately unselects" — and the app's tmux scroll stood aside, so
  nothing scrolled. Blue is the app's own selection.
- **Fix (visionOS):** `mouseModeChanged` switches off SwiftTerm's new drag pan (no delegate) as it is made;
  `UIKitAlternateScreenScrollWatcher` begins whatever the mouse mode and scrolls tmux's history through the session, or
  sends the program SGR wheel steps (button 4/5, one per three rows) where there is no tmux session. A pinch still
  clicks. iPhone and iPad unchanged (they likely have the same trouble with tmux 3.8; not yet looked at).
- **Test:** `testAPinchDragScrollsAProgramThatHasTheMouse`; the tmux demo answers SGR wheel reports on its status line
  (`DemoWheelAnswer`). Fails without the change (`pan(-) began` in the log: the drag sent to the program). All six
  selection tests pass. Help updated.
- With the terminal focused as a real session's is (`--demo-keyboard`), a double-pinched word in the tmux demo stays
  highlighted (captured), so the simulator never showed his failure: the mouse was the difference.
- The headset log couldn't be copied: the Mac (no Wi-Fi joined, a new address) and the headset can't see each other.
- Working files moved to `~/Software/glass/tmp` after a /tmp cleanup wiped the scratchpad.
