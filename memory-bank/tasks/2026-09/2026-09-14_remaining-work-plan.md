# The remaining work, planned

Owner: coordinating agent. 2026-09-14. **Status: PLAN. Nothing built from this note yet.**

Authorization: the user asked for a thorough plan for the remainder of the work, stressing that
reuse is essential in a professional, public codebase and that edits must be precise. D26 itself is
already **Approved** ([decisions](../../decisions.md#d26)); this note plans its execution and
everything queued behind it.

## How this plan is written

Three constraints the user set, applied to every item below rather than stated once:

- **Reuse is the first move, not the fallback.** Each stage names the *existing* implementation it
  extends and the line it extends at. Where a stage creates something, it says what was searched for
  and not found — per rule 24, a negative claim has to show where it looked.
- **Precise edits.** Named call sites, not "update the storage layer". No bulk regex: the
  2026-09-13 rename crossed unbalanced quotes and rewrote 105 occurrences across 64 files.
- **Public codebase.** Provenance comments, licence chain and `THIRD-PARTY-NOTICES.md` stay intact;
  nothing is deleted on a grep alone (rule 24 again), and every deletion here names its replacement.

**The magic directive** — familiar to a Mac user, but with the feel of visionOS to use (2026-09-13), with
visionOS leading the design — binds one item in this plan above all: the **key manager** (D26 stage
4) is a new surface, and new surfaces get designed on the headset's terms and adapted down, not
drawn as a Mac panel and ported. It also binds Stage 4 W5.

## Measured state, 2026-09-14

Tree clean at `57bca0b`. **1153 tests / 117 suites**, plus RDPKit's 1014 in its own package. Three
platforms build. Installed **0.4.92 (95)** on Mac, iPhone and Vision Pro. No path dependency leaves
this repository, so nothing in this plan is a cross-repo change.

---

# Part 1 — D26: the store and sync rebuild

## What is already built, and must not be rebuilt

Measured in the tree today, not remembered:

| Piece | Where | State |
|---|---|---|
| `configuration: Data?` on the service link | `Sources/GlassConnectionKit/HostProfile.swift:37` | **Done.** Optional, so an older record decodes |
| The narrow protocol capabilities see | `Sources/GlassShell/GlassServiceStore.swift` | **Done**, with typed `Decodable`/`Encodable` helpers and an in-memory double |
| The shell-side read/write | `GlassShellModel.swift:357-400` | **Done**, including the local-vs-cloud catalog split for D8's "This Mac" |
| Identity | `EndpointID.rawValue` **is** each capability's record UUID | **Already true** in all three: `GlassTerminalCapability.swift:198`, `GlassDatabaseCapability.swift:116`, `GlassDesktopCapability.swift:90` |

**The last row is the single most important fact in this plan.** There is no identity migration in
D26 — the three capabilities already key their records by the shell's endpoint id. Stage 1 relocates
bytes; it does not re-key anything.

## Stage 1 — connections into the catalog

**Objective.** A capability's configuration is read from and written to its service link. The three
separate stores are deleted.

### The reuse anchor, and why the three capabilities differ

The database already has the exact seam this needs:

```
struct ConnectionPersistenceStore { load: () -> Data?; save: (Data) throws -> Void; restore: (Data?) throws -> Void }
                                            — ConnectionManager.swift:31-54
```

Injectable, with a readback check and a rollback. **That shape is the target for all three.** The
other two are asymmetric today and the asymmetry is the actual work:

| Capability | Reads | Writes | Work |
|---|---|---|---|
| Database | `ConnectionPersistenceStore.live` | same | Repoint `.live` at the catalog. Smallest |
| Terminal | `defaults.object/data(forKey:)` **directly**, `ServerManager.swift:229-231` | injectable `serverDataWriter`, `ServerManager.swift:196-215` | Give reads the same seam writes already have, then repoint both |
| Desktop | `DesktopRepository` actor, file-backed | same | **Delete the file store entirely** |

### Precise edits

**Database** — `Sources/GlassDatabase/ConnectionManager.swift`

1. Add a catalog-backed `ConnectionPersistenceStore` alongside `.live`, taking a `GlassServiceStore`
   and a `HostServiceKind`. `load` becomes `configurations(ofKind: .database)` encoded as the same
   array; `save`/`restore` become per-endpoint `setConfiguration`.
2. `.live` is kept **only** until the composition root passes the catalog-backed one, then removed
   in the same stage. Two stores that both work is the state D26 exists to end.
3. `UserDefaultsKeys.connections` (`Constants.swift:26`) is deleted, and its removal added to the
   stage-5 sweep.

**Terminal** — `Sources/GlassTerminal/ServerManager.swift`

4. Introduce `ServerPersistenceStore` mirroring the database's triple. `loadServers()` reads through
   it instead of `defaults` (lines 227-231), keeping every existing guard: the size cap
   (`maximumServerCatalogBytes`), `validateServerCatalog`, and the wrong-persisted-type branch that
   correctly treats a non-`Data` value as corruption rather than an empty catalog. **Those guards
   move; they are not reimplemented.**
5. The rollback path (lines 810-868) currently snapshots and restores the defaults key by hand. It
   uses the store's `restore` instead. This is the one place a careless edit loses failure
   semantics, so it gets its own test before the change.
6. `UserDefaultsKeys.servers` (`Constants.swift:11`) is deleted — **and so are its two legacy
   migration entries**, `Constants.swift:113` and `Constants.swift:124`, which copy `servers` in
   from `sh.glas.app`. D26's "no conversion path" makes them dead. `sshKeys` leaves those lists in
   stage 3, not here. **Everything else in `legacyMacNonSecretKeys` stays** — theme, scrollback,
   snippets and the rest are settings, not connections, and the user's settings migration test
   depends on them.

**Desktop** — `Sources/GlassDesktop/`

7. `DesktopRepository.swift` is **deleted**, not adapted. It carries a publication/removal journal
   (`pendingHostRemovals`, `pendingHostPublications`) that exists solely to keep three processes
   agreeing, which is the machinery `AGENTS.md` says the merge removes. Its file locking, atomic
   rename and size caps have no counterpart need once the catalog is the store.
8. `DesktopAppModel.swift:76` stops constructing it and takes a `GlassServiceStore`.
   `DesktopConnection.validated()` is preserved verbatim and called on every decode — it is the
   VNC canonicalisation the capability depends on, and a test already pins it.
9. `connections.json` is removed on first launch by the stage-5 sweep, which is the only place that
   deletes anything from disk.

**Shared** — every capability's setup draft already commits its record and then records the link.
That order is preserved: the draft writes through `setConfiguration` first, the shell records the
link second, so a service never exists half-made (`GlassShellModel.swift:756-760`).

### What must not change

- Secrets never enter a configuration. The link carries `credentialID`; the Keychain carries the
  secret. `GlassServiceStore.swift:21-23` states this and the tests assert it.
- A configuration this build cannot decode is **skipped, never fatal** — the typed helpers already
  do this (`GlassServiceStore.swift:44-47`) and match the catalog backend's own rule.
- The local host's services do not travel. `setConfiguration` already routes them to `localCatalog`
  (`GlassShellModel.swift:389`); a test must pin it, because it is invisible until two devices.

### Validation

- Each capability keeps its existing store tests, repointed at `GlassInMemoryServiceStore`. Per the
  standing rule, **each rewritten test is watched failing with the logic defeated** before it counts.
- New: a round-trip per capability; an undecodable configuration skipped rather than throwing; a
  stale-link write rejected (`setConfiguration` re-reads the link before writing,
  `GlassShellModel.swift:380-385`); the local host never published.
- The terminal's rollback test is written **first**, against the current code, so the refactor is
  proven not to change failure behaviour.

### Risk

The terminal is the only capability with a second index over the same data — `SettingsManager` and
the saved-server surfaces read `ServerManager.servers`. Those readers stay; only the persistence
underneath them moves. **Grep every reader before the change, and the readers of the readers** —
that defect class now has seven recorded occurrences.

## Stage 2 — synced deletion cascades

**Objective.** A host deleted on one device cleans up the other devices' capability state, as local
deletion already does (D25).

**The seam, exactly.** `synchronizeCatalog()` applies the merge outcome at
`GlassShellModel.swift:331-333`:

```swift
for profile in outcome.toApplyLocally {
    try await catalog.upsert(profile)
}
```

A tombstone arrives, is upserted, and **no capability is told**. `deleteHost` gets this right
(`GlassShellModel.swift:744-752`) and is the implementation to reuse — it captures the owned
services *before* the records go, deletes records first, then asks each capability, and collects a
failure rather than stranding the deletion.

**Stage 1 shrinks this stage, and it is worth saying why.** Once the configuration lives on the
link, a tombstone takes the configuration with it. The cascade therefore has one job left:
**Keychain credentials**. That is smaller than it looked when D26 was written.

**Precise edits.** Extract the cascade from `deleteHost` into one private method taking the services
to clean; call it from `deleteHost` and from the apply loop for every profile arriving with
`deletedAt != nil` or with services that disappeared. Diffing services matters: a service removed on
another device is not a tombstone and leaves a credential behind otherwise.

**Validation.** A merge outcome containing a tombstone drives a fake capability's `removeService`;
a profile that merely lost one service cascades for that service only; a throwing capability does
not strand the sync. No test replaces the two-device run.

## Stage 3 — keys promoted, and device-bound services redacted

**Objective.** A key outlives the connections that use it and is reachable from any capability. A
service whose credential cannot leave this device does not appear on other devices at all.

### Reuse: most of this exists at the right layer already

- **The model is already shared.** `StoredSSHKey` is in `Sources/GlasSecretStore/Models/`, not the
  terminal, and decodes v1 records with defaults. Nothing about the model changes.
- **The material already synchronizes** — `SecretStoreConfiguration.swift:115`.
- **Device-binding is already detectable** — `KeychainManager.swift:575-582` matches the
  `TRUE_SE_P256:` / `SECURE_ENCLAVE_P256:` prefixes and routes that material to the device-bound
  configuration. It is the trigger; nothing new is invented to detect it.
- **Deleting a connection already leaves the key alone**, and **deleting a key already unassigns
  it** from servers using it.

**What is actually missing is one thing: the list is terminal-scoped.** `SettingsManager.sshKeys`
(`SettingsManager.swift:161`), persisted at `SettingsManager.swift:230` and read at
`SettingsManager.swift:461-474`. Nothing outside the terminal can offer a key.

### Precise edits

1. Move the list to a shell-owned `GlassKeyLibrary`, with `SettingsManager.sshKeys` becoming a
   read-through so the terminal's existing surfaces keep working unchanged during the stage.
2. The record rides in the Keychain beside its material, as the addendum concluded — no second
   store, no reconciliation rule, and a record that cannot contradict its material.
3. `UserDefaultsKeys.sshKeys` leaves `Constants.swift:113` and `:124` here.
4. **Publish redacts; apply re-attaches.** Both halves, in one commit, or neither:
   - Publish: before `catalogBackend.save(outcome.toPublish)` (`GlassShellModel.swift:335`), strip
     services whose credential is device-bound.
   - Apply: after `catalog.upsert(profile)` (`GlassShellModel.swift:332`), re-attach this device's
     own device-bound services to the winning profile.

   Without the second half the Mac publishes a host without its hardware-key terminal, pulls its own
   record back as the merge winner (`GlassCatalogSync.swift:70-77`, last write wins on the whole
   profile) and **deletes its own local service on the second sync**. Nothing errors. This is the
   most dangerous line in D26 and it passes every single-device test.
5. Binding is **derived from the credential on every save, never stored.** A stored flag drifts the
   moment a terminal switches from a hardware key to a password.
6. Binding attaches to the **service**, not the host: a host with a hardware-key terminal and a
   database keeps the database on the phone.
7. Settle the inherited default: `DesktopConnection.swift:56` sets `mobility = .deviceOnly`, against
   D18's synchronize-by-default. Stage 4's plan flagged it as an open decision and stage 3 is where
   it has to be answered, because it decides whether every desktop is device-bound by accident.

### Validation

Unit: derived binding flips both ways; a redacted publish plus an apply round-trip leaves the local
service intact **across two syncs, not one**; a host keeps its non-bound services.
Device: acceptance items 4 and 5 in the keys addendum. Nothing here is provable on one device.

## Stage 4 — the key manager

**Objective.** A workspace-level surface for keys, with the "used by" that makes deletion safe.

**Reuse.** The surface is a contributed library panel — `GlassLibraryPanel`
(`GlassConnectionUI/GlassLibraryPanel.swift:16`), whose one consumer today is Workgroups
(`GlassTerminalCapability.swift:295-317`). That is the pattern to copy, including the two-column
`results`/`detail` split with a model the contributor owns.

**The one precise change the shell needs:** `GlassShellLibraryView.swift:58` collects panels only
from `model.registry.registered`. Keys are shell-owned, not a capability's, so that line gains the
shell's own panels ahead of the capabilities'. It is one line, and it is the joining line — exactly
the kind that has been missing seven times.

**Content.** Name, algorithm, fingerprint, added date, and an *iCloud* / *This device only* badge.
Per key: rename, copy public key, export public key, **used by**, delete. "Used by" is the piece
that does not exist and is a straight read across the catalog once stage 1 lands — which is why this
stage sits after it. Delete names what will be unassigned and how many.

**Existing behaviour to move rather than rewrite:** the current manager at
`SettingsView.swift:182-275` and its delete alert at `SettingsView.swift:313-325`.

**The magic directive applies here.** This is the only genuinely new surface in the whole plan.
Design it on visionOS first — ornament placement, gaze-scale row metrics, the sheet rules in project
rules 13-15 — then adapt to Mac and touch. Not the reverse.

## Stage 5 — storage cleanup

Mechanical, user-visible, and it goes last because it is the least interesting. Measured on this Mac
today, `~/Library/Preferences/com.glasspowertools.plist`, 341,257 bytes:

| Finding | Count |
|---|---|
| Keys total | 529 |
| Carrying `glassdb` / `app.glassdb` names | 210 |
| `macWorkspaceRestoration.*`, never pruned | 263 |

Plus first-launch removal of `UserDefaultsKeys.servers`, `glassdb.connections`, `sshKeys` and
`connections.json` — the only place in this plan that deletes from disk, done once, with the old
names listed explicitly rather than matched by prefix.

View state (query history, grid layouts) **stays local** under corrected names. Renaming a key is a
reset for that key, which is acceptable here and is stated so nobody reports it as a bug.

### A correction to the record, and a real defect behind it

The memory bank records "4,112 abandoned test `UserDefaults` suites". **Re-measured today: 17,905**
plists in `~/Library/Preferences`. Top producers: `sh.glas.mac-workspace-tests` (7,282),
`GlassLayersTests` (4,983), `sh.glas.legacy-migration-tests` (974),
`com.glasspowertools.tests.audit` (605).

**And the obvious explanation is wrong.** The tests are not failing to clean up:
`MacWorkspaceTests.swift:2502-2520` creates a fixture and calls `cleanup()`, 24 creations against 24
cleanups. `removePersistentDomain` empties the domain but leaves a **42-byte empty plist on disk**,
verified by inspecting one. So the count grows by one file per fixture per run, forever, and
sweeping the files fixes today while changing nothing.

The fix is to bound the name: derive each suite name from the **test's own identity** rather than a
fresh `UUID()`, so the file count is bounded by the number of tests and reused across runs, and
parallel tests still get distinct suites. **To verify before adopting:** that no single test
constructs two fixtures concurrently. Proposal, not a decision.

---

# Part 2 — Stage 4, the remote desktop (W1 and W2 shipped)

| Wave | Scope | Done when |
|---|---|---|
| **W3 — presentation and input** | Metal surface, cursor decoder, audio, keyboard mapping, pointer, held-key release, display resize, colour-key modes, wallpaper | a real session renders, accepts input, resizes the source and disconnects clean, against the Windows 11 and Ubuntu VMs already standing |
| **W4 — parity sweep** | the 40-item checklist in the Stage 4 plan walked against the running app | signed off item by item; the 14 glassDT UI workflow tests pass |
| **W5 — spatial** | the visionOS canvas on current HIG; never paint a `Material` over system glass (rule 13) | **captured on the headset**, not the simulator |
| **W6 — audit and close-out** | reachability and dead-code audit, TODO/stub scan, **each `GLASSDT-PATCHES.md` hardening re-verified at its trust boundary**, attribution chain checked | findings recorded with owners; nothing deleted on a grep alone |

**W3 carries one debt the plan names:** the signed-in Apple Screen Sharing session is proven in
*glassDT*, by the user, not on the moved code. `Tests/LiveDesktop/GlassVNCProbe` takes the password
as a file path so it never reaches a command line. It needs the user's own Mac account, so it is
theirs to run.

**W5 is the only item in this entire plan whose size is unknown.** visionOS design pass 1 has never
been seen on hardware. It is either small or a redesign, and the magic directive means the answer
matters more here than anywhere else — which is the argument for doing it early rather than after
four more waves of Mac work.

# Part 3 — Stage 4.5, the desktop gaps

Items 1 and 2 are closed (the user's real Screen Sharing session on security type 30 retired both).

| # | Item | Size | Note |
|---|---|---|---|
| 3 | VNC-over-SSH, with an encrypted/unencrypted indicator | Small | The only confidentiality the capability can have — VNC is plaintext after the handshake. `VNCClient.init(configuration:callbacks:source:sink:open:)` (`VNCClient.swift:50-51`) already takes any `RFBByteSource` and D7's forward already exists |
| 4 | Sleep/wake handling | Medium | Absent everywhere, and **required by this project's own testing table**. Not optional |
| 5 | RD Gateway (MS-TSGU over HTTPS) | Large | Genuinely new protocol work. Reasonable to stop before it |
| 6 | Measured performance | Medium | No latency, FPS, energy or memory figure exists anywhere. Until it does: claim the pixels, never the speed |
| 7 | Multi-monitor UI, file clipboard, microphone | Each a product decision | |
| 8 | `.vnc` as a first-class `HostServiceKind` | Small, but it is the one CloudKit-replicated schema change | Only if the library genuinely wants to distinguish them |

# Part 4 — carried over from before Stage 4

1. **Network/Tailscale panel.** `TerminalTailscaleView` needs the `presentation` + shared-model
   split. Workgroups proved the pattern end to end, so this is small and mostly mechanical.
2. **visionOS design pass 1 is unverified on hardware**, plus two undiagnosed on-device UI failures
   that pass on macOS. Overlaps Stage 4 W5; do them in one headset session.
3. **Database workspace window sizing.** `GlassDatabaseScenes.swift:34-40` has the same defect
   already fixed in the desktop scene: an `else` branch with no greedy frame on the wrapper, so a
   workspace opened without a resolvable id sizes the window to a `ContentUnavailableView`. One
   line, deliberately left alone during Stage 4 because that stage changed nothing outside the move.
4. **Platform parity.** Vision Pro desktop overlaps W5; iPhone/iPad desktop overlaps W3-W4; SSH key
   records is subsumed by D26 stage 3. The only standalone item is **remembered dividers
   everywhere** — macOS-only today because SwiftUI exposes no equivalent, so it needs a different
   answer per platform rather than one shared fix.

# Part 5 — after that

- **Stage 5 — the editor interface.** GlassEditorKit is absorbed and already powering the database's
  SQL and record editors and the terminal's SFTP remote editor. What does not exist is the editor as
  a capability of its own. The user has SFTP interface ideas intended to make editing shine, and
  they belong here.
- **Stage 6 — deprecate the three public repositories with redirects.** Not started. Project rule 9:
  public repositories are not touched without explicit instruction.

---

# Sequence, and the reasoning

1. **D26 stages 1-3.** The product's defining sentence — add a host anywhere, connect from
   everywhere — is false until these land, and every other item is cosmetic beside it.
2. **Stage 4 W3-W4.** Makes the desktop real rather than merely present, against VMs already
   standing.
3. **Stage 4 W5 + carried item 2, in one headset session.** Early, because it is the only
   unknown-size item in the plan and the magic directive puts the most weight on it.
4. **D26 stages 4-5**, then Stage 4.5 items 3, 4 and 6.
5. Tailscale panel, the one-line database window fix and remembered dividers slot in anywhere.
6. RD Gateway and Stage 5 on their own merits, once the above is green.

# Acceptance, and what no test replaces

The user's own scenario, unchanged since it was stated:

1. Add a host with a Terminal service on the Mac, authenticate with an imported key, connect from
   the phone **without re-approving host trust**. That single run proves configuration sync, key
   record sync and D23's pin sync together.
2. Delete that Terminal connection. **The key is still there**, usable, and the manager shows it is
   used by nothing.
3. Attach the same key to a second host and connect with it from a third device.
4. Generate a Secure Enclave key on the Mac and use it for a second terminal on that host. The host
   still appears on the phone. **That terminal does not. The database on the same host still does.**
5. With the hardware-key terminal in place, **sync twice.** It must still be there.

1-3 need two devices; 4 and 5 need a Mac with a Secure Enclave and one other device. Item 5 is the
one that catches the dangerous bug, and it is the reason stage 3's two halves ship together.

# Evidence

Every file:line in this note was read in the checkout at `57bca0b` on 2026-09-14. Defaults counts
were measured with `plutil -p` against `~/Library/Preferences/com.glasspowertools.plist` and by
listing `~/Library/Preferences`. The empty-plist finding was verified by inspecting a leaked file
(42 bytes, `{}`). Test and suite counts are from the last recorded run, not re-run for this note.

---

# Execution log — D26 stage 1

## Terminal, part 1: the seam (2026-09-14) — **done, and behaviour-neutral by construction**

Authorized: the user gave the go-ahead. Nothing committed; the user commits.

**What landed.** `ServerPersistenceStore` (`ServerManager.swift:59-96`), the load/hasStoredValue/
save/restore quartet shaped after the database's `ConnectionPersistenceStore`. Reads now go through
it (`loadServers`), so the terminal's reads are finally behind the same seam its writes already
were. The store is still `UserDefaults`-backed, deliberately: this step changes *where the seam is*,
not *what is behind it*, so a green suite is the evidence it changed nothing.

**Tests written first, against the pre-refactor code**, and watched failing with the rollback
defeated before being trusted: `Tests/GlassTerminalTests/ServerPersistenceTests.swift`, pinning that
a failed write rethrows the *original* error with the catalog and the in-memory list untouched, and
that a failed rollback is reported as `rollbackFailed`.

**One of those tests was wrong on its first draft and the code was right.** A write that lands
nowhere rolls back *successfully*, because the rollback re-persists the original catalog and
verifies it by readback — and if the failing writer merely dropped the bytes, the stored catalog is
still the original. Reaching `rollbackFailed` needs the store to end up holding something genuinely
different. Recorded because the first draft asserted the opposite and would have been "fixed" in the
wrong place.

## The consequential decision: the write path is now async

`HostCatalogStore` is an actor, so every catalog write is async. That is pre-existing and
shell-wide. The terminal was the only capability whose saves were synchronous — the desktop's
`DesktopAppModel.save`, the database's draft and the shell's own `GlassServiceDraft.commit` are all
already async — so the terminal was made to match rather than the catalog made synchronous.

Measured cost: **16 functions became async**, across `ServerManager`, `SessionManager`,
`SettingsManager`, `GlassTerminalCapability` and the draft, plus their call sites and 41 test call
sites.

**Three call sites are in SwiftUI actions that cannot await**, and each was wrapped in
`Task { @MainActor in … }` around code that *already* caught its error and turned it into UI state,
so what the user sees is unchanged and only the timing moves by a turn of the run loop:
`SettingsView` (delete SSH key, import SSH config), `TerminalConnectFlow` (trust host key, delete
server), `TerminalWindowView.trustAndReconnect`, and the standalone server form's save.

### The one genuine behaviour change, stated plainly

**The legacy host-trust migration no longer completes during `loadServers`.** It writes the catalog,
and `loadServers` is called from `init`, which cannot await. It now runs in a task the manager holds
(`ServerManager.legacyHostTrustMigration`) so anything needing it finished can wait for it. Eight
tests asserted the migration's results immediately after loading and failed until they awaited it —
they were right to fail, and that is the evidence the change is real rather than cosmetic.

D26 deletes this migration outright along with the defaults-backed catalog: it reads `sh.glas.app`'s
legacy `trustedHostKeys`, and the decision is that the new build reads nothing old.

### A process note worth keeping

A scripted pass to add `await` across the tests rewrote `#expect(` into `#await expect(` and marked
three *helper* functions async that never call the async API. Caught by the compiler, reverted with
`git checkout` on the four tracked test files, and redone with named receivers only. **This is the
second time a clever regex across many files has cost more than explicit edits would have** — the
first being the 2026-09-13 rename that hit 105 occurrences across 64 files.

## State

`swift build` and `swift test` green: **1146 tests / 117 suites**, stable across two consecutive
runs. The previously recorded 1153 was not reproduced and is not reconciled here; 1146 is what this
checkout measures.

**Not done, and this is the half that is actually D26:** the store is still `UserDefaults`-backed.
Wiring `ServerPersistenceStore` to `GlassServiceStore`, deleting `UserDefaultsKeys.servers` and its
two legacy-migration entries (`Constants.swift:113`, `:124`), and doing the same for the database
and the desktop, all remain.

## Terminal, part 2: a gap the plan did not name — servers with no service link

Found while designing the catalog-backed store, because the adapter forced the question: a
`ServerPersistenceStore` backed by `GlassServiceStore` writes **per endpoint**, so a saved server
with no service link has nowhere to go.

**Two live paths create servers with no host record and no link**, both with a fresh `UUID()`:

- `SettingsManager.importSSHConfig` (`SettingsManager.swift:1040-1049`) — every imported `Host`.
- The standalone Add Server form, `TerminalServiceDraft.saveStandalone`
  (`ServerFormViews.swift:324-336`), reached from `requestAddServer()` and from the Tailscale
  panel (`TerminalTailscaleView.swift:104`).

Only `GlassShellSetup.swift:334` creates a service link today.

**These servers are already invisible in the library.** `GlassShellLibraryView` renders
`model.items`, which is the catalog; nothing anywhere in `Sources/GlassShell` reads
`serverManager.servers` (searched for the concept, not the name: `.servers`, `serverManager`, and
the library's item source). So a host imported from an `ssh_config` cannot be seen, favourited,
tagged, given a second service, or synced — it is reachable only from the terminal's own
Connect-Saved-Host surfaces. That is a live inconsistency, not something D26 introduces.

**Impact on real data, measured on this Mac:** `com.glasspowertools.plist` holds **1** saved server.
So this is a correctness fix, not a migration problem — consistent with the user base being two
people.

### The decision taken

**Keep both forms exactly as they are, and have them create the host record and `.ssh` link behind
the scenes**, rather than rerouting the user through the shell's host sheet. Same UX, same number of
steps; the difference is that the machine now appears in the library like every other one, which is
what a person would already have expected. The alternative — making Add Server open the shell's host
sheet — is a visible workflow change and buys nothing that this does not.

**Mechanism, reusing the pattern already in the codebase:** a closure on the runtime set by the
composition root, exactly as `GlassDesktopRuntime.hostAccess` is
(`GlassDesktopCapability.swift:45`), so the capability still never holds the shell model (project
rule 6). The shell side is already public: `addHost(displayName:address:…)` and
`addService(kind:displayName:endpointID:)`.

### Also found: a second kind of test residue

`~/Library/Application Support/GlassPowerTools-Tests/` holds **23** abandoned catalog directories
(172 KB). The stage-5 sweep was scoped to `UserDefaults` suites and misses this entirely — tests
leave host catalogs behind as well as defaults domains.

## Stage 5, partially done early: the test residue is swept

Authorized: the user asked for the old test files to be cleaned up. Done 2026-09-14, on this Mac only — nothing in the
repository changed, so this is an environment cleanup, not a commit.

| Removed | Count |
|---|---|
| Abandoned `UserDefaults` suite plists in `~/Library/Preferences` | **35,865** |
| Abandoned host catalogs in `~/Library/Application Support/GlassPowerTools-Tests/` | 23 dirs, 172 KB |

`~/Library/Preferences` went from **37,175 entries to 1,310**.

**The count had nearly doubled since it was measured this morning.** It was 17,905 before today's
work; three `swift test` runs during the D26 seam refactor added roughly eighteen thousand more
files. That is the strongest argument yet for bounding the suite names rather than sweeping again:
**a full test run currently costs about six thousand files in the user's Preferences folder.**

**What was deliberately left:** `ai.mirrormesh.tests` (525 files). It is another project's residue
and not ours to delete.

**Verified after the sweep:** `com.glasspowertools.plist` (529 keys, 341,257 bytes),
`sh.glas.app.plist` and `app.glassdb.plist` all intact; the real
`~/Library/Application Support/GlassPowerTools/` still holds `GlassHostCatalog`,
`shell-preferences.json`, `SQLDrafts` and `Desktop`; `swift test` still green.

Ownership was checked before deleting rather than assumed from the name: every suite prefix was
grepped back to the test file that creates it (`GlassLayersTests`, `WorkspaceCaptureTests`,
`WorkspacePresetTests`, `test.MigrationDefaults`, `com.glasspowertools.tests.audit` all resolve to
files in `Tests/`).

**Still to do, and it is the part that matters:** the leak itself. Sweeping fixes today and changes
nothing about tomorrow.

## Terminal, part 3: the catalog is the store (2026-09-15) — done

`ServerPersistenceStore.catalog(_:)` puts each saved server on its own service link. The composition
root attaches it; `UserDefaultsKeys.servers` is no longer the production store and is out of both
legacy migrations. Deleting a server takes its link with it, through `detachService` — link-only,
because the capability is the one deleting and `removeService` would call straight back into the
delete that is running.

**1481 tests / 157 suites, exit status 0.**

### The bug that cost the machine 90 GB

`GlassServiceStore` carried both the requirement `setConfiguration(_ data: Data?, for:)` and a
convenience `setConfiguration<T: Encodable>(_ value: T, for:)`. **`Data` is `Encodable`.** Passing
`Data` matches the generic *exactly* while matching the requirement only through optional
promotion, so Swift chose the generic — which encoded the `Data` to a base64 JSON string, producing
more `Data`, and called itself. The extension's own body did this, so it recursed for **any**
caller, not just the new one.

It had no callers from the day it was written until stage 1 reached it. When it finally ran it
allocated until the process was killed at **90 GB**.

**Why it took so long to find, and this is the lesson worth keeping:** an out-of-memory kill leaves
**no crash report, no failure line and no output** — the test process simply stopped, in about two
seconds, looking exactly like a hang. Two whole diagnostic passes went into the locked-screen
hypothesis first, because that *also* produces an opaque failure on this machine and was genuinely
present. The thing that actually found it was instrumenting the call path with unbuffered stderr
writes and watching which line never printed: the callee was never entered, which pointed at
dispatch rather than at anything the callee did.

Fixed by labelling the convenience `setConfiguration(encoding:for:)` and typing its local as `Data?`
so the requirement is the only thing it can resolve to. `Tests/GlassShellTests/GlassServiceStoreTests.swift`
pins both halves; each case completes in microseconds when the API is right and does not complete at
all when it is not.

**A watchdog is now the way to run a suspect test**: launch it, sample total RSS, kill above a
ceiling. The runaway went from 4,885 MB peak to 8 MB.

### Two other defects found on the way

- **`adoptedIdentity` swallowed adoption failures** with `try?`, making a real failure
  indistinguishable from "no shell attached" — and then saving the server anyway under a fresh
  `UUID()`, which is exactly the orphan D27 exists to remove. It propagates now, and both call sites
  report it.
- **`attach(store:)` re-ran the first-launch migrations**, reaching the Keychain on every store
  swap. Confined to the first load.

### Tests updated rather than deleted

Two legacy-migration tests asserted that a legacy `servers` blob is copied forward and that an
unreadable one holds the migration open for a retry. Both describe machinery D26 removed, so they
now assert the contract that exists: the blob is ignored, the settings beside it still migrate, and
the pass completes rather than staying pending.

## D26 stage 1 complete — database and desktop, 2026-09-15

**1485 tests / 158 suites, exit status 0, and the app target builds.**

### The DRY move that made this small

The terminal's reconcile — *make the stored set match this list* — is the same problem for all three
capabilities, because all three key a record by the shell's endpoint id. It is now
`GlassShell/GlassServiceRecords.swift`, written once and used three times, and the terminal's own
copy was deleted to use it. It owns three rules in one place: **removals before writes** (a
configuration left behind for a record that is gone is D25's orphan), **unchanged records skipped**
(every write publishes, so rewriting churns the catalog for every other device), and **compare as
bytes** rather than by some type's idea of equality.

Proof it is genuinely shared: defeating the removal branch fails **both** the terminal's deletion
test and the desktop's, from one edit.

### Database

`ConnectionPersistenceStore.catalog(_:)` beside `.live`, and the store's writes became async for
the same reason the terminal's did — the catalog is an actor. Far smaller than the terminal: one
`persist` funnel and four mutators rather than sixteen. `ConnectionManager.attach(store:)` and
`GlassDatabaseRuntime.connectToLibrary(store:)` mirror the terminal's exactly.

### Desktop — the file store is gone

`DesktopRepository` was **rewritten, not adapted**: it was a file-backed actor with `flock`, an
atomic rename, a size cap, a schema version *and a publication journal* —
`pendingHostRemovals`/`pendingHostPublications`, which recorded what still had to be told to a
separate app's catalog so a crash could not lose it. That existed because glassDT was one of three
processes agreeing about one model. **Checked before deleting: nothing outside that file ever read
those queues.** `connections.json` no longer exists.

`validated()` now runs on the way **out** as well as in, because it is what canonicalises a VNC
record and a record written by an older build has to reach the same shape as one written now.

### A model with no library says so

`DesktopAppModel`'s repository is optional and `requireRepository()` throws
`DesktopError.libraryUnavailable`. Deliberate: *"no desktops"* and *"no catalog to read"* are
different answers and only one is safe to act on. Nine call sites route through it rather than
optional-chaining into a silent empty list.

Four desktop tests had to attach a store — correctly, because they were asserting against a model
that could not read anything. One reloaded from a *directory* to prove an import survives; under
D26 "relaunched" means a second model over the **same catalog**, which is what two launches of the
app actually share.

### Stage 1 is done

All three capabilities read and write their records on their service links. `UserDefaultsKeys.servers`,
`glassdb.connections` and `connections.json` are no longer production stores. **Next: stage 2**, the
synced deletion cascade, which stage 1 shrank to Keychain credentials alone.

## D26 stage 2 complete — synced deletion cascades, 2026-09-15

**1489 tests / 159 suites, exit status 0; the app target builds.**

### Extraction, not new logic

`deleteHost` already did this correctly and had since D25: capture the owned services *before* the
records go, delete the records, then ask each capability to clean up, collecting the first failure
so one throwing capability cannot strand the rest. That body is now `cascadeRemoval(of:)` and both
deletion paths call it — a host deleted **here**, and a host deleted **on another device**.

### What the sync had to learn

`synchronizeCatalog` applied the merge outcome and told nobody. It now captures what each incoming
record *takes away*, before applying it, from the local snapshot it already holds:

- a **tombstone** removes every service on the record;
- an **ordinary edit** removes whichever services are no longer on it.

A host arriving for the first time has no local record, so nothing departed — and a rename removes
nothing, which is the case most likely to be got wrong and has its own test.

### Two deliberate differences from the local path

**The cascade runs after the projection is rebuilt**, matching `deleteHost`'s order: the records go
first, then the capabilities are asked. A stray configuration is harmless; a link to nothing is not.

**A failure here is swallowed, where `deleteHost` throws.** `deleteHost` throws because a person
pressed Delete and is waiting for an answer. Nobody is watching a background sync, and a capability
failing to remove a credential must not fail a sync that has already applied correctly.

### What the cascade is actually for now

Since stage 1 the configuration lives on the service link, so a tombstone takes it along. The
Keychain credential is what has nobody else to remove it — which is why stage 2 is small, and why
it would have been much larger before stage 1.

### Evidence

Four tests drive a real `GlassShellModel` through a scripted backend with a capability that records
every `removeService`. Defeating the cascade fails both positive tests and leaves both negative ones
green — the shape that shows they test the cascade rather than the sync.

## D26 stage 3, first half — device-bound services stay put, 2026-09-15

**1493 tests / 160 suites, exit status 0; the app target builds.**

One protocol member, `GlassCapability.isDeviceBound(_:host:)`, defaulting to false, and three places
in `synchronizeCatalog` that have to agree about the answer:

- **publish redacts** — `redactingDeviceBoundServices`, applied to `toPublish`;
- **apply re-attaches** — `reattachingDeviceBoundServices`, applied to `toApplyLocally`;
- **stage 2 excludes** — a redacted service is absent from every record the account holds, so
  without this it reads as *deleted elsewhere* on the next sync and stage 2 removes its credential.
  The two stages would have quietly undone each other. A tombstone still takes it.

The derivation lives in one place, `deviceBoundServices(of:)`, because those three depend on
agreeing. The terminal answers it from the server's current `sshKeyID` → the key's
`storageKind == .secureEnclave`, so switching a service to a password makes it start travelling with
no flag to clear.

### The test that was passing for the wrong reason

`syncingTwiceKeepsTheDeviceBoundService` was written as the decisive one — the half implementation
"passes every single-sync test and deletes the connection on the second". **It passed with the
re-attach deleted.**

Syncing twice proves nothing on its own: the account echoes the redacted record back with the *same*
`updatedAt`, so `GlassCatalogMerge.winner` keeps the local copy on equal timestamps and applies
nothing at all. The record has to come back **newer** — which is what happens the moment any other
device touches that host. With one added line stamping the returning record, removing the re-attach
now fails it.

The test that caught the half implementation first time was
`aRedactedServiceIsNotMistakenForOneDeletedElsewhere`, because a remote edit there is genuinely
newer. Both are kept: they fail for different reasons and the pair covers the rule.

**This is rule 27 again, in its sharpest form yet** — a test aimed at the right defect, passing
because the scenario never reached the code under test.

### Still to do in stage 3

The key **library** itself is still terminal-scoped: `SettingsManager.sshKeys` under the terminal's
`sshKeys` defaults key. Moving it to the shell — so any capability can offer a key, and the records
ride in the Keychain beside their material — is the remaining half, and it is what stage 4's "used
by" needs.

## D26 stage 3, second half — key records move into the Keychain, 2026-09-15

A key's record now lives beside its material rather than in `UserDefaultsKeys.sshKeys`.

**Where it went, and why not the shell.** The plan said "a shell-owned key library". It went to
**`GlasSecretStore`** instead, which already owns `StoredSSHKey`, the material store and the
mobility policy. That satisfies the actual requirement — any capability can reach it, and the shell
depends on no capability (project rule 6) — without the shell taking ownership of credential
storage, which is not what the shell is for.

**`SSHKeyRecordStore`**, beside `SSHKeyKeychainStore`. A second store would have needed its own
merge rule and could have disagreed with the material it describes — a record for a key that is not
there, or a key with no name. Beside the material there is nothing to reconcile, because the same
routing decides both.

**That routing is the rule**, and it lives where it already lived: `KeychainManager` sends Secure
Enclave *material* to the device-bound configuration, and now sends a Secure Enclave *record* there
too. A hardware key listed on a device that cannot use it is worse than one that is not listed.
`recordDestination(for:)` is separated from the write so the decision can be tested — the production
configuration carries a real access group and an unsigned test binary cannot write to it, which is
why every other Keychain test builds its own. The same seam exists for `isDeviceBoundKeyMaterial`,
for the same reason.

**`sshKeysRecordService` is in `synchronizableServices`**, so a portable key's record travels with
its material. A secret that arrived on another device but could not be named there would be a key
with no identity.

**`SettingsManager.SSHKeyCatalogStore`** is the third injectable store of this shape (servers,
connections, now keys). The defaults-backed one stays the default so the existing key tests — which
inject `sshKeyDefaults` and a catalog writer — keep testing what they always did; the runtime
attaches the Keychain one in production. *Three stores of the same shape is itself a smell, noted
rather than forced: they differ in what they key by — per-service configurations against a single
collection — and a shared abstraction would have to pretend otherwise.*

`sshKeys` is out of both legacy migrations, alongside `servers`.

### Verification, honestly

**The full suite could not be verified: the Mac's screen locked** (the user said they were away).
100 tests failed, 89 carrying rule 28's signature outright and the other 11 being assertions
downstream of a catalog write that could not happen — every one of them writes a host catalog under
`.completeFileProtection`. The same suite was **exit status 0 at 1497 tests / 161 suites** minutes
earlier, before the lock, and the only changes since are a pure extraction and a four-test file that
passes. **The app target builds.** The full run should be repeated unlocked before this is treated
as proven.

### Still open in stage 3

The key library is reachable by any capability *in principle* — the records are in a shared module —
but nothing outside the terminal offers keys yet, and the deletion journal still lives in
`SettingsManager`. Stage 4's "used by" is what makes the library worth opening.

## D26 stage 4, model layer — "used by", 2026-09-15

### One question, not two

`isDeviceBound` was replaced by `credential(for:host:) -> GlassServiceCredential`, because *can this
service travel* (stage 3) and *which shared credential does it reference* (D28's "used by") are the
same question — **what authenticates this service** — reached by the same lookup. Two members would
have walked the same path twice and let the answers disagree.

```
case ownedByService            // a password: belongs to this service and nothing else
case sharedKey(id:deviceBound:) // a key: the thing a manager has to be able to trace
case unreadable                // this build cannot say, and must not pretend otherwise
```

The distinction that earns the enum is **shared or not**. A password ends with the service that uses
it. A key can authenticate a terminal on `alpha` and another on `bravo`, which is why deleting one
must leave the key alone and why the manager has to name who is using it.

`unreadable` is the failure mode designed in rather than retrofitted: a configuration written by a
newer build is skipped rather than fatal, so without counting it a key in genuine use reads as *used
by nothing* — and then someone deletes it.

### Derived, never stored

`services(usingKey:)` and `usageCount(ofKey:)` walk the catalog and ask the owning capability. No
table. The edge already exists on each service's configuration, and a second copy would have to be
kept in step through deletion, editing, sync and merge — D25 is the bug where deleting a thing
forgot to tell the other store. Both readers, and stage 3's redaction, now go through one private
`credential(for:on:)` so they cannot disagree.

### Verification — blocked, not green

**The Mac's screen was locked for this entire piece** (rule 28), so every test that writes a host
catalog fails at the write. What is verified: **the app target builds**, and the three suites that
touch no catalog pass (12 tests). `D28KeyUsageTests` — five tests including the user's own
`bravo`/`alpha` scenario — **has never been run** and must be before this is believed.

**Owed:** a full unlocked run covering stages 1–4 and the two-device acceptance list.

### Still to build in stage 4

The panel itself: a contributed `GlassLibraryPanel` beside Collections, listing name, algorithm,
fingerprint, added date and an *iCloud* / *This device only* badge, with rename, copy public key,
export public key, **used by**, and a delete that names what it will unassign. The model layer above
is what it reads.

## The menu bar: three apps that each owned File, 2026-09-16

Reported by the user against the installed 0.4.119: ⌘T did not open a new tab or session.

### What was actually wrong

`CommandGroup(replacing:)` does not merge. When two scenes replace the same placement SwiftUI keeps
one and the other is **absent** — no warning, no failure, nothing to see at runtime except a
shortcut that reaches nothing. The database's File group and the terminal workspace's both replaced
`.newItem`; the database's scene is registered later and won.

Read out of the running app rather than inferred (`osascript` → System Events → menu bar):

```
File → New SQL Document, New Connections Window, Open SQL Document…,
       Close Active Tab, Save SQL Document…, Close, Close All
```

Every terminal item was gone: **New Terminal Window**, **New Workspace Tab (⌘T)**, **Connect Saved
Host… (⌥⌘T)** — and the `replacing: .saveItem` group too, so ⌘W closed the window instead of the
tab. `CommandMenu` contributions (Terminal, Query, Library) were unaffected, which is why only the
File menu was hollow.

### The shape of the fix, which is the user's

⌘N is a **stub the focused window aims**, rather than a key one capability owns:

| Focused window | ⌘N |
|---|---|
| Database workspace | New SQL Document |
| Terminal workspace | New Terminal Window |
| Connections library | New Host |
| anything else | *New*, disabled |

`GlassNewItemAction` carries the title *and* the action, published with
`.focusedSceneValue(\.glassNewItem, …)`, so the menu always names what ⌘N will make. One scope —
`GlassShellFileCommands`, attached by the composition root — replaces `.newItem`; every capability
appends with `after:` and keeps its item **unbound**, so it stays reachable from any window. The
library's Add Host button gave up its own ⌘N for the same reason.

### ⇧⌘T — another tab on the same machine

`MacNewWorkspaceTabAction` gained `repeatingCurrentConnection()` and a title naming the machine —
**"New Tab on the Linux server"**. It copies the focused pane's **intent**, not its session: a
`MacWorkspacePaneIntent` already carries the saved server for SSH and the shell and directory for
local, so the new tab connects through the same server, credentials and host trust with no chooser.
`sourceSessionIndex` is cleared — it identifies a pane inside a restored workgroup layout, and this
is a new tab, not a restoration.

### The test class that had no test

`Tests/GlassShellTests/MenuBarPlacementTests.swift` reads the sources, because nothing else can see
this defect: no unit test can instantiate a `Commands` tree and ask what the menu bar became, and
the loss happens when SwiftUI merges scenes in a running app. Four checks: one replacer per
placement (recorded with the platform that makes visionOS's `PlatformTerminalCommands` exclusive),
one owner for ⌘N, one owner per platform for ⌘T, and the set of windows publishing `\.glassNewItem`.
Proven to bite by putting the database back to `replacing:` — it fails on exactly the shipped
defect.

## D26 stage 4, the panel — 2026-09-16

`Sources/GlassShell/GlassKeyManagerPanel.swift`, contributed through `GlassShellModel.libraryPanels()`
and joined at `GlassShellLibraryView.swift` — the shell's panels lead, then each capability's.

**The surface moved; the lifecycle stayed.** `GlassKeyStore` (in the shell) is what the manager
needs — the keys, the public key, delete, and the three sheets as views. `GlassTerminalKeyStore`
forwards every one to `SettingsManager`, which owns passphrase inspection, Secure Enclave
generation, the record that travels with the material, and a **journalled** delete that rolls the
key and its servers back together. Re-implementing that for a new surface would have been a rewrite
of the one part of the system where a rewrite is least affordable. The sheets come across as
`AnyView` for the same reason `GlassCapability` already hands the library whole views.

The Settings section is replaced by one line pointing at the library; `AddSSHKeyView`,
`GenerateSecureEnclaveSSHKeyView` and `RenameSSHKeyView` are unchanged and now presented from the
panel. The nested Add SSH Key sheet inside the server form (rule 15) is untouched, and so is the UI
test that drives it.

**Fingerprints.** `StoredSSHKey` has no fingerprint field, so it is derived from the public key.
`OpenSSHPublicKeyLine` (GlasSecretStore) parses the `authorized_keys` line and hands the blob to
`PinnedSSHHostKey.sha256Fingerprint(for:)`; `SSHPublicKeys.sha256Fingerprint(for material:)` now
goes through it too, so a key cannot present one fingerprint in the transport and another in the
library. Checked against `ssh-keygen -lf`'s own output for a throwaway ed25519 key, and against the
comment being excluded — two exports of one key must not look like two keys.

**Verified:** 14 new tests pass (9 panel, 5 fingerprint), package and all three app targets build at
0.4.120. `attachingAKeyStoreOffersThePanelWithItsCount` proven to bite by defeating
`libraryPanels()`.

**Owed:** the panel has never been *seen*. The line that joins it to the sidebar is a view, and no
unit test can reach it — install and look. The two-device acceptance run is still owed and still
the only thing that proves D26's sentence.

## The reset that was data loss — 2026-09-16

The user asked why their connection settings were reset each time. The machine stayed in the library, the SSH key
stayed in the key list, and Edit Terminal on the Linux server said **"This terminal has no saved configuration
behind it. Remove the service and add it again."**

**Cause.** `App.init` calls `terminal.connectToLibrary(store: model)`, and `ServerManager.attach`
read the store immediately — but `GlassShellModel.load()` runs later, from the library view's
`.task`. `configurations(ofKind:)` on an unloaded model returns nothing, and nothing is
indistinguishable from an empty library. So every launch built an empty saved-server list, and the
next write — adding a machine, stamping "last connected" — called
`GlassServiceRecords.replaceAll(with: [])`, whose contract is to delete what is missing. The
capability deleted the user's configurations while trying to load them. The desktop attached through
an unawaited `Task` and lost the same race; the database attached the same way and survived only
because its `loadIfNeeded()` happened to run later.

**Fix**, one gate at the shared door rather than three:

- `GlassServiceStore.isCatalogLoaded` — the honest distinction. Defaulted `true` for in-memory
  stores; `GlassShellModel` returns `isLoaded`.
- `GlassServiceRecords.replaceAll` **throws `catalogNotRead`** rather than reconciling. This is the
  one call in D26 that can destroy data by doing exactly what it was asked.
- `GlassCapability.catalogDidLoad()`, called after every `GlassShellModel.load()` including a failed
  one. The terminal rebuilds its saved-server list there, the database reloads, the desktop reloads.
- `ServerManager.loadServersIfNeeded` and `ConnectionManager.load` refuse an unreadable store
  instead of reading it as empty; `DesktopAppModel.load` does the same.

**Proven, then fixed.** `Tests/GlassTerminalTests/D26RelaunchTests.swift` drives two real
`GlassShellModel`s over one directory — a relaunch. Before the fix: 0 servers read back, and adding
a second machine deleted the first machine's terminal. After: both pass. 1529 tests, exit status 0.
Installed as 0.4.121.

**Recovery was written and then deleted, deliberately.** The pre-D26 `servers` key and the
desktop's `connections.json` both still held the erased records, and a one-time pass that refilled
only empty links — never overwriting, never resurrecting a deleted record, guarded by four tests —
worked. The user's direction ended it: there is no legacy, and the product does not need that baggage. This is
the first version, the data on that Mac is test data, and four records are cheaper to re-enter than
a migration is to carry. See **rule 36**, which also retires the stage 5 item about deleting legacy
keys on first launch: nothing reads them.

## Stage 5, first take — the editor as a surface, 2026-09-16

Built in one pass at the user's direction: plan and build the Edit module in a single attempt, for
all platforms, with best-in-class features and polished Apple-native behaviour.

**What was already there, and is not rebuilt.** `GlassEditorCore` and `GlassEditorUI` are a complete
editing engine — text storage, undo with coalescing, tree-sitter highlighting, a find engine,
encoding and line-ending detection, atomic saves, and remote conflict detection — and have been in
production behind the SQL editor, the record editor and the SFTP remote editor since the absorption.
`GlassEditorModel` holds a document; `GlassEditorView` draws it on AppKit and UIKit. **The new module
is the workspace around that**, which is the part the engine deliberately does not do: where a
document came from, what it is called, whether it has been saved.

`Sources/GlassEditor/`:

| File | What it is |
|---|---|
| `GlassEditorDocument` | one open file: open, save, save-as, language from the extension |
| `GlassEditorWorkspace` | the open set, recents, find state, projects — no SwiftUI, so it is testable |
| `GlassEditorProject` | a folder **on a machine**, its lazily-read tree, and how it is reached |
| `GlassMachineIdentity` | whether a host record *is* this machine, decided by SSH host key |
| `GlassEditorWorkspaceView` | sidebar of projects and documents, editor, find bar, status bar |
| `GlassEditorScenes` | the window, the runtime, and the File/Text menu items |

**The project idea is the answer to the user's question**: how to move from the editor on the Mac
to the Vision Pro, where the Mac is an SSH connection, and have the two associated. A
project is `(hostID, path)` rather than a URL, so it is the same project on both devices and travels
on the existing D19 catalog sync; each device decides the transport. **Identity is the SSH host key,
never a name or an address**: a hostname is ambiguous, a Tailscale address moves, and only the
machine holding a key's private half can present it. `reach(...)` returns *this machine*, *over SSH*
or *unreachable* — and never guesses, because a Vision Pro publishes no host keys at all and absence
of evidence must not read as evidence of absence.

**What works now:** open a file or a folder, a tree that reads a directory only when it is expanded,
tabs with an unsaved marker, find and replace with regex and case options, go to line, a status bar
with position, language, line endings and a warning when a large file drops out of highlighting,
drag and drop onto the window, recents bounded at 20, ⇧⌘E for a window, ⌥⌘F and ⌥⌘L for find and go
to line, and ⌘N meaning **New Document** while the editor is focused — the shell's contextual New
picked the window up with no extra wiring, which is the menu-bar work from this morning paying off.

**23 tests**, the two load-bearing ones being that a file opened and saved unchanged is
byte-identical (CRLF fixture, because the platform default is LF and a naive save rewrites every
line) and that closing a dirty document refuses rather than discarding. 1,554 tests overall, exit 0;
macOS, iOS and visionOS all build; 0.4.128 installed on the Mac and the Editor window verified open
with its own menu.

**The next piece, and it is the whole of the remote half:** `GlassEditorDirectoryReader` is a
protocol with one implementation (the local file system). The SFTP one is the work — and it needs a
broker, because rule 6 forbids the editor importing the terminal. The shape is
`GlassCapabilityHostAccess`'s: the shell asks whichever capability owns `.ssh` for a directory
listing and a file's bytes, and the editor never learns who served it. Until that exists, a project
on another machine shows its badge and cannot be browsed.

## The evening of 2026-09-16 — grammars, and two things that vanished

### Twelve languages, and the integration that came free

Six added (Python, JavaScript, Go, Rust, C, PHP) to the six config formats that were there. **The
SFTP remote editor picks its grammar with `LanguageID.forFileExtension`**, so a `.py` or `.php` file
opened on a server through the Files browser now colours with no further change — the point the user
made in reminding us not to forget the other integrations.

Three of the six had to be vendored (`Packages/TreeSitterPython`, `TreeSitterJavaScript`,
`TreeSitterRust`, `TreeSitterPHP`) for the reason YAML already was: upstream's SPM manifest compiles
`parser.c` and not `scanner.c`, so the grammar will not link against its own external scanner. The
vendored copies differ from upstream by one manifest. Go and C have no scanner and stay pinned.

**Swift was refused deliberately**: upstream ships no generated `parser.c`, and generating one here
produced a **20.6 MB** C file — the weight this project shed when it stopped carrying 55 MB of
grammars, for the one language its user edits in Xcode.

Two existing tests found everything: the capture-mapping suite named each unmapped capture
(`@delimiter`, `@constructor`, `@tag`, `@module`), and the grammar suite caught that Rust paints
integers, floats and booleans alike as `@constant.builtin`, so requiring `.number` of it would have
demanded something upstream does not emit.

### Duplicate services — residue, not a new defect

The Linux server showed two Terminals and two Desktops, identical, one of each dead: the morning's persistence
defect emptied configurations without removing their links, and re-adding a service created a second
link beside the corpse. **The row now says "Terminal · Not set up" in orange** when nothing is behind
the link, so the dead one is identifiable and removable. Built-in local services are never marked —
they store nothing by design and the warning would be permanent on the one host nobody can repair.

### "This Mac" disappeared — caused by the sync fix

See **rule 38**. `synchronizeCatalog`'s post-apply rebuild had never run while the tombstone was
throwing above it; the moment the sync was repaired it ran and dropped the local host, which is
inserted into the projection rather than living in the catalog. `rebuildProjection()` is now the one
composer. Proven by defeating it: the test fails with *"This Mac disappeared when the sync applied a
record."*

## Stage 5 — what is left, in order

1. **The remote directory reader.** `GlassEditorDirectoryReader` has one implementation. Until
   there is a second, a project on another machine draws an empty tree and the editor is local-only
   — which removes the only reason it belongs in this app. Cheapest correct shape is the one the
   database already uses for tunnels: **the composition root hands the editor a closure the terminal
   implements**, so neither module imports the other. The real work is sessions: opening a project
   later means connecting to that host on demand rather than borrowing a browser window's session.
2. **Persisting projects.** `projects` is in-memory and dies with the window. Local persistence is
   small; making them *sync* means carrying them in the catalog, which is a schema addition to
   `HostProfile` — deliberate work, because every device decodes that record.
3. **"Open in Editor"** in the SFTP browser's context menu — three lines once (1) exists.
4. Project-wide search by running `rg --json` on the far machine.
5. Git status in the tree from `git status --porcelain=v2`.
6. **Server-side LSP**: run the language server on the remote host over an SSH exec channel and
   speak LSP across its stdio. The engine's `CompletionProvider`, `DiagnosticsProvider` and
   `StatementBoundaryProvider` are already the seam — nothing needs re-architecting, something needs
   to conform. Two to three weeks, and it is the differentiator no iPad editor can match.

**The editor has no entry point on iOS or visionOS.** macOS has ⇧⌘E and File ▸ New Editor Window;
the other platforms have the scene and nothing that opens it. The fix is to contribute the editor as
a **library panel** beside SSH Keys and Workgroups — the results column is the document and project
list, the detail column is the text, which is the shape the panel mechanism already gives.
