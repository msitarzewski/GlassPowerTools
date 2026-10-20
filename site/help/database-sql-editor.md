# Write and run SQL

This page covers SQL documents: opening one, running statements, Explain Plan, cancelling, formatting, saving and opening `.sql` files, query history with literal redaction, and saved queries.

## Open a SQL document

Choose **SQL Editor** in the workspace's toolbar or in the overview. Each SQL document is its own tab. Its title is taken from the SQL, for example `shop.orders` for a simple `SELECT`, and on a device with Apple Intelligence the on-device model may suggest a short title instead.

**On Mac:** **File ▸ New SQL Document** is ⌘N while a database workspace is in front.

**On Mac**, SQL a terminal shows can open here too: right-click it and choose **Open in SQL Editor**. It opens in a new SQL document on the terminal machine's database, without running, with the table it names opened beside it. See [Open SQL in the SQL editor](terminal-sessions.md#open-sql-in-the-sql-editor-mac).

As you type, a row of suggestions under the editor offers keywords, functions and the names of tables and columns in the active database; choose one to insert it. **On Mac:** a dimmed completion is also shown at the cursor; press Tab to accept it.

Unsaved SQL is kept as a draft and comes back the next time you open a workspace on the same service.

## Run statements

The run button runs the statement at the cursor, or the selection when there is one. Its menu offers **Run Statement**, **Run Selection** and **Run All Statements**.

| Command | Shortcut |
|---|---|
| **Run Statement** (or **Run Selection**) | ⌘↩ |
| **Run All Statements** | ⇧⌘↩ |
| **Explain Plan** | ⌥⌘E |
| **Cancel Query** | ⌘. (Mac) |
| **Format SQL** | ⇧⌘F |

**On Mac:** these are also in the **Query** menu, with **Run Statement at Cursor**, **Query History** and **Saved Queries**. Holding Shift and Command changes the run button to **All Statements**.

A statement that changes data, is destructive or cannot be classified opens **Review SQL Before Executing**, which names the kind of SQL in the script. Choose **Execute** to run it or **Cancel**. When several statements run, the first error stops the rest.

A single `SELECT` returns up to 1,000 rows. To change that, set **Result row limit** (1 to 100,000) in Settings ▸ **Databases**, or, on Mac, iPad and Vision Pro, for one window under **Settings** (gear) ▸ **This Window** in its toolbar; see [Database settings](database-workspace.md#database-settings). When there are more rows than the limit, the bar under the results says so, for example **more available — loaded result limited to 1000**. Other statements are sent as written.

**Clear** empties the editor and its results. **New Query Tab** and **Close Query Tab** open and close SQL documents. **On Mac, iPad and Vision Pro:** after a query succeeds, **Detach Results** opens its result in a window of its own, with **Copy All** (⌘C) and **Export**.

## Explain a query

Choose **Explain Plan** (⌥⌘E) to see how the server would run the statement at the cursor without running it. MySQL and PostgreSQL return the plan as JSON; SQLite returns `EXPLAIN QUERY PLAN` rows.

## Cancel a query

While a query runs, **Cancel Query** appears in the toolbar. If the engine cannot cancel in place, the connection is closed, and the workspace offers **Reconnect**.

## When a query fails

The error card names the kind of failure, such as **Invalid SQL Syntax**, and shows the server's message. Choose **Copy Error** to copy it. **Suggest Fix** appears when the on-device model is available; see [The on-device assistant](database-on-device-assistant.md).

The first failure also offers **Enable Notifications**. Query-failure notifications say only that a query failed; they contain no SQL, names or server details.

## Save and open SQL files

- Choose **Queries ▸ Save SQL Document** to save the editor's text as a `.sql` file. **On Mac:** **File ▸ Save SQL Document…** (⌘S).
- Choose **Queries ▸ Open SQL Document** to open a `.sql` or text file of up to 10 MB in a new tab. **On Mac:** **File ▸ Open SQL Document…** (⇧⌘O).
- Closing a tab with unsaved SQL asks **Save Changes?** with **Save…**, **Don't Save** (⌘D) and **Cancel**.

## Query history

Choose **Queries ▸ Query History**. The list shows this service's statements, newest first, with the time, database, duration, row counts and a **Failed** mark. Search by SQL, database or error. The **Filter** menu picks **All**, **Succeeded** or **Failed**, and **Clear This Connection** removes this service's history. Swipe a row to **Delete** it. Selecting an entry puts its SQL in the editor.

History keeps the latest 500 statements, from all your database services together, and survives relaunch. To keep more or fewer, set **Query history limit** in Settings ▸ **Databases**.

> [!NOTE]
> With **Redact literals in query history** on, as it is unless you turn it off in Settings ▸ **Databases**, quoted strings are replaced with `'?'` and numbers with `?` before a statement is stored in history. `WHERE email = 'ann@example.com'` is stored as `WHERE email = '?'`. The SQL sent to the database is never changed. The error text a server returned is stored as it was received.

## Saved queries

1. Choose **Queries ▸ Save Current Query**.
2. Enter a **Name** and choose **Save**.

The name starts as the query's first line. A saved query belongs to the database service it was saved on.

Choose **Queries ▸ Saved Queries** to find one by name or SQL and put it in the editor. The list shows this service's saved queries, most recently used first, with how many times each was used. Saved queries remain available after the app restarts. Swipe to **Delete** one.

A saved query also opens from Siri and Shortcuts, and on Mac from the Command Palette as **Open Query:** followed by its name. It opens in a new SQL tab, connecting first if needed, and is never run. See [Siri, Shortcuts and the rest of the system](library-siri-and-system.md).
