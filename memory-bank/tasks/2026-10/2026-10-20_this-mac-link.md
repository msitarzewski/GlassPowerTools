# This Mac knows its own library record (D86, 2026-10-20)

**His ask:** "we don't recognize in the app that 'This Mac' and [his Mac's library record] are one in the same. How can
we set that?" Then: "yes, build it".

**Authorization:** build it; commits on his word.

## What was there

- **This Mac** is `GlassLocalHost`: a fixed id, stored only on the device, never published, no address (D8).
- **His Mac's library record** is a separate synced machine with Screen Sharing, Terminal (SSH) and MySQL. This Mac
  had no services of its own.
  - So a local tab's Open in SQL Editor said "No database on this machine".
  - Active can list the same tmux sessions twice (D50).
- **Evidence the two are one:**
  - The record's address (its Tailscale address) is on one of this Mac's interfaces.
  - This Mac's SSH host key (`/etc/ssh/ssh_host_*_key.pub`) is readable, to compare with a pinned key for the
    record's SSH service.

## Plan

1. **The link:** this Mac's library record, by host id, kept on this device only (never in the synced catalog). Set
   by:
   - the pinned SSH host key matching this Mac's own (automatic);
   - an address of this Mac (offered once);
   - the machine's editor ("This is this Mac", and Unlink).
2. **Library:** one row. The linked machine reads as "<name> — This Mac" and carries the local shell. This Mac's own
   row folds into it when it has no services.
3. **Terminal:** the linked machine's Terminal service opens a local shell, in tmux when local tmux is on.
4. **Databases:** the linked machine's databases are This Mac's, including a local tab's Open in SQL Editor.
5. **Next:** Screen Sharing to itself hidden; Active lists each session once.

## Built (2026-10-20, 0.4.488)

- **Recognition:**
  - `GlassThisMac` (GlassShell) holds this Mac's addresses (`getifaddrs`, Bonjour name) and the evidence rule.
  - The key match reuses `SSHHostKeyIdentity` and `GlassMachineIdentity`, which the editor and terminal already use.
    A first draft of mine compared `type base64` lines with pinned base64 blobs and would never have matched; the
    research agent caught it.
  - The app supplies `GlassShellModel.thisMacEvidence` (pinned fingerprints from the terminal against this Mac's).
    It is the Mac only.
- **The link:**
  - `GlassShellPreferences.thisMacHostID` and `declinedThisMacHostIDs`, in this device's `shell-preferences.json`,
    never pushed.
  - Set through `setThisMac` and `declineThisMacSuggestion`.
  - `recognizeThisMac()` runs after every catalog load and every sync that brings records. One machine matching by
    key is linked; one matching by address is offered (`thisMacSuggestion`) unless declined; a linked machine gone
    from the library unlinks.
- **The fold** (`rebuildProjection`), when This Mac keeps no services:
  - The machine's host (`GlassShellHost(thisMac:foldingIn:builtInServices:)`) goes first, keeping its id, members and
    tags.
  - It gains This Mac's built-ins of kinds it lacks; the local shell is hidden beside its own Terminal but answers
    `host(owningEndpoint:)`.
  - `host(GlassLocalHost.id)` finds it. The row's subtitle starts "This Mac · ".
  - If This Mac has services of its own, both rows stay and the machine is still marked.
- **Connect** (`open(_:on:)`): the machine's `.ssh` opens the built-in local shell with This Mac's record; its
  built-ins open as This Mac's.
- **SQL:** a local terminal's destinations include the machine's databases, and those reached through its SSH
  (`sqlDestinations(reachedThrough: Set)`). The editor's project reach treats the machine as this device.
- **Interface:**
  - "This is this Mac" toggle in the machine's editor (macOS), applied at once.
  - The library's one-time offer, "Is <name> this Mac?", with It's This Mac and Not Now.
- **Tests:**
  - `GlassThisMacLinkTests` (5): the fold, Connect, persistence and unlink, recognition and the remembered Not Now,
    This Mac with services. The fold and Connect tests were seen failing without their code.
  - `GlassThisMacTests` (3).
  - Shell 329, terminal 951, database 334, connection UI 55 and editor 172 all pass.
- **Seen on his Mac (0.4.488):**
  - It linked by itself, by its SSH host key: the pin his other devices made for the machine is this Mac's own key,
    synced through iCloud Keychain.
  - No offer was needed. The link points at the live record (Screen Sharing, Terminal, MySQL).

## Active and Screen Sharing (2026-10-20, 0.4.489, his "yes, do the Active and Screen Sharing part")

- **Active:**
  - `GlassTerminalRuntime.isThisMacServer` (set by the app from the shell's `isThisMac`).
  - `runningReport()` doesn't ask that server over SSH.
  - `runningReport(local:hosts:)` drops its listing whatever tmux server answered, so its sessions are listed once,
    as This Mac's.
  - Before, only a host whose tmux server matched the local one was dropped, which needed the same user and socket.
  - `TerminalActiveListingTests` +1 (listed for any other machine, not for This Mac's).
- **Screen Sharing:**
  - The linked machine's `.rdp` services aren't in its services on this Mac, folded or not. They stay in the record,
    synced and used from other devices.
  - A first build rebuilt the folded list from the unfiltered one; the new test caught it.
  - `GlassThisMacLinkTests` +1.
- **Suites:** shell 330, terminal 952.
- **Still not:** the terminal's own direct connect paths (Basic Terminal, the palette's "without tmux", workgroups)
  SSH to the machine.
