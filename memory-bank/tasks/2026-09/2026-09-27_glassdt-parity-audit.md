# glassDT → Glass Power Tools: remote desktop parity audit — 2026-09-27

**State:** QA (read-only audit) → awaiting the owner's choice of fixes. Asked by the owner: "evaluate
the glassDT code base against our Desktop implementation … anything missing? Be diligent." Five
read-only agents (rendering, input, model/trust, engines, docs); every headline finding below was
re-checked by the coordinator against the source. Nothing edited.

## Moved intact
RDPKit engine (only GPT additions: desktop scale factor, whole-chain TLS trust; `Examples/` dropped),
VNCKit and GlassVNCTransport byte-identical, GlassRDPTransport plus scale factor only. Input,
Metal, cursor, audio, keyboard maps, trust prompts, credential rules, `.rdp` import: same code.

## Findings (verified)
1. **Data loss, shared by all three capabilities.** `GlassServiceRecords.replaceAll`
   (`Sources/GlassShell/GlassServiceRecords.swift:63-75`) deletes every stored configuration missing
   from the given list, but callers build the list from `all()`, which skips records this build
   cannot decode. Any desktop save/favourite/last-connected/delete (`DesktopRepository.swift:76,82,106`),
   and terminal/database saves (`ServerManager.swift:100`, `ConnectionManager.swift:61`), erase
   records written by a newer build, and the erasure syncs. glassDT refused (`invalidDocument`).
2. **Desktop settings unreachable.** `DesktopSettingsView` has no caller; the capability declares no
   `settingsPages`. Consequence: "Important Session Notices" can never be enabled, so
   `DesktopNotices.connectionFailed` never posts; `configurePresentation()` never called.
3. **Open in Screen Sharing (macOS, VNC)** missing, unrecorded (glassDT `DesktopLibraryView.swift:274,310`).
4. **⇧⌘I Import RDP File…** not registered in any `.commands` (`DesktopImportCommands.swift`).
5. **Tests:** of glassDT's 142 app-level desktop tests only the 9 import tests moved. Input,
   trackpad, GPU presentation, colour key, notices and 46 session-regression tests have no
   counterpart. The Docker xrdp/TigerVNC functional harnesses (input, clipboard, resize) did not
   move; `Tests/LiveDesktop` probes check negotiation and frames only. The 14 glassDT UI workflow
   tests did not move; the stage-4 parity sweep has no completion record.
6. Smaller: visionOS session window lacks `defaultWindowPlacement` beside the library; shell
   Appearance does not reach desktop windows (own `display.glass.*` keys); VNC shows RDP-only size
   fields; `ConnectionEditor.swift` is dead code; logger subsystems still `app.glassdt.*`;
   RDP+VNC on one host with default names may collide in host merge (unreproduced); app-wide ⌘
   menu shortcuts probably keep ⌘K/⌘O/⌘T etc. from reaching the remote (unverified at runtime).
7. Docs: progress.md/D31 say desktops contribute no switcher sessions — stale;
   CAPABILITY-LEDGER row on post-login desktop stale.

## Not regressions (absent in glassDT too)
File/drive/printer/USB redirection, drag and drop, Gateway, VeNCrypt/Tight, `.rdp` document type.

## Next
Owner chooses which to fix. Suggested order: 1 (with a red-first test), 2, 3/4, then tests.

## Also found: library sync republished stale copies (2026-09-27, fixed, uncommitted)
Owner: collections made on the Mac never reached the phone, whose status said "Synced". Cause
(`GlassShellModel.synchronizeCatalog`): every sync after the first fetched a delta since a token,
and `GlassCatalogMerge.reconcile` publishes whatever the fetch did not return — so each sync
re-sent every unchanged record with `.changedKeys`, overwriting newer account copies. The CloudKit
backend also read only the first page (`moreComing` ignored) and discarded per-record save
failures. Fix: every sync reads the whole account (nil token); the backend pages through
everything, restarts on `changeTokenExpired`, and throws on a refused record; syncs are serialised
(launch ran two at once). Red first: `D19StaleRepublishTests.aSecondSyncWithNoChangesPublishesNothing`
failed on the old code; all 27 sync tests pass after. New: `GlassICloudStatusButton` in the library
toolbar (Apple's icloud symbols, popover with last sync, counts, Sync Now), and
`--ui-testing-seed-hosts` accepts `name#Tag1,Tag2`.

Desktop fixes in the same tree: Settings ▸ Desktops page (notices toggle, visionOS glass),
notification presentation delegate, ⇧⌘I in File, ⚡ in desktop windows (Mac/iPad toolbar,
visionOS control bar).

## Also fixed: iPhone terminal's last line under the keyboard bar (2026-09-27, uncommitted)
Measured with a temporary layout probe on the iPhone 17 Pro simulator (`--demo-open terminal
--demo-keyboard`, a new DEBUG switch that keeps the keyboard up in a demo run): terminal 370pt,
21 rows of 17pt; SwiftTerm pinned its offset to the content's bottom (259) but drew from
`yDisp × row` (272), so every row sat 13pt low and the prompt went under the accessory bar,
unreachable by scrolling. Fix: `TerminalHardwareKeyContainerView` sizes the terminal to whole rows,
top-aligned. Seen fixed on the simulator; installed on the phone as 0.4.239. The accessory bar
itself measures to the HIG (44pt targets, margins aligned with the navigation bar, centred).
The iCloud status moved from the toolbar to a footer row pinned under the library sidebar
(`GlassConnectionLibrary.sidebarFooter`), at the owner's request.

## The three open items, fixed (2026-09-27, the owner: "Fix all three")
1. **Records a newer build wrote survive writes.** `GlassServiceRecords.replaceAll` deletes only
   records it can read, compares by JSON value (key order is not stable in `JSONEncoder`, so
   unchanged records were rewritten and republished) and writes sorted keys; `preserving:` leaves
   the desktop's validation-rejected records untouched. Red first: `GlassServiceRecordsUnreadableTests`
   and `DesktopUnreadableRecordTests` failed on the old code.
2. **Open in Screen Sharing** is a tool row on a Mac VNC desktop's host detail
   (`DesktopScreenSharing`, endpoint only, IPv6 bracketed), with tests.
3. **glassDT's tests ported**: 124 of 137 app-level tests (13 dropped, each for a mechanism GPT
   removed on purpose: connections.json, journals, pairing); the xrdp and TigerVNC Docker rigs
   moved into `Tests/LiveDesktop` and run — xrdp 6/6 checks, TigerVNC 5/5 (the VNC probe gained
   real assertions; glassDT's only printed).
Porting found two real defects, fixed: the notification delegate set in the desktop runtime's
init crashed any test process (moved to the app root, where glassDT had it); saving a desktop
before the library loaded wrote a Keychain credential and then deleted it (now refused first).
Validation: the Mac's screen was locked, so protected-file tests fail; the shell and terminal
failures were compared against the last commit under the same lock and are identical. Rerun the
full suite unlocked. Also: private names in test fixtures (the owner's username, two machine
names) replaced with neutral ones; private-range addresses and database names in older notes are
left for the pre-publication scrub.

## 2026-09-28: the headset's stale library reached iCloud (fixed)
The Vision Pro, last installed at 0.4.123, got 0.4.241; its upgrade re-stamped its old records and
newest-wins published them: 10 sent, three long-deleted machines resurrected in iCloud without
configurations. The Mac was quit before syncing; `GLASS_SYNC_DRY_RUN=1` showed the account record by
record. Merge now: tombstones final; a configuration is never lost to a copy without one;
corrections stamped past both copies; duplicate and rounding-error records settle. Mac took 13 and
sent 3, then 0/0. All three devices on 0.4.247. The headset's list is inset grouped.
**Before letting a device with an old install sync, dry-run it or update everything first.**

## 2026-09-28 (evening): sync repairs, round 2, and the headset's lists
- The first merge rules still let machines vanish: the stale headset folded the Mac's live records
  into old copies, then "deletion is final" deleted those. Now (`caa10cb`): pairwise decision, then no
  set-up service may end live nowhere — the record holding it is revived, iCloud's live copy
  preferred so devices converge; the catalog store dates a deletion by its statement (`updatedAt`);
  refused records are retried one by one and counted in the status. Mac revived the two machines
  (3/3 each), then 0/0. The Sept 21 protection (folded services never lost) is kept and tested.
- Test cleanup trapped the terminal test process on exit (main-actor default); fixed (`0ef580d`).
  Check `swift test` logs for `signal code|exited with`, not only result lines.
- Headset lists (`172d16a`, `d3af0ac`): every list uses `glassSpatialList()` / `glassSpatialListRow()`
  — the database schema list's shape, one system capsule per row. Removed our nested gaze highlights
  and spatial padding from connections, projects, file tree, keys, Active, SFTP, sidebar panels.
  SFTP rows show the Mac's columns; the database window's toolbar (⚡, back) attaches to the detail
  column on visionOS; the results bar scrolls instead of wrapping.
- Owner's verdict on the cause: nearly all of it was ours, not Apple's defaults. Direction: leave
  spatial design to Apple. Pass 2 of the unwind is proposed (see activeContext).

## 2026-09-29 — the database results bar, the gutter, the editor's last ⌘W

- **Results bar** (`TableDetailView.gridControls`): thirteen controls in four styles became Mail's
  shape — Filter and the sort summary leading; Format, Analyze, Columns, Copy, Export, Delete as icons
  with help text; Compare Rows, Extend Selection, Paste Rows, Import TSV… and "First Row Is Column
  Names" in a More menu. Paste Rows reads the clipboard directly (the system asks on iOS/visionOS).
  The bar fits without scrolling on the headset; the Mac keeps `.small`.
- **Pager**: `statementCompletedView` fills the results pane, so the pager stays at the foot.
- **Gutter** (`GlassLineNumberGutter.verticalOffset`): in a window the text view's frame is offset
  inside its clip view, and the summed offset drew every number a line or more low. Now a view
  conversion. Test `gutterNumberIsLevelWithItsLineInAWindow` fails on the old sum (50 pt against 12).
- **Sync**: `synchronizeCatalog` callers arriving mid-pass now await the running pass (a stored task)
  instead of returning at once; that race flaked two shell tests.
- **Editor ⌘W → Discard**: `performClose` is refused while the question's sheet is attached, which
  left the window on "No Document". The window now orders out immediately and is closed when the
  sheet has gone. Confirmed by the owner on the Mac (0.4.253).
