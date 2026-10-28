# Terminal settings, themes and snippets

The terminal adds three pages to Settings: **Connections**, **Terminal** and **Snippets**. This page covers what each controls, choosing a theme or a color scheme, editing themes, giving a terminal window its own settings and look, importing an SSH config file, and Tailscale.

## Connections

- **Auto-reconnect on disconnect**: try again after a dropped connection. On by default.
- **Confirm before closing active sessions**: ask before disconnecting a connected session. On by default.
- **Keep scrollback during session** and **Max scrollback lines** (1,000 to 100,000; default 10,000). Scrollback stays in memory and is cleared when the session ends.
- **Suggest fixes for errors**: when a terminal's output shows an error, Apple Intelligence on this device explains it and offers a fix to review. On by default, and kept on this device. To stop it in one terminal only, use the menu on the suggestion itself; see [The session's tools menu](terminal-sessions.md#the-sessions-tools-menu).
- **On Mac**, **Local Terminal**: the **Shell** and **Working directory** for new local terminals. Leave them empty for your login shell and home folder. A Workgroup's tab can override them. Whether they run in tmux is on the **Terminal** page, under **tmux**.
- **Session Recording**: how many recordings you have and the space they use.
- **Bell enabled** plays a sound when a program rings the bell. It is off by default. **Visual bell** also flashes the terminal, and works only while **Bell enabled** is on.
- **Host key verification**: **Ask** or **Strict**. See [Sign in with keys and trust host keys](terminal-keys-and-trust.md).

## Terminal

- **Theme**: the theme or color scheme every terminal uses, its font, and a few of its colors. **Choose…** opens **Choose Theme** (see [Choose a theme or a color scheme](#choose-a-theme-or-a-color-scheme)); **Edit Theme** opens the theme editor.
- **Canvas**: a tint for the terminal background. **Opacity**, **Glass** and **Material** are shared with every window and set in Settings under **Appearance**. A window can keep its own of these and more; see [Give a terminal window its own settings](#give-a-terminal-window-its-own-settings).
- **Font Family** (**SF Mono**, **Monaco**, **Menlo** or **Courier New**) and **Font Size** (10 to 28 points).
- **On iPhone, iPad and Vision Pro**, **Scale with System Text Size** (on by default): **Font Size** is the size at the standard text size, and a larger text size in the system's Settings makes the terminal's text larger too. Turn it off to keep the terminal at **Font Size** whatever the system's text size. It is kept on this device only.
- **Initial Terminal Size**: **Columns** and **Rows** for a new terminal before its window is measured.
- **On Vision Pro, Mac and iPad**, **Resizing**: **When a window is resized**, choose **Change Rows and Columns** (the starting setting), where a smaller window holds fewer and the program redraws to fit, or **Scale the Text**, where the terminal keeps its rows and columns and its text grows and shrinks with the window. **Scale Text** in a window's bar switches that window alone. See [Scale the text with the window](terminal-sessions.md#scale-the-text-with-the-window).
- **Cursor Style** (**Block**, **Underline** or **Bar**) and **Blinking cursor**.
- **On Mac and Vision Pro**, **Previews**: **Show previews**, **Never**, **Mouseover** (the starting setting) or **Mouseover + Space**, for the file a path in a terminal names. See [Preview a file over the terminal](terminal-sessions.md#preview-a-file-over-the-terminal).
- **On Mac**, **tmux**: **Keep local terminals running with tmux** keeps local terminals running when you quit, update or force quit the app. **Running in the background** shows whether they are running and how many there are, and **End All Local Terminals…** ends them all. See [Local terminals on a Mac](terminal-tmux.md#local-terminals-on-a-mac). Each saved host has its own tmux setting, in its Terminal service; see [Turn it on](terminal-tmux.md#turn-it-on).

## Choose a theme or a color scheme

**Choose…**, beside **Theme**, opens **Choose Theme**. It lists **Your Themes** (the theme library) and **Terminal Themes**: color schemes from macOS Terminal profiles. Each is drawn small in its own colors: its background, a prompt in its text color, a word highlighted as a selection, and its sixteen ANSI colors. Choose one and every terminal uses it at once; the search field finds one by name. **Done** closes it.

**Terminal Themes** are `.terminal` files, the profiles macOS Terminal exports and that color-scheme collections come as:

- **Import…** adds them: choose files, or a folder of them. Each is read before it's added; one that isn't a Terminal profile is named, with the reason. A profile with the same name as one already there replaces it, so importing a collection again updates it.
- They're kept in **iCloud Drive ▸ Glass Power Tools ▸ Terminal Themes**, so every device that uses your iCloud Drive has them, and you can add or remove files there in Files or the Finder. Without iCloud Drive, they're kept on this device.
- **Open With ▸ Glass Power Tools** on a `.terminal` file in the Finder, AirDrop, or opening one from Files adds it too; a single file becomes the scheme every terminal uses. **On Mac**, files opened together are added together, and a message says what was added.
- A scheme brings its **background**, **text**, **selection**, **cursor** (its text color, if it has none) and its sixteen colors, read as Terminal reads them; how much of the background shows is still the window's **Opacity**. Your font stays. A profile's bold-text color isn't used: bold text is drawn in the text color, or in the bright form of one of the sixteen.
- Pinch and hold, or right-click, a scheme for **Copy to Your Themes**, which makes it an ordinary theme in your library to change in the theme editor (and uses it), or **Delete…**, which removes its file from Terminal Themes on every device.

Which scheme every terminal uses syncs with **Sync terminal settings**. A device that doesn't have its file yet uses your theme until the file arrives.

## Edit a theme

1. Choose **Edit Theme**.
2. Select a theme in **Themes**. **New** and **Duplicate** make an editable copy; **Delete** removes a custom theme; **Reset** restores a built-in one.
3. Change its **Name**, **Canvas Material** (**Automatic**, **Light** or **Dark**), **Background**, **Foreground**, **Cursor**, **Selection**, font, and each normal and bright color under **ANSI Colors**. **Use Apple Clear Dark Colors** takes the text, cursor, selection and ANSI colors of Terminal's Clear Dark profile and sets **Canvas Material** to **Dark**; the background, name and font stay as they are. **Preview** shows the result.
4. Choose **Save**. The selected theme becomes the terminal's theme.

**On Mac:** **Import** reads a Terminal profile **From .terminal File…**, or from **Apple Built-in Profiles**, into your library as a theme of its own, with its background and, if this Mac has it, its font. To keep many profiles, use **Choose…** ▸ **Import…** instead.

Saving the theme editor makes its selected theme the one every terminal uses, in place of a color scheme.

**Sync terminal settings**, under **iCloud Sync** in the theme editor's list of themes, keeps your themes the same on every device. It also syncs your Workgroups and your reconnect, closing, scrollback, bell, cursor, initial size, resizing, previews and tint preferences. It never syncs passwords, keys, saved connections, host keys or snippets.

## Give a terminal window its own settings

Anything about how a terminal window looks and behaves can be set for that window alone, so you can tell your windows apart at a glance, or keep a larger font in one. In any tab of the window, open the tools menu and choose **Settings**: it opens on **This Window**. **All Terminals**, beside it, changes every terminal window. iPhone has no **This Window**: its terminals all use **All Terminals**. **On Mac**, a local terminal's tools menu opens the same **Settings**; the app's own Settings are in the app menu, or press ⌘,.

**This Window** has:

- **Appearance**: **Opacity**, **Glass** and a **Glass Tint**. **On iPad**, also **Material**.
- **Theme**: any theme from your theme library, or a color scheme from **Terminal Themes**, its **Font Family** and its **Font Size**.
- **Look** and **Text**: a background behind the text (a picture, **Digital Rain**, **Synthwave** or **Phosphor Screen**), **Readability**, a **Text Palette** and a **Text Glow**, or a whole look from **Start From**. See [Backgrounds and glowing text](terminal-looks.md).
- **Cursor**: **Cursor Style** and **Blinking cursor**.
- **When resized** (**on Vision Pro, Mac and iPad**): **Change Rows and Columns** or **Scale the Text**. **Scale Text** in the window's bar changes this setting.
- **Show previews** (**on Mac and Vision Pro**): **Never**, **Mouseover** or **Mouseover + Space**.
- **Bell and Scrollback**: **Bell enabled**, **Visual bell**, **Keep scrollback during session** and **Max scrollback lines**.
- **Activity** (**on Vision Pro**): **Auto-focus on activity**. While a terminal in this window prints, **Grid** and **Carousel** bring it forward, and the window's orb pulses (see [Shrink a session window to an orb on Vision Pro](library-connect.md#shrink-a-session-window-to-an-orb-on-vision-pro)). Until you change it here, it follows the saved Workgroup the window was opened from, and is otherwise off.

Each setting follows **All Terminals** (or **Appearance**, or **Settings**) until you change it here. Once you do, a small ↺ appears beside its name; choose it to follow again. Its tooltip says what it returns to: hold the pointer over it, or on Vision Pro look at it. **Reset This Window**, at the end, returns every one. Every tab in the window changes at once.

**Opacity**, **Glass** and **Material** are the window's own **Appearance**: change them here and only this window changes; change them in Settings under **Appearance** and every window that hasn't set its own changes. A tint colours the terminal whatever its opacity; for a completely clear terminal, set **Opacity** and **Glass** to 0% and choose no tint. **On Vision Pro**, **Glass** is the window's glass: at 100% it's the system's glass, and at 0% there is none, so only the text floats in the room. **Opacity** paints the area behind the text.

A theme comes from your theme library, which syncs with **Sync terminal settings**, or from **Terminal Themes** in iCloud Drive. If a window's theme or scheme isn't on this device yet, the window uses the theme from **All Terminals** until it arrives.

Some settings are only ever for every window: **Initial Terminal Size** (a window that is already open has its own size), and the settings for connections, host keys, Tailscale, SSH keys, local shells, recordings, snippets and sync.

- A tab you move into another window takes that window's settings. **Move Tab to New Window** gives the new window the settings of the one the tab left.
- The settings stay with the window: they come back when the app relaunches.
- **On Mac**, the tab icons in the window's sidebar take its tint.
- **On Mac**, **Save Workspace as Workgroup…** saves the window's settings with the Workgroup, and the Workgroup opens with them, on every device where **Sync terminal settings** is on. Changing a window's settings doesn't change a saved Workgroup; to update one, save the window again under its name and choose **Replace**. A device not yet updated still opens it with the window's glass and tint.

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
