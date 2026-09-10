//
//  GlassTerminalCapability.swift
//  Glass Power Tools — GlassTerminal
//
//  The SSH capability's public surface: the runtime the app owns, the capability the shell routes
//  Connect through, and the bootstrap wrapper that hosts glas.sh's startup, deep-link, trust and
//  connect flows around the shell's library. Everything else in this module stays internal.
//

import SwiftUI
import GlassConnectionKit
import GlassShell

/// What the shell asked the terminal to open.
public enum GlassTerminalOpenPurpose: Sendable { case terminal, sftp }

/// Owns glas.sh's managers for the process. One per app, created in the composition root.
@MainActor @Observable
public final class GlassTerminalRuntime {
    let sessionManager: SessionManager
    let settingsManager: SettingsManager
    let windowRecoveryManager: WindowRecoveryManager

    struct ConnectRequest { let serverID: UUID; let purpose: TerminalSession.Purpose }
    struct SetupRequest: Identifiable {
        let host: HostProfile
        let service: HostServiceLink
        var id: EndpointID { service.endpointID }
    }

    private(set) var connectRequestSerial = 0
    private var pendingConnect: ConnectRequest?
    var setupRequest: SetupRequest?

    public init() {
        sessionManager = SessionManager(loadImmediately: false)
        settingsManager = SettingsManager(loadImmediately: false)
        windowRecoveryManager = WindowRecoveryManager()
    }

    /// Connect to the saved server whose id is the shell's endpoint id. Consumed by the bootstrap.
    public func requestConnect(serverID: UUID, purpose: GlassTerminalOpenPurpose = .terminal) {
        pendingConnect = ConnectRequest(serverID: serverID, purpose: purpose == .sftp ? .sftp : .terminal)
        connectRequestSerial &+= 1
    }

    func takeConnectRequest() -> ConnectRequest? {
        defer { pendingConnect = nil }
        return pendingConnect
    }

    /// True when a saved SSH server exists for this endpoint id.
    public func hasServer(id: UUID) -> Bool {
        sessionManager.serverManager.server(for: id) != nil
    }

    #if os(macOS)
    /// Lets the app's `NSApplicationDelegateAdaptor` confirm quit with live sessions, as glas.sh does.
    public func attach(to delegate: MacTerminalAppDelegate) {
        delegate.sessionManager = sessionManager
        delegate.settingsManager = settingsManager
    }
    #endif
}

/// The shell's SSH capability. `open` connects when a saved server exists for the service's
/// endpoint id; otherwise it asks the bootstrap to present glas.sh's server form so the user
/// creates one — the new server takes the shell's endpoint id, which is the link.
@MainActor
public final class GlassTerminalCapability: GlassCapability {
    public let kind: HostServiceKind = .ssh
    public let displayName = "Terminal"
    public let symbolName = "terminal"
    private let runtime: GlassTerminalRuntime

    public init(runtime: GlassTerminalRuntime) { self.runtime = runtime }

    public func open(service: HostServiceLink, host: HostProfile) {
        let serverID = service.endpointID.rawValue
        if runtime.hasServer(id: serverID) {
            runtime.requestConnect(serverID: serverID)
        } else {
            runtime.setupRequest = .init(host: host, service: service)
        }
    }
}

/// Wraps the shell's library window content with glas.sh's bootstrap (persistent state load,
/// deep links, trust prompts), the connect flow, the server-setup sheet, and — on iPhone — the
/// router that swaps the library for a live terminal workgroup or an SFTP browser.
public struct GlassTerminalBootstrap<Content: View>: View {
    private let runtime: GlassTerminalRuntime
    private let content: Content
    #if os(iOS)
    @State private var router = IOSAppRouter()
    #endif

    public init(runtime: GlassTerminalRuntime, @ViewBuilder content: () -> Content) {
        self.runtime = runtime
        self.content = content()
    }

    public var body: some View {
        @Bindable var runtime = runtime
        platformRoot
            .modifier(TerminalConnectFlow())
            .sheet(item: $runtime.setupRequest) { request in
                AddServerView(
                    serverManager: runtime.sessionManager.serverManager,
                    draft: ServerConfiguration(
                        id: request.service.endpointID.rawValue,
                        name: request.host.displayName,
                        host: request.host.aliases.first ?? "",
                        username: ""
                    )
                )
            }
            .environment(runtime)
            .environment(runtime.sessionManager)
            .environment(runtime.settingsManager)
            #if os(iOS)
            .environment(router)
            #endif
    }

    @ViewBuilder
    private var platformRoot: some View {
        #if os(iOS)
        @Bindable var router = router
        Group {
            if let workgroupID = router.terminalWorkgroupID {
                VisionTerminalWorkgroupView(workgroupID: workgroupID)
                    .id(workgroupID)
            } else {
                MainBootstrapView { content }
            }
        }
        .sheet(isPresented: Binding(
            get: { router.sftpContext != nil },
            set: { if !$0 { router.sftpContext = nil } }
        )) {
            if let context = router.sftpContext,
               runtime.sessionManager.session(for: context.sessionID) != nil {
                SFTPBrowserView(sessionID: context.sessionID)
            } else {
                SFTPBrowserNotFoundView(context: router.sftpContext)
            }
        }
        #else
        MainBootstrapView { content }
        #endif
    }
}
