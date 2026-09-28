// swift-tools-version: 6.2
import PackageDescription

// A separate package on purpose: it is a live probe against a real host, never part of `swift test`.
// It consumes the transports exactly as the app does.
let package = Package(
    name: "GlassLiveDesktopProbes",
    platforms: [.macOS("26.0")],
    dependencies: [.package(name: "GlassPowerTools", path: "../..")],
    targets: [
        .executableTarget(name: "GlassWindowsRDPProbe",
                          dependencies: [.product(name: "GlassRDPTransport", package: "GlassPowerTools")]),
        .executableTarget(name: "GlassVNCProbe",
                          dependencies: [.product(name: "GlassRDPTransport", package: "GlassPowerTools"),
                                         .product(name: "GlassVNCTransport", package: "GlassPowerTools")]),
        // Functional probes run by Docker/xrdp/run.sh and Docker/tigervnc/run.sh against disposable
        // local fixtures: they assert side effects (input, resize, clipboard, reconnect), not just a frame.
        .executableTarget(name: "GlassRDPFunctionalProbe",
                          dependencies: [.product(name: "GlassRDPTransport", package: "GlassPowerTools")]),
        .executableTarget(name: "GlassVNCFunctionalProbe",
                          dependencies: [.product(name: "VNCKit", package: "GlassPowerTools")])
    ]
)
