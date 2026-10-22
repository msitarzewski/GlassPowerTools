# Release notes

The Mac app's first release was 0.4.491, and the latest is 0.4.494 (both 20 October 2026): a download from
[glasspowertools.com](https://glasspowertools.com), signed with a Developer ID, notarized by Apple, and
updated through Sparkle. iPhone, iPad and Vision Pro builds go to TestFlight for internal testing; their
first App Store release will be 1.0, and the Mac will be 1.0 then too. Builds are numbered 0.4.*n* until
then. These notes say what the app holds and what changed in each build, and are kept current as the
work lands. What is verified, and how, is in [memory-bank/progress.md](memory-bank/progress.md).

## What it holds (0.4.494)

### One library of machines
- Every machine you work on, once, with its services — Terminal, Database, Desktop — and Connect
  choosing among them. Favorites (machines, services, projects, workgroups and folders), collections,
  tags, other names, search, and an overview of what is reachable.
- Your Library shows the time you spend on each machine: every minute with typing or output counts,
  per machine and kind of service, added up across your devices, with the connections you made beside
  it.
- On a Mac, the library's record of that same Mac is recognised (by its SSH host key, or you say so):
  its Terminal opens a local shell, its databases are the Mac's own, and its sessions are listed once.
- Active lists what is open and what is still running on your machines, on every device; Show All
  Windows lays out every window and tab as cards, grouped by machine, with live pictures.
- The library, favorites, workgroups and projects sync through iCloud; credentials and trusted host
  keys through iCloud Keychain. Keys made in the Secure Enclave stay on their device.

### Terminal
- SSH with host-key pinning, password and key sign-in (including Secure Enclave keys), jump hosts,
  port forwarding (local, remote, SOCKS5) and an SFTP file browser. A local shell on the Mac.
- Terminals kept in tmux, on servers and on the Mac, so they outlive the app and the device: pick a
  session up from Active on another device, or add it to a window as a tab. Basic terminals outside
  tmux when you want one. With tmux 3.2 or later the terminal keeps every line itself: its whole
  history, a drag that selects through a scroll, and the mouse for full-screen programs.
- Looks for a terminal window: a picture behind the text, Digital Rain that quickens while the
  terminal prints, a Synthwave horizon or a phosphor screen; green or amber phosphor text, a glow, and
  Vaporwave's colours, on the Mac, iPad and Vision Pro. Readability keeps the text legible over any
  of them.
- On the Mac, right-click SQL a terminal printed and open it in the query editor on that machine's
  database, not yet run, with the table it names opened beside it.
- A terminal's folder button opens the shell's folder in the Finder (or Files, on another machine) or
  in the Editor: the project that holds it, or a new window.
- Windows with tabs and splits, named by what runs in them (repository and branch included), themes,
  workgroups, a window's own look and settings, find, paste review, snippets and recording. Windows
  and their tabs come back after a relaunch on every device.
- Terminals that scale as well as resize: Scale Text keeps the rows and columns and scales the text,
  and ⌘+, ⌘− and ⌘0 size the window. Text up to
  28 points; on iPhone, iPad and Vision Pro it can follow the system's text size.
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

### Next (not yet released)
- **Four more terminal looks.** **Coding Agent** shows the agent each terminal is running, Claude
  Code, Codex, Gemini CLI or another, behind its text in the agent's own colour: a smoke drifts and
  the mark breathes while the agent works; when it stops and waits for you, the mark holds still and
  glows. **Aurora** and **Starfield** move faster while the terminal prints (the stars streak into
  warp); **Blueprint** is a still drafting grid with white-blue text. A glow can take the agent's
  colour too.
- **A Workgroup's look.** Creating or editing a Workgroup now offers Look and Text, as a window's
  own settings do, so every window it opens starts with that look, on every device, iPhone included.
  Before, a Workgroup had a look only when saved from a Mac window that had one.
- **Settings in Tools on iPhone and iPad.** A terminal's Tools menu has Settings as a row of its own;
  it was the last row of the Session menu inside it. Open Folder Here, Connections and New Terminal
  Tab say what they are there; they were bare symbols.
- **Open Folder in Editor from an iPhone terminal** opens the editor over the terminal, and its back
  button returns to the terminal. Before, it did nothing.
- **Join Wrapped Lines leaves code alone.** Lines indented deeper than the text around them, and a
  Mermaid diagram's lines, keep their breaks: a diagram copied from Claude came back with two of its
  statements on one line, because the widest of them looked as if it reached the margin.
- **Mermaid diagrams in terminals.** A diagram a program prints as text, as Claude Code does when it
  can't draw one, gets a button after its first line that shows it drawn over the terminal, on the
  Mac, iPad, iPhone and Vision Pro.
- **A sidebar for Vision Pro's terminal windows.** From the second terminal on, a window lists its
  terminals in a sidebar, as a Mac window does, and widens for it: each row with its name and where
  it is. Pinch and hold a row for its menu, or drag it onto another window, onto another row, or into
  empty space for a window of its own; a terminal's name at the top drags the same way. Apple's tab
  bar, which held the tabs before, showed only identical symbols until looked at.
- **Vision Pro's terminal bar, tidied.** **Sidebar** shows and hides a window's sidebar; a pinch on
  **Terminal View** shrinks the window to its orb (held, it lists the layouts); Font Size and the AI
  Assistant are in the tools menu. The orb's ring has larger dots, each showing its terminal's agent.
- **Tabs show their coding agent.** On the Mac and Vision Pro, a tab's symbol is the agent running
  in it, in the agent's colour, pulsing while it works; it replaces the wave under a busy Mac tab.
- **A picture's Blur works along the whole slider.** It blurred the picture away within the first tenth
  and changed nothing after; now it softens gradually, to the same full blur at Soft.
- **New terminals from the Mac sidebar.** Right-click the sidebar's empty space for the toolbar's +
  menu: New Terminal, New Basic Terminal, running terminals, and New Terminal on a host.
- **iPhone Duo, half open.** Stood up like a small laptop, the terminal takes the top half and its
  bar sits below the fold, above the keyboard's keys: the keyboard button, Tools with the cursor pad,
  and Keys. Before, the bar sat above the fold and took rows from the terminal. Held like a book,
  the controls keep off the fold.
- **Keys on Vision Pro.** A terminal's bar has a Keys menu: Escape, Tab, Control for the next key,
  the arrows and F1–F12, for when no keyboard is paired. The headset shows apps no keyboard
  accessory, which is where iPhone and iPad keep these.

### 0.4.492 – 0.4.494 (20 October 2026)
- **0.4.494 is the Mac's second release**, through Sparkle, and TestFlight build 494.
- **Scale Text on the Mac's own terminals**, tmux tabs included. A local tab ignored Scale Text: the
  view that draws it never had the part that keeps the rows and columns. Now the bar's Scale Text and
  ⌘+, ⌘− and ⌘0 work there as on a terminal on another machine.
- **Open Folder in Editor** in a Mac terminal's tools menu, the Mac's own terminals included (before,
  only on other machines'). It opens the project on that machine whose folder is the shell's, or holds
  it; otherwise the folder, in a new Editor window on this Mac or as a project on another machine.
  Vision Pro's pinch and hold on the folder button does the same.
- **A local terminal's tools menu no longer repeats the toolbar**: Connections, AI Assistant, Open
  Folder Here, Focus Mode and Scale Text are the buttons beside it.
- **Not signed in to iCloud says so.** A Mac without an Apple Account showed "iCloud sync failed" and
  CloudKit's own words; the library now says iCloud is unavailable and to sign in.

### 0.4.481 – 0.4.491 (19 – 20 October 2026)
- **0.4.491 is the first Mac release.** The same build went to TestFlight for iPhone, iPad and
  Vision Pro.
- **Your Library counts time in use.** It counted one connection per Connect, however long the
  session stayed open, so days of work in tmux showed as one. Now each minute with typing or output
  counts for its machine and kind of service, a Mac's local terminals included. The overview opens on
  Time in Use (hours per day, and the machines you use most by time), with Connections beside it.
  Minutes are counted from 0.4.490.
- **A Mac knows its own record in the library.** When a machine in the library is this Mac (its SSH
  host key is the Mac's own, or you say so in its editor), its Terminal opens a local shell instead of
  SSH to itself, its databases are the Mac's, Active lists its sessions once, and Screen Sharing to
  itself isn't offered.
- **Terminal looks** (Mac, iPad and Vision Pro; looked at on the Mac so far): backgrounds (a picture, which can be blurred, pixelated and toned to the theme;
  Digital Rain; Synthwave; a Phosphor Screen), text palettes (green, amber and digital-green phosphor,
  Vaporwave), a glow, and Start From looks that set them together. A picture's bright patches are
  held down so text stays legible, and motion stops under Reduce Motion, in Low Power Mode and in the
  background.
- **SQL from a terminal (Mac):** right-click a statement a terminal printed ▸ Open in SQL Editor, a
  menu when the machine has several databases. The SQL opens unrun in a new query tab, and the table
  it names is found and opened.
- **tmux tabs keep every line.** A terminal kept in tmux attaches as tmux's control-mode client, as
  iTerm2 does: the terminal keeps its own complete history, a drag selects through a scroll, and
  full-screen programs get the mouse. tmux older than 3.2 attaches as before. Reattaching a tab with
  a long history is quick (2,000 lines took 15 seconds before).
- **A new tmux tab's cursor sits on its prompt.** It was one row above it in a terminal taller than
  tmux's pane. A resize while the tab opens, and a change of font size, now reach tmux.
- Mac tab rows name each terminal's tmux session, machine, program and folder in a tooltip.
- **The largest text sizes:** the terminal's font goes to 28 points, and on iPhone, iPad and Vision Pro
  grid and terminal text follow the system's text size (a switch for each, on by default). The iPad editor's file list is wider at
  accessibility sizes.
- **A paste of text a program wrapped is joined again:** Join Wrapped Lines in the paste review,
  remembered; a paste that joins to one line skips the review.
- The Mac's Terminal Overview no longer lists a window's own terminals as open elsewhere.

### 0.4.480 (18 October 2026)
- **On iPad, opening a database no longer stops the app.** The database's window, which an iPad
  opens on its own, required something only the library's window has. Found while making the App
  Store's pictures. iPhone, Mac and Vision Pro were not affected.
- **The app has a privacy manifest**, which Apple requires: it collects nothing and tracks no one, and
  it gives Apple's reason for each API it uses from Apple's list (settings, file dates, free space,
  and the time since the device started).

### 0.4.479 (18 October 2026)
- **About is the last page of Settings**, after Editor, on every device. It sat between Privacy and
  the services' pages.
- **Command Palette… is listed once on the Mac, on ⇧⌘P.** The app menu also listed it as "Command
  Palette (Alternate)…" for ⌘K, which no longer opens it.

### 0.4.478 (18 October 2026)
- **Glass Power Tools is licensed under the GNU GPL, version 3**, chosen before its first publication.
  Settings ▸ About says so. Contributions come with a contributor agreement (`CLA.md`).

### 0.4.477 (18 October 2026)
- **The library of machines moved to iCloud's production database**, the one released copies use.
  Until now builds from Xcode used CloudKit's development database, which a released copy never sees.
  The first device on this build uploads its library, and the others take it from there. Favorites,
  workgroups, projects, settings and passwords were never in that database, so they are unchanged.
- The Mac build carries its update key (Sparkle), so Check for Updates… appears. The update feed is
  empty until the first release.

### 0.4.476 (18 October 2026)
- **A crash in database windows on the Mac, fixed.** A database or diagram window re-applied its
  window settings on every update, and that could reach the window's content while it was being
  taken down, which crashed the app. It now changes only what differs. Found while taking the
  website's pictures.

### 0.4.475 (17 October 2026)
- **No gray line in database and desktop windows**, as in terminal windows since 0.4.469: a database
  window's sidebar meets its workspace with no line between, and a desktop window has no line down its
  left edge.

### 0.4.474 (17 October 2026)
- **Your Library counts connections on all your devices.** The overview's chart and Most used add up
  every device's connections, with a menu to show one device by its name. Each device shares how
  many connections it made each day, per machine and kind of service, through iCloud; its history
  stays on it. Name a device in Settings ▸ General ▸ This Device (iPhone, iPad and Vision Pro
  otherwise go by their kind).

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
