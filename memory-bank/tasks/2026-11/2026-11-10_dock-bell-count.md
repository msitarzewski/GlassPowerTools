# The Dock counts the terminals that rang out of sight (2026-11-10)

## Task
- **Asked (the owner, 2026-11-10):** "badges for the number of terminals that need attention. We have the orange
  glow in the tab, the pulsing in the dock icon, etc. but nothing in the dock if the user is on another virtual
  desktop or has windows covered."
- **His choices (asked, since macOS needs a permission for it):** the permission asked "at the next launch"; "dock
  count, notification, or both (in settings)".
- **Scope:** the Mac. Not committed.

## What was there
- A bell rung out of sight was already kept (`TerminalBellNotice`, 2026-11-03) and shown on its tab, orb and card.
  On the Mac a tab is in sight only when it is in front in a window whose occlusion state is visible
  (`MacWorkspaceView`), so a window on another desktop, covered or minimized already left its bells unseen; nothing
  outside the window said so.

## What changed
- `macOS/MacBellBadge.swift` (new):
  - `MacBellBadge`: the count of unseen terminals across every window's tabs and panes
    (`MacWorkspaceController.unseenBellCount`), on `NSApp.dockTile.badgeLabel`, followed by observation.
  - `MacBellNotifications`: a notification per terminal as its bell goes unseen, "*name* rang its bell", silent,
    taken back once seen; a click selects its tab and pane and brings its window forward
    (`MacWorkspaceController.paneID(holding:)`).
  - `MacBellOutOfSight` and its setting: Dock Count (default), Notification, Both, kept on this Mac
    (`bellOutOfSight`).
- `TerminalBellNotice.onUnseen` / `onSeen`: told once per change.
- `GlassSystemNotifications` (GlassConnectionUI): authorization with given options, `remove(identifiers:)`, user
  info, one delegate for the app with click handlers by thread. The desktop's notices use it (behaviour unchanged).
- `MacTerminalAppDelegate.applicationDidFinishLaunching`: starts both and asks for alerts, badges and sounds, except
  in UI-test runs unless `--ask-notifications` is given.
- Settings ▸ Connections ▸ Notifications: **A bell rung out of sight** (Mac).
- Help (bell section, settings), release notes 0.4.615; PRIVACY.md's permissions now list notifications (the Mac's
  ask at launch, and the two settings that already asked: **Notify when a query fails**, **Important Session Notices**).

## Validation
- **Unit** (`MacBellBadgeTests` 7):
  - The count, and whether one seen drops out.
  - The count followed by observation.
  - The setting and its default; no badge for Notification alone.
  - The notice's hooks, once each.
  - The notification posted, taken back when seen, and a click choosing the tab and bringing its window forward.
  - Seen failing:
    - with the per-tab count constant;
    - with the setting ignored;
    - with no take-back;
    - with the hook on every ring.
- **macOS VM, the real app:**
  - Without permission, the count reached 2 and the app set the badge (its log), but macOS drew none. Other developers
    report the same (Electron's badge count, OpenJDK). This Mac's notification settings had no entry for the app: it
    had never asked.
  - With permission given (Allow pressed through Accessibility):
    - The badge read 2 with both bells rung and the window minimized, and 1 with the window back and its front tab
      seen. None after quitting.
    - The Dock picture shows the red 2.
    - The banner "alpha rang its bell / ann@192.0.2.10:22" was pictured.
    - The log shows both delivered and one withdrawn when seen.
  - The demo rings only tabs shown once (their terminal draws); the check showed both tabs first.
  - A launch in the VM that put `--ask-notifications` before `-bellOutOfSight both` opened no windows. AppKit took
    the stray "both" for a file to open, and an opened file brings up no Connections window (D72). With the flag
    last, the request ran and both windows opened, so this came from how the script ordered its arguments.
- Suites: Mac `GlassTerminalTests` 1,271; `GlassShellTests`, `GlassDesktopTests` passing; `GlassConnectionUITests`
  67 after one fix: `GlassBottomOrnamentTests.noSceneDrawsItsOwnBottomBar` failed on the Vision Pro type-ahead
  chips' ornament (`TerminalWindowView`, since `6c7a03aa`; the suite hadn't run since). Not a bar of controls but
  D102's chips, placed by his choice: recorded in the test's list of allowed ornaments with that reason.
- **Not checked:**
  - another desktop (Spaces) in the VM. Minimizing gives the same occlusion state.
  - his Mac's first-launch prompt.

## Next
- 0.4.615 on the Mac (and the iPhone and headset with it); his Allow at the prompt.
