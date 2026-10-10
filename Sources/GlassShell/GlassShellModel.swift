import GlassLayers
import Foundation
import OSLog
import Observation
import GlassConnectionKit
import GlassHostCatalog
import GlasSecretStore

public enum GlassShellError: LocalizedError, Equatable {
    case hostNotFound(HostID)
    case serviceNotFound(EndpointID)
    case invalidName
    case preferencesReadOnly
    /// The device's own host cannot be deleted (D8): it is not a record the user created, and
    /// removing it would take its saved databases with it.
    case localHostNotRemovable
    /// A built-in local service has nothing stored behind it, so there is nothing to edit or
    /// remove. See `GlassCapability.builtInLocalServices()`.
    case builtInServiceNotEditable(String)
    /// The local host has no address and never asks for one (D8).
    case localHostHasNoAddress

    public var errorDescription: String? {
        switch self {
        case .hostNotFound: "That host is no longer in the library."
        case .serviceNotFound: "That service is no longer on the host."
        case .invalidName: "Enter a name."
        case .preferencesReadOnly: "Favorites and recent services are read-only because the preferences file could not be read. Quit and reopen the app to try again."
        case .localHostNotRemovable: "\(GlassLocalHost.displayName) is this device and is always in the library. Remove its services instead."
        case .builtInServiceNotEditable(let name): "\(name) is built in to this device. There is nothing to configure and nothing to remove."
        case .localHostHasNoAddress: "\(GlassLocalHost.displayName) is this device, so it has no address to set."
        }
    }

    /// User-facing text for any error the shell surfaces. The kit's validation and catalog errors
    /// carry no `LocalizedError` text of their own, so they are mapped here; everything else
    /// keeps its own description.
    public static func message(for error: Error) -> String {
        switch error {
        case let error as GlassShellError:
            return error.localizedDescription
        case let error as HostProfileError:
            switch error {
            case .invalidName: return "The name is empty or longer than 1,024 bytes."
            case .invalidAlias: return "An alias is empty or longer than 1,024 bytes."
            case .invalidTag: return "A collection name is empty or longer than 1,024 bytes."
            case .tooManyEntries: return "Too many entries: a host allows up to 64 aliases, 64 collections and 128 services."
            case .duplicateService: return "That service is already on this host."
            case .invalidTimestamp: return "The host record has an invalid timestamp."
            case .invalidAddress: return "The address must be a hostname or an IP address, with no user, port or spaces."
            case .unsupportedVersion(let v): return "The host record uses schema version \(v), which this build does not understand."
            }
        case let error as HostCatalogError:
            switch error {
            case .unsupportedVersion(let v): return "The host library uses schema version \(v), which this build does not understand. Update the app; nothing was changed."
            case .tooLarge: return "The host library is too large to load safely (more than 8 MB or 10,000 hosts). Nothing was changed."
            case .duplicateHost: return "A host with that identity already exists."
            case .endpointAlreadyPaired: return "That service is already attached to a host."
            case .endpointNotFound: return "That service is no longer on the host."
            case .hostNotFound: return "That host is no longer in the library."
            case .hostDeleted: return "That host was deleted; restore it before editing."
            case .fileLockFailed(let code): return "The host library is busy in another app (lock error \(code)). Try again in a moment."
            }
        default:
            return error.localizedDescription
        }
    }
}

/// The shell's one model: the shared host catalog, shell preferences, the
/// credential boundary configuration and routing into capabilities.
/// Adapted from glassDT's `DesktopAppModel`, minus everything that existed only
/// to keep three processes agreeing (dual catalogs, publication, deletion outbox,
/// pairing). One catalog, one writer, one store.
@MainActor @Observable
public final class GlassShellModel: GlassServiceStore {
    public static let sharedContainerIdentifier = "group.sh.glas.shared"
    public static let catalogRelativePath = "GlassHostCatalog/hosts.json"

    /// A host the library should show the next time it is looked at, and then forget.
    ///
    /// **Where a capability hands you back to.** Leaving a database on a phone returned to the
    /// top of the connection list, which is not where the user came from — they came from *that
    /// machine*, and its other services are the reason they are going back (reported
    /// 2026-09-19). Every capability that replaces the library on a phone wants this; the
    /// database is the first to use it.
    public var hostToShow: HostID?
    /// A library panel something asked to be shown — the ⚡ asking for **Active**. The library
    /// view observes it, opens the panel, and clears it. Same shape as `hostToShow`.
    public var panelToShow: String?
    /// Sessions running on hosts that this device is not showing (D44), as last asked. Active
    /// asks when it appears and when it is refreshed; the library when it appears and when the
    /// app comes back, unless the last answer is recent (`refreshRunningSessionsIfDue`).
    public internal(set) var runningSessions: [GlassRunningSession] = []
    /// The machines that same ask could not reach without a prompt, and why (W6).
    public internal(set) var uncheckedMachines: [GlassUncheckedMachine] = []
    public internal(set) var isCheckingRunningSessions = false
    /// When the machines last answered what runs on them; nil before the first answer.
    var runningSessionsCheckedAt: ContinuousClock.Instant?
    /// Connections handed to a capability that has not reported back yet, and when each began
    /// (W29). Removed on the capability's one report, whatever it says.
    private(set) var connectAttempts: [UUID: ContinuousClock.Instant] = [:]
    /// When the oldest unanswered connection began: while one waits, the headset's Connections
    /// window does not shrink into its orb under the person who just pressed Connect.
    public var connectingSince: ContinuousClock.Instant? { connectAttempts.values.min() }

    public func showHost(_ id: HostID) { hostToShow = id }

    /// Asks the library to open one of its sidebar panels — Active for the ⚡, Workgroups for its
    /// menu items. The library opens it and clears the request, so asking twice opens it twice;
    /// a Connections window opened to show it picks it up as it appears.
    public func showPanel(_ id: String) { panelToShow = id }

    /// The library's hosts: catalog records that describe the same machine, consolidated
    /// (see `GlassShellHostGrouping`). Never written back as one record before Stage 6.
    public private(set) var hosts: [GlassShellHost] = []
    /// The catalog as stored, one record per publishing app and endpoint. For diagnostics.
    public private(set) var records: [HostProfile] = []
    public private(set) var isLoaded = false
    public var errorMessage: String?
    public private(set) var hasSharedContainer: Bool
    public private(set) var hostLibraryStatus: String
    public private(set) var preferencesProblem: String?
    /// True while the preferences file exists but cannot be trusted or read; nothing is written
    /// over it until `resetPreferences()` or a later successful read.
    public private(set) var preferencesReadOnly = false

    /// Why the device's own host is missing from the library, when it is. Nil in the normal case.
    /// Surfaced in Settings rather than as an alert: the rest of the library still works, and
    /// `load()` runs on every activation, so an alert would nag on every switch back to the app.
    public private(set) var localHostProblem: String?

    public let storageDirectory: URL
    public private(set) var catalog: HostCatalogStore
    /// The device's own host (D8), kept in this app's private storage and **never** in the App
    /// Group file the three source applications also read: a record they cannot open has no
    /// business appearing in their libraries, and the device's host is local to the device.
    public let localCatalog: HostCatalogStore
    /// Mirrored like `catalogFileURL`, so views and tests need not hop to the actor.
    public let localCatalogFileURL: URL
    /// The stored local record, once `load()` has read or created it.
    public private(set) var localRecord: HostProfile?
    /// Mirrored here so views and tests need not hop to the actor.
    public private(set) var catalogFileURL: URL
    public let writerID: WriterID
    public let layers: GlassLayerStore
    public let registry: GlassCapabilityRegistry
    public let secretConfiguration: SecretStoreConfiguration

    private let preferencesStore: GlassShellPreferencesStore
    private var preferences: GlassShellPreferences

    /// - Parameters:
    ///   - storageDirectory: per-app state (preferences, fallback catalog). Defaults to
    ///     Application Support/GlassPowerTools.
    ///   - sharedContainerURL: the App Group container. `nil` resolves the real one;
    ///     tests pass a temporary directory and never touch the real group.
    ///   - accessGroup: Keychain access group for `SecretStoreConfiguration`.
    public init(storageDirectory: URL? = nil, sharedContainerURL: URL? = nil,
                resolveSharedContainer: Bool = true, accessGroup: String? = nil,
                layers: GlassLayerStore, registry: GlassCapabilityRegistry = GlassCapabilityRegistry()) {
        let directory = storageDirectory ?? URL.applicationSupportDirectory.appendingPathComponent("GlassPowerTools", isDirectory: true)
        self.storageDirectory = directory
        self.layers = layers
        self.registry = registry
        self.preferencesStore = GlassShellPreferencesStore(fileURL: directory.appendingPathComponent("shell-preferences.json"))
        let loaded = GlassShellPreferencesStore(fileURL: directory.appendingPathComponent("shell-preferences.json")).load()
        let writerID = loaded.preferences.writerID
        self.preferences = loaded.preferences
        self.preferencesProblem = loaded.outcome.problem
        self.preferencesReadOnly = !loaded.outcome.isWritable
        self.preferencesUnavailable = { if case .unavailable = loaded.outcome { true } else { false } }()

        let shared = sharedContainerURL ?? (resolveSharedContainer
            ? FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.sharedContainerIdentifier) : nil)
        self.writerID = writerID
        // Always the app's own directory, never `shared`: that is the whole point (D8).
        localCatalogFileURL = directory.appendingPathComponent(GlassLocalHost.storeRelativePath)
        localCatalog = HostCatalogStore(fileURL: localCatalogFileURL, writerID: writerID)
        if let shared {
            let fileURL = shared.appendingPathComponent(Self.catalogRelativePath)
            catalogFileURL = fileURL
            catalog = HostCatalogStore(fileURL: fileURL, writerID: writerID)
            hasSharedContainer = true
            hostLibraryStatus = "The host library is kept in the app group container on this device."
        } else {
            let fileURL = directory.appendingPathComponent(Self.catalogRelativePath)
            catalogFileURL = fileURL
            catalog = HostCatalogStore(fileURL: fileURL, writerID: writerID)
            hasSharedContainer = false
            hostLibraryStatus = "The shared App Group is unavailable, so hosts are kept in this app only. Check the group.sh.glas.shared entitlement and signing."
        }
        // D18/D21: on by default, so a host defined on one device is usable from the next.
        secretConfiguration = SecretStoreConfiguration(serviceNamePrefix: "sh.glas", accessGroup: accessGroup,
                                                       useDataProtectionKeychain: true,
                                                       mobilityPolicy: .iCloudKeychain)
    }

    /// Set when the file was unreadable for availability reasons (protected before first
    /// unlock); `load()` retries it, and a successful read lifts read-only.
    private var preferencesUnavailable = false

    /// Retries an unavailable preferences file. Never overwrites; only adopts a successful read.
    public func reloadPreferencesIfUnavailable() {
        guard preferencesReadOnly, preferencesUnavailable else { return }
        let loaded = preferencesStore.load()
        guard loaded.outcome.isWritable else {
            preferencesProblem = loaded.outcome.problem
            preferencesUnavailable = { if case .unavailable = loaded.outcome { true } else { false } }()
            return
        }
        preferences = loaded.preferences
        preferencesProblem = nil
        preferencesReadOnly = false
        preferencesUnavailable = false
    }

    /// The user's explicit choice to start fresh: the unreadable file is moved aside, not deleted.
    public func resetPreferences() throws {
        try preferencesStore.setAside()
        preferences = GlassShellPreferences()
        preferencesProblem = nil
        preferencesReadOnly = false
        preferencesUnavailable = false
        try preferencesStore.save(preferences)
    }

    // MARK: Loading

    public func load() async {
        reloadPreferencesIfUnavailable()
        do {
            #if DEBUG
            try await seedForUITestingIfRequested()
            #endif
            records = try await catalog.snapshot()
            // The device's own host is read **before** the library is published, not after.
            // Publishing `group(records)` here first showed a library with no "This Mac" in it and
            // then inserted the row a moment later, and a row inserted into a list that has already
            // been laid out keeps the height it was first measured at — which is how the local row
            // ended up 24pt tall with its Connect button sliced off at the separator, while every
            // other row was 51pt (measured out of the running app, 2026-09-16). One projection,
            // published once, complete.
            await loadLocalHost()
            rebuildProjection()
            // D19: pull the library from the user's other devices before showing it. Deliberately
            // awaited rather than fired and forgotten — a host added on the Vision Pro should be
            // present when the Mac's library first appears, not arrive a moment later and move
            // under the pointer. It fails quietly: an unavailable iCloud account is a normal state,
            // not an error the user caused, and the local catalog is complete on its own.
            await synchronizeCatalog()
            // Preferences keyed on a member record move to the canonical id **while the group
            // still lists its members** — a moment later they are one record and the member id
            // is a tombstone nobody can look up.
            if !Self.isSyncDryRun {
                migratePreferencesToCanonicalHosts()
                // Two devices that each set the same machine up become one record here, not two
                // rows' worth of services under one name (2026-09-21).
                await consolidateDuplicateHosts()
            }
            isLoaded = true
            errorMessage = nil
            // Only now can a capability read its own records honestly: until `isLoaded`, every
            // configuration read answers "nothing". Capabilities that keep an in-memory index
            // build it here. See `GlassCapability.catalogDidLoad()`.
            notifyCapabilitiesCatalogLoaded()
            await adoptKnownAddresses()
        } catch {
            isLoaded = true
            notifyCapabilitiesCatalogLoaded()
            if hasSharedContainer, Self.isPermissionDenied(error) {
                // The container resolves but the sandbox refuses it: the App Group entitlement is
                // not granted by this build's provisioning profile. Degrade to the private
                // catalog and say so where the user will see it, instead of alerting every launch.
                switchToLocalCatalog(reason: "This build is not allowed to use the shared host library "
                    + "(the App Group entitlement is not granted by its provisioning profile), so hosts are "
                    + "kept in this app only until it is signed with the group.")
                await load()
                return
            }
            errorMessage = "The host library could not be read: \(GlassShellError.message(for: error))"
        }
    }

    /// The library's list: the catalog's machines, with the device's own at the head.
    ///
    /// **One place, because the local host is not in the catalog.** It lives in its own store (D8)
    /// and is *inserted* into the projection, so any code that rebuilds `hosts` from
    /// `GlassShellHostGrouping.group(records)` alone silently drops it. That is exactly what
    /// happened on 2026-09-16: the sync's post-apply rebuild had been unreachable while a tombstone
    /// was throwing before it, and the moment the sync started working again, "This Mac"
    /// disappeared from the library.
    private func rebuildProjection() {
        var grouped = GlassShellHostGrouping.group(records)
        if let localRecord {
            grouped.insert(GlassShellHost(local: localRecord, builtInServices: registry.builtInLocalServices),
                           at: 0)
        }
        hosts = grouped
    }

    /// Told after every load, including a failed one: a capability that cannot read its records
    /// has to learn that too, rather than sitting on an empty list it believes is the truth.
    private func notifyCapabilitiesCatalogLoaded() {
        for capability in registry.registered { capability.catalogDidLoad() }
    }

    // MARK: The device's own host (D8)

    /// Reads the device's host from its own store, creating it the first time, and puts it at the
    /// head of the library: the machine you are holding comes before the ones you reach. It never
    /// goes through `GlassShellHostGrouping`, so it can never merge with a discovered machine that
    /// happens to share its name.
    private func loadLocalHost() async {
        do {
            let stored = try await localCatalog.snapshot()
            let record: HostProfile
            if let existing = stored.first(where: { $0.id == GlassLocalHost.id }) {
                record = existing
            } else {
                record = try HostProfile(id: GlassLocalHost.id, displayName: GlassLocalHost.displayName,
                                         lastWriterID: writerID)
                try await localCatalog.upsert(record)
            }
            #if DEBUG
            try await seedLocalServicesForUITestingIfRequested(on: record)
            #endif
            let current = (try await localCatalog.snapshot()).first { $0.id == GlassLocalHost.id } ?? record
            localRecord = current
            localHostProblem = nil
            rebuildProjection()
        } catch {
            // The library is still usable without it, so this is reported rather than thrown:
            // silence would be the honest-status failure, an alert on every activation would be
            // noise. Settings says what happened.
            localRecord = nil
            localHostProblem = "\(GlassLocalHost.displayName) is not in the library: its record could not be read or created (\(GlassShellError.message(for: error)))."
        }
    }

    /// True for the device's own host, for any of its ids.
    public func isLocalHost(_ id: HostID) -> Bool { id == GlassLocalHost.id }

    /// The local host, when it loaded.
    public var localHost: GlassShellHost? { hosts.first { $0.isLocal } }

    /// The library minus this device: the machines that came from the shared catalog. What
    /// diagnostics about that file should count, and what a test about it should assert on.
    // MARK: - Catalog synchronization (D19)

    /// The remote half of the library. Nil until `enableCatalogSync` supplies one, so a build or a
    /// test that has no business talking to CloudKit does not.
    private var catalogBackend: (any GlassCatalogSyncBackend)?
    private var remoteChangeTask: Task<Void, Never>?
    public private(set) var catalogSyncStatus: GlassCatalogSyncStatus = .idle
    /// What the last completed sync moved, for the iCloud status: how many records the account
    /// holds, how many were taken here, how many were sent from here.
    public private(set) var catalogSyncSummary: GlassCatalogSyncSummary?
    /// One sync at a time. The library's first load and its return to the foreground each ask for
    /// one, and two interleaved merges each publish from a snapshot the other is changing.
    private var catalogSyncTask: Task<Void, Never>?
    private var catalogSyncRequestedAgain = false

    /// Starts syncing the library through `backend`.
    ///
    /// Injected rather than constructed here so the merge can be driven by a fake in tests, and so
    /// the shell does not require CloudKit to exist at all — the app supplies
    /// `GlassCloudKitCatalogBackend`; a unit test supplies whatever it needs to assert.
    public func enableCatalogSync(_ backend: any GlassCatalogSyncBackend) {
        catalogBackend = backend
        // Register for change notifications and start listening. Both halves matter: a
        // subscription nothing listens for is a silent push into a void, and a listener with no
        // subscription never hears one. This is the seventh time in this project that a working
        // part existed with nothing joined to it, so they are wired together here, in one place.
        Task { [weak self] in
            try? await backend.subscribeToChanges()
            await self?.listenForRemoteChanges()
        }
    }

    /// Re-syncs whenever the platform tells us the library changed on another device.
    ///
    /// The notification is posted by whatever receives the silent push — an app delegate on Apple
    /// platforms. The model does not import UIKit or AppKit to hear it, so this stays testable:
    /// a test posts the same notification and asserts a sync ran.
    public nonisolated static let remoteChangeNotification = Notification.Name("com.glasspowertools.catalog.remoteChange")

    private func listenForRemoteChanges() async {
        guard remoteChangeTask == nil else { return }
        remoteChangeTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: Self.remoteChangeNotification) {
                guard let self, !Task.isCancelled else { return }
                await synchronizeCatalog()
                // A pull that changed nothing still leaves the view correct; one that did needs the
                // projection rebuilt, and `synchronizeCatalog` has already done that.
            }
        }
    }

    /// One pull-merge-push cycle.
    ///
    /// Both directions in one pass, because they are the same question asked twice: what does this
    /// device have that the account does not, and vice versa. `GlassCatalogMerge.reconcile` decides;
    /// nothing here does.
    public func synchronizeCatalog() async {
        guard catalogBackend != nil else { return }
        // One pass at a time. A caller that arrives mid-pass asks for one more round and waits for
        // it: returning at once (as this did on 2026-09-28) let Sync Now, and any test, read the
        // library before the sync it asked for had happened.
        if let running = catalogSyncTask {
            catalogSyncRequestedAgain = true
            await running.value
            return
        }
        let task = Task { @MainActor in
            repeat {
                catalogSyncRequestedAgain = false
                await synchronizeCatalogOnce()
            } while catalogSyncRequestedAgain
            catalogSyncTask = nil
        }
        catalogSyncTask = task
        await task.value
    }

    /// `GLASS_SYNC_DRY_RUN=1`: fetch the account, compare it with this device record by record,
    /// log the comparison, and change nothing — no apply, no publish, none of the launch tidy-ups
    /// that write to the local library. For diagnosing what another device put in the account
    /// before this one takes it (2026-09-28: a headset with a months-old library sent 10 records).
    nonisolated static var isSyncDryRun: Bool {
        ProcessInfo.processInfo.environment["GLASS_SYNC_DRY_RUN"] == "1"
    }

    private func logDryRun(local: [HostProfile], remote: [HostProfile], outcome: GlassCatalogMerge.Outcome) {
        let localByID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let remoteByID = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func describe(_ h: HostProfile?) -> String {
            guard let h else { return "absent" }
            let configured = h.services.filter { $0.configuration != nil }.count
            return "updated=\(h.updatedAt.timeIntervalSince1970) deleted=\(h.deletedAt != nil) services=\(h.services.count) configured=\(configured) writer=\(h.lastWriterID.rawValue.uuidString.prefix(8))"
        }
        let apply = Set(outcome.toApplyLocally.map(\.id)), publish = Set(outcome.toPublish.map(\.id))
        for id in Set(localByID.keys).union(remoteByID.keys).sorted(by: { $0.rawValue.uuidString < $1.rawValue.uuidString }) {
            let name = (localByID[id] ?? remoteByID[id])?.displayName ?? "?"
            let action = apply.contains(id) ? "WOULD-APPLY" : publish.contains(id) ? "WOULD-SEND" : "same"
            var differing: [String] = []
            if let l = localByID[id], let r = remoteByID[id], l != r {
                let pairs: [(String, Bool)] = [
                    ("name", l.displayName != r.displayName), ("address", l.address != r.address),
                    ("aliases", l.aliases != r.aliases), ("services", l.services != r.services),
                    ("tags", l.tags != r.tags), ("created", l.createdAt != r.createdAt),
                    ("updated", l.updatedAt != r.updatedAt), ("deleted", l.deletedAt != r.deletedAt),
                    ("writer", l.lastWriterID != r.lastWriterID), ("version", l.schemaVersion != r.schemaVersion)]
                differing = pairs.filter(\.1).map(\.0)
                if l.updatedAt != r.updatedAt {
                    differing.append("Δupdated=\(l.updatedAt.timeIntervalSinceReferenceDate - r.updatedAt.timeIntervalSinceReferenceDate)")
                }
            }
            Logger.catalogSync.info("DRY diff \(id.rawValue.uuidString.prefix(8), privacy: .public): \(differing.joined(separator: ","), privacy: .public)")
            Logger.catalogSync.info("DRY \(action, privacy: .public) \(id.rawValue.uuidString.prefix(8), privacy: .public) \(name, privacy: .public) | local: \(describe(localByID[id]), privacy: .public) | account: \(describe(remoteByID[id]), privacy: .public)")
        }
        Logger.catalogSync.info("DRY summary: \(local.count, privacy: .public) local, \(remote.count, privacy: .public) in account, \(apply.count, privacy: .public) would apply, \(publish.count, privacy: .public) would send")
    }

    private func synchronizeCatalogOnce() async {
        guard let catalogBackend else { return }
        catalogSyncStatus = .syncing
        do {
            // **The whole account, every time** (2026-09-27). A fetch since a token returns only
            // what changed, and the merge reads "not in what came back" as "the account has never
            // seen this" and publishes it. Against a delta that was every unchanged record, sent
            // over whatever the account held, newer or not: a phone with copies from before the
            // Mac's collections overwrote them on every foreground and read its own copies back,
            // while saying "Synced". The library is tens of records; reading all of them is the
            // only reading under which the merge's rule is true.
            let (remote, _) = try await catalogBackend.fetchChanges(since: nil)
            // `includeDeleted: true`: a tombstone is a record, and publishing the library without
            // them would let a host deleted here come back from a device that never heard.
            let local = try await catalog.snapshot(includeDeleted: true)
            let outcome = GlassCatalogMerge.reconcile(local: local, remote: remote)
            if Self.isSyncDryRun {
                logDryRun(local: local, remote: remote, outcome: outcome)
                catalogSyncStatus = .failed("Dry run: nothing applied or sent")
                return
            }

            // What the incoming records take away, captured before they are applied: afterwards
            // there is nothing left to ask. A tombstone removes every service on the record; an
            // ordinary edit removes whichever services are no longer on it.
            var departed: [(service: HostServiceLink, owner: HostProfile)] = []
            let localByID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for profile in outcome.toApplyLocally {
                guard let mine = localByID[profile.id], mine.deletedAt == nil else { continue }
                let surviving = profile.deletedAt == nil ? Set(profile.services.map(\.endpointID)) : []
                // A device-bound service is absent from every record the account holds because
                // this device redacted it on publish. Without this it would look deleted
                // elsewhere on the very next sync, and stage 2 would delete its credential —
                // the two stages quietly undoing each other. A tombstone still takes it.
                let bound = profile.deletedAt == nil ? deviceBoundServices(of: mine) : []
                departed += mine.services
                    .filter { !surviving.contains($0.endpointID) && !bound.contains($0.endpointID) }
                    .map { (service: $0, owner: mine) }
            }

            Logger.catalogSync.info(
                """
                Sync: \(local.count, privacy: .public) local, \(remote.count, privacy: .public) incoming, \
                \(outcome.toApplyLocally.count, privacy: .public) to apply, \
                \(outcome.toPublish.count, privacy: .public) to publish
                """)
            // **`merge`, not `upsert`.** `upsert` is the local-edit path: it refuses a tombstone by
            // design — editing a deleted machine is a mistake — and it restamps `updatedAt` and
            // `lastWriterID` as though this device authored the record. Both are wrong for an
            // incoming one. On 2026-09-16 a single machine deleted on two devices made every
            // subsequent sync throw here, and because the publish sits below this line, that device
            // silently stopped publishing altogether: a database added on the Mac never reached the
            // phone. `merge` is the API for incoming records and always was — deletion precedence,
            // revision time and writer id, tested in the catalog's own suite.
            // Applying and publishing are two directions, not one transaction. Incoming records
            // this device cannot take must not cost it the ability to send its own — and one
            // record the catalog refuses must not cost it the rest: the merge is all-or-nothing,
            // so a refused batch is retried one record at a time. What still fails is counted and
            // said in the status, not only logged (2026-09-28: a headset said "Synced" while
            // taking nothing).
            let incoming = reattachingDeviceBoundServices(outcome.toApplyLocally, local: local)
            var unapplied = 0
            do {
                try await catalog.merge(incoming)
            } catch {
                Logger.catalogSync.error(
                    "Sync: could not apply incoming records together: \(String(describing: error), privacy: .public)")
                for record in incoming {
                    do { try await catalog.merge([record]) } catch {
                        unapplied += 1
                        Logger.catalogSync.error(
                            "Sync: could not apply \(record.id.rawValue.uuidString.prefix(8), privacy: .public): \(String(describing: error), privacy: .public)")
                    }
                }
            }
            if !outcome.toPublish.isEmpty {
                try await catalogBackend.save(redactingDeviceBoundServices(outcome.toPublish))
                Logger.catalogSync.info("Sync: published \(outcome.toPublish.count, privacy: .public) record(s)")
            }
            catalogSyncSummary = GlassCatalogSyncSummary(
                inAccount: remote.count, received: outcome.toApplyLocally.count,
                sent: outcome.toPublish.count)

            if !outcome.toApplyLocally.isEmpty {
                records = try await catalog.snapshot()
                rebuildProjection()
            }
            if !departed.isEmpty {
                // Deliberately not rethrown: a capability failing to delete its credential must not
                // fail the whole sync, which has already applied correctly. `deleteHost` throws
                // because a person is watching; nobody is watching this.
                try? await cascadeRemoval(of: departed)
            }
            catalogSyncStatus = unapplied == 0
                ? .synced(Date())
                : .failed(unapplied == 1 ? "1 record from iCloud could not be applied on this device"
                                         : "\(unapplied) records from iCloud could not be applied on this device")
        } catch {
            // Signed out of iCloud, restricted, or offline: all normal, none the user's mistake,
            // and none worth an alert. The library on this device is complete without the others.
            //
            // **Logged, though.** Not alerting is a judgement about the user's attention; saying
            // nothing anywhere is a hole. A sync that failed here published nothing, and on
            // 2026-09-16 that was invisible: a database added on the Mac never reached the phone,
            // and the only evidence was a status line nobody was looking at.
            Logger.catalogSync.error("Sync failed: \(String(describing: error), privacy: .public)")
            catalogSyncStatus = .failed(error.localizedDescription)
        }
    }

    // MARK: The one store for a connection (D26)
    //
    // A capability's configuration lives on its service link. These three methods are the whole of
    // the read/write side; `GlassServiceStore` is the narrow protocol capabilities see, so none of
    // them holds this model.

    /// The link for an endpoint, wherever in the library it lives.
    private func link(for endpointID: EndpointID) -> (host: HostProfile, link: HostServiceLink)? {
        for record in records {
            if let found = record.services.first(where: { $0.endpointID == endpointID }) {
                return (record, found)
            }
        }
        return nil
    }

    public func configuration(for endpointID: EndpointID) -> Data? {
        link(for: endpointID)?.link.configuration
    }

    /// D26: the catalog has been read from disk. Until it has, every read here answers "nothing",
    /// which is indistinguishable from an empty library — see `GlassServiceStore.isCatalogLoaded`.
    public var isCatalogLoaded: Bool { isLoaded }

    public func configurations(ofKind kind: HostServiceKind) -> [EndpointID: Data] {
        var found: [EndpointID: Data] = [:]
        for record in records {
            for service in record.services where service.kind == kind {
                if let configuration = service.configuration { found[service.endpointID] = configuration }
            }
        }
        return found
    }

    /// Writes the capability's record onto its link and publishes it.
    ///
    /// The link is re-read from the catalog immediately before writing rather than taken from
    /// `records`, which is a projection that may be a moment behind a sync. Writing a stale link
    /// back would silently revert whatever arrived in between.
    public func setConfiguration(_ data: Data?, for endpointID: EndpointID) async throws {
        guard let located = link(for: endpointID) else {
            throw GlassShellError.serviceNotFound(endpointID)
        }
        let isLocal = isLocalHost(located.host.id)
        let store = isLocal ? localCatalog : catalog
        let snapshot = try await store.snapshot()
        guard let owner = snapshot.first(where: { $0.services.contains { $0.endpointID == endpointID } }),
              var current = owner.services.first(where: { $0.endpointID == endpointID }) else {
            throw GlassShellError.serviceNotFound(endpointID)
        }
        guard current.configuration != data else { return }
        current.configuration = data
        try await store.pair(current, with: owner.id)
        await load()
    }

    // MARK: Importing a machine from another tool (D27)

    /// A machine a capability parsed out of a file, waiting for the library to open its sheet.
    ///
    /// A property rather than a callback because the library owns the sheet and a capability must
    /// not reach into a view. The library clears it once presented, so the same import is not
    /// re-opened on every redraw.
    public private(set) var pendingSetupPrefill: GlassShellSetupPrefill?

    /// Asks the library to open the host sheet filled in from an imported file. The capability
    /// parsed it; everything after this — the host record, the service link, the credential — is
    /// the ordinary setup flow, which is exactly why importing gets a library entry for free.
    public func requestSetup(prefill: GlassShellSetupPrefill) {
        pendingSetupPrefill = prefill
    }

    /// Called by the library once the sheet is up.
    public func clearPendingSetup() { pendingSetupPrefill = nil }

    /// The library's sync state, in words a person can act on.
    ///
    /// "Not set up" rather than an error when no backend is attached: a build without CloudKit, or
    /// a UI test, is not broken — it simply has no other devices to talk to.
    public var catalogSyncStatusDescription: String {
        switch catalogSyncStatus {
        case .idle: return catalogBackend == nil ? "Not synced on this build" : "Waiting to sync"
        case .syncing: return "Syncing…"
        case .synced(let date):
            return "Synced \(date.formatted(date: .omitted, time: .shortened))"
        case .unavailable(let reason): return reason
        case .failed(let message): return "Not synced — \(message)"
        }
    }

    public var catalogHosts: [GlassShellHost] { hosts.filter { !$0.isLocal } }

    /// `items` without this device. Internal: the library itself always shows every row, and
    /// this exists so a test about the shared catalog can say which rows it means.
    var catalogItems: [GlassLibraryItem<HostID>] { items.filter { $0.id != GlassLocalHost.id } }

    /// Writes the device's own record and reloads. Separate from `updateHost` because the local
    /// record lives in its own store and carries no address.
    private func updateLocalRecord(_ body: (inout HostProfile) -> Void) async throws {
        let stored = try await localCatalog.snapshot()
        guard let current = stored.first(where: { $0.id == GlassLocalHost.id }) else {
            throw GlassShellError.hostNotFound(GlassLocalHost.id)
        }
        var updated = current
        body(&updated)
        try updated.validate()
        try await localCatalog.upsert(updated)
        await load()
    }

    // MARK: Projection

    public var items: [GlassLibraryItem<HostID>] {
        hosts.map { host in
            let record = preferences[host: host.id]
            let kinds = HostServiceKind.allCases.filter { kind in host.services.contains { $0.kind == kind } }
            let subtitle = Self.subtitle(for: kinds)
            return GlassLibraryItem(id: host.id, name: host.displayName, subtitle: subtitle,
                                    searchTerms: host.aliases + host.services.map(\.displayName),
                                    tags: host.tags, isFavorite: record.isFavorite,
                                    lastConnected: record.lastConnected, dateAdded: host.createdAt,
                                    sortKeys: [host.displayName, host.id.rawValue.uuidString])
        }
    }

    /// The consolidated host for a canonical id — or for any member record's id, so a selection
    /// or preference keyed on a record that later joined a group still resolves.
    /// The row's second line. Up to two kinds are named; three or more are counted, because the
    /// shared row middle-truncates a long subtitle ("Desk…abase") and the icons beside the row
    /// already say which kinds they are.
    static func subtitle(for kinds: [HostServiceKind]) -> String {
        switch kinds.count {
        case 0: "No services yet"
        case 1, 2: kinds.map(GlassServicePresentation.displayName(for:)).joined(separator: " · ")
        default: "\(kinds.count) services"
        }
    }

    public func host(_ id: HostID) -> GlassShellHost? {
        hosts.first { $0.id == id } ?? hosts.first { $0.contains(id) }
            ?? mergedMemberIDs[id].flatMap { canonical in hosts.first { $0.id == canonical } }
    }

    /// The machine one of whose services is this endpoint.
    ///
    /// The way back from a capability's own record to the catalog's: a capability knows its
    /// service's id and nothing about hosts, so this is how "which machine is this connection to?"
    /// is answered without the capability holding a second copy of the answer (D26).
    public func host(owningEndpoint endpointID: EndpointID) -> GlassShellHost? {
        hosts.first { $0.services.contains { $0.endpointID == endpointID } }
    }

    /// The stored record with this id, if any — the device's own included, though it is not in
    /// `records`, which is the shared catalog as stored.
    public func record(_ id: HostID) -> HostProfile? {
        if id == GlassLocalHost.id { return localRecord }
        return records.first { $0.id == id }
    }

    /// The canonical id for any host or member id.
    public func canonicalID(for id: HostID) -> HostID { host(id)?.id ?? id }

    public func services(for id: HostID) -> [HostServiceLink] { host(id)?.services ?? [] }

    public func serviceKinds(for id: HostID) -> [HostServiceKind] {
        let present = Set(services(for: id).map(\.kind))
        return HostServiceKind.allCases.filter(present.contains)
    }

    public func isFavorite(_ id: HostID) -> Bool { preferences[host: canonicalID(for: id)].isFavorite }

    /// Connections made on this device, oldest first, each mapped to its host as the library shows
    /// it now (a host folded into another counts as that one). Never synced (D41).
    public var connectionHistory: [GlassShellPreferences.ConnectionEvent] {
        (preferences.connectionHistory ?? []).map {
            var event = $0
            event.hostID = canonicalID(for: $0.hostID)
            return event
        }
    }
    public func lastConnected(_ id: HostID) -> Date? { preferences[host: canonicalID(for: id)].lastConnected }
    public func lastUsedService(for id: HostID) -> HostServiceLink? {
        guard let endpointID = preferences[host: canonicalID(for: id)].lastUsedEndpointID else { return nil }
        return services(for: id).first { $0.endpointID == endpointID }
    }

    /// Preferences written against a record that has since joined a group move to the group's
    /// canonical id: favorite if any member was, the latest connection time, and the last-used
    /// service of whichever member connected most recently. Idempotent; persisted only when the
    /// file is writable and something actually moved.
    private func migratePreferencesToCanonicalHosts() {
        var moved = false
        for host in hosts where host.isConsolidated {
            var canonical = preferences.hosts[host.id] ?? .init()
            for member in host.members.dropFirst() {
                guard let stray = preferences.hosts.removeValue(forKey: member.id) else { continue }
                moved = true
                canonical.isFavorite = canonical.isFavorite || stray.isFavorite
                if let strayDate = stray.lastConnected, strayDate > (canonical.lastConnected ?? .distantPast) {
                    canonical.lastConnected = strayDate
                    canonical.lastUsedEndpointID = stray.lastUsedEndpointID ?? canonical.lastUsedEndpointID
                } else if canonical.lastUsedEndpointID == nil {
                    canonical.lastUsedEndpointID = stray.lastUsedEndpointID
                }
            }
            if moved { preferences.hosts[host.id] = canonical }
        }
        guard moved, !preferencesReadOnly else { return }
        do { try persistPreferences() } catch { errorMessage = GlassShellError.message(for: error) }
    }

    // MARK: Mutations

    public func addHost(displayName: String, address: String? = nil, aliases: [String] = [], tags: [String] = []) async throws -> HostProfile {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GlassShellError.invalidName }
        let profile = try HostProfile(displayName: trimmed, address: Self.blankToNil(address), aliases: aliases, tags: tags,
                                      lastWriterID: preferences.writerID)
        try await catalog.upsert(profile)
        await load()
        return profile
    }

    /// Blank means "no address", never an empty string that the kit would reject.
    static func blankToNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Renames every member record (so the group stays together) and applies aliases and tags to
    /// the canonical one. Each record is re-read right before writing so services another app
    /// paired since our last load survive. (Interim until the kit offers an in-lock field edit.)
    public func updateHost(_ id: HostID, displayName: String, address: String? = nil, aliases: [String], tags: [String]) async throws {
        guard let host = host(id) else { throw GlassShellError.hostNotFound(id) }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GlassShellError.invalidName }
        if host.isLocal {
            // Rename, aliases and collections are the user's; an address is not a thing this host
            // has, and an attempt to set one is refused rather than quietly dropped.
            guard Self.blankToNil(address) == nil else { throw GlassShellError.localHostHasNoAddress }
            try await updateLocalRecord { record in
                record.displayName = trimmed
                record.aliases = aliases
                record.tags = tags
            }
            return
        }
        let newAddress = try Self.blankToNil(address).map(HostProfile.normalizedAddress)
        let snapshot = try await catalog.snapshot()
        var updatedMembers: [HostProfile] = []
        for member in host.members {
            let fresh = snapshot.first { $0.id == member.id } ?? member
            let isCanonical = member.id == host.id
            // The address is the machine's, so every member record carries the same one.
            let updated = try HostProfile(id: fresh.id, displayName: trimmed, address: newAddress,
                                          aliases: isCanonical ? aliases : fresh.aliases,
                                          services: fresh.services,
                                          tags: isCanonical ? tags : fresh.tags,
                                          createdAt: fresh.createdAt,
                                          updatedAt: max(Date(), fresh.updatedAt), lastWriterID: preferences.writerID)
            try await catalog.upsert(updated)
            updatedMembers.append(updated)
        }
        await load()
        if newAddress != host.address { notifyAddressChange(members: updatedMembers, address: newAddress) }
    }

    /// Sets only the address, leaving name, aliases and tags as they are. Used by the address
    /// prompt and by adoption from a capability's saved record, so the machine's identity is
    /// defined once, at the host.
    public func setHostAddress(_ address: String?, for id: HostID) async throws {
        guard let host = host(id) else { throw GlassShellError.hostNotFound(id) }
        try await updateHost(host.id, displayName: host.displayName, address: address, aliases: host.aliases, tags: host.tags)
    }

    /// Every capability hears about each member record: a capability keys its services by the
    /// endpoint ids inside those records.
    private func notifyAddressChange(members: [HostProfile], address: String?) {
        for capability in registry.registered {
            for member in members where member.services.contains(where: { $0.kind == capability.kind }) {
                capability.hostAddressDidChange(host: member, address: address)
            }
        }
    }

    /// What a capability may read about a host while it sets a service up or connects, plus the
    /// brokered forward: when the machine has an SSH service, any capability may borrow it to
    /// reach a service that only listens on the machine itself (D7), without importing the
    /// capability that owns it.
    /// Public because the composition root hands it to capabilities that need it outside a
    /// connect — the database's setup sheet settles host-key trust through it (D14).
    /// The tidier-looking alternative, passing access through `setupDraft(for:host:)`, was
    /// considered and rejected: `makeSetupDraft()` has no host, so it would cover only half the
    /// cases — exactly the one-and-done sheet that creates a host and its services in one save.
    public func hostAccess(for id: HostID) -> GlassCapabilityHostAccess {
        guard let host = host(id) else {
            return GlassCapabilityHostAccess(address: nil, tunnelChoices: tunnelChoices(excluding: nil),
                                             openForwardThrough: forwardThroughProvider(),
                                             resolveTrustThrough: trustThroughResolver())
        }
        return GlassCapabilityHostAccess(address: host.address,
                                         openForward: portForwardProvider(for: host),
                                         resolveTrust: hostTrustResolver(for: host),
                                         tunnelChoices: tunnelChoices(excluding: host.id),
                                         openForwardThrough: forwardThroughProvider(),
                                         resolveTrustThrough: trustThroughResolver())
    }

    // MARK: Tunnelling through another machine (2026-10-05)

    /// Machines whose Terminal service can carry a tunnel for another: every machine but this
    /// device and `excluded`, with an SSH service on the record that carries the machine's
    /// address (`sshMember`, the same rule as this machine's own tunnel). In library order.
    public func tunnelChoices(excluding excluded: HostID?) -> [GlassTunnelChoice] {
        guard registry.capability(for: .ssh) != nil else { return [] }
        return hosts.compactMap { host in
            guard !host.isLocal, host.id != excluded, let member = sshMember(of: host),
                  let ssh = member.services.first(where: { $0.kind == .ssh }) else { return nil }
            return GlassTunnelChoice(serviceID: ssh.endpointID, machineName: host.displayName)
        }
    }

    /// The machine record that owns an SSH service, for a tunnel through it. Nil when the
    /// service is gone, belongs to this device, or is not an SSH service.
    private func tunnelMember(for service: EndpointID) -> HostProfile? {
        guard let host = host(owningEndpoint: service), !host.isLocal,
              let member = host.record(owning: service),
              member.services.contains(where: { $0.endpointID == service && $0.kind == .ssh }) else { return nil }
        return member
    }

    private func forwardThroughProvider()
    -> (@MainActor @Sendable (EndpointID, String, Int) async throws -> any GlassHostPortForward)? {
        guard let capability = registry.capability(for: .ssh) else { return nil }
        return { [weak self] service, remoteHost, port in
            guard let member = self?.tunnelMember(for: service) else { throw GlassPortForwardError.tunnelMachineGone }
            return try await capability.openPortForward(host: member, toHost: remoteHost, port: port)
        }
    }

    private func trustThroughResolver() -> (@MainActor @Sendable (EndpointID) async -> GlassHostTrustOutcome)? {
        guard let capability = registry.capability(for: .ssh) else { return nil }
        return { [weak self] service in
            guard let member = self?.tunnelMember(for: service) else { return .unavailable }
            return await capability.resolveHostTrust(host: member)
        }
    }

    /// The forward provider for a host, or nil when there is nothing to borrow: the machine has
    /// no SSH service, no registered capability owns that kind, or the machine is this device.
    /// Resolved once per access so a caller's `canForwardPorts` answers the same question the
    /// call will.
    ///
    /// **The local host is excluded explicitly (D8), and it has to be**: it carries a Terminal
    /// service — the Mac's own shell — so the plain "does this host have an `.ssh` service?" test
    /// says yes, and the database capability would then tunnel to loopback through loopback to
    /// reach a server already listening on it.
    /// The member whose SSH service a borrowed forward runs through.
    ///
    /// **A host is a group, not a machine.** `GlassShellHostGrouping.group` joins records whose
    /// normalised display names match, which is one of three ways in and does not require the
    /// addresses to agree — `GlassShellHost` says so itself, keeping `addresses` plural and taking
    /// `address` as the first. Two records both called "db" on different machines are one row.
    ///
    /// Taking simply "the first member with an `.ssh` service" therefore picks a machine by
    /// creation order. A database on the newer record would be tunnelled through the SSH service on
    /// the older one, and `DatabaseSessionManager` then opens the forward to `127.0.0.1:port` **as
    /// that other machine sees it** and sends the username and password down it. With TLS off — the
    /// ordinary setting for a tunnelled database — nothing notices.
    ///
    /// So the SSH service must belong to the machine the host *is*: the address shown in the UI and
    /// the one the user believes they are reaching. When no SSH member carries that address the
    /// group is genuinely ambiguous, and this returns nil rather than guessing — tunnelling to the
    /// wrong machine is worse than not tunnelling, and the caller already reports the absence.
    ///
    /// One selection serves both the forward and the trust resolver on purpose, so a fingerprint
    /// the user approves belongs to the machine the bytes go to.
    /// Internal rather than private so the selection can be tested directly. Reaching it through
    /// `hostAccess` proves nothing without a registered `.ssh` capability, and the rule being
    /// tested — which machine is chosen — is independent of whether one is registered.
    func sshMember(of host: GlassShellHost) -> HostProfile? {
        let candidates = host.members.filter { $0.services.contains { $0.kind == .ssh } }
        guard let address = host.address, !address.isEmpty else {
            // No address to agree with: only one candidate is unambiguous.
            return candidates.count == 1 ? candidates.first : nil
        }
        let matching = candidates.filter { $0.address == address }
        // More than one member at the same address is the same machine recorded twice, which is
        // what grouping exists for; any of them reaches it.
        return matching.first
    }

    private func portForwardProvider(for host: GlassShellHost)
    -> (@MainActor @Sendable (String, Int) async throws -> any GlassHostPortForward)? {
        guard !host.isLocal else { return nil }
        guard let capability = registry.capability(for: .ssh),
              let member = sshMember(of: host)
        else { return nil }
        return { remoteHost, port in
            try await capability.openPortForward(host: member, toHost: remoteHost, port: port)
        }
    }

    /// The host-key trust resolver for a host (D14), resolved against the same SSH service the
    /// forward would use so that settling trust settles it for the forward. Nil on exactly the
    /// same conditions, so `resolveHostTrust` cannot promise more than `forwardPort` can deliver.
    private func hostTrustResolver(for host: GlassShellHost)
    -> (@MainActor @Sendable () async -> GlassHostTrustOutcome)? {
        guard !host.isLocal else { return nil }
        guard let capability = registry.capability(for: .ssh),
              let member = sshMember(of: host)
        else { return nil }
        return { await capability.resolveHostTrust(host: member) }
    }

    /// An address one of the host's capabilities already stores for a service of the host — a
    /// record saved by the source app before hosts carried an address. Nil when none, or when
    /// the capabilities disagree (that is for the user to settle, not for the shell to guess).
    /// Every service with an address and a port to probe, for the availability dots (D41).
    public func availabilityTargets() -> [GlassAvailabilityMonitor.Target] {
        hosts.flatMap { host -> [GlassAvailabilityMonitor.Target] in
            guard let address = host.address ?? knownAddress(for: host) else { return [] }
            return host.services.compactMap { service in
                guard let owner = host.record(owning: service.endpointID),
                      let port = registry.capability(for: service.kind)?.knownPort(service: service, host: owner)
                else { return nil }
                return .init(endpointID: service.endpointID, host: address, port: port)
            }
        }
    }

    func knownAddress(for host: GlassShellHost) -> String? {
        var found = Set<String>()
        for member in host.members {
            for service in member.services {
                guard let capability = registry.capability(for: service.kind),
                      let address = capability.knownAddress(service: service, host: member)?
                        .trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty else { continue }
                found.insert(address.lowercased())
            }
        }
        return found.count == 1 ? found.first : nil
    }

    /// Hosts that predate the address gain it from the services already saved on their
    /// capabilities, once, so the detail never says "Not set" for a machine the terminal knows.
    /// Runs after each load; a host whose capabilities disagree is left for the user.
    private var isAdoptingAddresses = false
    private func adoptKnownAddresses() async {
        guard !isAdoptingAddresses else { return }
        isAdoptingAddresses = true
        defer { isAdoptingAddresses = false }
        // The local host is skipped: it has no address by design, and a SQLite file path or a
        // loopback literal saved on one of its services is not a machine to adopt.
        let candidates = hosts.filter { $0.address == nil && !$0.isLocal }.compactMap { host in
            knownAddress(for: host).map { (host.id, $0) }
        }
        for (id, address) in candidates {
            do { try await setHostAddress(address, for: id) } catch {
                // Not fatal: the host simply keeps "Not set" until the user enters it.
                continue
            }
        }
    }

    /// Deletes every record that makes up the host. The device's own host is not one the user
    /// created and is not one they can remove (D8) — its services are removed individually.
    /// Deletes the machine, **and everything its capabilities stored for it**.
    ///
    /// The capability pass is the part that was missing. Removing the records unlinked the
    /// services and left each capability's own configuration behind — the terminal's
    /// `ServerConfiguration`, the database's connection, and the Keychain entries with them. The
    /// orphans stayed reachable through surfaces that read the capability's store rather than the
    /// catalog: a host deleted from the library went on appearing in Connect Saved Host, with no
    /// way left to remove it, because the thing that owned it no longer existed.
    ///
    /// `removeService` has always done this for one service and says so in its own documentation.
    /// Deleting the host simply never called it.
    ///
    /// Order matters and matches `removeService`: the records go first, then the capabilities are
    /// asked to clean up. A stray configuration is harmless; a link to nothing is not. A capability
    /// that throws must not strand the deletion either, so a failure there is collected and
    /// reported after every other service has had its turn.
    public func deleteHost(_ id: HostID) async throws {
        guard let host = host(id) else { throw GlassShellError.hostNotFound(id) }
        guard !host.isLocal else { throw GlassShellError.localHostNotRemovable }
        // Captured before the records go: afterwards there is nothing left to ask.
        let owned = host.members.flatMap { member in
            member.services.map { (service: $0, owner: member) }
        }
        for member in host.members { try await catalog.delete(hostID: member.id) }
        for member in host.members { preferences.hosts[member.id] = nil }
        try persistPreferences()
        await load()

        try await cascadeRemoval(of: owned)
    }

    // MARK: Keys (D26 stage 4)

    /// Whoever holds SSH key material, so the library can offer a key manager.
    ///
    /// Attached by the composition root rather than constructed here, exactly as the catalog
    /// backend is: the shell must work with no key store at all (the manager simply is not in the
    /// sidebar), and nothing in the shell may reach into a capability to find one.
    public private(set) var keyStore: (any GlassKeyStore)?

    /// Selection and presentation for the key manager's two columns. Held here rather than in
    /// either column, because they are two columns of one split view and a `@State` in one cannot
    /// be read by the other — the arrangement Workgroups uses for the same reason.
    public let keyPanel = GlassKeyManagerModel()

    public func attachKeyStore(_ store: any GlassKeyStore) { keyStore = store }

    // MARK: What uses a key (D28)

    /// Every service that authenticates with `keyID`, with the machine it belongs to.
    ///
    /// **Derived, never stored.** The edge already exists on each service's own configuration, so a
    /// usage table would be a second copy of an existing truth that has to be kept in step through
    /// deletion, editing, sync and merge — and D25 is the bug where deleting a thing forgot to tell
    /// the other store. A derived index cannot drift.
    ///
    /// This is what makes deleting a key safe: the manager can name what it is about to unassign.
    public func services(usingKey keyID: UUID) -> [(host: HostProfile, service: HostServiceLink)] {
        var found: [(host: HostProfile, service: HostServiceLink)] = []
        for record in records where record.deletedAt == nil {
            for service in record.services {
                guard case .sharedKey(let id, _) = credential(for: service, on: record), id == keyID else { continue }
                found.append((host: record, service: service))
            }
        }
        return found
    }

    /// How many services use `keyID`, and how many this build could not read.
    ///
    /// The second number is not decoration. A configuration written by a newer build is skipped
    /// rather than fatal, so without counting it a key in genuine use can read as *used by nothing*
    /// — and then somebody deletes it. A zero only ever proves where you looked.
    public func usageCount(ofKey keyID: UUID) -> (readable: Int, unreadable: Int) {
        var readable = 0
        var unreadable = 0
        for record in records where record.deletedAt == nil {
            for service in record.services {
                switch credential(for: service, on: record) {
                case .sharedKey(let id, _) where id == keyID: readable += 1
                case .unreadable: unreadable += 1
                default: continue
                }
            }
        }
        return (readable, unreadable)
    }

    /// The one place that asks a capability what authenticates a service.
    private func credential(for service: HostServiceLink, on record: HostProfile) -> GlassServiceCredential {
        registry.capability(for: service.kind)?.credential(for: service, host: record) ?? .ownedByService
    }

    /// The services on `record` whose credential cannot leave this device (D26 stage 3).
    ///
    /// Asked of whichever capability owns each service, every time, because binding is derived from
    /// the credential rather than stored. One place, because three things depend on agreeing about
    /// it: what is published, what is re-attached, and what counts as deleted elsewhere.
    private func deviceBoundServices(of record: HostProfile) -> Set<EndpointID> {
        var bound: Set<EndpointID> = []
        for service in record.services
        where credential(for: service, on: record).isDeviceBound {
            bound.insert(service.endpointID)
        }
        return bound
    }

    /// `profiles` with every device-bound service removed, for publishing.
    ///
    /// **This is half of a pair and is useless — worse than useless — alone.** Redacting without
    /// re-attaching means this device publishes a host without its hardware-key service, pulls its
    /// own record back as the merge winner, and deletes its own local service on the *second* sync.
    /// Nothing fails; the configuration is simply gone. See `reattachingDeviceBoundServices`.
    private func redactingDeviceBoundServices(_ profiles: [HostProfile]) -> [HostProfile] {
        profiles.map { profile in
            let bound = deviceBoundServices(of: profile)
            guard !bound.isEmpty else { return profile }
            var redacted = profile
            redacted.services = profile.services.filter { !bound.contains($0.endpointID) }
            return redacted
        }
    }

    /// `incoming` with this device's own device-bound services put back.
    ///
    /// The other half of the pair. A record arriving from the account cannot carry them — this
    /// device redacted them on the way out, and no other device ever had them — so applying it
    /// unchanged would delete them here.
    private func reattachingDeviceBoundServices(_ incoming: [HostProfile],
                                                local: [HostProfile]) -> [HostProfile] {
        let localByID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return incoming.map { profile in
            guard let mine = localByID[profile.id] else { return profile }
            let bound = deviceBoundServices(of: mine)
            guard !bound.isEmpty else { return profile }
            let present = Set(profile.services.map(\.endpointID))
            var restored = profile
            restored.services += mine.services.filter { bound.contains($0.endpointID) && !present.contains($0.endpointID) }
            return restored
        }
    }

    /// Tells each capability to delete what it stored for services that have gone.
    ///
    /// The one implementation both deletion paths use: a host deleted **here** (`deleteHost`) and a
    /// host deleted **on another device**, which arrives as a tombstone through the sync. D25 fixed
    /// the first; the second went on orphaning credentials until D26 stage 2, because the merge
    /// applied tombstones and told nobody.
    ///
    /// **What is left to clean is credentials.** Since stage 1 the configuration lives on the link,
    /// so a tombstone takes it along; the Keychain entry is what has nobody else to remove it.
    ///
    /// A capability that throws must not strand the rest, so every one gets its turn and the first
    /// failure is reported afterwards.
    private func cascadeRemoval(of owned: [(service: HostServiceLink, owner: HostProfile)]) async throws {
        var firstFailure: Error?
        for entry in owned {
            do {
                try await registry.capability(for: entry.service.kind)?
                    .removeService(entry.service, host: entry.owner)
            } catch {
                if firstFailure == nil { firstFailure = error }
            }
        }
        if let firstFailure { throw firstFailure }
    }

    // MARK: Adopting a machine a capability created (D27)

    /// Finds or creates the host for `address`, links a service of `kind` to it, and returns the
    /// endpoint id the capability must store its record under.
    ///
    /// D27: some ways of making a connection do not go through the host sheet — the terminal's own
    /// Add Server form and its `ssh_config` import both build a saved server directly. Before this,
    /// those servers had no host record and no link, which meant they never appeared in the library
    /// at all: the library renders the catalog, and nothing in the shell reads a capability's own
    /// store. Under D26 they would have had nowhere to be stored.
    ///
    /// **An existing machine is reused rather than duplicated.** Importing an `ssh_config` that
    /// names a machine already in the library adds a service to that machine; it does not stand a
    /// second record beside it with the same address.
    ///
    /// The caller owns what happens next: on failure to write its own record it must call
    /// `discardAdoption(_:)`, exactly as the setup sheet rolls back a draft.
    @discardableResult
    public func adoptService(kind: HostServiceKind, hostName: String, address: String,
                             serviceName: String) async throws -> EndpointID {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else { throw GlassShellError.invalidName }

        let existing = records.first { record in
            guard record.deletedAt == nil, record.id != GlassLocalHost.id,
                  let candidate = record.address else { return false }
            return candidate.compare(trimmedAddress, options: [.caseInsensitive, .diacriticInsensitive])
                == .orderedSame
        }
        let hostID: HostID
        if let existing {
            hostID = canonicalID(for: existing.id)
        } else {
            let name = hostName.trimmingCharacters(in: .whitespacesAndNewlines)
            hostID = try await addHost(displayName: name.isEmpty ? trimmedAddress : name,
                                       address: trimmedAddress).id
        }
        return try await addService(kind: kind, displayName: serviceName, to: hostID).endpointID
    }

    /// Removes a service link **without** asking the capability to clean up after it.
    ///
    /// The distinction from `removeService` is the whole point and is easy to get wrong. The shell
    /// deleting a service must tell the capability (D25). A *capability* deleting its own service
    /// must not be told to delete it again: `removeService` would call straight back into the
    /// capability that is mid-delete, which is at best a no-op it has to defend against and at
    /// worst a loop.
    ///
    /// Used for both directions of D27's cleanup: an adoption whose record then failed to save,
    /// and a record the capability deleted from its own surfaces. Removing the last service
    /// tombstones the record it was on, so a machine created only for that service does not
    /// survive as an empty row.
    public func detachService(_ endpointID: EndpointID) async {
        guard let owner = records.first(where: { record in
            record.services.contains { $0.endpointID == endpointID }
        }) else { return }
        do {
            if isLocalHost(owner.id) {
                try await localCatalog.unpair(endpointID: endpointID, from: owner.id)
            } else {
                try await catalog.unpair(endpointID: endpointID, from: owner.id)
            }
            if preferences[host: owner.id].lastUsedEndpointID == endpointID {
                preferences[host: owner.id].lastUsedEndpointID = nil
                try persistPreferences()
            }
            await load()
        } catch {
            // Best effort: a link that outlives its record shows in the library as a service the
            // capability has nothing for, which the capability already reports honestly on Connect.
            catalogSyncStatus = .failed(error.localizedDescription)
        }
    }

    /// Undoes an `adoptService` whose caller then failed to write its own record.
    public func discardAdoption(_ endpointID: EndpointID) async {
        await detachService(endpointID)
    }

    /// Links a service to the host's canonical record. `endpointID` is the key the owning
    /// capability stored the service's configuration under: the setup sheet commits the
    /// capability's draft first, then records the link, so a service never exists half-made.
    @discardableResult
    public func addService(kind: HostServiceKind, displayName: String, endpointID: EndpointID = EndpointID(),
                           to id: HostID) async throws -> HostServiceLink {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GlassShellError.invalidName }
        let link = HostServiceLink(endpointID: endpointID, kind: kind, displayName: trimmed)
        if isLocalHost(canonicalID(for: id)) {
            try await localCatalog.pair(link, with: GlassLocalHost.id)
        } else {
            try await catalog.pair(link, with: canonicalID(for: id))
        }
        await load()
        return link
    }

    /// Removes the service from whichever member record owns it, then lets the owning
    /// capability delete what it stored for it. The link goes first: a stray configuration is
    /// harmless, a link to nothing is not.
    public func removeService(_ endpointID: EndpointID, from id: HostID) async throws {
        guard let host = host(id) else { throw GlassShellError.hostNotFound(id) }
        if host.isBuiltIn(endpointID) {
            let name = host.services.first { $0.endpointID == endpointID }?.displayName ?? "That service"
            throw GlassShellError.builtInServiceNotEditable(name)
        }
        guard let owner = host.member(owning: endpointID),
              let service = owner.services.first(where: { $0.endpointID == endpointID }) else {
            throw GlassShellError.serviceNotFound(endpointID)
        }
        if host.isLocal {
            try await localCatalog.unpair(endpointID: endpointID, from: owner.id)
        } else {
            try await catalog.unpair(endpointID: endpointID, from: owner.id)
        }
        if preferences[host: host.id].lastUsedEndpointID == endpointID {
            preferences[host: host.id].lastUsedEndpointID = nil
            try persistPreferences()
        }
        await load()
        try await registry.capability(for: service.kind)?.removeService(service, host: owner)
    }

    public func toggleFavorite(_ id: HostID) {
        let canonical = canonicalID(for: id)
        preferences[host: canonical].isFavorite.toggle()
        preferences[host: canonical].favoriteChangedAt = Date()
        do { try persistPreferences() } catch { errorMessage = GlassShellError.message(for: error) }
        pushFavorites()
    }

    // MARK: Favourites on every device (2026-10-08)

    private var favoritesSync: GlassSettingsSyncService<GlassFavoritesPayload>?

    /// Attaches favourites to iCloud. Without it they stay on this device, as they did before.
    public func startSynchronizingFavorites(with service: GlassSettingsSyncService<GlassFavoritesPayload>) async {
        favoritesSync = service
        await service.start(onMerge: { [weak self] incoming in self?.applyFavorites(incoming) })
        pushFavorites()
    }

    /// This device's favourites as the sync carries them. Not the device's own host: every device
    /// has one, under one fixed id, and a favourite "This Mac" is not a favourite "This iPhone".
    public var favoritesPayload: GlassFavoritesPayload {
        var payload = GlassFavoritesPayload()
        for (id, record) in preferences.hosts where id != GlassLocalHost.id
            && (record.isFavorite || record.favoriteChangedAt != nil) {
            payload.marks[id.rawValue.uuidString] = .init(
                isFavorite: record.isFavorite,
                changedAt: record.favoriteChangedAt ?? GlassFavoritesPayload.legacyChange)
        }
        return payload
    }

    /// Takes each newer favourite from another device, under the id this library knows the host
    /// by — another device may still list it under a duplicate's id.
    public func applyFavorites(_ incoming: GlassFavoritesPayload) {
        var changed = false
        for (key, mark) in incoming.marks {
            guard let uuid = UUID(uuidString: key) else { continue }
            let id = canonicalID(for: HostID(rawValue: uuid))
            guard id != GlassLocalHost.id else { continue }
            let current = preferences[host: id]
            let currentMark: GlassFavoritesPayload.Mark?
            if let changedAt = current.favoriteChangedAt {
                currentMark = .init(isFavorite: current.isFavorite, changedAt: changedAt)
            } else {
                currentMark = current.isFavorite ? .init(isFavorite: true, changedAt: GlassFavoritesPayload.legacyChange) : nil
            }
            guard GlassFavoritesPayload.replaces(mark, currentMark) else { continue }
            preferences[host: id].isFavorite = mark.isFavorite
            preferences[host: id].favoriteChangedAt = mark.changedAt
            changed = true
        }
        guard changed else { return }
        do { try persistPreferences() } catch { errorMessage = GlassShellError.message(for: error) }
    }

    private func pushFavorites() {
        guard let favoritesSync else { return }
        let payload = favoritesPayload
        Task { try? await favoritesSync.push(payload) }
    }

    /// Merges a consolidated host's member records into its canonical record **in the catalog**:
    /// every service moves to the canonical record, aliases and tags are unioned, the emptied
    /// members are deleted — and a service the machine now has twice is kept once.
    ///
    /// Written for Stage 6 and held back while the three source applications still read
    /// `hosts.json` by their own record ids. They are obsolete now, and on 2026-09-21 the phone
    /// showed why holding back cost something: eleven records for one server at one address from
    /// three devices, two of them fully configured, grouped into one row whose detail listed the
    /// Mac's Terminal and the phone's Terminal, the Mac's Desktop and the phone's Desktop. So
    /// this runs on its own now — `consolidateDuplicateHosts()` after every load and sync — and
    /// the group projection is what you see only until the next sync makes it one record.
    ///
    /// **Which duplicate survives is decided from the catalog alone**, never from this device's
    /// preferences, so every device reaches the same answer and none of them fights the others:
    /// the same kind and the same name (case-insensitively) is the same service, and the
    /// lexicographically smallest endpoint id keeps it. The losers are removed the way a user
    /// removing them would be — link first, then the owning capability's own record.
    public func consolidateRecords(of id: HostID) async throws {
        guard let host = host(id) else { throw GlassShellError.hostNotFound(id) }
        try await consolidate(host)
        await load()
    }

    /// Every group in the library collapsed to one record. Idempotent; a library with no groups
    /// does nothing and touches nothing, so a device that is already clean publishes nothing.
    func consolidateDuplicateHosts() async {
        let groups = hosts.filter(\.isConsolidated)
        guard !groups.isEmpty else { return }
        for group in groups {
            do { try await consolidate(group) } catch {
                Logger.catalogSync.error("Consolidating \(group.displayName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        // One reload for the whole pass; `consolidate` itself never reloads, which is also what
        // keeps `load()` from calling this and this from calling `load()`.
        records = (try? await catalog.snapshot()) ?? records
        rebuildProjection()
    }

    /// Member records folded into a canonical one by this process, so an id someone is still
    /// holding — a selection, a capability's callback, a test's variable — keeps resolving to
    /// the machine it meant. Preferences are migrated on disk; this covers everything else.
    private var mergedMemberIDs: [HostID: HostID] = [:]

    private func consolidate(_ host: GlassShellHost) async throws {
        guard host.isConsolidated, !host.isLocal else { return }
        // **Only a group that agrees about the address is one machine.** Two records named "db"
        // at two addresses are two machines that share a name, and the design surfaces that
        // disagreement for the user to settle with one edit rather than guessing. Merging them
        // would silently glue a database on one box to a terminal on another.
        guard host.addresses.count <= 1 else { return }
        let survivor = Self.foldTarget(among: host.members)
        for member in host.members where member.id != survivor.id {
            mergedMemberIDs[member.id] = survivor.id
            for link in member.services { try await catalog.move(endpointID: link.endpointID, to: survivor.id) }
            // `move` tombstones a record once its last service leaves; delete only what is left.
            if member.services.isEmpty { try await catalog.delete(hostID: member.id) }
        }
        // Preferences were keyed on the group's canonical id; the survivor may not be it.
        if survivor.id != host.id, preferences.hosts[host.id] != nil, preferences.hosts[survivor.id] == nil {
            preferences.hosts[survivor.id] = preferences.hosts[host.id]
            preferences.hosts[host.id] = nil
            try persistPreferences()
        }
        let fresh = (try await catalog.snapshot()).first { $0.id == survivor.id } ?? survivor
        let (kept, dropped) = Self.deduplicated(fresh.services)
        let merged = try HostProfile(id: fresh.id, displayName: host.displayName, address: host.address, aliases: host.aliases,
                                     services: kept, tags: host.tags, createdAt: fresh.createdAt,
                                     updatedAt: max(Date(), fresh.updatedAt), lastWriterID: preferences.writerID)
        try await catalog.upsert(merged)
        for link in dropped {
            if preferences[host: survivor.id].lastUsedEndpointID == link.endpointID {
                preferences[host: survivor.id].lastUsedEndpointID = nil
                try persistPreferences()
            }
            try await registry.capability(for: link.kind)?.removeService(link, host: merged)
        }
    }

    /// The record a group folds into: **the most recently updated member**, ties to the smallest
    /// id. Not the group's canonical (oldest) record.
    ///
    /// On 2026-09-21 folding into the oldest left a server with no services on the Mac. The oldest live record
    /// in a group is exactly the one most likely to be a tombstone already on another device —
    /// old duplicates are what other devices cleaned up first — and a tombstone beats a live
    /// record in the merge whatever the dates. Every service moved into it went with it. The
    /// most recently updated record is the one every device most recently agreed exists.
    ///
    /// A member with services outranks an empty one, whatever the dates: an empty record is an
    /// adoption that saved a host and then nothing, and folding a machine's services into it
    /// would keep the shell and throw away the one that had been carrying them.
    static func foldTarget(among members: [HostProfile]) -> HostProfile {
        members.max {
            if $0.services.isEmpty != $1.services.isEmpty { return $0.services.isEmpty }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt < $1.updatedAt }
            return $0.id.rawValue.uuidString > $1.id.rawValue.uuidString
        }!
    }

    /// One link per (kind, name); the smallest endpoint id wins so every device agrees. Pure,
    /// and the order of the survivors is the order they were listed in.
    static func deduplicated(_ services: [HostServiceLink]) -> (kept: [HostServiceLink], dropped: [HostServiceLink]) {
        var winners: [String: HostServiceLink] = [:]
        for link in services {
            let key = "\(link.kind.rawValue)|\(link.displayName.lowercased())"
            if let current = winners[key], current.endpointID.rawValue.uuidString <= link.endpointID.rawValue.uuidString { continue }
            winners[key] = link
        }
        let keptIDs = Set(winners.values.map(\.endpointID))
        return (services.filter { keptIDs.contains($0.endpointID) }, services.filter { !keptIDs.contains($0.endpointID) })
    }

    // MARK: Connecting

    /// Connect picks the sole service, else the last-used one if still present,
    /// else the first. Returns the chosen service, or nil if the host has none.
    @discardableResult
    public func connect(hostID: HostID) -> HostServiceLink? {
        let available = services(for: hostID)
        guard let chosen = available.count == 1 ? available.first
            : (lastUsedService(for: hostID) ?? available.first) else { return nil }
        connect(hostID: hostID, endpointID: chosen.endpointID)
        return chosen
    }

    public func connect(hostID: HostID, endpointID: EndpointID) {
        guard let host = host(hostID) else { errorMessage = GlassShellError.hostNotFound(hostID).localizedDescription; return }
        guard host.services.contains(where: { $0.endpointID == endpointID }) else {
            errorMessage = GlassShellError.serviceNotFound(endpointID).localizedDescription; return
        }
        // The user chose this service, so remember it either way; but "last connected" is only
        // true when a capability reports a live session. A failed attempt and a cancelled prompt
        // connect nothing.
        preferences[host: host.id].lastUsedEndpointID = endpointID
        do { try persistPreferences() } catch { errorMessage = GlassShellError.message(for: error) }
        open(endpointID, on: host)
    }

    /// Every service on the host, in the order the host lists them. This is what the library
    /// row's play button does: the machine has three services, the user wants the machine.
    /// It records no "last used" service, because the user picked the host, not one service.
    /// A kind with no capability in this build reports itself and the rest still open.
    ///
    /// **Not offered on the local host (D8).** "Connect the machine" is an act of reaching a box;
    /// this device is already here, and its services are unrelated local things — a shell, a
    /// SQLite file, a MySQL instance, a VM. Opening all of them at once is never what anyone
    /// means, and it is the one host where a mis-click costs a window per service on the display
    /// you are looking at. Its row shows the service picker alone (`GlassShellConnectControl`),
    /// so this is the model-level guarantee behind that, not a second opinion about it.
    public func connectAll(hostID: HostID) {
        guard let host = host(hostID) else { errorMessage = GlassShellError.hostNotFound(hostID).localizedDescription; return }
        guard host.allowsConnectAll else { return }
        guard !host.services.isEmpty else { return }
        for service in host.services { open(service.endpointID, on: host) }
    }

    /// Hands one service to its capability. The capability receives the record that owns the
    /// endpoint — its endpoint id is what the capability's own store is keyed by.
    private func open(_ endpointID: EndpointID, on host: GlassShellHost) {
        guard let service = host.services.first(where: { $0.endpointID == endpointID }),
              let owner = host.record(owning: endpointID) else {
            errorMessage = GlassShellError.serviceNotFound(endpointID).localizedDescription; return
        }
        // A kind no capability in this build owns cannot be connected: say so and connect nothing.
        guard let capability = registry.capability(for: service.kind) else {
            errorMessage = Self.unavailableMessage(for: service.kind)
            return
        }
        let hostID = host.id
        let attempt = UUID()
        connectAttempts[attempt] = .now
        capability.open(service: service, host: owner, hostAccess: hostAccess(for: hostID)) { [weak self] outcome in
            self?.connectAttempts[attempt] = nil
            guard let self, case .connected = outcome else { return }
            let now = Date()
            self.preferences[host: hostID].lastConnected = now
            self.preferences.recordConnection(.init(date: now, hostID: hostID, kind: service.kind))
            do { try self.persistPreferences() } catch { self.errorMessage = GlassShellError.message(for: error) }
        }
    }

    /// What the shell says about a kind this build has no capability for.
    public static func unavailableMessage(for kind: HostServiceKind) -> String {
        "\(GlassServicePresentation.displayName(for: kind)) is not part of this build yet. Nothing was connected."
    }

    #if DEBUG
    private var didSeedHostsForUITesting = false
    private var didSeedLocalServicesForUITesting = false

    /// UI tests seed the isolated catalog through a launch argument, because the runner cannot
    /// reach the app's container on iOS or visionOS:
    /// `--ui-testing-seed-hosts "bravo:ssh|bravo:rdp|alpha:ssh+database"` creates one record
    /// per `|` entry, named before the colon, with one service per `+`-separated kind; a name may
    /// carry the host's address after `@` (`bravo@192.0.2.6:ssh`) and its collections after `#`,
    /// comma-separated (`alpha#Production,Home:ssh`). Only honoured alongside
    /// `--ui-testing`, only into a catalog that is not under a real Group Container, and only when
    /// that catalog is empty.
    private func seedForUITestingIfRequested() async throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-testing"),
              let index = arguments.firstIndex(of: "--ui-testing-seed-hosts"), arguments.indices.contains(index + 1),
              !catalogFileURL.path.contains("Group Containers"), !didSeedHostsForUITesting else { return }
        // Claimed before the first await. `load()` has two callers — the library's `.task` and
        // its scene-phase observer — which can interleave, and an emptiness check made *after*
        // an await is passed by both of them, seeding the same hosts twice.
        didSeedHostsForUITesting = true
        guard try await catalog.snapshot().isEmpty else { return }
        for (offset, entry) in arguments[index + 1].split(separator: "|").enumerated() {
            let parts = entry.split(separator: ":", maxSplits: 1)
            guard let head = parts.first.map(String.init), !head.isEmpty else { continue }
            let headParts = head.split(separator: "#", maxSplits: 1).map(String.init)
            let nameAndAddress = headParts[0]
            let tags = headParts.count > 1 ? headParts[1].split(separator: ",").map(String.init) : []
            let nameParts = nameAndAddress.split(separator: "@", maxSplits: 1).map(String.init)
            let name = nameParts[0]
            let address = nameParts.count > 1 ? nameParts[1] : nil
            guard !name.isEmpty else { continue }
            let kinds = parts.count > 1 ? parts[1].split(separator: "+").compactMap { HostServiceKind(rawValue: String($0)) } : []
            let services = kinds.map {
                HostServiceLink(endpointID: EndpointID(), kind: $0, displayName: "\(GlassServicePresentation.displayName(for: $0)) on \(name)")
            }
            let created = Date(timeIntervalSince1970: 1_700_000_000 + Double(offset))
            var host = try HostProfile(displayName: name, address: address, aliases: [], services: services,
                                       createdAt: created, updatedAt: created, lastWriterID: writerID)
            host.tags = tags
            try await catalog.upsert(host)
        }
    }
    #endif

    #if DEBUG
    /// The device's own host cannot be seeded through `--ui-testing-seed-hosts`, which writes the
    /// shared catalog, so it has its own argument with the same shape and the same guards:
    /// `--ui-testing-seed-local-services "database:notes.sqlite|database:gpt_test"` pairs one link
    /// per `|` entry, kind before the colon. Only alongside `--ui-testing`, only into a store
    /// outside a real Group Container, and only when the host has no services yet.
    private func seedLocalServicesForUITestingIfRequested(on record: HostProfile) async throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-testing"),
              let index = arguments.firstIndex(of: "--ui-testing-seed-local-services"),
              arguments.indices.contains(index + 1),
              !localCatalogFileURL.path.contains("Group Containers"),
              !didSeedLocalServicesForUITesting, record.services.isEmpty else { return }
        // One shot, claimed before the first await: see `seedForUITestingIfRequested`.
        didSeedLocalServicesForUITesting = true
        for entry in arguments[index + 1].split(separator: "|") {
            let parts = entry.split(separator: ":", maxSplits: 1)
            guard let kind = parts.first.flatMap({ HostServiceKind(rawValue: String($0)) }) else { continue }
            let name = parts.count > 1 ? String(parts[1]) : GlassServicePresentation.displayName(for: kind)
            guard !name.isEmpty else { continue }
            try await localCatalog.pair(HostServiceLink(endpointID: EndpointID(), kind: kind, displayName: name),
                                        with: GlassLocalHost.id)
        }
    }
    #endif

    private func switchToLocalCatalog(reason: String) {
        catalogFileURL = storageDirectory.appendingPathComponent(Self.catalogRelativePath)
        catalog = HostCatalogStore(fileURL: catalogFileURL, writerID: writerID)
        hasSharedContainer = false
        hostLibraryStatus = reason
        errorMessage = nil
    }

    /// EACCES/EPERM from the kit's lock, or Cocoa's no-permission codes from directory creation.
    static func isPermissionDenied(_ error: Error) -> Bool {
        if case HostCatalogError.fileLockFailed(let code) = error { return code == EACCES || code == EPERM }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain {
            return [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(ns.code)
                || (ns.underlyingErrors.first.map(isPermissionDenied) ?? false)
        }
        return ns.domain == NSPOSIXErrorDomain && (ns.code == Int(EACCES) || ns.code == Int(EPERM))
    }

    private func persistPreferences() throws {
        guard !preferencesReadOnly else { throw GlassShellError.preferencesReadOnly }
        try preferencesStore.save(preferences)
    }
}

/// The catalog sync's log. Module-wide rather than private to the CloudKit backend: the model's
/// own reconcile is where a failure actually stops a publish, and that is what went unrecorded.
extension Logger {
    static let catalogSync = Logger(subsystem: "com.glasspowertools", category: "catalog-sync")
}
