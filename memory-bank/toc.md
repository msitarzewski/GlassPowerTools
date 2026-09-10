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
| [Stage 3 — database](tasks/2026-09/2026-09-10_stage-3-database.md) | GlassDBKit + GlassDatabase over the shared SSH engine; tunnel replacement; ownership |
| [September tasks](tasks/2026-09/README.md) | Monthly index |

This project is `~/Software/glass/GlassPowerTools`. Source applications and their own memory banks
are sibling directories at `../glas.sh`, `../glassdb`, `../glassDT`, `../GlassConnectionKit`,
`../GlasSecretStore` and `../GlassEditorKit`. Treat them as the record of what exists today; treat
this bank as the record of what is being built. Two further siblings are **not** inputs:
`../docs` holds two July 2026 security audit reports whose still-open findings are tracked in
[technical context](techContext.md). A stale copy of glassdb was archived to
`../glassdb-connection-library.zip` and removed on 2026-09-10. The full layout is in [technical context](techContext.md).

Operational transitions are recorded in `.brain/sessions.jsonl` at the project root.
