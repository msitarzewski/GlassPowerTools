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
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import GlassConnectionKit
import GlassShell
import GlassLayers

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

    public init(defaults: UserDefaults = GlassUITestRun.settingsDefaults) {
        self.defaults = defaults
        payload = Self.load(from: defaults)
        #if DEBUG
        seedForUITestingIfRequested()
        #endif
    }

    #if DEBUG
    /// Makes a project the UI test can open, **inside the app's own container**.
    ///
    /// `--ui-testing --ui-testing-seed-project` creates a small folder in Documents and records it.
    /// The same shape as the shell's `--ui-testing-seed-hosts`, and for a sharper reason: a phone
    /// has no way into the editor except a project, and choosing one means the system file picker,
    /// which a test cannot drive. Seeding it from the host instead does not work — the simulator's
    /// data container is given a new identifier when the app is reinstalled, so a path written
    /// before the install points at a directory that no longer exists. That is not a hypothetical;
    /// it cost an evening, and the app was right to refuse to open it.
    ///
    /// Only alongside `--ui-testing <uuid>` — the per-run identifier the app uses to give the
    /// editor a defaults suite of its own — because the seed replaces the whole list.
    private func seedForUITestingIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "--ui-testing"), arguments.indices.contains(flag + 1),
              UUID(uuidString: arguments[flag + 1]) != nil,
              defaults != .standard,
              arguments.contains("--ui-testing-seed-project"),
              let documents = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                           appropriateFor: nil, create: true)
        else { return }
        // **Replaced, not added to.** `UserDefaults` survives a reinstall while the container that
        // gave the project its path does not, so a list left from an earlier run points at a
        // directory that is gone — and a guard of "only seed when empty" then seeds nothing and
        // leaves the dead record in place. The app is right to refuse to open it; a test fixture
        // has no business asking it to.
        for record in payload.records where !record.isDeleted { forget(record.id) }
        let root = documents.appendingPathComponent("DemoProject", isDirectory: true)
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            try Data("# Demo\n\nA project for checking the editor.\n".utf8)
                .write(to: root.appendingPathComponent("README.md"))
            try Data("let greeting = \"hello\"\nprint(greeting)\n".utf8)
                .write(to: sources.appendingPathComponent("main.swift"))
            // For the viewers and Preview (2026-09-23): a picture, and Markdown with a table, a
            // Mermaid diagram and that picture beside it.
            try Self.seedPNG().write(to: root.appendingPathComponent("logo.png"))
            try Data("""
            # Preview

            | Machine | Services |
            |---|---|
            | alpha | 3 |
            | bravo | 3 |

            ```mermaid
            graph LR
              Library --> Active --> Editor
            ```

            ![logo](logo.png)

            """.utf8).write(to: root.appendingPathComponent("PREVIEW.md"))
            // A logo the way a design tool exports one: a single line of megabytes. The shape that
            // froze the Mac on 2026-09-23; asked for only by the test that opens it.
            // A real file from the host, copied in by the test that names it: the simulator's app
            // can read the Mac's disk, and a user's own file is the one that matters.
            if let index = arguments.firstIndex(of: "--ui-testing-seed-file"), arguments.indices.contains(index + 1) {
                let source = URL(filePath: arguments[index + 1])
                let target = root.appendingPathComponent(source.lastPathComponent)
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.copyItem(at: source, to: target)
            }
            if arguments.contains("--ui-testing-seed-large-svg") {
                var path = "M0 0"
                path.reserveCapacity(700_000)
                for step in 0..<60_000 { path += " L\((step * 37) % 1000) \((step * 91) % 300)" }
                let image = Self.seedPNG().base64EncodedString()
                let embedded = String(repeating: image, count: 1 + 1_200_000 / max(image.count, 1))
                let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" viewBox=\"0 0 1000 300\"><path d=\"\(path) Z\" fill=\"#b5412b\"/><image width=\"200\" height=\"80\" xlink:href=\"data:image/png;base64,\(embedded)\"/></svg>"
                try Data(svg.utf8).write(to: root.appendingPathComponent("wide-logo.svg"))
            }
        } catch { return }
        remember(GlassEditorProject.local(root))
        // A **second real** project, so a test can have two editor sessions open at once — which
        // is the only way to see the session switcher on a phone without a server to connect to.
        if arguments.contains("--ui-testing-seed-second-project") {
            let other = documents.appendingPathComponent("OtherProject", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
                try Data("# Other\n\nThe second project, for the session switcher.\n".utf8)
                    .write(to: other.appendingPathComponent("NOTES.md"))
                remember(GlassEditorProject.local(other))
            } catch { /* the first project is still usable; the test that needs two will say so */ }
        }
        // A second project whose folder is **not** there, only when asked for. Reported
        // 2026-09-18: a project that refuses to open leaves an alert, and the next project's Open
        // did nothing at all — which needs two projects and a failure to reproduce.
        if arguments.contains("--ui-testing-seed-missing-project") {
            remember(GlassEditorProject.local(documents.appendingPathComponent("GoneProject",
                                                                               isDirectory: true)))
        }
    }

    /// A small blue square with a white stripe, drawn rather than carried as bytes.
    private static func seedPNG() -> Data {
        let size = 96
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return Data() }
        context.setFillColor(CGColor(red: 0.04, green: 0.39, blue: 0.84, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 40, y: 12, width: 16, height: 72))
        guard let image = context.makeImage() else { return Data() }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return Data() }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
    #endif

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

    /// The project a folder belongs to, on any of `hostIDs` (one machine can be named more than
    /// one way: This Mac is nil, its own record, and the library machine it is, D86): the project
    /// at that folder, else the nearest one whose folder holds it. A terminal's Open in Editor
    /// (2026-10-20, the owner: "opens the Project with the same server/path or it opens a new
    /// Editor with pwd at the working directory"): a shell in a project's subfolder is still in
    /// that project.
    public func project(containing path: String, on hostIDs: [HostID?]) -> GlassEditorProject? {
        let wanted = GlassEditorProject.normalized(path)
        return payload.records
            .filter { record in !record.isDeleted && hostIDs.contains(record.project.hostID) }
            .map(\.project)
            .filter { project in
                project.path == wanted || project.path == "/"
                    || wanted.hasPrefix(project.path + "/")
            }
            .max { $0.path.count < $1.path.count }
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

    /// Changes one live project's record. Every edit to a stored project goes through here, so
    /// there is one place that stamps `modifiedAt` and one that upserts — the rename and the text
    /// overrides are the same act with a different field.
    public func modify(_ id: GlassEditorProject.ID, at date: Date = Date(),
                       _ change: (inout GlassEditorProject) -> Void) {
        guard var record = payload.records.first(where: { $0.id == id }), !record.isDeleted else { return }
        change(&record.project)
        record.modifiedAt = date
        upsert(record)
    }

    /// Renames a project without moving it: the folder is unchanged, only what it is called here.
    public func rename(_ id: GlassEditorProject.ID, to name: String, at date: Date = Date()) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        modify(id, at: date) { $0.displayName = trimmed }
    }

    /// What this project says about the text. Empty is stored as nil, so a project that has
    /// stopped disagreeing follows the app's defaults again rather than pinning today's values.
    public func setTextOverrides(_ overrides: GlassEditorTextOverrides,
                                 for id: GlassEditorProject.ID, at date: Date = Date()) {
        modify(id, at: date) { $0.textOverrides = overrides.isEmpty ? nil : overrides }
    }

    /// Removes a project from the list. A tombstone rather than a deletion, so a device that is
    /// offline today cannot put it back tomorrow. **The folder is not touched** — a project is a
    /// name for a place, and forgetting the name deletes nothing.
    public func forget(_ id: GlassEditorProject.ID, at date: Date = Date()) {
        guard var record = payload.records.first(where: { $0.id == id }) else { return }
        record.deletedAt = date
        upsert(record)
        // The way back into the folder goes with the last record that names it.
        if !projects.contains(where: { $0.path == record.project.path }) {
            forgetBookmark(forPath: record.project.path)
        }
        // And what its window kept on this device goes with the project.
        forgetWindow(of: id)
    }

    // MARK: This device's way back in

    /// Bookmarks for folders picked from Files, by path — **this device's only, and never
    /// synchronized.**
    ///
    /// A folder chosen from Files on an iPad or a headset can be read only with the access the
    /// picker granted, and that access does not survive a relaunch: the project stayed in the list
    /// and its Open said the folder was gone. A bookmark is how the access comes back (decided
    /// 2026-10-08). It is this device's permission for a folder on this device, so it means nothing
    /// on any other, and it is kept under its own key beside the list rather than in the payload.
    static let bookmarksDefaultsKey = "com.glasspowertools.editor.projects.device-bookmarks"

    private var bookmarks: [String: Data] {
        defaults.dictionary(forKey: Self.bookmarksDefaultsKey) as? [String: Data] ?? [:]
    }

    /// Keeps a way back into a folder that was opened with granted access. Made while that access
    /// is held, which is the only time it can be.
    func keepBookmark(of url: URL, forPath path: String) {
        guard let data = try? url.bookmarkData(options: .minimalBookmark,
                                               includingResourceValuesForKeys: nil,
                                               relativeTo: nil) else { return }
        var stored = bookmarks
        stored[GlassEditorProject.normalized(path)] = data
        defaults.set(stored, forKey: Self.bookmarksDefaultsKey)
    }

    /// The folder at `path` as the bookmark finds it, and whether the bookmark wants remaking.
    /// Nil when there is none, which is every folder that never needed one.
    func bookmarkedURL(forPath path: String) -> (url: URL, isStale: Bool)? {
        guard let data = bookmarks[GlassEditorProject.normalized(path)] else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        return (url, isStale)
    }

    func forgetBookmark(forPath path: String) {
        var stored = bookmarks
        guard stored.removeValue(forKey: GlassEditorProject.normalized(path)) != nil else { return }
        defaults.set(stored, forKey: Self.bookmarksDefaultsKey)
    }

    // MARK: This device's windows

    /// Each project's editor window as this device keeps it — the window's own settings (W23) — by
    /// project. **This device's only, and never synchronized**, kept beside the list rather than in
    /// its payload, as the bookmarks are: what a window overrides, Settings ▸ Editor and
    /// Appearance, is each device's own (`GlassEditorWindowSettings`).
    static let windowsDefaultsKey = "com.glasspowertools.editor.projects.device-windows"

    @ObservationIgnored private lazy var windows = GlassEditorWindowRecords.decoded(
        from: defaults.data(forKey: Self.windowsDefaultsKey))

    /// What the window showing this project set for itself the last time, on this device.
    public func windowSettings(for id: GlassEditorProject.ID) -> GlassWindowOverrides {
        windows.settings(for: id)
    }

    /// Keeps what the window showing this project sets, for the next time it opens on this device.
    /// Only for a project in the list: one removed from it, still open in a window, keeps its
    /// settings for as long as the window is open, as a window with no project does.
    public func setWindowSettings(_ settings: GlassWindowOverrides, for id: GlassEditorProject.ID) {
        guard payload.records.contains(where: { $0.id == id && !$0.isDeleted }) || settings.isEmpty else { return }
        var updated = windows
        updated.set(settings, for: id)
        guard updated != windows else { return }
        windows = updated
        persistWindows()
    }

    private func forgetWindow(of id: GlassEditorProject.ID) {
        guard windows.byProject[id] != nil else { return }
        windows.forget(id)
        persistWindows()
    }

    private func persistWindows() {
        guard !windows.byProject.isEmpty, let data = windows.encoded() else {
            defaults.removeObject(forKey: Self.windowsDefaultsKey)
            return
        }
        defaults.set(data, forKey: Self.windowsDefaultsKey)
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
