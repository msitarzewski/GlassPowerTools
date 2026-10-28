# Release notes

The Mac app's first release was 0.4.491 (20 October 2026), and the latest is 0.4.547 (28 October 2026): a download from
[glasspowertools.com](https://glasspowertools.com), signed with a Developer ID, notarized by Apple, and
updated through Sparkle. iPhone, iPad and Vision Pro builds go to TestFlight for internal testing; their
first App Store release will be 1.0, and the Mac will be 1.0 then too. Builds are numbered 0.4.*n* until
then. These notes say what the app holds and what changed in each build, and are kept current as the
work lands. What is verified, and how, is in [memory-bank/progress.md](memory-bank/progress.md).

## What it holds (0.4.547)

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
- Color schemes from macOS Terminal profiles, any number, kept in iCloud Drive for every device and
  chosen with a preview of each, for every terminal or one window.
- On Vision Pro, Focus Mode surrounds you with a built-in environment or your own 3D room or 360°
  photo, which you can walk about in, with a room's own motion, clocks and sounds.

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
- Git: a project's branch and changes, change marks beside the lines, staging and committing, and
  pull, push and fetch, on this Mac or on a server over the project's SSH connection.

### Across the system
- Widgets (Machines, Machine, Active), Siri and Shortcuts, Spotlight, Controls, Handoff and
  `ssh://` links. On the Mac: the Finder's Services, toolbar button and Quick Action, Share ▸ Send to
  a Machine, Open With and the Dock menu.
- Light, Dark or System for the whole app on the Mac, iPhone and iPad; window opacity and glass
  everywhere; and on Vision Pro, session windows that shrink into an orb, or into one dock.

### Known limits
- The Mac app runs outside App Sandbox (a terminal cannot work inside it), so it will be distributed
  directly, signed and notarized, not through the Mac App Store. See [SECURITY.md](SECURITY.md).
- VNC without a Mac account is not encrypted after sign-in.
- A file on a server larger than 64 MB can't be opened in the Editor.
- What has not been verified on a device or against a real server is listed under "Not verified" and
  "Known and open" in [progress.md](memory-bank/progress.md).

## Recent builds

### 0.4.495 – 0.4.547 (21 – 28 October 2026)
- **0.4.547 is the Mac's third release**, through Sparkle.
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
