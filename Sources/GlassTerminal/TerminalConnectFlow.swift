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
import GlassLayers

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
    @State private var addServerDraft: AddServerRequest?
    @State private var editingServer: ServerConfiguration?
    @State private var viewingServer: ServerConfiguration?
    @State private var serverPendingDeletion: ServerConfiguration?
    #if os(visionOS) || os(iOS)
    @State private var pendingPasswordWorkgroup: LayoutPreset?
    @State private var workgroupPasswordWasSaved = false
    @State private var isOpeningWorkgroup = false
    @State private var substitutionReviewPreset: LayoutPreset?
    @State private var reviewedSubstitutionPreset: LayoutPreset?
    #endif

    /// `Identifiable` wrapper so an empty draft (plain "Add Server") can drive a `.sheet(item:)`.
    struct AddServerRequest: Identifiable { let id = UUID(); let draft: ServerConfiguration? }

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
        .sheet(item: $passwordPromptServer, onDismiss: {
            #if os(visionOS) || os(iOS)
            resumeWorkgroupAfterPasswordPrompt()
            #endif
        }) { server in
            GlassLayeredPanel(cornerRadius: 0) {
                ConnectionPasswordPromptSheet(
                    server: server,
                    savesPassword: serverManager.server(for: server.id) != nil
                ) { password in
                    #if os(visionOS) || os(iOS)
                    if pendingPasswordWorkgroup != nil {
                        guard let current = serverManager.server(for: server.id) else {
                            return "This saved connection is no longer available."
                        }
                        do {
                            try serverManager.updateServerOrThrow(current, password: password)
                            workgroupPasswordWasSaved = true
                            return nil
                        } catch {
                            return "The password could not be saved. \(error.localizedDescription)"
                        }
                    }
                    #endif
                    return await submitPassword(password, for: server)
                }
            }
        }
        .sheet(item: $addServerDraft) { request in
            GlassLayeredPanel(cornerRadius: 0) {
                AddServerView(serverManager: serverManager, draft: request.draft)
            }
        }
        .sheet(item: $editingServer) { server in
            GlassLayeredPanel(cornerRadius: 0) {
                EditServerView(server: server, serverManager: serverManager)
            }
        }
        .sheet(item: $viewingServer) { server in
            ServerInfoView(server: server, session: sessionManager.sessions.first { $0.server.id == server.id })
        }
        .confirmationDialog(
            "Delete Server?",
            isPresented: Binding(
                get: { serverPendingDeletion != nil },
                set: { if !$0 { serverPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: serverPendingDeletion
        ) { server in
            Button("Delete \(server.name)", role: .destructive) {
                do {
                    try serverManager.deleteServer(server)
                    serverPendingDeletion = nil
                } catch {
                    connectionFailureMessage = "The server was not deleted because its saved credential could not be removed: \(error.localizedDescription)"
                    serverPendingDeletion = nil
                }
            }
            .accessibilityIdentifier("connection-library-confirm-delete-server")
            Button("Cancel", role: .cancel) {
                serverPendingDeletion = nil
            }
        } message: { server in
            Text("This removes '\(server.name)' and its terminal-specific saved password. SSH keys shared by other servers are kept.")
        }
        #if os(visionOS) || os(iOS)
        .sheet(item: $substitutionReviewPreset, onDismiss: {
            guard let preset = reviewedSubstitutionPreset else { return }
            reviewedSubstitutionPreset = nil
            openVisionWorkgroup(preset, plan: LayoutRestorationPlan(
                preset: preset, availableServers: serverManager.servers), reviewedLocalEntries: true)
        }) { preset in
            WorkgroupSSHSubstitutionReview(preset: preset, servers: serverManager.servers,
                                          saved: settingsManager.sshSubstitutions(for: preset)) { replacements, remember in
                settingsManager.saveSSHSubstitutions(remember ? replacements : [:], for: preset)
                var launchPreset = preset
                launchPreset.sessionIntents = preset.sessionIntents.enumerated().compactMap { index, intent in
                    intent.kind == .local ? replacements[index]?.intent : intent
                }
                launchPreset.workspaceLayout = nil
                reviewedSubstitutionPreset = launchPreset
                substitutionReviewPreset = nil
            }
        }
        #endif
        .onChange(of: runtime.requestSerial) { _, _ in
            for request in runtime.takeRequests() { handle(request) }
        }
        #if os(macOS)
        // glas.sh's command palette posts a saved-server id and reopens the library window.
        .onChange(of: sessionManager.paletteConnectionRequest, initial: true) { _, request in
            guard let request, sessionManager.paletteConnectionRequest == request,
                  let server = serverManager.server(for: request) else { return }
            sessionManager.paletteConnectionRequest = nil
            connectToServer(server)
        }
        #endif
    }

    private func handle(_ request: GlassTerminalRuntime.Request) {
        switch request {
        case .connect(let serverID, let purpose):
            guard let server = serverManager.server(for: serverID) else { return }
            connectToServer(server, purpose: purpose)
        case .quickConnect(let config, let password):
            Task { @MainActor in
                if let failure = await connectTransient(config, password: password) {
                    connectionFailureMessage = failure
                }
            }
        case .openWorkgroup(let preset):
            openWorkgroup(preset)
        case .addServer(let draft):
            addServerDraft = AddServerRequest(draft: draft)
        case .editServer(let server):
            editingServer = server
        case .serverInfo(let server):
            viewingServer = server
        case .deleteServer(let server):
            serverPendingDeletion = server
        case .localTerminal:
            #if os(macOS)
            openWindow(id: "workspace", value: MacWorkspaceLaunchRequest())
            #endif
        case .showWorkgroups:
            #if os(iOS)
            iOSRouter.showsWorkgroups = true
            #else
            openWindow(id: "terminal-workgroups")
            #endif
        case .showTailscale:
            #if os(iOS)
            iOSRouter.showsTailscale = true
            #else
            openWindow(id: "terminal-tailscale")
            #endif
        }
    }

    // MARK: - Workgroups (moved verbatim from ConnectionManagerView.openWorkgroup and friends)

    private func openWorkgroup(_ preset: LayoutPreset) {
        settingsManager.updateLayoutPresetLastUsed(preset.id)
        let restorationPlan = LayoutRestorationPlan(
            preset: preset,
            availableServers: serverManager.servers
        )
        #if os(visionOS) || os(iOS)
        openVisionWorkgroup(preset, plan: restorationPlan)
        #else
        openMacWorkgroup(preset, plan: restorationPlan)
        #endif
    }

    #if os(visionOS) || os(iOS)
    private func resumeWorkgroupAfterPasswordPrompt() {
        guard let preset = pendingPasswordWorkgroup else { return }
        let shouldContinue = workgroupPasswordWasSaved
        pendingPasswordWorkgroup = nil
        workgroupPasswordWasSaved = false
        guard shouldContinue else { return }
        openVisionWorkgroup(preset, plan: LayoutRestorationPlan(
            preset: preset, availableServers: serverManager.servers
        ))
    }

    private func openVisionWorkgroup(_ preset: LayoutPreset, plan: LayoutRestorationPlan, reviewedLocalEntries: Bool = false) {
        guard !isOpeningWorkgroup, passwordPromptServer == nil else { return }
        if !reviewedLocalEntries && preset.sessionIntents.contains(where: { $0.kind == .local }) {
            substitutionReviewPreset = preset
            return
        }
        // Resolve credentials for the entire recipe before opening any sessions.
        // This also finds missing jump-host passwords through the shared policy.
        for target in plan.targets {
            guard let server = target.server else { continue }
            do {
                _ = try sessionManager.prepareConnection(for: server)
            } catch SessionOpenError.missingPassword(let missingServer, _) {
                pendingPasswordWorkgroup = preset
                workgroupPasswordWasSaved = false
                passwordPromptServer = missingServer
                return
            } catch {
                // The launch path below reports non-password failures per pane.
                continue
            }
        }
        isOpeningWorkgroup = true
        Task { @MainActor in
            defer { isOpeningWorkgroup = false }
            let workgroupID = sessionManager.createWorkgroup(
                name: preset.name,
                colorTag: preset.colorTag
            )
            var failures = plan.failures
            var appendedSessionIDs: [UUID] = []

            for target in plan.targets {
                guard target.intent.kind == .ssh,
                      let server = target.server,
                      let serverID = target.intent.serverID else {
                    failures.append("\(target.displayName): local terminals are available on macOS.")
                    continue
                }
                do {
                    let launch = try await sessionManager.createAuthorizedSessionByServerID(
                        serverID,
                        settingsManager: settingsManager,
                        startupCommand: target.intent.startupCommand
                    )
                    let session = launch.session
                    if session.state == .connected
                        || (interactiveHostKeyTrustIsAllowed && session.pendingHostKeyChallenge != nil) {
                        if sessionManager.appendSession(session, toWorkgroup: workgroupID) {
                            appendedSessionIDs.append(session.id)
                        } else {
                            failures.append("\(target.displayName): the terminal could not be added to the workgroup.")
                            sessionManager.closeSession(session)
                        }
                    } else if let challenge = session.pendingHostKeyChallenge {
                        let reason = challenge.reason == .changed
                            ? "presented a changed host key"
                            : "presented an unknown host key"
                        failures.append("\(server.name): Strict host-key verification blocked the connection because it \(reason).")
                        session.pendingHostKeyChallenge = nil
                        sessionManager.closeSession(session)
                    } else if case .error(let message) = session.state {
                        failures.append("\(server.name): \(message)")
                        sessionManager.closeSession(session)
                    }
                } catch {
                    failures.append("\(server.name): \(error.localizedDescription)")
                }
            }

            if let firstSessionID = appendedSessionIDs.first {
                sessionManager.selectSession(firstSessionID, inWorkgroup: workgroupID)
                #if os(visionOS)
                openWindow(id: "terminal", value: workgroupID)
                #else
                iOSRouter.showTerminal(workgroupID: workgroupID)
                #endif
            } else {
                sessionManager.discardWorkgroupIfEmpty(workgroupID)
            }
            if !failures.isEmpty {
                connectionFailureMessage = failures.joined(separator: "\n")
            }
        }
    }
    #else
    private func openMacWorkgroup(_ preset: LayoutPreset, plan: LayoutRestorationPlan) {
        // Keep every pane's position even when a saved endpoint is missing;
        // its native pane offers recovery without rearranging the workspace.
        // Legacy algorithm consent still requires the direct connection flow.
        if preset.sessionIntents.contains(where: { intent in
            serverManager.servers.contains { $0.id == intent.serverID && $0.legacyAlgorithmsEnabled }
        }) {
            connectionFailureMessage = "A connection in this Workgroup uses legacy algorithms. Open that connection directly to review its security settings."
            return
        }
        do {
            try MacWorkgroupLauncher.launch(preset: preset) { request in
                openWindow(id: "workspace", value: request)
            }
        } catch {
            connectionFailureMessage = error.localizedDescription
        }
    }
    #endif



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
        return await connectTransient(server, password: password)
    }

    /// One-off connection that is never saved (quick connect from a Tailscale device). Returns a
    /// failure message, or nil when a session was presented or a prompt was staged.
    private func connectTransient(
        _ server: ServerConfiguration,
        password: String
    ) async -> String? {
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
