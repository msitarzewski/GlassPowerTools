# Two security patches were dropped when the grammars became pinned dependencies

Owner: coordinating agent. 2026-09-14. **Status: diagnosed, not fixed. Needs a decision.**

## What is wrong

`57bca0b` ("Absorb GlassEditorKit, and stop carrying 55 MB of generated C") replaced GlassEditorKit's
**vendored** grammar sources with pinned SPM dependencies at the revisions the kit had already
pinned and licence-verified. Those sources were not stock. **Two of them carried local security
patches, and pinning upstream silently dropped both.**

| Grammar | Finding | What the patch did | Status now |
|---|---|---|---|
| **markdown** | pen **H-1** | Bounds the `memcpy` in `serialize()` to `TREE_SITTER_SERIALIZATION_BUFFER_SIZE` | **Lost** |
| **SQL** | pen **M-5** | Makes `serialize()` non-destructive; frees before overwriting `start_tag`; checks the allocation | **Lost** |
| YAML | — | its own patch | **Intact** — YAML had to be vendored anyway (its manifest cannot be consumed as a dependency) |
| Bash, TOML | — | none | Identical to upstream |

Proven by diffing `../GlassEditorKit/Sources/TreeSitter*/src/scanner.c` against the resolved
checkouts in `.build/checkouts/`.

## The markdown one is the serious one

Upstream's `serialize()` copies every open block into a fixed 1024-byte buffer with no bound. The
patch comment, written when it was found, states the consequence exactly:

> with >254 open blocks the memcpy overruns the 1024-byte buffer — tree-sitter asserts length<=1024
> in debug and silently corrupts the heap in release, **reachable purely by opening a deeply-nested
> markdown file.**

So this is heap corruption from untrusted content, in a capability whose whole job is opening other
people's files — the SFTP remote editor included.

`Tests/GlassEditorCoreTests/ScannerOverflowPenTests.swift:35` exists to catch exactly this, came
across with the absorption, and **aborts deterministically** (signal 6) on every run. The SQL case
at `:63` cannot even be reached: markdown kills the process first.

## Why it was not caught, and this is the part worth keeping

`57bca0b`'s message claims **"1153 tests / 117 suites"** and three platforms building. The build was
real. The test claim was not, and the way it went wrong is a measurement defect, not bad luck:

**A test target that aborts emits no `✘` line and no `Test run with N tests` line at all.** Every
verification this session used `grep -E "✘"` for failures and summed the `Test run with …` lines for
the total. A crashed target is invisible to both: it contributes no failure to find and no count to
add, so the pipeline reports success and a plausible total.

That is how "1146 tests / 117 suites, stable across two runs" was also reported earlier today while
this crash was present.

**The fix to the method, applied from now on:** check the exit status and the
`Note: Some test targets reported failures:` trailer, never a `✘` grep alone. The trailer *did*
appear in the first run of the session and was read as being about the target then being refactored.

## The two ways to fix it

Both restore the patches; they differ in where the patched source lives.

**A — vendor the two grammars here, as YAML already is.** Self-contained, and the patch record lives
beside the code in `THIRD-PARTY-NOTICES.md`. Cost measured today: markdown 2.2 MB + inline 2.4 MB,
**SQL 41 MB**. That last figure undoes most of the size win the absorption bought.

**B — fork upstream, apply the patch, pin the fork.** Keeps the repository small and the patch
visible as a commit with a message. The user has already said this is acceptable: pinning against a
version in a Git repository is fine. Needs two repositories created and the patches applied
there.

**Recommendation: B for SQL, either for markdown.** SQL's 41 MB is the whole argument; markdown's
4.6 MB is small enough that vendoring it beside YAML is defensible and removes a moving part.

## What must also be corrected

`THIRD-PARTY-NOTICES.md` lists markdown and SQL as plain pinned dependencies. It does not record
that the kit's versions were patched, which is the fact that would have made this obvious. Whichever
fix lands, the notices table gains a **patched** column, and the grammar table stops implying that a
pinned revision equals the code that was reviewed.

---

## Fixed for markdown, 2026-09-14 — and the measurement defect confirmed

**Markdown is vendored and patched.** `Packages/TreeSitterMarkdown` and
`Packages/TreeSitterMarkdownInline`, at the same commit that was pinned, with the H-1 bound restored
in the block scanner. `parser.c` is the pinned revision byte for byte — diffed, not assumed — and
only `scanner.c` differs, where the patch names itself. The dependency is gone from the manifest
entirely, which is what resolved the target-name collision: SwiftPM will not let a vendored target
share a name with one a dependency declares, so vendoring half was not possible.

`ScannerOverflowPenTests` now passes all four cases.

**The measurement defect, now quantified.** With the target no longer aborting, the full suite
reports **1466 tests / 153 suites at exit status 0**. Every count reported earlier in this session —
1146, 1153, 1169 — was missing the whole `GlassEditorCoreTests` target: **320 tests and 36 suites**
that contributed no count line because the process died before printing one, and no `✘` because an
abort is not a recorded failure.

So the numbers were not merely unverified, they were **wrong by a fifth of the suite**, and the
method reported success throughout. Exit status is the check; the `✘` grep never was one.

**SQL's M-5 patch is still missing**, and this is the second useful thing the fix proved: the
`sql: dollar-quoted strings survive incremental reparse without a memory error` case **passes
without the patch**. It could not run before because markdown aborted the process first. So the
suite being green is not evidence M-5 is unnecessary — it is evidence the test does not reach it.
Recorded in `THIRD-PARTY-NOTICES.md` rather than left implicit, because a pinned stock revision now
reads as reviewed when it is not.

**Still open:** the SQL fork. Vendoring it is a poor answer — its generated `parser.c` alone is
41 MB, which is most of what the absorption removed — so the fix is a patched fork pinned by
revision, which needs a repository the user owns.

---

## SQL fixed too, 2026-09-15 — and the "41 MB" that drove the wrong recommendation

**The recommendation to fork was based on a wrong measurement.** "SQL is 41 MB" was the *working
tree* size of its generated `parser.c`. Committed, git stores it in **2.6 MB** — measured by
committing the file to a throwaway repository — which is the same order as markdown's 1.2 MB. The
whole argument for a fork evaporated with the number that produced it.

So SQL is vendored at the pinned commit with the M-5 patch restored, exactly like markdown and YAML.
`parser.c` is the pinned revision byte for byte; only `scanner.c` differs. The dependency is dropped
from the manifest, which is also forced: SwiftPM will not let a vendored target share a name with
one a dependency declares.

**Upstream has not fixed it.** `origin/HEAD` still frees and nils `start_tag` inside `serialize()`,
checked 2026-09-15 by fetching the repository, so bumping the pin was never an option.

### What could not be shown, said plainly

Unlike markdown — where `ScannerOverflowPenTests` aborts without the patch — **M-5 could not be
reproduced through the app's behaviour.** Three attempts, all of which pass with the bug present:

1. the existing `sql: dollar-quoted strings survive incremental reparse` smoke test;
2. that same test under **AddressSanitizer**, which its own comment names as the real check;
3. a new incremental-versus-full highlight comparison over a dollar-quoted document, with
   `lastParseWasIncremental` asserted at every step so the equivalence cannot be satisfied by a
   silent full reparse — `Tests/GlassEditorCoreTests/SQLDollarQuoteStateTests.swift`.

The patch is applied because **the code is wrong**, not because a test demanded it: a `serialize()`
that destroys the state it was asked to snapshot, and a `deserialize()` that overwrites a live
pointer without freeing or checking it, are defects whether or not this app's edit patterns reach
them. The new tests stay as regression cover for the equivalence, and their header records what they
could not show, so nobody later reads them as proof the patch is load-bearing.

**Both grammar patches are now restored and `THIRD-PARTY-NOTICES.md` distinguishes the two cases** —
guarded by a test, versus applied on inspection.

## A flaky test found by the same run, and fixed

`incomingDropRetainsProviderFileAndCleansOwnedStaging` (`MacWorkspaceTests.swift:238`) asserted that
a staging directory was gone on the statement after its last reference was dropped.
`SFTPDropStaging` cleans up in `deinit`, and dropping the last reference does not guarantee the
deallocation happens right there — an autorelease pool or the optimizer can defer it. It passed
every time in isolation and failed in the parallel suite, which is project rule 21's warning
exactly. Now it waits, bounded, for the directory to disappear: the same property, without the
dependency on when.

**Full suite: 1468 tests / 154 suites, exit status 0.**
