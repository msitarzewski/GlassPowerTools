import Foundation
import Testing
@testable import GlassTerminal

/// The Workgroup edited in its panel (the owner, 2026-11-19: "remove the edit modal and put that directly into the panel
/// itself"; asked, he chose saving as you go, on every device, and new ones straight into the panel).
@MainActor
struct WorkgroupPanelEditorTests {
    private let alpha = ServerConfiguration(name: "alpha", host: "alpha.example.com", username: "ann")

    private func preset(_ name: String, intents: [LayoutPreset.SessionIntent]? = nil) -> LayoutPreset {
        LayoutPreset(id: UUID(), name: name, colorTag: .blue,
                     sessionIntents: intents ?? [WorkgroupTabDraft(kind: .local).intent],
                     createdAt: Date(timeIntervalSince1970: 1_790_000_000), lastUsed: nil)
    }

    @Test("an edit is saved only when the Workgroup is whole: a name, something to open, every tab complete")
    func whatKeepsAnEditFromSaving() {
        let local = [WorkgroupTabDraft(kind: .local)]
        #expect(WorkgroupEditorView.validationMessage(name: "Backend", tabs: local, services: [], servers: []) == nil)
        #expect(WorkgroupEditorView.validationMessage(name: "", tabs: local, services: [], servers: [])?
                    .hasPrefix("Enter a name") == true, "the last name stays saved until there is one")
        #expect(WorkgroupEditorView.validationMessage(name: "Backend", tabs: [], services: [], servers: [])?
                    .hasPrefix("Add a terminal tab") == true)
        #expect(WorkgroupEditorView.validationMessage(name: "Backend", tabs: [], services: [UUID()], servers: []) == nil,
                "a database or desktop alone is a Workgroup")
        let unconnected = [WorkgroupTabDraft(kind: .ssh, serverID: nil)]
        #expect(WorkgroupEditorView.validationMessage(name: "Backend", tabs: unconnected, services: [], servers: [alpha])?
                    .hasPrefix("Tab 1:") == true)
        let connected = [WorkgroupTabDraft(kind: .ssh, serverID: alpha.id)]
        #expect(WorkgroupEditorView.validationMessage(name: "Backend", tabs: connected, services: [], servers: [alpha]) == nil)
    }

    @Test("a new Workgroup's name is one no other has; names are compared as people read them")
    func newNames() {
        #expect(WorkgroupEditorView.unusedName(in: []) == "New Workgroup")
        let saved = [preset("New Workgroup"), preset("new workgroup 2")]
        #expect(WorkgroupEditorView.unusedName(in: saved) == "New Workgroup 3")
        #expect(WorkgroupEditorView.unusedName("Backend", in: saved) == "Backend")
        #expect(WorkgroupEditorView.workgroup(named: "NEW WORKGROUP", in: saved)?.id == saved[0].id)
    }

    @Test("what was saved, read back with its save time, is the same Workgroup: the panel isn't redrawn from it")
    func savedAndReadBack() {
        let saved = preset("Backend")
        var readBack = saved
        readBack.modifiedAt = Date()
        #expect(WorkgroupEditorView.sameContent(saved, readBack))
        var renamed = readBack
        renamed.name = "Frontend"
        #expect(!WorkgroupEditorView.sameContent(saved, renamed), "changed on another device: shown as it is there")
    }

    @Test("+, Duplicate and a window saved as a Workgroup are saved at once; replacing one keeps it, and how it opens")
    func madeAtOnce() {
        var original = preset("Backend", intents: [LayoutPreset.SessionIntent(serverID: alpha.id, tmuxSession: "glass-4")])
        original.openingView = .grid
        original.services = [UUID()]

        let copy = WorkgroupEditorContext.duplicate(original).savedPreset()
        #expect(copy.id != original.id && copy.name == "Backend Copy")
        #expect(copy.sessionIntents.map(\.tmuxSession) == [nil], "a copy opens terminals of its own")
        #expect(copy.services == original.services && copy.openingView == .grid)

        let fresh = WorkgroupEditorContext.new(name: "  New Workgroup  ", sessionIntents: [WorkgroupTabDraft(kind: .local).intent])
            .savedPreset()
        #expect(fresh.name == "New Workgroup" && fresh.sessionIntents.count == 1)

        let window = WorkgroupEditorContext(original: nil, name: "Backend", colorTag: .green,
                                            sessionIntents: [LayoutPreset.SessionIntent(serverID: alpha.id)])
        let replaced = window.savedPreset(replacing: original)
        #expect(replaced.id == original.id && replaced.createdAt == original.createdAt, "every device updates that one")
        #expect(replaced.openingView == .grid, "how it opens is kept")
        #expect(replaced.services == original.services, "a window brings terminals; its databases and desktops stay")
        #expect(replaced.colorTag == .green && replaced.sessionIntents.count == 1)
    }
}
