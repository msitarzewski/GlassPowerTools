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
        /// When the favourite last changed, here or on another device — its sync clock
        /// (2026-10-08). Nil for one set before favourites synced.
        public var favoriteChangedAt: Date?
        public var lastConnected: Date?
        public var lastUsedEndpointID: EndpointID?
        public init() {}
    }

    /// One connection made on this device: when, to which machine, which kind of service — nothing
    /// else (D41). Kept here because these preferences never leave the device.
    public struct ConnectionEvent: Codable, Equatable, Sendable {
        public var date: Date
        public var hostID: HostID
        public var kind: HostServiceKind
        public init(date: Date, hostID: HostID, kind: HostServiceKind) {
            self.date = date; self.hostID = hostID; self.kind = kind
        }
    }

    /// Bounds on the history: the overview looks back 90 days.
    public static let historyLimit = 2_000
    public static let historyWindow: TimeInterval = 90 * 24 * 60 * 60

    public var version = Self.currentVersion
    public var writerID = WriterID()
    public var hosts: [HostID: HostRecord] = [:]
    /// Optional so a file written before the history existed still decodes.
    public var connectionHistory: [ConnectionEvent]?

    /// Adds a connection, dropping what falls outside the window or over the limit.
    public mutating func recordConnection(_ event: ConnectionEvent) {
        var history = connectionHistory ?? []
        history.append(event)
        let cutoff = event.date.addingTimeInterval(-Self.historyWindow)
        history.removeAll { $0.date < cutoff }
        if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
        connectionHistory = history
    }

    public init() {}

    public subscript(host id: HostID) -> HostRecord {
        get { hosts[id] ?? HostRecord() }
        set { hosts[id] = newValue }
    }
}

/// Atomic JSON persistence. A file that cannot be read is **never overwritten**: the store
/// reports why, the model stays read-only until the user explicitly resets, and a reset moves the
/// unreadable file aside first. Protected-before-first-unlock reads and downgrades are both
/// distinguished from corruption so a routine launch cannot destroy favorites or the writer ID.
public struct GlassShellPreferencesStore: Sendable {
    public enum LoadOutcome: Equatable, Sendable {
        /// No file yet: defaults, writable.
        case missing
        /// Read and decoded.
        case loaded
        /// The file exists but could not be read because the process may not read it yet
        /// (data protection before first unlock, or permissions). Retry later; do not write.
        case unavailable(String)
        /// The file exists but is not valid; do not write until an explicit reset.
        case corrupt(String)
        /// Written by a newer build; do not write until an explicit reset.
        case newerVersion(Int)

        /// Whether the model may persist over this file.
        public var isWritable: Bool { self == .missing || self == .loaded }
        public var problem: String? {
            switch self {
            case .missing, .loaded: nil
            case .unavailable(let why): "Preferences are not readable yet (\(why)). Favorites and recent services are read-only until they can be."
            case .corrupt(let why): "Preferences could not be read (\(why)). Favorites and recent services are read-only; reset them in Settings to start fresh."
            case .newerVersion(let v): "Preferences were written by a newer build (version \(v)). They are read-only in this build."
            }
        }
    }

    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() -> (preferences: GlassShellPreferences, outcome: LoadOutcome) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return (GlassShellPreferences(), .missing) }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            return (GlassShellPreferences(), Self.isAvailabilityError(error)
                    ? .unavailable(error.localizedDescription) : .corrupt(error.localizedDescription))
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            // Version first, so a newer schema that no longer decodes is still reported as newer.
            if let probe = try? JSONDecoder().decode(VersionProbe.self, from: data),
               probe.version > GlassShellPreferences.currentVersion {
                return (GlassShellPreferences(), .newerVersion(probe.version))
            }
            let decoded = try decoder.decode(GlassShellPreferences.self, from: data)
            return (decoded, .loaded)
        } catch {
            return (GlassShellPreferences(), .corrupt(error.localizedDescription))
        }
    }

    public func save(_ preferences: GlassShellPreferences) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        // No secrets here, and it is read at launch: readable after first unlock.
        try encoder.encode(preferences).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Moves an unreadable file out of the way so a fresh file can be written without losing the
    /// evidence. Returns the new location, or nil if there was nothing to move.
    @discardableResult
    public func setAside() throws -> URL? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let aside = fileURL.appendingPathExtension("unreadable-\(stamp)")
        try FileManager.default.moveItem(at: fileURL, to: aside)
        return aside
    }

    private struct VersionProbe: Decodable { let version: Int }

    /// Data-protection-before-unlock and permission failures, as opposed to bad content.
    static func isAvailabilityError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain {
            return ns.code == NSFileReadNoPermissionError || ns.code == CocoaError.fileReadNoPermission.rawValue
                || (ns.underlyingErrors.first.map(isAvailabilityError) ?? false)
        }
        if ns.domain == NSPOSIXErrorDomain { return ns.code == Int(EACCES) || ns.code == Int(EPERM) }
        return false
    }
}
