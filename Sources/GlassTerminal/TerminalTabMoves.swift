//
//  TerminalTabMoves.swift
//  Glass Power Tools — GlassTerminal
//
//  W15 (owner, 2026-10-09, on the Vision Pro): "We also have no way to move tabs from one window
//  to another with vision os that I can see," and then: "maybe we do that with grid view? drag and
//  drop." A terminal window there is a workgroup; moving a tab moves its terminal — the same
//  `TerminalSession`, its connection and its tmux client — from one workgroup to another, never a
//  second client on the same session (the Mac's drag once "copied", 2026-10-08). A window whose
//  last tab leaves closes, as a Mac window does (W8). The Mac's own windows move tabs with
//  `MacWorkspaceController`; this is the same act for Vision Pro, iPad and iPhone.
//

import Foundation
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// Takes tabs dragged onto a terminal — a Vision Pro window showing one terminal, which is
/// "anywhere on it" for the owner's drag. Nil where nothing takes them: the drop is refused.
typealias TerminalTabDrop = @MainActor ([TerminalTabTransfer]) -> Void

private struct TerminalTabDropKey: EnvironmentKey {
    static let defaultValue: TerminalTabDrop? = nil
}

extension EnvironmentValues {
    var terminalTabDrop: TerminalTabDrop? {
        get { self[TerminalTabDropKey.self] }
        set { self[TerminalTabDropKey.self] = newValue }
    }
}

/// W26 (owner, 2026-10-10, on the Vision Pro): "we still don't have a way to combine two
/// independent terminal windows there's no tab to drag between". A window holding one terminal
/// shows no tab bar, so the terminal itself moves: its tools menu and its title. The workgroup's
/// view owns the moves — it opens or brings forward the window a terminal goes to and closes the
/// one it empties — and hands them down here, as it hands down `terminalTabDrop`. Nil where
/// nothing moves terminals between windows (the Mac's own windows, an iPhone's single screen).
nonisolated struct TerminalTabMoving: Sendable {
    /// Whether **Move Tab to New Window** is offered: the window has other terminals to leave.
    var canMoveToNewWindow: Bool
    var moveToNewWindow: @MainActor (TerminalSession) -> Void
    /// Moves the terminal into the open workgroup with this id.
    var move: @MainActor (TerminalSession, UUID) -> Void
}

private struct TerminalTabMovingKey: EnvironmentKey {
    static let defaultValue: TerminalTabMoving? = nil
}

extension EnvironmentValues {
    var terminalTabMoving: TerminalTabMoving? {
        get { self[TerminalTabMovingKey.self] }
        set { self[TerminalTabMovingKey.self] = newValue }
    }
}

/// A terminal tab being dragged: which terminal, from which workgroup. Only this app's windows
/// read it (`ownProcess`), so nothing else accepts it, and it is never uploaded as a file.
nonisolated struct TerminalTabTransfer: Codable, Hashable, Sendable, Transferable {
    var workgroupID: UUID
    var sessionID: UUID

    static let contentType = UTType(exportedAs: "com.glasspowertools.terminal-workgroup-tab")
    /// The same, as a drop target lists the types it takes.
    static var typeIdentifier: String { contentType.identifier }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: contentType).visibility(.ownProcess)
    }

    /// Whether a drop carries a dragged tab, so a terminal moves it rather than uploading it.
    static func isCarried(by providers: [NSItemProvider]) -> Bool {
        providers.contains { $0.hasItemConformingToTypeIdentifier(typeIdentifier) }
    }

    /// The dragged tabs among `providers`, in their order, delivered together on the main actor.
    @MainActor
    static func load(from providers: [NSItemProvider], _ completion: @escaping @MainActor ([TerminalTabTransfer]) -> Void) {
        let matching = providers.filter { $0.hasItemConformingToTypeIdentifier(contentType.identifier) }
        guard !matching.isEmpty else { return }
        Task { @MainActor in
            var loaded: [TerminalTabTransfer] = []
            for provider in matching {
                if let tab = await load(provider) { loaded.append(tab) }
            }
            if !loaded.isEmpty { completion(loaded) }
        }
    }

    private static func load(_ provider: NSItemProvider) async -> TerminalTabTransfer? {
        await withCheckedContinuation { continuation in
            _ = provider.loadTransferable(type: TerminalTabTransfer.self) { result in
                continuation.resume(returning: try? result.get())
            }
        }
    }
}

#if os(visionOS)
/// A tab dragged on Vision Pro — a sidebar row or a terminal's title (2026-10-21): let go over
/// another terminal window it moves there (`TerminalTabTransfer`); let go in empty space it opens a
/// window of its own where it was let go, still running. A `Transferable` can't make a window, so
/// the drag carries an activity as well, which the terminal window group claims at the drop, as a
/// terminal dragged out of the library does (`GlassServiceDrag`, D72). Declared in Info.plist.
enum TerminalTabDrag {
    static let activityType = "com.glasspowertools.terminal-tab"

    static func itemProvider(_ tab: TerminalTabTransfer) -> NSItemProvider {
        let activity = NSUserActivity(activityType: activityType)
        activity.targetContentIdentifier = activityType
        activity.userInfo = ["workgroup": tab.workgroupID.uuidString, "session": tab.sessionID.uuidString]
        let provider = NSItemProvider(object: activity)
        provider.register(tab)
        return provider
    }

    /// The tab a dropped activity names.
    static func tab(from activity: NSUserActivity) -> TerminalTabTransfer? {
        guard let workgroup = (activity.userInfo?["workgroup"] as? String).flatMap(UUID.init(uuidString:)),
              let session = (activity.userInfo?["session"] as? String).flatMap(UUID.init(uuidString:)) else { return nil }
        return TerminalTabTransfer(workgroupID: workgroup, sessionID: session)
    }
}
#endif

/// Moving live terminals between workgroups. Pure model changes through `SessionManager`, so
/// each is tested without a window.
@MainActor
enum TerminalTabMoves {
    enum Outcome: Equatable {
        /// Nothing changed: the terminal or the window is gone, or the window is full.
        case refused
        /// Within one window: it took the place it was dropped on.
        case reordered
        /// Into another window; `sourceClosed` when it was the last tab of its own, whose
        /// workgroup is gone and whose window closes.
        case moved(sourceClosed: Bool)
    }

    /// The workgroup a terminal is in now. A drag says where it started; the model says where it is.
    static func workgroup(holding sessionID: UUID, in manager: SessionManager) -> TerminalWorkgroup? {
        manager.workgroups.first { $0.sessionIDs.contains(sessionID) }
    }

    /// Moves a live terminal into `destination`, at `index` (nil: after the last). Within its own
    /// workgroup it takes the place it is dropped on, and the selection stays; into another it is
    /// selected there, and a workgroup left with nothing is discarded so its window closes. The
    /// same session object throughout: its connection, its tmux client, its name go with it.
    @discardableResult
    static func move(_ sessionID: UUID, to destination: UUID, at index: Int?, in manager: SessionManager) -> Outcome {
        guard let source = workgroup(holding: sessionID, in: manager),
              let target = manager.workgroup(for: destination) else { return .refused }
        if source.id == destination {
            let last = target.sessionIDs.count - 1
            let position = min(max(0, index ?? last), last)
            return manager.moveSession(sessionID, inWorkgroup: destination, to: position) ? .reordered : .refused
        }
        let position = min(max(0, index ?? target.sessionIDs.count), target.sessionIDs.count)
        guard manager.transferSession(sessionID, fromWorkgroup: source.id, toWorkgroup: destination, at: position) else {
            return .refused
        }
        let emptied = manager.workgroup(for: source.id)?.sessionIDs.isEmpty == true
        if emptied { manager.discardWorkgroupIfEmpty(source.id) }
        return .moved(sourceClosed: emptied)
    }

    /// The dragged tabs that come from another window. Dropped on a terminal, one already in
    /// `workgroupID` was let go over its own window — a terminal's title dragged and dropped back
    /// on it (W26) — and stays where it is, rather than going to the end of the tabs.
    static func arriving(_ tabs: [TerminalTabTransfer], at workgroupID: UUID,
                         in manager: SessionManager) -> [TerminalTabTransfer] {
        tabs.filter { workgroup(holding: $0.sessionID, in: manager)?.id != workgroupID }
    }

    /// Whether **Move Tab to New Window** has anything to do: a terminal alone in its window is
    /// in a window of its own already.
    static func canMoveToNewWindow(from workgroupID: UUID, in manager: SessionManager) -> Bool {
        manager.sessions(inWorkgroup: workgroupID).count > 1
    }

    /// **Move to New Window**: a new workgroup holding only this terminal, named for its machine
    /// as Connect names one (so Active and the window name it by the terminal), with the settings
    /// of the window it left, as a Mac's Move Tab to New Window keeps them (W20, W22). Returns the
    /// new workgroup's id, or nil when nothing moved.
    static func moveToNewWorkgroup(_ sessionID: UUID, in manager: SessionManager) -> UUID? {
        guard let source = workgroup(holding: sessionID, in: manager),
              let session = manager.session(for: sessionID) else { return nil }
        let created = manager.createWorkgroup(name: session.server.name, colorTag: session.server.colorTag,
                                              windowSettings: source.windowSettings)
        guard move(sessionID, to: created, at: 0, in: manager) != .refused else {
            manager.discardWorkgroupIfEmpty(created)
            return nil
        }
        return created
    }

    /// Where **Move to** can send a terminal from `workgroupID`.
    nonisolated struct Destination: Identifiable, Equatable {
        let id: UUID
        let title: String
    }

    /// The other workgroups with live terminals and room for one more, in the order they opened,
    /// each titled as Active titles it. Two with the same title say which terminal each shows.
    /// - Parameter among: Vision Pro passes the workgroups whose window is open: a terminal moved
    ///   into one without a window would vanish from sight. Nil offers every one, as iPhone and
    ///   iPad show one workgroup at a time and Active lists the others.
    static func destinations(from workgroupID: UUID, among open: Set<UUID>?, in manager: SessionManager) -> [Destination] {
        let candidates = manager.workgroups.compactMap { workgroup -> (TerminalWorkgroup, [TerminalSession])? in
            guard workgroup.id != workgroupID, open?.contains(workgroup.id) ?? true,
                  workgroup.sessionIDs.count < LayoutPreset.maximumSessionCount else { return nil }
            let live = manager.sessions(inWorkgroup: workgroup.id)
            return live.isEmpty ? nil : (workgroup, live)
        }
        // Steady: a title with an agent's spinner changed with every turn of it, and the menu
        // listing it was rebuilt under the pinch that chose from it.
        let titles = candidates.map { TerminalSessionNaming.steady(GlassTerminalCapability.title(of: $0.0, live: $0.1)) }
        return candidates.enumerated().map { index, candidate in
            let (workgroup, live) = candidate
            var title = titles[index]
            if titles.filter({ $0 == title }).count > 1 {
                let shown = workgroup.selectedSessionID.flatMap(manager.session(for:)) ?? live[0]
                let label = TerminalSessionNaming.steady(TerminalWorkgroupOpening.label(shown, on: .tabOrnament))
                if label != title { title += " · \(label)" }
            }
            return Destination(id: workgroup.id, title: title)
        }
    }
}
