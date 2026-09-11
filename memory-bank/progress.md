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
