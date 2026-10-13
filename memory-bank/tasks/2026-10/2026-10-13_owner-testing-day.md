# 2026-10-13 — the owner testing: Duo, headset, desktops, Show All Windows, terminal windows, database errors

**Objective:** fix what the owner found while using 0.4.392 → 0.4.399 on the Mac, the Vision Pro, the iPhone
and the iPhone Duo simulator, and clear agent-side tier-3 items in the time between his reports.
**Owner:** the agent (coordinator); every report and every choice below is the owner's.
**Authorization:** "go with your recommendations, commit each piece as it lands"; Mac builds installed when
ready (he accepted each one today). Nothing pushed.
**End state (13:25):** **0.4.400 on the Mac, Vision Pro and iPhone**; no new crash reports; the working tree is
clean. The owner confirmed the last fix ("+" ▸ New Terminal on): "it works".

## Overnight, before the owner was up (tier 3)

| Item | Commit | What changed | Evidence |
|---|---|---|---|
| tree-sitter capture-pool overflow | 0b5d421 | The highlight cursor's match limit (256, as Helix uses) instead of vendoring the runtime | No limit down to 64 changes a match on 16 real files in 14 languages |
| B-X5 | 9ee28f3 | Each subscriber of a transport's events gets its own stream (`SSHTransportEventBroadcast`): every terminal on a lost shared connection says so; none closes as if exited | Unit test; gated live test through a relay that cuts the connection |
| B-X13 | 461dc59 | Local Network guidance only for "No route to host" or "policy denied" | Measured: a test runner without Local Network access gets EHOSTUNREACH at once |
| B-X18 | 44f6b2a | One true message for an SSH key that cannot be imported | Unit |
| B-X22 (first half) | be02fe5 | The editor's remote folder listing leaves out names that would leave the folder | Unit |
| B-X27 (found) | f522a6a, f5cbd32 | Files written with complete protection fail on a locked Mac: about 23 terminal tests, and live remote saves | Measured per protection class; **the owner's decision**, not changed |

## The owner's reports, in order

**Duo and phones (0.4.393–0.4.395).**
- The folded Duo's terminal showed a white corner; the terminal's colour now ignores every safe-area edge (f7ba758).
- "How do I get back to the main all connections?": the library keeps UIKit's own sidebar toggle on iPhone and
  iPad. **D24 amended** (a31e5d4).
- Phones present sessions in place even unfolded. Unfolded, a window took the whole inner display, and a phone
  cannot end a scene: "not supported for this device idiom", measured on the Duo simulator (dad7bda).

**Headset input (2f38ec4, 0.4.393).** Held delete repeats. It is a priority key command with `.repeatable`, whose
action is SwiftTerm's `deleteBackward`. The arrows repeat too. Selection: pinch and hold, then drag (the owner's
choice); hold on a selection's end to move it; Copy through `UIEditMenuInteraction`. **Unverified on the device:**
UIKit keys and gestures cannot be reached from the package tests.

**Desktops (dad7bda, b5ac1d7).** "This feels web … no way to get back":
- The disconnected state is the system's `ContentUnavailableView`, with the error as its description.
- An iPad desktop window sits in a `NavigationStack`, so its bar is drawn. Close ends the scene through UIKit.
- On a phone, "Desktop Not Found" says to close the window in the app switcher.
- `--demo-open desktop-disconnected` (DEBUG) shows the state.

**Show All Windows** (was Show All Terminals):
- **8b2fb4d.** "include all of our connection/service types … one component?" `GlassShowAllWindows` in the shell:
  the terminal sets the action and draws the overlay, and the button sits beside every ⚡. Databases, Desktops and
  Editor appear as groups after the terminal windows. A desktop's tile is its last frame.
- **1da944b.** The pinch moved to the shell (`GlassWindowPinch`, `GlassWindowPinchMonitor`) and works on desktop
  windows. Database and editor windows don't get it, because they pinch to zoom. "Clipboard sync is failing": it
  never failed. Share clipboard is off by default (a trust boundary), and the Clipboard menu now says so.
- **0f1e2ef.** A tabbed terminal no longer repeats under Other: it is left to its window's group, and Files
  browsers get their own group. The caption's second line is legible. **Settings ▸ Terminal ▸ Show All Windows ▸
  Blur previews**: this Mac's choice, not synced.

**App menu (922503f).** "This menu needs attention":
- Command Palette… was listed twice, once by the terminal and once by the database.
- The shell owns ⇧⌘P and ⌘K now (`GlassShellPaletteCommands`). Each capability registers its entries
  (`GlassCommandPaletteSources`), and a menu-bar test holds the one owner.
- Check for Updates shows only in a build configured for Sparkle (B-R1).

**A real crash (fd5a70d).** 0.4.393 aborted at 05:58 in Quick Look: `setPreviewItem` was called on a
`QLPreviewView` already showing a file. Each file now gets its own view (`.id(fileURL)`). Not reproduced here;
the fix removes the only call that crashed.

**Terminal windows' SSH panes (0.4.398 → 0.4.400).** "+ ▸ New Terminal on … these always fail".
- **795ce5d (0.4.398).** The log said `CancellationError`. The connection ran in the placeholder's `.task`, which
  SwiftUI cancelled when the placeholder gave way to the terminal; the task moved to the pane. The same commit:
  - Restored tabs wait for the saved hosts.
  - Retry is renamed Reconnect.
  - Every Close Pane closes the tab with its last pane.
  - Each sidebar tab row has a close box.
- **998a225 (0.4.399).** Panes that fill the tab are square: "rounded corners meeting square … these should be
  square". The owner confirmed it. A pane told its server was missing asks again when the server appears.
- **9ce83d9 (0.4.400).** "+" ▸ New Terminal on still failed, while All Connections worked. The pane's view task
  is cancelled too: a new tab is drawn, removed and drawn again as it settles. **The controller owns each pane's
  connection now** (`MacWorkspaceController.startSSHPaneIfNeeded`). The view only asks, and only closing the
  pane or the tab cancels it. The test fails with the view's old await (exactly the owner's
  `CancellationError`). **The owner: "it works."**

## Database errors (b1e9e3c) — found by measuring

The database's Local Network check looked for EPERM/EACCES. It was measured from a test runner without Local
Network access, against the test VM:

| Failure | MySQLNIO | PostgresNIO |
|---|---|---|
| Local Network denial | `IOError` "No route to host (errno: 65)", at once | `PSQLError(.connectionError)` around `NIOConnectionError` around the same; plain description generic, reflected one has it |
| Wrong password | `MySQLError`, readable | `PSQLError(.server)`; the user saw "The operation couldn't be completed. (PostgresNIO.PSQLError error 1.)" |
| Unknown host | `SocketAddressError.UnknownHost`, shown as "error 1" | the same inside `NIOConnectionError` |
| Refused port | `IOError` errno 61 | the same, wrapped |

Neither driver's error bridges to the POSIX domain, so the old rule never matched, and a MySQL denial was told
to turn on the tunnel. Other developers report the same "No route to host" on a Local Network denial (Apple's
developer forums, thread 765285).

- **One rule, in the shell:** `GlassLocalNetworkAccess` (`mayBeDenial`, `isLikelyLocalHost`, `advice`). The
  terminal's rule moved there, and both the terminal and the database use it.
- **PostgreSQL at its connect boundary:** `PostgreSQLEngine.connectFailure` turns a refusal into
  `DatabaseError.server(<the server's words>)` and a transport failure into the error MySQLNIO throws.
  `.sslUnsupported` becomes `tlsRequiredButUnavailable`.
- **Unknown host:** `DatabaseConnectionFailure` now says "No machine named … could be found".
- **Queries unaffected:** they go through PostgresNIO's older API, whose `PostgresError` reads well.
- **Tests:** they use the drivers' own failures: an `.invalid` name and a refused loopback port, plus a gated
  wrong password against the test server. Each fails with the change undone.

## B-X5's leftover — closed by design (cf5c64e, D69)

Database and desktop tunnels keep their own SSH connections; reasons in D69 and at `GlassTerminalPortForward`.

## Housekeeping

- Two uncommitted edits had been carried as "the owner's": a one-space README change and an agent's arrow-key UI
  probe (written 2026-10-11). Neither was his; both were discarded at his word (96f9771).
- **Rule 61:** three code comments and this day's notes quoted the owner's machine and tab names; they were
  neutralised. The messages of 998a225 and 1da944b quote two of them. Under the owner's earlier ruling (no history
  rewrite for messages, "just keep moving forward"), they are left and listed here.
- Mermaid 12.2.0 came in through the build's pre-action (D35), as expected (e62babd).

## Validation

- Suites with the screen unlocked: terminal 781, database 280, DBKit 321, shell 28. The owner's tmux sessions
  were unchanged by every run (md5 of `tmux list-sessions` before and after).
- Release builds for macOS, iOS and visionOS on every version from 0.4.392 to 0.4.400.
- Devices:
  - 0.4.400 is installed on all three.
  - The owner confirmed the square corners (0.4.399) and "+" ▸ New Terminal on (0.4.400).
  - No new crash reports after each install.

## Open, carried to `activeContext.md`

- **The owner's:** B-X27 (protection class; recommended complete-unless-open for recordings and downloads); the
  unfolded Duo tour; B-X10/B-X11; B-X4; headset selection and held keys on the device; B-V4 two-device run;
  B-R1–R7; B-Q28.
- **Agent:**
  - The database still removes the sidebar toggle off the Mac (`databaseSidebarChrome()`; see D24's
    amendment).
  - B-X22's second half.
  - Tier 3 continues: B-X2/B-Q11, B-X6/B-F32, B-X7.
