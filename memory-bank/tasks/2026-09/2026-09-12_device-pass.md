# Stage 3 device pass — the first UI test to open a window on the Database capability

**Date** 2026-09-12 (evening/night) · **Owner** coordinating agent · **State** QA
**Authorization** standing: build and test Stages 1–5 end to end, then scan for TODO/stubs and
repair in the same manner.

## Objective

Stage 3's R1–R8 were closed and the remainder was recorded as *"not code — a device pass"*:
row deletion and a foreign-key follow driven through the UI, the D14 fingerprint prompt, whether
SQL-draft restore fires at all, and iOS/visionOS still compile-verified only.

**Preparing that pass produced code anyway, and that is the finding.** Six product defects, none of
which any unit test could have seen.

## Why no test had ever opened this window

Two reasons, both structural rather than negligent:

1. **`../glassdb` has no UI tests either** — one 194 KB unit file, no XCUITest target, nothing
   outside vendored packages (verified: `project.pbxproj` declares one `bundle.unit-test`; the only
   `XCUIApplication` matches are Citadel's sample code). The capability inherited the absence.
2. **The workspace was undrivable.** 19 accessibility identifiers in the whole module, 16 of them in
   the setup form. Nothing on the grid, the schema sidebar, the row menus or the editor.

Fixed first: the identifier contract (`db-schema-*`, `db-tab-*`, `db-grid-row/cell-*`,
`db-row-menu-*`, `db-delete-*`, `db-query-*`, `record-editor-*`), 19 → 52 identifiers.

## Product defects found

| # | Defect | Why nothing caught it |
|---|---|---|
| 1 | **SSH fingerprint spelled unlike every other SSH tool** — bare padded base64 where OpenSSH prints `SHA256:` + unpadded | Trust is decided on the key blob, never the fingerprint text. Nothing malfunctioned; only a human comparing two strings would see it |
| 2 | **Grid filters ran no size check at all**, any type, any engine | `GridColumnFilter.validationError` was a second, weaker copy of the record editor's check that called `boundValue()` — type conversion only |
| 3 | **The entire Database menu bar was attached to nothing** | `DatabaseCommands`' only reference in the codebase was its own declaration. An unattached `Commands` is perfectly valid Swift |
| 4 | **`openWindow(id: "query-editor")` — no such window group** (`SchemaBrowserView.swift:467`, the live "Open in New Window") | Declared ids are `database-workspace` / `database-results`. Nothing type-checks a window id |
| 5 | **The AI prompt's error region was unfenced** while the schema region beside it was escaped | Output is reviewed by the user before running; bounded, but the *inconsistency* is the defect |
| 6 | **The read-only gate trusted callers to split scripts** (latent, not reachable) | `safetyClassification` classifies one statement; `SELECT 1; DELETE FROM members` returns `.readOnly` |

Plus a Swift trap worth remembering: changing `validationError` from a property to a method left
`filters[0].validationError == nil` **compiling** — an unparenthesised method reference is a function
value, which `== nil` promotes and always answers `false`. A property→method change does not
reliably break its call sites.

## Questions closed by observation

- **SQL draft restore fires.** `onChange(of: session?.connectionConfig.id, initial: true)` had been
  *read*, never observed. `testSQLDraftSurvivesClosingAndReopeningTheWorkspace` passes, four runs
  running — typed marker, debounce, close with the window's red button (never ⌘W, which is the
  deliberate discard), reconnect, read back.
- **`db-query-editor` publishes its text as its `.value`.** The identifier had to be threaded onto
  the underlying `NSTextView`/`UITextView`; a SwiftUI modifier lands on the `NSScrollView` wrapper,
  which carries no value. That was a *mechanism argument* until the test measured it.
- **The schema sidebar can be driven by synthesized events** — `select the row, press right arrow`.
  The disclosure triangle is unaddressable (`app.outlineRows.containing(.staticText, identifier:)`
  matches nothing), so the keyboard path is the only one that works.

## Coverage added for modules that moved with none

Asked whether glassdb's tests were useful, the answer was: not to copy, but as a **record of what
each module was guarding**. Five modules had arrived with zero tests. **Every one turned out to be
correct** — the gap was that nothing guarded them.

| Module | Tests | Verdict |
|---|---|---|
| `SQLHighlighter.safetyClassification` — D15's whole gate delegates to it | 14 | correct |
| `SQLiteFileImporter.validatedURL` — its result is passed to `removeItem` | 13 | correct |
| `SchemaContext` — untrusted metadata into a model prompt | 19 | correct |
| `GridServerQueryBuilder` — rejects unknown columns before they reach a `WHERE` | 18 | correct |
| `GridExportFormatter` — TSV's three NULL states | 24 | correct |

`validatedURL`'s test asserts both that the guard refuses the `…Databases-evil` sibling **and** that
a naive `hasPrefix` *would* have passed it, so a future "simplification" fails the test rather than
quietly stopping to exercise anything.

## What the loop actually cost, recorded honestly

**Sixteen invocations of the macOS UI suite.** Two product defects surfaced (3 and 4, on the first
run); **every other iteration was a test-harness defect** — each a different way the surface resists
automation:

- a Touch Bar proxy carries the **same accessibility identifier** as the control it mirrors
- `scope.buttons[title]` over a window *query* — `.exists` true, `.click()` refuses a multi-match
- grid cells label themselves `"<column>: <value>"` for VoiceOver
- three `Outline`s on screen, so "the first disclosure triangle" is never the right one
- a fixture that asserted *the run succeeded* rather than *the rows exist*
- `accessibilityIdentifier` on a `Button` inside a **nested `Menu`** never reaches the bridged
  `NSMenuItem`. It lands on a `ScrollView` container that answers **both** `exists` and `isHittable`
  true while having no hit point — a lookup that succeeds and a press that cannot. Match nested menu
  items by their visible title instead, which is the stronger assertion anyway
- **`click()` and `rightClick()` scroll-to-visible first**, and in this grid that scroll resolves to
  a `ScrollView` with no hit point. Both must use `coordinate(withNormalizedOffset:)`. These are one
  defect at two call sites a line apart; they were fixed in two separate runs because the class was
  not recognised the first time

**The class worth carrying, which cost more than any single bug here:** *`exists` is not `clickable`,
and a lookup succeeding is not an interaction succeeding.* Four distinct failures this evening were
that same confusion in different clothes — the Touch Bar proxy, the multi-match query, the
`ScrollView` phantom, and scroll-to-visible.

**The process lesson:** three of those were diagnosed by guessing and re-running (~10 min each)
before anyone exported the UI hierarchy from the result bundle, which named the cause immediately.
*Export the hierarchy on the first failure, not the fourth.*

Also hit mid-pass: `Timed out while enabling automation mode` — the Stage 2 blocker recorded for
this Mac, returning after an interrupted run. Clearing stale `testmanagerd` did not help; it needed
the user.

## Result: 7/7, and what each test now proves

**The macOS Database UI suite passes in full** — `exit status 0`, on a machine verified quiet before
and after (project rule 21).

| Test | Proves |
|---|---|
| `testDeletingARowThroughTheGrid…` MySQL + PostgreSQL | the row context menu reaches the delete path with the row it was opened on; asserted on cell text so `beta` surviving *or* `alpha` vanishing both fail, then re-read through an independent `SELECT` because the post-commit reload is the same path that did the deleting |
| `testFollowingAForeignKey…` MySQL + PostgreSQL | the composite key `(x, y) → (a, b)` opens **exactly one** row reading `one-two`. The fixture holds both `(1,2)` and `(2,1)`, so a transposed pairing lands on `two-one` — a row that *exists*. A wrong answer cannot pass as "no rows" |
| `testRunAllStatementsRunsEveryStatementInTheScript` | one paste, one Query ▸ Run All Statements, verified by reading back **one statement at a time** so the check cannot be defeated by the thing it checks |
| `testSQLDraftSurvivesClosingAndReopeningTheWorkspace` | `onChange(of:initial:)` fires; the draft survives closing the window with its red button (never ⌘W, the deliberate discard) |
| `testTheSQLEditorPublishesItsTextAsItsValue` | `db-query-editor` carries SQL as its AX value — measured, not argued |

**"Run All Statements" is correct.** The earlier suspicion that it ran only the first statement was
**wrong**, and the error is worth recording: the scratch database was queried *after* a run and found
empty, which was read as "the fixture never populated". It was empty because the test's own cleanup
had dropped the tables — a fact already present in the activity log (`cleanup ran 3 DROP
statement(s)`). The fixture had worked all along; the grid comparison was failing on a VoiceOver
label prefix.
- The D14 prompt still has not been driven through the UI by anyone; the *fingerprint text* is now
  correct and known-answer tested against `ssh-keygen`, but the prompt itself is untested.
- **An accessibility gap, reported and not fixed** (product decision): a schema row's primary
  interaction is an `onTapGesture`, which is not surfaced as an accessibility action, and the element
  is a `StaticText` with no `.isButton` trait. Assistive technology can hear the name and invoke
  "Open Database in Tab", but cannot perform the single-click selection the row exists for.
  `tableRow` has the same shape.
- iOS and visionOS remain **compile-verified only**. The visionOS UI target cannot link at all:
  `UITests/GlassShellLocalHostUITests.swift:143` calls `.click()` on an `XCUICoordinate`, absent from
  the xrOS SDK.

## Validation

Package **811 tests / 68 suites, all passing**. `swift build` and `xcodebuild build-for-testing`
clean on macOS. Every UI run recorded the frontmost application and any competing
`xcodebuild`/`xctest` before and after, so results are attributable rather than argued about
(project rule 21 — three runs earlier this stage were discarded as contaminated).

**Nothing committed.**
