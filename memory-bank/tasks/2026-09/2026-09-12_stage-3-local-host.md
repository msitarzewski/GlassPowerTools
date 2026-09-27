# Stage 3 W-local — the built-in local host, "This Mac"

Owner `/root`. 2026-09-12. Implements **D8** from the
[Stage 3 plan](2026-09-12_stage-3-database-plan.md). **Status: built, unit-tested and verified in
the running macOS app.** Not committed at time of writing.

## What it is

A host row that is the device itself. It takes services like any other machine and differs in the
four ways D8 names, each of which follows from its being *this* device rather than one to reach.

| | The device's own host | A machine you reach |
|---|---|---|
| Address | none, never asked for; services commit against `127.0.0.1` or a file path | required before any service |
| Record | this app's own file, `GlassHostCatalog/local-host.json` | the App Group's `hosts.json` |
| Grouping | never; it does not enter `GlassShellHostGrouping` | by name, alias or address |
| Tunnel | never | borrows its own `.ssh` service (D7) |
| Connect-the-machine | not offered; the row is the service picker alone | play opens every service |
| Delete | refused; services are removed one at a time | deletes every member record |

## How it is stored, and why that way

`GlassLocalHost` (`Sources/GlassShell/GlassShellLocalHost.swift:19`) holds a fixed `HostID`
(`4c4f4341-4c00-…-0001`, "LOCAL"), the loopback address its services use, and the device's name.

The record is kept in **a second `HostCatalogStore` pointed at this app's private storage**
(`GlassShellModel.swift:106`), not in the App Group file. That reuses the kit's locking,
validation, `pair`/`unpair` and tombstone rules wholesale rather than inventing a parallel store,
and it is what "never published" means in practice: a record named "This Mac" with a `Local Shell`
service would otherwise appear in glas.sh, glassdb and glassDT, which cannot open it.

`loadLocalHost()` (`GlassShellModel.swift:228`) reads or creates the record after grouping and
inserts the host at the head of `hosts`. Never through `GlassShellHostGrouping`, so a discovered
machine that happens to share its name cannot swallow it — tested.

`GlassShellHost` gained `isLocal`, `builtInEndpointIDs`, `isBuiltIn(_:)`, `allowsConnectAll` and a
second initialiser (`GlassShellHost.swift:30,43,59`).

## Built-in services: the capability declares them, the shell stores nothing

Two new members on `GlassCapability`, both defaulted (`GlassCapability.swift:223,229`):

```swift
func builtInLocalServices() -> [HostServiceLink]   // default: none
var supportsLocalSetup: Bool { get }               // default: true
```

`builtInLocalServices()` returns links with **constant** endpoint ids — nothing is written for
them, and the constant is how the capability recognises the service again in `open`. The terminal
returns the Mac's `Local Shell` (`GlassTerminalCapability.swift:236,241`) and nothing on the other
platforms. A built-in service appears on the host, connects, and has no Edit and no Remove: there
is no stored configuration to open or delete, and both surfaces say so rather than reporting the
service as broken (`GlassShellModel.swift` `builtInServiceNotEditable`, `GlassShellLibraryView.swift:297`).

`supportsLocalSetup` defaults to **true** because the user answered that every kind belongs on This
Mac, so a capability opts out rather than in. The terminal opts out
(`GlassTerminalCapability.swift:252`): its local service is the built-in shell, and glas.sh's
workgroups already hold a saved shell, directory and layout, so a second configurable way to make
one would only be a worse one. **`GlassDatabase` was not edited and gets local setup for free.**

## The pattern: a capability is asked for, never inferred from a service

Both defects in this section are one mistake made twice — **inferring a capability from the presence
of a service instead of asking the broker that owns the answer.** `host.services.contains { $0.kind
== .ssh }` reads like "can this machine lend a forward?" and is not that question. It is "does this
machine have a Terminal service?", which was an adequate proxy only while every Terminal service
was a real SSH connection to somewhere else. The local host makes the two questions come apart, and
they will come apart again: a Terminal service whose credential is missing, a machine behind a jump
host that is unreachable, a capability that is not registered in this build.

`GlassShellModel.hostAccess(for:)` is the broker and `GlassCapabilityHostAccess.canForwardPorts` is
the answer. **Anything that needs to know whether a forward is possible asks that, including UI
that only means to describe it** — a row saying "tunnel available" when the tunnel will never be
used is a false statement about the product's behaviour, whether or not something later fails.

Recorded as a rule rather than two incidents, because the proxy is tempting every time: the
`HostProfile` is right there and the broker takes a hop to reach.

## The forward-broker exclusion — the trap D8 warned about, confirmed

`portForwardProvider(for:)` offered a forward whenever a host had **any** `.ssh` service. The local
host has one — the Mac's own shell — so the plain test says yes, and the database capability would
have tunnelled to loopback through loopback to reach a server already listening on it.
`GlassShellModel.swift:466` excludes it explicitly; `:480` does the same for D14's trust resolver,
so `resolveHostTrust()` cannot promise more than `forwardPort` can deliver. Both are covered by
`GlassShellPortForwardTests.theLocalHostNeverForwards`, which adds a real `.ssh` link to the local
host first so the test fails if the guard is removed.

**The setup sheet's own copy of that question is still wrong, and it was not mine to fix.**
`GlassDatabaseCapability.hostCanForwardPorts(_:)` (`Sources/GlassDatabase/GlassDatabaseCapability.swift:206`)
asks `host.services.contains { $0.kind == .ssh }` directly, so on the local host the Advanced
tunnel row will read as available when it is not. Nothing fails — at connect time
`hostAccess.canForwardPorts` is false, `openForward` stays nil and the session connects straight to
`127.0.0.1` — but the row implies a tunnel that is never used, which is the lie the rule above
exists to prevent. **One line:**

```swift
hostCanForwardPorts: runtime.hostAccess.map { $0(host).canForwardPorts }
```

which asks the shell (the authority) instead of guessing, and is the same answer everywhere else.
The call site in `setupDraft(for:host:)` already holds `runtime.hostAccess` for D14's trust
resolver, so nothing new has to be plumbed. Reported rather than
edited because `Sources/GlassDatabase` was W-capability's; **the coordinator took the change on
2026-09-12** after W-capability stood down.

## connectAll: the recommendation, and why

**Recommendation: the local host's row offers the service picker alone — no play glyph.** Built and
shipped that way (`GlassShellModel.connectAll` at `:644` refuses; `GlassShellLibraryView.swift:472`
draws `pickerOnlyControl`).

The reasoning, since the coordinator asked for it rather than a coin flip:

- `connectAll` exists for a real act: *"the machine has three services, I want the machine."*
  Opening a box's terminal, its database and its desktop together is one intention.
- The device is already here. There is no "connect to this machine", and its services are not
  facets of one thing — they are a shell, a SQLite file, a local MySQL, and in Stage 4 a VM. They
  are picked **by name**, which is exactly what the chevron menu already does.
- The failure mode is asymmetric. On a remote host a stray connectAll costs a few sessions to one
  box. Here it opens a terminal window, a database workspace per database and a VM console at
  once, on the display you are looking at. It is the one row where the mis-click is expensive.
- It costs nothing in discoverability. The chevron is already its own hit region on every platform
  and already lists the services by name, so removing the play half removes an action nobody wants
  and leaves the one they do.

With exactly one service the row is still a plain play button — "all of them" and "this one" are
the same act — and it connects that service by name rather than routing through `connectAll`.

## Several services of one kind — what the check turned up

The catalog always allowed it; the shell had never been driven that way. Three terminals and two
databases on one host, plus the local host's shell and two databases, found **one real defect**:

**Accessibility identifiers collided.** `host-service-connect-<kind>`, `-edit-`, `-more-` and
`host-connect-menu-<kind>` are per-kind, so three terminals produced three identical identifiers
and UI automation matched an arbitrary one. Fixed at `GlassShellLibraryView.swift:339`: the first
service of a kind keeps the bare identifier every existing surface and test already uses, the
second and later carry their 1-based position within the kind (`…-ssh-2`, `…-ssh-3`).

Everything else held up and is now asserted rather than assumed: the row's icons are one per kind
(`serviceKinds` already deduplicates), the subtitle counts rather than lists, `connectAll` opens
every service in host order and hands each capability *its own* service, and each detail row keeps
its own Connect/Edit. Verified in the running app: see `mac-35-local-host-several-services`.

## What "This Mac" is on iPhone, iPad and Vision Pro

**It is there, it is real, and it is emptier.** The row appears on every platform under the
device's own name (`GlassLocalHost.displayName`: "This Mac", "This iPhone", "This iPad", "This
Apple Vision Pro").

- **Terminal: nothing.** There is no local shell off the Mac — no login shell to spawn, no PTY — so
  `builtInLocalServices()` returns an empty array rather than a row that would do nothing when
  pressed. This is the honest half of the answer.
- **Database: real.** SQLite is a file the user picks, and `DatabaseServiceDraft` requires no
  address for it (`Sources/GlassDatabase/DatabaseServiceDraft.swift:155-163`), so "This iPhone"
  holding SQLite databases works exactly as it does on the Mac. A local MySQL or PostgreSQL can
  also be added; nothing will be listening on an iPhone, and it will fail honestly if tried.
- **Desktop:** Stage 4, containers and VMs, macOS only in practice.
- So on a fresh iPhone install the row exists with **no services** and says "No services yet. Add a
  database on this device — a SQLite file, or a server running here." That is not a dead row: it is
  the only place a SQLite file can live, and "Add a service…" leads straight to it.

## What the plan got wrong, and other findings

1. **The plan lists Files as a service kind on the local host.** It is not one. `Files` is a
   `GlassServiceTool` riding a Terminal service's SSH session (`GlassTerminalCapability.swift`
   `serviceTools`), and the SFTP browser needs a live `SSHSession`. There is no local-filesystem
   browser anywhere in the tree. **Not shipped**, deliberately, rather than shipping a Files row
   that opens nothing. Closing it means a local backend for `SFTPBrowserView` or a new browser —
   a real piece of work, recorded below.
2. **`load()` can run twice concurrently, and the existing UI-test seeder was not safe against it.**
   `GlassShellLibraryView.swift:67-68` starts one `load()` from `.task` and another from the
   scene-phase observer. Both seeders checked "is it empty?" *after* an await, so both could pass:
   the first run of the new local-services seeder produced **four** database rows instead of two —
   visible in a screenshot, not in a unit test. Both seeders now claim a one-shot flag
   synchronously before their first await (`GlassShellModel.swift:693`). The pre-existing
   `--ui-testing-seed-hosts` had the same latent defect and is fixed with it.
3. **`GlassShellHost.member(owning:)` could not answer for a built-in service**, since there is no
   stored link. Added `record(owning:)` (`GlassShellHost.swift:51`), which falls back to the local
   record for a built-in and to nothing otherwise — used by the connect path and both detail hooks.
4. **Opening a window is not a session.** `GlassTerminalCapability` could have reported `.connected`
   the moment it asked for a local terminal, which would stamp "last connected" on a shell that may
   have failed to launch. Instead the outcome is queued (`:120`) and answered by the pane that
   actually starts the process, or by its `launchError`
   (`Sources/GlassTerminal/macOS/MacLocalTerminalPaneView.swift:497`). Each click queues another,
   answered in order; a pane nobody asked for reports to nobody.
5. **`model.hosts` now includes the device**, so twenty-odd existing assertions about the shared
   catalog were changed to `model.catalogHosts` / `catalogItems` (`GlassShellModel.swift:263`).
   Settings' "Catalog records" diagnostic counts against `catalogHosts` for the same reason, or it
   would differ by one on every launch.

## Files changed

| File | What |
|---|---|
| `Sources/GlassShell/GlassShellLocalHost.swift` | **new** — the local host's identity, address, store path and per-platform name |
| `Sources/GlassShell/GlassShellHost.swift` | `isLocal`, `builtInEndpointIDs`, `isBuiltIn`, `allowsConnectAll`, `record(owning:)`, the local initialiser |
| `Sources/GlassShell/GlassCapability.swift` | `builtInLocalServices()`, `supportsLocalSetup`, and the registry's aggregation of both |
| `Sources/GlassShell/GlassShellModel.swift` | the local store, `loadLocalHost`, mutation routing, three new errors, the forward and trust exclusions, the `connectAll` guard, `catalogHosts`, the local-services UI-test seeder, both seeders made one-shot |
| `Sources/GlassShell/GlassShellSetup.swift` | `isLocalHost`, the address-gate exemption, `setupKinds(for:registry:)`, loopback as the committed address, no delete section |
| `Sources/GlassShell/GlassShellLibraryView.swift` | the picker-only control, per-service identifier suffixes, built-in rows without Edit or Remove, the local host's address and empty-state wording, `addableKind(for:)` |
| `Sources/GlassShell/GlassShellSettingsView.swift` | the local host's own status line, and the corrected record-count diagnostic |
| `Sources/GlassTerminal/GlassTerminalCapability.swift` | `localShellEndpointID`, `builtInLocalServices()`, `supportsLocalSetup`, `openLocalShell`, the outcome queue |
| `Sources/GlassTerminal/macOS/MacLocalTerminalPaneView.swift` | reports the shell's real outcome once per pane |
| `Tests/GlassShellTests/GlassShellLocalHostTests.swift` | **new** — 13 tests |
| `Tests/GlassShellTests/GlassShellPortForwardTests.swift` | the local-host case, where D8 asked for it |
| `Tests/GlassTerminalTests/GlassTerminalLocalShellTests.swift` | **new** — 5 tests |
| `UITests/GlassShellLocalHostUITests.swift` | **new** — 4 tests |
| `Tests/GlassShellTests/*` (5 files) | `model.hosts` → `catalogHosts`, `items` → `catalogItems` |

`Sources/GlassDatabase`, `Sources/GlassDBKit`, and the three source applications: **untouched.**

## Verification

| Check | Outcome |
|---|---|
| `swift test --build-system native` | **592 passed, 0 failed**, 45 suites. Was 568 before this work; +24 (13 local host, 5 local shell, 1 forward exclusion, and 5 files' assertions retargeted) |
| `xcodebuild -scheme GlassPowerTools -destination generic/platform=macOS` | **BUILD SUCCEEDED** |
| `… generic/platform=iOS` | **BUILD SUCCEEDED** |
| `… generic/platform=visionOS` | **BUILD SUCCEEDED** |
| `xcodebuild test -only-testing:GlassPowerToolsUITests/GlassShellLocalHostUITests` (macOS) | **4 of 4 passed.** The row exists on a first launch with nothing seeded; the detail says "This device"; `Local Shell` is a service with Connect and no Edit; the edit sheet offers no Delete; two seeded databases give the picker-only control and distinct per-row identifiers |
| Full macOS UI suite, `-only-testing:GlassPowerToolsUITests` | **17 tests: 15 passed, 2 failed.** Both failures examined rather than assumed: (a) `GlassShellTagFieldUITests.testCollectionsAreChipsAndFeedTheSystemWideVocabulary` — "the Clients collection appears in the sidebar"; the same failure W-capability already isolated to the in-flight tag vocabulary work and reproduced with this work absent. (b) `GlassShellLibraryUITests.testAddHostWithTerminalInOneSheetThenConnect` — **not an assertion failure**: `UITests/GlassShellLibraryUITests.swift:113`, "Failed to synthesize event: Timed out while synthesizing event", in the shared `addHost` helper that three tests in the same run used successfully. Re-run alone: **passed (78.1 s)**. A second Glass Power Tools instance from another worker's run was on the machine, and synthesized clicks go to the frontmost app — the suite's own comment at `:42` records exactly that hazard |
| Real device install | **not run.** iOS and visionOS were compiled, not launched: what "This iPhone" looks like in the running app is a build result, not a device result |
| Live local MySQL / PostgreSQL on the Mac | **not run.** No local server is installed; the live database work is W-capability's against `192.0.2.6` |

Screenshots, taken from the passing macOS run (project rule 11, own window only):
`mac-30-local-host-row`, `mac-31-local-host-detail`, `mac-32-local-host-services`,
`mac-33-local-host-edit-sheet`, `mac-34-local-host-picker-only`,
`mac-35-local-host-several-services`.

## Remaining work

1. **Files on the local host is not shipped.** It needs a local backend for the SFTP browser, or a
   new local-filesystem browser. The user already found it an odd fit; it is the one part of D8's
   table that is absent, and it is absent visibly rather than as a row that does nothing.
2. **`GlassDatabaseCapability.hostCanForwardPorts`** — the one-line change above, for W-capability.
3. **Stage 4's desktop capability inherits local setup** from the `supportsLocalSetup` default, so
   containers and VMs on localhost need no shell change — only a capability that returns a draft.
4. **The local host's name is fixed per platform.** Rename is supported and persisted
   (`updateHost` routes to the local store), but there is no UI reason to rename it yet.
5. **iOS and visionOS are compile-verified only.** The UI suite's local-host tests are written to
   run on all three (they assert "No services yet" off macOS); they have not been run there.
