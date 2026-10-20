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

(Results below as built.)
