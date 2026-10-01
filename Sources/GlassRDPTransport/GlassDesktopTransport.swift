import Foundation

/// The transport surface the desktop session model and native input surfaces depend on.
/// RDP and VNC sessions both publish immutable BGRA frames and the same event vocabulary, and
/// accept the same RDP set-1 scancode input so platform keyboard handling stays protocol-agnostic.
public protocol GlassDesktopTransport: Actor {
    nonisolated var frames: AsyncStream<GlassRDPFrame> { get }
    nonisolated var events: AsyncStream<GlassRDPEvent> { get }
    func disconnect() async
    func keyboard(scancode: UInt16, extended: Bool, isDown: Bool, isRepeat: Bool) async throws
    func sendText(_ text: String) async throws
    func movePointer(x: Int, y: Int) async throws
    func pointerButton(button: GlassRDPPointerButton, isDown: Bool, x: Int, y: Int) async throws
    func scroll(vertical: Int, horizontal: Int, x: Int, y: Int) async throws
    func releaseInputs() async
    func synchronize(capsLock: Bool, numLock: Bool, scrollLock: Bool) async throws
    func resize(width: Int, height: Int, desktopScale: Int) async throws
    func sendClipboard(_ content: GlassClipboardContent) async throws
}

public extension GlassDesktopTransport {
    func keyboard(scancode: UInt16, extended: Bool = false, isDown: Bool) async throws {
        try await keyboard(scancode: scancode, extended: extended, isDown: isDown, isRepeat: false)
    }
    func synchronize(capsLock: Bool) async throws {
        try await synchronize(capsLock: capsLock, numLock: true, scrollLock: false)
    }
}

extension GlassRDPSession: GlassDesktopTransport {}
