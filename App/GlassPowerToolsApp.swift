//
//  GlassPowerToolsApp.swift
//  Glass Power Tools
//
//  Composition root. One GlassLayerStore and one GlassShellModel for the process; the library
//  window and the settings surface are the only scenes in Stage 1. Capabilities register with
//  `model.registry` and declare their own window scenes in later stages.
//

import SwiftUI
import GlassShell
import GlassLayers
import GlassConnectionKit
import GlassConnectionUI
import GlassTerminal
import GlassDatabase
import GlassDesktop
import VNCKit
import GlassEditor
import GlassEditorCore
import GlassWidgetData

/// The app; on a Mac, also the background process that keeps local terminals running
/// (`MacTmuxHost`), which must start nothing of the app's, so it is chosen before SwiftUI is.
@main
enum GlassPowerToolsMain {
    static func main() {
        #if os(macOS)
        MacTmuxHost.runIfAsked()
        #endif
        GlassPowerToolsApp.main()
    }
}

struct GlassPowerToolsApp: App {
    @State private var layers: GlassLayerStore
    @State private var model: GlassShellModel
    @State private var terminal: GlassTerminalRuntime
    @State private var database: GlassDatabaseRuntime
    @State private var desktop: GlassDesktopRuntime
    @State private var windowRecovery: GlassWindowRecoveryManager
    @State private var editor: GlassEditorRuntime
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacTerminalAppDelegate.self) private var appDelegate
    #else
    // iOS and visionOS have no delegate of their own, so this is the one place silent pushes can
    // be received. macOS routes the same three calls through MacTerminalAppDelegate, which already
    // exists and which the platform will not let us add a second of.
    @UIApplicationDelegateAdaptor(GlassPushDelegate.self) private var pushDelegate
    #endif

    init() {
        // Appearance in the run's own suite while a UI test drives the app, as every other store
        // is, with nothing migrated into it from the person's legacy suites (W35, 2026-10-11).
        let layers = GlassUITestRun.defaults.map { GlassLayerStore(defaults: $0, legacyDefaults: []) } ?? GlassLayerStore()
        // Screen sharing's events also go to a small file in the app's storage, which can be copied
        // off a headset with devicectl when a session goes wrong (VNCDiagnostics). Not in UI tests.
        if GlassUITestRun.defaults == nil {
            VNCDiagnostics.enable()
            #if os(visionOS)
            // And a terminal's holds and pinches, in the same file (places only, never text).
            glassTerminalRecordSelection { VNCDiagnostics.record(category: "terminal-selection", $0) }
            #endif
            // Whether this device decodes a Mac's High Performance picture, found once in the
            // background and written to that file: a 3 KB sample, a few milliseconds.
            Task.detached(priority: .background) { _ = RFBAppleVideoDecoder.decodesHighPerformance }
        }
        var isolatedDirectory: URL?
        #if DEBUG || GLASS_STRESS_HARNESS
        // `--ui-testing <uuid>` isolates storage and the catalog under a per-run directory so UI
        // tests never touch the real App Group container. Same convention as glassDT.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--ui-testing"), arguments.indices.contains(index + 1),
           let identifier = UUID(uuidString: arguments[index + 1]) {
            let testsRoot = URL.applicationSupportDirectory.appendingPathComponent("GlassPowerTools-Tests", isDirectory: true)
            isolatedDirectory = testsRoot.appendingPathComponent(identifier.uuidString, isDirectory: true)
            Self.pruneStaleTestDirectories(in: testsRoot, keeping: identifier.uuidString)
        }
        #endif
        let configuredGroup = Bundle.main.object(forInfoDictionaryKey: "GlasKeychainAccessGroup") as? String
        let accessGroup = configuredGroup.flatMap { $0.contains("$(") || $0.isEmpty ? nil : $0 }
        let model = GlassShellModel(
            storageDirectory: isolatedDirectory,
            sharedContainerURL: isolatedDirectory,
            resolveSharedContainer: isolatedDirectory == nil,
            accessGroup: isolatedDirectory == nil ? accessGroup : nil,
            layers: layers
        )
        // Stage 3.5 (D19): the host library reaches the user's other devices.
        //
        // Attached here rather than constructed inside the model on purpose — the shell must not
        // require CloudKit to exist, and a UI test running against an isolated directory has no
        // business talking to the user's iCloud account. `isolatedDirectory` is exactly the "this
        // is a test run" signal, so the backend is supplied only for the real app.
        if isolatedDirectory == nil {
            model.enableCatalogSync(GlassCloudKitCatalogBackend())
        }
        #if os(macOS)
        // The Command Palette's connections: every service in the library, desktops among them.
        model.registerPaletteConnections()
        #endif
        // All Windows off the Mac draws the library's open sessions (2026-10-14); on iPhone and
        // iPad a pull down on any top bar brings it.
        GlassShowAllWindows.model = model
        #if os(iOS)
        GlassShowAllWindows.installPullDown()
        #endif
        // Stage 2: the SSH capability. glas.sh's managers live for the process in the runtime; the
        // shell routes Connect for `.ssh` services through the capability.
        let windowRecovery = GlassWindowRecoveryManager()
        let terminal = GlassTerminalRuntime(layers: layers, windowRecovery: windowRecovery)
        // D27: Add Server and `ssh_config` import build a saved server directly rather than going
        // through the host sheet. Without this they produce a server with no host record and no
        // link — invisible in the library, and under D26 with nowhere to be stored at all. The
        // shell puts the machine in the library on the capability's behalf.
        // D26/D27 in one call: saved servers live on their service links from here on, and the
        // two paths that build a server directly ask the shell for a machine to hang it on.
        terminal.connectToLibrary(
            store: model,
            adopt: { [weak model] hostName, address, serviceName in
                guard let model else { throw GlassShellError.hostNotFound(HostID()) }
                return try await model.adoptService(kind: .ssh, hostName: hostName, address: address,
                                                    serviceName: serviceName).rawValue
            },
            // Link-only. The capability is the one deleting, so asking it to delete again through
            // `removeService` would call straight back into the delete that is running.
            discard: { [weak model] id in await model?.detachService(EndpointID(rawValue: id)) })
        let terminalCapability = GlassTerminalCapability(runtime: terminal)
        model.registry.register(terminalCapability)
        // D26 stage 4: the key manager is a library panel, and the terminal is what holds SSH key
        // material. The shell presents; the capability keeps the lifecycle it already owns.
        model.attachKeyStore(terminal.keyStore())
        // Stage 3: the database capability. Its managers live for the process in the runtime;
        // the shell routes Connect for `.database` services through the capability, and the
        // tunnel a service asks for is brokered back to whichever capability owns `.ssh` (D7).
        let database = GlassDatabaseRuntime(layers: layers)
        // The setup sheet settles a machine's SSH host-key trust through the shell's broker
        // (D14). Handed in here because the shell model owns the brokering and a capability
        // must not hold the model.
        database.hostAccess = { [weak model] host in
            model?.hostAccess(for: host.id) ?? GlassCapabilityHostAccess(address: host.address)
        }
        // A database added with a new machine has no host to ask about yet; it can still be
        // reached through another machine's Terminal service (2026-10-05).
        database.tunnelAccess = { [weak model] in
            model?.hostAccess(for: HostID()) ?? GlassCapabilityHostAccess(address: nil)
        }
        // Leaving a database goes back to **the machine it is on**, not to the top of the list.
        // The catalog is what turns a connection's endpoint into a host, and the database does
        // not hold the catalog — so the answer is supplied from here, like `hostAccess` above.
        database.showHostForConnection = { [weak model] connectionID in
            guard let model,
                  let host = model.host(owningEndpoint: EndpointID(rawValue: connectionID))
            else { return }
            model.showHost(host.id)
        }
        // D26: the database's saved connections live on their service links too.
        database.connectToLibrary(store: model)
        model.registry.register(GlassDatabaseCapability(runtime: database))
        // Stage 4: the remote desktop capability. It owns `.rdp` and serves both RDP and
        // VNC/Screen Sharing, because the protocol is a field on the saved desktop rather than a
        // service kind — glassDT's model, which is why the catalog needs no fourth kind.
        let desktop = GlassDesktopRuntime(layers: layers)
        // Desktop notices show as banners while the app is in front, as glassDT set at launch
        // (`glassDTApp.swift:10`). Here, in the app, not in the runtime: a test process has no
        // bundle, and the notification centre throws there.
        DesktopNotices.shared.configurePresentation()
        desktop.hostAccess = { [weak model] host in
            model?.hostAccess(for: host.id) ?? GlassCapabilityHostAccess(address: host.address)
        }
        // Importing a `.rdp` file opens the library's own host sheet, filled in. The capability
        // parses; the shell presents and saves, so an imported machine gets its host record and
        // service link from the ordinary setup flow rather than a second path (D27).
        desktop.requestSetup = { [weak model] prefill in
            model?.requestSetup(prefill: prefill)
        }
        // D26: and the desktop's, which is why `connections.json` no longer exists.
        let desktopRuntime = desktop
        Task { @MainActor in await desktopRuntime.connectToLibrary(store: model) }
        model.registry.register(GlassDesktopCapability(runtime: desktop))
        // Stage 5: the editor. Not a capability — a file is not a service on a machine — so it is
        // registered nowhere and simply owns its own window. What makes it part of the product is
        // that a project names a *host*, which is the catalog's identity (see `GlassEditorProject`).
        // Under `--ui-testing <uuid>` the editor keeps its projects and preferences in a suite of
        // its own, as the shell keeps its storage: the project seed replaces the list, and in the
        // standard suite that list is the real one, shared with the installed app.
        let editorDefaults = isolatedDirectory.flatMap {
            UserDefaults(suiteName: "com.glasspowertools.editor.uitests.\($0.lastPathComponent)")
        } ?? .standard
        let editor = GlassEditorRuntime(layers: layers, defaults: editorDefaults)
        // Its preferences still belong in the one settings surface, so the page is registered here
        // — the composition root is the only place that knows about both the shell and the editor.
        model.registry.registerSettingsPage(editor.settingsPage)
        // D1: and its open windows belong in the one session switcher, for the same reason and
        // through the same escape hatch. Read at draw time so the list follows the editor's state.
        model.registry.registerSessionProvider(id: "editor") { [editor] in editor.openSessions() }
        // Show All Windows lists every open window beside the terminal's (GlassShowAllWindows):
        // the composition root is the one place that holds every capability's sessions.
        GlassShowAllWindows.openSessions = { [model] in model.registry.openSessions() }
        // Stage C: Projects in the library, the same way. Answering "is that machine this one?"
        // needs the catalog, which the editor deliberately does not hold, so the answer is supplied
        // from here: the catalog's own local record (D8), or a saved machine whose Terminal service's
        // pinned host key is one of this Mac's own (B-X22) — a project on it is read from the disk,
        // not over SSH to itself. Keys are looked up only on a device that has host keys at all.
        let projectReach: @MainActor (GlassShellHost) -> GlassEditorProjectReach = { [terminal] host in
            let terminalServices = host.services.filter { (service: HostServiceLink) in service.kind == .ssh }
            let local = GlassMachineIdentity.localHostKeyFingerprints()
            var pinned: Set<String> = []
            #if os(macOS)
            if !host.isLocal, !local.isEmpty {
                for service in terminalServices {
                    pinned.formUnion(terminal.pinnedHostKeyFingerprints(serverID: service.endpointID.rawValue))
                }
            }
            #endif
            return GlassMachineIdentity.reach(
                hostName: host.displayName,
                isLocalHostRecord: host.isLocal,
                remoteFingerprints: pinned,
                hasTerminalService: !terminalServices.isEmpty,
                localFingerprints: local
            )
        }
        let projectsPanel = GlassEditorProjectsPanelModel()
        let library = model
        model.registry.registerLibraryPanel(
            editor.libraryPanel(panel: projectsPanel) { project in
                guard let hostID = project.hostID else { return .thisMachine }
                guard let host = library.host(hostID) else {
                    return .unreachable(host: project.displayName)
                }
                return projectReach(host)
            }
        )
        // Stage D: how the editor reads a folder on another machine. It borrows the capability
        // that owns SSH, exactly as the database borrows it for a tunnel — the editor makes no
        // connection, resolves no credential and judges no host key.
        let registry = model.registry
        editor.remoteAccess = { @MainActor hostID in
            guard let record = library.record(hostID) else { throw GlassEditorRemoteAccessError.machineNotInLibrary }
            guard record.services.contains(where: { $0.kind == .ssh }),
                  let capability = registry.capability(for: .ssh) else { throw GlassEditorRemoteAccessError.noTerminalService }
            let lister = try await capability.openDirectoryLister(host: record)
            return GlassEditorRemoteFileAccess { path in
                try await lister.list(path).map {
                    GlassEditorDirectoryEntry(name: $0.name, isDirectory: $0.isDirectory)
                }
            } read: { path in
                try await lister.read(path)
            } write: { data, path, expecting in
                let committed = try await lister.write(
                    data, to: path,
                    expecting: expecting.map {
                        GlassHostFileStamp(
                            size: $0.size,
                            modifiedAt: $0.modificationSeconds.map {
                                Date(timeIntervalSince1970: TimeInterval($0))
                            }
                        )
                    }
                )
                return committed.map {
                    RemoteStat(
                        size: $0.size,
                        modificationSeconds: $0.modifiedAt.map {
                            Int64($0.timeIntervalSince1970.rounded(.down))
                        }
                    )
                }
            } stat: { path in
                try await lister.stat(path).map {
                    RemoteStat(
                        size: $0.size,
                        modificationSeconds: $0.modifiedAt.map { Int64($0.timeIntervalSince1970.rounded(.down)) },
                        modificationNanoseconds: $0.modifiedAt.map {
                            let seconds = $0.timeIntervalSince1970
                            return Int64((seconds - seconds.rounded(.down)) * 1_000_000_000)
                        }
                    )
                }
            } onClose: {
                await lister.close()
            }
        }
        // "Open in Editor" on a folder in the Files browser — the other direction of the same
        // seam. The terminal knows the server the browser is connected through; the catalog turns
        // that into the machine's id, which is what makes the project the *same* project on
        // another device.
        let editorRuntime = editor
        // The Mac's Terminal Overview shows every open session, not only this window's tabs —
        // the user asked where the database was, standing in the overview. Read at draw time.
        terminal.openSessions = { [registry = model.registry] in registry.openSessions() }
        // "New Terminal on ▸ alpha", not "Terminal on alpha": the machine's name, from the catalog.
        terminal.hostName = { [weak model] serverID in model?.host(owningEndpoint: EndpointID(rawValue: serverID))?.displayName }
        // Open in SQL Editor (2026-10-20): the Database services of a terminal's machine, from the
        // catalog, and the databases reached through its server, which the database knows (D45).
        terminal.sqlDestinations = { [weak model] endpoint in
            let machine = model?.host(owningEndpoint: EndpointID(rawValue: endpoint))
            let databases = machine?.services.filter { $0.kind == .database }.map(\.endpointID.rawValue) ?? []
            return database.sqlDestinations(machineDatabases: databases, reachedThrough: endpoint)
                .map { GlassTerminalSQLDestination(id: $0.id, title: $0.title) }
        }
        // The SQL, unrun, in a new query tab; connected first as the library's Connect does, from a
        // Connections window, where the database asks for a password and says what failed.
        terminal.openSQL = { [weak model] sql, connection in
            #if os(macOS)
            if !GlassLibraryWindows.isOpen { GlassWindowOpener.shared.perform { $0.openConnections() } }
            #endif
            guard let model, let toConnect = database.openSQL(sql, connectionID: connection) else { return }
            let endpoint = EndpointID(rawValue: toConnect)
            if let host = model.host(owningEndpoint: endpoint) { model.connect(hostID: host.id, endpointID: endpoint) }
        }
        // The + menu's running terminals (2026-10-15): Active's list, and its refresh when old.
        terminal.runningSessions = { [weak model] in model?.runningSessions ?? [] }
        terminal.refreshRunningSessionsIfDue = { [weak model] in await model?.refreshRunningSessionsIfDue() }
        // The ⚡ in every toolbar means one thing — the library's Active panel — so all four
        // runtimes get the same closure.
        let showActive: GlassShowActiveConnections = { [weak model] in model?.showActiveConnections() }
        terminal.showActiveConnections = showActive
        database.showActiveConnections = showActive
        desktop.showActiveConnections = showActive
        editor.showActiveConnections = showActive
        // Workgroups is a panel in the library, not a window: its menu items open it there.
        terminal.showLibraryPanel = { [weak model] panelID in model?.showPanel(panelID) }
        terminal.openFolderAsProject = { @MainActor serverID, path in
            let host = library.host(owningEndpoint: EndpointID(rawValue: serverID))
            let project = GlassEditorProject(hostID: host?.id, path: path)
            // This Mac browsed over SSH opens from the disk too (B-X22).
            let reach: GlassEditorProjectReach = host.map { projectReach($0) } ?? .thisMachine
            // The returned id is a window that has to be *shown*; dropping it left the project
            // opened into a workspace nothing was displaying.
            if let windowID = editorRuntime.openProject(project, reach: reach) {
                editorRuntime.present(windowID)
            }
        }
        // Favorites beyond machines (2026-10-13): the editor's and the terminal's stars ask the
        // shell, and the shell asks here how a project, a workgroup or a folder is named and opened.
        terminal.favorites = model.favoritesAccess
        editor.favorites = model.favoritesAccess
        model.describeFavorite = { [weak model] item in
            guard let model else { return nil }
            switch item {
            case .service:
                return nil   // The shell's own.
            case .project(let id):
                guard let project = editorRuntime.projects.projects.first(where: { $0.id == id }) else { return nil }
                let reach: GlassEditorProjectReach
                if let hostID = project.hostID {
                    guard let host = model.host(hostID) else { return nil }
                    reach = projectReach(host)
                } else {
                    reach = .thisMachine
                }
                return GlassFavoriteDescription(
                    title: project.displayName,
                    subtitle: "\(project.path) · \(reach.badge)",
                    symbol: .system("chevron.left.forwardslash.chevron.right"),
                    open: { editorRuntime.present(editorRuntime.openProject(project, reach: reach)) })
            case .workgroup(let id):
                guard let workgroup = terminal.workgroups.first(where: { $0.id == id }) else { return nil }
                return GlassFavoriteDescription(
                    title: workgroup.name,
                    subtitle: workgroup.terminals == 1 ? "1 terminal" : "\(workgroup.terminals) terminals",
                    symbol: .system("rectangle.3.group"),
                    open: { terminal.requestOpenWorkgroup(id) })
            case .folder(let endpoint, let path):
                guard let host = model.host(owningEndpoint: endpoint),
                      host.services.contains(where: { $0.endpointID == endpoint && $0.kind == .ssh }) else { return nil }
                let name = path == "/" ? "/" : (path as NSString).lastPathComponent
                return GlassFavoriteDescription(
                    title: name,
                    subtitle: "\(path) on \(host.displayName)",
                    symbol: .system("folder"),
                    open: { terminal.requestFiles(serverID: endpoint.rawValue, at: path) },
                    actions: [
                        .init(title: "Open as Project", symbolName: "chevron.left.forwardslash.chevron.right") {
                            terminal.openFolderAsProject?(endpoint.rawValue, path)
                        },
                    ])
            }
        }
        // Open in Editor on a path a terminal on this Mac shows (2026-10-14): a file as a tab, a
        // folder as a project, as the Finder's Open in Editor.
        terminal.openLocalInEditor = { urls in
            GlassWindowOpener.shared.perform { editor.show(editor.open(urls: urls), with: $0) }
        }
        #if os(macOS)
        // A path a Mac terminal printed, previewed over it as the editor previews files (2026-10-16).
        terminal.filePreview = { url in AnyView(GlassEditorQuickPreview(url: url)) }
        #endif
        // "Edit" on a file in the Files browser opens it in the editor, as a tab, and saves back
        // over the same connection through the verified commit.
        terminal.openFileInEditor = { @MainActor serverID, path in
            guard let host = library.host(owningEndpoint: EndpointID(rawValue: serverID)) else { return }
            if let windowID = editorRuntime.open(path: path, on: host.id,
                                                 machine: host.displayName) {
                editorRuntime.present(windowID)
            }
        }
        // And the same file as a *view*, for a phone: the browser presents the editor itself so
        // that presenting it does not dismiss the browser and close the session underneath.
        terminal.editorFileScreen = { @MainActor serverID, path, onDone in
            guard let host = library.host(owningEndpoint: EndpointID(rawValue: serverID)) else {
                return nil
            }
            return AnyView(
                GlassEditorRemoteFileScreen(runtime: editorRuntime, hostID: host.id,
                                            machine: host.displayName, path: path, onDone: onDone)
            )
        }
        // The project list travels with everything else. Attached rather than required: without an
        // account the list is a local one and nothing else changes.
        // Never from a test run: its seeded list would replace the person's on every device.
        let projects = editor.projects
        if isolatedDirectory == nil {
            Task { @MainActor in
                await projects.startSynchronizing(
                    with: GlassSettingsSyncService(projectStore: GlassUbiquitousSettingsStore())
                )
            }
            // Favourites too (2026-10-08), the same way and for the same reasons.
            Task { @MainActor in
                await model.startSynchronizingFavorites(
                    with: GlassSettingsSyncService(favoritesStore: GlassUbiquitousSettingsStore())
                )
            }
            // And the rest of Favorites (2026-10-13), under a key of its own.
            Task { @MainActor in
                await model.startSynchronizingFavoriteItems(
                    with: GlassSettingsSyncService(favoriteItemsStore: GlassUbiquitousSettingsStore())
                )
            }
            // Each device's connections, counted per day, for Your Library's overview (D81).
            Task { @MainActor in
                await model.startSynchronizingUsage(
                    with: GlassSettingsSyncService(usageStore: GlassUbiquitousSettingsStore())
                )
            }
        }
        _layers = State(initialValue: layers)
        _model = State(initialValue: model)
        _terminal = State(initialValue: terminal)
        _database = State(initialValue: database)
        _desktop = State(initialValue: desktop)
        _windowRecovery = State(initialValue: windowRecovery)
        _editor = State(initialValue: editor)
        // The Machines and Active widgets: their snapshot kept current, and their taps carried
        // out — one that launched the app included (`GlassWidgetBridge`). Not in a UI-test run,
        // which must not change what the person's widgets show.
        #if os(macOS)
        // Open With, a drop on the Dock icon, an `ssh://` link: a file into the editor, a folder to a
        // terminal there, a `.command` run in one, a link connected — without a Connections window
        // coming up too (the owner, 2026-10-13).
        MacTerminalAppDelegate.openURLs = { urls in
            for url in urls {
                guard let request = GlassWidgetRequest.forOpened(url, isMac: true) else { continue }
                if GlassUITestRun.defaults == nil {
                    GlassWidgetRequests.shared.post(request)
                } else if case .openInEditor(let files) = request, let windowID = editor.open(files[0]) {
                    // A UI-test run carries no bridge: its files still open as before.
                    editor.present(windowID)
                }
            }
        }
        // A quit asks first when the editor has unsaved changes, and Cancel goes to them.
        MacTerminalAppDelegate.unsavedDocumentNames = { editor.unsavedDocumentNames }
        MacTerminalAppDelegate.showUnsavedDocuments = { editor.presentFirstUnsaved() }
        // Handoff: a terminal, database or desktop continued from another device (D72).
        MacTerminalAppDelegate.continueActivity = { activity in
            guard let endpoint = GlassHandoff.endpoint(from: activity) else { return false }
            GlassWidgetRequests.shared.post(.continueSession(endpoint: endpoint, tmux: GlassHandoff.tmuxSession(from: activity)))
            return true
        }
        if GlassUITestRun.defaults == nil {
            // Finder ▸ Services: New Glass Power Tools Tab Here, Window Here, Open in (D72).
            MacTerminalAppDelegate.servicesProvider = GlassFinderServices()
            // The Dock icon's menu: New Terminal Window and your machines.
            MacTerminalAppDelegate.dockMenu = { GlassDockMenu.make() }
        }
        #endif
        // The database's saved queries as Shortcuts, Siri and the Command Palette name them: with
        // their database as the library names it, so two "Orders" queries differ. Never their SQL.
        let savedQueries: @MainActor () -> [GlassWidgetSnapshot.SavedQuery] = { [weak model] in
            guard let model else { return [] }
            return database.savedQueryEntries.compactMap { entry in
                let endpoint = EndpointID(rawValue: entry.connectionID)
                guard let host = model.host(owningEndpoint: endpoint),
                      let service = host.services.first(where: { $0.endpointID == endpoint }) else { return nil }
                return GlassWidgetSnapshot.SavedQuery(id: entry.id, name: entry.name,
                                                      database: "\(service.displayName) on \(host.displayName)")
            }
        }
        #if os(macOS)
        // The Command Palette's places (2026-10-14): projects, Favorites' folders, saved queries and
        // sessions running with no window here.
        model.registerPalettePlaces(projects: { editorRuntime.projects.projects.map(\.id) },
                                    savedQueries: savedQueries)
        #endif
        if GlassUITestRun.defaults == nil {
            // And every other intent's request — Shortcuts, Siri, Spotlight (D72) — carried out
            // with the capabilities that do each.
            GlassWidgetBridge.start(model: model, actions: GlassWidgetBridge.Actions(
                openWorkgroup: { terminal.requestOpenWorkgroup($0) },
                newLocalTerminal: { folder, openWindow in
                    #if os(macOS)
                    terminal.openLocalTerminal(in: folder, with: openWindow)
                    #endif
                },
                newLocalTerminalTab: { folder, openWindow in
                    #if os(macOS)
                    terminal.openLocalTerminalTab(in: folder, with: openWindow)
                    #endif
                },
                runInTerminal: { script, openWindow in
                    #if os(macOS)
                    terminal.runInTerminal(script, with: openWindow)
                    #endif
                },
                openInEditor: { urls, openWindow in
                    editor.show(editor.open(urls: urls), with: openWindow)
                },
                openSSHLink: { terminal.requestOpen(sshLink: $0) },
                sendFiles: { files, machine, folder in
                    guard let host = model.host(HostID(rawValue: machine)), let member = model.sshMember(of: host) else {
                        throw GlassWidgetBridge.SendError.notInLibrary
                    }
                    return try await terminalCapability.sendFiles(files, toHost: member, folder: folder).summary
                },
                continueTerminal: { server, tmux in terminal.requestContinue(serverID: server, tmuxSession: tmux) },
                attachLocalTerminal: { name, openWindow in
                    #if os(macOS)
                    terminal.openLocalTerminal(tmuxSession: name, with: openWindow)
                    #endif
                },
                workgroups: {
                    terminal.workgroups.map { GlassWidgetSnapshot.Workgroup(id: $0.id, name: $0.name, terminals: $0.terminals) }
                },
                savedQueries: savedQueries,
                openSavedQuery: { database.openSavedQuery($0) }))
        }
        #if os(macOS)
        // D38: Sparkle's scheduled checks, in a build that names a feed and a signing key — and
        // never in a UI-test run.
        if isolatedDirectory == nil { GlassShellUpdates.shared.start() }
        #endif
    }

    /// The library window. On macOS it carries glas.sh's Connections window sizing
    /// (`../glas.sh/glas.sh/glas_shApp.swift:99-113`): without a default size the window opened
    /// at the sidebar's ideal height and clipped the detail.
    private var mainScene: some Scene {
        #if os(visionOS)
        // **One Connections window on the headset** (owner, 2026-09-29). A plain window group made
        // a new one for every bolt and every "show Connections". A window group keyed by one fixed
        // value keeps it to one — opening a value already shown brings that window forward — so
        // everything asks for it with `openWindow.openConnections()`, which names that value.
        // `openWindow(id: "main")` names none, and SwiftUI answers that from `defaultValue` as a
        // new window: a second Connections window on visionOS 27 (W29b).
        //
        // Not a `Window` scene (2026-10-07): after a crash visionOS handed the app two saved
        // sessions for it, and SwiftUI stops the app on the second — "Your app was given a scene
        // with id 'main' but the matching Window in your app body is already connected" — on
        // every launch, a reinstall included, until the saved sessions were gone.
        return WindowGroup("Connections", id: "main", for: GlassConnectionsWindow.self) { _ in
            mainContent
        } defaultValue: {
            GlassConnectionsWindow()
        }
        // **Plain, so Glass can clear it** (W33; the owner, 2026-10-10: "Yes, all four"). The
        // system's window keeps its glass behind a focused window whatever the app draws, as the
        // terminal found (D59). The library draws Apple's glass itself at Glass, in Apple's
        // corner, with Opacity's paint over it (`GlassShellLibraryView`), and lays its columns
        // out itself (`GlassSpatialSplitView`).
        .windowStyle(.plain)
        // **Its size follows its content** (W39): the library takes any size, as before (its
        // scene's limits read 0 to unbounded), and the window as its orb is exactly the orb's,
        // 320 × 184, so idle it can become its own orb rather than push a second window over
        // itself (`glassConnectionsIdleShrink`).
        .windowResizability(.contentSize)
        // **The Mac's width, 1180 × 700** (the owner, on the headset, 2026-10-14: "it should be
        // wider by default"). W29 had made it 960, a 600-point detail beside the list; the
        // system's 1280 × 720 was "pretty large" (2026-10-10). It is the size a new window opens
        // at; the window can still be resized, and comes back from its orb at whatever size it had.
        .defaultSize(width: GlassConnectionsWindowSize.width, height: GlassConnectionsWindowSize.height)
        #else
        let group = WindowGroup("Connections", id: "main") { mainContent }
        #if os(macOS)
        return group
            .defaultSize(width: 1180, height: 720)
            .windowResizability(.contentMinSize)
            // File ▸ New, owned once by the shell and aimed by whichever window is focused: a SQL
            // document in a database workspace, a terminal window in a terminal workspace, a host
            // here. Attached to this scene because the shell has no scene of its own, and because
            // exactly one scope may replace a command placement — two replacements are not merged,
            // they silently delete each other (see `GlassShellFileCommands`).
            .commands {
                GlassShellFileCommands()
                // Edit ▸ Find, the same way: the shell owns ⌘F, ⌘G and ⇧⌘G, the focused window aims them.
                GlassShellFindCommands()
                // Command Palette… (⇧⌘P), once: every capability's entries and the focused window's.
                GlassShellPaletteCommands()
                // D38: Check for Updates…, for the build distributed outside the App Store.
                GlassShellUpdateCommands()
            }
        #else
        return group
        #endif
        #endif
    }

    /// The library, inside every capability's bootstrap, as each Connections window shows it.
    private var mainContent: some View {
        GlassTerminalBootstrap(runtime: terminal) {
            GlassDatabaseBootstrap(runtime: database) {
                GlassDesktopBootstrap(runtime: desktop) {
                    GlassEditorBootstrap(runtime: editor) {
                        GlassShellLibraryView(model: model)
                    }
                }
            }
        }
        .glassLayers(layers)
        // The registry reaches every session's own chrome from here: the switcher's control
        // is drawn inside a terminal, a workspace or an editor, and each of those is a view
        // in this scene (or a cover presented from it), not something the shell can reach.
        .environment(model.registry)
        .modifier(GlassWidgetLibraryOpener())
        .trackWindowPresence(key: "main", recovery: windowRecovery)
        #if os(visionOS)
        // Idle for the time chosen in Settings ▸ General, with other windows open: the window
        // becomes its own orb, and a pinch on the orb brings the library back as it was (W29,
        // W39). Opened again after Connections closed last, it opens as its orb.
        .glassConnectionsIdleShrink(model: model, recovery: windowRecovery)
        #endif
        #if !os(macOS)
        // Handoff: a terminal, database or desktop continued from another device (D72).
        .onContinueUserActivity(GlassHandoff.activityType) { activity in
            if let endpoint = GlassHandoff.endpoint(from: activity) {
                GlassWidgetRequests.shared.post(.continueSession(endpoint: endpoint, tmux: GlassHandoff.tmuxSession(from: activity)))
            }
        }
        // Something opened with the app (D72): a file handed over by another app into the editor;
        // an `ssh://` link connects. Carried out as Siri's requests are (`GlassWidgetBridge`). The
        // Mac takes these in its app delegate (`MacTerminalAppDelegate.openURLs`), so an Open With
        // does not bring up a Connections window as well.
        .onOpenURL { url in
            guard let request = GlassWidgetRequest.forOpened(url, isMac: false) else { return }
            if GlassUITestRun.defaults == nil {
                GlassWidgetRequests.shared.post(request)
            } else if case .openInEditor(let urls) = request, let windowID = editor.open(urls[0]) {
                // A UI-test run carries no bridge: its files still open as before.
                editor.present(windowID)
            }
        }
        #endif
        #if os(macOS)
        .onAppear { terminal.attach(to: appDelegate) }
        #endif
        #if DEBUG
        // Screenshots: `--demo-open <surface>` in a `--ui-testing` run (GlassDemoMode.swift).
        // After the bootstraps mount, so each surface's request is drained where it always is.
        .modifier(GlassDemoModeTask { await GlassDemoMode.run(editor: editor, terminal: terminal, database: database, desktop: desktop, layers: layers, shell: model) })
        #endif
    }

    #if DEBUG || GLASS_STRESS_HARNESS
    /// The UI test runner cannot reach this sandbox from iOS or visionOS, so each isolated run
    /// removes earlier runs' directories older than ten minutes (a run in progress is never
    /// touched). macOS runs also clean up from the test side.
    private static func pruneStaleTestDirectories(in root: URL, keeping current: String) {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-600)
        for entry in entries where entry.lastPathComponent != current {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if modified < cutoff { try? manager.removeItem(at: entry) }
        }
    }
    #endif

    var body: some Scene {
        mainScene
        // The Files window carries the editor's presenter: Open in Editor there has to show a
        // window when Connections, the other place that can, is closed.
        GlassTerminalScenes(runtime: terminal) { [editor] in
            AnyView(Color.clear.accessibilityHidden(true).glassEditorWindowPresenter(editor))
        }
        GlassDatabaseScenes(runtime: database)
        GlassDesktopScenes(runtime: desktop)
        GlassEditorScenes(runtime: editor)
        #if os(macOS)
        Settings {
            GlassShellSettingsView(model: model)
                .glassLayers(layers)
        }
        #elseif os(visionOS)
        Window("Settings", id: "settings") {
            // No `NavigationStack` around it: the settings `TabView` is the window's root so its
            // tabs become the leading ornament; each pane has its own stack inside its tab.
            GlassShellSettingsView(model: model)
                .glassLayers(layers)
        }
        // All Windows (the ⚡ held, or Siri): a window of its own, which can be made as large as
        // the work needs (the owner, 2026-10-14, of the sheet it was: "will that work for larger
        // workloads?"). A place to go from, not to come back to: never reopened at launch.
        Window("All Windows", id: GlassShowAllWindows.windowID) {
            allWindowsContent
        }
        .defaultSize(width: 1280, height: 800)
        .restorationBehavior(.disabled)
        #endif
    }

    #if os(visionOS)
    /// All Windows inside every capability's bootstrap, as Connections is: what a card asks for — a
    /// terminal's window, a desktop's — is carried out by a window's bootstrap, and Connections may
    /// not be open.
    private var allWindowsContent: some View {
        GlassTerminalBootstrap(runtime: terminal) {
            GlassDatabaseBootstrap(runtime: database) {
                GlassDesktopBootstrap(runtime: desktop) {
                    GlassEditorBootstrap(runtime: editor) {
                        GlassAllWindowsWindow(model: model)
                    }
                }
            }
        }
        .glassLayers(layers)
        .environment(model.registry)
        .glassRegistersWindowOpener()
    }
    #endif
}
