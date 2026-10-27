# 2026-10-24 — Test audit: every test useful, every suite reliable

`<work>` is the working-files folder outside the repository (scripts, logs, captures).

## Objective and authorization
The owner, after a full run showed 12 failures across 6 tests that I first put down to load: "Wew don't do this:
'12 failures across 6 tests' make sure those are found and settled properly. In fact verify that all of our tests
are usefule and work." Local test and product fixes are authorized; nothing is committed.

## Evidence so far
- The six failures pass alone (3/3 each) and fail in a full `GlassTerminalTests` run **on an idle machine** too
  (2 runs: 3 and 20 issues). So the target is unreliable as a whole, not "under load".
- Mechanism (measured): a temporary probe (`Tests/GlassTerminalTests/ZZMainActorProbe.swift`, env
  `GPT_MAIN_PROBE`) times `DispatchQueue.main.sync {}` from a background thread through a run, with Swift
  Testing's event stream (`--experimental-event-stream-output … --experimental-event-stream-version 0`) for
  each test's start/end. A full run: main thread held 14.7 s in one stretch (≈28 s from the start), and the
  failing tests' wall-clock deadlines expire inside it. The host process sits at 2–10% CPU: the main thread is
  *waiting* (Thread.sleep, semaphores, waitpid/waitUntilExit), not computing.
- `GlassTerminalTests` has `.defaultIsolation(MainActor.self)` (Package.swift:420): every test is on the main
  actor unless marked otherwise.
- Elimination (`<work>/stalls/measure.zsh`): skipping the live/process suites → 863 pass, longest
  stall 1.3 s, run 27.7 s (from 50 s). Skipping only the tmux/Find/scale half → longest 1.8 s; only the
  process half → 4.1 s, tmux failures remain. The 14.7 s stall needs both.
- `sample` can't read `swiftpm-testing-helper` stacks (Apple-signed): empty call graphs.

## Reviews (8 read-only reviewers; their reports are in <work>/review/*.md, untracked)
Scope: ~3,200 package tests, 119 UI tests, RDPKit (vendored steelbrain/RDPKit 0.3.1 fork) and Citadel (fork).
Static scan: `<work>/test-audit.py` → test-audit.txt (EARLY-RETURN 36, NO-ASSERT 50, SLEEP 129).

### Product defects the reviews point at (to verify before fixing)
- GlassDBKit SQLite: a timeout or cancel that arrives before the statement starts is lost
  (SQLiteAdapter.swift ~474, ~562).
- Database: `literalExpression` (TableDetailView.swift ~5175) only doubles quotes; MySQL with backslash escapes
  may reopen a DEFAULT clause (uncertain).
- Terminal: credential migrations re-run on every `catalogDidLoad` (ServerManager.swift 370/412/448).

### Unsafe
- UITests/GlassTerminalUITests.swift:403-410 leaves the SSH test private key on the general pasteboard.
- GlassDesktopCapabilityTests:38-40 starts a real RDP connect to alpha.local.
- GlassShellLibraryUITests:138,386 real SSH attempt to 10.9.8.7.
- Citadel testRebex connects to test.rebex.net, ungated.
- MacTmuxServiceTests live: bootstraps a real launchd job in the owner's GUI domain.
- `GlassLayerStore()` default (tests in shell, terminal, database, desktop, editor): writes `UserDefaults.standard`
  of the runner and reads the owner's real legacy domains (sh.glas.app, app.glassdb, app.glassdt, the App Group).
- Many terminal tests reach the real Keychain through the legacy credential migration, and the real
  key-value store through SettingsManager's default workgroups sync service.

### Plan, in order
1. Reliability: take blocking work off the main actor in the terminal suites; fix fixed-sleep
   synchronisation (GlassRemoteChangeTests and the reviewers' E lists); run every target twice.
2. Silent passes: `.enabled(if:)` for environment-gated tests.
3. Unsafe items above.
4. Can't-fail, misleading and duplicate tests (A/D/G): fix or delete.
5. Mirrors-the-implementation (B): independent known-answer vectors (MS-NLMP 4.2.4 for NTLM, a short-password
   VNC DES vector, ssh-keygen fingerprints, contrast constants) — values checked against the sources.
6. Tests of code nothing calls (C): the owner decides whether the dead code goes with them.
7. Vendored packages (RDPKit, Citadel, swift-nio-ssh): only unsafe/flaky fixes and our own patches' tests.

## Done so far (not committed)
- **Product: `GlassSpawn` (new, `Sources/GlassTerminalEmulator/GlassSpawn.swift`).** A child of `posix_spawn`
  inherits the spawning thread's blocked signals; Dispatch and concurrency threads block most (mask fbfee027:
  SIGHUP, SIGINT, SIGTERM, SIGCHLD…; main blocks none — `ps -o sigmask` shows 0 and misleads). A tmux server
  started from one ignored `kill-server` and SIGTERM (its panes never got SIGHUP; it couldn't reap), and its panes
  would start with Ctrl-C blocked. Reproduced standalone (`<work>/sigmask/`); Foundation's `Process`
  from the same thread is fine. `GlassSpawn.prepare` gives children an empty mask and default dispositions;
  used by `MacLocalTmux.run`, `TmuxControlPipe`, `MacTmuxHost.serve`, the tests' `LiveProcess` and
  `LiveTmuxControlTests`. Today's server starts are on main or launchd, so no live defect is known; it was one
  background start away. Test: `MacTmuxHostTests.signalsReachWhatTheAppStarts` (fails without it, with
  `endsWithoutSessions`).
- Terminal suites' blocking work off the main actor: `LiveProcess.runDetached`, `offMainActor` (Dispatch, not the
  cooperative pool); MacTmuxHost/Service suites `nonisolated`; live tmux, Find, repository, session-name,
  dropped-path, link-target and key-import tests await their processes; fixed sleeps → waits for the condition.
  `reattachWithHistory` waited for history ≥ 1,980 (an off-by-one race) → the last row. The scale test runs its
  own shell (`env -i`), not `/bin/sh -l` with the owner's profile. The "SwiftTerm PTY reader" comment in
  `localPane` was wrong (control mode uses a pipe) and the "tmux 3.8 kill-server" one too (blocked signals).
- Result: `GlassTerminalTests` 991 pass twice in a row in 21 s (was 50 s and failing), longest main-thread stall
  2.5 s (was 14.7 s), no leftover servers.
- `TerminalHostTrustBroker.waitingCount` (internal, for tests) and a 1-minute limit on its suite: its cancel test
  raced and hung a whole run.
- Silent gates → `.enabled(if:)` with the reason: SSH real-host suites (and `XCTSkipEquivalent` gone), live remote
  suites, control-mode suite (and `#require` its server), root-only save test, six timing probes, the live
  database diagram (cases only for configured engines).
- Unsafe: the UI test's SSH private key is kept to this device, concealed and cleared; the Active-row desktop test
  no longer dials alpha.local; UI tests' 10.9.8.7 → 192.0.2.87; Citadel `testRebex` opt-in
  (`CITADEL_INTERNET_TESTS=1`, PATCHES.md); `GlassLayerStore.forTest()` (TestLayers.swift in shell, terminal,
  database, desktop; TestDefaults.swift copied to shell) replaces ~80 bare `GlassLayerStore()`.
- Shell: remote-change, settings-sync log read (off main), service availability (waits for the listener to close),
  window aspect lock, toolbar placement (requires the pane's own buttons) no longer use fixed sleeps.
- Editor: `AtomicSaver.writeAtomically(…, write:)` seam; the partial-write pen tests use `Pen.writeFailingPast`
  instead of a process-wide `RLIMIT_FSIZE`.

- **Product: SQLite Cancel and timeout** (`SQLiteAdapter.swift`). `sqlite3_interrupt` reaches only a running
  statement; a Cancel or timeout while a query waited its turn or was preparing was lost and the query ran to
  its end (shown: 262 s for a billion-row query the test cancelled). Now every in-flight query has a stop flag
  (`SQLiteQueryStop`) set by its timeout, task cancellation and `cancelCurrentQuery`, checked before stepping
  and by `sqlite3_progress_handler` every 1,000 VM steps; an interrupted prepare reports the cancel/timeout,
  not "interrupted". Test `SQLiteAdapterTests.cancelAndTimeoutReachAQueryNotYetRunning` (fails without).
- **Product: MySQL default literals** (`TableDetailView.literalExpression`, `escapingBackslashes`). Only quotes
  were doubled; MySQL treats `\` as an escape (NO_BACKSLASH_ESCAPES off by default), so `x\', DROP COLUMN
  secret #` reopened the clause — and Keep Current carries the *server's* default, a trust boundary — and a
  server default `a\b` went back as a backspace. MySQL now doubles backslashes; PostgreSQL/SQLite unchanged.
  Two tests (fail without); the old check with a space that never matched now asserts the exact SQL.
- Run 3, 4 (one my own rewrite), 5 (DatabaseConnectWatch deadline race: fixed with a released stream), 6 all
  pass otherwise. Full package ≈ 115 s.
- Can't-fail / misleading / duplicate fixes so far: editor (workspace tautologies → the file must arrive in the
  named window; contract tautology deleted; my marks test settles first; UIKit offset read-back dropped;
  setgid precondition; pass-through test deleted; "BUG:" names); terminal (key names pinned; three identity
  tests deleted; SOCKS5 encodes what the manager holds; setup-sheet test renamed to what it checks; retry
  tests say what they cover; command policy renamed; duplicates in key import, open-together, look sync;
  geometry tautology); shell (route and card-contract tests deleted; exact registry order; tag spellings;
  every shortcut spelling via `owners(of:)`; widget intents performed; favourites-first visible; usage day
  keys; remote-change posts until a sync).
- Isolation: `SettingsManager.forTest()` (TestSettings.swift, in-memory stores) for a dozen terminal tests;
  editor runtimes and terminal runtimes get `GlassLayerStore.forTest()`; desktop import/relaunch tests use
  in-memory credentials and a temporary folder.
- Timing: VNC polls 30 s + `#require` before slicing (a short answer crashed the whole run); free UDP ports
  below the ephemeral range; seeded ZRLE test; iCloud stale-completion tests use `mainActorTurns()` (exact
  ordering) instead of 10 ms sleeps; glas_sh 10 ms polls 30 s.
- Private names removed from code and tests: the test VM's name, a machine's MySQL, a private-range address
  (now 10.0.0.20), a person's name, a tailnet host name, the macOS VM's name and its key's file name; RDPKit's
  upstream author's machine and account (GLASSDT-PATCHES.md); Citadel's (PATCHES.md).

## Done since (later the same day)
- **Product: RDP, a server's reason for ending** (`Packages/RDPKit/Sources/RDPKit/ConnectionPreflight.swift`,
  `TLSTPKTStreamHandler`). Found by `liveDeactivateThenEOFHonorsOptionalReasonAndExplicitDenial`, which failed only
  in busy full runs (`nextStage` "rdp-graphics-frame-decode", no ErrorInfo). The close (`channelInactive`) went
  through `fail()`, which discarded packets that had arrived whole but were not yet asked for, and `nextPacket`
  answered the failure before the queue: a server's ErrorInfo + Deactivate All before it hangs up were lost when
  the client was still busy with the frame before them, and the session read as a clean end. A close now hands on
  what arrived, then the disconnect; an error or cancellation still discards at once. `TPKTReaderTests` (embedded
  channel, both cases; fails without). RELEASE-NOTES bullet; GLASSDT-PATCHES.md.
- RDPKit: MS-NLMP 4.2.4 known answers (bytes fetched from Microsoft's pages, cited in the test): NTOWFv2, session
  base key, NTProofStr and temp, encrypted session key, LMv2, and the context driven with the spec's CHALLENGE to
  the sealed "Plaintext" and its signature. Passed first time. Swapping client/server sealing keys is caught by
  it and by the GNOME transcript replay too. `ntlmV2Hash`, `ntlmV2Response`, `RDPNTLMRC4` lost `private`.
- RDPKit: `trustFixtureCertificate()` no longer turns on redirection and auxiliary channels (the app never does);
  the two auxiliary-channel tests opt in. 1,030 tests, three clean runs.
- Citadel: free loopback ports (were 2222/2345 on every interface, any host key accepted); exec fixtures end once
  the server has read their output (`succeedOnceRead`, FIONREAD + stderr reader done) instead of 0.3 s; the exec
  *server* hands stdin over only as it closes the pipes (measured: none in a second), so the stdin test waits for
  it; disconnect test waits and closes its server; remote-forward tests count opened forwards (live, not run:
  password sign-in, the test VM takes keys); hard-link test drives `hardLink`; open flags 0x2A and ATTRS bytes from the
  SFTP draft; two names corrected; memberwise test deleted. 62 tests, 6 skip without a server; ~1 s (was 5 s).
  PATCHES.md. BUILDING.md's tunnel port 2222 → 2223.
- swift-nio-ssh: 367 pass; PATCHES.md count corrected (11 added, not 7).
- Editor: grammar loading merged into `GrammarCoverageTests` (pattern count kept); UIPen's clamp and mid-application
  tests folded into AttributedAssembly/AppKitEngine (two extra cases, the "view's own write passes" check);
  `EngineProtocolTests` deleted (defaults: Debounce has 75 ms, Theme now pins 4.5); six UIPen names that still
  said the old bug corrected. StoragePropertyTests kept beside FuzzPen (different generators). 325 pass.
- Desktop/VNC: the "input lands" test repeated `pointerMappingFollowsTheVisibleDisplay` and the Retina window's
  `pictureRegion` tests (and used `region`, not what input uses): deleted. Several-displays resize: 400 ms sleep →
  `resizeTask` is nil (fails without the guard). VNC record layer: positive wait for the pasteboard record (the
  send returns before the record reaches the sink); RetinaAndPointer: 50 ms sleep → wait for the scale message,
  the whole-desktop check folded into the later frame check; shared `waitUntil` 2 s → 30 s with a message;
  high-performance poll 1.5 s → 30 s. VNC DES known answers from OpenSSL (short, long, empty password).
  `GPUPresentationTests` draw through the renderer (`drawTexture`, wallpaper from a PNG) — a texture-binding swap
  in the renderer fails them now, which the copied pipeline could not see.
- SSH fingerprint from `ssh-keygen -lf`; terminal contrast pinned to WCAG (21:1, #767676 4.54, #777777 4.48).
- UI tests: vacuous checks (labels and identifiers the app no longer has: `setup-enable-*`, "Set Up…", "Desktop is
  not part of this build") removed or made positive (a connect attempt); `if tab.waitForExistence {…}` →
  asserted; the phone tour fails at the end naming unreached pages; All Windows pane `#if os(iOS)`; clipboard
  saved and restored (`UITestClipboard`) in the database, paste and key-paste paths; the device's edit sheet
  checks the Terminal tab is absent; Material test renamed. The foreign-key menu tests stay an honest skip
  (XCUITest cannot open a Menu inside a contextMenu). The live-terminal echo is still not asserted: whether the
  terminal's text reaches accessibility at all is an open question.
- Verified, not changed: terminal tests' live Keychain stores resolve no access group under `swift test` and read
  the runner's own namespace (probe: notFound); no test writes a credential through one. The credential and
  host-trust migrations re-run per load but return at once on their stored version.
- The temporary probe `ZZMainActorProbe.swift` is removed.

## The UI tests, run on an iPhone 17 Pro simulator (iOS), the same day
Both platforms' UI tests compile (`build-for-testing`, macOS and the iOS simulator; `-skipPackagePluginValidation`
as the release scripts pass). The Mac UI tests were not run: they drive the owner's screen.
First full iPhone run: 51 passed, 13 skipped, 15 failed. Each failure looked at with its screenshots:
- **Product: the paste review was wider than a phone** (`TerminalPasteReviewSheet`, a Mac `.frame(minWidth: 560)`
  on every platform): on a 402-point screen the sheet was clipped both sides, Cancel, Paste and Join Wrapped Lines
  off its edges. Mac-only now. `TerminalPasteUITests` had failed since 2026-10-19 with this as the cause.
- **Product: VoiceOver's terminal lines after a resize** (`SwiftTermHostView`, both coordinators' `sizeChanged`):
  the value was refreshed after output and scrolls, not a new grid, so at the largest text it still held the
  80-column lines from before layout. `LargeTextUITests.testTheTerminalsTextGrowsAtTheLargestText` failed
  (80 vs 41 columns) and passes with the fix alone. Screen recording showed the text itself had grown.
- Test, eight at once: the scope row's identifier is on its stack, so on iOS the first match is the icon, which
  iOS 27 calls not hittable. `XCUIApplication.libraryScope` (UITestLibrary.swift) takes the title text on iOS;
  the tag-field test reads `shownText` (label on iOS, value on the Mac).
- Test: the editor's Save went into the iPhone toolbar's overflow, so "the editor opened" waits for the status
  bar's position button, now `editor-position` (an identifier added for it). Screenshot: the file was open.
- Test: a long-line SVG opens as its picture on a phone (D-decision 2026-09-23, "previews only on iOS"); the test
  waited for text. It now checks the picture is drawn (red pixels in the app's screenshot), then text and back.
  Its fixture, one filled zigzag of 60,000 self-crossing points, is never painted by WebKit (checked on the Mac
  with a WKWebView probe, `<work>/svgprobe/`); a 1–2 MB line of 40,000 small shapes plus the
  embedded PNG is, so the seed (`GlassEditorProjectLibrary`) is that now. Small SVGs preview on the phone.
- Test: the row's chevron was looked for in the detail, whose Connect went on 2026-09-13 (D24); it is the row's
  on touch platforms, skipped on the Mac (the row is one element there).
- Vacuous checks fixed earlier showed their worth: `setup-enable-*`, "Set Up…", a desktop string — none exist.
Re-runs: the 15 → all pass except the paste test, re-run after its fix (see State).

## Skips (the owner: "why are there skips?! Why bother?")
A skip proves nothing, so each was run, turned into a check of what that device does, or put to him.
- **Live tests run against the test VM** (started the runbook's way). Loopback tunnels: 2223 SSH,
  23306 MySQL, 15432 PostgreSQL — not 13306, where this Mac's own mysqld listens (a test reaching it would have
  been reaching the owner's database). `<work>/live-env.zsh` (and `live-ui-env.zsh`, the
  `TEST_RUNNER_` form) source `~/.config/gpt-db-test.env` and print nothing. 49 package tests that skipped ran.
- Tunnel tests assumed the far side sees the Mac's address and ports; through the documented loopback tunnels it
  does not. `GPT_SSH_TEST_FAR_HOST/_PORT`, `GPT_DB_TEST_MYSQL_FAR_PORT`, `GPT_DB_TEST_PG_FAR_PORT` (BUILDING.md);
  unset, the same as the others.
- `claimedSessionSeesWhatATypedOneSees` compared PATH strings; the claim appends `searchPath` on purpose (D47) and a
  typed session's login profile repeats entries. Now: the same directories in the same order, extras only
  `searchPath`'s, the same locale. (A test adapted to the code, said so to the owner.) Its "no tmux" early
  returns record an issue instead of passing.
- Reconnect tests: `DatabaseSessionManager.retrieveSavedPassword` (internal; the Keychain by default) lets them
  give the password without writing a synchronizing Keychain item. Both pass against the test VM.
- The passwordless MySQL test defaulted to `root` on 127.0.0.1:13306 — this Mac's MySQL. It now needs a named
  user and refuses root; not run (needs a passwordless test user made by someone with admin rights).
- UI: Scale on a phone checks the Tools menu has no Scale Text; the database test runs on both (a window of its
  own, or in place); the overview and file-name large-text tests check the phone's case; the SVG test the iPad's
  (opens as text, Preview draws it); the iPhone Tools, desktop status-bar and filter-bar tests run on iPad too.
  The user's-own-logo test (needed a path by hand) is deleted: the large-SVG fixture is that shape.
- iPad: iPadOS brings back windows from earlier launches, so a database window from one test ("Connection
  Closed") stood in front of every later test's library — the 18 iPad failures. A UI-test launch (Debug,
  `--ui-testing`) with more than one saved window now discards them and asks for one fresh default window
  (`GlassPushDelegate`); a person's windows are untouched. A first try in the library window did not fire when
  that window was hidden; discarding alone left no window at all.
- Duo: the outer display puts the back button in iOS's column; tests tapped "the bar's first button".
  `XCUIApplication.backButton` finds `BackButton` (UITestLibrary.swift), eleven uses.
- Measurement probes (7), D-008's tests (3), the synchronizing-Keychain tests (3, signed app only), the
  passwordless test are the owner's decisions (report). The foreign-key menu tests run on iOS (2026-10-25,
  below); on the Mac they await decision 7.

## The Duo (outer display, folded; iOS 27.1)
Full run, then re-runs of what failed. Test causes: the back button is in iOS's column (`backButton`); search is a
button in that column; the ⚡ a person can reach is the editor's, not the library's still in the tree; a tap in a
right-aligned field puts the cursor before its value (`tapAtEnd`, which made a port 222322); the engine picker
publishes its choice in the label on 27.1 (`Engine, MySQL`), not the value; a phone shows a database in place with
tabs, its Settings in the overflow; a phone's file list wraps a long name at the largest size (checked unclipped).
**Duo finding for the owner:** in the Add Host sheet, committing a name or collection with Return in the lower
fields makes the sheet's whole bar — title, Cancel, Add — disappear until the form is dragged down (probe pictures,
`<work>/uitests/att-p3/grid.png`). Our sheet is a plain Form with a standard toolbar; the likely
remedy is an inline title in iPhone sheets, a visual change, so asked rather than made. Tests drag the form down
first (`revealSheetButton`), as a person would.
Also seen: the number pad has no Done key (iOS gives none; the app adds none).

## The final runs (2026-10-25)
Latest build, live servers: iPhone 17 Pro (iOS 26.5) 72 pass, 6 fail; folded Duo (iOS 27.1) 71 pass, 7 fail; no
skips. Every failure traced:
- Five database tests: `replaceText`'s double tap selected nothing (the form's fields are trailing-aligned and the
  centre is empty space), so "gpt_test" went in front of "root"/"postgres"; `setField`'s new check caught it.
  Probed six ways on both phones (`ZZFieldProbeUITests`, removed): Select All from the press-and-hold menu works on
  both, whatever the alignment, and is what a person does. `replaceText` uses it.
- Files header: the Open button's identifier is replaced on iOS by the row's (`host-tool-files-<id>`), as with the
  library's scope rows; the test now takes the button under either name. The swipe-ups added for the Duo were a
  guess and are gone.
- Tag test (Duo only): the input reports the whole row as its frame, chips included; a tap at its centre (x 203)
  hit the edge of Lab's remove button (138–204) and deleted Lab, so the second host was offered only Clients. The
  duplicate check ("no third chip") passed regardless. The suite now focuses inputs at their trailing end, as a
  person taps, and the duplicate check also asserts Lab is still there. The refocus line added for the Duo
  ("choosing a suggestion ends editing") was a wrong diagnosis and is removed: the iPhone probe showed suggestions
  stay after a pick. **Finding for the owner:** the input's accessibility frame covers the chips on iOS (both
  phones); what VoiceOver does with it is not checked yet. *(Superseded below: the fixes above were not all
  right, and VoiceOver is now checked.)*

## The re-run, and VoiceOver (2026-10-25)
The first re-run of the three suites on the iPhone (stopped) still failed seven tests:
- Five database tests still typed "gpt_testroot": `replaceText` skipped the menu when the value equalled the
  placeholder, and the database form shows the engine's default user both as the value and as the prompt ("root").
  Now only an empty value skips Select All.
- The tag test: tapping the input's trailing end missed the real field on the iPhone (no chips: frame
  125–370, field elsewhere). Superseded by the product fix below; the suite taps the input again.
- `testConnectsToRealHostThroughTheShell`: no keyboard focus after connecting. Cause: D44's "Keep Terminals Running
  with tmux?" alert, shown on the first connection to a server with tmux (the test VM has it; every run has a new
  library). Typing raced it. Its echo check could not fail ("terminal output not visible to accessibility" was
  recorded as an activity and passed), and in every passing run the echo was never seen. Now: answer Not Now, type
  `echo GPT_OK_$((6*7))_<id>`, and require the shell's `GPT_OK_42_<id>` in the terminal's accessibility value
  (passes on the iPhone; fails when Return is not sent, so typed text alone cannot satisfy it). The suite launches
  with `-blinkingCursor NO`: the blinking caret made XCUITest wait 60 s for idle before each action (three per run,
  316 s → 118 s).

**VoiceOver, with the real VoiceOver.** The iOS 27.1 simulator runtime ships `VoiceOverTouch.app`; it starts with
`defaults write com.apple.Accessibility VoiceOverTouchEnabled -bool true`, `notifyutil -p
com.apple.accessibility.cache.vot.enabled`, `launchctl start com.apple.VoiceOverTouch` (via `simctl spawn`). XCUITest
touches and swipes reach it; its log (`log stream --predicate 'process == "vot"' --level debug`) names the element
under each touch and every phrase spoken (`Action: '…'`); full-screen screenshots show its cursor. Its double tap
is recognised ("Built-in: Activate") but reaches nothing, not even a plain button, so activation cannot be observed
in the simulator. Findings on the spare Duo (outer display), Add Host, tags Clients and Lab:
- Touch reached every chip ("Clients, tag"), every remove button ("Remove Lab, Button") and the input; swipes read
  Also known as → Clients → Remove Clients → Lab → Remove Lab → the input → keyboard.
- The defect: the input (`SwiftUI.UIKitTextField`) had the whole row as its accessibility frame; VoiceOver outlined
  the chips as the text field, a touch at the end of Lab landed on the field, and the activation point was the row's
  centre (203, 363). `accessibilityActivate` returns NO (measured in the app with an injected probe library,
  `<work>/ax/axprobe.m`), and a tap at that point removed Lab in the Duo suite run. Deque documents
  VoiceOver's default activation point as what triggers an element; Apple's page says only that the double tap calls
  `accessibilityActivate`. Not observed on a device.
- Cause: the row's `.contentShape(.rect).onTapGesture { focused = true }`. Moved into a `.background`, the field's
  frame is its own box (210, 352, 135 × 22), activation point inside it; VoiceOver outlines only the field and a
  touch at the end of Lab reads "Lab, tag". Every tap still focuses the field (a chip's name, the gaps, after the
  field, just below the row), and × still removes. The tag suite asserts the input's frame covers no chip (iOS
  only; fails without the fix, passes with it on the Duo and the iPhone). The Mac is not measured.
- Also found: when two keystrokes arrive in one update ("Clients,L"), `commitDraft` commits everything, so "L"
  became a tag. Proposal for the owner: commit up to the last separator and keep the rest as the draft (as macOS
  token fields do); it changes paste of "a,b,c" (c stays until Return).

**Database suite past its old failure point (iOS runs five of its tests).** With the text fixed, the tests reach
code never run on iOS before:
- Every open tab keeps its views (`DatabaseWorkspaceView.detailSurface`: opacity 0, no hit testing,
  `.accessibilityHidden`). VoiceOver does not see the hidden ones (Device Hub's flat list has one
  `db-query-editor`), XCUITest does: two editors in one frame, and `firstMatch` on `db-query-run` was a hidden
  tab's (hit point {-1, -1}), so the fixture statements never ran; the server check caught it ("the server holds
  [] …"). The suite's `element` and `queryEditor` now take the hittable match when there are several (`onScreen`).
- The Duo's outer display puts Run in the bar's More, where the entry is its visible title "\u{2002}Statement":
  no identifier, no "Run". **Finding for the owner:** the Run control's accessibility label on iOS is " Statement"
  even in the wide bar (Device Hub shows `desc= Statement`; the `.accessibilityLabel("Run Statement")` modifier
  does not reach the toolbar item), so VoiceOver reads "Statement". Proposal: title it "Run Statement" (visible).
- Run behind the keyboard: on the iPhone Run is in the bottom bar, covered while the editor has the keyboard. The
  tap had no hit point and XCUITest carried on as if it landed; `isHittable` even said yes under the keyboard.
  The suite compares Run's frame with the keyboard's and uses the editor's own Hide Keyboard key
  (`editor-hide-keyboard`). Observation for the owner: running SQL on the iPhone needs the keyboard put away
  first; a Run key on the editor's keyboard bar would save it.
- Text in the editor: backspacing from the tap left the rest of the old statement after the cursor, so the server
  got a CREATE with the end of the DROP ("near 'IF EXISTS …'"). Now ⌘A then type, and the suite asserts the editor
  holds exactly the statement before running it.
- The schema list on the iPhone is a level behind the editor; `refreshDatabase` returned quietly when it was not
  on screen (now: back to it, and a failure if it never shows). A table's actions are its row's "…" menu
  ("Table Actions"); a long press on the row acts as a tap and opens the preview. **Finding for the owner:** the
  preview reads "double-click the table in the sidebar to open its Data workspace" on the iPhone, which has
  neither (`DatabaseDetailView.swift:1031`).
- Caution: XCUITest's log prints the first 18 characters typed into a secure field ("Type '…' into
  SecureTextField"); filter such lines out of anything shown.
- A Set Up hung 11 minutes: `UIPasteboard.general.items` never returned (the iPhone simulator's pasteboard service:
  `simctl pbpaste` → "Unable to connect to device pasteboard" while booted). `UITestClipboard` now gives up after
  10 s with "shut the simulator down and boot it again". Not yet seen firing (the service recovered).

**Full iPhone run (2026-10-25, every UI test, latest build):** 78 tests, 0 failures, 2 skipped, 63 min. The two
skips were the foreign-key tests, and their reason ("no synthesized gesture opens the submenu") was false on iOS:
the tree dump at the skip shows the submenu open, its entries buttons with the right identifiers and titles. The
lookup searched `menuItems` (the Mac's type). Now `buttons` on iOS, and a missing entry fails there instead of
skipping; the Mac keeps its skip, unmeasured (decision 7). `openTable` also goes back to the schema list first
(a follow leaves the iPhone on the referenced table's data). **Follow Reference is now seen working through the UI
for the first time**, on MySQL and PostgreSQL: the composite key opens `gpt_ui_parent` at exactly (1, 2, one-two),
the single-column key `gpt_ui_ref` at exactly id 8. Both pass (498 s, 497 s). Bite: with the composite pairing
transposed in `ForeignKeyNavigation.filters`, the MySQL test failed "the grid reads ‘two-one’"; file restored
byte for byte. Each takes about 8 minutes because the fixture is 13 statements typed and run through the editor,
then three checking queries: work, not waiting.

**Full folded-Duo run (same day):** 78 tests, 67 pass, 11 fail, 0 skip, 45 min (the runner restarts once per
failed test: 11 restarts, 11 failures, none on the iPhone run). Two causes, traced from the recordings:
- **Product defect, fixed: a ⚡ under a sheet answered a hold.** The window's hold knows a ⚡ SwiftUI draws by the
  view behind it (`GlassBoltProbe`), judged by frame alone, and a sheet leaves the library (⚡ and probe) in the
  window. On the Duo's outer display the library's ⚡ is at (224, 47); XCUITest scrolled the port field there and
  pressed for the edit menu, All Windows ("Nothing Is Open") came down over the Add Host sheet, Select All went
  under it (hit point {-1, -1}), and "23306" went in front of 3306 (five database tests). A person holding the
  sheet's title there gets the same. New test `testHoldingASheetOverTheBoltIsNotAHoldOnTheBolt` fails on both
  phones without the fix; `isOnProbe` now takes only a probe inside the frontmost presented controller's view
  (`GlassAllWindowsPull.frontmostController`).
- **Test, against a known Duo behaviour: the sheet's bar leaves.** About a second after a password is typed, with
  nothing touched, Add moves to y −27 (not hittable) and stays there until the form is dragged down (probe, 20 s
  sampled). The tests found Add, then tapped it after it had gone (six library/terminal tests: "the sheet closes
  after Save", "missing host-editor-save"). `revealSheetButton` is replaced by `tapUntilSheetCloses`
  (`UITests/UITestLibrary.swift`): taps only while Add is on screen, drags the form down otherwise, and counts a
  tap as landed only when the sheet (known by its bar's title) is gone; fails if a drag closes the sheet before
  any tap. **Finding for the owner:** Add Host does not refuse a drag down, so a person who drags to bring the bar
  back can close the sheet and lose what was typed.

**Second full folded-Duo run, after both fixes (same day, `full2-duo.log`):** 79 tests, 75 pass, 4 fail, 0 skip,
71 min. The four were the database tests' fixture checks ("the server holds [alpha] where [alpha, beta, gamma] was
written"), and the server held all three: the grid read "3 rows". On the outer display Run is in the bar's More,
which (unlike the bar's Run) left the keyboard up, the keyboard covered all but the grid's first row, and rows not
laid out are not in the tree, so the reader's walk ended at row 1 and blamed the inserts. Fixed in the test:
`serverRows` puts the keyboard away first (`putKeyboardAway`, the editor's own Hide Keyboard key), and a short read
now says "the grid says N rows but only … could be read" when the grid's count disagrees, instead of blaming the
server. Compiles for iOS and macOS (all changed files compiled in both).

**Second full iPhone run (`full2-iphone.log`): every database test failed in Set Up in 10 s,** "Unanswered()" from
`UITestClipboard`. Not a broken pasteboard, as its message said: Xcode copies the Mac's clipboard into every booted
simulator (`dtpasteboardd`; saves with no bundle ID at 11:24, 11:27, 11:35 ×3 and 11:53, on both simulators, while
the owner used the Mac), and the runner's read of text it did not write is answered by iOS with "“GlassPowerToolsUITests-
Runner” would like to paste from “dtpasteboardd”" (Allow Paste / Don't Allow Paste) over the home screen, captured on
the Duo; the simulator log reads "Paste requires user authorization. Prompting...". The earlier 11-minute hang was
very likely the same prompt. Fixed in `UITestClipboard.init`: when the read has not answered in 2 s, tap Allow Paste
in SpringBoard, as a person would; the text is read only to be put back. Proof: the SQL-editor test failed twice on
the Duo in that state, and passed with the change (Allow Paste tapped at 3.3 s).

The terminal and paste suites passed in that run, and that was the second defect in the guard. XCUITest's default
alert handler dismissed the prompts left by the timed-out reads with "Don't Allow Paste" (log: "Default interruption
handler attempting to dismiss alert by tapping … cancel-button"), and from then on iOS answered the runner's reads
"Paste denied silently": the right number of items with nothing in them. The guard saved that and put it back, so
every terminal test ended by emptying the clipboard (12:14 on). Fixed: an all-empty read while
`UIPasteboard.general.types` still lists data (the types are not refused) throws `Refused`, whose message says to copy
something new. A temporary probe (deleted) proved each case on the iPhone: Don't Allow → one empty item while types
reads `public.utf8-plain-text` → `Refused` (before the fix: "did not throw"); a pasteboard holding one genuinely empty
item (types `[]`, left by the old guard) → saved without complaint; a new copy → asked again, allowed, read.
**For the owner:** during a UI run the Mac's clipboard is shared with the simulators both ways, so a copy made on the
Mac mid-test can be replaced when the test puts the clipboard back, and the 12:14 empty write very likely emptied
the Mac's clipboard too.

## Decisions for the owner
1. Tests of code nothing calls (reviewers' C lists): EndpointProfile*, GlassConnectionLink/GlassDestination,
   HostCatalogDeletionOutbox, HostCatalog publish/detach/remove, GlassSpatialGeometry, the concentric window
   shape, canvasOpacity, GlassServiceStore helpers, consolidation, DesktopEdgeGeometry, PresentationSettings.alpha,
   the per-display connection (dormant), retrievePasswordWithFallback, the Secure Enclave wrap, SchemaContext
   options, givenNameQuery, SQLStatementSpikeTests, `Disabled-transport-era-tests.swift.txt`: delete code and
   tests, or keep both?
2. Seven measurement probes that only print (`GPT_LARGE_FILE`, `GPT_SCROLL_TIMING`, `GPT_GRID_TIMING`,
   `GPT_TUNNEL_PROBE_PORT`, `GPT_DB_PERF_PROBE`): keep as opt-in tools, or delete.
3. D-008's three tests, which can never run (tree-sitter-sql cannot do it): delete (decisions.md keeps the fact).
4. The synchronizing-Keychain tests (3): host them in the signed app (they would write a per-run item to iCloud
   Keychain and delete it), or delete.
5. The passwordless MySQL test: a passwordless non-root test user on the test VM's MySQL (needs its admin), or delete.
6. ~~The foreign-key menu UI tests~~: settled on iOS (they run and pass; the skip was a wrong lookup). On the Mac
   they still skip after their gestures; whether that is also a lookup goes with decision 7.
7. The Mac UI tests: run them in the macOS VM, or on his screen at a time he chooses.
8. The Duo sheet bar: an inline title for sheets on iPhone? Now also seen leaving on its own a second or two
   after a password is typed, and staying gone until the form is dragged down.
9. Add Host does not refuse a drag down: with the Duo's bar gone, the drag that brings it back can close the
   sheet and lose what was typed. Refuse it while the form has changes (`interactiveDismissDisabled`), or ask?
10. Run's accessibility label on iOS is " Statement" (VoiceOver: "Statement"; the Duo's More shows "Statement").
    Title it "Run Statement" (visible)?
11. The tag field's draft split: two keystrokes in one update ("Clients,L") commit "L" as a tag. Commit up to
    the last separator and keep the rest as the draft (changes pasting "a,b,c": c waits for Return)?
12. Observations: Run is behind the keyboard on the iPhone (a Run key on the editor's keyboard bar?); on the Duo's
    outer display the keyboard stays up after a run and covers every result row (the grid shows its header and
    "3 rows", nothing else); the iPhone preview says "double-click the table in the sidebar"
    (`DatabaseDetailView.swift:1031`).
13. Device test plans (the iPad runs phone-only suites).

## State
Package: 3,113 pass (run 15, live servers, under load); 14 skips, all in the decisions list. RDPKit 1,030,
Citadel 62, swift-nio-ssh 367. UI (2026-10-25): every UI test on the iPhone 17 Pro and the folded Duo, 79 each.
iPhone 74 pass, 5 fail; Duo 75 pass, 4 fail; no skips. All nine failures were the tests (the clipboard guard's
prompt; the grid read behind the keyboard), fixed and proven as above. The database, terminal and paste suites are
re-running with the final code on both (`<work>/uitests/fix-{duo,iphone}.log`); their result is the last open
check. Every changed file compiles for macOS. The iPad run on an older build had 23 failures: fixed causes, plus
phone-only suites now running there (the editor-on-iPhone suite, the All Windows pane, the iPhone
Tools/diagram/desktop tests) — device test plans proposed to the owner. Not run: the iPad on the latest build, the
unfolded Duo, the Mac UI tests (decision 7). Committed with 0.4.522 at the owner's word (2026-10-25). Probe test
files are removed.

## 2026-10-26 — W19's interval, timed from the wrong moment (test fixed)
`MacLocalTmuxTests` "W19: one read of this Mac's tmux answers every local tab…" failed once in a full terminal run:
`ContinuousClock.now - first >= interval - .milliseconds(150)`. The product paces reads from its last read
(`MacLocalTmuxContextReads.lastReadAt`); the test started its clock after its own wait for the first titles, so a late
wake from that wait made a read on time look early. The fake now records when each read begins and the test times
between the reads (50 ms allowance). Shown: with a 300 ms late wake added after the first read, the old timing failed
and the new passed, the product unchanged; with the product's wait for the interval removed, the new timing failed.
Sources restored byte for byte; the terminal suite then passed whole (1,021).
