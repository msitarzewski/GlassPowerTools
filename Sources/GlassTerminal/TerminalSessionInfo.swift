//
//  TerminalSessionInfo.swift
//  Glass Power Tools — GlassTerminal
//
//  Get Info for a terminal (the owner, 2026-11-19, after testing a lost session meant finding a tab's tmux name: "it
//  looks like we need a right click > Get Info... on the tabs so finsing its tmux name is easier"). What it says, agreed
//  with him: the tmux session's name with a Copy button, the machine, when tmux made the session, the folder and what
//  runs there, and whether it is open somewhere else too. A Mac tab's right-click menu opens it beside the tab, with
//  Copy tmux Session Name beside it in the menu; on iPhone, iPad and Vision Pro the terminal's own menu does.
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// One terminal, as Get Info says it.
struct TerminalSessionInfo: Identifiable, Equatable {
    var id: UUID
    /// What the terminal is called, for a tab of several terminals.
    var title: String
    /// "This Mac", or the machine's name.
    var machine: String
    /// The tmux session it is kept in; nil for a terminal not in tmux.
    var tmuxSession: String?
    /// When tmux made the session (`TerminalTmux.Session.created`), once known.
    var created: Date?
    var folder: String?
    /// The coding agent, or else the program, in front.
    var running: String?
    /// Clients attached to the session besides this terminal: other devices, or other windows. Nil until asked, or
    /// when it can't be said.
    var otherClients: Int?

    /// "Only here", or how many other places show it.
    var openElsewhere: String? {
        guard tmuxSession != nil, let otherClients else { return nil }
        switch otherClients {
        case ..<1: return "Only here"
        case 1: return "Here and in 1 other place"
        default: return "Here and in \(otherClients) other places"
        }
    }

    /// When the session was made: the time today, with its date on another day.
    func started(now: Date = .now) -> String? {
        created.map { TerminalTmux.EndedReason.time($0, now: now) }
    }

    /// A folder under `home` as `~/…`.
    static func folder(_ directory: String?, home: String?) -> String? {
        guard let directory else { return nil }
        guard let home, !home.isEmpty, directory == home || directory.hasPrefix(home + "/") else { return directory }
        return "~" + directory.dropFirst(home.count)
    }

    /// The other clients of `listed` — this terminal's session — besides the `here` this device shows it with.
    static func otherClients(of listed: TerminalTmux.Session?, here: Int) -> Int? {
        listed.map { max(0, $0.attachedClients - here) }
    }

    /// Puts the session's name on the clipboard.
    @MainActor static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

extension TerminalSession {
    /// Get Info for this terminal from what it knows now: its session, when tmux made it, the folder and program its
    /// last read found. Who else has the session open is the machine's to say (`sessionInfoAskingTheMachine`).
    func sessionInfo(title: String? = nil) -> TerminalSessionInfo {
        TerminalSessionInfo(
            id: id,
            title: title ?? TerminalWorkgroupOpening.label(self, on: .tabBar),
            machine: server.name,
            tmuxSession: survivesClose ? tmuxSessionName : nil,
            created: tmuxSessionCreated.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            folder: TerminalSessionInfo.folder(tmuxPane?.directory, home: tmuxPane?.home),
            running: GlassTerminalCapability.agent(of: self)?.displayName ?? tmuxPane?.program)
    }

    /// The same, with the machine asked who else has the session open: its other clients, besides this terminal.
    /// Not connected, or not in tmux, it says what it knows.
    func sessionInfoAskingTheMachine(title: String? = nil) async -> TerminalSessionInfo {
        var info = sessionInfo(title: title)
        guard state == .connected, survivesClose, let name = tmuxSessionName,
              let listed = try? await runTmuxCommand(TerminalTmux.listCommand),
              case .sessions(let sessions) = TerminalTmux.parse(listed),
              let own = sessions.first(where: { $0.isSession(name, created: tmuxSessionCreated) }) else { return info }
        info.otherClients = TerminalSessionInfo.otherClients(of: own, here: 1)
        if info.created == nil { info.created = own.created.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
        return info
    }
}

/// Get Info's panel: a popover beside a Mac tab, a sheet on iPhone, iPad and Vision Pro.
struct TerminalSessionInfoView: View {
    let title: String
    @State var infos: [TerminalSessionInfo]
    /// Asked as it appears: who else has the session open, which only the machine can say.
    var refresh: (@MainActor () async -> [TerminalSessionInfo])? = nil
    /// A sheet's Done; nil in a popover, which closes by itself.
    var done: (() -> Void)? = nil
    @State private var copied: UUID?
    /// The machine is being asked who else has the session open: the row says so meanwhile, so the panel doesn't grow
    /// under the pointer when the answer comes.
    @State private var asking = true

    var body: some View {
        if let done {
            NavigationStack {
                ScrollView { content.padding(16) }
                    .navigationTitle(title)
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", action: done).accessibilityIdentifier("terminal-info-done")
                        }
                    }
            }
        } else {
            // A popover sizes itself to what it holds: no scroll view, which would keep the first size and hide a
            // row that arrives later below its edge (seen in the macOS VM, 2026-11-19).
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.headline)
                content
            }
            .padding(16)
            .frame(minWidth: 300, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(infos) { info in
                VStack(alignment: .leading, spacing: 6) {
                    if infos.count > 1 { Text(info.title).font(.subheadline.weight(.semibold)) }
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                        row("Session") { session(info) }
                        row("Machine") { Text(info.machine) }
                        if let started = info.started() { row("Session started") { Text(started) } }
                        if let folder = info.folder { row("Folder") { Text(folder).textSelection(.enabled) } }
                        if let running = info.running { row("Running") { Text(running) } }
                        if let elsewhere = info.openElsewhere {
                            row("Open") { Text(elsewhere) }
                        } else if asking, refresh != nil, info.tmuxSession != nil {
                            row("Open") { Text("Checking…").foregroundStyle(.secondary) }
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("terminal-info-\(info.id.uuidString)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            defer { asking = false }
            guard let refresh else { return }
            infos = await refresh()
        }
    }

    @ViewBuilder
    private func session(_ info: TerminalSessionInfo) -> some View {
        if let name = info.tmuxSession {
            HStack(spacing: 6) {
                Text(name).monospaced().textSelection(.enabled)
                Button(copied == info.id ? "Copied" : "Copy", systemImage: copied == info.id ? "checkmark" : "doc.on.doc") {
                    TerminalSessionInfo.copy(name)
                    copied = info.id
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Copy the session's name")
                .accessibilityLabel(copied == info.id ? "Copied" : "Copy Session Name")
                .accessibilityIdentifier("terminal-info-copy")
            }
        } else {
            Text("Not in tmux").foregroundStyle(.secondary)
        }
    }

    private func row<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            value()
        }
    }
}
