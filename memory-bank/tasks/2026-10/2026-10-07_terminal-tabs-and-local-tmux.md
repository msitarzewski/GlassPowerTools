# 2026-10-07 — Terminal tabs: one row shape, names, activity, Finder drop, local tmux (D47)

**Owner:** the owner. **Authorization:** local edits, tests and builds; commits and installs only on
the owner's word (the owner approved one Mac install "after these changes", D48 below). **State:**
built and tested, not committed; 0.4.288 built for macOS, iOS and visionOS, on the Vision Pro.

## What the owner asked

1. The Workgroups list on the shared row: "The blue dot should be aligned with the Workgroup name,
   and each line should show both the name and the tab count" — and "Consistency is the key …
   row heights should not fluctuate".
2. "We need to be able to rename terminal tabs … do better by default than the location of
   terminal … Edit in either the title bar or in the tab sidebar."
3. "If the tab has motion, I'd like to see the progress wave under the tab background", and a file
   dragged from the Finder should land as a path "like Apple's Terminal".
4. Dogfooding: the owner runs an agent inside the app's local terminal, so installing a new build
   ends it. Agreed: local tmux. "Terminal gets 'Keep local terminals running with tmux'. We use it
   for SSH already." (D47.)

## What was built

| Piece | Where |
|---|---|
| Library row: colour dot beside the name; the second line one fixed height, so every row kind is the same height | `Sources/GlassConnectionUI/GlassLibraryComponents.swift` (`GlassLibraryConnectionRow`) |
| Workgroups rows (saved and live) on that row: name, then "N tabs" / "N live tabs" | `Sources/GlassTerminal/TerminalWorkgroupsView.swift` |
| Automatic tab name: the title the shell or program set, else its directory (`~`, `/`, last part); a given name wins | `macOS/MacWorkspaceTabNaming.swift`, `MacWorkspaceController.windowIdentity` |
| Local shell directory read from the process (`proc_pidinfo`) 300 ms after output settles — macOS zsh reports OSC 7 only to Terminal.app | `GlassTerminalEmulator/SwiftTermHostView.swift` |
| Rename in the sidebar (double-click, or Rename Tab…; Use Automatic Name) and in the editable window title; kept across a relaunch | `macOS/MacWorkspaceView.swift`, `MacWorkspaceController.rename(to:)` |
| Activity wave behind a busy tab's sidebar row; a static tint with Reduce Motion | `macOS/MacTerminalActivityWave.swift` |
| Finder drop into any pane: paths escaped the way Terminal.app does (`$'…'` for control characters), bracketed paste when the program asked for it | `TerminalDroppedPaths.swift`, `SwiftTermHostModel.insertDroppedText` |
| **D47 local tmux** — below | `macOS/MacLocalTmux.swift` and the workspace files |

### D47: local terminals kept in tmux

- **Setting:** Settings → Terminal → Local Terminal → *Keep local terminals running with tmux*.
  Off by default. Disabled with "Install it with Homebrew (brew install tmux)" when tmux is not found
  on the app's PATH or in `/opt/homebrew/bin`, `/usr/local/bin`, `/opt/local/bin`.
- **Launch:** a local pane runs `tmux -T sync,RGB new-session -A -s glass-N -c <dir>` directly (a
  chosen shell is passed as the session's command). `-T` tells tmux this terminal takes synchronized
  frames and 24-bit colour; with TERM=xterm-256color alone it would send neither. tmux starts the login shell, so PATH and prompt match a
  plain local tab.
- **Names:** `glass-N`, the first not on the Mac's tmux server and not chosen by another pane in this
  run. Saved in the pane's restoration record (`MacWorkspacePaneIntent.localTmuxSession`, validated:
  local panes only, `glass-N` only), so a relaunched tab reattaches. ⇧⌘T's repeated tab gets its own.
- **Ending:** closing a pane, a tab or a window ends its session (`tmux kill-session`); quitting the
  app leaves every session running (`MacLocalTmux.applicationIsTerminating`, set in
  `applicationShouldTerminate`). A tmux client that exits by itself — the session ended, or someone
  detached — kills nothing.
- **Confirmations:** quitting no longer asks about local terminals in tmux, and says they "keep
  running and reopen with the app" when it asks for another reason. Closing a tab asks when a tmux
  pane runs anything other than a shell (`list-panes … #{pane_current_command}`), because the tmux
  client has no child processes to inspect.
- **Names and directory in tmux:** tmux keeps titles and directory changes to itself, so once
  output settles the tab asks tmux (`display-message … #{pane_current_path}`, `#{pane_title}`;
  tmux's default title, the host name, is ignored). Open Folder Here, the AI assistant and Save as
  Workgroup use the directory tmux reports.
- **SSH:** the exec-channel tmux commands (list, current path, kill) append Homebrew's folders to
  PATH, so an SSH connection to a Mac finds its tmux — the way to pick these sessions up from
  another device (the Mac needs Remote Login and a Terminal service in the library).
- tmux queries use `posix_spawn` + `waitpid`: `Process.waitUntilExit` spins the main run loop.

## Validation

- `swift test` (2026-10-07): terminal **443 passed** (9 new in `MacLocalTmuxTests`), shell **208
  passed**. `GlassLibraryRowConsistencyTests` fails on the old row; `MacLocalTmuxTests` fails when
  closing ignores the quit flag or a detach (both mutations run, both caught, file restored).
- Release Mac build 0.4.287 succeeded. **Not installed** (installing ends the owner's session).
- **Live, tmux 3.7c on a private socket (`-L`), not the owner's server:** `list-panes -s -t =name`
  answers `zsh` idle and `sleep` while busy; `display-message -t =name:` gives the folder and a title
  a program set; a missing session exits 1 (read as "running", so closing asks); `-T sync,RGB` is
  accepted on `new-session`. (zsh expands a bare `=glass-1` argument; quote it when testing by hand.)
- **Not run:** the app itself driving a real tmux (not installed yet).
- **Not seen by the owner:** Workgroups rows, rename, the wave, Finder drop, local tmux.

## Next

1. The owner installs tmux (`brew install tmux`), then the 0.4.287 install (ends this session;
   resume with `claude --continue`), then turns the setting on and opens a new local tab.
2. Check live: relaunch reattaches; closing a tab ends the session; detach (prefix d) closes the
   pane and leaves the session; the tab name follows `cd` and program titles.
3. Commit in logical pieces on the owner's word: row consistency; tab names and rename; activity
   wave; Finder drop; local tmux.

## Finding: why TUIs draw roughly here (owner, 2026-10-07)

The owner saw `claude -c` scroll its history in visibly (Terminal.app shows it at once) and odd jumps
while Claude Code works. Evidence from Claude Code 2.1.293's bundled code (strings of the installed
binary):

- It sends XTVERSION (`CSI > 0 q`) first. **Only if the terminal answers** does it ask DECRQM 2026
  (synchronized output); otherwise synchronized output stays at its default, off.
- Scroll regions (DECSTBM) are enabled only when synchronized output is on (and not in tmux, Zellij,
  JetBrains, VS Code or Windows Terminal). So here every update is a plain repaint by cursor
  movement, drawn mid-repaint by SwiftTerm's 60 Hz display timer.
- `CLAUDE_CODE_FORCE_SYNC_OUTPUT=1` (undocumented) forces it on outside tmux: a way to test the
  diagnosis without a build.
- SwiftTerm 1.18 (our exact pin) does not answer XTVERSION; it does implement mode 2026 and answers
  DECRQM 2026, and holds drawing while a synchronized frame is open. **SwiftTerm 1.19 and 1.20
  answer XTVERSION** (`cmdXTVERSION`, identity `SwiftTerm(<version>)`), checked in their sources.
- Local terminals get SwiftTerm's minimal environment: TERM, COLORTERM, LANG, LOGNAME, USER, HOME.
  No `TERM_PROGRAM`, `SSH_AUTH_SOCK` or `TMPDIR` (observed from inside the app's local terminal).
  Terminal.app passes the full login environment and `TERM_PROGRAM=Apple_Terminal`.
- In local tmux, Claude Code talks to tmux (which answers both probes), and tmux's drawing into
  SwiftTerm is governed by `-T sync,RGB` above.

## D48: SwiftTerm 1.20, the Mac's environment, and the update check (owner's choices, 2026-10-07)

- **SwiftTerm 1.18 → 1.20** (`Package.swift` exact, `Package.resolved`, Xcode's pins, acknowledgements
  revision; licence text unchanged). 27 commits: XTVERSION reply, Ghostty terminfo capabilities,
  DECSET 1007 (wheel → arrows in full-screen programs), OSC 8 fix, kitty keyboard work, Metal renderer
  recovery from stalled frames, iOS view changes (+315/−29). Its build-tool plugin runs `git -C
  <SwiftTerm checkout>` only, to stamp a version. `xcodebuild` now needs `-skipPackagePluginValidation`
  (added to `Tools/Release/release-mac.sh`, `Tools/Screenshots/capture.sh`, `Documentation/BUILDING.md`).
- **`TerminalCapabilityProbeTests`:** XTVERSION, DECRQM 2026 (reset, and set while a frame is open),
  2004, 47, DA1 and the kitty keyboard query are answered. 1049 is not reported by DECRQM in 1.20.
- **Environment:** `MacLocalTerminalConfiguration.environment(from:version:)` passes the app's
  environment minus another terminal's identity, `TMUX`, loader/debugger settings and the launchd job
  name, plus `TERM=xterm-256color`, `COLORTERM=truecolor`, `TERM_PROGRAM=GlassPowerTools`,
  `TERM_PROGRAM_VERSION`, and `LANG` when the Mac set none.
- **Update check:** `Tools/Packages/check-updates.py` (survey; `--test NAME[@VERSION]` / `--test newer`
  in a temporary worktree with this checkout's committed and uncommitted state; acknowledgements and
  Xcode pins regenerated there as a real raise would; every test target, then Debug app builds for
  macOS, iOS, visionOS). `Tools/Packages/install-weekly-check.sh` installed a LaunchAgent
  (`com.glasspowertools.dependency-check`, Mondays 08:00, reports in `~/Library/Logs/GlassPowerTools/`).

### Validation

- Every test target passes on SwiftTerm 1.20 (`swift test`, exit 0; one pre-existing known issue).
- Release builds 0.4.288 succeeded for macOS, iOS and visionOS (`-skipPackagePluginValidation`).
- The update check, live: survey found 8 of 30 pins behind. `--test swiftterm@1.18.0 --platforms none`
  **failed as it should**: the XTVERSION probe test fails on 1.18, so the test and the tool both catch
  the regression; the worktree was removed afterwards. A first run also failed
  `AcknowledgementsTests` because the tool had not regenerated acknowledgements — fixed.
- Installed and running on Vision Pro and iPhone (0.4.288, `devicectl device info apps`). Mac: not yet —
  the detached installer's quit request timed out at the app's quit confirmation; stopped unchanged.
- **Not run:** Claude Code on the new build (needs the Mac install); device checks of the SSH terminal
  on iPhone and Vision Pro with SwiftTerm 1.20 (owner); the weekly run itself (first due Monday).

## Vision Pro crash on 0.4.288 (owner, 2026-10-07)

Three reports from the headset (`devicectl … --domain-type systemCrashLogs`):
- 22:48:48, 50 s into a session with SSH connections open: SIGSEGV in SwiftUI's stack layout
  (`HVStack.updateCache` → `swift_release`), during a preferences update in a render pass. No frame
  of ours on the stack.
- 22:48:56 and 23:12:30, under a second after launch: an assertion in SwiftUI's
  `AppSceneDelegate.makeSceneHostWindow(restorationSceneItemID:…)` while connecting a restored scene.
  The report carries no message; collecting the device log needs root. A launch through `devicectl`
  at 23:16 did not crash. No scene declarations changed since 0.4.283.
- **Inferred, not proven:** this build made `SwiftTermHostModel.terminalTitle` `@Published`, so every
  title change re-rendered every terminal window on every platform; Claude Code's animated title does
  that several times a second. Fixed regardless: the title is a plain property with an
  `onTerminalTitleChange` callback that only the Mac's self-naming tabs set, and the Mac applies tab
  names at most twice a second (`paneContextInterval`, tested). Terminal tests: 450 pass.
- 0.4.289 (visionOS) installed on the headset. Pending: the owner opens it from the home view; if the
  startup assertion recurs, its message comes from `sudo log collect --device-udid …`.

## Closing detaches (owner, 2026-10-07): "the warning that the session will end also ends the tmux session so I can't resume it"

- Closing a local pane, tab or window detaches; nothing kills a session except Active's End or
  `exit`. `removePane` lost `endsTmuxSession`, and `MacLocalTmux.applicationIsTerminating` is gone.
- `closeStopsWork` and `focusedPaneCloseStopsWork` leave local tmux terminals out; the tab-close
  "running commands in tmux" warning is gone; the pane's tools menu says **Detach**, unconfirmed.
- Active lists this Mac's sessions under This Mac (the Local Shell service's endpoint), less those a
  tab here shows (`MacLocalTmux.shownHere`, counted per pane): **Open** (`.localTerminal(tmux:)`, a new
  window whose pane attaches), **Take Over** (`detach-client -s`, then open), **End** (`kill-session`).
  A pane may now hold one of the user's own session names (`TerminalTmux.isValidSessionName`).
- Tests: terminal 450 pass (`closing`, `confirming`, name validation rewritten).
- **Vision Pro 0.4.289:** the owner reports it "starts and runs fine". Also reported: favourites do
  not sync (to look at separately). The headset's first crash came when the app's window first
  appeared, with nothing open — so the title-publishing theory is not shown to be the cause.

## Headset lockout and the reattach gap (2026-10-07, late)

- **Vision Pro startup assertion, found:** `devicectl device process launch --console` printed
  "SwiftUI/UIKitAppDelegate.swift:1659: Fatal error: Your app was given a scene with id 'main' but the
  matching Window in your app body is already connected." After a crash visionOS kept two sessions for
  the singleton `Window("Connections", id: "main")` and stopped every launch, a reinstall included.
  Fixed in 0.4.292: the headset's Connections scene is a `WindowGroup` keyed by one fixed value
  (`GlassConnectionsWindow`), so opening it again still brings the one window forward and a second
  saved session cannot be fatal. Installed; launched cleanly twice, no new report.
- **The crash that started it** (SwiftUI stack layout, an over-release; opening a terminal, and once
  as the library first appeared) is not yet explained. 0.4.291 changed the library row's fixed
  second-line height to a plain `minHeight` from the system font's line height (no hidden text, no
  zero-width spacer); whether that was the trigger is unproven until the owner opens terminals on it.
- **Reattach after quit did not happen** (Mac 0.4.291 install, this session survived in tmux but no
  tab came back): macOS's "Close windows when quitting an application" (default on;
  `NSQuitAlwaysKeepsWindows` unset) restores no windows after a quit. Now the app records windows
  holding local tmux terminals as it quits (`MacLocalTmux.rememberWindowsToReopen`) and reopens them
  at launch (`takeWindowsToReopen`, from `TerminalConnectFlow`), unless macOS restores windows itself,
  one is already open, or its tabs are no longer saved. Tested (451 terminal tests pass); in source,
  not yet in an installed Mac build. The owner reattached meanwhile through Active → This Mac.

## Scrolling in local tmux (owner, 2026-10-08): "tmux is eating the scroll … only scrolling previous claude code messages"

- Cause: tmux draws on the alternate screen, so the terminal has no scrollback; with tmux's mouse
  off, SwiftTerm 1.20 (DECSET 1007, as Terminal.app does) sends a scroll as ↑/↓, and Claude Code
  reads ↑ as "previous message".
- Not taken: tmux `mouse on` — a plain drag would then select in tmux, and its copies reach the
  clipboard only by OSC 52, which our policy denies by design.
- Done: `SwiftTermHostModel.onAlternateScreenScroll`; the local engine watches scrolls over its view
  with an `NSEvent` local monitor (SwiftTerm's `scrollWheel` is not open) and offers those on the
  alternate screen with no mouse mode requested. A local tmux pane takes them: points → lines
  (16 pt a line; a wheel's are lines already), gathered for 30 ms, sent on one serial queue as
  `copy-mode -e -t =S: ; send-keys -t =S: -X -N n scroll-up` (down: `scroll-down`; `-e` leaves the
  history view at the bottom). Verified on tmux 3.7c (private socket): positions 5 → 3, exit past
  the bottom. Native selection is untouched. Tests: 452 terminal, 208 shell pass.
- Installed: Mac 0.4.293, iPhone 0.4.293, Vision Pro 0.4.292. The Mac install was quit by 0.4.291,
  which does not record windows yet, so this once the owner reattaches through Active; from 0.4.293
  on, quitting records them. Three saved window states mention a tmux tab (two likely stale).
- tmux's own history view takes keys as copy-mode commands until it is left (scroll to the bottom,
  or `q`); typing does not snap back as it does in a plain terminal. Not changed.

## Scrolling over SSH, favourites, and This Mac elsewhere (2026-10-08)

- **SSH tmux scrolling (Mac):** the scroll watcher (`MacAlternateScreenScrollWatcher`) now serves the
  SSH engine too; `TerminalSession.scrollTmux` sends `TerminalTmux.scrollCommand` over the session's
  exec channel, one at a time, gathering scrolls while one travels. A live test runs the command
  through `sh` against a private tmux (`TMUX_TMPDIR`). iPhone, iPad and Vision Pro: SwiftTerm's iOS
  view never turns scrolls into arrows, so scrolling in tmux there probably does nothing; wiring
  their gestures to the hook is not done.
- **Favourites (D49):** built; `GlassFavoritesSyncTests` (merge rules, two devices over a shared
  in-memory store, This Mac kept local); the two-device test fails without the push (checked).
- **This Mac from the Vision Pro (D50, proposed):** the library has no Terminal service for the Mac's
  synced record — only two other machines' Terminal services — so the headset had nothing to
  check. Remote Login is on (port 22 answers locally).
- All test targets pass (`swift test`, exit 0). 0.4.294 built for macOS, iOS, visionOS; not installed.
- **Installed 0.4.294 on all three (2026-10-08 00:50).** Mac: quit by 0.4.293, which recorded the tmux
  window; 0.4.294 reopened it and a client attached to the session one second after launch
  (`tmux list-clients`), with no step from the owner — **D47's reattach after a quit, verified live**.
  The reopen record was taken and cleared. Vision Pro relaunched with no new crash report.

## Committed, and SSH scrolling everywhere (2026-10-08, ~01:10)

- Committed in pieces: 24ca9af rows, b64f664 SwiftTerm 1.20, bc734b6 update check, ed851ec tabs
  (built and tested on its own in a worktree: 440 terminal tests), 1074d5a local tmux + environment +
  Mac scrolling, a924c9d headset Connections window, f2f304e favourites, ca2e62b + 7db0ba3 notes
  (ca2e62b's task note named a private machine; 7db0ba3 removes it — the history keeps it until the
  pre-publication scrub), c60f280 iOS/visionOS scrolling + safe tmux naming.
- **A Vision Pro opened the Mac's terminal over SSH** (the owner added a Terminal service for the
  Mac's synced record) and landed in the Mac's running `glass-1` — this session — instead of a new
  one: the only way a new terminal gets `glass-1` while it is taken is a failed or empty listing.
  Cause of the failure not yet known (the headset's log needs `sudo log collect`). Now: the list is
  asked again once, and unlisted names are `glass-N` with N ≥ 100 (test fails on the old fallback).
- iOS/visionOS: `UIKitAlternateScreenScrollWatcher`, a pan (touch, trackpad scroll, pinch-drag) on
  the alternate screen with no mouse mode → `onAlternateScreenScroll` → `TerminalSession.scrollTmux`.
  Not seen on a device yet.
- 0.4.295 installed on Mac, iPhone, Vision Pro. No tab was attached to the session at the Mac's quit,
  so nothing reopened; the owner reattaches through Active.

## Workgroups sync (D51) and the headset crash, continued (2026-10-08, ~01:45)

- D51 built: `ICloudWorkgroupsPayload`, `SettingsManager.workgroupsPayload/applyWorkgroups`, tombstones
  (`layoutPresetTombstones`), started with the terminal's iCloud switch. `WorkgroupsSyncTests`: merge
  rules; two devices over a shared in-memory store (save arrives, opening sends nothing, deleting
  travels); the two-device test fails without the push. Terminal: 457 pass.
- Headset crash: four Release crashes (0.4.288–0.4.295) in SwiftUI stack layout, over-releases with
  garbage pointers, each while a terminal showed this Mac's tmux session running Claude Code (tmux on
  another host was fine). An Address Sanitizer debug build attached to the same session for 20+
  minutes, resized, did not crash and reported nothing. A desktop in that build overflowed the stack
  in `performRDPGraphicsDynamicChannelHandshake` (sanitizer frames are larger; Release connects
  fine). The headset runs xrOS 27.2 beta 24N5103f. Cause unknown; the debug build is still installed.
- 0.4.294's CPU report: 50% CPU for three minutes while attached — mostly the terminal's CoreGraphics
  drawing of Claude Code's constant redraws.
- Owner's idea, not started: drag terminal tabs between windows to consolidate them.

## Draggable tabs, and Active not listing the Mac until connected (2026-10-08, ~02:00)

- 0.4.296 installed on all three (the Mac reattached on its own; the headset has the normal build back).
- Draggable tabs built and committed (51d585f): sidebar rows drag a private type; `onInsert` on the
  tab list takes them; `MacWorkspaceWindowController.acceptDroppedTab/moveTab/detachTabForMove/
  adoptTab`; a window whose last tab leaves keeps a placeholder and closes. 461 terminal tests pass.
  Mac 0.4.297 built, not installed. Not yet tried by hand.
- Owner: the Mac's tmux session "doesn't show in Active until I connect manually". Expected only if
  the headset cannot sign in without asking (password not saved there, or host key not yet trusted):
  Active's probe never prompts and skips silently. To check: whether the Mac's Terminal service has a
  saved credential on the headset; Active should say why a machine was skipped.

