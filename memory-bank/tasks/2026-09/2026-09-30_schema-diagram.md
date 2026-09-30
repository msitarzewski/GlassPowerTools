# Schema diagram — 2026-09-30

**State:** DOCS — built and in use on the Mac (0.4.262, owner: "Holy crap, nice work"); the headset's volume awaits the owner's look. Owner: coordinating agent. Authorized by the owner (2026-09-30): "2 please.
In 3D, in space on VP if possible. … this was a major miss and is an expected feature. … design and
plan it, then build it." Decision D43. Local commits only; nothing pushed.

## What it is

A live diagram of one database: every table as a card (name, columns, types, key marks), and a
connector for every foreign key from the referencing columns to the referenced ones. Built from the
live connection each time it opens, with Refresh. Nothing in the app or in glassdb did this.

- **Mac, iPad, iPhone:** a 2D canvas. Cards are laid out automatically, can be dragged, the canvas
  pans and zooms, a selected table lights up its relationships and dims the rest, and Open Table
  opens it in a workspace. Keys Only shrinks every card to its key columns.
- **Vision Pro:** a volume — the same cards as SwiftUI attachments laid out in three dimensions,
  facing the viewer (billboard), with the relationships as lines between them. Turn it with the
  controls below it or by dragging its back; select a card to light up its relationships.

## Reuse

- Schema reads: `DatabaseConnection.tables/columns/foreignKeys` (`Sources/GlassDBKit/DatabaseProtocol.swift:154-158`),
  implemented and tested for MySQL, PostgreSQL and SQLite. Per table, so a load is 1 + 2n queries,
  reported as progress; a bulk information-schema read is a later optimisation, not a new owner.
- Window pattern: `database-results` (`GlassDatabaseScenes.swift`), a `UUID`-keyed group resolving
  a registered request through `DatabaseSessionManager`.
- Opening a table: `DatabaseWorkspaceWindowRequest.additional(sessionID:initialSelection:)` +
  `registerWorkspace`, as "Open in New Window" does (`SchemaBrowserView.swift`).
- Phone: no windows (`GlassWindowPresentation.canOpenWindows`), so a sheet.

## Parts

| File | Responsibility |
|---|---|
| `GlassDatabase/SchemaDiagram.swift` | Model (tables, columns, relationships) and the loader over `DatabaseConnection` |
| `GlassDatabase/SchemaDiagramLayout.swift` | Deterministic force-directed layout, 2D and 3D; unconnected tables in rows; overlap removal |
| `GlassDatabase/SchemaDiagramView.swift` | The 2D canvas, the card, the toolbar |
| `GlassDatabase/SchemaDiagramVolume.swift` | visionOS: the RealityKit volume |
| `GlassDatabaseScenes.swift` | `database-diagram` window (volumetric on visionOS) |
| `SchemaBrowserView.swift` | Entry points: Show Diagram on a database, Show in Diagram on a table |

Edge cases: a key to a table outside the diagram is counted, not drawn; SQLite's key to an implicit
primary key has an empty referenced column and resolves to the target's primary key; composite keys
are one relationship; self-references loop on the card's own side; over 300 tables the diagram shows
the first 300 by name and says so.

## Validation plan

- Unit: loader against an in-memory SQLite schema (composite, self-reference, implicit-PK, a key to
  a missing table); layout determinism, no card overlap, related tables nearer than unrelated.
- Live: the loader against the scratch VM's MySQL and PostgreSQL.
- Builds on all three platforms; the headset's volume judged by the owner.

## Built (2026-09-30, uncommitted)

`SchemaDiagram.swift` (model + loader), `SchemaDiagramLayout.swift`, `SchemaDiagramView.swift`
(document, card, 2D canvas, presenter), `SchemaDiagramVolume.swift` (visionOS), the
`database-diagram` window in `GlassDatabaseScenes.swift`, Show Diagram / Show in Diagram in
`SchemaBrowserView.swift`, the registry in `DatabaseSessionManager`, `site/help/database-schema-diagram.md`.
Demo mode: `--demo-open diagram`; the demo shop gained eight empty tables with real keys (the four
seeded tables are unchanged, so the database screenshots are too).

**Found on the way:** SQLite's key to an implicit primary key (`REFERENCES customers`) reached the
app as a column named "NULL" — shown in the Foreign Keys view and used by Follow Reference. The
adapter now resolves it to the target's primary key (`SQLiteAdapter.foreignKeys`).

**Layout corrections from the first captures:** the volume came out a one-card-wide column (box
separation pushed along the thinnest axis) → centre-distance spreading, principal-axis rotation so
the widest spread faces the viewer, depth at least a third of the width; the plane was spread over
2,300 pt → tighter ideal distance and stronger gravity; the canvas opens fitted, scrolled to the
selection; stacked cards join with a bracket, not an S.

## Validation

- Unit (`SchemaDiagramTests`, 10): the shop schema with composite, self and implicit keys; a key to
  a missing table; determinism; no overlap (plane) / no crowding (volume); the volume spread in all
  three directions; related tables nearer; keyless tables in rows. All pass.
- Live, scratch VM: `schemaDiagramOnRealServers` on MySQL and PostgreSQL — pass.
- Builds: the app, Release, visionOS, macOS and iOS — pass. GlassDatabaseTests 301/301.
- Seen: visionOS simulator volume and iPad simulator canvas (demo shop). Not yet seen: the physical
  headset, the Mac window, the iPhone sheet.
- Full suite on a locked screen: two desktop relaunch tests fail with EPERM from mktemp (the known
  data-protection-under-lock limit); they passed unlocked this morning. Rerun unlocked.

## Mac round with the owner (0.4.256–0.4.262)

- ⌘-scroll zooms about the pointer (`MacCommandScrollZoom`, a local scroll-wheel monitor); pinch
  and the buttons zoom about their point too. Zoom is previewed as a scale of the finished picture
  and committed once input pauses for 150 ms (the owner asked for a debounce).
- Zoom to Fit really fits (it stopped at the 35% "readable" floor meant only for opening).
- Pan: press-drag the empty canvas, or ⌥-Space-drag anywhere; the grab hand for every drag. Pans
  and zooms clamp to the scroll view's real limits (the canvas rests at y ≈ -52 under the toolbar;
  clamping at 0 made pans jump).
- Transparency: `DatabaseWorkspaceBackground` + `MacDatabaseWorkspaceWindowReader`, the workspace's
  own glass, reused (the modifier lost its `private`).
- View Diagram in the database overview beside Set as Active and SQL Editor.
- Card centring used a padded marker whose frame spanned from the corner; now a 1-pt view placed by
  `position`.
- The sidebar follows the displayed tab: a table shown from anywhere is disclosed and scrolled to.
  A second `.id` on a list row drew it twice on the Mac; the `ForEach` identity is the scroll target.
