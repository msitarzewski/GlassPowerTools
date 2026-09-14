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
    ],
    dependencies: [
        .package(path: "../GlassConnectionKit"),
        .package(path: "../GlassEditorKit"),
        // The SSH stack vendored from glas.sh, verbatim (see Stage 2 transport note).
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
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.15.0"),
        // Stage 4: the RDP engine. A vendored fork of steelbrain/RDPKit 0.3.1 (MIT, Steelbrain
        // copyright retained), so it sits in Packages/ beside the other vendored forks rather than
        // in Sources/ with our own code. Its patch record is Packages/RDPKit/GLASSDT-PATCHES.md.
        .package(path: "Packages/RDPKit"),
    ],
    targets: [
        // Credentials, trust storage and mobility. Absorbed from the standalone GlasSecretStore
        // package on 2026-09-13: that repository is obsolete, Glass Power Tools is now the only
        // consumer, and the split had become a reason not to fix its own eligibility list.
        // The module name is unchanged, so no `import` moved.
        .target(name: "GlasSecretStore"),
        .target(
            name: "GlassLayers",
            dependencies: [
                .product(name: "GlassConnectionUI", package: "GlassConnectionKit"),
            ]
        ),
        .target(
            name: "GlassShell",
            dependencies: [
                "GlassLayers",
                .product(name: "GlassConnectionKit", package: "GlassConnectionKit"),
                .product(name: "GlassConnectionUI", package: "GlassConnectionKit"),
                .product(name: "GlassHostCatalog", package: "GlassConnectionKit"),
                "GlasSecretStore",
                .product(name: "GlassEditorCore", package: "GlassEditorKit"),
            ]
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
                .product(name: "GlassConnectionKit", package: "GlassConnectionKit"),
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
                .product(name: "GlassConnectionKit", package: "GlassConnectionKit"),
                .product(name: "GlassConnectionUI", package: "GlassConnectionKit"),
                .product(name: "GlassHostCatalog", package: "GlassConnectionKit"),
                "GlasSecretStore",
                // glas.sh's SFTP remote editor already uses GlassEditorUI; parity brings it.
                .product(name: "GlassEditorKit", package: "GlassEditorKit"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                // W2 TEMPORARY until the transport call sites move to GlassSSHTransport:
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
            ],
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
                .product(name: "GlassConnectionKit", package: "GlassConnectionKit"),
                .product(name: "GlassConnectionUI", package: "GlassConnectionKit"),
                "GlasSecretStore",
                // The SQL editor surface and the record editor's JSON fields are GlassEditorKit.
                .product(name: "GlassEditorKit", package: "GlassEditorKit"),
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
                "GlassRDPTransport", "GlassVNCTransport", "GlasSecretStore", "GlassShell", "GlassLayers",
                .product(name: "GlassConnectionKit", package: "GlassConnectionKit"),
                .product(name: "GlassConnectionUI", package: "GlassConnectionKit"),
                .product(name: "GlassHostCatalog", package: "GlassConnectionKit"),
            ]
        ),
        .testTarget(name: "GlassDesktopTests", dependencies: ["GlassDesktop"]),
        .testTarget(name: "VNCKitTests", dependencies: ["VNCKit"]),
        .testTarget(name: "GlassRDPTransportTests", dependencies: ["GlassRDPTransport"]),
        .testTarget(name: "GlassVNCTransportTests", dependencies: ["GlassVNCTransport"]),
        .testTarget(name: "GlasSecretStoreTests", dependencies: ["GlasSecretStore"]),
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
                .product(name: "GlassEditorKit", package: "GlassEditorKit"),
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
    ],
    swiftLanguageModes: [.v6]
)
