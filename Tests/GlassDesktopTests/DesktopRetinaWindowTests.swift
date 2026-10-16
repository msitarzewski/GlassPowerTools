import Foundation
import CoreGraphics
import Testing
import GlassConnectionKit
import GlassLayers
import GlassRDPTransport
import GlassShell
import GlassVNCTransport
@testable import GlassDesktop

/// W38 (owner, 2026-10-11, on the Vision Pro with a Mac's Retina display beside a 1x one): "we need
/// a way to lock the dimensions to the actual screen ratio" and "can we have the Mac chill on the 2x
/// retina resolution when screen sharing?" A display window's own connection, its pointer, the
/// pointer's size, and the window's shape.
@MainActor
@Suite("Retina displays at 1x and a display window's own connection", .serialized)
struct DesktopRetinaWindowTests {
    @MainActor private final class Fixture {
        let root: URL
        let defaults: UserDefaults
        var connects: [(transport: ObjectIdentifier, configuration: DesktopTransportConfiguration)] = []
        var disconnects: [ObjectIdentifier] = []

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("DesktopRetinaWindows-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defaults = try #require(UserDefaults.forTest(suiteName: "DesktopRetinaWindowTests-\(UUID().uuidString)"))
        }

        func clean() { try? FileManager.default.removeItem(at: root) }

        func launch() async -> DesktopAppModel {
            let app = DesktopAppModel(storageDirectory: root, credentialAccess: .inMemory(),
                                      windowSettings: DesktopWindowSettingsStore(defaults: defaults))
            await app.attach(store: GlassInMemoryServiceStore(defaultKind: .rdp))
            return app
        }

        var operations: DesktopSessionOperations {
            var value = DesktopSessionOperations()
            value.connect = { transport, configuration in self.connects.append((ObjectIdentifier(transport), configuration)) }
            value.disconnect = { transport in self.disconnects.append(ObjectIdentifier(transport)) }
            value.resize = { _, _, _ in }
            value.delay = { _ in }
            value.recordConnection = { _, _, _ in }
            return value
        }

        let connection = DesktopConnection(name: "bravo", host: "192.0.2.20", port: 5900, username: "", protocol: .vnc)

        /// A Mac with a 2x main display, 3200 × 1800, and a 1x one, 1280 × 800, to its right.
        static let mixed = [GlassRemoteScreen(id: 4, x: 0, y: 0, width: 3200, height: 1800, isPrimary: true, density: 2),
                            GlassRemoteScreen(id: 1, x: 3200, y: 0, width: 1280, height: 800, isPrimary: false, density: 1)]
        /// Two Retina displays.
        static let uniform = [GlassRemoteScreen(id: 4, x: 0, y: 0, width: 3200, height: 1800, isPrimary: true, density: 2),
                              GlassRemoteScreen(id: 5, x: 3200, y: 0, width: 2560, height: 1440, isPrimary: false, density: 2)]

        /// The mechanism's tests turn it on; the app leaves it off (`opensDisplayConnections`).
        var opensDisplayConnections = true

        func connected(app: DesktopAppModel, screens: [GlassRemoteScreen] = Fixture.mixed,
                       framebuffer: (Int, Int) = (4480, 1800)) async throws -> DesktopSessionModel {
            let session = DesktopSessionModel(connection: connection, app: app, operations: operations,
                                              wallpaperRoot: root.appendingPathComponent("wallpapers"))
            session.canOpenDisplayWindows = true
            session.displayWindows = .oneWindow
            session.opensDisplayConnections = opensDisplayConnections
            session.attach(session.primaryViewport)
            try await session.connect(username: "", domain: nil, password: "test secret")
            await session.receive(.state(.connected), attempt: session.attemptID, connection: connection)
            session.receive(try GlassRDPFrame(width: framebuffer.0, height: framebuffer.1, bytesPerRow: framebuffer.0 * 4,
                                              pixels: Data(count: framebuffer.0 * framebuffer.1 * 4), sequence: 1),
                            attempt: session.attemptID)
            await session.receive(.screens(screens), attempt: session.attemptID, connection: connection)
            session.primaryViewport.selectedScreenID = screens.first?.id
            return session
        }

        /// Lets the display connection's opening task run.
        func settle(until condition: () -> Bool) async {
            for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
        }
    }

    private static func frame(_ width: Int, _ height: Int) throws -> GlassRDPFrame {
        try GlassRDPFrame(width: width, height: height, bytesPerRow: width * 4, pixels: Data(count: width * height * 4), sequence: 1)
    }

    @Test("a display's window opens its own connection with the sign-in already given, and the desktop's stops fetching it")
    func ownConnectionLifecycle() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let session = try await fixture.connected(app: await fixture.launch())
        let second = session.displayViewport(for: 1)
        session.attach(second)
        let connection = try #require(session.displayConnections[second.id])
        await fixture.settle { fixture.connects.count == 2 }
        #expect(fixture.connects.count == 2, "the desktop's connection, then the display's")
        let primary = try #require(fixture.connects.first?.configuration.vnc)
        let display = try #require(fixture.connects.last?.configuration.vnc)
        #expect(display.display == 1 && primary.display == nil)
        #expect(display.host == primary.host && display.port == primary.port)
        #expect(display.username == primary.username && display.password == "test secret", "the same sign-in, held for this attempt")
        #expect(!display.clipboardEnabled, "the clipboard is the desktop's connection's (D42a)")
        #expect(!session.needsCredentials, "never asked again")
        #expect(fixture.connects.last?.transport == ObjectIdentifier(connection.transport))

        // Until it shows a picture, the window shows its display from the desktop's connection.
        #expect(session.ownConnection(for: second) == nil)
        #expect(session.currentRequestedRegions == [GlassRemoteRegion(x: 0, y: 0, width: 3200, height: 1800),
                                                    GlassRemoteRegion(x: 3200, y: 0, width: 1280, height: 800)])
        connection.receive(.state(.connected))
        connection.receive(try Self.frame(1280, 800))
        #expect(session.ownConnection(for: second) === connection)
        #expect(session.currentRequestedRegions == [GlassRemoteRegion(x: 0, y: 0, width: 3200, height: 1800)],
                "the desktop's connection fetches only the display it still shows: one density, so 1x")
        #expect(session.pictureFrame(for: second)?.width == 1280)
        #expect(session.pictureRegion(for: second) == .whole(width: 1280, height: 800))
        #expect(session.inputTransport(for: second) === connection.transport)
        #expect(session.inputTransport(for: session.primaryViewport) === session.transport)

        // A window in the background fetches nothing on either connection.
        second.isOnScreen = false
        #expect(session.currentRequestedRegions == [GlassRemoteRegion(x: 0, y: 0, width: 3200, height: 1800)])

        // Closing the window closes its connection; the desktop's carries on.
        session.detach(second)
        #expect(session.displayConnections.isEmpty && connection.isClosed)
        await fixture.settle { fixture.disconnects.contains(ObjectIdentifier(connection.transport)) }
        #expect(fixture.disconnects.contains(ObjectIdentifier(connection.transport)))
        #expect(session.isConnected && !session.shouldClosePresentation)
        session.close()
    }

    /// The owner (2026-10-11, Vision Pro): "The second display doesn't reflect any changes." A Mac
    /// serves one scale at a time: the 1x display's own connection got nothing once the desktop's
    /// was at half size.
    @Test("as the app runs: a Retina display and a 1x display both come from the desktop's connection, at their own pixels")
    func noSecondConnectionInTheApp() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        fixture.opensDisplayConnections = false
        let session = try await fixture.connected(app: await fixture.launch())
        #expect(!DesktopSessionModel(connection: fixture.connection, app: await fixture.launch(), operations: fixture.operations,
                                     wallpaperRoot: fixture.root).opensDisplayConnections, "off unless a test turns it on")
        let second = session.displayViewport(for: 1)
        session.attach(second)
        await fixture.settle { fixture.connects.count > 1 }
        #expect(session.displayConnections.isEmpty && fixture.connects.count == 1, "one connection")
        #expect(session.currentRequestedRegions == [GlassRemoteRegion(x: 0, y: 0, width: 3200, height: 1800),
                                                    GlassRemoteRegion(x: 3200, y: 0, width: 1280, height: 800)],
                "both displays from the desktop's connection: mixed densities, so their own pixels")
        #expect(session.inputTransport(for: second) === session.transport)
        session.close()
    }

    @Test("one density, Native 2x, the desktop's own window, or All Displays: no second connection")
    func whenThereIsNone() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let app = await fixture.launch()
        let uniform = try await fixture.connected(app: app, screens: Fixture.uniform, framebuffer: (5760, 1800))
        let other = uniform.displayViewport(for: 5)
        uniform.attach(other)
        #expect(uniform.displayConnections.isEmpty, "two Retina displays share one factor: one connection asks 1x of both")
        #expect(!uniform.hasMixedDensities)
        uniform.close()

        let session = try await fixture.connected(app: app)
        #expect(session.hasMixedDensities)
        #expect(session.ownConnectionDisplay(for: session.primaryViewport) == nil, "the desktop's own window keeps its connection")
        let second = session.displayViewport(for: 1)
        session.attach(second)
        #expect(session.displayConnections.count == 1)
        session.retinaDisplays = .native
        #expect(session.displayConnections.isEmpty, "Native 2x: each display at its own pixels, on one connection")
        session.retinaDisplays = .oneX
        #expect(session.displayConnections.count == 1)
        second.selectedScreenID = nil
        #expect(session.displayConnections.isEmpty, "All Displays is the desktop's picture")
        session.close()
    }

    @Test("a second connection the Mac will not take is not tried again, and the window shows its display as before")
    func refusedConnection() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let session = try await fixture.connected(app: await fixture.launch())
        let second = session.displayViewport(for: 1)
        session.attach(second)
        let connection = try #require(session.displayConnections[second.id])
        connection.receive(.state(.failed("The Mac did not send display 1 on a connection of its own within ten seconds.")))
        #expect(session.displayConnections.isEmpty)
        #expect(session.displayConnectionFailure?.contains("did not send display 1") == true)
        second.isOnScreen = false; second.isOnScreen = true
        #expect(session.displayConnections.isEmpty, "not tried again for this connection")
        #expect(session.pictureRegion(for: second) == DesktopRegion(origin: .init(x: 3200, y: 0), size: DesktopSize(width: 1280, height: 800)))
        #expect(!session.needsCredentials && session.isConnected)
        session.close()
    }

    @Test("a point in a display window's own picture is the session's pointer, in the desktop's framebuffer, and back")
    func pointerPerWindow() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let session = try await fixture.connected(app: await fixture.launch())
        let second = session.displayViewport(for: 1)
        session.attach(second)
        let connection = try #require(session.displayConnections[second.id])
        connection.receive(.state(.connected))
        connection.receive(try Self.frame(1280, 800))
        session.movePointer(to: DesktopPoint(x: 640, y: 400), in: second)
        #expect(session.pointerPosition == DesktopPoint(x: 3840, y: 400))
        #expect(session.pointerInPicture(for: second) == DesktopPoint(x: 640, y: 400))
        #expect(session.pointerInPicture(for: session.primaryViewport) == nil, "drawn only in the window of the display it is on")
        // Where the Mac says its pointer is, from the display's connection: mapped the same way.
        connection.receive(.cursor(.position(x: 10, y: 20)))
        #expect(session.pointerPosition == DesktopPoint(x: 3210, y: 20))
        // The desktop's connection at half size: the display's part of it is half too.
        await session.receive(.screens(Fixture.mixed.map {
            GlassRemoteScreen(id: $0.id, x: $0.x / 2, y: $0.y / 2, width: $0.width / 2, height: $0.height / 2,
                              isPrimary: $0.isPrimary, density: $0.density)
        }), attempt: session.attemptID, connection: fixture.connection)
        session.movePointer(to: DesktopPoint(x: 640, y: 400), in: second)
        #expect(session.pointerPosition == DesktopPoint(x: 1920, y: 200))
        #expect(session.pointerInPicture(for: second) == DesktopPoint(x: 640, y: 400))
        // A window on the desktop's connection: its picture is the desktop's.
        session.movePointer(to: DesktopPoint(x: 100, y: 100), in: session.primaryViewport)
        #expect(session.pointerPosition == DesktopPoint(x: 100, y: 100))
        #expect(session.pointerInPicture(for: session.primaryViewport) == DesktopPoint(x: 100, y: 100))
        session.close()
    }

    @Test("a Mac's pointer is drawn at its display's pixels per point: twice its pixels on a Retina display at its own pixels")
    func pointerSize() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let session = try await fixture.connected(app: await fixture.launch())
        let shape = GlassRDPCursorImage(width: 1, height: 1, hotSpotX: 0, hotSpotY: 0, xorBitsPerPixel: 32,
                                        xorMask: Data([1, 2, 3, 255]), andMask: Data([0, 0]), paletteEntries: nil, isPointSized: true)
        await session.receive(.cursor(.image(shape)), attempt: session.attemptID, connection: fixture.connection)
        #expect(session.cursorBitmap?.isPointSized == true)
        #expect(session.cursorPictureScale(for: session.primaryViewport) == 2, "the 2x display at its own pixels")
        await session.receive(.linkStatistics(GlassDesktopLinkStatistics(bytesPerSecond: 0, updatesPerSecond: 0, quality: .best,
                                                                          level: .best, colourDepth: 24, encoding: nil,
                                                                          measuredKilobitsPerSecond: nil, regionLimited: true,
                                                                          paused: false, serverScale: 0.5)),
                              attempt: session.attemptID, connection: fixture.connection)
        #expect(session.cursorPictureScale(for: session.primaryViewport) == 1, "the 2x display at 1x")
        session.primaryViewport.selectedScreenID = 1
        #expect(session.cursorPictureScale(for: session.primaryViewport) == 0.5, "the 1x display at half")
        #expect(session.sending(for: session.primaryViewport) == "1280 × 800 at 0.5x (50%)")
        let pixels = GlassRDPCursorImage(width: 1, height: 1, hotSpotX: 0, hotSpotY: 0, xorBitsPerPixel: 32,
                                         xorMask: Data([1, 2, 3, 255]), andMask: Data([0, 0]), paletteEntries: nil)
        await session.receive(.cursor(.image(pixels)), attempt: session.attemptID, connection: fixture.connection)
        #expect(session.cursorPictureScale(for: session.primaryViewport) == 1, "a shape in the picture's pixels is drawn as they are")
        #expect(DesktopLinkReadout.density(2) == "2x" && DesktopLinkReadout.density(1) == "1x"
                && DesktopLinkReadout.density(0.75) == "0.75x" && DesktopLinkReadout.density(1.5) == "1.5x")
        session.close()
    }

    @Test("a window keeps its display's shape, the chrome around it added; while the desktop follows the window, it is free")
    func aspect() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let app = await fixture.launch()
        let session = try await fixture.connected(app: app)
        #expect(session.pictureAspect(for: session.primaryViewport) == 3200.0 / 1800.0,
                "a Mac never takes the window's size: its window is held")
        let second = session.displayViewport(for: 1)
        session.attach(second)
        #expect(session.pictureAspect(for: second) == 1.6)
        second.keepsProportions = false
        #expect(session.pictureAspect(for: second) == nil)
        session.close()

        // A host that resizes to the window (Match Window Size): the window is free; turned off, held.
        let single = try await fixture.connected(app: app, screens: [], framebuffer: (1920, 1080))
        await single.receive(.displayCapabilities(.init(maximumMonitors: 1, maximumArea: UInt64(DesktopSize.maximumPixels))),
                             attempt: single.attemptID, connection: fixture.connection)
        #expect(single.matchWindow && single.pictureAspect(for: single.primaryViewport) == nil)
        single.matchWindow = false
        #expect(single.pictureAspect(for: single.primaryViewport) == 1920.0 / 1080.0)
        single.close()

        // The window: the picture's shape plus 34 points of chrome on each side on Vision Pro.
        #expect(DesktopWindowAspect.spatialChrome == CGSize(width: 68, height: 68))
        #expect(GlassWindowAspect.windowSize(current: CGSize(width: 1280, height: 800), aspect: 16.0 / 9.0,
                                             chrome: DesktopWindowAspect.spatialChrome,
                                             minimum: DesktopWindowAspect.spatialMinimum) == CGSize(width: 1280, height: 750))
        // A portrait display keeps the window's height, and grows to the minimum width keeping its shape.
        #expect(GlassWindowAspect.windowSize(current: CGSize(width: 1280, height: 800), aspect: 0.5,
                                             chrome: DesktopWindowAspect.spatialChrome,
                                             minimum: DesktopWindowAspect.spatialMinimum) == CGSize(width: 800, height: 1532))
        // A very wide picture: below the minimum height, grown keeping its shape.
        #expect(GlassWindowAspect.windowSize(current: CGSize(width: 900, height: 500), aspect: 4,
                                             chrome: DesktopWindowAspect.spatialChrome,
                                             minimum: DesktopWindowAspect.spatialMinimum) == CGSize(width: 1556, height: 440))
        // No chrome (a Mac window whose status bar is measured as none): the picture is the window.
        #expect(GlassWindowAspect.windowSize(current: CGSize(width: 1000, height: 1000), aspect: 2, chrome: .zero,
                                             minimum: .zero) == CGSize(width: 1000, height: 500))
        #expect(GlassWindowAspect.sameAspect(1.6, 1.603) && !GlassWindowAspect.sameAspect(1.6, 1.7))
    }

    @Test("Retina Displays is the connection's, from the desktop's window; Keep Display Proportions is each window's")
    func settings() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let session = try await fixture.connected(app: await fixture.launch())
        var window = GlassWindowOverrides()
        window[DesktopWindowSettings.retina] = .native
        window[DesktopWindowSettings.keepProportions] = false
        let profile = DesktopWindowProfile(window: window, defaults: .standard, reduceTransparency: false)
        #expect(profile.retina == .native && !profile.keepProportions)
        let second = session.displayViewport(for: 1)
        session.attach(second)
        session.apply(profile, to: second)
        #expect(session.retinaDisplays == .oneX && !second.keepsProportions, "a display window cannot change the connection")
        session.apply(profile, to: session.primaryViewport)
        #expect(session.retinaDisplays == .native && !session.primaryViewport.keepsProportions)
        #expect(DesktopDefaults.standard.retina == .oneX && DesktopDefaults.standard.keepProportions)
        let stored = DesktopDefaults(storedOpacity: 1, frost: 0, backgroundRemoval: "", red: 1, green: 0, blue: 1, tolerance: 0,
                                     edgeSoftness: 0, detail: "", pointer: "", retina: "native", keepProportions: false)
        #expect(stored.retina == .native && !stored.keepProportions)
        let unknown = DesktopDefaults(storedOpacity: 1, frost: 0, backgroundRemoval: "", red: 1, green: 0, blue: 1, tolerance: 0,
                                      edgeSoftness: 0, detail: "", pointer: "", retina: "4x")
        #expect(unknown.retina == .oneX)
        #expect(DesktopWindowSettings.keys.contains("desktop.retina") && DesktopWindowSettings.keys.contains("desktop.keepProportions"))
        session.close()
    }

    @Test("modifiers armed for the next key are taken once, in a fixed order, and cleared with the session")
    func armedModifiers() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let session = try await fixture.connected(app: await fixture.launch())
        session.toggleArmed(.shift)
        session.toggleArmed(.command)
        session.toggleArmed(.option)
        session.toggleArmed(.option)
        #expect(session.armedModifiers == [.shift, .command])
        #expect(session.takeArmedModifiers() == [DesktopKey(0x5b, extended: true), DesktopKey(0x2a)], "Command before Shift")
        #expect(session.armedModifiers.isEmpty && session.takeArmedModifiers().isEmpty, "for one key only")
        session.toggleArmed(.control)
        session.close()
        #expect(session.armedModifiers.isEmpty)
    }

    @Test("High Performance is the connection's, from the desktop's window, and asks for the window's size at its density")
    func highPerformance() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let session = try await fixture.connected(app: await fixture.launch())
        #expect(session.highPerformanceRequest() == nil, "Standard unless chosen")
        var window = GlassWindowOverrides()
        window[DesktopWindowSettings.macScreenSharing] = .highPerformance
        let profile = DesktopWindowProfile(window: window, defaults: .standard, reduceTransparency: false)
        let second = session.displayViewport(for: 1)
        session.attach(second)
        session.apply(profile, to: second)
        #expect(session.macScreenSharing == .standard, "a display window cannot change the connection")
        session.apply(profile, to: session.primaryViewport)
        #expect(session.macScreenSharing == .highPerformance)
        #expect(session.highPerformanceRequest() == GlassVNCHighPerformance(width: 1920, height: 1080, density: 1),
                "no window size yet: 1920 × 1080")
        session.resize(width: 1366.4, height: 800, displayScale: 2)
        #expect(session.highPerformanceRequest() == GlassVNCHighPerformance(width: 1366, height: 800, density: 2))
        session.resize(width: 300, height: 200, displayScale: 1)
        #expect(session.highPerformanceRequest() == GlassVNCHighPerformance(width: 640, height: 480, density: 1), "at least 640 × 480")
        session.streamQuality = .dataSaver
        #expect(session.highPerformanceRequest()?.bitrateCap == 8_000_000)
        session.streamQuality = .lowest
        #expect(session.highPerformanceRequest()?.bitrateCap == 3_000_000)
        session.streamQuality = .best
        #expect(session.highPerformanceRequest()?.bitrateCap == nil, "the Mac's own rate controller")
        let stored = DesktopDefaults(storedOpacity: 1, frost: 0, backgroundRemoval: "", red: 1, green: 0, blue: 1, tolerance: 0,
                                     edgeSoftness: 0, detail: "", pointer: "", macScreenSharing: "highPerformance")
        #expect(stored.macScreenSharing == .highPerformance && DesktopDefaults.standard.macScreenSharing == .standard)
        #expect(DesktopWindowSettings.keys.contains("desktop.macScreenSharing"))
        // Its status reaches the window while the session runs, and goes with it.
        await session.receive(.highPerformance(.streaming), attempt: session.attemptID, connection: fixture.connection)
        #expect(session.highPerformanceStatus == .streaming)
        #expect(DesktopLinkReadout.highPerformance(.unavailable("No.")) == "Not available: No.")
        session.close()
        #expect(session.highPerformanceStatus == nil)
    }
}
