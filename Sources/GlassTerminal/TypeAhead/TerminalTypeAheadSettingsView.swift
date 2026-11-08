//
//  TerminalTypeAheadSettingsView.swift
//  Glass Power Tools — GlassTerminal
//
//  Settings ▸ Suggestions (D102, 2026-11-06): type-ahead on or off, the Mac's grey text, keeping history, each
//  source, and each machine's kept history with Forget. `tasks/2026-11/2026-11-06_type-ahead.md`, "Privacy".
//

import SwiftUI
import GlassLayers

struct TerminalTypeAheadSettingsView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var settings = TerminalTypeAheadSettings.load(from: GlassUITestRun.settingsDefaults)
    @State private var counts: [String: Int] = [:]
    @State private var confirmingForgetAll = false
    @State private var importing: Set<String> = []
    @State private var integrationStates: [UUID: TerminalShellIntegrationInstaller.State] = [:]
    @State private var changingIntegration: Set<UUID> = []
    @State private var integrationError: String?
    /// What the last import said, by machine, in place of its count until the page is opened again.
    @State private var importNotes: [String: String] = [:]

    private let history = TerminalCommandHistory.shared

    var body: some View {
        Form {
            Section {
                Toggle("Suggest commands as you type", isOn: $settings.enabled)
                #if os(macOS)
                Toggle("Show the suggestion in grey after the cursor", isOn: $settings.showsGreyText)
                    .disabled(!settings.enabled)
                #endif
                Toggle("Keep the commands run on each machine", isOn: $settings.keepsHistory)
                    .disabled(!settings.enabled)
                #if os(macOS)
                Toggle("Mark prompts in this Mac's zsh terminals", isOn: $settings.integratesThisMac)
                    .disabled(!settings.enabled)
                    .help("zsh tells the terminal where its prompt and each command begin, so suggestions follow the line exactly. Your own start-up files are read as always. Applies to terminals opened from now on.")
                #endif
            } footer: {
                #if os(macOS)
                Text("→ takes the whole suggestion, ⌥→ its next word. Commands are kept on this device only, never synced, and never those that look like they carry a password or token.")
                #else
                Text("Tap a suggestion above the keyboard to type the rest of it. Commands are kept on this device only, never synced, and never those that look like they carry a password or token.")
                #endif
            }

            Section("Suggest from") {
                ForEach(Self.sources, id: \.source) { item in
                    Toggle(isOn: sourceBinding(item.source)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            Text(item.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!settings.enabled)
                }
            }

            Section {
                ForEach(connectedSessions, id: \.server.id) { session in
                    LabeledContent(session.server.name) {
                        HStack {
                            Text(integrationText(session.server.id)).foregroundStyle(.secondary)
                            if case .installed = integrationStates[session.server.id] {
                                Button("Remove") { changeIntegration(on: session, install: false) }
                                    .disabled(changingIntegration.contains(session.server.id))
                            } else if case .notInstalled = integrationStates[session.server.id] {
                                Button("Install") { changeIntegration(on: session, install: true) }
                                    .disabled(changingIntegration.contains(session.server.id))
                            }
                        }
                    }
                }
                if connectedSessions.isEmpty {
                    Text("Connect a terminal to a machine to install it there.").foregroundStyle(.secondary)
                }
            } header: {
                Text("Shell integration on your machines")
            } footer: {
                Text("The shell tells the terminal where its prompt and each command begin, so suggestions follow the line exactly. Installing adds one line to the shell's start-up file (~/.zshrc, ~/.bashrc or fish's config.fish) and a script in ~/.config/glasspowertools; Remove takes both out. Terminals opened afterwards are marked.")
            }

            Section {
                ForEach(machines, id: \.key) { machine in
                    LabeledContent(machine.name) {
                        HStack {
                            Text(importNotes[machine.key]
                                 ?? (counts[machine.key, default: 0] == 1 ? "1 command" : "\(counts[machine.key, default: 0]) commands"))
                                .foregroundStyle(.secondary)
                            Button("Import") { importHistory(machine) }
                                .disabled(importing.contains(machine.key) || importReader(for: machine.key) == nil
                                          || !settings.uses(.imported))
                                .help(importReader(for: machine.key) == nil
                                      ? "Connect a terminal to \(machine.name) first: its history is read over that connection."
                                      : "Read \(machine.name)'s own zsh, bash or fish history into its suggestions.")
                            Button("Forget") {
                                history.forgetAll(machine: machine.key)
                                refreshCounts()
                            }
                            .disabled(counts[machine.key, default: 0] == 0)
                        }
                    }
                }
                Button("Forget All Commands…", role: .destructive) { confirmingForgetAll = true }
                    .disabled(counts.values.allSatisfy { $0 == 0 })
            } header: {
                Text("Kept on this device")
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshCounts)
        .task { await refreshIntegrationStates() }
        .alert("The shell integration couldn't be changed", isPresented: Binding(
            get: { integrationError != nil }, set: { if !$0 { integrationError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(integrationError ?? "")
        }
        .onChange(of: settings) { _, new in new.save(to: GlassUITestRun.settingsDefaults) }
        .confirmationDialog("Forget every command kept for suggestions?", isPresented: $confirmingForgetAll,
                            titleVisibility: .visible) {
            Button("Forget All", role: .destructive) {
                history.forgetEverything()
                refreshCounts()
            }
        } message: {
            Text("Suggestions start again from what you run next. Shells' own history on each machine isn't touched.")
        }
    }

    /// This Mac's own terminals, then each machine with a terminal, by name.
    private var machines: [(key: String, name: String)] {
        var list: [(key: String, name: String)] = []
        #if os(macOS)
        list.append((TerminalCommandHistory.thisMac, "This Mac"))
        #endif
        list += sessionManager.serverManager.servers
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { ($0.id.uuidString, $0.name) }
        return list
    }

    private func refreshCounts() {
        counts = Dictionary(uniqueKeysWithValues: machines.map { ($0.key, history.count(for: $0.key)) })
    }

    /// One connected terminal per machine: what the integration is read and installed through.
    private var connectedSessions: [TerminalSession] {
        var seen: Set<UUID> = []
        return sessionManager.sessions.filter { session in
            guard case .connected = session.state else { return false }
            return seen.insert(session.server.id).inserted
        }.sorted { $0.server.name.localizedStandardCompare($1.server.name) == .orderedAscending }
    }

    private func integrationText(_ server: UUID) -> String {
        if changingIntegration.contains(server) { return "Changing…" }
        switch integrationStates[server] {
        case .installed(let shell)?: return "Installed (\(shell.rawValue))"
        case .notInstalled(let shell, let others)?:
            return others.isEmpty ? "Not installed (\(shell.rawValue))" : "\(others.joined(separator: ", ")) marks its prompts"
        case .unsupported(let path)?: return "Its shell (\(path ?? "unknown")) can't be marked"
        case nil: return "Checking…"
        }
    }

    private func refreshIntegrationStates() async {
        for session in connectedSessions {
            integrationStates[session.server.id] = await TerminalShellIntegrationInstaller.state(of: session)
        }
    }

    private func changeIntegration(on session: TerminalSession, install: Bool) {
        let id = session.server.id
        changingIntegration.insert(id)
        Task {
            do {
                if install {
                    try await TerminalShellIntegrationInstaller.install(on: session)
                } else {
                    try await TerminalShellIntegrationInstaller.remove(from: session)
                }
            } catch {
                integrationError = error.localizedDescription
            }
            integrationStates[id] = await TerminalShellIntegrationInstaller.state(of: session)
            changingIntegration.remove(id)
        }
    }

    /// Where a machine's own history can be read now: this Mac's files, or a connected terminal's SFTP.
    private func importReader(for machine: String) -> (reader: any TerminalFolderReader, home: String)? {
        #if os(macOS)
        if machine == TerminalCommandHistory.thisMac { return (TerminalLocalFolderReader(), NSHomeDirectory()) }
        #endif
        guard let session = sessionManager.sessions.first(where: {
            guard $0.server.id.uuidString == machine, case .connected = $0.state else { return false }
            return true
        }) else { return nil }
        let holder = TerminalSFTPClientHolder { [weak session] in
            guard let session else { throw SSHError.notConnected }
            return try await TerminalRemoteDrops.openClient(for: session)
        }
        // SFTP starts in the account's home folder: names relative to it reach the history files.
        return (TerminalRemoteFolderReader(holder: holder), ".")
    }

    private func importHistory(_ machine: (key: String, name: String)) {
        guard let source = importReader(for: machine.key) else { return }
        importing.insert(machine.key)
        importNotes[machine.key] = "Reading…"
        Task {
            let added = await TerminalHistoryImport.importHistory(into: history, machine: machine.key,
                                                                  reader: source.reader, home: source.home)
            history.saveNow()
            importing.remove(machine.key)
            refreshCounts()
            importNotes[machine.key] = added == 0 ? "Nothing new to import" : "\(added) imported"
        }
    }

    private func sourceBinding(_ source: TerminalTypeAheadSource) -> Binding<Bool> {
        Binding(
            get: { !settings.disabledSources.contains(source) },
            set: { on in
                if on { settings.disabledSources.remove(source) } else { settings.disabledSources.insert(source) }
            })
    }

    private static let sources: [(source: TerminalTypeAheadSource, title: String, detail: String)] = [
        (.history, "Commands you've run", "On the same machine, ranked by how often, how lately, in which folder"),
        (.imported, "The machine's own shell history", "Read once you allow it, from zsh, bash or fish"),
        (.snippet, "Snippets", "Your saved commands"),
        (.library, "Your library", "Machine names for ssh and scp, database names for psql and mysql"),
        (.folder, "The current folder", "Git branches, file names, package scripts, make targets"),
        (.tool, "Common tools", "Subcommands and options of git, docker, kubectl, npm and more"),
        (.commands, "Programs on the machine", "Command names from its PATH folders and the shell's own commands"),
        (.screen, "Words on screen", "Names, hashes and paths printed above the prompt"),
        (.assistant, "On-device AI", "A likely next command, worked out on this device; off unless turned on"),
    ]
}
