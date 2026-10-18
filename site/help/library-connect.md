# Connect and switch between sessions

You start a session from a host in the library, and you return to any open session from **Active** or **Show All Windows**. This page covers the Connect controls, which service a host opens, the Mac's Command Palette, how to switch to or close open sessions, and shrinking windows into orbs on Vision Pro.

## Connect from the host list

Each host row has a Connect control at its trailing edge.

- **A host with one service** shows a single **Connect** button (play symbol). It opens that service.
- **A host with several services** shows a split button. The play half opens every service on the host. The chevron half opens a menu of the host's services; choose one to open only that service. The chevron is its own button on every device: click it, tap it or pinch it on Vision Pro.
- **This device** with several services shows one button with a play symbol and a chevron. It always opens the menu, because opening every local service at once is rarely what you want.

## Connect from a host's details

Select the host. Under **Services**, choose **Connect** (play symbol) beside the service you want. This is the most precise way to connect, because each button names its service.

## Connect with the keyboard or the host's menu

- **On Mac:** double-click a host.
- With a keyboard on any device, select a host and press Return.
- Right-click a host, or touch and hold it (pinch and hold on Vision Pro), and choose **Connect**.

Each of these opens one service: the one you last chose on that host, from its details or the chevron menu, or the first service if you have not chosen one yet. It is remembered when you choose it, even if that attempt doesn't connect. The play half of the split button opens every service and changes nothing here. The host's details show which one under **Connect opens**.

The host's **Last connected** time and its place in **Recent** change only when a session actually connects. A failed or cancelled attempt does not count.

## Connect from the Command Palette (Mac)

Press ⇧⌘P, or choose **Glass Power Tools** ▸ **Command Palette…**, from any window, and type to narrow the list. Return opens what is selected. The palette lists:

- **Connect:** every service of every machine, for example **Connect: Terminal on alpha**, **Connect: Desktop on alpha** or **Connect: MySQL on alpha**. It connects as the library's **Connect** does.
- **Open Project:** each editor project, and **Open Folder:** each folder in **Favorites**, opened as **Favorites** opens them.
- **Open Query:** each saved database query, opened in a new SQL tab. It is not run.
- **Attach:** each tmux session running on your machines that no window here shows, opened as **Active** opens it.
- The terminal's commands, whatever window is in front: **New Connection** (the terminal's own **Add Server** form, for a machine reached over SSH), **Open Local Terminal**, **Open Basic Local Terminal**, **Workgroups**, **Tailscale Devices** (once Tailscale is set up), **Open Files on alpha** for each machine, **Connect to alpha without tmux** for each machine that keeps its terminals in tmux, and **Open** followed by each Workgroup's name.
- The commands of the window in front, and the menu bar's, with their shortcuts.

A command that needs the library window opens it first when it isn't open. Type `connect:` first to list only the **Connect** entries. Commands you ran recently come first.

## Connect from a widget

The **Machines** widget has a button for each service of your favorite and recent machines, and the **Machine** widget for each service of the one machine you choose; choose one to connect. The **Active** widget opens **Active**. See [Widgets](library-widgets.md).

## Connect with Siri, Shortcuts and the system

Siri, the Shortcuts app, Spotlight, Control Center, Handoff, `ssh://` links and, on the Mac, the Finder and the Dock can open your machines' services too. See [Siri, Shortcuts and the rest of the system](library-siri-and-system.md).

## See what is open

**Active** lists every open session: terminals, databases, remote desktops and editor windows.

- **On Vision Pro:** choose the **Active** tab beside the library window.
- **On Mac, iPad and iPhone:** choose **Active** in the sidebar's **Library** section. The number beside it is how many sessions **Active** lists: those open on this device, and the tmux sessions running on your machines when **Active** last checked.

Sessions are grouped under the host they belong to, with a count for each host. A host whose Terminal service keeps sessions running with tmux also lists the tmux sessions running there, by the names their tabs have, and a host **Active** couldn't check says why; see [Keep terminals running with tmux](terminal-tmux.md). Sessions that belong to no host in the library are grouped under **Elsewhere**. Collapse a host's group with its disclosure arrow. When nothing is open, **Active** says **Nothing Is Open** and lists your machines under **Terminal**, **Database** and **Desktop**; choose one to connect to that service.

## Switch to a session

Choose a session in **Active** to switch to it. The open session comes back to the screen; a second session is not opened. You can also right-click the session, or touch and hold it, and choose **Switch To**.

Sessions running on your machines can be chosen several at a time and opened together; see [Open several together](terminal-tmux.md#open-several-together).

## Get to Active from anywhere

Every session has **Active Connections** (⚡) at the right end of its top toolbar, and the library has one too.

- **On Vision Pro, Mac and iPad:** ⚡ brings the library window forward and opens **Active**. **On Vision Pro** there is only ever one library window, and a desktop's ⚡ is last in its control bar.
- **On iPhone:** ⚡ leaves the session screen and opens **Active** in the library.
- **On iPhone, iPad and Vision Pro:** touch and hold ⚡ (pinch and hold on Vision Pro) for **All Windows**. **On Mac**, **Show All Windows** is beside ⚡. See [See everything open with Show All Windows](#see-everything-open-with-show-all-windows).

## See everything open with Show All Windows

**Show All Windows** shows what you have open as pictures, all at once, so you can go straight to one: terminals, Files windows, databases, remote desktops and the editor.

To open it:

- **On Mac:** press ⇧⌘\, or choose **Window** ▸ **Show All Windows**, from any window, Connections included. **Show All Windows** is also in each window's toolbar: beside ⚡ in a session's window, and after **Local Terminal** in Connections. On a terminal or remote desktop window, you can pinch in with two fingers; pinch out to close it again.
- **On iPad and iPhone:** pull down from an empty part of the bar at the top of the screen (not on a button or a search field), or touch and hold ⚡. It slides down as a pane of glass over what you were doing.
- **On Vision Pro:** pinch and hold ⚡. It opens as a window of its own, which you can make as large as the work needs; the pictures grow with it.
- **With Siri or Shortcuts**, on any device: say "Show all windows in Glass Power Tools", or use the **Show All Windows** action.

### On Mac

The screen dims, and the windows are laid out the way Mission Control shows them. Each terminal window becomes a group, named like its window, with a live picture of each tab. Busy tabs show the same sweep of light as in the sidebar. The other windows follow in a group for each kind, **Files**, **Databases**, **Desktops** and **Editor**, each window with its picture, or its symbol when it has none.

In it:

- Click a picture, or select it and press Return, to bring its window forward, on that tab for a terminal.
- Use the arrow keys to move between pictures, across groups.
- Type to show only those whose name, folder, repository or branch contains what you type. Delete removes the last letter.
- Hover over a terminal to see its name and where it is: its repository and branch, or its folder.
- Drag a terminal onto another window's group to move that tab there. Its terminals keep running, and a window whose last tab leaves closes.
- Press Escape, or click outside the groups, to close it.

**Not in a window** lists this Mac's tmux sessions that no tab is showing, the same ones **Active** lists under This Mac. **Reopen** opens one in a new terminal window. The group appears only when there are such sessions.

A terminal that has not drawn anything yet says **Waiting for terminal preview…** until it does.

### On iPhone, iPad and Vision Pro

What is connected appears as cards, with editor windows while they are open, grouped under the machine each is on, and laid out the way the Mac lays them out: every card the same size, as large as fits. Each tab of a terminal window has a card of its own. A card shows its session's picture, taken again every second while the card is on screen, with its name and where it is across the bottom. A terminal's picture is live while the terminal is on screen somewhere (on Vision Pro, in any window); one that isn't, such as a terminal in another set on iPhone, shows the last picture it drew. **On iPhone and iPad**, a terminal that waits to connect until you switch to it, such as one in a set that came back after a relaunch, has a card too, saying **Connects when opened**; choosing it goes to that terminal and connects it.

- Choose a card to go to that session. **On iPhone and iPad** the screen you were on is left, and the session comes back; **on Vision Pro** its window comes to you, and **All Windows** closes.
- The × in a card's corner closes that session, as **Close** in **Active** does. A terminal kept in tmux is detached instead and keeps running.
- Search with the field at the top. A machine's name keeps everything on it; a session's name, or where it is, keeps that session.
- Choose **Done** to close it. **On iPhone and iPad** you can also tap below the pane, or push the bar at its bottom edge up.

When nothing is connected, it says **Nothing Is Open**. Sessions running on your machines with no window here are in **Active** instead.

### AI agents and private pictures

A terminal running an AI coding agent shows the agent's mark, faint, in the middle of its picture, on every device. The agent is told by the program running in the terminal: on any machine when the terminal is kept in tmux, and in a Mac's local terminals. Outside tmux on another machine, only Claude Code is recognized, by the title it sets. The mark is a hint, not a guarantee. The agents recognized are Claude Code, Codex, opencode, Gemini CLI, Cursor Agent, GitHub Copilot, Qwen Code, Kimi, OpenClaw, Hermes Agent, Mistral Vibe, DeepSeek Harness, ZCode, Amp, Goose, Cline, Kilo Code, OpenHands, Grok CLI, Kiro, Trae Agent, Qoder, Aider, Crush, Droid, Auggie, Plandex and iFlow CLI. The marks are their owners' trademarks, shown only to say which tool is running.

**On Mac**, **Settings** ▸ **Appearance** ▸ **Show All Windows** ▸ **Blur previews** softens what each picture shows, so a screenshot of it can be shared. Lines keep their shape, but the letters can't be read; names stay sharp. It is kept on this Mac.

The pictures are only pictures: nothing is typed into a session, and no window changes size.

## Close a session

In **Active**, swipe left on a session and choose **Close**, or right-click it (touch and hold on touch devices) and choose **Close**.

A terminal kept in tmux says so under its name, and its action is **Detach** instead: it leaves the session running on the machine, where **Active** then lists it as **Detached**.

## Bring the library back on Vision Pro

When you leave the library window alone, it gets out of the way. After two minutes with no tap, scroll or typing in it, while another of the app's windows is open, it shrinks into a small glass orb in the same place. The orb shows the app's icon, and on its rim ⚡ and the number of sessions **Active** lists, when there are any.

- Look at the orb: it grows a little and shows **Connections** beneath it.
- Tap it (look and pinch) to bring the library window back where it was, at the size it was, showing what it showed before.
- ⚡ in a session, or **Connections** in a terminal window, also brings the library window back, and the orb goes.

The library window keeps its size while it is the only window open, while a sheet, alert or menu is open over it, while you are typing in it, and while a connection you started from it is still connecting. To wait longer, or never shrink, change **Settings** ▸ **General** ▸ **Shrink Connections when idle**; see [Settings](library-settings.md#general).

> [!NOTE]
> Vision Pro does not tell apps where you are looking, so looking at the orb shows its name and a tap brings the window back. With **Dwell Control** on (**Settings** ▸ **Accessibility** ▸ **Interaction** ▸ **Dwell Control**), holding your gaze on the orb taps it.

If you close the library window while nothing else is open, the orb takes its place. Tap it to open the library again. Close the orb too to leave nothing open. If you close your last session window, the library opens again.

## Shrink a session window to an orb on Vision Pro

A terminal, remote desktop, database or editor window can shrink into a small glass orb where it stands, and grow back when you want it, the way the library window does. Its session keeps running while it is an orb: terminals stay connected, and so does a desktop.

- Choose **Shrink to Orb**, first in the window's bottom bar. A terminal window with two or more terminals has it in its **Terminal View** menu instead: pinch and hold the layout button and choose **Orb**.
- The orb is a glass sphere with the session's live picture in it: the terminal in front, or the desktop's screen. A database or editor window shows itself as it looked when it shrank.
- Look at the orb: it grows a little and shows the window's name below it.
- Pinch the orb, or its name, to bring the window back where it was, at the size it was.

A terminal window's terminals sit around its orb as small glass dots, up to 12, each colored as its tab shows its state. Look at a dot to see that terminal's picture in the orb and its name beside the dot; you can look across to the name to read it. Pinch the dot, or the name, to bring the window back with that terminal in front.

When the window has **Auto-focus on activity** on, the orb pulses while a terminal in it prints, and shows the terminal that printed last. See [Give a terminal window its own settings](terminal-settings.md#give-a-terminal-window-its-own-settings).
