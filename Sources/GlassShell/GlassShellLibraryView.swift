import GlassLayers
import SwiftUI
import GlassConnectionKit
import GlassConnectionUI

/// The host library. Shape copied from glassDT's `DesktopLibraryView`; the
/// rows and detail are host-centric, the "Paired Services" section is replaced
/// by the host's own services and "Add a service…", and no external-app routing
/// remains. The window and detail panel are the Stage 1 layering proof surfaces.
public struct GlassShellLibraryView: View {
    @Bindable private var model: GlassShellModel
    @State private var selection: HostID?
    @State private var scope = GlassLibraryScope.allConnections
    @State private var search = ""
    @State private var addingHost = false
    @State private var editingHost: HostProfile?
    @State private var addingServiceTo: HostProfile?
    @State private var deleting: HostProfile?
    @State private var showSettings = false
    @Environment(\.scenePhase) private var scenePhase

    public init(model: GlassShellModel) { self.model = model }

    public var body: some View {
        GlassLayeredWindow {
            GlassConnectionLibrary(items: model.items, selection: $selection, scope: $scope, searchText: $search,
                                   order: .source, columnAutosaveName: "com.glasspowertools.library.columns",
                                   onActivate: { model.connect(hostID: $0) }) { item in
                row(item)
            } detail: { id in
                GlassLayeredPanel {
                    if let id, let host = model.host(id) { detail(host) } else { emptyDetail }
                }
            } toolbarActions: {
                HStack {
                    Button("Add Host", systemImage: "plus") { addingHost = true }
                        .keyboardShortcut("n", modifiers: .command)
                        .accessibilityIdentifier("connection-library-add-host")
                    #if !os(macOS)
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                        .accessibilityIdentifier("connection-library-settings")
                    #endif
                }
            } presentationAnchor: {
                alertAnchor
            }
        }
        .sheet(isPresented: $addingHost) { GlassShellHostEditor(model: model, host: nil) { selection = $0 } }
        .sheet(item: $editingHost) { GlassShellHostEditor(model: model, host: $0) { _ in } }
        .sheet(item: $addingServiceTo) { GlassShellServiceEditor(model: model, host: $0) }
        .sheet(item: $model.placeholderRequest) { GlassShellPlaceholderSession(request: $0) }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                GlassShellSettingsView(model: model)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showSettings = false }.accessibilityIdentifier("settings-done") } }
            }
            #if os(visionOS)
            .frame(width: 760, height: 560)
            #endif
        }
        .task { if !model.isLoaded { await model.load() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.load() } } }
    }

    // MARK: Row

    private func row(_ item: GlassLibraryItem<HostID>) -> some View {
        GlassLibraryConnectionRow(name: item.name, subtitle: item.subtitle, isFavorite: item.isFavorite,
                                  lastConnected: item.lastConnected, nameAccessibilityIdentifier: "host-row-\(item.name)") {
            HStack(spacing: 8) {
                serviceIcons(for: item.id)
                GlassShellConnectControl(model: model, hostID: item.id)
            }
        }
        .contextMenu {
            Button("Connect") { model.connect(hostID: item.id) }
            Button("Edit") { editingHost = model.host(item.id) }
            Button(item.isFavorite ? "Remove Favorite" : "Add Favorite") { model.toggleFavorite(item.id) }
            Button("Delete", role: .destructive) { deleting = model.host(item.id) }
        }
    }

    private func serviceIcons(for id: HostID) -> some View {
        HStack(spacing: 4) {
            ForEach(model.serviceKinds(for: id), id: \.self) { kind in
                Image(systemName: GlassServicePresentation.symbolName(for: kind))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(GlassServicePresentation.displayName(for: kind))
                    .accessibilityIdentifier("host-service-\(kind.rawValue)")
            }
        }
    }

    // MARK: Detail

    private var emptyDetail: some View {
        ContentUnavailableView {
            Label(model.hosts.isEmpty ? "Your Hosts" : "Select a Host", systemImage: "server.rack")
        } description: {
            Text(model.hosts.isEmpty ? "Every machine you own, and every service on it, in one library."
                 : "Choose a host to see its services.")
        } actions: {
            Button("Add Host") { addingHost = true }.accessibilityIdentifier("connection-library-add-host-empty")
        }
    }

    private func detail(_ host: HostProfile) -> some View {
        GlassLibraryDetail(title: host.displayName, content: {
            Section("Services") {
                if host.services.isEmpty {
                    Text("No services yet. Add a terminal, database or desktop to this host.")
                        .foregroundStyle(.secondary)
                }
                ForEach(host.services) { service in
                    HStack {
                        Label(service.displayName, systemImage: GlassServicePresentation.symbolName(for: service.kind))
                        Spacer()
                        Text(GlassServicePresentation.displayName(for: service.kind)).foregroundStyle(.secondary)
                        Button("Connect") { model.connect(hostID: host.id, endpointID: service.endpointID) }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("host-service-connect-\(service.kind.rawValue)")
                    }
                    .contextMenu {
                        Button("Remove Service", role: .destructive) {
                            Task { await run { try await model.removeService(service.endpointID, from: host.id) } }
                        }
                    }
                }
                Button("Add a service…", systemImage: "plus.circle") { addingServiceTo = host }
                    .accessibilityIdentifier("host-add-service")
            }
            Section("Host") {
                if !host.aliases.isEmpty { LabeledContent("Also known as", value: host.aliases.joined(separator: ", ")) }
                if !host.tags.isEmpty { LabeledContent("Collections", value: host.tags.joined(separator: ", ")) }
                if let last = model.lastConnected(host.id) { LabeledContent("Last connected") { Text(last, style: .relative) } }
                else { LabeledContent("Last connected", value: "Never") }
                if let used = model.lastUsedService(for: host.id) { LabeledContent("Connect opens", value: used.displayName) }
                Button(model.isFavorite(host.id) ? "Remove Favorite" : "Add Favorite",
                       systemImage: model.isFavorite(host.id) ? "star.fill" : "star") { model.toggleFavorite(host.id) }
                    .accessibilityIdentifier("host-favorite")
            }
            if !model.hasSharedContainer {
                Section { Text(model.hostLibraryStatus).font(.footnote).foregroundStyle(.secondary) }
            }
        }, actions: {
            HStack {
                GlassShellConnectControl(model: model, hostID: host.id, prominent: true)
                Button("Edit") { editingHost = host }.accessibilityIdentifier("host-edit")
                Button("Delete", role: .destructive) { deleting = host }.accessibilityIdentifier("host-delete")
            }.buttonStyle(.bordered).controlSize(.large)
        })
    }

    // MARK: Alerts

    private var alertAnchor: some View {
        Color.clear.frame(width: 0, height: 0).allowsHitTesting(false)
            .alert("Delete Host?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                   presenting: deleting) { host in
                Button("Delete", role: .destructive) {
                    deleting = nil
                    Task { await run { try await model.deleteHost(host.id) } }
                }.accessibilityIdentifier("host-delete-confirm")
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: { host in
                Text("This removes \(host.displayName) and its \(host.services.count) service link\(host.services.count == 1 ? "" : "s") from the shared library. Credentials are not touched.")
            }
            .alert("Unable to Complete", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK") { model.errorMessage = nil }
            } message: { Text(model.errorMessage ?? "") }
    }

    private func run(_ body: () async throws -> Void) async {
        do { try await body() } catch { model.errorMessage = error.localizedDescription }
    }
}

/// Connect plus the service picker: a chevron menu beside the button on Mac,
/// press-and-hold on touch. A host with one service is a plain Connect.
public struct GlassShellConnectControl: View {
    private let model: GlassShellModel
    private let hostID: HostID
    private let prominent: Bool

    public init(model: GlassShellModel, hostID: HostID, prominent: Bool = false) {
        self.model = model
        self.hostID = hostID
        self.prominent = prominent
    }

    private var services: [HostServiceLink] { model.services(for: hostID) }

    public var body: some View {
        if services.isEmpty {
            EmptyView()
        } else if services.count == 1 {
            connectButton
        } else {
            #if os(macOS)
            HStack(spacing: 0) {
                connectButton
                Menu { serviceButtons } label: { Image(systemName: "chevron.down") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("Choose a service")
                    .accessibilityIdentifier("host-connect-menu")
            }
            #else
            connectButton
                .contextMenu { serviceButtons }
                .accessibilityHint("Touch and hold to choose a service")
            #endif
        }
    }

    private var connectButton: some View {
        Button("Connect", systemImage: "play.fill") { model.connect(hostID: hostID) }
            .buttonStyle(.borderedProminent)
            .controlSize(prominent ? .large : .small)
            .accessibilityIdentifier("host-connect")
    }

    @ViewBuilder private var serviceButtons: some View {
        ForEach(services) { service in
            Button(service.displayName, systemImage: GlassServicePresentation.symbolName(for: service.kind)) {
                model.connect(hostID: hostID, endpointID: service.endpointID)
            }
            .accessibilityIdentifier("host-connect-menu-\(service.kind.rawValue)")
        }
    }
}
