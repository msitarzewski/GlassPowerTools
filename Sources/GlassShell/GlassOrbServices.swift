//
//  GlassOrbServices.swift
//  Glass Power Tools — GlassShell
//
//  A machine's services on an orb's ring (D88; the owner, 2026-10-25: "add Editor, Database, and
//  Desktop to the orb so it's more of a machine nav than just tabs for a Terminal window", and on the
//  headset that evening: "we should only show connected services"). The ones open, each with its
//  session. Which ones is decided here, apart from drawing them, so it is tested without a headset;
//  the dots are drawn on Vision Pro (`orbServiceDots`).
//

import Foundation
import GlassConnectionKit

/// One of a machine's services, as an orb's ring shows it.
public struct GlassOrbService: Equatable, Sendable {
    public let hostID: HostID
    public let endpointID: EndpointID
    public let kind: HostServiceKind
    public let title: String
    public let symbolName: String
    /// The session open for it (`GlassOpenSession.id`).
    public let openSessionID: String
}

extension GlassShellModel {
    /// The services open on the machine `endpointIDs` are on — the first of them the library knows
    /// — other than `own` kind (a terminal window's tabs are its terminals already), in the order the
    /// machine lists them, each with its session. One not open is left off: a ring of services that
    /// weren't there was "ghost services" on every orb. So is a kind this build cannot open.
    public func orbServices(for endpointIDs: [EndpointID], excluding own: HostServiceKind?,
                            open: [GlassOpenSession]) -> [GlassOrbService] {
        guard let host = endpointIDs.lazy.compactMap({ self.host(owningEndpoint: $0) }).first else { return [] }
        return host.services.filter { $0.kind != own }.compactMap { service in
            guard let capability = registry.capability(for: service.kind),
                  let session = open.first(where: { $0.endpointIDs.contains(service.endpointID) }) else { return nil }
            return GlassOrbService(hostID: host.id, endpointID: service.endpointID, kind: service.kind,
                                   title: service.displayName,
                                   symbolName: capability.symbolName, openSessionID: session.id)
        }
    }
}
