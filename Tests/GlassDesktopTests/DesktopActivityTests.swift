import Foundation
import Testing
@testable import GlassDesktop

/// A desktop's input marks it in use, for the library's time in use (2026-10-20); the queue's own
/// housekeeping doesn't.
@Suite("A desktop's activity")
@MainActor
struct DesktopActivityTests {
    @Test("a key, a click, a move, a scroll or text is activity; a release or a lock-state sync isn't")
    func inputIsActivity() async {
        var told = 0
        let input = DesktopInput(dispatch: { _ in }, onError: { Issue.record("\($0)") })
        input.onActivity = { told += 1 }
        let point = DesktopPoint(x: 4, y: 4)
        input.send(.synchronize(false))
        input.send(.release)
        #expect(told == 0)
        input.send(.move(point))
        input.send(.button(.left, true, point))
        input.send(.key(0x1e, false, true, false))
        input.send(.scroll(1, 0, point))
        input.send(.text("a"))
        #expect(told == 5)
        await input.flush()
    }
}
