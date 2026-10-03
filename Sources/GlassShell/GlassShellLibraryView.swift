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
    /// Set only when the sheet was opened by an import; cleared implicitly by the next open.
    @State private var setupPrefill: GlassShellSetupPrefill?
    @State private var deleting: GlassShellHost?
    #if os(visionOS)
    @Environment(\.openWindow) private var openSettingsWindow
    #endif
    @State private var showSettings = false
    /// The ⚡'s request, handed to the library as a binding it clears once the panel is open.
    @State private var panelRequest: String?
    /// D41: service availability dots, off unless chosen in Settings ▸ General.
    @AppStorage(GlassAvailabilityMonitor.settingKey) private var showsAvailability = false
    @State private var availabilityMonitor = GlassAvailabilityMonitor()
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
                    if let id, let host = model.host(id) {
                        detail(host)
                    } else if model.hosts.isEmpty {
                        emptyDetail
                    } else {
                        // D41: the library at a glance, and how this device has used it.
                        GlassLibraryOverview(statistics: .make(hosts: model.hosts, isFavorite: { model.isFavorite($0) },
                                                               history: model.connectionHistory)) { selection = $0 }
                    }
                }
                // Fills the column so the layered surface behind it does too. **No opaque
                // background of its own**: painting one here was an attempt to hide the seams by
                // covering the glass, which cost the panel the opacity and frost settings and left
                // the empty state as a white card floating on the wallpaper. The seams were never
                // a missing background — they were the *presence* of opaque children over a
                // translucent window. With the list and form no longer painting, there is one
                // surface and nothing to seam.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } toolbarActions: {
                HStack {
                    // The ⚡, here too: every top toolbar in the app has it, and in the library it
                    // simply opens Active.
                    GlassActiveConnectionsButton { model.showActiveConnections() }
                    ForEach(model.registry.registered, id: \.kind) { capability in
                        capability.libraryToolbarItems()
                    }
                    // On the Mac "Add Host" belongs to the sidebar column (left of the sidebar
                    // toggle); compact stacks and the visionOS tab bar have no sidebar region.
                    #if !os(macOS)
                    addHostButton
                    Button("Settings", systemImage: "gearshape") {
                        // The headset's Settings is its own window, where its icon tabs are the
                        // leading ornament; in a sheet that ornament was lost (2026-09-11). The
                        // database workspace already opened this window.
                        #if os(visionOS)
                        openSettingsWindow(id: "settings")
                        #else
                        showSettings = true
                        #endif
                    }
                        .accessibilityIdentifier("connection-library-settings")
                    #endif
                }
            } presentationAnchor: {
                alertAnchor
            }
            // The shell's own panels lead, then each capability's. Keys are the shell's because a
            // key crosses capabilities: it can sign in to a terminal on one machine and a database
            // on another, and only something that sees the whole library can say what deleting one
            // would unassign (D26 stage 4).
            // Active first: it sits inside the Library section, after the three categories.
            .libraryPanels([model.activeConnectionsPanel()] + model.libraryPanels() + model.registry.libraryPanels)
            .panelToOpen($panelRequest)
            // Right-click, long-press or pinch-and-hold anywhere in the list — including the empty
            // space below the machines, which is where you are looking when what you want is a new
            // one. The same button the toolbar's + is.
            .listActions { addHostButton }
            // Pull down to sync. `load()` is the whole cycle — read the catalog, pull the account,
            // merge, publish what this device has that the account does not — so the gesture asks
            // for exactly what a launch asks for, at the moment the user wants it rather than the
            // moment a push happens to arrive.
            .refreshAction { await model.load() }
            // The library's iCloud state, pinned to the foot of the sidebar where Apple's own
            // apps keep theirs (2026-09-27, the owner: "sync status locked here in footer").
            .sidebarFooter { GlassICloudStatusFooter(model: model) }
            #if os(macOS)
            .sidebarActions { addHostButton }
            #endif
        }
        // A capability asking to be sent back to the machine it belongs to. Selecting the host
        // is all it takes: on a compact width the library pushes the detail for a selection
        // change on its own, and on a Mac the detail column is already showing.
        .onChange(of: model.hostToShow) { _, wanted in
            guard let wanted else { return }
            scope = .allConnections
            selection = wanted
            model.hostToShow = nil
        }
        // The ⚡ from anywhere in the app: the model says which panel, the library opens it.
        // Probed only while the library is on screen (the task ends with the view), at most once
        // a minute, and only when the owner has turned the dots on.
        .task(id: showsAvailability) {
            guard showsAvailability else { return }
            while !Task.isCancelled {
                await availabilityMonitor.refresh(model.availabilityTargets())
                try? await Task.sleep(for: .seconds(GlassAvailabilityMonitor.interval))
            }
        }
        // `initial`: a bolt that brought the window back from closed asked before this view
        // existed, and a plain onChange never sees a value that was already there.
        .onChange(of: model.panelToShow, initial: true) { _, wanted in
            guard let wanted else { return }
            panelRequest = wanted
            model.panelToShow = nil
        }
        // One sheet for Add Host, Add a service, Edit service and Edit Host (rule 15) — and for
        // importing a machine from another tool, which is an Add Host with the fields filled in.
        .sheet(item: $setupMode) { mode in
            GlassShellHostSetupSheet(model: model, mode: mode, prefill: setupPrefill) { selection = $0 }
        }
        .onChange(of: model.pendingSetupPrefill?.id) { _, _ in
            guard let prefill = model.pendingSetupPrefill else { return }
            setupPrefill = prefill
            setupMode = .addHost
            // Cleared now, not on dismiss: the sheet has its own copy, and leaving it set would
            // re-present on the next redraw.
            model.clearPendingSetup()
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
        // ⌘N in the library means a new machine.
        .focusedSceneValue(\.glassNewItem, GlassNewItemAction(title: "New Host") { setupMode = .addHost })
        .task { if !model.isLoaded { await model.load() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.load() } } }
        #if os(macOS)
        // glas.sh's Connections window minimum; with the scene's default size this keeps the
        // detail's controls inside the window instead of below its bottom edge.
        .frame(minWidth: 900, minHeight: 560)
        #endif
    }

    private var addHostButton: some View {
        // ⌘N is not bound here. The library publishes `\.glassNewItem`, so while this window is
        // focused the shell's one File ▸ New item *is* "New Host" and carries the key. A second
        // ⌘N on the button would make which one fires depend on where the focus happens to be
        // inside the window.
        Button("Add Host", systemImage: "plus") { setupMode = .addHost }
            .accessibilityIdentifier("connection-library-add-host")
    }

    // MARK: Row

    /// The row is the host's name and its service icons: no subtitle naming or counting the
    /// services the icons already show, and no "last connected" (that lives in the detail's Host
    /// section). Removed family-wide 2026-09-11 at the user's direction.
    private func row(_ item: GlassLibraryItem<HostID>) -> some View {
        GlassLibraryConnectionRow(name: item.name, isFavorite: item.isFavorite,
                                  nameAccessibilityIdentifier: "host-row-\(item.name)") {
            // The machine's service kinds belong to the machine, so they sit under its name at the
            // same leading edge rather than beside the control that acts on it. In the trailing
            // accessory they competed with Connect for the row's width and made the name truncate
            // first — worst in the spatial sidebar, which is why that column had been shrinking its
            // own controls to cope.
            serviceIcons(for: item.id)
        } accessory: {
            #if os(visionOS)
            // No hover on the whole capsule: each half has its own (`splitControl`), inside the
            // list row's one shape.
            GlassShellConnectControl(model: model, hostID: item.id, compact: true)
                .fixedSize(horizontal: true, vertical: false)
            #else
            GlassShellConnectControl(model: model, hostID: item.id)
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
        let connected = model.connectedEndpoints()
        let services = model.host(id)?.services ?? []
        return HStack(spacing: 4) {
            ForEach(model.serviceKinds(for: id), id: \.self) { kind in
                let isConnected = services.contains { $0.kind == kind && connected.contains($0.endpointID) }
                let availability = showsAvailability ? availability(of: kind, on: id) : nil
                GlassServiceIcon(GlassServicePresentation.symbol(for: kind))
                    .foregroundStyle(.secondary)
                    .overlay(alignment: .bottomTrailing) {
                        GlassServiceStatusDot(isConnected: isConnected, availability: availability)
                    }
                    .accessibilityLabel(GlassServicePresentation.displayName(for: kind))
                    .accessibilityValue(GlassServiceStatusDot.description(isConnected: isConnected, availability: availability))
                    .accessibilityIdentifier("host-service-\(kind.rawValue)")
            }
        }
    }

    /// The worst state among the host's services of `kind`; nil until one has been probed.
    private func availability(of kind: HostServiceKind, on id: HostID) -> GlassServiceAvailability? {
        let services = model.host(id)?.services.filter { $0.kind == kind } ?? []
        return GlassServiceAvailability.worst(services.compactMap { availabilityMonitor.states[$0.endpointID] })
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
                #if os(visionOS)
                // The one control on an otherwise empty pane, and the first thing a new user is
                // asked to do. `ContentUnavailableView`'s default button is sized for a list on a
                // Mac; here it is the whole point of the screen.
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
                #endif
        }
        #if os(visionOS)
        // Given the pane rather than floating in the middle of it, and set at reading distance.
        // The default composes a compact card, which on a Mac sits neatly inside a detail column
        // and in a headset reads as a small object adrift in a large empty rectangle.
        .font(.title3)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
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
                    Text("Services here run on this machine: they reach it at \(GlassLocalHost.address), or open a file you choose. Nothing about this host is shared with your other devices.")
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
            // Edit alone. Connect lived here too, which made three ways to start the same session
            // from one screen — the row's own split control, the Connect beside each service in
            // the Services section above, and this. The service rows are the precise ones: they
            // say *which* service they open. Removing a machine stays deliberate, in the row's
            // context menu and at the bottom of the edit sheet (2026-09-11).
            Button("Edit") { setupMode = .editHost(host) }
                .accessibilityIdentifier("host-edit")
                .buttonStyle(.bordered)
                .controlSize(.large)
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
    /// Whether this link has no capability record behind it. Built-in local services have nothing
    /// stored by design (D8) and are never "unconfigured".
    private func isUnconfigured(_ service: HostServiceLink, host: GlassShellHost) -> Bool {
        !host.isBuiltIn(service.endpointID) && model.configuration(for: service.endpointID) == nil
    }

    private func subtitle(for service: HostServiceLink, isBuiltIn: Bool) -> String {
        let kind = GlassServicePresentation.displayName(for: service.kind)
        if isBuiltIn { return "\(kind) · Built in" }
        if model.configuration(for: service.endpointID) == nil { return "\(kind) · Not set up" }
        return kind
    }

    private func serviceRow(_ service: HostServiceLink, host: GlassShellHost) -> some View {
        let suffix = Self.identifierSuffix(for: service, in: host)
        let isBuiltIn = host.isBuiltIn(service.endpointID)
        let isConnected = model.connectedEndpoints().contains(service.endpointID)
        let availability = showsAvailability ? availabilityMonitor.states[service.endpointID] : nil
        let identity = HStack(spacing: 10) {
            GlassServiceIcon(GlassServicePresentation.symbol(for: service.kind))
                .foregroundStyle(.secondary)
                .overlay(alignment: .bottomTrailing) {
                    GlassServiceStatusDot(isConnected: isConnected, availability: availability)
                }
                .accessibilityValue(GlassServiceStatusDot.description(isConnected: isConnected, availability: availability))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(service.displayName).lineLimit(1).truncationMode(.tail)
                // **A link with nothing behind it says so here.** Until now the only way to find
                // out was to press Connect and be told "has no saved configuration" — which is how
                // a machine ends up with two Terminals that look identical, one of them dead: the
                // 2026-09-16 persistence defect emptied configurations without removing their
                // links, and re-adding the service created a second link beside the corpse.
                Text(subtitle(for: service, isBuiltIn: isBuiltIn))
                    .font(.footnote)
                    .foregroundStyle(isUnconfigured(service, host: host) ? .orange : .secondary)
                    .lineLimit(1)
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
                // Said as it is: the services' settings and saved passwords go too, everywhere the
                // library syncs. The old text said credentials were not touched.
                Text(GlassShellHost.deletionConsequence(host))
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
            #if os(visionOS)
            .hoverEffect(.highlight)
            #endif
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
            }
            // A menu does not inherit `foregroundStyle` the way a button does, and setting it on
            // the label content does not win either — the menu style is applied afterwards. The
            // button style is the hook that is not overridden, so the family shares one.
            .glassMenuOnFilled()
            .menuIndicator(.hidden)
            .fixedSize()
            #if os(visionOS)
            .hoverEffect(.highlight)
            #endif
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
        }
        .glassMenuOnFilled()
        .menuIndicator(.hidden)
        .fixedSize()
        .font(metrics.font)
        .background(Color.accentColor, in: Capsule())
        .accessibilityLabel("Choose a service")
        .accessibilityIdentifier("host-connect-menu")
    }

    private var metrics: Metrics {
        #if os(visionOS)
        // A control that is aimed with the eyes cannot be sized for a cursor. `compact` exists so a
        // narrow sidebar does not wrap, and on the Mac `.caption` at 4 pt of padding is a perfectly
        // reasonable answer to that — in a headset it is a target smaller than the eye can settle
        // on, which is why the row's Connect button read as a speck. The spatial sidebar is given
        // the width to carry these instead (`GlassConnectionLibrary.visionNavigation`).
        if prominent { return Metrics(playPadding: 20, chevronPadding: 14, verticalPadding: 12, font: .body) }
        if compact { return Metrics(playPadding: 12, chevronPadding: 9, verticalPadding: 6, font: .body) }
        return Metrics(playPadding: 16, chevronPadding: 12, verticalPadding: 10, font: .body)
        #else
        if prominent { return Metrics(playPadding: 16, chevronPadding: 11, verticalPadding: 9, font: .body) }
        if compact { return Metrics(playPadding: 9, chevronPadding: 6, verticalPadding: 4, font: .caption) }
        return Metrics(playPadding: 11, chevronPadding: 8, verticalPadding: 5, font: .callout)
        #endif
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
