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

## 2026-09-13 (evening) — a long session driving real builds, 0.3.81 → 0.3.99

**948 tests / 90 suites.** The user ran the app on the Mac and the headset and reported what they
saw; most of what follows was found that way, not by reading code.

### Two decisions

**D24 — the family's sidebar toolbar arrangement.** On macOS, *do not remove* `.sidebarToggle`;
AppKit's own item sits at the sidebar's trailing edge, never overflows, and moves with the column.
The app's action goes on the **content** column at `.navigation`. This is glassdb's
`databaseSidebarChrome()` and glas.sh's arrangement, copied rather than reinvented — after five
attempts at owning the toggle each failed in a different way, and after
`workspaceUsesNativeTitle` turned out to be *pinning the deviation* and so requiring every fix to do
something the standard deliberately does not.

**D25 — deleting a machine deletes what its capabilities stored.** `deleteHost` removed the catalog
records and told no capability, orphaning the terminal's `ServerConfiguration`, the database's
connection and their Keychain entries — and leaving them reachable through surfaces that read a
capability's store rather than the catalog. `removeService` had always done this correctly for one
service and said so in its own documentation; deletion never called it.

### The defect class, again

Both of those, and two more this session, are the same shape recorded since Stage 2: **the
machinery exists, documented, and nothing joins it.**

- `GlassLibraryNavigation`'s `extras` builder — documented verbatim as the place to append
  "Workgroups, Network, or other specialized sections" — with both call sites using the no-extras
  convenience.
- `columnControls` in the terminal, whose comment claimed it rendered "in the detail column while
  [the sidebar] is not [visible]", called once, from the sidebar column.

That is now six occurrences. It is worth grepping for *callers* before believing a feature exists.

### Found by using the app

- Workgroups restored to the library sidebar as a contributed `GlassLibraryPanel`, and a tab in the
  visionOS tab-bar ornament.
- The connect control's caret rendered black on the accent capsule: a `Menu` does not inherit
  `foregroundStyle`, and setting it on the label content loses to the menu style. A `ButtonStyle`
  is the hook that wins — `GlassOnFilledLabelStyle` / `.glassMenuOnFilled()`.
- The app said "Quit glas.sh?" — `GlassProduct.displayName` now names it, reading the bundle.
- "Open Folder Here" *selected* the folder in its parent instead of opening it; the remote half
  works because the shell already reports its directory over OSC 7, so SFTP opens where the user is.
- Native form fields: both capabilities had a macOS-only `.frame(width: 340, alignment: .leading)`.
- Service icons moved under the machine name; split-view dividers now remembered (macOS only —
  SwiftUI exposes no equivalent elsewhere).

### Two things that are *not* finished

**The glass is over-corrected.** Making the columns honour the transparency settings fixed the seams
and left them reading as bare wallpaper at the default `ultraThin`. The user's words: *"Now this is
broken?!"* A thicker default (`.regular`, what a sidebar uses) or opaque columns — not decided, and
not changed unilaterally, because it is a look rather than a defect.

**Network/Tailscale is still a window.** Workgroups proved the panel pattern; Tailscale needs the
same split and carries more state.

### Process, honestly

Two things cost real time and both were mine. Builds went to a scratch directory for the first half
of the session while the user launched the app normally, so they spent an hour looking at **0.3.69
from the previous day** while being told about the day's changes. And a regex meant to rename ten
user-visible strings spanned unbalanced quotes in comments and rewrote **105 occurrences across 64
files**, including an enum's raw values and provenance comments; 18 files were restored from git and
the rest repaired by hand. Explicit edits, or a constant, would have been faster than either.

---

# 2026-09-15 — D26 stages 1 to 3 built

## Verified by running

| Claim | Evidence |
|---|---|
| Package suite green | **1497 tests / 161 suites, exit status 0**, measured after the key-record move. Verified by exit status, never by grepping for failures (rule 25) |
| The app builds | `xcodebuild -scheme GlassPowerTools -configuration Release`, macOS arm64. Checked separately every time, because `swift build` never compiles the App target (rule 32) |
| Installed and launched | **0.4.107 (107)** at `/Applications/GlassPowerTools.app`, version read back off the bundle (rule 16) |
| VNC against a real server | TigerVNC **1.15.0**, Ubuntu 26.04.1, `192.0.2.6:5902` — 1024×640 first frame in 0.21s, non-zero pixels |
| RDP against a real server, signed in | GNOME Remote Desktop **50.2**, same VM — refused unpinned, reporting a leaf SHA-256 identical to the certificate minted on that VM minutes earlier; pinned, a 1360×768 frame in 0.41s |
| RDP certificate refusal against Windows | Windows 11 Pro, `192.0.2.3:3389` — leaf byte-identical to the 2026-09-14 record, and it fails at the certificate before any credential is sent |

## Compiled but not verified by running

- **D26 stage 3's second half.** The final full-suite run could not complete: the Mac's screen locked
  (rule 28). The app target builds and the new suites pass; the last complete run before the lock
  was green. **Repeat the full run unlocked before treating it as proven.**
- **Neither real RDP server advertised MS-RDPEDISP.** Two of two decline it, so *resize works* is
  unclaimed for both — not a failure, a limit on what may be said.

## Still needs two devices, and no test replaces it

The D26 acceptance run, unchanged since it was written: add a host with a key on the Mac, connect
from the phone **without re-approving host trust**. That one run proves configuration sync, key
record sync and D23's pin sync together. Then: delete the connection and confirm the key survives;
attach it to a second host from a third device; generate a Secure Enclave key and confirm that
terminal does **not** appear on the phone while the database on the same host still does; and sync
twice with it in place.

## Not verified on hardware

Input, held-key release and clean disconnect over RDP — they need the session window, not a probe.
Both VMs are configured and were left running.

# 2026-09-17 — the editor after a morning of use

## Verified by running

| Claim | Evidence |
|---|---|
| Package suite green | **1,578 tests, exit status 0**, measured by exit status (rule 25). Run unlocked — a locked screen reports 104 false failures, every one of them a test that writes `.completeFileProtection` storage (rule 28) |
| All three platforms build | `xcodebuild` Release for `platform=macOS`, `generic/platform=iOS`, `generic/platform=visionOS`. Checked after **every** change that touched a view this session, because three separate breaks were invisible to the macOS build |
| Installed and launched | **0.4.158** at `/Applications/Glass Power Tools.app`, version read back off the bundle (rule 16). iPhone `00008150` at **0.4.143**, also read back off the device |
| ⌘W, ⌘O and ⌘N are contextual and single-owner | Read out of the **running app's menu bar**: `Close ⌘W enabled`, `Open File… ⌘O`, `Open SQL Document… ⇧⌘O`, `Open Project… ⌥⌘O`. ⌘W verified by use: closes a terminal tab and leaves the window; closes an editor window with no tabs |
| Swift and XML highlight | `GrammarModuleTests` colours a real fixture in each; `GrammarCoverageTests` compiles every query against its grammar; `CaptureMappingTests` caught six unmapped captures before they shipped as grey text |
| The desktop's record survives a relaunch | `D26DesktopRelaunchTests`, against a real `GlassShellModel` and a catalog file. One of the three fails without its fix — checked by reverting it |
| A second editor window is empty | `GlassEditorWindowIsolationTests`; preferences stay shared, documents do not |

## Compiled but not verified by running

- **The light-theme switch while the app is running.** Verified from a capture that Light mode
  renders correctly at launch; a system change mid-session takes the same path but was not watched.
- **iPhone and Vision Pro carry none of the editor work.** The phone is at 0.4.143 (before rounds
  two to four) and the headset at 0.4.123. Neither has an editor entry point at all — it is a Mac
  surface until stage C contributes the library panel.

## Driven on a phone, by the user, 2026-09-19

| Capability | Evidence |
|---|---|
| Editor | The full walkthrough, twice, photographed at every step, plus two UI tests on iOS 27.2 |
| Database | Schema → tables → detail, the SQL editor, the grid and its pinned chrome. Three defects and one regression found and fixed |
| Desktop | **RDP to `oscar`**: a GNOME login at 1,320 × 2,318, "Connected", with the Esc/Tab/Keyboard bar |
| Terminal | Driven in the same pass; no defects reported |

## Known and unfixed

- **No UI test reaches a database or desktop surface at all.** Both are gated on live fixtures,
  and a simulator runner does not receive `TEST_RUNNER_*`. A seeded configuration is the fix.
- **The database's compact layout is unproven by test.** Built 2026-09-19 and reasoned from the
  editor's identical defect; no UI test can reach it, because the database fixtures are gated on
  environment a simulator runner never receives.

- **The line-number strip reaches into the title bar.** `NSRulerView` spans its scroll view and is
  not inset by the scroll view's content insets. Three fixes at three different links in that chain
  all missed, and the app's own geometry could not be measured: the unified log stopped answering
  for this process and the sandbox container is closed to the shell. The fix worth making is to stop
  using the ruler and draw the gutter beside the text, where it can only occupy the text's bounds.
  Line numbers can be turned off in Settings ▸ Editor meanwhile.
- **Projects are not persisted.** Closing an editor window loses its project; stage C.
- Still owed from before: the D26 two-device acceptance run, and the test hygiene — 1,519 keychain
  items and the preference-file sprawl.

# 2026-09-17 (afternoon) — the gutter's shape, and Projects in the library

## Verified by running

| Claim | Evidence |
|---|---|
| Package suite green | **1,592 tests, exit status 0**, measured by exit status (rule 25), screen unlocked |
| All three platforms build | `xcodebuild` Release for `platform=macOS`, `generic/platform=iOS`, `generic/platform=visionOS`, after the gutter change and again after the panel |
| Installed and launched | **0.4.160** at `/Applications/Glass Power Tools.app` and on iPhone `00008150`, both read back off the installed bundle (rule 16) |
| The gutter is a sibling, not a ruler | `gutterIsBesideTheText`: subview of the container, no ruler on the scroll view, and after layout its frame matches the scroll view's band. **Proven to bite** — pinning it 28 points higher fails it, and that edit was reverted |
| Line numbers off collapse rather than tear down | `gutterVisibility`: hidden and zero-width off, 44 points on |
| The project list survives its window and merges honestly | 13 tests: tombstones survive a stale device, a later edit beats a tombstone, merge is order-independent, one folder twice is one project, one path on two machines is two, unreadable storage is an empty list |

## Compiled but not verified by running

- **The gutter's appearance.** Its frame is asserted; whether the strip stops at the tabs can only
  be seen. The app's own geometry is not measurable from this shell.
- **Projects syncing between two devices.** The payload, the merge and the local store are tested;
  the transport is the shell's proven one, but this list has never crossed a real account.
- **The Projects panel on iOS and visionOS.** Both platforms build with it and it is their only
  route into the editor; only the Mac has been run.

## Known and unfixed

- **The Vision Pro is at 0.4.123** and refuses a build while locked.
- **Stage D — the remote reader.** A project on another machine lists and says why it cannot open.
- Still owed: the D26 two-device acceptance run, and the test hygiene.

# 2026-09-17 (evening) — verified unlocked

| Claim | Evidence |
|---|---|
| Package suite green | **1,620 tests, exit status 0**, measured by exit status with the screen unlocked. A locked screen reports these as permission and mktemp failures (rule 28) and did so once today |
| The editor's remote half against a real server | **7 live tests** against `192.0.2.6` — listing, whole-file read past the 32 KiB window, stat, save, **mode preserved**, a changed file refused, no staging litter. They fail on a 30-second timeout against a dead address, so they are not passing by not running |
| All three platforms build | `xcodebuild` Release for macOS, iOS and visionOS, after every change |
| Installed | **0.4.167** on the Mac and iPhone `00008150`, read back off each |
| The desktop opens on a real iPhone | Confirmed by the user at 0.4.166; 0.4.167 reshapes the same fix to match glassDT's original |

## Known and unfixed

- **The Vision Pro is at 0.4.123** and refuses a build while locked.
- **The desktop has no UI test** and cannot have one until a desktop *configuration* can be seeded.
- The route through the UI for remote editing — Edit → a tab → save — is unproven by a test.

# 2026-09-17 (night) — the terminal configuration the Mac deleted

## Verified by running

| Claim | Evidence |
|---|---|
| A stale list destroys another device's record | `aStaleListDeletesAnotherDevicesConfiguration` — passes with the re-read, and on the old once-only path fails with *"a save on this device deleted a configuration another device had written"* |
| A service arriving after the first load is found | `aServiceThatArrivesAfterTheFirstLoadIsStillFound`, which fails if pointed back at `loadServersIfNeeded` |
| An unconfigured link can be set up rather than only deleted | `aServiceWithNoConfigurationCanStillBeSetUp`, and the older contract test updated to the new answer with its reason |
| Recovery works end to end | Re-entering the service on the Mac synced to the iPhone — user-confirmed |
| Installed | **0.4.170** on the Mac and iPhone `00008150`, read back off each |

## Known and unfixed

- **The lost configuration is not recoverable.** The fix prevents recurrence; the reconcile had
  already deleted it. Re-entry was the recovery.
- **`replaceAll` remains a whole-kind reconcile from one device's list.** Freshness is now every
  capability's duty rather than a property of the primitive.
- **`configurations(ofKind:)` skips undecodable records silently** — the same report would be
  produced by a shape mismatch between builds, with nothing logged.
- The Mac's catalog cannot be inspected from the shell: TCC refuses the Group Container.

# 2026-09-18 — the editor on a phone

## Verified by running

| Claim | Evidence |
|---|---|
| A document opens and renders on an iPhone | `README.md` on an iPhone 17 Pro simulator: content, line numbers, Markdown highlighting, footer `Line 1, Column 1 · Markdown · LF`. Photographed |
| A project opens on a phone | The editor's compact layout, its own empty state, and the Files sheet listing `Sources` and `README.md`. Photographed |
| A panel's detail is reachable on a phone | The project detail with Open/Rename/Remove, pushed. Photographed before and after |
| A failing action says why | The alert *"There is no folder at … any more"*, which the same refusal used to raise invisibly. Photographed |
| Package suite | **1,623 tests, exit status 0** |
| All three platforms build | `xcodebuild` Release for macOS, iOS and visionOS |
| Installed | **0.4.171** on iPhone `00008150`, read back off the device |

## Finding your way around on iOS — A, B and C, 2026-09-18

| Claim | Evidence |
|---|---|
| Opening a project on a phone lands on its **files** | `EditorOnIPhoneUITests`, iPhone 17 Pro simulator, screenshot `04-project-files`. The `Files` toggle's absence is asserted in the same test |
| A folder is a push; back returns | Screenshots `05-folder-pushed`, then `README.md` found again after the back button |
| Choosing a file opens the editor with its text | Screenshot `06-file-open` |
| The header names the folder, path beneath, truncated from the front | Nine unit tests on `GlassPathLocation`, and photographed on the editor's folder screens |
| **The same header in the Files browser** | **NOT RUN.** `GlassTerminalUITests.testFilesBrowserHeaderNamesTheFolder` is written and gated; macOS UI automation cannot start on this machine at present ("Timed out while enabling automation mode", reproduced with `LaunchSmokeUITests`) |
| Package suite | **1,632 tests, exit status 0** |
| All three platforms build | `xcodebuild` Release for macOS, iOS and visionOS, after every change |
| A panel's sidebar count follows its list | Two tests, both seen **red** against a stored count and green against the closure. Reported from the running app: Projects said 5 with four listed |
| Text settings cascade file over project over global | Seven tests on `GlassEditorTextOverrides`, including the decode of a project record written before the field existed |
| A project's overrides and name reach the durable list | `GlassEditorProjectKeepingTests`; the rename test seen **red** against the old path |
| A project root's landmarks are found by name | Five tests, including a folder of 3D models that correctly has nothing to say |
| One click previews, commitment keeps | Seven tests: the tab is reused, the slot's index is held, an edited preview is promoted rather than evicted, saving keeps it, closing empties the slot |
| A panel's second selection pushes its detail | Three unit tests, **and** `EditorOnIPhoneUITests.testAProjectThatRefusesToOpenDoesNotBlockTheNextOne` on an iPhone 17 Pro simulator — seen **red** against the old `hasSelection: Bool` and green against `selectedItem` |
| A panel's sidebar row is one accessibility element | Both iPhone tests failed on iOS 27.2 by matching the row's image; they pass with `.accessibilityElement(children: .combine)` |
| HTML parses and colours | `GrammarModuleTests` requires keyword, attribute, string, comment **and** embedded from a real page fixture — a query that compiles and colours nothing is the failure being guarded against |
| The keyboard can be asked for twice | `GlassEditorKeyboardRequestTests`; the serial is why a second Show works |
| Package suite | **1,663 tests, exit status 0** |
| Installed | **0.4.187** on the Mac (`/Applications`, read back off the installed bundle)  and on iPhone `00008150`, both read back off the installed bundle. The Vision Pro is still **0.4.123** |

## Known and unfixed

- **The Files browser's header has never been looked at** over a real listing — only the component
  it shares with the editor has, and only there.
- **macOS UI automation is down on this machine**, so no macOS surface can be driven or
  photographed until it is working again.
- **The Mac is still on 0.4.170** — 0.4.171 is built and waiting for the app to be quit.
- **Only the editor has been driven on a phone.** The terminal, the database and the desktop have
  the same shape and nobody has watched any of them; the desktop still has no UI test at all and
  cannot have one until a configuration can be seeded.
- The Vision Pro is still at 0.4.123.
