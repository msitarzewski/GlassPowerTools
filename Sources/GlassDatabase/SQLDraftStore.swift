//
//  SQLDraftStore.swift
//  Glass Power Tools — GlassDatabase
//
//  Durable SQL drafts. glassdb kept every editor's text in `QueryDocumentTab.text`
//  (`QueryEditorView.swift:347`) and nowhere else, so closing the window or quitting lost it —
//  the one ported defect that loses user work rather than merely lacking a feature (D9).
//
//  A draft belongs to a *connection*, not to a session: `DatabaseSessionManager.connect` mints a
//  fresh `sessionID` per connection attempt (`DatabaseSessionManager.swift:81`), so nothing keyed
//  by it can survive a quit. `DatabaseConnectionConfig.id` is the durable identity — it is what
//  the connection record is stored under (`UserDefaultsKeys.connections`).
//

import Foundation
import os

// MARK: - Records

/// One editor's unsaved SQL, plus enough state to put the cursor back.
struct SQLDraftRecord: Codable, Hashable, Sendable {
    var selection: WorkspaceSelection
    var sql: String
    /// `NSRange` is not `Codable`, and a hand-edited file must not be able to hand SwiftUI an
    /// out-of-range selection. Stored as two integers and clamped on the way out.
    var selectionLocation: Int
    var selectionLength: Int
    var createdAt: Date
    var updatedAt: Date
    /// Whether this text was **typed**, or is the browsing query the app generated.
    ///
    /// A table's SQL pane usually holds generated SQL — `SELECT … LIMIT 100 OFFSET 0` — which the
    /// grid rewrites on every page, filter and sort. `TableDetailView` refuses to overwrite a
    /// draft it believes the user edited, and a restored draft used to come back as an edit
    /// *always*: `QueryDocumentTab(text:)` leaves `savedText` empty, so `hasUnsavedChanges` was
    /// true for the rest of the session. The visible symptom was the pager working while the SQL
    /// above it still said `OFFSET 0` (reported 2026-09-19).
    ///
    /// Decoding a file written before this field treats the draft as generated, because that is
    /// what a table's draft nearly always is; the cost of being wrong is one typed query replaced
    /// by the generated one at the next load, and the cost of the other default is the defect
    /// staying for every table already browsed.
    var isUnsavedEdit = false

    /// The selection clamped to `sql`'s UTF-16 length, which is what `NSRange` indexes.
    var clampedSelection: NSRange {
        let limit = (sql as NSString).length
        let location = min(max(selectionLocation, 0), limit)
        let length = min(max(selectionLength, 0), limit - location)
        return NSRange(location: location, length: length)
    }

    var byteCount: Int { sql.utf8.count }
}

/// The on-disk envelope. glassdb's connection file shipped without a version number and needed
/// one added during the move (see the plan's risk table); this one has had one from the start.
struct SQLDraftFile: Codable, Sendable {
    var version: Int
    var connectionID: UUID
    var drafts: [SQLDraftRecord]

    init(version: Int = SQLDraftStore.currentVersion, connectionID: UUID, drafts: [SQLDraftRecord] = []) {
        self.version = version
        self.connectionID = connectionID
        self.drafts = drafts
    }
}

// MARK: - Store

/// Per-connection draft storage, one JSON file per connection.
///
/// **Not `UserDefaults`, unlike this module's other four persisted collections** (connections,
/// saved queries, query history, mutation audit). Those are bounded by construction — history is
/// capped at 500 entries by `DatabaseSessionManager.configuredHistoryLimit` precisely because the
/// whole defaults domain is materialised into memory at launch. Draft text has no such bound:
/// `SQLTextDocument` accepts imports up to 10 MiB (`QueryEditorView.swift:74`). A file per
/// connection keeps the launch cost at zero and makes eviction a `removeItem`. The read/write
/// shape follows the shell's own file stores (`GlassShellModel.swift:127`,
/// `GlassShellPreferencesStore`), which is where file-backed state in this product already lives.
extension SQLDraftRecord {
    /// **A default value is not a default on decode.** The synthesized decoder requires every
    /// key, so adding `isUnsavedEdit` with `= false` made every draft file written before it
    /// fail to decode — every stored draft on the machine, gone, from a field meant to fix a
    /// cosmetic staleness. Caught by the test that decodes an older file, which is the only
    /// reason it is not in a release.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selection = try container.decode(WorkspaceSelection.self, forKey: .selection)
        sql = try container.decode(String.self, forKey: .sql)
        selectionLocation = try container.decode(Int.self, forKey: .selectionLocation)
        selectionLength = try container.decode(Int.self, forKey: .selectionLength)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isUnsavedEdit = try container.decodeIfPresent(Bool.self, forKey: .isUnsavedEdit) ?? false
    }
}

@MainActor
final class SQLDraftStore {
    static let shared = SQLDraftStore()

    nonisolated static let currentVersion = 1

    /// Caps. Eviction is least-recently-updated first and never touches the record being written,
    /// so the tab you are typing in cannot evict itself. A store that grows forever is its own bug.
    static let maximumDraftsPerConnection = 24
    static let maximumBytesPerConnection = 8 * 1_024 * 1_024
    /// A connection file untouched for this long is deleted on first use. Deleting a *connection*
    /// should also delete its drafts; that hook belongs in `ConnectionManager` and is not wired
    /// yet — see `removeAll(connectionID:)`.
    static let expiry: TimeInterval = 90 * 24 * 60 * 60

    private let directory: URL
    private let debounceInterval: Duration

    /// Read-modify-write happens here, not on disk: everything that touches drafts is
    /// `@MainActor` in one process, so the cache is the serialisation point.
    private var files: [UUID: SQLDraftFile] = [:]
    private var dirty: Set<UUID> = []
    /// A moved caret is not work worth an I/O, and a draft can be megabytes. Range-only changes
    /// wait for the next text edit or for `flush()` — which is what window close and scene
    /// background call — rather than scheduling a write of their own.
    private var caretDirty: Set<UUID> = []
    private var pendingWrites: [UUID: Task<Void, Never>] = [:]
    /// Which workspace instance restored a connection's drafts. A second window on the same
    /// connection ("Open in New Window") must not duplicate every SQL tab into itself.
    private var restoreClaims: [UUID: UUID] = [:]
    private var didPruneExpired = false

    /// - Parameters:
    ///   - directory: the folder holding one JSON file per connection. Defaults to
    ///     `Application Support/GlassPowerTools/SQLDrafts`, beside the shell's own state.
    ///   - debounceInterval: how long a burst of typing is coalesced before it reaches the disk.
    init(directory: URL? = nil, debounceInterval: Duration = .milliseconds(1_200)) {
        self.directory = directory ?? URL.applicationSupportDirectory
            .appendingPathComponent("GlassPowerTools", isDirectory: true)
            .appendingPathComponent("SQLDrafts", isDirectory: true)
        self.debounceInterval = debounceInterval
    }

    // MARK: Restore

    /// The drafts for `connectionID`, claimed by `workspace`.
    ///
    /// Returns them once per claim: the first workspace to ask owns restoration until it releases,
    /// and any other window on the same connection gets an empty array rather than a duplicate set
    /// of tabs. Both windows may still *write* drafts, because writes are per-record upserts.
    func claimDrafts(connectionID: UUID, workspace: UUID) -> [SQLDraftRecord] {
        guard restoreClaims[connectionID] == nil || restoreClaims[connectionID] == workspace else {
            return []
        }
        restoreClaims[connectionID] = workspace
        return file(for: connectionID).drafts.sorted { $0.createdAt < $1.createdAt }
    }

    /// Releases a claim so the workspace can be closed and reopened in the same run.
    func releaseDrafts(connectionID: UUID, workspace: UUID) {
        guard restoreClaims[connectionID] == workspace else { return }
        restoreClaims.removeValue(forKey: connectionID)
    }

    func drafts(for connectionID: UUID) -> [SQLDraftRecord] {
        file(for: connectionID).drafts.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: Write

    /// Upserts one editor's text. Whitespace-only SQL removes the record instead of storing it,
    /// so an untouched ⌘N tab never reaches the disk.
    func record(sql: String, selection: WorkspaceSelection, selectedRange: NSRange,
                connectionID: UUID, isUnsavedEdit: Bool = false, now: Date = Date()) {
        guard !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            remove(selection: selection, connectionID: connectionID)
            return
        }
        var stored = file(for: connectionID)
        var textChanged = true
        var editedChanged = false
        if let index = stored.drafts.firstIndex(where: { $0.selection == selection }) {
            textChanged = stored.drafts[index].sql != sql
            // The flag alone is a change worth storing: the generated query is written and then
            // marked saved in the same pass, and the second write is the one that says it is a
            // baseline rather than an edit.
            editedChanged = stored.drafts[index].isUnsavedEdit != isUnsavedEdit
            guard textChanged || editedChanged
                || stored.drafts[index].selectionLocation != selectedRange.location
                || stored.drafts[index].selectionLength != selectedRange.length else { return }
            stored.drafts[index].sql = sql
            stored.drafts[index].isUnsavedEdit = isUnsavedEdit
            stored.drafts[index].selectionLocation = selectedRange.location
            stored.drafts[index].selectionLength = selectedRange.length
            if textChanged { stored.drafts[index].updatedAt = now }
        } else {
            stored.drafts.append(SQLDraftRecord(
                selection: selection,
                sql: sql,
                selectionLocation: selectedRange.location,
                selectionLength: selectedRange.length,
                createdAt: now,
                updatedAt: now,
                isUnsavedEdit: isUnsavedEdit
            ))
        }
        stored.drafts = Self.pruned(stored.drafts, keeping: selection)
        files[connectionID] = stored
        if textChanged || editedChanged {
            markDirty(connectionID)
        } else {
            caretDirty.insert(connectionID)
        }
    }

    /// Discards a draft. Called when a tab is closed deliberately — closing the *window* must not
    /// reach this, which is the whole point of the store.
    func remove(selection: WorkspaceSelection, connectionID: UUID) {
        var stored = file(for: connectionID)
        let before = stored.drafts.count
        stored.drafts.removeAll { $0.selection == selection }
        guard stored.drafts.count != before else { return }
        files[connectionID] = stored
        markDirty(connectionID)
    }

    /// Every draft for a connection, for when the connection itself is deleted.
    func removeAll(connectionID: UUID) {
        pendingWrites.removeValue(forKey: connectionID)?.cancel()
        files.removeValue(forKey: connectionID)
        dirty.remove(connectionID)
        caretDirty.remove(connectionID)
        restoreClaims.removeValue(forKey: connectionID)
        try? FileManager.default.removeItem(at: fileURL(for: connectionID))
    }

    /// Writes everything pending immediately. Called when the scene leaves the foreground and when
    /// a workspace goes away; a debounced write is otherwise up to `debounceInterval` behind.
    func flush() {
        for task in pendingWrites.values { task.cancel() }
        pendingWrites.removeAll()
        let pending = dirty.union(caretDirty)
        dirty.removeAll()
        caretDirty.removeAll()
        for connectionID in pending { write(connectionID) }
    }

    // MARK: Pruning

    /// Least-recently-updated first, never the record just written.
    static func pruned(_ drafts: [SQLDraftRecord], keeping protected: WorkspaceSelection?) -> [SQLDraftRecord] {
        var kept = drafts
        func dropOldest() -> Bool {
            let candidates = kept.indices.filter { kept[$0].selection != protected }
            guard let victim = candidates.min(by: { kept[$0].updatedAt < kept[$1].updatedAt }) else { return false }
            kept.remove(at: victim)
            return true
        }
        while kept.count > maximumDraftsPerConnection, dropOldest() {}
        while kept.reduce(0, { $0 + $1.byteCount }) > maximumBytesPerConnection, dropOldest() {}
        return kept
    }

    /// Deletes connection files nothing has touched in `expiry`. Runs once per process, on the
    /// first read, so it costs one directory listing.
    private func pruneExpiredFilesIfNeeded(now: Date = Date()) {
        guard !didPruneExpired else { return }
        didPruneExpired = true
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for entry in entries where entry.pathExtension == "json" {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard let modified, now.timeIntervalSince(modified) > Self.expiry else { continue }
            try? manager.removeItem(at: entry)
            if let id = UUID(uuidString: entry.deletingPathExtension().lastPathComponent) {
                files.removeValue(forKey: id)
            }
        }
    }

    // MARK: Disk

    private func fileURL(for connectionID: UUID) -> URL {
        directory.appendingPathComponent(connectionID.uuidString).appendingPathExtension("json")
    }

    private func file(for connectionID: UUID) -> SQLDraftFile {
        pruneExpiredFilesIfNeeded()
        if let cached = files[connectionID] { return cached }
        let loaded = read(connectionID)
        files[connectionID] = loaded
        return loaded
    }

    private func read(_ connectionID: UUID) -> SQLDraftFile {
        let url = fileURL(for: connectionID)
        guard let data = try? Data(contentsOf: url) else {
            return SQLDraftFile(connectionID: connectionID)
        }
        do {
            let decoded = try JSONDecoder().decode(SQLDraftFile.self, from: data)
            // A file from a future version is left where it is rather than overwritten: the
            // drafts in it are user work this build cannot read.
            guard decoded.version <= Self.currentVersion else {
                Logger.database.error("SQL drafts for this connection were written by a newer version and were left unread")
                return SQLDraftFile(connectionID: connectionID)
            }
            return SQLDraftFile(version: Self.currentVersion, connectionID: connectionID, drafts: decoded.drafts)
        } catch {
            Logger.database.error("Could not read SQL drafts: \(error, privacy: .public)")
            return SQLDraftFile(connectionID: connectionID)
        }
    }

    private func markDirty(_ connectionID: UUID) {
        dirty.insert(connectionID)
        caretDirty.remove(connectionID)
        pendingWrites[connectionID]?.cancel()
        let interval = debounceInterval
        pendingWrites[connectionID] = Task { [weak self] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled, let self else { return }
            self.pendingWrites.removeValue(forKey: connectionID)
            guard self.dirty.remove(connectionID) != nil else { return }
            self.write(connectionID)
        }
    }

    private func write(_ connectionID: UUID) {
        guard let stored = files[connectionID] else { return }
        let url = fileURL(for: connectionID)
        do {
            if stored.drafts.isEmpty {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                return
            }
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                // The same class `UserDefaults` gives this module's other persisted collections:
                // readable after the device's first unlock, so a flush from the background never
                // fails, and unreadable to another user of the machine.
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            try JSONEncoder().encode(stored).write(to: url, options: [.atomic])
        } catch {
            Logger.database.error("Could not save SQL drafts: \(error, privacy: .public)")
        }
    }
}
