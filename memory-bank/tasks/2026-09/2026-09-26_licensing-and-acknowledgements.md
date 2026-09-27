# Licensing and acknowledgements — 2026-09-26

**State:** DOCS. Owner: coordinating agent. Release-prep item 1. Local only; nothing committed.

## Objective

Every third-party component's licence is named correctly, its text and NOTICE travel with the app,
and the list cannot silently fall behind the dependencies.

## What was found

- **Wrong licences in THIRD-PARTY-NOTICES:** postgres-nio and mysql-nio are MIT (listed as Apache-2.0);
  swift-cmark is BSD-2-Clause with MIT parts (listed as Apache-2.0). Eight Apple packages carry the
  Swift Runtime Library Exception, which was not mentioned.
- **Missing:** tree-sitter-html; Heroicons (the database icon; a comment claimed a `Vendor/heroicons/`
  folder that does not exist); nvim-treesitter (origin of the Markdown highlight queries, Apache-2.0);
  the Unicode licence inside the tree-sitter runtime; the packages compiled into `mermaid.min.js`.
- **Two BoringSSL licences.** swift-nio-ssl vendors BoringSSL `817ab07` (OpenSSL/SSLeay, ISC, MIT);
  swift-crypto vendors `0226f30`, after BoringSSL's relicensing to Apache-2.0. Only the first was recorded.
- **An undocumented patch.** The vendored YAML scanner carries a bounds fix (pen finding H-2) that the
  notices called unmodified; two scanner comments pointed at a file that does not exist here.
- **Grammar provenance verified** file by file against upstream at the recorded commits: SQL, YAML, XML,
  Markdown (block and inline) and Swift differ only by their documented changes; Python, JavaScript,
  Rust and PHP were verified earlier the same day. Full commits recorded for all four.
- **Go and C were version ranges**; now exact commits (v0.25.0 `1547678`, v0.24.2 `b780e47`).
- **Xcode's `Package.resolved` had drifted**: swift-crypto 3.15.1 and BigInt 5.7.0 against the package's
  4.5.2 and 6.0.1, left from before the vendored manifests' ranges were widened. The app build used the
  older cryptography. Restored; Xcode now resolves the same pins.

## What changed

- `Tools/Licenses/components.json` — every component: SPDX licence, source, revision, licence text path.
- `Tools/Licenses/generate-acknowledgements.py` — copies each pin's LICENSE/NOTICE/COPYING files from the
  checkout at the pinned revision into `Documentation/ThirdPartyLicenses/<id>/` (with `REVISION`), merges
  Mermaid's list, writes `Sources/GlassShell/Resources/Acknowledgements.json` (164 components). `--check`
  reports whether the output is current.
- `Tools/Mermaid/mermaid-licenses.py` + `update-mermaid.sh` — a new Mermaid is taken only with a list of
  its packages' licences (npm install of that version) and only if every licence is of a reviewed kind;
  otherwise the build keeps its copy and says why. Both paths exercised in a scratch copy.
- Settings ▸ About ▸ **Acknowledgements**: grouped, searchable list with each component's full text
  (`GlassShellAcknowledgementsView.swift`).
- `AcknowledgementsTests` (5) and `PackagePinAgreementTests` (1). The two coverage tests were proven to
  fail with an entry removed.
- THIRD-PARTY-NOTICES.md rewritten as one document (one grammar table, the package table with correct
  licences, embedded code, artwork). Package.swift, AGENTS.md, techContext and the grammar test header now
  tell the same grammar story. Widget copyright string set; Heroicons and audio-player attributions corrected;
  BoringSSL `SOURCE.md` rewritten.

## Validation

- `swift test`: 1,771 tests, 0 failures.
- macOS Release build 0.4.231 succeeds and bundles `Acknowledgements.json`. Not installed: the app was
  running. iOS and visionOS Release builds succeed.

## Remaining

- The in-app screen has not been looked at on a device.
- Dependency refresh is release-prep item 2 (SwiftTerm 1.20, tree-sitter 0.27, swift-crypto 5 separately).
