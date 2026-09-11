# Stage 2 — integration: a real host through the shell

Worker: Stage 2 integration. 2026-09-10. **Status: partial. The shell → terminal handoff and the
engine's connection to the real host are proven on the iOS simulator up to the host-trust prompt;
the post-trust reconnect fails on a session-registration defect; macOS is blocked at the key-entry
sheet by a deterministic accessibility crash. Nothing committed by this worker.**

Runs were made from a detached worktree at `../GlassPowerTools-stage2` (first `9d59988`, then
`9f58a61` = HEAD at the time) because the main tree was being edited by W3 mid-run; the worktree is
left in place for the coordinator. My only file in the main tree: `UITests/GlassTerminalUITests.swift`.

## Parity table (what was actually exercised)

| Item | iOS Simulator (iPhone 17 Pro Max, iOS 27) | macOS (real profile, no override) |
|---|---|---|
| App builds | passed | passed (`xcodebuild build`, signed, entitlements incl. iCloud KVS) |
| Add host → detail → Add a service → SSH | passed | passed |
| Connect on the SSH service opens glas.sh's server form, pre-filled from the shell host (name, alias as host) | passed | passed (`Import Connection`, `Save Connection`) |
| Legacy-algorithms toggle shows the audit's warning text | — | passed (visible in the form) |
| Server form: username, port, Method → SSH Key | passed | passed |
| Add SSH Key sheet: name + pasted private key → Save | passed | **failed — app crashes (see Defect 1)** |
| Save Connection → Connect from the detail | passed | not reached |
| Engine reaches `192.0.2.6:22`, key exchange, host key received | **passed** — trust prompt shows `ssh-ed25519`, SHA-256 fingerprint of the VM | not reached |
| Trust and Connect → live terminal | **failed — "This terminal session is no longer active" (Defect 2)** | not reached |
| `echo ok` round trip, resize | not run | not run |
| SFTP browse `/tmp`, upload/download | not run | not run |
| Local port forward to the host's own :22 | not run | not run |
| Workgroups / Mac workspace | not run | not run |
| `../glas.sh` still builds untouched | passed (`BUILD SUCCEEDED`, macOS target; its 61 dirty entries pre-date this session) | |

**Local Network prompt for the GUI app:** none observed on macOS — the run never reached a network
attempt (blocked at the key sheet). On the iOS simulator no prompt is involved and the connection
reached the host; the simulator can reach the VM (no errno).

## Defect 1 — macOS crash presenting "Add SSH Key" from the server form (High)

**Reproduction (deterministic, 5/5 runs):** Add Host → Add a service → SSH → Connect → in glas.sh's
`AddServerView` sheet set Method = SSH Key → click **Add SSH Key** (`ServerFormViews.swift:427`
`.sheet(isPresented: $showingAddSSHKey) { AddSSHKeyView() }`, a sheet presented from inside a sheet)
→ any accessibility resolution of the app afterwards crashes it: `EXC_BAD_ACCESS` on the main
thread, `CoreFoundation ___CFBasicHashFindBucket_Linear ← CFDictionaryGetValue ← AppKit
_accessibilityFindRoleFromProtocol ← NSAccessibilityGetObjectValueForAttribute ← SwiftUI
PlatformAccessibilityElementProtocol.valueForAttribute ← AccessibilityNode.resolvedRole(forPlatformElement:)
← labelExposedAs ← labelsToResolve ← AccessibilityNode.accessibilityLabel()` — a label-resolution
cycle through the platform element, as the coordinator read it. No frames from GlassShell,
GlassLayers or GlassTerminal.

**Correlation:** crash reports `~/Library/Logs/DiagnosticReports/GlassPowerTools-2026-09-10-18{04,15,18,22,44}*.ips`
each land at the runner's "Requesting snapshot of accessibility hierarchy" step (+44.6–44.9 s after
test start) immediately after the "Add SSH Key" click; the test start times match
(e.g. 18:21:52 + 44.9 s = 18:22:37 → report 18:22:38; 18:43:50.9 + 44.6 s → 18:44:40). Between the
click and the snapshot, the sheet's "Key name" text field is never found for 10 s: the sheet's
accessibility subtree is already broken, not merely slow.

**What is sound:** a full snapshot with the server form open and no key sheet succeeds (probe A:
`snapshot OK, children=3`). The same `AddSSHKeyView` from Settings could not be compared because the
terminal's settings pages are not exposed (Defect 4). The view itself (`SettingsView.swift`
`AddSSHKeyView`: `Form` with `TextField("Key name").focused`, `SecureField`, `TextEditor` under a
`Section("Private Key")`, `.navigationTitle`, `.onAppear { isNameFocused = true }`) is byte-identical
to glas.sh, so glas.sh on macOS 27 with an accessibility client attached most likely crashes the same
way; its UI suite does not exercise this path.

**Proposed avoidance (for W2/W3, one line of routing):** on macOS present `AddSSHKeyView` from the
server form as its own window (`openWindow`) or a `.popover`, never as a sheet on a sheet; keep the
sheet on iOS/visionOS where it works. Element-level bisection (which control's label cycles) could
not be completed: every post-click query, including an element screenshot, trips the crash.

## Defect 2 — post-trust reconnect fails: "This terminal session is no longer active" (High)

After **Trust and Connect**, `TerminalConnectFlow.retryPendingConnection()`
(`TerminalConnectFlow.swift:706`) calls `sessionManager.reconnect(session)`, which throws
`SessionOpenError.sessionNotRegistered` from `origin(for:)` (`SessionManager.swift:343-352`,
message at `:885`) because the session is no longer in `sessions`. So between staging the trust
challenge (`stageHostKeyChallenge`, `:533-541`, called from the launch failure path at `:686`) and
the retry, the session was removed — the connect-failure path `removeSession(...)`
(`SessionManager.swift:587-599`) runs for the trust-challenge error on the engine path, whereas
glas.sh kept a challenged session registered until the user decided. Also observed: the shell
stamped `Last connected` (`GlassShellModel.swift:377`) when the capability opened, before any
session succeeded; F3's rule was "only when a real capability opens", which this satisfies, but the
user now sees "Last connected 47 sec" for a connection that failed. Suggest stamping on the
capability's success callback instead.

## Defect 3 — `lastConnected` semantics (Low)

See above; `GlassShellModel.swift:377`.

## Defect 4 — terminal settings pages not exposed (Medium)

On HEAD `9f58a61` the settings picker on macOS shows only General | Appearance | Privacy | About
(`settings-sections` radio labels), although `GlassTerminalSettingsPages.all` declares
Connections / Terminal / Snippets and `GlassShellSettingsView.swift:39` reads
`model.registry.settingsPages`. Either the terminal capability's `settingsPages` is empty at that
point or registration happens after the view is built. Not proven which; observed under
`--ui-testing` isolation. This also removes the only single-level path to Add SSH Key on macOS.

## Test written

`UITests/GlassTerminalUITests.swift` — `testConnectsToRealHostThroughTheShell`, gated on
`GPT_SSH_TEST_HOST` / `_USER` / `_KEY_PATH` (pass as `TEST_RUNNER_GPT_SSH_TEST_*` to `xcodebuild
test`); skips with a reason otherwise. Drives add host → add SSH service → form (per-platform field
entry, Method picker, Add SSH Key with the key pasted via the pasteboard) → save → connect → trust
prompt → waits for a Connected state → `echo` round trip (recorded as a limit if SwiftTerm's buffer
is not exposed to accessibility). On macOS it stops with `XCTSkip` and evidence when the key sheet
does not expose its field, because a failure there makes XCTest request the full snapshot that
crashes the app. Screenshots are element screenshots (sheet or window) — a whole-display capture on
this two-display Mac included other applications' windows; those captures were deleted, none kept.

## Screenshots kept (session scratchpad `shots/`, app-only)

`ios-terminal-01-library`, `02-server-form`, `03-add-key-sheet`, `04-server-form-filled`,
`05-trust-prompt` (the VM's fingerprint), `06-terminal-not-live` (the failure alert).
macOS: none kept — the only clean capture was the server form (`Import Connection`), and it was
purged with the display captures; re-capturable with the fixed `snap()`.

## Findings for other workers

- W2/W3: Defects 1, 2, 4 above; the legacy-algorithms warning text is present (audit item closed).
- Shell (consolidation): the row now combines its children into one element, so `host-service-ssh`
  is not individually addressable on macOS; tests use `host-service-connect-ssh` on the detail.
- Test infrastructure: `app.popUpButtons.firstMatch` on macOS can match the Touch Bar's
  "emoji & symbols" pop-up — always use a predicate.

## Not run

Terminal I/O, resize, SFTP, port forwarding, workgroups, Mac workspace — all downstream of Defect 2
(iOS) and Defect 1 (macOS). Physical devices not attempted (out of this brief).
