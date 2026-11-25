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
- **Reproduced in the macOS VM (2026-11-23)**, the throwaway `glasspowertools-mac26-run`, macOS 26.6.2, tmux 3.7c
  from Homebrew, the released Developer ID builds 0.4.623 and 0.4.632 from GitHub (checksums matched), the host
  started by the job `MacTmuxService.job` writes (`<work>/tcc-host/`):
  - **SIP had to be on.** Cirrus Labs' image ships with it off, and then the folders weren't protected at all: a pane
    read Documents with no prompt and tccd logged nothing. Turned on in recoveryOS over the VM's own VNC
    (`tart run --recovery --vnc-experimental`, vncdotool; Utilities ▸ Terminal, `csrutil enable`, boot security left
    as it was), as Cirrus's `disable-sip` template turns it off.
  - `launchctl procinfo` of a pane's shell: responsible path the host (`Glass Power Tools --tmux-host`).
  - Before the update: reading Documents from a pane asked "“Glass Power Tools” would like to access files in your
    Documents folder"; allowed, it read (TCC.db: `kTCCServiceSystemPolicyDocumentsFolder`, `com.glasspowertools`,
    bundle ID, allowed).
  - 0.4.632 put in its place as an update does (written beside it, renamed over it, the old deleted) while the host
    ran: Documents still read at once, from the old pane and from new ones, and after `killall tccd`; Desktop and
    Downloads were refused at once ("Operation not permitted", the kernel's "System Policy: cat deny(1)
    file-read-data"), with no prompt and no request reaching tccd.
  - **Ten minutes on, Documents was refused too**, from a new session: the report's "files I could read earlier began
    failing".
  - **The remedy:** `kill-server` and `launchctl bootout` (what End All Local Terminals does), the job started again,
    so the host ran 0.4.632: Documents read at once, no prompt (the Developer ID grant carries across versions);
    Desktop asked again, and read once allowed.

## Unblock (no build needed)
- Settings ▸ Terminal ▸ tmux ▸ End All Local Terminals… ends tmux and the host; the next terminal starts a host
  from the current app. It ends every local terminal and what runs in it.

## Quick fix (0.4.644)
- `Sources/GlassTerminal/macOS/MacTmuxHostCheck.swift`: the tmux server's process (`list-sessions -F '#{pid}'`,
  through `MacLocalTmux.Server.serverProcess`, so stand-ins never ask this Mac's tmux), its parent (`proc_pidinfo`),
  and macOS's own check of that parent when it is signed `com.glasspowertools`: `SecCodeCheckValidity` answering
  `errSecCSStaticCodeChanged` is a host an update replaced. Checked on his Mac's host (started 2026-11-19): -67034,
  "the code on disk does not match what is running"; the running app: no error.
- On opening (`MacLaunchReopen`, after the ended-tabs notice, before the running-sessions offer), once a launch: an
  alert with the count, the folders and the way out; End N Terminals (what End All Local Terminals does) or Not Now
  (remembered for that host). Settings ▸ Terminal ▸ tmux: an orange line under the status while it holds.
- Tests (`MacTmuxHostCheckTests`, 5): a small C program compiled into a temporary folder, run, and its file replaced
  as an update does (copies of `/bin/sleep` or `/bin/bash` can't stand in: macOS ends them away from their folder,
  status 137): intact, then replaced; a host and its forked child found as host and server. With the check's
  replaced case broken, both of those failed.
- RELEASE-NOTES 0.4.644; `site/help/terminal-tmux.md`, Running in the background.

- **Seen in the VM** (`macvm.sh build-app`, ad-hoc, `--ui-testing <uuid> -localTmux YES`), installed over a running
  host from 0.4.623's successor 0.4.632 or from an earlier ad-hoc build: the alert at opening ("Terminals from before
  the update can't open some folders", the count, End N Terminals / Not Now); End ended tmux, the host and the job;
  Not Now kept for that host (no alert at the next launch, the host still running); Settings ▸ Terminal ▸ tmux showed
  the orange line under "Running, 2 terminals". The first wording said "programs in them" of one terminal; fixed and
  seen again. A harness trap: `macvm.sh quit-app` is `pkill -x 'Glass Power Tools'`, which also kills the host (same
  name) and leaves tmux under launchd, so no host is found; stop the app's own process instead.

- **On his Mac (0.4.644, installed 13:29; iPhone too; the headset was locked):** his host from 2026-11-19 was
  replaced, so the alert showed; he ended the terminals. A new host started 13:58, and macOS's check of it answers
  no error.

- **0.4.645 installed at 14:19 left the 13:58 host replaced again** (-67034), so the alert showed again: the quick
  fix asks at every update. That is the case for a lasting fix.
- **His answer, shown the alert after the 0.4.645 install:** "This is not ok. Every quit CAN NOT DO THIS."

## Lasting fix (0.4.646, D114)
- `MacTmuxHostCopy`: the job runs the host from an APFS clone of the whole app bundle in
  `Application Support/Glass Power Tools/Terminal Host.noindex/<version>-<cdhash 12>/` (clone 0.05 s, check 0.18 s
  for the 229 MB app on his Mac), checked before use (same CDHash, `SecStaticCodeCheckValidity`); copies no host
  uses removed when a server starts. A whole-bundle copy, not a helper of its own: same code and signature, so the
  app's grants apply and nothing new is asked.
- **Found in the VM, first try:** the copy's first run took 4.5 s (AMFI and XProtect scan a new executable once),
  longer than the 3 s a terminal waits for its server, so the app started tmux itself and the late host exited 1.
  Run again it started in 0.15 s. So each new copy is run once with `--tmux-host-ready` (exits at once, before any
  AppKit) at the app's start in the background (5.5 s in the VM), and before a server if it hasn't been.
- Tests: `MacTmuxHostCopyTests` 5 (a small ad-hoc signed app built in a temporary folder: copied once, checks, the
  original replaced and the copy untouched, the next build's copy and the old one removed; a changed sealed file
  refused and removed — seen failing with the check taken out; the warm run once a process).
- **VM (SIP on, ad-hoc build of this code, then 0.4.632 put in its place as an update):** the copy made and warmed at
  launch; New Terminal Window started the host from the copy under launchd ("started under launchd", 0.1 s);
  `launchctl procinfo` of tmux: responsible path the copy; Documents asked for in the name "Glass Power Tools" and
  allowed; after the app was replaced, Documents read and Desktop was asked for, not refused (the old way refused it
  silently). **Eleven minutes on** (the old way lost Documents by ten): Documents and Desktop read from the old
  terminal and from a new one; Downloads was asked for, and read once allowed. The host still the copy's.

- **On his Mac (0.4.646):** he ended the 0.4.644 host's terminals once; the host started 16:39 runs from
  `Terminal Host.noindex/0.4.646-561ec843e79e/` (proc_pidpath the same), SecCodeCheckValidity no error, the copy's
  CDHash the name's. A clone of the app measured 0.05 s and about 0.3 MB of free space (`df` before and after).
  `codesign -vvv +<pid>` answers "Invalid argument" for the static half on this macOS for the app in /Applications
  too: the command's quirk, not the copy's; the Security framework's own check is the one to read.

## Earlier copies left at each update (0.4.647)
- **His question: the copy "seems incredibly inefficient".** The clone costs nothing while the app it came from is
  in place; but copies were removed only when a server started, and the app's start only added one. With terminals
  kept across updates, every build's copy stayed, each holding a replaced build on disk alone (229 MB).
- `MacTmuxHostCopy.removeUnusedCopies`: every copy but this build's and those a running program runs from
  (`runningExecutables`: `proc_listallpids`, `proc_pidpath`; matched to the folder as written and through
  `realpath`, as macOS names a program by its real path) is removed, at the app's start (`prepareHost`) and when a
  server starts (`defaultHost`). When the running programs can't be listed, nothing is removed: a running host's
  copy taken away would fail macOS's check as the update did.
- Test `unusedCopiesRemoved` (three builds' copies, a sleeping host run from the first in a /var temporary folder):
  nothing removed when unlisted; the second removed, the first and third kept; the first removed once the host ends.
  Seen failing with each of: the running copies ignored, the unlisted case removing, the realpath match removed.
  1,338 terminal tests passed.

- **The update test on his Mac:** 0.4.647 installed at 16:53 over his terminals (the app quit, replaced, reopened) while
  the 0.4.646 copy's host (started 16:39) ran. From one of its terminals, at once and at 17:04 (eleven minutes on; the
  old way lost Documents by ten): the same host, SecCodeCheckValidity no error, Documents, Desktop and Downloads read.
  The new build made and ran its copy in 1.37 s; the 0.4.646 copy stays while its host runs.

## A small helper instead of the whole copy (VM, 2026-11-23) — Observed; not decided
- **His question:** a 229 MB copy (the executable alone is 179 MB) and a 35 MB process, to carry the app's name for
  privacy permissions: the host relays nothing (no sockets or pipes, stdio /dev/null, 0% CPU; tabs' tmux clients talk
  to tmux's socket). He asked for the small helper to be tried in the VM.
- **Probe** (`<work>/helper-probe/`): a 50 KB C program that runs its arguments as a child and waits, as the host runs
  tmux; packaged several ways, signed with the Apple Development identity (a real certificate: a grant's requirement
  names it), each run as a launchd job in the GUI domain listing a protected folder. A stand-in app (own test bundle
  ID) was granted Documents and Desktop first. The throwaway VM, SIP on, macOS 26.6.2.
- **A bare executable is known by its path** (TCC.db `client_type` 1): with the app's identifier and certificate, and
  its Info.plist embedded, it was still asked for in its file name's name, a permission of its own.
- **A small `.app` bundle with the app's bundle ID, signed as the app is, has the app's permissions:** Documents and
  Desktop read with no prompt; a folder the app hadn't been granted (Downloads) was asked for in the helper's
  `CFBundleName`, and the answer was recorded under the app's bundle ID, which the app then read with no prompt. After
  the app was replaced by its next build, both read.
- **Controls:** the same bundle signed ad hoc (requirement a cdhash) was asked for ("Operation not permitted" when
  declined); with its own bundle ID, asked for in its own name. **One row per bundle ID:** declining the ad-hoc one
  replaced the app's Documents row with a refusal under that signature, and the app was asked again. A helper signed
  differently from the app (another identity) would do the same; Xcode signs nested code with the app's.
- **LaunchServices** registered the helper bundles (the prompt looked their names up). In the same VM it already knows
  four bundles with `com.glasspowertools` (the app, two release builds, D114's copy) and picks /Applications.
- **What a helper would be** (a proposal): a small bundle built and signed with the app (bundle ID
  `com.glasspowertools`, `CFBundleName` "Glass Power Tools" so a prompt names the app, a low `CFBundleVersion`, no
  URL schemes or document types), copied out of the app as D114 copies the whole, only when its code changes; the
  host's work (`MacTmuxHost`) moved into it. Unproven: a Developer ID build, and whether its code hash stays the same
  across app builds.

## The small helper built (0.4.648, 2026-11-24) — Approved, implemented (D115)
- **His word:** "yes, build 0.4.648 and test it in the VM first". Asked first whether the new build would need his
  terminals rebuilt: no. The app picks the host only when no tmux server answers (`MacTmuxService.ensureServer`), and
  a copy a running program uses is never removed.
- **What changed:**
  - `GlassTerminalHost` module: `MacTmuxHost` (moved from GlassTerminal; `main`/`run`: ready 0, host, else 64) and
    `GlassSpawn` (moved from GlassTerminalEmulator, with `output`, the body `MacLocalTmux.run` had).
  - `TerminalHost/` (main.swift, Info.plist) and the Xcode target `GlassPowerToolsTerminalHost`, embedded in
    `Contents/Helpers` by an "Embed Terminal Host" phase, Mac only. The app's `--tmux-host` entry point removed.
  - `MacTmuxHostCopy`: `helper(of:)`, `executable(inBundle:)`, `copyBundleName`, copies named `host-<cdhash12>`.
    `MacTmuxService.defaultHost(helper:folder:)` and `prepareHost(bundle:folder:)`.
- **Found in the VM, first build:** a folder prompt names the program by its bundle's file name, not `CFBundleName`.
  Yesterday's probe couldn't tell, as its file name and `CFBundleName` were the same. The build product was
  `Glass Power Tools Terminal Host.app` and the prompt said “Glass Power Tools Terminal Host” would like to access
  files in your Downloads folder. The same signed bundle copied as `Glass Power Tools.app` (executable unchanged) was
  asked for as “Glass Power Tools”, and still verified. So the copy is named after `CFBundleName`. The product can't
  carry the app's name in the build folder beside the app. The prompt shows the folder's icon, not the program's, so
  the icon (2.4 MB of the 2.7 MB) was taken out.
- **Unit tests:** the host, copy, service and check suites, 23 tests (ready/usage/unstartable tmux statuses; copy
  keyed by hash, an unchanged helper keeps its copy, the copy named after `CFBundleName` and still intact, fallback to
  the helper inside the app). Each new check seen failing:
  `run` answering 0 for no request, `executable(inBundle:)` accepting a `/` in its name, `defaultHost` without
  folder returning nothing, the copy keeping the build's name. The terminal suite: 1,341 passed (live tmux tests run
  only in the VM).
- **VM (SIP on, macOS 26.6.2), builds signed with the Apple Development identity his Mac's builds use** (designated
  requirement checked equal; Debug, no entitlements, `<work>/helper-648/vm-build.zsh`). The grants for
  `com.glasspowertools` were reset first.
  1. 0.4.647 (this code before the change): a local terminal hosted by its whole-app copy (50 MB). Documents and
     Desktop asked for and allowed.
  2. **0.4.648 installed over it as an update** (app quit, replaced, reopened): the same host process, macOS's check
     of it intact, its copy kept (in use); the app reopened onto the terminal with its earlier output and no alert.
     The helper's copy `host-cc55e36e9080/Glass Power Tools.app` made beside it (352 KB; first run 0.28 s, the
     whole app's took 4.5 s). Old and new terminals read Documents and Desktop with no prompt.
  3. **All terminals ended** (kill-server and bootout, as End All Local Terminals): the next server's host was the
     helper's copy, 6.8 MB, the tmux server's responsible process; the 0.4.647 copy removed. Documents and Desktop
     read with no prompt (granted under the 0.4.647 host); Downloads asked for as “Glass Power Tools”, allowed, and
     recorded under `com.glasspowertools` (client type 0); no row of the helper's own. LaunchServices lists the copy
     among the bundles for the ID and picks /Applications. `lsappinfo` lists one running Glass Power Tools, the app.
  4. **0.4.649 (the same code, another version) installed over it while the helper hosted:** the helper's code hash
     the same (`cc55e36e…` in both builds; `09e0c303…` in both before the icon came out), so no new copy; the same
     host, intact; the old terminal read all three folders at once.
  5. **Eleven minutes on** (the old way lost Documents by ten): the same helper host, intact; the old terminal and a
     new session read Documents, Desktop and Downloads with no prompt.
  No crash reports. The VM stopped after.
- **Release build (Apple Development, as his builds):** the helper is 228 KB (one 218 KB program, hardened runtime),
  its designated requirement the app's own; the iPhone and headset builds carry none.
- **On his Mac:** 0.4.648 installed at 07:45 (2026-11-24) over his running terminals. After: the same host (the
  0.4.646 copy's, started 2026-11-23 16:39), macOS's check of it intact, Documents, Desktop and Downloads read from
  a terminal of his; the helper's copy `host-09431c4033b9/Glass Power Tools.app` (228 KB) made, the unused 0.4.647
  copy removed, the 0.4.646 copy (229 MB) kept while its terminals run. No crash reports. Headset installed (second
  try; the first was interrupted); the iPhone unreachable.

## Shipping 0.4.650 (his "update the memory bank, commit, and push. Ship it!", 2026-11-24)
- `b737ac73` (0.4.644–0.4.650, with README, RELEASE-NOTES and the site's pages at 0.4.650) pushed.
- Mac v0.4.650 built with Xcode 27.2 (27B52) in the release worktree (`<work>/release-622-tree`; 0.4.632's outputs
  kept as `build/release-632`, `build/testflight-632`): app and disk image notarized, stapled, Gatekeeper-accepted
  (Notarized Developer ID); `SUPublicEDKey` the same as 0.4.632's. **The helper's first Developer ID build:** signed
  with the hardened runtime and a secure timestamp, its designated requirement the app's, 88 KB, Gatekeeper-accepted;
  the script's new check passed. GitHub v0.4.650 Latest, the tag at `b737ac73`; dmg, zip and checksums downloaded
  back byte-identical. Feed entry `321f19ff` pushed. The Mac's sixteenth release. Texts in `<work>/release-650`.
- TestFlight 650: iOS and visionOS uploaded from `b737ac73` (a second worktree, `<work>/release-650-tf-tree`), both
  VALID, What to Test set (3,280 characters, read back), both in Testers (read from the group's side; the build's
  side refuses the read), submitted for beta review; both APPROVED by the morning of 2026-11-25.
- Site built at `321f19ff` (111 files) and staged on the server, 111 of 111 matching by SHA-256; he provisioned it.
- Live, checked 2026-11-25: 111 of 111 files match the build. The feed is served `no-cache`, newest item 0.4.650,
  byte for byte `site/static/appcast.xml` at `321f19ff`. The zip from its enclosure URL is 29,734,936 bytes as
  advertised and equals the release's; its EdDSA signature verifies against the app's `SUPublicEDKey` (a copy with
  one byte changed fails).
- An independent agent check from the raw sources agreed on everything: the release and its tag, main, the
  signatures and the helper, the feed and its signature (the key the same as 0.4.632's), the site rebuilt at
  `321f19ff` (110 identical; `sitemap.xml` differs only in its `lastmod`, the build's own date), and App Store
  Connect.
- Left out of the release's highlights: the layout (0.4.636), refused until `LayoutItem` is in CloudKit's production
  schema.

## Next
- The iPhone's install when it is reachable (the change is the Mac's alone).
- His terminals move to the helper when they next all end (End All Local Terminals, or a restart); the 0.4.646 copy
  goes then.
- Watch the first release: a Developer ID helper, and notarization of a nested app sharing the app's bundle ID.
  `Tools/Release/release-mac.sh` now checks the helper as it checks the widget: present in `Contents/Helpers`,
  Developer ID signed, hardened runtime, and its designated requirement the app's (what folder grants follow,
  which notarization doesn't check). Seen failing three ways on copies of his installed build
  (`~/Software/glass/tmp/release-650/host-check-bite.sh`): Apple Development, not Developer ID; the helper re-signed
  ad hoc; the helper removed. 0.4.644–0.4.648 committed and pushed at his word (2026-11-24, "update the memory bank,
  commit, and push. Ship it!") for the 0.4.650 release.
