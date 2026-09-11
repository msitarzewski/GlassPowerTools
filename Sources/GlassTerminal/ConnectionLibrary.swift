//
//  ConnectionLibrary.swift
//  Glass Power Tools — GlassTerminal
//
//  The workgroup surface's projection over the saved servers and presets. glas.sh's library
//  modes, scopes, collections and column defaults left with the library itself (the shell's,
//  over GlassConnectionUI's `GlassLibraryProjection`); only what `TerminalWorkgroupsView` reads
//  remains.
//

import Foundation
import GlassConnectionKit
import GlassConnectionUI

struct ConnectionLibraryProjection {
    /// Saved servers, deduplicated by id in source order (the kit's projection does the work).
    let servers: [ServerConfiguration]
    let workgroups: [LayoutPreset]
    let networkIsConfigured: Bool

    init(servers: [ServerConfiguration], workgroups: [LayoutPreset], networkIsConfigured: Bool) {
        let shared = GlassLibraryProjection(items: servers.map(Self.item), order: .source)
        var records: [UUID: ServerConfiguration] = [:]
        for server in servers where records[server.id] == nil { records[server.id] = server }
        self.servers = shared.items.compactMap { records[$0.id] }
        self.workgroups = workgroups
        self.networkIsConfigured = networkIsConfigured
    }

    func workgroups(matching searchQuery: String = "") -> [LayoutPreset] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return workgroups }
        return workgroups.filter { preset in
            preset.name.localizedCaseInsensitiveContains(query) || preset.sessionIntents.contains {
                $0.label?.localizedCaseInsensitiveContains(query) == true
            }
        }
    }

    private static func item(_ server: ServerConfiguration) -> GlassLibraryItem<UUID> {
        .init(id: server.id, name: server.name, searchTerms: [server.host, server.username], tags: server.tags,
              isFavorite: server.isFavorite, lastConnected: server.lastConnected, dateAdded: server.dateAdded,
              sortKeys: [server.host, server.username])
    }
}
