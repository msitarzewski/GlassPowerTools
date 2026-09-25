# Project rules

These sit on top of the four core rules in [AGENTS.md](../AGENTS.md) and apply to the merge.

1. **Move, do not rewrite.** Capability code arrives as modules. Rewriting working functionality to
   make it fit the new shell is how a merge turns into a rewrite and loses a year.
2. **Draw the shell boundary before the second capability.** Otherwise the first capability's
   assumptions silently become the boundary.
3. **The source apps keep building until parity.** They are the working software. Nothing in
   `../glas.sh`, `../glassdb` or `../glassDT` is deleted, moved or reset as part of this work.
4. **One capability reaches parity at a time**, with its own validation, before the next starts.
5. **Never present a moved capability as working because it compiles.** Parity means its own tests
   and native workflows pass here.
6. **The shell depends on no capability**, and capabilities do not depend on each other.
7. **Protocol engines never depend on the shell.** They stay independently testable, and remain
   candidates for process isolation later.
8. **Preserve user data.** The bundle identity, App Group and Keychain group decisions are made once,
   proven on a test build, and recorded. No silent migration or reset.
9. **Public repositories are not touched** without explicit instruction, including archiving,
   redirecting or renaming.
10. **No Git initialisation or commits** as an incidental part of any task.
11. **UI tests capture elements, never the screen.** `XCUIScreen.main.screenshot()` on a
    multi-display Mac captures other applications' windows. Use `element.screenshot()`; on the
    visionOS simulator, where in-test captures are 1×1, use `simctl io screenshot` outside the test.
    (Found 2026-09-10; the offending captures were deleted.)
12. **Superseded 2026-09-11.** The "never sheet-on-sheet on macOS" rule came from a crash that W4
    bisected to the SSH Key row's accessibility label (an `.accessibilityElement(children: .ignore)`
    label over a text-and-button stack), not to nested sheets. Nested sheets are allowed; modal
    editors follow rule 15.

13. **Layered panels declare their role.** `GlassLayeredPanel(role:)` is `.presented` for a sheet,
    popover or secondary window (paints theme + frost on every platform) and `.embedded` for a
    column or region inside a `GlassLayeredWindow` (paints only on visionOS, where panels float;
    pass-through on Mac, iPad and iPhone, whose window already paints edge to edge). Never nest a
    painting panel inside a layered window on the Mac: it double-paints the theme, clips the
    detail's action bar into a lighter band and exposes the window corner (observed 2026-09-10).

14. **No ornaments for controls inside visionOS sheets.** A `TabView`'s ornament and a hand-built
    `.ornament` both vanish from the accessibility hierarchy when their host is a sheet on visionOS
    (element trees captured 2026-09-11 show only the page content; no tab bar in any window).
    Section pickers and similar controls presented in a sheet live inside the surface — the
    settings sections use a leading column of vertical tabs there.

15. **Apple HIG patterns by default.** Unless the user explicitly asks otherwise, every surface uses
    the platform's native pattern. Modal editors (server form, SSH key, host, service) are sheets
    with a title header, a grouped `Form`, and the standard bottom bar with Cancel and the primary
    action bottom-trailing — the "Add Terminal to <host>" sheet is the reference. No custom
    title-bar buttons, no columns-style forms in windows for what is a save/cancel editor.

16. **Verify the version after every install.** A failed build leaves the previous product in
    derived data, so installing on a stale bundle looks successful. Stamp device and Mac builds with
    `CURRENT_PROJECT_VERSION`/`MARKETING_VERSION` from the commit count and read
    `CFBundleShortVersionString` back from the installed app before reporting it.

17. **The app icon is an Icon Composer document, and its layers are the delivered artwork.**
    `App/GlassPowerTools.icon` carries one layer per element with `image-name-specializations`, so
    light and dark use different *artwork*, not just different fills. Light variants are generated
    from the delivered renders by a gamma curve on neutral pixels — never redrawn, never flattened
    to grey, and never applied to the prompt glyph, which is white in every appearance because it
    sits on the red screen. Clear and tinted belong to the system; do not author them. Verify a
    change with `actool` plus `assetutil --info`, and say plainly that only the default appearance
    can be rendered from the command line.


18. **Verify a rule's placement at the call sites, not from the API's shape.** Three Stage 3
    defects shared a shape: the type signature suggested where a rule belonged and the call sites
    decided otherwise. Read-only looked like it belonged in `executeQuery`; five write paths reach
    the driver without it, so a guard there would have protected nothing while looking correct
    (D15). `.requiredCertificates(_, serverName:)` looked like it could pin a CA; no string works
    against a stock MySQL certificate, and the app never constructs that case at all (D13).
    `information_schema` looked like the portable way to read foreign keys; it is owner-restricted,
    so the tab rendered empty for non-owning accounts. So: grep every call site before placing a
    guard, and where a real server is involved, test against a realistic **account**, not just a
    reachable server. A permission-shaped defect is invisible to compilation, to unit tests and to
    reading.

19. **State a mechanism only after checking it — a confident wrong explanation travels.** The
    coordinator explained a failing tunnel test with "MySQL keys its auth cache by source address,
    so a forward is a different entry from the direct path." Plausible, confident, and wrong: the
    cache is keyed by the **matched account**, and only `gpt_test@%` exists. The cost was not the
    wrong idea but its distribution — a worker took it on trust and wrote it into a task note as
    grounds for withdrawing a sound result, and a controlled test then refuted the theory outright.
    When explaining a failure to anyone else, say which parts are **measured** and which are
    **hypothesis**. "I do not know why yet" is safe to propagate; a confident wrong explanation is
    not, because it gets acted on. Two corollaries: never record "it passes now" as a resolution —
    it passed before, too; and **retract in place rather than delete**, because the route an error
    took is more instructive than the corrected fact.

20. **A capability is asked for, never inferred from the presence of a service.**
    `host.services.contains { $0.kind == .ssh }` reads like "can this machine lend a forward?" but
    asks "does it have a Terminal service?" — the same question only while every Terminal service
    was a real SSH connection elsewhere. The built-in local host has one and is deliberately
    excluded from the broker (D8); so will a missing credential, an unreachable jump host or an
    unregistered capability. It went wrong twice in one stage, in the shell's forward provider and
    in the database capability's Advanced row, and **neither failed at connect time**, which is why
    both would have shipped. Ask `GlassCapabilityHostAccess.canForwardPorts` — **including from UI
    that only means to describe it**, since the second judgement is the one nobody tests.

21. **Only one macOS UI suite may run on this machine at a time.** XCUITest drives the app with
    synthesized events, which go to the **frontmost** application, so two runs interfere by
    construction and surface as `Failed to synthesize event: Timed out while synthesizing event` —
    an event-synthesis timeout, not an assertion failure (the hazard is already noted at
    `UITests/GlassShellLibraryUITests.swift:42`). Three runs were discarded in one session for this,
    two of them the coordinator's. **Checking at launch is not enough:** a run is attributable only
    if the machine was quiet for its *whole duration*, and a suite that starts clean is still
    contaminated by an instance appearing halfway through. Announce a UI run before starting it. When
    a UI test fails with an event-synthesis timeout, the first question is **what else was on
    screen**, not what changed in the code. And "passes in isolation" is weaker evidence than
    "passes in the suite" — re-running one test alone shows it *can* pass, not that it passes where
    it failed.

22. **A green test is not a green feature: the shape of the test decides what it can catch.** Three
    Stage 3 defects passed every test that existed. The SSH forward dropped a server-first
    protocol's opening bytes — the live tunnel test could not catch it, because the test server
    listens on `0.0.0.0` and the race depends on packet coalescing. `isBool` matched a bare
    `tinyint`, so a score column rendered as a toggle and would have saved `0` over real data — no
    test held a `tinyint` that was not a boolean. Temporal columns accepted any string at all. Each
    was found by a person using the app against their own data. So: when a feature's correctness
    depends on **someone else's** schema, server configuration or timing, say plainly what the
    suite cannot reach, and get it in front of real data before calling it done.

23. **Before investigating a regression, read your own diff.** The macOS sidebar toggle drifted into
    the `»` overflow after a line was deleted as an apparent duplicate — `.toolbar(removing:)`
    applied twice, where once is not enough. An investigation went looking at how macOS re-homes a
    collapsed column's toolbar items and reported "still open, needs watching"; `git diff` on the
    one edited file would have answered it in seconds. A failing test that deliberately collapsed
    the sidebar was pointing at it and was misread as protecting an intentional decision. When
    something worked recently and does not now, the first question is what changed, and the cheapest
    place to look is the uncommitted diff.

24. **A negative claim needs more evidence than a positive one.** "There is no audit store" was
    written into a plan after grepping for `auditLog`, `AuditEntry` and `writeAudit`, finding
    nothing, and checking that no `os.Logger` category was named for it. The store existed as
    `MutationAuditRecord` / `MutationAuditStore` with eleven call sites already writing to it, and a
    worker nearly built a second one on the strength of the claim. A positive finding carries its own
    evidence — here is the line. A negative one only ever proves **where you looked**. So search for
    the *concept* and not the name you expect: the behaviour, the call sites, the persistence key,
    the types it would have to produce. And when reporting one, say what you searched for, so the
    next reader can see the shape of the hole rather than trusting the conclusion.

25. **Verify a test run by its exit status, never by grepping for failures.** A target that aborts
    prints no `✘` line *and* no `Test run with N tests` line, so a pipeline that greps for failures
    and sums the counts sees a crashed target as neither — it reports success, with a plausible
    total. `GlassEditorCoreTests` aborted from `57bca0b` until 2026-09-15 and **320 tests in 36
    suites** were silently missing from every figure reported in between. Check `$?`, and read the
    `Note: Some test targets reported failures:` trailer; it did appear, and was misread as being
    about a different target. A count that cannot be wrong is worth more than a count that is
    usually right.

26. **Never `git checkout --` a file that has uncommitted work in it.** Defeating a rule to prove a
    test bites is right; undoing that defeat with `git checkout` is not, because it reverts
    everything else in the file too. It destroyed a finished implementation mid-session on
    2026-09-14 and cost a full reapplication. Edit the defeat back out in place, or stash only it.

27. **A test written against the wrong projection looks exactly like a passing test.** Two on
    2026-09-15. `aSecondServiceAtTheSameAddressJoinsTheMachineAlreadyThere` asserted on
    `catalogHosts` and passed with address reuse disabled, because `GlassShellHostGrouping` already
    merges records that share an address into one row — the duplicate record was real and invisible.
    The SQL scanner pen test passes with pen finding M-5 present, even under AddressSanitizer,
    because the bug is state loss rather than a memory error. So: **defeat the logic and watch the
    test fail** before trusting it, and when it still passes, the test is pointed at the wrong thing
    — not the bug at nothing.

28. **`mktemp` / `NSCocoaErrorDomain Code=513` in a test means the Mac's screen is locked, not that
    the code is broken.** The catalog and several stores write with `.completeFileProtection`, and
    those writes fail while the screen is locked — surfacing as *"Creating a temporary file via
    mktemp failed… errno 1"* **and** as `NSCocoaErrorDomain Code=257 "Operation not permitted"` on a
    *read*. Both read like a permissions or sandbox fault and neither is. **Most of the failures
    will not carry the signature at all:** on 2026-09-15 a locked screen produced 100 failures, 89
    with it and 11 that were simply assertions downstream of a catalog write that never happened.
    Count them — if every failing test writes protected storage, that is the answer. It
    cost a long diagnosis on 2026-09-13 (116 failures) and again on 2026-09-15, where it first
    looked like a hang because the failure was being swallowed. **Check it first:**
    `ioreg -n Root -d1 -a | grep -A1 CGSSessionScreenIsLocked`. Ask the user to unlock; do not
    change code in response to it, and do not report the run as a failure of the work under test.

29. **A process killed for memory leaves no crash report, no failure line and no output.** It looks
    exactly like a hang, and on 2026-09-15 it looked exactly like the locked-screen failure too, so
    two diagnostic passes went the wrong way. `GlassServiceStore`'s convenience overload recursed
    into itself — `Data` is `Encodable`, so `setConfiguration(someData,…)` matched the generic
    exactly and the `Data?` requirement only by promotion — and ran to **90 GB**. What found it was
    instrumenting the call path with unbuffered `FileHandle.standardError.write` and seeing that the
    *callee was never entered*, which pointed at overload resolution rather than at anything the
    callee did. **Run a suspect test under a memory watchdog** (launch, poll total RSS, kill above a
    ceiling) rather than re-running it and hoping. And treat a generic overload that shadows a
    concrete one as a defect: label it.

30. **A pty echoes what you send it, so never drive a credential prompt through one.** Using
    `script -qec` to give `grdctl` a terminal echoed the typed password straight back into the
    session transcript on 2026-09-15; it had to be treated as burned and rotated. Feed secrets
    through a mode-600 file the reader deletes, or through stdin to a process that does not echo.
    And when a tool refuses stdin — `grdctl rdp set-credentials` segfaults on a non-tty — that is a
    reason to find another door, not to reach for a terminal.

31. **`which` proves only what is on `PATH`.** The scratch VM was reported to the user as having no
    RDP server because `which gnome-remote-desktop-daemon` found nothing; it was installed all
    along, in `/usr/libexec`. Use the package manager (`apt-cache policy`, `dpkg -l`) or the unit
    list to ask whether software is present. This is rule 24 in a new costume, and the cost was a
    wrong "cannot be done" told to the user.

32. **A green package suite is not a building app.** `swift build` and `swift test` compile the
    SwiftPM package; the **App target lives in the Xcode project** and neither touches it. On
    2026-09-15 the composition root reached `GlassTerminalRuntime.sessionManager`, which is
    `internal`, and 1481 tests passed at exit status 0 while the app could not be built at all — the
    error surfaced only when an install was attempted. Before claiming a change works, build the
    app: `xcodebuild -scheme GlassPowerTools -configuration Release -destination
    'platform=macOS,arch=arm64'`. Anything a capability exposes to the composition root has to be
    `public`, and the right shape is one public method on the runtime rather than widening access to
    its internals.

33. **Replacing a protocol member does not break its conformers — it silently orphans them.** Stage
    4 replaced `GlassCapability.isDeviceBound` with `credential(for:host:)`. Every *test double*
    still implementing `isDeviceBound` kept compiling: the old method became an ordinary method
    nobody calls, and the type quietly picked up the new member's **default**. Four stage 3 tests
    went from proving redaction to proving nothing, and only the full suite caught it. So: after
    renaming or replacing a protocol requirement, **grep for the old name** and check every hit is
    gone rather than merely compiling — a conformer that still builds is the failure mode, not the
    reassurance.


34. **Exactly one scope may replace a `CommandGroup` placement, and the menu bar has to be read
    back from the running app.** `CommandGroup(replacing:)` does not merge: when two scenes replace
    the same placement SwiftUI keeps one and the other is simply absent — no warning, no failure,
    and nothing visible except a shortcut that reaches nothing. The database's File group and the
    terminal workspace's both replaced `.newItem`, so the shipped build had no *New Terminal
    Window*, no *New Workspace Tab* (⌘T did nothing, which is how the user found it), no *Connect
    Saved Host…* and no *Close Tab*. `CommandMenu` contributions are unaffected, which is why the
    Terminal and Query menus looked fine and hid the problem. So: the shell owns every replaced
    placement (`GlassShellFileCommands`), capabilities contribute with `after:`, a key shared
    between capabilities is a stub the focused window aims through a focused value, and
    `Tests/GlassShellTests/MenuBarPlacementTests.swift` records who may replace what. Verify a menu
    change by reading the real menu bar —
    `osascript -e 'tell application "System Events" to tell process "GlassPowerTools" to get name of
    menu items of menu 1 of menu bar item "File" of menu bar 1'` — never from the source, which is
    exactly where this defect looks correct.

35. **"Not read yet" and "empty" must never be the same answer.** D26 made the catalog the one
    store for a connection. The composition root attaches that store in `App.init`; the catalog is
    read from disk later, in the library's `.task`. In between, `configurations(ofKind:)` answered
    *nothing* — so `ServerManager.attach` built an empty saved-server list, and the next write
    reconciled the catalog to match it and **deleted every terminal and desktop configuration the
    user had**. The machine and its service link survived, which is why it read as "settings reset
    each time" rather than as data loss: the sheet said *"This terminal has no saved configuration
    behind it."* So: `GlassServiceStore.isCatalogLoaded` is the distinction, `GlassServiceRecords`
    refuses to reconcile without it (one guard at the door all three capabilities share), and
    `GlassCapability.catalogDidLoad()` is how a capability learns it may now build its index. Any
    reconcile that deletes what is missing from a list needs to know where the list came from.

36. **There is no legacy. Do not write migration code.** 2026-09-16, the user's words: *"there is no
    LEGACY. We're building the first version of this. There is no reason to import old previous
    version settings. There are no users, we don't need the baggage for that… they shouldn't be
    changing so drastically at this point to require code specifically dedicated to morphing
    preferences."* A recovery pass that refilled emptied service links from the pre-D26
    `UserDefaults` copy was written, tested and then **deleted** for exactly this reason. The data
    on this Mac is the user's *test* data; re-entering four records costs minutes, and shipping a
    migration to save them costs a permanent seam in the product. Fix the defect that lost the data
    and let the test data be re-entered. This also retires the stage 5 plan item about first-launch
    removal of legacy keys: nothing reads them, so nothing has to delete them either.

37. **The product is named "Glass Power Tools", with the spaces.** Three names, and only one of them
    is `CFBundleDisplayName`: macOS Finder and the Dock show the **bundle's file name**, the
    left-most menu title is **`CFBundleName`**, and iOS's home screen is the display name.
    `INFOPLIST_KEY_CFBundleName` does not exist — Xcode accepts the setting and ignores it, because
    the generated plist hardcodes `CFBundleName = $(PRODUCT_NAME)` (verified 2026-09-16 by building
    with it set and reading the plist back). So the app target sets
    `PRODUCT_NAME = "Glass Power Tools"`, the bundle is `Glass Power Tools.app` on every platform,
    and the bundle identifier stays `com.glasspowertools` — the App Group, the Keychain group and
    every existing record are keyed on the identifier, never on the name. Install to
    `/Applications/Glass Power Tools.app`, and note the process is now `Glass Power Tools`:
    `pgrep -x GlassPowerTools` matches nothing.

38. **The projection is not the data, and a fix can make a latent defect reachable.** Twice on
    2026-09-16 something "disappeared" and the records on disk were correct the whole time. The
    second was created by fixing the first: `synchronizeCatalog` rebuilds the library's list from
    `GlassShellHostGrouping.group(records)` after applying incoming records, and **the device's own
    host is not in the catalog** — it lives in its own store (D8) and is *inserted* into the list.
    That rebuild had been unreachable for as long as a tombstone was throwing above it; the moment
    the sync worked again, "This Mac" vanished from the library. So: `rebuildProjection()` is the
    one composer, used by every path that refreshes `hosts`, and when something vanishes, **look at
    what draws the list before going looking for lost data.** A repair that unblocks code which has
    never run is a change in behaviour, and the newly reachable lines deserve the same suspicion as
    new ones.

39. **A key equivalent has exactly one owner, and the loser is silent.** ⌘T, ⌘N, ⌘W and ⌘O have each
    cost a defect: declaring a shortcut another item already carries does **not** give the focused
    window a choice between them. One item is dropped from the menu bar, or the standard item is
    stripped of its key and a disabled item keeps it — and which happens is not something the source
    says. AppKit's own File ▸ Close cannot be out-declared at all: a `Commands` item with ⌘W never
    reaches the menu bar, in any placement, so what a window closes is **registered**
    (`GlassCloseCommandRouter`) rather than declared. `MenuBarPlacementTests` holds one guard per
    key; add one when a new shortcut appears, and read the result out of the running app's menu bar,
    because nothing else shows it.

40. **A view that observes its model needs an identity per model.** `GlassEditorView` renders
    whatever `GlassEditorModel` it is handed, and the engine deliberately observes that model rather
    than being pushed values through `updateNSView` — so handing the view a *different* model never
    reached the text view already on screen. With five files open the editor kept rendering the
    first one, and every test passed throughout, because the model was always right. `.id(document.id)`
    is the fix. The general form: when a representable's content comes from an object rather than
    from its arguments, SwiftUI has nothing to diff, and identity is the only thing that tells it to
    build a new one.

41. **A window owns its documents.** The editor kept one workspace for the whole app, so a second
    window was a second view of the same open files — a panel pretending to be a window. What is
    true of the *editor* (text size, wrapping, line numbers, recents) is shared, in
    `GlassEditorPreferences`; what a *window* is (documents, projects, selection, find) belongs to
    one `GlassEditorWorkspace` per window, keyed by a window id through a value-based `WindowGroup`.
    Ask which of the two a new piece of state is before adding it to either.

42. **The obsolete apps are a record to read, and they already solved this.** `../glas.sh`,
    `../glassdb` and `../glassDT` do not compile and are not dependencies, which is exactly why it
    is tempting to skip them and reason from first principles instead. Three defects in one day
    came from doing that: **`openWindow` does nothing on an iPhone**, silently, and glassDT had
    handled it at `App/glassDTApp.swift:107-143` — a `fullScreenCover` holding the *resolved*
    connection, dismissed by a chevron so the machine's name is the only wording in the bar. The
    merged app reintroduced the bug in the desktop's session and twice in the editor. Before
    designing a surface these apps had, open the file. A guess that happens to work is still a
    guess, and it will not carry the decisions the original made for reasons it wrote down.

43. **One answer to "can this device open a window".** `GlassWindowPresentation.canOpenWindows`,
    which requires `supportsMultipleScenes` **and** a non-phone idiom. Two signals because they
    fail in opposite directions: the first also catches an iPad with multiwindow switched off, the
    second is the half already proven in production by the database's iPhone routing. Any
    capability that answers a user action with `openWindow` must ask it first and present in place
    when the answer is no — otherwise the tap does nothing at all, with no window, no error and no
    log line to find it by.

44. **A capability's in-memory list is a cache of the catalog, and the catalog changes underneath
    it.** `GlassServiceRecords.replaceAll` reconciles the catalog to the list it is handed, which
    means every stored configuration of that kind that the caller does not know about is deleted.
    It guards "the catalog was never read" and cannot guard "the catalog was read, and then D19
    delivered another device's changes" — so **re-read on every `catalogDidLoad()`, not once**. The
    terminal read once and its next save deleted a configuration the iPhone had written; the
    desktop and the database re-read and were unaffected (2026-09-17). If a capability keeps a
    list, `catalogDidLoad()` must refresh it, and a guard named `…IfNeeded` is the wrong one to
    call from there.

45. **Every action an error message offers must work.** *"Edit the service to set it up, or remove
    it"* was shown for a service link with no configuration, and `setupDraft(for:host:)` answered
    nil for exactly that case — so Edit opened nothing and the only working action was the
    destructive one. A message that names two ways out, one of which is a dead end, is an
    instruction to destroy data. When writing the sentence, try both.

46. **Drive the phone, do not reason about it.** Four iPhone defects in one evening, every one a
    surface that silently did nothing, and not one of them visible from a Mac build or a unit test:
    `openWindow` is a no-op on an iPhone; a `NavigationSplitView` collapses to its *sidebar* on a
    compact width; a contributed panel's detail is never pushed because the library cannot see the
    panel's selection; and a double-click gesture has no touch equivalent, so a file list could
    select a file and never open one. The app had 1,623 unit tests and a single iPhone UI test that
    checked it launched. `UITests/EditorOnIPhoneUITests.swift` is the pattern: seed, walk, and
    photograph every step.

47. **A simulator fixture must live inside the app.** The data container is given a new identifier
    when the app is reinstalled, while `UserDefaults` survives — so anything that records an
    absolute path from the host is stale by the next run, and a seeding guard of "only when empty"
    then seeds nothing and leaves the dead record in place. `--ui-testing-seed-project` makes the
    fixture in the app's own container and replaces what was there. Write screenshots to the
    runner's `NSTemporaryDirectory()` as well as attaching them: result bundles arrive unfinalised
    often enough that an attachment alone is not evidence.

48. **Before wrapping a view in a navigation container, find out whether it already navigates.**
    `DatabaseWorkspaceView` got a compact `NavigationStack(path:)` typed `[DatabaseCompactRoute]`
    on 2026-09-19. The schema browser inside it has pushed its own `CompactSchemaDatabaseDestination`
    for a database's tables since glassdb — and **a typed path accepts only its own type**, so every
    one of those links silently did nothing: *"now the databases can't be clicked"*, reported within
    the hour by the only person driving a phone. `NavigationPath` takes both, at the cost of not
    being able to ask what is in it. The working half of a screen is the half to leave alone.

49. **An accessibility identifier on a container reaches its children.** Both iPhone UI tests
    began failing on iOS 27.2 because `app.descendants(matching: .any).matching(identifier:)`
    resolved a library panel row's *image* — not hittable, so the tap did nothing and the test
    failed before reaching what it tested. VoiceOver had the same row three times over. Which
    child the query picks changes between OS versions, so the fix is not a better query:
    `.accessibilityElement(children: .combine)` makes the row one control that says its name and
    its count.

50. **Pinned chrome must occlude, whatever the transparency setting says.** The grid's column
    header and row-number gutter painted nothing at 0% window opacity, on the stated reasoning
    that a transparent window should be transparent everywhere — so the data scrolled through
    them and `#` sat on top of cell text. A canvas may honour 0%; chrome that tells you which
    column you are reading may not. `.ultraThinMaterial` under the tint keeps it translucent and
    legible, and disappears under the tint at full opacity, so the opaque end is unchanged.

51. **A contributed page owns its own container.** The shell's settings surface wrapped every page
    in a `Form`, which is right for its own four — they are sets of `Section`s — and wrong for a
    capability's, which is already a `Form`. A `Form` inside a `Form` **collapses on iOS** into one
    clipped row: Settings ▸ Terminal on a phone was the word "Theme", cut in half, and nothing
    else (2026-09-19). On a Mac the nesting drew a box inside a box and nobody noticed for weeks.
    The same shape as rule 48 one level up: when a contributor already provides structure, the host
    must not impose its own.

52. **`#if os(macOS)` is not a capability.** The Files browser refused a dropped file everywhere
    but a Mac — not because receiving one is a Mac idea, but because the code happened to live in
    a file fenced with `#if os(macOS)`. iPadOS has had cross-application drag and drop for years,
    and the iPhone Duo brings it to a phone in October; the app had been turning it down on a
    device that could do it since the browser was written. Five `⌘`-shortcut fences were the same
    thing: an iPad with a keyboard has ⌘A and Escape.
    Fence the **API** — `NSFilePromiseReceiver`, `NSPasteboard`, `NSViewRepresentable` — and let
    the *capability* be offered everywhere. A drop target nothing can reach costs nothing and
    starts working the day the system allows it, with no build. Where a capability genuinely has
    to be asked about at runtime, it gets one answer in one place (rule 43).

53. **A default in a protocol extension is invisible through `any`.** `openSessions()` was declared
    only in `public extension GlassCapability`, so the registry — which holds
    `[any GlassCapability]` — dispatched statically and called the *default* for every capability.
    The terminal and the database each implemented it correctly, and the switcher was empty. A
    contributed hook goes in the **protocol body** with its default in the extension, the way
    `libraryPanels()` and `settingsPages` already do. Caught by `GlassOpenSessionTests` rather than
    on a device; the sibling of rule 33, which is the same silence from the other direction.

54. **Leaving a screen is not closing it where there are no windows.** `onDisappear` means "this
    window closed" on a Mac and "the user tapped back" on a phone, and the editor keyed a lifetime
    decision on it: `forget` discarded the workspace, so dismissing the full-screen cover threw the
    open documents away — unsaved edits included — with nothing said and no way back. Two verbs,
    not one: leaving the screen gives up frontmost, and **closing** is a separate, deliberate act
    (`closeWorkspace`, reachable from the session switcher). The policy is a settable property
    rather than a call to `GlassWindowPresentation` inside the method, because the suite's own
    machine always answers "Mac" and the phone's behaviour would never be tested.

55. **A device capability read during app construction is read before the device has answered.**
    `closesWorkspaceWithItsWindow` was a stored property defaulting to
    `GlassWindowPresentation.canOpenWindows`, which meant it ran inside `GlassPowerToolsApp.init`
    — before any scene had connected. `UIDevice.current.userInterfaceIdiom` is `.unspecified`
    then, `.unspecified != .phone`, and an iPhone therefore answered *"this device has windows"*.
    The editor kept discarding its workspace on every dismissal and the session switcher listed
    nothing, with every unit test green and the registry correctly wired — the UI test's probe
    said `registry=ok windows=false others=0`, which is how it was found.
    So: ask a platform question **at the point of use**, or behind a computed property that asks
    then. An override for tests is a stored `Bool?` consulted first, never a stored default. Rule
    43 says one answer in one place; this says *and at the right time*.

56. **A locked screen is not a broken machine.** Around 35 tests failed with `EPERM`, atomic
    writes failed with `mktemp … errno 1`, and `GlassShellTests` took SIGTRAP — and it was
    reproducible in a twelve-line Foundation script with no project code, in three directories,
    and with the session's work stashed. Every one of those observations was true and the
    conclusion drawn from them ("this Mac is in a bad state; confirm on a second one") was wrong.
    `FileProtectionType.complete` means **unreadable while the device is locked**, nine places in
    `Sources` write files with it, and the screen was locked. Unlocking it gave 1,685 / exit 0.
    So: before concluding anything about the toolchain, the OS or an entitlement, **check whether
    the screen is locked** — and note that "I reproduced it outside the project" narrows a cause
    without identifying it.

57. **Inventory the feature, not just the seam.** The session switcher's seam was surveyed
    carefully — where each capability's session lives, who can bring it forward — and the
    *presentation* was not surveyed at all. So a list was written from scratch, "the carousel" was
    planned as future work, and `snapshot` was left out of `GlassOpenSession` on the grounds that
    nothing could supply one, while the product already shipped a grid, a carousel, live previews,
    a card-width slider, arrow-key navigation, an attention rule and a **tested** layout solver —
    and `SwiftTermHostModel.previewImage(maxPixelWidth:)` had rendered a terminal to an image
    since before the merge. The user had to point at it.
    A reuse check covers the behaviour being built **and the way it is shown**, across every
    capability and every platform fence, before the first file is written. Searching for the
    seam's nouns (`openSessions`, `router`) finds none of this; searching for the feature's
    (`overview`, `grid`, `carousel`, `preview`, `card`, `thumbnail`) finds all of it. The standing
    inventory is in `systemPatterns.md`; add to it rather than re-deriving it.

58. **A limit checked after the work is not a limit.** The highlighter's size ceiling was tested when
    turning the parse into colours — after copying the text, indexing its lines and running a full
    tree-sitter parse. A 14.6 MB file spent 13 s on work the ceiling then discarded, and "highlighting
    off for large files" looked true in the status bar the whole time. Put the guard in front of the
    cost it exists to avoid, and test that the cost is not paid (`HighlightingCeilingTests` checks
    `parseCount == 0`, not only the degraded flag).
59. **Measure the frame, then the window.** Offscreen harnesses (`ScrollTimingTests`,
    `TextKitComparisonTests`, `LargeFile*TimingTests`) find where time goes and prove a fix; they can
    also skip work a real window does. Before a claim reaches the user — or a decision rests on it —
    repeat it in a running app with real input, and look at the screen: a probe whose window never
    came forward "measured" an idle main thread (2026-09-23). When the user is at the Mac, do not
    drive it; wait until they step away.
60. **A command placement draws per scene, and the Mac's export panel is not a Save panel.** A
    `CommandGroup(after: .saveItem)` in the editor's scene drew; the same placement in the shell's
    commands, attached to the library scene, drew nothing — replacing or appending (0.4.218,
    0.4.219). Rule 34 said to read the menu bar; this is what reading it caught. And SwiftUI's
    `fileExporter` on a Mac is an **export**: "Export As:", an Export button, and an extension added
    from the content type — a new `.env` becomes `.env.txt`. A document's first save on a Mac is
    `NSSavePanel` (`GlassEditorSavePanel`), which says Save and writes the name typed.
