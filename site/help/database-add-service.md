# Add a database service

This page covers adding a database to a host, the engines Glass Power Tools supports, and every field in the database setup sheet, including the read-only option.

## Supported engines

The database capability connects to three engines:

- **MySQL**, default port 3306, default username `root`. MariaDB servers use this engine.
- **PostgreSQL**, default port 5432, default username `postgres`.
- **SQLite**, a database file on this device. It has no address, port, username, password, encryption or tunnel.

## Add a database to a host

1. Select the host in the library, for example `alpha`.
2. In **Services**, choose **Add a service…**.
3. If the sheet offers more than one kind of service, choose **Database** in the segmented control at the top.
4. Choose the **Engine**.
5. For MySQL or PostgreSQL, fill in the required rows:
   - **Database**: optional. The prompt reads **Optional — all databases if blank**. For MySQL, a blank value lets the browser list every database the account can see. For PostgreSQL the browser always lists the schemas of the database you connect to.
   - **Username**: required, for example `ann`.
   - **Password**: optional. A blank password is saved as no password, which is correct for servers that use socket, peer or trust authentication. When you edit a service, the prompt reads **Leave blank to keep saved password**.
6. Open **Advanced** to change anything else (see below).
7. Choose **Add**.

When you add a new host with **Add Host**, the same database rows appear on the host sheet, so you can create the machine and its database in one save.

> [!NOTE]
> The address belongs to the host, not to the database service. If you change the host's address, every MySQL and PostgreSQL service on that host follows it.

## Add a SQLite file

1. Add a Database service and choose **SQLite** as the **Engine**.
2. Choose **Choose SQLite File** and pick the database file, usually a `.sqlite`, `.sqlite3` or `.db` file.
3. The row **Database File** shows the file name. If **Name** under **Advanced** was blank, it is filled with the file name, without its extension.
4. Choose **Add**.

The app imports a private working copy of the file. The original is left unchanged, and changes you make in the app are made to the copy, which lives on this device. To use a newer version of the original, choose **Choose Different File** while editing the service.

## Advanced options

| Row | What it does |
|---|---|
| **Name** | The name shown in the library. Blank uses the database name, or the engine, with the host's name, for example `shop on alpha`. |
| **Port** | The server's port. Must be from 1 through 65535. |
| **Reach it through this machine's Terminal service** | Opens the connection through the host's SSH service. When another machine in your library has a Terminal service, this is a **Connect** menu instead: **Directly**, **Through this machine's Terminal**, or **Through** another machine. See [Encryption and the SSH tunnel](database-encryption-and-tunnel.md). |
| **Database address** | Shown when the connection goes through this machine's Terminal. Blank, the prompt **This machine**, means the database is on the machine itself; otherwise enter the address of a database server that only this machine can reach, as this machine sees it. |
| **Encrypt the database connection** | Turns on TLS and shows **Verification**. See [Encryption and the SSH tunnel](database-encryption-and-tunnel.md). |
| **Read-only** | Refuses every statement that is not a read. See below. |
| **Rows per page** | How many rows a table you have not opened before shows at a time, from 1 through 10,000. Blank means 100. See [Page through rows](database-data-grid.md#page-through-rows). |
| **Color tag** | A color for the service. The tag's name is shown in the confirmation before a table is truncated or dropped. |

Changing the **Engine** resets the port, username, database, encryption, certificate and tunnel to the new engine's defaults.

## Make a service read-only

1. Edit the service, open **Advanced** and turn on **Read-only**.
2. Choose **Save**.

With **Read-only** on, the connection itself refuses any statement it cannot classify as a read before it is sent. This covers the SQL editor, the data grid, the record editor, pasted ranges, row deletion, the Structure, Indexes and Foreign Keys tools, and **Truncate Table…** and **Drop Table…** in the schema browser. `USE`, `SET`, `EXPLAIN` and transactions are still allowed. A refused statement reports that the service is set to read-only and that you can turn it off in the service's settings.

## Edit or remove a service

- To edit, choose the **Edit** button (a pencil) on the database's row in the host's **Services** section. The sheet is titled **Edit Database on alpha** and its button is **Save**.
- To remove, open the row's context menu and choose **Remove Service**. The saved password and, for SQLite, the imported copy are removed with it.
