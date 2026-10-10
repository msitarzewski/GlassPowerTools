# Work in a terminal

This page covers terminal windows and tabs, moving tabs between windows, what comes back after a relaunch, Show All Terminals, the session's tools menu, text size, search, pasting, dropping files, snippets, recording, and the Mac's local shell.

## Windows and tabs

**On Vision Pro:** each connection opens a terminal window. To add a terminal to the same window, press ⌘T or choose **New Terminal Tab** (the plus button), then pick a saved host. With two or more terminals, a tab bar appears, and **Terminal View** switches between **Tabs**, **Grid** and **Carousel**. In Grid or Carousel, use **Previous** and **Next**, then **Open Terminal** to return to that terminal's tab.

To move a terminal to another window, touch and hold its tab, or its card in **Grid** or **Carousel**, and choose **Move Tab to New Window** (when the window has other tabs), or **Move Tab To** and then the window. **Move Tab To** lists the terminal windows that are open, named as **Active** names them. The terminal's tools menu (the gear button in its bottom bar) has **Move Tab To** too, with **New Window** at the top of its list when the window has other tabs. You can also drag the terminal's name, at the top of its window, onto another terminal window: it goes after that window's last tab. Both work with only one terminal in the window, so to put two windows together, drag one window's name onto the other, or choose **Move Tab To** in its tools menu. Letting go over its own window leaves it where it was. In **Grid** you can also drag a card onto another terminal window: dropped on a card in that window's grid, it takes that card's place; dropped anywhere else on the window, it goes after the last tab. Dragging a card onto another card in the same grid moves it there. A moved terminal keeps running, with its connection, its tmux session and its name, and a window whose last tab leaves closes.

**On Mac:** terminals open in a terminal window with tabs. Each tab can be split into panes.

| Action | Where | Shortcut |
|---|---|---|
| New tab with a shell on this Mac, in tmux when that's on | **New Terminal Tab** (the plus button) | ⌘T |
| New tab on the same machine | **New Tab with Same Connection** | ⇧⌘T |
| New window | **New Terminal Window** | ⌘N in a terminal window |
| Split with a local shell | **Split Right**, **Split Down** | ⌘D, ⇧⌘D |
| Split with a saved host | **Connect Saved Host…** or **Connect Saved Host in Split…** | ⌥⌘T |
| Next pane | **Focus Next Pane** | ⌥⌘] |
| Close pane | **Close Pane** | ⌥⌘W |
| Close tab | | ⌘W |
| Move the selected tabs to a new window | **Move Tab to New Window**, or right-click the tabs | |
| Go to tab 1–9 | | ⌘1–⌘9 |
| All tabs as a grid or carousel | **Terminal Grid**, **Terminal Carousel** | ⌥⌘G, ⌥⇧⌘G |
| Every terminal window and its tabs at once | **Window ▸ Show All Terminals** | ⇧⌘\ |
| Find in the focused pane | **Edit ▸ Find ▸ Find…**, **Find Next**, **Find Previous** | ⌘F, ⌘G, ⇧⌘G |

A tab is named after what is running in it: the title a program set (Claude Code's task, the file open in vim), else the Git repository it is in, else the folder it is in. In your home folder it takes its Workgroup's name, or, in tmux, its session's name as **Active** shows it (**Terminal 1**), or else the shell's. Below the name: where it is, and **in tmux** when it is kept in tmux. In a Git repository, where it is reads as the repository and branch, then the folder inside the repository, for example **app · main · Sources**. A long branch name is shortened in the middle. After you switch branches in it, the tab shows the new branch within a few seconds, or within about 15 seconds over SSH. On a machine you reach over SSH, that machine's `git` is asked; without `git` there, the tab shows the folder as before. Over SSH the repository and branch come before the machine's address. In tmux, over SSH too, the title, folder and name come from the tmux session, so the tab, **Active** and your other devices call the terminal the same; a name given on another device shows in the tab while it is open (see [Keep terminals running with tmux](terminal-tmux.md)).

To work with several tabs at once, ⌘-click them in the sidebar, or ⇧-click to select a range; the window shows the tab you clicked last. Right-click the selection for **Move 3 Tabs to New Window** (with however many you chose), which opens one window holding them in their order, still running, or **Close 3 Tabs**, which asks first under the same rules as closing one. **Move Tab to New Window**, in the **Terminal** menu and under **Tab Actions** in the toolbar, moves the selected tabs too; when they are every tab in the window, that window closes. To bring windows together, drag a tab from the sidebar onto another terminal window, anywhere on it, sidebar open or not: it moves there with its terminals still running, and a window whose last tab leaves closes. Dropped on the other window's sidebar, it lands where you drop it; dragging a tab within the sidebar reorders it. Double-click a tab, or right-click it, to rename it. Closing a tab that has an SSH session, a recording, a connection in progress or running commands asks first. A terminal kept in tmux doesn't count: closing it leaves it running, and **Active** lists it (see [Keep terminals running with tmux](terminal-tmux.md)). A Mac's local terminals kept in tmux work the same way, listed under This Mac. Closing a tab never changes a saved Workgroup.

**On iPad and iPhone:** the plus button (**New Terminal Tab**) adds a terminal to the current set. iPad shows the terminals as tabs; iPhone lists them in a menu at the top. To move a terminal into another open set, open the tools menu (**Tools** ▸ **Session**) or touch and hold its tab in the sidebar on iPad, or open the menu at the top on iPhone, and choose **Move Tab To**, then the set. On iPad, **Move Tab to New Window** (in the tools menu, **Move Tab To** ▸ **New Window**) opens it in a window of its own (when the set has other terminals). The terminal keeps running; a set whose last terminal leaves closes, and the screen shows the set it went to.

**After a relaunch on Vision Pro, iPad and iPhone** (the app quit, crashed or was updated), the terminal windows and sets you had open come back once the library has loaded: their terminals in the same order, the same one selected, with their names and the window's own settings. Each terminal kept in tmux goes back into its own session, with everything still running there (see [Keep terminals running with tmux](terminal-tmux.md)). Any other terminal in it comes back as a new terminal on the same machine; what was running in it is gone. A window or set comes back only when a terminal in it is kept in tmux.

- **On Vision Pro** each comes back as its own window, and every terminal in it connects. A window you closed doesn't come back; its terminals keep running, and **Active** lists them.
- **On iPad and iPhone** the set that was on screen is shown again, and only its terminal on screen connects; the others connect when you switch to them, and the other sets are in **Active**.
- A set whose last terminal ended, or that you closed in **Active**, doesn't come back. A terminal on a machine you removed, or one that allows legacy algorithms (which asks each time), is left out, and a message says so.
- Your saved Workgroups are never changed by this.

**On Vision Pro, iPad and iPhone**, a terminal is named the way the Mac names its tabs: the name you gave it, else the title its program set, else its Git repository, else its folder, else its server. For a terminal kept in tmux, these come from its tmux session, so a name you give a tab on your Mac shows on your other devices too, without reconnecting. In a repository, the repository and branch come before the machine's address. To rename a terminal, touch and hold its tab (on Vision Pro, its tab or its card in **Grid** and **Carousel**), or open the menu at the top on iPhone, and choose **Rename Tab…**. Leave the name blank, or choose **Use Automatic Name**, to go back to the automatic name. A terminal kept in tmux keeps the name on its session, so every device shows it.

## Show All Terminals

**On Mac:** see every terminal window and all of its tabs at once, the way Mission Control shows windows. The screen dims, and each terminal window becomes a group, named like its window, with a live picture of each tab. Busy tabs show the same moving wave as in the sidebar.

To open it, do any of these:

- Press ⇧⌘\, or choose **Window ▸ Show All Terminals**. This works from any window, Connections included.
- Click **Show All Terminals** in the toolbar of Connections or of a terminal window.
- Pinch in with two fingers on a terminal window. Pinch out to close it again.

In it:

- Click a terminal, or select it and press Return, to bring its window forward on that tab.
- Use the arrow keys to move between terminals, across windows.
- Type to show only the terminals whose name, folder, repository or branch contains what you type. Delete removes the last letter.
- Hover over a terminal to see its name and where it is: its repository and branch, or its folder.
- Drag a terminal onto another window's group to move that tab there. Its terminals keep running, and a window whose last tab leaves closes.
- Press Escape, or click outside the groups, to close it.

**Not in a window** lists this Mac's tmux sessions that no tab is showing, the same ones **Active** lists under This Mac. **Reopen** opens one in a new terminal window. The group appears only when there are such sessions.

The pictures are only pictures: nothing is typed into a terminal, and no terminal changes size. A terminal that has not drawn anything yet says **Waiting for terminal preview…** until it does.

## The session's tools menu

Each SSH terminal has a tools menu: the gear button in its toolbar on Mac, or in its bottom bar on Vision Pro. It holds **Search**, **Clear**, **Snippets**, **Start Recording…**, **Recordings**, **Duplicate Session**, on Vision Pro and iPad **Move Tab To** when there is somewhere to move it (see [Windows and tabs](#windows-and-tabs)), **Reconnect**, **Disconnect** (**Detach** for a terminal kept in tmux), and **Settings**: **This Window** for the window's own settings, **All Terminals** for the settings every terminal shares (see [Give a terminal window its own settings](terminal-settings.md#give-a-terminal-window-its-own-settings)), and the session's port forwards.

**On iPhone and iPad:** the tools menu and the buttons below are in **Tools**, at the bottom of the terminal and on the bar above the on-screen keyboard. **On iPhone held sideways**, **Tools** is in the top bar beside **+** and ⚡, so the terminal gets the whole height.

Beside the tools menu:

- **Open Folder Here**, once the remote shell reports its current directory. It opens that folder in the file browser.
- **Focus Mode**. **On Vision Pro** it surrounds you with a dimmed environment. **On Mac** it makes the window full screen.
- **AI Assistant**, when Apple Intelligence is available. It suggests a command from a description; **Review & Run** shows the exact command and asks before sending it. When a command fails, it can explain the error and suggest a fix; a fix that is advice rather than a command is shown to read, with nothing to run.

## Text size

Press ⌘+ to enlarge, ⌘- to shrink and ⌘0 to reset. This changes the current terminal only. **On Mac** these are in the **Terminal** menu.

## Search

Choose **Search** from the tools menu, or press ⌘F (on Mac, **Edit ▸ Find ▸ Find…**; on iPad and Vision Pro, with a hardware keyboard). Type, then press Return: the first match is the newest, and each Return goes on to an older one. The arrows step to older and newer matches, the bar shows how many there are, and Escape closes it. **On Mac**, ⌘G (**Find Next**) and ⇧⌘G (**Find Previous**) step older and newer too, and with the bar closed they open it with the last word searched for.

In a terminal kept in tmux, tmux searches its own history, so text that has scrolled away is found; closing the bar returns to the live prompt. In a program that fills the screen, such as `less` or `vim`, only what's on screen can be searched: use the program's own search.

## Paste

Pasting a single short line sends it straight away. Text with more than one line, or longer than 4,096 bytes, opens **Review Terminal Paste** first. Edit it if needed, then choose **Paste**. Clipboards larger than 262,144 bytes are refused.

## Right-click in a terminal (Mac)

Right-click, or Control-click, in a terminal for **Look Up**, **Copy**, **Paste** and **Select All**. The selected text also works with **Services**. Right-clicking a word outside the selection selects that word first; right-clicking inside the selection keeps it. **Paste** goes through the same review as ⌘V.

## Drop files on a terminal

Drag files onto a terminal to type their paths at the cursor, ready for the program that reads them, such as Claude Code. The paths are escaped for the shell and separated by spaces, with a space after the last. Nothing is run: press Return yourself.

- **On Mac, in a local terminal:** each file types its own path. A screenshot dragged from its thumbnail, or an image dragged from a browser, is saved in the app's caches first and types that path.
- **In an SSH terminal, on every platform:** the shell is on the host, so the files are uploaded there first, into `~/.cache/glass-power-tools/dropped/` in a folder for the day, and their paths on the host are typed. This works with files from Files or the Finder, photos from Photos, and files from other apps. A photo in HEIC is uploaded as a JPEG, which more tools can read; other files go as they are. If a name is taken, the file gets a number, for example `photo-2.jpg`. Nothing is ever uploaded into the shell's current folder.

While files upload, the terminal's corner shows their progress; its × cancels, and a cancelled drop types nothing. A file that doesn't arrive types nothing either, and the corner says why and what to do. A terminal that isn't connected refuses the drop.

The day folders are cleared once they're more than a week old, the first time you drop something on each connection. Only that drop folder is touched. To keep a dropped file, move it somewhere else on the host.

Folders can't be dropped; drop the files inside them.

## The on-screen keyboard bar

**On Vision Pro, iPad and iPhone**, the bar above the on-screen keyboard has:

- the cursor pad: drag it to move the cursor.
- **Terminal Keys**: **Escape**, **Tab**, **Control for Next Key**, arrow keys under **Navigation**, and **Function Keys** F1–F12.
- **Dismiss Keyboard**.

## Snippets

Choose **Snippets** from the tools menu and pick one. Its command runs at once. To create snippets, see [Terminal settings, themes and snippets](terminal-settings.md).

## Record a session

1. Choose **Start Recording…**.
2. Choose **Record Output Only**, or **Record Output and Keyboard Input**.

> [!WARNING]
> Keyboard input can include passwords and tokens. Record input only when you need it.

While input is recorded, the terminal shows **INPUT REC**. Choose **Stop Recording** to finish. **Recordings** lists saved recordings, where you can delete them.

## The Mac's local shell

**On Mac:** choose **Local Terminal** in the library toolbar, or **Connect** on this Mac's **Local Shell** service. A local pane's tools menu adds **New Local Terminal Window** and, after the shell exits, **Restart**. Its **Settings** opens the same Terminal Settings as an SSH terminal's, without port forwarding. **Open Folder Here** opens the shell's directory in Finder. A local terminal starts with your Mac's environment, as Terminal.app's do (so `ssh` finds your agent), and tells programs it is Glass Power Tools through `TERM_PROGRAM`.

**Secure Keyboard Entry**, in the toolbar and the **Terminal** menu, stops other apps from reading what you type in the focused terminal.

iPad, iPhone and Vision Pro have no local shell.
