# Save Your Work

This page covers saving a document, choosing where a new document goes the first time you save it, what happens when a file changed after you opened it, and closing a document with unsaved changes.

## Save a document

Choose **Save** (the save button in the toolbar). It is available when the document has unsaved changes, and for a document that has never been saved, even before you type anything. The bar at the bottom of the window shows **Edited** until you save.

**On Mac:** choose File ▸ **Save**, or press ⌘S. For a document that has never been saved, the menu item reads **Save…**.

**On Vision Pro, iPad and iPhone**, with a keyboard, ⌘S does what **Save** does: a document that has never been saved asks where to save it.

A save keeps the file's text encoding and its line endings as they were when you opened it, so saving an unchanged file leaves it byte for byte the same. A file on this device is written through a temporary file and then moved into place, so an interrupted save does not leave a half-written file, and a file that was executable stays executable.

## Save a new document for the first time

What you see depends on whether the window has a project open.

**With a project open**, a **Save** sheet asks for:

1. **Name** — the file name, including its extension.
2. **Folder** — the project's top folder, where it starts, or any folder its file list has already read. A folder on a server shows the machine's name after it.
3. Choose **Save**.

The file is written to that folder, on this device or on the server, and the tab takes its name. Its language is chosen from the new extension. If a file with that name is already in the folder, nothing is written and the sheet asks you to choose another name. On a server, the new file is uploaded under a hidden name and checked, then given its name only if that name is still free, so a half-written file never appears under it. If the server refuses, the message says why in plain words, for example that the account isn't allowed to write to that folder, and what to check.

To save somewhere outside the project, choose **On This Device…** in the sheet. **On Mac** the button reads **On This Mac…**.

**With no project open**, the system's save panel opens directly.

**On Mac:** the save panel writes exactly the name you type — a file named `.env` stays `.env`, with no extension added.

## When the file changed after you opened it

Before every save, the Editor checks whether the file changed since you opened it — on a server, or on this device through a checkout, a build or another app. It also looks when the file's window comes forward and when you choose its tab, so you hear about a change before you edit an old copy. Each change is asked about once. If the file changed, a **The file has changed** message explains what it found, and offers:

- **Save Anyway** — replaces the file with your version.
- **Discard My Changes and Reload** — throws away your edits and shows the file as it is now.
- **Keep Editing** — saves nothing and leaves your edits in place.

If the file could not be checked at a save, the message says it may have changed and offers the same choices.

When you have no unsaved changes, there is nothing of yours to keep, so the choices are **Reload** and **Keep Editing**.

> [!IMPORTANT]
> **Save Anyway** replaces the version that was there when the message appeared. If the file changes again while the message is showing, nothing is written and you see: "… changed while it was being saved, so nothing was written. Save again to see what it looks like now."

If the connection to a server drops during a save, the Editor cannot tell whether the file was replaced, and says so. Open the file again to see which version is there.

## Close a document

Close a document with its tab's close button, with **Close Document** (×) in the toolbar on iPhone, iPad and Vision Pro, or **on Mac** with ⌘W. Tabs appear once two or more documents are open. If it has unsaved changes, **Close without saving?** offers:

- **Save** — saves, then closes. A never-saved document first asks where to save it. If the save fails, or stops to ask about a file that changed, the document stays open with your changes.
- **Discard Changes** — closes without saving.
- **Cancel** — keeps the document open.

**On Mac:** when ⌘W closes the last document in a window with no project, the window closes too. **Cancel**, in the message or in the save panel, keeps both open.

> [!WARNING]
> Closing the editor window itself, quitting the app on the Mac, or closing the editor session in **Active** does not ask: unsaved changes are lost. See [Leave the Editor](editor-opening.md#leave-the-editor).
