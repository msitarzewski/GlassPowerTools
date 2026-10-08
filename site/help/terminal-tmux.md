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

If the machine doesn't have tmux, the terminal says so and opens an ordinary shell instead.

## Scroll back

tmux keeps its own history, so scrolling over a terminal in tmux scrolls tmux's history: two fingers on a trackpad, a mouse wheel, a finger on iPad and iPhone, or pinch and drag on Vision Pro. Scroll back to the bottom, or press **q**, to return to typing. While you are scrolled back, keys go to tmux's history view rather than to the program.

## One session in several places

A session can be open in more than one place at once: on your Mac and your Vision Pro, say. Both show the same screen, and typing in either goes to the same program. The window fits the device you used last. **Active**'s **Open** joins whoever is already there; **Take Over** disconnects them first.

## Pick up a session from Active

**Active** lists, under each machine, the tmux sessions running there that this device isn't showing:

- **Detached**: nobody is attached. It may be one you closed, one from a dropped connection, or one you started on another device.
- **Open elsewhere**: another device, or a terminal outside Glass Power Tools, is attached.

Your own tmux sessions, with names you gave them, are listed too.

Choose a session to open it here. To use it here and disconnect everyone else, right-click it (touch and hold on touch devices) and choose **Take Over**.

**Active** checks your machines when it appears. To check again, choose **Check Machines** in its toolbar, or pull down the list on iPhone and iPad. Only machines with the setting on are checked, and only those that can sign in without asking: if a machine's password isn't saved, or its host key hasn't been trusted yet, connect to it once first.

## End a session

In **Active**, swipe left on a running session and choose **End**, or right-click it and choose **End Session…**. Everything running in it stops, on every device.

## Local terminals on a Mac

A Mac's own terminals can be kept in tmux too, so quitting or updating Glass Power Tools doesn't stop what's running in them: a build, a server, a long command.

1. Install tmux, for example `brew install tmux`.
2. Open Settings, choose **Terminal**, and under **Local Terminal** turn on **Keep local terminals running with tmux**. Until the Mac has tmux, the switch is off and says how to install it.

Each local terminal you open afterwards runs in its own tmux session on the Mac.

- **Quit** the app and the sessions keep running. When it opens again, each tab picks up where it was. Windows of SSH terminals in tmux come back too, each terminal on its own session.
- **Close** a tab, a pane or a window and its session keeps running, as for a terminal in tmux on any other machine. Its tools menu says **Detach** rather than **Disconnect**.
- **Active** lists the Mac's sessions under **This Mac**: open one again, take it over from another terminal, or end it (swipe left and choose **End**, or right-click and choose **End Session…**). Typing `exit` in the session ends it too.
- The tab's name follows the program's title and the folder you `cd` into, as it does without tmux.

To reach these sessions from another device, turn on **Remote Login** on the Mac (System Settings, **General**, **Sharing**) and add the Mac to the library with a Terminal service that keeps sessions running with tmux. **Active** on your other devices then lists the Mac's sessions like any machine's.
