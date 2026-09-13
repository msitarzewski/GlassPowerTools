# R7 / R8 — trusting a self-signed database certificate, and two validation gaps

Owner **W-tls**, 2026-09-12. Stage 3, wave 3. Closes **D13**; closes one of R8's two validation
gaps and closes most of the other.

**Authorization.** Wave-3 assignment from the coordinator: R7 (D13) plus R8's `text`/`blob` byte
limits and PostgreSQL array formats. Local edits and tests only. **Nothing committed.**

---

## 1. What D13 asked for, and what it got wrong

D13 is right about the mechanism and right about both halves being needed. Two corrections:

**D13 says "the app never constructs `.requiredCertificates`" and cites a grep of
`../glassdb/glassdb/`.** That grep was of the *source* app. Re-run against this tree,
`grep -rn requiredCertificates Sources/GlassDatabase/` also returns nothing, so the finding
survives the port — but it had not been checked here, and the two are different claims.

**D13 does not say that `ConnectionFormView` is dead.** `grep -rn ConnectionFormView Sources/
App/ Tests/ UITests/` returns its own file and three doc comments pointing at glassdb's original —
**no call sites**. So "the connection form has a Use TLS toggle with nothing that accepts a
certificate" (the plan, R7) describes a form the merged product never presents. The live surface is
the shell's setup sheet (`DatabaseServiceFields.swift`). This matters for where the work goes: the
TLS section was added to the sheet and deliberately **not** to `ConnectionFormView`, because a
second place that decides transport security is rule 18's mistake in a new spot.

**Deleted, with the coordinator's ruling, after R7 landed** — in two steps so the tree was never
red for long. `SQLiteFileImporter` moved verbatim to `Sources/GlassDatabase/SQLiteFileImporter.swift`
first: same module, still internal, so none of its three callers (`DatabaseServiceDraft`,
`DatabaseSessionManager`, `ConnectionManager`) changed. Then the 1,295-line
`ConnectionFormView.swift` was removed.

What was checked before removing it: the file declared exactly two top-level types
(`SQLiteFileImporter`, `ConnectionFormView`), one `private extension View`, and four types nested
inside the view (`Mode`, `FormField`, `ValidationInput`, `TestResult`). Every one of the
extension's six members and every nested type was grepped across `Sources/`, `Tests/`, `UITests/`
and `App/`: no references. The two apparent hits were false — `ValidationInput` is GlassTerminal's
own nested type in `ServerFormViews.swift:126`, and `TestResult` matched an unrelated
`tailscaleTestResult` variable. Package builds; full suite green after.

Everything else in D13 held up, including the part that is easy to disbelieve: NIOSSL refuses the
CN as a *string*, before any socket, and the fix is a mode that matches no name at all.

---

## 2. The policy, and what each mode does and does not verify

`DatabaseTLSPolicy` (`Sources/GlassDBKit/DatabaseProtocol.swift:78-110`) gains one case:

```swift
case requiredCertificatesWithoutHostnameVerification([DatabaseTLSCertificate])
```

**A separate case, not a reinterpretation of `serverName: nil`.** On `.requiredCertificates`,
`serverName: nil` already means "match the host I am connecting to"; redefining it as "match
nothing" would have been one line and would have silently weakened every existing call site.
`nilServerNameStillMeansMatchTheConnectionHost` in `Tests/GlassDBKitTests/GlassDBKitTests.swift`
exists to keep it that way.

| Policy | Chain verified against | Server's name checked | An attacker who can redirect the connection |
|---|---|---|---|
| `.disabled` | — | — | reads and rewrites everything |
| `.requiredSystemTrust` | system roots | yes, against the connection host | needs a certificate for *this name* from a public CA |
| `.requiredSystemTrustForHost(name)` | system roots | yes, against `name` (the machine's real name behind a tunnel) | same |
| `.requiredCertificates(_, serverName:)` | the supplied roots only | yes | needs a certificate for this name **from that private CA** |
| `.requiredCertificatesWithoutHostnameVerification(_)` | the supplied roots only | **no** | needs **any** certificate from that CA — so a second machine issued by the same CA can take this connection undetected |

The last row is the whole cost of the mode and is said in those words in the sheet. What it still
stops: anybody who cannot produce a certificate from that authority, which is every off-path
attacker and every on-path one without the CA's signature. It is MySQL's `VERIFY_CA` and
PostgreSQL's `sslmode=verify-ca`, neither more nor less.

**No automatic downgrade, anywhere.** Nothing in the engine or the app reacts to a failed
handshake by verifying less. `DatabaseSessionManager.transportPlan` chooses one policy from the
record and there is no retry path (D13's own correction, re-checked). The weaker mode is reachable
only by a user selecting it by name in the sheet, having read what it gives up.

### Where the mapping lives

The policy-to-NIOSSL switch existed twice, identically, in `MySQLAdapter.makeTLSConfiguration` and
`PostgreSQLAdapter.makeTLS`. It is now once, in
`Sources/GlassDBKit/DatabaseTLSConfiguration.swift`, and both adapters delegate
(`MySQLAdapter.swift:99-105`, `PostgreSQLAdapter.swift:62-72`). Two copies of a decision about what
is verified is one too many, and the new case would have had to be added to both.

`.noHostnameVerification` is NIOSSL's own: *"Certificates will be validated against the trust
store, but will not be checked to see if they are valid for the given hostname"*
(`.build/checkouts/swift-nio-ssl/Sources/NIOSSL/TLSConfiguration.swift:186-188`). The mode returns
`serverHostname: nil` as well — passing a name would set SNI while the configuration claims to
check no name.

---

## 3. Certificate import and storage

**Reused:** `Sources/GlassTerminal/SSHPrivateKeyImport.swift`, the house pattern for importing
trust material — refuse by size *before* reading, parse through the module that owns the format
rather than re-implementing it, hand the caller back facts for the form's state, keep nothing on
disk. `Sources/GlassDatabase/DatabaseCertificateImport.swift` is that shape for certificates.

**Parsing lives in GlassDBKit**, not the app: `GlassDatabase` does not depend on swift-nio-ssl
(`Package.swift:130-140`, which I must not edit), and adding that edge to show a fingerprint would
have put certificate parsing in two modules. `DatabaseTLSCertificate.inspect()`
(`Sources/GlassDBKit/DatabaseTLSCertificateInspection.swift`) returns the count, each certificate's
SHA-256 fingerprint and each validity window.

**Storage: the record, not GlasSecretStore.** A CA certificate is public trust metadata — the
server hands it to every client that connects — and `AGENTS.md`'s security rules say to keep
metadata separate from secrets. Inline in `DatabaseConnectionConfig.tlsCertificate` also means
there is no managed file beside the record to lose, to validate for directory escape, or to leave
behind on delete, all of which the SQLite import has to handle
(`SQLiteFileImporter.validatedURL(forPath:)`). Bounded at 64 KB at import and again in
`tlsCertificateMaterial`, so a hand-edited defaults plist cannot make the app read a megabyte of
anything as a trust root.

PEM and DER are told apart **by content**, not by the file's extension: a `.crt` may hold either.

The fingerprint is shown in the sheet as uppercase colon-separated hex — `openssl x509
-fingerprint -sha256`'s presentation, so it can be compared character for character against the
server. Deliberately **not** the `SHA256:<base64>` form the terminal shows for SSH host keys: that
is OpenSSH's presentation and this is compared against OpenSSL's. The reason for showing it at all
is the same as the terminal's: a pinned root is only as good as the out-of-band check on it.

---

## 4. Changed files

| File | What |
|---|---|
| `Sources/GlassDBKit/DatabaseProtocol.swift` | the fifth policy case; `verifiesServerIdentity` |
| `Sources/GlassDBKit/DatabaseTLSConfiguration.swift` | **new** — the one policy-to-NIOSSL mapping, shared by both adapters |
| `Sources/GlassDBKit/DatabaseTLSCertificateInspection.swift` | **new** — fingerprint, validity, count |
| `Sources/GlassDBKit/MySQLAdapter.swift` | duplicate switch replaced by delegation |
| `Sources/GlassDBKit/PostgreSQLAdapter.swift` | same |
| `Sources/GlassDatabase/Models.swift` | `DatabaseTLSVerification`; `tlsVerification` + `tlsCertificate` on the record; `tlsCertificateMaterial`, `certificateFormat(of:)`, `transportVerificationSummary` |
| `Sources/GlassDatabase/DatabaseCertificateImport.swift` | **new** — the file import |
| `Sources/GlassDatabase/DatabaseServiceDraft.swift` | the mode, the staged certificate, validation, reset on engine change |
| `Sources/GlassDatabase/DatabaseServiceFields.swift` | the three-mode picker, its explanation, the importer row, the fingerprint |
| `Sources/GlassDatabase/DatabaseSessionManager.swift` | the mode → policy mapping in `transportPlan`; `TransportPlan.tunnelRemoteHost`/`tunnelRemotePort` deleted |
| `Sources/GlassDatabase/SQLiteFileImporter.swift` | **new** — extracted verbatim from the deleted form |
| `Sources/GlassDatabase/ConnectionFormView.swift` | **deleted** — 1,295 unreachable lines (§1) |
| `Sources/GlassDatabase/ColumnTypeConstraint.swift` | R8 — MySQL's eight TEXT/BLOB byte limits, dialect-aware |
| `Sources/GlassDatabase/ColumnValueFormat.swift` | R8 — PostgreSQL array types |
| `Tests/GlassDBKitTests/GlassDBKitTests.swift` | D13's `withKnownIssue` removed; five new tests |
| `Tests/GlassDatabaseTests/DatabaseCertificateTrustTests.swift` | **new**, 10 tests |
| `Tests/GlassDatabaseTests/DatabaseServiceDraftTests.swift` | 5 new tests |
| `Tests/GlassDatabaseTests/ColumnTypeConstraintTests.swift` | 3 new tests |
| `Tests/GlassDatabaseTests/ColumnValueFormatTests.swift` | 4 new tests |
| `Tests/GlassDatabaseTests/DatabaseTransportPlanTests.swift` | 4 new tests; the dead-field assertions removed |
| `Tests/GlassDatabaseTests/LiveDatabaseIntegrationTests.swift` | 3 new gated tests against the real server |

`DatabaseConnectionConfig.currentSchemaVersion` stays at **2**. The two new keys are additive with
correct defaults, so no record needs rewriting to be read; bumping would have marked every existing
record as migrated when none was.

---

## 5. Verification

Against **MySQL 8.4.11** and **PostgreSQL 18.6** on the wave-1 test VM, over
`GPT_DB_TEST_*` (credentials never copied here).

| What | Result |
|---|---|
| `.requiredCertificates(CA, serverName: <the CN>)` against the real server | **throws**, as before — the CN is not a DNS name. Kept as an assertion: without it the next row proves nothing |
| `.requiredCertificatesWithoutHostnameVerification(CA)` against the real server | **connects** |
| the connection is really TLS, per the server | `SHOW SESSION STATUS LIKE 'Ssl_cipher'` → **`TLS_AES_128_GCM_SHA256`** |
| the assertion above actually executes | **proved**, not assumed — see below |
| `.requiredCertificatesWithoutHostnameVerification(<an unrelated self-signed CA>)` | **throws** — the chain is genuinely checked, so this is not "encrypt and trust anything" |
| `.requiredSystemTrust` against the self-signed server | **throws**, unchanged |
| empty / malformed PEM / malformed DER in the new mode, both engines | **throws before any socket** |
| SQLite refuses the new mode | **throws**, like every other required policy |
| a real DER certificate imports and matches its own PEM's fingerprint | **passes** |
| a **saved service** with the CA-only mode connects through `DatabaseSessionManager`, and `Ssl_cipher` is non-empty | **passes** — record → `transportPlan` → policy → real server, the end of R7 |
| the same saved service with the name-checking mode | **throws**, as it must |
| a saved pinned service with no certificate, against a reachable server | **throws**, and leaves no session behind |
| `swift test` (whole package) | **709 tests / 59 suites, all passing** at the last run (baseline 615/48; the total moves as other wave-3 workers land, so it is a floor, not a signature) |
| GlassDBKit alone | **26 tests / 3 suites**, including both live round trips |

**On that 0.1-second green.** `mysql8LiveRoundTrip` passes in ~0.1 s, which is too fast to trust on
its face for ~25 round trips plus four TLS handshakes (rule 19, rule 22). It was checked rather than
believed: the CA-only assertion was temporarily made to fail, which printed the cipher above and
proved the block runs. The VM is on a local Parallels network, so the timing is real. The probe was
reverted; the suite is green without it.

**D13's `withKnownIssue` is gone**, as it was designed to be: the wrapper would now report "known
issue was not recorded".

### What the suite cannot reach

- **One server, one certificate.** Verified against MySQL 8.4.11's auto-generated certificate. The
  PostgreSQL server on the VM is not running TLS, so the CA-only path is **not** exercised against
  PostgreSQL — the code path is shared and unit-tested, the live proof is MySQL's only.
- **No UI test.** The picker, the importer and the fingerprint row have accessibility identifiers
  (`add-database-tls-verification`, `-tls-certificate`, `-tls-certificate-choose`,
  `-tls-certificate-summary`) but no UI test drives them; rule 21 forbids a second macOS UI suite
  and one was running. Owed.
- ~~DER was tested only as malformed input.~~ **Closed:** a real DER certificate now imports and is
  asserted to produce the same fingerprint and validity as its own PEM form.
- **No chain file.** Multi-certificate PEM is handled and unit-covered by construction, not by a
  real intermediate chain.

---

## 6. R8 — the two validation gaps

### `text`/`blob` byte limits — **partly closed, and say so**

MySQL's eight families are now a table in `ColumnTypeConstraint.swift`, in **bytes**: 255 /
65,535 / 16,777,215 / 4,294,967,295 for the TINY/plain/MEDIUM/LONG forms of both TEXT and BLOB.
Bytes, from MySQL 8.4 §13.7's `L + n` storage with `L < 2^(8n)`; the manual's "65,535 characters"
is the ASCII case and it adds that the effective maximum is less with multibyte characters.
`usage(of:)` and `overflowMessage(for:)` already count `.bytes` as UTF-8, which is exact for
utf8mb4 and conservative for a single-byte charset — it can refuse a value the server would take,
never the reverse.

**The brief said this "needs the schema path". It does not: the declared type carries it** — the
type's own name is the family. What it needs instead is the **dialect**, for exactly two of the
eight names. Bare `text` and bare `blob` are also PostgreSQL's and SQLite's spellings, where the
limit is about a gigabyte, so applying 65,535 without knowing the engine would refuse values that
store perfectly well. `parse` therefore takes `dialect: DatabaseDialect? = nil`; the six MySQL-only
spellings work without it, the two ambiguous ones do not.

**Not closed, and not reportable as closed:** the dialect is not available at the call site.
`StagedEdit` (`RecordEditorView.swift:125-167`) carries no engine, and that file belongs to another
worker. Closing it needs a `dialect` field on `StagedEdit` and `:167` becomes
`ColumnTypeConstraint.parse(columnType, isUnsigned: isUnsigned, dialect: dialect)`. **Until that
lands, a plain `TEXT` column is still unbounded in the record editor.**

### PostgreSQL array types — **closed**

`ColumnValueFormat` gains `.array(elementTypeName:element:)`, recognising both spellings —
`integer[]`, `text[][]` (in PostgreSQL the same type as `text[]`, so every trailing pair is
stripped) and the internal `_int4`. The literal is checked for balanced braces, closed quotes and
complete backslash escapes, and **each element is then checked against its own type**, so `date[]`
inherits the date check that was added earlier today: `{2026-02-30}` is refused for the same reason
a bare `date` column refuses it. An unquoted `NULL` is the array null; a quoted `"NULL"` is the
four-character string and is checked as a value.

Deliberately not checked: that the dimensions are rectangular. The server enforces it, and it
cannot be decided without also deciding what an empty array means.

Rule 22, plainly: none of this has met a real PostgreSQL array column. The VM's fixtures have no
array columns, and the check is unit-tested only.

---

## 7. The mapping, and where the record travels

`DatabaseSessionManager.transportPlan` is **the one place** a saved service becomes a transport
policy, and it now covers the three modes. Applied by the coordinator while this note was being
written; the shape is the one proposed and the error messages are better — they name the service.
A pinned mode with no usable certificate **throws**; it never becomes system trust, because
falling back would change what the connection checks without telling anyone. The setup sheet
refuses to save such a record, so that guard is for one arriving from a hand-edited defaults plist,
a partial restore or a future migration. An oversized blob is refused by the same path, since
`tlsCertificateMaterial` returns nil for it rather than handing it to the parser.

`TransportPlan.tunnelRemoteHost` and `tunnelRemotePort` are **gone**. They were written at every
return and never read, and they read as the forward's target, which they are not: the forward is
opened with `openForward("127.0.0.1", config.port)` — loopback **as the host's machine sees it**,
which is the whole of D7. A later maintainer "correcting" the forward to use a remembered remote
host would silently break every database bound only to its server's own loopback. The two tests
that asserted the fields were populated are replaced by a comment saying why they are not.

Two things on that path were checked and are **correct as they stand**: TLS over a tunnel verifies
against `config.host`, the machine's real name, never loopback; and `MySQLAdapter.serverAdvertisesTLS`
opens a second forwarded connection before the real one, which is right because it receives the
tunnel's local end and therefore tests the endpoint the session will use. Three separate things on
that path time out at exactly ten seconds and are distinguishable only by their strings — the table
is in [the VM note](2026-09-12_stage-3-vm-databases.md) under "Read this before grepping the error
log". Read it before interpreting any TLS timeout here.

### Where the certificate travels, and what treats it as a secret

Nothing does, and that is deliberate. `grep -rn tlsCertificate Sources/` outside the model, the
importer, the draft and the fields returns exactly the two `tlsCertificateMaterial` reads in
`transportPlan`. There is no redaction wrapper, no `privacy:` annotation, no Keychain mirroring —
the connect log line (`DatabaseSessionManager.swift:156`) records host, port and username and never
the trust root. Half-treating a CA as a secret would be worse than either choice.

It travels wherever connection metadata travels: `DatabaseConnectionConfig` is JSON in
`UserDefaults` under `UserDefaultsKeys.connections`, written by `ConnectionManager.persist`. A CA
crossing that boundary is harmless — it is the certificate the server hands to every client that
connects, and it is public by construction. Written down here so the next person does not have to
re-derive it.

## 8. Other work owed

- The `StagedEdit` dialect in §6, to finish the `text`/`blob` limits. Routed by the coordinator to
  land after W-rows is clear of `RecordEditorView.swift`. **Until then, plain `TEXT` is still
  unbounded in the record editor** — six of eight is six of eight.
- `DatabaseDetailView.swift:398` summarises the transport from `(usesHostTunnel, useTLS)` and will
  say "TLS" without saying what is verified. `transportVerificationSummary` on the record exists for
  it. Not my file; not changed.
- A UI test for the three rows, when the machine is quiet (rule 21).
- PostgreSQL TLS on the test VM, so the CA-only path has a live proof on both engines.
