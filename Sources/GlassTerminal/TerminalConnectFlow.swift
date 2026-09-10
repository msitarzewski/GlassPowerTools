//
//  TerminalConnectFlow.swift
//  Glass Power Tools — GlassTerminal
//
//  The connect flow moved verbatim out of glas.sh's ConnectionManagerView (which owned the
//  library that GlassShell now provides): legacy-algorithm confirmation, host-key trust prompt
//  gated on the verification setting, password-prompt fallback, terminal-or-SFTP purpose, and the
//  platform-specific presentation of the resulting session. The workgroup-preset password
//  path (`pendingPasswordWorkgroup`) stayed with the preset launcher and is not part of this flow.
//

import SwiftUI

/// Attached once by `GlassTerminalBootstrap`; runs connect requests posted to the runtime.
struct TerminalConnectFlow: ViewModifier {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(GlassTerminalRuntime.self) private var runtime
    @Environment(\.openWindow) private var openWindow
    #if os(iOS)
    @Environment(IOSAppRouter.self) private var iOSRouter
    #endif
    private var serverManager: ServerManager { sessionManager.serverManager }

    @State private var pendingTrustSession: TerminalSession?
    @State private var pendingTrustChallenge: HostKeyTrustChallenge?
    @State private var connectionFailureMessage: String?
    @State private var connectingServerIDs: Set<UUID> = []
    @State private var pendingLegacyAlgorithmServer: ServerConfiguration?
    @State private var passwordPromptServer: ServerConfiguration?
    @State private var pendingConnectionPurpose: TerminalSession.Purpose = .terminal

    func body(content: Content) -> some View {
        content
        .alert(
            trustPromptTitle,
            isPresented: trustPromptBinding,
            presenting: pendingTrustChallenge
        ) { challenge in
            Button(trustPromptConfirmTitle, role: challenge.reason == .changed ? .destructive : nil) {
                guard let session = pendingTrustSession else {
                    clearPendingTrustPrompt()
                    return
                }
                guard interactiveHostKeyTrustIsAllowed else {
                    rejectStrictHostKeyChallenge(challenge, for: session)
                    return
                }
                do {
                    try sessionManager.trustHostKey(challenge, for: session)
                    retryPendingConnection()
                } catch {
                    connectionFailureMessage = error.localizedDescription
                    sessionManager.closePendingHostTrustSession(session)
                    clearPendingTrustPrompt()
                }
            }
            Button("Cancel", role: .cancel) {
                closePendingTrustSessionAndClearPrompt()
            }
        } message: { challenge in
            Text(trustPromptMessage(for: challenge))
        }
        .alert("Connection Failed", isPresented: connectionFailureAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(connectionFailureMessage ?? "Unable to connect.")
        }
        .alert(
            "Use Legacy SSH Algorithms?",
            isPresented: legacyAlgorithmPromptBinding,
            presenting: pendingLegacyAlgorithmServer
        ) { server in
            Button("Connect with Legacy Algorithms", role: .destructive) {
                pendingLegacyAlgorithmServer = nil
                connectToServer(server, purpose: pendingConnectionPurpose, legacyAlgorithmsConfirmed: true)
            }
            Button("Cancel", role: .cancel) {
                pendingLegacyAlgorithmServer = nil
            }
        } message: { server in
            Text("\(server.name) permits obsolete SSH algorithms. They provide weaker protection and should only be used for a server you control when upgrading it is not currently possible.")
        }
        .sheet(item: $passwordPromptServer) { server in
            ConnectionPasswordPromptSheet(
                server: server,
                savesPassword: serverManager.server(for: server.id) != nil
            ) { password in
                return await submitPassword(password, for: server)
            }
        }
        .onChange(of: runtime.connectRequestSerial) { _, _ in
            guard let request = runtime.takeConnectRequest(),
                  let server = serverManager.server(for: request.serverID) else { return }
            connectToServer(server, purpose: request.purpose)
        }
    }

    private func presentTerminalWindow(for session: TerminalSession) {
        #if os(visionOS)
        let workgroupID = sessionManager.createWorkgroup(
            name: session.server.name,
            colorTag: session.server.colorTag
        )
        guard sessionManager.appendSession(session, toWorkgroup: workgroupID) else {
            sessionManager.closeSession(session)
            sessionManager.discardWorkgroupIfEmpty(workgroupID)
            connectionFailureMessage = "The terminal could not be added to its workgroup."
            return
        }
        openWindow(id: "terminal", value: workgroupID)
        #elseif os(iOS)
        let workgroupID = sessionManager.createWorkgroup(
            name: session.server.name,
            colorTag: session.server.colorTag
        )
        guard sessionManager.appendSession(session, toWorkgroup: workgroupID) else {
            sessionManager.closeSession(session)
            sessionManager.discardWorkgroupIfEmpty(workgroupID)
            connectionFailureMessage = "The terminal could not be added to its workgroup."
            return
        }
        iOSRouter.showTerminal(workgroupID: workgroupID)
        #else
        openWindow(
            id: "workspace",
            value: MacLiveSessionWorkspaceRouter.launchRequest(
                for: session,
                sessionManager: sessionManager
            )
        )
        #endif
    }
    
    private func connectToServer(
        _ server: ServerConfiguration,
        purpose: TerminalSession.Purpose = .terminal,
        legacyAlgorithmsConfirmed: Bool = false
    ) {
        if server.legacyAlgorithmsEnabled && !legacyAlgorithmsConfirmed {
            pendingConnectionPurpose = purpose
            pendingLegacyAlgorithmServer = server
            return
        }

        guard !connectingServerIDs.contains(server.id) else { return }
        connectingServerIDs.insert(server.id)

        Task { @MainActor in
            defer { connectingServerIDs.remove(server.id) }

            let launch: AuthorizedSessionLaunch
            do {
                launch = try await sessionManager.createAuthorizedSession(
                    for: server,
                    settingsManager: settingsManager,
                    purpose: purpose,
                    initialTerminalPresentation: { pendingSession in
                        presentConnectionSurface(for: pendingSession)
                    }
                )
            } catch {
                if let promptServer = Self.targetPasswordPromptServer(
                    for: error,
                    requestedServerID: server.id
                ) {
                    pendingConnectionPurpose = purpose
                    passwordPromptServer = promptServer
                } else {
                    connectionFailureMessage = Self.connectionFailureMessage(
                        base: error.localizedDescription,
                        diagnostics: nil,
                        host: server.host
                    )
                }
                return
            }

            let session = launch.session
            if let challenge = session.pendingHostKeyChallenge,
               settingsManager.hostKeyVerificationMode == HostKeyVerificationMode.ask.rawValue {
                pendingTrustSession = session
                pendingTrustChallenge = challenge
                return
            }

            if session.state == .connected {
                if !session.didRequestInitialTerminalPresentation {
                    presentConnectionSurface(for: session)
                }
                return
            }

            if case .error(let message) = session.state {
                if session.didRequestInitialTerminalPresentation {
                    return
                }
                connectionFailureMessage = Self.connectionFailureMessage(
                    base: message,
                    diagnostics: session.lastConnectionDiagnostics,
                    host: server.host
                )
                sessionManager.closeSession(session)
            }
        }
    }

    private func presentConnectionSurface(for session: TerminalSession) {
        guard session.purpose == .sftp else {
            presentTerminalWindow(for: session)
            return
        }
        #if os(iOS)
        iOSRouter.showSFTP(sessionID: session.id)
        #else
        openWindow(id: "sftp", value: SFTPBrowserContext(sessionID: session.id))
        #endif
    }

    private var trustPromptBinding: Binding<Bool> {
        Binding(
            get: { interactiveHostKeyTrustIsAllowed && pendingTrustChallenge != nil },
            set: { isPresented in
                if !isPresented {
                    if !interactiveHostKeyTrustIsAllowed,
                       let challenge = pendingTrustChallenge,
                       let session = pendingTrustSession {
                        rejectStrictHostKeyChallenge(challenge, for: session)
                    } else {
                        closePendingTrustSessionAndClearPrompt()
                    }
                }
            }
        )
    }

    private var interactiveHostKeyTrustIsAllowed: Bool {
        settingsManager.hostKeyVerificationMode == HostKeyVerificationMode.ask.rawValue
    }

    private var trustPromptTitle: String {
        pendingTrustChallenge?.reason == .changed ? "SSH Host Key Changed" : "Trust SSH Host Key?"
    }

    private var trustPromptConfirmTitle: String {
        pendingTrustChallenge?.reason == .changed ? "Trust Changed Key" : "Trust and Connect"
    }

    private func trustPromptMessage(for challenge: HostKeyTrustChallenge) -> String {
        switch challenge.reason {
        case .unknown:
            return "\(challenge.summary)\n\nAlgorithm: \(challenge.algorithm)\nFingerprint (SHA-256): \(challenge.fingerprintSHA256)"
        case .changed:
            return "The saved host key for \(challenge.host):\(challenge.port) no longer matches the server. This can happen after a legitimate server rebuild, but it can also indicate a security risk.\n\nNew algorithm: \(challenge.algorithm)\nNew fingerprint (SHA-256): \(challenge.fingerprintSHA256)"
        }
    }

    private func stageHostKeyChallenge(
        _ challenge: HostKeyTrustChallenge,
        for session: TerminalSession
    ) {
        guard interactiveHostKeyTrustIsAllowed else {
            rejectStrictHostKeyChallenge(challenge, for: session)
            return
        }
        pendingTrustSession = session
        pendingTrustChallenge = challenge
    }

    private func rejectStrictHostKeyChallenge(
        _ challenge: HostKeyTrustChallenge,
        for session: TerminalSession
    ) {
        let reason = challenge.reason == .changed
            ? "the presented key does not match the saved key"
            : "the presented key has not been saved"
        connectionFailureMessage =
            "Strict host-key verification blocked the connection to \(challenge.host):\(challenge.port) because \(reason). No trust decision was recorded."
        session.pendingHostKeyChallenge = nil
        sessionManager.closeSession(session)
        clearPendingTrustPrompt()
    }

    private var connectionFailureAlertBinding: Binding<Bool> {
        Binding(
            get: { connectionFailureMessage != nil },
            set: { isPresented in
                if !isPresented {
                    connectionFailureMessage = nil
                }
            }
        )
    }

    private var legacyAlgorithmPromptBinding: Binding<Bool> {
        Binding(
            get: { pendingLegacyAlgorithmServer != nil },
            set: { isPresented in
                if !isPresented {
                    pendingLegacyAlgorithmServer = nil
                }
            }
        )
    }

    static func targetPasswordPromptServer(
        for error: Error,
        requestedServerID: UUID
    ) -> ServerConfiguration? {
        guard let sessionError = error as? SessionOpenError,
              case .missingPassword(let server, .target) = sessionError,
              server.id == requestedServerID else {
            return nil
        }
        return server
    }

    static func connectionFailureMessage(
        base: String,
        diagnostics: String?,
        host: String
    ) -> String {
        var sections = [base]
        if let diagnostics,
           !diagnostics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(diagnostics)
        }
        if isLikelyLocalNetworkHost(host) {
            sections.append(
                "Local Network access may be required for this host. In System Settings, open Privacy & Security > Local Network, allow glas.sh, then try again."
            )
        }
        return sections.joined(separator: "\n\n")
    }

    static func isLikelyLocalNetworkHost(_ rawHost: String) -> Bool {
        var host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.hasPrefix("["), host.hasSuffix("]") {
            host.removeFirst()
            host.removeLast()
        }

        if host == "localhost" || host.hasSuffix(".local") {
            return true
        }

        if host.contains(":") {
            let address = host.split(separator: "%", maxSplits: 1).first.map(String.init) ?? host
            return address == "::1"
                || address.hasPrefix("fc")
                || address.hasPrefix("fd")
                || address.hasPrefix("fe8")
                || address.hasPrefix("fe9")
                || address.hasPrefix("fea")
                || address.hasPrefix("feb")
        }

        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        let values = octets.compactMap { Int($0) }
        guard octets.count == 4,
              values.count == 4,
              values.allSatisfy({ (0...255).contains($0) }) else {
            return false
        }

        return values[0] == 10
            || values[0] == 127
            || (values[0] == 169 && values[1] == 254)
            || (values[0] == 172 && (16...31).contains(values[1]))
            || (values[0] == 192 && values[1] == 168)
    }

    private func submitPassword(
        _ password: String,
        for server: ServerConfiguration
    ) async -> String? {
        if let savedServer = serverManager.server(for: server.id) {
            do {
                try serverManager.updateServerOrThrow(savedServer, password: password)
                connectToServer(savedServer, purpose: pendingConnectionPurpose)
                return nil
            } catch {
                return "The password could not be saved in Keychain. \(error.localizedDescription)"
            }
        }

        do {
            let launch = try await sessionManager.createTransientAuthorizedSession(
                for: server,
                settingsManager: settingsManager,
                password: password,
                initialTerminalPresentation: { pendingSession in
                    presentTerminalWindow(for: pendingSession)
                }
            )
            if launch.session.state == .connected {
                if !launch.session.didRequestInitialTerminalPresentation {
                    presentTerminalWindow(for: launch.session)
                }
                return nil
            }
            if let challenge = launch.session.pendingHostKeyChallenge {
                stageHostKeyChallenge(challenge, for: launch.session)
                return nil
            }
            if case .error(let message) = launch.session.state {
                if launch.session.didRequestInitialTerminalPresentation {
                    return nil
                }
                sessionManager.closeSession(launch.session)
                return message
            }
            if launch.session.didRequestInitialTerminalPresentation {
                return nil
            }
            sessionManager.closeSession(launch.session)
            return "The server did not establish a terminal session."
        } catch {
            return error.localizedDescription
        }
    }

    private func retryPendingConnection() {
        guard let session = pendingTrustSession else { return }

        Task { @MainActor in
            if let updatedServer = serverManager.server(for: session.server.id) {
                session.server = updatedServer
            }
            session.pendingHostKeyChallenge = nil
            do {
                try await sessionManager.reconnect(session, settingsManager: settingsManager)
            } catch {
                connectionFailureMessage = error.localizedDescription
                sessionManager.closePendingHostTrustSession(session)
                clearPendingTrustPrompt()
                return
            }
            if session.state == .connected {
                if !session.didRequestInitialTerminalPresentation {
                    presentConnectionSurface(for: session)
                }
                clearPendingTrustPrompt()
            } else {
                if case .error(let message) = session.state {
                    connectionFailureMessage = message
                }
                sessionManager.closePendingHostTrustSession(session)
                clearPendingTrustPrompt()
            }
        }
    }

    private func closePendingTrustSessionAndClearPrompt() {
        if let session = pendingTrustSession {
            sessionManager.closePendingHostTrustSession(session)
        }
        clearPendingTrustPrompt()
    }

    private func clearPendingTrustPrompt() {
        pendingTrustSession = nil
        pendingTrustChallenge = nil
    }

}
