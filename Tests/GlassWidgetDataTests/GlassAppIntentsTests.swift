import AppIntents
import Foundation
import Testing
@testable import GlassWidgetData

/// The library as Siri, Shortcuts and Spotlight see it, and what each intent asks the app for
/// (D72, 2026-10-13). Serialized: the entity source and the request queue are the process's own.
@Suite("Entities and intents", .serialized)
@MainActor
struct GlassAppIntentsTests {
    private let alpha = UUID(), bravo = UUID(), alphaTerminal = UUID(), alphaOrders = UUID(), bravoDesktop = UUID()
    private let deploy = UUID()

    private var library: GlassWidgetSnapshot {
        GlassWidgetSnapshot(
            machines: [
                .init(id: alpha, name: "alpha", isFavorite: true, services: [
                    .init(id: alphaTerminal, kind: .terminal, name: "Terminal"),
                    .init(id: alphaOrders, kind: .database, name: "Orders"),
                ]),
                .init(id: bravo, name: "bravo web", services: [.init(id: bravoDesktop, kind: .desktop, name: "Desktop")]),
            ],
            workgroups: [.init(id: deploy, name: "Deploy", terminals: 3)])
    }

    /// Runs `body` with the library above, catching what the intents ask for.
    private func withLibrary(_ body: () async throws -> Void) async rethrows -> [GlassWidgetRequest] {
        let snapshot = library
        let saved = GlassEntitySource.snapshot
        GlassEntitySource.snapshot = { snapshot }
        defer { GlassEntitySource.snapshot = saved }
        var asked: [GlassWidgetRequest] = []
        GlassWidgetRequests.shared.handle { asked.append($0) }
        try await body()
        return asked
    }

    @Test("machines are found by id, by any of the words typed, and suggested favourites first")
    func machineQueries() async throws {
        _ = try await withLibrary {
            let query = GlassMachineQuery()
            let byID = try await query.entities(for: [bravo, UUID()])
            let byWords = try await query.entities(matching: "web bravo")
            let none = try await query.entities(matching: "charlie")
            let suggested = try await query.suggestedEntities()
            #expect(byID.map(\.name) == ["bravo web"])
            #expect(byWords.map(\.id) == [bravo])
            #expect(none.isEmpty)
            #expect(suggested.map(\.name) == ["alpha", "bravo web"])
        }
    }

    @Test("a service is found by its own name, its machine's or its kind")
    func serviceQueries() async throws {
        _ = try await withLibrary {
            let query = GlassServiceQuery()
            let byName = try await query.entities(matching: "orders")
            let byMachineAndKind = try await query.entities(matching: "alpha database")
            let byKind = try await query.entities(matching: "desktop")
            let suggested = try await query.suggestedEntities()
            #expect(byName.map(\.id) == [alphaOrders])
            #expect(byMachineAndKind.map(\.id) == [alphaOrders])
            #expect(byKind.map(\.machineName) == ["bravo web"])
            #expect(suggested.count == 3)
        }
    }

    @Test("workgroups come from the snapshot; one written before them reads as none")
    func workgroups() async throws {
        _ = try await withLibrary {
            let found = try await GlassWorkgroupQuery().entities(matching: "dep")
            #expect(found.map(\.id) == [deploy])
        }
        let before = #"{"schema":1,"writtenAt":"2026-10-12T10:00:00Z","machines":[],"active":[]}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(GlassWidgetSnapshot.self, from: Data(before.utf8)).workgroups.isEmpty)
    }

    @Test("Open Terminal and Open Desktop open the machine's service of that kind, or say it has none")
    func openByKind() async throws {
        let machines = try await GlassMachineQuery.entities(in: library)
        let asked = try await withLibrary {
            _ = try await GlassOpenTerminalIntent(machine: machines[alpha]!).perform()
            _ = try await GlassOpenDesktopIntent(machine: machines[bravo]!).perform()
            await #expect(throws: GlassIntentError.self) {
                _ = try await GlassOpenDesktopIntent(machine: machines[alpha]!).perform()
            }
        }
        #expect(asked == [.connect(machine: alpha, service: alphaTerminal), .connect(machine: bravo, service: bravoDesktop)])
    }

    @Test("a service, a machine, a workgroup and files each ask for what they name")
    func eachAsks() async throws {
        let machines = try await GlassMachineQuery.entities(in: library)
        let file = URL(fileURLWithPath: "/tmp/notes.md")
        let asked = try await withLibrary {
            let orders = try #require(try await GlassServiceQuery().entities(for: [alphaOrders]).first)
            _ = try await GlassOpenServiceIntent(service: orders).perform()
            _ = try await GlassOpenMachineIntent(target: machines[bravo]!).perform()
            _ = try await GlassOpenWorkgroupIntent(target: GlassWorkgroupEntity(id: deploy, name: "Deploy", terminals: 3)).perform()
            let open = GlassOpenInEditorIntent()
            open.files = [IntentFile(fileURL: file, filename: "notes.md")]
            _ = try await open.perform()
        }
        #expect(asked == [.connect(machine: alpha, service: alphaOrders), .showMachine(bravo), .openWorkgroup(deploy),
                          .openInEditor([file])])
    }

    #if os(macOS)
    @Test("New Terminal Window asks for a terminal in the folder given, or none")
    func newTerminal() async throws {
        let folder = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let asked = try await withLibrary {
            let inFolder = GlassNewTerminalIntent()
            inFolder.folder = IntentFile(fileURL: folder, filename: "tmp")
            _ = try await inFolder.perform()
            _ = try await GlassNewTerminalIntent().perform()
        }
        #expect(asked == [.newLocalTerminal(folder: folder), .newLocalTerminal(folder: nil)])
    }
    #endif
}

private extension GlassMachineQuery {
    /// The library's machines as entities, by id.
    @MainActor
    static func entities(in snapshot: GlassWidgetSnapshot) async throws -> [UUID: GlassMachineEntity] {
        Dictionary(uniqueKeysWithValues: snapshot.machines.map { ($0.id, GlassMachineEntity($0)) })
    }
}
