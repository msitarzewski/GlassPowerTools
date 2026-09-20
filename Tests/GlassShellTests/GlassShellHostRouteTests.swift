import Testing
import Foundation
import GlassConnectionKit
import GlassLayers
@testable import GlassShell

@Suite("Handing the user back to a machine")
@MainActor
struct GlassShellHostRouteTests {
    private func makeShell() throws -> GlassShellModel {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HostRoute-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                               sharedContainerURL: nil, resolveSharedContainer: false,
                               accessGroup: "TEST.sh.glas.shared", layers: GlassLayerStore())
    }

    @Test func aCapabilityCanAskForAMachineAndAskAgain() throws {
        // Leaving a database on a phone returned to the top of the connection list. The user came
        // from a *machine*, and its other services are usually why they are going back.
        let model = try makeShell()
        #expect(model.hostToShow == nil, "nothing is requested until something asks")

        let host = HostID()
        model.showHost(host)
        #expect(model.hostToShow == host)

        // What the library does once it has selected it: puts the request back to nothing, so
        // asking for the *same* machine again is a change the view can see — the lesson the
        // contributed panels taught on the same day.
        model.hostToShow = nil
        model.showHost(host)
        #expect(model.hostToShow == host, "the same machine can be asked for twice")
    }
}
