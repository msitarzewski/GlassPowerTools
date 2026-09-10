//
//  ServerInfoView.swift
//  Glass Power Tools — GlassTerminal
//
//  Moved verbatim from glas.sh's ConnectionManagerView.swift (lines 3407-3518 and 3691-3696) on 2026-09-10 when the shell
//  took over the connection library. Read-only details for a saved server.
//

import SwiftUI
import GlasSecretStore

struct ServerInfoView: View {
    let server: ServerConfiguration
    let session: TerminalSession?
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    infoRow("Name", server.name)
                    infoRow("Host", "\(server.host):\(server.port)")
                    infoRow("User", server.username)
                    infoRow("Auth", server.authMethod.displayName)
                    if server.authMethod == .sshKey {
                        infoRow("Key Type", selectedSSHKeyBadge)
                        infoRow("Key Storage", selectedSSHKeyStorage)
                        infoRow("Key Migration", selectedSSHKeyMigrationState)
                    }
                }

                Section("Session") {
                    infoRow("State", session?.state.displayName ?? "Disconnected")
                    infoRow("Progress", session?.connectionProgress?.tickerLabel ?? "Idle")
                    infoRow(
                        "Last Connected",
                        server.lastConnected.map {
                            relativeDateFormatter.localizedString(for: $0, relativeTo: Date())
                        } ?? "Never"
                    )
                }

                Section("Advanced") {
                    infoRow("TERM", server.terminalType)
                    let initialGeometry = settingsManager.initialTerminalGeometry(for: server)
                    infoRow(
                        "Initial Size",
                        "\(initialGeometry.columns) × \(initialGeometry.rows)"
                            + (server.initialTerminalColumns == nil ? " (App Default)" : " (Connection)")
                    )
                    infoRow("Keep Alive", "\(server.keepAliveInterval)s")
                    infoRow("Legacy Algorithms", server.legacyAlgorithmsEnabled ? "Allowed" : "Disabled")
                }

                if !server.tags.isEmpty {
                    Section("Tags") {
                        Text(server.tags.joined(separator: ", "))
                    }
                }
            }
            .navigationTitle("Server Info")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private var selectedSSHKeyBadge: String {
        guard let key = selectedSSHKey else {
            return "Not selected"
        }
        return key.keyTypeBadge
    }

    private var selectedSSHKeyStorage: String {
        guard let key = selectedSSHKey else { return "Unknown" }
        switch key.storageKind {
        case .legacy:
            return "Legacy Keychain"
        case .imported:
            return "Imported Keychain"
        case .secureEnclave:
            return "Secure Enclave Hardware"
        }
    }

    private var selectedSSHKeyMigrationState: String {
        guard let key = selectedSSHKey else { return "Unknown" }
        switch key.migrationState {
        case .notNeeded:
            return "Not needed"
        case .pending:
            return "Pending"
        case .migrated:
            return "Migrated"
        case .failed:
            return "Failed"
        }
    }

    private var selectedSSHKey: StoredSSHKey? {
        guard let keyID = server.sshKeyID else { return nil }
        return settingsManager.sshKeys.first(where: { $0.id == keyID })
    }
}

private let relativeDateFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter
}()
