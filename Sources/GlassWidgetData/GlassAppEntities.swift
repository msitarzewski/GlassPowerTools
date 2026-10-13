//
//  GlassAppEntities.swift
//  Glass Power Tools — GlassWidgetData
//
//  The library's machines, services and workgroups as the system sees them — Siri, Shortcuts,
//  Spotlight, widgets — so an intent can name one ("Open a terminal on alpha") on every platform
//  (D72, 2026-10-13: "App intents, all of the modern stuff").
//
//  Read from the snapshot the app writes for the widgets (`GlassWidgetSnapshot`), which is metadata
//  only and is in the App Group for the app and its extensions alike: the same answer in the app,
//  a widget or an extension, and nothing here that a lock screen should not show.
//

import AppIntents
import Foundation

/// Where entity queries read the library. Tests replace it.
enum GlassEntitySource {
    nonisolated(unsafe) static var snapshot: @Sendable () -> GlassWidgetSnapshot? = { GlassWidgetStore.read() }

    static var machines: [GlassWidgetSnapshot.Machine] {
        snapshot()?.machines(limit: .max) ?? []
    }

    /// Names that contain every word typed, as the library's search matches them.
    static func matches(_ name: String, _ query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        return words.allSatisfy { name.localizedStandardContains($0) }
    }
}

// MARK: - Machines

/// A machine in the library: a host and its services.
public struct GlassMachineEntity: AppEntity, Identifiable, Sendable {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Machine"
    public static let defaultQuery = GlassMachineQuery()

    public let id: UUID
    public let name: String
    public let services: [GlassWidgetSnapshot.Service]

    public init(id: UUID, name: String, services: [GlassWidgetSnapshot.Service]) {
        self.id = id
        self.name = name
        self.services = services
    }

    init(_ machine: GlassWidgetSnapshot.Machine) {
        self.init(id: machine.id, name: machine.name, services: machine.services)
    }

    public var displayRepresentation: DisplayRepresentation {
        let kinds = GlassWidgetSnapshot.ServiceKind.allCases.filter { kind in services.contains { $0.kind == kind } }
        return DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(kinds.map(\.title).joined(separator: ", "))",
            image: .init(systemName: "server.rack"))
    }

    /// The machine's first service of `kind`, as the library's row orders them.
    public func service(_ kind: GlassWidgetSnapshot.ServiceKind) -> GlassWidgetSnapshot.Service? {
        services.first { $0.kind == kind }
    }
}

public struct GlassMachineQuery: EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [GlassMachineEntity] {
        let machines = GlassEntitySource.machines
        return identifiers.compactMap { id in machines.first { $0.id == id }.map(GlassMachineEntity.init) }
    }

    public func entities(matching string: String) async throws -> [GlassMachineEntity] {
        GlassEntitySource.machines.filter { GlassEntitySource.matches($0.name, string) }.map(GlassMachineEntity.init)
    }

    /// Favourites first, then by last use — the widget's order.
    public func suggestedEntities() async throws -> [GlassMachineEntity] {
        GlassEntitySource.machines.map(GlassMachineEntity.init)
    }
}

// MARK: - Services

/// One of a machine's services: its terminal, a database, its desktop.
public struct GlassServiceEntity: AppEntity, Identifiable, Sendable {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Service"
    public static let defaultQuery = GlassServiceQuery()

    /// The service's endpoint id, which Connect opens.
    public let id: UUID
    public let name: String
    public let kind: GlassWidgetSnapshot.ServiceKind
    public let machineID: UUID
    public let machineName: String

    public init(id: UUID, name: String, kind: GlassWidgetSnapshot.ServiceKind, machineID: UUID, machineName: String) {
        self.id = id
        self.name = name
        self.kind = kind
        self.machineID = machineID
        self.machineName = machineName
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(kind.title) on \(machineName)",
            image: .init(systemName: kind.symbolName))
    }

    static func all() -> [GlassServiceEntity] {
        GlassEntitySource.machines.flatMap { machine in
            machine.services.map {
                GlassServiceEntity(id: $0.id, name: $0.name, kind: $0.kind, machineID: machine.id, machineName: machine.name)
            }
        }
    }
}

public struct GlassServiceQuery: EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [GlassServiceEntity] {
        let services = GlassServiceEntity.all()
        return identifiers.compactMap { id in services.first { $0.id == id } }
    }

    /// A service by its own name or its machine's: "orders", "alpha", "alpha database".
    public func entities(matching string: String) async throws -> [GlassServiceEntity] {
        GlassServiceEntity.all().filter {
            GlassEntitySource.matches("\($0.name) \($0.machineName) \($0.kind.title)", string)
        }
    }

    public func suggestedEntities() async throws -> [GlassServiceEntity] {
        GlassServiceEntity.all()
    }
}

// MARK: - Workgroups

/// A saved workgroup: terminals that open together.
public struct GlassWorkgroupEntity: AppEntity, Identifiable, Sendable {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Workgroup"
    public static let defaultQuery = GlassWorkgroupQuery()

    public let id: UUID
    public let name: String
    public let terminals: Int

    public init(id: UUID, name: String, terminals: Int) {
        self.id = id
        self.name = name
        self.terminals = terminals
    }

    init(_ workgroup: GlassWidgetSnapshot.Workgroup) {
        self.init(id: workgroup.id, name: workgroup.name, terminals: workgroup.terminals)
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(terminals == 1 ? "1 terminal" : "\(terminals) terminals")",
            image: .init(systemName: "rectangle.3.group"))
    }
}

public struct GlassWorkgroupQuery: EntityStringQuery {
    public init() {}

    private var workgroups: [GlassWidgetSnapshot.Workgroup] {
        (GlassEntitySource.snapshot()?.workgroups ?? [])
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func entities(for identifiers: [UUID]) async throws -> [GlassWorkgroupEntity] {
        let all = workgroups
        return identifiers.compactMap { id in all.first { $0.id == id }.map(GlassWorkgroupEntity.init) }
    }

    public func entities(matching string: String) async throws -> [GlassWorkgroupEntity] {
        workgroups.filter { GlassEntitySource.matches($0.name, string) }.map(GlassWorkgroupEntity.init)
    }

    public func suggestedEntities() async throws -> [GlassWorkgroupEntity] {
        workgroups.map(GlassWorkgroupEntity.init)
    }
}
