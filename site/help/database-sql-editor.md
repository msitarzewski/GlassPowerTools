# Write and run SQL

This page covers SQL documents: opening one, running statements, Explain Plan, cancelling, formatting, saving and opening `.sql` files, query history with literal redaction, and saved queries.

## Open a SQL document

Choose **SQL Editor** in the workspace's toolbar or in the overview. Each SQL document is its own tab. Its title is taken from the SQL, for example `shop.orders` for a simple `SELECT`, and on a device with Apple Intelligence the on-device model may suggest a short title instead.

**On Mac:** **File ▸ New SQL Document** is ⌘N while a database workspace is in front.

As you type, the editor suggests keywords, functions and the names of tables and columns in the active database. Press Tab to accept the dimmed suggestion.

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

A single `SELECT` returns at most 1,000 rows. When there are more, the bar under the results says **more available — loaded result limited to 1000**. Other statements are sent as written.

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

History keeps the latest 500 statements and survives relaunch.

> [!NOTE]
> Before a statement is stored in history, quoted strings are replaced with `'?'` and numbers with `?`. `WHERE email = 'ann@example.com'` is stored as `WHERE email = '?'`. The SQL sent to the database is never changed. The error text a server returned is stored as it was received.

## Saved queries

1. Choose **Queries ▸ Save Current Query**.
2. Enter a **Name** and choose **Save**.

Choose **Queries ▸ Saved Queries** to find one by name or SQL and put it in the editor. Saved queries remain available after the app restarts. Swipe to **Delete** one.
