# System patterns

Status: written as the intended structure on 2026-09-10, before any code; **the structure is built**
and each later section, dated, records a pattern as it was established.

## Intended shape

**One multiplatform application target** for macOS, iOS and visionOS — the glas.sh and glassdb
model, decided 2026-09-10 in [decisions](decisions.md) — plus a widget extension, over a set of
local modules:

| Module | Owns |
|---|---|
| Shell | Library, host and service navigation, settings, window and scene model, credentials boundary |
| Layers | Window transparency, title bar backgrounds, panel and detail materials, opacity controls |
| Terminal capability | SSH sessions, SFTP, port forwarding, workgroups. Moved from glas.sh |
| Database capability | Connections, browsing, query surfaces. Moved from glassdb |
| Desktop capability | RDP and VNC sessions, Metal presentation, input. Moved from glassDT |
| Protocol engines | RDPKit, VNCKit, SSH and database drivers, kept as separate modules |

| Editing capability | GlassEditorKit. Library in from the start, interface built last |

The shell depends on no capability. Each capability depends on the shell and on its own engines.
Capabilities do not depend on each other.

**Layers are not a later polish pass.** Every surface gets its material from one system: windows,
title bars, panels, detail views and session canvases. A capability never invents its own background
treatment. This exists before the first capability arrives, because retrofitting transparency across
four capabilities is how the three apps ended up with three settings designs.

Build on what exists: the titlebar material already extracted into GlassConnectionUI and consumed by
all three applications, plus glassDT's window frame, canvas backdrop, opacity and background frost.

## What this replaces

Each item below exists today only because three processes had to agree, and should not be carried in:

- Service pairing between applications.
- The `glassh://`, `glassdb://` and `glassdt://` link routing and its "the paired app could not be
  opened" failure path.
- The shared App Group catalog with its publication journal, removal journal and offline retry.
- Three independently pinned copies of GlassConnectionKit, GlasSecretStore and GlassEditorKit.

The host catalog itself stays. It stops being a synchronisation mechanism and becomes the store.

## Design order

Every shared surface is designed for visionOS first and adapted down to Mac, iPad and iPhone. This
applies to the shell, the layering system, the library and the settings surface. A capability that
arrives with a Mac-shaped surface is adapted, not enshrined.

## Rules for the move

- Move code as modules; do not rewrite working functionality to make it fit.
- Draw the shell boundary before importing the second capability, or the first one's assumptions
  become the boundary by default.
- One capability at a time reaches parity, with the source application still building until it does.
- A capability's protocol engine never gains a dependency on the shell.

## Reuse inventory: session presentation (2026-09-21)

Written after building a session list from scratch while a grid, a carousel, live previews and a
**tested** layout solver were already in the product. The inventory below is what a reuse check
should have produced before any of that was written. Rule 57.

| Behaviour | Owner today | Reachable from | Notes |
|---|---|---|---|
| **Terminal still image** | `SwiftTermHostModel.previewImage(maxPixelWidth:)`, `Sources/GlassTerminalEmulator/SwiftTermHostView.swift:575` (NSImage) and `:601` (UIImage) | Anywhere — `GlassTerminalEmulator` is a base module | Cross-platform already. This is D4's snapshot |
| **Gallery layout solver** | `GlassGalleryLayout`, `Sources/GlassShell/GlassSessionGallery.swift` | Anywhere | **Moved here 2026-09-21** from `MacTerminalOverviewGrid`. `MacTerminalOverview` uses it through a typealias; its tests moved to `GlassShellTests` and now run on every platform |
| **Grid ⇄ carousel overview, card-width slider, arrow-key navigation** | `MacTerminalOverview`, `Sources/GlassTerminal/macOS/MacTerminalOverview.swift` | macOS only | **Since 2026-09-21 shows every open session** — its own tabs live, everything else as `GlassSessionCard` — browsed as one row (`MacOverviewItem`) |
| **Spatial grid and carousel** (3D rotation, ±1 card rendered) | `VisionTerminalWorkgroupView.spatialOverview`, `:414` | visionOS only | Same scope: one workgroup |
| **"Only fresh output may steal selection"** | `MacTerminalActivitySelection`, `MacTerminalOverview.swift:178` | macOS only, but pure and portable | A live gallery wants this; the session gallery does not use it yet |
| **Idle-hiding policy for overview chrome** | `MacOverviewIdlePolicy`, same file | macOS only, pure | |
| **Running-workgroup card grid** | `TerminalWorkgroupsView.swift:379` | macOS only | A *third* card treatment (see drift below) |
| **Cross-capability session list and gallery** | `GlassOpenSession`, `GlassSessionSwitcher`, `GlassSessionGallery`, `Sources/GlassShell/` | Everywhere | The gap all of the above left: they switch within one capability |
| **Desktop still image** | None. `DesktopSessionModel` holds a framebuffer and builds `CGImage` for the cursor (`:621`) but exposes no frame snapshot | — | Moot today: the desktop contributes no sessions (D31) |
| **Database / editor still image** | None, and none wanted | — | A card with a name and a symbol is the right answer for both |

**Known drift to settle when the gallery is next touched:** there are now four card treatments —
`MacTerminalOverview`'s, `VisionTerminalWorkgroupView.overviewCard`'s, the workgroups detail
grid's, and `GlassSessionCard`. They differ in corner radius, border and how selection is shown.
`GlassSessionCard` is the candidate to absorb the others, and the two terminal ones should adopt
it rather than a fifth being added.

## Contextual File items and Mac key owners (2026-09-25)

One menu item per key, aimed by the focused window: the window publishes a focused scene value with
the item's title and action, or nothing (the item is then disabled, never borrowed from another
window). `MenuBarPlacementTests` holds a single-owner guard per key.

| Key | Owner | What the window says |
|---|---|---|
| ⌘N | shell (`\.glassNewItem`) | New Host · New Terminal Window · New SQL Document · New Document |
| ⌘S | shell (`\.glassSaveItem`, D37) | Save… / Save (editor) · Save SQL Document… (database) |
| ⌘W | `GlassCloseCommandRouter` (registered, never declared) | editor: the document, and the window with its last document unless a project is open |
| ⌘O / ⌥⌘O | editor's Open File… / Open Project… | runs its own panel from any window |
| ⇧⌘O | database's Open SQL Document… | |
| ⇧⌘E | editor's New Editor Window — opens on a blank document | |
| ⌥⌘E | database's Explain Plan (moved from ⇧⌘E, 2026-09-25) | |
| ⌘T | terminal (Mac workspace; visionOS platform commands) | |

## Synced preferences beside the catalog (2026-10-08)

Hosts and services sync through CloudKit (the catalog). Smaller per-person lists sync through the
shell's iCloud key-value service, `GlassSettingsSyncService<Payload>` (`GlassShellSettingsSync.swift`):
one store key per payload, a revision envelope, and the payload's own `converged(with:)` merge.
Users: terminal themes and preferences, the editor's project list, favourites (D49), workgroups (D51).
The pattern each follows: every item carries its own change time; the newest change per item wins;
a deletion is a dated tombstone so it travels; fields that describe this device (last opened, last
used, per-device substitutions, the device's own host) are left out. A payload is used off the main
actor, so an item whose coding is main-actor-isolated in its module travels as JSON and is decoded
and validated when applied. Tests drive two "devices" over a shared in-memory store and check the
test fails without the push.

## Background processes, widgets and choices that travel (2026-10-12)

- **A process that must outlive the app runs under launchd as the app itself.** Local tmux (D66): a job in Application
  Support (no login item) runs the app's executable with `--tmux-host`, chosen in `GlassPowerToolsMain` before SwiftUI
  starts anything; it spawns tmux (stdout/stderr only inherited) and waits. Programs in panes answer to Glass Power
  Tools for privacy permissions and sit in the job's own coalition, so no app's Force Quit reaches them. A
  `ServerManager`-style seam (`MacLocalTmux.Server`) carries every tmux call, so tests swap all of it.
- **Widgets read a snapshot the app writes for them, never a store of record** (D68, `GlassWidgetData`): written into the
  App Group only when its content changes, metadata only, schema-numbered; `GlassShellModel.widgetSnapshot()` builds it
  from the library and Active. Taps are App Intents defined once in the package (`AppIntentsPackage` in the app and the
  extension) and handed to the app through `GlassWidgetRequests`, which holds a request until the app is ready.
- **A per-terminal choice travels with the terminal's record:** `withoutTmux` (D67) on `TerminalSession`, the Mac pane
  intent, the workgroup intent and the reopen record, set at every place a terminal is made and honoured where tmux is
  decided (`usesTmux`, `assignLocalTmuxSessions`, the offer).
- **A capability that needs the library's knowledge gets a closure from the composition root**, as `openSessions` did:
  `GlassTerminalRuntime.hostName` gives terminal menus the machine's name from the catalog.
- **A long-lived remote connection is wrapped to reopen itself** (`GlassTerminalReconnectingLister`): a call failing
  because the connection is gone is retried once on a new one; concurrent calls share one reconnect.

