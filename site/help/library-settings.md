# Settings and window appearance

Settings for the whole app are in one place. This page covers opening Settings, the **General**, **Appearance**, **Privacy** and **About** pages, and how to make windows more or less transparent. The pages after **About** (**Connections**, **Terminal**, **Snippets**, **Databases**, **Desktops** and **Editor**) are described in the help for those features.

## Open Settings

- **On Vision Pro:** choose **Settings** (gear) in the bar below the library window. Settings opens in its own window, with its pages as tabs beside it.
- **On Mac:** choose **Glass Power Tools** ▸ **Settings…** (⌘,). The pages are icons across the top of the window, and Settings reopens on the page you last used.
- **On iPad:** choose **Settings** (gear) in the library's toolbar. Choose a page from the control at the top, and choose **Done** when you finish.
- **On iPhone:** choose **Settings** (gear) in the library's toolbar, then choose a page from the list. Every page has **Done**.

## Change how transparent windows are

Choose **Appearance**. The **Windows** section has:

- **Opacity**: how strongly the theme color is painted behind content, from transparent to opaque.
- **Glass**: how much glass is behind a window, from none to full. **On Mac:** the title bar follows this setting too.
- **Material** (**on Mac, iPad and iPhone**): the kind of glass: **Light**, **Medium**, **Heavy** or **Max**. It is unavailable while **Glass** is at 0%.
- **Reset Appearance**: returns to the starting settings: **Opacity** 0%, **Glass** 100% and **Material** **Heavy**.

The sliders settle on 0%, 50% and 100% when you drag near them. Text and controls stay fully visible at every setting. For a completely clear window, set **Opacity** and **Glass** to 0%.

**On Vision Pro:** there is no **Material** to choose. **Glass** is a window's own glass: at 100% it looks like any visionOS window, and at 0% there is none. **Opacity** paints only the area a window's content sits in (a terminal's text, a remote desktop's screen, the editor's text, a database's workspace, the Files list, the Connections detail), never the whole window. Terminal and remote desktop windows are completely clear with both at 0%. Connections, Files, the editor and the database keep visionOS's own glass behind their columns, so **Glass** doesn't make them clearer.

These settings also apply to terminal windows. They are kept on each device.

### One window's own glass

A window can keep its own **Opacity**, **Glass** and **Material** in place of these: terminal, editor and database windows. (A remote desktop window has its own glass settings instead; see its This Window.)

- In a terminal, open its tools menu, choose **Settings**, then **This Window**, which has **Opacity** and **Glass**, and **Material** on iPad; see [Give a terminal window its own settings](terminal-settings.md#give-a-terminal-window-its-own-settings).
- In an editor window, choose **Settings** (gear) in its toolbar, then **This Window**, which has **Opacity**, and **Glass** and **Material** on Mac and iPad; see [Give an editor window its own settings](editor-settings.md#give-an-editor-window-its-own-settings).
- In a database window, choose **Settings** (gear) in its toolbar, then **This Window**, which has **Opacity** and **Glass**; see [Give a database window its own settings](database-workspace.md#give-a-database-window-its-own-settings).

Each follows **Appearance** until you change it there, and only that window changes. A setting the window has changed shows a small ↺ beside its name, which returns it to **Appearance**. Whatever a window hasn't set follows **Appearance**.

> [!NOTE]
> When **Reduce Transparency** is on in the system's Accessibility settings, every window is opaque, and these controls are unavailable until you turn it off.

## General

Under **Library**, **Show service availability** (off by default) puts a dot beside each service in the library: green when it answers, orange when it answers slowly, red when it does not. While the library is on screen, this device opens a connection to each service's port about once a minute and closes it at once; it never signs in. A database reached through its machine's SSH connection, and this Mac's own terminal, have no dot. A service you're connected to always shows a green dot, with this setting on or off.

**General** also shows the state of your host library on this device under **Host Library**: how many **Hosts** it has and whether **This device** is kept on this device only. If the file that holds favorites and recent hosts cannot be read, an orange message here explains why, and favorites and **Recent** cannot be changed until it can.

## Privacy

**Credentials** shows where passwords and keys are kept and their **Default mobility**. With **iCloud Keychain**, a credential you save is available on your other devices. Nothing on this page shows or reads a secret.

**On your other devices** shows the **Host library** sync status and explains which secrets travel with you. See "Your library on all your devices".

## About

**About** shows the app's version, a **Sponsor** link and **Acknowledgements**.

Choose **Acknowledgements** to see every third-party component in the app, grouped by what it is used for. Search by name or licence, and choose a component to read its licence text and see where its source is published. Choose **Done** to close the list.
