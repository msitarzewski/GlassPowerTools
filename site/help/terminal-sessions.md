# Work in a terminal

This page covers terminal windows and tabs, the session's tools menu, text size, search, pasting, snippets, recording, and the Mac's local shell.

## Windows and tabs

**On Vision Pro:** each connection opens a terminal window. To add a terminal to the same window, press ⌘T or choose **New Terminal Tab** (the plus button), then pick a saved host. With two or more terminals, a tab bar appears, and **Terminal View** switches between **Tabs**, **Grid** and **Carousel**. In Grid or Carousel, use **Previous** and **Next**, then **Open Terminal** to return to that terminal's tab.

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
| Find in the focused pane | **Edit ▸ Find ▸ Find…**, **Find Next**, **Find Previous** | ⌘F, ⌘G, ⇧⌘G |

A tab is named after what is running in it: the title a program set (Claude Code's task, the file open in vim), or the folder it is in. In your home folder it takes its Workgroup's name, or, in tmux, its session's name as **Active** shows it (**Terminal 1**), or else the shell's. Below the name: where it is, and **in tmux** when it is kept in tmux.

To work with several tabs at once, ⌘-click them in the sidebar, or ⇧-click to select a range; the window shows the tab you clicked last. Right-click the selection for **Move 3 Tabs to New Window** (with however many you chose), which opens one window holding them in their order, still running, or **Close 3 Tabs**, which asks first under the same rules as closing one. **Move Tab to New Window**, in the **Terminal** menu and under **Tab Actions** in the toolbar, moves the selected tabs too; when they are every tab in the window, that window closes. To bring windows together, drag a tab from the sidebar onto another terminal window, anywhere on it, sidebar open or not: it moves there with its terminals still running, and a window whose last tab leaves closes. Dropped on the other window's sidebar, it lands where you drop it; dragging a tab within the sidebar reorders it. Double-click a tab, or right-click it, to rename it. Closing a tab that has an SSH session, a recording, a connection in progress or running commands asks first. A terminal kept in tmux doesn't count: closing it leaves it running, and **Active** lists it (see [Keep terminals running with tmux](terminal-tmux.md)). A Mac's local terminals kept in tmux work the same way, listed under This Mac. Closing a tab never changes a saved Workgroup.

**On iPad and iPhone:** the plus button (**New Terminal Tab**) adds a terminal to the current set. iPad shows the terminals as tabs; iPhone lists them in a menu at the top.

## The session's tools menu

Each SSH terminal has a tools menu: the gear button in its toolbar on Mac, or in its bottom bar on Vision Pro. It holds **Search**, **Clear**, **Snippets**, **Start Recording…**, **Recordings**, **Duplicate Session**, **Reconnect**, **Disconnect** (**Detach** for a terminal kept in tmux), and **Settings** for this session's appearance and port forwards.

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

**On Mac:** choose **Local Terminal** in the library toolbar, or **Connect** on this Mac's **Local Shell** service. A local pane's tools menu adds **New Local Terminal Window** and, after the shell exits, **Restart**. **Open Folder Here** opens the shell's directory in Finder. A local terminal starts with your Mac's environment, as Terminal.app's do (so `ssh` finds your agent), and tells programs it is Glass Power Tools through `TERM_PROGRAM`.

**Secure Keyboard Entry**, in the toolbar and the **Terminal** menu, stops other apps from reading what you type in the focused terminal.

iPad, iPhone and Vision Pro have no local shell.
