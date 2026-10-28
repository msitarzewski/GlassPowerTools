# Product context

## The model

A **host** is a machine. It owns **services**: an SSH endpoint, a database, a remote desktop. The
shared catalog already expresses this as `HostProfile` with `services: [HostServiceLink]` of kind
`ssh`, `database` or `rdp`. Glass Power Tools makes that model the interface instead of splitting it
across three applications.

## What changes for the user

| Today, across three apps | In Glass Power Tools |
|---|---|
| A connection lives in whichever app matches its protocol | A host lives in one library and lists its services |
| "Paired Services", linking a connection in one app to one in another | "Add a service…" on the host |
| Opening a paired service launches another application, which may not be installed | The service opens in place |
| Three settings interfaces that have drifted apart | One settings surface |
| Three credential stores sharing one Keychain group by arrangement | One store, by construction |

## The library row and the Connect control

A host row shows an icon per service it actually has. When a host has more than one service, the
control has two halves on every platform (the press-and-hold plan gave way to a visible control): the
play glyph connects **every** service on the host, and the chevron beside it picks one (the brief's
2026-09-11 refinement; `GlassShellModel.connectAll`, `Sources/GlassShell/GlassShellModel.swift:1613`).
This Mac offers only the chevron, since connecting "all of it" means nothing for the device itself
(D8). The row's own menu has Connect, which opens the service last used on that host (the details call
it "Connect opens"). A host with one service has a single play button. *Corrected 2026-10-17: this
paragraph said Connect opened the last-used service.*

## Design order

visionOS first, then Mac, iPad and iPhone. Not because the headset is the busiest platform, but
because it is the one with capabilities and constraints that cannot be retrofitted, and because the
product exists to use them. Compact phone layouts adapt down from a spatial design far more honestly
than a spatial layout adapts up from a phone.

## Where the product is differentiated

On Vision Pro, a host's terminal, database and desktop can occupy one spatial workspace. glas.sh's
Workgroups concept already reaches toward this and could not complete it across three applications.
This is the reason to merge that no amount of shared packaging would have delivered.

## Interface decisions already made in the source apps, to be preserved

- Favorites, groups and collections, search, selection and the detail panel, from the shared library.
- Native platform navigation, with compact adaptation on phones rather than a bespoke pattern.
- Normal native windows on visionOS with shared Glass framing; source resolution kept separate from
  local scale.
- Optional presentation modes for remote desktops, including a reliable Original view.

## Terminals in and out of tmux, and widgets (2026-10-12)

- Local terminals in tmux live in a background Glass Power Tools process: quitting, updating or force quitting the app,
  or force quitting an app started from a terminal, leaves them running; it ends itself with the last one, and
  Settings ▸ Terminal ▸ tmux can end them all.
- tmux stays the default where it is set (one setting for this Mac, one per host), and any terminal can be opened as a
  **Basic** one outside it — the word the owner chose for the "+" menu ("new terminal, new basic terminal, new terminal
  on...").
- Menus that say "Terminal on" name machines, not the terminals' stored names.
- Widgets: **Machines** (favourites and recent machines; tap a service to connect) and **Active** (what is open and
  running). Workgroups and Controls widgets were offered and not chosen.
- A busy tab glows with a soft cloud of light sweeping across it (the owner's choices: light sweep, softer, slower,
  cloud-like, not clipped).


## One overview, one palette, and a way back on every screen (2026-10-13)

- **Show All Windows** (⇧⌘\, the button beside every ⚡, a pinch in on terminal and desktop windows) shows every
  window the app has open: terminal windows with a tile per tab, then Files, Databases, Desktops and Editor. A desktop's
  tile is its last picture. Settings ▸ Appearance ▸ Show All Windows ▸ **Blur previews** softens the pictures for
  screenshots that can be shared.
- **One Command Palette** (⇧⌘P, or ⌘K) holds every capability's entries: machines, connections, schemas and tables, and
  the front window's own commands. It is drawn in the windows' own glass.
- **Settings ▸ Appearance ▸ System, Light or Dark** (D71) sets the whole app's look on the Mac, iPhone and iPad.
- **A phone shows a session in place**, folded or not, with its back chevron and the ⚡: a phone cannot close a window
  from inside it. An iPad's desktop window has its bar and a working Close. A desktop that is not connected says so in
  the system's own view, not in a card ("this feels web").
- **The library keeps the system's sidebar toggle on iPhone and iPad**, so a two-column screen always has a way back
  to All Connections.
- **A terminal window's tabs each have a close box**; a failed pane offers Reconnect, Connections and Close Pane, and
  closing the last pane closes the tab.
- **Database errors say what happened in plain words:** the server's own refusal ("password authentication failed
  for user …"), "No machine named … could be found", and, for a machine on the local network that cannot be reached,
  where to allow Local Network access.

## Favorites, the overview everywhere, and the owner's October asks (2026-10-13 to 2026-10-17)

Each is built; where only a simulator or a test has seen it, the owner's devices are the check
(`progress.md`).

- **Favorites hold anything you return to** (D73): sections by kind — Machines, Services, Projects, Workgroups,
  Folders — synced between devices. Star a machine on its row, a service from its menu in the machine's details, a
  project or saved workgroup from its menu, and a folder from Files' toolbar (Add This Folder to Favorites). A
  favourite opens on one click or tap, as a Finder sidebar favourite does; a folder opens Files there, or, from its
  menu, as a project.
- **Show All Windows on every device** (2026-10-14): on iPhone and iPad hold the ⚡ or pull down from the empty part
  of a top bar (a glass pane; push or toss it up to close); on Vision Pro hold the ⚡ or ask Siri ("Show all
  windows") for a window of its own. Cards by machine, one per tab, pictures refreshed each second (on an iPhone a
  terminal has a picture only once it has been on screen, and keeps its last), an AI agent's mark on a terminal
  that runs one, Blur previews honoured. The Mac keeps ⇧⌘\, its button and the pinch.
- **Sessions into a window you already have** (2026-10-15): Active's Open as Tab In ▸ for a running session, and
  for several chosen at once; a terminal window's "+" (held, off the Mac) lists every saved server ▸ New Terminal and
  its running terminals, and the Mac's "+" menu lists running terminals too.
- **Vision Pro: a session window shrinks into an orb** (D74): Shrink to Orb first in the bottom bar (in a terminal
  window with several terminals, Orb in the view menu beside Tabs, Grid and Carousel). A glass sphere showing the
  session; its tabs as dots on a ring; look at a dot for its picture and name; a pinch grows the window back, on
  that tab. It pulses with activity when the window's Auto-focus on activity is on.
- **Vision Pro: orbs in a dock** (D88, 2026-10-25 to 27): with Settings ▸ Appearance ▸ Orbs on Into the Dock, Shrink
  to Orb closes the window into one dock with the Connections orb; a machine's databases, desktops and editors are one
  orb; look at a dot for its name (it opens left near the dock's right edge), pinch an orb to bring its window back,
  hold and carry an orb in any direction to reorder; a quick pinch-drag scrolls. The dock is resized like any window:
  its orbs wrap into rows as a flexbox does, a column when it is one orb wide, and once the hand lets go it snaps to
  the widest row and the nearest whole rows, keeping the size given; an orb docked below them grows it to show that
  row (up to three), and arrows at its ends show there is more to scroll to. A window comes back above a wide dock and beside
  a tall one: away from where the person turned in Focus Mode, else on the side set in Settings (Windows From a Tall
  Dock). Connections is a third larger and set apart; held, it offers favorite and recent machines and Dock Settings.
  Its own Opacity and Glass start from Appearance. After a relaunch, windows come back as they were left — open, in
  the dock with their last picture, or as their orb — and Connections goes back into the dock unless something needs
  an answer.
- **Vision Pro: Focus Mode environments** (D89, 2026-10-26): Dimmed Room, Night Sky, Dusk, Grid and Studio, and the
  person's own 3D rooms and 360° photos from iCloud Drive ▸ Glass Power Tools ▸ Environments; Open Immersed; Try Out
  fits a room (its units, size, floor, where to start) and keeps the fit for every Vision Pro; inside, look down and
  pinch to move, as in Mirador.
- **Vision Pro terminal text, as Apple's text works** (2026-10-15/16): double pinch selects a word, pinch and hold
  selects the word held, drag either end to change it, and a trackpad click-drag selects as on a Mac; a pinch-drag
  scrolls even when tmux has the mouse. A held link or path offers its actions.
- **A terminal that scales instead of re-gridding** (D75; Mac, iPad, Vision Pro): When Resized — Change Rows and
  Columns (as before) or Scale the Text — in Settings ▸ Terminal, This Window, and Scale Text in the window's bar.
  Under Scale the rows and columns stay, the window keeps their shape, and ⌘+ / ⌘− / ⌘0 size the window (on iPad
  only ⌘+ can, by growing it).
- **Links and paths in a Mac terminal** (2026-10-14/16): right-click a path for Quick Look, Open in Editor, Show in
  Finder, Watch Log File (a `tail -F` tab in the same window) and Copy Path; a link for Open Link and Copy Link.
  Show previews (D76) — Never, Mouseover (the default) or Mouseover + Space — shows a printed path's file over the
  terminal as the editor shows it, local or on the server, with Open in Editor; web addresses never preview on
  hover, and Space on one asks before opening it, as ⌘-click does.
- **A Mac terminal window's sidebar adds to the window** (D77): opening or closing it grows or shrinks the window,
  and the terminal keeps its size, place, rows and columns. "+" slides with the sidebar, as AppKit arranges it (a
  version that held it still was tried and closed at the owner's word). No line at the sidebar's edge in a terminal
  window; database and desktop windows keep theirs.
- **3D models wherever files open** (D78): USDZ, USD and Reality files in the editor's viewer, Files and the Mac's
  hover preview — turn and zoom on Mac, iPhone and iPad (View in AR on the phone and iPad), Apple's Quick Look volume
  on Vision Pro. A model's link in a terminal asks, then opens in 3D here (Open in 3D).
- **Smaller asks from the same days:** a file dropped on a terminal has its path typed, or the drop says why not;
  ⌘S off the Mac saves, asking where for a new document, and a new file saves into a project on a server; the
  desktop's Clipboard menu has Sync Automatically (per desktop, on by default); Settings ▸ a Desktop service ▸
  Graphics (Automatic, H.264 (4:2:0), Without H.264); Share ▸ Send to a Machine on the Mac (D72); Siri and Shortcuts
  open machines, services, workgroups and saved queries (a saved query opens in a new SQL tab, never run).
