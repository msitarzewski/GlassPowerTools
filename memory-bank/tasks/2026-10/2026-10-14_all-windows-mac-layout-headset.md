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

