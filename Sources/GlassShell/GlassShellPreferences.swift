import Foundation
import GlassConnectionKit

/// Shell-owned, per-install preferences that have no home in the shared catalog
/// schema: favorites, last connection time and the last-used service per host,
/// plus this install's stable catalog writer identity. Collections are *not*
/// here — they derive from `HostProfile.tags` exactly as `GlassLibraryProjection`
/// derives them for every app, so a collection made here is visible to the family.
public struct GlassShellPreferences: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public struct HostRecord: Codable, Equatable, Sendable {
        public var isFavorite = false
        public var lastConnected: Date?
        public var lastUsedEndpointID: EndpointID?
        public init() {}
    }

    public var version = Self.currentVersion
    public var writerID = WriterID()
    public var hosts: [HostID: HostRecord] = [:]

    public init() {}

    public subscript(host id: HostID) -> HostRecord {
        get { hosts[id] ?? HostRecord() }
        set { hosts[id] = newValue }
    }
}

/// Atomic JSON persistence; a corrupt or missing file yields fresh defaults and
/// reports it rather than silently discarding the store's writer identity.
public struct GlassShellPreferencesStore: Sendable {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() -> (preferences: GlassShellPreferences, problem: String?) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return (GlassShellPreferences(), nil) }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let decoded = try decoder.decode(GlassShellPreferences.self, from: data)
            guard decoded.version == GlassShellPreferences.currentVersion else {
                return (GlassShellPreferences(), "Preferences were written by a newer build (version \(decoded.version)); starting fresh.")
            }
            return (decoded, nil)
        } catch {
            return (GlassShellPreferences(), "Preferences could not be read (\(error.localizedDescription)); starting fresh.")
        }
    }

    public func save(_ preferences: GlassShellPreferences) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(preferences).write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
