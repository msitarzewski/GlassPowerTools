# Keep terminals running with tmux

With **Keep Sessions Running with tmux** on, each terminal you open on a machine runs inside its own tmux session there. The work keeps going when the connection drops, when the app is suspended, or when you close the terminal, and you can pick it up again from **Active** on any of your devices.

The machine needs tmux installed (for example `sudo apt install tmux`, or `brew install tmux` on a Mac). Each time a terminal connects, Glass Power Tools checks whether the machine has it.

## Turn it on

The first time you connect to a machine that has tmux, the terminal asks **Keep Terminals Running with tmux?** Choose **Turn On**, or **Not Now**. Either answer is remembered on all your devices, so you're asked once. With **Turn On**, the next terminal you open there runs in tmux; the one you're in is left as it is.

To change it later:

1. In the library, select the host and edit its **Terminal** service.
2. Under **Advanced**, turn **Keep Sessions Running with tmux** on or off.
3. Save.

The switch can only be turned on once a connection has found tmux on the machine. Before the first connection it says to connect once; if tmux wasn't there, it says to install it and connect again. The setting belongs to that one Terminal service, and it syncs to your other devices with the rest of the library.

## What changes when you connect

- Each terminal gets its own session on the machine: **Terminal 1**, **Terminal 2**, and so on (named `glass-1`, `glass-2` in tmux). Open as many terminals on the machine as you like; each one is separate.
- If the connection drops, **Reconnect**, or the automatic reconnect, goes back into the same session, with everything still running.
- Closing the terminal leaves its session running on the machine, so closing it, its window, or quitting doesn't ask first (unless other terminals there would stop). To end it, end it from **Active** (below), or type `exit` in it.
- In **Active**, a terminal in tmux says **in tmux** under its name, and swiping it offers **Detach** rather than **Close**. Its tools menu says **Detach** rather than **Disconnect**. Afterwards **Active** lists it under the machine as **Detached**.
- **Open Folder Here** and the **AI Assistant** ask tmux which folder the shell is in, so they follow your `cd` inside tmux too.
- Detaching from tmux yourself (its prefix key, then **d**) closes the terminal and leaves the session running.
- A Workgroup remembers each terminal's session and opens on it again. Its startup command runs only when the session is new, never into one still running. See [Save and open terminal Workgroups](terminal-workgroups.md).
- A new terminal never takes a session a saved Workgroup keeps on that machine.
- **On Vision Pro, iPad and iPhone**, after the app quits, crashes or is updated, the terminal windows and sets holding terminals in tmux come back, each terminal on its own session (see [Work in a terminal](terminal-sessions.md#windows-and-tabs)).

If the machine doesn't have tmux, the terminal says so and opens an ordinary shell instead.

## Scroll back

tmux keeps its own history, so scrolling over a terminal in tmux scrolls tmux's history: two fingers on a trackpad, a mouse wheel, a finger on iPad and iPhone, or pinch and drag on Vision Pro. Scroll back to the bottom, or press **q**, to return to typing. While you are scrolled back, keys go to tmux's history view rather than to the program.

## One session in several places

A session can be open in more than one place at once: on your Mac and your Vision Pro, say. Both show the same screen, and typing in either goes to the same program. The window fits the device you used last. **Active**'s **Open** joins whoever is already there; **Take Over** disconnects them first.

## Pick up a session from Active

**Active** lists, under each machine, the tmux sessions running there. A session is called what its tab would be called: the name you gave the tab, else the title its program set, else the Git repository it's in, else the folder it's in, else **Terminal 1**, **Terminal 2** and so on. Under the name is where it is (the repository and branch, or else the folder) unless the name already says it, and then where it's open:

- **Detached**: nobody is attached. It may be one you closed, one from a dropped connection, or one you started on another device.
- **Open elsewhere**: another device, or a terminal outside Glass Power Tools, is attached.
- **Open here**: a tab on this Mac shows it. Choosing it brings that tab forward.

A terminal this device has open over SSH is listed with the open sessions instead, so nothing appears twice. Your own tmux sessions, with names you gave them, are listed too.

Choose a session to open it here. To use it here and disconnect everyone else, right-click it (touch and hold on touch devices) and choose **Take Over**.

**Active** checks your machines when it appears. To check again, choose **Check Machines** in its toolbar, or pull down the list on iPhone and iPad. Only machines with the setting on are checked, and only those that can sign in without asking. A machine that wasn't checked says why under its name, for example **Not checked: signing in would need your password.** Save the password, or connect to the machine once (to trust its host key), and check again.

## Open several together

To open several running sessions at once, choose them in **Active** and open them together, a terminal for each, the way **Move 3 Tabs to New Window** gathers tabs. They can be on different machines.

- **On Mac:** ⌘-click the sessions, or ⇧-click to choose a range. Then choose **Open 3 in New Window** in the toolbar (with however many you chose), or right-click one of them and choose it there. They open in one new window, a tab for each. A click with neither key held still opens one session at once.
- **On Vision Pro:** choose **Select** at the top of **Active**, tap each session you want, then choose **Open 3 in New Window** at the bottom. They open as one workgroup window with a terminal for each. **Done** leaves without opening anything.
- **On iPad and iPhone:** the same, with **Open 3 Together**. They open as one workgroup, in place of the library as a terminal does. On iPhone only the terminal on screen connects, and each of the others connects when you switch to it.

They open in the order **Active** lists them, each on its own session, joining whoever is already there. A session that says **Open here** stays where it is and isn't counted. A machine that allows legacy SSH algorithms is left out, because it asks before each connection: open its sessions one at a time. Nothing is saved as a workgroup.

## Names travel with the session

When you rename a tab that runs in tmux, on any of your devices, its session keeps the name. **Active** on each of your devices lists the session by that name, and a tab that opens the session later takes the name too. A terminal that already has the session open shows the new name without reopening it: on Vision Pro, iPad and iPhone, and in an SSH tab on a Mac, the next time something happens in that terminal; in a Mac's local tab, the next time something happens in any of the Mac's local terminals. **Use Automatic Name** removes the name from the session as well, and those tabs go back to their automatic names.

When a tab on a Mac opens a session that has a different name from the tab, the session's name wins: it was given on another device while the tab was closed. A session with no name is given the tab's, for example when you renamed the tab while its connection was down.

A session also keeps the repository and branch its tab last showed, so **Active** on your other devices lists them too. If the branch changes while no tab shows the session, other devices show the old branch until a tab shows it again. On the Mac itself, **Active** reads the repository and branch of each of the Mac's own sessions from its folder each time it checks.

## End a session

In **Active**, swipe left on a running session and choose **End**, or right-click it and choose **End Session…**. Everything running in it stops, on every device.

To end several, choose them as you would to open them together (above), then right-click one and choose **End 3 Sessions…** on a Mac, or choose **End 3 Sessions…** at the bottom on iPhone, iPad and Vision Pro. It asks once for all of them. A session that couldn't be ended is named afterwards, with why.

## Local terminals on a Mac

A Mac's own terminals can be kept in tmux too, so quitting or updating Glass Power Tools doesn't stop what's running in them: a build, a server, a long command.

1. Install tmux, for example `brew install tmux`.
2. Open Settings, choose **Terminal**, and under **Local Terminal** turn on **Keep local terminals running with tmux**. Until the Mac has tmux, the switch is off and says how to install it.

Each local terminal you open afterwards runs in its own tmux session on the Mac.

- **Quit** the app and the sessions keep running. When it opens again, each tab picks up where it was. Windows of SSH terminals in tmux come back too, each terminal on its own session.
- **Close** a tab, a pane or a window and its session keeps running, as for a terminal in tmux on any other machine. Its tools menu says **Detach** rather than **Disconnect**.
- **Active** lists the Mac's sessions under **This Mac**. Those a tab shows say **Open here**, and choosing one brings its tab forward. Open the others again, take one over from another terminal, or end one (swipe left and choose **End**, or right-click and choose **End Session…**). Typing `exit` in the session ends it too.
- The tab's name follows the program's title, the repository and the folder you `cd` into, as it does without tmux. A Mac's SSH tabs in tmux do the same, from the session on the other machine.

To reach these sessions from another device, turn on **Remote Login** on the Mac (System Settings, **General**, **Sharing**) and add the Mac to the library with a Terminal service that keeps sessions running with tmux. **Active** on your other devices then lists the Mac's sessions like any machine's. On the Mac itself, **Active** recognizes that machine as this Mac and lists its sessions once, under **This Mac**.
