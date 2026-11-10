# Release notes

The Mac app's first release was 0.4.491 (20 October 2026), and the latest is 0.4.612 (9 November 2026): a download from
[glasspowertools.com](https://glasspowertools.com), signed with a Developer ID, notarized by Apple, and
updated through Sparkle. iPhone, iPad and Vision Pro builds go to a TestFlight beta by invitation; their
first App Store release will be 1.0, and the Mac will be 1.0 then too. Builds are numbered 0.4.*n* until
then. These notes say what the app holds and what changed in each build, and are kept current as the
work lands. What is verified, and how, is in [memory-bank/progress.md](memory-bank/progress.md).

## What it holds (0.4.612)

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
- Suggestions as you type at a shell prompt: grey text on the Mac, a row of choices above the keyboard on
  iPhone and iPad and under the window on Vision Pro. They come from the commands you've run on that machine,
  your snippets and library, the folder you're in (paths complete as you type them), common tools and the
  machine's programs. What you run is kept on the device, never synced, never what looks like a password.
- Terminals that scale as well as resize: Scale Text keeps the rows and columns and scales the text,
  and ⌘+, ⌘− and ⌘0 size the window. Text up to
  28 points; on iPhone, iPad and Vision Pro it can follow the system's text size.
- On the Mac and Vision Pro, a file whose path a terminal prints previews over the terminal, a log's
  end included, and Watch Log File follows a log in a new tab; files dropped on a terminal have their
  paths typed, and on a server they are uploaded first. AI coding agents are
  recognised on tabs and cards.
- A workgroup's terminals on a Mac belong to that Mac: every other device, another Mac too, opens
  them there over SSH, on their own tmux sessions. A workgroup can open databases and remote desktops
  from the library too, with its terminals or on their own.
- Color schemes from macOS Terminal profiles, any number, kept in iCloud Drive for every device and
  chosen with a preview of each, for every terminal or one window.
- On Vision Pro, Focus Mode surrounds you with a built-in environment or your own 3D room or 360°
  photo, which you can walk about in, with a room's own motion, clocks and sounds.
- A terminal that rings its bell while you're not looking stays marked in orange until you go to it.

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
  open as themselves. On the Mac it can be your default text editor. Undo and redo, Find and Replace,
  Transformations and the spelling switches TextEdit has, with the same keys on iPad, iPhone and Vision Pro.
- Git, on this Mac or on a server over the project's SSH connection: Source Control with a diff
  viewer (unified or side by side, changed words highlighted, 3 or 10 lines of context or the whole
  file, whitespace ignored), staging a file, a hunk or chosen lines, discarding, commit and amend,
  pull, push and fetch, the history with its graph, branches, stashes and tags, merges, rebases,
  cherry-picks, reverts and resets, a conflict resolver, Blame and a file's history, Clone, and change
  marks beside the lines.

### Across the system
- Widgets (Machines, Machine, Active), Siri and Shortcuts, Spotlight, Controls, Handoff and
  `ssh://` links. On the Mac: the Finder's Services, toolbar button and Quick Actions, Share ▸ Send to
  a Machine, Open With and the Dock menu.
- Light, Dark or System for the whole app on the Mac, iPhone and iPad; window opacity and glass
  everywhere; and session windows that shrink into an orb: on the Mac into a dock of Liquid Glass, and on
  Vision Pro where they stand or into one dock. The dock is a row or a column, as long as you make it; its
  orbs are drops of liquid that wobble as windows land and leave, with drops falling into a busy one.

### Known limits
- The Mac app runs outside App Sandbox (a terminal cannot work inside it), so it will be distributed
  directly, signed and notarized, not through the Mac App Store. See [SECURITY.md](SECURITY.md).
- VNC without a Mac account is not encrypted after sign-in.
- A file on a server larger than 64 MB can't be opened in the Editor.
- What has not been verified on a device or against a real server is listed under "Not verified" and
  "Known and open" in [progress.md](memory-bank/progress.md).

## Recent builds

### 0.4.613 (10 November 2026)
- **A terminal that loses its connection says so in the window.** Only the red line under its tab's name said so,
  and the terminal still looked connected. Now its text dims and a panel in the middle says **Connection Lost**
  and why (**Couldn't Connect** for one that never connected), with **Reconnect** and **Close Terminal**. While
  auto-reconnect works it shows each try, up to five, and **Cancel Reconnect**. The dimmed text stays there to
  read, scroll and copy. On the Mac and iPhone the panel takes the terminal theme's light or dark; on Vision Pro
  it is the system's glass.
- **Close Terminal closes a disconnected terminal on the Mac.** From the tools menu it disconnected instead, and
  the pane stayed, saying the session had ended. It now closes the pane, and the tab with its last.

### 0.4.612 (9 November 2026)
- **0.4.612 is the Mac's eighth release**, through Sparkle, with everything since 0.4.603 below; TestFlight build
  612 for iPhone, iPad and Vision Pro.
- **Every SSH terminal has its folder button.** Open Folder Here showed only on terminals kept in tmux: it
  took the folder a shell reports in a form no shell uses, and bash on most Linux servers reports none at all. It
  is there on every SSH terminal now, and opens the folder the shell reports, or else the one its prompt names in
  the title (as Ubuntu's, Debian's, Fedora's and Arch's do), even while a program such as Codex has the title.
  A shell that names no folder opens Files at home.

### 0.4.611 (8 November 2026)
- **Scrolling a busy terminal stays where you leave it, on iPhone, iPad and Vision Pro.** In a terminal printing all
  the time, such as one with a coding agent at work, a flick's coast was undone by the next output: the view jumped
  back to where your finger or hand let go, so the latest lines were out of reach unless you dragged the whole way.

### 0.4.610 (8 November 2026)
- **A paste is text, never keys.** Control characters are left out of everything you paste or drop into a
  terminal, as xterm does: only tab, newline and return go through. Text copied from a web page could hide the
  sequence that ends a paste, and whatever followed it then ran as if typed; a hidden Ctrl-O in a single line
  could run it in bash without the paste review.
- **Closed terminals free their memory on iPhone, iPad and Vision Pro.** Each terminal you closed had kept its
  screen and its whole scrollback until the app quit.
- **Dropped files with unusual names.** A file whose name holds an invisible formatting character, such as a
  right-to-left mark, is typed so the shell reads back its real name.

### 0.4.609 (7 November 2026)
- **Typed paths complete.** `cd ~/Software/gl` offers the folders in `~/Software` that start with `gl` as you type,
  and so do full paths (`/usr/lo…`) and paths from the folder you're in (`src/li…`). After `cd` only folders are
  offered, each with its slash, so the next level follows at once; other commands are offered files too. In a
  terminal on a server the names come over its SFTP connection. A hidden name waits until its dot is typed, as in
  zsh, so `cd ` no longer offers `.git/` first.

### 0.4.608 (7 November 2026)
- **Suggestions in a Mac tab in tmux.** A local tab in tmux offers suggestions as a tab outside tmux does: the shell
  integration reaches a new tmux session (tmux 3.2 or later), and the app tells the shell's own prompt from a program
  running in the pane, so nothing is offered over that program's input.
- **The programs on the machine.** A command's first word, and the word after `|`, `;`, `&&`, `sudo` and the like, is
  completed from the programs in the machine's usual program folders and the shell's own commands. A tool the app
  knows comes before the rest, and a command you've run comes before both. **Settings** ▸ **Suggestions** ▸
  **Programs on the machine** turns it off.

### 0.4.607 (6 November 2026)
- **Type-ahead in terminals.** At a shell prompt the terminal offers the rest of the command: grey text after the
  cursor on the Mac (→ at the end of the line takes it all, ⌥→ one word); up to three chips above the keyboard bar on
  iPhone and iPad, and in an ornament on Vision Pro, a tap typing the rest. Suggestions come from what you've run on
  that machine, your snippets, the folder you're in (branches, package scripts, make and just targets, file names) and
  common tools' commands and options. Nothing is offered in a full-screen program such as vim or less, at a password
  prompt, or when the line can't be read with confidence, and a command carrying a password or token is never kept.
  **Settings** ▸ **Suggestions** turns each source on or off, forgets a machine's history, imports a server's shell
  history, and installs or removes the shell integration on your machines. When zsh-autosuggestions or fish draws
  its own grey text, the app's stands aside. The chips were checked in the iPhone and Vision Pro simulators.
- **Resizing a tab in tmux no longer fills it with copies of the prompt.** zsh redraws its prompt by clearing the
  screen, and tmux kept each cleared screen in the history, where a growing window brought the copies back down.
- **Scale Text works in a Mac tab in tmux.** It did nothing there.
- **⌘V pastes a picture into a Mac terminal**, as dropping it does: a screenshot or a copied image is saved to the
  drop folder (on the server, for an SSH terminal) and its path typed. It pasted nothing. Text copied beside a
  picture still pastes as text.

### 0.4.605 and 0.4.606 (5 November 2026)
- **Vision Pro draws terminals with Metal, sharp at the headset's scale.** SwiftTerm drew at one pixel a point on
  visionOS. The app now carries its own copy of SwiftTerm 1.20.0 with that fixed (each change listed in
  `Packages/SwiftTerm/PATCHES.md`), and Metal drawing is the default on Vision Pro. Checked in the Vision Pro
  simulator.

### 0.4.604 (5 November 2026)
- **A machine is the name you gave it.** Two machines at one address, such as two sites on one server, stay two
  machines. They were folded into one on every device, the newer one's terminals and files moved onto the other and
  the newer one deleted.

### 0.4.603 (5 November 2026)
- **0.4.603 is the Mac's seventh release**, through Sparkle, with everything since 0.4.589 below; TestFlight build
  603 for iPhone, iPad and Vision Pro.
- **The dock keeps the length you give it**, on Vision Pro and the Mac. It scrolled past a longest of its own (about
  six orbs in a row on Vision Pro, seven on the Mac), and a hand's resize sprang back. Now resize it longer to show one
  more orb, or shorter to show fewer: when you let go it keeps that length as its longest, to the nearest whole orb,
  and goes back to one orb thick. It still fits its orbs within it, shorter with fewer, scrolling past it with more. A
  row and a column each keep their own.
- **On Vision Pro, Settings ▸ Terminal ▸ On-Screen Keyboard**: **Automatic**, as before, or **Only When Asked**, where
  the system keyboard no longer comes up under a terminal you pinch, connected keyboard or not, until **Keys** >
  **Show Keyboard**; **Hide Keyboard** puts it away. The headset hadn't reported a connected keyboard, so the whole
  keyboard came up under every terminal.

### 0.4.602 (5 November 2026, Vision Pro)
- **The orbs' glass is whole again on Vision Pro.** In 0.4.601 each orb's glass took the drop's shape, and on the
  headset it broke into white shards after a scroll of the dock, on every orb, in a row or a column. The glass is the
  system's own circle again; the whole orb squashes and stretches as it lands and as the wave passes, and the ripples
  stay in its picture. The Mac, where the glass held, keeps the drop's shape.

### 0.4.601 (5 November 2026)
- **The orbs are drops of liquid**, on Vision Pro and the Mac. A window landing in the dock squashes as it lands and
  wobbles like jelly until it settles, and the orbs beside it feel it in turn, a wave of wobble along the row or
  column that is smaller in each orb further on; one leaving does the same as the gap closes. The others slide over
  with a spring. On the Mac the dock's glass stretches a little past its new size and springs back. The wobble is a
  drop's own: an oval, three lobes, four, each ringing faster and dying sooner than the last, the drop keeping its
  size. On the Mac, Apple's glass takes the drop's shape, so it goes on bending what lies behind it as it wobbles.
- **A busy orb has drops falling into it** where its window asks for activity to show: rings of ripples spread across
  its picture, bending it as water does, with light catching the rings; on the Mac the rim trembles as each reaches it.
  This replaces the white ring that went out from the orb. Drawn by a Metal shader, and only while something moves.
  With **Reduce Motion** or **Low Power Mode** on, the orbs stay round and a busy orb's rim glows instead.

### 0.4.600 (5 November 2026)
- **The orb dock is a row or a column**, on Vision Pro and the Mac: **Settings** ▸ **Appearance** ▸ **Orbs** ▸
  **Dock**, **Horizontal** or **Vertical**. It grows and shrinks along it as windows come and go, and scrolls past
  about six orbs in a row (seven on the Mac) or four in a column (the screen's height on the Mac), with arrows at the
  ends. A window brought back from the dock and docked again goes back into the same row; it could land on a new one,
  as the dock kept a size it had been given and wrapped its orbs into it. Resized by hand, the dock goes back to
  fitting its orbs; **Fit Dock to Its Orbs** is gone. A vertical dock sends windows back beside it, as a tall one did.
- **Focus Mode is the app's on Vision Pro.** It stays open as windows go into the dock and come back (it closed as a
  terminal's view went away), and it closes by itself once the last terminal closes. Its environment is one for the
  app: the moon's menu sets **Settings** ▸ **Terminal** ▸ **Focus Mode**'s, and **This Window** no longer has its own.

### 0.4.599 (5 November 2026)
- **No mini keyboard on Vision Pro while a keyboard is connected.** With a Magic Keyboard (or any) connected, a
  terminal or a remote desktop takes your typing without visionOS's small on-screen keyboard floating by the window.
  For dictation or emoji, **Keys** > **Show Keyboard** in a terminal brings it back until **Hide Keyboard**; in a
  remote desktop, **Keys** > **Type Text…**. With no keyboard connected, the on-screen keyboard comes up as before.
  Seen in the Vision Pro simulator; typing with a Magic Keyboard is still to be tried on the headset.

### 0.4.598 (5 November 2026)
- **Files on Vision Pro keeps your size.** A Files window opens at the size you last left one at, on that Vision Pro;
  until you resize one, at 960 points wide (1,100 was a little too wide), still enough for every column and the names.
- **The moon offers Fine Position whenever Focus Mode is open.** Focus Mode is one for the app, but each terminal in
  a window kept its own note of whether it had opened it: on another terminal of the window, or another window, the
  moon read closed, its menu had no **Fine Position…**, and a pinch tried to open Focus Mode again. Every moon now
  follows Focus Mode itself: filled while it is open, **Fine Position…** in its menu, a pinch closes it.

### 0.4.597 (5 November 2026)
- **Files on Vision Pro shows the names.** The window opens wider (1,100 points instead of 700), where every file's
  name, size, date and permissions fit beside its buttons; at 700 the names were cut to "…". Made narrower, a row gives
  way to keep the name readable: **Permissions** goes first, then **Edit**, **Get Info** and **Download** fold into
  one ⋯ menu, then the date. Long names are shortened in the middle, keeping the extension. Folders' sizes and dates
  now line up with the files'. Checked in the Vision Pro simulator at both widths.

### 0.4.596 (3 November 2026)
- **The Editor with a keyboard on iPad, iPhone and Vision Pro:** **Find and Replace…** (⌥⌘F), **Find Next** (⌘G),
  **Find Previous** (⇧⌘G), **Use Selection for Find** (⌘E), **Jump to Selection** (⌘J), **Go to Line** (⌥⌘L) and the
  text size keys (⌘+, ⌘−, ⌘0), as the Mac's menus have them. Checked with key presses on the iPad simulator; on
  Vision Pro ⌘Z and ⇧⌘Z were checked the same way, and the other keys are still to be tried on the headset.
- **Transformations off the Mac:** select text and open its menu for **Make Upper Case**, **Make Lower Case** and
  **Capitalize**, each undone on its own (**Undo Change Case**); on the Mac, Edit ▸ Transformations now undoes the same.
- **Settings ▸ Editor ▸ Spelling and Substitutions**, on every device: check spelling while typing, correct
  automatically, smart quotes, smart dashes, smart copy/paste (and on the Mac grammar, links, data detectors and text
  replacement). Off until turned on; never in a database's SQL editor.

### 0.4.595 (3 November 2026)
- **The Editor's Edit menu on the Mac is TextEdit's.** Edit ▸ Find adds **Find and Replace…** (⌥⌘F), **Use
  Selection for Find** (⌘E) and **Jump to Selection** (⌘J), and the menu adds **Paste and Match Style** (⌥⇧⌘V),
  **Spelling and Grammar**, **Substitutions**, **Transformations** (Make Upper Case, Make Lower Case, Capitalize) and
  **Speech**. Spelling and substitutions stay off until you turn them on, apply to every Editor window, and never to
  a database's SQL editor.
- **Replace in the find bar** replaces the selected match and moves to the next, beside **All**; each undoes on its own
  (**Undo Replace**).

### 0.4.594 (3 November 2026)
- **Undo and redo in the Editor.** **Edit ▸ Undo** (⌘Z) and **Redo** (⇧⌘Z) were grey and did nothing in the
  Editor on the Mac, and on iPad, iPhone and Vision Pro neither ⌘Z nor the system's undo did anything. Now each takes
  back or brings back the last change, and the menu names it, as TextEdit does: **Undo Typing**, **Undo Paste**,
  **Undo Cut**. On iPad, iPhone and Vision Pro the system's own ways to undo (the keyboard's undo and redo buttons, the
  three-finger swipe, shaking iPhone) now reach the same undo; checked in tests on the simulator, not yet on a device.
  A cut now undoes on its own, rather than with the deletions beside it.

### 0.4.593 (3 November 2026)
- **A terminal that rings its bell while you're not looking at it stays marked in orange until you go to it**, on
  every device. A tab in an open window glows orange beneath its row; a window in the orb dock, or shrunk into its
  orb, turns that tab's icon orange (a window with one terminal gets an orange rim); **Show All Windows**, **Grid**
  and **Terminal Overview** glow beneath its picture, and **Carousel** lights its picture's edge. On iPhone the name
  at the top glows and the terminal shows a bell in the menu; on iPad its tab's symbol becomes an orange bell. A bell
  in the terminal in front leaves nothing behind, and the mark shows whether or not the bell plays a sound.

### 0.4.592 (3 November 2026, Vision Pro)
- **Vision Pro: a changed line is asked to be repainted where the terminal draws it, also when the terminal has fewer
  rows than its window** (a terminal kept in tmux and open on another device too, shown at that device's size).
  Before, the request named rows above it. Nothing changes on screen: the headset redraws the whole terminal for
  each request. Typing in a restored terminal that stays out of sight until the window is resized is not explained
  by this and is still open; the headset's diagnostics now record whether each terminal drew, to catch it next time.

### 0.4.591 (3 November 2026)
- **iPhone Duo stood like a small laptop: the remote desktop has the top half's full width.** It runs from just
  below the screen's rounded corners down to the fold, so they no longer cut off its menu bar or a window's close
  button. There is no status bar; the back button, the desktop's name, **Settings**, **Clipboard** and ⚡ are small
  glass controls in the band above it, kept as far from the corners as the system asks. A desktop that can change
  its size (Windows, most Linux desktops) is resized to fill the space; a Mac's screen keeps its shape.

### 0.4.590 (3 November 2026)
- **A window's overview and its carousel on iPhone, iPad and Vision Pro** (D99), as on the Mac. **Terminal View**
  chooses **Tabs**, **Grid** or **Carousel**: on iPhone and iPad at the top left, beside the back button; on Vision
  Pro in the window's bar, where it was. **Grid** draws the terminals as All Windows does — a picture of each, its
  coding agent's mark, its name and where it is — under the window's name, with a field to find one by name or
  folder, and the arrow keys, Return and Esc with a keyboard. **Carousel** is the Mac's album view; on Vision Pro it
  stands in real depth, the front out of the window toward you and the rest turned on either side, out into the room.
  Grid or Carousel is kept for the device. Off the Mac a terminal draws only while on screen, so the others show
  their last picture, and one not opened yet its symbol.
- **iPhone: the name at the top no longer runs under the buttons.** A long one, such as a coding agent's, now ends in
  "…" between the two sides.
- **Mermaid 12.3.0** draws diagrams (12.2.0 before), taken by the build as every build does; its packages' licences
  are in Acknowledgements.

### 0.4.589 (2 November 2026, Mac)
- **0.4.589 is the Mac's sixth release**, through Sparkle. iPhone, iPad and Vision Pro stay at TestFlight build 574.
- **The orb dock's drops behave again**: pointing at an orb no longer makes its drops shrink to a speck and grow back,
  the count on Connections shows again (it was hidden under the glass, a dark crescent below the circle), and a dot
  grows in place when you point at it.
- **The dock grows without a stumble**: Connections stays put and no "more below" arrow flashes while the dock widens
  for an orb that came; for a moment its orbs had wrapped into a column.

### 0.4.588 (2 November 2026, Mac)
- **The orb dock is Apple's Liquid Glass**: the dock is a slab of Apple's clear glass, its orbs and their dots are
  drops of the same glass instead of grey discs, and Connections is the app's icon floating in a drop instead of on a
  white circle. The dock's Glass, Material and Opacity still set it: Material Light to Heavy is the clear glass,
  dimmed a little more behind it as it gets heavier, and Max the frostier glass. macOS draws Liquid Glass clear only
  in the window you are working in and frosts it in every other, so the dock looks frosted while you work elsewhere.
- **Dots bud out of their orb** as it lands in the dock.
- **Smoother motion**: the dock grows and shrinks alongside its orbs' own animations; it held them still until it
  had finished. A coding agent's mark breathes as a smooth animation instead of being redrawn 30 times a second.

### 0.4.587 (2 November 2026, Mac)
- **The carousel's front tab is larger**: the row grows into the window, keeping room for the neighbours' outer
  edges and letting the reflection fade out behind the name. It had kept little more than half the height it was
  given, about a third of a window.

### 0.4.586 (2 November 2026, Mac)
- **The carousel's side tabs face the middle**, as Apple's album view turns its covers: each outer edge comes toward
  you and each inner edge goes back. They had faced out.

### 0.4.585 (2 November 2026, Mac)
- **The carousel's front tab stands clear of its neighbours.** The first tab either side tucked under it, and
  through a glass terminal showed as dark bands down its edges; now each starts just past the front's edge.

### 0.4.584 (2 November 2026, Mac)
- **The carousel is back on the Mac, as an album view** (D97). In a window's Terminal Overview, **Carousel** beside
  **Grid** puts one tab in front, large, with the rest turned toward it and stacked close on either side, each
  reflected on the floor, its name below. Its tiles are Show All Windows' — the live picture, the coding agent's
  mark, the wave while it prints. A trackpad swipe moves the row with your fingers, momentum and all; a drag, the
  scroll wheel or the arrow keys step it; a click on a tab beside the front brings it forward; Return or a click on
  the front opens it. Each tab travels through the middle as the row flows. With Auto-focus on activity, the front
  holds for three seconds before the next tab printing comes forward. Reduce Motion slides the row without turning.

### 0.4.583 (2 November 2026)
- **A terminal window's overview looks like Show All Windows** (D96), inside the window, with this window's tabs:
  a live tile per tab with its coding agent's mark, a wave while it prints, its name and folder on hover or
  selection; type to find, the arrow keys, Return to open, Esc or a click beside the tabs to go back. All tabs or
  This workgroup, and Auto-focus on activity, stay: with its controls fading after a few idle seconds, it can stand
  as a live wall. Blur previews softens it too. The card-size slider and the cards of sessions open elsewhere are
  gone: Show All Windows has everything.
- **No more carousel**, on the Mac or Vision Pro. The Mac's Terminal Carousel (⌥⇧⌘G) is gone, and Terminal Grid is
  **Terminal Overview** on ⌥⌘G; Vision Pro's Terminal View menu has Tabs, Grid and Orb. A Workgroup saved to open in
  the carousel opens in the grid.
- **⌫ takes back a letter** of what you typed in Show All Windows, as it now does in a window's overview: it did
  nothing.

### 0.4.582 (2 November 2026, Mac)
- **The Mac's orb dock springs back to show every orb** when you let go of a resize: as wide as you made it, and
  exactly as tall as its rows, however tall or short you dragged it. Dragged taller than its orbs, it used to stay
  that way, empty below them; made shorter, it hid rows to scroll to. Only a dock taller than the screen scrolls now.

### 0.4.581 (2 November 2026)
- **The Mac's orb dock grows from Connections**, which stays where you put it: orbs reach further to its right, a
  taller row grows evenly above and below it, a second row goes below, and the dock shrinks back to it as orbs go.
  It used to keep the middle of its bottom edge, so Connections slid left with every orb.
- **No dark crescents in a window's corners.** The frost was always rounded at 24 points, whatever the window's
  own corners, so a window rounded more tightly, such as the Mac's orb dock, showed its paint bare in each corner
  as a dark edge. The frost now takes the window's own shape.
- **The Mac's orb dock no longer stacks its orbs under a scroll bar** with a mouse attached: the Mac showed the
  dock's hidden scroller anyway, and it took the orbs' width as the dock grew.
### 0.4.580 (2 November 2026)
- **Shrink to Orb is a circle**, the orb's own glyph, everywhere a window becomes one: on the Mac in every
  window's toolbar, and on Vision Pro in the bars of desktops, databases and editors, as a terminal's view menu
  already had it. The two arrows were also the sign for Active's Take Over.
### 0.4.579 (2 November 2026, Mac)
- **The Mac's orb dock is only as big as its orbs**, the same distance from them on every side, with no bar under
  them: drag any empty part of it to move it. Pointing at an orb names it just above the dock, as the Mac's Dock
  names its icons (beside the dock when it stands taller than wide), so every name, Connections' too, is on one line.
### 0.4.578 (2 November 2026)
- **The Mac dock's Connections orb is Vision Pro's**: the app's icon on a white circle, ⚡ and Active's count on its
  rim, its middle level with the other orbs'. The band across the dock's top is gone: the dock painted a title
  bar's material it has no title for.
### 0.4.577 (2 November 2026)
- **The orb dock on the Mac** (D95), as on Vision Pro: **Shrink to Orb**, in every window's toolbar beside Show All
  Windows, puts the window in a dock of glass orbs that floats over your windows, its sessions still running. Each
  terminal window's orb shows the tab in front, with its tabs as dots around it, each with its coding agent in its
  colour; databases, desktops and editors gather on their machine's orb; Connections is first, with Active's count.
  Click an orb to bring its window back, a dot for that tab; drag an orb onto another to move it; resize the dock to
  make it a row or a column. Unlike Vision Pro, the window is only hidden, so nothing reconnects when it comes back.
  Settings ▸ Appearance ▸ Orbs: the dock above this app's windows, or above all windows, and its own Opacity and Glass.
  ⌘M still minimizes to the Mac's Dock.
### 0.4.576 (1 November 2026)
- **Vision Pro: a window's terminals come back when it is shown.** A terminal that was down stayed "Disconnected" when
  its window was opened, brought out of the dock or grown back from its orb: one whose connection was lost while the
  app was away, one whose five tries ran out, or one that didn't connect after a relaunch. Each now connects again as
  its window is shown, and when you come back to the app; one you disconnected yourself stays as it is. A terminal
  whose shell ended while its window was in the dock closes as the window opens, instead of staying behind with no
  way back. Choosing a relaunched window's terminal in Active or the dock reconnects it too.
- **A terminal that can't connect as it is shown says why** (every device), instead of only "Disconnected".
- **Vision Pro's diagnostics file records each terminal's connection** — connected, lost, retrying, given up, ended,
  disconnected by hand — with no names, addresses or text, so the next "why is it disconnected?" has an answer.
### 0.4.575 (1 November 2026)
- **0.4.575 is the Mac's fifth release**, through Sparkle. iPhone, iPad and Vision Pro stay at TestFlight build 574.
- **New Glass Power Tools Tab Here is a Finder Quick Action too** (Mac), beside Window Here: right-click a folder
  and it is under Quick Actions, and in the Finder's preview pane. If either is missing, turn it on in Quick Actions ▸
  Customize….
### 0.4.574 (1 November 2026)
- **Databases and remote desktops in Workgroups.** A Workgroup can now open databases and remote desktops from
  your library with its terminals, or on their own. Add them in the Workgroup's editor under Databases and
  Desktops; each opens as Connect opens it, and one already open comes forward instead of connecting again.
- **Favorites name a service by its machine** when its name says nothing more ("Database on alpha" is shown as
  alpha, Database).
- **The iPhone Duo:** a card chosen in Show All Windows, held like a book, opens on the page you are using, and a
  card's menu has Show on the Other Page. Stood like a laptop, a remote desktop could freeze the app as it opened;
  it no longer does.
- **Any short window:** a terminal moves Tools to its top bar when there is no height to spare, on any device, not
  only an iPhone on its side; a database's Disconnect and window settings follow whether it opened in a window.
### 0.4.573 (31 October 2026)
- **A remote desktop on the iPhone Duo, stood like a laptop: a keyboard and a trackpad at once.** Below the fold, the
  desktop's own keyboard sends each key as the remote computer's keyboard would, so shortcuts work: ctrl, alt and win
  (ctrl, opt and ⌘ on a Mac) held for the next key, fn for F1–F12 and Home, End, Page Up and Page Down, and Delete and
  the arrows repeating while held. Under it, three shortcut buttons (Copy, Undo and Select All to start; touch and
  hold one, then type the keys you want), Escape, and the trackpad. The iPhone's keyboard, for text and dictation, is
  the switch in the strip.
- **Use Both Pages and Swap Pages,** held like a book. Three dots above each page: Use Both Pages spreads one page
  across the screen for a session on its own — a remote desktop across both halves, a terminal twice as wide, a list
  beside its details — with the other page waiting underneath; Swap Pages trades their sides.
### 0.4.572 (31 October 2026)
- **The iPhone Duo, held like a book: two pages.** Held like a book, or open flat on its side, the inner display
  shows two pages, one each side of the fold, and each page is the phone as it is: a library, and whatever it
  opens, with its own back button. A terminal on the left and a database on the right, or any two.
  - What you open goes to the page you last touched. **Connect on the Other Page** (a machine's menu), **On the
    Other Page** (Connect's menu) and **Show on the Other Page** (a session's menu in Active) open it beside you.
  - A session is on one page at a time: chosen on the other page, it moves there, and the page it left goes back
    to its library.
  - A remote desktop and the editor open inside their page, as a terminal and a database do. Folded, the page
    you were using fills the screen, and it is still there, as it was, when you unfold.
- **A terminal on one side of the fold is that side's width.** Its text ran past both edges.
### 0.4.571 (31 October 2026)
- **The iPhone Duo, stood like a laptop.** Each tool keeps its work above the fold and puts a deck below it: a
  strip of keys just under the fold, then the keyboard or the tool's own panel, with a switch between them. A fresh
  fold brings the keyboard up once; put away, it stays away, and unfolding puts it back as it was.
  - **Remote desktop:** the remote screen above the fold, sized to it, and a **trackpad** below, which the fold
    brings up: one finger moves the pointer, a tap clicks, tap and drag drags, two fingers scroll or tap for a right
    click, and a click is felt. The strip has Keys and the arrow pad.
  - **Terminal:** the terminal above, Tools, the arrow pad and Keys in the strip, and with the keyboard away the
    window's **tabs as live pictures** below. With two tabs the other fills the panel, so a log stays in sight.
  - **Editor:** the code above; Tab, brackets and quotes, the arrows, Undo, Redo and Find in the strip; the file's
    preview below. A fold closes the project's files, which covered the strip.
  - **Database:** the query and its results above; Run, Explain and SQL's keys in the strip; the selected row,
    in the record editor, below.
- **A remote desktop's keyboard has no suggestions row,** as a terminal's has none.
- **Settings on Vision Pro lists its pages down the window's left side**, as the system's Settings does.
  Its tabs had room for only as many pages as the window was tall, and left Editor and About out.
- **A terminal tab can always be closed.** On Vision Pro, iPad and iPhone a tab's own menu has **Close Tab**,
  and a terminal whose connection has ended offers **Close Terminal** in its tools menu, where Detach was
  greyed out. A disconnected tab had no way to go.
### 0.4.549 – 0.4.569 (28 – 31 October 2026)
- **0.4.569 is the Mac's fourth release**, through Sparkle. Build 569 is also the first TestFlight build
  for testers outside the team, waiting for Apple's Beta App Review.
- **Git, end to end.** The Changes tab became **Source Control**: Changes, History, Branches, Stashes
  and Tags, on a Mac and, for a project on a server, on iPhone, iPad and Vision Pro too.
  - **A diff viewer.** Unified or side by side (unified when the window is narrow), the words that
    changed inside a line highlighted, 3 or 10 lines around each change or the whole file, and
    whitespace ignored when you ask.
  - **Stage a hunk, or single lines.** Each hunk has Stage, Unstage and Discard; choose line numbers
    to act on those lines only. What is staged is listed apart from what isn't. Discard a file's
    changes, or all of them (each asks first), and Amend the last commit.
  - **History** with the lines of its branches and merges, the branches and tags at each commit, and
    each commit's message and changes; from a commit, a branch or tag, check out, cherry-pick,
    revert, reset (soft, mixed or hard), copy, or open it on GitHub.
  - **Branches**, here and on each remote: switch, track a remote's branch, merge, rebase, make,
    rename, push, delete (asking again for one whose commits would be lost), open on GitHub, and begin
    a pull request. **Stashes** with their changes (apply, pop, drop), and **Tags** (make, push,
    delete).
  - **Merges and rebases that stop.** A bar says what is under way, with Continue, Skip and Abort, and
    a resolver puts each conflict's two sides beside each other: ours, theirs, or both.
  - **Blame** and a file's **History**, from the file list or the Mac's new Git menu, which also has
    each part of Source Control, Pull, Push, Fetch, New Branch… and Stash Changes….
  - **Clone**: File ▸ Clone Repository… on a Mac, or Clone Repository Here… on any folder in a
    project, on this Mac or on a server.
  - Open files a checkout, a merge, a stash or a discard changed are read again; one with unsaved
    edits keeps them, and saving it asks which version to keep.
  - Change marks beside the lines stay, in a narrow strip, with line numbers turned off.
  - Diffs follow Wrap Long Lines, and Show Only Changed Files narrows a project's files. The file tree
    strikes through deleted files and marks conflicted, staged and ignored ones, and says where a
    renamed file came from. Git 2.16 or later is needed.
- **Workgroups across Macs (0.4.567).** A workgroup's local terminals record their Mac. Every other
  device, another Mac too, opens them there over SSH on their own tmux sessions, made again in their
  folder only if they ended. An SSH terminal to a Mac's own record opens on that Mac as a local tab.
- **Logs and paths.** A log file's path leads its menu with **Watch Log File**, which follows it in a
  new tab. A log on the Mac previews its end and keeps up as it grows. **Open in Preview** on the Mac
  opens a picture or a PDF a terminal names, and a path's closing punctuation is left off.
- **The Mac's terminal toolbar (0.4.555).** One ⚡ for Active takes the place of the globe and the
  panes' server racks; Split Right and Split Down are in each pane's gear menu. Open Folder in Editor
  works from a terminal window.
- **Faster terminals.** Only the rows that changed are drawn again, and the Terminal Themes folder is
  read away from the main thread (0.4.550): on Vision Pro, keystrokes had been waiting half a second.
- **Editor windows as pictures** in Show All Windows and the switcher, sidebar and all.
- **SSH key records kept across devices (0.4.568).** A change to the keys on one device writes and
  deletes only its own records; it had been removing records another device made.
- **iCloud's footer says what to do:** "Sign in to iCloud to sync" or "Check iCloud to sync", in grey;
  red only for a sync that failed.
- **Vision Pro's diagnostics (0.4.569)** are hidden until you hold the version line in Settings ▸
  About; holding it again hides them.

### 0.4.495 – 0.4.548 (21 – 28 October 2026)
- **0.4.548 is the Mac's third release**, through Sparkle.
- **A Files window opened on an empty folder is painted all over.** On a Mac, a Files window that opened
  on an empty folder, or on one it couldn't reach, drew only its message in the middle, as tall as its
  words, with clear glass above and below where the window should be. It fills the window now.
- **Terminal color schemes.** Bring in macOS Terminal profiles — `.terminal` files, or a folder of
  them, as color-scheme collections come — and choose among them in a terminal's Settings ▸ All
  Terminals ▸ Theme ▸ **Choose…**, where each is drawn small in its own colors: its background, text, a
  highlighted word and its sixteen colors. They're kept in iCloud Drive ▸ Glass Power Tools ▸
  Terminal Themes, so every device has them, and Files and the Finder can add more. This Window can
  use one for one window, and the choice for all terminals syncs. A scheme brings its background,
  text, selection, cursor and sixteen colors, read on every device as Terminal reads them; your font
  stays. Copy to Your Themes makes one an ordinary theme to change. Open With Glass Power Tools on a
  `.terminal` file, AirDrop or Files adds it, and one file on its own becomes the scheme in use. A
  profile's bold-text color is not drawn: the terminal draws bold in the text's color, or bright.
- **Pull, Push and Fetch in the editor.** Changes shows Pull and Push with how many commits each
  would move, and Fetch; a branch the remote doesn't have yet offers **Publish Branch**. The branch
  button at the foot of the file list shows ↑ and ↓ counts, with the same on a right-click or a
  hold. A pull only ever moves the branch forward, and open files it changed are read again unless
  they hold unsaved edits. When git refuses — the remote has moved on, the key or the host isn't set
  up, there's no remote — it says what to do. A project on a server pulls and pushes there.
- **The orb dock on Vision Pro.** With Settings ▸ Appearance ▸ Orbs ▸ Shrink to Orb set to Into the
  Dock, a window shrunk to its orb falls into one dock you can move and resize, beside Connections'
  orb; terminals, databases, desktops and editors keep running while docked. A pinch brings a window
  back where it was. Orbs wrap in rows or stand in a column, names turn to stay clear of their
  neighbours, arrows show more to scroll to, and an orb held can be carried to another place.
- **Focus Mode environments on Vision Pro.** Focus Mode can surround you with a built-in — Night Sky,
  Dusk, Grid, Studio — or your own 3D room or 360° photo, kept in iCloud Drive ▸ Glass Power Tools ▸
  Environments, for every window or one (This Window, or a pinch and hold on the moon). **Open
  Immersed** opens it all the way round. **Try Out** fits a room: what its numbers are in, its size,
  its floor, where you start. Inside, look down and pinch the floor to go there, choosing your facing
  with your hand; pinch the sky to turn. Only the floor is landed on, never a desk's top. **Fine
  Position**, from the moon's menu, steps you 2 cm and turns you 1° at a time and raises or lowers the
  room a centimetre, held to keep going, and keeps your spot as the room's start. A room can bring
  its own life: what moves in it, a clock on the headset's time, a digital clock and date, sounds
  beside it (Room Sound sets how loud), and things that happen now and then.
- **A picture pasted in a terminal goes to the machine.** On iPhone, iPad and Vision Pro a picture
  or a file on the clipboard is copied to the machine and its path typed, as a dropped one is.
- **Vision Pro's terminal windows stay responsive while agents work.** A window was drawn again
  whenever any of its terminals printed, many times a second with a few coding agents at work, and
  its tools menu stopped answering. The front terminal now keeps its place while it prints, and
  the menu is rebuilt only when what it shows changes.
- **Every headset crash since 0.4.508 is fixed.** All seven were a terminal's picture — for All
  Windows' cards, an orb, the dock — drawn while SwiftUI was updating; it's drawn just after now.
- **A menu in the empty space of a Vision Pro terminal sidebar**, held: what the bar's + offers, as a
  Mac sidebar's right-click does.
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
  terminals in a sidebar, as a Mac window does, in its own glass on the window's plane, a few points
  from its left edge: each row with its name and where it is. Showing or hiding it leaves the window's
  size alone, so the terminal doesn't move or change its rows and columns. Pinch and hold a row for its
  menu, or drag it onto another window, onto another row, or into empty space for a window of its own;
  a terminal's name at the top drags the same way. Apple's tab bar, which held the tabs before, showed
  only identical symbols until looked at.
- **A tmux session open on the Mac and the headset follows the one in front.** tmux gives a session one
  size, the size of the device that attached last, and the other device drew the program's lines at its
  own width, broken and run together. Now a terminal takes the session's size when you select its tab,
  come back to its window or type in it, and the program redraws for that device; the other device
  shows the session at that size, with dots in the space past it, as tmux marks it.
- **Quick Look on Vision Pro.** Pinch and hold a path a terminal printed and choose Quick Look: the file,
  copied from the server, shows over the terminal as on the Mac, with Open in Editor and Show in Files.
  With a trackpad or mouse, resting the pointer on a path shows it too (Show previews in Settings ▸
  Terminal and in a window's settings), or Space does under Mouseover + Space.
- **No "host library could not be read" after taking the headset off.** The library is locked with the
  device; a read while it was locked was taken for a build without its shared storage. Now the app reads
  it again as the device unlocks, and says nothing.
- **Show All Windows around you on Vision Pro.** Pinch and hold ⚡ for All Windows; choose Around You,
  or set Settings ▸ Appearance ▸ Show All Windows ▸ Opens to Around You, and the same cards stand in an
  arc around you while other apps step out of the room. In a Window, or a pinch out with both hands,
  steps back. A two-handed pinch on a window is visionOS's resize, so it isn't used to open it.
- **⚡ in Vision Pro's terminal bar.** It takes the place of Connections: a pinch opens Connections on
  Active, and a pinch held shows every window, as ⚡ does in other windows.
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
- **A database that won't connect says why.** When the machine a database is tunnelled through finds
  nothing listening, the message says so at once, and where to enter another address if the
  database runs elsewhere. Any connect that hasn't finished after 30 seconds now stops and says so.
  Before, a MySQL connect through such a tunnel waited for ever and showed nothing.
- **Saved connections changed on another device stay changed.** Saving a terminal, database or
  remote desktop on one device wrote back its copy of every other one of that kind. A copy older
  than an edit made elsewhere went back over it: a database lost the address it is reached at. A
  connection added on another device could be deleted by the next "last connected" stamp, and a
  field from a newer build was dropped. Now a save writes only what was changed on that device,
  and the lists are read again whenever iCloud brings changes while the app is open.
- **A database's Connection Details show where the tunnel goes.** The Endpoint was the machine's
  own address even when the tunnel goes on to a Database address beyond it, so a lost address
  could not be seen there. It now shows the Database address, or "on this machine" when there is
  none, and the Tunnel row names the machine a tunnel goes through instead of always saying
  "this machine".
- **⌘F finds in the editor.** Edit ▸ Find ▸ Find…, Find Next (⌘G) and Find Previous (⇧⌘G) were
  greyed out in an editor window, whose find bar was on ⌥⌘F in the Editor menu. They search the
  document now, and Find puts the cursor in the find field. A match found, and a line gone to,
  is now selected and scrolled to: until now the find bar and Go to Line moved a selection the
  text never showed, on every device.
- **Git in the editor.** A project in a git repository shows its branch at the foot of the file list,
  with how many files differ from the last commit, and the tree marks each changed file (M, A, D, R,
  U for new) and every folder holding one. The branch opens **Changes**: every changed file's lines
  since the last commit in one scroll, numbered old and new, as `git diff HEAD` has them, new files
  whole. A line opens its file there. Changes keeps itself current while it is open, and every
  project's git is asked again when its window comes forward and after a save. On the Mac it is
  Text ▸ Show Changes (⌃⇧G). It runs the git where the folder is: the Mac's own, or the server's over
  the project's SSH connection, so a project on a server shows its changes on an iPhone, iPad or
  Vision Pro too. Folders on an iPhone, iPad or Vision Pro have no git to run.
- **Change marks and committing.** An open file in a git project marks its lines beside the
  numbers: green where lines were added since the last commit, amber where they changed, a red
  wedge where lines were removed. The marks follow what you type, before you save, and clear when
  the change is committed. In **Changes**, each file has a box that stages it for the next commit
  or takes it back out (a dash means part of it is staged), and **Stage All** does every file. Write
  a message above them and choose **Commit** (⌘↩); with nothing staged the button is **Commit
  All** and stages everything listed first. Folders that are repositories of their own are never
  staged. A project below its repository's root asks before committing files staged outside its
  folder, which Changes doesn't list. When git refuses — no name and email set, a hook that
  stopped the commit, another git command holding the repository — Changes says why and what to do.
- **A dropped terminal is listed once in Active.** When a terminal in tmux lost its connection, as an
  iPhone's do while it's put away, Active listed it twice: the terminal, Disconnected, and its
  session again below it, Open elsewhere, where choosing it opened a second terminal on the same
  session. Now the terminal's row stands for the session and says what the machine said of it —
  where it is, whether it's open elsewhere, when it was used — or that it has ended. Choosing it
  reconnects to the session. Swipe it to **Detach** and the session is listed under the machine
  straight away.
- **A remote desktop that ends the session says why.** A server ending a session sends its reason and
  hangs up; when the reason arrived while the app was still drawing the picture before it, it was
  dropped, and the session read as closed normally. The reason is kept now, so "logged on elsewhere"
  or "disconnected by an administrator" is what you're told.
- **tmux on the Mac can be stopped.** A tmux server the app started on the Mac inherited blocked
  signals from the thread that started it, and ignored `kill-server` and the signal the Mac sends
  to end a process. What the app starts on the Mac now gets every signal, as from a Terminal window.
- **Cancel and the time limit stop any SQLite query.** SQLite's interrupt reaches only a statement
  that is running, so a Cancel, or the query time limit, that came while a query was being prepared
  or between its statements was lost, and the query ran on. Both now stop it wherever it is.
- **Reviewing a paste works on an iPhone.** The sheet that asks before a multi-line paste is sent was
  laid out for a Mac's minimum width, wider than the phone: its sides were cut off, with Cancel,
  Paste and Join Wrapped Lines past the edges. It fits the screen now.
- **VoiceOver reads the lines a terminal shows after it changes size.** After a larger text size or
  a rotation, VoiceOver kept the old size's lines until the terminal printed something.
- **A text default with a backslash survives on MySQL.** MySQL reads `\` in a quoted value as an
  escape, so a column default holding a Windows path or a pattern lost or changed its backslashes
  when set from the table's structure. They are doubled for MySQL now; PostgreSQL is unchanged.
- **Holding a sheet over ⚡ is holding the sheet.** On an iPhone, a press held on a sheet such as Add
  Host, at the spot where the library's ⚡ lay underneath, opened All Windows over the sheet. On the
  iPhone Duo's outer display the sheet's title bar lies right there. Only a ⚡ on the screen in front
  answers a hold now.
- **VoiceOver finds a tag field's text box.** On iPhone and iPad VoiceOver outlined a host's tags as
  the text box, and a double tap could land on a tag's remove button instead. The text box is its
  own element again.

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
