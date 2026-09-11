# Host-level address (IP / DNS on the host, not per service) — W6, 2026-09-11

User requirement: "add the machine ID (IP, DNS) to the connection itself, and remove it from the
different services … Connection > Terminal > IP address is weird." Built as first-class model +
protocol work; nothing committed (coordinator commits; the kit stays uncommitted).

## Design (as implemented)

- **Kit model.** `HostProfile.address: String?` — optional on the wire, schema version stays 1, key
  absent (not null) when unset, so the three source apps' keyed decoders ignore it. Normalised
  (trim, IPv6 brackets stripped, lowercased) and validated: DNS labels / IPv4 / IPv6 with optional
  zone; no user, port or spaces (`HostProfileError.invalidAddress`). A malformed address from
  another writer is dropped on decode rather than making the catalog unreadable. `address` is part
  of equality, so changing it is a revision. `HostCatalogStore.applyPublication` preserves it.
- **Shell.** `GlassShellHost.address` (canonical member first, else the first member with one) and
  `addresses` (every distinct one; a disagreement is shown in the detail and settled by one edit).
  Grouping now also joins records that carry the same address (loopback excluded), through the
  existing alias index. Host editor: "Address" field under Name. Detail: Address row
  (`host-detail-address`). `GlassShellModel.addHost/updateHost(address:)`,
  `setHostAddress(_:for:)`; every member record gets the same address.
- **Capability protocol.** `GlassCapabilityHostAccess { address, setAddress }` handed to
  `open(service:host:hostAccess:report:)` (default forwards to the old `open`), and
  `hostAddressDidChange(host:address:)` (default no-op) called for each member record that has a
  service of the capability's kind, only when the address actually changed.
- **Terminal.** The setup form (`AddServerView` via `SetupRequest.formContext`) and Edit from the
  host detail (`requestEditServer(id:host:)`) receive a `ServerFormHostContext`: with an address the
  form shows it read-only ("From the host …", identifier `add-server-host` keeps its value) and no
  Host field; without one the Host field is the single place it is typed and, on save,
  `setAddress` records it on the host. `GlassTerminalHostAddressSync` updates every saved server
  that is one of the record's SSH services when the shell reports a new address (a cleared address
  changes nothing). The "Set Up…" action and the Tailscale edit path pass no access and keep the
  old behaviour (address still pre-filled from the record).
- **Seed syntax.** `--ui-testing-seed-hosts "scratch@192.0.2.6:ssh"` (old form still valid).

Assumption: ports, usernames and credentials remain per service (they differ across services).

## Changed files

Kit: `Sources/GlassConnectionKit/HostProfile.swift`, `Sources/GlassHostCatalog/HostCatalogStore.swift`
(one line), new `Tests/GlassConnectionKitTests/HostProfileAddressTests.swift`.
Shell: `GlassCapability.swift`, `GlassShellHost.swift`, `GlassShellModel.swift`,
`GlassShellEditors.swift`, `GlassShellLibraryView.swift`; new
`Tests/GlassShellTests/GlassShellHostAddressTests.swift`.
Terminal: `GlassTerminalCapability.swift`, `TerminalConnectFlow.swift`, `ServerFormViews.swift`,
one-token edits in `GlassTerminalLibraryEntries.swift` (Edit passes the host) and
`TerminalTailscaleView.swift` (enum case gained a label); new
`Tests/GlassTerminalTests/HostAddressSyncTests.swift`.
UI tests: `UITests/GlassTerminalUITests.swift` (host typed once on the host; the server form's
address asserted read-only).

## Coordinator additions (detail layout, same files)

- Services row: icon + name/kind stacked, Connect + capability actions trailing with layout
  priority; `ViewThatFits` drops the actions under the name when the column is narrow.
- Results row subtitle: up to two kinds named, three or more counted ("3 services") — the shared
  row middle-truncates; a kit-side tail truncation would be the fuller fix (kit UI files not
  touched by W6).
- "Connect opens": kind first, endpoint name only when it adds something
  (`GlassShellLibraryView.connectOpensText`, unit-tested).

## Verification

(filled in below as runs complete)

| Check | Result |
|---|---|
| Kit `swift test` (`../GlassConnectionKit`) | **passed: 53 tests** (17 + 13 + 23 across the three test targets) incl. `HostProfileAddressTests` |
| Whole package `swift test --build-system native` (scratch path `build-w6`) | **passed: 469 tests / 28 suites**, twice (after the address work; after the form-title fix) |
| App builds macOS (Release, coordinator's job) / iOS Simulator / visionOS Simulator | **passed** (iPhone 17 Pro Max, Apple Vision Pro; `xcodebuild` exit 0 each) |
| iPhone 17 Pro Max UI: `GlassShellLibraryUITests` 5, `GlassShellTagFieldUITests` 1, `GlassTerminalUITests` 2 | **7 passed, 1 failed.** The address flow itself passed end to end: host typed once with `192.0.2.6`, service added, Connect → server form titled for the host with the address **read-only** ("192.0.2.6 / From the host scratch", no Host field — `shots-w6-ios/ios-terminal-02-server-form.png`, judged by eye), key added, saved, Connect issued. The failure is at the network: `Connection to 192.0.2.6:22 timed out` — the VM is unreachable from this Mac right now (`nc -vz 192.0.2.6 22` → "Operation timed out"; it answered earlier in the evening). Not a code defect; rerun when the VM is up. |
| macOS UI suites (library, tag field, terminal with real host) | **not run — blocked:** every macOS XCUITest launch, even `LaunchSmokeUITests` alone, fails with "The test runner failed to initialize for UI testing (Timed out while enabling automation mode)". Screen is not locked (`IOConsoleLocked` false); no other xcodebuild/runner was alive; `testmanagerd` (root) cannot be restarted without sudo. Retried three more times (after the iPhone run ended, and again with no other `xcodebuild` alive): same error every time (`smoke-w6.log`, `smoke-w6b.log`, `smoke-w6c.log`). Something on this Mac's automation session needs a person: the runner cannot enable automation mode — typically a stale `testmanagerd` (root, needs `sudo launchctl kickstart -k system/com.apple.testmanagerd`) or a lost Accessibility/Automation grant for Xcode-beta's runner after the earlier session's terminal restart. |
| macOS element screenshots (host editor with Address; server form from a host) | **not captured** — same blocker. The iPhone captures cover the same views. |
| visionOS UI run | not run (not in the brief beyond the build). |

Follow-ups: the form title from the shell now reads "Add Terminal to <host>" (it read "Import
Connection", the Tailscale draft's word, in the first iPhone capture — fixed after that run, unit
suite green, not re-captured). Kit-side tail truncation for the results-row subtitle remains a
kit follow-up (kit UI files untouched).
