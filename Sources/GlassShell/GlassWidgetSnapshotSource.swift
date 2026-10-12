//
//  GlassWidgetSnapshotSource.swift
//  Glass Power Tools — GlassShell
//
//  What the widgets show, built from the library and Active (2026-10-12). The library is the
//  shell's, so this is where a machine's services, its favourite star and its last connection, and
//  what is open or running on it, are known together. The app writes the result for the widget
//  extension (`GlassWidgetStore`).
//

import Foundation
import GlassConnectionKit
import GlassWidgetData

public extension GlassShellModel {
    /// Every machine with a service a widget can open, and what is open and running, by machine.
    /// This device's own entry is left out: a widget on another device could not open it, and
    /// this one opens it from New Terminal.
    func widgetSnapshot(now: Date = Date()) -> GlassWidgetSnapshot {
        let machines = hosts.filter { !$0.isLocal }.compactMap { host -> GlassWidgetSnapshot.Machine? in
            let services = host.services.map {
                GlassWidgetSnapshot.Service(id: $0.endpointID.rawValue, kind: Self.widgetKind($0.kind), name: $0.displayName)
            }
            guard !services.isEmpty else { return nil }
            return GlassWidgetSnapshot.Machine(id: host.id.rawValue, name: host.displayName,
                                               isFavorite: isFavorite(host.id), lastConnected: lastConnected(host.id),
                                               services: services)
        }
        let active = activeMachines().map { machine in
            let endpoints = machine.sessions.flatMap(\.endpointIDs) + machine.running.map(\.endpointID)
            let present = Set(endpoints.compactMap { endpoint in
                host(owningEndpoint: endpoint)?.services.first { $0.endpointID == endpoint }.map { Self.widgetKind($0.kind) }
            })
            return GlassWidgetSnapshot.ActiveMachine(
                machineID: UUID(uuidString: machine.id), name: machine.name,
                open: machine.sessions.count, running: machine.running.count,
                kinds: GlassWidgetSnapshot.ServiceKind.allCases.filter(present.contains))
        }
        return GlassWidgetSnapshot(writtenAt: now, machines: machines, active: active)
    }

    static func widgetKind(_ kind: HostServiceKind) -> GlassWidgetSnapshot.ServiceKind {
        switch kind {
        case .ssh: .terminal
        case .database: .database
        case .rdp: .desktop
        }
    }
}
