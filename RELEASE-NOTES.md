# Release notes

Glass Power Tools has not had a public release yet. These notes say what the first release holds and
what changed in the builds leading up to it, and are kept current as the work lands. Builds before
the release are numbered 0.4.*n* and run on the maintainer's own Mac, iPhone and Vision Pro; there is
no download or TestFlight build yet. What is verified, and how, is in
[memory-bank/progress.md](memory-bank/progress.md).

## The first release (not yet released)

### One library of machines
- Every machine you work on, once, with its services — Terminal, Database, Desktop — and Connect
  choosing among them. Favorites (machines, services, projects, workgroups and folders), collections,
  tags, other names, search, and an overview of what is reachable.
- Active lists what is open and what is still running on your machines, on every device; Show All
  Windows lays out every window and tab as cards, grouped by machine, with live pictures.
- The library, favorites, workgroups and projects sync through iCloud; credentials and trusted host
  keys through iCloud Keychain. Keys made in the Secure Enclave stay on their device.

### Terminal
- SSH with host-key pinning, password and key sign-in (including Secure Enclave keys), jump hosts,
  port forwarding (local, remote, SOCKS5) and an SFTP file browser. A local shell on the Mac.
- Terminals kept in tmux, on servers and on the Mac, so they outlive the app and the device: pick a
  session up from Active on another device, or add it to a window as a tab. Basic terminals outside
  tmux when you want one.
- Windows with tabs and splits, named by what runs in them (repository and branch included), themes,
  workgroups, a window's own look and settings, find, paste review, snippets and recording. Windows
  and their tabs come back after a relaunch on every device.
- Terminals that scale as well as resize: Scale Text keeps the rows and columns and scales the text,
  and ⌘+, ⌘− and ⌘0 size the window (on the Mac, SSH terminals; not yet the local shell).
- On the Mac, a file whose path a terminal prints previews over the terminal; files dropped on a
  terminal have their paths typed, and on a server they are uploaded first. AI coding agents are
  recognised on tabs and cards.

### Databases
- MySQL, PostgreSQL and SQLite: browse, filter and edit rows with a review before every write,
  follow foreign keys, change structure, export, and see a live diagram of every table and key — in
  three dimensions on Vision Pro.
- Write and explain queries, keep query history with literals redacted, and ask the on-device
  assistant for SQL and fixes.
- Reach a database directly with TLS, through its machine's SSH connection, or through another
  machine; or mark it read-only.

### Remote desktops
- RDP and VNC, including Apple's own Screen Sharing protocol, which is encrypted after you sign in
  to a Mac with a Mac account.
- The remote resolution follows the window; a window per remote display; Quality you can set, or
  Automatic, which follows the link's lateness; audio; a shared clipboard both ways, with formatting
  and images; see-through glass on the Mac and Vision Pro.

### Editor
- Files on this device or on a server, projects with a file tree, syntax highlighting, and previews
  for Markdown (with Mermaid diagrams), HTML, SVG and CSV. Images, PDFs, video, audio and 3D models
  open as themselves. On the Mac it can be your default text editor.

### Across the system
- Widgets (Machines, Machine, Active), Siri and Shortcuts, Spotlight, Controls, Handoff and
  `ssh://` links. On the Mac: the Finder's Services, toolbar button and Quick Action, Share ▸ Send to
  a Machine, Open With and the Dock menu.
- Light, Dark or System for the whole app on the Mac, iPhone and iPad; window opacity and glass
  everywhere; and on Vision Pro, session windows that shrink into an orb.

### Known limits
- The Mac app runs outside App Sandbox (a terminal cannot work inside it), so it will be distributed
  directly, signed and notarized, not through the Mac App Store. See [SECURITY.md](SECURITY.md).
- VNC without a Mac account is not encrypted after sign-in.
- A file on a server larger than 64 MB can't be opened in the Editor.
- What has not been verified on a device or against a real server is listed under "Not verified" and
  "Known and open" in [progress.md](memory-bank/progress.md).

## Recent builds

### 0.4.473 (17 October 2026)
- **All Windows in light mode on iPhone and iPad:** a terminal's card is drawn on its theme's own
  canvas, as its window is, with its name and close button in the theme's light or dark — a dark
  theme's picture was green text on the white sheet.

### 0.4.472 (17 October 2026)
- **A machine you delete, or a service you remove, stays that way on your other devices.** Before,
  deleting a machine whose service was set up never reached your other devices, and a device that
  did hear of it sent the machine back; a removed service came back the same way.
- **Unsaved changes in the Editor are never lost without asking.** On the Mac, closing a window asks
  about each changed document, and quitting asks first and can take you to them. On iPad and
  Vision Pro, a window closed with changes keeps them in Active. Closing an editor session from
  Active or Show All Windows asks first, everywhere.

### 0.4.455 – 0.4.471 (15 – 17 October 2026)
- **Terminals scale as well as resize** (Vision Pro, iPad, and SSH terminals on the Mac; not the Mac's
  local shell yet, nor iPhone): Scale Text in a terminal window's
  bar, or the "When a window is resized" setting, keeps the rows and columns and scales the text;
  the window keeps the grid's shape; under Scale, ⌘+, ⌘− and ⌘0 size the window (on iPad, ⌘+ grows
  it and ⌘− can't shrink it).
- **File previews over a Mac terminal:** a path a terminal printed shows its file in a popover — on
  right-click ▸ Quick Look, or as the pointer rests on it, or on Space (Show previews: Never,
  Mouseover, Mouseover + Space). The kind is read from the file's bytes, code is highlighted, and
  Open in Editor opens it. Files on a server are fetched for the preview and removed after.
- **A Mac terminal window's sidebar adds to the window:** opening it grows the window and closing it
  shrinks it, and the terminal keeps its size and place. No line at the sidebar's edge, and the
  toolbar no longer flashes see-through as the sidebar opens.
- **3D models** (USDZ, USD, Reality) open wherever files do: the editor, Files, previews and links a
  terminal prints — RealityKit on the Mac, AR Quick Look on iPhone and iPad, Quick Look's volume on
  Vision Pro.
- A file dropped on a terminal has its path typed, or the app says why not (a paste review left
  waiting used to turn later drops away silently).
- **Vision Pro terminal:** selection works as Apple's text does — hold to select a word, drag its
  ends, click-drag with a trackpad — and a pinch-drag scrolls when tmux has its mouse on (tmux 3.8's
  default).
- **iPhone:** the tab switcher in the terminal's own light or dark; All Windows lists every tab of an
  open window, waiting ones too; a remote desktop shows one bar of controls at a time, and its title
  is readable in light mode.

### 0.4.392 – 0.4.454 (13 – 15 October 2026)
- **Show All Windows** on every device: every kind of window, a card per tab grouped by machine, live
  pictures. On iPhone and iPad pull down or hold ⚡; on Vision Pro it is a window of its own; Siri:
  "Show all windows".
- **The system's ways in:** Siri and Shortcuts, Spotlight, Controls, Handoff, `ssh://` links; on the
  Mac, the Finder's Services, toolbar button and Quick Action, Share ▸ Send to a Machine, Open With
  and the Dock menu.
- Favorites hold machines, services, projects, workgroups and folders.
- **Vision Pro:** session windows shrink into an orb with a live picture and the window's tabs on a
  ring; one Tabs/Grid/Carousel toggle; Auto-focus on activity; selection, and a held link's or
  path's actions.
- One Command Palette, listing services, terminal commands, projects, folders, saved queries and
  running tmux sessions; a link and path menu in the terminal; 28 AI coding agents recognised.
- Active: Open as Tab In for a running session, and the "+" of a terminal window lists running
  terminals.
- Terminal windows: SSH panes, Reconnect, a close box per tab.
- The app's own Light, Dark or System (Mac, iPhone, iPad).
- Remote desktops: the clipboard both ways with GNOME, Sync Automatically, a Graphics choice per
  Desktop service; on a phone a session opens in place, and an iPad's desktop window has a working
  Close.
- Editor: a new file's first save into a project on a server; ⌘S off the Mac asks where a new
  document goes. Database connection errors in plain words.
- Fixed: every terminal on a lost shared SSH connection says so; a Quick Look crash.

### Earlier in October (to 0.4.391)
- **tmux:** terminals on a server kept in tmux sessions, reattached, and listed in Active on every
  device; the Mac's local terminals kept in tmux under launchd, so they survive quitting the app,
  installing an update, or force-quitting an app started in one of them; Basic terminals outside tmux
  (⌃⌘T).
- Mac tabs named by what runs in them, renamed, dragged between windows; files and photos dropped on
  a remote terminal uploaded and their paths typed; find in tmux; windows and tab groups reopened with
  their places on every device.
- A window owns its look (tint, opacity, glass), and any setting can be overridden for one window.
  On Vision Pro, windows draw Apple's glass at their Glass setting, completely clear at 0.
- Favorites and workgroups sync across devices.
- A database reached through another machine's SSH connection.
- **Remote desktops:** Apple's Screen Sharing protocol, encrypted after a Mac-account sign-in; a
  window per remote display; Quality and an Automatic that follows lateness; Retina displays at 1x;
  windows held to their display's shape; the Keys menu, arrow pad and iPhone keyboard bar; trackpad
  scrolling on iPad and Vision Pro; RDP's bandwidth measurement answered. High Performance mode, from
  a Mac, is behind a switch and not yet verified against one.
- Widgets: Machines, Machine and Active.
- **Security:** a critical swift-nio-ssh flaw fixed (CVE-2026-43798: an oversized signature in a
  server's key-exchange reply could write past a buffer before the host key was checked). SwiftTerm
  1.20.
- Editor: Wrap Long Lines off on iPhone, iPad and Vision Pro; projects on a server reconnect when
  their connection drops.
