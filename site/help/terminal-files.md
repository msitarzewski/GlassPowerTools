# Browse and transfer files over SFTP

The file browser shows a machine's files over SFTP, using the host's Terminal service: its address, sign-in and host key. This page covers opening the browser, moving around, uploading and downloading, creating, renaming and deleting items, inserting paths into a terminal, and editing files.

## Open the file browser

- In the library, select the host, then choose **Files** in its detail.
- In a terminal, choose **Open Folder Here** to open the folder the shell is in. To open that folder in the Editor instead, choose **Open Folder in Editor** in the terminal's tools menu (see [The session's tools menu](terminal-sessions.md#the-sessions-tools-menu)).
- **On Mac:** in the command palette (⇧⌘P), choose **Open Files on** followed by the machine's name, for example **Open Files on alpha**.
- **On Mac and Vision Pro:** on a path a terminal shows, choose **Show in Files** (right-click it on Mac; pinch and hold it on Vision Pro). The browser opens at the path's folder. See [Links and paths](terminal-sessions.md#links-and-paths).

**On Vision Pro and Mac**, the browser opens in its own window. **On iPad and iPhone**, it opens as a sheet over the library or terminal.

Choose **Done** to close the browser. This also closes its SFTP connection.

## Move around

The title shows the folder's name with its path beneath it. **Parent Directory** at the top of the list goes up one level.

**On Vision Pro:** **Back** (‹), beside **Done**, returns to the folder you opened this one from (⌘[ with a keyboard). Choose the folder's name for a menu of the folders above it. The window's glass follows **Glass** in **Appearance**; with **Glass** and **Opacity** at 0% it is completely clear apart from its text and controls.

- **On Vision Pro, iPad and iPhone:** tap a folder to open it. Use the disclosure arrow to show its contents in place.
- **On Mac:** the list is a table with **Name**, **Size**, **Modified**, **Permissions** and **Actions**. Double-click a folder to open it. Select a folder and press → to expand it or ← to collapse it. Click a column header to sort.

Type in **Filter files...** to narrow the current list. Press Return to search the server instead: it looks up to three folders deep from here and shows the first 50 matches.

In the menu under the ellipsis (…) button in the toolbar, **Show Hidden Files** (⇧⌘.) shows names that begin with a dot, and **Refresh** reloads the folder.

## Upload files

- Choose **Upload File** in the ellipsis (…) menu and pick one or more files.
- Or drag files from another app onto the browser. Drop them on a folder row to upload into that folder.

Only files can be uploaded, not folders. An upload never replaces a file on the server: if the name is taken, the upload gets a number, for example `notes (2).txt`.

## Download files

1. Select one or more files, then choose **Download**, or use the download button on a file's row.
2. Pick a folder on this device.

If the folder already has a file with that name, the download gets a number instead of replacing it. Folders cannot be downloaded; select the files inside them.

**On Mac:** you can also drag a file from the table to the Finder, or select files, choose **Copy** (⌘C) and paste them in the Finder (⌘V). The copy downloads the files first, with its progress in the browser; until it finishes, pasting gives the files' `sftp://` addresses. To upload, copy files in the Finder and press ⌘V in the browser.

The bar at the bottom shows each transfer's progress. Its cancel button stops the current batch; **Clear History** removes finished items.

## Create, rename, copy, move and delete

Right-click an item, or touch and hold it, for its menu.

- **New Folder** and **New File** are in the ellipsis (…) menu. A new file opens in the editor straight away.
- **Rename** asks for a new name. **On Mac** it edits the name in place; clicking the name of a selected item does the same.
- **Remote** > **Copy…** or **Move…** copies or moves items to another folder on the same machine. Choose the folder, then **Copy Here** or **Move Here**.
- **Delete** asks you to confirm.

> [!NOTE]
> Delete removes a folder only when it is empty. Delete the folder's contents first.

To act on several items at once, select them; **Select All** (⌘A) in the ellipsis (…) menu selects everything. **On Vision Pro, iPhone and iPad**, choose **Select…** in that menu first, or swipe right on a file. While items are selected, a bar at the bottom offers **Download**, **Delete** and **Deselect All**.

**Get Info** shows a file's size, modification date, read-only permissions and SFTP address.

## Insert a path into the terminal

When you open the browser from a terminal with **Open Folder Here**, you can type paths into that terminal. Choose **Insert Path** in an item's menu, or select several items and choose **Insert** in the bar at the bottom. Their paths on the host are typed at the terminal's cursor, escaped for the shell and separated by spaces. Nothing is run.

- **On iPhone and iPad**, the browser then closes and you're back in the terminal. If a transfer is still running, the browser stays open so the transfer can finish.
- **On Vision Pro**, the terminal's window comes forward and the browser stays open.
- **On Mac**, the browser stays in front; click the terminal to carry on.

A browser opened from the library has no terminal, so **Insert Path** isn't offered there.

## Edit a file

Choose **Edit** in a file's menu, or its edit button. **On Vision Pro, iPad and iPhone** you can also tap the file.

- **On Vision Pro, Mac and iPad**, the file opens in the Editor's window as a tab.
- **On iPhone**, the file opens within the browser.

A file that isn't text, such as a picture, a PDF, a video, audio or a 3D model, opens in the Editor's viewer instead; see [Preview and Viewers](editor-preview-and-viewers.md).

When you save, the app writes the file back to the server and checks that nothing else changed it in the meantime. See the Editor's help for saving and conflicts.

For a folder, **Open in Editor** opens it as a project in the Editor.
