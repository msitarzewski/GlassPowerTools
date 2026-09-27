# Work with Projects

A project is a folder on a machine: a folder on this device, or a folder on a server that you reach through that server's Terminal service. This page covers opening projects, the **Projects** list in the library, and how the list follows you between devices.

## Open a folder on this device

1. In the library, choose **Projects**.
2. Choose **Open a Project…** (the plus button in the toolbar, or the button in the empty list).
3. Choose a folder.

The folder opens in an editor window and is added to **Projects**.

**On Mac:** you can also choose File ▸ **Open Project…** (⌥⌘O), or **Open Project…** in an empty editor window. A folder opened this way is not added to **Projects** automatically. The toolbar shows **Save as Project**; choose it to keep the folder in the list.

## Open a folder on a server

1. Connect to the machine's Terminal service and open its Files browser.
2. Open the context menu on a folder and choose **Open in Editor**.

The folder opens as a project in an editor window, over the same SSH connection the Terminal uses, and saves go back to the server. The project is added to **Projects**, tied to that machine, so you can open it again from the list on any of your devices that has the machine in its library.

To edit one file without opening its folder, choose **Edit** on the file instead.

## Open a project from the list

1. In the library, choose **Projects**, then select a project.
2. Choose **Open**.

The detail shows the project's **Folder**, **Machine** and **Last Opened** date, and an **Availability** note that says how this device reaches it:

- **On this Mac** — the folder is on this device and opens from its file system.
- **Over SSH · alpha** — the folder is on alpha and opens over its Terminal service.
- **alpha — no terminal service** — the machine has no Terminal service in your library, so **Open** is unavailable. Add a Terminal service to the machine and the project opens over it.

Use **Search Projects** to filter the list by name or folder path. The list is sorted by when each project was last opened, newest first.

## Rename or remove a project

- **Rename** changes what the project is called in the list. The folder is not moved or renamed.
- **Remove** takes the project out of the list on every device. The folder and its files are not touched.

Both are in the detail and in the row's context menu (**Open**, **Rename**, **Remove from Library**).

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

On Apple Vision Pro, iPad and Mac, when no file is open, the window shows an overview of the project: files in its top folder under **Agent Instructions** (such as `AGENTS.md` or `CLAUDE.md`), **Read First** (such as `README.md`), and **Build** (such as `Package.swift` or `Makefile`), and up to five files under **Recently Edited**. Choose a file to open it.

**On iPhone:** opening a project shows its top folder's files instead. The same two buttons sit at the foot of every folder screen.
