//
//  GlassOrbDockOrder.swift
//  Glass Power Tools — GlassShell
//
//  Where each orb stands in the dock (D88). The owner, 2026-10-25: "pinch/click and hold on a docked
//  window to move its order so muscle memory can land." An orb held, carried and let go on another
//  takes that one's place, as a row of a list does; every orb's place is kept, so one that leaves the
//  dock and comes back lands where it stood. Decided here, apart from drawing the dock, so it is
//  tested without a headset; the dock is drawn on Vision Pro (`GlassOrbDockView`).
//

import Foundation

/// The dock's orbs by their ids (a docked window's session id; `machine-` and a host's id), in the
/// order the owner set. An orb never moved stands after those that were, in the order it came.
public struct GlassOrbDockOrder: Equatable, Sendable {
    public private(set) var ids: [String]
    /// This device's, as the dock's setting is.
    public static let settingKey = "com.glasspowertools.orbs.dockOrder"
    /// Places kept for orbs not in the dock, past which the longest gone are forgotten.
    static let kept = 64

    public init(_ ids: [String] = []) { self.ids = ids }

    public init(defaults: UserDefaults) {
        self.init(defaults.stringArray(forKey: Self.settingKey) ?? [])
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(ids, forKey: Self.settingKey)
    }

    /// Where a carried orb is let go: on another, or before or after them all
    /// (`landing(at:frames:before:)`).
    public enum Landing: Equatable, Sendable {
        case on(Int)
        case first
        case last
    }

    /// `items` in the dock's order.
    public func arranged<Item>(_ items: [Item], id: (Item) -> String) -> [Item] {
        let place = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return items.enumerated().sorted { a, b in
            switch (place[id(a.element)], place[id(b.element)]) {
            case let (x?, y?): x < y
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): a.offset < b.offset
            }
        }.map(\.element)
    }

    /// `id` takes `target`'s place among `shown`, the orbs in the dock as it stands; with no target,
    /// it goes after the last of them, and with `first`, before the first. An orb not in the dock
    /// keeps its place between those that are.
    public mutating func move(_ id: String, to target: String?, first: Bool = false, among shown: [String]) {
        guard shown.contains(id), id != target else { return }
        var ids = self.ids
        // The dock as it stands, in its order, gets places of its own.
        let standing = arranged(shown, id: { $0 })
        for orb in standing where !ids.contains(orb) { ids.append(orb) }
        guard let from = ids.firstIndex(of: id) else { return }
        let anchor = target ?? (first ? standing.first(where: { $0 != id }) : standing.last(where: { $0 != id }))
        guard let anchor, let to = ids.firstIndex(of: anchor) else { return }
        ids.remove(at: from)
        let at = ids.firstIndex(of: anchor)!
        // Toward the end it lands after the one it was let go on, toward the start before it, as a
        // list's row does; at either end, past the last or before the first.
        let after = target == nil ? !first : from < to
        ids.insert(id, at: after ? at + 1 : at)
        // Past `kept`, the places of orbs not in the dock go, the last first.
        while ids.count > Self.kept, let gone = ids.lastIndex(where: { !shown.contains($0) }) {
            ids.remove(at: gone)
        }
        self.ids = ids
    }
}
