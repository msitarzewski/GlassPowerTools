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
    ],
    dependencies: [
        .package(path: "../GlassConnectionKit"),
        .package(path: "../GlasSecretStore"),
        .package(path: "../GlassEditorKit"),
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
        .testTarget(name: "GlassLayersTests", dependencies: ["GlassLayers"]),
        .testTarget(name: "GlassShellTests", dependencies: ["GlassShell"]),
    ],
    swiftLanguageModes: [.v6]
)
