# Work in a terminal

This page covers terminal windows and tabs, moving tabs between windows, what comes back after a relaunch, Show All Windows, the session's tools menu, text size, search, pasting, links and paths, selecting on Vision Pro, dropping files, snippets, recording, and the Mac's local shell.

## Windows and tabs

**On Vision Pro:** each connection opens a terminal window. To add a terminal to the same window, press ⌘T or choose **New Terminal Tab** (the plus button), then pick a saved host. Pinch and hold the plus button instead for a menu of your saved servers: each has **New Terminal**, then, under **Running**, the terminals running there in tmux that aren't open here, with where each one is. The one you choose opens as a tab of this window.

With two or more terminals, a tab bar appears, and the **Terminal View** button in the window's bar shows which layout the window is in: **Tabs**, **Grid** or **Carousel**. Pinch it to go on to the next, round again after **Carousel**. Pinch and hold it to choose one, or **Orb** to shrink the window into an orb (see [Shrink a session window to an orb on Vision Pro](library-connect.md#shrink-a-session-window-to-an-orb-on-vision-pro)). In Grid or Carousel, use **Previous** and **Next**, then **Open Terminal** to return to that terminal's tab. With **Auto-focus on activity** on for the window, Grid and Carousel bring forward the terminal that is printing (see [Give a terminal window its own settings](terminal-settings.md#give-a-terminal-window-its-own-settings)).

To move a terminal to another window, touch and hold its tab, or its card in **Grid** or **Carousel**, and choose **Move Tab to New Window** (when the window has other tabs), or **Move Tab To** and then the window. **Move Tab To** lists the terminal windows that are open, named as **Active** names them. The terminal's tools menu (the gear button in its bottom bar) has **Move Tab To** too, with **New Window** at the top of its list when the window has other tabs. You can also drag the terminal's name, at the top of its window, onto another terminal window: it goes after that window's last tab. Both work with only one terminal in the window, so to put two windows together, drag one window's name onto the other, or choose **Move Tab To** in its tools menu. Letting go over its own window leaves it where it was. In **Grid** you can also drag a card onto another terminal window: dropped on a card in that window's grid, it takes that card's place; dropped anywhere else on the window, it goes after the last tab. Dragging a card onto another card in the same grid moves it there. A moved terminal keeps running, with its connection, its tmux session and its name, and a window whose last tab leaves closes.

**On Mac:** terminals open in a terminal window with tabs. Each tab can be split into panes.

| Action | Where | Shortcut |
|---|---|---|
| New tab with a shell on this Mac, in tmux when that's on | **New Terminal Tab** (the plus button) | ⌘T |
| New tab with a shell on this Mac outside tmux | **New Basic Terminal Tab** | ⌃⌘T |
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
| Every window, and every terminal tab, at once | **Window ▸ Show All Windows** | ⇧⌘\ |
| Find in the focused pane | **Edit ▸ Find ▸ Find…**, **Find Next**, **Find Previous** | ⌘F, ⌘G, ⇧⌘G |

The plus button opens a new tab as ⌘T does. Its menu has **New Terminal**; **New Basic Terminal**, a shell on this Mac outside tmux (see [Open a terminal without tmux](terminal-tmux.md#open-a-terminal-without-tmux)); and **New Terminal on**, which lists every saved host with a Terminal service by its machine's name and opens a tab there, in tmux when that host keeps its terminals in tmux. A host with terminals running there in tmux is a submenu instead: **New Terminal**, then, under **Running**, each of its running terminals that no tab shows, with where it is and when it was last used. **Running on This Mac** lists this Mac's own tmux sessions that no tab shows. The running terminal you choose opens as a tab of this window, attached to its session. A Terminal service you gave a name of its own shows it after the machine's, for example **alpha — Admin shell**, and two that would still read the same show their user names, for example **alpha (root)** and **alpha (ann)**. **Connect Saved Host…** and the command palette name them the same way.

A new local tab, window or split opened while a local terminal is in front starts in the folder that terminal is in, as Terminal.app's Same Working Directory does; opened from anywhere else, or when that folder no longer exists, it starts in your home folder, or in the working directory set in Settings.

A tab is named after what is running in it: the title a program set (Claude Code's task, the file open in vim), else the Git repository it is in, else the folder it is in. In your home folder it takes its Workgroup's name, or, in tmux, its session's name as **Active** shows it (**Terminal 1**), or else the shell's. Below the name: where it is, and **in tmux** when it is kept in tmux. In a Git repository, where it is reads as the repository and branch, then the folder inside the repository, for example **app · main · Sources**. A long branch name is shortened in the middle. After you switch branches in it, the tab shows the new branch within a few seconds, or within about 15 seconds over SSH. On a machine you reach over SSH, that machine's `git` is asked; without `git` there, the tab shows the folder as before. Over SSH the repository and branch come before the machine's address. In tmux, over SSH too, the title, folder and name come from the tmux session, so the tab, **Active** and your other devices call the terminal the same; a name given on another device shows in the tab while it is open (see [Keep terminals running with tmux](terminal-tmux.md)).

To work with several tabs at once, ⌘-click them in the sidebar, or ⇧-click to select a range; the window shows the tab you clicked last. Right-click the selection for **Move 3 Tabs to New Window** (with however many you chose), which opens one window holding them in their order, still running, or **Close 3 Tabs**, which asks first under the same rules as closing one. **Move Tab to New Window**, in the **Terminal** menu and under **Tab Actions** in the toolbar, moves the selected tabs too; when they are every tab in the window, that window closes. To bring windows together, drag a tab from the sidebar onto another terminal window, anywhere on it, sidebar open or not: it moves there with its terminals still running, and a window whose last tab leaves closes. Dropped on the other window's sidebar, it lands where you drop it; dragging a tab within the sidebar reorders it. Double-click a tab, or right-click it, to rename it. Closing a tab that has an SSH session, a recording, a connection in progress or running commands asks first. A terminal kept in tmux doesn't count: closing it leaves it running, and **Active** lists it (see [Keep terminals running with tmux](terminal-tmux.md)). A Mac's local terminals kept in tmux work the same way, listed under This Mac. Closing a tab never changes a saved Workgroup.

**On iPad and iPhone:** the plus button (**New Terminal Tab**) adds a terminal to the current set. Touch and hold it for the menu of saved servers and their running terminals described for Vision Pro above; the one you choose joins this set. iPad shows the terminals as tabs; iPhone lists them in a menu at the top. To move a terminal into another open set, open the tools menu (**Tools** ▸ **Session**) or touch and hold its tab in the sidebar on iPad, or open the menu at the top on iPhone, and choose **Move Tab To**, then the set. On iPad, **Move Tab to New Window** (in the tools menu, **Move Tab To** ▸ **New Window**) opens it in a window of its own (when the set has other terminals). The terminal keeps running; a set whose last terminal leaves closes, and the screen shows the set it went to.

**After a relaunch on Vision Pro, iPad and iPhone** (the app quit, crashed or was updated), the terminal windows and sets you had open come back once the library has loaded: their terminals in the same order, the same one selected, with their names and the window's own settings. Each terminal kept in tmux goes back into its own session, with everything still running there (see [Keep terminals running with tmux](terminal-tmux.md)). Any other terminal in it comes back as a new terminal on the same machine; what was running in it is gone. A window or set comes back only when a terminal in it is kept in tmux.

- **On Vision Pro** each comes back as its own window, and every terminal in it connects. A window you closed doesn't come back; its terminals keep running, and **Active** lists them.
- **On iPad and iPhone** the set that was on screen is shown again, and only its terminal on screen connects; the others connect when you switch to them, and the other sets are in **Active**.
- A set whose last terminal ended, or that you closed in **Active**, doesn't come back. A terminal on a machine you removed, or one that allows legacy algorithms (which asks each time), is left out, and a message says so.
- Your saved Workgroups are never changed by this.

**On Vision Pro, iPad and iPhone**, a terminal is named the way the Mac names its tabs: the name you gave it, else the title its program set, else its Git repository, else its folder, else its server. For a terminal kept in tmux, these come from its tmux session, so a name you give a tab on your Mac shows on your other devices too, without reconnecting. In a repository, the repository and branch come before the machine's address. To rename a terminal, touch and hold its tab (on Vision Pro, its tab or its card in **Grid** and **Carousel**), or open the menu at the top on iPhone, and choose **Rename Tab…**. Leave the name blank, or choose **Use Automatic Name**, to go back to the automatic name. A terminal kept in tmux keeps the name on its session, so every device shows it.

## Show All Windows

See every terminal window and its tabs, with every other window you have open, at once, as live pictures, and go straight to one. **On Mac** press ⇧⌘\, or pinch in on a terminal or remote desktop window; **on iPad and iPhone** pull down from the bar at the top of the screen, or touch and hold ⚡; **on Vision Pro** pinch and hold ⚡. On the Mac you can also drag a terminal's picture onto another window's group to move that tab there. See [See everything open with Show All Windows](library-connect.md#see-everything-open-with-show-all-windows).

## The session's tools menu

Each SSH terminal has a tools menu: the gear button in its toolbar on Mac, or in its bottom bar on Vision Pro. It holds **Search**, **Clear**, **Snippets**, **Start Recording…**, **Recordings**, **Duplicate Session**, on Vision Pro and iPad **Move Tab To** when there is somewhere to move it (see [Windows and tabs](#windows-and-tabs)), **Reconnect**, **Disconnect** (**Detach** for a terminal kept in tmux), and **Settings**: **This Window** for the window's own settings, **All Terminals** for the settings every terminal shares (see [Give a terminal window its own settings](terminal-settings.md#give-a-terminal-window-its-own-settings)), and the session's port forwards.

**On iPhone and iPad:** the tools menu and the buttons below are in **Tools**, at the bottom of the terminal and on the bar above the on-screen keyboard. **On iPhone held sideways**, **Tools** is in the top bar beside **+** and ⚡, so the terminal gets the whole height.

Beside the tools menu:

- **Open Folder Here**, once the remote shell reports its current directory. It opens that folder in the file browser.
- **Focus Mode**. **On Vision Pro** it surrounds you with a dimmed environment. **On Mac** it makes the window full screen.
- **AI Assistant**, when Apple Intelligence is available. It suggests a command from a description; **Review & Run** shows the exact command and asks before sending it. When a command fails, it can explain the error and suggest a fix; a fix that is advice rather than a command is shown to read, with nothing to run. If the suggestions keep coming, for example while a test run prints "failed" on purpose, open the menu beside the suggestion's close button: **Pause in This Terminal** stops them in this terminal until it closes, and **Turn Off Error Suggestions** stops them everywhere, until you turn **Suggest fixes for errors** back on in **Settings** ▸ **Connections**.

## Text size

Press ⌘+ to enlarge, ⌘- to shrink and ⌘0 to reset. This changes the current terminal only. **On Mac** these are in the **Terminal** menu.

## Search

Choose **Search** from the tools menu, or press ⌘F (on Mac, **Edit ▸ Find ▸ Find…**; on iPad and Vision Pro, with a hardware keyboard). Type, then press Return: the first match is the newest, and each Return goes on to an older one. The arrows step to older and newer matches, the bar shows how many there are, and Escape closes it. **On Mac**, ⌘G (**Find Next**) and ⇧⌘G (**Find Previous**) step older and newer too, and with the bar closed they open it with the last word searched for.

In a terminal kept in tmux, tmux searches its own history, so text that has scrolled away is found; closing the bar returns to the live prompt. In a program that fills the screen, such as `less` or `vim`, only what's on screen can be searched: use the program's own search.

## Paste

Pasting a single short line sends it straight away. Text with more than one line, or longer than 4,096 bytes, opens **Review Terminal Paste** first. Edit it if needed, then choose **Paste**, or press ⌘↩ with a keyboard (Return adds a new line to the text). Clipboards larger than 262,144 bytes are refused.

## Right-click in a terminal (Mac)

Right-click, or Control-click, in a terminal for **Look Up**, **Copy**, **Paste** and **Select All**. The selected text also works with **Services**. Right-clicking a word outside the selection selects that word first; right-clicking inside the selection keeps it. **Paste** goes through the same review as ⌘V.

## Links and paths

**On Mac**, right-click a web address or a path the terminal shows, and the menu starts with what can be done with it. **On Vision Pro**, pinch and hold on it and let go without moving for the same actions.

- On a web address: **Open Link**, which asks before opening it in your browser, and **Copy Link**. **Open Link** is offered only for an `http` or `https` address with no user name or password in it.
- On a path: **Quick Look** on Mac (see [Preview a file over the terminal](#preview-a-file-over-the-terminal)); **Open in Editor**, which opens a file as a tab or a folder as a project, on the machine the path is on; **Show in Finder** for a path on this Mac, or **Show in Files** for a path on a server, which opens the file browser at its folder; **Watch Log File**; and **Copy Path**.

A path is read on the machine that printed it: from the shell's current folder when it is relative, and `~` as that machine's home folder. A `:line:column` after it is left off. A path that isn't there beeps.

**Watch Log File** opens a new tab in the same window, on the same machine, that follows the file with `tail -F`: new lines appear as they are written, and it keeps following when the log is rotated, or waits for a file that isn't there yet. The tab is named after the file. It runs outside tmux, so closing the tab ends it.

## Preview a file over the terminal

**On Mac**, the file a path names can show in a popover over the terminal: a picture, a PDF, a video, a document, code, or text. Markdown (with its diagrams), HTML, SVG and CSV show as the editor previews them. A file on a server is copied to this Mac for the preview, up to 32 MB, and the copy is removed when the preview closes. A folder has no preview.

- Choose **Quick Look** from a path's right-click menu.
- Or set **Show previews** in **Settings** ▸ **Terminal**:
  - **Mouseover**, the starting setting: rest the pointer on a path, and the preview opens after a moment. It closes when the pointer moves off the path and the preview.
  - **Mouseover + Space**: put the pointer on a path and press Space; Space again or Escape closes it. On a web address, Space asks whether to open it, as a ⌘-click does. Anywhere else, Space types a space.
  - **Never**: only **Quick Look** shows a preview.

A window can have its own **Show previews** in its settings, under **This Window**. A click, scrolling or typing in the terminal closes the preview.

## Select text on Vision Pro

These work as selecting text does in Apple's own apps:

- Pinch twice quickly to select a word, or three times to select a line, with **Copy** offered.
- Pinch and hold on a word to select it. Keep holding and drag to select more, a word at a time. Letting go offers **Copy**.
- Pinch and drag either end of a selection to make it longer or shorter. A pinch-and-drag that starts anywhere else scrolls.
- **With a trackpad:** click and drag to select, as on a Mac; double-click a word or triple-click a line; scroll with two fingers; click with two fingers for a menu with **Copy**, or a link's actions.
- All of these work even when the program in the terminal takes the mouse, as tmux does with its mouse mode on (tmux 3.8 turns it on unless your configuration turns it off). A selection stays while the program redraws around it.
- A single pinch clears a selection. With nothing selected, a single pinch goes to the program.
- A pinch-and-drag up or down scrolls: in tmux, tmux's history; in a program that takes the mouse, such as `vim` or `htop`, as its scroll wheel would. It never starts tmux's own selection, the yellow one, which tmux copies to its own buffer and clears when you let go.
- Pinch and hold on a link or a path, and let go without moving, for its actions (see [Links and paths](#links-and-paths)).

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

**On Mac:** choose **Local Terminal** in the library toolbar, or **Connect** on this Mac's **Local Shell** service. While local terminals are kept in tmux, **File** ▸ **New Basic Terminal Tab** (⌃⌘T) opens one outside it; see [Open a terminal without tmux](terminal-tmux.md#open-a-terminal-without-tmux). A local pane's tools menu adds **New Local Terminal Window** and, after the shell exits, **Restart**. Its **Settings** opens the same Terminal Settings as an SSH terminal's, without port forwarding. **Open Folder Here** opens the shell's directory in Finder. A local terminal starts with your Mac's environment, as Terminal.app's do (so `ssh` finds your agent), and tells programs it is Glass Power Tools through `TERM_PROGRAM`.

**Secure Keyboard Entry**, in the toolbar and the **Terminal** menu, stops other apps from reading what you type in the focused terminal.

iPad, iPhone and Vision Pro have no local shell.
