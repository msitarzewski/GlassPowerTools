# Stage 3 W-capability — glassdb's app files moved in as `GlassDatabase`

Owner W-capability. 2026-09-12. Wave 2 of the
[Stage 3 plan](2026-09-12_stage-3-database-plan.md). Builds on wave 1's
[kit move](2026-09-12_stage-3-kit-move.md), [forward broker](2026-09-12_stage-3-shell-forward.md)
and [floor sweep](2026-09-12_stage-3-floor-sweep.md).

**Status: all three stages done, D14 implemented, and proven against real servers; not committed.**
The capability is registered, the Database tab of the setup sheet is live, the scenes are declared,
and the connect path, the read-only guard and the D7 tunnel have each been exercised against the
VM's real MySQL 8.4.11 and PostgreSQL 18.6. Two defects found by that run are recorded below, both
fixed. The MySQL tunnel is additionally proven against a cold `caching_sha2_password` cache; one
unexplained ~10s timeout remains open and is recorded in the live-run section.

## Stage 1 — what moved

20 of glassdb's 22 app files, into `Sources/GlassDatabase`, plus one file split out of
`glassdbApp.swift` — 21 files, 19,332 lines, against glassdb's 22 files / 22,244. The 2,912-line
difference is the two files not moved (1,474) and roughly 1,440 lines of SSH configuration,
credential handling, key catalog and settings pages excised below.

`Package.swift` gains a `GlassDatabase` target and a `GlassDatabaseTests`
test target beside the existing ones, depending on `GlassDBKit`, `GlassShell`, `GlassLayers`,
`GlassConnectionKit`/`UI`, `GlasSecretStore` and `GlassEditorKit` — **never `GlassTerminal`**, and
no longer `GlassHostCatalog` either, since the deletion outbox went (below).

| File | Disposition |
|---|---|
| `AIAssistant.swift` | moved; availability gate corrected to the 26.0 floor (below) |
| `ConnectionFormView.swift` | moved, SSH excised (below); becomes the service draft in stage 2 |
| `ConnectionManager.swift` | moved whole |
| `Constants.swift` | moved; `databaseHighVisibilityPriority()` deleted in favour of `GlassLayers` |
| `DatabaseDetailView.swift` | moved; the "SSH route" overview row is now a "Tunnel" row |
| `DatabaseSessionManager.swift` | moved; tunnel rewired onto the shell's forward (D7) |
| `DatabaseWorkspaceView.swift` | moved whole |
| `DataExporter.swift` | moved whole |
| `GlassEditorAdapters.swift` | moved whole |
| `KeychainManager.swift` | moved; every SSH credential path excised |
| `Logger.swift` | moved whole |
| `Models.swift` | moved; the connection record rewritten (below) |
| `QueryEditorView.swift` | moved whole |
| `RecordEditorView.swift` | moved whole |
| `ResultsGridView.swift` | moved whole |
| `SchemaBrowserView.swift` | moved whole |
| `SettingsManager.swift` | moved; the second SSH key catalog excised |
| `SettingsView.swift` | moved; SSH Keys and Appearance pages dropped |
| `SQLHighlighter.swift` | moved whole |
| `TableDetailView.swift` | moved whole (5,847 lines, untouched apart from one import) |
| `DatabaseIOSRouter.swift` | **new file**, holding `IOSAppRouter` split out of `glassdbApp.swift:133-153` |

**Not moved, deliberately:**

| Not moved | Why |
|---|---|
| `ConnectionManagerView.swift` (1,223 lines) | The shell's `GlassShellLibraryView` is the one library. Its `ConnectionManagerView.swift:756` also passes `lastConnected:` to a `GlassLibraryConnectionRow` initialiser that no longer accepts it — dead on arrival, not carried |
| `glassdbApp.swift` | The app entry is the shell's. Its `IOSAppRouter` moved (above); `IOSAppRoot` did not — hosting the library and the deep-link handler is the shell's job |
| Assets, entitlements, `Info-*.plist`, `MacAppIcon.icon`, `PrivacyInfo.xcprivacy` | The merged app has its own |

## What the move changed, and why

### The connection record (D7 + the missing version)

`DatabaseConnectionConfig` loses **all six** SSH fields — `useSSHTunnel`, `sshHost`, `sshPort`,
`sshUsername`, `sshAuthMethod`, `sshKeyID` — plus `sshCredentialPolicy`. In their place, one
boolean, `usesHostTunnel`: reach the database through the host's own Terminal service. Everything
the tunnel needs is already on that service.

The format also gains the version number the survey noted it never had.
`DatabaseConnectionConfig.currentSchemaVersion = 2`; a record with no `schemaVersion` is version 1
(glassdb's shape) and its `useSSHTunnel` migrates to `usesHostTunnel` on read. `encode` always
writes version 2, so encoding is the rewrite. The custom encoder is new — glassdb relied on the
synthesised one — because the version and the dropped keys need stating explicitly.

`CredentialStoragePolicy.glassdbOnly` is renamed `appOnly` with its raw value `"glassdbOnly"`
preserved, so a version-1 record still decodes.

### The tunnel (D7), end to end through the session manager

`DatabaseSessionManager.connect` takes an optional `PortForwardProvider`:

```swift
typealias PortForwardProvider = @MainActor (_ remoteHost: String, _ port: Int) async throws -> any GlassHostPortForward
```

When `usesHostTunnel` is set it calls `openForward("127.0.0.1", config.port)` and connects the
driver to the returned `localPort`. Loopback because the database is on the host's machine; the
plan's open sub-question (a database on a *different* machine reached through this host as a jump)
is answered the way the plan recommends — that is a second host with its own service.

The session owns the live forward (`DatabaseSession.hostTunnel`) and the provider
(`DatabaseSession.openForward`) so disconnect, reconnect, a transport-closing cancel and a failed
connect all tear the forward down with the socket, and `reconnect` can re-open it without the
recovery UI re-resolving the host. `TransportPlan` keeps glassdb's TLS rule intact: through a
tunnel the certificate is still checked against the machine's real name
(`requiredSystemTrustForHost`), never against loopback.

Stage 3 supplies the provider from `GlassCapabilityHostAccess.forwardPort`, so the capability
never learns which other capability served it. When a service asks to tunnel and the machine has
nothing to tunnel through, the connect fails with an explanatory error rather than pretending:
there is no silent fallback to a direct connection and no silent success.

### The security review's `SecureBytes` finding is resolved by deletion, not by a fix

The survey's `DatabaseSessionManager.swift:131-132` downgrade of `SecureBytes` to `String` was the
SSH private key and passphrase being unwrapped to feed `SSHTunnelConfig`. That whole path left with
the tunnel. `grep` for `SecureBytes` and `toUTF8String` across `Sources/GlassDatabase` returns
nothing.

### Credentials: a database service now holds exactly one secret

Removed from `KeychainManager`: `saveSSHPassword` / `retrieveSSHPassword` / `deleteSSHPassword`,
`saveSSHKey` / `retrieveSSHKey` / `deleteSSHKey`, `saveHostKey` (host-key pinning),
`sharedSSHCompatibilityAccount`, `legacySSHAccount`, the SSH half of `saveCredentials` and of the
credential migration. `saveCredentials` no longer takes an `sshPassword`.

`deleteCredentials` **gained** work: a version-1 record may still have an SSH password glassdb
wrote, so deleting a service now sweeps the SSH account under all three descriptors. This app never
writes one, but it must not leave one behind.

### One SSH key catalog, one Appearance page, one visibility guard

- `SettingsManager`'s SSH key catalog (`glassdb/SettingsManager.swift:347-664`) and
  `SettingsView`'s SSH Keys page and `AddSSHKeyView` (`SettingsView.swift:320-579`) are **not
  carried**. `GlassTerminal`'s Connections settings page already owns the one catalog
  (`Sources/GlassTerminal/SettingsView.swift:181`).
- The Appearance page is dropped; the shell owns appearance.
- `Constants.swift:663`'s `databaseHighVisibilityPriority()` is deleted and its two call sites now
  use `GlassLayers.glassKeepVisibleWhenCompact()`.

### The AI assistant's availability gate

Five `guard #available(visionOS 27.0, macOS 27.0, *)` sites now read
`#available(iOS 26.0, macOS 26.0, visionOS 26.0, *)`, and the `unsupportedOS` message with them.
`SystemLanguageModel` is available from 26.0 on all three, and the product's floor is 26.0, so the
gate now names the floor. **This is a behaviour change, not a cleanup:** the old `*` resolved to
the iOS deployment target, so the assistant worked on iOS and was dark on macOS 26.x and
visionOS 26.x. It is now available on all three. Compiled, not exercised — no device run yet.

### The Keychain service prefixes keep their `app.glassdb` names — deliberately

`KeychainManager.swift:155,160,166` still name `app.glassdb`, `app.glassdb.private` and
`app.glassdb.protected`. **Do not tidy these.** The shared configuration's access group
`sh.glas.shared` is the one an existing glassdb installation already wrote into, and the service
name is the other half of the lookup: keeping both is what lets the merged app read a database
password glassdb saved. Renaming them would silently orphan every existing secret.

User-visible copy naming "glassdb" is a different matter and was changed (twelve strings across
six files: the SQLite import explanations, the connection-failure and recovery messages, the
statistics-unavailable text, a settings section header and an accessibility hint).

### The defaults keys keep their `glassdb.` namespace

`UserDefaultsKeys` is carried verbatim. `UserDefaults.standard` is per bundle identifier, so a
`com.glasspowertools` build starts with none of an existing glassdb installation's data; the old
key strings are the only handle a later import would have, and renaming them would gain nothing and
lose that. **Consequence to record: saved database connections do not migrate from glassdb by
themselves.** The Keychain and the App Group do carry over; `UserDefaults.standard` does not.

## Verification

Stage 3 additions to the table below: the app target builds and links `GlassDatabase`; the
`GlassDatabase` scheme still builds on all three platforms; and
`GlassShellLibraryUITests.testAddHostWithTerminalInOneSheetThenConnect` **passes on macOS against
the real app**, which is the first evidence that the Database tab is genuinely live — the toggle is
enabled and the engine, database, username and password fields render in the shell's own sheet.

**Still not proven, and it is the important one:** no database has been connected to. The connect
path, the D7 tunnel and the read-only guard against a real server are all compiled and unit-tested
only. The VM's MySQL 8.4.11 and PostgreSQL 18.6 exist for exactly this and have not been pointed at.

| Check | Result |
|---|---|
| `swift build` (whole package) | **passed**, no errors |
| `xcodebuild -scheme GlassDatabase`, `generic/platform=` macOS, iOS, visionOS | **BUILD SUCCEEDED** on all three, 0 errors |
| `xcodebuild -scheme GlassPowerTools`, `generic/platform=` macOS, iOS, visionOS | **BUILD SUCCEEDED** on all three, with `GlassDatabase` linked and the capability registered |
| `Tests/GlassDatabaseTests` | **45 tests / 7 suites passed** (34 offline + 11 live) |
| `swift test` (whole package) | **591 tests passed**, 0 failures (514 before this work). The live tests skip without `GPT_DB_TEST_*` set |
| `xcodebuild test -only-testing:GlassPowerToolsUITests` (macOS) | 19 tests: **18 passed, 1 failed.** Measured **before W-local began**; see the note below on why it was not re-measurable afterwards. The failure is `GlassShellTagFieldUITests.testCollectionsAreChipsAndFeedTheSystemWideVocabulary` ("the Clients collection appears in the sidebar"), which belongs to the in-flight tag vocabulary work. **Isolated, not assumed:** it reproduces identically with the database capability unregistered and the bootstrap removed, so it is not caused by this work. Every terminal and library test passes |
| `GlassShellLibraryUITests.testAddHostWithTerminalInOneSheetThenConnect` | **passed** — the Database tab is enabled and its four required fields render in the shell's own sheet, against the real app |
| Live round trip against the VM | **12 tests, all passed, 0 known issues** — see the live-run section below |
| The corrected AI availability gate | **compiled on all three platforms, not exercised.** No device or simulator run |

The 12 tests are not a smoke screen for the move: six cover the record's version-1 → version-2
migration (the intent carrying while the five SSH fields do not, the rewrite dropping them from the
JSON, the renamed policy still decoding `"glassdbOnly"`, a shared database policy normalizing to
private), and six cover the transport plan (direct, tunnelled to loopback, TLS through a tunnel
still checked against the machine's real name, a tunnel with no local port refused, SQLite refusing
both, and a tunnelling service with no forward provider failing with a message and leaving no
session behind).

## Stage 2 — the capability contract

Four new files. Nothing is registered with the shell yet; that is stage 3, and registering before
the scenes exist would give the user a Connect button that enqueues a request nobody consumes.

| File | What it is |
|---|---|
| `DatabaseServiceDraft.swift` | `GlassServiceDraft` for `.database`: fields, validation, and the commit that writes the record and its password under the shell's endpoint id |
| `DatabaseServiceFields.swift` | The rows the draft contributes to the setup sheet, laid out to match `ServerFormViews.swift:431-780` so both tabs read as one sheet |
| `GlassDatabaseCapability.swift` | `GlassCapability` + `GlassDatabaseRuntime` (the process's managers and its request queue) |
| `ReadOnlyDatabaseConnection.swift` | The read-only guard, on the connection (below) |

**Fields, as the plan specifies.** Required: engine, database, username, password. Advanced: name,
port, TLS, read-only, rows per page, colour tag, and D7's single tunnel switch. **No SSH fields and
no address** — `validate(address:)` takes the host's address and the draft never stores one. SQLite
needs only its file: no address, no port, no credentials, no TLS, no tunnel, and its `host` is the
managed file path rather than a machine.

**Read-only is enforced on the connection, not in the UI.** Five of the app's write paths call the
driver directly rather than going through `DatabaseSessionManager.executeQuery` —
`SchemaBrowserView.swift:518` (truncate and drop), `TableDetailView.swift:3966` (row update),
`:4060` (pasted range), `:4146` (insert), `:4756` (schema change). A guard at the session manager
would have left every one of them open, so `ReadOnlyDatabaseConnection` wraps the connection at
connect time and classifies each statement before it reaches the wire. Session control (`USE`,
`SET`) passes because it selects what you are reading; `unknown` is refused, because a statement the
classifier cannot read is not evidence that it is safe. Metadata, `EXPLAIN` and transactions pass —
a read-only service is still fully browsable.

**Two fields added to the record for this:** `isReadOnly` and `rowPageSize` (nil means follow the
app's setting; clamped 1…10,000 on read as well as in the UI, so a hand-edited value cannot become
a page size the grid will not render).

**`symbolName` is an SF Symbol, deliberately not `"circle-stack"`.** The database's real icon is the
vendored Heroicon, returned by `GlassServicePresentation.symbol(for: .database)`. But the shell
feeds names of this shape straight to `Image(systemName:)` (`GlassShellLibraryView.swift:214`),
where `"circle-stack"` would render nothing at all, so the capability's property is
`"cylinder.split.1x2"` and the vendored icon stays canonical.

**Verified:** 30 tests / 4 suites pass. The 18 added here cover the required four, the address
coming from the host, port and page-size bounds, SQLite needing only its file, engine-change resets,
the advanced switches reaching the record, the derived service name, an edit keeping its saved
password, focus landing on the first problem — and the read-only guard driven the way the five
direct callers drive it, asserting that nothing refused ever reaches the driver.

## Stage 3 — the scenes, and the capability registered

`GlassDatabaseScenes.swift` carries glassdb's two remaining window scenes
(`../glassdb/glassdb/glassdbApp.swift:56-99`) — the workspace and the detached results grid —
renamed `database-workspace` and `database-results` so they cannot collide with the terminal's.
Its Connections window and Settings scene did not come: the shell owns both.

`GlassDatabaseBootstrap` is the mirror of `GlassTerminalBootstrap` and the reason the capability
needs no environment of its own. A capability cannot reach `openWindow`, so `open` enqueues on the
runtime and the bootstrap — wrapped around the shell's library window — drains the queue, connects,
opens the workspace, and shows the failure alert when a link has nothing behind it. `report` is
called exactly once at the attempt's terminal state, so the shell stamps "last connected" only on a
real connection.

**Registered** in `App/GlassPowerToolsApp.swift`: one runtime sharing the shell's `GlassLayerStore`,
`model.registry.register(GlassDatabaseCapability(runtime:))`, the bootstrap around the library, and
`GlassDatabaseScenes` beside `GlassTerminalScenes`.

**The Xcode project needed one edit.** The app target links SwiftPM products explicitly, so adding
`import GlassDatabase` without adding the product failed with a Clang dependency-scanning error
about `_NumericsShims` rather than anything legible. `GlassPowerTools.xcodeproj/project.pbxproj`
gains the `XCSwiftPackageProductDependency`, its build file and the two references, matching how
`GlassTerminal` is declared.

**One existing UI test changed, because its subject did.**
`UITests/GlassShellLibraryUITests.swift:223-241` asserted the Database tab's toggle was *disabled*
("no capability: the tab's toggle is disabled"). That is no longer true, so it now asserts the
opposite and that the four required fields render. It also uses the suite's `press()` helper rather
than `tap()`: `tap()` compiles on macOS but does not drive a SwiftUI toggle there (project rule's
macOS `click()` quirk) — the first run failed on exactly that.

**The shell's `unavailableNote(for: .database)` still reads "Database services arrive in Stage 3."**
(`Sources/GlassShell/GlassShellSetup.swift:446`). It is unreachable in this build, since the note
only shows when no capability owns the kind. Left alone: it is the shell's file and W-local is in
it. Worth a one-line fix by whoever owns it next.

## D14 implemented — the tunnel asks instead of refusing

Built after stages 1–3, on the coordinator's approval and with `resolveHostTrust`'s shape as they
specified it. The interim `trustDecider: nil` refusal is gone.

**The connect path needed no new protocol hook**, as analysed: `forwardPort` is already `async` and
main-actor isolated, so prompt-and-retry fits the contract as written. `openPortForward` now passes
`BrokeredHostTrustDecider`; the transport's own loop (`SSHTransport.swift:171-191`) pins on
`.trust(remember: true)` and retries, so nothing here reimplements pinning.

**One prompt, two sources.** `TerminalHostTrustBroker` carries a challenge from a session-less
caller to the terminal's existing alert (`TerminalConnectFlow.swift:60-88`) and the answer back.
The alert, its wording and its destructive styling for a changed key are untouched;
`TerminalHostTrustDecider`'s capture-reject-retry semantics for the terminal's *own* path are
untouched. The broker presents one request at a time and queues the rest — two fingerprint
comparisons on screen at once is worse than making the second wait — and a session's own challenge
is never displaced by a brokered one.

**Strict mode is honoured without a prompt ever appearing.** The broker is constructed with the
user's `hostKeyVerificationMode`; when it is not `.ask`, `ask` returns `.reject` immediately and
stages nothing. `hostNotTrusted` remains the fallback, now meaning "declined, or could not ask"
rather than "never asks".

**Setup-time resolution** (`resolveHostTrust(host:)`): an already-pinned machine is answered from
the trust store without touching the network, so the sheet may call it unconditionally. Otherwise
it connects far enough to be offered the key, lets the prompt settle it, and drops the transport —
a trust decision, not a session. The database's tunnel row calls it when the switch goes on and
reports what came back.

**The three outcomes stay three.** `.declined` is the user saying no; `.unavailable` is nobody to
ask. Flattening them would have hidden a changed host key behind the same answer as "no SSH service
here". Per the coordinator's wrinkle, the one-and-done sheet's create-everything case returns
`.unavailable` — at the moment the tunnel switch flips there is no committed SSH service to
challenge — and **no outcome blocks Save**, which is asserted rather than assumed.

**One visibility change was needed:** `GlassShellModel.hostAccess(for:)` became `public`. The
composition root has to hand the access to the database runtime — a capability must not hold the
model — and the app target is a separate module. The accessor is read-only and already returned a
public type.

**Files touched outside `GlassDatabase`**, all of them the coordinator's explicit assignment:
`Sources/GlassShell/GlassCapability.swift` (the outcome enum, `resolveHostTrust` on both the access
struct and the protocol, with the refusing default), `Sources/GlassShell/GlassShellModel.swift`
(the resolver, nil on exactly the conditions the forward is, plus the visibility change),
`Sources/GlassTerminal/`
(`TerminalHostTrustBroker.swift` new, `GlassTerminalCapability.swift`, `TerminalConnectFlow.swift`).

**16 new tests, 560 passing overall.** Six on the shell hook (resolved through the SSH capability,
declining kept distinct, no service / no capability / unadopted hook all `.unavailable`, and trust
and forward resolving on the same conditions); six on the broker (accept, decline, strict mode
never prompting, queue order, a changed reason surviving, and `cancelAll` stranding nobody); four
on the draft (settles at setup, create-everything is `.unavailable`, declining still saves, no
outcome blocks Save).

**Not proven:** no fingerprint has been compared by a human, and no forward has been opened against
a real machine. The prompt is compiled and its broker unit-tested; the flow through SwiftUI is not.

## The deletion outbox is gone — it would have written into the shipping glassdb's directory

`ConnectionManager.swift:175` constructed `.applicationSupport(applicationIdentifier: "app.glassdb")`.
Removed on the coordinator's instruction, and the reason is worse than redundancy: this app is not
sandboxed on macOS, so that outbox would have written into `~/Library/Application Support/app.glassdb/`
— the still-shipping glassdb's own directory, which has to keep working until parity. The shell owns
catalog deletion now. `GlassHostCatalog` is no longer imported by this module at all.

## The live run — against the VM's real MySQL 8.4.11 and PostgreSQL 18.6

`Tests/GlassDatabaseTests/LiveDatabaseIntegrationTests.swift`, gated on `GPT_DB_TEST_*` (and
`GPT_SSH_TEST_*` for the tunnel) so a checkout without the environment skips rather than fails.
Credentials live in `~/.config/gpt-db-test.env`, outside the repository, and appear in no file,
note or assertion message. **Nothing in this file writes to either database:** every test reads, or
proves a write was refused.

| What was to be proven | Result |
|---|---|
| 1. Direct connection to both engines through the capability | **passed** — both connect through `DatabaseSessionManager.connect` and report real server versions; disconnect tears the session down |
| 2. Schema browser: seeded tables and the foreign key | **passed on both**, after the run exposed two defects in PostgreSQL foreign keys that are now fixed and guarded — below |
| 3. A query returning real rows | **passed** — both engines, through `executeQuery` |
| 4. **The read-only guard refusing a real write at the wire** | **passed on both engines** — and the part that matters: the rows are *read back afterwards through a separate session* and are byte-for-byte unchanged |
| 5. The tunnel through `forwardPort` | **passed on both engines** — a genuine `-L` forward over SSH, the driver connecting to the OS-assigned local end, returning real rows. MySQL additionally **proven against a cold `caching_sha2_password` cache** by W-vm; one unexplained timeout remains open, below |

Item 4 is the one worth the trouble. The refusal is exercised **both** through the session manager,
as the query editor would, **and straight at `connection.execute`**, as the grid, record editor and
schema tools do — the route a guard in the session manager would never have seen. Then the fixture
is re-read through an ordinary session and compared. It also holds **through the tunnel**, which is
the combination a user with a production database would actually be in.

### The MySQL tunnel: proven cold, with one unexplained timeout — and a retracted mechanism

**Proven cold.** W-vm flushed the `caching_sha2_password` cache at `05:39:28Z` and stayed off the
server; the first `gpt_test` connection after the flush was the Swift tunnel test, and
`MySQL over a real SSH forward` **passed in 0.072s**, with all three tunnel tests green. Cold
`caching_sha2_password` full authentication over our forward works — which also settles W-kit's
open question about mysql-nio's RSA exchange against swift-crypto 4.5.2, the path this merge
created and glassdb never ran. (Evidence: W-vm's controlled flush and run, not this worker's. The
account-keying claim below **is** this worker's, checked directly.)

**Still open, and smaller:** two runs of that test failed at almost exactly 10s —
MySQL's `connect_timeout` — with `Got timeout reading communication packets`, and are unexplained.
The leading hypothesis is contention: this worker's 12 live tests were running against the same
MySQL and the same sshd as the coordinator's while W-local was building. W-vm is pulling the server
error log for `05:15Z–05:25Z` to see whether the timeouts cluster with a burst of connections.
**A hypothesis, not a finding** — recorded that way deliberately, for the reason below.

**Retracted: the source-address mechanism this section previously gave.** An earlier version of
this note stated that MySQL keys the `caching_sha2_password` cache by client address, so a
connection arriving through a forward as `127.0.0.1` would be a different cache entry from the
direct path, and concluded that every green tunnel run might be a warm-cache artefact. **That
mechanism is wrong**, and the withdrawal built on it is retracted with it.

Checked directly against the server rather than taken on report — the same `SELECT` run twice, once
straight from this machine and once through an `ssh -L` forward:

| Path | `USER()` — where the connection appears to come from | `CURRENT_USER()` — the account it matched |
|---|---|---|
| Direct | `gpt_test@192.0.2.2` | **`gpt_test@%`** |
| Through a forward | `gpt_test@localhost` | **`gpt_test@%`** |

The apparent origin differs; **the matched account is identical**, and that is what
`caching_sha2_password` keys its cache by — so both paths share one entry and a forward cannot have
a cold entry while the direct path has a warm one. The loopback connection matching `@%` rather
than a `@localhost` account also demonstrates no more specific account exists, which is the other
half of the claim. `CURRENT_USER()` against `USER()` is the cheap check for this, and it needs no
privilege on `mysql.user`.

It is worth recording *how* that got here, because it is the more useful lesson. The mechanism was
offered as an explanation, sounded plausible, was not checked against the server, and this worker
wrote it into the durable record within the hour — where it would have misled whoever read it next
and, worse, would have taught them to distrust a result that was sound. A confidently stated
mechanism travels further and faster than a known unknown, which is why the timeout above is left
as an open question rather than given an explanation it has not earned.

One thing that survives intact: these tunnel tests take the forward from
`SSHTransport.forward(localPort: 0, …)` directly rather than through
`GlassTerminalCapability.openPortForward`, so they are a reproduction path that skips the
capability layer. If the contention theory fails, that is the next tool for isolating whether
anything above the transport is involved.

Item 5 exercises D7's real seam: the session manager asks for a forward, something else entirely
opens it, and the driver connects to the local end. The forward is built in the test rather than
imported, because `GlassDatabase` must never import `GlassTerminal` and the test is held to the
same rule. The local end is asserted to be a fresh OS-assigned port, not the database's own.

### Two defects this run found in `PostgreSQLAdapter.foreignKeys` — both now fixed

The first was found by the assertion failing; the second by investigating **why**, which the
coordinator asked for as "a query fix or something deeper". It is a query fix, and it is confined
to this one call — but the query was wrong in two independent ways.

**1. Foreign keys were invisible to any account that did not own the table.** The adapter
inner-joined `information_schema.constraint_column_usage`. Read from the server's own view
definition rather than from documentation:

```
constraint_column_usage:  WHERE pg_has_role(tblowner, 'USAGE')
```

The table's **owner**, with no privilege branch — a GRANT of SELECT is not enough. The constraint
was visible in `table_constraints` and absent from `constraint_column_usage`, so the inner join
dropped it and the Foreign Keys tab rendered empty, indistinguishable from a table with none. That
is the ordinary shape of an application or analyst account, and D9's foreign-key navigation is
built on this call.

**Audited the rest of the adapter for the same class of bug — there is none.** Each checked
against the live server as the non-owning account, not assumed:

| Call | Reads | Non-owning account |
|---|---|---|
| `databases()` | `information_schema.schemata` | **fine** — `WHERE pg_has_role(…) OR has_schema_privilege(…)`; the privilege branch saves it |
| `tables(in:)` | `information_schema.tables` | **fine** — returned `teams`, `members` |
| `columns(in:database:)` | `information_schema.columns` + `table_constraints`/`key_column_usage` | **fine** — primary key correctly detected |
| `indexes`, `tableStatus`, `showCreateTable` | `pg_catalog` | unaffected |
| `foreignKeys(in:database:)` | `constraint_column_usage` | **the only owner-scoped view in the adapter** |

**2. Composite keys came back as a cross product — confidently wrong, not merely missing.** The old
query joined the referenced columns with no ordinal correlation. Proven on a two-column key against
a table the account *owned*, so privileges were not the cause:

```
(x, y) → (a, b)   expected 2 rows          got 4 rows
                  x→a, y→b                 x→a, x→b, y→a, y→b
```

It asserted relationships that do not exist. Foreign-key navigation built on it would have followed
the wrong column. `conkey` and `confkey` are positionally paired arrays, so unnesting one
`WITH ORDINALITY` and indexing the other by it is what actually pairs them.

**Fixed** by the coordinator in `Sources/GlassDBKit/PostgreSQLAdapter.swift`, reading `pg_catalog` —
the pattern `tableStatus` and `indexes` in that adapter already use. Both defects are now guarded by
live tests: the seeded-fixture assertion covers the privilege case (the fixture is owned by
`postgres` and the test account is deliberately not the owner — **do not "simplify" the seed to make
it pass; that account shape is the condition under test**), and a new composite-key test covers the
pairing, creating and dropping its own tables in `gpt_scratch`.

MySQL was never affected: its query is privilege-filtered and returned the key correctly throughout.

### One flaky test, named rather than ignored

`GlassTerminalTests/MacWorkspaceTests.incomingDropRetainsProviderFileAndCleansOwnedStaging` failed
once during a full run and passed on every run since, alone and in the suite. It asserts a staging
directory was removed, and it ran while another worker's suite and the live database tests were
running concurrently, so temp-directory contention is the likely cause. It is unrelated to this
work — nothing here touches drag-and-drop staging — but it is a real flake and someone should own
it rather than rediscover it.

### Why these numbers are dated, and what that means

Every result above was taken before W-local's D8 work began. A re-run of the macOS UI suite
afterwards showed three failures rather than one, and **none of them is a regression in this
work**: `swift build` fails outright at `Sources/GlassShell/GlassShellSetup.swift:114` ("missing
return in getter") while that file is being written, and `GlassShellLibraryView.swift` references
`addableKind` and `GlassShellSetupModel.setupKinds(for:registry:)` from the same in-flight change.
`GlassDatabase`'s own errors in that state are all the same file cascading.

Recorded rather than papered over: a shared working tree means a red build is not evidence about
whoever measured it last. The gate for this work is wave 4's integration run on a settled tree.

## Open, and owned

- **The two blocking `deinit`s are closed**, by the coordinator, in their own module: both adapters
  now take `MultiThreadedEventLoopGroup.singleton` and the `deinit`s are deleted outright rather
  than made async. The survey said three; the third was `SSHTunnelManager`'s and left with it.
- **The command palette is duplicated.** `Constants.swift` carries glassdb's `MacCommandCenter` /
  `CommandPalettePanel`, and `Sources/GlassTerminal/macOS/MacWorkspaceCommands.swift:285` carries
  glas.sh's. Both are internal to their modules, so nothing collides — but they are two
  implementations of one macOS-wide surface, and the database's dynamic entries cannot reach the
  terminal's `macCommandCenterEntries` focused-scene key without a shared home. Extraction into
  `GlassLayers` or `GlassShell` is cross-module and wants its own task.
- **PostgreSQL `databases()` returns schemas.** Carried as-is so far; the browser's dialect switch
  (`SchemaBrowserView.swift:112`) already relabels the title, but the honest modelling the plan
  asks for is not done.
- **`ConnectionFormView` is still glassdb's sheet, minus SSH.** It compiles and its validation,
  field rows, password control, SQLite import and config building are intact, but it is still a
  `@State`-driven `View` with its own Cancel/Save/Test chrome. Stage 2 turns it into a
  `GlassServiceDraft` (an `@Observable` class supplying `requiredFields()` / `advancedFields()`),
  which is where its remaining glassdb-shaped parts — the "Name" field the shell derives, the
  Save & Connect button, the `openWindow` call — resolve.
- **The managed SQLite directory is still named `glassdb`** (`ConnectionFormView.swift:47`:
  `Application Support/glassdb/SQLite Databases`). Harmless — Application Support is per bundle, so
  nothing existing lives there — but it will read oddly in a fresh install. Left alone rather than
  churned, since stage 2 touches this file anyway.
- **Appearance settings values** (`windowOpacity`, `blurBackground`) still live in this module's
  `SettingsManager` and drive the database canvas, with no page to change them. W-settings folds
  them onto the shell's `GlassLayerStore`, the way `GlassTerminal`'s `SettingsManager(…layers:)`
  already does.
