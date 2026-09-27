# The on-device assistant

This page covers the three places the database capability uses Apple's on-device language model, what each one is given, and what it can and cannot do. Nothing is sent to a server: the model runs on your device through Apple Intelligence.

## When the assistant is available

The assistant needs a device that supports Apple Intelligence, with Apple Intelligence turned on and its model downloaded. When it is not ready, the assistant says why, for example **Enable Apple Intelligence in Settings to use the assistant.** or **The on-device model is still downloading or preparing. Try again later.** Choose **Check Again** after changing it.

Where the model is unavailable, the database works exactly the same without it; only the assistant's buttons are missing.

## Ask for a query

1. Open a table's **Data** view.
2. Choose the sparkles button in the toolbar. The **AI SQL Assistant** opens.
3. Type what you need in **Describe the query you need...**, for example "orders from the last seven days".
4. **On Vision Pro, iPad and iPhone:** choose the arrow button beside the field. **On Mac:** choose **Generate SQL**, or press Return.
5. Review the result under **Generated Query**, with the model's explanation and a badge such as **Read only**, **Changes data** or **Destructive**.
6. Choose **Insert into Editor** to put it in the table's SQL editor, or **Copy**.

The badge comes from the app's own classifier, not from the model. Inserting a query never runs it. When you run it, anything other than a read asks for confirmation as usual.

**What the model is given:** the database's name, and this table's name with its column names and types. No row values are included. The sheet shows this beside a lock icon: the number of tables and columns, the database name, and **No row values.**

## Get a suggested fix for an error

1. Run a query that fails.
2. On the error card, choose **Suggest Fix**.
3. Read **Potential Fix**: the problem, a corrected query and, under **Why this may work**, the model's reasoning.
4. Choose **Use in Editor** or **Copy Suggested SQL**.

If the suggestion would change data, the card says it will still require confirmation.

**What the model is given:** the query exactly as written, including any values in it, and the error message the server returned. From a table tab it is also given the database name and that table's column names and types; from a SQL document, only the active database's name.

## Automatic tab titles

When you pause typing in a SQL document, the model may give its tab a short title, such as "Orders by status". It is given the SQL with comments removed and every string and number replaced with `?`. If the model is unavailable or its answer is unsuitable, the tab keeps a title taken from the SQL.

> [!IMPORTANT]
> The model can be wrong. Treat every generated query and fix as a draft: read it before you run it, especially against a production database.

## Treatment of names and messages

Table names, column names, queries and error messages are passed to the model as data inside marked regions, with an instruction never to follow commands found in them. This limits, but cannot rule out, a crafted name or message steering the answer. The app's safety classification and confirmations apply whatever the model says.
