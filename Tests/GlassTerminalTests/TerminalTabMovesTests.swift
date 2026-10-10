import Foundation
import CoreTransferable
import Testing
import UniformTypeIdentifiers
@testable import GlassTerminal

/// W15 (owner, 2026-10-09, on the Vision Pro): "We also have no way to move tabs from one window
/// to another," then "maybe we do that with grid view? drag and drop." A tab moves — the same
/// terminal, still running, never a second client on its session — into another window or a new
/// one, and a window whose last tab leaves closes.
///
/// Nothing connects: terminals are registered with the manager and moved between workgroups.
@MainActor
@Suite("Tabs move between windows")
struct TerminalTabMovesTests {
    private func server(_ name: String) -> ServerConfiguration {
        ServerConfiguration(name: name, host: "\(name).example.com", username: "ann")
    }

    private func terminal(_ name: String, in manager: SessionManager) -> TerminalSession {
        let session = TerminalSession(server: server(name))
        manager.registerSession(session)
        return session
    }

    private func workgroup(_ name: String, _ sessions: [TerminalSession], in manager: SessionManager) -> UUID {
        let id = manager.createWorkgroup(name: name, colorTag: .blue)
        for session in sessions { manager.appendSession(session, toWorkgroup: id) }
        return id
    }

    @Test("moved into another window: the same terminal, selected there at its place; the rest stay; a window left empty goes")
    func movedBetweenWindows() {
        let manager = SessionManager(loadImmediately: false)
        let a1 = terminal("alpha", in: manager), a2 = terminal("alpha", in: manager), b1 = terminal("bravo", in: manager)
        let left = workgroup("Left", [a1, a2], in: manager)
        let right = workgroup("Right", [b1], in: manager)
        manager.selectSession(a1.id, inWorkgroup: left)

        #expect(TerminalTabMoves.move(a1.id, to: right, at: 0, in: manager) == .moved(sourceClosed: false))
        #expect(manager.workgroup(for: right)?.sessionIDs == [a1.id, b1.id])
        #expect(manager.selectedSession(inWorkgroup: right) === a1, "the very same session, selected where it went")
        #expect(manager.workgroup(for: left)?.sessionIDs == [a2.id])
        #expect(manager.selectedSession(inWorkgroup: left) === a2)
        #expect(manager.sessions.count == 3, "moved, never copied")

        // Its last tab gone, a window's workgroup goes too, so the window closes.
        #expect(TerminalTabMoves.move(a2.id, to: right, at: nil, in: manager) == .moved(sourceClosed: true))
        #expect(manager.workgroup(for: left) == nil)
        #expect(manager.workgroup(for: right)?.sessionIDs == [a1.id, b1.id, a2.id], "nil: after the last")
        #expect(manager.sessions.count == 3)
    }

    @Test("within one window a drop takes the place it lands on and keeps the selection")
    func reorderedWithinAWindow() {
        let manager = SessionManager(loadImmediately: false)
        let one = terminal("one", in: manager), two = terminal("two", in: manager), three = terminal("three", in: manager)
        let id = workgroup("Grid", [one, two, three], in: manager)
        manager.selectSession(two.id, inWorkgroup: id)

        #expect(TerminalTabMoves.move(one.id, to: id, at: 2, in: manager) == .reordered)
        #expect(manager.workgroup(for: id)?.sessionIDs == [two.id, three.id, one.id])
        #expect(TerminalTabMoves.move(one.id, to: id, at: 0, in: manager) == .reordered)
        #expect(manager.workgroup(for: id)?.sessionIDs == [one.id, two.id, three.id])
        #expect(TerminalTabMoves.move(one.id, to: id, at: nil, in: manager) == .reordered, "nil: to the end")
        #expect(manager.workgroup(for: id)?.sessionIDs == [two.id, three.id, one.id])
        #expect(TerminalTabMoves.move(three.id, to: id, at: 99, in: manager) == .reordered, "held to the window")
        #expect(manager.workgroup(for: id)?.sessionIDs == [two.id, one.id, three.id])
        #expect(manager.selectedSession(inWorkgroup: id) === two)
    }

    @Test("refused, nothing changes: a terminal in no window, a window that's gone, a full window")
    func refused() {
        let manager = SessionManager(loadImmediately: false)
        let loose = terminal("loose", in: manager)
        let a = terminal("alpha", in: manager)
        let left = workgroup("Left", [a], in: manager)
        #expect(TerminalTabMoves.move(loose.id, to: left, at: nil, in: manager) == .refused)
        #expect(TerminalTabMoves.move(a.id, to: UUID(), at: nil, in: manager) == .refused)

        let full = workgroup("Full", (0..<LayoutPreset.maximumSessionCount).map { terminal("t\($0)", in: manager) }, in: manager)
        #expect(TerminalTabMoves.move(a.id, to: full, at: 0, in: manager) == .refused)
        #expect(manager.workgroup(for: left)?.sessionIDs == [a.id])
    }

    @Test("Move Tab to New Window: a new workgroup named for its machine, holding only it; refused, nothing is left behind")
    func movedToANewWindow() throws {
        let manager = SessionManager(loadImmediately: false)
        let a = terminal("alpha", in: manager), b = terminal("bravo", in: manager)
        let left = workgroup("Left", [a, b], in: manager)

        let created = try #require(TerminalTabMoves.moveToNewWorkgroup(b.id, in: manager))
        #expect(manager.workgroup(for: created)?.name == "bravo", "named as Connect names one, so Active names it by the terminal")
        #expect(manager.workgroup(for: created)?.sessionIDs == [b.id])
        #expect(manager.workgroup(for: left)?.sessionIDs == [a.id])

        let loose = terminal("loose", in: manager)
        let before = manager.workgroups
        #expect(TerminalTabMoves.moveToNewWorkgroup(loose.id, in: manager) == nil)
        #expect(TerminalTabMoves.moveToNewWorkgroup(UUID(), in: manager) == nil)
        #expect(manager.workgroups == before, "no empty workgroup, and no empty window")
    }

    @Test("Move Tab To lists the other windows as Active names them; two alike say which terminal each shows")
    func destinations() {
        let manager = SessionManager(loadImmediately: false)
        let here = terminal("alpha", in: manager)
        let first = terminal("bravo", in: manager), second = terminal("bravo", in: manager)
        let third = terminal("charlie", in: manager), fourth = terminal("delta", in: manager)
        let source = workgroup("Here", [here], in: manager)
        // Two windows Connect made on the same machine, and one with a name of its own.
        let bravoOne = workgroup("bravo", [first], in: manager)
        let bravoTwo = workgroup("bravo", [second], in: manager)
        let named = workgroup("Deploy", [third, fourth], in: manager)
        first.rename(to: "logs")
        second.rename(to: "logs")
        third.rename(to: "build")
        manager.selectSession(third.id, inWorkgroup: named)
        _ = manager.createWorkgroup(name: "Emptied", colorTag: .blue)

        let all = TerminalTabMoves.destinations(from: source, among: nil, in: manager)
        #expect(all.map(\.id) == [bravoOne, bravoTwo, named], "never its own, nor one with nothing in it")
        #expect(all.map(\.title) == ["logs", "logs", "Deploy"], "a lone terminal by its name; a named workgroup by its name")

        second.rename(to: nil)
        #expect(TerminalTabMoves.destinations(from: source, among: nil, in: manager).map(\.title) == ["logs", "bravo", "Deploy"])

        // Two named alike: each says the terminal it shows.
        let twin = workgroup("Deploy", [terminal("echo", in: manager)], in: manager)
        let titles = TerminalTabMoves.destinations(from: source, among: nil, in: manager)
        #expect(titles.first { $0.id == named }?.title == "Deploy · build")
        #expect(titles.first { $0.id == twin }?.title == "Deploy · echo")

        // Vision Pro: only windows that are open, so a moved tab never vanishes from sight.
        #expect(TerminalTabMoves.destinations(from: source, among: [named], in: manager).map(\.id) == [named])
    }

    // MARK: One terminal to a window (W26)
    //
    // The owner, on the Vision Pro: "we still don't have a way to combine two independent terminal
    // windows there's no tab to drag between". The terminal's tools menu and its title move it.

    @Test("two windows of one terminal each combine: the terminal moves in, and the window it left goes")
    func loneTerminalsCombine() {
        let manager = SessionManager(loadImmediately: false)
        let a = terminal("alpha", in: manager), b = terminal("bravo", in: manager)
        let left = workgroup("alpha", [a], in: manager)
        let right = workgroup("bravo", [b], in: manager)

        // The tools menu: the other open window, never its own, and no new window for a terminal
        // that is in one of its own already.
        #expect(TerminalTabMoves.destinations(from: left, among: [left, right], in: manager).map(\.id) == [right])
        #expect(!TerminalTabMoves.canMoveToNewWindow(from: left, in: manager))

        #expect(TerminalTabMoves.move(a.id, to: right, at: nil, in: manager) == .moved(sourceClosed: true))
        #expect(manager.workgroup(for: left) == nil, "its window closes")
        #expect(manager.workgroup(for: right)?.sessionIDs == [b.id, a.id])
        #expect(manager.selectedSession(inWorkgroup: right) === a, "the very same session, on screen where it went")
        #expect(manager.sessions.count == 2, "moved, never copied")
        #expect(TerminalTabMoves.canMoveToNewWindow(from: right, in: manager), "with two, either can leave")
    }

    @Test("a title let go over its own window stays where it is; one from another window arrives")
    func droppedOnItsOwnWindow() {
        let manager = SessionManager(loadImmediately: false)
        let a1 = terminal("alpha", in: manager), a2 = terminal("alpha", in: manager), b = terminal("bravo", in: manager)
        let left = workgroup("Left", [a1, a2], in: manager)
        let right = workgroup("Right", [b], in: manager)
        let own = TerminalTabTransfer(workgroupID: left, sessionID: a1.id)
        let other = TerminalTabTransfer(workgroupID: right, sessionID: b.id)

        #expect(TerminalTabMoves.arriving([own], at: left, in: manager).isEmpty,
                "not taken, so not sent to the end of its own tabs")
        #expect(TerminalTabMoves.arriving([own, other], at: left, in: manager) == [other])
        // Where the terminal is now decides, not where the drag says it began.
        let movedSince = TerminalTabTransfer(workgroupID: right, sessionID: a2.id)
        #expect(TerminalTabMoves.arriving([movedSince], at: left, in: manager).isEmpty)
        #expect(TerminalTabMoves.arriving([movedSince], at: right, in: manager) == [movedSince])
    }

    // MARK: The drag

    @Test("a dragged tab arrives as the tab it was, and only this app's windows read it")
    func dragRoundTrip() async throws {
        let tab = TerminalTabTransfer(workgroupID: UUID(), sessionID: UUID())
        let provider = NSItemProvider()
        provider.register(tab)
        #expect(TerminalTabTransfer.isCarried(by: [provider]))
        #expect(!TerminalTabTransfer.isCarried(by: [NSItemProvider(object: "text" as NSString)]))

        let loaded: [TerminalTabTransfer] = await withCheckedContinuation { continuation in
            TerminalTabTransfer.load(from: [provider]) { continuation.resume(returning: $0) }
        }
        #expect(loaded == [tab])
    }

    @Test("a tab dropped on a terminal is never uploaded as a file")
    func neverUploaded() async throws {
        let session = TerminalSession(server: server("alpha"))
        session.state = .connected
        var opened = false
        let drops = TerminalRemoteDrops(openClient: { _ in
            opened = true
            throw SSHError.notConnected
        }, upload: { _, _, _, _, _, _ in throw SSHError.notConnected })
        let provider = NSItemProvider()
        let tab = TerminalTabTransfer(workgroupID: UUID(), sessionID: session.id)
        provider.register(tab)

        #expect(!drops.receive([provider], on: session), "refused, so the system sends it back")
        await drops.waitForDrop(on: session.id)
        #expect(!opened, "nothing was sent to the host")
        #expect(drops.statuses[session.id] == nil)
    }
}
