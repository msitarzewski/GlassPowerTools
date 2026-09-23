# Third-party notices

Glass Power Tools is MIT licensed (see `LICENSE`). Dependency licenses are preserved as they are;
this application's license does not relicense them. Collected copies of the transitive licenses are
in `Documentation/ThirdPartyLicenses/`.

## Vendored in this repository

Code carried in-tree under `Packages/`, with its own license file intact.

| Component | Source and baseline | Terms and local evidence |
|---|---|---|
| **RDPKit** | `steelbrain/RDPKit` 0.3.1, `2032fdbc9a300e6b78065abbaf8ed1acca14f938` | MIT, "Copyright (c) 2026 Steelbrain". `Packages/RDPKit/LICENSE` retained verbatim. Local changes recorded in `Packages/RDPKit/GLASSDT-PATCHES.md`; the implemented surface and its limits in `Packages/RDPKit/CAPABILITY-LEDGER.md`. Upstream's `Examples/` sample application was **not** carried. |
| **Citadel** | `orlandos-nl/Citadel`, vendored via glas.sh | MIT, "Copyright (c) 2022 Orlandos". `Packages/Citadel/LICENSE` retained. |
| **swift-nio-ssh** | `apple/swift-nio-ssh`, vendored via glas.sh | Apache License 2.0. `Packages/swift-nio-ssh/LICENSE` retained, NOTICE preserved. |
| **TreeSitterMarkdown**, **TreeSitterMarkdownInline** | `tree-sitter-grammars/tree-sitter-markdown` @ `a0a00f817d02412bd92c54d316f164d827b57b5c` | MIT. `Packages/TreeSitterMarkdown/LICENSE` retained. **Vendored rather than depended on, and patched.** Upstream's block `serialize()` copies every open block into a fixed 1024-byte buffer with no bound: above 254 open blocks it overruns — an assert in debug, heap corruption in release — reachable purely by opening a deeply-nested markdown file. The bound is restored in `Packages/TreeSitterMarkdown/src/scanner.c`, where the patch names itself and says why. `parser.c` is the pinned revision byte for byte, and the inline grammar is unmodified. Guarded by `Tests/GlassEditorCoreTests/ScannerOverflowPenTests.swift`. |
| **TreeSitterSql** | `DerekStride/tree-sitter-sql` @ `851e9cb257ba7c66cc8c14214a31c44d2f1e954e` | MIT. `Packages/TreeSitterSql/LICENSE` retained. **Vendored rather than depended on, and patched.** Upstream's `serialize()` frees and nils `start_tag` — it consumes the state it was asked to snapshot — and `deserialize()` overwrites the pointer without freeing it or checking the allocation (GlassEditorKit pen finding M-5). Still present on upstream's HEAD, checked 2026-09-15, so a newer pin is not the fix. `parser.c` is the pinned revision byte for byte; only `scanner.c` differs, and the patch names itself there. |
| **TreeSitterYAML** | `tree-sitter-grammars/tree-sitter-yaml` @ `a1c4812a73ec5e089de8e441fdea3a921e8d5079` (2026-05-22) | MIT. `Packages/TreeSitterYAML/LICENSE` retained. **Vendored rather than depended on** because upstream's SPM manifest decides whether to compile `scanner.c` with a *relative* `FileManager.fileExists(atPath:)`, which is false when the package is a dependency — the scanner is silently dropped and the external-scanner symbols go undefined at link. Same commit, same licence, built with the correct sources. |
| **Mermaid** (`mermaid.min.js`) | npm `mermaid`, **kept at the registry's latest** by `Tools/Mermaid/update-mermaid.sh`, which the GlassPowerTools scheme runs before every build and which verifies the tarball's sha512 against the registry's integrity field (D35). The version in the build is `Sources/GlassEditor/Resources/Mermaid/VERSION` | MIT, "Copyright (c) 2014 - 2022 Knut Sveidqvist". `Sources/GlassEditor/Resources/Mermaid/LICENSE` is copied from the same tarball on every update. Loaded only into the editor's Markdown preview, with no network access (D35). |

## Tree-sitter grammars — pinned dependencies

Consumed at exact revisions rather than version ranges, so a grammar cannot move underneath us.
These were vendored while GlassEditorKit was a standalone package; on absorption (2026-09-14) they
became dependencies, which removed **55 MB** of generated C from this repository. Every commit below
is the one GlassEditorKit had vendored and licence-verified on 2026-08-11. `Tests/GlassEditorCoreTests`
proves each one links, parses and compiles its highlight query — that test is what makes pinning safe.

| Grammar | Upstream | Pinned commit | Licence |
|---|---|---|---|
| JSON | `tree-sitter/tree-sitter-json` | `001c28d7a29832b06b0e831ec77845553c89b56d` | MIT |
| Bash | `tree-sitter/tree-sitter-bash` | `a06c2e4415e9bc0346c6b86d401879ffb44058f7` | MIT |
| TOML | `tree-sitter-grammars/tree-sitter-toml` | `64b56832c2cffe41758f28e05c756a3a98d16f41` | MIT |
| Markdown | **vendored — see the table above** | | MIT |
| SQL | **vendored — see the table above** | | MIT |
| YAML | see the vendored table above | | MIT |

`SwiftTreeSitter` (BSD-3-Clause) and the `tree-sitter` runtime (MIT) arrive with them. The grammars
declare `tree-sitter/swift-tree-sitter` where this project declares `ChimeHQ/SwiftTreeSitter`;
SwiftPM resolves both to **one** package, verified in `Package.resolved`.

**What a green suite does and does not prove here.** The markdown patch is guarded:
`ScannerOverflowPenTests` aborts without it. The SQL patch is **not**. Its pen test passes with the
bug present, and so does an incremental-versus-full highlight comparison over a dollar-quoted
document with the incremental path asserted — both checked on 2026-09-15, the second under
AddressSanitizer as well. The patch is applied because the code is wrong, not because a test
demanded it: a `serialize()` that destroys its own state, and a `deserialize()` that overwrites a
live pointer without freeing or checking it, are defects whether or not this app's edit patterns
reach them. `Tests/GlassEditorCoreTests/SQLDollarQuoteStateTests.swift` records the attempt and what
it could not show.

**Highlight queries.** `Sources/GlassEditorCore/Grammar/Queries/*.scm` are each grammar's own
`queries/highlights.scm`, taken at the pinned commit above and carried as resources. They remain
under their grammar's MIT licence.

## Authored for this application

MIT, under this repository's own copyright.

| Component | Note |
|---|---|
| `Sources/VNCKit` | RFB/VNC client written from RFC 6143 and the public RFB protocol registry. **No third-party VNC source was copied or linked.** |
| `Sources/GlassRDPTransport`, `Sources/GlassVNCTransport` | Adapters: frame ownership, configuration and transport selection. |
| `Sources/GlasSecretStore` | Absorbed from the standalone GlasSecretStore package, 2026-09-13. |
| `Sources/GlassEditorCore`, `GlassEditorUI` | Text editing and syntax analysis. Absorbed from the standalone GlassEditorKit package, 2026-09-14. |
| `Sources/GlassConnectionKit`, `GlassConnectionUI`, `GlassHostCatalog` | Host identities, library projection and the catalog. Absorbed, 2026-09-14. |
| `Sources/GlassDBKit` | Database engines moved from glassdb, its tunnel manager left behind (D7). |
| `Sources/GlassSSHTransport`, `Sources/GlassTerminal`, `Sources/GlassDatabase`, `Sources/GlassShell`, `Sources/GlassLayers` | Moved from glas.sh and glassdb; their MIT copyright notices remain applicable to extracted code. |

## Derived from third-party sources, with attribution

These are small extractions rather than whole modules, and each carries its attribution in-file.

| Where | Derived from |
|---|---|
| `MacKeyboardMapping.swift` | RDPKit 0.3.1 `Examples/RDPClient/RemoteInputCaptureView.swift` (MIT). The sample app itself is not carried; this mapping is. |
| The remote-audio approach | RDPKit's AVAudioEngine example (MIT), adapted with bounded scheduling and generation safety. |
| Glass library UI and projection | The existing MIT glas.sh and glassdb implementations. |

## Resolved package dependencies

Exact revisions are recorded in `Package.resolved`. Their licenses and any BoringSSL notices remain
in their own source distributions; collected copies are in `Documentation/ThirdPartyLicenses/`
(BoringSSL, llhttp, swift-atomics, swift-collections, swift-nio, swift-nio-ssl, swift-system).

Apple packages (swift-nio, swift-nio-ssl, swift-crypto, swift-log, swift-algorithms,
swift-collections, swift-atomics, swift-system, swift-numerics, swift-async-algorithms,
swift-argument-parser, swift-asn1, swift-metrics, swift-service-lifecycle,
swift-nio-transport-services) are Apache License 2.0. `postgres-nio` is Apache License 2.0.
`SwiftTerm` is MIT. `tree-sitter` and `swift-tree-sitter` are MIT. `BigInt` is MIT.
`swift-markdown` (pinned exactly, D35) and its `swift-cmark` are Apache License 2.0; cmark-gfm's
own notices travel in its source distribution.

**`mysql-nio` is pinned to a fork by revision**, `msitarzewski/mysql-nio`
`69489876bebca3b54c46680e519669789060d0ae`, Apache License 2.0 as upstream. The pin is mandatory:
upstream PR 126 (empty-password `caching_sha2_password`) was closed unmerged. The reason is recorded
beside the pin in `Package.swift` so it is not tidied into a version range.

## System libraries

`zlib` is linked as the operating system's `libz` on Apple platforms (`Sources/VNCKit`,
`linkerSettings: [.linkedLibrary("z")]`). It is linked, not vendored; the operating system's copy
and its notice apply.

## Scope of these notices

No protocol certification, patent clearance or interoperability guarantee is implied by any license
above. In particular, the RDP engine is a fork of an independent implementation and is not
Microsoft-certified; see `Packages/RDPKit/CAPABILITY-LEDGER.md` for what it actually implements.

## tree-sitter grammars added 2026-09-16

Five languages, so the editor can colour what is actually on the machines this app connects to.
All MIT, all unmodified; each grammar's own `queries/highlights.scm` is vendored beside it under
`Sources/GlassEditorCore/Grammar/Queries/`.

| Grammar | How it is consumed | Why |
|---|---|---|
| `tree-sitter/tree-sitter-go` | pinned dependency | no external scanner; upstream's manifest is enough |
| `tree-sitter/tree-sitter-c` | pinned dependency | no external scanner |
| `tree-sitter/tree-sitter-python` | **vendored**, `Packages/TreeSitterPython` | upstream's manifest compiles `parser.c` and not `scanner.c`; Python's scanner is the indentation stack, so the grammar does not link without it |
| `tree-sitter/tree-sitter-javascript` | **vendored**, `Packages/TreeSitterJavaScript` | same defect; its scanner does automatic semicolon insertion and template literals |
| `tree-sitter/tree-sitter-rust` | **vendored**, `Packages/TreeSitterRust` | same defect; its scanner does raw strings and nested block comments |
| `tree-sitter/tree-sitter-php` | **vendored**, `Packages/TreeSitterPHP` | same defect; its scanner handles heredocs and the `<?php` boundary. The vendored copy keeps upstream's `php/src` + `common/` shape, because `scanner.c` includes `../../common/scanner.h` |

The vendored copies differ from upstream in exactly one way: a `Package.swift` target that compiles
both `src/parser.c` and `src/scanner.c`. This is the same reason YAML, SQL and markdown are already
vendored (see above) — a manifest that omits the external scanner, not a change to the grammar.

## tree-sitter grammars added 2026-09-17

| Grammar | How | Why |
|---|---|---|
| `alex-pinkus/tree-sitter-swift` @ `00bbb0a2550f8bc0023a2a4992922d51ae045626` | **vendored**, `Packages/TreeSitterSwift` | MIT, `LICENSE` retained. Upstream publishes **no generated `parser.c`** — it generates at install time — so `src/parser.c` here is `tree-sitter generate` output from that revision, **20 MB**. The `grammar.json` it came from is upstream's, unmodified; `scanner.c` is upstream's byte for byte. |
| `tree-sitter-grammars/tree-sitter-xml` @ `5000ae8f22d11fbe93939b05c1e37cf21117162d` | **vendored**, `Packages/TreeSitterXML` | MIT, `LICENSE` retained. Ships a generated `parser.c`. Only the XML grammar is taken, not the DTD one beside it, so `scanner.c`'s `#include "../../common/scanner.h"` is repointed to `../common/scanner.h` — the sibling directory in this package. The header itself is unmodified and the patch names itself in place. |

**The 20 MB, said plainly.** Swift was left out on 2026-09-16 for exactly that weight, and the user
reversed the decision on 2026-09-17 having been shown the number: it is the language this project is
written in, and the SQL grammar already vendored beside it is **41.6 MB**. Revisit if upstream ever
ships a release artifact with the parser in it.
