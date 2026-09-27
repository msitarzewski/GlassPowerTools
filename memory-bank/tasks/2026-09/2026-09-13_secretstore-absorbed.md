# GlasSecretStore absorbed, and the host-trust defect that came with it

**Date** 2026-09-13 · **Owner** coordinating agent · **State** DOCS
**Authorization:** the owner stated that GlasSecretStore is made obsolete by Glass Power Tools,
that everything is now stored and accessed by Glass Power Tools, and directed that whatever is
needed be absorbed from GlasSecretStore; the owner also confirmed the source applications no longer
compile and are obsolete.

## What moved

`../GlasSecretStore/Sources/GlasSecretStore/` → `Sources/GlasSecretStore/` (15 files) and
`Tests/GlasSecretStoreTests/` (9 files), verbatim. `Package.swift` drops
`.package(path: "../GlasSecretStore")`, gains `.target(name: "GlasSecretStore")` and its test target,
and six `.product(name:package:)` references become the bare target name.

**The module name is unchanged, so not one `import` moved** — 36 files import it. The upstream
package declared no external dependencies, so the graph got smaller rather than more tangled.
`GlassPowerTools.xcodeproj` needed no edit: it references `.` as its only local package and the
siblings arrived transitively.

`LICENSE` (MIT, same copyright holder) is now at the repository root, which is where the absorbed
code's notice belongs.

## Verified

| Check | Result |
|---|---|
| `swift build` | succeeds |
| `swift test` | **946 tests / 90 suites passed** (847/74 before; +90 from the absorbed suite, +9 written here) |
| App build, macOS / iOS Simulator / visionOS Simulator | all three succeed |
| Real host over SSH (`SSHTransportIntegrationTests`, `GPT_SSH_TEST_*` set) | 5/5 against the live VM |
| Live databases (`LiveDatabase*`, env sourced from `~/.config/gpt-db-test.env`) | 21 tests, 2 skipped for a stored credential |
| macOS UI suite | 17 passed, 1 failed — the pre-existing Stage 2 tag-vocabulary test |

## The defect the absorption exposed

The open question recorded for the user was *"should pinned SSH host keys sync?"*. Answering it
meant reading the call sites, and the call sites were broken: D18's fix had moved the **transport's**
trust store to a device-bound configuration and left `KeychainManager`'s own four host-trust methods
— the ones the **trust prompt** calls — on the synchronizing one, where `validateMobility` refused
the service. Accepting a fingerprint threw. See **D23** in [decisions](../../decisions.md) for the
full account; the short version is that the split repository had been the reason not to fix a
one-line eligibility list, and with the split gone the fix was one line.

### Why no test had noticed, measured rather than assumed

An unsigned `swift test` process **cannot write a synchronizable Keychain item at all**:
`SecItemAdd` with `kSecAttrSynchronizable: true` returns `errSecMissingEntitlement` (-34018) with and
without the data-protection Keychain, and ad-hoc signing the binary with
`com.apple.application-identifier` gets it killed on launch. Both were run before being written down.

So `HostTrustSynchronizationTests` **skips with that reason** rather than passing vacuously, its
refusal half runs everywhere, and the end-to-end proof is `testConnectsToRealHostThroughTheShell`
driving the signed app against the real VM — which now reaches the D14 prompt, accepts it, and
connects. **That prompt had never been driven by a test or a person.**

One harness fix was needed to get there: `acceptTrustPromptIfShown` looked the button up
application-wide and kept finding the Touch Bar's copy of it, which refuses every click. The
scoped-lookup helper `GlassDatabaseUITests` already had for exactly this is now in the terminal
suite too.

## Left behind deliberately

`../GlasSecretStore` still exists on disk with its own git history, memory bank and `PROVENANCE.md`.
Nothing here reads it any more. Removing the directory is the user's call, not a side effect of this
task.

## Open

- The pre-existing Stage 2 `testCollectionsAreChipsAndFeedTheSystemWideVocabulary` failure.
- Stage 3.5's device checklist — still the only thing that can prove CloudKit delivers anything,
  and now also the only thing that can prove a pin made on the Mac reaches the Vision Pro.
