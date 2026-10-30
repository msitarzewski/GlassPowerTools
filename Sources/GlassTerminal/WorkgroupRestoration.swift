//
//  WorkgroupRestoration.swift
//  Glass Power Tools — GlassTerminal
//
//  Moved verbatim from glas.sh's ConnectionManagerView.swift (lines 2450-2590) on 2026-09-10 when the shell
//  took over the connection library. Launch planning and the local-terminal substitution review.
//

import SwiftUI
import GlassLayers

struct LayoutRestorationTarget {
    let intent: LayoutPreset.SessionIntent
    let server: ServerConfiguration?
    /// W4b: where this terminal is in the saved workgroup, so a tmux name it claims is written
    /// back to the right pane. Nil for a device's stand-in for a Mac terminal, which is not the
    /// workgroup's and keeps nothing.
    var sourceIndex: Int? = nil
    /// The folder a session made for it starts in: a Mac terminal's own, opened on its Mac.
    var folder: String? = nil

    var displayName: String {
        intent.label ?? server?.name ?? "Local Terminal"
    }
}

struct LayoutRestorationPlan {
    let targets: [LayoutRestorationTarget]
    let failures: [String]

    /// - Parameter substitutions: a device's SSH stand-ins for the workgroup's Mac terminals, by
    ///   index, once reviewed; Mac terminals left without one are skipped. Nil before review.
    ///   A Mac terminal whose Mac is in the library needs none: it opens there (`onItsMac`).
    init(preset: LayoutPreset, availableServers: [ServerConfiguration],
         substitutions: [Int: LayoutPreset.SessionIntent]? = nil) {
        let serversByID = Dictionary(
            availableServers.map { ($0.id, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        var targets: [LayoutRestorationTarget] = []
        var failures: [String] = []

        for (index, saved) in preset.sessionIntents.enumerated() {
            let sessionNumber = index + 1
            var intent = saved
            var sourceIndex: Int? = index
            var folder: String?
            if let mac = Self.mac(of: saved, in: availableServers) {
                let joining = Self.onItsMac(saved, mac: mac)
                intent = joining.intent
                folder = joining.folder
            } else if let substitutions, saved.kind == .local {
                guard let substitute = substitutions[index] else { continue }
                intent = substitute
                sourceIndex = nil
            }
            guard intent.isSupported else {
                failures.append("Session \(sessionNumber): this saved session intention is not supported by this version of \(GlassProduct.displayName).")
                continue
            }
            switch intent.kind {
            case .local:
                targets.append(LayoutRestorationTarget(intent: intent, server: nil, sourceIndex: sourceIndex))
            case .ssh:
                guard let serverID = intent.serverID,
                      let server = serversByID[serverID] else {
                    failures.append("Session \(sessionNumber): a saved server in this workgroup no longer exists.")
                    continue
                }
                guard !server.legacyAlgorithmsEnabled else {
                    failures.append("\(server.name): legacy algorithms require a direct security review.")
                    continue
                }
                targets.append(LayoutRestorationTarget(intent: intent, server: server, sourceIndex: sourceIndex,
                                                       folder: folder))
            }
        }

        self.targets = targets
        self.failures = failures
    }

    /// The Mac a local terminal lives on, when this device can reach it: its Terminal service, in
    /// the library here (2026-10-29). Nil for an SSH terminal, one no Mac has claimed, and one
    /// whose Mac this device has no record of — which still needs a stand-in.
    static func mac(of intent: LayoutPreset.SessionIntent, in servers: [ServerConfiguration]) -> UUID? {
        guard intent.kind == .local, let mac = intent.macServerID, servers.contains(where: { $0.id == mac }) else { return nil }
        return mac
    }

    /// A Mac terminal opened on its own Mac from elsewhere: over SSH, joining the session it runs
    /// in there — the same one the Mac's tab shows — and nothing typed into it. Only a session made
    /// for it, because it has ended, runs its startup command, in its folder (the owner, of the
    /// stand-ins that ran a Mac's startup scripts in `~` beside the real ones: "Maybe that's part of
    /// the problem too?"). A plain shell has no session to join: it starts in its folder.
    static func onItsMac(_ saved: LayoutPreset.SessionIntent, mac: UUID) -> (intent: LayoutPreset.SessionIntent, folder: String?) {
        if saved.withoutTmux {
            let command = WorkgroupSSHSubstitution.startup(saved.startupCommand ?? "", in: saved.localDirectory ?? "")
            return (.init(serverID: mac, label: saved.label, startupCommand: command, withoutTmux: true), nil)
        }
        return (.init(serverID: mac, label: saved.label, startupCommand: saved.startupCommand,
                      tmuxSession: saved.tmuxSession), saved.localDirectory)
    }
}

/// Opening a workgroup on iPhone, iPad and Vision Pro (W4b, 2026-10-08): each terminal attaches
/// to the tmux session the workgroup saved for it — claimed, so one that has ended is made again
/// and only then runs its startup command — and one without a session keeps the one it claims.
/// The workgroup's live terminals carry its id, so opening it again brings them forward.
@MainActor
enum TerminalWorkgroupOpening {
    /// Readies a terminal for its pane, before it connects.
    /// - Parameter joinsOnly: a relaunch's terminal (W15): its session is joined if it still runs,
    ///   and if it has ended the terminal is gone, as an `exit` leaves it — never made again
    ///   (2026-10-29, the owner: "how about they're just gone").
    static func prepare(_ session: TerminalSession, for target: LayoutRestorationTarget,
                        workgroupID: UUID, settingsManager: SettingsManager, joinsOnly: Bool = false) {
        session.workgroupLabel = target.intent.label
        // A plain shell by choice: no session, and none claimed to keep.
        session.withoutTmux = target.intent.withoutTmux
        guard !target.intent.withoutTmux else { return }
        session.tmuxSessionDirectory = target.folder
        if let name = target.intent.tmuxSession {
            session.tmuxSessionName = name
            session.tmuxClaimsGivenName = !joinsOnly
            session.tmuxJoinsOnly = joinsOnly
        }
        guard let index = target.sourceIndex, target.intent.tmuxSession == nil else { return }
        let opened = target.intent
        session.tmuxSessionClaimed = { [weak settingsManager] name in
            settingsManager?.recordWorkgroupTmuxSession(name, workgroupID: workgroupID, index: index, opened: opened)
        }
    }

    /// The workgroup's terminals live here already: shown again rather than opened twice.
    static func isOpen(_ workgroupID: UUID, in sessionManager: SessionManager) -> Bool {
        !sessionManager.sessions(inWorkgroup: workgroupID).isEmpty
    }

    /// iPhone: one slot per terminal, in order, none of them connected; the first is selected.
    /// The caller shows the workgroup, and the shown slot connects (`connectShownSlot`).
    /// Returns what could not be made.
    static func makeSlots(for plan: LayoutRestorationPlan, workgroupID: UUID,
                          sessionManager: SessionManager, settingsManager: SettingsManager) -> [String] {
        var failures: [String] = []
        for target in plan.targets {
            guard target.intent.kind == .ssh, let serverID = target.intent.serverID, let server = target.server else {
                failures.append("\(target.displayName): local terminals are available on macOS.")
                continue
            }
            do {
                let session = try sessionManager.createSessionWithoutConnecting(
                    serverID: serverID, settingsManager: settingsManager, startupCommand: target.intent.startupCommand
                ) { session in
                    prepare(session, for: target, workgroupID: workgroupID, settingsManager: settingsManager)
                    session.isWorkgroupSlot = true
                    session.connectsWhenShown = true
                }
                if !sessionManager.appendSession(session, toWorkgroup: workgroupID) {
                    failures.append("\(target.displayName): the terminal could not be added to the workgroup.")
                    sessionManager.closeSession(session)
                }
            } catch {
                failures.append("\(server.name): \(error.localizedDescription)")
            }
        }
        if let first = sessionManager.workgroup(for: workgroupID)?.sessionIDs.first {
            sessionManager.selectSession(first, inWorkgroup: workgroupID)
        }
        return failures
    }

    /// The selected slot is the one on screen: it connects if it needs to, and every other slot
    /// waits to be shown — after the app was suspended, only the visible one reconnects. A
    /// terminal added to the workgroup some other way is left as it is.
    static func connectShownSlot(in workgroupID: UUID, sessionManager: SessionManager,
                                 settingsManager: SettingsManager) async throws {
        let shown = sessionManager.selectedSession(inWorkgroup: workgroupID)
        for session in sessionManager.sessions(inWorkgroup: workgroupID) where session.isWorkgroupSlot {
            session.connectsWhenShown = session.id != shown?.id
        }
        guard let shown, shown.isWorkgroupSlot, shown.connectsOnShow else { return }
        try await sessionManager.connectWhenShown(shown, settingsManager: settingsManager)
    }

    /// The switcher's name for a slot: what the terminal is called (`terminalName`, W11) — a given
    /// name, the pane's label, its program's title, repository or folder — else "Terminal N · server".
    static func slotTitle(_ session: TerminalSession, position: Int) -> String {
        label(session, on: .switcher, position: position)
    }

    /// Where a terminal is labelled on iPhone, iPad and Vision Pro (W11). The owner, on the
    /// headset: "the tab names in the tab ornaments didn't keep the names, so neither did the
    /// grid or carousel views" — each surface read the server's name for itself.
    enum LabelSurface: CaseIterable {
        /// Vision Pro's tab ornament.
        case tabOrnament
        /// iPad's tab bar and sidebar.
        case tabBar
        /// Vision Pro's overview, as a grid.
        case grid
        /// Vision Pro's overview, as a carousel.
        case carousel
        /// The iPhone's session switcher.
        case switcher
        /// The connection ornament above a terminal.
        case connectionOrnament
        /// Active's row for a workgroup Connect made for one terminal.
        case active
        /// A tab's card in All Windows off the Mac.
        case allWindows
    }

    /// What a terminal is called on `surface`: one answer for all of them, by the rule the Mac's
    /// tabs and Active share (`terminalName`). With nothing to name it, the server — or in the
    /// iPhone's switcher, which lists a workgroup's slots, "Terminal N · server".
    static func label(_ session: TerminalSession, on surface: LabelSurface, position: Int = 0) -> String {
        if let name = session.terminalName { return name }
        return surface == .switcher ? "Terminal \(position + 1) · \(session.server.name)" : session.server.name
    }
}

/// Reviews a launch-only copy; never edits the saved workgroup's local intents.
struct WorkgroupSSHSubstitutionReview: View {
    @Environment(\.dismiss) private var dismiss
    let preset: LayoutPreset
    let servers: [ServerConfiguration]
    let onOpen: ([Int: WorkgroupSSHSubstitution], Bool) -> Void
    @State private var replacements: [Int: WorkgroupSSHSubstitution]
    @State private var remember: Bool

    init(preset: LayoutPreset, servers: [ServerConfiguration], saved: [Int: WorkgroupSSHSubstitution],
         onOpen: @escaping ([Int: WorkgroupSSHSubstitution], Bool) -> Void) {
        self.preset = preset
        self.servers = servers
        self.onOpen = onOpen
        let valid = saved.filter { index, value in
            preset.sessionIntents.indices.contains(index) && preset.sessionIntents[index].sameTerminal(as: value.source)
                && LayoutRestorationPlan.mac(of: preset.sessionIntents[index], in: servers) == nil
                && servers.contains { $0.id == value.serverID && !$0.legacyAlgorithmsEnabled }
        }
        _replacements = State(initialValue: valid)
        _remember = State(initialValue: !valid.isEmpty)
    }

    private var availableServers: [ServerConfiguration] { servers.filter { !$0.legacyAlgorithmsEnabled } }
    /// The Mac terminals this device has to stand in for: those whose Mac it can't reach open there.
    private var needingStandIns: [(offset: Int, element: LayoutPreset.SessionIntent)] {
        Array(preset.sessionIntents.enumerated()).filter {
            $0.element.kind == .local && LayoutRestorationPlan.mac(of: $0.element, in: servers) == nil
        }
    }
    private var canOpen: Bool {
        (!replacements.isEmpty
            || preset.sessionIntents.contains { $0.kind == .ssh || LayoutRestorationPlan.mac(of: $0, in: servers) != nil })
            && replacements.values.allSatisfy { replacement in
                !replacement.directory.utf8.contains(0) && !replacement.command.utf8.contains(0)
                    && availableServers.contains { server in server.id == replacement.serverID }
            }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This device cannot run local terminals. Choose SSH replacements below, or leave entries skipped. Your original workgroup and its Mac terminals stay unchanged.")
                    if needingStandIns.count < preset.sessionIntents.filter({ $0.kind == .local }).count {
                        Text("Mac terminals whose Mac is in Connections open on that Mac, in their own sessions. These are the ones whose Mac isn't.")
                    }
                    if availableServers.isEmpty {
                        Text("Add an SSH connection in Connections first. Connections requiring legacy security review must be opened directly.")
                    }
                }
                ForEach(needingStandIns, id: \.offset) { index, source in
                    Section {
                        Label(source.label ?? "Local Terminal \(index + 1)", systemImage: "apple.terminal")
                            .foregroundStyle(.secondary).opacity(0.55)
                        if let directory = source.localDirectory {
                            Text("Original Mac directory: \(directory)").font(.caption).foregroundStyle(.secondary)
                        }
                        Picker("Use SSH connection", selection: Binding<UUID?>(
                            get: { replacements[index]?.serverID },
                            set: { id in
                                if let id {
                                    // Its Mac folder to start with: a blank one ran the Mac's
                                    // startup scripts in the server's home (2026-10-29).
                                    replacements[index] = WorkgroupSSHSubstitution(source: source, serverID: id,
                                        directory: replacements[index]?.directory ?? source.localDirectory ?? "",
                                        command: replacements[index]?.command ?? source.startupCommand ?? "")
                                } else { replacements.removeValue(forKey: index) }
                            })) {
                                Text("Skip this terminal").tag(nil as UUID?)
                                ForEach(availableServers) { server in
                                    Text("\(server.name) — \(server.username)@\(server.host):\(server.port)").tag(Optional(server.id))
                                }
                            }
                        if replacements[index] != nil {
                            TextField("Remote directory (blank uses SSH default)", text: Binding(
                                get: { replacements[index]?.directory ?? "" },
                                set: { replacements[index]?.directory = $0 }))
                                .terminalTextInputDefaults()
                            TextField("Startup command (optional)", text: Binding(
                                get: { replacements[index]?.command ?? "" },
                                set: { replacements[index]?.command = $0 }), axis: .vertical)
                                .terminalTextInputDefaults()
                            Text("Open Workgroup runs this command on the selected server after authentication and host-key checks. The Mac shell is not copied.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Toggle("Remember replacements on this device", isOn: $remember)
                    Text("Remembered choices are reviewed each time. They are not synced to your other devices.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Use SSH Instead of Local")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open Workgroup") { onOpen(replacements, remember) }.disabled(!canOpen)
                }
            }
        }
    }
}

