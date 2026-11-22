//
//  GlassLayout.swift
//  Glass Power Tools — GlassShell
//
//  One layout on every device (the owner, 2026-11-21: "should we consider a global sync of windows/tabs/etc where
//  when I add a new tab on mac it appears available on ViionOS etc."; 2026-11-22: "If I add a tab to a window on my mac
//  with Vision Pro, then it should show on the Mac, too. Same window and tab."). The account's terminal windows and
//  their tabs, kept in iCloud. Plan and phases: memory-bank/tasks/2026-11/2026-11-21_shared-layout.md.
//
//  **Phase 1 (2026-11-22): published and listed, nothing opens by itself.** Each device publishes the windows it has
//  open and their tabs; Active lists the other devices'. Following, closing everywhere and Reopen Last Closed Window
//  come in later phases, on these records.
//
//  **A record per window and a record per tab**, so two devices adding tabs at once both land, and a tab moved
//  between windows is one record changed. Each record is merged on its own: the later `updatedAt` wins, a tombstone
//  (`deletedAt`) included, so a window closed and later opened again by its id comes back (a Vision Pro window is a
//  saved Workgroup's id). Ties go to the tombstone, then to the bytes, so every device picks the same one.
//
//  **Nothing in a record says where a machine is or who signs in.** A tab names its machine by the library's
//  service id, which every device's synced library resolves (D26), and a tmux session by its name and when tmux made
//  it (D111); a shell not kept in tmux by the device it lives on, which alone can show it.
//

import Foundation
import GlassConnectionKit

/// One window of the shared layout.
public struct GlassLayoutWindow: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// Records with another schema are skipped, never rewritten: an older build can't take a newer one's fields away.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public let id: UUID
    /// What the window is called where it is open.
    public var name: String
    /// The device it was published from, by its writer id, and what that device is called.
    public var device: String
    public var deviceName: String
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, name: String, device: String, deviceName: String, updatedAt: Date, deletedAt: Date? = nil) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.name = name
        self.device = device
        self.deviceName = deviceName
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

/// One tab of a window in the shared layout: one terminal. A Mac tab split into panes is one of these per pane, sharing
/// a `splitGroup`.
public struct GlassLayoutTab: Codable, Equatable, Hashable, Sendable, Identifiable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public let id: UUID
    public var windowID: UUID
    /// Its place in the window: tabs are shown in increasing order.
    public var position: Double
    /// What it is called: the name its own device shows.
    public var title: String
    /// The machine's terminal service (D26). Nil for a shell on a Mac that isn't linked to a machine of its own (D86),
    /// which only that Mac can show.
    public var endpointID: EndpointID?
    /// The tmux session it shows, and when tmux made it (D111). Nil for a shell not kept in tmux.
    public var tmuxSession: String?
    public var tmuxCreated: Int?
    /// A shell not kept in tmux: the device it lives on, by writer id, and that device's name. It can't be opened anywhere
    /// else: whatever runs in it lives only there (the owner, 2026-11-22: "We never knwo what's in then and running").
    public var shellDevice: String?
    public var shellDeviceName: String?
    /// The panes of one Mac tab split into several share this.
    public var splitGroup: UUID?
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, windowID: UUID, position: Double, title: String, endpointID: EndpointID?,
                tmuxSession: String?, tmuxCreated: Int?, shellDevice: String?, shellDeviceName: String?,
                splitGroup: UUID?, updatedAt: Date, deletedAt: Date? = nil) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.windowID = windowID
        self.position = position
        self.title = title
        self.endpointID = endpointID
        self.tmuxSession = tmuxSession
        self.tmuxCreated = tmuxCreated
        self.shellDevice = shellDevice
        self.shellDeviceName = shellDeviceName
        self.splitGroup = splitGroup
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// Kept in tmux, so another device can join it.
    public var isInTmux: Bool { tmuxSession != nil && shellDevice == nil }
}

/// A record of the layout as it travels: a window or a tab.
public enum GlassLayoutItem: Codable, Equatable, Hashable, Sendable {
    case window(GlassLayoutWindow)
    case tab(GlassLayoutTab)

    /// The record's name in the store: kind and id, so a window and a tab never collide.
    public var recordName: String {
        switch self {
        case .window(let window): "window-\(window.id.uuidString.lowercased())"
        case .tab(let tab): "tab-\(tab.id.uuidString.lowercased())"
        }
    }

    public var updatedAt: Date {
        switch self {
        case .window(let window): window.updatedAt
        case .tab(let tab): tab.updatedAt
        }
    }

    public var deletedAt: Date? {
        switch self {
        case .window(let window): window.deletedAt
        case .tab(let tab): tab.deletedAt
        }
    }

    var schemaVersion: Int {
        switch self {
        case .window(let window): window.schemaVersion
        case .tab(let tab): tab.schemaVersion
        }
    }

    /// Written in a schema this build knows.
    public var isReadable: Bool {
        switch self {
        case .window(let window): window.schemaVersion == GlassLayoutWindow.currentSchemaVersion
        case .tab(let tab): tab.schemaVersion == GlassLayoutTab.currentSchemaVersion
        }
    }
}

/// The account's layout as last read: every window and tab, tombstones included.
public struct GlassLayout: Equatable, Sendable {
    public private(set) var windows: [UUID: GlassLayoutWindow] = [:]
    public private(set) var tabs: [UUID: GlassLayoutTab] = [:]

    public init(_ items: [GlassLayoutItem] = []) {
        for item in items { take(item) }
    }

    /// Every record, for publishing or comparing.
    public var items: [GlassLayoutItem] {
        windows.values.map(GlassLayoutItem.window) + tabs.values.map(GlassLayoutItem.tab)
    }

    /// Takes a record when it wins over the one held (`GlassLayoutMerge.wins`). True when it was taken.
    @discardableResult
    public mutating func take(_ item: GlassLayoutItem) -> Bool {
        guard item.isReadable else { return false }
        switch item {
        case .window(let window):
            if let held = windows[window.id], !GlassLayoutMerge.wins(item, over: .window(held)) { return false }
            windows[window.id] = window
        case .tab(let tab):
            if let held = tabs[tab.id], !GlassLayoutMerge.wins(item, over: .tab(held)) { return false }
            tabs[tab.id] = tab
        }
        return true
    }

    /// The windows open, oldest name first within a device.
    public var openWindows: [GlassLayoutWindow] {
        windows.values.filter { $0.deletedAt == nil }
            .sorted { ($0.deviceName, $0.name, $0.id.uuidString) < ($1.deviceName, $1.name, $1.id.uuidString) }
    }

    /// A window's open tabs in their order. A tmux session shown twice in one window (two devices published the same
    /// window, each with its own terminal in it) is listed once.
    public func openTabs(in windowID: UUID) -> [GlassLayoutTab] {
        var seen = Set<String>()
        return tabs.values
            .filter { $0.windowID == windowID && $0.deletedAt == nil }
            .sorted { ($0.position, $0.id.uuidString) < ($1.position, $1.id.uuidString) }
            .filter { tab in
                guard tab.isInTmux, let endpoint = tab.endpointID, let session = tab.tmuxSession else { return true }
                return seen.insert("\(endpoint.rawValue.uuidString)|\(session)|\(tab.tmuxCreated ?? 0)").inserted
            }
    }
}

/// Which of two versions of one record stands.
public enum GlassLayoutMerge {
    /// The later `updatedAt` wins, a tombstone included: a window closed and later opened again by its id comes back.
    /// At the same instant (within half a millisecond, as `GlassCatalogMerge` reads a date that went through a store)
    /// the tombstone wins, then the larger encoding, so every device picks the same one.
    public static func wins(_ candidate: GlassLayoutItem, over held: GlassLayoutItem) -> Bool {
        let difference = candidate.updatedAt.timeIntervalSince(held.updatedAt)
        if difference > 0.0005 { return true }
        if difference < -0.0005 { return false }
        switch (candidate.deletedAt != nil, held.deletedAt != nil) {
        case (true, false): return true
        case (false, true): return false
        default: return encoded(candidate) > encoded(held)
        }
    }

    private static func encoded(_ item: GlassLayoutItem) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .secondsSince1970
        return (try? encoder.encode(item)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}

// MARK: - What a device has open

/// The windows a capability has open on this device, as the layout needs them. Nil from a capability that isn't ready
/// to say (still putting back the last run's windows): nothing is published, and nothing is taken as closed, until it
/// is.
public struct GlassLayoutSnapshot: Equatable, Sendable {
    public struct Window: Equatable, Sendable {
        public let id: UUID
        public var name: String
        public var tabs: [Tab]

        public init(id: UUID, name: String, tabs: [Tab]) {
            self.id = id
            self.name = name
            self.tabs = tabs
        }
    }

    public struct Tab: Equatable, Sendable {
        public let id: UUID
        public var title: String
        public var endpointID: EndpointID?
        public var tmuxSession: String?
        public var tmuxCreated: Int?
        /// Not kept in tmux: it lives on this device alone.
        public var isShellHere: Bool
        public var splitGroup: UUID?

        public init(id: UUID, title: String, endpointID: EndpointID?, tmuxSession: String?, tmuxCreated: Int?,
                    isShellHere: Bool, splitGroup: UUID? = nil) {
            self.id = id
            self.title = title
            self.endpointID = endpointID
            self.tmuxSession = tmuxSession
            self.tmuxCreated = tmuxCreated
            self.isShellHere = isShellHere
            self.splitGroup = splitGroup
        }
    }

    public var windows: [Window]

    public init(windows: [Window]) {
        self.windows = windows
    }
}

/// What this device sends: its open windows and tabs as records, those it published before and has no longer as
/// tombstones, and nothing that already stands in the account.
public enum GlassLayoutPublishing {
    /// A tab's title changes as its program works (Claude Code names its task); it's sent at most this often, so a busy
    /// terminal isn't a stream of saves. Anything else about a tab goes at once.
    public static let titleInterval: TimeInterval = 60

    public struct Outcome: Equatable {
        /// Records to save.
        public var items: [GlassLayoutItem]
        /// The windows and tabs this device has published as open, after these are saved.
        public var published: Set<UUID>
        /// When a title held back by `titleInterval` is due, if one was.
        public var nextDue: Date?
    }

    /// - Parameters:
    ///   - snapshot: what this device has open now.
    ///   - account: the layout as last read, with this device's own saves taken in.
    ///   - published: the windows and tabs this device published as open before (kept across launches), so one gone
    ///     since is closed in the layout — never one another device published.
    public static func outcome(snapshot: GlassLayoutSnapshot, account: GlassLayout, published: Set<UUID>,
                               device: String, deviceName: String, now: Date) -> Outcome {
        var items: [GlassLayoutItem] = []
        var open = Set<UUID>()
        var nextDue: Date?

        for window in snapshot.windows {
            open.insert(window.id)
            let held = account.windows[window.id]
            if held == nil || held?.deletedAt != nil || held?.name != window.name {
                items.append(.window(GlassLayoutWindow(id: window.id, name: window.name, device: device,
                                                       deviceName: deviceName, updatedAt: now)))
            }
            for (index, tab) in window.tabs.enumerated() {
                open.insert(tab.id)
                let wanted = GlassLayoutTab(
                    id: tab.id, windowID: window.id, position: Double(index), title: tab.title,
                    endpointID: tab.endpointID, tmuxSession: tab.tmuxSession, tmuxCreated: tab.tmuxCreated,
                    shellDevice: tab.isShellHere ? device : nil, shellDeviceName: tab.isShellHere ? deviceName : nil,
                    splitGroup: tab.splitGroup, updatedAt: now)
                guard let heldTab = account.tabs[tab.id], heldTab.deletedAt == nil else {
                    items.append(.tab(wanted))
                    continue
                }
                var same = heldTab
                same.updatedAt = now
                same.title = wanted.title
                if same != wanted {
                    items.append(.tab(wanted))
                } else if heldTab.title != wanted.title {
                    let due = heldTab.updatedAt.addingTimeInterval(titleInterval)
                    if due <= now {
                        items.append(.tab(wanted))
                    } else {
                        nextDue = min(nextDue ?? due, due)
                    }
                }
            }
        }

        // Published here before, not open now: closed. Only what this device published, and only once it can say what
        // it has (a nil snapshot never reaches here).
        for id in published.subtracting(open) {
            if var window = account.windows[id], window.deletedAt == nil {
                window.updatedAt = now
                window.deletedAt = now
                items.append(.window(window))
            } else if var tab = account.tabs[id], tab.deletedAt == nil {
                tab.updatedAt = now
                tab.deletedAt = now
                items.append(.tab(tab))
            }
        }
        return Outcome(items: items, published: open, nextDue: nextDue)
    }

    /// Tombstones older than this are removed from the account: every device has long since heard.
    public static let tombstoneLifetime: TimeInterval = 30 * 24 * 60 * 60

    /// The records to remove from the account for good.
    public static func expired(in account: GlassLayout, now: Date) -> [GlassLayoutItem] {
        account.items.filter { item in
            guard let deleted = item.deletedAt else { return false }
            return now.timeIntervalSince(deleted) > tombstoneLifetime
        }
    }
}
