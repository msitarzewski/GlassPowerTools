import Foundation
import SwiftUI
import Testing
import GlassConnectionKit
import GlassHostCatalog
import GlassLayers
@testable import GlassShell

@MainActor private func makeModel() throws -> (GlassShellModel, URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GlassShellSetupTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let model = GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                                sharedContainerURL: root.appendingPathComponent("group"),
                                resolveSharedContainer: false, accessGroup: "TEST.sh.glas.shared",
                                layers: GlassLayerStore())
    return (model, root)
}

/// A draft that records what the shell asked of it and can be told to fail.
@MainActor
private final class FakeDraft: GlassServiceDraft {
    let kind: HostServiceKind
    var username = ""
    var commits: [(EndpointID, HostID, String)] = []
    var rollbacks: [EndpointID] = []
    var focused: [GlassSetupIssue] = []
    var failCommit = false
    init(kind: HostServiceKind) { self.kind = kind }
    func serviceDisplayName(hostName: String) -> String { "\(kind.rawValue) on \(hostName)" }
    func requiredFields() -> AnyView { AnyView(EmptyView()) }
    func advancedFields() -> AnyView { AnyView(EmptyView()) }
    func validate(address: String) -> [GlassSetupIssue] {
        username.isEmpty ? [GlassSetupIssue(field: "username", message: "Enter the user.")] : []
    }
    func focusFirstIssue(_ issues: [GlassSetupIssue]) { focused = issues }
    func commit(endpointID: EndpointID, host: HostProfile, address: String) async throws {
        if failCommit { throw GlassShellError.invalidName }
        commits.append((endpointID, host.id, address))
    }
    func rollback(endpointID: EndpointID) async { rollbacks.append(endpointID) }
}

@MainActor
private final class SetupCapability: GlassCapability {
    let kind: HostServiceKind
    var displayName: String { kind.rawValue }
    var symbolName: String { "circle" }
    var made: [FakeDraft] = []
    var removed: [EndpointID] = []
    /// Endpoints this capability "holds" configuration for (edit mode loads a draft for them).
    var stored: Set<EndpointID> = []
    var nextFails = false
    init(kind: HostServiceKind) { self.kind = kind }
    func open(service: HostServiceLink, host: HostProfile, report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) {}
    func makeSetupDraft() -> any GlassServiceDraft {
        let draft = FakeDraft(kind: kind)
        draft.username = "u"
        draft.failCommit = nextFails
        made.append(draft)
        return draft
    }
    func setupDraft(for service: HostServiceLink, host: HostProfile) -> (any GlassServiceDraft)? {
        guard stored.contains(service.endpointID) else { return nil }
        let draft = FakeDraft(kind: kind)
        draft.username = "existing"
        made.append(draft)
        return draft
    }
    func removeService(_ service: HostServiceLink, host: HostProfile) async throws { removed.append(service.endpointID) }
}

@Suite("Host setup sheet", .serialized)
@MainActor
struct GlassShellSetupTests {
    @Test("Add Host with a service enabled creates the host and the service, complete, in one save")
    func addHostWithService() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let ssh = SetupCapability(kind: .ssh)
        model.registry.register(ssh)
        let setup = GlassShellSetupModel(model: model, mode: .addHost)
        #expect(setup.isAvailable(.ssh) && !setup.isAvailable(.database), "unregistered kinds are disabled tabs")
        setup.name = "golf"
        setup.address = "192.0.2.6"
        setup.select(.database)
        #expect(setup.selection == nil, "a kind without a capability cannot be selected")
        setup.select(.ssh)
        #expect(setup.enabledKinds == [.ssh], "the chosen tab is the service being added")

        let id = try #require(await setup.save())
        let host = try #require(model.host(id))
        #expect(host.displayName == "golf" && host.address == "192.0.2.6")
        #expect(host.services.map(\.kind) == [.ssh])
        let draft = try #require(ssh.made.first)
        #expect(draft.commits.count == 1)
        #expect(draft.commits.first?.2 == "192.0.2.6", "the draft is committed with the host's address")
        #expect(draft.commits.first?.0 == host.services.first?.endpointID, "the link carries the endpoint id the capability committed under")
        #expect(host.services.first?.displayName == "ssh on golf")
    }

    @Test("Validation: host fields first, then each enabled draft; the first problem is focused")
    func validation() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let ssh = SetupCapability(kind: .ssh)
        model.registry.register(ssh)
        let setup = GlassShellSetupModel(model: model, mode: .addHost)
        var issues = setup.validateForSave()
        #expect(issues.host.map(\.field) == ["name", "address"])
        #expect(setup.hostIssue(.name) != nil && setup.hostIssue(.address) != nil)
        #expect(await setup.save() == nil && model.catalogHosts.isEmpty, "nothing saved while invalid")

        setup.name = "box"
        setup.address = "user@bad:22"
        issues = setup.validateForSave()
        #expect(issues.host.map(\.field) == ["address"], "an invalid address is reported before any draft")

        setup.address = "box.example"
        setup.select(.ssh)
        let draft = try #require(setup.draft(for: .ssh) as? FakeDraft)
        draft.username = ""
        issues = setup.validateForSave()
        #expect(issues.host.isEmpty && issues.services[.ssh]?.map(\.field) == ["username"])
        #expect(draft.focused.map(\.field) == ["username"], "the draft is asked to focus its first issue")
        #expect(setup.selectedKind == .ssh)
    }

    @Test("One service per sheet: choosing another tab replaces the choice rather than adding both")
    func oneServicePerSheet() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let ssh = SetupCapability(kind: .ssh), rdp = SetupCapability(kind: .rdp)
        model.registry.register(ssh); model.registry.register(rdp)
        let setup = GlassShellSetupModel(model: model, mode: .addHost)

        #expect(setup.enabledKinds == [.ssh], "adding a machine starts on the first live tab")
        setup.select(.rdp)
        #expect(setup.enabledKinds == [.rdp], "the second choice replaces the first; never both")
        setup.select(.ssh)
        #expect(setup.enabledKinds == [.ssh])
        setup.select(nil)
        #expect(setup.enabledKinds == [.ssh], "None is not offered while adding, so it cannot be chosen")
    }

    @Test("A service that fails to commit takes the host this save created with it")
    func failedServiceRollsBackTheNewHost() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let ssh = SetupCapability(kind: .ssh)
        ssh.nextFails = true
        model.registry.register(ssh)
        let setup = GlassShellSetupModel(model: model, mode: .addHost)
        setup.name = "half"
        setup.address = "half.example"
        setup.select(.ssh)

        #expect(await setup.save() == nil)
        #expect(setup.error != nil)
        #expect(model.catalogHosts.isEmpty, "the host created by this save is deleted again")
        #expect(ssh.made.first?.rollbacks.count == 1, "the failed draft is asked to roll back")
    }

    @Test("Adding a machine adds a service: the first live tab is chosen and None is not offered")
    func addingAMachineAddsAService() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let ssh = SetupCapability(kind: .ssh)
        model.registry.register(ssh)
        let setup = GlassShellSetupModel(model: model, mode: .addHost)

        #expect(setup.selection == .ssh, "a machine with nothing on it is not worth a row")
        #expect(!setup.allowsNoService, "and there is no way to opt out while adding")

        setup.name = "box"
        setup.address = "box.example"
        let draft = try #require(setup.draft(for: .ssh) as? FakeDraft)
        draft.username = "casey"
        let id = try #require(await setup.save())
        #expect(model.services(for: id).count == 1)
    }

    @Test("Editing a machine adds nothing on its own")
    func editingAMachineAddsNoService() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        model.registry.register(SetupCapability(kind: .ssh))
        let created = try await model.addHost(displayName: "box", address: "box.example")
        let host = try #require(model.host(created.id))
        let setup = GlassShellSetupModel(model: model, mode: .editHost(host))

        #expect(setup.selection == nil, "editing is not adding")
        #expect(setup.allowsNoService)
        setup.name = "renamed"
        _ = try #require(await setup.save())
        #expect(model.services(for: created.id).isEmpty, "a rename does not grow a service")
    }

    @Test("Add a service to an existing host: the tab is preselected, host fields locked, address required if missing")
    func addServiceToExistingHost() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let ssh = SetupCapability(kind: .ssh)
        model.registry.register(ssh)
        let bare = try await model.addHost(displayName: "bare")
        let shellHost = try #require(model.host(bare.id))
        let setup = GlassShellSetupModel(model: model, mode: .addService(shellHost, .ssh))
        #expect(setup.selectedKind == .ssh && setup.isEnabled(.ssh) && !setup.allowsNoService)
        #expect(!setup.nameEditable && setup.addressEditable, "no address yet: it is collected here, on the host")
        #expect(!setup.showsOrganizeSection)
        #expect(await setup.save() == nil && setup.hostIssue(.address) != nil, "a service needs the machine's address")

        setup.address = "10.0.0.9"
        let id = try #require(await setup.save())
        let host = try #require(model.host(id))
        #expect(host.address == "10.0.0.9" && host.services.map(\.kind) == [.ssh])
        #expect(ssh.made.first?.commits.first?.2 == "10.0.0.9")

        // With an address the host fields are locked and Save goes straight to the commit.
        let again = GlassShellSetupModel(model: model, mode: .addService(host, .ssh))
        #expect(!again.addressEditable)
        _ = try #require(await again.save())
        #expect(model.host(id)?.services.count == 2)
    }

    @Test("Edit a service: the capability's loaded draft is committed under the existing endpoint; a link with nothing behind it is called broken")
    func editService() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let ssh = SetupCapability(kind: .ssh)
        model.registry.register(ssh)
        let created = try await model.addHost(displayName: "edit", address: "edit.example")
        let link = try await model.addService(kind: .ssh, displayName: "Terminal on edit", to: created.id)
        ssh.stored = [link.endpointID]
        let host = try #require(model.host(created.id))
        let setup = GlassShellSetupModel(model: model, mode: .editService(host, link))
        #expect(setup.offeredKinds == [.ssh] && !setup.allowsNoService && !setup.nameEditable && !setup.addressEditable)
        #expect(!setup.editedServiceIsBroken)
        _ = try #require(await setup.save())
        let draft = try #require(ssh.made.first)
        #expect(draft.commits.map(\.0) == [link.endpointID], "committed under the existing endpoint id")
        #expect(model.host(created.id)?.services.count == 1, "editing adds no link")

        ssh.stored = []
        let broken = GlassShellSetupModel(model: model, mode: .editService(host, link))
        #expect(broken.editedServiceIsBroken)
    }

    @Test("Edit Host touches only the machine and its organising fields")
    func editHost() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let created = try await model.addHost(displayName: "old name", address: "a.example", tags: ["Lab"])
        let host = try #require(model.host(created.id))
        let setup = GlassShellSetupModel(model: model, mode: .editHost(host))
        #expect(!setup.showsServiceTabs && setup.showsOrganizeSection && setup.tags == ["Lab"])
        setup.name = "new name"
        setup.aliases = ["nn"]
        _ = try #require(await setup.save())
        let after = try #require(model.host(created.id))
        #expect(after.displayName == "new name" && after.aliases == ["nn"] && after.address == "a.example")
    }

    @Test("Removing a service tells the owning capability to delete what it stored")
    func removeServiceReachesCapability() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let ssh = SetupCapability(kind: .ssh)
        model.registry.register(ssh)
        let created = try await model.addHost(displayName: "rm", address: "rm.example")
        let link = try await model.addService(kind: .ssh, displayName: "t", to: created.id)
        try await model.removeService(link.endpointID, from: created.id)
        #expect(ssh.removed == [link.endpointID])
        #expect(model.services(for: created.id).isEmpty)
    }

    /// The sibling of `removeServiceReachesCapability`, and the one that was missing.
    ///
    /// `removeService` had always told the owning capability to delete what it stored; `deleteHost`
    /// removed the records and told nobody. Every capability's configuration for that machine was
    /// orphaned — and stayed *reachable*, because surfaces that read the capability's own store
    /// rather than the catalog went on listing it. A host deleted from the library kept appearing
    /// in the terminal's Connect Saved Host with nothing left that could remove it.
    @Test("Deleting a host tells every owning capability to delete what it stored")
    func deleteHostReachesCapabilities() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        let ssh = SetupCapability(kind: .ssh)
        let database = SetupCapability(kind: .database)
        model.registry.register(ssh)
        model.registry.register(database)
        let created = try await model.addHost(displayName: "doomed", address: "doomed.example")
        let terminal = try await model.addService(kind: .ssh, displayName: "t", to: created.id)
        let db = try await model.addService(kind: .database, displayName: "d", to: created.id)

        try await model.deleteHost(created.id)

        #expect(ssh.removed == [terminal.endpointID], "the terminal's server is deleted with the host")
        #expect(database.removed == [db.endpointID], "and so is every other capability's")
        #expect(model.host(created.id) == nil)
    }

    /// One capability failing must not leave the others holding orphans — the deletion has already
    /// happened by then, so stopping at the first error would strand everything after it.
    @Test("A capability that fails to clean up does not strand the others")
    func deleteHostContinuesPastAFailure() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        final class Refuses: GlassCapability {
            let kind: HostServiceKind = .ssh
            var displayName: String { "Refuses" }
            var symbolName: String { "xmark" }
            func open(service: HostServiceLink, host: HostProfile, report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) {}
            struct Failure: Error {}
            func removeService(_ service: HostServiceLink, host: HostProfile) async throws { throw Failure() }
        }
        let refusing = Refuses()
        let database = SetupCapability(kind: .database)
        model.registry.register(refusing)
        model.registry.register(database)
        let created = try await model.addHost(displayName: "half", address: "half.example")
        _ = try await model.addService(kind: .ssh, displayName: "t", to: created.id)
        let db = try await model.addService(kind: .database, displayName: "d", to: created.id)

        await #expect(throws: Refuses.Failure.self) { try await model.deleteHost(created.id) }
        #expect(database.removed == [db.endpointID], "the other capability still cleaned up")
        #expect(model.host(created.id) == nil, "and the machine is still gone")
    }

    @Test("A capability without the setup contract cannot create a service")
    func unavailableDraftBlocksSave() async throws {
        let (model, root) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root) }
        final class Bare: GlassCapability {
            let kind: HostServiceKind = .database
            var displayName: String { "Bare" }
            var symbolName: String { "circle" }
            func open(service: HostServiceLink, host: HostProfile, report: @escaping @MainActor (GlassCapabilityOutcome) -> Void) {}
        }
        model.registry.register(Bare())
        let setup = GlassShellSetupModel(model: model, mode: .addHost)
        setup.name = "x"; setup.address = "x.example"
        setup.select(.database)
        #expect(setup.draft(for: .database) is GlassUnavailableServiceDraft)
        #expect(await setup.save() == nil && model.catalogHosts.isEmpty)
    }
}
