# Work with Projects

A project is a folder on a machine: a folder on this device, or a folder on a server that you reach through that server's Terminal service. This page covers opening projects, the **Projects** list in the library, and how the list follows you between devices.

## Open a folder on this device

1. In the library, choose **Projects**.
2. Choose the plus button in the toolbar, then **Open…** — or **Open a Project…** in the empty list.
3. Choose a folder.

The folder opens in an editor window and is added to **Projects**. Files chosen here instead open as tabs in an editor window, without a project. The same plus button has **New Document**, which opens an editor window on a new, empty document.

You can also choose **Open…** in an editor window (the folder button in the toolbar, or ⌘O with a keyboard) and pick a folder. **On Mac:** choose File ▸ **Open…** (⌘O), or **Open…** in an empty editor window. A folder opened any of these ways is added to **Projects** too.

Each project opens in its own editor window. Opening a project that is already open brings its window forward. When the editor window in front is empty, the project opens there rather than in a new window.

If a project is open but no longer in **Projects** (you removed it while its window was open), the toolbar shows **Save as Project**; choose it to keep the folder in the list.

**On Apple Vision Pro, iPad and iPhone:** a folder you pick from the Files app opens again from **Projects** after the app restarts. This device keeps its own permission to read that folder; it is not synchronized.

## Open a folder on a server

1. Connect to the machine's Terminal service and open its Files browser.
2. Open the context menu on a folder and choose **Open in Editor**.

The folder opens as a project in an editor window, over an SSH connection of its own made with the Terminal service's sign-in and host-key trust, and saves go back to the server. If that connection is lost, the project makes a new one the next time it reads a folder or a file, or saves. If it can't, it says so, for example **The connection to alpha was lost and could not be made again. Check that alpha is on and reachable, then try again.** The project is added to **Projects**, tied to that machine, so you can open it again from the list on any of your devices that has the machine in its library.

To edit one file without opening its folder, choose **Edit** on the file instead.

## Open a project from the list

1. In the library, choose **Projects**, then select a project.
2. Choose **Open**.

The detail shows the project's **Folder**, **Machine** and **Last Opened** date. **Machine** says how this device reaches it, and **Availability** below says the same in a sentence:

- **On this Mac** (**On this device** on Vision Pro, iPad and iPhone) — the folder is on this device and opens from its file system.
- **Over SSH · alpha** — the folder is on alpha and opens over its Terminal service.
- **alpha — no terminal service** — the machine has no Terminal service in your library, so **Open** is unavailable. Add a Terminal service to the machine and the project opens over it.

If a folder on this device is no longer there, **Open** says so: remove the project, or put the folder back.

Use **Search Projects** to filter the list by name or folder path. The list is sorted by when each project was last opened, newest first.

## See what changed (git)

When a project's folder is in a git repository, the foot of its file list shows the branch and how many files differ from the last commit. The file list marks each changed file: **M** modified, **A** added, **D** deleted, **R** renamed, **U** new and not yet added to git, **!** a conflict. A dot marks a folder with a changed file somewhere inside it.

Choose the branch to open **Changes**, a tab with every changed file's lines since the last commit, in one scroll — what `git diff HEAD` shows, with new files in full. Each line has its number in the last commit and in the file now. Choose a file's name to fold its lines away, its open button to open the file, or a line to open the file at that line. **On Mac:** choose Text ▸ **Show Changes** (⌃⇧G).

**Changes** keeps itself up to date while it is open. The marks and the count are read again when the window comes forward, when you save, and when you choose **Refresh** at the foot of the file list.

The editor runs git where the folder is: this Mac's own git for a folder on this Mac, and the server's git, over the project's SSH connection, for a folder on a server — so a server's project shows its changes on iPhone, iPad and Apple Vision Pro too. If git isn't installed there, **Changes** says so and how to install it.

> [!NOTE]
> A folder on an iPhone, iPad or Apple Vision Pro itself shows no git: there is no git on those devices for the app to run.

### Commit

In **Changes**, each file has a box beside its name:

- **Empty**: not staged. Choose it to stage the file for the next commit.
- **Ticked**: staged. Choose it to take the file back out of the next commit. The file itself isn't changed.
- **A dash**: part of the file is staged, and it changed again after that. Choose it to stage the rest.

**Stage All** stages every file in the list; when every file is staged it reads **Unstage All**. A folder that is a git repository of its own is never staged.

Type a message in **Message** and choose **Commit**, or press ⌘↩. When nothing is staged the button reads **Commit All** and stages every file in the list first. After the commit, **Changes** says which commit it made.

If the project is a folder inside its repository, files staged elsewhere in the repository would be committed too, and **Changes** doesn't list them. **Changes** names them and asks first; choose **Commit** to commit them as well, or **Cancel**.

If git won't commit, **Changes** says why under the message, for example when git doesn't yet know your name and email on that machine, or when a hook stopped the commit.

### Marks beside the lines

An open file in a git project marks its changed lines beside the line numbers:

- **Green**: lines added since the last commit.
- **Amber**: lines changed.
- **Red wedge**: lines removed at that point.

The marks follow what you type before you save, and clear once the change is committed. A file git doesn't track yet is marked green throughout. The marks appear only while line numbers are shown.

## Rename or remove a project

- **Rename** changes what the project is called in the list. Type a **Name** and choose **Rename**. The folder is not moved or renamed.
- **Remove** takes the project out of the list on every device, after **Remove Project?** asks. The folder and its files are not touched.

Both are in the detail and in the row's context menu (**Open**, **Rename**, **Add Favorite** or **Remove Favorite**, **Remove from Library**). A favorite project is listed in **Favorites**; see [Favorites, collections and other names](library-organize.md).

> [!WARNING]
> Removing a project removes it from **Projects** on all your devices, not only this one.

## How the list syncs

The **Projects** list is kept on this device and, when you are signed in to iCloud, synchronized to your other devices. Only where each project is — the machine and the folder path, its name and its text settings — is synchronized. No file contents travel with it.

> [!NOTE]
> A folder you opened from this device's own file system is listed on your other devices too, but it opens only on a device where that folder exists.

## Project settings

With a project open, the bar at the foot of its file list has two buttons:

- **Project Settings** (the gear) opens a sheet with the project's **Name**, **Where** it is (**Machine** and **Folder**), its text settings, and **Refresh Files**. Choose **Done** to save a new name. See [Editor settings](editor-settings.md).
- **Refresh** reads the project's folders again, for example after a build or a checkout outside the Editor.

On Apple Vision Pro, iPad and Mac, when no file is open, the window shows an overview of the project: files in its top folder under **Agent Instructions** (such as `AGENTS.md` or `CLAUDE.md`), **Read First** (such as `README.md`), and **Build** (such as `Package.swift` or `Makefile`), and, for a project on this device, up to five of the files you opened recently under **Recently Edited**. It also says how the project is reached, and **Git repository** when the folder is one. Choose a file to open it.

**On iPhone:** opening a project shows its top folder's files instead. The same two buttons sit at the foot of every folder screen.
