import SwiftUI
import GlassLayers
import Foundation
import Testing
import GlassConnectionKit
import GlassHostCatalog
import GlassConnectionUI
@testable import GlassShell

/// W13 (owner, 2026-10-09, on the Vision Pro): "Multiselect from the 'Active' would be stellar.
/// Right now a click (pinch) opens the target. I'd like to select multiple and open in a new window
/// like the tab view." Running sessions are chosen together, opened as one request, or ended after
/// one question; a plain click with nothing chosen still opens its row at once.
///
/// Nothing connects: the capability records what it was asked, and each row what was done to it.
@Suite("Active: choosing several running sessions")
@MainActor
struct GlassActiveSelectionTests {
    /// What the rows and the capability were asked to do, in order.
    @MainActor private final class Log {
        var opened: [String] = []
        var ended: [String] = []
        var together: [[GlassRunningAttachment]] = []
        var intoWindow: [(attachments: [GlassRunningAttachment], window: String)] = []
        var gathered: [(groups: [String], into: String?)] = []
    }

    private final class TerminalStub: GlassCapability {
        let kind: HostServiceKind = .ssh
        let displayName = "Terminal"
        let symbolName = "terminal"
        var running: [GlassRunningSession] = []
        let log: Log
        init(log: Log) { self.log = log }
        func open(service: HostServiceLink, host: HostProfile,
                  report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) { report(.dismissed) }
        func runningSessions() async -> [GlassRunningSession] { running }
        func openRunningSessions(_ attachments: [GlassRunningAttachment]) { log.together.append(attachments) }
        var windows: [GlassTabGroup] = []
        func tabGroups() -> [GlassTabGroup] { windows }
        func openRunningSessions(_ attachments: [GlassRunningAttachment], inTabGroup group: GlassTabGroup.ID) {
            log.intoWindow.append((attachments, group))
        }
        /// Windows open here, as Active lists them.
        var sets: [GlassOpenSession] = []
        func openSessions() -> [GlassOpenSession] { sets }
        /// What a gathering finds no room for.
        var full: [String] = []
        func gather(tabGroups: [GlassTabGroup.ID], into destination: GlassTabGroup.ID?) -> GlassGathering? {
            guard tabGroups.contains(where: { id in sets.contains { $0.tabGroupID == id } }) else { return nil }
            log.gathered.append((tabGroups, destination))
            return GlassGathering(tabGroup: destination ?? tabGroups[0], leftOut: full)
        }
    }

    /// A window open here, as the terminal lists one: gathered by its id where `gatherable` (off the Mac).
    private func set(_ name: String, on endpoint: EndpointID, gatherable: Bool = true) -> GlassOpenSession {
        GlassOpenSession(id: "terminal:\(name)", title: name, symbolName: "terminal", endpointIDs: [endpoint],
                         activate: {}, close: {}, tabGroupID: gatherable ? name : nil)
    }

    /// A row as the terminal makes one: opening, ending and its attachment are recorded.
    private func row(_ name: String, on endpoint: EndpointID, openHere: Bool = false,
                     opensTogether: Bool = true, log: Log, failsToEnd: Bool = false) -> GlassRunningSession {
        let id = "tmux:\(endpoint.rawValue.uuidString):\(name)"
        return GlassRunningSession(
            id: id, title: name, symbolName: "terminal", endpointID: endpoint,
            isAttachedElsewhere: false, isOpenHere: openHere,
            open: { log.opened.append(id) }, takeOver: {},
            end: {
                log.ended.append(id)
                if failsToEnd { throw CocoaError(.fileWriteNoPermission) }
            },
            attachment: opensTogether ? GlassRunningAttachment(kind: .ssh, endpointID: endpoint, name: name) : nil)
    }

    private struct Fixture {
        let model: GlassShellModel
        let root: URL
        let alpha: EndpointID
        let bravo: EndpointID
        let terminal: TerminalStub
        let log: Log
    }

    /// Two machines in the library, alpha and bravo, with a Terminal service each.
    private func fixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlassActiveSelection-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: root.appendingPathComponent("group"),
                                    resolveSharedContainer: false, layers: GlassLayerStore.forTest())
        let store = HostCatalogStore(fileURL: root.appendingPathComponent("group/GlassHostCatalog/hosts.json"))
        let alpha = HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "Terminal on alpha")
        let bravo = HostServiceLink(endpointID: EndpointID(), kind: .ssh, displayName: "Terminal on bravo")
        try await store.upsert(try HostProfile(displayName: "alpha", address: "192.0.2.1", services: [alpha]))
        try await store.upsert(try HostProfile(displayName: "bravo", address: "192.0.2.2", services: [bravo]))
        let log = Log()
        let terminal = TerminalStub(log: log)
        model.registry.register(terminal)
        await model.load()
        return Fixture(model: model, root: root, alpha: alpha.endpointID, bravo: bravo.endpointID, terminal: terminal, log: log)
    }

    /// The owner, 2026-11-19: "We should let the user know that we lost the tmux session … right now I'd be wondering
    /// why my sessions didn't restore."
    @Test("terminals closed because their sessions ended are said under their machine, counted together, until dismissed")
    func closedTerminalsSaid() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        f.model.noteClosed([GlassClosedTerminals(endpointID: f.alpha, count: 2, reason: "Their tmux sessions on alpha were ended.")])
        f.model.noteClosed([GlassClosedTerminals(endpointID: f.alpha, count: 1, reason: "tmux isn't running on alpha now.")])
        let alpha = try #require(f.model.activeMachines().first { $0.name == "alpha" }, "listed for its note alone")
        #expect(alpha.closed?.message == "3 terminals closed. tmux isn't running on alpha now.", "both, with the newest why")
        #expect(f.model.activeMachines().first { $0.name == "bravo" }?.closed == nil)
        f.model.dismissClosed(f.alpha)
        #expect(f.model.activeMachines().first { $0.name == "alpha" }?.closed == nil, "read: gone")
    }

    /// Open as Tab In (the owner, 2026-10-15): "show existing tab groups. So I can open a new
    /// session into a group."
    @Test("Open as Tab In: a row's capability offers its windows; choosing one sends the row there and it leaves the list")
    func openAsTabIn() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        f.terminal.windows = [GlassTabGroup(id: "backend", title: "Backend"), GlassTabGroup(id: "logs", title: "Logs")]
        f.terminal.running = [row("glass-2", on: f.alpha, log: f.log), row("logs", on: f.bravo, log: f.log)]
        await f.model.refreshRunningSessions()
        #expect(f.model.registry.tabGroups(for: .ssh).map(\.title) == ["Backend", "Logs"])
        #expect(f.model.registry.tabGroups(for: .database).isEmpty, "a kind with no capability offers none")

        let chosen = try #require(f.model.runningSessions.first { $0.title == "glass-2" })
        f.model.open(chosen, inTabGroup: f.terminal.windows[0])
        #expect(f.log.intoWindow.map(\.window) == ["backend"])
        #expect(f.log.intoWindow.first?.attachments == [GlassRunningAttachment(kind: .ssh, endpointID: f.alpha, name: "glass-2")])
        #expect(f.model.runningSessions.map(\.title) == ["logs"], "it leaves the list at once, as one opened alone does")
        #expect(f.log.opened.isEmpty && f.log.together.isEmpty, "not a window of its own")
    }

    /// The owner, 2026-10-15: "add Open as Tab In for multiple selected sessions too."
    @Test("Open N as Tabs In: the chosen join one window in Active's order, one request; one open here stays; the choice clears")
    func openSeveralAsTabsIn() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        f.terminal.windows = [GlassTabGroup(id: "backend", title: "Backend")]
        f.terminal.running = [row("glass-1", on: f.alpha, log: f.log), row("logs", on: f.bravo, log: f.log),
                              row("glass-2", on: f.alpha, openHere: true, log: f.log)]
        await f.model.refreshRunningSessions()
        let machines = f.model.activeMachines()
        let selection = GlassActiveSelection()
        _ = selection.listSelected(Set(machines.flatMap(\.running).map(\.id)), plainClick: false, in: machines)
        let plan = GlassOpenTogetherPlan(selection.chosen(in: machines))
        #expect(f.model.tabGroups(for: plan).map(\.title) == ["Backend"])
        #expect(GlassActiveSelection.openInTitle(count: plan.opening.count) == "Open 2 as Tabs In")

        let opened = selection.openChosen(in: f.model, inTabGroup: f.terminal.windows[0])
        #expect(opened.opening.map(\.title) == ["glass-1", "logs"])
        #expect(f.log.intoWindow.count == 1, "one request for all of them")
        #expect(f.log.intoWindow.first?.window == "backend")
        #expect(f.log.intoWindow.first?.attachments == [GlassRunningAttachment(kind: .ssh, endpointID: f.alpha, name: "glass-1"),
                                                        GlassRunningAttachment(kind: .ssh, endpointID: f.bravo, name: "logs")])
        #expect(f.model.runningSessions.map(\.title) == ["glass-2"], "the one open here stays where it is")
        #expect(selection.chosen(in: f.model.activeMachines()).isEmpty, "the choice ends")
        #expect(f.log.opened.isEmpty && f.log.together.isEmpty)
    }

    @Test("three sessions on two machines open as one request, in Active's order; the choice clears")
    func openThreeTogether() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        f.terminal.running = [row("glass-1", on: f.alpha, log: f.log), row("logs", on: f.bravo, log: f.log),
                              row("glass-2", on: f.alpha, log: f.log), row("glass-3", on: f.alpha, log: f.log)]
        await f.model.refreshRunningSessions()
        let machines = f.model.activeMachines()
        let listed = machines.flatMap(\.running)
        #expect(listed.map(\.title) == ["glass-1", "glass-2", "glass-3", "logs"], "alpha's, then bravo's")
        try #require(listed.count == 4)

        // ⌘-click glass-3, then logs, then glass-1: chosen in a different order from the list's.
        let selection = GlassActiveSelection()
        let ids = [listed[2].id, listed[3].id, listed[0].id]
        for count in 1...3 {
            #expect(selection.listSelected(Set(ids.prefix(count)), plainClick: false, in: machines) == nil,
                    "with ⌘ held a click chooses; nothing opens")
        }
        #expect(selection.chosen(in: machines).map(\.title) == ["glass-1", "glass-3", "logs"], "in the list's order")

        let plan = selection.openChosen(in: f.model)
        #expect(plan.opening.map(\.title) == ["glass-1", "glass-3", "logs"])
        #expect(f.log.together == [[GlassRunningAttachment(kind: .ssh, endpointID: f.alpha, name: "glass-1"),
                                    GlassRunningAttachment(kind: .ssh, endpointID: f.alpha, name: "glass-3"),
                                    GlassRunningAttachment(kind: .ssh, endpointID: f.bravo, name: "logs")]],
                "one request for all three, each on its own machine, in order")
        #expect(f.log.opened.isEmpty, "never each row's own Open, which makes a window apiece")
        #expect(f.model.runningSessions.map(\.title) == ["glass-2"], "those opened leave the list at once")
        #expect(selection.ids.isEmpty && !selection.isSelecting, "the choice clears after the action")
        #expect(selection.notice == nil, "nothing was left out")
    }

    @Test("a session open here already stays where it is: left out of the new window, and of the count")
    func openHereIsLeftOut() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        f.terminal.running = [row("glass-1", on: f.alpha, openHere: true, log: f.log),
                              row("glass-2", on: f.alpha, log: f.log), row("logs", on: f.bravo, log: f.log)]
        await f.model.refreshRunningSessions()
        let machines = f.model.activeMachines()
        let selection = GlassActiveSelection()
        selection.isSelecting = true
        _ = selection.listSelected(Set(machines.flatMap(\.running).map(\.id)), plainClick: false, in: machines)

        let plan = GlassOpenTogetherPlan(selection.chosen(in: machines))
        #expect(plan.opening.map(\.title) == ["glass-2", "logs"] && plan.alreadyOpen.map(\.title) == ["glass-1"])
        #expect(GlassActiveSelection.openTitle(count: plan.opening.count) == "Open 2 in New Window", "the count is what opens")

        selection.openChosen(in: f.model)
        #expect(f.log.together.map { $0.map(\.name) } == [["glass-2", "logs"]])
        #expect(f.log.opened.isEmpty, "the window showing it is not brought forward over the new one")
        #expect(f.model.runningSessions.map(\.title) == ["glass-1"], "and it stays listed, open here")
    }

    @Test("a plain click with nothing chosen opens its row at once; ⌘, ⇧ and selection mode choose")
    func plainClickStillOpens() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        f.terminal.running = [row("glass-1", on: f.alpha, log: f.log), row("glass-2", on: f.alpha, log: f.log)]
        await f.model.refreshRunningSessions()
        let machines = f.model.activeMachines()
        try #require(machines.flatMap(\.running).count == 2)
        let first = machines.flatMap(\.running)[0], second = machines.flatMap(\.running)[1]
        let selection = GlassActiveSelection()

        let clicked = try #require(selection.listSelected([first.id], plainClick: true, in: machines))
        #expect(clicked.id == first.id && selection.ids.isEmpty, "nothing is left chosen")
        f.model.open(clicked)
        #expect(f.log.opened == [first.id] && f.log.together.isEmpty, "opened as a tap always has")

        // ⌘-click chooses; a plain click on another row then opens that one, and the choice goes.
        #expect(selection.listSelected([first.id], plainClick: false, in: machines) == nil)
        #expect(selection.ids == [first.id])
        #expect(selection.listSelected([second.id], plainClick: true, in: machines)?.id == second.id)
        #expect(selection.ids.isEmpty)

        // In selection mode every tap chooses, and leaving it chooses nothing.
        selection.isSelecting = true
        #expect(selection.listSelected([first.id], plainClick: true, in: machines) == nil)
        #expect(selection.ids == [first.id])
        selection.isSelecting = false
        #expect(selection.ids.isEmpty)

        // Only running rows are chosen: a machine's disclosure or an open session is not one.
        #expect(selection.listSelected([first.id, "machine-id", "terminal:open"], plainClick: false, in: machines) == nil)
        #expect(selection.ids == [first.id])
    }

    @Test("End N asks once, plainly, then ends each; what could not end is said afterwards")
    func endAsksOnceThenEndsEach() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        f.terminal.running = [row("glass-1", on: f.alpha, log: f.log), row("glass-2", on: f.alpha, log: f.log),
                              row("logs", on: f.bravo, log: f.log, failsToEnd: true), row("keep", on: f.bravo, log: f.log)]
        await f.model.refreshRunningSessions()
        let machines = f.model.activeMachines()
        let listed = machines.flatMap(\.running)
        try #require(listed.count == 4)
        let selection = GlassActiveSelection()
        selection.askToEnd()
        #expect(!selection.isConfirmingEnd, "nothing chosen: nothing to ask")

        selection.isSelecting = true
        _ = selection.listSelected(Set(listed.prefix(3).map(\.id)), plainClick: false, in: machines)
        selection.askToEnd()
        #expect(selection.isConfirmingEnd, "one question for all three")
        #expect(f.log.ended.isEmpty, "and nothing ends before it is answered")
        let question = GlassActiveSelection.endQuestion(for: selection.chosen(in: machines))
        #expect(question.title == "End 3 sessions?")
        #expect(question.message == "What runs in them stops, on every device.")
        #expect(question.button == "End 3 Sessions")

        await selection.endChosen(in: f.model)
        #expect(f.log.ended == listed.prefix(3).map(\.id), "each ended once, in order")
        #expect(f.log.opened.isEmpty && f.log.together.isEmpty)
        #expect(selection.ids.isEmpty && !selection.isSelecting && !selection.isConfirmingEnd, "the choice clears")
        #expect(selection.notice?.title == "Couldn't End a Session")
        #expect(selection.notice?.message.hasPrefix("logs: ") == true, "named, with why")

        // One session is asked about by name, as its own row asks.
        let one = GlassActiveSelection.endQuestion(for: [listed[3]])
        #expect(one.title == "End keep?" && one.message == "Everything running in it stops, on every device.")
    }

    @Test("only terminal sessions open together for now: another's row is left out, and said so")
    func otherCapabilitiesAreLeftOut() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        f.terminal.running = [row("glass-1", on: f.alpha, log: f.log),
                              row("report", on: f.bravo, opensTogether: false, log: f.log)]
        await f.model.refreshRunningSessions()
        let machines = f.model.activeMachines()
        let selection = GlassActiveSelection()
        _ = selection.listSelected(Set(machines.flatMap(\.running).map(\.id)), plainClick: false, in: machines)

        let plan = selection.openChosen(in: f.model)
        #expect(plan.oneAtATime.map(\.title) == ["report"])
        #expect(f.log.together.map { $0.map(\.name) } == [["glass-1"]], "the terminal's own open together")
        #expect(f.log.opened.isEmpty)
        #expect(selection.notice == GlassActiveNotice(title: "Only Terminal Sessions Open Together",
                                                      message: "report didn't open. Open it on its own."))
        #expect(f.model.runningSessions.map(\.title) == ["report"], "and it stays listed")
    }

    /// The owner, 2026-11-15, on the iPhone: "the active list has a select, but it doesnt work, so i cant select
    /// multiple to add to a set." Every row was a set open on the phone, and only running sessions could be chosen.
    @Test("sets open here are chosen too: Open N Together gathers them into the first and opens running sessions there; one that can't gather can't be chosen")
    func gathersSetsOpenHere() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        f.terminal.windows = [GlassTabGroup(id: "one", title: "one"), GlassTabGroup(id: "two", title: "two")]
        f.terminal.sets = [set("one", on: f.alpha), set("mac", on: f.alpha, gatherable: false), set("two", on: f.bravo)]
        f.terminal.running = [row("glass-9", on: f.alpha, log: f.log)]
        await f.model.refreshRunningSessions()
        let machines = f.model.activeMachines()
        #expect(GlassActiveSelection.gatherable(in: machines).map(\.title) == ["one", "two"])

        let selection = GlassActiveSelection()
        selection.isSelecting = true
        let everything = machines.flatMap(\.sessions).map(\.id) + machines.flatMap(\.running).map(\.id)
        _ = selection.listSelected(Set(everything), plainClick: false, in: machines)
        let sets = selection.chosenSets(in: machines)
        #expect(sets.map(\.title) == ["one", "two"], "in Active's order; the one that can't gather isn't chosen")
        let plan = GlassOpenTogetherPlan(selection.chosen(in: machines))
        #expect(GlassActiveSelection.canOpen(plan, sets: sets))
        #expect(GlassActiveSelection.openTitle(count: plan.opening.count + sets.count, gathering: true) == "Open 3 Together")

        selection.openChosen(in: f.model)
        #expect(f.log.gathered.map(\.groups) == [["one", "two"]] && f.log.gathered.first?.into == nil,
                "one request, into the first")
        #expect(f.log.intoWindow.map(\.window) == ["one"], "the running session opens in the set gathered into")
        #expect(f.log.intoWindow.first?.attachments == [GlassRunningAttachment(kind: .ssh, endpointID: f.alpha, name: "glass-9")])
        #expect(f.log.together.isEmpty, "not a window of their own")
        #expect(selection.chosen(in: f.model.activeMachines()).isEmpty && !selection.isSelecting, "the choice ends")
    }

    @Test("one set into another: Open as Tabs In offers the sets, gathers into the one chosen, and says what didn't fit")
    func oneSetIntoAnother() async throws {
        let f = try await fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        f.terminal.windows = [GlassTabGroup(id: "one", title: "one"), GlassTabGroup(id: "two", title: "two")]
        f.terminal.sets = [set("one", on: f.alpha), set("two", on: f.bravo)]
        f.terminal.full = ["build"]
        let machines = f.model.activeMachines()
        let selection = GlassActiveSelection()
        selection.isSelecting = true
        _ = selection.listSelected(["terminal:two"], plainClick: false, in: machines)
        let sets = selection.chosenSets(in: machines)
        let plan = GlassOpenTogetherPlan(selection.chosen(in: machines))
        #expect(!GlassActiveSelection.canOpen(plan, sets: sets), "one set alone has nothing to open together")
        #expect(GlassActiveSelection.canOpenIn(plan, sets: sets))
        #expect(f.model.tabGroups(for: plan, sets: sets).map(\.title) == ["one", "two"], "the sets it can go into")
        #expect(GlassActiveSelection.openInTitle(count: sets.count) == "Open as Tab In")

        selection.openChosen(in: f.model, inTabGroup: f.terminal.windows[0])
        #expect(f.log.gathered.map(\.groups) == [["two"]] && f.log.gathered.first?.into == "one")
        #expect(f.log.intoWindow.isEmpty, "no running session to open")
        #expect(selection.notice == GlassActiveNotice(title: "A Terminal Didn't Fit",
                                                      message: "build stayed where it was: the window is full."))
    }

    @Test("the registry asks each capability once, with only its own sessions, in order")
    func registryRoutesByKind() {
        final class Recorder: GlassCapability {
            let kind: HostServiceKind
            let displayName = "Stub"
            let symbolName = "circle"
            var asked: [[String]] = []
            init(kind: HostServiceKind) { self.kind = kind }
            func open(service: HostServiceLink, host: HostProfile,
                      report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) { report(.dismissed) }
            func openRunningSessions(_ attachments: [GlassRunningAttachment]) { asked.append(attachments.map(\.name)) }
        }
        let registry = GlassCapabilityRegistry()
        let terminal = Recorder(kind: .ssh), database = Recorder(kind: .database)
        registry.register(terminal); registry.register(database)
        let endpoint = EndpointID()
        registry.openRunningSessions([GlassRunningAttachment(kind: .ssh, endpointID: endpoint, name: "a"),
                                      GlassRunningAttachment(kind: .database, endpointID: endpoint, name: "x"),
                                      GlassRunningAttachment(kind: .ssh, endpointID: endpoint, name: "b")])
        #expect(terminal.asked == [["a", "b"]] && database.asked == [["x"]])
    }
}
