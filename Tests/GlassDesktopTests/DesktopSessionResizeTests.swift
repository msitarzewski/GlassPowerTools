import Foundation
import Testing
import GlassRDPTransport
@testable import GlassDesktop

/// The server can change its own size — GNOME's login screen takes the window, the session after
/// it comes up at 640 × 480 — and the window must be asked for again (2026-09-22, alpha).
@Suite("A desktop that changes size on its own is asked for the window again")
@MainActor
struct DesktopSessionResizeTests {
    @MainActor private final class Fixture {
        let root: URL
        let app: DesktopAppModel
        let connection: DesktopConnection
        var sizes: [DesktopSize] = []
        var connects: [GlassRDPConfiguration] = []

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("DesktopResize-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            app = DesktopAppModel(storageDirectory: root, credentialAccess: .inMemory())
            connection = DesktopConnection(name: "alpha", host: "alpha.local", username: "michael")
        }

        func clean() { try? FileManager.default.removeItem(at: root) }

        /// No host: connect records the configuration, resize records the size, delays are instant.
        var operations: DesktopSessionOperations {
            var value = DesktopSessionOperations()
            value.connect = { _, configuration in if let rdp = configuration.rdp { self.connects.append(rdp) } }
            value.disconnect = { _ in }
            value.resize = { _, size, _ in self.sizes.append(size) }
            value.delay = { _ in }
            value.recordConnection = { _, _, _ in }
            return value
        }

        func model() -> DesktopSessionModel {
            DesktopSessionModel(connection: connection, app: app, operations: operations,
                                wallpaperRoot: root.appendingPathComponent("wallpapers"))
        }

        /// Connected, with the display channel open, the window reported at a Retina 1330 × 813
        /// points and that request acknowledged: the state of a session at the login screen.
        func atTheLoginScreen(_ model: DesktopSessionModel) async throws -> DesktopSize {
            try await model.connect(username: "michael", domain: nil, password: "test secret")
            await model.receive(.state(.connected), attempt: model.attemptID, connection: connection)
            await model.receive(.displayCapabilities(.init(maximumMonitors: 1, maximumArea: UInt64(DesktopSize.maximumPixels))),
                                attempt: model.attemptID, connection: connection)
            model.resize(width: 1330, height: 813, displayScale: 2)
            await model.resizeTask?.value
            let window = try #require(sizes.last)
            #expect(window == DesktopSize(width: 2660, height: 1626), "the window at two pixels per point")
            model.receive(try frame(window), attempt: model.attemptID)
            await model.resizeTask?.value
            #expect(sizes.count == 1, "a frame at the size asked for asks for nothing")
            return window
        }

        func frame(_ size: DesktopSize) throws -> GlassRDPFrame {
            try GlassRDPFrame(width: size.width, height: size.height, bytesPerRow: size.width * 4,
                              pixels: Data(count: size.width * 4 * size.height), sequence: UInt64(sizes.count))
        }
    }

    @Test("Logging in resets the desktop to 640 × 480; the window is asked for again, once")
    func loginSizeIsCorrected() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let model = fixture.model()
        let window = try await fixture.atTheLoginScreen(model)

        let session = DesktopSize(width: 640, height: 480)
        model.receive(try fixture.frame(session), attempt: model.attemptID)
        await model.resizeTask?.value
        #expect(fixture.sizes == [window, window], "the server changed its mind, so the window was asked for again")

        // The server keeps sending at its own size until it honours the request: no more asking.
        model.receive(try fixture.frame(session), attempt: model.attemptID)
        model.receive(try fixture.frame(session), attempt: model.attemptID)
        await model.resizeTask?.value
        #expect(fixture.sizes.count == 2, "frames at an unchanged size are not a new change of mind")

        // Honoured: back at the window's size, nothing further.
        model.receive(try fixture.frame(window), attempt: model.attemptID)
        await model.resizeTask?.value
        #expect(fixture.sizes.count == 2)
        await model.close().value
    }

    @Test("A server that keeps changing is asked a bounded number of times, not once per frame")
    func correctionsAreBounded() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let model = fixture.model()
        _ = try await fixture.atTheLoginScreen(model)

        for round in 0..<6 {
            let size = DesktopSize(width: 640 + round * 2, height: 480)
            model.receive(try fixture.frame(size), attempt: model.attemptID)
            await model.resizeTask?.value
        }
        #expect(fixture.sizes.count == 1 + DesktopSessionModel.maximumServerSizeCorrections)
        await model.close().value
    }

    @Test("The connect itself asks for the window's size at the window's scale, so the first frame is laid out right")
    func connectCarriesTheScale() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let model = fixture.model()
        // The view reports its size during layout, before the session starts.
        model.resize(width: 1330, height: 813, displayScale: 2)
        try await model.connect(username: "michael", domain: nil, password: "test secret")
        let rdp = try #require(fixture.connects.last)
        #expect(rdp.width == 2660 && rdp.height == 1626, "two pixels per point")
        #expect(rdp.desktopScaleFactor == 200, "and laid out at 200%, from the first frame")
        await model.close().value
    }

    @Test("With Match Window Size off, the server's size is its own business")
    func manualSizeIsLeftAlone() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let model = fixture.model()
        _ = try await fixture.atTheLoginScreen(model)
        model.matchWindow = false
        model.receive(try fixture.frame(DesktopSize(width: 640, height: 480)), attempt: model.attemptID)
        await model.resizeTask?.value
        #expect(fixture.sizes.count == 1)
        await model.close().value
    }
}

@Suite("A new desktop window on a Mac opens at the configured desktop, within the screen")
struct DesktopWindowSizingTests {
    @Test("The configured desktop, one point per pixel, when the screen has room")
    func configuredDesktopFits() {
        let size = DesktopWindowSizing.contentSize(desktop: DesktopSize(width: 1920, height: 1080),
                                                   available: CGSize(width: 2056, height: 1250))
        #expect(size == CGSize(width: 1920, height: 1080))
    }

    @Test("A desktop larger than the screen is held to the screen")
    func heldToTheScreen() {
        let size = DesktopWindowSizing.contentSize(desktop: DesktopSize(width: 3840, height: 2160),
                                                   available: CGSize(width: 2056, height: 1250))
        #expect(size == CGSize(width: 2056, height: 1250))
    }

    @Test("Nothing opens below the floor, whatever the desktop or the screen says")
    func floorWins() {
        let tiny = DesktopWindowSizing.contentSize(desktop: DesktopSize(width: 200, height: 200),
                                                   available: CGSize(width: 2056, height: 1250))
        #expect(tiny == DesktopWindowSizing.floor)
        let small = DesktopWindowSizing.contentSize(desktop: DesktopSize(width: 1920, height: 1080),
                                                    available: CGSize(width: 500, height: 300))
        #expect(small == DesktopWindowSizing.floor)
        #expect(DesktopWindowSizing.isAtFloor(CGSize(width: 640, height: 400)))
        #expect(DesktopWindowSizing.isAtFloor(CGSize(width: 1326, height: 400)))
        #expect(!DesktopWindowSizing.isAtFloor(CGSize(width: 1326, height: 905)))
    }
}
