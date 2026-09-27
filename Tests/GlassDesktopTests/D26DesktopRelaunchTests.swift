//
//  D26DesktopRelaunchTests.swift
//  Glass Power Tools — GlassDesktopTests
//
//  What a relaunch does to a saved desktop, against a **real** `GlassShellModel` and a real catalog
//  file — the arrangement the terminal has had since 2026-09-16 (`D26RelaunchTests`) and the
//  desktop did not.
//
//  Reported 2026-09-17: a desktop's settings, saved on a machine, were gone after the app was
//  closed and reopened.
//
//  The desktop's own tests drive `DesktopAppModel` over `GlassInMemoryServiceStore`, which answers
//  `isCatalogLoaded == true` from the moment it exists. That is precisely the condition the defect
//  needs to be *absent*, so those tests pass while the app loses records: a store nobody has read
//  yet says "no saved desktops", and the next write makes that permanent. The same class of defect,
//  the same day of the week, one capability over.
//

import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
import GlassShell
@testable import GlassDesktop

@MainActor
@Suite("Relaunching with a saved desktop (D26)")
struct D26DesktopRelaunchTests {

    /// One process, wired the way `GlassPowerToolsApp.init` wires it.
    private func launch(over root: URL) async -> (GlassShellModel, GlassDesktopRuntime) {
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: root.appendingPathComponent("group"),
                                    resolveSharedContainer: false,
                                    accessGroup: "TEST.sh.glas.shared", layers: GlassLayerStore())
        let desktop = GlassDesktopRuntime(layers: GlassLayerStore())
        await desktop.connectToLibrary(store: model)
        model.registry.register(GlassDesktopCapability(runtime: desktop))
        return (model, desktop)
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("D26DesktopRelaunch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// The report, as a test: set a desktop up on a machine, quit, come back.
    @Test func aSavedDesktopSurvivesARelaunch() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let (model, desktop) = await launch(over: root)
        await model.load()
        let endpoint = try await model.adoptService(kind: .rdp, hostName: "alpha",
                                                    address: "192.0.2.10", serviceName: "Desktop on alpha")
        try await desktop.app.save(DesktopConnection(id: endpoint, name: "Desktop on alpha",
                                                     host: "192.0.2.10", username: "michael"),
                                   password: nil)
        #expect(desktop.app.connections.count == 1)

        // Quit and come back: a second process over the same catalog directory.
        let (relaunched, secondDesktop) = await launch(over: root)
        await relaunched.load()
        // `catalogDidLoad()` hands the read to a `Task`, so the capability's answer arrives after
        // the shell's `load()` returns. Asked for directly here — `load()` is idempotent — so this
        // tests the record's survival rather than the scheduler's timing.
        await secondDesktop.app.load()

        #expect(secondDesktop.app.connections.map(\.name) == ["Desktop on alpha"],
                "the saved desktop did not survive a relaunch")
        #expect(relaunched.configuration(for: endpoint) != nil,
                "the catalog no longer holds the desktop's record")
    }

    /// **The window that made it look lost.**
    ///
    /// `catalogDidLoad()` hands the desktop's read to a `Task`, so for a moment after launch the
    /// in-memory list is empty while the catalog is not. Editing the service in that moment used to
    /// find nothing and report the link as having no saved configuration — which is exactly what a
    /// *lost* service looks like, and is why one got deleted on 2026-09-17. The catalog is the
    /// record, so the catalog is what gets asked.
    @Test func aServiceIsEditableBeforeTheDeferredReadHasRun() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let (model, desktop) = await launch(over: root)
        await model.load()
        let endpoint = try await model.adoptService(kind: .rdp, hostName: "alpha",
                                                    address: "192.0.2.10", serviceName: "Desktop on alpha")
        try await desktop.app.save(DesktopConnection(id: endpoint, name: "Desktop on alpha",
                                                     host: "192.0.2.10", username: "michael"),
                                   password: nil)

        // Second launch, and **nobody has called `load()` yet** — the state the deferred task
        // leaves behind for as long as it is pending.
        let (relaunched, secondDesktop) = await launch(over: root)
        await relaunched.load()
        #expect(secondDesktop.app.connections.isEmpty, "the fixture no longer reproduces the window")

        let host = try #require(relaunched.hosts.first { $0.displayName == "alpha" })
        let service = try #require(host.services.first { $0.endpointID == endpoint })
        let capability = try #require(relaunched.registry.capability(for: .rdp))
        let ownerRecord = try #require(host.member(owning: endpoint))

        let draft = capability.setupDraft(for: service, host: ownerRecord)
        #expect(draft != nil, "the saved desktop reads as a link with nothing behind it")
    }

    /// And the half that makes it permanent: a write on the second launch must not reconcile the
    /// catalog down to what the model happens to hold.
    @Test func aWriteAfterARelaunchDoesNotEraseWhatWasStored() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let (model, desktop) = await launch(over: root)
        await model.load()
        let first = try await model.adoptService(kind: .rdp, hostName: "alpha",
                                                 address: "192.0.2.10", serviceName: "Desktop on alpha")
        try await desktop.app.save(DesktopConnection(id: first, name: "Desktop on alpha",
                                                     host: "192.0.2.10", username: "michael"),
                                   password: nil)

        let (relaunched, secondDesktop) = await launch(over: root)
        await relaunched.load()
        let second = try await relaunched.adoptService(kind: .rdp, hostName: "bravo",
                                                       address: "10.0.0.9", serviceName: "Desktop on bravo")
        try await secondDesktop.app.save(DesktopConnection(id: second, name: "Desktop on bravo",
                                                          host: "10.0.0.9", username: "michael"),
                                         password: nil)

        #expect(secondDesktop.app.connections.map(\.name).sorted()
                == ["Desktop on alpha", "Desktop on bravo"],
                "saving a second desktop erased the first")
        #expect(relaunched.configuration(for: first) != nil,
                "the first desktop's record was reconciled away by the second write")
    }
}
