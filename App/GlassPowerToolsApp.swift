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

@main
struct GlassPowerToolsApp: App {
    @State private var layers: GlassLayerStore
    @State private var model: GlassShellModel
    @State private var terminal: GlassTerminalRuntime
    @State private var database: GlassDatabaseRuntime
    @State private var windowRecovery: GlassWindowRecoveryManager
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacTerminalAppDelegate.self) private var appDelegate
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
        // Stage 2: the SSH capability. glas.sh's managers live for the process in the runtime; the
        // shell routes Connect for `.ssh` services through the capability.
        let windowRecovery = GlassWindowRecoveryManager()
        let terminal = GlassTerminalRuntime(layers: layers, windowRecovery: windowRecovery)
        model.registry.register(GlassTerminalCapability(runtime: terminal))
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
        model.registry.register(GlassDatabaseCapability(runtime: database))
        _layers = State(initialValue: layers)
        _model = State(initialValue: model)
        _terminal = State(initialValue: terminal)
        _database = State(initialValue: database)
        _windowRecovery = State(initialValue: windowRecovery)
    }

    /// The library window. On macOS it carries glas.sh's Connections window sizing
    /// (`../glas.sh/glas.sh/glas_shApp.swift:99-113`): without a default size the window opened
    /// at the sidebar's ideal height and clipped the detail.
    private var mainScene: some Scene {
        let group = WindowGroup("Connections", id: "main") {
            GlassTerminalBootstrap(runtime: terminal) {
                GlassDatabaseBootstrap(runtime: database) {
                    GlassShellLibraryView(model: model)
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
