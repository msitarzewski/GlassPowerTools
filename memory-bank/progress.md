# Progress

Updated 2026-09-10.

## Done

- The decision to merge, with its reasoning and its costs, recorded in [decisions](decisions.md).
- This memory bank and the project guide.
- The staged [merge plan](tasks/2026-09/2026-09-10_merge-plan.md).
- Measurements the plan depends on: source sizes, bundle identifiers, shared entitlement groups,
  deployment targets. See [technical context](techContext.md). Re-verified 2026-09-10 at
  `~/Software/glass/GlassPowerTools` and unchanged.
- The bank reconciled with the actual workspace: project path corrected, sibling layout recorded, and
  the two siblings that are not inputs identified.

- The project-model decision: one multiplatform target, hand-maintained, approved 2026-09-10.
- Stage 1 planned against real APIs and real file locations:
  [task note](tasks/2026-09/2026-09-10_stage-1-shell.md). Its pre-steps and six decisions are
  listed there for the user.

- **Stage 2 at unit-level parity on 2026-09-10** (`6e5ffe6`…`410d0fc`): `GlassSSHTransport`
  engine (61 tests, security review clean, SFTP extensions/times, key-header probe); glas.sh moved
  in as `GlassTerminal` (348 tests, all pass after the inherited-PR fix); `ConnectionManagerView`
  deleted after re-homing; layering proven on the connection panel and visionOS terminal chrome;
  settings merged through three shell hooks; window recovery and settings sync moved to the
  shell; "choose a key file" delivered; one row per host with all service icons. **Whole package:
  461 tests in 23 suites pass.** Builds on macOS (real profile), iOS Simulator, visionOS Simulator.

## Not done

- **Stage 2 still open:** real-host session through the shell (integration worker; the CLI suite
  waits on the Local Network grant for Ghostty), UI suites on the final tree (blocked until the
  integration worker's `GlassTerminalUITests.swift` compiles), the macOS accessibility-recursion
  crash under XCUITest (analysis in progress), device re-installs of the Stage 2 build, widget
  verified on a device, iCloud settings sync verified live.


Stages 2–5. Stage 2 (SSH engine and terminal) is in progress with two workers; no capability has
reached parity yet. The public repositories are untouched.

## Known unverified assumptions

- That a new bundle identifier declaring the existing App Group and Keychain access group inherits
  current hosts and credentials in place. Now concrete: all three apps read
  `<App Group>/GlassHostCatalog/hosts.json`, so it should. Still proven only on a test build
  (Stage 1 step 1.8).
- That capability code moves largely intact. Measured by line count and structure, not by attempting
  it.

## Carried forward from glassDT, still open there

- Whether a GNOME sign-out now closes the session window rather than showing a failure panel.
- Whether the RDP Detail scale setting sharpens text on the user's Ubuntu host or merely shrinks the
  interface, which decides whether Automatic stays the default.
- A session indicator for encrypted versus unencrypted connections, and an SSH tunnel for VNC.

## 2026-09-11 checkpoint — Stage 2 close-out in progress

Verified: whole package 469 tests / 28 suites (W6, twice); engine real-host suite 5/5 (coordinator,
before the VM went down); kit 53/53; macOS, iOS Simulator and visionOS Simulator builds; iPhone UI
suites 7/8 (real-host test blocked by the VM being down); Mac library window, "+" placement, flat
detail column and no-sandbox local terminal judged by eye on the installed Release build.
Landed since the last checkpoint: macOS regression (three causes) and integration defects 1–5
(W4), close-out cleanup, system-wide tag field (W5), host-level address (W6), settings tabs per
platform, 3 pt canvas margin, panel roles, sandbox removal.
Open: macOS XCUITest automation mode blocked on this Mac; macOS accessibility recursion after the
connection-failure alert under XCTest diagnostics; widget on device and live iCloud sync unproven;
visionOS UI suite not re-run since the TabView change; kit changes uncommitted in the sibling repo.

## 2026-09-11 morning — Stage 2 functionally verified on Mac and iPhone against the real host

macOS: all UI suites green with the real host (library, tag field, smoke, terminal chrome, settings
pages, real-host connect to a live shell). iPhone: all suites green with the real host. Package
472 tests / 28 suites. Engine real-host suite 5/5. Fourth /Applications build pending install.
Remaining for Stage 2 close-out: visionOS UI re-run, widget on a device, live iCloud sync,
W4's post-failure accessibility recursion, the "Set Up…" bypass of the address gate.

## 2026-09-12 — Stage 3 waves 1–2: the Database capability, proven against real servers

**Verified.** Package **592 tests / 45 suites**, one known issue (D13). App builds on macOS, iOS
Simulator and visionOS Simulator with the capability registered. **12 gated live tests** against real
MySQL 8.4.11 and PostgreSQL 18.6: both engines connect through the capability, schema and foreign
keys, real rows, the read-only guard refusing a real `UPDATE` with rows read back unchanged, and
both engines **over a real SSH forward** with read-only still holding — so D7 is tested, not asserted.
MySQL additionally proven against a **flushed** auth cache, which is the only run that exercises
mysql-nio's RSA path on swift-crypto 4.5.2, a combination this port created.

**Landed.** `Sources/GlassDBKit` (engine, minus the tunnel manager — the swift-crypto conflict
dissolved with it); `Sources/GlassDatabase` (glassdb's app files, Database tab live in the one
sheet); D7's brokered forward; D14's trust prompt via a second source rather than a second prompt;
D15's read-only guard on the connection; D12's floor guard extracted to `GlassLayers`.

**Defects found by running, not reading.** Two independent PostgreSQL foreign-key bugs: an
owner-scoped `information_schema` view that returned nothing for non-owning accounts (an empty tab,
indistinguishable from a table with no keys), and composite keys returned as a **cross product**
asserting relationships that do not exist. Both fixed; the test that found the first now guards both.

**Open and honest.**
- **D13** — no way to trust a self-signed database certificate. Needs a CA-only verification mode
  *and* a CA import path; both MySQL and PostgreSQL self-sign by default.
- **Two ~10s tunnel failures, unexplained.** Three hypotheses proposed — cold-cache, contention,
  reverse DNS — **all three refuted by measurement**, two of them the coordinator's. Instrumented
  with `log_error_verbosity=3`, a counter baseline and a three-signature discriminator table,
  because three different things fail at exactly ten seconds on that path.
- **Unproven by anyone:** the D14 fingerprint prompt through SwiftUI. It needs a person, not a test.
- The macOS UI suite figure is unattributable until W-local settles; a drag-staging flake is unowned.
- Whether existing glassdb users get an import path for saved connections — credentials and hosts
  carry across the App Group and Keychain, **the connection list does not**. Awaiting the user.

**Nothing is committed.** 48 files in the working tree.

## 2026-09-12 (afternoon) — shipped to /Applications, and corrected by using it

Builds **0.3.56 → 0.3.67**, each installed with the version read back from the installed bundle.
**615 tests / 48 suites**, one known issue (D13). **Nothing committed — 63 files in the tree.**

**Verified by the user in the running app:** the canvas border, the service tabs, the colour menus,
the `tinyint` fix, and — the important one — a database connecting over the D7 tunnel to a
loopback-only MySQL on a Tailscale host.

**Closed: the two unexplained ~10s tunnel failures.** The SSH forward dropped a server-first
protocol's opening bytes; MySQL greets immediately, and the channel was wrapped in a
`NIOAsyncChannel` only after the open returned. Fixed by wrapping inside the channel initializer —
[note](tasks/2026-09/2026-09-12_ssh-forward-server-first.md).

**Three defects that passed every test**, each found by a person using the app: that forward bug
(the live tunnel test cannot catch it), `isBool` matching a bare `tinyint` so a score column
rendered as a toggle and **would have written 0 over real data**, and temporal columns accepting any
string at all. Rule 22 now records why the suite could not reach them.

**Also landed:** record-editor validation for size and format from the *declared* type (D17),
"Paint Theme Color" removed, the database name made optional, service tabs as the choice,
`Set to NULL` in the column tool row, and a Release-only link failure fixed by **not** sharing a
result-builder availability guard across modules (D16).

**Two self-inflicted regressions**, both now rules: a deleted `.toolbar(removing:)` line
investigated everywhere except the diff (rule 23), and an unverified mechanism propagated to a
worker (rule 19).

**Next, and re-planned against the code that exists** — see *Remaining work, re-planned* in the
Stage 3 plan. R1 the SQL draft-loss fix (in-memory only; it loses work), then row deletion and
foreign-key navigation. Two original estimates were wrong: AI on iOS is already done, and the audit
viewer has **no store to view** — only `os.Logger` output — so it needs a decision first.
