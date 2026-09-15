# The remaining work, planned

Owner: coordinating agent. 2026-09-14. **Status: PLAN. Nothing built from this note yet.**

Authorization: *"Please create a thorough plan for the remainder of the work. Reuse is essential,
we're working on a professional and public codebase. Be precise in your edits."* D26 itself is
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

**The magic directive** — *"familiar to a Mac user, but visionOS magic to use"* (2026-09-13), with
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

Authorized: *"Word given."* Nothing committed; the user commits.

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

Authorized: *"clean the old test files."* Done 2026-09-14, on this Mac only — nothing in the
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
