#if os(macOS)
import Testing
import SwiftUI
import GlassShell
@testable import GlassTerminal

/// Show All Windows (2026-10-13; Show All Terminals before): every other kind of window joins the
/// terminal windows' groups, a group per kind, from the shell's list of open sessions.
@Suite("Show All Windows: every kind of window")
@MainActor
struct MacShowAllWindowsTests {
    private func session(_ id: String, _ title: String, symbol: String = "circle") -> GlassOpenSession {
        GlassOpenSession(id: id, title: title, symbolName: symbol, activate: {}, close: {})
    }

    @Test("Databases, Desktops, Editor in turn; the terminal's sessions are its windows' own; an unknown kind still shows")
    func groupsByKind() {
        let groups = MacTerminalExposeModel.otherGroups([
            session("editor:1", "notes.md"),
            session("desktop:2", "bravo", symbol: "display"),
            session("terminal:3", "alpha"),
            session("database:4", "shop"),
            session("desktop:5", "charlie", symbol: "display"),
            session("files:6", "uploads"),
        ])
        #expect(groups.map(\.title) == ["Databases", "Desktops", "Editor", "Other"])
        #expect(groups[1].tiles.map(\.title) == ["bravo", "charlie"])
        #expect(groups[1].tiles.map(\.id) == [.session("desktop:2"), .session("desktop:5")])
        #expect(groups[1].tiles.first?.symbolName == "display")
        // A Files browser no tab shows comes first, as its own kind of window.
        let files = MacTerminalExposeModel.otherGroups([session("terminal-session:7", "SFTP on alpha", symbol: "folder")])
        #expect(files.map(\.title) == ["Files"])
        #expect(!groups.flatMap(\.tiles).contains { $0.title == "alpha" }, "a terminal is shown by its window's group")
    }

    @Test("Nothing open but terminals: no other groups")
    func onlyTerminals() {
        #expect(MacTerminalExposeModel.otherGroups([session("terminal:1", "alpha")]).isEmpty)
    }

    @Test("Typing narrows the other kinds too")
    func typingFindsADesktop() {
        let groups = MacTerminalExposeModel.otherGroups([session("desktop:1", "bravo"), session("database:2", "shop")])
        #expect(MacTerminalExposeModel.filtered(groups, by: "brav").map(\.title) == ["Desktops"])
    }
}
#endif
