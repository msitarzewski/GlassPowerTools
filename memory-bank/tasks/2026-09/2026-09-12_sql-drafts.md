# R1 — durable SQL drafts

Worker **W-drafts**. 2026-09-12. Closes the one Stage 3 item that loses user work: glassdb
discarded unsaved SQL on window close and app quit, and porting it verbatim ported the defect
(plan: [Stage 3 database plan](2026-09-12_stage-3-database-plan.md) → *Remaining work* → **R1**).

**Status: implemented, package green.** Nothing committed. Unit-tested only — see *Verification*
for what the suite cannot reach.

## Task contract

- **Scope and authorization:** R1 as assigned by the coordinator. Durable per-tab drafts, written
  debounced, restored when the workspace reopens, discarded when a tab is closed deliberately.
- **Owner and affected files:** `Sources/GlassDatabase/SQLDraftStore.swift` (new),
  `Sources/GlassDatabase/DatabaseWorkspaceView.swift`,
  `Tests/GlassDatabaseTests/SQLDraftStoreTests.swift` (new). `QueryEditorView.swift` was in scope
  and **needed no change** — see *What the plan got wrong*.
- **Validation:** `swift test --build-system native`, 17 new tests, full package green.
- **Approval boundary:** none crossed. No commit, no `git add`, no edit outside the owned list,
  `DatabaseSessionManager.swift` read but not edited.

## The defect, confirmed

`QueryDocumentTab.text` (`Sources/GlassDatabase/QueryEditorView.swift:347`) was the only home for
an editor's SQL. Every path into it is a `Binding<QueryDocumentTab>` handed down by the workspace
(`DatabaseWorkspaceView.swift:1056`, `:1068`), and both bindings previously wrote to `@State`
dictionaries and nothing else. `grep -n "UserDefaults\|AppStorage" Sources/GlassDatabase/QueryEditorView.swift
Sources/GlassDatabase/DatabaseWorkspaceView.swift` returns nothing.

Typing reaches that binding continuously — `SQLEditorSurface`'s `onModelTextChange` assigns the
text binding (`GlassEditorAdapters.swift:239-240`), which `DataTabView.queryText`'s setter writes
back into the document (`TableDetailView.swift:1351-1361`). So the workspace's two binding setters
are the complete choke point for *every* edit path: typing, Format, history insertion, Clear,
import. That is where the store is called from, rather than each command remembering to save.

## What was reused, and what is new

| Reused | Where |
|---|---|
| Tab identity | `WorkspaceSelection` and `WorkspaceTabState.tabs` (`DatabaseWorkspaceView.swift:99`) index the drafts. No second notion of "which tab" was invented; `WorkspaceSelection` is already `Codable`, so it is also the on-disk key |
| The document type | Restored drafts become ordinary `QueryDocumentTab`s. No parallel model |
| Versioned-envelope persistence | The shape of `loadQueryHistory`/`saveQueryHistory` (`DatabaseSessionManager.swift:834-853`) and `MutationAuditStore` (`Models.swift:429-448`): decode, cap, log-and-continue on failure |
| File-store shape | `GlassShellModel.swift:127` and `GlassShellPreferencesStore` — an injectable `URL`, atomic write, no singleton-only access — which is how file-backed state already works in this product |
| Data protection | `FileProtectionType` on `createDirectory`, as `SFTPBrowserView.swift:5305-5312` does for transfer metadata |

New: `SQLDraftStore` (~310 lines) and its 17 tests. Nothing in the module persisted
workspace-scoped state before, so there was no owner to extend.

## The three design decisions

### 1. Drafts live in their own file store, not in `UserDefaults` beside query history

The coordinator's brief pointed at query history as the pattern to follow. I followed its
*shape* and rejected its *medium*, for one reason: **`UserDefaults` is bounded by construction and
drafts are not.** `persistentQueryHistory` is capped at 500 entries by
`DatabaseSessionManager.configuredHistoryLimit` (`:802-805`) precisely because the whole defaults
domain is materialised into memory at launch and rewritten whole on every change. A draft has no
such bound — `SQLTextDocument` accepts imports up to 10 MiB (`QueryEditorView.swift:74`), and that
text lands in a `QueryDocumentTab` like any other.

So: `Application Support/GlassPowerTools/SQLDrafts/<connectionID>.json`, one file per connection.
Launch cost is zero (nothing is read until a workspace opens), a workspace reads exactly one file,
and eviction is a `removeItem`. The directory sits beside the shell's own state
(`GlassShellModel.swift:127`).

It is **not** a property of `DatabaseSessionManager`, which is shared and which I was asked not to
edit. That is also the right boundary independently: query history is session-manager state
because the session manager executes the queries that produce it, whereas a draft is workspace
state the session manager never sees. `MutationAuditStore` is the precedent for a small store with
its own key and its own cap living outside that object.

Two consequences recorded honestly:

- **Not `UserDefaults` means not in the App Group and not migrated from an existing glassdb
  install.** There is nothing to migrate: glassdb never stored drafts. The keys in
  `UserDefaultsKeys` are deliberately `glassdb.`-prefixed so an old installation's data can be
  found (`Constants.swift:20-23`); a draft store has no old data to find.
- Protection class is `.completeUntilFirstUserAuthentication`, matching what `UserDefaults` gives
  this module's other persisted collections. `.complete` (the SFTP metadata's choice) would make a
  flush from the background fail after the device locks, which is exactly when a flush matters.

### 2. A draft is keyed to the **connection**, and does not follow a tab to a different one

`DatabaseSessionManager.connect` mints a fresh `sessionID` per attempt
(`DatabaseSessionManager.swift:81`), so nothing keyed by a session can survive a quit. The durable
identity is `DatabaseConnectionConfig.id` — the key the connection record itself is stored under.

That settles the coordinator's question directly: **the same tab reopened against a different
connection gets nothing.** A draft is SQL written against a specific schema on a specific server.
Replaying `DELETE FROM members WHERE …` into an editor pointed at a different database is a
plausible way to destroy data, and the tab UUIDs of two connections never collide in any case.
Tested: `draftsAreScopedToTheirConnection`.

The corollary is that **one connection's drafts must be restored exactly once**, or "Open in New
Window" (`SchemaBrowserView.swift:444`) would duplicate every SQL tab into the second window and
the two windows would write over each other. The store hands out a restore *claim* per connection:
the first workspace to ask gets the drafts, any other window gets an empty array, and the claim is
released when the claiming workspace disappears so it can be reopened in the same run. Writes are
per-record upserts rather than whole-set saves, so a second window may still *create* drafts
safely. Tested: `onlyOneWorkspaceRestores`.

### 3. Pruning: three bounds plus expiry, and eviction can never take the live tab

A draft store that grows forever is its own bug.

| Bound | Value | Rule |
|---|---|---|
| Drafts per connection | 24 | Evict least-recently-updated |
| Bytes per connection | 8 MiB | Evict least-recently-updated until it fits |
| File age | 90 days untouched | Deleted on the first read of the process, one directory listing |
| Whitespace-only SQL | — | Never written; emptying an editor deletes its record, and a connection with no drafts has its file removed rather than left holding `[]` |

Eviction never considers the record being written, so the tab you are typing in cannot evict
itself even though `updatedAt` may make it look oldest. Tested: `prunesByCount`, `prunesByBytes`,
`prunesExpiredFiles`, `whitespaceIsNotADraft`.

**~~Gap, deliberately left and not mine to close:~~ closed 2026-09-12, and my proposal for it was
one call site too many.** Deleting a *connection* should delete its drafts at once rather than let
them age out over 90 days. `SQLDraftStore.removeAll(connectionID:)` exists for it, and the
coordinator landed the call at `ConnectionManager.swift:262`.

Retained rather than deleted, because the route the error took is the instructive part: I wrote
that there were **two** call sites — `ConnectionManager` and `GlassDatabaseCapability.removeService`.
There is one. `removeService` deletes nothing itself; it resolves the record and calls
`connectionManager.delete(config)` (`GlassDatabaseCapability.swift:134`), so every deletion path
converges on the one method and a second call would have been a duplicate, not a safety net. That
is rule 18 — verify a rule's placement at the call sites, not from the API's shape — which I applied
to the read-only guard while reading the port and then did not apply to my own suggestion.

## Behaviour

- **Written** on every text change, debounced 1.2 s and coalesced per connection.
- **Caret moves schedule no write.** A moved caret is not work worth an I/O and a draft can be
  megabytes, so a range-only change updates the cache and waits for the next text edit or for
  `flush()`. Tested: `caretMovesDoNotWrite`.
- **Flushed** when the scene leaves the foreground (`DatabaseWorkspaceView.swift` `scenePhase`
  handler) and when the workspace disappears.
- **Restored** once per workspace, when a connection identity first becomes available. Only
  `.query` drafts become tabs, and they are appended **without stealing the selection** — the
  window opens on the overview it was opened with, with the restored SQL waiting in the tab strip.
  A `.table` draft goes back into `tableSQLDrafts` and reappears when the user opens that table;
  restoring it as a tab would open table editors nobody asked for.
- **Discarded** when a tab is closed deliberately (`performCloseWorkspace`). Closing the *window*
  only flushes. That asymmetry is the fix.
- Restored drafts come back as unsaved (`hasUnsavedChanges == true`), so the existing close
  confirmation still guards them.

One text change: the close alert said *"This editor contains changes that are only stored in the
current workspace session."* That is now false, so it reads *"Closing this editor discards its SQL.
Save it to a file to keep a copy."* — which is what closing a tab now does.

The store treats its own file as untrusted input: a stored selection is clamped to the text
(`clampedSelection`), a file from a **newer** version is left unread **and unwritten** rather than
overwritten, and unreadable JSON is logged and treated as empty.

## Verification

Run: `swift test --build-system native`.

| Check | Outcome |
|---|---|
| `SQLDraftStoreTests`, 17 tests | **passed**, and passed on three consecutive isolated runs |
| Full package | **passed** — 664 tests / 55 suites. 649/52 was the tree immediately before this work; the coordinator's 615/48 baseline is further back, so the delta above mine is other workers' concurrent additions, not mine |
| `GlassDatabase` builds for iOS / visionOS | **not run** — no platform-specific code was added; the store is Foundation-only and the view changes are plain SwiftUI |
| macOS UI suite | **not run**, deliberately (rule 21: only one UI suite may run on this machine at a time, and other workers are active) |
| Against a real database | **not run.** Nothing here touches a connection |

**One test was written wrong and is recorded rather than quietly fixed** (rule 19). The
debounce test first asserted the write had landed after a fixed 200 ms sleep. It passed in
isolation and failed once in the full package, because every `@MainActor` test shares one actor
and a fixed sleep measures the suite's load, not the store. It now polls to a 10 s deadline, which
asserts the behaviour instead of the scheduler. The companion test — that a caret move schedules
*no* write — keeps a fixed wait deliberately: there, waiting longer can only strengthen it.

Two baseline runs were lost to `error: input file 'TableDetailView.swift' was modified during the
build` — another worker editing a file I do not own. Not a defect; recorded because it cost two
runs.

### What the suite cannot reach (rule 22)

The tests exercise `SQLDraftStore` directly. They do **not** drive SwiftUI, so these are unproven
by the suite and want a person in front of the running app:

1. That the restore actually fires — `onChange(of: session?.connectionConfig.id, initial: true)`
   depends on a session existing by first render. It does on the connect path
   (`GlassDatabaseScenes.swift:142`, `:166`, which open the workspace only after `connect`
   returns), but that is read, not observed.
2. That a hard quit is covered. Writes are flushed on scene background and on the workspace
   disappearing; a `SIGKILL` between a keystroke and the 1.2 s debounce loses that interval. No
   test can assert what a killed process wrote.
3. That the restored tab strip looks right with several drafts, and that a restored caret lands
   where the user left it.

## What the plan got wrong

- **The `file:line` is wrong.** R1 cites `QueryDocumentTab` at `QueryEditorView.swift:68`. Line 68
  is `var text: String` inside **`SQLTextDocument`**, the `FileDocument` used for import/export.
  `QueryDocumentTab` is at **`QueryEditorView.swift:345`**, and its `text` at `:347`. The
  conclusion the plan drew was right; the citation points at a different type.
- **`QueryEditorView.swift` did not need to change**, though the brief scoped it. The document is
  a binding owned by the workspace, so persisting it at the binding covers every editor command
  without touching the editor. The only edit in that area is the close alert's message, which
  lives in `DatabaseWorkspaceView.swift`.
- **The brief's "use the `tabs` array as the index" needed one addition.** `tabs` is the index for
  *restoring*, but it is not sufficient on its own: `tableSQLDrafts` is keyed by
  `WorkspaceSelection` and holds SQL the user wrote against a **table** tab
  (`DatabaseWorkspaceView.swift:203`) — also unsaved work, also lost on quit, and not mentioned in
  R1. It is persisted too, keyed the same way.
- **"Query history is already persisted, so follow that storage pattern" is half right.** The
  decode/cap/recover shape is worth following; the medium is not, for the reason in decision 1.

## Closed after this note was first written

**Deleting a connection now deletes its drafts at once**, rather than letting them age out over
ninety days. The coordinator landed the call at `ConnectionManager.swift:262`, in `delete`, after
this work was reported.

**One call site, not the two this note originally asked for.** I had proposed wiring it into both
`ConnectionManager` and `GlassDatabaseCapability.removeService`; that was one more than needed.
`removeService` does not delete anything itself — it resolves the record and calls
`connectionManager.delete(config)` (`GlassDatabaseCapability.swift:134`), so every deletion path
converges on the one method and a second call there would have been a duplicate, not a safety net.
Which is the same reading rule 18 asks for and I did not apply to my own suggestion: I proposed the
guard from the API's shape rather than from its call sites.

The reason it matters is worth keeping: a draft is the user's own text and can hold anything the
schema does. Deleting the connection is the clearest statement that they are finished with it, so
an expiry window is the wrong default for that case.

## Remaining work

1. Get it in front of real use (rule 22): quit with several drafts open, relaunch, confirm the tab
   strip and caret. Worth folding into the Stage 3 integration pass rather than running a UI suite
   now. **Start with whether the restore fires at all** — item 1 of the unproven list above is read,
   not observed, and everything else here is worthless if that `onChange` does not run.
2. Whether a restored draft should say so in the UI is **a question for the user**, raised by the
   coordinator, not a code change to make meanwhile. Today it is indistinguishable from a tab the
   user left open, which is the right default to ship while the question is open.
