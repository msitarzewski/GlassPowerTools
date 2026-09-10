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
        .library(name: "GlassShell", targets: ["GlassShell"]),
        .library(name: "GlassLayers", targets: ["GlassLayers"]),
        .library(name: "GlassSSHTransport", targets: ["GlassSSHTransport"]),
        .library(name: "GlassTerminal", targets: ["GlassTerminal"]),
        .library(name: "GlassTerminalEmulator", targets: ["GlassTerminalEmulator"]),
    ],
    dependencies: [
        .package(path: "../GlassConnectionKit"),
        .package(path: "../GlasSecretStore"),
        .package(path: "../GlassEditorKit"),
        // The SSH stack vendored from glas.sh, verbatim (see Stage 2 transport note).
        .package(path: "Packages/Citadel"),
        .package(path: "Packages/swift-nio-ssh"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.101.3"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.14.0"),
        // Terminal emulator host (glas.sh's misnamed RealityKitContent package) and its engine.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.15.0"),
    ],
    targets: [
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
                .product(name: "GlasSecretStore", package: "GlasSecretStore"),
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
                .product(name: "GlasSecretStore", package: "GlasSecretStore"),
                .product(name: "GlassConnectionKit", package: "GlassConnectionKit"),
            ]
        ),
        // The SSH capability: glas.sh moved in as one module (decision 2026-09-10). Files stay
        // `internal`; only capability registration, scene views and settings pages are public.
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
                .product(name: "GlasSecretStore", package: "GlasSecretStore"),
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
        .testTarget(name: "GlassLayersTests", dependencies: ["GlassLayers"]),
        .testTarget(
            name: "GlassTerminalTests",
            dependencies: [
                "GlassTerminal",
                .product(name: "GlasSecretStore", package: "GlasSecretStore"),
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
        .testTarget(name: "GlassShellTests", dependencies: ["GlassShell"]),
    ],
    swiftLanguageModes: [.v6]
)
