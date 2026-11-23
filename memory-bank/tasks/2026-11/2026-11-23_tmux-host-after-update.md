# Local terminals lose folder permissions after an update (2026-11-23)

## Task
- **Report (2026-11-23):** Claude Code in a local tmux terminal could no longer read the Documents, Desktop or Downloads folders, with the app's Files and Folders switches still on.
  It began partway through a session; quitting and reopening the app didn't help; a new Claude Code then said
  "Can't read the current directory (EPERM)".
- **Authorization:** diagnose; app changes to D66's host are the owner's call. His order (2026-11-23): commit the
  pending work, reproduce this in the macOS VM, then the quick fix (a host older than the app named on opening,
  with a way to restart it). The lasting fix (a host that an update doesn't leave stale) is still his call.

## Evidence
- **The host outlives the app by design (D66).** `MacTmuxService` has launchd run the app's own executable with
  `--tmux-host`; it starts `tmux -D`, and every pane answers to it for privacy permissions
  (`Sources/GlassTerminal/macOS/MacTmuxHost.swift:1-16`, `MacTmuxService.swift:1-25`). Settings says quitting
  or updating the app leaves local terminals running (`MacLocalTerminalServerSection.swift:30`). So quitting and
  reopening keeps the same host, and a new pane or Claude Code still answers to it.
- **A host from before an update no longer matches the app on disk.** On the owner's Mac the host started
  2026-11-19 and the app has been replaced by installs since: `codesign -vvv +<host pid>` says "dynamically
  valid" and then "invalid signature (code or signature have been modified)"; its CDHash differs from the
  installed app's.
- **macOS ties a folder grant to the code signature** (Apple DTS on the forums: TCC needs a stable signature to
  remember a grant; a broken signature "can easily lead to a TCC problem").
- **Not yet shown here:** tccd refusing such a host. This Mac's tccd logged no folder decision for the app in
  three days (no pane here reads those folders). A VM reproduction would settle it.

## Unblock (no build needed)
- Settings ▸ Terminal ▸ tmux ▸ End All Local Terminals… ends tmux and the host; the next terminal starts a host
  from the current app. It ends every local terminal and what runs in it.

## Next
- The VM reproduction, then the quick fix; the lasting fix stays his call.
