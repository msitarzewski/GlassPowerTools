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
import GlassTerminal
import GlassDatabase
import GlassDesktop
import GlassEditor

@main
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
        let layers = GlassLayerStore()
        var isolatedDirectory: URL?
        #if DEBUG
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
        model.registry.register(GlassTerminalCapability(runtime: terminal))
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
        // D26: the database's saved connections live on their service links too.
        database.connectToLibrary(store: model)
        model.registry.register(GlassDatabaseCapability(runtime: database))
        // Stage 4: the remote desktop capability. It owns `.rdp` and serves both RDP and
        // VNC/Screen Sharing, because the protocol is a field on the saved desktop rather than a
        // service kind — glassDT's model, which is why the catalog needs no fourth kind.
        let desktop = GlassDesktopRuntime(layers: layers)
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
        let editor = GlassEditorRuntime(layers: layers)
        // Its preferences still belong in the one settings surface, so the page is registered here
        // — the composition root is the only place that knows about both the shell and the editor.
        model.registry.registerSettingsPage(editor.settingsPage)
        _layers = State(initialValue: layers)
        _model = State(initialValue: model)
        _terminal = State(initialValue: terminal)
        _database = State(initialValue: database)
        _desktop = State(initialValue: desktop)
        _windowRecovery = State(initialValue: windowRecovery)
        _editor = State(initialValue: editor)
    }

    /// The library window. On macOS it carries glas.sh's Connections window sizing
    /// (`../glas.sh/glas.sh/glas_shApp.swift:99-113`): without a default size the window opened
    /// at the sidebar's ideal height and clipped the detail.
    private var mainScene: some Scene {
        let group = WindowGroup("Connections", id: "main") {
            GlassTerminalBootstrap(runtime: terminal) {
                GlassDatabaseBootstrap(runtime: database) {
                    GlassDesktopBootstrap(runtime: desktop) {
                        GlassShellLibraryView(model: model)
                    }
                }
            }
            .glassLayers(layers)
            .trackWindowPresence(key: "main", recovery: windowRecovery)
            #if os(macOS)
            .onAppear { terminal.attach(to: appDelegate) }
            #endif
        }
        #if os(macOS)
        return group
            .defaultSize(width: 1180, height: 720)
            .windowResizability(.contentMinSize)
            // File ▸ New, owned once by the shell and aimed by whichever window is focused: a SQL
            // document in a database workspace, a terminal window in a terminal workspace, a host
            // here. Attached to this scene because the shell has no scene of its own, and because
            // exactly one scope may replace a command placement — two replacements are not merged,
            // they silently delete each other (see `GlassShellFileCommands`).
            .commands { GlassShellFileCommands() }
        #else
        return group
        #endif
    }

    #if DEBUG
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
        GlassTerminalScenes(runtime: terminal)
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
            NavigationStack {
                GlassShellSettingsView(model: model)
            }
            .glassLayers(layers)
        }
        #endif
    }
}
