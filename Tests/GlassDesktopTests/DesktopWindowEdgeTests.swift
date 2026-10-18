#if os(macOS)
import AppKit
import Foundation
import Testing
import GlassConnectionKit
import GlassConnectionUI
import GlassShell
@testable import GlassDesktop

/// The owner, 2026-10-17: "remove the gray line in database and desktop windows too". A desktop
/// window has no sidebar, so the chrome's hairline stood down its leading edge, full height; the
/// picture now reaches the edge with no line.
@Suite(.serialized) @MainActor
struct DesktopWindowEdgeTests {
    @Test func noLineDownTheLeadingEdge() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DesktopWindowEdge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults = try #require(UserDefaults.forTest(suiteName: "DesktopWindowEdgeTests-\(UUID().uuidString)"))
        let app = DesktopAppModel(storageDirectory: root, credentialAccess: .inMemory(),
                                  windowSettings: DesktopWindowSettingsStore(defaults: defaults))
        await app.attach(store: GlassInMemoryServiceStore(defaultKind: .rdp))
        let connection = DesktopConnection(name: "bravo", host: "192.0.2.20", port: 5900, username: "", protocol: .vnc)
        let session = DesktopSessionModel(connection: connection, app: app, operations: DesktopSessionOperations(),
                                          wallpaperRoot: root.appendingPathComponent("wallpapers"))

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        defer { window.close() }
        let surface = DesktopMTKView(session: session, inputEnabled: false)
        surface.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        window.contentView?.addSubview(surface)

        let frame = try #require(window.contentView?.superview)
        frame.layoutSubtreeIfNeeded()
        let material = try #require(frame.subviews.compactMap { $0 as? GlassTitlebarMaterialView }.first)
        let hairline = try #require(frame.subviews.first { $0.identifier?.rawValue == "glass.sidebar.separator" })
        #expect(abs(hairline.frame.minX) < 1, "with no sidebar, the hairline's place is the window's edge")
        #expect(!material.showsSidebarEdge)
        #expect(hairline.isHidden)
    }
}
#endif
