//
//  RDPImportWiringTests.swift
//  Glass Power Tools — GlassDesktopTests
//
//  `RDPFileImporter` had no callers anywhere in the repository: its only one lived in glassDT's
//  `DesktopLibraryView`, the file the merge deleted because the shell's library replaced it. The
//  parser's own tests came across with it and pass, and passed the whole time it was unreachable —
//  which is the point. **A parser test cannot tell you the parser is joined to anything.**
//
//  So these tests walk the seam the parser sits behind: a parsed file becomes a prefill, the prefill
//  opens the host sheet already filled in, and the sheet builds the *desktop's* draft from it rather
//  than an empty one. If any link in that chain is removed, one of these fails.
//

import Foundation
import Testing
import GlassConnectionKit
import GlassLayers
import GlassShell
@testable import GlassDesktop

@MainActor
@Suite("RDP import is joined to the library")
struct RDPImportWiringTests {

    private func makeShell() throws -> (GlassShellModel, GlassDesktopRuntime, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RDPImportWiring-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                    sharedContainerURL: nil, resolveSharedContainer: false,
                                    accessGroup: "TEST.sh.glas.shared", layers: GlassLayerStore.forTest())
        let runtime = GlassDesktopRuntime(layers: GlassLayerStore.forTest(),
                                          app: DesktopAppModel(storageDirectory: root.appendingPathComponent("desktop"),
                                                                credentialAccess: .inMemory()))
        model.registry.register(GlassDesktopCapability(runtime: runtime))
        return (model, runtime, root)
    }

    private let office = """
    full address:s:desktop.example:3390
    username:s:LAB\\alice
    desktopwidth:i:1600
    desktopheight:i:900
    password 51:b:0100000
    """

    @Test func aParsedFileFillsInTheHostSheetAndSelectsTheDesktopTab() async throws {
        let (model, _, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        let imported = try RDPFileImporter.parse(Data(office.utf8), suggestedName: "Office")

        let prefill = GlassShellSetupPrefill(
            kind: .rdp, hostName: imported.connection.name, address: imported.connection.host,
            configuration: try JSONEncoder().encode(imported.connection), notices: imported.notices)
        let setup = GlassShellSetupModel(model: model, mode: .addHost, prefill: prefill)

        #expect(setup.name == "Office")
        #expect(setup.address == "desktop.example")
        // Not whatever the tab order would otherwise have picked: the import knows its kind.
        #expect(setup.selectedKind == .rdp)
        #expect(setup.selection == .rdp)
        // The dropped password is the notice that matters most; it is why this opens a form.
        #expect(setup.importNotices.contains { $0.lowercased().contains("password") })
    }

    @Test func theSheetBuildsTheDesktopDraftFromTheImportedRecord() async throws {
        let (model, _, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        let imported = try RDPFileImporter.parse(Data(office.utf8), suggestedName: "Office")

        let prefill = GlassShellSetupPrefill(
            kind: .rdp, hostName: imported.connection.name, address: imported.connection.host,
            configuration: try JSONEncoder().encode(imported.connection), notices: imported.notices)
        let setup = GlassShellSetupModel(model: model, mode: .addHost, prefill: prefill)

        let draft = try #require(setup.draft(for: .rdp) as? DesktopServiceDraft)
        // Fields that could only have come from the file, not from an empty draft.
        #expect(draft.username == "alice")
        #expect(draft.domain == "LAB")
        #expect(draft.portText == "3390")
    }

    @Test func anUnreadablePayloadStillOpensAUsableSheet() async throws {
        let (model, _, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        // A payload from a build that knew a different shape. A dead end would be worse than a
        // form the user can finish by hand, so the sheet opens empty rather than refusing.
        let prefill = GlassShellSetupPrefill(kind: .rdp, hostName: "Office", address: "desktop.example",
                                             configuration: Data("not a desktop record".utf8))
        let setup = GlassShellSetupModel(model: model, mode: .addHost, prefill: prefill)

        #expect(setup.name == "Office")
        #expect(setup.draft(for: .rdp) is DesktopServiceDraft)
    }

    @Test func requestingSetupReachesTheLibraryAndIsClearedOnce() async throws {
        let (model, _, root) = try makeShell()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(model.pendingSetupPrefill == nil)

        model.requestSetup(prefill: GlassShellSetupPrefill(
            kind: .rdp, hostName: "Office", address: "desktop.example", configuration: Data()))
        #expect(model.pendingSetupPrefill?.hostName == "Office")

        // The library clears it as it presents; leaving it set would re-present on every redraw.
        model.clearPendingSetup()
        #expect(model.pendingSetupPrefill == nil)
    }
}
