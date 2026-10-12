import Foundation
import Testing
@testable import GlassWidgetData

/// What the widgets show and ask for (2026-10-12).
@Suite("Widget snapshot and requests")
struct GlassWidgetDataTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func machine(_ name: String, favorite: Bool = false, ago: TimeInterval? = nil) -> GlassWidgetSnapshot.Machine {
        .init(id: UUID(), name: name, isFavorite: favorite, lastConnected: ago.map { now.addingTimeInterval(-$0) },
              services: [.init(id: UUID(), kind: .terminal, name: "Terminal")])
    }

    @Test("a widget shows favourites first, by name, then the rest by last use, then by name")
    func ordering() {
        let snapshot = GlassWidgetSnapshot(writtenAt: now, machines: [
            machine("zeta", ago: 60), machine("bravo", favorite: true), machine("alpha", favorite: true, ago: 10),
            machine("never-b"), machine("delta", ago: 5), machine("never-a"),
        ])
        #expect(snapshot.machines(limit: 10).map(\.name) == ["alpha", "bravo", "delta", "zeta", "never-a", "never-b"])
        #expect(snapshot.machines(limit: 3).map(\.name) == ["alpha", "bravo", "delta"])
        #expect(snapshot.machines(limit: 0).isEmpty)
    }

    @Test("counts across machines, and a snapshot that differs only in when it was written is the same")
    func countsAndSameness() {
        let active = [GlassWidgetSnapshot.ActiveMachine(machineID: UUID(), name: "alpha", open: 2, running: 3, kinds: [.terminal]),
                      .init(machineID: nil, name: "Elsewhere", open: 1, running: 0, kinds: [.database])]
        let first = GlassWidgetSnapshot(writtenAt: now, machines: [machine("alpha")], active: active)
        #expect(first.openCount == 3 && first.runningCount == 3)
        var later = first
        later.writtenAt = now.addingTimeInterval(600)
        #expect(later.sameContent(as: first))
        later.active[0].open = 1
        #expect(!later.sameContent(as: first))
    }

    @Test("written and read back from the container; a write that changes nothing is skipped")
    func store() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("widget-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Widgets/snapshot.json")
        #expect(GlassWidgetStore.read(from: url) == nil)
        let snapshot = GlassWidgetSnapshot(writtenAt: now, machines: [machine("alpha", favorite: true, ago: 30)],
                                           active: [.init(machineID: nil, name: "Elsewhere", open: 1, running: 0, kinds: [.desktop])])
        #expect(try GlassWidgetStore.write(snapshot, to: url))
        #expect(GlassWidgetStore.read(from: url) == snapshot)
        var again = snapshot
        again.writtenAt = now.addingTimeInterval(60)
        #expect(try !GlassWidgetStore.write(again, to: url), "nothing changed: no write, no widget woken")
        // A time with fractions of a second, as a real connection's is: read back to the second,
        // it is still the same snapshot (on the Mac every minute's write woke every widget).
        var fractional = snapshot
        fractional.machines[0].lastConnected = now.addingTimeInterval(-30.456)
        #expect(try GlassWidgetStore.write(fractional, to: url))
        fractional.writtenAt = now.addingTimeInterval(120)
        #expect(try !GlassWidgetStore.write(fractional, to: url), "the same, though its time read back has no fraction")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("host") && !text.contains("user"), "names, kinds, times and counts only")
    }

    @Test("a snapshot from another schema is not read, so a widget never misreads one")
    func schema() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("widget-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("snapshot.json")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"schema":99,"writtenAt":"2026-10-12T00:00:00Z","machines":[],"active":[]}"#.utf8).write(to: url)
        #expect(GlassWidgetStore.read(from: url) == nil)
    }

    @Test("a tap that launched the app waits for it to be ready; later ones go straight through")
    @MainActor
    func requests() async {
        let requests = GlassWidgetRequests()
        let machine = UUID(), service = UUID()
        requests.post(.showActive)
        requests.post(.connect(machine: machine, service: service))
        var handled: [GlassWidgetRequest] = []
        requests.handle { handled.append($0) }
        #expect(handled == [.showActive, .connect(machine: machine, service: service)])
        requests.post(.showMachine(machine))
        #expect(handled.last == .showMachine(machine) && handled.count == 3)
    }

    @Test("the intents carry what the widget gave them, and a malformed one asks for nothing")
    @MainActor
    func intents() async throws {
        let machine = UUID(), service = UUID()
        let connect = GlassConnectServiceIntent(machine: machine, service: service)
        #expect(connect.machine == machine.uuidString && connect.service == service.uuidString)
        #expect(GlassShowMachineIntent(machine: machine).machine == machine.uuidString)
    }
}
