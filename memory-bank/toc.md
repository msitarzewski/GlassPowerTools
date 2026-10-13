# Glass Power Tools Memory Bank

Created 2026-09-10; curated 2026-09-27 for publication. Aggregate owner: the coordinating agent.

Read [AGENTS.md](../AGENTS.md), then [active context](activeContext.md) and [progress](progress.md).
All four capabilities and the shell are built; the project is in release preparation. The three
source applications are obsolete and no longer compile.

| Note | Purpose |
|---|---|
| [Project brief](projectbrief.md) | Scope, the decision to merge, and what the product is |
| [Product context](productContext.md) | The host-centric model and the interface it implies |
| [System patterns](systemPatterns.md) | Intended module boundaries and what they replace |
| [Technical context](techContext.md) | Measured sizes, dependencies, targets and identities |
| [Active context](activeContext.md) | Current state, authorization, the release checklist and open questions |
| [Progress](progress.md) | What is built, how each part is verified, what is not verified, and what is open |
| [Project rules](projectRules.md) | Rules specific to this merge |
| [Decisions](decisions.md) | Decisions with status and provenance |
| [Merge plan](tasks/2026-09/2026-09-10_merge-plan.md) | The staged plan, its risks and open questions |
| [Stage 1 — shell](tasks/2026-09/2026-09-10_stage-1-shell.md) | The detailed plan for the first build: pre-steps, reuse, breakdown, decisions |
| [Stage 2/3 groundwork](tasks/2026-09/2026-09-10_stage-2-3-groundwork.md) | Dependency maps of glas.sh and glassdb, measured pin skew, the one-module carve proposal |
| [Stage 2 — SSH engine and terminal](tasks/2026-09/2026-09-10_stage-2-ssh-terminal.md) | Module layout, engine API contract, integration contract, ownership, parity checklist |
| [Stage 2 close-out review](tasks/2026-09/2026-09-10_stage-2-closeout-review.md) | Read-only review: parity reachability, TODO/stub scan, security spot-check, dead code; cleanup queued to W4 |
| [Shell tags](tasks/2026-09/2026-09-10_shell-tags.md) | W5: shared `GlassTagField` token editor and the system-wide tag vocabulary replacing comma-separated entry |
| [Host address](tasks/2026-09/2026-09-10_host-address.md) | W6: the machine address lives on the host record; services inherit it; capability hooks and terminal form changes |
| [Service setup and key window](tasks/2026-09/2026-09-11_service-setup-and-key-window.md) | W7: address gate before service setup, Add SSH Key sheet per rule 15, Services row overflow |
| [Row connect and icons](tasks/2026-09/2026-09-11_row-connect-and-icons.md) | W9: wordless split connect control, row cleanup, Heroicons circle-stack, Delete relocation, detail action bar |
| [App icon](tasks/2026-09/2026-09-11_app-icon.md) | Icon Composer document, per-appearance artwork, what the CLI can and cannot verify |
| [Stage 3 plan](tasks/2026-09/2026-09-12_stage-3-database-plan.md) | The Database capability, planned from a full survey of glassdb; supersedes the 2026-09-10 draft |
| [Stage 3 — kit move](tasks/2026-09/2026-09-12_stage-3-kit-move.md) | The engine moved as `Sources/GlassDBKit` minus its tunnel manager; the swift-crypto conflict dissolved with it |
| [Stage 3 — floor sweep](tasks/2026-09/2026-09-12_stage-3-floor-sweep.md) | Exactly one API above the floor, at macOS 26.1 not 27.0; the floor stays 26.0 (D12) |
| [Stage 3 — shell forward](tasks/2026-09/2026-09-12_stage-3-shell-forward.md) | D7: a capability borrows the host's SSH forward without importing the one that owns it |
| [Stage 3 — the capability](tasks/2026-09/2026-09-12_stage-3-capability.md) | glassdb's app files as `Sources/GlassDatabase`; the Database tab; D14's trust prompt; D15's read-only guard; two PostgreSQL FK defects found live |
| [Stage 3 — VM databases](tasks/2026-09/2026-09-12_stage-3-vm-databases.md) | Real MySQL 8.4.11 and PostgreSQL 18.6; least-privilege users; **read this before grepping the error log** |
| [Stage 3 — the local host](tasks/2026-09/2026-09-12_stage-3-local-host.md) | D8: "This Mac" as a real host; connectAll picker-only; four corrections to the plan |
| [SSH forward: server-first bytes](tasks/2026-09/2026-09-12_ssh-forward-server-first.md) | A real defect every test passed. MySQL's greeting dropped before the channel was wrapped; three refuted hypotheses recorded |
| [SQL drafts](tasks/2026-09/2026-09-12_sql-drafts.md) | R1: durable per-connection drafts; query history's shape reused, its medium rejected |
| [Rows and audit](tasks/2026-09/2026-09-12_rows-and-audit.md) | R2–R4: deletion proven live, foreign keys failing closed, the audit viewer |
| [Certificate trust](tasks/2026-09/2026-09-12_certificate-trust.md) | R7/D13: CA-only as a named mode, proven at the capability level |
| [UI and validation from use](tasks/2026-09/2026-09-12_ui-and-validation.md) | Builds 0.3.56–0.3.67: canvas border, Paint Theme removed, service tabs, colour swatches, record-editor validation, the `tinyint` data-loss bug |
| [Stage 3 — database (superseded draft)](tasks/2026-09/2026-09-10_stage-3-database.md) | Predates the setup sheet, the draft contract and the address-on-the-host rule. **Superseded by the plan above** |
| [Stage 4 — desktop](tasks/2026-09/2026-09-10_stage-4-desktop.md) | glassDT engines and Core/UI moved; pairing machinery deleted; validation ledger |
| [Stage 3.5 — continuity](tasks/2026-09/2026-09-13_stage-3.5-continuity.md) | D18–D22: credentials and the host catalog travel; the device checklist no test can replace |
| [GlasSecretStore absorbed](tasks/2026-09/2026-09-13_secretstore-absorbed.md) | The package moved in-repo, and the host-trust defect that answering "should pins sync?" exposed (D23) |
| [visionOS design pass](tasks/2026-09/2026-09-13_visionos-design-pass.md) | Native HIG on the Glass language; the two places the app was painting over the platform; how to actually get a capture |
| [Test pollution](tasks/2026-09/2026-09-13_test-pollution.md) | UI tests wrote into the real saved-server list; where the Mac's store actually lives, and the abandoned defaults suites still to sweep |
| [Stage 4 — live hosts](tasks/2026-09/2026-09-14_stage-4-live-hosts.md) | The first real Windows RDP session, TigerVNC 1.15.0, and the Apple Screen Sharing result that closed two Stage 4.5 items |
| [Connections do not sync](tasks/2026-09/2026-09-14_connection-records-do-not-sync.md) | The diagnosis behind "CloudKit isn't working", three options, and the wrong first diagnosis kept in place |
| [D26 — keys first class](tasks/2026-09/2026-09-14_d26-keys-first-class.md) | Keys outlive connections and get their own manager; device-bound means absent elsewhere; publish redacts and apply re-attaches |
| [The remaining work](tasks/2026-09/2026-09-14_remaining-work-plan.md) | **The plan for everything left**: D26 stages 1–5, Stage 4 W3–W6, Stage 4.5, carried items, Stages 5–6, with reuse anchors and precise edits |
| [D27 and D28 planned](tasks/2026-09/2026-09-14_d27-d28-plan.md) | Every record-creating surface enumerated; the two live D27 targets, the unreferenced `RDPFileImporter`, and the normaliser that silently re-attaches a key |
| [Stage 5.2 — the editor and the family](tasks/2026-09/2026-09-16_editor-stage-5.2-plan.md) | The editor's seven corrections: the database's tree and tabs as the template, the library's toolbar, Projects as a Workgroups-style panel, and the remote reader last |
| [The editor, round two](tasks/2026-09/2026-09-17_editor-round-two.md) | Seven corrections from the 0.4.143 test pass: the whole tab clickable, the rule through the strip, the gear into Settings, Open that takes a folder, ⌘W on the tab, a remembered frame, language in the footer |
| [The gutter, Projects, and the editor's remote half](tasks/2026-09/2026-09-17_gutter-and-stage-c.md) | The gutter stops being an `NSRulerView`; Projects become a persisted, synced library panel and the editor's entry point on iOS and visionOS; stages C and D, one file-access seam for both machines, the verified remote write proven against a real server, and three windows that opened nothing on an iPhone |
| [The terminal configuration the Mac deleted](tasks/2026-09/2026-09-17_terminal-configuration-loss.md) | A service that synced without its settings: `replaceAll` reconciling the catalog to a stale in-memory list, why the desktop was unaffected, and the error message whose only working action was the destructive one |
| [The editor on a phone](tasks/2026-09/2026-09-17_editor-on-a-phone.md) | Four iPhone-only defects behind one report, none in the editor's text view, and the simulator walkthrough that found them — including the fixture traps that cost an evening |
| [Finding your way around on iOS](tasks/2026-09/2026-09-18_ios-navigation-plan.md) | **The plan, with A, B and C built**: opening a folder lands on its files, file browsing stops being modal, one header that says where you are (SFTP included), and a session switcher for a phone that has no way between open connections — plus everything carried |
| [The iOS round, day two](tasks/2026-09/2026-09-19_ios-round-two.md) | 0.4.177–0.4.184: the provisional tab, HTML, the keyboard, and the database's collapse to its sidebar — plus the typed-path regression and what Xcode 27.2 broke |
| [iPhone Duo](tasks/2026-09/2026-09-20_iphone-duo.md) | Ships 23 October: two sessions on one phone at last, a size class that changes on a hinge, and the window gate that may refuse the one iPhone where a second window works |
| [Charts on macOS 27.2](tasks/2026-09/2026-09-21_charts-on-macos-27-2.md) | The overview's names overlapped their bars after the OS beta moved a categorical axis label to the band's top edge; names are annotations now, found with a headless `ImageRenderer` probe (`Tools/ChartProbe`) |
| [Duplicated services](tasks/2026-09/2026-09-21_duplicate-services.md) | Eleven Linux server records on the phone, two fully configured, grouped into one row showing the union; the two-part fix, the second being the D26 migration |
| [Active and the ⚡](tasks/2026-09/2026-09-21_active-and-the-bolt.md) | The library's fourth category and the one control in every toolbar that reaches it; the morning's switcher replaced (D33) |
| [Disconnect in the workspace](tasks/2026-09/2026-09-22_disconnect-in-the-workspace.md) | Closing the last database workspace window ends the session; the phone keeps ⋯ Disconnect |
| [Desktop window and login size](tasks/2026-09/2026-09-22_desktop-window-and-login-size.md) | The thumbnail window, and following a server that resizes itself after login |
| [Viewers and Preview](tasks/2026-09/2026-09-23_viewers-and-preview.md) | D35: images and media as themselves; Markdown with Mermaid, HTML, SVG, CSV previews; the large-file fixes |
| [Text engine research](tasks/2026-09/2026-09-23_text-engine-research.md) | The state of the art in Mac editors, measured; D36's TextKit 1 backend |
| [The grid's scroll cost](tasks/2026-09/2026-09-23_grid-scroll-cost.md) | The database grid measured at 120 Hz; option 1 partly built |
| [Editor: Save, ⇧⌘E, ⌘W](tasks/2026-09/2026-09-25_editor-save-and-new-window.md) | D37's shell-owned ⌘S, the Mac Save panel, a blank document on ⇧⌘E, ⌘W closing the window |
| [Documentation and site plan](tasks/2026-09/2026-09-25_documentation-and-site-plan.md) | The vision → audit → help → sites plan; Anomalous's help and AudioPaper's site as models; glasspowertools.com |
| [Licensing and acknowledgements](tasks/2026-09/2026-09-26_licensing-and-acknowledgements.md) | Corrected notices, the generated licence folder and in-app Acknowledgements, the Mermaid licence gate |
| [Dependencies and the audit's fixes](tasks/2026-09/2026-09-27_release-audit-fixes.md) | What moved and what is blocked upstream; each public-release audit finding, its fix and its proof |
| [Help, site and updates](tasks/2026-09/2026-09-27_help-site-and-updates.md) | 35 help pages audited from the code, glasspowertools.com and its generator, Sparkle and the release script, and the defects the audit found |
| [September tasks](tasks/2026-09/README.md) | Monthly index |
| [tmux sessions (D44)](tasks/2026-10/2026-10-01_tmux-sessions.md) | Per-server tmux, reattach, Active's running sessions, the availability check and one-time offer |
| [iPhone landscape and AI fixes](tasks/2026-10/2026-10-04_iphone-landscape-and-ai-fixes.md) | The landscape terminal, AI answers that are advice, menu icons, tests that wait on events |
| [A database through another machine (D45)](tasks/2026-10/2026-10-05_db-through-another-machine.md) | Reaching a database through another host's SSH, and a database address through its own machine |
| [RDP session bandwidth](tasks/2026-10/2026-10-05_rdp-session-bandwidth.md) | 0 bytes reported to Windows; fixed and verified live |
| [Vision Pro input and the scroll edge](tasks/2026-10/2026-10-06_visionos-input-and-scroll-edge.md) | Trackpad scrolling, the bolt on the right, pinch-pose measurements for D46 |
| [Terminal tabs and local tmux (D47)](tasks/2026-10/2026-10-07_terminal-tabs-and-local-tmux.md) | Tab names, rename, the activity wave, drags between windows, local terminals in tmux, favourites and workgroups sync |
| [Plan: find, tabs, tmux names, workgroups, editor](tasks/2026-10/2026-10-08_find-tabs-tmux-workgroups-editor-plan.md) | Eight owner reports, root causes and five workstreams (W1–W14) |
| [Apple Screen Sharing](tasks/2026-10/2026-10-11_apple-screen-sharing-protocol.md) | RFB 003.889 and its record layer, Quality, High Performance (D65), the hotspot findings |
| [tmux under launchd, Basic terminals (D66, D67)](tasks/2026-10/2026-10-12_tmux-under-launchd.md) | The coalition a Force Quit ends, the app as tmux host, the test leak onto the owner's server, terminals outside tmux |
| [Widgets: Machines and Active (D68)](tasks/2026-10/2026-10-12_widgets-machines-and-active.md) | A snapshot the app writes, App Intents for taps, the Mac's App Group |
| [October tasks](tasks/2026-10/README.md) | Monthly index: tmux (D44), database through another machine (D45), RDP bandwidth, iPhone landscape, Vision Pro input (D46 proposed) |
| [Backlog inventory, 2026-10-12](tasks/2026-10/2026-10-12_backlog-inventory.md) | Every open decision, release step, defect, feature, owed check and limit, including what the original apps and absorbed packages never carried forward; IDs to pick by |
| [Backlog tier 2, 2026-10-12](tasks/2026-10/2026-10-12_backlog-tier-2.md) | The CVE fix, wake liveness, iPhone Duo, licensing research and lawyer questions, the two-device checklist |

This project is `~/Software/glass/GlassPowerTools`. `../GlassEditorKit` was **absorbed on 2026-09-14**
— it was already in production behind the SQL, record and SFTP editors, so it was never a future
capability. `../GlassConnectionKit` was **absorbed on
2026-09-14** and is now a historical record like the rest. `../glas.sh`, `../glassdb`, `../glassDT` and `../GlasSecretStore` are
obsolete and do not compile — a historical record to read, never something to keep building.
GlasSecretStore was absorbed into `Sources/GlasSecretStore` on 2026-09-13. Two further siblings are **not** inputs:
`../docs` holds two July 2026 security audit reports of glas.sh and glassdb; every finding in them
is closed (see [technical context](techContext.md)). A stale copy of glassdb was archived to
`../glassdb-connection-library.zip` and removed on 2026-09-10. The full layout is in [technical context](techContext.md).

**Examples, not machines.** Examples and test fixtures use neutral values — `alpha`, `bravo`,
`shop`, `example.com` names and addresses reserved for documentation (`192.0.2.x`, `203.0.113.x`) —
that stand for nothing real. No real machine names, addresses, device identifiers, database names
or hosting details are written into this repository (`projectRules.md`, rule 61).

Operational transitions are recorded in `.brain/sessions.jsonl` at the project root, which is local
and git-ignored.
