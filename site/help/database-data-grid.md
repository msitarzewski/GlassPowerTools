# Browse table data

This page covers reading a table: its five views, sorting, filtering and paging rows, choosing columns, analyzing, following a foreign key and exporting. Changing rows is covered in [Edit rows and structure](database-edit-rows.md).

## Switch between a table's views

A table tab has five views: **Data**, **Structure**, **DDL**, **Indexes** and **Foreign Keys**.

- **On Vision Pro:** choose a view from the tab bar at the side of the window.
- **On Mac:** choose one of the five icon buttons in the toolbar.
- **On iPad and iPhone:** choose the menu in the toolbar that shows the current view's name.

**Data** shows the table's generated `SELECT` in an editor above a grid. You can edit that SQL and run it; drag the handle under the editor to resize it.

## Sort rows

- Select a column header to sort by it ascending, again for descending, and a third time to remove the sort. Selecting other headers adds further sort keys, numbered in the header, for example `2↑`.
- Open a header's context menu for **Sort Ascending**, **Sort Descending** and **Remove Sort**, and for **Freeze**, **Hide**, **Move Left** and **Move Right**.

In a table, sorting asks the server for the rows in that order. Sorts, filters and page size are remembered for each table.

## Filter rows

1. Choose **Filter**. The **Filter Rows** sheet opens.
2. Choose how filters apply. **Update SQL Query** adds bound conditions to the `SELECT` and reloads from the database. **Display Only** hides rows on the loaded page without contacting the database.
3. Choose a **Column** and a **Condition** (**Equals**, **Does Not Equal**, **Greater Than**, **Less Than**, **Is NULL** or **Is Not NULL**), enter a **Value**, and choose **Add Condition**. Each column can have one condition.
4. Choose **Done**.

A value that cannot fit the column's type is reported before the query runs. The **Filter** button's icon fills in while conditions are active, and VoiceOver reads how many.

## Page through rows

The bar under the grid shows the rows loaded, the total when known, and the time taken. Use the arrows to change page, and type a value from 1 through 10,000 in **Per page:** (100 by default). Choose **Calculate Total…** to run an exact count, stopped after 30 seconds.

## Choose, freeze and resize columns

Choose **Columns** to open **Manage Columns**. Turn **Visible** and **Frozen** on or off for each column, or use **Show All**, **Hide All**, **Unfreeze All** and **Reset**, then choose **Done**. Frozen columns stay at the leading edge while you scroll. Drag the mark at a header's trailing edge to resize a column.

## Select, copy and compare

- Select a cell to select it; select a row number to select the whole row. **On Mac:** Shift-click a row number to extend the selection and Command-click to add or remove a row.
- **More** (…) **▸ Extend Selection** extends a cell selection left, right, up or down.
- **Copy** copies the selection as tab-separated text.
- **More** (…) **▸ Compare Rows** lists the differences between exactly two selected rows.

## Analyze

**Analyze** groups and aggregates the table through a bounded server query. Use **Group Columns**, **Add Count All** and **Add Column Aggregate** (**Count**, **Sum**, **Average**, **Minimum** or **Maximum** of a column), and **Clear Analysis** to return to the rows.

## Follow a foreign key

Open a row number's context menu, choose **Follow Reference**, then the relationship, for example `customer_id → customers.id`. The referenced table opens in its own tab, filtered to the matching row. A relationship is unavailable when the row's value is `NULL`. The **Foreign Keys** view also opens the referenced table of each relationship.

## Export

Choose **Export** and then **CSV**, **JSON** or **SQL**, and pick where to save. The export contains the selected rows, or every row on the loaded page when nothing is selected. **SQL** writes one `INSERT` statement per row.

**On iPhone:** the grid's bar keeps **Filter**; **Choose Columns**, **Copy Selected Rows** and **Count All Rows** are in the **More** menu, and **Export** is in the toolbar.
