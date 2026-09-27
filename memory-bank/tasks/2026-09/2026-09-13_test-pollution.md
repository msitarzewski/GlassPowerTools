# UI tests were writing into the user's real store

**Date** 2026-09-13 · **Owner** coordinating agent · **State** fixed, with cleanup outstanding
**Found by** the user, looking at Connect Saved Host, who asked where these previous
connections were stored and wanted them wiped.

## What was wrong

`GlassPowerToolsApp.init` isolates the **shell's** storage under `--ui-testing <uuid>`: an
application-support directory per run, and CloudKit deliberately not attached. The terminal's
servers, themes, snippets, workgroups and preferences do not go through that. They go through
`SharedDefaults`, which on macOS is plain `UserDefaults.standard` — the Mac terminal is unsandboxed
by necessity, since it launches the user's shell and PTYs, and an App Group container requires
sandbox membership.

So **every UI run appended its fixtures to the real saved-server list.** By the time it was noticed
there were **122 saved servers, of which four were genuine**: the rest were `probe@10.9.8.7`,
`tester@chrome.example`, "Terminal on Doomed Host", and six duplicate `scratch` entries from the
day's real-host runs. They surfaced in Connect Saved Host, where `probe@editable.example` is plainly
not a machine anyone owns.

## Fixed

`SharedDefaults.defaults` returns a per-run suite (`group.sh.glas.shared.uitests.<uuid>`) when
`--ui-testing` is present, keyed on **the same argument the shell reads**, so there is one signal for
"this is a test run" rather than two that can disagree. Debug-only. Computed rather than stored:
`UserDefaults` is thread-safe but not `Sendable`, so a static constant of it is refused under strict
concurrency.

Where it lives, for next time: **`~/Library/Preferences/com.glasspowertools.plist`, key `servers`**.
`defaults read com.glasspowertools` does *not* show it — that resolves to a sandbox container path
that does not hold these. Read the plist directly.

## Cleaned

122 → 4 → 0. The four survivors turned out to be orphans of hosts the user had already deleted, which
is a second defect (**D25**: deleting a machine now deletes what its capabilities stored). The legacy
`sh.glas.mac` `servers` key was cleared too, so the migration path cannot resurrect them. A backup of
the original 122 is in the session scratchpad as `com.glasspowertools.plist.backup`.

## Still outstanding — the same root cause, a different blast radius

**Unit tests create real `UserDefaults` suites and abandon them.** Counted on this machine:

- **4,112** `GlassLayersTests.<UUID>` domains
- a comparable pile of `com.glasspowertools.tests.audit.<UUID>`
- and `app.glassdb.tests.appearance.<UUID>` from the source app

One per test run, never removed, accumulating every time the suite runs. Nothing is broken by them,
but they are thousands of files in the user's preferences and they make `defaults domains`
unreadable. The fix is for those tests to remove their suite in teardown
(`UserDefaults.standard.removePersistentDomain(forName:)`), plus a one-off sweep of what has already
accumulated. **Not done** — it touches several test files and was not what the user asked for.
