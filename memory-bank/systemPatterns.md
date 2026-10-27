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

**As built** (read from `Package.swift`, 2026-10-17): nineteen library products, beside the vendored
grammar targets. Shell side —
`GlassShell` (library, settings, capability registry, Active, All Windows, orbs, window sizing and
shape, additive sidebars; Sparkle on macOS only), `GlassLayers`, `GlassConnectionKit`,
`GlassConnectionUI` (shared library UI and window chrome), `GlassHostCatalog`, `GlasSecretStore`,
`GlassWidgetData` (the widget snapshot, intents and requests, shared with the extensions).
Capabilities — `GlassTerminal`, `GlassDatabase`, `GlassDesktop`, `GlassEditor`. Engines —
`GlassTerminalEmulator` (SwiftTerm's host), `GlassSSHTransport` (Citadel), `GlassDBKit` (MySQLNIO,
PostgresNIO), `GlassRDPTransport` (RDPKit, vendored in `Packages/`), `VNCKit`, `GlassVNCTransport`,
and the editor's `GlassEditorCore` and `GlassEditorUI`, which the terminal and the database import as
libraries (the editing row above became these three targets when GlassEditorKit was absorbed,
2026-09-14). No capability imports another: where one needs another's view, the composition root
hands it over as a closure (below, 2026-10-14 onward). The Xcode project adds the app, its UI tests
and five extensions: widgets (all three platforms) and, on the Mac only, Finder Sync, Quick Actions,
Share and an inert File Provider.

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
| **Terminal still image** | `SwiftTermHostModel.previewImage(maxPixelWidth:)`, `Sources/GlassTerminalEmulator/SwiftTermHostView.swift:684` (NSImage) and `:716` (UIImage) | Anywhere — `GlassTerminalEmulator` is a base module | Cross-platform already. This is D4's snapshot. Off the Mac it is drawn with `drawHierarchy`, because `layer.render` cannot see Metal drawing (7837885), and a terminal left keeps its last picture (f824c8c) |
| **Gallery layout solver** | `GlassGalleryLayout`, `Sources/GlassShell/GlassSessionGallery.swift:24` | Anywhere | **Moved here 2026-09-21** from `MacTerminalOverviewGrid`. `MacTerminalOverview` uses it through a typealias; its tests moved to `GlassShellTests` and now run on every platform |
| **All Windows layout solver** (groups of equal tiles, as large as the space allows) | `GlassAllWindowsLayout`, `Sources/GlassShell/GlassAllWindowsLayout.swift:20` | Anywhere | **Moved here 2026-10-14** (321a625) unchanged from `MacTerminalExposeLayout`, now a typealias (`Sources/GlassTerminal/macOS/MacTerminalExpose.swift:193`); the off-Mac overview uses it |
| **Grid ⇄ carousel overview, card-width slider, arrow-key navigation** | `MacTerminalOverview`, `Sources/GlassTerminal/macOS/MacTerminalOverview.swift` | macOS only | **Since 2026-09-21 shows every open session** — its own tabs live, everything else as `GlassSessionCard` — browsed as one row (`MacOverviewItem`) |
| **Spatial grid and carousel** (3D rotation, ±1 card rendered) | `VisionTerminalWorkgroupView.spatialOverview`, `:730` | visionOS only | Same scope: one workgroup |
| **"Only fresh output may steal selection"** | `MacTerminalActivitySelection`, `MacTerminalOverview.swift:471` | macOS only, but pure and portable | A live gallery wants this; the session gallery does not use it yet |
| **Idle-hiding policy for overview chrome** | `MacOverviewIdlePolicy`, same file | macOS only, pure | |
| **Running-workgroup card grid** | `TerminalWorkgroupsView.swift:414` | macOS only | A *third* card treatment (see drift below) |
| **Cross-capability session list and gallery** | `GlassOpenSession`, `GlassActiveConnections` (Active, D33; it replaced `GlassSessionSwitcher` on 2026-09-21), `GlassSessionGallery`, `Sources/GlassShell/` | Everywhere | The gap all of the above left: they switch within one capability |
| **Desktop still image** | `GlassDesktopCapability.openSessions`, `Sources/GlassDesktop/GlassDesktopCapability.swift:139`: `snapshot` is the remote screen as it last arrived (`:153`, 8b2fb4d, 2026-10-13) | Anywhere a `GlassOpenSession` goes | *Corrected 2026-10-17: this row said desktops gave no snapshot.* Show All Windows uses it; the desktop's orb draws the same picture (`GlassDesktopCapability.picture(of:)`, `Sources/GlassDesktop/DesktopSessionView.swift:193`) |
| **Database / editor still image** | None from the capability, and none wanted for Active | — | On Vision Pro an orb whose face has no picture draws its window as it shrinks (`GlassWindowSizer.picture`, `Sources/GlassShell/GlassWindowSizer.swift:80`, 30d6ca6) |

**Known drift to settle when the gallery is next touched:** there are now six card treatments —
`MacTerminalOverview`'s, `VisionTerminalWorkgroupView.overviewCard`'s, the workgroups detail
grid's, `GlassSessionCard`, the Mac's Show All Windows tiles (`MacTerminalExposeView.swift`) and the
off-Mac overview's `GlassAllWindowsCard` (`Sources/GlassShell/GlassShowAllWindowsOverview.swift:172`).
They differ in corner radius, border and how selection is shown. One shell card should absorb the
others rather than a seventh being added.

## Contextual File items and Mac key owners (2026-09-25; keys rechecked 2026-10-12 and 2026-10-17)

One menu item per key, aimed by the focused window: the window publishes a focused scene value with
the item's title and action, or nothing (the item is then disabled, never borrowed from another
window). `MenuBarPlacementTests` holds a single-owner guard for ⌘N, ⌘S, ⌘W, ⌘O (and ⌥⌘O's absence),
⇧⌘E, ⌘F, ⌘G, ⇧⌘G, ⌥⌘G, ⌥⇧⌘G, ⌘T, ⇧⌘\, ⇧⌘P and ⌘K; ⇧⌘O, ⌥⌘E and ⌃⌘T have none yet.

| Key | Owner | What the window says |
|---|---|---|
| ⌘N | shell (`\.glassNewItem`) | New Host · New Terminal Window · New SQL Document · New Document |
| ⌘S | shell (`\.glassSaveItem`, D37) | Save… / Save (editor) · Save SQL Document… (database). Off the Mac the editor's toolbar Save takes ⌘S, inside `#if !os(macOS)` (e3ee5d7); the guard checks it stays off the Mac |
| ⌘W | `GlassCloseCommandRouter` (registered, never declared) | editor: the document, and the window with its last document unless a project is open |
| ⌘O | editor's Open… — files and folders; a folder opens as a project in its own window | runs its own panel from any window. ⌥⌘O (Open Project…) was removed 2026-10-08 (`50f6cae`) and is guarded as undeclared |
| ⇧⌘O | database's Open SQL Document… | |
| ⇧⌘E | editor's New Editor Window — opens on a blank document | |
| ⌥⌘E | database's Explain Plan (moved from ⇧⌘E, 2026-09-25) | |
| ⌘F / ⌘G / ⇧⌘G | shell's Edit ▸ Find ▸ Find… / Find Next / Find Previous (`\.glassFindItem`, `GlassShellFindCommands`, 2026-10-08) | published by the terminal workspace and, from 2026-10-22, the editor (its find bar was ⌥⌘F in the Editor menu, now removed); ⌘G was Terminal Grid |
| ⌥⌘G / ⌥⇧⌘G | terminal's Terminal Grid / Terminal Carousel (`MacWorkspaceCommands`, moved from ⌘G 2026-10-08) | |
| ⌘T | terminal (Mac workspace; visionOS platform commands) | |
| ⌃⌘T | terminal's New Basic Terminal Tab — a local shell outside tmux (`MacWorkspaceCommands`, 2026-10-12) | |
| ⇧⌘\ | terminal's Window ▸ Show All Windows (`GlassTerminalLibraryEntries`, 2026-10-08; Show All Terminals until 2026-10-13) | works from any window |
| ⇧⌘P / ⌘K | shell's Command Palette… (`GlassShellPaletteCommands`, 2026-10-13) | capabilities add entries through `GlassCommandPaletteSources` |
| ⌘+ / ⌘− / ⌘0 | per scene: the terminal's (`MacWorkspaceCommands`) and the editor's Text menu (`GlassEditorScenes`) | under Scale (D75) the terminal's size the window, not the font |

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


## One owner for a shared control; connections outlive their views (2026-10-13)

- **A control every window carries is one component in the shell, filled by capabilities.** As the ⚡ is
  (`GlassActiveConnections`): Show All Windows (`GlassShowAllWindows`: the terminal sets the action and draws the
  overlay, the composition root supplies `openSessions`, the button sits beside every ⚡), the window pinch
  (`GlassWindowPinch`, `GlassWindowPinchMonitor`, only on windows whose content does not pinch to zoom), and the
  Command Palette (`GlassShellPaletteCommands` owns ⇧⌘P and ⌘K; capabilities register entries through
  `GlassCommandPaletteSources`). Two capabilities each declaring a command gave the app menu two of it, and which one a
  key opened was SwiftUI's choice; a menu-bar test now holds each shared key to its one owner.
- **A connection belongs to its controller, never to a view's `.task`** (D70). A view asks
  (`startSSHPaneIfNeeded`), the controller holds the task, and only closing the pane or tab cancels it.
- **One rule per platform behaviour, in the shell, when two capabilities meet it:** `GlassLocalNetworkAccess` decides
  whether a failure could be the Local Network permission and words the advice, for the terminal and the database
  alike. It was two rules, and only the measured one was right.
- **Driver quirks are normalised where the driver is wrapped** (GlassDBKit): `PostgreSQLEngine.connectFailure`
  turns PostgresNIO's redacted `PSQLError` into the server's words, or into the network error MySQLNIO throws for the
  same failure, so `DatabaseConnectionFailure` words both engines with one set of cases.

## The system's ways in, one path (D72, 2026-10-13)

- **Every way in posts one request** (`GlassWidgetRequest`, in `GlassWidgetData`): widgets, Siri, Shortcuts,
  Spotlight, controls, Finder services, Open With, the Dock, `ssh://` links and Handoff. `GlassWidgetBridge` (App)
  carries each out with the capabilities. A request that needs an answer back, such as Send Files, awaits a service
  the app installs instead (`GlassAppServices`).
- **Windows open from outside any window through `GlassWindowOpener`**, which every kind of window registers. A
  connection first makes sure a Connections window exists (`ensureLibrary`), because its views run the
  capabilities' requests and prompts.
- **On the Mac, what is opened with the app and Handoff go to the app delegate** (`MacTerminalAppDelegate.openURLs`,
  `continueActivity`), never a scene's `onOpenURL`: SwiftUI opens a scene's window to deliver one.
- **Extensions in other processes hand off through the App Group** (`GlassExternalRequests`): they leave a request
  and open the app, which takes it as it comes forward. A request expires after a minute.
- **A dragged `NSUserActivity` makes a window where it is dropped** (`GlassServiceDrag`; `Transferable` cannot). The
  window group claims the activity with `handlesExternalEvents`.
- **What the system can name lives in the widget snapshot, as names only:** machines, services, workgroups and the
  database's saved queries (with their database's name, never their SQL). Something that must reach a window not
  yet open waits on its owner, briefly: a saved query waits in `DatabaseSessionManager.pendingQueries` for its
  connection's workspace, and expires after two minutes so a failed connect cannot surface it later.

## Favorites by kind, the overview everywhere, orbs, scale, previews, sidebars, models (D73–D78, 2026-10-13 to 17)

- **Favorites beyond machines (D73).** Machines keep their mark on the host (`GlassFavoritesPayload`, D49), which
  older builds read. Everything else is a `GlassFavorite` (`Sources/GlassShell/GlassShellFavoritesSync.swift:79`:
  a service, a project, a workgroup, or a folder = a Terminal service plus an absolute path) in a payload of its
  own under `shell-favorite-items-envelope-v1` (`:184`), which older builds neither read nor write. D49's merge
  (`GlassFavoriteItemsPayload.replaces`: newest change wins, a tie keeps the star); an unstar is dropped after 90
  days (`GlassShellModel.favoriteTombstoneLifetime`, `Sources/GlassShell/GlassShellModel.swift:1402`). The shell
  names and connects services; what a project, workgroup or folder is comes from the composition root
  (`GlassShellModel.describeFavorite`, `GlassShellModel.swift:90`, set at `App/GlassPowerToolsApp.swift:322`), and
  the sections reach the library through `GlassLibraryExtraSections` (GlassConnectionUI). A favourite whose thing is
  missing or not yet synced is hidden, its star kept.
- **Show All Windows is the shell's off the Mac (2026-10-14).** The overview (`GlassShowAllWindowsOverview`) is
  built from `GlassOpenSession`s: a card per tab (`GlassOpenSession.tabs`, `Sources/GlassShell/GlassOpenSession.swift:72`;
  a tab not yet connected `waitsToBeShown`), grouped by machine (`GlassShellModel.allWindowsMachines()`,
  `Sources/GlassShell/GlassActiveConnections.swift:79`), laid out by `GlassAllWindowsLayout`, pictures from
  `snapshot` retaken each second while shown, an AI agent's `mark` (`TerminalAgent`). iPhone and iPad show it as a
  pane over the window (`GlassAllWindowsPane`); Vision Pro as a `Window` scene of its own
  (`GlassAllWindowsWindow`, id `all-windows`) declared inside every capability's bootstrap, so a chosen card works
  with no Connections window open. The Mac's overlay stays the terminal's (`GlassShowAllWindows.toggle`).
- **Sessions into an existing window (2026-10-15):** a capability lists its windows with room
  (`GlassCapability.tabGroups()`, `GlassTabGroup`) and opens running sessions into one
  (`openRunningSessions(_:inTabGroup:)`, `Sources/GlassShell/GlassCapability.swift:400`); Active's Open as Tab In
  and Open N as Tabs In use it. Both are requirements in the protocol body with defaults, per rule 53.
- **Vision Pro session orbs (D74).** One modifier on a session window's whole content,
  `glassSessionOrb(_:)` (`Sources/GlassShell/GlassSessionOrb.swift:119`), with a `GlassSessionOrbFace` the capability
  fills (title, symbol, picture, tabs as `GlassSessionOrbTab`, pulse, whether the bar shows the button), and
  `GlassSessionOrbButton` first in the bottom bar. The window itself becomes the orb, as Connections does (W39): its
  content stays laid out out of sight, and its size is asked of visionOS through `GlassWindowSizer` (moved out of
  the Connections probe). `GlassSessionOrbControl.isWindow` tells whatever holds a window's shape (the desktop's
  W38 lock) to wait until the window is back. Look effects are system hover effects only, in shared
  `HoverEffectGroup`s, pictures and names `.followsGroup` (`GlassSessionOrb.swift:241`): the app is never told
  where a person looks. Tabs on a ring, at most 12 (`GlassOrbRingLayout`); `glassHiddenWhileOrb()` takes the
  terminal's tab ornament away meanwhile.
- **Scale draws, it never changes the font (D75).** The engine's view sits in a scaling container — the Mac's
  `MacTerminalScaleView` (bounds scaled) and, on iOS and visionOS, `TerminalHardwareKeyContainerView`'s
  always-present scaler (a transform), in `Sources/GlassTerminalEmulator/SwiftTermScale.swift` and
  `SwiftTermHostView.swift` — and the host hears only the kept grid (`SwiftTermScaledGrid`). The choice is
  `TerminalWindowSettings.whenResized` (synced, This Window override); `TerminalScaling` and `TerminalScaleToggle`
  live in `Sources/GlassTerminal/TerminalResizeBehavior.swift`. The desktop's shape lock moved to the shell for
  both: `GlassWindowAspectLock` and its tested math `GlassWindowAspect`
  (`Sources/GlassShell/GlassWindowAspectLock.swift:42`); `DesktopWindowAspect` keeps only the desktop's chrome and
  minimum.
- **A capability that shows another's view gets it from the composition root (D76).** The terminal does not import
  GlassEditor: its hover preview is `GlassTerminalRuntime.filePreview`
  (`Sources/GlassTerminal/GlassTerminalCapability.swift:146`), set to `GlassEditorQuickPreview` at
  `App/GlassPowerToolsApp.swift:371`. What a file is comes from GlassEditorCore, which both import:
  `GlassEditorFileKind`, decided from the bytes (`Sources/GlassEditorCore/Document/FileKind.swift:23`). The pointer
  is watched by `MacTerminalPathPreviewer` (GlassTerminalEmulator) through a local `NSEvent` monitor, because
  SwiftTerm's `mouseMoved` and `keyDown` are `public`, not `open`; a remote file comes over the pane's own SSH
  connection (`TerminalRemotePreview`, ≤ 32 MB, removed on close); links and paths are found once for the menu
  and the previewer (`TerminalLinkLookup`, `TerminalLinkTarget`).
- **One 3D viewer (D78):** `GlassModelView` (`Sources/GlassEditor/GlassModelView.swift:33`), used by the editor's
  viewer, Files through it, and the Mac hover preview. A model is `.model3D` by its bytes; `GlassModelFile`
  (`Sources/GlassEditorCore/Document/ModelFile.swift:13`) handles links, a misnamed model's extension and text
  layers. A terminal's model link is the terminal's (`Sources/GlassTerminal/TerminalModelLinks.swift`: after the
  link confirmation, ≤ 512 MB, kept only if its bytes are a model's, in Caches, cleared after a week).
- **The app moves a window for its sidebar (D77, Mac).** `GlassAdditiveSidebars`
  (`Sources/GlassShell/GlassAdditiveSidebars.swift:37`) finds SwiftUI's split items in the window's views, sets
  each to `.preferResizingSiblingsWithFixedSplitView` so AppKit leaves the window alone, observes `isCollapsed`,
  and animates the window's frame by the sidebar's width toward its side (`windowFrame`), following the net state;
  it posts `willResizeWindow` so the column beside it holds its width meanwhile (`MacWorkspaceView.holdTerminalWidth`).
  The terminal's reader decides when it is off — the sidebar a window opens with, the overview, full screen
  (`MacTerminalWindowReader.Coordinator.keepSidebarsAdditive`, `Sources/GlassTerminal/macOS/MacTerminalWindowPolicy.swift:132`).
  The window's minimum sits on the terminal's column, not the whole content (a whole-content minimum fought the
  growing). Each move is logged (`com.glasspowertools` / `sidebar`). Shared, for other windows if wanted; only the
  Mac terminal window uses it. An exception to rule 62, recorded there.
- **The titlebar material and the sidebar's edge.** `GlassTitlebarMaterialView`
  (`Sources/GlassConnectionUI/GlassWindowChrome.swift:7`) follows the sidebar's edge but holds it from KVO's
  `.prior` notice to the last (`:66`), because AppKit draws the window with the sidebar laid out at full width
  before it slides it in. `showsSidebarEdge` (`:25`) off hides the chrome's hairline and makes AppKit's divider
  transparent, still draggable; the terminal window turns it off (`MacTerminalWindowPolicy.swift:347`); the
  database and desktop windows keep the line.
- **A drop or paste is never turned away in silence (2026-10-16).** The newest paste or drop takes a pending
  review's place, `insertDroppedText` reports what became of the text, and the Mac pane logs each step
  (`sh.glas` / `terminal-drop`) and beeps when nothing was typed (`Tests/GlassTerminalTests/TerminalDropTypingTests.swift`).

## What a person removes, and what closing loses (D79, D80, 2026-10-17)

- **The sync's merge revives only what a merge lost.** `GlassCatalogMerge.reconcile`'s second pass
  (`Sources/GlassShell/GlassCatalogSync.swift`) skips a service any tombstone names (`deleteHost` leaves its services
  on the tombstone; a fold moves them out first) and revives only from a record whose final copy is a tombstone (Remove
  Service leaves the record live). A new way of removing something must leave the same trace, or the merge will bring
  it back.
- **A session says what ending it would lose.** `GlassOpenSession.unsavedChanges` (`Sources/GlassShell/GlassOpenSession.swift`)
  and `requestClose(asking:)`; every place that ends a session asks through `glassAskingBeforeClosing` (Active's row,
  All Windows' cards, the Mac's overview). The editor answers it; a capability with nothing to lose leaves it nil.
- **A SwiftUI window that must ask before it closes** uses `GlassWindowCloseGate`
  (`Sources/GlassConnectionUI/GlassWindowCloseGate.swift`): it takes the window's delegate and forwards everything
  else to SwiftUI's. The editor's Mac window walks its unsaved documents through the document's own question, then
  closes itself; a quit asks through `MacTerminalAppDelegate.unsavedDocumentNames`, set by the composition root.
  Where a window can't ask (iPad, Vision Pro), the editor keeps a workspace with changes (`GlassEditorRuntime.forget`).
- **Each device's own counts, merged per device (D81).** `GlassUsagePayload` (`Sources/GlassShell/GlassShellUsageSync.swift`)
  is one key-value-store payload with an entry per device keyed by its writer id; a device pushes only its own entry
  and `converged` keeps the newest per device. The overview reads `GlassShellModel.usageByDevice` (this device from its
  history, the others mapped to this library's host ids). The same shape suits anything per-device that every device
  should see.
- **A card drawn as its window paints (2026-10-17).** `GlassOpenSession.backdrop` carries what a session's window paints
  behind it where the window has an opaque page (iPhone, iPad); All Windows draws it and takes its light or dark.

## tmux in control mode, looks, SQL, This Mac, time in use, the orb dock, environments (D83–D89, 2026-10-19 to 27)

- **A terminal kept in tmux is a control-mode client (D83).** `TmuxControlClient`
  (`Sources/GlassTerminalEmulator/TmuxControlClient.swift`) reads tmux's `%output` and feeds the emulator, which keeps
  the whole history, the program's alternate screen and its mouse. Remote tabs run `tmux -CC` on the SSH PTY; the Mac's
  own panes run `-C` on pipes (`Sources/GlassTerminal/macOS/MacLocalTmux.swift`). One session, one window, one pane per
  tab; the session still outlives the connection.
- **Looks are drawn behind the text, never over it (D84).** `TerminalLooks` and `TerminalWindowLook`
  (`Sources/GlassTerminal/`) are SwiftUI behind a transparent terminal: motion follows the terminal's activity and stops
  under Reduce Motion, Low Power Mode and in hidden windows; a readability guard keeps contrast; the window keeps its
  glass.
- **SQL from a terminal (D85).** `TerminalSQLDetector` (`Sources/GlassTerminalEmulator/TerminalSQLDetector.swift`) takes
  the statement under a Mac right-click (`MacTerminalContextMenu`); the destinations are the machine's databases and
  those reached through its server; the database capability opens it unrun, with the table it names opened beside it.
- **This Mac knows its own record (D86).** `GlassThisMac` (`Sources/GlassShell/GlassThisMac.swift`) keeps a device-local
  link, never synced, made by the pinned host key, offered by address, or set by hand; the library then shows one row and
  the record's Terminal opens a local shell.
- **Time in use (D87).** Capabilities report a minute with input or output as `GlassUsageActivity`
  (`Sources/GlassShell/GlassOpenSession.swift`); the shell keeps 90 days per device and syncs them per day in
  `GlassUsagePayload`, D81's one-entry-per-device shape.
- **The orb dock (D88).** `GlassOrbDockModel` (`Sources/GlassShell/GlassOrbDock.swift`, one per app) holds the docked
  windows: visionOS carries no window, so a window docks by closing, its sessions kept, and comes back through the
  scene's `defaultWindowPlacement` (`glassComesBackByOrbDock`), placed by the dock's `returning` queue: above a wide
  dock, `.leading`/`.trailing` of a tall one. Its order is `GlassOrbDockOrder` (kept by id). Its geometry is pure and
  tested apart from the view (`GlassOrbDockGeometry.swift`): `GlassOrbFlow` lays the orbs in wrapping rows and
  `snapped` gives the dock's size around them within the size the person gave it; `landing(at:)` places a carried orb;
  `GlassOrbNameSide` turns a name toward the room; `GlassOrbDockSide` picks the side; `GlassOrbDockMenu` fills
  Connections' hold menu. The size given is kept (`sizeKey`) and opened at (`glassOrbDockOpensAtItsSize`); the dock
  asks for its snapped size through `GlassWindowSizer` once `isInteractivelyResizing` is false. The carry is UIKit's
  long press on the dock's window (`GlassOrbCarryProbe`; visionOS has no `UIGestureRecognizerRepresentable`), begun
  only on an orb, so the scroll view keeps every quick drag. Connections there is a `Menu` whose primary action is the
  pinch (a `.contextMenu` on its button never opened). Head direction comes only from Focus Mode's
  `GlassHeadTracker` (`GlassHeadTracker.current`; a new ARKit session and provider each run); otherwise the side is the
  setting (`tallSideKey`). Docked windows' pictures are kept in Caches ("Orb Pictures", complete protection) until they
  leave the dock. Its look is a `GlassWindowOverrides` over Appearance, drawn as every window's, and edited with the
  same rows as This Window (`GlassWindowLayerControls`).
- **Windows come back as they were left (D88, 2026-10-26).** The terminal's reopen record (W15) carries `asOrb`, read
  from the dock's model when the list is written: a docked window is put in the dock and its window not opened; a
  standing orb opens as its orb (`opensAsOrb`, taken by the window's `standAsOrb`). Connections keeps
  `holdsConnections` on the device and, at launch, waits for the reopen to say it is done (`lastRunCameBack`) before
  going back into the dock — and stays open while it shows anything, since the reopen's questions are asked on it.
- **Focus Mode environments (D89).** `FocusEnvironmentLibrary` (`Sources/GlassTerminal/FocusEnvironments.swift`) lists
  the built-ins (drawn in code, `FocusEnvironmentArt`) and the person's files in the app's iCloud Drive folder; each 3D
  file's fit lives beside it in the container, outside Documents ("Environment Fits"). What a fit means is pure and
  tested (`FocusRoomFit`, `FocusRoomPose`, `FocusWorldPose`, `FocusLocomotion` in `FocusRoomFit.swift`); moving about
  moves the world, never the person (`FocusWalking`), with the numbers of the owner's Mirador gallery.
- **Test switches stand in for what the simulator's runner cannot do**, DEBUG and `--ui-testing` only: `--demo-reopen`
  (a last run's window), `--demo-dock-resize` (a hand on the dock's corner), `--demo-dock-carry` (a hold carrying the
  last orb onto the first), the `orb-dock-last-side` marker (the side a window was sent to, since the runner reads each
  window's frame in its own space), `--ui-testing-seed-hosts alpha:ssh=<uuid>`
  (a seeded service with a known id), `--demo-try-out`, `--demo-teleport`. A UI test that must cross a relaunch launches
  again under the same `--ui-testing <uuid>`, whose store is kept.
