//
//  GlassEditorProjectLibrary.swift
//  Glass Power Tools — GlassEditor
//
//  The list of projects, kept across launches and carried between devices.
//
//  A project is `(hostID, path)` (see `GlassEditorProject`), which is why this can sync at all:
//  the host id is the catalog's, so the same record means the same folder on the same machine
//  wherever it is read. What travels is the *name of a place*, never a file and never a byte of
//  content.
//
//  It travels over `GlassSettingsSyncService`, the shell's one synchronization service, whose
//  whole design is that a capability supplies a payload and a store key. The terminal's themes
//  are the existing payload and this one has the same shape, tombstones included: a record that
//  is deleted here must stay deleted when a device that never saw the deletion publishes next.
//

import Foundation
import GlassConnectionKit
import GlassShell

/// One project, with the metadata a merge needs. Deletion is a tombstone rather than a removal —
/// an offline device that still has the project would otherwise resurrect it simply by being the
/// next writer.
public struct GlassEditorProjectRecord: Codable, Equatable, Identifiable, Sendable {
    public var project: GlassEditorProject
    public var modifiedAt: Date
    public var deletedAt: Date?

    public var id: GlassEditorProject.ID { project.id }
    public var isDeleted: Bool { deletedAt != nil }

    public init(project: GlassEditorProject, modifiedAt: Date = Date(), deletedAt: Date? = nil) {
        self.project = project
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
    }
}

/// The synchronized project list.
public struct GlassEditorProjectsPayload: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    /// A cap the key-value store's 1 MB quota makes necessary, and well past what a person opens.
    public static let maximumRecordCount = 256

    public let schemaVersion: Int
    public var records: [GlassEditorProjectRecord]

    public init(schemaVersion: Int = Self.currentSchemaVersion,
                records: [GlassEditorProjectRecord] = []) {
        self.schemaVersion = schemaVersion
        self.records = records
    }

    /// The projects a device should show: undeleted, newest first.
    public var projects: [GlassEditorProject] {
        records.filter { !$0.isDeleted }
            .sorted { $0.project.openedAt > $1.project.openedAt }
            .map(\.project)
    }

    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw GlassSettingsSyncError.unsupportedPayloadSchema(schemaVersion)
        }
        guard records.count <= Self.maximumRecordCount else {
            throw GlassSettingsSyncError.invalidPayload(
                "At most \(Self.maximumRecordCount) projects can be synchronized."
            )
        }
        var seen = Set<GlassEditorProject.ID>()
        for record in records {
            guard seen.insert(record.id).inserted else {
                throw GlassSettingsSyncError.invalidPayload("Project identifiers must be unique.")
            }
            guard !record.project.path.isEmpty, record.project.path.hasPrefix("/") else {
                throw GlassSettingsSyncError.invalidPayload("A project's path must be absolute.")
            }
            guard record.project.path == GlassEditorProject.normalized(record.project.path) else {
                throw GlassSettingsSyncError.invalidPayload(
                    "A project's path must carry no trailing separator."
                )
            }
            guard record.modifiedAt.timeIntervalSinceReferenceDate.isFinite,
                  record.deletedAt?.timeIntervalSinceReferenceDate.isFinite != false else {
                throw GlassSettingsSyncError.invalidPayload("Project change dates must be finite.")
            }
        }
    }

    /// Unions both sides by project id, newest change winning, so publishing from a stale device
    /// keeps the other's records and its tombstones.
    public func converged(with other: Self) -> Self {
        var merged = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        for record in other.records {
            guard let existing = merged[record.id] else {
                merged[record.id] = record
                continue
            }
            if Self.isNewer(record, than: existing) { merged[record.id] = record }
        }
        return Self(records: merged.values.sorted { $0.id.uuidString < $1.id.uuidString })
    }

    /// A deletion is a change like any other, so a tombstone written after an edit wins and an
    /// edit made after a deletion brings the project back — the last thing the user did, either
    /// way. Ties break on the identifier so every device reaches the same answer.
    private static func isNewer(_ candidate: GlassEditorProjectRecord,
                                than existing: GlassEditorProjectRecord) -> Bool {
        let candidateDate = max(candidate.modifiedAt, candidate.deletedAt ?? .distantPast)
        let existingDate = max(existing.modifiedAt, existing.deletedAt ?? .distantPast)
        if candidateDate != existingDate { return candidateDate > existingDate }
        return candidate.id.uuidString > existing.id.uuidString
    }
}

extension GlassEditorProjectsPayload: GlassSettingsSyncPayload {}

public extension GlassSettingsSyncService where Payload == GlassEditorProjectsPayload {
    static var projectsStoreKey: String { "editor-projects-envelope-v1" }

    /// Labelled differently from the designated initializer so this forwards to it rather than
    /// to itself.
    convenience init(projectStore store: any GlassSettingsKeyValueStore, writerID: UUID = UUID()) {
        self.init(store: store, writerID: writerID, storeKey: Self.projectsStoreKey)
    }
}

/// Every project this person has opened, on any of their devices.
///
/// One list, held once. A window's `GlassEditorWorkspace` owns what is *open in that window*; this
/// owns what *exists*, which is why closing a window no longer forgets a project. Local storage is
/// `UserDefaults`, the same shape `GlassEditorPreferences` uses for recents, and the iCloud half is
/// the shell's sync service — attached rather than required, so the list works unchanged on a
/// device with no account.
@MainActor @Observable
public final class GlassEditorProjectLibrary {

    /// Undeleted projects, newest first. What a panel lists.
    public var projects: [GlassEditorProject] { payload.projects }

    public private(set) var payload = GlassEditorProjectsPayload()
    public private(set) var syncStatus: GlassSettingsSyncStatus = .disabled

    static let defaultsKey = "com.glasspowertools.editor.projects"

    private let defaults: UserDefaults
    private var sync: GlassSettingsSyncService<GlassEditorProjectsPayload>?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        payload = Self.load(from: defaults)
    }

    // MARK: Reading

    /// The record for a folder on a machine, if it is already a project. Compared on the
    /// normalized path, because that is the only spelling a project is ever stored in.
    public func project(at path: String, on hostID: HostID?) -> GlassEditorProject? {
        let wanted = GlassEditorProject.normalized(path)
        return payload.records
            .filter { !$0.isDeleted }
            .first { $0.project.path == wanted && $0.project.hostID == hostID }?
            .project
    }

    // MARK: Writing

    /// Records that a project was opened, adding it or moving it to the front.
    ///
    /// Opening the same folder twice is one project, not two — the same rule `openProject` applies
    /// inside a window, applied to the list that outlives it.
    @discardableResult
    public func remember(_ project: GlassEditorProject, at date: Date = Date()) -> GlassEditorProject {
        var stored = project
        if let existing = self.project(at: project.path, on: project.hostID) {
            stored.id = existing.id
        }
        stored.openedAt = date
        upsert(GlassEditorProjectRecord(project: stored, modifiedAt: date))
        return stored
    }

    /// Renames a project without moving it: the folder is unchanged, only what it is called here.
    public func rename(_ id: GlassEditorProject.ID, to name: String, at date: Date = Date()) {
        guard var record = payload.records.first(where: { $0.id == id }), !record.isDeleted else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        record.project.displayName = trimmed
        record.modifiedAt = date
        upsert(record)
    }

    /// Removes a project from the list. A tombstone rather than a deletion, so a device that is
    /// offline today cannot put it back tomorrow. **The folder is not touched** — a project is a
    /// name for a place, and forgetting the name deletes nothing.
    public func forget(_ id: GlassEditorProject.ID, at date: Date = Date()) {
        guard var record = payload.records.first(where: { $0.id == id }) else { return }
        record.deletedAt = date
        upsert(record)
    }

    private func upsert(_ record: GlassEditorProjectRecord) {
        var records = payload.records
        records.removeAll { $0.id == record.id }
        records.append(record)
        // The cap drops the coldest tombstones first: a live project must never be evicted by
        // bookkeeping the user cannot see.
        if records.count > GlassEditorProjectsPayload.maximumRecordCount {
            let ordered = records.sorted { lhs, rhs in
                if lhs.isDeleted != rhs.isDeleted { return !lhs.isDeleted }
                return lhs.modifiedAt > rhs.modifiedAt
            }
            records = Array(ordered.prefix(GlassEditorProjectsPayload.maximumRecordCount))
        }
        payload = GlassEditorProjectsPayload(records: records)
        persist()
        push()
    }

    // MARK: Storage

    private func persist() {
        guard let data = try? Self.encoder.encode(payload) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func load(from defaults: UserDefaults) -> GlassEditorProjectsPayload {
        guard let data = defaults.data(forKey: defaultsKey),
              let decoded = try? decoder.decode(GlassEditorProjectsPayload.self, from: data),
              (try? decoded.validate()) != nil
        else { return GlassEditorProjectsPayload() }
        return decoded
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    // MARK: Synchronization

    /// Attaches the list to iCloud. Optional by construction: without this the library is a local
    /// one and every other method behaves identically.
    public func startSynchronizing(
        with service: GlassSettingsSyncService<GlassEditorProjectsPayload>
    ) async {
        sync = service
        await service.start(
            onMerge: { [weak self] incoming in
                guard let self else { return }
                self.payload = self.payload.converged(with: incoming)
                self.persist()
            },
            onStatusChange: { [weak self] status, _ in
                self?.syncStatus = status
            }
        )
        push()
    }

    private func push() {
        guard let sync else { return }
        let payload = payload
        Task { try? await sync.push(payload) }
    }
}
