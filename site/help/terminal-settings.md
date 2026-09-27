# Terminal settings, themes and snippets

The terminal adds three pages to Settings: **Connections**, **Terminal** and **Snippets**. This page covers what each controls, editing themes, per-session appearance, importing an SSH config file, and Tailscale.

## Connections

- **Auto-reconnect on disconnect**: try again after a dropped connection. On by default.
- **Confirm before closing active sessions**: ask before disconnecting a connected session. On by default.
- **Keep scrollback during session** and **Max scrollback lines** (1,000 to 100,000; default 10,000). Scrollback stays in memory and is cleared when the session ends.
- **On Mac**, **Local Terminal**: the **Shell** and **Working directory** for new local terminals. Leave them empty for your login shell and home folder. A Workgroup's tab can override them.
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

**Sync terminal settings**, under **iCloud Sync**, keeps your themes the same on every device. It also syncs your reconnect, closing, scrollback, bell, cursor, initial size and tint preferences. It never syncs passwords, keys, saved connections, host keys or snippets.

## Change one session's appearance

In a terminal, open the tools menu and choose **Settings**, then **Overrides**. **On iPad**, the row is **Session Appearance**.

Set **Opacity**, **Blur** and a tint for this session only. **On Vision Pro**, also **Frost** and **Interactive glass**. **Reset Overrides** returns to your settings. Overrides do not sync.

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
