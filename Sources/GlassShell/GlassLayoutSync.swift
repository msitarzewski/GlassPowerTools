//
//  GlassLayoutSync.swift
//  Glass Power Tools — GlassShell
//
//  Moves the shared layout (`GlassLayout`) between this device and the account: reads the account whole, publishes
//  what this device has open, and closes in the layout what it published and has no longer. One pass at a time, as
//  the library's sync runs. The rules are `GlassLayoutPublishing`'s and `GlassLayoutMerge`'s; nothing here decides.
//

import Foundation
import Observation
import os

@MainActor @Observable
public final class GlassLayoutSync {
    /// The account's layout as last read, with this device's saves taken in.
    public private(set) var account = GlassLayout()
    public private(set) var status: GlassCatalogSyncStatus = .idle
    /// Whether the account has been read at least once since launch. Nothing is published before: what stands there
    /// decides what to send, and what this device closed since its last run is found only against it.
    public private(set) var hasRead = false

    @ObservationIgnored private let backend: any GlassLayoutSyncBackend
    /// What this device has open now; nil until every capability can say.
    @ObservationIgnored private let snapshot: @MainActor () -> GlassLayoutSnapshot?
    /// The windows and tabs this device has published as open, kept across launches.
    @ObservationIgnored private let loadPublished: @MainActor () -> Set<UUID>
    @ObservationIgnored private let savePublished: @MainActor (Set<UUID>) -> Void
    @ObservationIgnored private let device: @MainActor () -> (key: String, name: String)
    @ObservationIgnored private let now: @MainActor () -> Date

    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var againFetching: Bool?
    @ObservationIgnored private var soon: Task<Void, Never>?
    @ObservationIgnored private var due: Task<Void, Never>?
    /// After a failed pass, changes here wait this long before trying again: a terminal's title changes every second,
    /// and a store refusing every save (iCloud signed out, or a schema not deployed) would be asked as often, which
    /// iCloud answers by limiting the app, the library's sync included. Thirty seconds, doubling to fifteen minutes; a
    /// pass that reads (launch, foreground, a push) always runs.
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private(set) var retryAfter: Date?
    static let firstRetry: TimeInterval = 30
    static let longestRetry: TimeInterval = 15 * 60

    public init(backend: any GlassLayoutSyncBackend,
                snapshot: @escaping @MainActor () -> GlassLayoutSnapshot?,
                loadPublished: @escaping @MainActor () -> Set<UUID>,
                savePublished: @escaping @MainActor (Set<UUID>) -> Void,
                device: @escaping @MainActor () -> (key: String, name: String),
                now: @escaping @MainActor () -> Date = { Date() }) {
        self.backend = backend
        self.snapshot = snapshot
        self.loadPublished = loadPublished
        self.savePublished = savePublished
        self.device = device
        self.now = now
    }

    /// What this device has open changed: published a moment later, so a burst of changes is one save.
    public func publishSoon(after delay: Duration = .seconds(1)) {
        soon?.cancel()
        soon = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.synchronize(fetching: false)
        }
    }

    /// One pass: the account read (when `fetching`, or never read yet), then what this device has open sent. A caller
    /// arriving mid-pass gets one more pass, fetching if either asked to, and waits for it.
    public func synchronize(fetching: Bool = true) async {
        if let running {
            againFetching = (againFetching ?? false) || fetching
            await running.value
            return
        }
        let task = Task { @MainActor in
            var fetch = fetching
            repeat {
                againFetching = nil
                await once(fetching: fetch)
                fetch = againFetching ?? false
            } while againFetching != nil
            running = nil
        }
        running = task
        await task.value
    }

    private func once(fetching: Bool) async {
        // Waiting after a failure: what changed here goes out once the wait is over (`schedule`), or with the next read.
        if !fetching, let retryAfter, now() < retryAfter { return }
        status = .syncing
        do {
            if fetching || !hasRead {
                account = GlassLayout(try await backend.fetchAll())
                hasRead = true
            }
            if let snapshot = snapshot() {
                let me = device()
                let outcome = GlassLayoutPublishing.outcome(snapshot: snapshot, account: account,
                                                             published: loadPublished(), device: me.key,
                                                             deviceName: me.name, now: now())
                try await backend.save(outcome.items)
                for item in outcome.items { account.take(item) }
                savePublished(outcome.published)
                schedule(outcome.nextDue)
            }
            let expired = GlassLayoutPublishing.expired(in: account, now: now())
            if !expired.isEmpty {
                try await backend.remove(expired)
                account = GlassLayout(account.items.filter { !expired.contains($0) })
            }
            failures = 0
            retryAfter = nil
            status = .synced(now())
        } catch {
            failures += 1
            let wait = min(Self.longestRetry, Self.firstRetry * pow(2, Double(failures - 1)))
            retryAfter = now().addingTimeInterval(wait)
            schedule(retryAfter)
            Logger.layoutSync.error("Layout sync failed, trying again in \(Int(wait), privacy: .public) s: \(String(describing: error), privacy: .public)")
            status = GlassCatalogSyncStatus.after(error)
        }
    }

    /// A title held back is sent when it's due.
    private func schedule(_ next: Date?) {
        due?.cancel()
        guard let next else { return }
        let wait = max(0, next.timeIntervalSince(now()))
        due = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            await self?.synchronize(fetching: false)
        }
    }
}
