//
//  GlassWidgetBridge.swift
//  Glass Power Tools
//
//  The widgets' side of the app (2026-10-12): it keeps the snapshot the Machines and Active widgets
//  read current, and carries out what a tap on one asks for. Both read the library, so both live
//  here at the composition root, where the library is.
//

import AppIntents
import os
import Observation
import SwiftUI
import WidgetKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import GlassConnectionKit
import GlassConnectionUI
import GlassLayers
import GlassShell
import GlassWidgetData

/// The intents — the widgets' and Shortcuts', Siri's and Spotlight's (D72) — as part of the app.
struct GlassPowerToolsAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [GlassWidgetIntents.self] }
}

@MainActor
enum GlassWidgetBridge {
    /// What the bridge asks of the capabilities, given by the composition root, which holds them.
    struct Actions {
        var openWorkgroup: @MainActor (UUID) -> Void
        /// The Mac: a terminal window, in a folder when there is one.
        var newLocalTerminal: @MainActor (URL?, OpenWindowAction) -> Void
        /// The Mac: a tab in the terminal window in front, in a folder.
        var newLocalTerminalTab: @MainActor (URL, OpenWindowAction) -> Void
        /// The Mac: a `.command` script run in a new tab.
        var runInTerminal: @MainActor (URL, OpenWindowAction) -> Void
        var openInEditor: @MainActor ([URL], OpenWindowAction) -> Void
        /// An `ssh://` link.
        var openSSHLink: @MainActor (URL) -> Void
        /// Files to a machine's folder; what happened, in a sentence.
        var sendFiles: GlassAppServices.SendFiles
        /// The saved workgroups, for the snapshot (Shortcuts and Siri name them).
        var workgroups: @MainActor () -> [GlassWidgetSnapshot.Workgroup]
    }

    private static var started = false
    private static var actions: Actions?

    /// Carries out every intent's request from now on — a widget's tap, Shortcuts, Siri, Spotlight;
    /// any that launched the app first included — and keeps the snapshot current for as long as the
    /// app runs.
    static func start(model: GlassShellModel, actions: Actions) {
        guard !started else { return }
        started = true
        self.actions = actions
        GlassWidgetRequests.shared.handle { carryOut($0, model: model) }
        // Answered in place, for Shortcuts to say: a connection that may need its host trusted,
        // which the Connections window asks about.
        GlassAppServices.shared.sendFiles = { files, machine, folder in
            ensureLibrary()
            return try await actions.sendFiles(files, machine, folder)
        }
        Task { await keepSnapshotCurrent(model: model) }
        takeExternalRequests()
        // The search index follows the setting, both ways, as soon as it changes.
        updateSearch(force: false)
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { updateSearch(force: false) }
        }
        // What the Finder's toolbar button or a Quick Action left in the App Group, whenever the
        // app comes forward — which is how they bring it forward.
        NotificationCenter.default.addObserver(forName: becameActive, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { takeExternalRequests() }
        }
    }

    #if os(macOS)
    private static let becameActive = NSApplication.didBecomeActiveNotification
    #else
    private static let becameActive = UIApplication.didBecomeActiveNotification
    #endif

    /// Machines and workgroups in the system's search, as Settings ▸ Privacy says (D72): indexed
    /// when the library changes, and again — or cleared — when the setting does.
    private static var searchShown: Bool?

    private static func updateSearch(_ snapshot: GlassWidgetSnapshot? = GlassWidgetStore.read(), force: Bool = true) {
        let enabled = GlassUITestRun.settingsDefaults.bool(forKey: GlassSpotlight.settingKey)
        guard force || enabled != searchShown else { return }
        searchShown = enabled
        Task { await GlassSpotlight.update(snapshot, enabled: enabled) }
    }

    /// Requests extensions left for the app (`GlassExternalRequests`), carried out as Siri's are.
    private static func takeExternalRequests() {
        for request in GlassExternalRequests.take() { GlassWidgetRequests.shared.post(request) }
    }

    static func carryOut(_ request: GlassWidgetRequest, model: GlassShellModel) {
        switch request {
        case let .connect(machine, service):
            ensureLibrary()
            model.connect(hostID: HostID(rawValue: machine), endpointID: EndpointID(rawValue: service))
        case .showMachine(let machine):
            showLibrary()
            model.hostToShow = HostID(rawValue: machine)
        case .showActive:
            showLibrary()
            model.showActiveConnections()
        case .openWorkgroup(let workgroup):
            ensureLibrary()
            actions?.openWorkgroup(workgroup)
        case .newLocalTerminal(let folder):
            GlassWindowOpener.shared.perform { actions?.newLocalTerminal(folder, $0) }
        case .newLocalTerminalTab(let folder):
            GlassWindowOpener.shared.perform { actions?.newLocalTerminalTab(folder, $0) }
        case .runInTerminal(let script):
            GlassWindowOpener.shared.perform { actions?.runInTerminal(script, $0) }
        case .openInEditor(let urls):
            GlassWindowOpener.shared.perform { actions?.openInEditor(urls, $0) }
        case .openSSHLink(let link):
            ensureLibrary()
            actions?.openSSHLink(link)
        case .continueSession(let endpoint):
            // Handoff names the service; this device's library knows its machine (D26).
            guard let host = model.host(owningEndpoint: EndpointID(rawValue: endpoint)) else {
                GlassWidgetBridgeLog.logger.notice("A continued session names a service this library does not have")
                return
            }
            ensureLibrary()
            model.connect(hostID: host.id, endpointID: EndpointID(rawValue: endpoint))
        }
    }

    /// The Connections window, brought forward or opened.
    private static func showLibrary() {
        #if os(macOS)
        if !GlassLibraryWindows.bringForward() { GlassWindowOpener.shared.perform { $0.openConnections() } }
        #elseif os(visionOS)
        // The one Connections window, brought forward (`openConnections`).
        GlassWindowOpener.shared.perform { $0.openConnections() }
        #endif
    }

    /// A Connections window to carry a connection out: the capabilities run their requests — and
    /// ask for passwords and host trust — from its views. With only terminal windows open, a widget's
    /// Connect waited for a library window that never came (found building D72, 2026-10-13). One
    /// already open stays where it is.
    private static func ensureLibrary() {
        #if os(macOS)
        if !GlassLibraryWindows.isOpen { GlassWindowOpener.shared.perform { $0.openConnections() } }
        #elseif os(visionOS)
        GlassWindowOpener.shared.perform { $0.openConnections() }
        #endif
    }

    /// What the widgets, Shortcuts and Siri read: the library's machines and Active, and the
    /// terminal's workgroups.
    private static func snapshot(model: GlassShellModel) -> GlassWidgetSnapshot {
        var snapshot = model.widgetSnapshot()
        snapshot.workgroups = actions?.workgroups() ?? []
        return snapshot
    }

    /// How long a quiet library goes before the snapshot is written anyway: a running session's
    /// count changes where nothing observable says so.
    static let refreshInterval: Duration = .seconds(60)

    private static func keepSnapshotCurrent(model: GlassShellModel) async {
        while !Task.isCancelled {
            write(snapshot(model: model))
            await nextChange(in: model, orAfter: refreshInterval)
            // A burst of changes — a workgroup opening six terminals — is one write.
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Writes the snapshot when it changed, and only then wakes the widgets and tells Siri and
    /// Shortcuts the names their phrases can use.
    static func write(_ snapshot: GlassWidgetSnapshot) {
        do {
            if try GlassWidgetStore.write(snapshot) {
                WidgetCenter.shared.reloadAllTimelines()
                GlassPowerToolsShortcuts.updateAppShortcutParameters()
                updateSearch(snapshot)
            }
        } catch {
            GlassWidgetBridgeLog.logger.error("The widgets' snapshot could not be written: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Returns when anything the snapshot is built from changes, or after `timeout`.
    private static func nextChange(in model: GlassShellModel, orAfter timeout: Duration) async {
        let gate = Gate()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            gate.continuation = continuation
            withObservationTracking {
                _ = snapshot(model: model)
            } onChange: {
                Task { @MainActor in gate.open() }
            }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                gate.open()
            }
        }
    }

    /// Opened once, by whichever comes first.
    private final class Gate {
        var continuation: CheckedContinuation<Void, Never>?
        func open() {
            continuation?.resume()
            continuation = nil
        }
    }
}

extension GlassWidgetBridge {
    enum SendError: LocalizedError {
        case notInLibrary

        var errorDescription: String? {
            switch self {
            case .notInLibrary: "That machine is no longer in your library, or has no Terminal service to send through."
            }
        }
    }
}

enum GlassWidgetBridgeLog {
    static let logger = Logger(subsystem: "sh.glas", category: "widgets")
}

/// The library window's `openWindow`, for opening windows from outside any window
/// (`GlassWindowOpener`); every other kind of window registers its own.
struct GlassWidgetLibraryOpener: ViewModifier {
    func body(content: Content) -> some View {
        content.glassRegistersWindowOpener()
    }
}
