//
//  GlassShellFavoritesSync.swift
//  Glass Power Tools — GlassShell
//
//  Favourites on every device (owner, 2026-10-08: "Favorites aren't synced"). They were kept with
//  the rest of the shell's per-device preferences, a choice carried over from glas.sh; now each
//  host's favourite travels through the shell's iCloud key-value sync, as the editor's project list
//  does. Connection times, history and the last-used service stay on the device (D41).
//

import Foundation
import GlassConnectionKit

/// Every host's favourite, with when it last changed. The newest change wins per host, so turning
/// a favourite off on one device turns it off everywhere, and every device reaches one answer.
public struct GlassFavoritesPayload: Codable, Equatable, Sendable {
    public struct Mark: Codable, Equatable, Sendable {
        public var isFavorite: Bool
        public var changedAt: Date
        public init(isFavorite: Bool, changedAt: Date) {
            self.isFavorite = isFavorite
            self.changedAt = changedAt
        }
    }

    public static let maximumHosts = 5_000
    /// A favourite set before favourites synced: older than any change made since, so each device's
    /// earlier favourites are kept together on the first sync rather than one list replacing another.
    public static let legacyChange = Date(timeIntervalSince1970: 0)

    /// Keyed by host id.
    public var marks: [String: Mark]

    public init(marks: [String: Mark] = [:]) { self.marks = marks }

    /// Whether `candidate` replaces `existing`: the later change, and on a tie the favourite, so
    /// two devices merging in either order agree.
    public static func replaces(_ candidate: Mark, _ existing: Mark?) -> Bool {
        guard let existing else { return true }
        if candidate.changedAt != existing.changedAt { return candidate.changedAt > existing.changedAt }
        return candidate.isFavorite && !existing.isFavorite
    }
}

extension GlassFavoritesPayload: GlassSettingsSyncPayload {
    public func validate() throws {
        guard marks.count <= Self.maximumHosts else {
            throw GlassSettingsSyncError.invalidPayload("too many favourites")
        }
        guard marks.keys.allSatisfy({ UUID(uuidString: $0) != nil }) else {
            throw GlassSettingsSyncError.invalidPayload("a favourite names no host")
        }
    }

    public func converged(with other: GlassFavoritesPayload) -> GlassFavoritesPayload {
        var merged = marks
        for (key, mark) in other.marks where Self.replaces(mark, merged[key]) {
            merged[key] = mark
        }
        return GlassFavoritesPayload(marks: merged)
    }
}

public extension GlassSettingsSyncService where Payload == GlassFavoritesPayload {
    static var favoritesStoreKey: String { "shell-favorites-envelope-v1" }

    /// Labelled differently from the designated initializer so this forwards to it.
    convenience init(favoritesStore store: any GlassSettingsKeyValueStore, writerID: UUID = UUID()) {
        self.init(store: store, writerID: writerID, storeKey: Self.favoritesStoreKey)
    }
}

// MARK: - Favourites beyond machines

/// Something in Favorites that is not a machine (the owner, 2026-10-13: "Favorites should be
/// machines OR services OR projects OR Workgroups OR SFTP (at the current folder depth)"). Machines
/// keep their own mark on the host (`GlassFavoritesPayload`), which older builds read; these travel
/// under a key of their own, so an older build neither reads them nor writes over them.
public enum GlassFavorite: Codable, Hashable, Sendable {
    /// A terminal, database or desktop service of a machine: opening it connects.
    case service(EndpointID)
    /// An editor project, by its id in the project list.
    case project(UUID)
    /// A saved workgroup: opening it opens its terminals.
    case workgroup(UUID)
    /// A folder on a machine, reached through that machine's Terminal service: Files opens there.
    case folder(endpoint: EndpointID, path: String)

    public enum Kind: Int, CaseIterable, Comparable, Sendable {
        case service, project, workgroup, folder

        /// What Favorites' section for this kind is called, in its order.
        public var sectionTitle: String {
            switch self {
            case .service: "Services"
            case .project: "Projects"
            case .workgroup: "Workgroups"
            case .folder: "Folders"
            }
        }

        public static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public var kind: Kind {
        switch self {
        case .service: .service
        case .project: .project
        case .workgroup: .workgroup
        case .folder: .folder
        }
    }

    /// The key it is kept and synced under: one per thing, whichever device starred it.
    public var key: String {
        switch self {
        case .service(let endpoint): "service:\(endpoint.rawValue.uuidString)"
        case .project(let id): "project:\(id.uuidString)"
        case .workgroup(let id): "workgroup:\(id.uuidString)"
        case .folder(let endpoint, let path): "folder:\(endpoint.rawValue.uuidString):\(path)"
        }
    }

    /// The longest folder path kept.
    public static let maximumPathLength = 4_096

    /// Whether a favourite is well formed: a folder's path is absolute, bounded and without a
    /// control character.
    public var isValid: Bool {
        guard case .folder(_, let path) = self else { return true }
        return path.hasPrefix("/") && path.utf8.count <= Self.maximumPathLength
            && !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}

/// Every non-machine favourite, with when it last changed: the newest change wins per thing, an
/// unfavourite travels too, and on a tie the favourite stays — D49's rule, for the rest of Favorites.
public struct GlassFavoriteItemsPayload: Codable, Equatable, Sendable {
    public struct Mark: Codable, Equatable, Sendable {
        public var item: GlassFavorite
        public var isFavorite: Bool
        public var changedAt: Date
        public init(item: GlassFavorite, isFavorite: Bool, changedAt: Date) {
            self.item = item
            self.isFavorite = isFavorite
            self.changedAt = changedAt
        }
    }

    public static let maximumItems = 5_000

    /// Keyed by `GlassFavorite.key`.
    public var marks: [String: Mark]

    public init(marks: [String: Mark] = [:]) { self.marks = marks }

    public static func replaces(_ candidate: Mark, _ existing: Mark?) -> Bool {
        guard let existing else { return true }
        if candidate.changedAt != existing.changedAt { return candidate.changedAt > existing.changedAt }
        return candidate.isFavorite && !existing.isFavorite
    }
}

extension GlassFavoriteItemsPayload: GlassSettingsSyncPayload {
    public func validate() throws {
        guard marks.count <= Self.maximumItems else {
            throw GlassSettingsSyncError.invalidPayload("too many favourites")
        }
        guard marks.allSatisfy({ $0.key == $0.value.item.key && $0.value.item.isValid }) else {
            throw GlassSettingsSyncError.invalidPayload("a favourite is not well formed")
        }
    }

    public func converged(with other: GlassFavoriteItemsPayload) -> GlassFavoriteItemsPayload {
        var merged = marks
        for (key, mark) in other.marks where Self.replaces(mark, merged[key]) {
            merged[key] = mark
        }
        return GlassFavoriteItemsPayload(marks: merged)
    }
}

public extension GlassSettingsSyncService where Payload == GlassFavoriteItemsPayload {
    static var favoriteItemsStoreKey: String { "shell-favorite-items-envelope-v1" }

    convenience init(favoriteItemsStore store: any GlassSettingsKeyValueStore, writerID: UUID = UUID()) {
        self.init(store: store, writerID: writerID, storeKey: Self.favoriteItemsStoreKey)
    }
}
