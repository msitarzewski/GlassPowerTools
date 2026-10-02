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
- Detaching from tmux yourself (its prefix key, then **d**) closes the terminal and leaves the session running.
- A Workgroup's startup command runs inside the new session the first time it is created.

If the machine doesn't have tmux, the terminal says so and opens an ordinary shell instead.

## Pick up a session from Active

**Active** lists, under each machine, the tmux sessions running there that this device isn't showing:

- **Detached**: nobody is attached. It may be one you closed, one from a dropped connection, or one you started on another device.
- **Open elsewhere**: another device, or a terminal outside Glass Power Tools, is attached.

Your own tmux sessions, with names you gave them, are listed too.

Choose a session to open it here. To use it here and disconnect everyone else, right-click it (touch and hold on touch devices) and choose **Take Over**.

**Active** checks your machines when it appears. To check again, choose **Check Machines** in its toolbar, or pull down the list on iPhone and iPad. Only machines with the setting on are checked, and only those that can sign in without asking: if a machine's password isn't saved, or its host key hasn't been trusted yet, connect to it once first.

## End a session

In **Active**, swipe left on a running session and choose **End**, or right-click it and choose **End Session…**. Everything running in it stops, on every device.
