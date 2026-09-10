//
//  TerminalTailscaleView.swift
//  Glass Power Tools — GlassTerminal
//
//  glas.sh's Tailscale network mode (device list, import as server, quick connect), re-homed as
//  its own surface. Bodies are verbatim from ConnectionManagerView (lines 1409-1473, 1655-1800,
//  3647-3690); connecting and importing go through the runtime and the one connect flow.
//

import SwiftUI
import os

struct TerminalTailscaleView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(GlassTerminalRuntime.self) private var runtime

    private var serverManager: ServerManager { sessionManager.serverManager }
    @State private var selectedTailscaleDeviceID: String?
    @State private var tailscaleClient = TailscaleClient()
    @State private var tailscaleUsernamePromptDevice: TailscaleDevice?
    @State private var quickConnectPassword: String = ""
    @State private var quickConnectUsername: String = ""
    @State private var quickConnectPort: String = "22"
    @State private var connectionFailureMessage: String?

    var body: some View {
        NavigationSplitView {
            tailscaleDetailView
                .navigationTitle("Tailscale")
        } detail: {
            tailscaleDeviceDetail
        }
        .alert("Tailscale", isPresented: Binding(
            get: { connectionFailureMessage != nil },
            set: { if !$0 { connectionFailureMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(connectionFailureMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .tailscaleCredentialsDidChange)) { _ in
            tailscaleClient.invalidateCredentialState()
            selectedTailscaleDeviceID = nil
            Task {
                await runtime.refreshTailscaleConfiguration()
                if runtime.tailscaleIsConfigured { loadTailscaleDevices() }
            }
        }
        .onChange(of: tailscaleClient.devices.map(\.id)) { _, deviceIDs in
            if let selectedTailscaleDeviceID,
               !deviceIDs.contains(selectedTailscaleDeviceID) {
                self.selectedTailscaleDeviceID = nil
            }
        }
        .task { serverManager.loadServersIfNeeded() }
    }

    private var selectedTailscaleDevice: TailscaleDevice? {
        guard let selectedTailscaleDeviceID else { return nil }
        return tailscaleClient.devices.first(where: { $0.id == selectedTailscaleDeviceID })
    }

    private func savedServer(for device: TailscaleDevice) -> ServerConfiguration? {
        serverManager.servers.first {
            $0.provenance?.provider == .tailscale
                && $0.provenance?.externalID == device.id
        }
    }

    private var tailscaleUsernamePromptBinding: Binding<Bool> {
        Binding(
            get: { tailscaleUsernamePromptDevice != nil },
            set: { isPresented in
                if !isPresented {
                    tailscaleUsernamePromptDevice = nil
                    quickConnectUsername = ""
                    quickConnectPassword = ""
                    quickConnectPort = "22"
                }
            }
        )
    }

    private func loadTailscaleDevices() {
        let tailnet = settingsManager.tailscaleTailnet.trimmingCharacters(in: .whitespacesAndNewlines)
        if tailnet.isEmpty {
            // Use "-" wildcard — works for any authenticated user
            Logger.tailscale.info("No tailnet configured, using '-' wildcard")
        }
        let effectiveTailnet = tailnet.isEmpty ? "-" : tailnet
        Logger.tailscale.info("Loading Tailscale devices for tailnet: '\(effectiveTailnet)'")
        Task {
            await tailscaleClient.loadDevices(tailnet: effectiveTailnet)
        }
    }

    private func importTailscaleDevice(_ device: TailscaleDevice) {
        guard savedServer(for: device) == nil else { return }
        guard let draft = TerminalTailscaleImport.draft(for: device) else {
            connectionFailureMessage = "This Tailscale device has an invalid identity and was not imported."
            return
        }
        runtime.enqueue(.addServer(draft: draft))
    }

    @ViewBuilder
    private var tailscaleDeviceDetail: some View {
        if let device = selectedTailscaleDevice {
            let savedServer = savedServer(for: device)
            VStack(spacing: 0) {
                Form {
                    Section("Device") {
                        LabeledContent("Name", value: device.hostname)
                        LabeledContent("Address", value: device.sshAddress)
                        LabeledContent("Operating System", value: device.os)
                        if !device.user.isEmpty {
                            LabeledContent("Owner", value: device.user)
                        }
                    }
                    Section("Library") {
                        LabeledContent("Saved Connection", value: savedServer?.name ?? "Not imported")
                    }
                }
                .formStyle(.grouped)
                HStack {
                    if let savedServer {
                        Button("Edit", systemImage: "pencil") {
                            runtime.enqueue(.editServer(savedServer))
                        }
                        Spacer()
                        Button("Connect", systemImage: "terminal") {
                            runtime.requestConnect(serverID: savedServer.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier(
                            "connection-library-connect-tailscale-\(device.id)"
                        )
                    } else {
                        Button("Import", systemImage: "square.and.arrow.down") {
                            importTailscaleDevice(device)
                        }
                        .accessibilityIdentifier(
                            "connection-library-import-tailscale-\(device.id)"
                        )
                        Spacer()
                        Button("Connect", systemImage: "terminal") {
                            tailscaleUsernamePromptDevice = device
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier(
                            "connection-library-connect-tailscale-\(device.id)"
                        )
                    }
                }
                .buttonStyle(.bordered)
                .labelStyle(.titleAndIcon)
                .padding()
                .background(.bar)
            }
            .navigationTitle(device.hostname)
            .accessibilityIdentifier("connection-library-detail-tailscale-\(device.id)")
        } else {
            ContentUnavailableView(
                "Select a Tailscale Device",
                systemImage: "network",
                description: Text("Choose a device to connect or save it in the Library.")
            )
            .accessibilityIdentifier("connection-library-detail-empty-tailscale")
        }
    }


    private var tailscaleDetailView: some View {
        List(selection: $selectedTailscaleDeviceID) {
            if tailscaleClient.isLoading {
                HStack {
                    Spacer()
                    ProgressView("Loading Tailscale devices...")
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if let error = tailscaleClient.errorMessage {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            loadTailscaleDevices()
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            } else if tailscaleClient.devices.isEmpty {
                ContentUnavailableView {
                    Label("No Devices", systemImage: "network")
                } description: {
                    Text("No Tailscale devices found. Configure your API key or OAuth credentials in Settings.")
                }
            } else {
                Section("Devices (\(tailscaleClient.devices.count))") {
                    ForEach(tailscaleClient.devices) { device in
                        TailscaleDeviceRow(device: device)
                            .tag(device.id)
                            .contentShape(Rectangle())
                            #if os(iOS)
                            .onTapGesture {
                                selectedTailscaleDeviceID = device.id
                            }
                            #endif
                            .accessibilityIdentifier(
                                "connection-library-tailscale-\(device.id)"
                            )
                            .contextMenu {
                                if savedServer(for: device) == nil {
                                    Button {
                                        importTailscaleDevice(device)
                                    } label: {
                                        Label("Import as Server", systemImage: "square.and.arrow.down")
                                    }
                                }
                            }
                    }
                }
            }
        }
        .accessibilityIdentifier("connection-library-results-network")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    runtime.requestAddServer()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add connection")
                .accessibilityIdentifier("connection-library-add-server-network")
            }
        }
        .task {
            // Use .task instead of .onAppear — async context lets the load complete
            await tailscaleClient.loadDevices(
                tailnet: settingsManager.tailscaleTailnet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "-"
                    : settingsManager.tailscaleTailnet.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        .alert("SSH Login", isPresented: tailscaleUsernamePromptBinding) {
            TextField("Username", text: $quickConnectUsername)
                .terminalTextInputDefaults()
            SecureField("Password", text: $quickConnectPassword)
            TextField("Port", text: $quickConnectPort)
                .terminalNumericInput()
            Button("Connect") {
                if let device = tailscaleUsernamePromptDevice {
                    guard let port = Int(quickConnectPort), (1...65_535).contains(port) else {
                        connectionFailureMessage = "Enter an SSH port from 1 through 65535."
                        return
                    }
                    let config = ServerConfiguration(
                        name: device.hostname,
                        host: device.sshAddress,
                        port: port,
                        username: quickConnectUsername
                    )
                    let password = quickConnectPassword
                    quickConnectUsername = ""
                    quickConnectPassword = ""
                    quickConnectPort = "22"
                    tailscaleUsernamePromptDevice = nil
                    runtime.enqueue(.quickConnect(config, password: password))
                }
            }
            Button("Cancel", role: .cancel) {
                quickConnectUsername = ""
                quickConnectPassword = ""
                quickConnectPort = "22"
                tailscaleUsernamePromptDevice = nil
            }
        } message: {
            if let device = tailscaleUsernamePromptDevice {
                Text("Enter SSH credentials for \(device.hostname) (\(device.sshAddress))")
            }
        }
    }

}

/// Builds the saved-server draft for a Tailscale device (moved from ConnectionManagerView).
enum TerminalTailscaleImport {
    static func draft(for device: TailscaleDevice) -> ServerConfiguration? {
        guard let provenance = ServerConnectionProvenance(
            provider: .tailscale,
            externalID: device.id
        ) else { return nil }
        let importedTags = ["tailscale"] + device.tags.filter { $0 != "tailscale" }
        return ServerConfiguration(
            name: device.hostname,
            host: device.sshAddress,
            port: 22,
            username: "",
            tags: importedTags,
            provenance: provenance
        )
    }
}

private struct TailscaleDeviceRow: View {
    let device: TailscaleDevice

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 10, height: 10)

                Text(device.hostname)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(minWidth: 180, alignment: .leading)

            Text(device.sshAddress)
                .font(.subheadline.monospaced())
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(device.os)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: .capsule)

            Text(device.user)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .trailing)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(device.hostname), \(device.os), \(device.user)")
        .accessibilityHint("Select to show connection details")
    }
}
