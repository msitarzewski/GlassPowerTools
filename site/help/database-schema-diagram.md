# See a database's diagram

This page covers the schema diagram: every table in a database as a card, with its columns and keys, and a line for every foreign key between them. The diagram is read from the server each time it opens, so it always matches the database as it is now.

## Open the diagram

Choose **View Diagram** in a database's overview, beside **Set as Active** and **SQL Editor**. Or, in a database workspace's sidebar, open the context menu on a database and choose **Show Diagram**. To start with one table selected, open the context menu on the table instead and choose **Show in Diagram**.

- **On Vision Pro:** the diagram opens in its own volume, in three dimensions.
- **On Mac and iPad:** it opens in its own window.
- **On iPhone:** it opens over the workspace. Choose **Done** to close it.

While the diagram loads, it shows how many tables it has read. A database with more than 300 tables shows the first 300 by name, and the summary says so: at the bottom of the window, or **on Vision Pro** below the volume.

## Read a card

Each card is one table. Its name is at the top, then one row per column with the column's type.

- A key symbol marks a primary key column.
- An arrow marks a column that is part of a foreign key.

Each foreign key is one line, from the columns that hold it to the table they point at. A key made of several columns is one line. **On Mac, iPad and iPhone**, a table whose key points at itself shows a small loop on its own card.

**On Mac, iPad and iPhone**, the end of a line with a crow's foot is the table that holds the key; the end with a bar is the table it points at.

## Find your way around

- Select a card to light up every table it is joined to; the rest fade. Select the empty background to clear it. **On Vision Pro**, select the card again to clear it.
- **Keys Only** shrinks every card to its key columns, which makes a large schema easier to follow.
- Choose **Refresh** after changing the schema to read it again.
- To open a table, select its card and choose **Open Table**, or double-click (double-tap) the card. The table opens in a workspace window on the same connection. **On iPhone**, the diagram closes and the table opens in the workspace.

**On Vision Pro:** walk around the volume, or drag any card to turn the whole diagram. **Turn Left**, **Turn Right** and **Face Front** are below the volume. Cards always turn to face you.

**On Mac, iPad and iPhone:** drag a card to move it; its lines follow. The diagram opens fitted to the window, on the selected table when there is one. Pinch to zoom, or use **Zoom In**, **Zoom Out** and **Zoom to Fit** in the toolbar. **On Mac:** hold Command and scroll to zoom toward the pointer; drag the empty canvas to move around it, or hold Option-Space and drag from anywhere, cards included. Type in **Find a table** to outline every table whose name matches, and press Return to select the first.

## Limits

- The diagram shows one database (on PostgreSQL, one schema) at a time. A key to a table in another database or schema is not drawn; the summary counts it.
- Card positions are worked out each time the diagram opens. Cards you move are not remembered.
- Views appear as cards with their columns, and have no keys.
