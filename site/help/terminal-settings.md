# Terminal settings, themes and snippets

The terminal adds three pages to Settings: **Connections**, **Terminal** and **Snippets**. This page covers what each controls, editing themes, giving a terminal window its own look, importing an SSH config file, and Tailscale.

## Connections

- **Auto-reconnect on disconnect**: try again after a dropped connection. On by default.
- **Confirm before closing active sessions**: ask before disconnecting a connected session. On by default.
- **Keep scrollback during session** and **Max scrollback lines** (1,000 to 100,000; default 10,000). Scrollback stays in memory and is cleared when the session ends.
- **On Mac**, **Local Terminal**: the **Shell** and **Working directory** for new local terminals. Leave them empty for your login shell and home folder. A Workgroup's tab can override them. **Keep local terminals running with tmux** keeps them running when you quit or update the app; see [Keep terminals running with tmux](terminal-tmux.md#local-terminals-on-a-mac).
- **Session Recording**: how many recordings you have and the space they use.
- **Bell enabled** plays a sound when a program rings the bell. It is off by default. **Visual bell** also flashes the terminal, and works only while **Bell enabled** is on.
- **Host key verification**: **Ask** or **Strict**. See [Sign in with keys and trust host keys](terminal-keys-and-trust.md).

## Terminal

- **Theme**: the current theme and its font. **Edit Theme** opens the theme editor.
- **Canvas**: a tint for the terminal background. **On Vision Pro**, **Interactive glass** too. Opacity and frost are shared with every window and set in Settings under **Appearance**.
- **Font Family** (**SF Mono**, **Monaco**, **Menlo** or **Courier New**) and **Font Size** (10 to 24 points).
- **Initial Terminal Size**: **Columns** and **Rows** for a new terminal before its window is measured.
- **Cursor Style** (**Block**, **Underline** or **Bar**) and **Blinking cursor**.

## Edit a theme

1. Choose **Edit Theme**.
2. Select a theme in **Themes**. **New** and **Duplicate** make an editable copy; **Delete** removes a custom theme; **Reset** restores a built-in one.
3. Change its **Name**, **Canvas Material** (**Automatic**, **Light** or **Dark**), **Background**, **Foreground**, **Cursor**, **Selection**, font, and each normal and bright color under **ANSI Colors**. **Preview** shows the result.
4. Choose **Save**. The selected theme becomes the terminal's theme.

**On Mac:** **Import** reads a Terminal profile **From .terminal File…**, or from **Apple Built-in Profiles**.

**Sync terminal settings**, under **iCloud Sync**, keeps your themes the same on every device. It also syncs your Workgroups and your reconnect, closing, scrollback, bell, cursor, initial size and tint preferences. It never syncs passwords, keys, saved connections, host keys or snippets.

## Give a terminal window its own look

A terminal window can have its own tint, opacity and blur, so you can tell your windows apart at a glance. In any tab of the window, open the tools menu and choose **Settings**: it opens on **This Window**. **All Terminals**, beside it, changes every terminal window. **On Mac**, a local terminal's tools menu opens the same **Settings**; the app's own Settings are in the app menu, or press ⌘,.

Set **Opacity**, **Blur** and a **Glass Tint**. **On Vision Pro**, also **Frost** and **Interactive glass**. Every tab in the window changes at once. Anything you leave unset follows your settings, and **Reset Overrides** returns the window to them. The window's outer glass on Vision Pro follows **Appearance** in Settings, which every Glass window shares. A tint colours the terminal whatever its opacity; for a completely clear terminal, set **Opacity** and **Blur** to zero and choose no tint.

- A tab you move into another window takes that window's look. **Move Tab to New Window** gives the new window the look of the one the tab left.
- The look stays with the window: it comes back when the app relaunches.
- **On Mac**, the tab icons in the window's sidebar take its tint.
- **On Mac**, **Save Workspace as Workgroup…** saves the window's look with the Workgroup, and the Workgroup opens with it, on every device where **Sync terminal settings** is on. Changing a window's look doesn't change a saved Workgroup; to update one, save the window again under its name and choose **Replace**.

## Snippets

A snippet is a saved command you run from a terminal's tools menu.

1. Open the **Snippets** page and choose **Add Snippet**.
2. Enter a **Name** and the **Command**. **Description (optional)** and tags are optional.
3. Choose **Add**.

Each snippet shows how often and how recently you used it. Its edit button changes it; swipe it away, or use Delete, to remove it.

## Import an SSH config file

1. On the **Connections** page, under **Import SSH Config**, paste the contents of an OpenSSH `config` file.
2. Choose **Import into Server Configs**.

Each explicit `Host` entry becomes a saved connection, using `HostName`, `User`, `Port` and `IdentityFile`. The result lists how many were imported, updated and skipped, and why. `Match`, `Include`, wildcard entries and other options are skipped and reported.

> [!NOTE]
> An `IdentityFile` must match a key you have already imported under **SSH Keys**. The importer never reads key files.

## Tailscale

1. On the **Connections** page, under **Tailscale**, enter your **Tailnet name**.
2. Choose an **Auth method**, **API Key** or **OAuth Client**, and enter the credentials.
3. Choose **Save & Test**. **Connected to Tailscale.** confirms it works.

The library toolbar then has **Tailscale**, which lists your tailnet's devices. Select a device and choose **Import** to save it as a connection, finishing the form that opens, or **Connect** to enter a username, password and port and sign in once without saving.
