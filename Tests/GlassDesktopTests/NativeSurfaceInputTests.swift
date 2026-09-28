//
//  NativeSurfaceInputTests.swift
//  Glass Power Tools — GlassDesktopTests
//
//  Ported from glassDT `Tests/GlassDesktopCoreTests/NativeSurfaceInputTests.swift` on 2026-09-27.
//  Adapted: glassDT's `GlassDesktopCore` and `GlassDesktopUI` are one module here, `GlassDesktop`.
//  The fixture's `DesktopAppModel` no longer takes glassDT's `sharedDirectory` (the App Group
//  catalog it pointed at is gone, D26); it is built with a storage directory and in-memory
//  credentials so nothing touches the Keychain. It is never attached to a catalog because these
//  tests never save or load a desktop. Every test and assertion is unchanged. macOS only, as in
//  glassDT.
//

#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import GlassDesktop

@Suite("Native desktop input isolation") @MainActor
struct NativeSurfaceInputTests {
    @Test func localControlsReleaseAndDiscardRemoteInputUntilDismissed() async throws {
        let fixture = NativeSurfaceFixture()
        defer { fixture.clean() }
        await fixture.connectFixture()
        let view = DesktopMTKView(session: fixture.session)
        view.update(fixture.session)
        await view.input?.flush()
        let recorder = SurfaceInputRecorder()
        let input = DesktopInput(dispatch: { await recorder.receive($0) }, onError: { Issue.record("\($0)") })
        view.input = input
        defer { view.shutdown() }
        view.insertText("before", replacementRange: NSRange(location: NSNotFound, length: 0))
        input.send(.key(0x1e, false, true, false))
        await input.flush()
        view.setMarkedText("composing", selectedRange: NSRange(location: 9, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(view.hasMarkedText())
        input.send(.text("queued input must be discarded"))
        view.update(fixture.session, inputEnabled: false)
        view.insertText("blocked", replacementRange: NSRange(location: NSNotFound, length: 0))
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        await input.flush()
        #expect(!view.acceptsFirstResponder)
        #expect(!view.hasMarkedText())
        #expect(await recorder.events == ["text:before", "down", "release"])
        view.update(fixture.session, inputEnabled: true)
        #expect(view.acceptsFirstResponder)
        view.insertText("after", replacementRange: NSRange(location: NSNotFound, length: 0))
        await input.flush()
        #expect(await recorder.events == ["text:before", "down", "release", "text:after"])
        await fixture.session.close().value
    }

    @Test func reenablingDoesNotStealFocusFromNativeForm() async throws {
        _ = NSApplication.shared
        let fixture = NativeSurfaceFixture()
        defer { fixture.clean() }
        await fixture.connectFixture()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        let view = DesktopMTKView(session: fixture.session)
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 300)
        let field = NSTextField(frame: NSRect(x: 20, y: 320, width: 240, height: 24))
        container.addSubview(view)
        container.addSubview(field)
        window.contentView = container
        defer { view.shutdown(); window.close() }
        view.update(fixture.session)
        #expect(window.makeFirstResponder(view))
        #expect(window.firstResponder === view)
        view.update(fixture.session, inputEnabled: false)
        #expect(window.firstResponder !== view)
        #expect(window.makeFirstResponder(field))
        let localResponder = try #require(window.firstResponder)
        view.update(fixture.session, inputEnabled: true)
        #expect(window.firstResponder === localResponder)
        await fixture.session.close().value
    }
}

@MainActor
private final class NativeSurfaceFixture {
    let directory: URL
    let connection: DesktopConnection
    let session: DesktopSessionModel

    init() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gpt-desktop-native-input-\(UUID())")
        let connection = DesktopConnection(name: "Input fixture", host: "input.invalid", username: "fixture")
        self.directory = directory
        self.connection = connection
        let app = DesktopAppModel(storageDirectory: directory, credentialAccess: .inMemory())
        var operations = DesktopSessionOperations()
        operations.connect = { _, _ in Issue.record("Input isolation must never connect to a host") }
        operations.disconnect = { _ in }
        session = DesktopSessionModel(connection: connection, app: app, operations: operations,
            wallpaperRoot: directory.appendingPathComponent("wallpapers"))
    }

    func connectFixture() async {
        await session.receive(.state(.connected), attempt: session.attemptID, connection: connection)
    }

    func clean() { try? FileManager.default.removeItem(at: directory) }
}

private actor SurfaceInputRecorder {
    private(set) var events: [String] = []
    func receive(_ event: DesktopInput.Event) {
        switch event {
        case let .text(value): events.append("text:\(value)")
        case let .key(_, _, down, _): events.append(down ? "down" : "up")
        case .release: events.append("release")
        default: events.append("other")
        }
    }
}
#endif
