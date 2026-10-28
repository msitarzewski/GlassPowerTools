import Foundation
import Testing
@testable import GlassTerminal

/// Auto-focus on activity with several terminals at work: the one in front keeps its place while it
/// prints (the owner, 2026-10-27: "the hyper refresh is back and the gear no longer works").
@Suite("Auto-focus on activity with several terminals at work")
struct TerminalActivityFocusTests {
    @Test("the terminal in front keeps its place while it prints; the last to print comes forward once it is quiet")
    func keepsTheFrontWhileItPrints() {
        let front = UUID(), other = UUID()
        let start = ContinuousClock.now
        var focus = TerminalActivityFocus()
        focus.note(front, at: start)
        focus.note(other, at: start + .milliseconds(100))
        #expect(!focus.brings(other, over: front, at: start + .milliseconds(200)), "the one in front still printing")
        #expect(focus.brings(other, over: front, at: start + .milliseconds(1_300)), "the one in front quiet")
        #expect(focus.brings(other, over: nil, at: start), "nothing in front")
        #expect(!focus.brings(front, over: front, at: start + .seconds(5)), "already in front")
    }
}
