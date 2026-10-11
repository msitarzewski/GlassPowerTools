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
        // Drives VNCKit's client as GlassVNCSession configures it, so it can print a Mac's display
        // metadata as it arrived and ask for a server-side scale (W36).
        .executableTarget(name: "GlassVNCProbe",
                          dependencies: [.product(name: "GlassRDPTransport", package: "GlassPowerTools"),
                                         .product(name: "GlassVNCTransport", package: "GlassPowerTools"),
                                         .product(name: "VNCKit", package: "GlassPowerTools")]),
        // Functional probes run by Docker/xrdp/run.sh and Docker/tigervnc/run.sh against disposable
        // local fixtures: they assert side effects (input, resize, clipboard, reconnect), not just a frame.
        .executableTarget(name: "GlassRDPFunctionalProbe",
                          dependencies: [.product(name: "GlassRDPTransport", package: "GlassPowerTools")]),
        .executableTarget(name: "GlassVNCFunctionalProbe",
                          dependencies: [.product(name: "VNCKit", package: "GlassPowerTools")]),
        // W30, run by Docker/tigervnc-displays/run.sh: two screens, region requests, input mapped
        // into a display by the app's own `DesktopCoordinates`, and bytes per second per quality level.
        .executableTarget(name: "GlassVNCDisplaysProbe",
                          dependencies: [.product(name: "VNCKit", package: "GlassPowerTools"),
                                         .product(name: "GlassDesktop", package: "GlassPowerTools")])
    ]
)
