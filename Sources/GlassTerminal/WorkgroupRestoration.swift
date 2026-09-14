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

    var displayName: String {
        intent.label ?? server?.name ?? "Local Terminal"
    }
}

struct LayoutRestorationPlan {
    let targets: [LayoutRestorationTarget]
    let failures: [String]

    init(preset: LayoutPreset, availableServers: [ServerConfiguration]) {
        let serversByID = Dictionary(
            availableServers.map { ($0.id, $0) },
            uniquingKeysWith: { existing, _ in existing }
        )
        var targets: [LayoutRestorationTarget] = []
        var failures: [String] = []

        for (index, intent) in preset.sessionIntents.enumerated() {
            let sessionNumber = index + 1
            guard intent.isSupported else {
                failures.append("Session \(sessionNumber): this saved session intention is not supported by this version of \(GlassProduct.displayName).")
                continue
            }
            switch intent.kind {
            case .local:
                targets.append(LayoutRestorationTarget(intent: intent, server: nil))
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
                targets.append(LayoutRestorationTarget(intent: intent, server: server))
            }
        }

        self.targets = targets
        self.failures = failures
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
            preset.sessionIntents.indices.contains(index) && preset.sessionIntents[index] == value.source
                && servers.contains { $0.id == value.serverID && !$0.legacyAlgorithmsEnabled }
        }
        _replacements = State(initialValue: valid)
        _remember = State(initialValue: !valid.isEmpty)
    }

    private var availableServers: [ServerConfiguration] { servers.filter { !$0.legacyAlgorithmsEnabled } }
    private var canOpen: Bool {
        (!replacements.isEmpty || preset.sessionIntents.contains { $0.kind == .ssh })
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
                    if availableServers.isEmpty {
                        Text("Add an SSH connection in Connections first. Connections requiring legacy security review must be opened directly.")
                    }
                }
                ForEach(Array(preset.sessionIntents.enumerated()).filter { $0.element.kind == .local }, id: \.offset) { index, source in
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
                                    replacements[index] = WorkgroupSSHSubstitution(source: source, serverID: id,
                                        directory: replacements[index]?.directory ?? "",
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

