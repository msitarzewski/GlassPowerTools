# Active, and the ⚡ — 2026-09-21

*"We can simplify the mess out of the open connections problem on every app deployment target.
Add 'Active' to the Library of Connections: All, Favorites, Recent, Active. Then make that an
icon in the main toolbar, app wide. Every top toolbar gets the lightning bolt."* And on the
switcher built that morning: *"Replace, yes."* Workgroups stays as it is; Active groups by
machine with a disclosure, like the Files list.

## The idea, and why it is simpler

The library already knew every machine. It only lacked which ones were live. The morning's
switcher answered that with a fifth surface — a Sessions button on every session's chrome, a
sheet, a gallery. Active answers it with a **row in the sidebar** and one control that means
"take me there". A row under a machine is a live session, and choosing it **switches to** the
session rather than opening a second one — on the Mac the window comes forward, on a phone the
root swaps. That is what makes the library the switcher instead of a list beside one.

## What changed

| File | Change |
|---|---|
| `Sources/GlassShell/GlassActiveConnections.swift` | **New.** `GlassShellModel.activeMachines()` (sessions grouped by the machine that owns their endpoint, or the editor's project machine, else "Elsewhere"), `activeSessionCount()`, `showActiveConnections()`, `activeConnectionsPanel()`; `GlassActiveConnectionsList` (a `DisclosureGroup` per machine, open by default; rows switch, swipe closes); `GlassActiveConnectionsToolbarModifier` and `GlassActiveConnectionsButton` — the ⚡ |
| `Sources/GlassShell/GlassOpenSession.swift` | A session says where it belongs: `endpointIDs` (its services) or `hostID` (the editor). The Sessions control and the switcher sheet **deleted** |
| `Sources/GlassShell/GlassSessionGallery.swift` | The gallery sheet **deleted**; `GlassGalleryLayout` and `GlassSessionCard` stay — the Mac's Terminal Overview draws with them |
| `Sources/GlassShell/GlassShellModel.swift` | `panelToShow`, the `hostToShow`-shaped route the ⚡ uses |
| `Sources/GlassConnectionUI/GlassLibraryPanel.swift`, `GlassLibraryCategories.swift`, `GlassLibraryComponents.swift`, `GlassConnectionLibrary.swift` | A panel whose `sectionTitle` is `"Library"` is drawn **inside** the Library section after All, Favorites and Recent; `panelToOpen(_:)` lets something outside open a panel |
| `Sources/GlassShell/GlassShellLibraryView.swift` | Registers Active first, honours `panelToShow`, and carries the ⚡ in its own toolbar — the library is a top toolbar too |
| Terminal, database, desktop, editor runtimes | `showActiveConnections: GlassShowActiveConnections?`, one closure from the composition root for all four |
| `VisionTerminalWorkgroupView`, `DatabaseWorkspaceView`, `GlassEditorWorkspaceView`, `GlassDesktopScenes` | `.glassSessionsToolbar(…)` → `.glassActiveConnectionsToolbar(show:dismissCurrent:)`, each with the dismissal its chrome already had |
| `App/GlassPowerToolsApp.swift` | Wires the four runtimes to `model.showActiveConnections()` |
| `Tests/GlassShellTests/GlassActiveConnectionsTests.swift` | Grouping by machine, the editor under its project's machine, orphans under Elsewhere, nil for nothing, the bolt's request and the panel's seat |
| `UITests/EditorOnIPhoneUITests.swift` | The switcher walkthrough became the bolt walkthrough |

**Workgroups is untouched.** It is the terminal's own idea of a saved multi-machine layout and
stays in its own section; a live workgroup is one row under each machine it has a terminal on.

## The ⚡'s one behaviour on three platforms

`GlassWindowPresentation.canOpenWindows` decides: with windows, `openWindow(id: "main")` then
open Active; without, the session's own dismissal then open Active. The same test that says "the
Sessions control is not drawn with nothing else open" no longer applies — the bolt is drawn
always, because Active with nothing in it is still the right answer to "what is live?".
