// swift-tools-version: 6.2
// Glass Power Tools shell modules. The app target in GlassPowerTools.xcodeproj links these
// products; capabilities arrive as further targets in later stages.

import PackageDescription

let package = Package(
    name: "GlassPowerTools",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .visionOS(.v26),
    ],
    products: [
        .library(name: "GlasSecretStore", targets: ["GlasSecretStore"]),
        .library(name: "GlassConnectionKit", targets: ["GlassConnectionKit"]),
        .library(name: "GlassConnectionUI", targets: ["GlassConnectionUI"]),
        .library(name: "GlassHostCatalog", targets: ["GlassHostCatalog"]),
        .library(name: "GlassEditorCore", targets: ["GlassEditorCore"]),
        .library(name: "GlassEditorUI", targets: ["GlassEditorUI"]),
        .library(name: "GlassEditor", targets: ["GlassEditor"]),
        .library(name: "GlassShell", targets: ["GlassShell"]),
        .library(name: "GlassLayers", targets: ["GlassLayers"]),
        .library(name: "GlassSSHTransport", targets: ["GlassSSHTransport"]),
        .library(name: "GlassTerminal", targets: ["GlassTerminal"]),
        .library(name: "GlassTerminalEmulator", targets: ["GlassTerminalEmulator"]),
        .library(name: "GlassDBKit", targets: ["GlassDBKit"]),
        .library(name: "GlassDatabase", targets: ["GlassDatabase"]),
        .library(name: "VNCKit", targets: ["VNCKit"]),
        .library(name: "GlassRDPTransport", targets: ["GlassRDPTransport"]),
        .library(name: "GlassVNCTransport", targets: ["GlassVNCTransport"]),
        .library(name: "GlassDesktop", targets: ["GlassDesktop"]),
        // The widgets' snapshot and tap intents, shared by the app and the widget extension.
        .library(name: "GlassWidgetData", targets: ["GlassWidgetData"]),
    ],
    dependencies: [
        // The editor engine's own dependency, previously transitive through GlassEditorKit.
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter.git", from: "0.9.0"),
        // Tree-sitter grammars. Every one is fixed to an exact upstream commit, so a grammar cannot
        // move under us; THIRD-PARTY-NOTICES.md lists them all. Seven are dependencies, because
        // their own manifests build them correctly (JSON, Bash, TOML, HTML, Go, C, and the
        // `tree-sitter` runtime through SwiftTreeSitter). The rest are vendored in `Packages/`,
        // each for a stated reason at its target below: upstream's manifest drops the external
        // scanner (YAML, Python, JavaScript, Rust, PHP), upstream publishes no generated parser
        // (Swift), a scanner carries a security fix (Markdown, SQL, YAML), or a header moved (XML).
        .package(url: "https://github.com/tree-sitter/tree-sitter-json",
                 revision: "001c28d7a29832b06b0e831ec77845553c89b56d"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-bash",
                 revision: "a06c2e4415e9bc0346c6b86d401879ffb44058f7"),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-toml",
                 revision: "64b56832c2cffe41758f28e05c756a3a98d16f41"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-html",
                 revision: "73a3947324f6efddf9e17c0ea58d454843590cc0"),
        // v0.25.0 and v0.24.2 — commits, like the others, rather than version ranges.
        .package(url: "https://github.com/tree-sitter/tree-sitter-go",
                 revision: "1547678a9da59885853f5f5cc8a99cc203fa2e2c"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-c",
                 revision: "b780e47fc780ddc8da13afa35a3f4ed5c157823d"),
        // The SSH stack: Citadel and its fork of swift-nio-ssh, vendored at recorded upstream
        // commits with a documented set of local changes (each package's PATCHES.md).
        .package(path: "Packages/Citadel"),
        .package(path: "Packages/swift-nio-ssh"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.101.3"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.14.0"),
        // The database engines, moved from glassdb with its tunnel manager left behind (D7).
        // The mysql-nio fork is mandatory and pinned by revision: upstream PR 126 (empty-password
        // caching_sha2_password) was closed unmerged. See the Stage 3 plan.
        .package(
            url: "https://github.com/msitarzewski/mysql-nio.git",
            revision: "69489876bebca3b54c46680e519669789060d0ae"
        ),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.33.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.36.0"),
        // Terminal emulator host (glas.sh's misnamed RealityKitContent package) and its engine.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.20.0"),
        // 1.20 (owner, 2026-10-07): it answers XTVERSION, which TUIs such as Claude Code ask before
        // they use synchronized output. Since 1.19 it carries a build-tool plugin that runs `git` on
        // SwiftTerm's own checkout to stamp its version into a generated file (no network). Xcode
        // asks once to trust it; command-line builds pass -skipPackagePluginValidation.
        // D35: the editor's Markdown preview. Apple's parser over cmark-gfm (tables, task lists,
        // strikethrough, autolinks). Apache-2.0. Pinned exactly, like SwiftTerm.
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0"),
        // Stage 4: the RDP engine. A vendored fork of steelbrain/RDPKit 0.3.1 (MIT, Steelbrain
        // copyright retained), so it sits in Packages/ beside the other vendored forks rather than
        // in Sources/ with our own code. Its patch record is Packages/RDPKit/GLASSDT-PATCHES.md.
        .package(path: "Packages/RDPKit"),
        // D38: the Mac app is distributed outside the Mac App Store, and macOS has no updater for
        // that; Sparkle is linked on macOS only (the product condition on GlassShell below).
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        // Credentials, trust storage and mobility. Absorbed from the standalone GlasSecretStore
        // package on 2026-09-13: that repository is obsolete, Glass Power Tools is now the only
        // consumer, and the split had become a reason not to fix its own eligibility list.
        // The module name is unchanged, so no `import` moved.
        .target(name: "GlasSecretStore"),
        // Host identities, the shared library projection and the catalog. Absorbed from the
        // standalone GlassConnectionKit package on 2026-09-14: it existed to let three separate
        // applications agree about one model, and there is one application now. The module names
        // are unchanged, so no `import` moved.
        .target(name: "GlassConnectionKit"),
        .target(name: "GlassConnectionUI", dependencies: ["GlassConnectionKit"]),
        .target(name: "GlassHostCatalog", dependencies: ["GlassConnectionKit"]),
        // Text editing and syntax analysis. Absorbed from the standalone GlassEditorKit package on
        // 2026-09-14: it is already in production behind the database's SQL and record editors and
        // the terminal's SFTP remote editor, so it was never a future capability.
        .target(
            name: "GlassEditorCore",
            dependencies: [
                .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
                .product(name: "TreeSitterJSON", package: "tree-sitter-json"),
                .product(name: "TreeSitterBash", package: "tree-sitter-bash"),
                "TreeSitterYAML",
                .product(name: "TreeSitterTOML", package: "tree-sitter-toml"),
                "TreeSitterMarkdown",
                "TreeSitterMarkdownInline",
                "TreeSitterSql",
                "TreeSitterSwift",
                "TreeSitterXML",
                "TreeSitterPython",
                "TreeSitterPHP",
                "TreeSitterJavaScript",
                .product(name: "TreeSitterGo", package: "tree-sitter-go"),
                "TreeSitterRust",
                .product(name: "TreeSitterC", package: "tree-sitter-c"),
                .product(name: "TreeSitterHTML", package: "tree-sitter-html"),
            ],
            resources: [.copy("Grammar/Queries")]
        ),
        // The one grammar that cannot be a dependency. Upstream's manifest decides whether to
        // compile `scanner.c` with `FileManager.fileExists(atPath: "src/scanner.c")` — a *relative*
        // path, resolved against the manifest process's working directory rather than the package
        // root. True when you clone and build it in place; false when you are a dependency, so the
        // scanner is silently dropped and every `tree_sitter_yaml_external_scanner_*` symbol goes
        // undefined at link time. Vendored at its recorded commit instead, with its MIT licence,
        // and in `Packages/` because it is not our code. Its `scanner.c` also carries a bounds fix
        // (pen finding H-2, guarded by `ScannerOverflowPenTests`); `parser.c` is upstream's.
        // Vendored, not pinned, because upstream's block scanner has an unbounded `memcpy` in
        // `serialize()`: with more than 254 open blocks it overruns the fixed 1024-byte
        // serialization buffer — an assert in debug, heap corruption in release, reachable purely
        // by opening a deeply-nested markdown file. GlassEditorKit found this (pen finding H-1)
        // and patched it; pinning upstream silently dropped the patch, and
        // `ScannerOverflowPenTests` has been aborting ever since. `parser.c` is the pinned
        // revision byte for byte; only `scanner.c` differs, and it says where and why.
        //
        // The inline grammar is vendored beside it from the same commit, unmodified.
        .target(
            name: "TreeSitterMarkdown",
            path: "Packages/TreeSitterMarkdown",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("src")]
        ),
        .target(
            name: "TreeSitterMarkdownInline",
            path: "Packages/TreeSitterMarkdownInline",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("src")]
        ),
        // Vendored, not pinned, for the same reason as markdown: GlassEditorKit patched this
        // scanner (pen finding M-5) and depending on the stock revision dropped the patch.
        // Upstream's `serialize()` frees and nils `start_tag` — it consumes the state it was asked
        // to snapshot — and `deserialize()` overwrites the pointer without freeing it or checking
        // the allocation. Still present on upstream's HEAD, checked 2026-09-15, so a newer pin is
        // not the fix. `parser.c` is the pinned revision byte for byte; only `scanner.c` differs.
        // Vendored for the same reason YAML is: upstream's manifest compiles `src/parser.c` and
        // **not** `src/scanner.c`, so linking it fails on the external scanner's symbols
        // (`tree_sitter_javascript_external_scanner_create`, …). JavaScript has an external scanner
        // for automatic semicolon insertion and template literals, so the grammar is unusable
        // without it. 2.8 MB, MIT, unmodified — the whole diff from upstream is a manifest that
        // compiles both files.
        // Python and Rust are vendored for the same reason JavaScript is: an external scanner
        // upstream's manifest does not compile. Python's scanner does the indentation stack, Rust's
        // does raw strings and nested block comments — neither grammar links without it. Go and C
        // have no external scanner and stay ordinary pinned dependencies.
        // PHP keeps its scanner's shared header in `common/`, and `php/src/scanner.c` includes it
        // as `../../common/scanner.h` — so the vendored copy preserves that shape rather than
        // flattening it, which is the smaller lie.
        .target(
            name: "TreeSitterPHP",
            path: "Packages/TreeSitterPHP",
            sources: ["php/src/parser.c", "php/src/scanner.c"],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("php/src")]
        ),
        .target(
            name: "TreeSitterPython",
            path: "Packages/TreeSitterPython",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("src")]
        ),
        .target(
            name: "TreeSitterRust",
            path: "Packages/TreeSitterRust",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("src")]
        ),
        .target(
            name: "TreeSitterJavaScript",
            path: "Packages/TreeSitterJavaScript",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("src")]
        ),
        .target(
            name: "TreeSitterSql",
            path: "Packages/TreeSitterSql",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("src")]
        ),
        // Swift's grammar ships no generated parser — upstream generates it at install time — so
        // `parser.c` here is `tree-sitter generate` output from the pinned checkout, 20 MB of
        // tables. That is the price of colouring the language this project is written in, and it
        // is smaller than the SQL grammar already vendored beside it.
        .target(
            name: "TreeSitterSwift",
            path: "Packages/TreeSitterSwift",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("src")]
        ),
        .target(
            name: "TreeSitterXML",
            path: "Packages/TreeSitterXML",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("src")]
        ),
        .target(
            name: "TreeSitterYAML",
            path: "Packages/TreeSitterYAML",
            exclude: ["src/schema.core.c", "src/schema.json.c", "src/schema.legacy.c"],
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("src")]
        ),
        .target(name: "GlassEditorUI", dependencies: ["GlassEditorCore"]),
        // Stage 5: the editor as a surface of its own. The engine is `GlassEditorCore` /
        // `GlassEditorUI`, already in production behind the SQL, record and SFTP editors; this
        // target is the workspace around it — documents, tabs, saving, recents and the window.
        .target(name: "GlassEditor",
                dependencies: ["GlassEditorCore", "GlassEditorUI", "GlassConnectionUI",
                               "GlassLayers", "GlassShell", "GlasSecretStore",
                               "GlassConnectionKit",
                               .product(name: "Markdown", package: "swift-markdown")],
                // D35: Mermaid, kept current by `Tools/Mermaid/update-mermaid.sh`, which the
                // scheme runs before every build.
                resources: [.copy("Resources/Mermaid"), .copy("Resources/Preview")]),
        .target(
            name: "GlassLayers",
            dependencies: [
                "GlassConnectionUI",
            ]
        ),
        .target(
            name: "GlassShell",
            dependencies: [
                "GlassLayers",
                "GlassConnectionKit",
                "GlassConnectionUI",
                "GlassHostCatalog",
                "GlasSecretStore",
                "GlassEditorCore",
                "GlassWidgetData",
                .product(name: "Sparkle", package: "Sparkle", condition: .when(platforms: [.macOS])),
            ],
            // Settings ▸ About ▸ Acknowledgements, from `Tools/Licenses/generate-acknowledgements.py`.
            resources: [.copy("Resources/Acknowledgements.json")]
        ),
        // The SSH engine: no UI, no shell dependency. Consumed by the terminal, database,
        // desktop and editor capabilities through its public API.
        .target(
            name: "GlassSSHTransport",
            dependencies: [
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
                "GlasSecretStore",
                "GlassConnectionKit",
            ]
        ),
        // The SSH capability: glas.sh moved in as one module (decision 2026-09-10). Files stay
        // `internal`; only capability registration, scene views and settings pages are public.
        // The database engine: no UI, no shell dependency. Moved from glassdb's Packages/GlassDBKit
        // minus SSHTunnelManager.swift — the host's own SSH service supplies the forward (D7), so
        // the engine has no Citadel edge and the swift-crypto conflict does not arise.
        .target(
            name: "GlassDBKit",
            dependencies: [
                .product(name: "MySQLNIO", package: "mysql-nio"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
            ],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(
            name: "GlassTerminalEmulator",
            dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),
        .target(
            name: "GlassTerminal",
            dependencies: [
                "GlassTerminalEmulator",
                "GlassShell",
                "GlassLayers",
                "GlassSSHTransport",
                "GlassConnectionKit",
                "GlassConnectionUI",
                "GlassHostCatalog",
                "GlasSecretStore",
                // glas.sh's SFTP remote editor already uses GlassEditorUI; parity brings it.
                "GlassEditorCore", "GlassEditorUI",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                // W2 TEMPORARY until the transport call sites move to GlassSSHTransport:
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
            ],
            // The AI agents' marks as template images, for the iPhone, iPad and Vision Pro, which
            // cannot draw SVG text as the Mac does (`TerminalAgent.markImage`).
            resources: [.process("Resources")],
            // glas.sh builds with Xcode's approachable concurrency: default MainActor isolation
            // plus these upcoming features. Same code, same rules, expressed for SwiftPM.
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        // The database capability: glassdb's app files moved in as one module (Stage 3). Its
        // library is the shell's, its Appearance page is the shell's, and it never imports
        // GlassTerminal — the tunnel it needs comes from the shell's forward broker (D7).
        .target(
            name: "GlassDatabase",
            dependencies: [
                "GlassDBKit",
                "GlassShell",
                "GlassLayers",
                "GlassConnectionKit",
                "GlassConnectionUI",
                "GlasSecretStore",
                // The SQL editor surface and the record editor's JSON fields are GlassEditorKit.
                "GlassEditorCore", "GlassEditorUI",
            ],
            swiftSettings: [.enableUpcomingFeature("MemberImportVisibility")]
        ),
        // Stage 4: the RFB/VNC engine. Unlike RDPKit this is ours — written from RFC 6143 and the
        // public RFB protocol registry, with no third-party VNC source copied or linked — so it is
        // a target here rather than a vendored package.
        // `linkedLibrary("z")` is restated from the package it came from: ZlibInflater, and so the
        // Zlib and ZRLE encodings, link against the system zlib. Dropping it does not fail to
        // compile; it fails at link, or silently costs the two best encodings.
        .target(name: "VNCKit", linkerSettings: [.linkedLibrary("z")]),
        // The two adapters, also ours: frame ownership, configuration and transport selection.
        .target(
            name: "GlassRDPTransport",
            dependencies: [.product(name: "RDPKit", package: "RDPKit")]
        ),
        .target(name: "GlassVNCTransport", dependencies: ["GlassRDPTransport", "VNCKit"]),
        // Stage 4 W2: the remote desktop capability. glassDT's Core and UI merged into one target,
        // as GlassDatabase merged glassdb's, with its three-process machinery left behind.
        .target(
            name: "GlassDesktop",
            dependencies: [
                "GlassRDPTransport", "GlassVNCTransport", "VNCKit", "GlasSecretStore", "GlassShell", "GlassLayers",
                "GlassConnectionKit",
                "GlassConnectionUI",
                "GlassHostCatalog",
            ]
        ),
        .testTarget(name: "GlassDesktopTests", dependencies: ["GlassDesktop"]),
        .testTarget(name: "VNCKitTests", dependencies: ["VNCKit"], resources: [.copy("Fixtures")]),
        .testTarget(name: "GlassRDPTransportTests", dependencies: ["GlassRDPTransport"]),
        .testTarget(name: "GlassVNCTransportTests", dependencies: ["GlassVNCTransport"]),
        .testTarget(name: "GlasSecretStoreTests", dependencies: ["GlasSecretStore"]),
        .testTarget(name: "GlassConnectionKitTests", dependencies: ["GlassConnectionKit"]),
        .testTarget(name: "GlassConnectionUITests", dependencies: ["GlassConnectionUI"]),
        .testTarget(name: "GlassHostCatalogTests", dependencies: ["GlassConnectionKit", "GlassHostCatalog"]),
        .testTarget(name: "GlassEditorCoreTests", dependencies: ["GlassEditorCore"],
                    resources: [.copy("Fixtures")]),
        .testTarget(name: "GlassEditorUITests", dependencies: ["GlassEditorUI"]),
        // The UIKit engine, run on the iOS simulator (`xcodebuild test`); empty on a Mac.
        .testTarget(name: "GlassEditorUIKitTests", dependencies: ["GlassEditorUI"]),
        .testTarget(name: "GlassEditorTests", dependencies: ["GlassEditor"]),
        .testTarget(name: "GlassLayersTests", dependencies: ["GlassLayers"]),
        .testTarget(
            name: "GlassDatabaseTests",
            dependencies: [
                "GlassDatabase",
                "GlassDBKit",
                "GlassShell",
                // Live-tunnel tests only: they open a real SSH forward the way the terminal
                // capability does. The module under test never imports the transport.
                "GlassSSHTransport",
                "GlasSecretStore",
            ]
        ),
        .testTarget(
            name: "GlassTerminalTests",
            dependencies: [
                "GlassTerminal",
                "GlasSecretStore",
                "GlassEditorCore", "GlassEditorUI",
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOCore", package: "swift-nio"),
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        .testTarget(
            name: "GlassSSHTransportTests",
            dependencies: [
                "GlassSSHTransport",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ]
        ),
        .testTarget(
            name: "GlassDBKitTests",
            dependencies: [
                "GlassDBKit",
                .product(name: "MySQLNIO", package: "mysql-nio"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
            ]
        ),
        .testTarget(name: "GlassShellTests", dependencies: ["GlassShell"]),
        // What the widgets show and ask for: no UI, nothing but Foundation and App Intents, so
        // the widget extension carries little.
        .target(name: "GlassWidgetData"),
        .testTarget(name: "GlassWidgetDataTests", dependencies: ["GlassWidgetData"]),
    ],
    swiftLanguageModes: [.v6]
)
