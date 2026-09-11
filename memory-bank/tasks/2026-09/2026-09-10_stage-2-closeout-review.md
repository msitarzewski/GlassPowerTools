# Stage 2 close-out review (read-only) — 2026-09-11

Reviewer agent, read-only, at `13fed7f`; recorded by the coordinator. No files edited, no builds run
by the reviewer. Follow-up cleanup items are queued to W4 (owner of `Sources/GlassTerminal`).

## 1. Parity: every glas.sh feature is reachable from the shell

Reachable with entry points cited by the reviewer: Connect → terminal with host-trust prompt
(`GlassTerminalCapability.swift:127-134`, `TerminalConnectFlow.swift:199-203`); SFTP browser
(per-service action `GlassTerminalLibraryEntries.swift:65`, palette, terminal window, iPhone
sheet); port forwards and SOCKS5 inside the terminal window (`TerminalWindowView.swift:1605`);
workgroups (toolbar item + ⌘⌥W + windows/sheets); snippets (settings page `terminal.snippets`);
Tailscale when configured; command palette; local Mac terminal (⌘N); recording default output-only;
key management with Choose File… (`SettingsView.swift:1626`, `SSHPrivateKeyImport.swift:47`).
Widget target is embedded for iOS/visionOS and reads the same App Group key the app writes;
**not yet proven on a device.** iCloud settings sync is wired (`SettingsManager.swift:1245-1298`).
Settings pages: Connections / Terminal / Snippets; glas.sh's Appearance tab is replaced by the
shell's layer controls by design (D2).

Not regressions, but vestigial: the standalone `port-forwarding` window has no opener here or in
glas.sh; deep-link parsing remains although no URL scheme is declared (D4).

## 2. TODO / stub scan

No `TODO`, `FIXME`, `fatalError`, `try!` or `as!` in the created code. Remaining hits are
honest, user-visible limits or legitimate gates: `.agent` credentials throw "unavailable in this
release" (same as glas.sh); ECDSA P-384/P-521 not supported for auth and gated in the import form;
"Folder drops are not supported yet" in the SFTP browser (inherited); `GlassShellPlaceholderSession`
for kinds without a capability (Stage 3/4 contract, UI-tested); env-gated skips in the UI tests.
One blocker-class skip: the macOS `XCTSkip` at `UITests/GlassTerminalUITests.swift:230` masks the
sheet-on-sheet crash — W4 removes it with the fix. One no-op shim:
`SSHConnection.swift:425 resetKeepAliveCounter()`.

## 3. Security spot-check

Engine changes since its review commit (`SSHPublicKeys.swift` header-only key-type detection) are
clean. Terminal side: prepared credentials cross to the engine as key material, never `String`
secrets; the trust decider always rejects and pins only from the alert in `.ask` mode; no logging
line interpolates secret-named values; SFTP local writes are guarded by the browser's own
`isSafeBasename` at nine sites; Tailscale secrets stay in the Keychain; the widget reads only the
`servers` blob, which carries no password field.

**Should-fix:** `SSHPrivateKeyImport.swift:47-55` reads the whole chosen file before the 64 KiB
check — check the file-size resource value first. **Obligation for Stage 5:** the editor's SFTP
consumer must use the engine's `SFTPEntry.hasSafeName`.

## 4. Dead code in `Sources/GlassTerminal`

| Item | Action |
|---|---|
| `ConnectionLibrary.swift`: `ConnectionLibraryMode`, `ConnectionLibraryCollection` unused; `Scope`/`MacColumnLayout` test-only; only `ConnectionLibraryProjection` is live | trim |
| `glas_shApp.swift:98,151-153` `IOSAppRouter.showsSettings`/`showSettings()` never read | delete |
| `glas_shApp.swift:212,302-321` deep-link handling with no URL scheme (D4) | delete |
| `SSHConnection.swift:425` no-op `resetKeepAliveCounter` | delete with call sites |
| `GlassTerminalScenes.swift:69,141` `port-forwarding` window, no opener | delete (forwards live in the terminal window) |
| `WindowRecoveryManager.swift` is now a typealias plus `TerminalSessionOverride` | rename file |

## Status

Findings queued to W4 as a second phase after defects 1–5. Widget-on-device and live sync remain
on the Stage 2 verification list.
