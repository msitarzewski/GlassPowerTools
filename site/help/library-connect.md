# Connect and switch between sessions

You start a session from a host in the library, and you return to any open session from **Active**. This page covers the Connect controls, which service a host opens, and how to switch to or close open sessions.

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

Each of these opens one service: the one you connected to last on that host, or the first service if you have not chosen one yet. The host's details show which one under **Connect opens**.

The host's **Last connected** time and its place in **Recent** change only when a session actually connects. A failed or cancelled attempt does not count.

## See what is open

**Active** lists every open session: terminals, databases, remote desktops and editor windows.

- **On Vision Pro:** choose the **Active** tab beside the library window.
- **On Mac, iPad and iPhone:** choose **Active** in the sidebar's **Library** section. The number beside it is how many sessions **Active** lists: those open on this device, and the tmux sessions running on your machines when **Active** last checked.

Sessions are grouped under the host they belong to, with a count for each host. A host whose Terminal service keeps sessions running with tmux also lists the tmux sessions running there, by the names their tabs have, and a host **Active** couldn't check says why; see [Keep terminals running with tmux](terminal-tmux.md). Sessions that belong to no host in the library are grouped under **Elsewhere**. Collapse a host's group with its disclosure arrow. When nothing is open, **Active** says **Nothing Is Open**.

## Switch to a session

Choose a session in **Active** to switch to it. The open session comes back to the screen; a second session is not opened. You can also right-click the session, or touch and hold it, and choose **Switch To**.

## Get to Active from anywhere

Every session has **Active Connections** (⚡) at the right end of its top toolbar, and the library has one too.

- **On Vision Pro, Mac and iPad:** ⚡ brings the library window forward and opens **Active**. **On Vision Pro** there is only ever one library window, and a desktop's ⚡ is last in its control bar.
- **On iPhone:** ⚡ leaves the session screen and opens **Active** in the library.

## Close a session

In **Active**, swipe left on a session and choose **Close**, or right-click it (touch and hold on touch devices) and choose **Close**.

A terminal kept in tmux says so under its name, and its action is **Detach** instead: it leaves the session running on the machine, where **Active** then lists it as **Detached**.

## Bring the library back on Vision Pro

If you close the library window while nothing else is open, a small window with a spinning terminal symbol takes its place. Tap it to open the library again. Close that small window too to leave nothing open. If you close your last session window, the library opens again.
