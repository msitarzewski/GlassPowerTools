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

## Authored for this application

MIT, under this repository's own copyright.

| Component | Note |
|---|---|
| `Sources/VNCKit` | RFB/VNC client written from RFC 6143 and the public RFB protocol registry. **No third-party VNC source was copied or linked.** |
| `Sources/GlassRDPTransport`, `Sources/GlassVNCTransport` | Adapters: frame ownership, configuration and transport selection. |
| `Sources/GlasSecretStore` | Absorbed from the standalone GlasSecretStore package, 2026-09-13. |
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
