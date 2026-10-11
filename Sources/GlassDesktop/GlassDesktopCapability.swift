//
//  GlassDesktopCapability.swift
//  Glass Power Tools — GlassDesktop
//
//  The remote desktop capability's public surface: the runtime the app owns, and the capability
//  the shell routes Connect through. Everything else in this module stays internal.
//
//  Shaped after `Sources/GlassDatabase/GlassDatabaseCapability.swift`, which is itself shaped
//  after the terminal's. The one thing that differs: a desktop service carries its *protocol*
//  (RDP or VNC/Screen Sharing) as a field on the saved record rather than as a service kind, the
//  way glassDT modelled it. So this capability owns `.rdp` and serves both.
//

import SwiftUI
import GlassConnectionKit
import GlassShell
import GlassLayers
import GlassRDPTransport

/// The shell's outcome callback for one connect attempt (see `GlassCapabilityOutcome`).
public typealias GlassDesktopReport = @MainActor (GlassCapabilityOutcome) -> Void

/// Owns the desktop model for the process. One per app, created in the composition root.
@MainActor @Observable
public final class GlassDesktopRuntime {
    /// The ⚡ in the desktop's toolbar. Supplied by the composition root.
    public var showActiveConnections: GlassShowActiveConnections?

    let app: DesktopAppModel

    /// Everything the shell and this module's surfaces can ask the desktop to do. One queue,
    /// consumed by the scenes, so opening a session — and the failure alert when it cannot be
    /// opened — exists in exactly one place.
    enum Request {
        /// Open a session window for this saved connection.
        case connect(connectionID: EndpointID, report: GlassDesktopReport?)
        /// Bring an already-open desktop back to the screen (Active's row). Not a connect.
        case show(connectionID: EndpointID)
        /// Show the failure alert with this message (a link with nothing behind it).
        case showFailure(String)
    }
    private(set) var requestSerial = 0
    private var pendingRequests: [Request] = []

    #if DEBUG
    /// Screenshot demo sessions (`requestDemoDesktop`): a still frame, no host behind it.
    var demoSessions: [EndpointID: DesktopSessionModel] = [:]
    #endif

    /// The one layering state, shared with the shell so no second material system exists.
    public let layers: GlassLayerStore

    /// How to ask the shell what a capability may do with a host. Set by the composition root,
    /// because the shell model owns the brokering and a capability must not hold the model.
    public var hostAccess: (@MainActor (HostProfile) -> GlassCapabilityHostAccess)?

    /// How to ask the library to open its host sheet for a machine parsed out of a file. Set by
    /// the composition root for the same reason `hostAccess` is: the library owns the sheet, and a
    /// capability must not reach into a view.
    public var requestSetup: (@MainActor (GlassShellSetupPrefill) -> Void)?

    /// D26: points the saved-desktop store at the shell's catalog. Called once, by the composition
    /// root, for the same reason the terminal's and the database's are.
    @MainActor
    public func connectToLibrary(store: any GlassServiceStore) async {
        await app.attach(store: store)
    }

    /// D26: read the saved desktops now that the catalog can answer. A `Task` because loading is
    /// async and the hook is not; `load()` is idempotent and refuses an unread store.
    public func catalogDidLoad() {
        let app = self.app
        Task { @MainActor in await app.load() }
    }

    public init(layers: GlassLayerStore? = nil, app: DesktopAppModel? = nil) {
        self.layers = layers ?? GlassLayerStore()
        // A window's own settings (W25) are kept on this device, beside All Desktops'.
        self.app = app ?? DesktopAppModel(windowSettings: DesktopWindowSettingsStore(defaults: GlassUITestRun.settingsDefaults))
    }

    func enqueue(_ request: Request) {
        pendingRequests.append(request)
        requestSerial &+= 1
    }

    func takeRequests() -> [Request] {
        defer { pendingRequests.removeAll() }
        return pendingRequests
    }

    /// Reports the shell has asked for, held until the session window reaches a real state.
    /// Keyed by endpoint so a second Connect to the same desktop replaces the first rather than
    /// leaving a caller waiting forever.
    private var heldReports: [EndpointID: GlassDesktopReport] = [:]

    func holdReport(_ report: GlassDesktopReport?, for id: EndpointID) {
        guard let report else { return }
        heldReports[id] = report
    }

    /// Called once the session actually connected or failed. Removing it first means an outcome
    /// is delivered exactly once, however many times the state changes afterwards.
    func reportOutcome(_ state: GlassRDPState, for id: EndpointID?) {
        guard let id, let report = heldReports.removeValue(forKey: id) else { return }
        switch state {
        case .connected: report(.connected)
        case .failed(let message): report(.failed(message))
        default: break
        }
    }

    /// Loads saved desktops once, at first use.
    public func loadIfNeeded() async {
        guard !app.isLoaded else { return }
        await app.load()
    }

    /// The saved desktop behind a shell endpoint, if there is one — **asked of the catalog** when
    /// the in-memory list has not been read yet. Editing a service in the first moments after
    /// launch used to find nothing and report the link as broken, which is what a saved desktop
    /// looks like when it has been lost.
    func connection(for id: EndpointID) -> DesktopConnection? {
        app.storedConnection(for: id)
    }
}

/// The shell's remote desktop capability. A service is created complete through the shell's host
/// sheet: the draft commits the desktop record and its password under the shell's endpoint id,
/// which is the link. `open` connects to that record; a link with nothing behind it is reported
/// as such rather than silently doing nothing.
@MainActor
public final class GlassDesktopCapability: GlassCapability {
    public let kind: HostServiceKind = .rdp
    public let displayName = "Desktop"
    public let symbolName = "display"

    /// Every desktop on screen, one row each, on the machine its service belongs to.
    public func openSessions() -> [GlassOpenSession] {
        runtime.app.liveSessions.map { session in
            let connection = session.connection
            let protocolName = connection.protocol == .rdp ? "RDP" : "VNC"
            return GlassOpenSession(
                id: Self.sessionID(connectionID: connection.id),
                title: connection.name,
                subtitle: session.isConnected ? protocolName : "\(protocolName) · \(session.status)",
                symbolName: symbolName,
                endpointIDs: [connection.id],
                activate: { [runtime] in runtime.enqueue(.show(connectionID: connection.id)) },
                close: { _ = session.close() },
                isConnected: session.isConnected
            )
        }
    }

    /// Open in Screen Sharing, on the Mac, for a VNC desktop (`DesktopScreenSharing`).
    public func serviceTools(service: HostServiceLink, host: HostProfile) -> [GlassServiceTool] {
        #if os(macOS)
        guard let connection = runtime.connection(for: service.endpointID),
              DesktopScreenSharing.url(for: connection) != nil else { return [] }
        let runtime = self.runtime
        return [
            GlassServiceTool(id: "screen-sharing-\(service.endpointID.rawValue.uuidString.lowercased())",
                             title: "Screen Sharing",
                             symbolName: "macwindow.on.rectangle",
                             subtitle: "Open this desktop in the Mac's Screen Sharing app") {
                DesktopScreenSharing.open(connection) { runtime.enqueue(.showFailure($0)) }
            }
        ]
        #else
        return []
        #endif
    }

    public var settingsPages: [GlassCapabilitySettingsPage] {
        [GlassCapabilitySettingsPage(id: "desktop.general", title: "Desktops", systemImage: "display") {
            AnyView(DesktopSettingsView())
        }]
    }

    public static func sessionID(connectionID: EndpointID) -> String {
        "desktop:\(connectionID.rawValue.uuidString)"
    }
    private let runtime: GlassDesktopRuntime

    public init(runtime: GlassDesktopRuntime) { self.runtime = runtime }

    // MARK: Setup (the shell's host sheet)

    public func makeSetupDraft() -> any GlassServiceDraft {
        DesktopServiceDraft(app: runtime.app)
    }

    public func setupDraft(for service: HostServiceLink, host: HostProfile) -> (any GlassServiceDraft)? {
        guard let connection = runtime.connection(for: service.endpointID) else { return nil }
        return DesktopServiceDraft(editing: connection, app: runtime.app)
    }

    /// A draft from an imported `.rdp` file. The record arrives with an id of its own; `commit`
    /// re-keys it to the shell's endpoint id (`DesktopServiceDraft.swift:211`), so an import is
    /// identical to any other new service by the time it is saved.
    public func setupDraft(importing configuration: Data) -> (any GlassServiceDraft)? {
        guard let connection = try? JSONDecoder().decode(DesktopConnection.self, from: configuration) else {
            return nil
        }
        return DesktopServiceDraft(editing: connection, app: runtime.app)
    }

    public func libraryToolbarItems() -> AnyView {
        AnyView(DesktopImportCommand(runtime: runtime))
    }

    /// D25: the shell deletes the host record and cascades here, so this removes only what the
    /// capability itself stored — the desktop record and its Keychain credential.
    public func removeService(_ service: HostServiceLink, host: HostProfile) async throws {
        guard let connection = runtime.connection(for: service.endpointID) else { return }
        await runtime.app.delete(connection)
        if let message = runtime.app.errorMessage {
            runtime.app.errorMessage = nil
            throw AppStorageError.recovery(message)
        }
    }

    /// The saved record's address, for hosts that predate addresses on the host record.
    public func knownAddress(service: HostServiceLink, host: HostProfile) -> String? {
        guard let connection = runtime.connection(for: service.endpointID) else { return nil }
        let address = connection.host.trimmingCharacters(in: .whitespacesAndNewlines)
        return address.isEmpty ? nil : address
    }

    /// The desktop's RDP or VNC port, for the availability dot.
    public func knownPort(service: HostServiceLink, host: HostProfile) -> Int? {
        runtime.connection(for: service.endpointID).map { Int($0.port) }
    }

    /// The machine's address changed in the shell: every saved desktop that is a service of that
    /// host follows it, so the machine's identity is edited once.
    public func hostAddressDidChange(host: HostProfile, address: String?) {
        guard let address else { return }
        let owned = Set(host.services.filter { $0.kind == kind }.map(\.endpointID))
        let following = runtime.app.connections.filter { owned.contains($0.id) && $0.host != address }
        guard !following.isEmpty else { return }
        let app = runtime.app
        Task { @MainActor in
            for var connection in following {
                connection.host = address
                // No password: this is a metadata edit and must not rebind the credential.
                try? await app.save(connection, password: nil)
            }
        }
    }

    // MARK: Connect

    public func open(service: HostServiceLink, host: HostProfile, report: @escaping GlassDesktopReport) {
        open(service: service, host: host,
             hostAccess: GlassCapabilityHostAccess(address: host.address), report: report)
    }

    public func open(service: HostServiceLink, host: HostProfile, hostAccess: GlassCapabilityHostAccess,
                     report: @escaping GlassDesktopReport) {
        guard runtime.connection(for: service.endpointID) != nil else {
            let message = "\(service.displayName) has no saved desktop configuration. Edit the service to set it up, or remove it."
            runtime.enqueue(.showFailure(message))
            report(.failed(message))
            return
        }
        runtime.enqueue(.connect(connectionID: service.endpointID, report: report))
    }
}
