import Foundation
import Testing
import GlassConnectionKit
@testable import GlassShell

/// The shared layout's records, merge and publishing (phase 1, 2026-11-22; plan in
/// memory-bank/tasks/2026-11/2026-11-21_shared-layout.md).
@Suite("One layout on every device: records, merge, publishing")
struct GlassLayoutTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let alpha = EndpointID()

    func window(_ id: UUID, _ name: String = "w", at date: Date, deleted: Date? = nil,
                device: String = "mac") -> GlassLayoutWindow {
        GlassLayoutWindow(id: id, name: name, device: device, deviceName: device, updatedAt: date, deletedAt: deleted)
    }

    func tab(_ id: UUID, in windowID: UUID, at date: Date, title: String = "t", position: Double = 0, session: String = "glass-1",
             deleted: Date? = nil) -> GlassLayoutTab {
        GlassLayoutTab(id: id, windowID: windowID, position: position, title: title, endpointID: alpha,
                       tmuxSession: session, tmuxCreated: 100, shellDevice: nil, shellDeviceName: nil,
                       splitGroup: nil, updatedAt: date, deletedAt: deleted)
    }

    @Test("the later version of a record stands, a tombstone included; at one instant the tombstone does")
    func laterWins() {
        let id = UUID()
        var layout = GlassLayout([.window(window(id, "old", at: t0))])
        let newer = layout.take(.window(window(id, "new", at: t0 + 1)))
        #expect(newer)
        #expect(layout.windows[id]?.name == "new")
        let older = layout.take(.window(window(id, "older", at: t0 - 5)))
        #expect(!older, "an older version is passed over")
        let closed = layout.take(.window(window(id, "new", at: t0 + 2, deleted: t0 + 2)))
        #expect(closed, "closed later: closed")
        #expect(layout.openWindows.isEmpty)
        let again = layout.take(.window(window(id, "again", at: t0 + 3)))
        #expect(again, "opened again later by its id: open")
        #expect(layout.openWindows.map(\.name) == ["again"])

        let other = UUID()
        var tie = GlassLayout([.window(window(other, "open", at: t0))])
        tie.take(.window(window(other, "open", at: t0, deleted: t0)))
        #expect(tie.windows[other]?.deletedAt != nil, "the same instant: the tombstone")
        var tieOtherOrder = GlassLayout([.window(window(other, "open", at: t0, deleted: t0))])
        tieOtherOrder.take(.window(window(other, "open", at: t0)))
        #expect(tieOtherOrder.windows[other]?.deletedAt != nil, "whichever arrives first")
    }

    @Test("a record in a schema this build doesn't know is left as it is, never taken")
    func unknownSchema() {
        let id = UUID()
        var newer = window(id, "from a newer build", at: t0)
        newer.schemaVersion = GlassLayoutWindow.currentSchemaVersion + 1
        var layout = GlassLayout()
        let taken = layout.take(.window(newer))
        #expect(!taken)
        #expect(layout.windows.isEmpty)
    }

    @Test("two devices adding a tab to one window at once: both tabs stand, in their places")
    func concurrentAdds() {
        let w = UUID(), a = UUID(), b = UUID()
        var mac = GlassLayout([.window(window(w, at: t0)), .tab(tab(a, in: w, at: t0 + 1, title: "on the Mac", position: 1))])
        let headset = GlassLayout([.window(window(w, at: t0)), .tab(tab(b, in: w, at: t0 + 1, title: "on the headset", position: 2, session: "glass-2"))])
        for item in headset.items { mac.take(item) }
        #expect(mac.openTabs(in: w).map(\.title) == ["on the Mac", "on the headset"])
    }

    @Test("one tmux session shown twice in a window, by two devices' terminals, is listed once")
    func sameSessionOnce() {
        let w = UUID()
        let layout = GlassLayout([.window(window(w, at: t0)),
                                  .tab(tab(UUID(), in: w, at: t0, title: "first", position: 0)),
                                  .tab(tab(UUID(), in: w, at: t0, title: "second", position: 1))])
        #expect(layout.openTabs(in: w).map(\.title) == ["first"])
    }

    // MARK: Publishing

    func snapshot(_ windows: [GlassLayoutSnapshot.Window]) -> GlassLayoutSnapshot { GlassLayoutSnapshot(windows: windows) }

    func snapTab(_ id: UUID, _ title: String = "t", tmux: String? = "glass-1", shell: Bool = false) -> GlassLayoutSnapshot.Tab {
        GlassLayoutSnapshot.Tab(id: id, title: title, endpointID: alpha, tmuxSession: shell ? nil : tmux,
                                tmuxCreated: shell ? nil : 100, isShellHere: shell)
    }

    @Test("what is open here is published once; nothing again while it stands unchanged")
    func publishesOnce() {
        let w = UUID(), a = UUID(), b = UUID()
        let open = snapshot([.init(id: w, name: "Work", tabs: [snapTab(a, "one"), snapTab(b, "two", shell: true)])])
        let first = GlassLayoutPublishing.outcome(snapshot: open, account: GlassLayout(), published: [],
                                                  device: "mac", deviceName: "Mac", now: t0)
        #expect(first.items.count == 3)
        #expect(first.published == [w, a, b])
        var account = GlassLayout(first.items)
        let shellTab = account.tabs[b]
        #expect(shellTab?.shellDevice == "mac" && shellTab?.shellDeviceName == "Mac" && shellTab?.isInTmux == false,
                "a shell not in tmux is this device's alone")
        #expect(account.openTabs(in: w).map(\.title) == ["one", "two"])

        let again = GlassLayoutPublishing.outcome(snapshot: open, account: account, published: first.published,
                                                  device: "mac", deviceName: "Mac", now: t0 + 5)
        #expect(again.items.isEmpty)

        // A tab moved to another place: sent.
        let moved = snapshot([.init(id: w, name: "Work", tabs: [snapTab(b, "two", shell: true), snapTab(a, "one")])])
        let reordered = GlassLayoutPublishing.outcome(snapshot: moved, account: account, published: again.published,
                                                      device: "mac", deviceName: "Mac", now: t0 + 6)
        #expect(reordered.items.count == 2)
        for item in reordered.items { account.take(item) }
        #expect(account.openTabs(in: w).map(\.title) == ["two", "one"])
    }

    @Test("a title alone goes at most once a minute, and says when it's due")
    func titlesHeldBack() {
        let w = UUID(), a = UUID()
        let first = GlassLayoutPublishing.outcome(snapshot: snapshot([.init(id: w, name: "Work", tabs: [snapTab(a, "one")])]),
                                                  account: GlassLayout(), published: [], device: "mac", deviceName: "Mac", now: t0)
        let account = GlassLayout(first.items)
        let renamed = snapshot([.init(id: w, name: "Work", tabs: [snapTab(a, "✳ Fixing the build")])])
        let soon = GlassLayoutPublishing.outcome(snapshot: renamed, account: account, published: first.published,
                                                 device: "mac", deviceName: "Mac", now: t0 + 10)
        #expect(soon.items.isEmpty)
        #expect(soon.nextDue == t0 + GlassLayoutPublishing.titleInterval)
        let later = GlassLayoutPublishing.outcome(snapshot: renamed, account: account, published: first.published,
                                                  device: "mac", deviceName: "Mac", now: t0 + 61)
        #expect(later.items.count == 1)
        #expect(later.nextDue == nil)
    }

    @Test("a window gone from here is closed in the layout with its tabs; another device's are left alone")
    func closesWhatItPublished() {
        let mine = UUID(), mineTab = UUID(), theirs = UUID(), theirTab = UUID()
        let first = GlassLayoutPublishing.outcome(snapshot: snapshot([.init(id: mine, name: "Mine", tabs: [snapTab(mineTab)])]),
                                                  account: GlassLayout(), published: [], device: "mac", deviceName: "Mac", now: t0)
        var account = GlassLayout(first.items + [.window(window(theirs, "Theirs", at: t0, device: "headset")),
                                                 .tab(tab(theirTab, in: theirs, at: t0))])
        let closed = GlassLayoutPublishing.outcome(snapshot: snapshot([]), account: account, published: first.published,
                                                   device: "mac", deviceName: "Mac", now: t0 + 1)
        #expect(Set(closed.items.map(\.recordName)) == ["window-\(mine.uuidString.lowercased())",
                                                        "tab-\(mineTab.uuidString.lowercased())"])
        #expect(closed.items.allSatisfy { $0.deletedAt == t0 + 1 })
        #expect(closed.published.isEmpty)
        for item in closed.items { account.take(item) }
        #expect(account.openWindows.map(\.name) == ["Theirs"])
    }

    @Test("tombstones a month old are removed for good; newer ones and open records stay")
    func expiry() {
        let old = UUID(), recent = UUID(), open = UUID()
        let account = GlassLayout([.window(window(old, at: t0, deleted: t0)),
                                   .window(window(recent, at: t0 + 86_400 * 20, deleted: t0 + 86_400 * 20)),
                                   .window(window(open, at: t0))])
        let gone = GlassLayoutPublishing.expired(in: account, now: t0 + GlassLayoutPublishing.tombstoneLifetime + 1)
        #expect(gone.map(\.recordName) == ["window-\(old.uuidString.lowercased())"])
    }
}

/// The sync pass, against a store in memory.
@Suite("One layout on every device: the sync")
@MainActor
struct GlassLayoutSyncTests {
    actor Store: GlassLayoutSyncBackend {
        var records: [String: GlassLayoutItem] = [:]
        var saves = 0
        var attempts = 0
        var failing = false
        func fetchAll() async throws -> [GlassLayoutItem] { Array(records.values) }
        func save(_ items: [GlassLayoutItem]) async throws {
            attempts += 1
            if failing { throw CancellationError() }
            saves += 1
            for item in items { records[item.recordName] = item }
        }
        func remove(_ items: [GlassLayoutItem]) async throws {
            for item in items { records[item.recordName] = nil }
        }
        func setFailing(_ value: Bool) { failing = value }
        func put(_ item: GlassLayoutItem) { records[item.recordName] = item }
    }

    final class Device {
        var snapshot: GlassLayoutSnapshot?
        var published: Set<UUID> = []
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
    }

    func sync(_ store: Store, _ device: Device, key: String = "mac") -> GlassLayoutSync {
        GlassLayoutSync(backend: store, snapshot: { device.snapshot }, loadPublished: { device.published },
                        savePublished: { device.published = $0 }, device: { (key, key.capitalized) },
                        now: { device.clock })
    }

    @Test("nothing is sent or closed until this device can say what it has open")
    func waitsUntilReady() async {
        let store = Store()
        let device = Device()
        let earlier = UUID()
        device.published = [earlier]
        await store.put(.window(GlassLayoutWindow(id: earlier, name: "Last run's", device: "mac", deviceName: "Mac",
                                                  updatedAt: device.clock - 100)))
        let layout = sync(store, device)
        await layout.synchronize()
        #expect(await store.saves == 0, "not ready: nothing sent")
        #expect(layout.account.openWindows.map(\.name) == ["Last run's"], "and nothing taken as closed")
        #expect(device.published == [earlier])

        device.snapshot = GlassLayoutSnapshot(windows: [])
        await layout.synchronize(fetching: false)
        #expect(layout.account.openWindows.isEmpty, "ready, without it: the last run's window is closed")
        #expect(device.published.isEmpty)
    }

    @Test("after a failed save, changes here wait: thirty seconds, then twice as long; a read always runs")
    func waitsAfterFailing() async {
        let store = Store()
        let device = Device()
        device.snapshot = GlassLayoutSnapshot(windows: [.init(id: UUID(), name: "Work", tabs: [])])
        await store.setFailing(true)
        let layout = sync(store, device)
        await layout.synchronize()
        #expect(await store.attempts == 1)
        await layout.synchronize(fetching: false)
        #expect(await store.attempts == 1, "a change a moment later waits")
        device.clock += GlassLayoutSync.firstRetry + 1
        await layout.synchronize(fetching: false)
        #expect(await store.attempts == 2, "after thirty seconds it's tried again")
        device.clock += GlassLayoutSync.firstRetry + 1
        await layout.synchronize(fetching: false)
        #expect(await store.attempts == 2, "then it waits a minute")
        await layout.synchronize()
        #expect(await store.attempts == 3, "a read (the app back in front, a push) tries at once")
        await store.setFailing(false)
        await layout.synchronize()
        #expect(layout.retryAfter == nil, "and once it works, nothing waits")
    }

    @Test("the first pass reads the account even when only publishing, so a window closed since the last run is found")
    func firstPassReads() async {
        let store = Store()
        let device = Device()
        let earlier = UUID()
        device.published = [earlier]
        device.snapshot = GlassLayoutSnapshot(windows: [])
        await store.put(.window(GlassLayoutWindow(id: earlier, name: "Last run's", device: "mac", deviceName: "Mac",
                                                  updatedAt: device.clock - 100)))
        let layout = sync(store, device)
        await layout.synchronize(fetching: false)
        #expect(await store.records.values.allSatisfy { $0.deletedAt != nil }, "closed in the account")
        #expect(device.published.isEmpty)
    }

    @Test("another device's windows are read and listed; this device's go out, and a failed save keeps what was published")
    func twoDevices() async {
        let store = Store()
        let mac = Device(), headset = Device()
        let w = UUID(), a = UUID()
        mac.snapshot = GlassLayoutSnapshot(windows: [.init(id: w, name: "Work", tabs: [
            .init(id: a, title: "claude", endpointID: EndpointID(), tmuxSession: "glass-3", tmuxCreated: 5, isShellHere: false)])])
        headset.snapshot = GlassLayoutSnapshot(windows: [])
        let macSync = sync(store, mac), headsetSync = sync(store, headset, key: "headset")
        await macSync.synchronize()
        await headsetSync.synchronize()
        #expect(headsetSync.account.openWindows.map(\.name) == ["Work"])
        #expect(headsetSync.account.openTabs(in: w).map(\.tmuxSession) == ["glass-3"])
        #expect(headset.published.isEmpty, "the headset publishes none of the Mac's")

        await store.setFailing(true)
        mac.snapshot = GlassLayoutSnapshot(windows: [])
        mac.clock += 10
        await macSync.synchronize()
        #expect(mac.published == [w, a], "not saved: still published, so the close is tried again")
        if case .failed = macSync.status {} else { Issue.record("a failed save is said: \(macSync.status)") }
        await store.setFailing(false)
        await macSync.synchronize()
        #expect(mac.published.isEmpty)
        await headsetSync.synchronize()
        #expect(headsetSync.account.openWindows.isEmpty)
    }
}
