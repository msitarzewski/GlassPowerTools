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
    @State private var setupMode: GlassShellSetupMode?
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
        // One sheet for Add Host, Add a service, Edit service and Edit Host (rule 15).
        .sheet(item: $setupMode) { mode in
            GlassShellHostSetupSheet(model: model, mode: mode) { selection = $0 }
        }
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
        Button("Add Host", systemImage: "plus") { setupMode = .addHost }
            .keyboardShortcut("n", modifiers: .command)
            .accessibilityIdentifier("connection-library-add-host")
    }

    // MARK: Row

    /// The row is the host's name and its service icons: no subtitle naming or counting the
    /// services the icons already show, and no "last connected" (that lives in the detail's Host
    /// section). Removed family-wide 2026-09-11 at the user's direction.
    private func row(_ item: GlassLibraryItem<HostID>) -> some View {
        GlassLibraryConnectionRow(name: item.name, isFavorite: item.isFavorite,
                                  nameAccessibilityIdentifier: "host-row-\(item.name)") {
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
            Button("Edit") { if let host = model.host(item.id) { setupMode = .editHost(host) } }
            Button(item.isFavorite ? "Remove Favorite" : "Add Favorite") { model.toggleFavorite(item.id) }
            // The device itself is not a record the user added and is not one they can remove
            // (D8); its services are removed individually from the detail.
            if model.host(item.id)?.isLocal != true {
                Button("Delete", role: .destructive) { deleting = model.host(item.id) }
                    .accessibilityIdentifier("host-delete")
            }
        }
    }

    private func serviceIcons(for id: HostID) -> some View {
        HStack(spacing: 4) {
            ForEach(model.serviceKinds(for: id), id: \.self) { kind in
                GlassServiceIcon(GlassServicePresentation.symbol(for: kind))
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
            Button("Add Host") { setupMode = .addHost }.accessibilityIdentifier("connection-library-add-host-empty")
        }
    }

    private func detail(_ host: GlassShellHost) -> some View {
        GlassLibraryDetail(title: host.displayName, content: {
            Section("Services") {
                if host.services.isEmpty {
                    Text(host.isLocal
                         ? "No services yet. Add a database on this device — a SQLite file, or a server running here."
                         : "No services yet. Add a terminal, database or desktop to this host.")
                        .foregroundStyle(.secondary)
                }
                ForEach(host.services) { service in
                    serviceRow(service, host: host)
                        .contextMenu {
                            // A built-in local service has nothing stored behind it, so there is
                            // nothing to remove — and offering the item would only produce an
                            // error the user could not act on.
                            if !host.isBuiltIn(service.endpointID) {
                                Button("Remove Service", role: .destructive) {
                                    Task { await run { try await model.removeService(service.endpointID, from: host.id) } }
                                }
                            }
                        }
                }
                // Tools a configured service makes available, as peer rows: Files (SFTP) today,
                // the editor in Stage 5. They are not services and are never configured here.
                ForEach(host.services) { service in
                    if let owner = host.record(owning: service.endpointID) {
                        ForEach(model.registry.serviceTools(service: service, host: owner)) { tool in
                            toolRow(tool)
                        }
                    }
                }
                if let kind = addableKind(for: host) {
                    Button("Add a service…", systemImage: "plus.circle") { setupMode = .addService(host, kind) }
                        .accessibilityIdentifier("host-add-service")
                }
            }
            Section("Host") {
                if host.isLocal {
                    // This device: there is nothing to reach and nothing to type (D8).
                    LabeledContent("Address", value: "This device").accessibilityIdentifier("host-detail-address")
                    Text("Services here run on this machine: they reach it at \(GlassLocalHost.address), or open a file you choose. Nothing about this host is shared with the other Glass apps or with your other devices.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if host.addresses.count > 1 {
                    LabeledContent("Address", value: host.addresses.joined(separator: " · "))
                        .accessibilityIdentifier("host-detail-address")
                    Text("The records that make up this host disagree on the address. Edit the host to settle it.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    // A record another family app wrote without an address shows "Not set";
                    // Edit on the host, or adding a service, collects it.
                    LabeledContent("Address", value: host.address ?? "Not set").accessibilityIdentifier("host-detail-address")
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
            // Removing a machine is deliberate, not one slip beside Connect: it lives in the
            // row's context menu and at the bottom of the edit sheet (2026-09-11).
            HStack {
                GlassShellConnectControl(model: model, hostID: host.id, prominent: true)
                Button("Edit") { setupMode = .editHost(host) }.accessibilityIdentifier("host-edit")
            }.buttonStyle(.bordered).controlSize(.large)
        })
    }

    /// The tab "Add a service…" opens on: the first kind this host will take that a capability
    /// in this build can create. Nil when the host takes none, and then the button is not shown
    /// rather than opening a sheet that can only refuse.
    private func addableKind(for host: GlassShellHost) -> HostServiceKind? {
        let kinds = GlassShellSetupModel.setupKinds(for: host, registry: model.registry)
        return kinds.first { model.registry.capability(for: $0) != nil } ?? kinds.first
    }

    private func toolRow(_ tool: GlassServiceTool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: tool.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.title).lineLimit(1)
                if let subtitle = tool.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button("Open", systemImage: "play.fill") { tool.open() }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .help("Open \(tool.title)")
                .accessibilityIdentifier("host-tool-open-\(tool.id)")
        }
        .accessibilityIdentifier("host-tool-\(tool.id)")
    }

    /// One service: its name and kind at the leading edge, Connect and the capability's actions
    /// at the trailing edge. The name truncates first. When the column cannot fit the actions
    /// inline they collapse into one overflow menu beside Connect, so nothing ever clips at the
    /// trailing edge (the 900-pt minimum window showed the trash button cut off, 2026-09-11).
    private func serviceRow(_ service: HostServiceLink, host: GlassShellHost) -> some View {
        let suffix = Self.identifierSuffix(for: service, in: host)
        let isBuiltIn = host.isBuiltIn(service.endpointID)
        let identity = HStack(spacing: 10) {
            GlassServiceIcon(GlassServicePresentation.symbol(for: service.kind))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(service.displayName).lineLimit(1).truncationMode(.tail)
                Text(isBuiltIn ? "\(GlassServicePresentation.displayName(for: service.kind)) · Built in"
                     : GlassServicePresentation.displayName(for: service.kind))
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .layoutPriority(0)
        // Wordless, like the library row: the glyph carries the meaning and the label stays for
        // assistive technology and the tooltip.
        let connect = Button("Connect", systemImage: "play.fill") { model.connect(hostID: host.id, endpointID: service.endpointID) }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .help("Connect")
            .accessibilityIdentifier("host-service-connect-\(service.kind.rawValue)\(suffix)")
        // Edit is the shell's: it opens the one host sheet on this service's tab. A built-in
        // local service has no saved configuration to open, so it has no Edit either — the
        // sheet would have nothing to show and would say so as though something were broken.
        let edit = Group {
            if !isBuiltIn {
                Button("Edit", systemImage: "pencil") { setupMode = .editService(host, service) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .help("Edit")
                    .accessibilityIdentifier("host-service-edit-\(service.kind.rawValue)\(suffix)")
            }
        }
        let owner = host.record(owning: service.endpointID)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                identity
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    connect
                    edit
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
                    edit
                    if let owner {
                        Menu {
                            model.registry.serviceDetailActions(service: service, host: owner)
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                        }
                        .labelStyle(.iconOnly)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .accessibilityIdentifier("host-service-more-\(service.kind.rawValue)\(suffix)")
                    }
                }
                .fixedSize()
                .layoutPriority(1)
            }
        }
    }

    /// Several services of one kind on one host are legal in the catalog and are what the device's
    /// own host is made of (D8) — two databases and a shell on one row. Identifiers have to stay
    /// unique or UI automation matches an arbitrary one of them. The first service of a kind keeps
    /// the bare identifier every existing surface and test already uses; the second and later
    /// carry their 1-based position within that kind, which is stable for a given host.
    static func identifierSuffix(for service: HostServiceLink, in host: GlassShellHost) -> String {
        let sameKind = host.services.filter { $0.kind == service.kind }
        guard let index = sameKind.firstIndex(where: { $0.endpointID == service.endpointID }),
              index > 0 else { return "" }
        return "-\(index + 1)"
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

/// A split control, never a word: the play glyph opens **every** service on the host, and the
/// chevron beside it opens one. The chevron is its own hit region on every platform, because a
/// press-and-hold menu is not discoverable and cannot be pinched on visionOS. A host with a
/// single service is a plain play button with no chevron.
public struct GlassShellConnectControl: View {
    private let model: GlassShellModel
    private let hostID: HostID
    private let prominent: Bool
    /// Smaller metrics for narrow rows, such as the spatial sidebar.
    private let compact: Bool

    public init(model: GlassShellModel, hostID: HostID, prominent: Bool = false, compact: Bool = false) {
        self.model = model
        self.hostID = hostID
        self.prominent = prominent
        self.compact = compact
    }

    private var services: [HostServiceLink] { model.services(for: hostID) }
    /// Whether "connect the machine" means anything for this host. See
    /// `GlassShellModel.connectAll(hostID:)` — on the device itself it does not, so the play
    /// half of the split control is not drawn at all rather than drawn and refused.
    private var allowsConnectAll: Bool { model.host(hostID)?.allowsConnectAll ?? true }

    public var body: some View {
        if services.isEmpty {
            EmptyView()
        } else if services.count == 1 {
            // One service, so "all of them" and "this one" are the same act; the local host
            // connects it by name because `connectAll` refuses there on principle.
            Button("Connect", systemImage: "play.fill") {
                if allowsConnectAll { model.connectAll(hostID: hostID) }
                else if let only = services.first { model.connect(hostID: hostID, endpointID: only.endpointID) }
            }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderedProminent)
                .controlSize(prominent ? .large : .small)
                .fixedSize()
                .accessibilityLabel("Connect")
                .accessibilityIdentifier("host-connect")
        } else if allowsConnectAll {
            splitControl
        } else {
            pickerOnlyControl
        }
    }

    /// SwiftUI has no native split button (`Menu(primaryAction:)` only opens its menu on a long
    /// press off macOS), so the two halves are drawn in one accent capsule with a hairline
    /// between them — the platform's own split-button idiom.
    private var splitControl: some View {
        HStack(spacing: 0) {
            Button { model.connectAll(hostID: hostID) } label: {
                Image(systemName: "play.fill")
                    .padding(.horizontal, metrics.playPadding)
                    .padding(.vertical, metrics.verticalPadding)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Connect all services")
            .accessibilityIdentifier("host-connect")

            Rectangle()
                .fill(.white.opacity(0.35))
                .frame(width: 1)
                .accessibilityHidden(true)

            Menu { serviceButtons } label: {
                Image(systemName: "chevron.down")
                    .padding(.horizontal, metrics.chevronPadding)
                    .padding(.vertical, metrics.verticalPadding)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Choose a service")
            .accessibilityIdentifier("host-connect-menu")
        }
        .font(metrics.font)
        .fixedSize()
        .foregroundStyle(.white)
        .background(Color.accentColor, in: Capsule())
        .accessibilityElement(children: .contain)
    }

    /// The same capsule with the play half removed: one control that opens the service menu.
    /// Used on the device's own host, where the services are unrelated local things picked by
    /// name — a shell, a SQLite file, a MySQL instance — and never a machine entered as a whole.
    private var pickerOnlyControl: some View {
        Menu { serviceButtons } label: {
            HStack(spacing: 4) {
                Image(systemName: "play.fill")
                Image(systemName: "chevron.down").font(metrics.font.weight(.semibold))
            }
            .padding(.horizontal, metrics.playPadding)
            .padding(.vertical, metrics.verticalPadding)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .font(metrics.font)
        .foregroundStyle(.white)
        .background(Color.accentColor, in: Capsule())
        .accessibilityLabel("Choose a service")
        .accessibilityIdentifier("host-connect-menu")
    }

    private var metrics: Metrics {
        if prominent { return Metrics(playPadding: 16, chevronPadding: 11, verticalPadding: 9, font: .body) }
        if compact { return Metrics(playPadding: 9, chevronPadding: 6, verticalPadding: 4, font: .caption) }
        return Metrics(playPadding: 11, chevronPadding: 8, verticalPadding: 5, font: .callout)
    }

    private struct Metrics {
        let playPadding: CGFloat
        let chevronPadding: CGFloat
        let verticalPadding: CGFloat
        let font: Font
    }

    @ViewBuilder private var serviceButtons: some View {
        let host = model.host(hostID)
        ForEach(services) { service in
            Button {
                model.connect(hostID: hostID, endpointID: service.endpointID)
            } label: {
                Label {
                    Text(service.displayName)
                } icon: {
                    GlassServiceIcon(GlassServicePresentation.symbol(for: service.kind))
                }
            }
            .accessibilityIdentifier("host-connect-menu-\(service.kind.rawValue)"
                                     + (host.map { GlassShellLibraryView.identifierSuffix(for: service, in: $0) } ?? ""))
        }
    }
}
