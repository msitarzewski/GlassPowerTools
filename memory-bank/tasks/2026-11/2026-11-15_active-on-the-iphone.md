# Active on the iPhone: the bell, gathering sets, names after a relaunch (2026-11-15, 0.4.620, D108)

## Task
- **His reports, a day on the iPhone (0.4.619):** Active "doesn't highlight which terminals need attention / have
  alerts (the orange pulse/highlight)"; "the active list has a select, but it doesnt work, so i cant select multiple
  to add to a set"; moving a terminal between sets from the name menu "worked, but it crashed", then Active's names
  were "generic … session names". The "crash": "screen just went black. no controls."
- **Asked, he chose:** "Not worried about it [the black screen]. Let's work on the other stuff": Select for sets open
  on the phone, and bells from terminals open elsewhere (proposed as a bell kept on the tmux session). Not committed.

## What changed
- **Active's bell (open here):** `GlassActiveSessionRow` reads `GlassOpenSession.hasUnseenBell` (a window's tabs'):
  the symbol orange and glowing, as a tab's mark (`glassBellIconGlow`), "Bell rang" to VoiceOver. A glow beneath the
  whole row, as a sidebar row's, lay over the text like a highlighter on the iPhone's light list (simulator).
- **The bell kept on the tmux session (D108):** `TerminalTmux.bellOption` `@glass-bell`, set by the session's own
  `alert-bell` hook (`bellHookArguments`, target `=name:`; `=name` alone is refused by set-hook) as the bell passes
  through tmux, whoever is attached; cleared (`clearBellArguments`) by the device that shows the terminal.
  - Set up at each remote attach (`TerminalSession.keepBellOnSession`) and as a Mac pane first shows a local session
    (`MacLocalTmux.keepBell`, once per session per run).
  - Read in Active's listing (`listFormat`, 16 fields, the bell before the title) and in a pane read and the Mac's
    contexts (`contextFormat`, 8 fields): a running row's symbol orange (`GlassRunningSession.bellRang`); a down
    terminal here, or a connected one whose read says it, unseen here (`TerminalBellNotice.sessionKeepsOne`).
  - `TerminalBellNotice.clearsSession`: called when the terminal comes into sight, or rings in sight, while the
    session may keep one; false (not connected) leaves it for the next time it is seen.
- **Gathering sets:** `GlassOpenSession.tabGroupID` (off the Mac, the workgroup's id); `GlassCapability.gather`
  (`GlassTerminalCapability`: `TerminalTabMoves.gather`, each terminal after the destination's, the destination
  keeping the terminal it showed; what doesn't fit, 32 a set, stays and is named). Active's selection chooses those
  rows (`GlassActiveSelection.chosenSets`); Open N Together gathers into the first and opens running sessions there;
  Open N as Tabs In into the window chosen. Select was off with no running session: every row his.
- **Names while down:** `TerminalSession.nameWhileDown`: a terminal down and unread since it connected is named by
  the machine's last listing (`tmuxWhileDown`), as its subtitle already said where it is.
- Help: `terminal-sessions.md` (the bell in Active, kept on the session), `terminal-tmux.md` (gathering windows),
  `library-connect.md`. RELEASE-NOTES 0.4.620.

## Validation
- **Unit:** `TerminalSessionNamesTests.downNamedByTheListing` (4 checks failing without it);
  `TerminalTabMovesTests.gatheredIntoOne` (5 issues with the gather broken); `GlassActiveSelectionTests`
  `gathersSetsOpenHere`, `oneSetIntoAnother` (11 issues with sets unchoosable); `TerminalBellNoticeTests.
  keptOnTheSession` (6 issues without the clear); `TerminalTmuxTests.richListing` (the bell field; failing with it
  unread); **live** `TerminalTmuxTests.bellLive` on a private tmux server: no hook keeps nothing; the hook keeps it
  detached and with a control client on the window (tmux's own flag stays 0); the listing and a pane read say it;
  clearing takes it away. It failed with the hook's target `=name` (refused), which is how that was found.
- **Suites:** Mac terminal 1,286, shell 428; iPhone and Vision Pro simulators 874 each (2026-11-16).
- **UI, iPhone simulator (a simulator made for each run):** `ActiveBellUITests` (the `terminal-tabs` demo's bell, not
  `terminal`'s); seen failing with the bell unread. `TerminalMoveOnIPhoneUITests`: a set's only terminal into another
  from the name menu (passes: the black screen not reproduced); two sets gathered from Active (seen failing with sets
  unchoosable).
- **The black screen:** no crash or Jetsam report for the app on the phone; its log shows a launch at 22:16. `log
  collect` refuses a phone on Wi-Fi ("Device not configured"). Not pursued, at his word.
- **Installed at his word** ("install it everywhere", 2026-11-16): Mac, iPhone and headset read back 0.4.620 (620);
  no Mac crash report; every `glass-` tmux session on the Mac carries the `alert-bell` hook once the app reattached.
- **Not yet:** a real Mac and iPhone together (a bell on the Mac seen in the phone's Active); the visionOS gather.
