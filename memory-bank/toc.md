# Glass Power Tools Memory Bank

Created 2026-09-10. Aggregate owner: coordinating agent `/root` until handed off.

Read [AGENTS.md](../AGENTS.md), then [active context](activeContext.md), [progress](progress.md) and
the [merge plan](tasks/2026-09/2026-09-10_merge-plan.md). This project has not been built yet; the
three source applications are still the working software.

| Note | Purpose |
|---|---|
| [Project brief](projectbrief.md) | Scope, the decision to merge, and what the product is |
| [Product context](productContext.md) | The host-centric model and the interface it implies |
| [System patterns](systemPatterns.md) | Intended module boundaries and what they replace |
| [Technical context](techContext.md) | Measured sizes, dependencies, targets and identities |
| [Active context](activeContext.md) | Current state, ownership and next action |
| [Progress](progress.md) | What is actually done, which today is nothing but planning |
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
| [UI and validation from use](tasks/2026-09/2026-09-12_ui-and-validation.md) | Builds 0.3.56–0.3.67: canvas border, Paint Theme removed, service tabs, colour swatches, record-editor validation, the `tinyint` data-loss bug |
| [Stage 3 — database (superseded draft)](tasks/2026-09/2026-09-10_stage-3-database.md) | Predates the setup sheet, the draft contract and the address-on-the-host rule. **Superseded by the plan above** |
| [Stage 4 — desktop](tasks/2026-09/2026-09-10_stage-4-desktop.md) | glassDT engines and Core/UI moved; pairing machinery deleted; validation ledger |
| [September tasks](tasks/2026-09/README.md) | Monthly index |

This project is `~/Software/glass/GlassPowerTools`. Source applications and their own memory banks
are sibling directories at `../glas.sh`, `../glassdb`, `../glassDT`, `../GlassConnectionKit`,
`../GlasSecretStore` and `../GlassEditorKit`. Treat them as the record of what exists today; treat
this bank as the record of what is being built. Two further siblings are **not** inputs:
`../docs` holds two July 2026 security audit reports whose still-open findings are tracked in
[technical context](techContext.md). A stale copy of glassdb was archived to
`../glassdb-connection-library.zip` and removed on 2026-09-10. The full layout is in [technical context](techContext.md).

Operational transitions are recorded in `.brain/sessions.jsonl` at the project root.
