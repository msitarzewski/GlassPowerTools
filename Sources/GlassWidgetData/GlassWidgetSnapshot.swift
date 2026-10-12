//
//  GlassWidgetSnapshot.swift
//  Glass Power Tools — GlassWidgetData
//
//  What the widgets show, written by the app into the App Group container and read by the widget
//  extension (2026-10-12: "update the widget suite to make all of them useful for today's
//  platform"; the owner chose Machines and Active, on iPhone, iPad, Vision Pro and the Mac).
//
//  The one widget before this read a `servers` list from shared defaults that nothing has written
//  since the catalog became the one store for connections (D26): it showed "No Servers" or a list
//  frozen before then. This is a snapshot the app writes for the widgets alone, so their format is
//  not the catalog's and a change to one does not break the other.
//
//  Metadata only, as the catalog's own records are: names, kinds, times and counts — no address,
//  user name, credential or anything else a lock screen should not show.
//

import Foundation

public struct GlassWidgetSnapshot: Codable, Sendable, Equatable {
    public static let currentSchema = 1

    public var schema: Int
    /// When the app wrote it.
    public var writtenAt: Date
    /// Every machine with a service the widgets can open, favourites first, then by last use.
    public var machines: [Machine]
    /// What was running when it was written, by machine.
    public var active: [ActiveMachine]

    public init(writtenAt: Date = Date(), machines: [Machine] = [], active: [ActiveMachine] = []) {
        self.schema = Self.currentSchema
        self.writtenAt = writtenAt
        self.machines = machines
        self.active = active
    }

    public enum ServiceKind: String, Codable, Sendable, CaseIterable {
        case terminal, database, desktop

        public var title: String {
            switch self {
            case .terminal: "Terminal"
            case .database: "Database"
            case .desktop: "Desktop"
            }
        }

        public var symbolName: String {
            switch self {
            case .terminal: "apple.terminal"
            case .database: "cylinder.split.1x2"
            case .desktop: "display"
            }
        }
    }

    public struct Service: Codable, Sendable, Equatable, Identifiable {
        /// The service's endpoint id, which Connect opens.
        public var id: UUID
        public var kind: ServiceKind
        public var name: String

        public init(id: UUID, kind: ServiceKind, name: String) {
            self.id = id
            self.kind = kind
            self.name = name
        }
    }

    public struct Machine: Codable, Sendable, Equatable, Identifiable {
        /// The host's id in the library.
        public var id: UUID
        public var name: String
        public var isFavorite: Bool
        public var lastConnected: Date?
        public var services: [Service]

        public init(id: UUID, name: String, isFavorite: Bool = false, lastConnected: Date? = nil, services: [Service]) {
            self.id = id
            self.name = name
            self.isFavorite = isFavorite
            self.lastConnected = lastConnected
            self.services = services
        }
    }

    public struct ActiveMachine: Codable, Sendable, Equatable, Identifiable {
        /// The host's id; nil for sessions no machine in the library owns.
        public var machineID: UUID?
        public var name: String
        /// Sessions open in the app.
        public var open: Int
        /// Sessions left running on the machine — tmux, detached or open on another device.
        public var running: Int
        /// The kinds of what is open, for the icons.
        public var kinds: [ServiceKind]

        public var id: String { machineID?.uuidString ?? "elsewhere-\(name)" }

        public init(machineID: UUID?, name: String, open: Int, running: Int, kinds: [ServiceKind]) {
            self.machineID = machineID
            self.name = name
            self.open = open
            self.running = running
            self.kinds = kinds
        }
    }

    /// Open in the app, everywhere.
    public var openCount: Int { active.reduce(0) { $0 + $1.open } }
    /// Running on machines, everywhere.
    public var runningCount: Int { active.reduce(0) { $0 + $1.running } }

    /// The machines a widget of `limit` rows shows: favourites first, by name, then the rest by
    /// last use, most recent first, then by name.
    public func machines(limit: Int) -> [Machine] {
        let favorites = machines.filter(\.isFavorite)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let others = machines.filter { !$0.isFavorite }.sorted { a, b in
            switch (a.lastConnected, b.lastConnected) {
            case let (x?, y?) where x != y: return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
        return Array((favorites + others).prefix(max(limit, 0)))
    }

    /// The same snapshot apart from when it was written: a write that changes nothing else need
    /// not wake every widget.
    public func sameContent(as other: GlassWidgetSnapshot) -> Bool {
        machines == other.machines && active == other.active && schema == other.schema
    }
}

/// Where the snapshot lives: a file in the App Group container both the app and the extension
/// can reach.
public enum GlassWidgetStore {
    /// The App Group, from the `GlassAppGroup` Info.plist key the app and the extension both carry.
    public static var appGroup: String {
        (Bundle.main.object(forInfoDictionaryKey: "GlassAppGroup") as? String)
            .flatMap { $0.isEmpty || $0.hasPrefix("$(") ? nil : $0 } ?? "group.sh.glas.shared"
    }

    public static func snapshotURL(appGroup: String = appGroup, fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("Widgets", isDirectory: true)
            .appendingPathComponent("snapshot.json")
    }

    public static func read(from url: URL? = snapshotURL()) -> GlassWidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url),
              let snapshot = try? decoder.decode(GlassWidgetSnapshot.self, from: data),
              snapshot.schema == GlassWidgetSnapshot.currentSchema else { return nil }
        return snapshot
    }

    /// Writes it when its content changed; true when it did.
    @discardableResult
    public static func write(_ snapshot: GlassWidgetSnapshot, to url: URL? = snapshotURL()) throws -> Bool {
        guard let url else { return false }
        if let existing = read(from: url), existing.sameContent(as: snapshot) { return false }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(snapshot).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return true
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
