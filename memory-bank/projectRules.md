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

