import GlassLayers
import Foundation
import Testing
import GlassConnectionKit
import GlassHostCatalog
@testable import GlassShell

/// Regression tests for the Stage 1 security review findings F1, F2, F3 (and the F7 sibling in
/// GlassLayersTests). Every test runs against a temporary directory, never the real App Group.
@MainActor
private func makeRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("GlassShellFixTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("app"), withIntermediateDirectories: true)
    return root
}

@MainActor
private func makeModel(at root: URL) -> GlassShellModel {
    GlassShellModel(storageDirectory: root.appendingPathComponent("app"),
                    sharedContainerURL: root.appendingPathComponent("group"),
                    resolveSharedContainer: false, accessGroup: nil, layers: GlassLayerStore())
}

@Suite("GlassShell security fixes", .serialized)
@MainActor
struct GlassShellSecurityFixTests {
    @Test("F1: a corrupt preferences file is never overwritten; the model is read-only and says so")
    func corruptPreferencesAreNotOverwritten() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("app/shell-preferences.json")
        let garbage = Data("{ this is not json".utf8)
        try garbage.write(to: file)

        let model = makeModel(at: root)
        #expect(model.preferencesReadOnly)
        #expect(model.preferencesProblem?.contains("read-only") == true)
        #expect(try Data(contentsOf: file) == garbage, "init must not rewrite the file")

        let host = try await model.addHost(displayName: "Alpha")
        model.toggleFavorite(host.id)                       // attempts a persist
        #expect(model.errorMessage?.contains("read-only") == true)
        #expect(try Data(contentsOf: file) == garbage, "a failed persist must not rewrite the file")

        // Explicit reset moves the file aside and starts fresh.
        try model.resetPreferences()
        #expect(!model.preferencesReadOnly)
        let aside = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("app").path)
            .filter { $0.hasPrefix("shell-preferences.json.unreadable-") }
        #expect(aside.count == 1)
        #expect(try Data(contentsOf: root.appendingPathComponent("app/\(aside[0])")) == garbage)
        #expect(try JSONDecoder().decode(GlassShellPreferences.self, from: Data(contentsOf: file)).version == GlassShellPreferences.currentVersion)
    }

    @Test("F1: a newer-version preferences file is never overwritten")
    func newerVersionIsNotOverwritten() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("app/shell-preferences.json")
        let newer = Data(#"{"version": \#(GlassShellPreferences.currentVersion + 5), "writerID": "\#(UUID().uuidString)", "hosts": {}, "futureField": true}"#.utf8)
        try newer.write(to: file)

        let model = makeModel(at: root)
        #expect(model.preferencesReadOnly)
        #expect(model.preferencesProblem?.contains("newer build") == true)
        let host = try await model.addHost(displayName: "Alpha")
        model.toggleFavorite(host.id)
        #expect(try Data(contentsOf: file) == newer)
    }

    @Test("F1: a file that cannot be read yet is left alone and adopted once readable")
    func unavailablePreferencesAreRetriedNotReplaced() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("app/shell-preferences.json")
        var original = GlassShellPreferences()
        let hostID = HostID()
        original[host: hostID].isFavorite = true
        try GlassShellPreferencesStore(fileURL: file).save(original)
        let originalBytes = try Data(contentsOf: file)
        // Simulate "protected before first unlock" with a permission denial.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }

        let model = makeModel(at: root)
        #expect(model.preferencesReadOnly)
        #expect(model.preferencesProblem?.contains("not readable yet") == true)
        #expect(model.isFavorite(hostID) == false, "defaults in memory while unreadable")
        model.toggleFavorite(hostID)
        #expect(model.errorMessage?.contains("read-only") == true)

        // Once readable, the real file is adopted — not replaced.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        await model.load()
        #expect(!model.preferencesReadOnly)
        #expect(model.preferencesProblem == nil)
        #expect(model.isFavorite(hostID) == true)
        #expect(try Data(contentsOf: file) == originalBytes, "adopting must not rewrite")
        // The stored writer identity survives the next save; the process keeps stamping catalog
        // writes with its init-time identity until relaunch (provenance only).
        model.toggleFavorite(hostID)
        let saved = try JSONDecoder().decode(GlassShellPreferences.self, from: Data(contentsOf: file))
        #expect(saved.writerID == original.writerID)
        #expect(saved[host: hostID].isFavorite == false)
    }

    @Test("F2: updateHost keeps a service another app paired since our last load")
    func updateHostKeepsExternalServices() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(at: root)
        let host = try await model.addHost(displayName: "Alpha", tags: ["lab"])
        // Another process pairs a service after we loaded.
        let sibling = HostCatalogStore(fileURL: model.catalogFileURL)
        let external = HostServiceLink(endpointID: EndpointID(), kind: .database, displayName: "db")
        try await sibling.pair(external, with: host.id)
        #expect(model.services(for: host.id).isEmpty, "our copy is stale on purpose")

        try await model.updateHost(host.id, displayName: "Alpha Renamed", aliases: ["a1"], tags: ["lab"])
        let after = try #require(model.host(host.id))
        #expect(after.displayName == "Alpha Renamed")
        #expect(after.aliases == ["a1"])
        #expect(after.services.map(\.endpointID) == [external.endpointID])
    }

    @Test("F3: Connect with no capability records the choice but never a connection time")
    func placeholderDoesNotStampLastConnected() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(at: root)
        let host = try await model.addHost(displayName: "Alpha")
        let link = try await model.addService(kind: .ssh, displayName: "shell", to: host.id)
        model.connect(hostID: host.id)
        #expect(model.placeholderRequest != nil)
        #expect(model.lastUsedService(for: host.id)?.endpointID == link.endpointID)
        #expect(model.lastConnected(host.id) == nil)
        #expect(model.items[0].lastConnected == nil)
    }
}

@Suite("GlassShell first run", .serialized)
@MainActor
struct GlassShellFirstRunTests {
    @Test("An existing but empty shared container loads as zero hosts with no error")
    func emptySharedContainerLoads() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("group"), withIntermediateDirectories: true)
        let model = makeModel(at: root)
        await model.load()
        #expect(model.isLoaded)
        #expect(model.errorMessage == nil, "first run must not alert: \(model.errorMessage ?? "")")
        #expect(model.hosts.isEmpty)
        #expect(model.hasSharedContainer)
    }

    @Test("A shared container that does not exist yet still loads and is created on first write")
    func absentSharedContainerLoadsAndCreates() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = makeModel(at: root)   // root/group does not exist
        await model.load()
        #expect(model.errorMessage == nil, "load must not alert: \(model.errorMessage ?? "")")
        _ = try await model.addHost(displayName: "First")
        #expect(FileManager.default.fileExists(atPath: model.catalogFileURL.path))
        #expect(model.hosts.count == 1)
    }

    @Test("A shared container the sandbox refuses degrades to the private catalog with a visible reason, no alert")
    func unwritableSharedContainerFallsBack() async throws {
        let root = try makeRoot()
        let group = root.appendingPathComponent("group")
        try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: group.path)   // cannot create GlassHostCatalog/
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: group.path); try? FileManager.default.removeItem(at: root) }

        let model = makeModel(at: root)
        #expect(model.hasSharedContainer, "resolves before the first load, as on macOS")
        await model.load()
        #expect(model.errorMessage == nil, "must not alert: \(model.errorMessage ?? "")")
        #expect(!model.hasSharedContainer)
        #expect(model.hostLibraryStatus.contains("not allowed"))
        #expect(model.catalogFileURL.path.hasPrefix(root.appendingPathComponent("app").path))
        _ = try await model.addHost(displayName: "Local Only")
        #expect(model.hosts.count == 1)
        #expect(!FileManager.default.fileExists(atPath: group.appendingPathComponent("GlassHostCatalog").path))
    }
}
