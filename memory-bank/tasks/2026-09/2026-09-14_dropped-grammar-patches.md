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
visible as a commit with a message. The user has already said this is acceptable: *"I'm also ok with
pinning against a version in a git repo."* Needs two repositories created and the patches applied
there.

**Recommendation: B for SQL, either for markdown.** SQL's 41 MB is the whole argument; markdown's
4.6 MB is small enough that vendoring it beside YAML is defensible and removes a moving part.

## What must also be corrected

`THIRD-PARTY-NOTICES.md` lists markdown and SQL as plain pinned dependencies. It does not record
that the kit's versions were patched, which is the fact that would have made this obvious. Whichever
fix lands, the notices table gains a **patched** column, and the grammar table stops implying that a
pinned revision equals the code that was reviewed.
