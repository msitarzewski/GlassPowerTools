# Save and open terminal Workgroups

A Workgroup is a saved set of terminal tabs, each with a connection and an optional startup command, that you open together. This page covers finding Workgroups, creating and editing them, and what happens when you open one.

## Find your Workgroups

Workgroups are in the library's sidebar, beside Collections, under **Workgroups**. Select one to see its terminals and startup commands.

**On Vision Pro and Mac**, **Library** > **Workgroups…** also opens them in a window of their own.

Use **Search workgroups...** to filter the list. A Workgroup's menu (right-click, or touch and hold) offers **Open**, **Edit**, **Duplicate** and **Delete**.

> [!NOTE]
> **Delete…** in that menu asks you to confirm. Deleting a Workgroup removes it from all your devices; the connections in it are not affected.

## Workgroups on all your devices

With **Sync terminal settings** on (Settings ▸ **Terminal**, under **iCloud Sync**), a Workgroup you create, edit or delete on one device does the same on your others. If it changes on two devices, the most recent change wins. When you last opened a Workgroup, and the replacements a device remembers for its Mac terminals, stay on that device.

## Create a Workgroup

- **On Vision Pro, iPad and iPhone:** choose the plus button (**New workgroup**) above the list. To capture the SSH terminals you have open now, choose the button beside it (**Save current SSH sessions as workgroup**).
- **On Mac:** arrange tabs and split panes in a terminal window, then choose **Save Workspace as Workgroup…** in its toolbar. This saves the window's tabs and split layout. With no Workgroup selected, **New Workgroup** in the detail also starts an empty one.

In **New Workgroup**:

1. Enter a **Name** and choose a color.
2. **On Mac:** choose how it opens with **Open in**: **Tabs**, **Grid** or **Carousel**. **Auto-focus on activity** follows new output while you view Grid or Carousel; it does not switch tabs.
3. Choose **Add Tab** for each terminal. In **Add Tab**:
   - **Type**: **SSH** or, on Mac, **Local**.
   - **Connection**: the saved connection to open, for an SSH tab.
   - **Label**: an optional name for the tab.
   - **Startup command**: an optional command to run once after the tab connects, for example `cd /srv/shop && git status`.
   - For a local tab: **Shell** and **Working directory**, or leave them empty to use the app's defaults.
4. To reorder tabs on Mac, use **Move Up** and **Move Down** in a tab's menu. Elsewhere, choose **Edit** above the tabs and drag them.
5. Choose **Save**.

A Workgroup holds up to 32 terminals.

> [!IMPORTANT]
> Startup commands are saved with the Workgroup. Do not put passwords or tokens in them.

## Open a Workgroup

Select it and choose **Open Workgroup**, or choose **Open** in its menu. **On Mac**, the command palette also lists each Workgroup as **Open** followed by its name.

All terminals start together. Each runs its startup command once, after it connects and its host key is checked, without waiting for the others.

- **On Vision Pro:** the terminals open as tabs in one terminal window. If a connection needs a password, you are asked for it before anything opens.
- **On Mac:** the Workgroup opens in a terminal window with its tabs and split layout, in the view you chose with **Open in**. A pane that cannot connect shows **Connection Failed** with **Enter Password…** (when a password is missing), **Retry** and **Close Pane**. The Workgroup's detail shows its running tabs under **Running terminals**.
- **On iPad and iPhone:** the terminals open in place of the library, after asking for any missing password. The list's **Live Terminals** section shows open Workgroups; **Resume Terminal** returns to one.

If some terminals cannot open, the others still do, and a message lists what failed and why.

## Open a Mac Workgroup on Vision Pro or iPad

Local terminals run only on a Mac. When a Workgroup has local tabs, **Use SSH Instead of Local** appears first.

1. For each local tab, pick a connection in **Use SSH connection**, or leave **Skip this terminal**.
2. Optionally enter a **Remote directory (blank uses SSH default)** and a **Startup command (optional)**.
3. Turn on **Remember replacements on this device** to offer the same choices next time. They are not synced.
4. Choose **Open Workgroup**.

Your saved Workgroup and its Mac terminals are not changed.

## Edit a Workgroup

Select it and choose **Edit**. Changes apply when you choose **Save**; **Cancel** discards them.

A Workgroup saved from a Mac window keeps its split layout. You can edit each terminal's settings anywhere, but to add, remove or rearrange its panes, open it on a Mac, change the window, and save the workspace again.

Closing a tab in an open Workgroup never changes the saved Workgroup.
