# Siri, Shortcuts and the rest of the system

Glass Power Tools works with the system's own ways in: Siri, the Shortcuts app, Spotlight, Control Center, Handoff, `ssh://` links and, on the Mac, the Finder and the Dock. This page covers each one and what it opens.

Each of them opens what you ask for the way the library's **Connect** does: signing in and trusting a host key are asked as usual, never skipped. **On Vision Pro**, a session opened this way gets a window of its own in the room, as it does from the library. A machine that doesn't have the service you asked for says so, and what to do.

## Siri and the Shortcuts app

These phrases work with Siri, in Spotlight, in the Shortcuts app and with the iPhone's Action button, on every device. Name the machine, service, Workgroup or query as the library names it; the example machine here is alpha.

| Say | What happens |
|---|---|
| "Open a terminal on alpha in Glass Power Tools", or "Connect to alpha in Glass Power Tools" | Connects to alpha's Terminal service. |
| "Open the desktop of alpha in Glass Power Tools" | Connects to alpha's Desktop service. |
| "Open *service* in Glass Power Tools" | Connects to that service, whatever its kind. |
| "Open the *name* workgroup in Glass Power Tools" | Opens that Workgroup. |
| "Open the *name* query in Glass Power Tools" | Opens that saved database query in a new SQL tab, connecting first. It is not run. |
| "Show alpha in Glass Power Tools" | Opens the library with alpha selected. |
| "Show all windows in Glass Power Tools" | Opens **Show All Windows**; see [See everything open with Show All Windows](library-connect.md#see-everything-open-with-show-all-windows). |
| "Show my active connections in Glass Power Tools" | Opens **Active**. |
| "What's open in Glass Power Tools", or "What's running in Glass Power Tools" | Answers without opening the app, for example "1 open and 4 running on 2 machines.", with a card of the machines that have something open or running. The button beside one opens the library with it selected. |
| "New Glass Power Tools terminal" (**on Mac**) | Opens a terminal window on this Mac. |

The Shortcuts app also has these actions, to use in shortcuts of your own:

- **Open in Editor**: opens files in the editor. A folder opens as a project.
- **New Terminal Window** (**on Mac**): opens a terminal window on this Mac, in a folder when you choose one.
- **Send Files to a Machine**: see below.

## Send files to a machine

**Send Files to a Machine**, in the Shortcuts app, sends files to a folder on a machine in your library, through its Terminal service. Give the folder from the machine's home folder, or as a full path; leave it empty for the home folder itself. Nothing on the machine is replaced: a name that is already taken gets a number. The shortcut says what happened, or why a file didn't arrive. To send from the share sheet on iPhone, iPad and Vision Pro, make a shortcut with this action that takes files, and show it in the share sheet.

**On Mac**, choose **Share** ▸ **Send to a Machine** in any app that shares files. Choose a machine with a Terminal service and, if you like, a folder under its home folder, then **Send**. Glass Power Tools opens, sends the files the same way, and says what happened. The share panel itself holds no password and connects to nothing.

## Find your machines in Spotlight

Turn on **Settings** ▸ **Privacy** ▸ **Show Machines in Search** to find your machines and Workgroups by name in Spotlight and Siri on this device, and open them from there. It is off by default, because it puts your machines' names in the system's index on this device. Only names and the kinds of service are indexed, never an address, a user name or a credential. Turning it off takes them all out again.

## Controls

Add these controls the way you add any control:

- **Open Terminal**: a terminal on the machine you choose when you add the control. With no machine chosen, it opens the library.
- **Active Connections**: opens **Active**.
- **New Terminal Window** (**on Mac**): a terminal window on this Mac.

**On iPhone** they go in Control Center, on the Lock Screen and on the Action button; **on iPad**, in Control Center. **On Mac** they go in Control Center and the menu bar. Vision Pro has no controls.

## Handoff

The terminal, database or remote desktop in front is offered on your other devices, when they use the same iCloud account and have Handoff on: in the Mac's Dock, in the app switcher on iPhone and iPad, and on Vision Pro where the system offers it. Continuing it connects to the same service there, as **Connect** does.

A terminal kept in tmux continues in its own tmux session. If a tab on the other device already shows that session, it comes forward; otherwise a terminal there attaches to the session, in the same folder with the same programs running, rather than starting a new one. On a Mac, a session running on that Mac itself comes back in its local tab.

Only the focused pane of a terminal window is offered, and a Mac's local terminals are not offered. What is handed off names the service and its tmux session, and nothing else.

## Drag a service into its own window

**On Vision Pro**, drag a machine's **Terminal** or **Desktop** row out of its details in the library and let go: its window opens where you dropped it, so a machine's terminal and desktop can stand side by side. It connects as **Connect** does.

**On iPad**, dragging a **Desktop** row out opens the desktop in a window beside the library.

## ssh:// links

Glass Power Tools opens `ssh://` links on every device. A link to a machine in your library, with the same address and port (and user name, when the link has one), connects to it as saved. Any other link opens the form for a new machine, filled in from the link, for you to check and save. A host key fingerprint in a link is never trusted: you compare the machine's key as usual (see [Sign in with keys and trust host keys](terminal-keys-and-trust.md)).

## The Finder and the Dock (Mac)

Right-click a folder or a file in the Finder and choose, under **Services** or **Quick Actions**:

- **New Glass Power Tools Tab Here**: a terminal on this Mac in that folder, as a new tab of the terminal window in front, or in a new window when none is open. A file stands for the folder it is in.
- **New Glass Power Tools Window Here**: the same, in a new terminal window. It is also in the Finder's preview pane under **Quick Actions**.
- **Open in Glass Power Tools**: a file opens in the editor; a folder opens as an editor project.

If you don't see them, turn them on in **System Settings** ▸ **Keyboard** ▸ **Keyboard Shortcuts** ▸ **Services**.

For the same three in every Finder window's toolbar, turn on **Glass Power Tools Finder** in **System Settings** ▸ **General** ▸ **Login Items & Extensions** ▸ **Finder**, then in a Finder window choose **View** ▸ **Customize Toolbar…** and drag **Glass Power Tools** into the toolbar.

Also:

- **Open With** ▸ **Glass Power Tools** on a folder, or dropping a folder on the app's Dock icon, opens a terminal there. A `.command` script opened this way runs in a new terminal tab; other files, `.sh` scripts among them, open in the editor (see [Open the Editor](editor-opening.md#open-text-files-from-the-finder)).
- The Dock icon's menu has **New Terminal Window**, then up to eight of your favorite and recent machines. Choosing a machine connects to its terminal, or to its first service when it has no terminal.
