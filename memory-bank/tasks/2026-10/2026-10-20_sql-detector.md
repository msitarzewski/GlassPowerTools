# SQL in a terminal, opened in the query editor — proposal (2026-10-20)

**His ask:** "we need a data detector for SQL that when engaged checks the server for a defined DB and will take the
SQL into a new editor with the proper database and table selected (if possible). Thoughts?"

**State:** built on the Mac (2026-10-20, 0.4.486), at his answers: "1. right-click only 2. present a menu? 3. nah".

## What exists (research, 2026-10-20)

**Detection:**
- Terminal detection is two hard-coded cases, `TerminalLinkTarget.url`/`.path`
  (`GlassTerminalEmulator/TerminalLinkTarget.swift:18`), found by `TerminalLinkLookup.target(at:in:)`, with actions
  in `TerminalLinkLookup.actions`.
- SwiftTerm keeps link ranges and the hover underline internal (`linkHighlightRange`). An underline of our own needs
  a SwiftTerm change.
- The app shows a range of its own through the selection, as Find does (`SwiftTermFindTracker`).

**Where an action can go:**
- **Mac:** the right-click menu, `MacTerminalContextMenu.menu(for:event:)`, beside Look Up. A right-click outside the
  selection selects one word, not a statement.
- **Mac hover:** `MacTerminalPathPreviewer` (a 600 ms rest, then a popover), paths only.
- **visionOS:** hold or secondary-click shows an edit menu of the link's actions.
- **iPhone and iPad:** no custom menu; SwiftTerm's `UIMenuController` allows only copy, paste and select.

**From a terminal to its machine's databases:**
- An SSH session has `server.id`, the catalog endpoint; a local pane has `localShellEndpointID`. From there:
  `GlassShellModel.host(owningEndpoint:)` → `services` (`.database`).
- D45 databases reached *through* this machine (`DatabaseConnectionConfig.tunnelServiceID`) only GlassDatabase can
  list. The modules don't import each other; cross-module calls are closures set in `App/GlassPowerToolsApp.swift`.

**Opening the editor:**
- The pattern is `GlassDatabaseRuntime.openSavedQuery` (`GlassDatabaseCapability.swift:190`): queue the SQL
  (`queueQuery`, 120 s), open the editor on a live session, or connect first.
- A table is selected with `WorkspaceSelection.table(database:table:)` on a workspace request; the sidebar follows.
- MySQL switches database with `USE`. PostgreSQL's browser "databases" are schemas; another database needs another
  connection.

**Checking the server:**
- `databases()` and `tables(in:)` on a live connection.
- Connecting uses stored credentials. A password stored with user presence asks for Touch ID; a tunnel opens its own
  SSH connection and may ask to trust a host key.

**Recognising SQL:**
- `SQLHighlighter` (GlassDatabase, internal) has a tokenizer, `statements(in:)` and `safetyClassification`.
- Table names are parsed only from a plain `SELECT … FROM a.b` (`QueryEditorView.swift:397`).
- Tree-sitter SQL is in GlassEditorCore, which GlassTerminal imports.

## Proposed

1. **Engage:** right-click on SQL.
   - On a selection that starts like a statement, or on a line of SQL with nothing selected: the app widens it to the
     whole statement (up to `;` or a blank line) and shows it with the selection.
   - Then **Open in SQL Editor**. Later: the hover popover, as paths have.
2. **Which database:**
   - the terminal machine's Database services, plus databases reached through it (D45);
   - on This Mac, the local ones.
   - One is used; several give a short chooser, remembered per terminal; none offers Add a Database Service.
3. **Which database and table:**
   - The statement's tables, from FROM, JOIN, UPDATE, INSERT INTO, DELETE FROM and ALTER TABLE.
   - A qualified name settles the database; an unqualified one is looked up on the server (the default database
     first), then the table is selected in the sidebar.
4. **The editor:**
   - A new query tab with the SQL, **never run**. Destructive statements show as they do today, and read-only
     services stay read-only.
   - A live session is reused; otherwise it connects with stored credentials, a connect the person asked for.
5. **Plumbing:**
   - A shared SQL lexer (`statements(in:)`, `safetyClassification`, table names) moved where both sides can import it.
   - An `onOpenSQL` closure on the host model.
   - A `GlassTerminalRuntime` closure that the app wires to a new `GlassDatabaseRuntime.openSQL(_:nearEndpoint:)`.
6. **Platforms:** Mac first, then Vision Pro (its hold menu exists). iPhone and iPad need a menu of our own.

## Built (2026-10-20)

**His answers:** right-click only; a menu when the machine has several databases; no reading of `psql` or `mysql`
prompts.

**How:**
- **`TerminalSQLDetector`** (GlassTerminalEmulator):
  - `looksLikeSQL` takes a statement keyword with the one that must follow it.
  - Lower case needs a `;` or a clause English lacks, so "Select a file from the list" isn't SQL.
  - `statement(around:in:)` goes up to the start and down to the `;`, a blank line or the next statement, at most
    80 rows.
  - Frames come off each line (indentation, │, ⏺, ⎿, •, >); soft-wrapped rows are joined.
- **`MacTerminalContextMenu`:**
  - On SQL, the statement is selected to show its extent, in place of the word.
  - **Open in SQL Editor** comes first: one database, with its name as the subtitle; several, as a submenu; none,
    dimmed, "No database on this machine".
  - A selection clicked inside is used when it is SQL.
- **Closures:**
  - `SwiftTermHostModel.sqlDestinations` and `onOpenSQL`, set by `MacWorkspaceController.installPathActions` from
    `GlassTerminalRuntime.sqlDestinations` and `openSQL` (`GlassTerminalSQLDestination`).
  - The app wires them: the catalog host's `.database` services plus D45 databases through the server, by
    `GlassDatabaseRuntime.sqlDestinations`.
  - Opening: `GlassDatabaseRuntime.openSQL`, as `openSavedQuery` does, connecting first from a Connections window.
- **`PendingQuery.findsTable`:** the workspace opens the SQL tab, then `SQLTableReferences`:
  - `tables(in:)` reads names with the editor's tokenizer; unquoted `a.b` is one token and is split.
  - `locate` takes the named database, else the current one, else the first of up to 64 that has the table, in the
    server's spelling.
  - The workspace then makes that database active (MySQL `USE`, else `currentDatabase`), opens the table, and
    brings the SQL tab back to the front.

**Tested:**
- `TerminalSQLDetectorTests` (6).
- `MacTerminalContextMenuTests` (+4), through the real view: statement selection, the subtitle, the submenu, the
  dimmed item, prose unchanged, unwired terminals.
- `SQLTableReferencesTests` (4).
- All 948 terminal and 334 database tests pass.

**Not tested:**
- End to end against a real database: the workspace step (connect, open the tab, `USE`, the table) was not driven;
  the VM's demo has no saved database it can reach.
- iPhone, iPad and Vision Pro have no SQL item yet.

