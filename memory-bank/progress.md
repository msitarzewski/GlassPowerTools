# Progress

Updated 2026-09-10.

## Done

- The decision to merge, with its reasoning and its costs, recorded in [decisions](decisions.md).
- This memory bank and the project guide.
- The staged [merge plan](tasks/2026-09/2026-09-10_merge-plan.md).
- Measurements the plan depends on: source sizes, bundle identifiers, shared entitlement groups,
  deployment targets. See [technical context](techContext.md). Re-verified 2026-09-10 at
  `~/Software/glass/GlassPowerTools` and unchanged.
- The bank reconciled with the actual workspace: project path corrected, sibling layout recorded, and
  the two siblings that are not inputs identified.

- The project-model decision: one multiplatform target, hand-maintained, approved 2026-09-10.
- Stage 1 planned against real APIs and real file locations:
  [task note](tasks/2026-09/2026-09-10_stage-1-shell.md). Its pre-steps and six decisions are
  listed there for the user.

- **Stage 2 at unit-level parity on 2026-09-10** (`6e5ffe6`…`410d0fc`): `GlassSSHTransport`
  engine (61 tests, security review clean, SFTP extensions/times, key-header probe); glas.sh moved
  in as `GlassTerminal` (348 tests, all pass after the inherited-PR fix); `ConnectionManagerView`
  deleted after re-homing; layering proven on the connection panel and visionOS terminal chrome;
  settings merged through three shell hooks; window recovery and settings sync moved to the
  shell; "choose a key file" delivered; one row per host with all service icons. **Whole package:
  461 tests in 23 suites pass.** Builds on macOS (real profile), iOS Simulator, visionOS Simulator.

## Not done

- **Stage 2 still open:** real-host session through the shell (integration worker; the CLI suite
  waits on the Local Network grant for Ghostty), UI suites on the final tree (blocked until the
  integration worker's `GlassTerminalUITests.swift` compiles), the macOS accessibility-recursion
  crash under XCUITest (analysis in progress), device re-installs of the Stage 2 build, widget
  verified on a device, iCloud settings sync verified live.


Stages 2–5. Stage 2 (SSH engine and terminal) is in progress with two workers; no capability has
reached parity yet. The public repositories are untouched.

## Known unverified assumptions

- That a new bundle identifier declaring the existing App Group and Keychain access group inherits
  current hosts and credentials in place. Now concrete: all three apps read
  `<App Group>/GlassHostCatalog/hosts.json`, so it should. Still proven only on a test build
  (Stage 1 step 1.8).
- That capability code moves largely intact. Measured by line count and structure, not by attempting
  it.

## Carried forward from glassDT, still open there

- Whether a GNOME sign-out now closes the session window rather than showing a failure panel.
- Whether the RDP Detail scale setting sharpens text on the user's Ubuntu host or merely shrinks the
  interface, which decides whether Automatic stays the default.
- A session indicator for encrypted versus unencrypted connections, and an SSH tunnel for VNC.

## 2026-09-11 checkpoint — Stage 2 close-out in progress

Verified: whole package 469 tests / 28 suites (W6, twice); engine real-host suite 5/5 (coordinator,
before the VM went down); kit 53/53; macOS, iOS Simulator and visionOS Simulator builds; iPhone UI
suites 7/8 (real-host test blocked by the VM being down); Mac library window, "+" placement, flat
detail column and no-sandbox local terminal judged by eye on the installed Release build.
Landed since the last checkpoint: macOS regression (three causes) and integration defects 1–5
(W4), close-out cleanup, system-wide tag field (W5), host-level address (W6), settings tabs per
platform, 3 pt canvas margin, panel roles, sandbox removal.
Open: macOS XCUITest automation mode blocked on this Mac; macOS accessibility recursion after the
connection-failure alert under XCTest diagnostics; widget on device and live iCloud sync unproven;
visionOS UI suite not re-run since the TabView change; kit changes uncommitted in the sibling repo.

## 2026-09-11 morning — Stage 2 functionally verified on Mac and iPhone against the real host

macOS: all UI suites green with the real host (library, tag field, smoke, terminal chrome, settings
pages, real-host connect to a live shell). iPhone: all suites green with the real host. Package
472 tests / 28 suites. Engine real-host suite 5/5. Fourth /Applications build pending install.
Remaining for Stage 2 close-out: visionOS UI re-run, widget on a device, live iCloud sync,
W4's post-failure accessibility recursion, the "Set Up…" bypass of the address gate.

## 2026-09-12 — Stage 3 waves 1–2: the Database capability, proven against real servers

**Verified.** Package **592 tests / 45 suites**, one known issue (D13). App builds on macOS, iOS
Simulator and visionOS Simulator with the capability registered. **12 gated live tests** against real
MySQL 8.4.11 and PostgreSQL 18.6: both engines connect through the capability, schema and foreign
keys, real rows, the read-only guard refusing a real `UPDATE` with rows read back unchanged, and
both engines **over a real SSH forward** with read-only still holding — so D7 is tested, not asserted.
MySQL additionally proven against a **flushed** auth cache, which is the only run that exercises
mysql-nio's RSA path on swift-crypto 4.5.2, a combination this port created.

**Landed.** `Sources/GlassDBKit` (engine, minus the tunnel manager — the swift-crypto conflict
dissolved with it); `Sources/GlassDatabase` (glassdb's app files, Database tab live in the one
sheet); D7's brokered forward; D14's trust prompt via a second source rather than a second prompt;
D15's read-only guard on the connection; D12's floor guard extracted to `GlassLayers`.

**Defects found by running, not reading.** Two independent PostgreSQL foreign-key bugs: an
owner-scoped `information_schema` view that returned nothing for non-owning accounts (an empty tab,
indistinguishable from a table with no keys), and composite keys returned as a **cross product**
asserting relationships that do not exist. Both fixed; the test that found the first now guards both.

**Open and honest.**
- **D13** — no way to trust a self-signed database certificate. Needs a CA-only verification mode
  *and* a CA import path; both MySQL and PostgreSQL self-sign by default.
- **Two ~10s tunnel failures, unexplained.** Three hypotheses proposed — cold-cache, contention,
  reverse DNS — **all three refuted by measurement**, two of them the coordinator's. Instrumented
  with `log_error_verbosity=3`, a counter baseline and a three-signature discriminator table,
  because three different things fail at exactly ten seconds on that path.
- **Unproven by anyone:** the D14 fingerprint prompt through SwiftUI. It needs a person, not a test.
- The macOS UI suite figure is unattributable until W-local settles; a drag-staging flake is unowned.
- Whether existing glassdb users get an import path for saved connections — credentials and hosts
  carry across the App Group and Keychain, **the connection list does not**. Awaiting the user.

**Nothing is committed.** 48 files in the working tree.

## 2026-09-12 (afternoon) — shipped to /Applications, and corrected by using it

Builds **0.3.56 → 0.3.67**, each installed with the version read back from the installed bundle.
**615 tests / 48 suites**, one known issue (D13). **Nothing committed — 63 files in the tree.**

**Verified by the user in the running app:** the canvas border, the service tabs, the colour menus,
the `tinyint` fix, and — the important one — a database connecting over the D7 tunnel to a
loopback-only MySQL on a Tailscale host.

**Closed: the two unexplained ~10s tunnel failures.** The SSH forward dropped a server-first
protocol's opening bytes; MySQL greets immediately, and the channel was wrapped in a
`NIOAsyncChannel` only after the open returned. Fixed by wrapping inside the channel initializer —
[note](tasks/2026-09/2026-09-12_ssh-forward-server-first.md).

**Three defects that passed every test**, each found by a person using the app: that forward bug
(the live tunnel test cannot catch it), `isBool` matching a bare `tinyint` so a score column
rendered as a toggle and **would have written 0 over real data**, and temporal columns accepting any
string at all. Rule 22 now records why the suite could not reach them.

**Also landed:** record-editor validation for size and format from the *declared* type (D17),
"Paint Theme Color" removed, the database name made optional, service tabs as the choice,
`Set to NULL` in the column tool row, and a Release-only link failure fixed by **not** sharing a
result-builder availability guard across modules (D16).

**Two self-inflicted regressions**, both now rules: a deleted `.toolbar(removing:)` line
investigated everywhere except the diff (rule 23), and an unverified mechanism propagated to a
worker (rule 19).

**Next, and re-planned against the code that exists** — see *Remaining work, re-planned* in the
Stage 3 plan. R1 the SQL draft-loss fix (in-memory only; it loses work), then row deletion and
foreign-key navigation. Two original estimates were wrong: AI on iOS is already done, and the audit
viewer has **no store to view** — only `os.Logger` output — so it needs a decision first.

## 2026-09-12 (evening) — Stage 3 remaining work R1–R8 closed

**711 tests / 61 suites, no known issues.** D13's `withKnownIssue` is gone because the defect is
fixed, not suppressed. Three workers in parallel plus the coordinator; nothing committed at time of
writing.

Done: the SQL draft-loss fix (and a **second instance** the worker found itself, `tableSQLDrafts`);
row deletion, with *a row edited underneath the user reporting 0 against both real servers*;
foreign-key navigation that **fails closed** on a repeated ordinal, so this morning's cross-product
defect cannot return through it; the mutation audit viewer, storing the predicate's shape and never
its parameters; settings folded onto the one `GlassLayerStore`; one command palette; D13's
certificate trust with the connection detail now saying *what* TLS verifies; PostgreSQL array
formats; and ~1,295 lines of unreachable `ConnectionFormView` deleted.

**The correction worth carrying:** an engine-level test proved the *engine* could do `VERIFY_CA` —
it could not prove a saved record reaches it. Until `transportPlan` mapped the mode, every piece
existed and nothing joined them. Only a **capability-level** test tells those two states apart.
"It works" and "the parts that would make it work all exist" look identical from below.

**Open, and none of it is code.** Driving deletion and a foreign-key follow through the running app;
the D14 fingerprint prompt; whether SQL-draft restore fires at all; iOS and visionOS, still
compile-verified only. **No test in this stage opens a window.** Plus `text`/`blob` limits at six of
eight MySQL families — bare `text`/`blob` left unconstrained rather than wrongly limited, since a
missing limit only fails to warn while a borrowed one silently refuses storable data.

## 2026-09-12 (night) — Stage 3 device pass: the Database UI suite passes 7/7

**`UITests/GlassDatabaseUITests.swift` is the first test in this product to open a window on the
Database capability, and it passes in full** — `exit status 0`, machine verified quiet before and
after (rule 21). Package **811 tests / 68 suites**, all passing. **Nothing committed; 73 files.**

**Driven through the real UI for the first time:** row deletion on **both** MySQL and PostgreSQL;
a **composite** foreign-key follow landing on exactly one row, against a fixture holding both
`(1,2)` and `(2,1)` so a transposed pairing lands on a row that *exists*; Run All Statements
executing every statement; SQL-draft restore; and the SQL editor publishing its text as its AX value.

**Two questions that had been open since Stage 3 began are closed by observation, not inference.**
Draft restore fires — `onChange(of:initial:)` had been *read* and never watched. And
`db-query-editor` really does carry SQL as its value, which was a mechanism argument until measured.

**Six product defects, none visible to 800 passing unit tests.** Full table in
[the device-pass note](tasks/2026-09/2026-09-12_device-pass.md). The two a user would have hit:
the **entire Database menu bar was attached to nothing** (`DatabaseCommands`' only reference was its
own declaration — ⌘↩ Run, ⌘N/⌘O/⌘S, the whole Query menu, all unreachable), and **"Open in New
Window" pointed at a window group that does not exist**. Both found on the suite's first run.

**~100 tests added to five modules that moved from glassdb with none** — `SQLHighlighter`
(D15's read-only gate delegates to it), `SQLiteFileImporter.validatedURL` (its result is passed to
`removeItem`), `SchemaContext`, `GridServerQueryBuilder`, `GridExportFormatter`. **Every one was
already correct.** The gap was that nothing guarded them, which is a quieter risk than a bug: a
future "simplification" of `validatedURL`'s component walk into a `hasPrefix` would have passed
review.

**Two corrections worth carrying, both mine.**
- I reported that "Run All Statements" ran only the first statement of a script. **It does not — it
  is correct.** I queried the scratch database after a run, found it empty, and read that as a
  fixture that never populated; it was empty because the test's own cleanup had dropped the tables,
  which the activity log already said. The real cause was a VoiceOver label prefix on grid cells.
- I concluded the Follow Reference submenu "cannot be opened by any synthesized gesture" and had
  written that into a skip. The activity trace then showed the composite follow **working**. The
  actual fault was `click()`/`rightClick()` scrolling to visible against a `ScrollView` with no hit
  point, two call sites one line apart.

**The transferable class, which cost more than any individual bug:** *`exists` is not `clickable`,
and a lookup succeeding is not an interaction succeeding.* Four separate failures were that same
confusion — a Touch Bar proxy sharing an identifier with the control it mirrors, a multi-match query,
an identifier landing on a `ScrollView` instead of a nested `NSMenuItem`, and scroll-to-visible.
**And: export the UI hierarchy from the result bundle on the first failure, not the fourth.**

**Still not verified by anyone:** the D14 fingerprint *prompt* through the UI — the fingerprint text
is now correct and known-answer tested against `ssh-keygen`, but nobody has driven the prompt. iOS
and visionOS remain compile-verified only; the visionOS UI target cannot link
(`GlassShellLocalHostUITests.swift:143` calls `.click()` on an `XCUICoordinate`, absent from xrOS).
An accessibility gap is recorded and deliberately unfixed: schema rows expose no accessibility action
for the single-click selection they exist for.

## 2026-09-13 — visionOS UI testing unblocked, and the macOS regression it exposed

**One unguarded call had blocked an entire platform's UI verification.**
`GlassShellLocalHostUITests.swift:143` called `.click()` on an `XCUICoordinate`.
`XCUIAutomation/XCUICoordinate.h` declares it `API_AVAILABLE(ios(15.0), macCatalyst(13.0))`, and
visionOS does **not** inherit that the way it inherits most iOS availability — the Swift interface
has no `click` member, so it is a hard compile error on xrOS. `tap()`, `doubleTap()` and
`pressForDuration:` carry no annotation and exist everywhere. The file already split click/tap for
*elements*; it had no coordinate overload. Because the fault broke **linking**, it failed the whole
target rather than one test, which is why it read as "visionOS cannot be tested".

Verified from the SDK header on this machine and by building, not from the web, which had nothing
specific. The secondhand explanation was checked before being believed — visionOS usually *does*
inherit iOS availability — and it held.

### What running it found, and the correction that matters

First run: **10/16**. The six failures looked like visionOS problems. They were not.
**macOS failed identically** — same tests, same lines — so the real finding is that

> **the macOS shell library suite had regressed from 7/7 to 3/7 and nobody noticed.**

Two changes the user asked for had invalidated four tests, and the suite was never re-run:

| Change | Test that still assumed the old behaviour |
|---|---|
| *"Adding a machine without a service doesn't make sense"* | three tests added a service-less host; Save was **correctly refused** |
| *"Painting the glass isn't optional"* → Paint Theme removed | one test drove `layers-paints-theme`, which by then existed **only in the test file** |

Both product changes are right. The tests were stale. **And the failure message actively misled:**
*"the sheet closes after Save"* reads like a dismissal bug when the truth was validation working and
an incomplete form being refused. A fifth test had become internally *incoherent* rather than merely
stale — it built a service-less host then added a terminal, so under the new rule the host had two
ssh services and Edit opened the first while the assertions described the second.

**The rule worth carrying: a suite recorded green is only green as of its last run.** The memory bank
said 7/7 as of 2026-09-12 and that was true when written; two deliberate decisions silently voided it.

### Results

| Suite | Result |
|---|---|
| macOS `GlassShellLibraryUITests` | **7/7** (recovered from a silent 3/7) |
| macOS `GlassTerminalUITests` | **4 passed, 1 skipped** (gated real-host) |
| macOS `GlassDatabaseUITests` | **7/7** |
| visionOS full UI target | **12/15**, from a target that could not link at all |

visionOS's three remaining: the Material picker does not take a selection there the way it does on
macOS (the rewritten appearance test); `testEditTerminalOpensTheSheetWithAdvanced`, fixed on macOS and
not yet re-run there; and the **pre-existing Stage 2** tag-vocabulary failure, which fails on macOS too
and is tracked separately.

### Mistakes recorded in the helpers rather than quietly fixed

Both are easy to reintroduce by someone simplifying them:
- The verifying `type()` helper must **not** touch a `SecureTextField`: its value is bullets or nil so
  the check can never pass, and re-pressing a focused secure field **drops focus**. The field that
  actually needed verification was the *username*, a plain text field, swallowed on visionOS after a
  tab switch. Writing a general helper for a specific fault broke a working path.
- On a **cold launch** the first sheet's secure field has not taken focus when `typeText` dispatches.
  `setField` — already in `GlassTerminalUITests` — handles this because it presses, calls
  `selectAll()`, then types. That `selectAll` is the focus guarantee. Three hand-rolled versions were
  written before the existing helper was reused.

### Operational note

Two OOM kills during this session, both from accumulated test artefacts: **37 worker DerivedData
directories (~99 GB)** and **XCUITest result bundles carrying full screen recordings** (~6 GB over
twenty-odd runs). Neither is obvious until the machine complains. Clear the scratchpad between long
UI campaigns.

## 2026-09-13 (later) — GlasSecretStore absorbed, D23, and the last standing UI failure closed

**`Sources/GlasSecretStore` is now part of this repository.** 15 source files and 9 test files moved
in verbatim; the module name is unchanged so none of the 36 files that import it changed a line. The
`.package(path: "../GlasSecretStore")` dependency is gone and `GlassPowerTools.xcodeproj` needed no
edit — it references `.` as its only local package. `LICENSE` (MIT) is now at the repository root.

**Package: 946 tests / 90 suites passing**, from 847/74. Three of those are recorded **skipped**, not
passed — see below.

### D23: host trust travels, and the defect that answering the question exposed

The open item was *"should pinned SSH host keys sync?"*. Reading the call sites to answer it showed
host trust **did not work**: D18's fix had moved the transport's trust store to a device-bound
configuration and left `KeychainManager.savePinnedHostKey`, `replaceHostKey`, `allPinnedHostKeys` and
`trustedHostKeyBase64Set` — where the **trust prompt** writes — on the synchronizing one, which
`validateMobility` refused. Accepting a fingerprint threw `ineligibleService`. And even without the
throw, a synchronizable Keychain item and a device-only one with the same account are *different
items*, so a pin written on connect was invisible to the prompt.

A pinned host key is a **public** key, and re-approving every machine on every device is the thing
the continuity requirement exists to remove. So `sshHostTrustService` is eligible now, the eligible
set moved out of `validateMobility` onto the configuration as the public
`SecretStoreConfiguration.synchronizableServices` — so a caller can ask the question the validator
answers — and `KeychainManager.hostTrustConfig` is the one name for where pins live. Secure Enclave
services stay off the set permanently. Full account in [decisions](decisions.md) under **D23**.

### Why 800 unit tests could not have caught either defect, measured

**No `swift test` process can write a synchronizable Keychain item at all.** `SecItemAdd` with
`kSecAttrSynchronizable: true` returns `errSecMissingEntitlement` (-34018) with *and* without the
data-protection Keychain, because the item needs `com.apple.application-identifier`; ad-hoc signing
the test binary with that entitlement gets the process killed on launch. Both measured here, not
inferred. The real-host integration suite passes an `InMemoryHostTrustStore`, so it proves SSH works
and proves nothing about storage.

`HostTrustSynchronizationTests` therefore **reports skipped with that reason** rather than passing
vacuously; its refusal half runs everywhere. The proof is
`testConnectsToRealHostThroughTheShell` against the live VM, which reaches the D14 prompt, accepts
it, stores the pin under the app's real configuration and connects — **the first time anything has
driven that prompt.** Getting there needed one harness fix: the trust button was looked up
application-wide and kept resolving to the Touch Bar's copy, which refuses every click.

### The Stage 2 tag-vocabulary failure was never a product defect

`testCollectionsAreChipsAndFeedTheSystemWideVocabulary` had been failing since Stage 2 and is now
passing. **Two stale assumptions, no app bug:**

1. The add-host sheet arrives with the Terminal service selected — *"adding a machine without a
   service doesn't make sense"* — so Save was **correctly refused** with
   `add-server-username-validation = "Error: Enter the SSH username"`. The test never filled the
   service. Same class as the four `GlassShellLibraryUITests` cases that decision invalidated; this
   suite was missed when those were repaired.
2. The sidebar's collection row publishes its text as the element's **`value`** and leaves `label`
   empty, so `label CONTAINS[c] 'Clients'` could never match however right the app was.

**Two process notes worth more than the fix.** The first guess — "a service is required, so
`validateForSave` rejects a service-less host" — was *wrong*: `validateForSave` requires no service;
the enabled Terminal draft's own validation fails. Reading the source before acting caught it. And
the first diagnostic added to find out **failed from inside itself**: it enumerated
`app.staticTexts.allElementsBoundByIndex`, each read takes its own snapshot, and with the UI still
settling it raised "No matches found for Element at index 34" and — with
`continueAfterFailure = false` — failed the test, hiding the failure it was added to explain.
`debugDescription` on a single window or sheet element is one snapshot and cannot race with itself.

### Also corrected

`AGENTS.md` said the source applications "must keep building until this product reaches parity" and
named `../GlasSecretStore` as the owner of credentials. Both were stale and actively misleading;
`memory-bank/toc.md` still said nothing had been built. Corrected.

## 2026-09-13 (later still) — visionOS design pass 1

**The user's verdict, from the physical headset:** *"pay attention to the design. it's terribly
off… These are functional, but don't provide that polished magic visionOS experience."* Scope agreed
as native visionOS HIG **plus** the Glass/transparency/theme language, sequenced **before Stage 4**
so the desktop capability is built into the right patterns rather than inheriting the flat ones. The
governing constraint: *"this should feel familiar to a Mac user, but should be visionOS magic to
use"* — the information architecture stays; presentation and interaction change.

### The premise was wrong, and measuring it first saved building on sand

The expectation was that the source apps already carry most of the spatial language. Counted:
glas.sh has 4 `glassBackgroundEffect` / 9 `.ornament` / 2 `hoverEffect`; glassdb and glassDT have
**none**; this product already had 3 / 6 / 2 and GlassConnectionKit 3 / 4 / 0. glas.sh's vocabulary
is essentially what already moved across. What the source apps *did* carry, and what genuinely is in
place, is the Glass language itself — `Sources/GlassLayers`, its two independent dimensions and the
four frost materials mapped to glas.sh's persisted values. **HIG conformance is new work in all four
codebases**, and saying so up front was better than discovering it late.

### Two faults where the app was fighting the platform

Neither was missing polish; both were the app actively overriding visionOS.

**The window painted over the system glass.** At the default state (`opacity` 0, `frost` 1) the whole
window was filled with `RoundedRectangle.fill(.ultraThinMaterial)`. A `Material` is a *2-D
simulation* of glass — on a Mac it samples the desktop behind the window and convinces completely,
which is why this was never wrong before. In a headset it composites as an even translucent sheet
with no specular edge and no response to the room's light, covering the real glass with a
convincing-looking grey rectangle. `GlassLibraryDetail`'s `.background(.bar)` was the same fault one
control smaller.

**The seam was our own padding.** `GlassNativeWindowFrame` inset content 22/34/26 pt to clear the
title and control ornaments — and applied it even when neither ornament is shown. The library shows
neither, so its `NavigationSplitView` floated inside the window and visionOS drew the sidebar surface
inside the inset: a darker rectangle with a seam on all four sides. Removing the frost is what
*exposed* it; under a grey plate it was invisible.

### Also in pass 1

Primary actions moved from `.toolbar(.primaryAction)` — three ~30 pt circles inside the window's
corner — to an ornament below the window. The spatial sidebar widened to 320–460 pt instead of
shrinking the row to fit it. Row Connect went from `.caption`/4 pt to `.body`/9–12 pt, past Apple's
60 pt gaze target. Row type from `.headline`/`.caption` to `.title3`/`.callout`, visionOS only.
`hoverEffect(.highlight)` on rows, because a control that does not answer a look reads as disabled.
The empty detail given the pane rather than floating as a card in it. The host sheet enlarged with
large controls.

`GlassSpatialMetrics.swift` holds every spatial number in one place, as no-ops or pass-throughs off
visionOS. **No macOS metric changed** — by construction, and proven by macOS UI staying 25/25.

### Two capture facts, measured, that cost two failed runs

- **The visionOS simulator cannot screenshot through XCUITest at all** — *"Unable to take a
  screenshot - remote interface does not have this capability."* A suite that snaps on every step
  fails there for that reason alone, nothing to do with the app.
- **`xcrun simctl io <udid> screenshot` works.** So the loop without a headset is build → install →
  launch → `simctl` screenshot. That shows layout — and it is what caught both structural faults —
  but not how glass behaves in a real room.

### The gap, stated plainly

**Nothing in pass 1 has been seen on the headset.** It locked at *"Unlock My Vision Pro to
Continue"* before the first change and stayed locked. The simulator renders glass differently from
hardware, which is exactly what pass 1 altered, so the frost and inset fixes are **unconfirmed**.
Also still undiagnosed: two on-device UI failures that pass on macOS.
