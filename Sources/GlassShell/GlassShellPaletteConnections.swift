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
}
#endif
