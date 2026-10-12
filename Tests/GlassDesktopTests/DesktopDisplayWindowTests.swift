import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
import GlassRDPTransport
import GlassShell
@testable import GlassDesktop

/// W30 (owner, 2026-10-10, on Vision Pro over a mobile connection): "I'd like two screens,
/// independently controllable like a real desktop setup." One connection; a window per display,
/// each with its own display, zoom and settings; input landing on its display; only what is on
/// screen asked for; the session ending with its last window.
@MainActor
@Suite("A display in a window of its own", .serialized)
struct DesktopDisplayWindowTests {
    @MainActor private final class Fixture {
        let root: URL
        let defaults: UserDefaults
        var resizes: [DesktopSize] = []

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("DesktopDisplayWindows-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defaults = try #require(UserDefaults.forTest(suiteName: "DesktopDisplayWindowTests-\(UUID().uuidString)"))
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
            value.connect = { _, _ in }
            value.disconnect = { _ in }
            value.resize = { _, size, _ in self.resizes.append(size) }
            value.delay = { _ in }
            value.recordConnection = { _, _, _ in }
            return value
        }

        let connection = DesktopConnection(name: "bravo", host: "192.0.2.20", port: 5900, username: "", protocol: .vnc)

        /// A connected session to a host with two displays: a 2000 × 1200 main display and a
        /// 1000 × 600 one to its right, in one 3000 × 1600 framebuffer.
        func connected(app: DesktopAppModel, displayWindows: DesktopDisplayWindows = .oneWindow,
                       canOpenWindows: Bool = true) async throws -> DesktopSessionModel {
            let session = DesktopSessionModel(connection: connection, app: app, operations: operations,
                                              wallpaperRoot: root.appendingPathComponent("wallpapers"))
            session.canOpenDisplayWindows = canOpenWindows
            session.displayWindows = displayWindows
            session.attach(session.primaryViewport)
            try await session.connect(username: "", domain: nil, password: "test secret")
            await session.receive(.state(.connected), attempt: session.attemptID, connection: connection)
            session.receive(try GlassRDPFrame(width: 3000, height: 1600, bytesPerRow: 3000 * 4,
                                              pixels: Data(count: 3000 * 1600 * 4), sequence: 1), attempt: session.attemptID)
            await session.receive(.displayCapabilities(.init(maximumMonitors: 1, maximumArea: UInt64(DesktopSize.maximumPixels))),
                                  attempt: session.attemptID, connection: connection)
            await session.receive(.screens(Self.screens), attempt: session.attemptID, connection: connection)
            return session
        }

        static let screens = [GlassRemoteScreen(id: 1, x: 0, y: 0, width: 2000, height: 1200, isPrimary: true),
                              GlassRemoteScreen(id: 2, x: 2000, y: 0, width: 1000, height: 600, isPrimary: false)]
        static let main = GlassRemoteRegion(x: 0, y: 0, width: 2000, height: 1200)
        static let second = GlassRemoteRegion(x: 2000, y: 0, width: 1000, height: 600)
    }

    @Test("each window shows its own display, and only the displays on screen are asked for")
    func regionsFollowTheWindowsOnScreen() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let session = try await fixture.connected(app: await fixture.launch())
        #expect(session.currentRequestedRegions == nil, "one window showing every display asks for everything")

        session.primaryViewport.selectedScreenID = 1
        #expect(session.currentRequestedRegions == [Fixture.main])
        let second = session.displayViewport(for: 2)
        session.attach(second)
        #expect(session.region(for: second) == DesktopRegion(origin: .init(x: 2000, y: 0), size: DesktopSize(width: 1000, height: 600)))
        #expect(session.currentRequestedRegions == [Fixture.main, Fixture.second])

        second.isOnScreen = false
        #expect(session.currentRequestedRegions == [Fixture.main], "a window in the background costs nothing")
        session.primaryViewport.isOnScreen = false
        #expect(session.currentRequestedRegions == [], "nothing on screen: nothing asked for")
        session.primaryViewport.isOnScreen = true
        session.primaryViewport.selectedScreenID = nil
        #expect(session.currentRequestedRegions == nil)
        session.close()
    }

    @Test("a display that leaves the layout: the desktop's window shows everything, a display's window waits for it")
    func aDisplayLeavesAndComesBack() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let session = try await fixture.connected(app: await fixture.launch())
        session.primaryViewport.selectedScreenID = 2
        let second = session.displayViewport(for: 2)
        session.attach(second)
        await session.receive(.screens([Fixture.screens[0]]), attempt: session.attemptID, connection: fixture.connection)
        #expect(session.primaryViewport.selectedScreenID == nil)
        #expect(second.selectedScreenID == 2)
        #expect(session.region(for: second) == .whole(width: 3000, height: 1600))
        await session.receive(.screens(Fixture.screens), attempt: session.attemptID, connection: fixture.connection)
        #expect(session.region(for: second).origin == DesktopPoint(x: 2000, y: 0), "back on its display")
        session.close()
    }

    @Test("a point in a display's window lands inside that display's rectangle of the framebuffer")
    func inputLandsOnTheWindowsDisplay() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let session = try await fixture.connected(app: await fixture.launch())
        let second = session.displayViewport(for: 2)
        session.attach(second)
        let region = session.region(for: second)
        // The middle of a 500 × 300-point window showing the 1000 × 600 display.
        let middle = DesktopCoordinates.map(x: 250, y: 150, viewWidth: 500, viewHeight: 300,
                                            desktop: region.size, origin: region.origin)
        #expect(middle == DesktopPoint(x: 2500, y: 300))
        let corner = DesktopCoordinates.map(x: 0, y: 0, viewWidth: 500, viewHeight: 300, desktop: region.size, origin: region.origin)
        #expect(corner == DesktopPoint(x: 2000, y: 0))
        // The main display's window maps the same point into its own display.
        session.primaryViewport.selectedScreenID = 1
        let main = session.region(for: session.primaryViewport)
        #expect(DesktopCoordinates.map(x: 250, y: 150, viewWidth: 500, viewHeight: 300, desktop: main.size, origin: main.origin)
                == DesktopPoint(x: 1000, y: 600))
        session.close()
    }

    @Test("closing one display's window leaves the others connected; closing the last ends the session")
    func theSessionEndsWithItsLastWindow() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let app = await fixture.launch()
        let session = try await fixture.connected(app: app)
        let second = session.displayViewport(for: 2)
        session.attach(second)
        #expect(session.displayViewport(for: 2) === second, "a display window that is open is the one used")

        session.detach(session.primaryViewport)
        #expect(!session.shouldClosePresentation)
        #expect(session.isConnected)
        #expect(app.liveSession(for: fixture.connection.id) === session, "the desktop's window, reopened, joins it")
        #expect(session.leadViewport === second, "the display window answers for the session now")

        session.detach(second)
        #expect(session.shouldClosePresentation)
        #expect(app.liveSession(for: fixture.connection.id) == nil)
    }

    @Test("a window for each display: the desktop's window shows the main one and asks for the rest, once")
    func aWindowForEachDisplay() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let session = try await fixture.connected(app: await fixture.launch(), displayWindows: .windowPerDisplay)
        #expect(session.primaryViewport.selectedScreenID == 1)
        #expect(session.displayWindowRequests == [2])
        #expect(session.takeDisplayWindowRequests() == [2])
        #expect(session.displayWindowRequests.isEmpty)

        // Its window opens, and is closed by hand: it is not asked for again in this session.
        let second = session.displayViewport(for: 2)
        session.attach(second)
        session.detach(second)
        await session.receive(.screens(Fixture.screens), attempt: session.attemptID, connection: fixture.connection)
        #expect(session.displayWindowRequests.isEmpty)
        session.close()

        // Where a second window cannot open, nothing changes.
        let phone = try await fixture.connected(app: await fixture.launch(), displayWindows: .windowPerDisplay, canOpenWindows: false)
        #expect(phone.primaryViewport.selectedScreenID == nil && phone.displayWindowRequests.isEmpty)
        phone.close()
        // And with one window, the window shows every display.
        let one = try await fixture.connected(app: await fixture.launch(), displayWindows: .oneWindow)
        #expect(one.primaryViewport.selectedScreenID == nil && one.displayWindowRequests.isEmpty)
        one.close()
    }

    @Test("a display's window keeps its own settings, per display, and they go with the desktop")
    func perDisplaySettingsPersist() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let app = await fixture.launch()
        let session = try await fixture.connected(app: app)
        var own = GlassWindowOverrides()
        own[DesktopWindowSettings.opacity] = 0.4
        own[DesktopWindowSettings.backgroundRemoval] = .removeBlack
        session.displayViewport(for: 2).windowSettings = own
        session.close()

        let relaunched = await fixture.launch()
        let again = try await fixture.connected(app: relaunched)
        #expect(again.displayViewport(for: 2).windowSettings == own)
        #expect(again.primaryViewport.windowSettings.isEmpty, "the desktop's own window is a different window")
        #expect(again.displayViewport(for: 1).windowSettings.isEmpty, "and so is the other display's")
        let stored = try #require(fixture.defaults.data(forKey: DesktopWindowSettingsStore.key)
            .flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(stored.keys.contains("\(fixture.connection.id.rawValue.uuidString)/display/2"))

        relaunched.windowSettings.remove(fixture.connection.id)
        #expect(relaunched.windowSettings.settings(for: DesktopWindowKey(endpoint: fixture.connection.id, display: 2)).isEmpty)
        again.close()
    }

    @Test("Quality and Display Windows are the desktop's window's; a display window cannot change them for the connection")
    func connectionSettingsComeFromTheDesktopsWindow() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let session = try await fixture.connected(app: await fixture.launch())
        var defaults = DesktopDefaults()
        defaults.quality = .dataSaver
        defaults.displays = .windowPerDisplay
        session.apply(DesktopWindowProfile(window: GlassWindowOverrides(), defaults: defaults, reduceTransparency: false))
        #expect(session.streamQuality == .dataSaver && session.displayWindows == .windowPerDisplay)

        var own = GlassWindowOverrides()
        own[DesktopWindowSettings.quality] = .best
        session.apply(DesktopWindowProfile(window: own, defaults: defaults, reduceTransparency: false))
        #expect(session.streamQuality == .best, "the desktop's window's own Quality")

        let second = session.displayViewport(for: 2)
        var displays = GlassWindowOverrides()
        displays[DesktopWindowSettings.quality] = .lowest
        displays[DesktopWindowSettings.opacity] = 0.5
        session.apply(DesktopWindowProfile(window: displays, defaults: defaults, glass: true, reduceTransparency: false), to: second)
        #expect(session.streamQuality == .best, "a display window draws with its settings but does not set the connection's")
        #expect(second.presentation.opacity == 0.5 && session.presentation.opacity == 1)
        session.close()
    }

    @Test("a host with several displays keeps its layout: no Match Window Size, no Desktop Resolution")
    func severalDisplaysAreNotResized() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let session = try await fixture.connected(app: await fixture.launch())
        #expect(session.holdsDisplayLayout)
        session.resize(width: 1280, height: 800)
        try await Task.sleep(for: .milliseconds(400))
        await session.setSourceSize(DesktopSize(width: 1920, height: 1080))
        #expect(fixture.resizes.isEmpty, "SetDesktopSize would fold the displays into one")
        #expect(session.errorMessage?.contains("several displays") == true)
        session.close()
    }

    @Test("the link's readout is the connection's, while connected")
    func statistics() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let session = try await fixture.connected(app: await fixture.launch())
        let value = GlassDesktopLinkStatistics(bytesPerSecond: 150_000, updatesPerSecond: 9.5, quality: .automatic, level: .dataSaver,
                                               colourDepth: 16, encoding: "ZRLE", measuredKilobitsPerSecond: 1_800,
                                               regionLimited: true, paused: false)
        await session.receive(.linkStatistics(value), attempt: session.attemptID, connection: fixture.connection)
        #expect(session.linkStatistics == value)
        #expect(DesktopLinkReadout.line(value) == "1.2 Mbit/s · 9.5 updates/s · 16-bit color · ZRLE")
        #expect(DesktopLinkReadout.rate(bytesPerSecond: 40_000) == "320 kbit/s")
        #expect(DesktopLinkReadout.level(value) == "Automatic: Data Saver")
        #expect(DesktopLinkReadout.colour(8) == "256 colors")
        // W36: a Mac sending a smaller picture says so; at its own size, nothing is added.
        var scaled = value
        scaled.serverScale = 0.75
        #expect(DesktopLinkReadout.line(scaled) == "1.2 Mbit/s · 9.5 updates/s · 16-bit color · ZRLE · 75% size")
        scaled.serverScale = 1
        #expect(DesktopLinkReadout.line(scaled) == "1.2 Mbit/s · 9.5 updates/s · 16-bit color · ZRLE")
        #expect(DesktopLinkReadout.scale(0.5) == "50%")
        #expect(DesktopLinkReadout.roundTrip(0.042, queued: 0.002) == "42 ms")
        #expect(DesktopLinkReadout.roundTrip(1.25, queued: 1.21) == "1.2 s, 1.2 s of it waiting in the network")
        #expect(DesktopLinkReadout.roundTrip(0.3, queued: 0.26) == "300 ms, 260 ms of it waiting in the network")
        #expect(DesktopLinkReadout.roundTrip(0.08, queued: nil) == "80 ms")
        await session.receive(.state(.disconnected), attempt: session.attemptID, connection: fixture.connection)
        #expect(session.linkStatistics == nil)
        session.close()
    }

    @Test("window keys and All Desktops' new settings read back what was stored, and nothing else")
    func keysAndDefaults() {
        let id = EndpointID()
        for key in [DesktopWindowKey(endpoint: id), DesktopWindowKey(endpoint: id, display: 7)] {
            #expect(DesktopWindowKey(storageKey: key.storageKey) == key)
        }
        #expect(DesktopWindowKey(storageKey: "\(id.rawValue.uuidString)/display/x") == nil)
        #expect(DesktopWindowKey(storageKey: "\(id.rawValue.uuidString)/screen/7") == nil)
        let stored = DesktopDefaults(storedOpacity: 1, frost: 0, backgroundRemoval: "", red: 1, green: 0, blue: 1,
                                     tolerance: 0, edgeSoftness: 0, detail: "", pointer: "", quality: "dataSaver",
                                     displays: "windowPerDisplay")
        #expect(stored.quality == .dataSaver && stored.resolvedDisplays == .windowPerDisplay)
        let unknown = DesktopDefaults(storedOpacity: 1, frost: 0, backgroundRemoval: "", red: 1, green: 0, blue: 1,
                                      tolerance: 0, edgeSoftness: 0, detail: "", pointer: "", quality: "turbo", displays: "")
        #expect(unknown.quality == .automatic && unknown.resolvedDisplays == DesktopDisplayWindows.standard)
        #expect(DesktopDisplayLayout.name(of: 2, in: Fixture.screens) == "Display 2")
        #expect(DesktopDisplayLayout.name(of: 1, in: Fixture.screens) == "Main Display")
        #expect(DesktopDisplayLayout.mainScreen(Fixture.screens)?.id == 1)
    }
}
