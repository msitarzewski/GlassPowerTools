//
//  TerminalWorkgroupsToReopen.swift
//  Glass Power Tools — GlassTerminal
//
//  W15 (owner, 2026-10-09, on the Vision Pro): "We should also work on restoring tab groups on
//  relaunch with vision OS and iPad OS." A Vision Pro terminal window, and the tabs an iPad or
//  iPhone shows in place of the library, are a workgroup held in memory; a quit, a crash or a
//  reinstall lost every one. The app now keeps its own list of them, as the Mac does for its
//  windows (`MacWindowsToReopen`, W12; D54: never the system's restoration, which brought the
//  Mac's windows back empty): kept current while the app runs, so a crash reopens the same ones,
//  and taken once per launch, never each time a view appears.
//
//  What comes back follows the Mac. A workgroup comes back when a terminal in it is kept in tmux;
//  each of its terminals comes back in its place, a terminal in tmux attached to its own session
//  and any other as a new terminal on the same machine (a plain shell's work is gone). One with no
//  terminal in tmux does not come back, as a Mac window of plain shells does not. A workgroup
//  closed by hand, or whose last terminal ended, is not in the list.
//

import Foundation
import Observation
import GlassLayers
import OSLog
#if os(visionOS)
import SwiftUI
import UIKit
#endif

/// One workgroup as the next launch reopens it: its terminals in order, which one was selected,
/// and — on iPhone and iPad — whether it was the one on screen. The app's own record, written
/// only by this app; never a saved Workgroup, which the person made and which syncs (D51).
nonisolated struct TerminalWorkgroupReopenRecord: Codable, Equatable, Sendable {
    nonisolated struct Terminal: Codable, Equatable, Sendable {
        /// The saved server it was on.
        var serverID: UUID
        /// The tmux session it was attached to; nil for a terminal not kept in tmux.
        var tmuxSession: String?
        /// What its saved Workgroup called it, if it was opened from one.
        var label: String?
        /// The name someone gave it (W11). For a terminal in tmux its session says it again once
        /// attached; until then — an iPhone's slot not yet shown — this is what it is called.
        var name: String?
    }

    var id: UUID
    var name: String
    var colorTag: ServerColorTag
    var terminals: [Terminal]
    var selectedIndex: Int
    /// iPhone and iPad: the workgroup on screen when the app last ran, shown again.
    var isShown: Bool
    /// Its window's own settings (W20's look, W22's rest), which it comes back with. Absent from
    /// lists written before them; an earlier build reading the list ignores what it doesn't know.
    var windowSettings = GlassWindowOverrides()

    init(id: UUID, name: String, colorTag: ServerColorTag, terminals: [Terminal], selectedIndex: Int,
         isShown: Bool, windowSettings: GlassWindowOverrides = GlassWindowOverrides()) {
        self.id = id
        self.name = name
        self.colorTag = colorTag
        self.terminals = terminals
        self.selectedIndex = selectedIndex
        self.isShown = isShown
        self.windowSettings = windowSettings
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, colorTag, terminals, selectedIndex, isShown, look, windowSettings
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        colorTag = try container.decode(ServerColorTag.self, forKey: .colorTag)
        terminals = try container.decode([Terminal].self, forKey: .terminals)
        selectedIndex = try container.decode(Int.self, forKey: .selectedIndex)
        isShown = try container.decode(Bool.self, forKey: .isShown)
        // Settings that can't be read cost the workgroup those settings, never its terminals.
        windowSettings = TerminalWindowSettingsCoding.decode(from: container, look: .look, settings: .windowSettings)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(colorTag, forKey: .colorTag)
        try container.encode(terminals, forKey: .terminals)
        try container.encode(selectedIndex, forKey: .selectedIndex)
        try container.encode(isShown, forKey: .isShown)
        try TerminalWindowSettingsCoding.encode(windowSettings, into: &container, look: .look, settings: .windowSettings)
    }
}

/// The workgroups to reopen at the next launch, for the whole run (W15). One per process.
@MainActor
@Observable
final class TerminalWorkgroupsToReopen {
    static let shared = TerminalWorkgroupsToReopen()
    static let key = "terminalWorkgroupsToReopen"
    /// More than anyone keeps open; a list longer than this was not written by this app.
    static let maximumWorkgroups = 64
    private nonisolated static let logger = Logger(subsystem: "sh.glas", category: "reopen")

    @ObservationIgnored private let defaults: UserDefaults
    /// This run has taken the last run's list: from then on, this run's workgroups are the list.
    @ObservationIgnored private(set) var hasTaken = false
    @ObservationIgnored private weak var sessionManager: SessionManager?

    /// Vision Pro: workgroups whose window is open now. **Move Tab To** offers these.
    private(set) var openWindowIDs: Set<UUID> = []
    /// Vision Pro: workgroups whose window was closed by hand. Their terminals go on running and
    /// Active lists them, but they do not come back at the next launch.
    private(set) var closedByHand: Set<UUID> = []
    /// iPhone and iPad: the workgroup on screen, if one is.
    private(set) var shownWorkgroupID: UUID?

    init(defaults: UserDefaults = SharedDefaults.defaults) {
        self.defaults = defaults
    }

    // MARK: Taking the last run's list, once

    /// The workgroups the last run left, for the first caller of this launch; nil for every later
    /// one. The list is removed as it is taken, and written again from this run's workgroups once
    /// `keepCurrent` starts. A list that can't be read is dropped, and says so in the log.
    ///
    /// - Parameter catalogLoaded: whether the terminal's saved servers have been read from the
    ///   library. Until then every terminal's machine would look gone, so nothing is taken: the
    ///   list waits for a later call, or — when the library can't be read at all — the next launch.
    func takeOnce(askedBy asker: String, catalogLoaded: Bool) -> [TerminalWorkgroupReopenRecord]? {
        guard catalogLoaded else {
            Self.logger.notice("Reopen: asked by \(asker, privacy: .public) before the library loaded")
            return nil
        }
        guard !hasTaken else {
            Self.logger.notice("Reopen: asked by \(asker, privacy: .public), already taken at this launch")
            return nil
        }
        hasTaken = true
        let records = Self.read(defaults)
        defaults.removeObject(forKey: Self.key)
        Self.logger.notice("Reopen: asked by \(asker, privacy: .public), \(records.count) workgroups listed")
        return records
    }

    /// What `defaults` holds, checked: never more workgroups, or terminals in one, than this app
    /// writes; a selection inside the terminals; nothing at all when it can't be decoded.
    static func read(_ defaults: UserDefaults) -> [TerminalWorkgroupReopenRecord] {
        guard let data = defaults.data(forKey: key) else { return [] }
        guard let decoded = try? JSONDecoder().decode([TerminalWorkgroupReopenRecord].self, from: data) else {
            logger.error("Reopen: the list of workgroups to reopen could not be read, and was dropped")
            return []
        }
        var seen = Set<UUID>()
        return decoded.prefix(maximumWorkgroups).compactMap { record in
            guard seen.insert(record.id).inserted else { return nil }
            var record = record
            record.terminals = Array(record.terminals.prefix(LayoutPreset.maximumSessionCount))
            guard !record.terminals.isEmpty else { return nil }
            record.selectedIndex = min(max(0, record.selectedIndex), record.terminals.count - 1)
            return record
        }
    }

    // MARK: Keeping it current

    /// From now on the list is this run's workgroups, written whenever they change — a terminal
    /// added, moved, closed or renamed, a tmux session claimed, a window opened or closed — so a
    /// crash or a forced quit reopens what was open. Nothing is written before the last run's list
    /// is taken: until then it is still that run's.
    func keepCurrent(_ sessionManager: SessionManager) {
        self.sessionManager = sessionManager
        observe()
    }

    private func observe() {
        guard hasTaken, let manager = sessionManager else { return }
        let records = withObservationTracking {
            current(in: manager)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        write(records)
    }

    /// The list as it stands now.
    func current(in manager: SessionManager) -> [TerminalWorkgroupReopenRecord] {
        Self.records(of: manager.workgroups, session: manager.session(for:),
                     isSaved: { manager.serverManager.server(for: $0) != nil },
                     leaving: closedByHand, shown: shownWorkgroupID)
    }

    private func write(_ records: [TerminalWorkgroupReopenRecord]) {
        if records.isEmpty {
            guard defaults.object(forKey: Self.key) != nil else { return }
            defaults.removeObject(forKey: Self.key)
            Self.logger.notice("Reopen: no workgroups listed now")
            return
        }
        // Keys in one order, so an unchanged list is never written again.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(records), defaults.data(forKey: Self.key) != data else { return }
        defaults.set(data, forKey: Self.key)
        Self.logger.notice("Reopen: \(records.count) workgroups listed now")
    }

    /// The workgroups worth reopening, in order: each with a terminal kept in tmux, on a saved
    /// server; none closed by hand. A terminal on a server that isn't saved (Quick Connect, a
    /// Tailscale device) has nothing to connect with at the next launch, and is left out.
    static func records(of workgroups: [TerminalWorkgroup], session: (UUID) -> TerminalSession?,
                        isSaved: (UUID) -> Bool, leaving closedByHand: Set<UUID>,
                        shown: UUID?) -> [TerminalWorkgroupReopenRecord] {
        let listed = workgroups.compactMap { workgroup -> TerminalWorkgroupReopenRecord? in
            guard !closedByHand.contains(workgroup.id) else { return nil }
            let kept = workgroup.sessionIDs.compactMap(session).filter { $0.purpose == .terminal && isSaved($0.server.id) }
            let terminals = kept.map { terminal in
                TerminalWorkgroupReopenRecord.Terminal(
                    serverID: terminal.server.id,
                    tmuxSession: terminal.survivesClose ? terminal.tmuxSessionName : nil,
                    label: terminal.workgroupLabel,
                    name: terminal.givenName)
            }
            guard terminals.contains(where: { $0.tmuxSession != nil }) else { return nil }
            return TerminalWorkgroupReopenRecord(
                id: workgroup.id, name: workgroup.name, colorTag: workgroup.colorTag, terminals: terminals,
                selectedIndex: kept.firstIndex { $0.id == workgroup.selectedSessionID } ?? 0,
                isShown: workgroup.id == shown, windowSettings: workgroup.windowSettings)
        }
        return Array(listed.prefix(maximumWorkgroups))
    }

    // MARK: Windows (Vision Pro) and the workgroup on screen (iPhone, iPad)

    /// A workgroup's window is on screen: it comes back at the next launch again, even if an
    /// earlier window of it was closed by hand.
    func windowAppeared(_ workgroupID: UUID) {
        openWindowIDs.insert(workgroupID)
        closedByHand.remove(workgroupID)
    }

    /// A workgroup's window went away. Closed by hand, its workgroup does not come back at the
    /// next launch, though its terminals go on running and Active lists them. One the system took
    /// away while the app was in the background is not the person's choice, and stays listed.
    func windowDisappeared(_ workgroupID: UUID, closedByHand byHand: Bool) {
        openWindowIDs.remove(workgroupID)
        if byHand { closedByHand.insert(workgroupID) }
    }

    /// iPhone and iPad: the workgroup now on screen, or nil for the library. A window going back
    /// to the library clears it only if it was the one showing it.
    func noteShown(_ workgroupID: UUID?, replacing previous: UUID? = nil) {
        if let workgroupID {
            shownWorkgroupID = workgroupID
        } else if shownWorkgroupID == previous {
            shownWorkgroupID = nil
        }
    }
}

// MARK: Reopening one

extension TerminalWorkgroupOpening {
    /// What reopening a workgroup from the last run made, and what it could not, in plain words.
    struct Reopened: Equatable {
        var opened = false
        var failures: [String] = []
    }

    /// Reopens one workgroup the last run left (W15), under its own id: each terminal in its place
    /// as a slot — made, registered, not connected — attached to its tmux session when it was in
    /// one, named as it was, the selected one selected again. Nothing is written back to a saved
    /// Workgroup: its panes may have been rearranged since. A terminal whose server is no longer
    /// saved, or allows legacy algorithms (which need their own confirmation each time), is left
    /// out and said; the others still come back.
    ///
    /// - Parameter connectsWhenShown: iPhone and iPad connect only the slot on screen (W4b); Vision
    ///   Pro connects them all, since its grid and carousel show them all.
    static func reopen(_ record: TerminalWorkgroupReopenRecord, connectsWhenShown: Bool,
                       sessionManager: SessionManager, settingsManager: SettingsManager) -> Reopened {
        var result = Reopened()
        guard !isOpen(record.id, in: sessionManager) else { return result }
        let servers = sessionManager.serverManager.servers
        let workgroupID = sessionManager.createWorkgroup(id: record.id, name: record.name, colorTag: record.colorTag,
                                                         windowSettings: record.windowSettings)
        var selected: UUID?
        for (index, terminal) in record.terminals.enumerated() {
            let called = displayName(of: terminal)
            guard let server = servers.first(where: { $0.id == terminal.serverID }) else {
                result.failures.append("\(called) didn't come back: its machine's Terminal service is no longer here.")
                continue
            }
            guard !server.legacyAlgorithmsEnabled else {
                result.failures.append("\(server.name) uses legacy algorithms, so \(called) didn't come back. Open it on its own to review its security settings.")
                continue
            }
            let intent = LayoutPreset.SessionIntent(serverID: server.id, label: terminal.label, tmuxSession: terminal.tmuxSession)
            let target = LayoutRestorationTarget(intent: intent, server: server, sourceIndex: nil)
            do {
                let session = try sessionManager.createSessionWithoutConnecting(
                    serverID: server.id, settingsManager: settingsManager
                ) { session in
                    prepare(session, for: target, workgroupID: workgroupID, settingsManager: settingsManager)
                    session.isWorkgroupSlot = true
                    session.connectsWhenShown = connectsWhenShown
                    if let name = terminal.name { session.rename(to: name) }
                }
                if sessionManager.appendSession(session, toWorkgroup: workgroupID) {
                    if index == record.selectedIndex { selected = session.id }
                } else {
                    result.failures.append("\(called) didn't come back: the terminal could not be added to its window.")
                    sessionManager.closeSession(session)
                }
            } catch {
                result.failures.append("\(server.name): \(error.localizedDescription)")
            }
        }
        guard let first = sessionManager.workgroup(for: workgroupID)?.sessionIDs.first else {
            sessionManager.discardWorkgroupIfEmpty(workgroupID)
            return result
        }
        sessionManager.selectSession(selected ?? first, inWorkgroup: workgroupID)
        result.opened = true
        return result
    }

    /// A terminal from the list in a sentence: its name, its label, its tmux session as Active
    /// names it ("Terminal 3"), or just "A terminal".
    static func displayName(of terminal: TerminalWorkgroupReopenRecord.Terminal) -> String {
        if let name = terminal.name ?? terminal.label { return name }
        if let session = terminal.tmuxSession {
            return TerminalTmux.glassNumber(session).map { "Terminal \($0)" } ?? session
        }
        return "A terminal"
    }

    /// Vision Pro: connects every slot of the reopened workgroups — one machine's one after
    /// another, so a second terminal shares the first one's connection, and the machines side by
    /// side, so one that doesn't answer holds up no other. A terminal that doesn't connect stays
    /// in its place, saying why, and **Reconnect** tries again. Returns what failed.
    static func connectReopened(_ workgroupIDs: [UUID], sessionManager: SessionManager,
                                settingsManager: SettingsManager) async -> [String] {
        let slots = workgroupIDs.flatMap { sessionManager.sessions(inWorkgroup: $0) }.filter(\.isWorkgroupSlot)
        var byServer: [UUID: [TerminalSession]] = [:]
        var order: [UUID] = []
        for slot in slots {
            if byServer[slot.server.id] == nil { order.append(slot.server.id) }
            byServer[slot.server.id, default: []].append(slot)
        }
        let machines = order.map { serverID in
            let sessions = byServer[serverID] ?? []
            return Task { @MainActor () -> [String] in
                var failures: [String] = []
                for session in sessions {
                    do {
                        try await sessionManager.connectWhenShown(session, settingsManager: settingsManager)
                        if case .error(let message) = session.state { failures.append("\(session.server.name): \(message)") }
                    } catch {
                        failures.append("\(session.server.name): \(error.localizedDescription)")
                    }
                }
                return failures
            }
        }
        var failures: [String] = []
        for machine in machines { failures += await machine.value }
        return failures
    }
}

#if os(visionOS)
/// Vision Pro: a terminal window coming and going, for the reopen list (W15) and **Move Tab To**.
struct TerminalWorkgroupWindowPresence: ViewModifier {
    let workgroupID: UUID

    func body(content: Content) -> some View {
        content
            .onAppear { TerminalWorkgroupsToReopen.shared.windowAppeared(workgroupID) }
            .onDisappear {
                // Closed by hand while the app is in front. A window the system takes away from an
                // app in the background was not the person's choice, and comes back.
                let byHand = UIApplication.shared.applicationState != .background
                TerminalWorkgroupsToReopen.shared.windowDisappeared(workgroupID, closedByHand: byHand)
            }
    }
}
#endif
