# Browse your machines

The library is the window that lists every machine you use, called a host, and the services on each one: a terminal, a database, a remote desktop. This page explains how the library is laid out on each device, how to search it, and what a host's details tell you.

## Find your way around the library

**On Vision Pro:** A tab bar beside the library window holds **All**, **Favorites**, **Recent** and **Collections**, followed by a tab for each panel, such as **Active** and **SSH Keys**. The window shows the list of hosts on the left and the selected host's details on the right. **Add Host**, **Settings** and **Active Connections** (⚡) sit in a bar below the window. Left alone while other windows are open, the library shrinks into a small orb; tap the orb to bring it back. See [Bring the library back on Vision Pro](library-connect.md#bring-the-library-back-on-vision-pro).

**On Mac:** The library window is titled **Connections**. Its sidebar has a **Library** section with **All Connections**, **Favorites**, **Recent** and **Active**, each with a count. Below it are **Collections** (once any host belongs to one), **Keys** with **SSH Keys**, and sections such as **Workgroups**. The middle column lists hosts and the right column shows the selected host. **Add Host** (+) is in the toolbar above the host list, and ⚡ is at the top right.

**On iPad:** At full width the library has the same three columns as on Mac. The toolbar holds ⚡, **Add Host** (+) and **Settings** (gear). In a narrow window it works as it does on iPhone.

**On iPhone:** The library opens on the list of categories. Tap a category to see its hosts, then tap a host to see its details. ⚡, **Add Host** and **Settings** are in the toolbar.

## Search the library

1. Select the category you want to search, such as **All Connections** or **Favorites**.
2. Type in the **Search connections...** field.

The list shows hosts whose name, other names (**Also known as**), collection names or service names contain what you type. Upper and lower case do not matter. The search applies only to the category you selected.

## Read a host's details

Select a host to see two sections.

**Services** lists each service on the host with its kind: **Terminal**, **Database** or **Desktop**. Each row has a **Connect** button (play symbol) and an **Edit** button (pencil). When the row is too narrow, extra actions move into a **More** menu. Rows for tools that a service provides, such as a file browser, appear under the services with an **Open** button. **Add a service…** is at the end of the section.

> [!NOTE]
> A service marked **Not set up** in orange has no saved settings behind it. Connecting cannot work. Right-click it, or touch and hold it, choose **Remove Service**, then add it again.

**Host** shows:

- **Address**: the hostname or IP address. If the records that make up the host disagree, every address is listed and you are asked to edit the host to settle it.
- **Also known as** and **Collections**, when set.
- **Last connected**: how long ago a session on this host last connected, or **Never**.
- **Connect opens**: the service that opens when you connect the host without choosing one.
- **Add Favorite** or **Remove Favorite**.

**Edit** at the bottom of the details opens the host's settings.

## This device

The first host in the list is the device you are using: **This Mac**, **This iPad**, **This iPhone** or **This Apple Vision Pro**. Its address reads **This device**, because its services reach it at 127.0.0.1 or open a file you choose.

- **On Mac:** it includes **Local Shell**, marked **Terminal · Built in**, which opens a terminal on your Mac.
- You can add Database and Desktop services to it, such as a SQLite file or a database server running on the same device.
- You can rename it, mark it as a favorite and put it in collections. You cannot delete it, and built-in services cannot be edited or removed.

> [!NOTE]
> This device's host is never copied to your other devices. Each device has its own.

## The library at a glance

With no host selected, the library's detail shows an overview: how many machines, services, favorites and collections you have, the services of each kind, the connections this device made in the last 30 days, and the machines it used most. Choose one of those machines to select it.

The connection history is kept on this device only. It records when you connected and to which kind of service on which machine, and nothing else. It never syncs, and it keeps 90 days.

A green dot on a service's icon means it's **connected** right now: a terminal, database or desktop session through it is open and connected, on this device. The dot appears on the host's row and beside the service in the host's detail, and goes when you disconnect. A session still connecting or reconnecting has no dot yet.

To see at a glance which services are answering, turn on **Settings** ▸ **General** ▸ **Show service availability**. See [Settings](library-settings.md#general).
