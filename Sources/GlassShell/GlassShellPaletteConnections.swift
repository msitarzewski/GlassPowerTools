//
//  GlassShellPaletteConnections.swift
//  Glass Power Tools — GlassShell
//
//  The Command Palette's connections: every service on every machine, connected as the library's
//  Connect connects it (the owner, 2026-10-14: "Let's get desktops into this command list").
//
//  The terminal and the database each listed their own — "connect: Terminal on alpha",
//  "connect: MySQL on alpha" — and the desktop never had a list, so its services were missing.
//  The database's entries set a request nothing read: they opened Connections and connected
//  nothing. One list from the library covers every kind there is, and any added later.
//

#if os(macOS)
import SwiftUI
import GlassConnectionKit
import GlassConnectionUI
import GlassLayers
import GlassWidgetData

public extension GlassShellModel {
    /// Lists the library's services in the Command Palette, replacing any list registered before.
    func registerPaletteConnections() {
        GlassCommandPaletteSources.register(id: "connections") { [weak self] openWindow in
            self?.paletteConnections(openConnections: { openWindow.openConnections() }) ?? []
        }
    }

    /// "Connect: Desktop on alpha", one per service, machine by machine as the library lists them.
    /// A capability carries a connection out from a Connections window's views, so one is opened
    /// first when none is (as Siri's Connect does).
    func paletteConnections(openConnections: @escaping @MainActor () -> Void) -> [MacCommandCenterEntry] {
        let available = Set(registry.registeredKinds)
        return hosts.flatMap { host in
            host.services.filter { available.contains($0.kind) }.map { service in
                let kind = GlassServicePresentation.displayName(for: service.kind)
                return MacCommandCenterEntry(
                    id: "connection.connect.\(service.endpointID.rawValue)",
                    title: "Connect: " + Self.paletteName(of: service, on: host),
                    detail: "\(kind) · \(host.displayName)"
                ) { [weak self] in
                    if !GlassLibraryWindows.isOpen { openConnections() }
                    self?.connect(hostID: host.id, endpointID: service.endpointID)
                }
            }
        }
    }

    /// A service's name with its machine's: "Terminal on alpha" for one named only by its kind or
    /// its machine, its own name where that already says the machine ("MySQL on alpha"), and
    /// "reports on alpha" where it does not.
    nonisolated static func paletteName(of service: HostServiceLink, on host: GlassShellHost) -> String {
        let kind = GlassServicePresentation.displayName(for: service.kind)
        let name = service.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name.caseInsensitiveCompare(kind) == .orderedSame
            || name.caseInsensitiveCompare(host.displayName) == .orderedSame {
            return "\(kind) on \(host.displayName)"
        }
        if name.range(of: " on \(host.displayName)", options: [.caseInsensitive, .anchored, .backwards]) != nil {
            return name
        }
        return "\(name) on \(host.displayName)"
    }

    // MARK: Places (2026-10-14)

    /// Lists the Command Palette's places: every project, Favorites' folders, the database's saved
    /// queries and the sessions running on the machines with no window here. The composition root
    /// hands over what the shell does not hold: the editor's projects and the database's queries.
    func registerPalettePlaces(projects: @escaping @MainActor () -> [UUID],
                               savedQueries: @escaping @MainActor () -> [GlassWidgetSnapshot.SavedQuery]) {
        GlassCommandPaletteSources.register(id: "places") { [weak self] openWindow in
            self?.palettePlaces(projects: projects(), savedQueries: savedQueries(),
                                openConnections: { openWindow.openConnections() }) ?? []
        }
    }

    /// Each opened the way its usual place opens it: a project or a folder as Favorites does
    /// (`describeFavorite`), a saved query as Siri does (`GlassWidgetRequest.openSavedQuery`), a
    /// running session as Active does. A folder opens in Files, which a Connections window carries
    /// out, so one is opened first when none is.
    func palettePlaces(projects: [UUID], savedQueries: [GlassWidgetSnapshot.SavedQuery],
                       openConnections: @escaping @MainActor () -> Void) -> [MacCommandCenterEntry] {
        var entries: [MacCommandCenterEntry] = []
        for id in projects {
            guard let project = describeFavorite?(.project(id)) else { continue }
            entries.append(MacCommandCenterEntry(id: "project.\(id)", title: "Open Project: \(project.title)",
                                                 detail: project.subtitle) { project.open() })
        }
        for item in favoriteItems {
            guard case .folder = item, let folder = describeFavorite?(item) else { continue }
            entries.append(MacCommandCenterEntry(id: "folder.\(item.key)", title: "Open Folder: \(folder.title)",
                                                 detail: folder.subtitle) {
                if !GlassLibraryWindows.isOpen { openConnections() }
                folder.open()
            })
        }
        for query in savedQueries {
            entries.append(MacCommandCenterEntry(id: "query.\(query.id)", title: "Open Query: \(query.name)",
                                                 detail: query.database) {
                GlassWidgetRequests.shared.post(.openSavedQuery(query.id))
            })
        }
        for session in runningSessions where !session.isOpenHere {
            let machine = host(owningEndpoint: session.endpointID)?.displayName
            entries.append(MacCommandCenterEntry(
                id: "running.\(session.id)", title: "Attach: \(session.title)",
                detail: ([session.subtitle, machine].compactMap { $0 } + ["running, no window here"]).joined(separator: " · ")
            ) { [weak self] in self?.open(session) })
        }
        return entries
    }
}
#endif
