# Open the Editor

The Editor is a text and code editor built into Glass Power Tools. This page covers the ways into it on each platform, what an editor window holds, and how you leave it.

## Open the Editor

On Apple Vision Pro, iPad and iPhone there is no File menu, so you reach the Editor from the library or from a server's files:

- Choose **Projects** in the library, select a project, and choose **Open**. See [Work with projects](editor-projects.md).
- In a Terminal service's Files browser, choose **Edit** on a file, or **Open in Editor** on a folder. See [Projects on a server](editor-projects.md#open-a-folder-on-a-server).

**On Mac:** you can also use the File menu from any window:

| Command | Shortcut | What it does |
|---|---|---|
| **New Editor Window** | ⇧⌘E | Opens a new editor window on a new, empty document, ready to type into. |
| **Open File…** | ⌘O | Asks for one or more files, then opens them. |
| **Open Project…** | ⌥⌘O | Asks for a folder, then opens it as a project. |
| **Open Recent** | — | Lists files you opened recently on this Mac. **Clear Menu** empties the list. |

A file or folder you choose from the File menu opens in the editor window in front. A new window opens only when no editor window is open. If you cancel the panel, nothing opens.

The Editor does not open by itself when the app starts. The library is the first thing you see.

## What an editor window holds

Each editor window has its own set of documents. A second window starts empty; it does not show the first window's tabs. Your text size, line-number and wrapping settings, and the recent files list, are shared by every window.

- Open documents appear as tabs across the top once there are two or more.
- The file list on the left appears only when a project is open. With no project, the window shows just the document.
- The bar at the bottom shows the cursor position, the language and the line endings. See [Languages and syntax highlighting](editor-languages.md).

An empty editor window shows **No Document** with three buttons: **Open Project…**, **Open File…** and **New Document**. You can also drop files onto any editor window to open them.

## Start a new document

Choose **New Document** (the plus button in the toolbar). Each new document is named **Untitled**, then **Untitled 2**, and so on, until you save it.

**On Mac:** ⌘N in an editor window also makes a new document. The File menu names it **New Document** while an editor window is in front.

## Leave the Editor

On Apple Vision Pro and iPad, close the editor window as you close any window.

**On iPhone:** the Editor fills the screen. The back chevron in the top corner returns to **Connections**, the library. Your open documents and project are kept, including unsaved changes. To return, choose the editor session in **Active** (the lightning bolt). Its row shows how many files are open and how many are unsaved. Swipe the row to end the session.

**On Mac:** ⌘W closes the document in front. When it is the last document and no project is open, the window closes with it. When a project is open, the window stays on the project, and ⌘W again closes the window. If the document has unsaved changes, you are asked first. See [Save your work](editor-saving.md#close-a-document).

> [!NOTE]
> There is no Close Project command. Closing the editor window closes its project. On iPhone, ending the session in **Active** closes it.
