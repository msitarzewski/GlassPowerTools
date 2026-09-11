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
    @State private var editingHost: GlassShellHost?
    @State private var addingServiceTo: GlassShellHost?
    @State private var deleting: GlassShellHost?
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
                // Embedded in the layered window's own column: paints only on visionOS (rounded
                // panel); on macOS and iOS the column is flat and the window paints once.
                GlassLayeredPanel(role: .embedded) {
                    if let id, let host = model.host(id) { detail(host) } else { emptyDetail }
                }
            } toolbarActions: {
                HStack {
                    ForEach(model.registry.registered, id: \.kind) { capability in
                        capability.libraryToolbarItems()
                    }
                    // On the Mac "Add Host" belongs to the sidebar column (left of the sidebar
                    // toggle); compact stacks and the visionOS tab bar have no sidebar region.
                    #if !os(macOS)
                    addHostButton
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                        .accessibilityIdentifier("connection-library-settings")
                    #endif
                }
            } presentationAnchor: {
                alertAnchor
            }
            #if os(macOS)
            .sidebarActions { addHostButton }
            #endif
        }
        .sheet(isPresented: $addingHost) { GlassShellHostEditor(model: model, host: nil) { selection = $0 } }
        .sheet(item: $editingHost) { GlassShellHostEditor(model: model, host: $0) { _ in } }
        .sheet(item: $addingServiceTo) { GlassShellServiceEditor(model: model, host: $0) }
        .sheet(item: $model.placeholderRequest) { GlassShellPlaceholderSession(request: $0) }
        .sheet(item: $model.addressRequest) { GlassShellAddressPrompt(model: model, request: $0) }
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
        #if os(macOS)
        // glas.sh's Connections window minimum; with the scene's default size this keeps the
        // detail's controls inside the window instead of below its bottom edge.
        .frame(minWidth: 900, minHeight: 560)
        #endif
    }

    private var addHostButton: some View {
        Button("Add Host", systemImage: "plus") { addingHost = true }
            .keyboardShortcut("n", modifiers: .command)
            .accessibilityIdentifier("connection-library-add-host")
    }

    // MARK: Row

    private func row(_ item: GlassLibraryItem<HostID>) -> some View {
        GlassLibraryConnectionRow(name: item.name, subtitle: item.subtitle, isFavorite: item.isFavorite,
                                  lastConnected: item.lastConnected, nameAccessibilityIdentifier: "host-row-\(item.name)") {
            // The spatial sidebar is narrow: an icon-only Connect (press and hold still opens the
            // picker) and the service icons in one row, so nothing wraps. Wide rows keep the label.
            #if os(visionOS)
            HStack(spacing: 6) {
                serviceIcons(for: item.id)
                GlassShellConnectControl(model: model, hostID: item.id, compact: true)
            }
            .fixedSize(horizontal: true, vertical: false)
            #else
            HStack(spacing: 8) {
                serviceIcons(for: item.id)
                GlassShellConnectControl(model: model, hostID: item.id)
            }
            #endif
        }
        // The kit row combines its children into one element. macOS joins the children's
        // identifiers into that element's identifier (`host-row-x-host-service-ssh-…`), so the
        // row is named here explicitly; its label still lists every service icon's name.
        #if os(macOS)
        .accessibilityIdentifier("host-row-\(item.name)")
        #endif
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
            VStack(spacing: 8) {
                Text(model.hosts.isEmpty ? "Every machine you own, and every service on it, in one library."
                     : "Choose a host to see its services.")
                if !model.hasSharedContainer {
                    Text(model.hostLibraryStatus).foregroundStyle(.secondary)
                        .accessibilityIdentifier("connection-library-status")
                }
            }
        } actions: {
            Button("Add Host") { addingHost = true }.accessibilityIdentifier("connection-library-add-host-empty")
        }
    }

    private func detail(_ host: GlassShellHost) -> some View {
        GlassLibraryDetail(title: host.displayName, content: {
            Section("Services") {
                if host.services.isEmpty {
                    Text("No services yet. Add a terminal, database or desktop to this host.")
                        .foregroundStyle(.secondary)
                }
                ForEach(host.services) { service in
                    serviceRow(service, host: host)
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
                if host.addresses.count > 1 {
                    LabeledContent("Address", value: host.addresses.joined(separator: " · "))
                        .accessibilityIdentifier("host-detail-address")
                    Text("The records that make up this host disagree on the address. Edit the host to settle it.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if let address = host.address {
                    LabeledContent("Address", value: address).accessibilityIdentifier("host-detail-address")
                } else {
                    // The button carries the row's identity: an identifier on the LabeledContent
                    // would hide the button from the accessibility tree on macOS.
                    LabeledContent("Address") {
                        Button("Set Address…") { model.addressRequest = GlassShellAddressRequest(host: host, endpointID: nil) }
                            .accessibilityIdentifier("host-detail-set-address")
                    }
                }
                if !host.aliases.isEmpty { LabeledContent("Also known as", value: host.aliases.joined(separator: ", ")) }
                if !host.tags.isEmpty { LabeledContent("Collections", value: host.tags.joined(separator: ", ")) }
                if let last = model.lastConnected(host.id) { LabeledContent("Last connected") { Text(last, style: .relative) } }
                else { LabeledContent("Last connected", value: "Never") }
                if let used = model.lastUsedService(for: host.id) {
                    LabeledContent("Connect opens", value: Self.connectOpensText(used, host: host))
                }
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

    /// One service: its name and kind at the leading edge, Connect and the capability's actions
    /// at the trailing edge. The name truncates first. When the column cannot fit the actions
    /// inline they collapse into one overflow menu beside Connect, so nothing ever clips at the
    /// trailing edge (the 900-pt minimum window showed the trash button cut off, 2026-09-11).
    private func serviceRow(_ service: HostServiceLink, host: GlassShellHost) -> some View {
        let identity = HStack(spacing: 10) {
            Image(systemName: GlassServicePresentation.symbolName(for: service.kind))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(service.displayName).lineLimit(1).truncationMode(.tail)
                Text(GlassServicePresentation.displayName(for: service.kind))
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .layoutPriority(0)
        let connect = Button("Connect") { model.connect(hostID: host.id, endpointID: service.endpointID) }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("host-service-connect-\(service.kind.rawValue)")
        let owner = host.member(owning: service.endpointID)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                identity
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    connect
                    if let owner { model.registry.serviceDetailActions(service: service, host: owner) }
                }
                .fixedSize()
                .layoutPriority(1)
            }
            HStack(spacing: 12) {
                identity
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    connect
                    if let owner {
                        Menu {
                            model.registry.serviceDetailActions(service: service, host: owner)
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                        }
                        .labelStyle(.iconOnly)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .accessibilityIdentifier("host-service-more-\(service.kind.rawValue)")
                    }
                }
                .fixedSize()
                .layoutPriority(1)
            }
        }
    }

    /// "Desktop · What is this?" — the kind first, because the endpoint's own name came from
    /// whichever app saved it and may say nothing about the service; the kind alone when the
    /// name adds nothing (it equals the host's name or the shell's default "Kind on Host").
    static func connectOpensText(_ service: HostServiceLink, host: GlassShellHost) -> String {
        let kind = GlassServicePresentation.displayName(for: service.kind)
        let name = service.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let redundant = name.isEmpty
            || name.caseInsensitiveCompare(host.displayName) == .orderedSame
            || name.caseInsensitiveCompare(kind) == .orderedSame
            || name.caseInsensitiveCompare("\(kind) on \(host.displayName)") == .orderedSame
        return redundant ? kind : "\(kind) · \(name)"
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
        do { try await body() } catch { model.errorMessage = GlassShellError.message(for: error) }
    }
}

/// Connect plus the service picker: a chevron menu beside the button on Mac,
/// press-and-hold on touch. A host with one service is a plain Connect.
public struct GlassShellConnectControl: View {
    private let model: GlassShellModel
    private let hostID: HostID
    private let prominent: Bool
    /// Icon-only, single line, for narrow rows; the picker still opens on press-and-hold.
    private let compact: Bool

    public init(model: GlassShellModel, hostID: HostID, prominent: Bool = false, compact: Bool = false) {
        self.model = model
        self.hostID = hostID
        self.prominent = prominent
        self.compact = compact
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

    @ViewBuilder private var connectButton: some View {
        if compact {
            Button("Connect", systemImage: "play.fill") { model.connect(hostID: hostID) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .fixedSize()
                .accessibilityLabel("Connect")
                .accessibilityIdentifier("host-connect")
        } else {
            Button("Connect", systemImage: "play.fill") { model.connect(hostID: hostID) }
                .lineLimit(1)
                .fixedSize()
                .buttonStyle(.borderedProminent)
                .controlSize(prominent ? .large : .small)
                .accessibilityIdentifier("host-connect")
        }
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
