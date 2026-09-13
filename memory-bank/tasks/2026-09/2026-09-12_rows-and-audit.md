# Stage 3 — R2 row deletion, R3 foreign-key navigation, R4 the mutation audit

Owner **W-rows**. 2026-09-12. Scope assigned by the coordinator from
[the Stage 3 plan](2026-09-12_stage-3-database-plan.md) § "Remaining work, re-planned" → R2, R3, R4.

**Status: R2, R3 and R4 complete.** The two edits this task needed in files it does not own —
the `.glassdbOpenTable` observer in `DatabaseWorkspaceView.swift:376` (W-drafts) and
`MutationAuditRecord.predicate` in `Models.swift:534` (the coordinator) — have both landed and the
last inch is wired on this side. Nothing is committed.

Authorization: the coordinator's task message. Local editing and testing only; no commit, no `git
add`, no macOS UI suite (rule 21). Live work confined to `gpt_scratch`.

---

## What the plan got wrong, and what that changed

| Plan said | Actually | Consequence |
|---|---|---|
| R4: "there is no audit store; **decide** whether to build one or read `OSLogStore`" | **A real store already exists and eleven call sites already write to it.** `MutationAuditStore` + `MutationAuditRecord` + `MutationOutcome`, `Models.swift:388-445`, persisting a 1,000-record ring to `UserDefaults` key `glassdb.mutationAudit.v1` (`Constants.swift:30`). Added by W-capability in `3e6df40`, the port commit | R4 was never the decision the plan framed. What is missing is a **reader** and a **predicate field**. The coordinator's decision (a real store, not `OSLogStore`) stands — it is already the shape in the tree |
| R2: "one predicate path already exists", pointing at `TableDetailView.swift:781 static func predicate(...)` | That is the **browsing** filter behind SELECT and COUNT. The row-identity predicate lives inline in the two update paths | Corrected in the plan before work started, and the coordinator repeated the warning. Both predicates are now named types so the confusion cannot recur: `RowMutationSQL` writes, `GridServerQueryBuilder.predicate` browses |
| R4: "Mutation audit log is written but never readable" (D9 table) | True, but "written" meant written to **`UserDefaults`**, not to OSLog as the re-plan then claimed | — |

Two corrections in opposite directions on the same item. Both were found by reading the tree rather
than the plan, which is rule 18's point restated: the plan described an API's shape; the call sites
decided.

---

## R2 — row deletion

### Reused, not invented

The two existing write paths built the same `WHERE` inline: the primary key **plus every original
value of the row**, so a row changed underneath the user matches nothing. That block is now
`RowMutationSQL.identityPredicate` (`Sources/GlassDatabase/RowMutationSQL.swift:65`) and has three
callers instead of two copies and a third:

| Caller | Was | Now |
|---|---|---|
| single-row update | inline loop | `TableDetailView.swift:4046` |
| pasted-range update | inline loop | `:4145` |
| **deletion (new)** | did not exist | `RowMutationSQL.delete` (`RowMutationSQL.swift:102`), called at `TableDetailView.swift:4371` |

The extraction is behaviour-preserving by construction: same clause order, same `IS NULL` handling,
same skip of columns past the end of the row, same placeholder numbering. `parameterOffset` exists
because the single-row update binds its `SET` values first, so its predicate cannot start at `$1` —
getting that wrong would bind the right values to the wrong columns with no error anywhere.

Also reused unchanged: the mutation review sheet (`recordMutationReviewSheet`, `:2763`) via a new
`PendingRecordMutation.delete` case (`:1182`), the preview text (`:3929`), the transaction and
rollback helpers, `outcomeDescription`, and the audit append.

### How deletion proves it affected exactly one row

Three layers, and only the third is evidence about a server:

1. **Before any SQL exists.** `identityPredicate` throws `RowIdentityError.noPrimaryKey` when the
   table has no primary key and `.emptyPredicate` when the row contributes no clauses. A `DELETE`
   with a collapsed predicate would empty the table, so there is no path that emits one —
   `RowDeleteSQLTests.deleteAlwaysHasAPredicate` asserts both refusals.
2. **Around the statement.** `deleteRows` (`:4371`) opens a transaction, and for each target row
   requires `deleteResult.affectedRows == 1` or throws `MutationExecutionError.affectedRows`. Any
   failure rolls the whole batch back, so a multi-row delete is all-or-nothing. This is the same
   guard `applyEdits` and `applyBatchPaste` already used.
3. **Against real servers.** `LiveRowDeletionTests` in `Tests/GlassDatabaseTests/LiveDatabaseIntegrationTests.swift`,
   MySQL 8.4.11 and PostgreSQL 18.6, in `gpt_scratch`:
   - a current row → server reports **1**, and the other two rows survive;
   - a row whose `name` is NULL → server reports **1**, through `IS NULL`. `= NULL` would have
     matched nothing, and the test asserts the SQL contains `IS NULL` so the check cannot pass by
     accident;
   - a row updated by another statement first, deleted with the stale values → server reports
     **0**, and the row is still there carrying the other edit. **This is the optimistic conflict
     check actually firing.**

   The probe table is created and dropped inside the test and `tables(in:)` is asserted clean
   afterwards. Cleanup is awaited, not deferred into a detached `Task` — the composite-key test
   above it left a table behind exactly that way once.

### Entry points

| Surface | Where |
|---|---|
| macOS row-number gutter context menu | `TableDetailView.swift:3013` — "Delete Row…" / "Delete *n* Rows…" |
| iOS compact list row context menu | `:2277` |
| iOS "More" menu | `:2359` |
| Grid control bar (macOS, visionOS) | `:2485`, with `deleteControlHelp` (`:4312`) saying *why* it is dimmed |

Deliberately **not** in the window toolbar beside Add Row: that toolbar posts notifications blindly
and knows nothing about selection, so the button would always look enabled and usually do nothing.

**Read-only services are not special-cased in this UI.** D15 puts the refusal on the connection, and
`TableDetailView` contains no `isReadOnly` anywhere today — Add Row is offered on a read-only
service too and the connection refuses it. A second opinion in the UI would be the untested one
(rule 20). The live suite already asserts `ReadOnlyDatabaseConnection` refuses `DELETE FROM teams`
both directly and through a tunnel.

---

## R3 — foreign-key navigation

`Sources/GlassDatabase/ForeignKeyNavigation.swift`. Two steps kept apart on purpose:

- `relationships(from:)` (`:75`) groups the per-column `ForeignKeyInfo` rows into constraints and
  pairs them **by `ordinalPosition`**.
- `filters(following:row:columns:referencedColumns:)` (`:105`) turns a selected row plus a
  relationship into `GridColumnFilter`s on the referenced table — the **browsing** predicate, which
  is that function's correct use.

### What the composite-key test showed

Three cases, `ForeignKeyRelationshipTests`:

| Input | Result |
|---|---|
| the correct two rows for `(x, y) → parent (a, b)`, **supplied in reverse ordinal order** | one relationship, `[x→a, y→b]`, in ordinal order. Row order is not trusted; the ordinals are |
| the **four-row cross product** the PostgreSQL adapter returned before 2026-09-12 (every ordinal duplicated) | **the key is dropped, not followed.** Half those pairings are wrong and nothing in the data says which half, so guessing would open the referenced table filtered by the wrong column and show a wrong row confidently |
| members disagreeing about the referenced table | dropped |

**Why refusal rather than a best guess, since this is the kind of caution that gets deleted later
by someone who never saw the original bug.** A repeated ordinal is not ambiguity to resolve — it is
the signature of the exact defect fixed in `PostgreSQLAdapter` on 2026-09-12, where
`information_schema.constraint_column_usage` was joined with no ordinal correlation and a
two-column key came back as a four-row cross product. Half of those pairings are wrong and the data
carries nothing that says which half. Following the first one would open the referenced table
filtered by the wrong column and show **a row that exists**, which is worse than showing none: it
looks like the feature working. So this path **fails closed**. If that adapter ever regresses, foreign-key
navigation goes quiet rather than lying, and `crossProductIsRefused` is what holds it that way.

And `ForeignKeyFollowTests.compositeFollowCarriesEveryPair` asserts the follow emits **both**
filters. With only the leading pair the target opens at the first row sharing `a`, which is a
different row whenever a key is composite for a reason.

Two refusals worth naming: a **NULL** foreign key references nothing, so it is refused rather than
turned into `IS NULL` on the target (that asks a different question); and a value whose
`displayString` is a placeholder — `DatabaseValue.data` displays as `<3 bytes>` — is refused rather
than filtered on, which would have looked like an empty referenced table. The filter is typed by
the **referenced** column's declared type (D17), not the referencing one.

### Navigation reuse

Opening a table is `openWorkspace(.table(database:table:))` (`DatabaseWorkspaceView.swift:1013`),
the one existing way, reached through a notification — the seam `glassdbOpenSQLDraft` already
established (declared in `TableDetailView.swift`, observed in the workspace at `:355`). No second
way to open a table was added.

`ForeignKeyFilterHandoff` (`ForeignKeyNavigation.swift:151`) exists because navigation is two steps
and the target may or may not already be mounted: filters wait there and the data tab claims them
destructively, on first load (`TableDetailView.swift:1948`) or on the `.glassdbOpenTable`
notification when it is already alive (`:1869`). Staging writes nothing; only applying persists,
exactly as typing a filter by hand does.

### The three-way fan-out, confirmed deliberate

`.glassdbOpenTable` now reaches **three** observers, and that is intended. They are complementary,
not duplicated: one navigates, two are the destination reacting to having been navigated to.

| # | Where | Guards on | Does |
|---|---|---|---|
| A | `DatabaseWorkspaceView.swift:376` | session | opens or re-selects the tab |
| B | `TableDetailView.swift:62` | session + database + table | selects the **Data** sub-tab |
| C | `DataTabView` (`TableDetailView.swift:1866`) | session + database + table | claims the staged filters and reloads |

B and C guard on the table as well as the session, so only the named table reacts; every other open
table ignores the post. A is the only one that can act on a table that is not open, which is why it
belongs to the workspace.

**Ordering does not matter, and does not need to be guaranteed.** `NotificationCenter` delivers
synchronously to all three before `post` returns, in unspecified order, and the three mutate
independent state: A the tab strip, B a sub-tab selection, C the filters. There is no pair whose
outcome depends on which ran first. The one thing that *would* matter — a remount re-running
`.task` and claiming twice — cannot produce a wrong result either, because `claim` is destructive:
a second claim returns `nil` and `claimStagedForeignKeyFilters` returns `false` without touching
the filters. `ForeignKeyFilterHandoffTests.claimIsDestructive` holds that.

**The target table not being open is the case that matters, and it is covered by A + the handoff,
not by C.** C cannot fire on a view that is not mounted. The filters survive because `stage`
happens *before* the post and `ForeignKeyFilterHandoff` is a store independent of any view: A opens
the tab, `DataTabView` mounts, and its `.task` claims in `loadInitialWorkspaceContent`
(`TableDetailView.swift:1948`) — after the persisted grid state so the follow wins over it, and
before the first fetch so the table never appears unfiltered and then jumps. This is the failure
shape the coordinator flagged: had it not worked, the table would have opened unfiltered and looked
like it worked.

**A staged handoff that nothing ever claims now goes stale after 30 seconds**
(`ForeignKeyNavigation.swift:163`). The claim it waits for happens on the next run loop, so this is
not a race window; it bounds the one bad outcome, an entry left behind because nothing opened the
table, which would otherwise filter the user's *next ordinary visit* to that table and look exactly
like the app working. `staleHandoffIsDiscarded` drives it with an injected clock, so the test has no
real delay in it.

---

## R4 — the mutation audit

### What was already there

`MutationAuditStore.append` and eleven call sites: single-row update (`TableDetailView.swift:4060`,
`:4084`), pasted range (`:4150`, `:4173`), insert (`:4475`, `:4500`), schema change (`:5087`,
`:5105`), truncate and drop (`SchemaBrowserView.swift:533`, `:555`), and confirmed query-editor
statements (`:3973`). Deletion now appends too (`recordDeleteAudit`, `:4417`), so **every** mutation
path writes one record.

### What was added

- **The reader**, as an extension on `MutationAuditStore` in `MutationAuditView.swift:25` —
  `records(defaults:)` newest-first, `records(forConnection:)`, `clear(defaults:)`. An extension in
  a new file rather than an edit to `Models.swift`, which this task does not own. A record that
  will not decode is dropped rather than failing the whole read.
- **The viewer**, `MutationAuditView` (`:93`): operation, object, outcome, timestamp, source and
  affected rows; filtered to the current connection with an all-connections toggle; clearing is
  all-or-nothing, because an audit a user can edit selectively is not an audit.
  `serverStateUnknown` is spelled out in the row, since it is the one outcome a user must act on —
  the commit went out and no answer came back.
- **Reachable from** the schema sidebar toolbar (`SchemaBrowserView.swift:126`), which is
  session-scoped and owned by this task.

### What is stored, and what is deliberately left out

**The predicate's shape is stored. Its values are not — not hashed, not truncated, simply never
written.** An audit record would read
`` `id` = ? AND `email` IS NULL ``, never `` `id` = 7 AND `email` = 'ada@example.test' ``.

The reason is specific to this predicate: it binds the primary key **plus every original value of
the row**, so the parameter array is a verbatim copy of the entire record. Writing it would put
complete user data — names, emails, whatever the table holds — into `UserDefaults` in plaintext,
persisted across sessions, in a store whose purpose is to be read back and displayed. That is a
copy of the user's data nobody asked for.

The shape still answers: which columns identified the row, whether NULLs took part, how wide the
optimistic check was, and therefore whether a conflict failure was a real concurrent edit or a
malformed predicate. With the table, operation, outcome, affected-row count, timestamp and
connection already on the record, that covers *what happened and did it commit*.

It deliberately **cannot** answer *which specific row*. Storing the primary key values would close
that and is not being done unilaterally: a primary key is routinely itself identifying — an email,
an account number — so there is no subset of the parameters that is safely "just the key". Row-level
traceability is a separate decision to take in the open.

`MutationAuditTests.noRowValuesAreStored` asserts this at the boundary rather than at the call
sites: it appends a record, reads the raw bytes back out of `UserDefaults` and requires the secret
string to be absent. A future call site that passed a formatted statement instead of a shape would
look perfectly reasonable and would fail this test.

**`MutationAuditRecord.predicate` landed** (`Models.swift:534`, applied by the coordinator,
`String?` defaulted to `nil`). The three write paths now pass `identity.auditShape`: the single-row
update (`TableDetailView.swift:4077`), the pasted range (`:4173`) and deletion (`recordDeleteAudit`,
`:4437`). In each the shape is held in a `var` declared **outside** the `do`, so a *failed* mutation
records the same predicate a successful one would have — the failure case is the one an audit is
read for.

The store was deliberately **not** versioned past `glassdb.mutationAudit.v1`, on the grounds that
`JSONDecoder` tolerates a missing key for an `Optional`.
`MutationAuditTests.olderRecordsStillDecode` feeds the reader a hand-written record with no
`predicate` key and requires it to survive — asserted rather than assumed, because being wrong
would make a user's whole audit log read as empty.

The viewer shows the shape under each row, monospaced and selectable, and the empty state says
plainly that row values are never recorded.

---

## Also in this task: `StagedEdit` carries the dialect

Asked for by the coordinator on W-tls's behalf, and reachable without leaving this task's files.

`ColumnTypeConstraint.parse` now takes `dialect: DatabaseDialect?`. Six of MySQL's eight
`TEXT`/`BLOB` byte limits work without it, because those names exist only in MySQL. Bare `text` and
bare `blob` do not: the same names mean roughly a gigabyte on PostgreSQL and SQLite, so applying
65,535 without knowing the engine would **refuse values that store perfectly well**.

`StagedEdit` therefore carries `var dialect: DatabaseDialect?` (`RecordEditorView.swift:137`) and
`constraint` passes it through. The engine is threaded from the connection at every site that
builds edits from real table metadata:

| Site | Source of the dialect |
|---|---|
| `RecordEditorView` (edit and add) | `dialect:` parameter (`:336`), passed `session?.connection?.dialect` from both sheets |
| `StagedEdit.initialValue(for:columnIndex:dialect:)` | its caller |
| `GridPastePlanBuilder.build(…dialect:)` | `session?.connection?.dialect` at `stagePastedRange` |

**One site deliberately left `nil`:** `GridColumnFilter.boundValue()` (`TableDetailView.swift:425`)
builds a throwaway `StagedEdit` to parse a filter value. `GridColumnFilter` is `Codable` and
persisted per table, so giving it a dialect would change a stored format for no gain — a filter is
matched by the server, not stored by it, so a size limit there buys nothing. The effect is that a
filter on a bare `text` column stays unconstrained, exactly as it is today.

Optional rather than defaulted to MySQL, on purpose and asserted in
`StagedEditDialectTests.unknownDialectLeavesSharedNamesAlone`: a missing limit only fails to warn,
and the user gets a legible server error; a borrowed limit silently refuses data that would have
stored.

---

## Files

**Added**

| File | Purpose |
|---|---|
| `Sources/GlassDatabase/RowMutationSQL.swift` | the row-identity predicate, extracted; the DELETE built on it |
| `Sources/GlassDatabase/ForeignKeyNavigation.swift` | relationships, follow filters, the open handoff |
| `Sources/GlassDatabase/MutationAuditView.swift` | the audit reader and viewer |
| `Tests/GlassDatabaseTests/RowMutationSQLTests.swift` | 13 tests |
| `Tests/GlassDatabaseTests/ForeignKeyNavigationTests.swift` | 17 tests |
| `Tests/GlassDatabaseTests/MutationAuditTests.swift` | 8 tests |
| `Tests/GlassDatabaseTests/StagedEditDialectTests.swift` | 5 tests |

**Changed**

| File | Change |
|---|---|
| `Sources/GlassDatabase/TableDetailView.swift` | update paths call the extracted predicate and record its shape; delete path, its guards, audit and four entry points; FK relationships loaded once per table, follow menu, handoff claim, `.glassdbOpenTable` + `OpenTableRequest`, Data-tab selection on open; Foreign Keys tab open button; dialect threaded to the record editor and the paste plan; `interactionView` split into `observedView` + `interactionView` |
| `Sources/GlassDatabase/RecordEditorView.swift` | `StagedEdit.dialect` and the `dialect` parameter on the editor and on `initialValue` |
| `Sources/GlassDatabase/SchemaBrowserView.swift` | Mutation Log toolbar item and sheet |
| `Tests/GlassDatabaseTests/LiveDatabaseIntegrationTests.swift` | `LiveRowDeletionTests`, `LiveForeignKeyNavigationTests`; `GPT_DB_TEST_MYSQL_SCRATCH_DB` and the scratch-namespace helpers |

**Changed by others, at this task's request** (listed so the trail is complete, not claimed as this
task's work): `Models.swift:534` — `MutationAuditRecord.predicate`, applied by the coordinator;
`DatabaseWorkspaceView.swift:376` — the `.glassdbOpenTable` observer, applied by W-drafts.

`interactionView` had to be split: with the foreign-key observer added, the single modifier chain
stopped type-checking in reasonable time (`error: the compiler is unable to type-check this
expression in reasonable time`, at `:1888` as it then was). Two properties, same view, comment in
place saying why it must not be rejoined.

---

## Verification

| Check | Outcome |
|---|---|
| `swift build` (macOS host) | **passed**, no errors |
| `swift test`, whole package | **passed — 711 tests in 60 suites** (362 + 80 + 62 + 24 + 157 + 26) |
| `RowIdentityPredicateTests`, `RowDeleteSQLTests` | **13 passed** |
| `ForeignKeyRelationshipTests`, `ForeignKeyFollowTests`, `ForeignKeyFilterHandoffTests` | **17 passed** |
| `MutationAuditTests` | **8 passed** |
| `StagedEditDialectTests` | **5 passed** |
| `LiveRowDeletionTests` — MySQL **8.4.11**, `gpt_scratch` | **passed**: 1 / 1 (via `IS NULL`) / **0** for a stale predicate |
| `LiveRowDeletionTests` — PostgreSQL **18.6**, `gpt_scratch` | **passed**, same three |
| `LiveForeignKeyNavigationTests` — MySQL **8.4.11** | **passed**: a live composite key opens `one-two`, provably not `two-one` |
| `LiveForeignKeyNavigationTests` — PostgreSQL **18.6** | **passed**, same |
| Scratch database left clean | **verified in-test** for both fixtures — tables dropped and their absence asserted |
| `xcodebuild -scheme GlassDatabase -destination 'generic/platform=iOS Simulator'` | **BUILD SUCCEEDED**, exit 0, no warnings in this task's files |
| `xcodebuild -scheme GlassDatabase -destination 'generic/platform=visionOS Simulator'` | **BUILD SUCCEEDED**, exit 0 |
| macOS UI suite | **not run**, by instruction (rule 21) |
| Deletion or a follow driven through the actual UI | **not run** — see below |

The `DatabaseCertificateTrustTests` failure reported mid-task (a `CredentialStoragePolicy` decode in
W-tls's then-in-flight file) is **gone**: the whole package is green.

### The live foreign-key test, and why its fixture is shaped the way it is

`LiveForeignKeyNavigationTests` runs the whole chain on a real server — `foreignKeys()` through the
real adapter → real ordinals → `relationships` → `filters(following:)` → the browsing `SELECT`
`GridServerQueryBuilder` builds → the row that comes back.

The parent holds **both `(1, 2)` and `(2, 1)`**. That is the point of the fixture: transposing the
pairs, which is exactly what the cross-product defect did, lands on a row that *exists*. A test
whose wrong answer is "no rows" would pass for the wrong reason on a server that simply returned
nothing. Here the assertion is `label == "one-two"` **and** `label != "two-one"`, so a wrong pairing
fails loudly on both engines.

### What the suite cannot reach (rule 22)

- **No test opens a window.** The menus, the deletion review sheet, the audit sheet, the tab switch
  on follow and the three-observer fan-out are compiled and reasoned about, not seen. The fan-out
  argument above is about *state independence*, which is checkable by reading; it is not a
  substitute for driving it.
- **The live tests drive the model layer, not the view.** They prove the SQL, the pairing and the
  server's answer. They do not prove the view calls them with the row the user pointed at.
- **SQLite is untested here.** Both live engines are MySQL and PostgreSQL; the SQLite path compiles
  only. It is also the engine where `ForeignKeysTabView` already reports that changes need a table
  rebuild.
- **The 30-second staleness bound is tested with an injected clock**, so it proves the rule, not the
  wall-clock behaviour of a real navigation.

---

## Remaining work

1. Drive deletion and a foreign-key follow through the running app, including the composite key, on
   macOS. The only evidence owed for R2 and R3 — **reassigned to the coordinator**, see item 5.
2. iOS and visionOS remain **compile-verified only** for this work, as for the rest of the stage.
3. Whether the audit should record primary-key values — open, and deliberately not decided here.
4. ~~Whether a rolled-back batch should record `affectedRows` as `0`.~~ **Settled by the
   coordinator 2026-09-12: keep it as the count reached before the failure.** It says how far the
   batch got before it was undone, which is more than `0` says, and `outcome` already disambiguates;
   `0` would read as "nothing happened", true of the database and false of the attempt. Deletion
   deliberately **follows** `applyBatchPaste` rather than diverging — two write paths disagreeing
   about what `affectedRows` means would be worse than either convention. Not changing it.

5. **Driving R2 and R3 through the macOS UI is the coordinator's, from 2026-09-12** — the tree went
   quiet, so rule 21 no longer blocks a run. It remains the only evidence owed for those two items.
