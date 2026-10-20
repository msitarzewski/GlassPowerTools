# 2026-10-18 — Accessibility audit, for the App Store's Accessibility Nutrition Labels

**Objective.** Honest Accessibility Nutrition Labels for iPhone, iPad and Vision Pro. The Mac is not
on the App Store. Also fix whatever fails without changing anything anyone sees.
**Authorization.** The owner, 2026-10-18: "accessibility: yes".
**Owner.** A forked agent, in its own worktree. Nothing was committed, pushed or uploaded.
**Not changed.** Anything visual: colours, contrast, sizes, layout, glass, transparency, motion.
Those are proposals for the owner (below).

## Apple's criteria

A feature is "supported" only when a person can complete all of the app's **common tasks** with it.
Common tasks are what the description and screenshots market, first launch, and Settings.
Here they are:
- browse the library;
- add a host and a service;
- connect;
- use the session (terminal, database, remote desktop, editor);
- disconnect;
- change Settings.

The labels are voluntary for now. Remote content, such as a remote desktop's screen, counts as
third-party content: the app's own controls must be accessible, but that content need not be.

The criteria, one page per feature:
- [Overview](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels)
- [VoiceOver](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/voiceover-evaluation-criteria)
- [Voice Control](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/voice-control-evaluation-criteria)
- [Larger Text](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/larger-text-evaluation-criteria):
  at least 200% of the default size.
- [Dark Interface](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/dark-interface-evaluation-criteria):
  this includes "text remains readable with Dark Mode combined with Increase Contrast".
- [Differentiate Without Color Alone](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/differentiate-without-color-alone-evaluation-criteria)
- [Sufficient Contrast](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/sufficient-contrast-evaluation-criteria):
  4.5:1 for text, 3:1 for controls.
- [Reduced Motion](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/reduced-motion-evaluation-criteria):
  scaling, depth, spinning and ongoing motion must stop or change.
- [Captions](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/captions-evaluation-criteria)
- [Audio Descriptions](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/audio-descriptions-evaluation-criteria)

## Method

`UITests/AccessibilityAuditUITests.swift` runs Xcode's `performAccessibilityAudit` over 17
surfaces, reached through the demo hooks: `--ui-testing`, `--ui-testing-seed-hosts`,
`--demo-open`, and `GlassDemoMode.shopDatabase`. The surfaces:

| Group | Surfaces |
|---|---|
| Library | library, overview, Add Host, a machine's page, Settings, Active, workgroups |
| Terminal | terminal and its settings, the file browser |
| Database | database and its settings |
| Remote desktop | desktop, its settings, disconnected |
| Editor | editor and its settings |

Runs, all on simulators:

| Device | Runs |
|---|---|
| iPhone 17 Pro Max | default text size, the largest accessibility size, Increase Contrast on |
| iPad Pro 13-inch (M5) | default size and the largest size, **each test on a fresh install** |
| Apple Vision Pro | default size |

- **The audit API on visionOS:** it is declared only for iOS, macOS, tvOS and watchOS, but it
  compiles and runs on visionOS, so Vision Pro was audited too.
- **Why fresh installs on iPad:** iPadOS restores the windows a previous test opened. A dead
  database window ("Connection Closed") then covered the surface and invalidated a first pass.
- **Not run on a simulator:** Reduce Motion and Differentiate Without Color can't be switched on
  from the command line, so they were checked in the code. VoiceOver speech and Voice Control need
  a person and a device.

## Findings (before the fixes)

| | iPhone, default | iPhone, largest | iPad, default (fresh) | iPad, largest (fresh) | Vision Pro, default |
|---|---|---|---|---|---|
| Dynamic Type | 46 | 32 | 42 | 34 | — |
| Text clipped | 38 | 33 | 26 | 24 | — |
| Hit area | 18 | 5 | 26 | 5 | 3 |
| Contrast | 15 | 9 | 29 | 17 | 0 |
| No description / not human-readable | 4 / 0 | 4 / 0 | 0 / 7 | 0 / 7 | 13 / 7 |
| Possibly inaccessible text | 1 | 1 | 40 | 34 | — |

The iPad was audited after the label fixes, and Vision Pro after the iOS fixes. "Not
human-readable" is always a file name (compose.yaml), which is what the tab shows.

The iPad's "possibly inaccessible text" findings carry no element. They come from sheets (Add
Host, Settings and the settings pages), and the likely source is the dimmed window behind the
sheet, which is correctly hidden from VoiceOver. That needs a person to confirm.

With Increase Contrast on, the iPhone had the same 15 contrast failures: the colours do not respond
to it.

## Fixes (nothing visible changes)

**F1. Workspace tabs are named by their title.**
- **The problem:** a tab's spoken label was its tooltip. In the editor that is the file's
  folder, so every tab from one folder sounded the same, and Close named the folder. In the
  database it was "Table editor for main.orders" where the tab shows "orders", and Voice Control
  acts on what it shows.
- **The fix:** the label is now the title, and the tooltip is the hint. Database tabs get an
  identifier (`db-workspace-tab-…`), so tests can find a tab whatever its title.
  `GlassDatabaseUITests.testSQLDraftSurvives…` finds the SQL tab by that identifier now. That
  test needs a live MySQL server and was not run.
- **Files:** `GlassWorkspaceTabBar.swift`, `DatabaseWorkspaceView.swift`, `GlassDatabaseUITests.swift`.

**F2. The service icon on a machine's page has a name.**
- **The problem:** the drawn database icon had none, so VoiceOver read only its status.
- **The fix:** it is now labelled as the library row's icons are, and so is the icon in the SSH
  keys panel.
- **Files:** `GlassShellLibraryView.swift`, `GlassKeyManagerPanel.swift`.

**F3. The data grid's column-width handles are named.**
- **The fix:** each is "Width of <column>", says its width in points, and has an adjustable action
  (VoiceOver swipe up or down, ±24 pt).
- **Not tested:** XCUITest on iOS cannot send the adjustable action.
- **File:** `TableDetailView.swift`.

**F4. Vision Pro: no window-sized empty element.**
- **The problem:** every window's glass (`GlassSpatialWindowGlass`) reached VoiceOver as a nameless
  element the size of the window, despite `accessibilityHidden`. It disappeared with Glass at 0
  and came back with it on.
- **The fix:** `.accessibilityRepresentation { EmptyView() }` removes it. A capture of the library
  window shows the glass unchanged.
- **Ruled out:** zero-size background helpers (the probe and the sizer) were tried first and did
  not help. They were reverted.
- **File:** `GlassSpatialWindowGlass.swift`.

**F5. Vision Pro: the file browser's title menu is named** by its folder (`GlassSpatialColumns.swift`).

**Tests:** `UITests/AccessibilityLabelsUITests.swift` (iOS and visionOS). Each test failed without
its fix:

| Test | Without the fix | With it |
|---|---|---|
| `testEditorTabsAreNamedByTheirFiles` | no tab button named compose.yaml or README.md; no "Close compose.yaml" | passes on iPhone and Vision Pro |
| `testDatabaseTabsAreNamedAsShown` | no tab button "orders", no "Close orders", no identifier | passes on iPhone and Vision Pro |
| `testServiceIconsOnAMachinesPageAreNamed` | one unnamed element (the icon) | passes on iPhone and Vision Pro |
| `testColumnWidthHandlesAreNamed` | three unnamed handles | passes on iPhone and Vision Pro |
| `testTheLibraryHasNoUnnamedElements` (Vision Pro) | one window-sized element | passes |
| `testATerminalWindowHasNoUnnamedElements` (Vision Pro) | one window-sized element | passes |
| `testTheFileBrowsersTitleIsNamed` (Vision Pro) | one unnamed menu | passes |

`AccessibilityAuditUITests` fails only on an element with no name at all; every other finding is
printed as an `A11Y|…` line. After the fixes:
- **iPhone:** 17 of 17 pass.
- **Vision Pro:** 17 of 17 pass. What remains there: 8 small hit areas (P7, plus the labelled
  service icon, which is not a control) and 7 file names flagged as not human-readable.
- **iPad:** no unnamed element is left (fresh runs).

Its header says how to run it.

**Builds:**
- The iOS, visionOS and Mac app and UI tests compile.
- The Mac UI test that was changed was not run (it needs a live MySQL server).

**Regressions checked on Vision Pro:**
- The orb UI tests: 10 of 11 pass.
- `GlassConnectionsOrbUITests.testAMenuHoldsConnectionsOpen` fails with "host-connect-menu not
  hittable". It fails the same way on the unchanged code on this simulator, so it is not from
  these changes.

## Proposals for the owner (visual; not made)

Screenshots are in the maintainer's working folder, not in the repository (`a11y/proposals/`).

**P1. A machine's services at large text (iPhone and iPad).**
- **The problem:** at the largest sizes the service name and its kind shrink to "…", because
  Connect, Edit and More keep their place in the row.
- **The proposal:** at accessibility sizes, put the buttons under the name.

**P2. Database chrome at large text.**
- **The problem:**
  - on iPhone, "Filter" and "More" wrap a letter or two per line;
  - on iPad, the footer breaks "Cal-culate Total…";
  - tabs show "Ov…ew", and the title "o…".
- **The proposal:** at accessibility sizes, icon-only buttons with the Large Content Viewer, or an
  overflow menu.

**P3. Terminal text size.**
- **The problem:** the default is 14 pt and the maximum 24 pt, which is 171%. Larger Text asks
  for 200%, and the terminal is primary content. The database and editor reach 229–246% with
  their own settings.
- **The proposal:** raise the terminal's maximum to at least 28 pt.

**P4. Contrast** (it fails, and is the same with Increase Contrast on).
- **The problem:** these fail:
  - "Not synced on this build" in the library's footer;
  - Add Host's "Required", "Advanced" and "Also known as & Collections";
  - unselected tab text in the shared tab strip;
  - on iPad, the editor's sidebar and status bar and the desktop's status text;
  - the library's search placeholder nearly passes.
- **The proposal:** stronger styles, at least when Increase Contrast is on.

**P5. Reduced Motion.** None of these checks the setting:
- the busy orb's ring scales "again and again" (Vision Pro, ongoing motion);
- the All Windows pane scales in (iPhone and iPad);
- the terminal carousel turns in 3D (a chosen layout).

The Mac code already checks it in its Exposé and shimmer. The proposal: fades when Reduce Motion
is on.

**P6. Differentiate Without Color.**
- **The problem:** the availability dots (green, orange, red) differ only in colour. They are off
  by default, so not a common task.
- **The proposal:** a shape for each state, at least when the setting is on.

**P7. Small hit areas.**
- **The problem:**
  - a tab's close "x" is 11 pt wide;
  - the desktop's Keys and Keyboard glyphs;
  - the editor's status bar (line and column, language, keyboard toggle);
  - the file path's segments.
- **The proposal:** larger targets. Some can grow invisibly, but they would overlap their
  neighbours, so the owner decides.

**P8. Not accessibility.** On iPad, a relaunch restores a dead database window ("Connection
Closed").

## Labels (honest)

| Label | iPhone | iPad | Vision Pro |
|---|---|---|---|
| VoiceOver | Needs device check | Needs device check | Needs device check |
| Voice Control | Needs device check | Needs device check | Needs device check |
| Larger Text | Not yet (P1, P2, P3) | Not yet (P1, P2, P3) | Not yet (P3; large sizes not audited here) |
| Dark Interface | Not yet (P4) | Not yet (P4) | Needs device check |
| Differentiate Without Color Alone | Needs device check (P6 if on) | Needs device check (P6 if on) | Needs device check (P6 if on) |
| Sufficient Contrast | Not yet (P4) | Not yet (P4) | Needs device check |
| Reduced Motion | Not yet (P5) | Not yet (P5) | Not yet (P5) |
| Captions | Not applicable | Not applicable | Not applicable |
| Audio Descriptions | Not applicable | Not applicable | Not applicable |

Why:
- **Dark Interface:** the app follows the system's Dark Mode, and every audited surface was dark.
  It is "not yet" because readability under Increase Contrast fails (P4).
- **Captions and Audio Descriptions:** the app presents no video or audio of its own. A media file
  the user opens is their own content.
- **The terminal's text:** SwiftTerm exposes it to VoiceOver line by line
  (`UIAccessibilityReadingContent`).
- **The editor:** it is a `UITextView`.
- **A remote desktop's screen:** VoiceOver cannot read it (third-party content). Its audio does
  come through, so a screen reader running on the remote machine can be heard.

## Device checks for the owner

On each device, turn the feature on, then do the common tasks:
1. Browse the library.
2. Add a host with a Terminal service.
3. Connect.
4. Read the terminal's output and type a command.
5. Open a database and move through the grid.
6. Open a file in the editor, read it and change it.
7. Disconnect.
8. Change a setting.

Then, per feature:

| Feature | Where to turn it on | What to check |
|---|---|---|
| VoiceOver | Settings ▸ Accessibility ▸ VoiceOver | Every control has a sensible name; nothing is unreachable; the terminal reads by line (rotor ▸ Lines); dialogs take focus. |
| Voice Control | Settings ▸ Accessibility ▸ Voice Control | Say "Show names", then "Show numbers", and do every task by voice. Names must match the visible words. |
| Differentiate Without Color | Settings ▸ Accessibility ▸ Display & Text Size ▸ Color Filters ▸ Grayscale | Every task can still be done. |
| Contrast and Dark Interface (Vision Pro) | Increase Contrast and Reduce Transparency, with a bright room behind a window | Text stays readable. |

## Changed files (uncommitted, in the worktree)

**Sources:**
- `GlassConnectionUI/GlassWorkspaceTabBar.swift`
- `GlassConnectionUI/GlassSpatialColumns.swift`
- `GlassDatabase/DatabaseWorkspaceView.swift`
- `GlassDatabase/TableDetailView.swift`
- `GlassLayers/GlassSpatialWindowGlass.swift`
- `GlassShell/GlassShellLibraryView.swift`
- `GlassShell/GlassKeyManagerPanel.swift`

**Tests:**
- `UITests/AccessibilityAuditUITests.swift` (new)
- `UITests/AccessibilityLabelsUITests.swift` (new)
- `UITests/GlassDatabaseUITests.swift`

**Notes:** this note.

**Next:** the owner decides P1–P8 and does the device checks. Re-run the audit before declaring
any label.
