# Third-party notices

Glass Power Tools is licensed under the GNU GPL, version 3 (see `LICENSE`). The components below
keep their own licences; this application's licence does not relicense them.

**Where the licence texts are.** Every component's full licence and NOTICE text is in
`Documentation/ThirdPartyLicenses/` (or beside the vendored code, under `Packages/`), and the app
shows all of them at **Settings ▸ About ▸ Acknowledgements**. Both are generated from one list,
`Tools/Licenses/components.json`, by `Tools/Licenses/generate-acknowledgements.py`;
`AcknowledgementsTests` fails when a resolved package, a vendored package or the bundled Mermaid is
not covered.

## Vendored in this repository

Code carried in-tree, each with its licence file intact.

| Component | Source and baseline | Licence and local changes |
|---|---|---|
| **Citadel** | `orlandos-nl/Citadel` @ `ae8562f895de06ccb86fdb1cbb65fd99c8976e12` (0.12.1 and later `main`) | MIT, © 2022 Orlandos. `Packages/Citadel/LICENSE`. Local changes in `Packages/Citadel/PATCHES.md`. Its `CCitadelBcrypt` target is OpenBSD code: `blf.c` (Niels Provos, BSD-4-Clause — *"This product includes software developed by Niels Provos."*), `bcrypt.c` (ISC) and `bcrypt-kdf.c` (derived from `bcrypt_pbkdf.c`, © 2013 Ted Unangst, ISC; its notice, missing from Citadel's copy, is restored). |
| **swift-nio-ssh** | Citadel's fork of `apple/swift-nio-ssh`: `Wellz26/swift-nio-ssh` 0.3.7, `6acaa1ae7afb7fe9d07d06cda159e7fecea32500` | Apache-2.0. `Packages/swift-nio-ssh/LICENSE.txt`; neither Apple's repository nor the fork ships a NOTICE file. Local changes in `Packages/swift-nio-ssh/PATCHES.md`, and each modified file says so. |
| **RDPKit** | `steelbrain/RDPKit` 0.3.1, `2032fdbc9a300e6b78065abbaf8ed1acca14f938` | MIT, © 2026 Steelbrain. `Packages/RDPKit/LICENSE`. Local changes in `Packages/RDPKit/GLASSDT-PATCHES.md`; what it implements, and its limits, in `Packages/RDPKit/CAPABILITY-LEDGER.md`. Upstream's `Examples/` were not carried (its README still describes them). |
| **Mermaid** (`mermaid.min.js`) | npm `mermaid`, kept at the registry's latest by `Tools/Mermaid/update-mermaid.sh`, which the scheme runs before every build and which checks the tarball against the registry's sha512 (D35). The version is in `Sources/GlassEditor/Resources/Mermaid/VERSION` | MIT, © 2014–2022 Knut Sveidqvist; `LICENSE` beside it comes from the same tarball. The file is compiled from Mermaid **and about 115 packages it depends on**; their licences are listed in `Documentation/ThirdPartyLicenses/mermaid/bundled-packages.json` and in the app. At 12.0.0: MIT, ISC, BSD-3-Clause, Apache-2.0, the Unlicense, **EPL-2.0** (elkjs, the Eclipse Layout Kernel) and DOMPurify's *MPL-2.0 or Apache-2.0*, taken as Apache-2.0. The updater refuses a new Mermaid that brings a licence of a kind not yet reviewed. Loaded only into the editor's Markdown preview, with no network access (D35). |
| **Tree-sitter grammars** | ten of the sixteen; see the next section | MIT. |

## Tree-sitter grammars

Every grammar is fixed to an exact upstream commit, so none can move under us. Six are package
dependencies. Ten are vendored in `Packages/`, each for the reason given. All are MIT, with each
`LICENSE` retained. Checked file by file against upstream on 2026-09-26: apart from the changes
named here, every vendored file is upstream's, byte for byte.

| Grammar | Upstream @ commit | How | Why, and any change |
|---|---|---|---|
| JSON | `tree-sitter/tree-sitter-json` @ `001c28d7a29832b06b0e831ec77845553c89b56d` | dependency | |
| Bash | `tree-sitter/tree-sitter-bash` @ `a06c2e4415e9bc0346c6b86d401879ffb44058f7` | dependency | |
| TOML | `tree-sitter-grammars/tree-sitter-toml` @ `64b56832c2cffe41758f28e05c756a3a98d16f41` | dependency | |
| HTML | `tree-sitter/tree-sitter-html` @ `73a3947324f6efddf9e17c0ea58d454843590cc0` | dependency | |
| Go | `tree-sitter/tree-sitter-go` @ `1547678a9da59885853f5f5cc8a99cc203fa2e2c` (v0.25.0) | dependency | |
| C | `tree-sitter/tree-sitter-c` @ `b780e47fc780ddc8da13afa35a3f4ed5c157823d` (v0.24.2) | dependency | |
| YAML | `tree-sitter-grammars/tree-sitter-yaml` @ `a1c4812a73ec5e089de8e441fdea3a921e8d5079` | vendored, **patched** | Upstream's manifest decides whether to compile `scanner.c` with a *relative* `FileManager.fileExists(atPath:)`, false when the package is a dependency, so the scanner is silently dropped and its symbols go undefined at link. `scanner.c` also carries a bounds fix: `serialize()` checked for room for one 2-byte write where the loop makes two, so a deeply nested document wrote two bytes past the 1024-byte buffer. |
| Markdown | `tree-sitter-grammars/tree-sitter-markdown` @ `a0a00f817d02412bd92c54d316f164d827b57b5c` | vendored, **patched** | Upstream's block `serialize()` copies every open block into a fixed 1024-byte buffer with no bound: above 254 open blocks it overruns — an assert in debug, heap corruption in release — reachable by opening a deeply nested Markdown file. The bound is restored in `scanner.c`. |
| Markdown (inline) | same repository and commit | vendored | Unmodified; kept beside the block grammar. |
| SQL | `DerekStride/tree-sitter-sql` @ `851e9cb257ba7c66cc8c14214a31c44d2f1e954e` | vendored, **patched** | Upstream's `serialize()` frees and nils `start_tag` — it consumes the state it was asked to snapshot — and `deserialize()` overwrites the pointer without freeing it or checking the allocation. Still on upstream's HEAD (checked 2026-09-15), so a newer pin is not the fix. |
| Python | `tree-sitter/tree-sitter-python` @ `293fdc02038ee2bf0e2e206711b69c90ac0d413f` (v0.25.0) | vendored | Upstream's manifest compiles `parser.c` and not `scanner.c`; the scanner is the indentation stack, so the grammar does not link without it. |
| JavaScript | `tree-sitter/tree-sitter-javascript` @ `44c892e0be055ac465d5eeddae6d3e194424e7de` (v0.25.0) | vendored | Same manifest defect; its scanner does automatic semicolon insertion and template literals. |
| Rust | `tree-sitter/tree-sitter-rust` @ `1d600ad6fd8f99ef3e6049a1152f0cebba26f11b` | vendored | Same manifest defect; its scanner does raw strings and nested block comments. |
| PHP | `tree-sitter/tree-sitter-php` @ `5b5627faaa290d89eb3d01b9bf47c3bb9e797dea` (v0.24.2) | vendored | Same manifest defect; its scanner handles heredocs and the `<?php` boundary. Keeps upstream's `php/src` + `common/` layout, because `scanner.c` includes `../../common/scanner.h`. |
| Swift | `alex-pinkus/tree-sitter-swift` @ `00bbb0a2550f8bc0023a2a4992922d51ae045626` | vendored, **generated** | Upstream publishes no generated `parser.c`, so `src/parser.c` here is `tree-sitter generate` output from that commit's unmodified `grammar.json` (20 MB). `scanner.c` is upstream's. |
| XML | `tree-sitter-grammars/tree-sitter-xml` @ `5000ae8f22d11fbe93939b05c1e37cf21117162d` | vendored, one line changed | Only the XML grammar is taken, not the DTD one beside it, so `scanner.c`'s `#include "../../common/scanner.h"` points to the sibling `../common/scanner.h`. The header is unmodified. |

Each patch names itself in the file it changes. `Tests/GlassEditorCoreTests/ScannerOverflowPenTests.swift`
fails without the Markdown and YAML fixes. The SQL fix has **no** test that fails without it: its pen
test, and an incremental-against-full highlight comparison under AddressSanitizer, both pass with the
defect present (`SQLDollarQuoteStateTests.swift` records the attempt). It is applied because the code
is wrong — a `serialize()` that destroys its own state is a defect whether or not this editor's
edits reach it.

**Highlight queries.** `Sources/GlassEditorCore/Grammar/Queries/*.scm` are each grammar's own
`queries/highlights.scm` at the commit above, under that grammar's licence; `html-highlights.scm`
adds two captures and says so. The Markdown queries originate in **nvim-treesitter** (Apache-2.0),
as their first line says; its licence is included.

The `tree-sitter` runtime (MIT, with the Unicode licence for `lib/src/unicode`) and
`SwiftTreeSitter` (BSD-3-Clause) come with them. The grammars declare `tree-sitter/swift-tree-sitter`
where this project declares `ChimeHQ/SwiftTreeSitter`; SwiftPM resolves both to one package.

## Resolved package dependencies

Exact revisions are in `Package.resolved`. Each package's licence and NOTICE files are copied into
`Documentation/ThirdPartyLicenses/<package>/` with the revision they came from.

| Package | Licence | NOTICE reproduced |
|---|---|---|
| swift-nio, swift-nio-ssl, swift-crypto, swift-log, swift-metrics, swift-asn1, swift-service-lifecycle | Apache-2.0 | yes |
| swift-nio-transport-services | Apache-2.0 | none shipped |
| swift-algorithms, swift-argument-parser, swift-async-algorithms, swift-atomics, swift-collections, swift-numerics, swift-system, swift-markdown | Apache-2.0 with the Swift Runtime Library Exception | swift-markdown: yes; the others ship none |
| swift-cmark (cmark-gfm) | BSD-2-Clause, with MIT-licensed parts, in its `COPYING` | — |
| postgres-nio | MIT | yes |
| mysql-nio | MIT | — |
| SwiftTerm | MIT | — |
| Sparkle (macOS only, the Mac app's updater) | MIT, with the notices of the code it includes in its `LICENSE` | — |
| BigInt | MIT | — |
| SwiftTreeSitter | BSD-3-Clause | — |
| tree-sitter and the six grammar dependencies | MIT | — |

**`mysql-nio` is a fork pinned by revision**, `msitarzewski/mysql-nio`
`69489876bebca3b54c46680e519669789060d0ae`, MIT as upstream. The pin is required: upstream PR 126
(empty-password `caching_sha2_password`) was closed unmerged. The reason is beside the pin in
`Package.swift` so it is not tidied into a version range.

**Code inside those packages with its own licence:**

| Code | Inside | Licence |
|---|---|---|
| BoringSSL `817ab07` | swift-nio-ssl | OpenSSL and SSLeay licences (*"This product includes software developed by the OpenSSL Project for use in the OpenSSL Toolkit"*, *"…cryptographic software written by Eric Young"*), ISC for new code, MIT for `third_party/fiat` |
| BoringSSL `0226f30` | swift-crypto | Apache-2.0 (BoringSSL was relicensed between the two revisions) |
| llhttp | swift-nio | MIT |
| Unicode data | tree-sitter | Unicode licence |

The two BoringSSL texts, and where they came from, are in `Documentation/ThirdPartyLicenses/BoringSSL/`.

## Artwork

| Asset | Source | Licence |
|---|---|---|
| The database icon (`HeroiconCircleStack`) | Heroicons v2.2.0 `outline/circle-stack`, Tailwind Labs, redrawn as a SwiftUI path | MIT, `Documentation/ThirdPartyLicenses/heroicons/LICENSE` |
| AI agents' marks in Show All Windows (`TerminalAgent`) | Lobe Icons @ `05a9b8c41e4735a4a2b6d2f1e43574bd8ec6c8cb`, `packages/static-svg/icons`, LobeHub: eight monochrome SVGs, byte for byte but for the `<title>`, carried as text. The marks are their owners' trademarks | MIT, © 2023 LobeHub, `Documentation/ThirdPartyLicenses/lobe-icons/LICENSE` |

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
| `Sources/GlassSSHTransport`, `Sources/GlassTerminal`, `Sources/GlassDatabase`, `Sources/GlassShell`, `Sources/GlassLayers` | Moved from glas.sh and glassdb, both MIT under the same author. |

## Derived from third-party sources, with attribution

Small extractions rather than whole modules; each carries its attribution in the file.

| Where | Derived from |
|---|---|
| `MacKeyboardMapping.swift` | RDPKit 0.3.1 `Examples/RDPClient/RemoteInputCaptureView.swift` (MIT). The example app is not carried; this mapping is. |
| `DesktopAudioPlayer.swift` | RDPKit's AVAudioEngine example player (MIT), adapted with bounded scheduling and generation safety. |
| `Sources/VNCKit/RFBAppleRecordLayer.swift`, the 003.889 handshake in `VNCClient.swift` | remotex (MIT, Copyright (c) 2026 Andrew Chen, https://github.com/andrewtheguy/remotex): `src/vnc_record.rs`, `src/vnc_apple.rs`, `src/vnc.rs` and `docs/apple-vnc-889.md`, ported to Swift and CommonCrypto. |
| `Sources/VNCKit/RFBAppleMediaNegotiation.swift`, `RFBAppleSRTP.swift`, `RFBAppleHEVC.swift`, `RFBAppleVideoDecoder.swift` (High Performance) | remotex (MIT, as above): `src/vnc_apple_media.rs`, `src/vnc_apple.rs` and `docs/apple-vnc-889.md` ("The media stream", "The High Performance virtual display"), ported to Swift, CommonCrypto and VideoToolbox. The tests carry its captured offers, SRTP vectors and rate report, and `Tests/VNCKitTests/Fixtures/hevc-444-64x48.h265` is its `tests/fixtures` file, unchanged. |

## System libraries

`zlib` is the operating system's `libz` on Apple platforms (`Sources/VNCKit`,
`linkerSettings: [.linkedLibrary("z")]`). It is linked, not vendored; the operating system's copy
and its notice apply.

## Scope of these notices

No protocol certification, patent clearance or interoperability guarantee is implied by any licence
above. In particular, the RDP engine is a fork of an independent implementation and is not
Microsoft-certified; see `Packages/RDPKit/CAPABILITY-LEDGER.md` for what it actually implements.
