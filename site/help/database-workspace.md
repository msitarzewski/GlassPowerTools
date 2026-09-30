# The database workspace

This page covers connecting to a database, finding your way around the workspace, the overview and its charts, the schema browser's commands, the Mutation Log and ending a session.

## Connect

1. Select the host, for example `alpha`, in the library.
2. Choose **Connect** on the database's row in **Services**.

The workspace opens in its own window. On Vision Pro it is a window you can place anywhere, and closing it ends the session. On Mac and iPad, closing the last window on a session ends it too.

**On iPhone:** the workspace replaces the library on the same screen. Use **Connections** at the top left to go back to the host, and **Disconnect** in the ⋯ menu to end the session.

Once a database is connected, the host's **Query** row opens its workspace. If nothing is connected yet, it asks you to connect first.

## Find your way around

The sidebar is the schema browser. Its title is **Databases** for MySQL and SQLite, and **Schemas** for PostgreSQL, where it lists the schemas of the database you connected to. Expand one to see its tables and views. Use the search field (**Filter**, or **Filter databases and tables** on iPhone and iPad) to narrow the list.

- **Select** a database or table to preview its statistics.
- **Open** it in a tab by double-clicking on Mac, or double-tapping on Vision Pro and iPad. A table opens with its data.
- **On iPhone:** tap a database to see its tables, then tap a table. Each table row also has a **Table Actions** menu.

Tabs appear once more than one is open, and a trail above the content shows where you are.

**Connections**, at the leading edge of the toolbar, returns to the host in the library.

## Read the overview

The first tab, **Overview**, shows:

- **Server version**, **Tables** and **Table storage**.
- **Connection Details**: **Endpoint**, **User**, **Transport**, the active database or schema, and **Tunnel** when one is open.
- Two charts, **Largest by Rows** and **Storage Distribution**. Point at a bar, or tap it, to see its value. Values marked `~` are server estimates.
- **SQL Editor**, which opens a new SQL document.

A database tab shows the same kind of summary for its tables, with **Set as Active** and a list of tables. For MySQL, **Set as Active** runs `USE` so unqualified SQL resolves in that database. Choose **Refresh Overview** in the toolbar to reload statistics. **On Mac:** the toolbar button is **Refresh**.

## Commands in the schema browser

Open the context menu on a database for **Open Database in Tab**, **Set as Active Database** (MySQL only), **Open SQL Editor**, **Open in New Window** and **Refresh**.

Open the context menu on a table for:

- **Browse Data**.
- **Copy Table Name** and **Copy SELECT Statement**, which copy quoted names.
- **Calculate Exact Row Count…**, which runs `SELECT COUNT(*)` after you confirm. It is stopped after 30 seconds, and you can cancel it while it runs.
- **Truncate Table…** (MySQL and PostgreSQL) and **Drop Table…**. The confirmation names the connection, its color tag, the table and the operation.

> [!WARNING]
> On MySQL, `TRUNCATE` and `DROP TABLE` commit immediately and cannot be rolled back.

## Review the Mutation Log

Choose **Mutation Log** in the sidebar's toolbar (in the overflow menu where space is short). It lists the row and schema changes made from table tabs, and the destructive operations from the schema browser, with the outcome and the number of rows affected. Row values are never recorded, only which columns identified the row.

Turn on **All Connections** to include every service. **Clear Log…** removes every entry for every connection and changes nothing in any database.

## When the connection drops

If the server closes the connection, the workspace shows **Disconnected** and keeps your tabs. Choose **Reconnect** to reconnect with the saved password, or **Show Connections** to go back to the host. If Local Network access is off, the message says to allow it in Settings.

## Keyboard and menus on Mac

- **File ▸ New SQL Document** (⌘N while a database workspace is in front) and **Open SQL Document…** (⇧⌘O).
- **File ▸ Close Active Tab** (⇧⌘W). ⌘W also closes the active tab rather than the window.
- **File ▸ New Connections Window** (⇧⌘N).
- **Command Palette…** (⇧⌘P or ⌘K). Type `connect:` to connect a saved database, or a connected service's name and a period to step into its databases and tables.

## Database settings

Open **Settings** and choose **Databases**:

- **Result row limit** and **Query history limit** keep memory use bounded.
- **Redact literals in query history** replaces quoted strings and numbers before a statement is kept in history. It never changes what is sent to the database.
- **Notify when a query fails** shows a private notification with no SQL, schema names or server details.
- **SQL editor text** and **Results grid text** set their text sizes, with line numbers and JSON formatting in the record editor.
