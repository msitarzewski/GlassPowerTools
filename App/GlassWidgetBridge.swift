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
import GlassConnectionKit
import GlassConnectionUI
import GlassShell
import GlassWidgetData

/// The widget intents, as part of the app: a tap on a widget runs them here.
struct GlassPowerToolsAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [GlassWidgetIntents.self] }
}

@MainActor
enum GlassWidgetBridge {
    /// Opens the Connections window, from a window that can. Set when the library first appears;
    /// a tap that wants the library while it is closed opens it with this.
    static var openLibrary: (() -> Void)?
    private static var started = false

    /// Carries out widget taps from now on (any that launched the app first included), and keeps
    /// the snapshot current for as long as the app runs.
    static func start(model: GlassShellModel) {
        guard !started else { return }
        started = true
        GlassWidgetRequests.shared.handle { carryOut($0, model: model) }
        Task { await keepSnapshotCurrent(model: model) }
    }

    static func carryOut(_ request: GlassWidgetRequest, model: GlassShellModel) {
        switch request {
        case let .connect(machine, service):
            model.connect(hostID: HostID(rawValue: machine), endpointID: EndpointID(rawValue: service))
        case .showMachine(let machine):
            showLibrary()
            model.hostToShow = HostID(rawValue: machine)
        case .showActive:
            showLibrary()
            model.showActiveConnections()
        }
    }

    private static func showLibrary() {
        #if os(macOS)
        if !GlassLibraryWindows.bringForward() { openLibrary?() }
        #elseif os(visionOS)
        // The one Connections window, brought forward (`openConnections`).
        openLibrary?()
        #endif
    }

    /// How long a quiet library goes before the snapshot is written anyway: a running session's
    /// count changes where nothing observable says so.
    static let refreshInterval: Duration = .seconds(60)

    private static func keepSnapshotCurrent(model: GlassShellModel) async {
        while !Task.isCancelled {
            write(model.widgetSnapshot())
            await nextChange(in: model, orAfter: refreshInterval)
            // A burst of changes — a workgroup opening six terminals — is one write.
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Writes the snapshot when it changed, and only then wakes the widgets.
    static func write(_ snapshot: GlassWidgetSnapshot) {
        do {
            if try GlassWidgetStore.write(snapshot) { WidgetCenter.shared.reloadAllTimelines() }
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
                _ = model.widgetSnapshot()
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

enum GlassWidgetBridgeLog {
    static let logger = Logger(subsystem: "sh.glas", category: "widgets")
}

/// Gives the bridge a way to open Connections, from the library's own window.
struct GlassWidgetLibraryOpener: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            let openWindow = openWindow
            GlassWidgetBridge.openLibrary = { openWindow.openConnections() }
        }
    }
}
