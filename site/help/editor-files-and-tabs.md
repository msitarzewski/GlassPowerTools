# Files, Folders and Tabs

This page covers the file list of an open project, how files open into tabs, and how to create a new file in a project folder — on this device or on a server.

## Browse a project's files

On Apple Vision Pro, iPad and Mac, the project's files are a list on the left of the editor window. **On Apple Vision Pro**, the list is titled **Files**; to hide or show it, choose the sidebar button beside the document's name at the top of the window (⌃⌘S with a keyboard). Folders come first, then files, each sorted by name. Choose the disclosure triangle beside a folder to open it. A folder on a server is read when you first open it, and shows a progress indicator while it is read. A folder that cannot be read shows a warning symbol; hold the pointer over it to see why. On iPhone the folder's screen says why instead.

Type in **Filter** above the list to show only the entries whose names contain what you typed.

Some folders are never listed because they hold tooling rather than work: `.git`, `.build`, `.DS_Store`, `node_modules`, `.swiftpm` and `DerivedData`.

**On iPhone:** a folder is its own screen. Tap a folder to go into it, and use the back button to go up. Each screen shows the folder's name and its path, and has its own **Filter** field.

## Open a file

- **One click or tap** opens the file in a *preview tab*, shown in italics. The next file you choose with one click takes its place, so looking through a folder does not leave a tab behind for every file.
- **Double-click or double-tap** keeps the file open in its own tab.
- A preview tab is also kept as soon as you edit or save it.

With the keyboard, use the up and down arrow keys to move through the list, and Return or ⌘↓ to open the selected file. Return on a folder opens or closes it.

Opening a file that is already open selects its tab instead of opening a second copy.

## Work with tabs

When two or more documents are open, they appear as tabs above the text. Choose a tab to show it, or its close button to close it. **On iPhone, iPad and Vision Pro**, **Close Document** (×) in the toolbar closes the document in front, including when it is the only one, and **Find** (magnifying glass, or ⌘F with a keyboard) opens the find bar. **On Mac**, use **File** ▸ **Close** (⌘W) and **Edit** ▸ **Find** (⌘F). A tab whose document has unsaved changes shows a dot after its name. Hold the pointer over a tab to see its folder, and the machine it is on when that is not this device.

**On Mac:** the window's subtitle shows the project name and its folder, or the folder of a file opened on its own. **On Apple Vision Pro**, the same is at the right-hand end of the status bar at the bottom of the window.

## Create a new file in a project

1. In the file list, open the context menu on a folder, or on a file in the folder you want.
2. Choose **New File…**.
3. Type a **File name** and choose **Create**.

The file is created empty in that folder — on this device or on the server — appears in the list, and opens in the Editor. A name cannot be empty or contain a slash. If a file with that name is already in the folder, nothing is created and you are asked to choose another name.

The same context menu has **Open** (or **Open Folder**) and, on a folder, **Refresh**, which reads that folder again.

## Open a file on its own

A file does not need a project. Open one with **Open…**, by dropping it on an editor window, or with **Edit** in a Terminal service's Files browser. It opens as a tab in the editor window in front. The file list stays hidden while no project is open.

**On iPhone:** **Edit** in the Files browser opens the Editor over the browser. The back chevron, **Files**, returns to the browser with its connection still open.

## Files that are not text

Images, PDFs, video, audio and other binary files open in a viewer rather than as text. See [Preview and viewers](editor-preview-and-viewers.md).
