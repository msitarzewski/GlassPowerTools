// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RDPKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
        .tvOS(.v17),
        .macCatalyst(.v17),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "RDPKit",
            targets: ["RDPKit"]
        ),
    ],
    dependencies: [
        // Glass Power Tools local patch: upstream pins these `exact:`. In a single-graph app that
        // freezes every other consumer of NIO at the same two versions. The engine has no API
        // requirement for an exact pin — the versions below are the ones it was tested against and
        // remain what the app resolves. See GLASSDT-PATCHES.md.
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.102.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.37.4"),
    ],
    targets: [
        .target(
            name: "RDPKit",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOTLS", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
            ]
        ),
        .testTarget(
            name: "RDPKitTests",
            dependencies: [
                "RDPKit",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOEmbedded", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
            ],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
