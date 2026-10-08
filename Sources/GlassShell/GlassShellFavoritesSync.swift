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
