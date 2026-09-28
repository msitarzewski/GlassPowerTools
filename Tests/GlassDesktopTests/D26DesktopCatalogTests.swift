//
//  D26DesktopCatalogTests.swift
//  Glass Power Tools — GlassDesktopTests
//
//  D26 for the desktop: `connections.json` is gone and each saved desktop lives on its service
//  link. These drive `DesktopAppModel` through a real store and check the catalog, not the model's
//  own array — the array would look right even if nothing were written anywhere.
//

import Foundation
import Testing
import GlassConnectionKit
import GlassShell
@testable import GlassDesktop

@MainActor
@Suite("The desktop's records live in the catalog (D26)")
struct D26DesktopCatalogTests {

    private func makeModel() async -> (DesktopAppModel, GlassInMemoryServiceStore) {
        let store = GlassInMemoryServiceStore(defaultKind: .rdp)
        let model = DesktopAppModel(storageDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("D26Desktop-\(UUID().uuidString)"),
                                    credentialAccess: .inMemory())
        await model.attach(store: store)
        return (model, store)
    }

    private func connection(_ name: String) -> DesktopConnection {
        DesktopConnection(name: name, host: "\(name).example", username: "casey")
    }

    @Test func aSavedDesktopIsWrittenOntoItsServiceLink() async throws {
        let (model, store) = await makeModel()
        let value = connection("foxtrot")

        try await model.save(value, password: nil)

        let stored = try #require(store.configuration(DesktopConnection.self, for: value.id))
        #expect(stored.host == "foxtrot.example")
        #expect(stored.username == "casey")
    }

    @Test func aFreshModelReadsThemBackOutOfTheCatalog() async throws {
        let (model, store) = await makeModel()
        for name in ["alpha", "beta"] { try await model.save(connection(name), password: nil) }

        // A second model over the same catalog, as a second launch of the app would be.
        let relaunched = DesktopAppModel(storageDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("D26Desktop-\(UUID().uuidString)"),
                                         credentialAccess: .inMemory())
        await relaunched.attach(store: store)

        #expect(relaunched.connections.map(\.name).sorted() == ["alpha", "beta"])
    }

    @Test func deletingRemovesTheConfigurationFromTheLink() async throws {
        let (model, store) = await makeModel()
        let value = connection("foxtrot")
        try await model.save(value, password: nil)
        #expect(store.configuration(for: value.id) != nil)

        await model.delete(value)

        #expect(store.configuration(for: value.id) == nil,
                "the configuration outlived the desktop it described")
        #expect(model.connections.isEmpty)
    }

    /// The model is deliberately inert without a library rather than silently empty: "no desktops"
    /// and "no catalog to read" are different answers and only one of them is safe to act on.
    @Test func aModelWithNoLibrarySaysSoRatherThanLookingEmpty() async throws {
        let model = DesktopAppModel(storageDirectory: FileManager.default.temporaryDirectory
            .appendingPathComponent("D26Desktop-\(UUID().uuidString)"),
                                    credentialAccess: .inMemory())

        await #expect(throws: DesktopError.libraryUnavailable) {
            try await model.save(connection("foxtrot"), password: nil)
        }
    }
}
