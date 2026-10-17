# glassdb — Complete User-Facing Feature Inventory

Read-only survey of `../glassdb` performed 2026-09-11 for the GlassPowerTools merge.
Purpose: porting checklist. Every feature below must have a destination in the merged product or be
an explicit, recorded decision to drop.

All citations are `file:line` relative to `../glassdb`.

---

## 0. Scale and platforms

| Scope | Files | Lines |
|---|---|---|
| Whole repo (includes vendored Citadel + swift-nio-ssh) | 194 | 67,690 |
| App target `glassdb/` | 22 | 22,244 |
| `Packages/GlassDBKit/Sources/` | 6 | 3,195 |
| `glassdbTests/glassdbTests.swift` | 1 | 4,567 |

Largest app files, descending: `TableDetailView.swift` 5,847; `ConnectionFormView.swift` 1,804;
`Constants.swift` 1,256; `DatabaseDetailView.swift` 1,244; `ConnectionManagerView.swift` 1,223;
`DatabaseWorkspaceView.swift` 1,206; `QueryEditorView.swift` 1,197; `DatabaseSessionManager.swift` 1,159;
`KeychainManager.swift` 900; `SQLHighlighter.swift` 893; `RecordEditorView.swift` 822; `AIAssistant.swift` 734;
`SettingsManager.swift` 664; `SchemaBrowserView.swift` 659; `GlassEditorAdapters.swift` 613;
`SettingsView.swift` 579; `Models.swift` 427; `ConnectionManager.swift` 338; `glassdbApp.swift` 251;
`DataExporter.swift` 223; `ResultsGridView.swift` 187; `Logger.swift` 18.

GlassDBKit files: `DatabaseProtocol.swift` 239, `MySQLAdapter.swift` 885, `PostgreSQLAdapter.swift` 591,
`QueryResult.swift` 267, `SQLiteAdapter.swift` 674, `SSHTunnelManager.swift` 539.

Vendored and NOT glassdb features: `Packages/Citadel/`, `Packages/swift-nio-ssh/` (~42,000 lines combined).

**Platforms.** One target, no per-platform targets. `glassdb.xcodeproj/project.pbxproj:415-433`:
- `MACOSX_DEPLOYMENT_TARGET = 27.0`
- `IPHONEOS_DEPLOYMENT_TARGET = 26.0`, `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone + iPad)
- `XROS_DEPLOYMENT_TARGET = 26.0`, `TARGETED_DEVICE_FAMILY[xros] = 7`
- `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx xros xrsimulator"`
- `PRODUCT_BUNDLE_IDENTIFIER = app.glassdb`, `MARKETING_VERSION = 0.1.0`

Every feature ships on all three platforms unless a `#if os(...)` note says otherwise.

Entitlements `glassdb/glassdb-macOS.entitlements`: app sandbox, network client, network server,
user-selected files read-write, Keychain group `$(AppIdentifierPrefix)sh.glas.shared`,
App Group `group.sh.glas.shared`.
`glassdb/glassdb.entitlements` (iOS/visionOS) declares the same Keychain and App Group.
`glassdb/Info-macOS.plist` also carries `GlasKeychainAccessGroup`, `NSLocalNetworkUsageDescription`,
and `LSApplicationCategoryType = public.app-category.developer-tools`.

URL scheme `glassdb://` declared in `glassdb/Info-URLs.plist` and `glassdb/Info-macOS.plist`,
URL name `app.glassdb.saved-connection`.

---

## 1. Connections

**Record shape**
- `DatabaseConnectionConfig` fields: id, name, engine, host, port, username, defaultDatabase,
  useSSHTunnel, sshHost, sshPort, sshUsername, sshAuthMethod, sshKeyID, databaseCredentialPolicy,
  sshCredentialPolicy, useTLS, isFavorite, colorTag, dateAdded, lastConnected, tags — `Models.swift:13-140`.
- Custom decoder migrates legacy records and forces database passwords out of the shared Keychain
  group while preserving pre-G04 SSH records in the shared group — `Models.swift:89-127`.
- `displaySubtitle` renders SQLite as a filename and network engines as `user@host:port / database` — `Models.swift:129-139`.

**Engines**
- MySQL, PostgreSQL, SQLite only — `Models.swift:144-214`.
- Decoder aliases `mariadb` → MySQL, `postgres`/`postgres-nio` → PostgreSQL, `sqlite3` → SQLite — `Models.swift:195-208`.
- Per-engine defaultPort (3306/5432/0), defaultHost, defaultUsername (root/postgres/empty), iconName — `Models.swift:159-188`.
- Capability flags `supportsNetworkTransport`, `supportsCredentials`, `supportsTLS`, `supportsSSHTunnel`
  are all false for SQLite — `Models.swift:190-193`.

**Organization**
- Color tags: none, red, orange, yellow, green, blue, purple, pink — `Models.swift:280-306`.
- Collections are free-text comma-separated `tags`, normalized through the shared library projection — `ConnectionManager.swift:134-140`.
- Library scopes All, Favorites, Recent (limit 10), Collections, backed by `GlassLibraryProjection`
  from GlassConnectionKit — `ConnectionManager.swift:59-156`.
- Search matches name, engine display name, host, username, and default database — `ConnectionManager.swift:142-147`.

**Storage**
- JSON in `UserDefaults` key `glassdb.connections` — `Constants.swift:19`, `ConnectionManager.swift:38-56`.
- Writes are transactional with readback verification and rollback; a failed rollback raises a
  distinct error telling the user to reopen and verify — `ConnectionManager.swift:16-31`, `304-320`.
- Deleting stages a durable removal intent in a `HostCatalogDeletionOutbox` before touching
  credentials, then rolls credentials back if persistence fails — `ConnectionManager.swift:237-255`.
- Deleting or re-pointing a SQLite connection removes its unreferenced managed working copy — `ConnectionManager.swift:257-276`.

**Family integration**
- Every saved connection is published as a `HostPublication` of kind `.database` into the App Group
  host catalog at `group.sh.glas.shared/GlassHostCatalog/hosts.json` — `ConnectionManagerView.swift:260-290`.
- Publication re-runs on scene activation and on catalog change — `ConnectionManagerView.swift:66-70`.

**Form — `glassdb/ConnectionFormView.swift`**
- Sections on macOS: Connection, Database Authentication, Advanced, Appearance, Connection Actions — `ConnectionFormView.swift:487-507`.
- Sections on iOS/visionOS: Connection, Database Authentication, SSH Tunnel, Appearance, Test — `ConnectionFormView.swift:499-506`.
- Required-field labels are stated up front rather than revealed after a failed save — `ConnectionFormView.swift:822-836`.
- Per-field validation appears after touch or after a failed save; focus jumps to the first invalid
  field — `ConnectionFormView.swift:260-300`, `1571-1600`.
- Port validation enforces 1–65535 for both database and SSH ports — `ConnectionFormView.swift:279-295`.
- Password fields have a reveal eye toggle and a system `PasteButton` — `ConnectionFormView.swift:1131-1173`.
- In edit mode password prompts read "Leave blank to keep saved password" — `ConnectionFormView.swift:1139`.
- Changing engine resets host, port, username, default database, TLS, and tunnel — `ConnectionFormView.swift:416-427`.

**SSH tunnel options**
- Host, port, username, plus three credential modes: Password, SSH Key, Shared Credentials — `ConnectionFormView.swift:172-187`.
- Shared Credentials reuses a glas.sh identity and stores no second secret; the password is read from
  the shared record at connect time — `ConnectionFormView.swift:1248-1312`, `1649-1670`.
- The Shared mode only appears when the shared catalog has entries or the connection already uses it — `ConnectionFormView.swift:1289-1291`.
- Selecting a shared identity fills host, port, and username and leaves the password blank — `ConnectionFormView.swift:1254-1265`.
- SSH key picker lists imported keys with an algorithm badge; Secure Enclave keys without a tag are
  disabled and labeled "use in glas.sh" — `ConnectionFormView.swift:788-815`, `1729-1737`.
- "Add SSH Key…" opens the same import sheet used by Settings — `ConnectionFormView.swift:457-466`.

**TLS options**
- A single "Encrypt the database connection" toggle; no custom CA or client-certificate UI — `ConnectionFormView.swift:612-615`.
- Policy resolution: direct connections use `requiredSystemTrust`; tunneled connections use
  `requiredSystemTrustForHost(config.host)` so the certificate is checked against the real hostname
  rather than 127.0.0.1 — `DatabaseSessionManager.swift:238-244`.
- `DatabaseTLSPolicy.requiredCertificates` exists in the protocol but is unreachable from the UI — `DatabaseProtocol.swift:85`.

**SQLite import**
- `SQLiteFileImporter` copies the chosen file into Application Support under
  `glassdb/SQLite Databases/<uuid>.<ext>` via `SQLiteEngine.createManagedSnapshot` — `ConnectionFormView.swift:18-104`.
- `validatedURL(forPath:)` refuses any path that escapes the managed directory — `ConnectionFormView.swift:81-103`.
- Accepted content types: `sqlite`, `sqlite3`, `db`, plus `.data` — `ConnectionFormView.swift:897-905`.
- Abandoned staged imports are deleted on sheet dismissal — `ConnectionFormView.swift:1610-1622`.
- SQLite connections reject TLS and SSH tunnels at connect time — `DatabaseSessionManager.swift:86-92`.

**Actions**
- "Test SSH Connection" and "Test Connection" run without saving — `ConnectionFormView.swift:1674-1727`.
- "Save & Connect" (⌘Return on macOS) is the only action that saves and opens a session — `ConnectionFormView.swift:1507-1562`.
- Test result indicator shows Testing / Passed / Failed, with Failed clickable for detail — `ConnectionFormView.swift:1392-1421`.
- Return/Next only advances focus; it never implies Save, Test, or Connect — `ConnectionFormView.swift:1592-1600`.

**Library actions — `glassdb/ConnectionManagerView.swift`**
- Row context menu: Open Workspace, Open New Workspace Window, Disconnect, Connect, Add/Remove
  Favorite, Edit Connection, Delete Connection — `ConnectionManagerView.swift:785-827`.
- Delete is disabled while a session is active, with a help string explaining why — `ConnectionManagerView.swift:823-826`.
- iOS swipe actions: leading favorite toggle, trailing Edit and Delete — `ConnectionManagerView.swift:692-717`.
- macOS double-click connects, or opens the workspace if already connected — `ConnectionManagerView.swift:728-737`.
- Return key on the results list connects the selected connection — `ConnectionManagerView.swift:591-599`.
- Detail panel sections: Connection, Security, Activity, Organization — `ConnectionManagerView.swift:861-927`.
- Security summary line combines credential policy, TLS state, and direct-vs-tunnel — `ConnectionManagerView.swift:1003-1012`.
- Delete confirmation text differs for SQLite, naming the managed working copy — `ConnectionManagerView.swift:1014-1019`.
- Empty states per scope with tailored descriptions — `ConnectionManagerView.swift:657-677`.
- Active connections show a green bolt instead of the engine icon — `ConnectionManagerView.swift:755-770`.

**Host key trust**
- First-use and changed-key prompts show host, port, algorithm, and SHA-256 fingerprint with
  Trust & Retry; the changed case is styled destructive — `ConnectionManagerView.swift:175-190`.
- Trust writes the key through `KeychainManager.saveHostKey` then retries — `ConnectionManagerView.swift:1150-1166`.
- `SSHHostKeyChallenge` carries host, port, algorithm, fingerprint, full wire-format key data, and
  reason (unknown or changed) — `SSHTunnelManager.swift:20-46`.

**Import/export of connections**
- **None.** There is no file-based import or export of the connection list.
- The only external entry is `glassdb://` selecting a saved connection by UUID, which shows a
  confirmation alert naming the connection and destination, and re-resolves the record after review
  so a changed record is refused — `glassdbApp.swift:193-198`, `ConnectionManagerView.swift:84-108`.

**Credential handling — `glassdb/KeychainManager.swift`**
- Three `SecretStoreConfiguration`s: shared, app-only, authenticated — `KeychainManager.swift:152-172`.
- Policies: `sharedWithGlas`, `glassdbOnly`, `requireAuthentication` — `Models.swift:228-278`.
- Database passwords are never shared; only SSH identity is shareable — `Models.swift:254-259`.
- Separate services for passwords, SSH passwords, SSH private keys, passphrases, sealed P256 keys
  and tags — `Constants.swift:38-46`.
- Credential writes use snapshot, apply, verify, restore-on-failure — `KeychainManager.swift:302-430`.
- A versioned migration runs at load, currently version 2 — `KeychainManager.swift:19-20`, `469-529`.
- Shared SSH credential catalog enumeration for the Shared Credentials picker — `KeychainManager.swift:564-646`.
- Shared Keychain availability is detected at runtime; unsigned builds disable the option with an
  explanation — `KeychainManager.swift:190-209`, `ConnectionFormView.swift:1241-1246`.

---

## 2. Schema browsing

`glassdb/SchemaBrowserView.swift` — the sidebar of every workspace window.

- Two levels only: databases (PostgreSQL: schemas) then tables; the navigation title switches on
  dialect — `SchemaBrowserView.swift:112`.
- **No tree node** for views as a category, columns, indexes, triggers, functions, sequences, or enums.
- Views are folded silently into the table list:
  - PostgreSQL includes `BASE TABLE`, `VIEW`, `FOREIGN` — `PostgreSQLAdapter.swift:226-237`.
  - SQLite includes `table` and `view`, excluding `sqlite_%` — `SQLiteAdapter.swift:305-316`.
  - MySQL uses `SHOW TABLES FROM`, which includes views — `MySQLAdapter.swift:606-614`.
  - PostgreSQL `databases()` actually returns schemata excluding `information_schema` — `PostgreSQLAdapter.swift:214-224`.
  - SQLite `databases()` returns `PRAGMA database_list` — `SQLiteAdapter.swift:297-303`.
- Inline per-table row count, prefixed `~` when the server value is an estimate, with a tooltip naming
  the capture time and whether it is an estimate or an exact statistic — `SchemaBrowserView.swift:399-416`.
- Exact counts calculated by the user override the cached estimate and show their own timestamp — `SchemaBrowserView.swift:402-406`.
- Search field filters both database and table names; sidebar placement on macOS/visionOS, automatic
  on iOS — `SchemaBrowserView.swift:650-658`.
- Toolbar Refresh reloads databases and every expanded database's tables — `SchemaBrowserView.swift:114-123`, `606-611`.
- Database context menu: Open Database in Tab, Set as Active Database (MySQL only, issues `USE`),
  Open SQL Editor, Open in New Window, Refresh — `SchemaBrowserView.swift:418-459`.
- Table context menu: Browse Data, Copy Table Name, Copy SELECT Statement, Calculate Exact Row
  Count…, Refresh, Truncate Table…, Drop Table… — `SchemaBrowserView.swift:461-493`.
- Copy SELECT emits `SELECT * FROM <db>.<table> LIMIT 100;` with correctly quoted identifiers — `SchemaBrowserView.swift:472-476`.
- Exact row count is confirmation-gated, runs with a 30-second timeout, shows a cancellable progress
  overlay, and cancels the server query on Cancel — `SchemaBrowserView.swift:148-161`, `613-647`.
- Truncate is only offered when the engine advertises `.truncateTable` — `SchemaBrowserView.swift:485-489`.
- Truncate/Drop confirmation previews connection, environment color tag, database, table, operation,
  estimated scope, and transaction behavior (MySQL DDL may commit implicitly) — `SchemaBrowserView.swift:497-504`.
- Both write a `MutationAuditRecord` with committed or serverStateUnknown outcome and invalidate the
  statistics cache — `SchemaBrowserView.swift:506-553`.
- Single click previews a destination, double click opens it as a tab — `SchemaBrowserView.swift:376-397`.
- iPhone (compact) replaces the disclosure tree with a drill-down `NavigationStack` of databases then
  tables, with a per-row actions menu — `SchemaBrowserView.swift:234-318`.
- Per-database load errors render inline under the disclosure group rather than failing the tree — `SchemaBrowserView.swift:341-344`.
- Reconnecting clears the table cache, exact counts, and load errors, then reloads — `SchemaBrowserView.swift:127-133`.
- **No create, alter, or rename of databases or tables from the browser.** Column, index, and
  foreign-key DDL lives in the table tabs. There is no CREATE TABLE UI anywhere in the app.

---

## 3. Table data grid

`DataTabView` — `glassdb/TableDetailView.swift:1180-4209`. Doubles as the SQL result grid via a second
initializer, so features marked "table only" do not apply to free-form SQL results.

**Paging**
- Server-side `LIMIT`/`OFFSET` with one extra sentinel row fetched to prove a next page exists — `TableDetailView.swift:611-701`, `839-869`.
- Page size user-editable 1 to 10,000, validated on submit with an explanatory alert — `TableDetailView.swift:3378-3388`.
- Prev/Next control group with "Page N" or "N of M" when a total is known — `TableDetailView.swift:2168-2190`.
- Total row count is never computed automatically; the pager shows a cached server estimate — `TableDetailView.swift:1436-1439`, `2087-2102`.
- "Calculate Total…" runs `COUNT(*)` with a 30-second timeout, cancellable mid-flight — `TableDetailView.swift:3759-3794`.
- Free-form results instead show "more available — loaded result limited to N" when truncated — `TableDetailView.swift:2103-2107`.

**Sorting**
- Multi-column with priority numbers and arrows rendered in the header — `TableDetailView.swift:3046-3050`.
- Header click cycles ascending → descending → off — `TableDetailView.swift:3397-3414`.
- Header context menu: Sort Ascending, Sort Descending, Remove Sort — `TableDetailView.swift:3083-3085`.
- Table context rewrites the server query; free-form SQL results sort the loaded page in memory — `TableDetailView.swift:514-543`, `2752-2769`.
- Sort state persists per connection+database+table — `TableDetailView.swift:3588-3600`.

**Filtering**
- Two explicit modes the user chooses between, with an explanation of each — `TableDetailView.swift:431-452`.
  - "Update SQL Query" adds bound `WHERE` conditions and reloads from the database.
  - "Display Only" hides non-matching loaded rows without contacting the database.
- Free-form SQL results are locked to Display Only — `TableDetailView.swift:1906-1907`, `2476`.
- Operators: Equals, Does Not Equal, Greater Than, Less Than, Is NULL, Is Not NULL — `TableDetailView.swift:359-379`.
- Values are type-validated against the column via `StagedEdit.boundValue()` before they can be added — `TableDetailView.swift:403-428`.
- Display-mode comparison is numeric where possible, otherwise literal string compare, with a footer
  warning that it may differ from the server's collation — `TableDetailView.swift:493-511`, `2555-2557`.
- The filter sheet stages changes and shows a live "visible rows N of M loaded" count — `TableDetailView.swift:2549-2558`.
- Filter button badges the active count and changes its icon when filters are live — `TableDetailView.swift:2335-2349`.

**Grouping and aggregates (table only)**
- Group By any set of columns — `TableDetailView.swift:2362-2368`, `3533-3542`.
- Aggregates: Count All, Count, Sum, Average, Minimum, Maximum — `TableDetailView.swift:550-585`.
- Executed as a bounded server query with generated aliases and ordering by the group columns — `TableDetailView.swift:662-734`.
- Sum and Average are rejected on non-numeric columns — `TableDetailView.swift:762-766`.
- Clear Analysis resets grouping and aggregates — `TableDetailView.swift:3552-3558`.
- Analysis mode disables paste, TSV import, header-mapping, and row comparison — `TableDetailView.swift:2451-2464`, `2803-2807`.

**Editing**
- No in-cell editing; double-clicking a row opens the `RecordEditorView` sheet — `TableDetailView.swift:3149-3159`.
- Updates use an optimistic predicate of the primary key plus every original row value, inside a
  transaction, requiring exactly 1 affected row — `TableDetailView.swift:3925-4009`.
- Tables without a primary key refuse updates with an explicit message — `TableDetailView.swift:3930-3935`.
- Inserts omit columns marked "use default" so the server applies DEFAULT; MySQL uses
  `INSERT INTO t () VALUES ()` and others `DEFAULT VALUES` when nothing is provided — `TableDetailView.swift:4109-4190`.
- Every mutation records committed / rolledBack / serverStateUnknown / notStarted, and a
  serverStateUnknown outcome invalidates the statistics cache — `TableDetailView.swift:3985-4008`.
- A review sheet (macOS) or alert (iOS/visionOS) previews connection, database, table, operation,
  changed columns, predicate, and transaction behavior before any write — `TableDetailView.swift:2696-2728`, `3842-3852`.
- **No row deletion exists anywhere** in the grid or the record editor; removal requires typing SQL.

**Record editor — `glassdb/RecordEditorView.swift`**
- Staging model: edits are highlighted "Modified", batched, and applied only on explicit save — `RecordEditorView.swift:125-269`.
- Field types rendered specially: Boolean toggle, JSON editor, large-text multiline, standard — `RecordEditorView.swift:437-532`.
- JSON columns get a full GlassEditorKit editor with per-field Format and Validate buttons and a
  drag handle to resize between 120 and 800 points — `RecordEditorView.swift:607-695`.
- JSON pretty-print and compaction are hand-written to preserve string contents exactly — `RecordEditorView.swift:14-121`.
- Dirty detection for JSON is semantic equivalence, not text equality — `RecordEditorView.swift:145-147`.
- "Set to NULL" and, in add mode, "Use Column Default" and "Provide Value" — `RecordEditorView.swift:444-490`.
- Generated columns are read-only and labeled "Generated by server" — `RecordEditorView.swift:440-443`.
- Per-type value coercion covers bool, all integer widths with unsigned handling, decimal-as-string,
  float/double finiteness, JSON, bit strings with byte padding, Base64 binary, and the five temporal
  kinds — `RecordEditorView.swift:191-268`.
- Discard prompts for confirmation when anything was changed — `RecordEditorView.swift:387-393`, `427-433`.
- Apply button shows the pending change count — `RecordEditorView.swift:367`.

**Value display**
- NULL renders tertiary as "NULL" — `TableDetailView.swift:2962`.
- Numeric values use monospaced digits and trailing alignment; everything else leading — `TableDetailView.swift:17-25`, `2953-2961`.
- `DatabaseValue` distinguishes string, int, uint, exact decimal-as-string, double, binary data,
  JSON, temporal with raw server text, bit field, bool, date, null — `QueryResult.swift:132-180`.
- Binary displays as `<N bytes>` in the grid but exports as Base64 — `QueryResult.swift:156`, `174-179`.

**Column presentation**
- Resize, reorder, hide, and freeze, all four persisted per connection+database+table under
  `app.glassdb.gridLayout.<uuid>.<base64 db+table>` — `TableDetailView.swift:871-909`, `3560-3574`.
- Automatic width measured from the header and the first 50 rows, clamped 80–400; manual resize
  clamped 60–600 — `TableDetailView.swift:3604-3617`, `3517-3521`.
- Frozen columns stay pinned at the leading edge during horizontal scroll via `visualEffect` offsets — `TableDetailView.swift:2974-2981`, `3072-3079`.
- Header context menu: sort actions, Freeze/Unfreeze, Hide, Move Left, Move Right — `TableDetailView.swift:3082-3093`.
- Manage Columns sheet stages changes with Show All, Hide All, Unfreeze All, Reset, plus a column
  search and a "N visible · M frozen" summary — `TableDetailView.swift:2578-2659`.
- Hiding the last visible column is prevented — `TableDetailView.swift:3488-3496`.
- Row-number gutter is pinned and generated, never a database column — `TableDetailView.swift:2921-2945`.

**Clipboard and range selection**
- Copy emits TSV with `\N` for NULL and escaped tabs, CRs, LFs, and backslashes — `DataExporter.swift:79-105`.
- Copy scope is the selected rows, else the selected cell rectangle, else all displayed rows — `TableDetailView.swift:2809-2839`, `3198-3207`.
- Paste or TSV import at the selected cell, mapped positionally or by an exact header row — `TableDetailView.swift:1012-1123`.
- Paste plan validates rectangularity, fit within loaded rows, writable columns, nullability, unique
  target primary keys, and per-value type coercion before anything is staged — `TableDetailView.swift:1059-1116`.
- Applied as one all-or-nothing transaction with a per-row optimistic predicate — `TableDetailView.swift:4011-4105`.
- Paste review sheet previews target row, row and column counts, mapping mode, and rollback semantics — `TableDetailView.swift:2662-2694`, `2790-2799`.
- Import cap is 10 MB UTF-8, checked both before and after reading the file — `TableDetailView.swift:986-998`, `1870-1890`.

**Selection and navigation**
- Arrow-button control group extends the selection by cell — `TableDetailView.swift:2399-2410`, `3209-3224`.
- Shift-click extends and Command-click toggles row selection on macOS — `TableDetailView.swift:916-948`, `3170-3196`.
- There is **no arrow-key cell cursor**; keyboard navigation is limited to the button group.
- Selection is restored after a reload by primary-key identity — `TableDetailView.swift:3796-3833`.
- Compare exactly two selected rows for a per-column difference listing — `TableDetailView.swift:956-979`, `3247-3277`.
- **No foreign-key navigation**; keys are shown in their own tab but are not clickable.

**Other grid behavior**
- iPhone replaces the grid with a card list showing the first four visible columns, with tap-to-edit
  and an Edit-mode multi-select for export — `TableDetailView.swift:2192-2249`.
- "Run every 10s" auto-repeat from the Run control's context menu, stopped when the tab deactivates — `TableDetailView.swift:135-139`, `3905-3921`.
- A statement returning no result set reports "Statement Completed" with affected rows and duration
  rather than an ambiguous empty grid — `TableDetailView.swift:2054-2076`.
- An unexecuted editor shows a striped empty grid with the same geometry and a "Ready" hint, with no
  invented columns or rows — `TableDetailView.swift:2843-2893`.
- Generated browsing SQL is treated as a clean baseline so a refresh never erases a user draft — `TableDetailView.swift:3731-3736`.

---

## 4. Query editor

`glassdb/QueryEditorView.swift`, `glassdb/GlassEditorAdapters.swift`, `glassdb/SQLHighlighter.swift`.

**Editor engine**
- GlassEditorKit `GlassEditorModel` bridged through `SQLEditorSurface`, supplying a completion
  provider, a diagnostics provider, and a statement-boundary provider — `GlassEditorAdapters.swift:173-289`.
- Theme follows system appearance; the surface follows the same opacity and blur pair that drives the
  database canvas — `GlassEditorAdapters.swift:276-287`.
- `SQLEditorController` is an imperative handle for external text and selection replacement, with an
  equality no-op so typing does not echo — `GlassEditorAdapters.swift:96-167`.
- Editor height is drag-resizable between 60 and 400 points — `TableDetailView.swift:1567-1590`.

**Highlighting and language services**
- Hand-written tokenizer with keyword and function sets; token kinds include keyword, function,
  string, number, comment, identifier, plain, error — `SQLHighlighter.swift:23-34`, `100-330`.
- `NSAttributedString` highlighting used for the read-only DDL view, with UIKit and AppKit variants — `SQLHighlighter.swift:791-892`.
- Statement splitting respects strings, comments, and compound routine bodies — `SQLHighlighter.swift:331-393`.
- Linting produces exactly one diagnostic, "Unterminated string or identifier" — `SQLHighlighter.swift:772-786`.

**Autocomplete**
- Identifiers come from every database name, the focus database's table names, qualified `db.table`
  names, and plain plus `table.column` names for up to 50 tables — `TableDetailView.swift:5805-5847`.
- Qualified table names for a typed `db.` prefix are fetched on demand and validated against live
  database names so an alias is never treated as a database — `TableDetailView.swift:5808-5814`, `1494-1508`.
- A horizontal pill bar floats over the editor's bottom edge, gradient-masked, aligned to the text
  area rather than the gutter — `TableDetailView.swift:1540-1551`, `1992-2049`.
- Tab accepts the top suggestion; a dimmed ghost suffix previews what Tab would insert — `TableDetailView.swift:1972-1990`, `1529-1533`.
- Tab-to-complete is macOS only; hardware-keyboard Tab on iPad still indents — `GlassEditorAdapters.swift:181-184`.
- Completion insertion tracks an automatic trailing space so following punctuation absorbs it — `GlassEditorAdapters.swift:113-130`.

**Execution**
- Four modes: Run Statement at cursor, Run Selection, Run All Statements, and an automatic
  selection-or-statement mode — `SQLHighlighter.swift:19-21`, `401-435`.
- Split button relabels live to "All Statements" while Shift-Command is held on macOS — `QueryEditorView.swift:29-61`.
- Every statement is classified readOnly, mutation, destructive, sessionControl, or unknown — `SQLHighlighter.swift:38-63`, `436-576`.
- Anything not readOnly or sessionControl triggers a confirmation alert naming the classifications — `QueryEditorView.swift:738-752`, `932-940`.
- A batch stops at the first server error and keeps that result visible — `QueryEditorView.swift:942-967`.
- SELECTs are rewritten with a bounded read plan using the user's row limit plus a sentinel row, and
  the result is flagged truncated — `SQLHighlighter.swift:500-530`, `DatabaseSessionManager.swift:492-523`.
- Editor row limits are validated against 1…100,000 before execution — `DatabaseSessionManager.swift:485-490`.
- `USE <db>` is detected so the UI's current-database indicator follows — `DatabaseSessionManager.swift:552-559`.
- Mutating statements invalidate every cached namespace's statistics for the session — `DatabaseSessionManager.swift:572-576`.
- Mutating statements executed from the table surface write a `MutationAuditRecord` — `TableDetailView.swift:3883-3893`.

**Cancellation and explain**
- Cancel (⌘.) is offered only when the connection advertises `.cancellation` — `QueryEditorView.swift:574-581`.
- Drivers without a native cancel packet abort by closing the transport; the session manager detects
  that and tears down the tunnel rather than presenting a dead connection — `DatabaseSessionManager.swift:808-833`.
- Explain (⇧⌘E) runs the engine's `EXPLAIN` when advertised and renders as an ordinary result grid — `DatabaseSessionManager.swift:758-806`.
- **There is no visual plan tree.**

**History**
- Durable, persisted to `UserDefaults` key `glassdb.queryHistory` — `Constants.swift:21`, `DatabaseSessionManager.swift:912-933`.
- Entries store SQL, timestamp, duration, row count, affected rows, error, database, connection id,
  and safety class — `DatabaseSessionManager.swift:1124-1159`.
- Capped by the user's limit, clamped 1…10,000, enforced on both the persistent list and each
  session's in-memory list — `DatabaseSessionManager.swift:870-884`.
- History sheet searches SQL, database, and error text; filters All / Succeeded / Failed; swipe-deletes
  single entries; and can clear one connection with confirmation — `QueryEditorView.swift:1015-1119`.
- Failed entries carry a red "Failed" badge — `QueryEditorView.swift:1060-1063`.
- Opt-in literal redaction rewrites quoted strings and numbers before history is written, never
  changing what is sent to the server — `SQLHighlighter.swift:577-593`, `DatabaseSessionManager.swift:886-910`.

**Saved queries**
- Name, SQL, optional connection scope, use count, created and last-used dates — `Models.swift:337-363`.
- Persisted to `glassdb.savedQueries` — `SettingsManager.swift:300-320`.
- Sheet sorts most-recently-used first, searches name and SQL, swipe-deletes — `QueryEditorView.swift:1121-1197`.
- Selecting one increments its use count and stamps last-used — `SettingsManager.swift:339-345`.
- Save sheet on macOS previews the SQL and validates a non-empty name; iOS uses an alert — `QueryEditorView.swift:764-819`.
- Default proposed name is the first line of the query, truncated to 48 characters — `QueryEditorView.swift:599-605`.

**Documents and tabs**
- Workspace tabs: Overview is permanent; database, table, and SQL tabs are closable — `DatabaseWorkspaceView.swift:18-71`, `98-175`.
- A preview tab overlays the selection without committing it, so single-click browsing does not
  accumulate tabs — `DatabaseWorkspaceView.swift:132-150`.
- Closing a SQL tab with unsaved text prompts Save… / Don't Save (⌘D) / Cancel — `DatabaseWorkspaceView.swift:377-399`.
- SQL documents open and save as plain `.sql` up to 10 MB with UTF-8 validation and a size recheck
  after reading — `QueryEditorView.swift:842-911`.
- Export filenames are sanitized from the tab title — `QueryEditorView.swift:863-869`, `DatabaseWorkspaceView.swift:1095-1104`.
- Tab titles are deterministic from statement shape: a direct SELECT source name, "SQL Script · N
  statements", or an operation label — `QueryEditorView.swift:393-419`.
- A model-generated title may replace it, validated to 64 characters with no control characters,
  semicolons, backticks, or SQL fragments — `QueryEditorView.swift:439-446`.
- Only one SQL document is active at a time; hidden editors stay alive in a ZStack and register their
  command handlers but never win command routing — `DatabaseWorkspaceView.swift:876-921`.

**Other editor actions**
- Format (⇧⌘F) uppercases keywords and normalizes statement spacing while preserving strings,
  identifiers, and comments byte-for-byte — `SQLHighlighter.swift:706-717`.
- In the table surface Format applies to the selection only when one exists — `TableDetailView.swift:1953-1967`.
- Clear empties the editor and the current result — `QueryEditorView.swift:620-626`.
- Detach Results opens the current result in its own window — `QueryEditorView.swift:611-618`.
- New Query Tab and Close Query Tab from the Queries menu — `QueryEditorView.swift:640-652`.
- Error card classifies messages into Invalid SQL Syntax, Authentication Failed, Query Timed Out,
  Duplicate Value, Foreign Key Constraint, or Query Failed, with Copy Error and Suggest Fix — `QueryEditorView.swift:89-342`.
- Error detail is truncated at 16 KB and stripped of NUL characters — `QueryEditorView.swift:93-100`.

---

## 5. Schema and DDL editing

All generated SQL passes through a review sheet before being sent — `TableDetailView.swift:4689-4734`.
Every applied change writes a `MutationAuditRecord` with committed / rolledBack / serverStateUnknown
and invalidates the statistics cache — `TableDetailView.swift:4736-4794`.
Multi-statement changes run in a transaction when the engine advertises `.transactions` — `TableDetailView.swift:4749-4752`.

**Structure tab — `TableDetailView.swift:4798-5205`**
- Column list with primary-key and generated badges, type, nullability, default, ordinal position — `TableDetailView.swift:4843-4901`.
- Header shows the column count and a Refresh button — `TableDetailView.swift:4949-4973`.
- Add Column dialog: name, SQL type (default `VARCHAR(255)`), Allow NULL toggle — `TableDetailView.swift:4975-5006`.
- Edit Column dialog: rename, type, Allow NULL, MySQL Unsigned, and a default-behavior picker — `TableDetailView.swift:5008-5075`.
- Default modes: Keep Current, No Default, NULL, Literal Value, Current Timestamp — `TableDetailView.swift:4230-4238`.
- Drop Column with a destructive confirmation — `TableDetailView.swift:5176-5186`.
- Generated columns can only be renamed; type, nullability, and default controls are disabled — `TableDetailView.swift:5015-5035`, `4302-4306`.
- Primary-key columns cannot be made nullable, with a pointer to the Indexes tool — `TableDetailView.swift:4307-4311`.
- Unsigned is rejected on non-MySQL dialects and on non-numeric types — `TableDetailView.swift:4312-4314`, `5126-5133`.
- A failed schema change opens the full `QueryErrorCard` with an AI Suggest Fix that can open the
  correction as a new SQL draft — `TableDetailView.swift:4925-4946`.

**Dialect-specific ALTER generation — `TableDetailView.swift:4274-4367`**
- MySQL emits one `ALTER TABLE … CHANGE COLUMN` carrying type, unsigned, nullability, and default.
- PostgreSQL emits a sequence: `RENAME COLUMN`, `ALTER COLUMN … TYPE`, `SET|DROP NOT NULL`,
  `SET DEFAULT|DROP DEFAULT`.
- SQLite allows rename only and refuses type, nullability, and default changes with a message
  pointing at a reviewed rebuild migration — `TableDetailView.swift:4317-4323`.
- Default literals are validated per type: numeric parses as `Decimal`, boolean accepts true/false/1/0,
  CURRENT_TIMESTAMP requires a temporal type, everything else is single-quote escaped — `TableDetailView.swift:4505-4546`.

**Type and identifier validation — `TableDetailView.swift:4548-4651`**
- Identifiers must be non-empty, at most 256 bytes, free of control characters, and are quote-doubled.
- Type expressions are parsed tracking quotes, parentheses, and brackets, capped at 2,048 bytes.
- Top-level constraint keywords are rejected: ADD, ALTER, AUTO_INCREMENT, CHECK, COLLATE, COLUMN,
  COMMENT, CONSTRAINT, DEFAULT, DROP, GENERATED, KEY, NOT, NULL, PRIMARY, REFERENCES, UNIQUE, UNSIGNED.

**DDL tab — `TableDetailView.swift:5209-5298`**
- Read-only server `SHOW CREATE TABLE` with syntax highlighting — `TableDetailView.swift:5267-5278`.
- Copy and "Open as SQL", which posts the definition into a new SQL tab — `TableDetailView.swift:5238-5250`.
- PostgreSQL does not advertise `.createTableDefinition`, so this tab shows an explanation pointing at
  the Structure, Indexes, and Foreign Keys tools — `TableDetailView.swift:5256-5261`, `PostgreSQLAdapter.swift:277`.

**Indexes tab — `TableDetailView.swift:5311-5539`**
- Multi-column indexes grouped by name, ordered by sequence, with PRIMARY and UNIQUE badges and the
  index type — `TableDetailView.swift:5332-5345`, `5383-5418`.
- Add Index: name, "Unique values only" toggle, column multi-select preserving table order — `TableDetailView.swift:5443-5480`, `5495-5511`.
- Drop Index, suppressed for primary keys and `sqlite_autoindex_` entries — `TableDetailView.swift:5408-5414`.
- `DROP INDEX` syntax differs by dialect: MySQL `DROP INDEX x ON t`, others `DROP INDEX db.x` — `TableDetailView.swift:4394-4408`.
- `CREATE INDEX` targeting differs on SQLite, which qualifies the index rather than the table — `TableDetailView.swift:4369-4392`.

**Foreign Keys tab — `TableDetailView.swift:5551-5798`**
- Constraints grouped by name showing local columns, an arrow, and referenced table and columns — `TableDetailView.swift:5579-5591`, `5629-5656`.
- Add Foreign Key: constraint name (pre-filled `fk_<table>_`), local column, referenced table, and
  referenced column loaded on demand when the table changes — `TableDetailView.swift:5681-5713`, `5729-5752`.
- Drop Foreign Key; MySQL uses `DROP FOREIGN KEY` and PostgreSQL `DROP CONSTRAINT` — `TableDetailView.swift:4426-4438`.
- Both Add and Drop are disabled on SQLite with an explanation about rebuild migrations — `TableDetailView.swift:4420-4422`, `5606-5609`.

**Not present**
- No migrations system, no CREATE TABLE, no CREATE or DROP DATABASE, no trigger, function, view,
  sequence, or enum editing anywhere in the app.

---

## 6. AI assistant

`glassdb/AIAssistant.swift`.

**Provider and gating**
- Apple's on-device `FoundationModels`, weak-linked with `@_weakLinked` — `AIAssistant.swift:8-10`.
- Gated to visionOS 27.0 / macOS 27.0 or later — `AIAssistant.swift:176`, `217`, `282`, `366`, `396`.
- **There is no API key and no network provider.** Nothing to migrate for key storage.
- iOS is absent from every availability check, so the assistant is effectively macOS and visionOS only
  despite the target building for iPhone and iPad.
- Seven availability states with their own user-facing messages: checking, available, deviceNotEligible,
  appleIntelligenceDisabled, modelNotReady, unsupportedOS, unavailable — `AIAssistant.swift:127-147`.
- Unavailability shows a `ContentUnavailableView` with a "Check Again" button — `AIAssistant.swift:518-526`.
- Availability is logged to the `ai` category — `AIAssistant.swift:198`.

**Operations**
- Generate SQL from a natural-language prompt — `AIAssistant.swift:204-267`.
- Explain a SQL error and suggest a corrected query — `AIAssistant.swift:269-345`.
- Summarize a query in plain language — `AIAssistant.swift:347-358`, `394-438`.
- Generate a short SQL tab title — `AIAssistant.swift:362-392`.
- Interactive operations cancel each other; title generation runs independently so it can never
  cancel a user's request — `AIAssistant.swift:204-213`, `361-362`.

**Context sent**
- Database name, table names, column names and types — `AIAssistant.swift:45-92`.
- Optionally up to 3 explicitly-included sample rows per table; `includeSampleValues` defaults false — `AIAssistant.swift:48`, `79-85`.
- `redactSensitiveNames` replaces identifiers containing password, passwd, secret, token, api_key, or
  private_key with `[redacted sensitive identifier]` — `AIAssistant.swift:99-105`.
- All identifiers and values are control-character stripped and escaped as prompt literals with
  backslash, quote, `<` and `>` encoding — `AIAssistant.swift:94-124`.
- Sample values are truncated to 256 characters each — `AIAssistant.swift:114`.
- Total context truncated at `maximumCharacters`, clamped to 1,000–24,000, default 12,000, with an
  explicit `[Context truncated at privacy limit]` marker — `AIAssistant.swift:49`, `86-91`.
- The assistant sheet shows a lock-shield disclosure stating exactly how many tables, columns, and
  sample rows are being sent — `AIAssistant.swift:63-70`, `528-532`.

**Prompt-injection defenses**
- Schema is wrapped in `<UNTRUSTED_SCHEMA_METADATA>`, query in `<UNTRUSTED_QUERY>`, error in
  `<UNTRUSTED_DATABASE_ERROR>` — `AIAssistant.swift:240-242`, `306-308`, `313-318`.
- System prompts state the wrapped content is data never instructions, and forbid requesting,
  revealing, or inferring credentials or secrets — `AIAssistant.swift:232-238`, `297-304`.
- Responses must be a single JSON object with named string fields, decoded with a 64 KB cap — `AIAssistant.swift:453-463`.
- Per-field size caps: query 32 KB, explanation 16 KB, problem 16 KB, suggestedFix 32 KB,
  reasoning 16 KB, summary 16 KB — `AIAssistant.swift:248-251`, `325-329`, `422`.
- Title generation uses temperature 0 and a 96-token cap, is capped at 24,576 input bytes, and falls
  back silently to the deterministic title on any failure — `AIAssistant.swift:362-392`.
- Title input is pre-redacted: comments dropped, strings and numbers replaced with `?` — `QueryEditorView.swift:421-437`.

**Execution and safety**
- **The assistant cannot execute anything.** Generated SQL is inserted into the editor or copied — `AIAssistant.swift:621-636`.
- Risk class is computed deterministically by `SQLHighlighter.safetyClassification`, not by the model,
  and shown as a colored badge — `AIAssistant.swift:252-256`, `643-659`.
- A mutating suggestion still passes through the normal confirmation alert; the error card warns that
  a suggestion can modify state and will still require confirmation — `QueryEditorView.swift:294-302`.
- Fenced code blocks in a suggested fix are unwrapped before insertion — `QueryEditorView.swift:138-152`.

**Entry points**
- Sparkles toolbar button on the table Data tab, compiled only when `FoundationModels` is available — `TableDetailView.swift:122-129`.
- "Suggest Fix" on the query error card, shown only when the assistant reports available — `QueryEditorView.swift:193-201`.
- "Suggest Fix" on a failed schema change, which can open the correction as a new SQL draft — `TableDetailView.swift:4925-4946`.
- One `AIAssistant` instance per database session, so context and cancellation are per-connection — `DatabaseSessionManager.swift:1073`.

---

## 7. Export and import

**Formats**
- File export: CSV, JSON, SQL `INSERT` statements — `DataExporter.swift:12-26`.
- Clipboard copy and paste/import: TSV — `DataExporter.swift:79-105`.
- SQL documents export separately as plain text — `QueryEditorView.swift:63-87`.

**Type fidelity**
- CSV quotes fields containing commas, quotes, CR, or LF and doubles embedded quotes — `DataExporter.swift:190-195`.
- JSON emits `$binary` Base64 wrappers for binary, `$bit` binary-digit strings for bit fields,
  unsigned ints above 2^53 as strings, non-finite doubles as their description, and parses embedded
  JSON columns into real objects — `DataExporter.swift:145-162`.
- SQL emits `X'...'` hex for binary, `B'...'` for bit fields, `NULL` for non-finite doubles, and
  single-quote-escaped strings; identifiers are quoted with the connection's quote character — `DataExporter.swift:164-188`.
- TSV emits `\N` for NULL, renders bit fields as display strings, and escapes backslash, tab, CR, LF — `DataExporter.swift:79-105`, `197-203`.
- Binary values export as Base64 rather than the abbreviated `<N bytes>` UI label — `QueryResult.swift:172-179`.

**Scope**
- Selected rows, else the selected cell rectangle, else all currently displayed rows — `TableDetailView.swift:2809-2839`.
- Always the loaded page. **No whole-table, whole-database, or whole-server dump. No streaming export.**
- Column scope follows the visible and frozen column layout — `TableDetailView.swift:2820-2827`.

**Destination**
- System `fileExporter` save panel via `GridExportDocument` — `TableDetailView.swift:1852-1869`.
- Default filenames: `<database>_<table>.<ext>` for tables — `TableDetailView.swift:1864`.
- Default filenames: `result_<8 hex>.<ext>` for detached results — `ResultsGridView.swift:61`.
- Export failures surface as an alert rather than silently — `ResultsGridView.swift:67-75`, `TableDetailView.swift:1866-1868`.
- Detached result windows carry their own Copy All and Export menu — `ResultsGridView.swift:126-154`.
- Table toolbar has a dedicated Import TSV button and Export menu when the Data tab is active — `TableDetailView.swift:67-81`, `164-180`.

**Import**
- TSV only, 10 MB cap, UTF-8 only, validated both before and after reading — `TableDetailView.swift:986-998`, `1870-1890`.
- It is an **update path, not an insert path**: it maps onto existing loaded rows starting at the
  selected cell and requires the table to have a primary key — `TableDetailView.swift:1012-1123`.
- Mapping is positional from the selected cell or by an exact header row with unique names — `TableDetailView.swift:1029-1057`.
- `\N` in a cell means NULL and is rejected on a non-nullable column — `TableDetailView.swift:1091-1094`.
- Generated columns are rejected as paste targets — `TableDetailView.swift:1088-1090`.
- SQL document import accepts `.sql` and plain text up to 10 MB with UTF-8 validation — `QueryEditorView.swift:842-902`.

---

## 8. Settings

`glassdb/SettingsView.swift`, persisted by `glassdb/SettingsManager.swift`, keys in `glassdb/Constants.swift:18-36`.

**Pages**
- macOS: a 5-tab `TabView` — General, Editor, Appearance, SSH Keys, About — `SettingsView.swift:102-127`.
- iOS: one Form with Query, Editor, SSH Keys, Workspace, About sections; **no Appearance section** — `SettingsView.swift:129-152`.
- visionOS: one Form with Query, Editor, SSH Keys, Appearance, About, plus a visionOS-only
  "Show sidebar when opening a workspace" toggle — `SettingsView.swift:154-165`, `302-306`.
- Every control writes immediately on change — `SettingsView.swift:34-43`.

**Keys**

| Setting | Key | Range / default |
|---|---|---|
| Result row limit | `glassdb.resultRowLimit` | 1–100,000, step 100, default 1000 |
| Query history limit | `glassdb.maxQueryHistoryItems` | 1–10,000, step 100, default 500 |
| Redact literals in query history | `glassdb.redactQueryHistoryLiterals` | Bool, default off |
| Notify when a query fails | `glassdb.queryFailureNotificationPreference` | undecided / enabled / disabled |
| SQL editor text | `glassdb.editorFontSize` | 10–32 pt, default 14 |
| Results grid text | `glassdb.dataGridFontSize` | 10–32 pt, default 13 |
| Show line numbers | `glassdb.showLineNumbers` | Bool, default on |
| Format JSON automatically while editing | `glassdb.autoFormatJSONInRecordEditor` | Bool, default on |
| Workspace opacity | `glassdb.windowOpacity` | 0.0–1.0, default 0.95 |
| Background blur | `glassdb.blurBackground` | 0.0–1.0, default 1.0 |
| Show sidebar by default | `glassdb.showSidebarByDefault` | Bool, default on |

- Bounds are re-clamped on every save, not just in the UI — `SettingsManager.swift:228-252`.
- `blurBackground` migrates from an older Boolean toggle without collapsing later slider values — `SettingsManager.swift:189-197`.
- Other persisted keys: `glassdb.connections`, `glassdb.savedQueries`, `glassdb.queryHistory`,
  `glassdb.sshKeys`, `glassdb.mutationAudit.v1` (`Models.swift:410`), plus per-table
  `app.glassdb.gridLayout.*` and `app.glassdb.gridQuery.*`, and the AppKit column autosave name
  `app.glassdb.connection-library.columns` (`Constants.swift:64`).

**Sync**
- **Nothing syncs via iCloud or `NSUbiquitousKeyValueStore`.** No CloudKit, no KVS.
- The only cross-process storage is App Group suite `group.sh.glas.shared`, holding the shared SSH key
  catalog under key `sshKeys` — `SettingsManager.swift:103-104`.
- The shared host catalog file `group.sh.glas.shared/GlassHostCatalog/hosts.json` is the other
  cross-app surface — `ConnectionManagerView.swift:223-230`.
- A legacy app-local `glassdb.sshKeys` catalog is merged forward and kept in sync on every write — `SettingsManager.swift:496-530`.

**Query section**
- Two bounded steppers with monospaced digit readouts and accessibility hints — `SettingsView.swift:410-434`.
- Footer explains that limits protect memory, redaction applies only to history, and notifications
  contain no database details — `SettingsView.swift:244-246`.

**Editor section**
- Two bounded double steppers with a "pt" suffix — `SettingsView.swift:436-458`.
- Footer notes text sizes apply to newly rendered editors, and that valid JSON is always compacted
  before being sent regardless of editor formatting — `SettingsView.swift:274-276`.

**Appearance section**
- Two `GlassSettingSlider`s for workspace opacity and background blur — `SettingsView.swift:283-295`.
- Footer states the controls affect only the live SQL and row-management canvas, that 0% on both gives
  a fully transparent canvas, and that titlebar, sidebar, tabs, Connections, Settings, and detached
  results retain Apple system materials — `SettingsView.swift:298-300`.

**SSH Keys page — `SettingsView.swift:320-407`**
- List of name, algorithm/storage badge, and creation date.
- macOS uses an ellipsis menu, iOS adds swipe actions, and both have a context menu, for Rename and Delete.
- "Import SSH Key…" opens `AddSSHKeyView` — `SettingsView.swift:462-579`.
- Import accepts a pasted OpenSSH RSA or Ed25519 private key with an optional passphrase and a
  show/hide eye toggle; the algorithm is detected before storage — `SettingsView.swift:569-578`.
- Rename is an inline alert with a text field; Delete confirms with "permanently remove from Keychain".
- Secure Enclave keys created by glas.sh appear but are badged "glas.sh only" and are unusable here — `SettingsView.swift:399-407`.
- Catalog errors surface inline in red at the top of the section — `SettingsView.swift:323-327`.
- Footer states private key material and passphrases live in Keychain via GlassSecretStore and that
  Secure Enclave keys stay bound to their creating device — `SettingsView.swift:394-396`.
- Catalog writes are transactional across the shared and legacy suites with readback verification and
  rollback — `SettingsManager.swift:556-602`.
- Limits: 4,096 entries, 1 MB catalog, 256-byte names, 1 MB private keys, 4,096-byte passphrases — `SettingsManager.swift:105-109`.
- Add rolls the Keychain write back if the catalog write fails, and vice versa — `SettingsManager.swift:389-411`, `418-465`.

**About page**
- Version 0.1.0, "Database engines: MySQL, PostgreSQL, SQLite", "Platforms: Apple silicon" — `SettingsView.swift:310-316`.

**Credential policy controls (in the connection form, not Settings)**
- Database passwords offer glassdb only or Require authentication — `Models.swift:257-259`.
- SSH offers a "Share with glas.sh" toggle; when off, the same two private options — `ConnectionFormView.swift:663-674`.
- Each policy shows a one-line description of where the secret lives — `Models.swift:243-252`.
- Unsigned builds disable sharing with an explicit message — `ConnectionFormView.swift:1241-1246`.

---

## 9. Windows, scenes, sheets, shortcuts, commands

**Scenes — `glassdb/glassdbApp.swift:25-129`**
- `WindowGroup id "main"` Connections, default 1320×760, `handlesExternalEvents(matching: ["*"])`,
  `.defaultLaunchBehavior(.presented)` — `glassdbApp.swift:36-44`.
- On iPhone the primary scene is wrapped in `IOSAppRoot`, which routes the workspace in-window rather
  than opening a second window — `glassdbApp.swift:27-34`, `155-199`.
- `WindowGroup id "query-editor"` valued by `UUID`, default 1400×900, restoration disabled, launch
  suppressed, `.windowStyle(.plain)` on visionOS — `glassdbApp.swift:58-85`.
- `WindowGroup id "results"` valued by `UUID`, default 1000×600, for detached result grids — `glassdbApp.swift:88-99`.
- Settings is the native macOS `Settings` scene at 620×540 with `.windowResizability(.contentSize)`,
  a `WindowGroup id "settings"` on iPad, a `Window id "settings"` on visionOS, and a sheet on iPhone — `glassdbApp.swift:104-129`, `180-192`.
- `DatabaseWorkspaceWindowRequest` separates the shared session id from the per-window id so several
  windows can drive one live connection — `DatabaseWorkspaceView.swift:80-96`.
- Older builds where the scene UUID was the session UUID are still supported — `DatabaseSessionManager.swift:64-67`.
- "Open New Workspace Window" appears on macOS, visionOS, and iPad only — `ConnectionManagerView.swift:791-801`.
- Workspace windows are clear-backed with a passive AppKit titlebar material and full-size content
  view — `Constants.swift:631-656`.

**Navigation shells**
- macOS and iPad regular width: three-column `NavigationSplitView` with autosaved divider positions — `ConnectionManagerView.swift:264-295`, `Constants.swift:55-65`.
- visionOS: a four-tab `TabView` of All, Favorites, Recent, Collections — `ConnectionManagerView.swift:297-357`.
- iPhone: a `NavigationStack` with explicit results and detail destinations — `ConnectionManagerView.swift:359-386`.
- Workspace is a two-column `NavigationSplitView` with the schema browser as sidebar — `DatabaseWorkspaceView.swift:232-252`.
- Table detail is a ZStack of visited tabs on macOS and iOS, and a real `TabView` on visionOS — `TableDetailView.swift:191-247`.

**Menu commands — `Constants.swift:785-878`, macOS only**

| Command | Shortcut | Line |
|---|---|---|
| Command Palette… | ⇧⌘P | `Constants.swift:811-814` |
| Command Palette (Alternate)… | ⌘K | `Constants.swift:815-818` |
| New SQL Document | ⌘N | `Constants.swift:825` |
| New Connections Window | ⇧⌘N | `Constants.swift:828` |
| Open SQL Document… | ⌘O | `Constants.swift:832` |
| Close Active Tab | ⇧⌘W | `Constants.swift:838` |
| Save SQL Document… | ⌘S | `Constants.swift:841` |
| Run Statement / Run Selection | ⌘Return | `Constants.swift:847` |
| Run Statement at Cursor | none | `Constants.swift:850` |
| Run Selection | none | `Constants.swift:852` |
| Run All Statements | ⇧⌘Return | `Constants.swift:854` |
| Explain Plan | ⇧⌘E | `Constants.swift:857` |
| Cancel Query | ⌘. | `Constants.swift:860` |
| Format SQL | ⇧⌘F | `Constants.swift:866` |
| Query History | none | `Constants.swift:872` |
| Saved Queries | none | `Constants.swift:874` |
| Add Connection (Connections window) | ⌘N | `ConnectionManagerView.swift:1214-1222` |
| Save & Connect (connection form) | ⌘Return | `ConnectionFormView.swift:1796-1801` |
| Copy All (detached results) | ⌘C | `ResultsGridView.swift:138` |

- `SidebarCommands()` and `ToolbarCommands()` are also installed — `glassdbApp.swift:47-48`.
- `.newItem` is deliberately replaced so ⌘N creates a SQL document rather than a window, because the
  system-generated "New Connections Window ⌘N" would otherwise capture the key — `Constants.swift:820-830`.
- ⌘W is intercepted by a custom AppKit router that walks the File menu, retargets the Close item, and
  routes to the focused editor tab instead of closing the window — `Constants.swift:316-426`.
- The workspace holds exactly one window-level ⌘W registration so hidden tabs cannot shadow it — `DatabaseWorkspaceView.swift:993-1008`.

**Command palette — `Constants.swift:931-1256`**
- A borderless `NSPanel` attached as a child window of the key window, with popover material and a
  12-point corner radius.
- Fuzzy subsequence matching over title plus detail, diacritic- and case-insensitive — `Constants.swift:943-954`.
- Ranking boosts enabled entries, prefix matches, substring matches, and the 20 most recent commands — `Constants.swift:1136-1145`.
- Tab completes a hierarchical destination; arrows navigate; Return runs; Escape cancels — `Constants.swift:1178-1199`.
- Enumerates the live main menu to depth 6, rendering real key equivalents — `Constants.swift:1010-1040`.
- Dynamic entries: every saved connection as `connect: <name>` — `Constants.swift:793-799`.
- Dynamic entries: every open workspace tab, every database, and every known table — `DatabaseWorkspaceView.swift:1022-1041`.
- Lazily expanded `server.database.table` destinations fetched as the query narrows — `Constants.swift:736-783`.
- `connect:` prefix filters to connection entries only — `Constants.swift:1131-1134`.
- Focus is restored to the originating responder before the chosen action runs — `Constants.swift:1216-1235`.
- A destination load failure shows a footer note and leaves existing commands usable — `Constants.swift:1120-1123`.

**Sheets**
- Add Connection, Edit Connection — `ConnectionManagerView.swift:119-161`.
- Import SSH Key — `SettingsView.swift:44-53`, `ConnectionFormView.swift:457-466`.
- Rename SSH Key alert, Delete SSH Key alert, SSH Key Error alert — `SettingsView.swift:54-99`.
- Record Editor (edit and add) — `TableDetailView.swift:1676-1699`.
- Filter Rows — `TableDetailView.swift:1700-1702`, `2471-2576`.
- Manage Columns — `TableDetailView.swift:1703-1705`, `2578-2659`.
- Review Pasted Range (macOS sheet, iOS alert) — `TableDetailView.swift:1763-1782`, `2662-2694`.
- Review Row Mutation (macOS sheet, iOS alert) — `TableDetailView.swift:1744-1762`, `2696-2728`.
- Compare Rows (macOS sheet, iOS alert) — `TableDetailView.swift:1783-1800`, `2730-2749`.
- Add Column, Edit Column, Schema Change review, Schema Change failure — `TableDetailView.swift:4918-4946`.
- Add Index, Add Foreign Key — `TableDetailView.swift:5435-5440`, `5673-5678`.
- Query History, Saved Queries, Save Query — `QueryEditorView.swift:704-737`.
- AI SQL Assistant — `TableDetailView.swift:1706-1729`.
- Review SQL Before Executing, Review SQL Before Execution — `QueryEditorView.swift:738-752`, `TableDetailView.swift:1730-1743`.
- Save Changes? on tab close, SQL Document Error — `DatabaseWorkspaceView.swift:377-408`.
- Connect to Database? on URL open, Connection Error, SSH Host Key, Delete Connection — `ConnectionManagerView.swift:85-190`.
- Calculate Exact Row Count?, Truncate Table?, Drop Table?, Database Operation Failed — `SchemaBrowserView.swift:148-197`.
- **No inspectors**; the `inspector` modifier is not used anywhere in the app.

**Toolbar placement by platform — `Constants.swift:881-899`**
- macOS: automatic for most, `.navigation` for sidebar.
- iOS: `.bottomBar` for general and transfer, `.primaryAction` for execution, `.topBarLeading` for sidebar.
- visionOS: `.bottomOrnament` for general and transfer, `.primaryAction` for execution.
- A persistent macOS toolbar group supplies SQL Editor and Settings on every detail surface — `Constants.swift:901-922`.

---

## 10. Everything else user-visible

**Activity and monitoring**
- Connection Overview: server version, namespace count, table count, total table storage, endpoint,
  user, transport description, active database, SSH route — `DatabaseDetailView.swift:13-561`.
- Two Swift Charts bar charts of the top 8 namespaces by estimated rows and by bytes, with a byte
  formatter on the axis — `DatabaseDetailView.swift:259-320`.
- Namespace list with table count, estimated rows, storage, and a chevron to open each — `DatabaseDetailView.swift:322-380`.
- Progress reporting during inspection: "Inspecting databases… N of M" — `DatabaseDetailView.swift:148-164`.
- A partial-results notice names how many namespaces had no statistics and reassures they are still
  openable — `DatabaseDetailView.swift:243-257`.
- One aggregate round trip is preferred when the engine advertises `.aggregateTableStatistics`, with a
  per-database fallback that publishes in chunks of 16 to avoid re-rendering per query — `DatabaseDetailView.swift:468-560`.
- Database Detail repeats the above per database with a storage-engine summary and per-table charts — `DatabaseDetailView.swift:608-966`.
- Table Statistics Preview: rows, storage, storage engine, collation, capture time, last-analyzed
  time, and a PostgreSQL warning about rows modified since analysis — `DatabaseDetailView.swift:968-1186`.
- Row counts are labeled "Estimated rows" vs "Rows" based on `rowCountAccuracy` — `DatabaseDetailView.swift:1083-1087`.
- Statistics cache for 15 minutes and are invalidated on any mutation — `DatabaseSessionManager.swift:1083-1097`, `735-756`.
- Concurrent callers share one in-flight statistics query — `DatabaseSessionManager.swift:605-638`, `676-683`.

**Connection lifecycle and recovery**
- Connection stages surfaced to the user: Resolving host, Establishing SSH tunnel, Authenticating,
  Selecting database, Connected — `Models.swift:327-333`.
- A full-window recovery overlay on disconnect with state-specific title, message, icon, and tint,
  the raw server detail as selectable monospaced text, a Reconnect button that reuses saved
  credentials, and Show Connections — `DatabaseWorkspaceView.swift:424-593`.
- Reconnect preserves the logical session so every window over it recovers together without losing
  tabs, history, or AI context — `DatabaseSessionManager.swift:320-394`.
- MySQL reconnects restore the previously selected database with a `USE` before publishing — `DatabaseSessionManager.swift:345-360`.
- A background task polls every 5 seconds and re-broadcasts a data refresh when a connection returns — `DatabaseWorkspaceView.swift:595-620`.
- Scene-phase changes mark the transport as needing validation rather than closing it, since another
  iPad window may still own the session — `DatabaseSessionManager.swift:396-410`, `DatabaseWorkspaceView.swift:409-419`.
- Terminal connection errors are recognized from a fixed phrase list — `DatabaseSessionManager.swift:939-955`.
- Local Network permission denial is classified specially with an actionable message — `DatabaseSessionManager.swift:957-985`, `1049-1051`.
- Closed sessions show a "Connection Closed" overlay with Show Connections — `DatabaseWorkspaceView.swift:440-473`.

**Notifications**
- Opt-in local notifications when a query fails, offered inline on the first error card rather than
  buried in Settings — `QueryEditorView.swift:238-265`.
- The notification body deliberately contains no SQL, schema names, literals, or server diagnostics — `SettingsManager.swift:279-296`.
- A denied authorization flips the preference to disabled and shows a follow-up note — `SettingsManager.swift:264-277`, `QueryEditorView.swift:206-214`.

**Audit**
- `MutationAuditStore` keeps the last 1,000 mutations with connection id, database, object,
  normalized operation, source surface, timestamp, outcome, and affected rows — `Models.swift:374-427`.
- Sources recorded: `schema-browser`, `query-editor`, `record-editor`, `grid-paste`, `table-tools`.
- **This log has no UI. It is written and never read back.**

**Navigation aids**
- Breadcrumb trail connection → database → table above the workspace content, with ancestors
  clickable to reopen them — `DatabaseWorkspaceView.swift:667-706`, `1180-1206`.
- Workspace tab strip with per-tab close buttons, a context menu, and horizontal scrolling — `DatabaseWorkspaceView.swift:708-767`.
- Window title reflects the displayed destination — `DatabaseWorkspaceView.swift:862-873`.

**Appearance**
- A workspace-only glass canvas whose opacity and blur are independently user-controlled — `Constants.swift:75-109`.
- macOS uses an AppKit behind-window `NSVisualEffectView` with `.underWindowBackground`; other
  platforms use a SwiftUI material — `Constants.swift:518-538`, `DatabaseWorkspaceView.swift:1145-1175`.
- Pinned grid chrome uses a square-root alpha curve so scrolling values cannot merge into it while
  preserving the exact transparent and opaque endpoints — `Constants.swift:92-103`.
- Titlebar, sidebar, workspace tabs, Connections, Settings, and detached results deliberately keep
  Apple system materials — `Constants.swift:222-225`, `DatabaseWorkspaceView.swift:657-664`.
- visionOS enables look-to-scroll on every scrolling surface — `Constants.swift:185-192`.

**Logging**
- `os.Logger` under subsystem `app.glassdb` with categories app, database, keychain, settings,
  connections, query, ai — `Logger.swift:10-18`.
- Credential material is never logged; failures log only localized descriptions — `ConnectionManager.swift:188-191`.
- **No in-app log viewer.**

**Confirmed absent** (grep across `glassdb/` found zero hits)
- Drag and drop (`onDrop`, `draggable`, `dropDestination`, `NSItemProvider`).
- Quick Look (`QLPreview`), printing, widgets (`WidgetKit`).
- App Intents, Shortcuts, `NSUserActivity`, `ShareLink`, `Transferable`.

**Accessibility**
- Accessibility identifiers on library scopes, connection rows, detail panels, form fields, settings
  tabs, and SSH key fields — e.g. `ConnectionManagerView.swift:494-496`, `ConnectionFormView.swift:404`.
- Labels and hints on grid cells, headers, the row-number gutter, and every toolbar action — `TableDetailView.swift:2942-2945`, `2982`, `3109`.
- `.isSelected` and `.isHeader` traits applied where selection and headers exist — `ConnectionManagerView.swift:502`, `TableDetailView.swift:3109`.
- Named accessibility actions such as "Open Database in Tab" and "Open Table" — `SchemaBrowserView.swift:362-364`, `390-392`.
- Value announcements on toggles and steppers — `RecordEditorView.swift:593-595`, `SettingsView.swift:428-430`.
- Error messages are announced with an "Error:" prefix — `ConnectionFormView.swift:784`.

**Privacy**
- `glassdb/PrivacyInfo.xcprivacy` declares no tracking, no tracking domains, no collected data types,
  and UserDefaults access with reasons CA92.1 and 1C8F.1.

**GlassDBKit engine capabilities** (drives which UI affordances appear)

| Capability | MySQL | PostgreSQL | SQLite |
|---|---|---|---|
| transactions | yes | yes | yes |
| parameterBinding | yes | yes | yes |
| transportTLS | yes | yes | no |
| queryTimeout | yes | yes | yes |
| cancellation | yes | yes | yes |
| metadata | yes | yes | yes |
| schemas | no | yes | yes |
| indexes | yes | yes | yes |
| foreignKeys | yes | yes | yes |
| tableStatistics | yes | yes | yes |
| aggregateTableStatistics | yes | yes | no |
| createTableDefinition | yes | **no** | yes |
| explain | yes | yes | yes |
| serverVersion | yes | yes | yes |
| truncateTable | yes | yes | **no** |

Sources: `MySQLAdapter.swift:22-32` and `222-233`; `PostgreSQLAdapter.swift:23-32` and `114-122`;
`SQLiteAdapter.swift:14-23` and `178-185`.

- Identifier quote character: MySQL backtick (protocol default `DatabaseProtocol.swift:169`),
  PostgreSQL and SQLite double quote — `PostgreSQLAdapter.swift:122`, `SQLiteAdapter.swift:185`.
- Parameter placeholders: `$N` for PostgreSQL, `?` for MySQL and SQLite — `DatabaseProtocol.swift:172-177`.
- SQLite opens with `SQLITE_OPEN_FULLMUTEX`, runs `PRAGMA quick_check`, and enables
  `PRAGMA foreign_keys = ON` — `SQLiteAdapter.swift:154`, `195-210`.
- TLS policies fail closed and never fall back to plaintext — `DatabaseProtocol.swift:77-93`.

---

## 11. TODO / FIXME / DEBUG scan and known gaps

**Scan results**
- **Zero** `TODO`, `FIXME`, `XXX`, or `HACK` markers in `glassdb/` and `Packages/GlassDBKit/Sources/`.
  Independently corroborated by `memory-bank/progress.md:15`, which records a final authored-code scan
  finding no in-scope TODO/FIXME/stub/fatalError/preconditionFailure/empty-catch implementation.
- **Zero** `#if DEBUG` blocks in the app or GlassDBKit sources.
- The only environment gate is `GLASSDB_TEST_OPEN_SETTINGS`, used by UI tests to open the Settings
  scene — `glassdbApp.swift:245`.
- Markers that do exist live only in the vendored Citadel and swift-nio-ssh packages.

**Open bug, explicitly unfixed**
- **SQL draft data loss.** `memory-bank/activeContext.md:17` records that the user reported edited SQL
  was still not captured, that the exact action and prompt path is unconfirmed, that whole-window
  close and app-quit protection and durable draft recovery are not implemented, and that agents must
  not describe this as fixed.

**Missing features**
- No row deletion anywhere in the grid or the record editor.
- No foreign-key navigation despite foreign keys being displayed in their own tab.
- No CREATE TABLE, no CREATE or DROP DATABASE, no trigger, function, view, sequence, or enum editing.
- No import or export of the connection list.
- No whole-table, whole-database, or whole-server export, and no streaming export.
- No visual query plan tree; `EXPLAIN` output renders as a plain grid.
- No in-app viewer for the mutation audit log, which is written but never read.
- No in-app log viewer.
- No inspectors, drag and drop, Quick Look, printing, widgets, App Intents, or Shortcuts.

**Platform and engine gaps**
- The AI assistant is unavailable on iOS because its availability check names only visionOS 27 and
  macOS 27, though the target builds for iPhone and iPad — `AIAssistant.swift:176`.
- Tab-to-complete is macOS only; hardware-keyboard Tab on iPad still indents, noted in-code as a known
  gap — `GlassEditorAdapters.swift:181-184`.
- PostgreSQL has no DDL tab content because it does not advertise `.createTableDefinition` — `PostgreSQLAdapter.swift:277`.
- SQLite cannot alter column type, nullability, or defaults, and cannot add or drop foreign keys — `TableDetailView.swift:4317-4323`, `4420-4422`.
- SQLite does not support TRUNCATE, so that menu item is hidden for it — `SQLiteAdapter.swift:180-184`.
- `DatabaseTLSPolicy.requiredCertificates` is defined in the protocol but unreachable from the UI, so
  custom CA and client-certificate TLS is a declared capability with no user surface — `DatabaseProtocol.swift:85`.
- The iOS Settings form omits the Appearance section entirely, so opacity and blur cannot be changed
  on iPhone or iPad — `SettingsView.swift:129-152`.

**Unverified, flagged rather than guessed**
- I did not confirm at runtime that `SHOW TABLES` surfaces views on every MySQL server version; the
  code relies on default MySQL behavior.
- I did not read the 885-line MySQL adapter or the 4,567-line test file line by line, so
  adapter-level type-coercion, character-set, and protocol-handshake behavior may hold details not
  captured here.
- I did not exercise the app, so all behavior above is read from source, not observed.
