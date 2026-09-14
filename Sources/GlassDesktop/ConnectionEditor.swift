import SwiftUI
import GlasSecretStore

struct ConnectionEditor: View {
    let model: DesktopAppModel
    let importNotices: [String]
    private let originalDesktop: DesktopSize
    @State var connection: DesktopConnection
    @State private var password = ""
    @State private var savePassword = false
    @State private var portText: String
    @State private var collections: String
    @State private var error: String?
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    init(model: DesktopAppModel, connection: DesktopConnection, importNotices: [String] = []) {
        self.model = model
        self.importNotices = importNotices
        self.originalDesktop = connection.desktop
        _connection = State(initialValue: connection)
        _portText = State(initialValue: String(connection.port))
        _collections = State(initialValue: connection.tags.joined(separator: ", "))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("connection.error") } }
                if !importNotices.isEmpty {
                    Section("Imported Settings") {
                        ForEach(importNotices, id: \.self) { Text($0).font(.callout) }
                    }.accessibilityIdentifier("connection.importNotes")
                }
                Section("Connection") {
                    Picker("Protocol", selection: $connection.protocol) {
                        ForEach(DesktopProtocol.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .accessibilityIdentifier("connection.protocol")
                    .onChange(of: connection.protocol) { previous, current in
                        // Only an untouched default port follows the protocol.
                        if portText.isEmpty || portText == String(previous.defaultPort) { portText = String(current.defaultPort) }
                    }
                    TextField("Name", text: $connection.name).accessibilityIdentifier("connection.name")
                    TextField("Host", text: $connection.host).accessibilityIdentifier("connection.host")
                        .autocorrectionDisabled()
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    TextField("Port", text: $portText).accessibilityIdentifier("connection.port")
                    TextField("Collections, separated by commas", text: $collections)
                    Toggle("Favorite", isOn: $connection.isFavorite)
                }
                Section {
                    TextField(connection.protocol == .vnc ? "Mac user name (optional)" : "Username", text: $connection.username)
                        .accessibilityIdentifier("connection.username")
                        .autocorrectionDisabled()
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    if connection.protocol == .rdp {
                        TextField("Domain (optional)", text: $connection.domain).autocorrectionDisabled()
                            #if !os(macOS)
                            .textInputAutocapitalization(.never)
                            #endif
                    }
                    Toggle(model.connections.contains(where: { $0.id == connection.id }) ? "Set or update saved password" : "Save password in Keychain", isOn: $savePassword)
                    if model.connections.contains(where: { $0.id == connection.id }) {
                        Text("Leaving this off preserves the existing saved password.").font(.footnote).foregroundStyle(.secondary)
                    }
                    if savePassword {
                        SecureField("Password", text: $password).accessibilityIdentifier("connection.password")
                    }
                    Picker("Credential storage", selection: $connection.mobility) {
                        Text("This device").tag(SecretMobilityPolicy.deviceOnly)
                        Text("iCloud Keychain").tag(SecretMobilityPolicy.iCloudKeychain)
                    }
                    if connection.protocol == .rdp {
                        Picker("Authentication", selection: $connection.authentication) {
                            Text("Network Level Authentication").tag(DesktopAuthentication.networkLevel)
                            Text("Allow TLS fallback").tag(DesktopAuthentication.tls)
                        }.accessibilityIdentifier("connection.authentication")
                    }
                } header: { Text("Account") } footer: {
                    if connection.protocol == .vnc {
                        Text("Apple Screen Sharing signs in with a Mac user name and password. Leave the user name empty for servers that accept only a VNC password. A saved password uses the shared Glass credential store; iCloud Keychain syncs eligible credentials when Keychain syncing is enabled. Saved desktops and service pairings stay on this device.")
                    } else {
                        Text("Choose the authentication supported by your server. A saved password uses the shared Glass credential store. iCloud Keychain syncs eligible credentials when Keychain syncing is enabled. Saved desktops and service pairings stay on this device. Changing storage selects the copy used here; it does not delete existing copies on other devices.")
                    }
                }
                Section {
                    if connection.protocol == .rdp {
                        Picker("Initial resolution", selection: $connection.desktop) {
                            if ![DesktopSize(width: 1280, height: 800), .standard, DesktopSize(width: 2560, height: 1440),
                                 DesktopSize(width: 3840, height: 2160)].contains(originalDesktop) {
                                Text("\(originalDesktop.width) × \(originalDesktop.height)").tag(originalDesktop)
                            }
                            Text("1280 × 800").tag(DesktopSize(width: 1280, height: 800))
                            Text("1920 × 1080").tag(DesktopSize.standard)
                            Text("2560 × 1440").tag(DesktopSize(width: 2560, height: 1440))
                            Text("3840 × 2160").tag(DesktopSize(width: 3840, height: 2160))
                        }
                    }
                    Toggle("Clipboard text", isOn: $connection.clipboardEnabled)
                    if connection.protocol == .rdp { Toggle("Remote audio", isOn: $connection.audioEnabled) }
                } header: { Text("Desktop") } footer: {
                    if connection.protocol == .vnc {
                        Text("The Screen Sharing host chooses the desktop size. Resizing from this app is used when the server offers it; audio is not part of VNC.")
                    }
                }
            }
            .formStyle(.grouped)
            .accessibilityIdentifier("connection.form")
            .navigationTitle(model.connections.contains(where: { $0.id == connection.id }) ? "Edit Desktop" : "New Desktop")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(saving)
                        .accessibilityIdentifier("connection.save")
                }
            }
            .frame(minWidth: 300, idealWidth: 480, minHeight: 420)
        }
    }

    private func save() async {
        guard let port = UInt16(portText), port > 0 else { error = DesktopError.invalidPort.localizedDescription; return }
        connection.port = port
        connection.tags = collections.split(separator: ",").map(String.init)
        saving = true
        defer { saving = false }
        do {
            try await model.save(connection, password: savePassword ? password : nil)
            password = ""
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
