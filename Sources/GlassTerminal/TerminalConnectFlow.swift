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
import GlassShell
import GlassSSHTransport
#if os(iOS)
import UIKit
#endif

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
    /// D14: the same prompt, driven by a caller that has no session — a borrowed port forward,
    /// or a setup-time trust resolution. Non-nil means the currently shown challenge came from
    /// the broker and the answer goes back to it rather than to a session.
    @State private var pendingTrustBrokerRequest: TerminalHostTrustBroker.Request?
    @State private var connectionFailureMessage: String?
    @State private var connectingServerIDs: Set<UUID> = []
    /// The shell's outcome callbacks for attempts still in flight (trust prompt, password
    /// prompt, legacy-algorithm confirmation), keyed by server id. Each is called once.
    @State private var outcomeReports: [UUID: GlassCapabilityReport] = [:]
    @State private var pendingLegacyAlgorithmServer: ServerConfiguration?
    @State private var passwordPromptServer: ServerConfiguration?
    @State private var pendingConnectionPurpose: TerminalSession.Purpose = .terminal
    /// The tmux session a pending connect was attaching to (D44), kept across the password and
    /// legacy-algorithm prompts so the retry attaches to it rather than opening a new one.
    @State private var pendingTmuxAttachment: TerminalTmuxAttachment?
    @State private var addServerDraft: AddServerRequest?
    @State private var editingServer: EditServerRequest?
    @State private var viewingServer: ServerConfiguration?
    @State private var serverPendingDeletion: ServerConfiguration?
    #if os(macOS)
    /// W7b: local tmux sessions still running that no tab shows, offered once at launch.
    @State private var runningSessionsToOffer: [String] = []
    #endif
    #if os(visionOS) || os(iOS)
    @State private var pendingPasswordWorkgroup: LayoutPreset?
    /// The device's stand-ins for the waiting workgroup's Mac terminals, already reviewed.
    @State private var pendingPasswordSubstitutions: [Int: LayoutPreset.SessionIntent]?
    @State private var workgroupPasswordWasSaved = false
    @State private var isOpeningWorkgroup = false
    @State private var substitutionReviewPreset: LayoutPreset?
    @State private var reviewedSubstitution: ReviewedSubstitution?
    #endif

    /// `Identifiable` wrapper so an empty draft (plain "Add Server") can drive a `.sheet(item:)`.
    struct AddServerRequest: Identifiable { let id = UUID(); let draft: ServerConfiguration? }
    /// A workgroup with its Mac terminals' SSH stand-ins chosen: the saved workgroup itself, so
    /// its other terminals keep their places and tmux sessions (W4b).
    struct ReviewedSubstitution {
        let preset: LayoutPreset
        let replacements: [Int: LayoutPreset.SessionIntent]
    }
    struct EditServerRequest: Identifiable {
        let server: ServerConfiguration
        let hostContext: ServerFormHostContext?
        var id: UUID { server.id }
    }

    func body(content: Content) -> some View {
        content
        #if os(macOS)
        // D47: the windows that held local terminals in tmux when the app quit, back on their
        // sessions. Taken once. With macOS's own window restoration on, it goes first — it puts
        // windows back where they were — and this opens whatever it did not bring back.
        .task {
            if UserDefaults.standard.bool(forKey: GlassWindowRestoration.key) {
                try? await Task.sleep(for: .milliseconds(1500))
                guard !Task.isCancelled else { return }
            }
            for windowID in MacLocalTmux.takeWindowsToReopen() {
                openWindow(id: "workspace", value: MacWorkspaceLaunchRequest(windowID: windowID, tabs: []))
            }
            // W7b: then, once those windows and any macOS restored have opened on their sessions,
            // the sessions still running that no tab shows. After a crash that was all of them,
            // and nothing said so. If this view goes away first, it asks when it next appears.
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            runningSessionsToOffer = MacLocalTmuxLaunchOffer.shared
                .take(shown: MacLocalTmuxLaunchOffer.shownSessions()) ?? []
        }
        .alert(
            MacLocalTmuxLaunchOffer.message(count: runningSessionsToOffer.count),
            isPresented: Binding(
                get: { !runningSessionsToOffer.isEmpty },
                set: { if !$0 { runningSessionsToOffer = [] } }
            )
        ) {
            Button("Reopen") { reopenRunningSessions() }
            Button("Not Now", role: .cancel) { runningSessionsToOffer = [] }
        } message: {
            Text(runningSessionsToOffer.count == 1
                 ? "It opens in a new window. Not Now leaves it in Active."
                 : "They open in one window, a tab for each. Not Now leaves them in Active.")
        }
        #endif
        .alert(
            trustPromptTitle,
            isPresented: trustPromptBinding,
            presenting: pendingTrustChallenge
        ) { challenge in
            Button(trustPromptConfirmTitle, role: challenge.reason == .changed ? .destructive : nil) {
                if pendingTrustBrokerRequest != nil {
                    // The transport pins the key and retries; trust is keyed `host:port` in the
                    // store, so accepting here settles this machine for every capability.
                    answerTrustBroker(.trust(remember: true))
                    return
                }
                guard let pending = pendingTrustSession else {
                    clearPendingTrustPrompt()
                    return
                }
                guard interactiveHostKeyTrustIsAllowed else {
                    rejectStrictHostKeyChallenge(challenge, for: pending)
                    return
                }
                // **Taken now, not inside the task.** SwiftUI runs this action, then sets the
                // alert's `isPresented` to false, whose setter closes and unregisters whatever
                // session is still pending — before the task below gets to run. The 2026-09 fix
                // took the session before the *reconnect*, but `trustHostKey` runs first and
                // looks the session up too, so every first connect to a new machine ended in
                // "This terminal session is no longer active" and the key was never saved
                // (2026-09-22, the first connect to a newly added server). With nothing pending, the dismissal has
                // nothing to close.
                guard let session = Self.takePendingTrustSession(&pendingTrustSession,
                                                                 challenge: &pendingTrustChallenge) else { return }
                Task { @MainActor in
                    do {
                        try await sessionManager.trustHostKey(challenge, for: session)
                        reconnectTrustedSession(session)
                    } catch {
                        connectionFailureMessage = error.localizedDescription
                        report(.failed(error.localizedDescription), for: session.server.id)
                        sessionManager.closePendingHostTrustSession(session)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                if pendingTrustBrokerRequest != nil {
                    answerTrustBroker(.reject)
                    return
                }
                closePendingTrustSessionAndClearPrompt()
            }
        } message: { challenge in
            Text(trustPromptMessage(for: challenge))
        }
        // A session-less challenge arriving from the broker drives the very same alert above.
        // A session's own challenge, if one is already showing, keeps the screen: the broker
        // queues, and its request is promoted when this one is answered.
        .onChange(of: runtime.trustBroker.pending?.id) { _, _ in
            adoptBrokeredTrustRequestIfIdle()
        }
        .onChange(of: pendingTrustChallenge == nil) { _, isClear in
            if isClear { adoptBrokeredTrustRequestIfIdle() }
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
                connectToServer(server, purpose: pendingConnectionPurpose, tmux: pendingTmuxAttachment, legacyAlgorithmsConfirmed: true)
            }
            Button("Cancel", role: .cancel) {
                report(.dismissed, for: server.id)
                pendingLegacyAlgorithmServer = nil
            }
        } message: { server in
            Text("\(server.name) permits obsolete SSH algorithms. They provide weaker protection and should only be used for a server you control when upgrading it is not currently possible.")
        }
        .onChange(of: passwordPromptServer?.id) { previous, current in
            // The prompt closed without a submitted password: the attempt is over. A submitted
            // password has already started `connectToServer`, which reports on its own.
            if let previous, current == nil, !connectingServerIDs.contains(previous) {
                report(.dismissed, for: previous)
            }
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
                            try await serverManager.tryPassword(password, for: current)
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
        .sheet(item: $editingServer) { request in
            GlassLayeredPanel(cornerRadius: 0) {
                EditServerView(server: request.server, serverManager: serverManager, hostContext: request.hostContext)
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
                Task { @MainActor in
                    do {
                        try await serverManager.deleteServer(server)
                        serverPendingDeletion = nil
                    } catch {
                        connectionFailureMessage = "The server was not deleted because its saved credential could not be removed: \(error.localizedDescription)"
                        serverPendingDeletion = nil
                    }
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
            guard let reviewed = reviewedSubstitution else { return }
            reviewedSubstitution = nil
            openVisionWorkgroup(reviewed.preset, substitutions: reviewed.replacements)
        }) { preset in
            WorkgroupSSHSubstitutionReview(preset: preset, servers: serverManager.servers,
                                          saved: settingsManager.sshSubstitutions(for: preset)) { replacements, remember in
                settingsManager.saveSSHSubstitutions(remember ? replacements : [:], for: preset)
                reviewedSubstitution = ReviewedSubstitution(preset: preset,
                                                            replacements: replacements.mapValues(\.intent))
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
        case .connect(let serverID, let purpose, let report, let tmux):
            guard let server = serverManager.server(for: serverID) else {
                report?(.failed(SessionOpenError.savedServerNotFound.localizedDescription))
                return
            }
            if let report {
                // A second Connect while one is pending replaces the callback; the shell only
                // cares about the latest attempt.
                if let superseded = outcomeReports[serverID] { superseded(.dismissed) }
                outcomeReports[serverID] = report
            }
            connectToServer(server, purpose: purpose, tmux: tmux)
        case .quickConnect(let config, let password):
            Task { @MainActor in
                if let failure = await connectTransient(config, password: password) {
                    connectionFailureMessage = failure
                }
            }
        case .openWorkgroup(let preset):
            openWorkgroup(preset)
        #if DEBUG
        case .demoReplay(let name, let output):
            // No SSHConnection is ever started: the sinks swallow typing and resizes, and the
            // transcript goes straight to the emulator, queued until the window's view attaches.
            let server = ServerConfiguration(name: name, host: "192.0.2.10", username: "ann")
            let session = TerminalSession(server: server,
                                          terminalWriteSink: { _ in },
                                          terminalResizeSink: { _, _ in })
            sessionManager.registerSession(session)
            session.state = .connected
            session.feedTerminalData(output)
            presentTerminalWindow(for: session)
        #endif
        case .addServer(let draft):
            addServerDraft = AddServerRequest(draft: draft)
        case .editServer(let server, let hostContext):
            editingServer = EditServerRequest(server: server, hostContext: hostContext)
        case .showFailure(let message):
            connectionFailureMessage = message
        case .serverInfo(let server):
            viewingServer = server
        case .deleteServer(let server):
            serverPendingDeletion = server
        case .localTerminal(let tmux):
            #if os(macOS)
            if let tmux {
                var intent = MacWorkspacePaneIntent.local
                intent.localTmuxSession = tmux
                openWindow(id: "workspace", value: MacWorkspaceLaunchRequest(initialPaneIntent: intent))
            } else {
                openWindow(id: "workspace", value: MacWorkspaceLaunchRequest())
            }
            #endif
        case .showWorkgroups:
            // The library's Workgroups panel — there is no Workgroups window (2026-10-08).
            #if os(iOS)
            // A phone may be showing a terminal in the library's place.
            iOSRouter.showConnections()
            runtime.showWorkgroupsPanel()
            #else
            runtime.showWorkgroups(openWindow: openWindow)
            #endif
        case .showTailscale:
            #if os(iOS)
            iOSRouter.showsTailscale = true
            #else
            openWindow(id: "terminal-tailscale")
            #endif
        case .showWorkgroup(let workgroupID):
            #if os(iOS)
            iOSRouter.showTerminal(workgroupID: workgroupID)
            #else
            openWindow(id: "terminal", value: workgroupID)
            #endif
        }
    }

    // MARK: - Workgroups (moved verbatim from ConnectionManagerView.openWorkgroup and friends)

    private func openWorkgroup(_ preset: LayoutPreset) {
        settingsManager.updateLayoutPresetLastUsed(preset.id)
        #if os(visionOS) || os(iOS)
        openVisionWorkgroup(preset)
        #else
        openMacWorkgroup(preset)
        #endif
    }

    /// Whether a Workgroup includes a connection that allows legacy SSH algorithms, which only a
    /// direct, confirmed connection may use.
    static func workgroupNeedsLegacyConsent(_ preset: LayoutPreset, servers: [ServerConfiguration]) -> Bool {
        preset.sessionIntents.contains { intent in
            servers.contains { $0.id == intent.serverID && $0.legacyAlgorithmsEnabled }
        }
    }

    static let legacyWorkgroupMessage = "A connection in this Workgroup uses legacy algorithms. Open that connection directly to review its security settings."

    #if os(visionOS) || os(iOS)
    private func resumeWorkgroupAfterPasswordPrompt() {
        guard let preset = pendingPasswordWorkgroup else { return }
        let shouldContinue = workgroupPasswordWasSaved
        let substitutions = pendingPasswordSubstitutions
        pendingPasswordWorkgroup = nil
        pendingPasswordSubstitutions = nil
        workgroupPasswordWasSaved = false
        guard shouldContinue else { return }
        openVisionWorkgroup(preset, substitutions: substitutions)
    }

    /// Shows a workgroup whose terminals are open here already.
    private func showOpenWorkgroup(_ workgroupID: UUID) {
        #if os(visionOS)
        openWindow(id: "terminal", value: workgroupID)
        #else
        iOSRouter.showTerminal(workgroupID: workgroupID)
        #endif
    }

    /// The phone: one slot per terminal, connected when shown (W4b). iPad and Vision Pro open
    /// every terminal, since their grid and carousel previews need live sessions.
    private var opensWorkgroupSlotsLazily: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    /// - Parameter substitutions: the reviewed SSH stand-ins for its Mac terminals; nil until
    ///   they have been reviewed.
    private func openVisionWorkgroup(_ preset: LayoutPreset, substitutions: [Int: LayoutPreset.SessionIntent]? = nil) {
        guard !isOpeningWorkgroup, passwordPromptServer == nil else { return }
        // Open here already: shown, never opened a second time (W4b). Its live terminals carry
        // the workgroup's id.
        if TerminalWorkgroupOpening.isOpen(preset.id, in: sessionManager) {
            showOpenWorkgroup(preset.id)
            return
        }
        if substitutions == nil && preset.sessionIntents.contains(where: { $0.kind == .local }) {
            substitutionReviewPreset = preset
            return
        }
        let plan = LayoutRestorationPlan(preset: preset, availableServers: serverManager.servers,
                                         substitutions: substitutions)
        // The Mac's policy, on every platform: a Workgroup opens its connections without the
        // per-connection confirmation that legacy algorithms require, so it does not open one of
        // those at all. Before this, a headset, iPad or iPhone connected it without asking.
        if Self.workgroupNeedsLegacyConsent(preset, servers: serverManager.servers) {
            connectionFailureMessage = Self.legacyWorkgroupMessage
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
                pendingPasswordSubstitutions = substitutions
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
            // The workgroup's own id, so opening it again finds these terminals (W4b).
            let workgroupID = sessionManager.createWorkgroup(
                id: preset.id,
                name: preset.name,
                colorTag: preset.colorTag
            )
            var failures = plan.failures

            if opensWorkgroupSlotsLazily {
                failures += TerminalWorkgroupOpening.makeSlots(for: plan, workgroupID: workgroupID,
                                                              sessionManager: sessionManager, settingsManager: settingsManager)
                if TerminalWorkgroupOpening.isOpen(workgroupID, in: sessionManager) {
                    showOpenWorkgroup(workgroupID)
                    do {
                        try await TerminalWorkgroupOpening.connectShownSlot(in: workgroupID, sessionManager: sessionManager,
                                                                            settingsManager: settingsManager)
                    } catch {
                        failures.append(error.localizedDescription)
                    }
                } else {
                    sessionManager.discardWorkgroupIfEmpty(workgroupID)
                }
                if !failures.isEmpty {
                    connectionFailureMessage = failures.joined(separator: "\n")
                }
                return
            }

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
                        startupCommand: target.intent.startupCommand,
                        configure: { session in
                            TerminalWorkgroupOpening.prepare(session, for: target, workgroupID: workgroupID,
                                                             settingsManager: settingsManager)
                        }
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
    private func openMacWorkgroup(_ preset: LayoutPreset) {
        // Open already — a window opened from it, or one showing its saved sessions: brought
        // forward, never opened a second time beside it (W4b).
        if MacWorkspacePreviewRegistry.shared.reveal(workgroup: preset) { return }
        // Keep every pane's position even when a saved endpoint is missing;
        // its native pane offers recovery without rearranging the workspace.
        // Legacy algorithm consent still requires the direct connection flow.
        if Self.workgroupNeedsLegacyConsent(preset, servers: serverManager.servers) {
            connectionFailureMessage = Self.legacyWorkgroupMessage
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
        tmux: TerminalTmuxAttachment? = nil,
        legacyAlgorithmsConfirmed: Bool = false
    ) {
        if server.legacyAlgorithmsEnabled && !legacyAlgorithmsConfirmed {
            pendingConnectionPurpose = purpose
            pendingTmuxAttachment = tmux
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
                    tmux: tmux,
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
                    pendingTmuxAttachment = tmux
                    passwordPromptServer = promptServer
                } else {
                    let message = Self.connectionFailureMessage(
                        base: error.localizedDescription,
                        diagnostics: nil,
                        host: server.host
                    )
                    connectionFailureMessage = message
                    report(.failed(message), for: server.id)
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
                report(.connected, for: server.id)
                return
            }

            if case .error(let message) = session.state {
                if session.didRequestInitialTerminalPresentation {
                    report(.failed(message), for: server.id)
                    return
                }
                let failure = Self.connectionFailureMessage(
                    base: message,
                    diagnostics: session.lastConnectionDiagnostics,
                    host: server.host
                )
                connectionFailureMessage = failure
                report(.failed(failure), for: server.id)
                sessionManager.closeSession(session)
                return
            }
            // A strict-mode host-key rejection leaves the session neither connected nor errored;
            // the flow has already told the user. The attempt is over either way.
            report(.dismissed, for: server.id)
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
                    if pendingTrustBrokerRequest != nil {
                        // Dismissed without an explicit answer: the caller is still suspended,
                        // so it gets a refusal rather than waiting forever.
                        answerTrustBroker(.reject)
                    } else if !interactiveHostKeyTrustIsAllowed,
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

    /// Shows the broker's next request, but never over a session's own challenge.
    private func adoptBrokeredTrustRequestIfIdle() {
        guard pendingTrustChallenge == nil, pendingTrustBrokerRequest == nil,
              let request = runtime.trustBroker.pending else { return }
        pendingTrustBrokerRequest = request
        pendingTrustChallenge = request.challenge
    }

    private func answerTrustBroker(_ decision: SSHHostTrustDecision) {
        pendingTrustBrokerRequest = nil
        pendingTrustChallenge = nil
        runtime.trustBroker.answer(decision)
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
            return "\(challenge.summary)\n\nAlgorithm: \(challenge.algorithm)\nFingerprint: \(challenge.fingerprintSHA256)"
        case .changed:
            return "The saved host key for \(challenge.host):\(challenge.port) no longer matches the server. This can happen after a legitimate server rebuild, but it can also indicate a security risk.\n\nNew algorithm: \(challenge.algorithm)\nNew fingerprint: \(challenge.fingerprintSHA256)"
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
        let message =
            "Strict host-key verification blocked the connection to \(challenge.host):\(challenge.port) because \(reason). No trust decision was recorded."
        connectionFailureMessage = message
        report(.failed(message), for: session.server.id)
        session.pendingHostKeyChallenge = nil
        sessionManager.closeSession(session)
        clearPendingTrustPrompt()
    }

    #if os(macOS)
    /// Reopen: one window, a tab per session, leaving out any a tab took up since the offer.
    private func reopenRunningSessions() {
        let shown = MacLocalTmuxLaunchOffer.shownSessions()
        let sessions = runningSessionsToOffer.filter { !shown.contains($0) }
        runningSessionsToOffer = []
        for request in MacLocalTmuxLaunchOffer.launchRequests(for: sessions) {
            openWindow(id: "workspace", value: request)
        }
    }
    #endif

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
                if !isPresented, let server = pendingLegacyAlgorithmServer {
                    report(.dismissed, for: server.id)
                    pendingLegacyAlgorithmServer = nil
                }
            }
        )
    }

    // MARK: - Outcome reports (the shell's `GlassCapability.open` callback)

    /// Delivers the shell's outcome for a server's attempt, once; later calls for the same
    /// attempt are no-ops. Attempts the terminal started itself have no report.
    private func report(_ outcome: GlassCapabilityOutcome, for serverID: UUID) {
        guard let pending = outcomeReports.removeValue(forKey: serverID) else { return }
        pending(outcome)
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
                "Local Network access may be required for this host. In System Settings, open Privacy & Security > Local Network, allow Glass Power Tools, then try again."
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
                // On trial: kept only if this sign-in succeeds.
                try await serverManager.tryPassword(password, for: savedServer)
                connectToServer(savedServer, purpose: pendingConnectionPurpose, tmux: pendingTmuxAttachment)
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

    /// Reconnects the session whose host key the user just trusted. The caller takes it out of
    /// the prompt state first (`takePendingTrustSession`), before any await.
    ///
    /// The session is taken out of the prompt state *before* the reconnect task starts. The
    /// alert's Confirm action runs first, then SwiftUI sets the alert's `isPresented` binding to
    /// false, whose setter performs the Cancel cleanup (close and unregister the pending
    /// session). With the session still pending at that point, the cleanup closed it before the
    /// task ran `reconnect`, which then threw `sessionNotRegistered` — the post-trust failure
    /// seen against the real host. Clearing synchronously leaves the dismissal nothing to close.

    /// Clears the prompt state and hands back the session it held, so the prompt's dismissal
    /// cannot close the session a retry is about to reconnect. Nonisolated for unit testing.
    nonisolated static func takePendingTrustSession(
        _ session: inout TerminalSession?,
        challenge: inout HostKeyTrustChallenge?
    ) -> TerminalSession? {
        defer { session = nil; challenge = nil }
        return session
    }

    private func reconnectTrustedSession(_ session: TerminalSession) {
        let serverID = session.server.id
        Task { @MainActor in
            if let updatedServer = serverManager.server(for: serverID) {
                session.server = updatedServer
            }
            session.pendingHostKeyChallenge = nil
            do {
                try await sessionManager.reconnect(session, settingsManager: settingsManager)
            } catch {
                connectionFailureMessage = error.localizedDescription
                report(.failed(error.localizedDescription), for: serverID)
                sessionManager.closePendingHostTrustSession(session)
                return
            }
            if session.state == .connected {
                if !session.didRequestInitialTerminalPresentation {
                    presentConnectionSurface(for: session)
                }
                report(.connected, for: serverID)
            } else {
                if case .error(let message) = session.state {
                    connectionFailureMessage = message
                    report(.failed(message), for: serverID)
                } else {
                    report(.dismissed, for: serverID)
                }
                sessionManager.closePendingHostTrustSession(session)
            }
        }
    }

    private func closePendingTrustSessionAndClearPrompt() {
        if let session = pendingTrustSession {
            report(.dismissed, for: session.server.id)
            sessionManager.closePendingHostTrustSession(session)
        }
        clearPendingTrustPrompt()
    }

    private func clearPendingTrustPrompt() {
        pendingTrustSession = nil
        pendingTrustChallenge = nil
    }

}
