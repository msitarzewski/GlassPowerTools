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

A host row shows an icon per service it actually has. Connect opens the service last used on that
host. When a host has more than one service, the rest are reachable from the same control: a chevron
menu beside Connect on every platform (the press-and-hold plan gave way to a visible control). A host with one service behaves exactly as it does today.

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
