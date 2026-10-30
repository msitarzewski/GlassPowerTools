# Workgroups' Mac terminals belong to their Mac (D91) — 2026-10-29/30

**Owner and authorization:** the owner, 2026-10-29: "end the six empty sessions, Build 1 to 6 and check the rest of
the app for others". Local edits, tests, builds and installs; no commit.

## What was found (verified in code, and independently by an agent from the source)
- Workgroups hold local and SSH terminals, mixed; any device makes or edits one (only the Mac adds local ones); they
  sync per workgroup through iCloud key-value, newest wins; stand-ins and last-opened stay on the device.
- Nothing recorded a local terminal's Mac. The headset's stand-ins for two of his workgroups pointed at his Mac's own
  record, with blank folders and no tmux names, so each opening made new sessions in `~` and ran the Mac terminals'
  startup commands there (a build, start scripts, a second copy of a tunnel). The six "Not in a window" sessions (created 14:27:06–07, all at
  a zsh prompt in `~`) were these; two took `glass-5`/`glass-6`, which a third workgroup kept. Ended at his word, 2026-10-29.
- On a Mac, an SSH terminal to the Mac's own record went over SSH to itself; a second Mac ran another Mac's
  terminals on itself, joining any same-named session there.

## Changed
- `Models.swift`: `SessionIntent.macServerID` (optional, local only, ignored by `sameTerminal`), `machine(thisMac:)`,
  `tmuxSessionsHeld(in:serverID:thisMac:)` by machine; `TerminalSession.tmuxSessionDirectory`, `tmuxJoinsOnly`,
  `tmuxSessionRenamed`; `WorkgroupSSHSubstitution.startup(_:in:)` shared.
- `TerminalTmux.swift`: `claimCommand(candidates:directory:)`; `shellPath` (a leading `~` as `"$HOME"`).
- `SettingsManager.swift`: `thisMacServerID`; stamping in `upsertLayoutPreset` (macOS); `recordWorkgroupMac`;
  `recordWorkgroupTmuxSession` matches by machine across kinds; `renameWorkgroupTmuxSession`.
- `WorkgroupRestoration.swift`: `LayoutRestorationPlan.mac(of:in:)`, `onItsMac`, `LayoutRestorationTarget.folder`;
  `prepare(…joinsOnly:)`; the sheet lists only terminals without a reachable Mac and pre-fills the Mac folder.
- `TerminalConnectFlow.swift`: the sheet only when a Mac terminal has no reachable Mac.
- `TerminalWorkgroupsToReopen.swift`: reopened terminals join only.
- `macOS/MacWorkspaceState.swift`: `MacWorkgroupLauncher.launch(…thisMac:)` by machine; `MacWorkspacePaneIntent.sshDirectory`.
- `macOS/MacWorkspaceController.swift`: SSH claims in `sshDirectory`; held names by machine; `recordWorkgroupMac` at a
  tab's start; local and SSH renames kept.
- `macOS/MacTerminalOverview.swift`: `locate` by machine; `recordThisMacOnOpenWorkgroups`, called from the terminal
  capability's `catalogDidLoad`.
- `TmuxControlClient.swift`: `%session-renamed` (both forms) → `.renamed`; `SwiftTermHostView.swift`: `onTmuxSessionRenamed`.
- `GlassTerminalCapability.swift`, `App/GlassPowerToolsApp.swift`: `thisMacServerID` from D86's link.
- `WorkgroupEditorView.swift`: the draft keeps `macServerID`.

## Validation
- New `WorkgroupMacTerminalsTests` (10, one live tmux on a private socket), three in `MacWorkgroupTmuxTests`, one in
  `TmuxControlClientTests`; `WorkgroupTmuxSessionsTests.newNamesSkipHeld` updated for unclaimed names held everywhere.
- Each new test bitten: two batches of independent breaks (`~/Software/glass/tmp/bite-1030/breaks.py`), every test
  failed at the expectation its break targets; restored from copies, `cmp` identical.
- tmux 3.8's notices checked by hand: `%session-renamed $0 renamed`; `%exit` without a reason for exit, detach and a
  killed server alike (so "ended" is read from the session list, not `%exit`).

## Not done / limits
- Not seen on devices yet: the headset opening a Mac workgroup onto the Mac's running sessions; a second Mac (none here).
- A Mac whose library has no record of itself records nothing; its workgroups open as before.
- Existing headset stand-ins for terminals with a reachable Mac are ignored, not deleted.

## The rest of the app, for more than one Mac (read-only sweep, 2026-10-30; nothing built from it)
An agent read the source with a second agent re-tracing its claims; I re-read the two most serious myself (A and 2).
Root: a Mac not linked under D86 has no synced identity; "this device" is written as the fixed `GlassLocalHost.id`,
the fixed Local Shell endpoint, or `hostID == nil`, and any of them in synced data means "mine" to every reader.
- **A (every device, data loss):** `SSHKeyCatalogStore.keychain.save` deletes every key record not in this process's
  list, which is read once per launch (`SettingsManager.swift:424, 572`); a key imported elsewhere since loses its
  record at this device's next key change. Fix direction: reload from the Keychain before saving.
- **1 (overwrite):** a SQLite database on a synced machine syncs a path to one device's managed copy; re-importing on
  another device replaces it for both.
- **2 (wrong machine):** local-folder editor projects carry `hostID` nil, which every device opens as its own
  (`App/GlassPowerToolsApp.swift:255`); removing a missing one on a phone removes it everywhere.
- **3:** the D86 link is never re-checked, so a copied preferences file (Migration Assistant, inferred) makes one Mac
  treat another's record as itself; the same file's `writerID` makes their usage overwrite each other.
- **4:** two Mac records with one name group, and the D86 fold takes both.
- **5:** a loopback address on a synced machine reaches each device's own server (a database sends the synced login).
- **6–7 (cosmetic):** unlinked This Mac's usage under the shared fixed id; the Local Shell favourite syncs; Handoff of
  device-only sessions; D86 recognition misses DNS-named records and ones with no SSH service.
- **B:** removing a database never removes its credential, SQLite copy or drafts (the capability's list is reloaded
  first). **C:** a database can't be added to the device's own This Mac record (`serviceNotFound`).
Checked fine: the This Mac record, the D86 link, local terminal settings, the launchd tmux job, Active, Handoff
continuation, widgets/Spotlight/App Intents, editor recents and bookmarks, folder favourites, schemes and fonts.

## Fixed first, at his word ("install on the mac, then fix the SSH key one first"): key records (0.4.568)
- 0.4.567 installed on the Mac at his OK (the first try met a modal of his). The Mac at once recorded itself on the
  four workgroups open in its windows; one not open there waits for its next open or save.
- `SettingsManager.SSHKeyCatalogStore`: `save(all, changed, removed)` and `writesWholeList`. The Keychain store is
  `.records(all:write:delete:)`: a change writes and deletes only its own records, never one this device hasn't
  read; checked only for what changed. The defaults store (one device, tests) still writes the whole list.
  `persistSSHKeysAndVerify` returns the catalog as it stands (other devices' keys included) and every import, rename,
  delete and rollback passes its own change. A rename of a key deleted elsewhere is refused (`notFound`) rather than
  bring its record back.
- `SSHKeyRecordsAcrossDevicesTests` (2): two devices on one shared store of records. With the old save put back the
  first failed where the bug bit (the phone's record gone after a rename here); without the rename guard the second
  did; restored, `cmp` identical.
- The full run after it failed three `GlassCatalogSyncWordingTests` once, under an app build's load; they passed
  alone and in six later runs. Cause found, not waved off: `GlassRemoteChangeTests` posted the process-wide
  remote-change notice in a loop, every listening model in the run heard it, and a wording test read its status in
  the middle of the extra sync ("syncing"). A model now acts only on a notice with no object (the push, for every
  library) or addressed to it; the test addresses its own. New test: a notice for another model syncs nothing (bit
  without the filter; restored, `cmp` identical). The shell suite then passed four times during a build.
