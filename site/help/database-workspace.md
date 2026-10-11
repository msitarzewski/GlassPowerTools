# The database workspace

This page covers connecting to a database, finding your way around the workspace, the overview and its charts, the schema browser's commands, the Mutation Log, ending a session, and giving a database window its own settings.

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

Open **Settings** and choose **Databases**. The same page is **All Databases** in a database window's own settings, under the gear in its toolbar.

- **Result row limit** and **Query history limit** keep memory use bounded.
- **Redact literals in query history** replaces quoted strings and numbers before a statement is kept in history. It never changes what is sent to the database.
- **Notify when a query fails** shows a private notification with no SQL, schema names or server details.
- **SQL editor text** and **Results grid text** set their text sizes, with line numbers and JSON formatting in the record editor.

## Give a database window its own settings

A database window can keep settings of its own, so one window can have larger text or lighter glass than the rest. Choose **Settings** (gear) in the workspace's toolbar, then **This Window**. **All Databases**, beside it, changes every database window.

- **On Mac:** the gear is at the end of the toolbar, and Settings opens on **This Window**. The app's own Settings are still in the app menu, or press ⌘,.
- **On iPad:** the gear is in the toolbar at the bottom, or in the ⋯ menu when the window is narrow. Choose **This Window** from the list.
- **On Vision Pro:** the gear is in the bar below the window, and Settings opens on **This Window**.

**This Window** has:

- **Appearance**: **Opacity** and **Glass**, which otherwise follow **Appearance** in Settings. They change the canvas behind the window's tabs, editor and results; the schema sidebar keeps the system's material. **On Vision Pro**, **Appearance** has **Opacity** only: it paints the theme color behind the whole window, which tints visionOS's own glass, and under the SQL editor and the results. At 0% the window is visionOS's own glass.
- **Query**: **Result row limit**.
- **Editor**: **SQL editor text**, **Results grid text**, **Show line numbers** and **Format JSON automatically while editing**.

Each setting follows **All Databases** (or **Appearance**) until you change it here. Once you do, a small ↺ appears beside its name; choose it to follow again. Its tooltip says what it returns to: hold the pointer over it, or on Vision Pro look at it. **Reset This Window**, at the end, returns every one. Only this window changes, and it changes at once.

A database window doesn't reopen when the app relaunches, so its settings are kept for its database: the next window you open on that database starts with them, after a relaunch too. **Open in New Window**, in the schema browser, gives the new window the settings of the one you opened it from. They're kept on this device.

Some settings are only ever for every window. **Query history limit**, **Redact literals in query history** and **Notify when a query fails** govern the history and notifications every window shares, and **Show schema sidebar when space allows** only decides how a new window starts on iPad. **Read-only** belongs to the database service; see [Make a service read-only](database-add-service.md#make-a-service-read-only). **Material**, in **Appearance**, doesn't change a database window, so **This Window** doesn't offer it.

**On iPhone:** the workspace is a screen rather than a window, so **Settings**, in the ⋯ menu, opens **All Databases**.
