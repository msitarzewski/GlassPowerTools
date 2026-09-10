# AGENTS.md

**Version**: 3.0 (2026-09-10) | **Compatibility**: All agents that support AGENTS.md
**Status**: Canonical project guide for Glass Power Tools. `CLAUDE.md` links to this file.

## Project Context

Glass Power Tools is an MIT-licensed, native Apple application that merges the previously separate
glas.sh (SSH/terminal), glassdb (databases) and glassDT (RDP/VNC remote desktop) apps into one
product, with GlassEditorKit available as a further capability. Bundle identifier
`com.glasspowertools`. The merge was decided on 2026-09-10; nothing has been built yet.

**Read first:** `memory-bank/toc.md`, then `memory-bank/activeContext.md` and the merge plan in
`memory-bank/tasks/2026-09/2026-09-10_merge-plan.md`. The three source applications remain at
`../glas.sh`, `../glassdb` and `../glassDT` and must keep building until this product reaches parity.

**Why one product.** The shared catalog already models a host owning several services, so the three
apps were each a partial view of one model. Merging removes machinery that exists only to keep three
processes agreeing: service pairing, the `glassh://`, `glassdb://` and `glassdt://` routing, the
shared App Group catalog with its publication and removal journals, the cross-app Keychain group, and
three separately pinned copies of the shared packages.

**User requirements carried forward from the three apps:**
- Native Mac, iPad, iPhone and Vision Pro experiences. Apple TV and watchOS are excluded.
- One library of hosts. A host shows an icon per defined service, and Connect chooses among them when
  more than one exists: a chevron menu on Mac, press and hold on touch. "Paired Services" becomes
  "Add a service…".
- One settings and configuration surface for all capabilities, replacing three drifting designs.
- Preserve the family library, favorites, groups, selection and detail-panel patterns. Users must not
  have to learn a new navigation model.
- Credentials stay in GlasSecretStore with its existing eligibility and mobility policy.
- visionOS uses normal native windows with the shared Glass framing; the spatial workspace where a
  host's terminal, database and desktop coexist is the product's differentiator.

**Deployment targets observed in the source apps:** glas.sh macOS 26.0, iOS 26.0, visionOS 26.0;
glassdb macOS 27.0, iOS 26.0, visionOS 26.0; glassDT 26.0 on all three. The merged product must pick
one floor deliberately and record it.

**Existing installations whose data must be preserved:** `/Applications/glassDT.app` (`app.glassdt`),
glas.sh (`sh.glas.app`) and glassdb (`app.glassdb`), all signed by team 7JQGQ7CRH8. All three already
share the App Group `group.sh.glas.shared` and the Keychain access group `sh.glas.shared`, so a new
bundle identifier that declares the same two groups inherits existing hosts and credentials in place.
Verify this before relying on it; do not reset or migrate user data without explicit authorization.

**Public repositories to deprecate later, with redirects:** the separate glas.sh, glassdb and glassDT
repositories. Not yet actioned, and not to be actioned without the user's instruction.

**Existing functionality to examine before writing an equivalent:**

| Responsibility | Existing owner / evidence |
|---|---|
| Terminal, SFTP, port forwarding, workgroups | `../glas.sh/glas.sh/` (about 31,400 lines) |
| Database browsing and query surfaces | `../glassdb/glassdb/` (about 22,200 lines) |
| RDP and VNC engines, Metal presentation, spatial canvas | `../glassDT/` (about 5,600 lines plus `Packages/RDPKit`, `Packages/VNCKit`, transports) |
| Host identities, library projection, shared library UI, host catalog | `../GlassConnectionKit` |
| Credentials, trust storage, mobility | `../GlasSecretStore` |
| Text editing and syntax analysis | `../GlassEditorKit` |

Reuse means moving these in as modules, not rewriting them. Record what actually moved.

---

## Table of Contents

1. [Compliance & Core Rules](#1-compliance--core-rules)
2. [Session Startup](#2-session-startup)
   - [Compaction Protocol](#compaction-protocol-mid-session-context-preservation)
3. [Memory Bank](#3-memory-bank)
4. [State Machine](#4-state-machine)
5. [Task Contract & Budgets](#5-task-contract--budgets)
6. [Quality & Documentation](#6-quality--documentation)
7. [Example Workflow](#7-example-workflow)
8. [Troubleshooting](#8-troubleshooting)

---

## 1. Compliance & Core Rules

### Startup Compliance

Read this guide and the required Memory Bank files before implementation. A short task-focused acknowledgment is sufficient; do not repeat a ceremonial banner or a list of user responsibilities.

### The Four Core Rules

| Rule | Requirement | Evidence |
|---|---|---|
| **Reuse existing functionality** | Before implementing a function or behavior, search this app, the sibling apps and relevant shared packages. Use the existing implementation when it fits; extend or extract it when appropriate. | Name the implementation examined and the actual gap if new code is needed. |
| **Prefer incremental changes** | Preserve working behavior and unrelated edits. Refactor or extract a reusable component rather than copying an entire app or rewriting working code. | Explain the affected responsibilities and any required migration. |
| **Ground claims in evidence** | Cite current code for implementation claims and primary specifications/docs for protocol/platform claims. Label proposals and unverified assumptions. | `file:line`, Memory Bank section, or an authoritative source link, as appropriate. |
| **Preserve family architecture and UX** | Honor existing library navigation and interaction patterns, shared identities and credential boundaries. | Compare both sibling implementations before adding an equivalent surface. |

**Reuse means avoiding duplicate functionality, not avoiding new files.** New files are normal for new responsibilities, extracted shared behavior, tests and documentation. A short reuse check is enough; there is no exhaustive per-file justification ritual. Do not stretch an unrelated module merely to avoid creating a file.

### Reuse Validation Checklist

- Search for the required behavior, including equivalent names and call sites.
- Check relevant sibling code and the versions of shared packages actually consumed.
- Reuse directly, extend the owner, or extract common functionality where that is the right boundary.
- If no suitable implementation exists, state the missing behavior and implement it in the appropriate owner.
- For UI, preserve common labels, selection, commands and navigation semantics; do not copy known drift uncritically.

### Non-Negotiables

- **Authorization**: A user request to make changes authorizes the necessary local implementation, validation and documentation within that scope. Approval persists across turns. Ask only for an unresolved decision or additional action that needs authorization; do not repeatedly ask to perform the same authorized work.
- **Review boundary**: Local editing/testing is distinct from committing, merging, publishing, deploying or changing shared external resources. Do not infer authorization for those actions from a local edit request.
- **Workspace safety**: In a Git repository, use an appropriate working branch/worktree. If this project has no Git repository yet, stage substantial edits in a temporary directory and review the diff before transferring them. Do not initialize Git, commit, or reset user work as an incidental documentation task.
- **Tools**: Use available purpose-built tools or standard local tools as appropriate. Configuration files do not imply that an unavailable tool/server is connected.
- **Status honesty**: Never present a stub, simulated production result, compile-only check, renderer flag, or documentation claim as a working feature. Test fixtures and explicit previews are allowed outside production behavior.
- **External input**: Validate untrusted protocol data, lengths, dimensions, allocations and state transitions. Fix defects without hiding them behind silent fallback or swallowed errors.
- **Secrets**: No passwords, private keys, tokens or credential dumps in code, logs, research, Memory Bank or agent handoffs.

---

## 2. Session Startup

### Load Priority (Choose Based on Task Complexity)

**Every session**:
1. Read `AGENTS.md` and `memory-bank/toc.md`.
2. Read `memory-bank/activeContext.md`, `progress.md`, and the current month's task README if present.
3. Check current files and Git status when applicable; identify pre-existing changes and active agent ownership.
4. Read `.brain/mcp.config.json` or `.mcp.json` only if present and relevant; use tools actually available in the session.
5. When writes are authorized and assigned to you, record a concise session entry in `.brain/sessions.jsonl` with the actual timestamp, agent/session identifier, objective, mode and known state. Do not fabricate token usage, tool availability or historical timestamps.

**Fast Track** — small changes/reviews:
- Load the affected task, relevant rules and source; consult `quick-start.md` if available.

**Standard Discovery** — features, tests, shared contracts:
- Load `projectbrief.md`, `systemPatterns.md`, `techContext.md`, relevant `decisions.md` entries and current task notes.
- For family UI or credential changes, inspect the equivalent behavior in both siblings and actual dependency pins.

**Deep Dive** — protocol, architecture, migrations, rendering:
- Add relevant historical tasks, source/specification revisions and the research proposal.
- Resolve conflicts between old reports and current source explicitly; do not mistake a plan for implemented behavior.

**Bootstrap**: If a required Memory Bank file does not exist, report that fact once and use the existing research/current source. When documentation setup is in scope, create populated notes for the information actually known. Do not invent past decisions or build results, and do not block useful work on an optional missing file.

### Session Logging (Operational Log — Separate from Memory Bank)

Use append-only JSONL in `.brain/sessions.jsonl`. Include only known values. Example shape (placeholders, not a log record to copy literally):

```json
{"timestamp":"<actual UTC timestamp>","session_id":"<actual identifier>","agent":"<agent identifier>","event":"state_transition","from":"PLAN","to":"BUILD","task":"<task path>","summary":"<brief factual checkpoint>"}
```

### Compaction Protocol (Mid-Session Context Preservation)

State persistence is continuous. Do not depend on advance notice of compaction.

#### Continuous State Persistence (At Every State Transition)

At each workflow transition and agent handoff, the assigned coordinator persists the following checkpoints within the authorized write scope. In an explicitly read-only task, report the checkpoint without editing files. Workers send updates to the coordinator unless the relevant note/log is assigned to them; do not write another agent’s aggregate files.

1. Update `activeContext.md` with current task, state, owner, edited files, authorization already given, validation, blockers and next action.
2. Append a concise progress/status entry to `tasks/YYYY-MM/README.md` and update the task note. Do not duplicate the whole conversation.
3. Record new decisions only when something changed, with explicit **Proposed**, **Approved**, **Implemented**, **Observed**, or **Superseded** status and provenance. A proposal does not become approved merely because an agent persisted it.
4. Append the operational transition/handoff record.
5. Preserve user requirements and pending questions needed for continuity, excluding secrets and unnecessary private data.

Routine checkpoints are authorized as part of an editing task and do not wait for final code approval. Approval for an architectural change or external action must still be recorded truthfully.

#### After Compaction (Recovery)

1. Read `activeContext.md`, the active task note, its monthly README and relevant decisions.
2. Compare the saved checkpoint with current workspace state and any newer user instruction.
3. Resume the existing task; do not restart discovery or repeat permissions already granted.
4. Briefly report a recovery discrepancy if one exists. If saved state is absent or stale, reconstruct it from evidence and mark uncertainty instead of claiming recovery succeeded.

#### Cross-Agent Ownership

- Assign explicit file/module ownership before parallel edits. Agents are not alone in the workspace and must preserve each other's changes.
- The coordinating agent owns aggregate Memory Bank files (`activeContext`, `progress`, `toc`, monthly README and `decisions`) unless ownership is explicitly transferred.
- Workers report structured findings or write assigned task notes. Avoid concurrent writes to the same aggregate document.
- Every handoff records evidence, actual changed paths, validation performed, remaining work and pending decisions. Re-check line numbers after edits.
- Memory Bank is the durable cross-agent record. Conversation updates and tool results may be newer; reconcile them rather than blindly treating either as infallible.

---

## 3. Memory Bank

### Structure

Preserve this structure. Core notes should contain real project information; optional reference files are added when relevant.

```text
memory-bank/
├── toc.md                    # Index and reading order
├── projectbrief.md           # Product scope and user requirements
├── productContext.md         # User workflows and family UX
├── systemPatterns.md         # Architecture, ownership and reuse boundaries
├── techContext.md            # Actual stack, toolchain and dependency status
├── activeContext.md          # Current task, ownership, authorization and next action
├── progress.md               # Verified completion, open work and validation limits
├── projectRules.md           # Project-specific implementation rules
├── decisions.md              # Decisions with status and provenance
├── quick-start.md            # Optional common workflows and commands
├── database-schema.md        # Optional local metadata schema when one exists
├── build-deployment.md       # Optional verified build/deployment procedures
├── testing-patterns.md       # Optional established test procedures
└── tasks/
    └── YYYY-MM/
        ├── README.md         # Monthly index, progress and handoffs
        └── YYYY-MM-DD_topic.md # Task-specific evidence, status and outcomes
```

### File Reference Table

| File | Read when | Update when |
|---|---|---|
| `toc.md` | Startup/navigation | Files or reading order change |
| `projectbrief.md` | Scope/requirements work | User requirements change |
| `productContext.md` | UI/workflow work | Agreed workflow or product understanding changes |
| `systemPatterns.md` | Architecture/shared code work | Ownership or established patterns change; mark proposals |
| `techContext.md` | Implementation/build work | Verified stack, pins, commands or platform status change |
| `activeContext.md` | Every session/recovery | Every state transition and handoff |
| `progress.md` | Every session | Verified completion, blockers or validation status change |
| `projectRules.md` | Relevant implementation | Established project rules change |
| `decisions.md` | Relevant architectural work | Decision/status changes, with evidence |
| `tasks/*/README.md` | Current or relevant month | Concise progress, task links and completion |
| `tasks/*/*.md` | Active/relevant task | Evidence, changed files, tests and next action |

### Read vs Write Paths

Read frequently and keep the working context focused. Write concise factual checkpoints throughout authorized work, including research and documentation tasks. Finalize outcomes after validation; never defer all communication until code approval. Do not rewrite history to make an unfinished feature look completed.

---

## 4. State Machine

### Overview

Preserve the workflow vocabulary: `PLAN → BUILD → DIFF → QA → APPROVAL → APPLY → DOCS`.

Substates: `CODING`, `WAITING_TOOL`, `RUNNING`, `IDLE`. Persist transitions as described above. These states organize work; they do not create redundant permission gates.

- A sufficiently clear user request can authorize PLAN and BUILD together.
- Research/review tasks may proceed through analysis, QA and DOCS without manufacturing a code change.
- APPROVAL checks whether authorization exists for the intended next action. If it already exists, record that and continue.
- APPLY means delivering/transferring the reviewed local result or performing the specifically authorized integration action. Changes already edited and tested in a working tree are not applied a second time.

### PLAN

Record the objective, scope, existing authorization, owned files, reuse findings, proposed changes, validation and material uncertainties. Use current file/specification citations where available. Ask about an unresolved material requirement while continuing independent work; do not ask for blanket approval already provided.

**Exit**: A concrete plan within authorized scope; genuinely additional actions have their own approval boundary.

### BUILD

Implement the authorized changes in the working branch/worktree or temporary staging area. Reuse existing functionality and preserve family UX. Add appropriate tests with behavioral value. Keep production behavior honest and the Memory Bank current.

**Exit**: A reviewable local implementation, explicitly not assumed committed, merged, published or deployed.

### DIFF

Review the actual edits against the initial state. Check scope, unintended changes, secret exposure, compatibility, reuse and ownership boundaries. Summarize significant changes; a full diff can remain in an artifact/tool result. In a non-Git workspace, use a temporary baseline for comparison.

**Exit**: The changes are understood and ready for relevant validation.

### QA

Run checks appropriate to the changes. Report actual outcomes and distinguish **passed**, **failed**, **not run**, and **not applicable**. Never copy sample test counts or coverage percentages into results.

For documentation changes, validate links, structure, cross-references and contradictory instructions. For app work, use the relevant build/unit/integration/device/protocol checks in Section 6. Missing hardware or hosts limits the claim; a simulator compile does not establish device performance or interoperability.

**Exit**: Required checks passed, or the remaining limitations are clearly recorded for review. Resolve failures where possible; do not hide or waive them yourself.

### APPROVAL

Compare the concrete result and intended next action with existing authorization. Local changes explicitly requested by the user do not require another confirmation merely to finish the task. If an additional action needs approval, prepare its complete reviewable result first and explain the exact action and reason for asking.

**Exit**: Existing or newly received authorization covers the action. Elapsed time is not approval.

### APPLY

Transfer validated staged edits once, verifying that destination files have not changed unexpectedly; otherwise preserve and reconcile newer edits. If the work was already performed in an authorized working tree, no second patch application is needed. Commit/merge/publish/deploy only when separately authorized or clearly included in the task.

**Exit**: The intended local result or authorized integration action is complete and checked. If recovery is needed, revert only changes owned by this task.

### DOCS

Finalize the active task note and monthly index; update progress, patterns, decisions and `toc.md` as relevant. Include actual validation and remaining work. Research/documentation tasks can complete here without prior code approval. Routine checkpoints were already written throughout the task.

**Exit**: Another agent can understand what changed, what is proven and what to do next. Documentation does not imply permission to create a commit or PR.

---

## 5. Task Contract & Budgets

### Task Contract Format

```markdown
## Task: <concrete objective>
- Scope and existing authorization:
- Owner and affected files/modules:
- Existing functionality examined and reuse decision:
- Requirements and acceptance criteria:
- Proposed changes and migration, if any:
- Validation (unit/integration/device/protocol/docs as appropriate):
- Uncertainties, dependencies and additional approval boundaries:
- Evidence and related Memory Bank entries:
- Current state and next action:
```

Scale the contract to the task. A small documentation correction does not require a full feature proposal.

### Budget System

Honor explicit user/runtime budgets. Otherwise use task-appropriate estimates and checkpoints, not a universal three-iteration or thirty-minute stop rule. Never invent token accounting. Long-running protocol tests, builds and physical-device investigations can be necessary; report progress and preserve state while they run.

### Stall Detection

A stall means repeated attempts produce no new evidence or progress and no useful independent work remains. An unchanged diff while testing, tracing or measuring is not by itself a stall.

After repeated failure, inspect the root cause, change the approach and record what was learned. Ask for missing input or an environment change when actually necessary. Do not discard work, restart the project, or swap agents automatically because a counter was reached.

### Context Management

Keep current requirements, ownership and active evidence close at hand; load historical material on demand. Persist at transitions and handoffs.

**Parallel Execution**: Use parallel agents for concrete independent subtasks where useful. Give each explicit scope and ownership, note the shared workspace, and tell workers not to revert others' edits. Coordinate aggregate Memory Bank updates through one owner and integrate the findings before reporting completion. Respect any higher-level restrictions on delegation.

---

## 6. Quality & Documentation

### Absolute Prohibitions

- No fabricated production data, connected/synced states, test results or performance claims.
- No stubs presented as complete, swallowed critical errors, or silent security downgrade.
- No credentials or private key material in logs, screenshots, task notes, URLs or handoffs.
- No wholesale reset, deletion or reversion of unrelated user/agent work.
- No claim of protocol conformance, shared storage, hardware acceleration or physical-device support based solely on a dependency declaration or successful compile.

Test fixtures, parser fuzz inputs, deterministic replays, test doubles and clearly separated UI previews are allowed. Use them to verify real behavior; do not let fixture data masquerade as a production connection.

### Code Reuse Enforcement

Before adding behavior, search its current owner and family equivalents. Prefer direct reuse or incremental extension. When two apps repeat the same behavior, evaluate extracting it into an appropriate shared target instead of creating a third copy. Record only the useful findings, not an exhaustive list of irrelevant files.

For the main library, share common presentation and behavior where feasible: favorites, groups/collections, search, connections, selection, detail-panel layout, common commands, empty states and accessibility. Let adapters supply app-specific data, fields, actions and status. Keep live terminal/database/RDP canvases outside this shared surface. Preserve platform-native layouts and existing user workflows during extraction.

### Security Review

- Validate untrusted PDUs, lengths, dimensions, resource budgets and protocol state before use.
- Verify endpoint identity before releasing credentials; keep SSH, RDP, Gateway and DB trust independent.
- Follow the shared credential lifecycle and explicit app-access/mobility policies. Device-bound keys cannot be advertised as synchronized.
- Keep metadata separate from secrets. Host pairing does not grant cross-protocol authentication or imply identical accounts.
- Review imported files, clipboard/drive redirection and any optional host helper at their trust boundaries.
- Pin dependencies, retain required license notices, review relevant advisories and record unresolved findings accurately.

### Linting & Code Quality

Use established Swift/platform conventions, explicit ownership and concurrency boundaries, and clear errors. Follow actual configured lint/build checks; do not invent missing tools or enforce arbitrary nesting limits as a substitute for readable code. The authored project is MIT; third-party licenses remain intact.

### Testing Requirements

Choose tests by behavior and risk rather than counting functions:

| Area | Required evidence when affected |
|---|---|
| Domain/persistence | Deterministic identity, pairing, migration, conflict and deletion tests |
| Family UI | Same navigation/actions across consumers; selection restoration, compact adaptation, keyboard and accessibility checks |
| RDP | Applicable specification ledger, malformed-input/fuzz coverage and real-server interoperability |
| Host support | Windows, Ubuntu/Linux and identified macOS RDP implementations; test server/backend capabilities explicitly |
| Rendering | Correct reconstruction and presentation, resize/reset behavior, GPU resource lifetime, measured device latency/memory/energy |
| Spatial | Physical Vision Pro resizing, tilt, input mapping, legibility and transparency fallbacks |
| Credentials/sync | Signed cross-app access and eligible device sync; locked/missing/late-arriving credentials and migration recovery |
| Lifecycle | Reconnect, cancellation, focus changes, held-key release, sleep/wake and bounded cleanup |

Keep unit tests fast and deterministic. Integration tests, network fault tests and device soak/performance runs have separate, realistic durations and recorded conditions. Do not add tests that merely mirror implementation or require a full app test run for a low-impact documentation edit.

### Documentation Standards

- Preserve the Memory Bank structure and update checkpoints at every transition/handoff.
- Routine progress, task notes and researched proposals are part of authorized work. Mark approval and implementation status accurately.
- Cite code as `path/file:line`, Memory Bank entries by file/section, and protocol/platform facts with primary source links. Do not fabricate code citations for unimplemented features.
- Record known limits and provenance: current checkout, pinned dependency, upstream claim, simulation, physical device or real server.
- Task documents include objective, owner, authorization, reuse, changed files, validation, decisions and remaining work.
- Use actual dates and neutral placeholders in templates. Do not invent release/milestone identifiers or approved decisions.

### Versioning & Rollback

Document-version updates are distinct from application releases. Preserve established app release identifiers; propose new release/milestone labels when needed.

Before recovery, inspect current changes and ownership. Revert only this task's edits where necessary, preserving unrelated and newer work. If edits overlap, reconcile or ask for the exact unresolved decision. Never use a blanket reset/clean/discard as an automatic response to a failed check.

---

## 7. Example Workflow

### Task: Make window resizing update the remote desktop (remote desktop capability)

**PLAN**: Read the family resize-coalescing precedent, the display coordinator moved from glassDT, and MS-RDPEDISP requirements. Record the user's authorization, file ownership, supported server cases and fallback behavior.

**BUILD**: Reuse the existing coordinator when appropriate. Observe content geometry, coalesce requests, validate negotiated display limits and send complete monitor layouts. Keep source resolution independent of local zoom and spatial tilt.

**DIFF**: Verify no duplicate resize mechanism, unrelated UI redesign, credential changes or assumed Windows-only behavior slipped in.

**QA**: Test latest-request handling, cancellation and graphics resets. On named real servers, verify actual source-resolution changes and honest behavior when resizing is unavailable. Record physical Vision Pro results separately from simulator/build results. Do not invent results before running checks.

**APPROVAL**: Check whether the requested local change is already authorized. Ask only if an additional action needs authorization.

**APPLY**: Deliver the reviewed local result once; do not infer permission to merge or publish it.

**DOCS**: Finalize the task note, monthly index and progress with tested server/device versions, known limits and next actions. Checkpoints were maintained at every preceding transition.

---

## 8. Troubleshooting

### Decision Tree: Agent Stuck

1. Identify the actual failure and retain its evidence.
2. Read the active task and relevant source/specification; verify environment and dependency versions.
3. Determine whether a new approach or independent task can make progress.
4. If missing user input or an external-state change is required, ask specifically and preserve the checkpoint.
5. Resume from existing work when the blocker clears; do not restart or repeat authorization unnecessarily.

### Common Issues

| Issue | Response |
|---|---|
| Saved context differs from source | Preserve both facts, inspect current files and newer instructions, then correct the checkpoint. |
| Dependency sibling differs from app pin | Inspect the actual consumed revision; record version skew before proposing integration. |
| Family UI behavior differs | Identify shared semantics and app-specific requirements; propose an incremental extraction that preserves workflows. |
| Metal reports active but no frames appear | Verify actual drawable presentation and resource lifetime on the target device; do not report acceleration as proven. |
| RDP server lacks a feature | Honor negotiation and endpoint policy; provide the specified fallback and report the server/backend tested. |
| Tests fail or hardware is missing | Fix what is actionable and report precise validation limits; do not fabricate success. |
| Memory Bank is missing or stale | Reconstruct from available evidence, label uncertainty and populate it when in scope. |

### Recovery Procedures

Use a scoped rollback only when required. Preserve unrelated work, completed evidence and task state. When transferring to another agent, provide objective, authorization, file ownership, current diff, checks performed, blockers and next action; coordinate Memory Bank ownership explicitly.

---

## Quick Reference

- **Reuse**: Find existing functionality before implementing an equivalent. New files are permitted.
- **Family UX**: Preserve the shared favorites/groups/connections/detail model and evaluate a shared surface before duplicating it.
- **Continuity**: Maintain Memory Bank state at every transition and handoff, with one owner for aggregate files.
- **Workflow**: `PLAN → BUILD → DIFF → QA → APPROVAL → APPLY → DOCS`; existing authorization counts.
- **Evidence**: Distinguish proposals, inspected source, tested behavior and released capability.
- **Safety**: Validate external data, preserve credentials and unrelated work, and avoid silent failure/downgrade.

**Mission**: Build one precise, performant Apple-native workspace for every machine the user owns and every service on it. Move existing functionality in rather than rewriting it, preserve familiar interactions, and leave reliable context for the next agent.
