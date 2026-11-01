# Databases and desktops in Workgroups (B-F40, 2026-11-01)

**Ask (the owner):** "finish the duo, then workgroups. Remember that reuse is essential. DRY, and KISS. Proceed."
B-F40 (backlog, 2026-10-12): terminal, database and desktop together in Workgroups, AGENTS.md's differentiator;
workgroups were terminal-only (`GlassTerminalWorkgroup`, `LayoutPreset.sessionIntents`).
**Status:** built 2026-11-01, uncommitted. Decision D94.

## Reuse
- Every way a saved workgroup opens (Connections ▸ Workgroups, Favorites, the Mac's palette, Siri and Shortcuts)
  reaches one function, `TerminalConnectFlow.openWorkgroup` (mapped by a search agent from source, each path
  cited). The services open there, before the platform split, so every path gets them and none is touched.
- A service opens through the shell's own Connect (`GlassShellModel.connect(hostID:endpointID:)`), reached as
  Favorites reaches it: `favoriteDescription(.service(endpoint))`, whose `open` is Connect and whose title,
  subtitle and symbol name it. The terminal module gets two closures from the composition root (as `openSQL`):
  `workgroupServiceChoices` (the library's non-SSH services) and `describeService`. No new connect path, no
  new naming.
- One open already is shown (`GlassOpenSession.activate`, found by its `endpointIDs` in `openSessions`), never
  connected a second time, as the workgroup's terminals are (W4b).
- Stored as `LayoutPreset.services: [UUID]`, endpoint IDs as `SessionIntent.serverID` stores a terminal's.

## Built
- Model (`Models.swift`): `services`, at most 16; a workgroup needs a terminal, a database or a desktop (was: a
  terminal). Written only when there are any, read with `try?` (unreadable ones cost the workgroup them, never the
  workgroup), no schema change, as `windowSettings`: an older build reads the terminals, skips a workgroup with
  none, and drops the services only if it saves the workgroup again. Sync (D51) carries them unchanged: it moves
  each workgroup's encoded bytes.
- Opening (`GlassTerminalRuntime.openServices(of:)`, `TerminalConnectFlow.openWorkgroup`): services first, then
  the terminals, which on a phone take the screen; a workgroup of services alone opens no terminal window. One that
  has left the library is said in the workgroup's alert ("… no longer in your library. Edit the workgroup to
  remove it.").
- Editor (`WorkgroupEditorView`): "Databases and Desktops · n" under the tabs, each row as Favorites names it with
  a Remove button, and Add Database or Desktop (a menu of the library's, those not added). Validation: "Add a
  terminal tab, a database or a desktop." Replacing a workgroup from a Mac window keeps its services unless the
  draft names its own. Context `edit` and `duplicate` carry them.
- Shown: the workgroup's row and detail (`TerminalWorkgroupsView.contents`), a "Databases and Desktops" section
  in the detail, Favorites' subtitle (`GlassTerminalWorkgroup.summary`: "2 terminals · 1 database or desktop").

## Not built (KISS)
- A desktop or database inside the terminal window's grid and carousel (glassDT's grid contract in B-F40's text):
  each opens in its own window, as Connect opens it; on Vision Pro that is the windows around you.
- On an iPhone Duo held like a book, a service on the other page: everything opens on the page in use, and the
  rest wait in Active.
- Saving open databases and desktops from Active or a window as a workgroup; Shortcuts' workgroup entity still
  counts terminals only.

## Validation
- `WorkgroupServicesTests` (4): validity, saved form, two-device sync, opening (shown when open, connected
  otherwise, gone counted). Each seen failing with its piece broken (validity back to terminals only, the key not
  written, an open one connected again), then restored and compared.
- `WorkgroupServicesUITests.testAWorkgroupOpensItsDatabase` (iPhone 18 Pro Max simulator): a workgroup made in the
  editor with alpha's database and no terminals, saved ("Data, 1 database or desktop"), its detail listing it,
  opened: the database is asked to connect alpha's database and answers as Connect does for a seeded service
  without database settings ("Database on alpha has no saved database configuration…"). Passes; fails with the
  services left unopened in `openWorkgroup`.
- Found on the way: the menu read "Database on alpha, Database on alpha". Favorites named a service by its own name
  when that was the setup's default "Kind on Host", then again as kind and machine. Four copies of the rule
  (Favorites, Connect's text, the palette, Active's launcher) are one now, `GlassShellHost.namesOnlyByDefault`
  (test in `GlassShellDetailTextTests`, failing without "Kind on Host").
- Also seen: the workgroup detail's container identifier overrides its Edit and Open Workgroup buttons' own
  (`connection-library-detail-workgroup-…` on all three); no test used them, left as is.
