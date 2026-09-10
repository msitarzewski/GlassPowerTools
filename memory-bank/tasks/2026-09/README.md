# September 2026

- 2026-09-10: Glass Power Tools created as a project. Decision to merge glas.sh, glassdb and glassDT
  recorded with its evidence and its accepted cost. Memory bank, project guide and the staged
  [merge plan](2026-09-10_merge-plan.md) written.
- 2026-09-10: Stage 0 complete. The editor is built in as a library with its interface last; data
  migration is not a constraint; capability order is SSH and SFTP, databases, remote desktop, editor;
  the floor is 26.0 everywhere on `arm64` only; and the layering system is foundational rather than a
  later pass. No code, no project structure, no build. Stage 1 is unblocked.

- 2026-09-10T17:32:27Z: Session handoff written for compaction. Stage 0 complete, Stage 1 unblocked, no code yet.

- 2026-09-10: Memory bank reconciled with the workspace at the start of a fresh session. The project
  path was corrected from `~/Software/glasspowertools` to `~/Software/glass/GlassPowerTools` in the
  active context, decisions and merge plan. A workspace layout section was added to
  [technical context](../../techContext.md): the six sibling inputs, the two siblings that are not
  inputs (`glassdb-connection-library`, a stale glassdb snapshot, and `docs`, July evaluation
  reports), and per-sibling Git state. Sizes, entitlement groups and deployment targets re-measured
  at the new location and unchanged. Still no code, no project structure, no build.

- 2026-09-10: The July 2026 audit reports in `../docs` were checked against current source rather
  than assumed stale. Most findings are fixed: no `.acceptAnything()` or `SSHAlgorithms.all` remains
  in any live source, `SSHHostTrustKeychainStore` is wired into glas.sh and glassdb, MySQL builds a
  real TLS configuration, recordings carry file protection, and `NSFaceIDUsageDescription` is
  present. Two remain unresolved and are now a Stage 2 checklist in
  [technical context](../../techContext.md): keystroke recording consent in
  `SessionRecorder.recordInput`, and one-click AI execution trusting the model's own `riskLevel`.
  Both live in glas.sh, which Stage 2 moves in without rewriting.
- 2026-09-10: `glassdb-connection-library` archived to `../glassdb-connection-library.zip` by the
  user and the directory removed, after being proven a strict subset of live glassdb. One of the two
  documented traps is now gone; `../docs` stays until Stage 2 closes the two open findings.

- 2026-09-10: Project model decided by the user — one multiplatform target, hand-maintained
  project with synchronized folders, following glas.sh rather than glassDT's XcodeGen template.
  Recorded in decisions, system patterns and the merge plan.
- 2026-09-10: [Stage 1 planned](2026-09-10_stage-1-shell.md). Found while planning: all three apps
  share `<App Group>/GlassHostCatalog/hosts.json`; layering *views* are shared but layering *state*
  has three defaults; GlasSecretStore is in three revisions with the only RDP credential store
  sitting uncommitted in the local working tree; GlassConnectionKit has no version control. Three
  pre-steps and six decisions await the user. No code yet.
- 2026-09-10: **BUILD begins.** User approved Stages 1–5 end to end with parallel agents and
  function/unit/UI/security testing. P3 ran: GlasSecretStore 90 tests passed, GlassConnectionKit 21
  passed (`swift test`, macOS host). Package skeleton laid down; the three local packages resolve in
  one Swift 6.4 graph. Stage 1 fanned out to three workers with exclusive ownership: project file
  (`GlassPowerTools.xcodeproj`, `App/`, `Platforms/macOS/`, `UITests/`), `Sources/GlassLayers`,
  `Sources/GlassShell`. Each writes its own task note here. D1 Git actions still await the user.
