import Foundation
import GlassRDPTransport

@MainActor
final class DesktopInput {
    enum Event: Sendable {
        case move(DesktopPoint)
        case button(GlassRDPPointerButton, Bool, DesktopPoint)
        case key(UInt16, Bool, Bool, Bool)
        case text(String)
        case scroll(Int, Int, DesktopPoint)
        case synchronize(Bool)
        case release
    }
    private var pending: [Event] = []
    private var task: Task<Void, Never>?
    private let dispatch: @Sendable (Event) async throws -> Void
    private let onError: @MainActor (String) -> Void
    private var accepting = true
    /// Told of each key, click, move, scroll or text sent: the library's time in use (2026-10-20).
    var onActivity: (@MainActor () -> Void)?

    convenience init(session: any GlassDesktopTransport, onError: @escaping @MainActor (String) -> Void) {
        self.init(dispatch: { event in
            switch event {
                    case .move(let point): try await session.movePointer(x: point.x, y: point.y)
                    case .button(let button, let down, let point): try await session.pointerButton(button: button, isDown: down, x: point.x, y: point.y)
                    case .key(let code, let extended, let down, let repeated): try await session.keyboard(scancode: code, extended: extended, isDown: down, isRepeat: repeated)
                    case .text(let text): try await session.sendText(text)
                    case .scroll(let vertical, let horizontal, let point): try await session.scroll(vertical: vertical, horizontal: horizontal, x: point.x, y: point.y)
                    case .synchronize(let capsLock): try await session.synchronize(capsLock: capsLock)
                    case .release: await session.releaseInputs()
            }
        }, onError: onError)
    }

    init(dispatch: @escaping @Sendable (Event) async throws -> Void, onError: @escaping @MainActor (String) -> Void) {
        self.dispatch = dispatch
        self.onError = onError
    }

    deinit {
        task?.cancel()
        let dispatch = dispatch
        Task { try? await dispatch(.release) }
    }

    func send(_ event: Event) {
        guard accepting else { return }
        switch event {
        case .move, .button, .key, .text, .scroll: onActivity?()
        case .synchronize, .release: break
        }
        if case .release = event {
            // An in-flight event finishes before this release; unsent input is discarded on focus loss.
            pending.removeAll(keepingCapacity: true)
        } else if case .move = event, let last = pending.last, case .move = last {
            pending[pending.count - 1] = event
            return
        }
        guard pending.count < 512 else {
            stop()
            onError("Remote input could not keep up. Reconnect to resume input safely.")
            return
        }
        pending.append(event)
        drain()
    }

    func stop() {
        accepting = false
        pending = [.release]
        drain()
    }

    func flush() async { await task?.value }

    private func drain() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while let self, !pending.isEmpty, !Task.isCancelled {
                let event = pending.removeFirst()
                do { try await dispatch(event) }
                catch { if accepting { onError(error.localizedDescription) } }
            }
            self?.task = nil
        }
    }
}
