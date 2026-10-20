# Browse your machines

The library is the window that lists every machine you use, called a host, and the services on each one: a terminal, a database, a remote desktop. This page explains how the library is laid out on each device, how to search it, what a host's details tell you, this device's own host and the Mac's link to its machine in the library, and the overview of how you use your machines.

## Find your way around the library

**On Vision Pro:** A tab bar beside the library window holds **All**, **Favorites**, **Recent** and **Collections**, followed by a tab for each panel, such as **Active** and **SSH Keys**. The window shows the list of hosts on the left and the selected host's details on the right. **Search connections** above the list filters it, and the sidebar button at the top left of the details hides and shows the list (⌃⌘S with a keyboard). **Add Host**, **Settings** and **Active Connections** (⚡) sit in a bar below the window. Left alone while other windows are open, the library shrinks into a small orb; tap the orb to bring it back. See [Bring the library back on Vision Pro](library-connect.md#bring-the-library-back-on-vision-pro).

**On Mac:** The library window is titled **Connections**. Its sidebar has a **Library** section with **All Connections**, **Favorites**, **Recent** and **Active**, each with a count. Below it are **Collections** (once any host belongs to one), **Keys** with **SSH Keys**, and sections such as **Workgroups**. The middle column lists hosts and the right column shows the selected host. **Add Host** (+) is in the toolbar above the host list. The toolbar also has ⚡, **Local Terminal**, **Show All Windows**, **Import RDP File…** and, once Tailscale is set up, **Tailscale**. **File** ▸ **New Connections Window** (⇧⌘N) opens another library window.

**On iPad:** At full width the library has the same three columns as on Mac. The toolbar holds ⚡, **Add Host** (+), **Settings** (gear), **Import RDP File…** and, once Tailscale is set up, **Tailscale**. In a narrow window it works as it does on iPhone.

**On iPhone:** The library opens on the list of categories. Tap a category to see its hosts, then tap a host to see its details. ⚡, **Add Host** and **Settings** are in the toolbar, with **Import RDP File…** and, once Tailscale is set up, **Tailscale**.

## Search the library

1. Select the category you want to search, such as **All Connections** or **Favorites**.
2. Type in the **Search connections...** field.

The list shows hosts whose name, other names (**Also known as**), collection names or service names contain what you type. Upper and lower case do not matter. The search applies only to the category you selected.

## Read a host's details

Select a host to see two sections.

**Services** lists each service on the host with its kind: **Terminal**, **Database** or **Desktop**. Each row has a **Connect** button (play symbol) and an **Edit** button (pencil). Rows for tools that a service provides appear under the services with an **Open** button: **Files** for a Terminal service, and **Basic Terminal**, a shell outside tmux, for one that keeps its terminals in tmux (see [Open a terminal without tmux](terminal-tmux.md#open-a-terminal-without-tmux)). **Add a service…** is at the end of the section.

> [!NOTE]
> A service marked **Not set up** in orange has no saved settings behind it. Connecting cannot work. Right-click it, or touch and hold it, choose **Remove Service**, then add it again.

**Host** shows:

- **Address**: the hostname or IP address, or **Not set** for a host that has none yet. If the records that make up the host disagree, every address is listed and you are asked to edit the host to settle it.
- **Also known as** and **Collections**, when set.
- **Last connected**: how long ago a session on this host last connected, or **Never**.
- **Connect opens**: the service that opens when you connect the host without choosing one. It appears once you have chosen one of the host's services to connect to.
- **Add Favorite** or **Remove Favorite**.

**Edit** at the bottom of the details opens the host's settings.

## This device

The first host in the list is the device you are using: **This Mac**, **This iPad**, **This iPhone** or **This Apple Vision Pro**. Its address reads **This device**, because its services reach it at 127.0.0.1 or open a file you choose.

- **On Mac:** it includes **Local Shell**, marked **Terminal · Built in**, which opens a terminal on your Mac.
- You can add Database and Desktop services to it, such as a SQLite file or a database server running on the same device.
- You can rename it, mark it as a favorite and put it in collections. You cannot delete it, and built-in services cannot be edited or removed.

> [!NOTE]
> This device's host is never copied to your other devices. Each device has its own.

## When a machine in your library is this Mac

Your Mac may also be a machine in your library, added so your other devices can reach it: with a Terminal service over SSH, its databases, and Screen Sharing. On that Mac, the app knows the two are one machine:

- **By itself**, when the host key you trusted for the machine's Terminal service, on any of your devices, is this Mac's own. It takes no question.
- **By asking**, when the machine's address is one of this Mac's, since an address alone could pass to another machine: **Is alpha this Mac?**, with the machine's name. Choose **It's This Mac**, or **Not Now**, which is remembered, so you're asked once.
- **By you:** in the machine's settings (select it and choose **Edit**), turn on **This is this Mac**. Turn it off to separate the two again.

Once they are linked, on this Mac:

- The machine's row stands for this Mac. It comes first, and the line under its name starts **This Mac ·**. When **This Mac** has no services of its own, its row joins the machine's, which also lists **Local Shell** when the machine has no Terminal service of its own; otherwise both rows stay.
- **Connect** on the machine's Terminal service opens a terminal on this Mac, in tmux when local terminals are kept in tmux, instead of connecting to the Mac over SSH. A basic terminal, the command palette's **without tmux**, and a Workgroup still connect over SSH.
- Its databases are This Mac's: a local terminal's **Open in SQL Editor** offers them (see [Open SQL in the SQL editor](terminal-sessions.md#open-sql-in-the-sql-editor-mac)).
- Its Desktop services, such as Screen Sharing, aren't offered here, since they would show the screen you're looking at. They stay in the library for your other devices.
- **Active** lists the Mac's tmux sessions once, under **This Mac**.
- Time in use in a local terminal counts for the machine (see [The library at a glance](#the-library-at-a-glance)).

The link is kept on this Mac only. Your other devices see the machine as before and connect to it over the network. If the machine is deleted from the library, the link goes with it.

## The library at a glance

With no host selected, the library's detail shows an overview, **Your Library**: how many machines, services, favorites and collections you have, the services of each kind, how you used your machines in the last 30 days, and the machines used most. Choose one of those machines to select it.

**Time in Use** and **Connections**, under the chart's title, choose what it counts. It opens on **Time in Use**:

- **Time in Use** counts the minutes your sessions were in use: each minute in which a session had input or output counts once for its machine and its kind of service. Typing in a terminal or a program printing in it, running a query, opening a table or moving to another one, and a key, click, scroll or pointer move in a remote desktop all count. Two sessions on one machine through the same kind of service count one minute between them, and a session left open with nothing happening counts nothing. On a Mac, its local terminals count for **This Mac**, or for its machine in the library when the two are linked. Only sessions open in the app count: a tmux session running on a machine with no terminal open on it doesn't. The chart shows hours per day by kind of service, and **Most used** lists the machines by time, for example **41 h** or **45 min**.
- **Connections** counts, per day, each connection made with **Connect** in the library, as **Last connected** does; a reconnect, or a window that comes back after a relaunch, isn't counted again. **Most used** lists the machines by how many.

Time in use is counted from the version of the app that added it, so earlier days show connections only.

Both are those of all your devices, added up. When more than one device has used your machines in the last 30 days, a menu beside the chart's title chooses **All Devices** or one device, by its name; the chart and **Most used** follow it. A device's name is set in **Settings** ▸ **General** ▸ **This Device**.

Each device keeps its own history, for 90 days: when you connected, and its minutes in use, to which kind of service on which machine. What reaches your other devices, through iCloud, is how many connections it made and how many minutes it was in use each day of the last 30, for each machine and kind of service, and its name — not the times of day.

A green dot on a service's icon means it's **connected** right now: a terminal, database or desktop session through it is open and connected, on this device. The dot appears on the host's row and beside the service in the host's detail, and goes when you disconnect. A session still connecting or reconnecting has no dot yet.

To see at a glance which services are answering, turn on **Settings** ▸ **General** ▸ **Show service availability**. See [Settings](library-settings.md#general).
