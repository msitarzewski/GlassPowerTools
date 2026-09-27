# Service setup never asks for an address; Add SSH Key window — W7, 2026-09-11

Worker W7. Requirement (user, paraphrased): the Terminal/SSH connection setup should have no host
field; the address is defined at the machine level and inherited by each connection type. The
Add SSH Key window also needed layout attention. Not committed (coordinator).

## Changed files

| File | Change |
|---|---|
| `Sources/GlassShell/GlassCapability.swift` | `GlassCapabilityHostAccess` is read-only (`address` only; `setAddress` removed). New protocol hooks with defaults: `needsSetup(service:host:)` (false) and `knownAddress(service:host:)` (nil). New `GlassShellAddressRequest`. |
| `Sources/GlassShell/GlassShellModel.swift` | `addressRequest` state. `connect(hostID:endpointID:)` gates a setup on the host's address: adopts a capability's saved address when exactly one is known, else raises the address request and returns; resumes after the prompt saves. `knownAddress(for:)`, `adoptKnownAddresses()` after every `load()` (hosts that predate addresses take the address their saved services already carry; disagreements are left to the user). |
| `Sources/GlassShell/GlassShellEditors.swift` | New `GlassShellAddressPrompt` ("Address for <host>"; ids `host-address-prompt-field/-continue/-cancel`). |
| `Sources/GlassShell/GlassShellLibraryView.swift` | Presents the prompt; detail's unset address row is a "Set Address…" button (`host-detail-set-address`). Services row: one line, name truncates first; when the actions do not fit they collapse into an overflow menu beside Connect (`host-service-more-<kind>`), so nothing clips. |
| `Sources/GlassTerminal/GlassTerminalCapability.swift` | `needsSetup` (no saved server) and `knownAddress` (the saved server's host). `SetupRequest.formContext` is optional; the setup sheet shows `GlassTerminalSetupNeedsAddressView` when no address is known (only reachable from the terminal's own "Set Up…" on a host record that predates addresses). Edit from the shell passes `host.address ?? server.host`. |
| `Sources/GlassTerminal/ServerFormViews.swift` | `ServerFormHostContext { hostName, address }` (address required). From the shell the form shows the address read-only ("From the host …") and has no Host field; the write-back path (`recordAddressOnHostIfNew`) is gone. Standalone glas.sh form keeps "Host". Titles: "Add Terminal to <host>" / "Edit Terminal on <host>". |
| `Sources/GlassTerminal/SettingsView.swift` | `AddSSHKeyView` rebuilt as the server form's pattern (per the user's HIG direction): `NavigationStack` + grouped `Form` + title + cancellation/confirmation toolbar items, which a macOS sheet renders as the title header and the bottom Cancel / Save bar. Sections: Key (name, passphrase); Private Key with Choose File… first (prominent), a bounded monospaced editor (132–176 pt, scrolls), detection footer. Save is the default action on macOS. Identifiers unchanged. |
| `Sources/GlassTerminal/GlassTerminalScenes.swift` | The `Window("Add SSH Key")` scene is removed: the key form is a **sheet on every platform**, nested over the server form (W4 traced the earlier macOS crash to the SSH Key row's accessibility label, not to sheet nesting). While it existed it was also observed restoring itself at launch. |
| `Sources/GlassTerminal/ServerFormViews.swift` (cont.) | "Add SSH Key" presents the sheet on macOS too; `openWindow` dependency dropped. |
| `Tests/GlassShellTests/GlassShellHostAddressTests.swift` | Write-back test replaced by: setup waits for the host address then resumes; with address straight to setup and saved service connects without a prompt; known address adopted on load and on connect, disagreement left alone; request without connect. |
| `UITests/GlassTerminalUITests.swift` | `addHost(named:address:)` address optional; new `testAddressIsCollectedOnTheHostBeforeTerminalSetup` (bare host → Connect → prompt → form read-only, titled for the host, no text field, detail shows the address). `snap` captures the main window (sheets ride on it) now that no key window exists. |

Not in my ownership, noted: `GlassTerminalLibraryEntries.swift`'s "Set Up…" action opens the
setup directly (bypassing the shell's gate); on a host record without an address it now lands on
the needs-address view instead of a form. The shell's per-service Connect is the gated path.

## Verification

| Check | Result |
|---|---|
| `swift test --build-system native` (whole package, scratch path `build-w7`) | **passed: 472 tests / 28 suites** (`scratchpad/w7-swift-test-1.log`); shell suite alone 41/8 |
| macOS build (test host + Release) | passed |
| macOS UI, all suites, real host env (`results-mac-w7.xcresult`) | **11 passed / 1 failed** on first run: library 5/5, tag field 1/1, smoke 1/1, terminal chrome, settings pages, and **`testConnectsToRealHostThroughTheShell` passed (94 s)** — the Local Network grant is in place, live shell reached on the Mac. The new `testAddressIsCollectedOnTheHostBeforeTerminalSetup` failed once: an identifier on the `LabeledContent` hid the Set Address… button from the tree on macOS; identifier moved to the button, **re-run passed** (`results-mac-w7b.xcresult`) |
| Screenshots (own window only) | `scratchpad/shots-w7/mac-address-prompt.png` ("Address for bare", footer, Cancel/Continue); `mac-server-form-readonly-address.png` ("Add Terminal to bare", Address 10.9.8.7 · From the host bare, no field); `mac-add-ssh-key-window.png` (Key section, Choose File… prominent, bounded editor, detection footer); `mac-detail-services-row.png` (chrome host at default width: one line, Connect + Set Up…) — the five-action row at the 900-pt minimum is checked on the Release build below |
| iPhone 17 Pro Max UI, all suites, real host env (`results-ios-w7.xcresult`, then `results-ios-w7b.xcresult`) | First run 6 passed / 2 failed — both failures were mine: I ran `pkill -x GlassPowerTools` to quit a Release build while the simulator's app (same process name) was under test, which killed it mid-`testSearchFiltersRows` and before `testConnectsToRealHostThroughTheShell` could screenshot. **Re-run of those two: both passed** (search 33 s; real host 196 s, live shell). Address-step test, tag field, settings pages, smoke, library ×4: passed |
| macOS terminal suite after the key form became a sheet (`results-mac-w7c.xcresult`) | real host **passed** (67 s, key added through the nested sheet), chrome passed, settings pages passed; `testAddressIsCollectedOnTheHostBeforeTerminalSetup` **failed once** at `addSSHService()` (the service editor did not appear within 10 s after "Add a service…") while the iPhone run was on the same machine; **alone it passed twice** (`results-mac-w7b`, `results-mac-w7d`, 29–30 s). Recorded as a timing flake under load; not masked |
| Whole package after every edit (`w7-swift-test-2.log`) | **472 / 28 passed** |
| Screenshots (own window only) | `shots-w7/mac-add-ssh-key-sheet-over-form.png` — the key form as a sheet over "Add Terminal to scratch": title header, Key / Private Key sections, Choose File… prominent, bounded editor, detection footer (the Cancel / Save bar sits below the crop because the sheet is taller than the 612-pt test window; the test pressed Save on it). `shots-w7/mac-detail-services-row-900.png` — Release build of this tree, user's real library, window resized to 900×612 by System Events: the terminal row shows Connect + an overflow menu (⋯), the desktop/database rows Connect only; nothing clips. Earlier `mac-add-ssh-key-window.png` shows the interim window layout (superseded). |

## Side effect to know about

Launching the Release build against the user's real library ran `adoptKnownAddresses()`: the
`alpha` host record in the shared catalog gained the address its saved terminal server already
carried (`198.51.100.6` as shown in the detail). That is the designed behaviour for hosts that
predate addresses, applied to real data by this verification.

## Remaining

- The `serviceRow` overflow menu carries the capability's actions as menu items; the
  capability's `Set Up…` / `SFTP` / `Edit` / `Details` / `Delete` buttons render as menu rows
  (verified visually only in the collapsed state's icon; the menu was not opened in a capture).
- `GlassTerminalLibraryEntries.swift` "Set Up…" (not mine) still opens the setup directly; on a
  host record without an address it now shows the needs-address view rather than a form.
- macOS accessibility recursion after the connection-failure alert (W4's open item) untouched.
