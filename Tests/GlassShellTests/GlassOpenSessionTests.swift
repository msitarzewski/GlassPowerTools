import Testing
import Foundation
import SwiftUI
@testable import GlassShell
import GlassConnectionKit

/// D1: one list of what is open, contributed rather than known by the shell.
@Suite("Open sessions: one list, contributed")
@MainActor
struct GlassOpenSessionTests {
    /// A capability that has whatever sessions the test says it has, and records what was done.
    private final class StubCapability: GlassCapability {
        let kind: HostServiceKind
        let displayName: String
        let symbolName = "circle"
        var sessions: [GlassOpenSession] = []

        init(kind: HostServiceKind, displayName: String) {
            self.kind = kind
            self.displayName = displayName
        }

        func open(service: HostServiceLink, host: HostProfile,
                  report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) {
            report(.dismissed)
        }

        func openSessions() -> [GlassOpenSession] { sessions }
    }

    private func session(_ id: String, title: String = "a machine",
                         activated: @escaping @MainActor @Sendable () -> Void = {},
                         closed: @escaping @MainActor @Sendable () -> Void = {}) -> GlassOpenSession {
        GlassOpenSession(id: id, title: title, symbolName: "circle",
                         activate: activated, close: closed)
    }

    @Test func aCapabilityThatSaysNothingContributesNothing() {
        // The default matters more than it looks: three of four capabilities took it at first,
        // and a protocol requirement would have forced each to write `[]` by hand.
        let registry = GlassCapabilityRegistry()
        registry.register(StubCapability(kind: .rdp, displayName: "Desktop"))
        #expect(registry.openSessions().isEmpty)
    }

    @Test func everyContributorIsAsked() {
        let registry = GlassCapabilityRegistry()
        let terminal = StubCapability(kind: .ssh, displayName: "Terminal")
        terminal.sessions = [session("terminal:1"), session("terminal:2")]
        let database = StubCapability(kind: .database, displayName: "Database")
        database.sessions = [session("database:1")]
        registry.register(terminal)
        registry.register(database)
        // The editor is not a capability and contributes through the standalone hook.
        registry.registerSessionProvider(id: "editor") { [self] in [session("editor:1")] }

        #expect(registry.openSessions().map(\.id) == ["terminal:1", "terminal:2", "database:1", "editor:1"])
    }

    @Test func capabilitiesComeInKindOrderAndStandalonesLast() {
        // Stable across launches, so the list does not reshuffle between two glances at it.
        let registry = GlassCapabilityRegistry()
        let database = StubCapability(kind: .database, displayName: "Database")
        database.sessions = [session("database:1")]
        let terminal = StubCapability(kind: .ssh, displayName: "Terminal")
        terminal.sessions = [session("terminal:1")]
        // Registered database-first; the order must come from the kind, not from registration.
        registry.register(database)
        registry.register(terminal)
        registry.registerSessionProvider(id: "editor") { [self] in [session("editor:1")] }

        let ids = registry.openSessions().map(\.id)
        #expect(ids.last == "editor:1", "a standalone provider comes after the capabilities")
        #expect(ids.contains("terminal:1") && ids.contains("database:1"))
        #expect(ids.count == 3)
    }

    @Test func aProviderIsAskedAgainEveryTime() {
        // The whole reason this is a closure. A stored list is the stale sidebar count of
        // 2026-09-18 in a new costume.
        final class Count { var value = 2 }
        let open = Count()
        let registry = GlassCapabilityRegistry()
        registry.registerSessionProvider(id: "editor") { [self] in
            (0..<open.value).map { session("editor:\($0)") }
        }
        #expect(registry.openSessions().count == 2)
        open.value = 0
        #expect(registry.openSessions().isEmpty)
    }

    @Test func registeringTheSameProviderTwiceReplacesIt() {
        let registry = GlassCapabilityRegistry()
        registry.registerSessionProvider(id: "editor") { [self] in [session("editor:old")] }
        registry.registerSessionProvider(id: "editor") { [self] in [session("editor:new")] }
        #expect(registry.openSessions().map(\.id) == ["editor:new"])
    }

    @Test func theSessionYouAreLookingAtIsNotOffered() {
        // A row that goes where you already are is a tap that does nothing, which is the exact
        // failure this feature exists to remove.
        let registry = GlassCapabilityRegistry()
        let terminal = StubCapability(kind: .ssh, displayName: "Terminal")
        terminal.sessions = [session("terminal:1"), session("terminal:2")]
        registry.register(terminal)

        #expect(registry.openSessions(excluding: "terminal:1").map(\.id) == ["terminal:2"])
        #expect(registry.openSessions(excluding: nil).count == 2)
        #expect(registry.openSessions(excluding: "terminal:nothing").count == 2,
                "an id from no session excludes nothing rather than emptying the list")
    }

    @Test func activateAndCloseReachTheContributor() throws {
        var activated = false
        var closed = false
        let registry = GlassCapabilityRegistry()
        let terminal = StubCapability(kind: .ssh, displayName: "Terminal")
        terminal.sessions = [session("terminal:1",
                                     activated: { activated = true },
                                     closed: { closed = true })]
        registry.register(terminal)

        let row = try #require(registry.openSessions().first)
        row.activate()
        row.close()
        #expect(activated)
        #expect(closed)
    }

    /// Ending a session that would lose something asks first (2026-10-17): Active, All Windows and
    /// the Mac's overview threw an editor's unsaved changes away without a word.
    @Test func endingASessionThatWouldLoseSomethingAsksFirst() {
        var closed = 0
        var unsaved: String? = "notes.txt has changes that haven't been saved."
        let session = GlassOpenSession(id: "editor:1", title: "notes.txt", symbolName: "doc.text",
                                       activate: {}, close: { closed += 1 },
                                       unsavedChanges: { unsaved })
        var asked: GlassOpenSession?
        session.requestClose { asked = $0 }
        #expect(asked?.id == "editor:1", "it was ended without asking")
        #expect(closed == 0)

        unsaved = nil
        asked = nil
        session.requestClose { asked = $0 }
        #expect(asked == nil, "asked though nothing would be lost")
        #expect(closed == 1)
    }
}
