import Foundation
import Testing
@testable import GlassTerminalEmulator

/// A terminal's new size goes to tmux once a resize is over (the owner, 2026-11-21: "hold the size until
/// the resize ends"): each size tmux was given during a window's drag made Claude Code print its whole
/// conversation again, and left the last copy in the history at the old width.
@MainActor
@Suite("Sizes held for tmux until a resize ends")
struct TmuxResizeHoldTests {
    @MainActor private final class Record {
        var handed: [String] = []
        var waits = 0
        var liveResizing = false
    }

    /// A wait that is over at once, so each step is the test's to take. Cancelled, it ends at once,
    /// as `Task.sleep` does.
    private func hold(_ record: Record, letGoAfter waits: Int? = nil) -> TmuxResizeHold {
        TmuxResizeHold(
            sleep: { _ in
                try Task.checkCancellation()
                record.waits += 1
                if record.waits == waits { record.liveResizing = false }
                await Task.yield()
            },
            isLiveResizing: { record.liveResizing },
            handOn: { record.handed.append("\($0)x\($1)") })
    }

    @Test("a resize's sizes reach tmux once: the last, after they stop changing")
    func lastSizeOnce() async {
        let record = Record()
        let hold = hold(record)
        hold.size(columns: 100, rows: 30, hold: true)
        hold.size(columns: 105, rows: 30, hold: true)
        hold.size(columns: 110, rows: 32, hold: true)
        #expect(record.handed.isEmpty, "nothing while sizes change")
        await hold.waitUntilHandedOn()
        #expect(record.handed == ["110x32"])
        #expect(record.waits == 1, "one wait: each newer size ended the one before")
    }

    @Test("nothing goes while a window is resized by its edge; the last size goes once it is let go")
    func heldThroughALiveResize() async {
        let record = Record()
        record.liveResizing = true
        let hold = hold(record, letGoAfter: 3)
        hold.size(columns: 140, rows: 40, hold: true)
        hold.size(columns: 120, rows: 40, hold: true)
        await hold.waitUntilHandedOn()
        #expect(record.handed == ["120x40"])
        #expect(record.waits == 3, "waited until the edge was let go")
    }

    @Test("before the pane is followed a size goes at once, and one held is dropped")
    func notHeldAtTheStart() async {
        let record = Record()
        let hold = hold(record)
        hold.size(columns: 100, rows: 30, hold: true)
        hold.size(columns: 90, rows: 20, hold: false)
        #expect(record.handed == ["90x20"], "at once: the attach waits on it")
        await hold.waitUntilHandedOn()
        // The held size's wait has its turn to run.
        for _ in 0..<10 { await Task.yield() }
        #expect(record.handed == ["90x20"], "the held size never follows it")
    }
}
