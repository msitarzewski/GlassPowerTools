//
//  TerminalWindowView.swift
//  glas.sh
//
//  Main terminal window with visionOS glass design and ornaments
//

import SwiftUI
import GlassLayers
import GlassConnectionUI
import GlassShell
import GlassEditorCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
import Combine
#endif
import GlassTerminalEmulator

struct TerminalFontActions {
    let increase: () -> Void
    let decrease: () -> Void
    let reset: () -> Void
}

private struct TerminalFontActionsKey: FocusedValueKey {
    typealias Value = TerminalFontActions
}

extension FocusedValues {
    var terminalFontActions: TerminalFontActions? {
        get { self[TerminalFontActionsKey.self] }
        set { self[TerminalFontActionsKey.self] = newValue }
    }
}

enum TerminalNewTerminalRoute: Equatable {
    case connections
    case macTab

    static var platformDefault: Self {
        #if os(macOS)
        .macTab
        #else
        .connections
        #endif
    }

    var accessibilityLabel: String {
        switch self {
        case .connections: "New Terminal"
        case .macTab: "New Terminal Tab"
        }
    }

    func perform(openConnections: () -> Void, openMacTab: () -> Void) {
        switch self {
        case .connections: openConnections()
        case .macTab: openMacTab()
        }
    }
}

struct TerminalWindowView: View {
    #if os(visionOS)
    @Environment(\.visionTerminalPresentation) private var visionPresentation
    #endif
    @Bindable var session: TerminalSession
    /// Standalone terminal windows own their session. An app-level workspace or
    /// workgroup retains ownership so view identity and tab moves cannot disconnect SSH.
    var ownsSessionLifecycle = true
    /// Native workgroup tabs provide connection identity. Standalone visionOS
    /// terminal windows keep the per-connection ornament.
    var showsConnectionOrnament = true
    /// A workgroup can retain several terminal views so their emulator state is
    /// preserved. Only the selected view may own keyboard focus.
    var isTerminalActive = true
    /// Split workspaces retain pane separation; a single terminal uses the
    /// square edge-to-edge canvas provided by the native window. This value is
    /// harmless on other platforms and keeps the shared initializer portable.
    var showsMacPaneChrome = false
    /// Find, Find Next and Find Previous from the menu bar, for this pane; each new nonce is one
    /// command. The bar's state stays in this view.
    var externalFindRequest: TerminalFindRequest = .none
    /// Embedded workspaces provide their own tab launcher. Standalone windows
    /// use their platform's default terminal-launch route.
    var onNewTerminalTab: (() -> Void)? = nil
    /// The + held: a terminal on a saved server opened in this window, new or attached to a running
    /// tmux session (`TerminalNewTabMenu`). Nil leaves the + a button.
    var onOpenTerminal: (@MainActor (ServerConfiguration, TerminalTmuxAttachment?) -> Void)? = nil
    /// Embedded workspaces retain their own window and pane topology when an
    /// SSH session ends. The owner removes the live session and presents retry
    /// state instead of allowing this view to dismiss the workspace window.
    var onSessionRequestedClose: (() -> Void)? = nil
    /// A successful remote shell exit completes the pane instead of presenting
    /// the retry state reserved for disconnect actions and connection failures.
    var onSessionEndedCleanly: (() -> Void)? = nil
    /// The remote shell's title and directory, as they change — a Mac tab is named by them.
    var onTerminalContextChange: ((_ title: String?, _ directory: String?) -> Void)? = nil
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    /// For Open in Editor: the composition root's way to the editor. Optional, as in a window
    /// without one the item is simply not offered.
    @Environment(GlassTerminalRuntime.self) private var terminalRuntime: GlassTerminalRuntime?
    #if os(iOS)
    @Environment(IOSAppRouter.self) private var iOSRouter
    #endif
    #if !os(macOS)
    /// W15: a tab dragged onto this terminal moves into its window.
    @Environment(\.terminalTabDrop) private var terminalTabDrop
    /// W20, W22: the workgroup this terminal is drawn in, whose settings This Window edits.
    @Environment(\.terminalWorkgroupID) private var workgroupID
    /// W26: that workgroup's moves, for the tools menu and, on Vision Pro, the title.
    @Environment(\.terminalTabMoving) private var tabMoving
    #else
    /// W20, W22: the Mac terminal window this pane is in, whose settings This Window edits.
    @Environment(MacWorkspaceWindowController.self) private var macWindow: MacWorkspaceWindowController?
    #endif
    /// W22: the settings of the window this terminal is in, which it draws and behaves with.
    @Environment(\.glassWindowOverrides) private var windowSettings
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var find = TerminalFindController()
    /// A link to a 3D model, opened in 3D here (D78).
    @State private var modelLinks = TerminalModelLinkOpener()
    @State private var showingTerminalSettings = false
    #if os(iOS)
    @State private var softwareKeyboardVisible = false
    #endif
    @State private var showingCloseConfirmation = false
    @State private var showVisualBell = false
    @State private var showingSnippetPicker = false
    @State private var showingAIAssistant = false
    /// The directory given to the assistant, asked for when it opens (tmux keeps it to itself).
    @State private var aiAssistantDirectory: String?
    @State private var showingErrorCard = false
    @State private var aiAssistant = AIAssistant()
    @ObservedObject private var terminalHostModel: SwiftTermHostModel
    @State private var errorCheckTask: Task<Void, Never>?
    @State private var terminalAudioManager = TerminalAudioManager()
    @State private var notificationManager = NotificationManager()
    @State private var isImmersiveFocusActive = false
    @State private var showingRecordings = false
    @State private var recordings: [SessionRecording] = []
    @State private var recordingPendingDeletion: SessionRecording?
    @State private var recordingDeletionError: String?
    @State private var showingRecordingConsent = false
    #if os(macOS)
    @State private var macTerminalWindow: NSWindow?
    @State private var isMacFullScreen = false
    @State private var macInitialGeometryFitAttempts = 0
    #endif
    /// The terminal's own area, which under Scale keeps the grid's shape (D75).
    @State private var terminalCanvasSize = CGSize.zero
    @Environment(\.openWindow) private var openWindow
    #if os(visionOS)
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    #endif
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.colorScheme) private var systemColorScheme
    #endif

    init(
        session: TerminalSession,
        ownsSessionLifecycle: Bool = true,
        showsConnectionOrnament: Bool = true,
        isTerminalActive: Bool = true,
        showsMacPaneChrome: Bool = false,
        externalFindRequest: TerminalFindRequest = .none,
        onNewTerminalTab: (() -> Void)? = nil,
        onOpenTerminal: (@MainActor (ServerConfiguration, TerminalTmuxAttachment?) -> Void)? = nil,
        onSessionRequestedClose: (() -> Void)? = nil,
        onSessionEndedCleanly: (() -> Void)? = nil,
        onTerminalContextChange: ((_ title: String?, _ directory: String?) -> Void)? = nil
    ) {
        self.session = session
        self.ownsSessionLifecycle = ownsSessionLifecycle
        self.showsConnectionOrnament = showsConnectionOrnament
        self.isTerminalActive = isTerminalActive
        self.showsMacPaneChrome = showsMacPaneChrome
        self.externalFindRequest = externalFindRequest
        self.onNewTerminalTab = onNewTerminalTab
        self.onOpenTerminal = onOpenTerminal
        self.onSessionRequestedClose = onSessionRequestedClose
        self.onSessionEndedCleanly = onSessionEndedCleanly
        self.onTerminalContextChange = onTerminalContextChange
        _terminalHostModel = ObservedObject(wrappedValue: session.terminalHostModel)
    }
    
    var body: some View {
        terminalWindowIdentity
            // The terminal in front, offered on your other devices (D72): Continue opens the same
            // machine's terminal there. Only the focused pane of a window offers itself.
            .glassHandoff(endpoint: isTerminalActive ? session.server.id : nil, title: session.server.name,
                          tmuxSession: session.tmuxSessionName)
            // The title arrives by callback rather than a published change, so a program
            // animating it does not re-render this window (2026-10-07).
            .onChange(of: terminalHostModel.currentDirectory, initial: true) { _, directory in
                onTerminalContextChange?(terminalHostModel.terminalTitle, directory)
            }
            .onAppear {
                terminalHostModel.pasteRewrite = TerminalWrappedPaste.rewrite(settings: settingsManager)
                guard let onTerminalContextChange else { return }
                terminalHostModel.onTerminalTitleChange = { [weak terminalHostModel] title in
                    onTerminalContextChange(title, terminalHostModel?.currentDirectory)
                }
            }
            #if os(macOS)
            // The Mac menu consumes these closure-valued focused commands; nothing else does.
            // Publishing them through the iOS TabView causes a layout update
            // loop on iOS 27. iPhone, iPad and Vision Pro use fontSizeMenu and its shortcuts.
            .focusedValue(\.terminalFontActions, isTerminalActive ? fontActions : nil)
            #endif
            .sheet(isPresented: $showingRecordings) {
                recordingsListSheet
            }
            .confirmationDialog(
                "Start Session Recording",
                isPresented: $showingRecordingConsent,
                titleVisibility: .visible
            ) {
                Button("Record Output Only") {
                    startRecording(capturesInput: false)
                }
                Button("Record Output and Keyboard Input", role: .destructive) {
                    startRecording(capturesInput: true)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Output-only is the safest default. Keyboard input may include passwords, tokens, and other secrets because remote password prompts cannot be detected reliably. This choice applies only to this recording.")
            }
    }

    @ViewBuilder
    private var terminalWindowIdentity: some View {
        #if os(macOS)
        terminalFocusTracking
            .toolbar {
                macTerminalToolbar
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) {
                updateMacFullScreenState(from: $0, isFullScreen: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) {
                updateMacFullScreenState(from: $0, isFullScreen: false)
            }
        #else
        terminalFocusTracking
        #endif
    }

    private var terminalLifecycle: some View {
        terminalPresentation
            .onAppear {
                handleTerminalAppear()
            }
            .onChange(of: settingsManager.hostKeyVerificationMode) { _, _ in
                rejectPendingHostKeyChallengeInStrictMode()
            }
            .onChange(of: session.pendingHostKeyChallenge?.fingerprintSHA256) { _, _ in
                rejectPendingHostKeyChallengeInStrictMode()
                updateTerminalFocusOwnership(
                    competingControlPresented: session.pendingHostKeyChallenge != nil
                )
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && terminalCanOwnFocus {
                    terminalHostModel.focus()
                }
            }
            .onChange(of: session.closeWindowNonce) { _, _ in
                closeTerminalAfterCleanExit()
            }
            .modifier(TerminalScaling(model: terminalHostModel, scales: wantsScaling,
                                      holdsWindow: isTerminalActive, aspect: windowShapeAspect,
                                      canvas: terminalCanvasSize))
            .onDisappear {
                handleTerminalDisappear()
            }
            .onChange(of: find.isPresented) { oldValue, showing in
                handleSearchPresentationChange(oldValue, showing)
            }
    }

    private var terminalFocusTracking: some View {
        terminalLifecycle
            .onChange(of: externalFindRequest) { _, request in
                guard request.nonce > 0 else { return }
                configureFind()
                withAnimation(.easeInOut(duration: 0.2)) { find.perform(request.command) }
            }
            .onChange(of: showingTerminalSettings) { _, showing in
                updateTerminalFocusOwnership(competingControlPresented: showing)
            }
            .onChange(of: showingSnippetPicker) { _, showing in
                updateTerminalFocusOwnership(competingControlPresented: showing)
            }
            .onChange(of: showingAIAssistant) { _, showing in
                updateTerminalFocusOwnership(competingControlPresented: showing)
            }
            .onChange(of: showingRecordings) { _, showing in
                updateTerminalFocusOwnership(competingControlPresented: showing)
            }
            .onChange(of: showingRecordingConsent) { _, showing in
                updateTerminalFocusOwnership(competingControlPresented: showing)
            }
            .onChange(of: terminalHostModel.pendingPasteReview?.id) { _, requestID in
                updateTerminalFocusOwnership(competingControlPresented: requestID != nil)
            }
            .onChange(of: terminalHostModel.pendingExternalLink?.id) { _, requestID in
                updateTerminalFocusOwnership(competingControlPresented: requestID != nil)
            }
            .onChange(of: showingCloseConfirmation) { _, showing in
                updateTerminalFocusOwnership(competingControlPresented: showing)
            }
            .onChange(of: showingErrorCard) { _, showing in
                updateTerminalFocusOwnership(competingControlPresented: showing)
            }
            .onChange(of: isTerminalActive) { _, _ in
                updateTerminalFocusOwnership(competingControlPresented: !isTerminalActive)
            }
            .onChange(of: session.state) { oldState, newState in
                handleSessionStateNotification(from: oldState, to: newState)
            }
    }

    @ViewBuilder
    private var terminalSurface: some View {
        #if os(visionOS)
        // Stage 2 layering proof: the window chrome comes from the one layering state. The canvas
        // keeps its own theme painting; the window's glass behind it is the workgroup's, drawn
        // once for the whole window (`GlassSpatialWindowGlass`).
        GlassLayeredWindow(
            showTitle: visionShowsTitle,
            showControls: isTerminalActive,
            paintsTheme: false
        ) {
            terminalContent
                .padding(Self.visionCanvasPadding(showsTitle: visionShowsTitle, showsControls: isTerminalActive))
        } title: {
            movableConnectionLabel
        } controls: {
            bottomStatusBar
        }
        // Three shapes nest from Apple's corner in (owner, 2026-10-10): the window's glass, in the
        // window's own corner; the canvas an even `visionCanvasEdgeInset` inside it; the rows an
        // even `visionRowsInset` inside that.
        #elseif os(macOS)
        terminalContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        VStack(spacing: 0) {
            if !ownsSessionLifecycle && showsConnectionOrnament {
                connectionLabel
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial)
                Divider()
            }

            terminalContent
                // iOS has an opaque page behind the terminal, not spatial
                // passthrough. Match that backing to the selected terminal
                // theme so transparent dark themes never blend into white.
                .background(windowTheme.canvasBackgroundColor.color)
                .modifier(GlassWindowBackground(
                    interactive: false,
                    material: resolvedMaterial,
                    blurAmount: effectiveBlurBackground,
                    appearance: windowTheme.resolvedAppearance
                ))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Under the keyboard's accessory, and the home indicator, the terminal's colour too. With a
        // hardware keyboard the accessory stands alone at the bottom of the screen, and the strip
        // the terminal gives up to it showed the page behind: white under a black terminal
        // (2026-10-12, the iPhone Duo). Every edge, not only the bottom: folded, the Duo keeps its
        // system controls on one side, and the corner where that side's inset meets the bottom's
        // stayed white (the owner's screenshot, 2026-10-13).
        .background {
            windowTheme.canvasBackgroundColor.color.ignoresSafeArea()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // An iPhone on its side has no height to spare: Tools moves to the top bar instead.
            if !keyboardToolsShown && !isPhoneLandscape {
            bottomStatusBar
                .controlSize(.small)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                // The terminal's own colour, not the system bar's: a light grey band under a
                // dark terminal read as a separate panel (2026-10-04).
                .background(windowTheme.canvasBackgroundColor.color)
                .environment(\.colorScheme, themeColorScheme ?? systemColorScheme)
            }
        }
        .toolbar {
            if isPhoneLandscape && isTerminalActive && !keyboardToolsShown {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        bottomStatusBarContents(compact: true, inMenu: true)
                    } label: {
                        Label("Tools", systemImage: "wrench.and.screwdriver")
                    }
                    .accessibilityIdentifier("terminal-landscape-tools")
                }
            }
        }
        .onAppear { updateKeyboardTools() }
        .onDisappear { terminalHostModel.clearKeyboardTools() }
        .onChange(of: session.state) { _, _ in updateKeyboardTools() }
        .onChange(of: session.recorder?.isRecording) { _, _ in updateKeyboardTools() }
        .onChange(of: settingsManager.snippets.isEmpty) { _, _ in updateKeyboardTools() }
        .onChange(of: aiAssistant.isAvailable) { _, _ in updateKeyboardTools() }
        .onChange(of: isTerminalActive) { _, active in
            if active { updateKeyboardTools() }
            else { softwareKeyboardVisible = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            softwareKeyboardVisible = terminalHostModel.keyboardOverlapsHost(frame)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            softwareKeyboardVisible = false
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }

    private var terminalPresentation: some View {
        terminalSurface
        .sheet(isPresented: $showingTerminalSettings) {
            terminalSettingsModal
        }
        .sheet(isPresented: $showingSnippetPicker) {
            snippetPicker
        }
        .sheet(isPresented: $showingAIAssistant) {
            AIAssistantView(
                aiAssistant: aiAssistant,
                host: session.server.host,
                username: session.server.username,
                currentDirectory: aiAssistantDirectory,
                onRunCommand: { command in
                    session.sendCommand(command)
                }
            )
        }
        .sheet(item: pendingPasteReviewBinding) { request in
            TerminalPasteReviewSheet(
                request: request,
                onCancel: { terminalHostModel.resolvePendingPaste(approvedText: nil) },
                onPaste: { text in terminalHostModel.resolvePendingPaste(approvedText: text) }
            )
        }
        // D44: the first connection that finds tmux on a server asks once, for every device.
        .alert("Keep Terminals Running with tmux?", isPresented: $session.tmuxOffer) {
            Button("Turn On") { Task { await sessionManager.answerTmuxOffer(for: session, turnOn: true) } }
            Button("Not Now", role: .cancel) { Task { await sessionManager.answerTmuxOffer(for: session, turnOn: false) } }
        } message: {
            Text("\(session.server.name) has tmux. With it on, each terminal you open there runs in its own tmux session, keeps going when you disconnect, and can be picked up from Active on any device. Starts with the next terminal you open. You can change this in the server's Advanced settings.")
        }
        .alert("Close Connection?", isPresented: $showingCloseConfirmation) {
            Button("Disconnect", role: .destructive) {
                closeTerminalSession()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have an active SSH connection to \(session.server.name).")
        }
        .alert(
            session.pendingHostKeyChallenge?.reason == .changed ? "SSH Host Key Changed" : "Trust SSH Host Key?",
            isPresented: hostTrustBinding,
            presenting: session.pendingHostKeyChallenge
        ) { challenge in
            Button(
                challenge.reason == .changed ? "Trust Changed Key & Reconnect" : "Trust & Reconnect",
                role: challenge.reason == .changed ? .destructive : nil
            ) {
                guard interactiveHostKeyTrustIsAllowed else {
                    rejectPendingHostKeyChallengeInStrictMode()
                    return
                }
                trustAndReconnect(challenge)
            }
            Button("Cancel", role: .cancel) {
                session.pendingHostKeyChallenge = nil
            }
        } message: { challenge in
            Text("\(challenge.summary)\n\nAlgorithm: \(challenge.algorithm)\nFingerprint: \(challenge.fingerprintSHA256)")
        }
        .alert(
            "Open External Link?",
            isPresented: externalLinkConfirmationBinding,
            presenting: terminalHostModel.pendingExternalLink
        ) { request in
            Button(GlassModelFile.isModelLink(request.url) ? "Open in 3D" : "Open") {
                guard let url = terminalHostModel.resolvePendingExternalLink(approved: true) else { return }
                if GlassModelFile.isModelLink(url) {
                    modelLinks.open(url)
                    return
                }
                #if canImport(UIKit)
                UIApplication.shared.open(url)
                #elseif canImport(AppKit)
                NSWorkspace.shared.open(url)
                #endif
            }
            Button("Cancel", role: .cancel) {
                _ = terminalHostModel.resolvePendingExternalLink(approved: false)
            }
        } message: { request in
            let authority = request.port.map { "\(request.normalizedHost):\($0)" }
                ?? request.normalizedHost
            Text("A remote terminal link wants to open this address.\n\nHost: \(authority)\n\nExact URL:\n\(request.exactURL)")
        }
        .modifier(TerminalModelLinkPresentation(opener: modelLinks))
    }

    private func handleTerminalAppear() {
        #if DEBUG
        // Screenshots (App/GlassDemoMode.swift): This Window, over the window it changes.
        // Once the window is on screen and its tab chosen: a sheet asked for as it first appears
        // is not presented.
        if session.demoOpensSettings {
            session.demoOpensSettings = false
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                showingTerminalSettings = true
            }
        }
        #endif
        rejectPendingHostKeyChallengeInStrictMode()
        updateTerminalFocusOwnership(
            competingControlPresented: session.pendingHostKeyChallenge != nil || showingErrorCard
        )
    }

    private func handleTerminalDisappear() {
        terminalHostModel.stopFocusMaintenance()
        // SwiftUI may temporarily remove adaptive tab content during sidebar,
        // selection, size-class, and scene transitions. Session teardown is an
        // explicit close operation owned by closeTerminalSession or the parent
        // workspace; view disappearance is never lifecycle authority.
        #if os(visionOS)
        if isImmersiveFocusActive {
            Task { await dismissImmersiveSpace() }
            isImmersiveFocusActive = false
        }
        #endif
    }

    /// The bar holds the keyboard while it is open; closing it gives the terminal back. The bar
    /// itself clears the highlight, or leaves tmux's copy mode.
    private func handleSearchPresentationChange(_ oldValue: Bool, _ showing: Bool) {
        updateTerminalFocusOwnership(competingControlPresented: showing)
    }

    /// Where this terminal's finds search: tmux on the host while it is kept in tmux and
    /// connected, otherwise its own buffer. Asked again at every step.
    private func configureFind() {
        let session = session
        find.configure(model: terminalHostModel) { [weak session] in session?.tmuxFindTarget }
    }

    /// The folder this shell reported over OSC 7, when it is a path.
    private var reportedFolder: String? {
        terminalHostModel.currentDirectory.flatMap { $0.hasPrefix("/") ? $0 : nil }
    }

    /// Whether this shell's folder can be found: reported over OSC 7, or asked of tmux.
    private var canOpenWorkingFolder: Bool {
        reportedFolder != nil || session.survivesClose
    }

    /// Finds the folder this shell is in — in tmux, asked of tmux, since what was reported goes
    /// stale — and hands it to `open`.
    private func withWorkingFolder(_ open: @escaping @MainActor (String) -> Void) {
        let reported = reportedFolder
        Task {
            if let directory = await session.workingDirectory(reported: reported) { open(directory) }
        }
    }

    /// Opens a folder on this machine as an editor project, as Files' Open in Editor does. Nil
    /// where no editor is wired in, and then not offered.
    private var openFolderInEditor: (@MainActor (String) -> Void)? {
        guard let open = terminalRuntime?.openFolderAsProject else { return nil }
        let serverID = session.server.id
        return { open(serverID, $0) }
    }

    /// What a pinch and hold on the folder button offers (owner, 2026-10-09: "an Open in Editor
    /// option on pinch and hold on the folder icon").
    @ViewBuilder
    private var workingFolderActions: some View {
        Button("Open in Files", systemImage: "folder") { withWorkingFolder(openFolderHere) }
        if let openFolderInEditor {
            Button("Open in Editor", systemImage: "chevron.left.forwardslash.chevron.right") {
                withWorkingFolder(openFolderInEditor)
            }
        }
    }

    /// Opens this session's current directory in the file browser.
    ///
    /// A remote shell's directory arrives over OSC 7, so it is only known once the shell has
    /// reported one — which is why the control appears with it rather than sitting disabled.
    private func openFolderHere(_ directory: String) {
        #if os(macOS) || os(visionOS)
        openWindow(id: "sftp", value: SFTPBrowserContext(sessionID: session.id, initialPath: directory))
        #else
        iOSRouter.sftpContext = SFTPBrowserContext(sessionID: session.id, initialPath: directory)
        #endif
    }

    #if os(macOS)
    private func toggleMacFocusMode() {
        guard let window = macTerminalWindow ?? NSApp.keyWindow else { return }
        macTerminalWindow = window
        isMacFullScreen = window.styleMask.contains(.fullScreen)
        window.toggleFullScreen(nil)
    }

    private func updateMacFullScreenState(
        from notification: Notification,
        isFullScreen: Bool
    ) {
        guard let window = notification.object as? NSWindow,
              let macTerminalWindow,
              window === macTerminalWindow else { return }
        self.isMacFullScreen = isFullScreen
    }
    #endif
    
    // MARK: - Connection Label (top ornament)

    /// The terminal by the rule the Mac's tabs and Active share, as its tab says it (W11).
    private var terminalName: String { TerminalWorkgroupOpening.label(session, on: .connectionOrnament) }

    /// The machine, after the repository and branch when it is in one (W11).
    private var connectionLine: String {
        let machine = "\(session.server.username)@\(session.server.host):\(session.server.port)"
        return session.repositoryLine.map { "\($0) · \(machine)" } ?? machine
    }

    private var connectionLabel: some View {
        HStack(spacing: 8) {
            #if os(visionOS)
            Text(terminalName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(VisionTerminalStatus.color(for: session.state))
                .accessibilityValue(session.state.displayName)
            #endif
            if session.state == .reconnecting {
                ProgressView()
                    .controlSize(.small)
                Text("Reconnecting... (\(session.reconnectAttemptCount)/5)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.yellow)
                Button {
                    session.cancelReconnect()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel reconnect")
            } else {
                recordingIndicator

                #if !os(visionOS)
                Text(terminalName)
                    .font(.caption)
                    .fontWeight(.semibold)
                #endif

                Text(connectionLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        #if os(visionOS)
        .accessibilityValue(session.state.displayName)
        #endif
        .accessibilityLabel(session.state == .reconnecting
            ? "Reconnecting, attempt \(session.reconnectAttemptCount) of 5"
            : "\(terminalName), \(session.repositoryLine.map { "\($0), " } ?? "")\(session.server.username) at \(session.server.host) port \(session.server.port)")
    }

    #if os(visionOS)
    /// **The title drags** (W26): onto another terminal window, this terminal moves there, still
    /// running — the owner's "combine two independent terminal windows" from a window with no tab
    /// to drag. It is the tab here: the same `TerminalTabTransfer` a grid card carries, taken by the
    /// same drops. Let go over its own window, nothing changes (`TerminalTabMoves.arriving`). The
    /// tools menu's **Move Tab To** is the same move without a drag. The ornament looks as before:
    /// the content shape only lets the whole capsule be picked up, and the lifted copy wears the
    /// capsule's glass.
    @ViewBuilder
    private var movableConnectionLabel: some View {
        if let workgroupID, tabMoving != nil {
            connectionLabel
                .contentShape(.capsule)
                .draggable(TerminalTabTransfer(workgroupID: workgroupID, sessionID: session.id)) {
                    connectionLabel.glassBackgroundEffect(in: .capsule)
                }
                .accessibilityHint("Drag onto another terminal window to move this terminal there.")
        } else {
            connectionLabel
        }
    }
    #endif

    // MARK: - Terminal Content

    private var terminalContent: some View {
        ZStack {
            #if os(macOS)
            macTerminalCanvasBackground
            #elseif os(visionOS)
            terminalDisplayBackground
            if let tintColor = tintColor {
                Rectangle()
                    .fill(tintColor.opacity(TerminalCanvasTint.strength(canvasOpacity: effectiveWindowOpacity)))
                    .allowsHitTesting(false)
            }
            #else
            // UIKit owns the terminal text surface. Keep its canvas clear and
            // paint opacity/tint underneath so ANSI glyph colors are not composited.
            terminalDisplayBackground
            if let tintColor = tintColor {
                Rectangle()
                    .fill(tintColor.opacity(TerminalCanvasTint.strength(canvasOpacity: effectiveWindowOpacity)))
                    .allowsHitTesting(false)
            }
            #endif
            SwiftTermHostView(
                model: terminalHostModel,
                theme: swiftTermTheme,
                // The window's cursor and scrollback over the settings' (W22).
                runtimeSettings: profile.runtimeSettings,
                allowsFocusOwnership: terminalCanOwnFocus,
                onSendData: { data in
                    session.sendTerminalData(data)
                },
                onResize: { cols, rows in
                    #if os(macOS)
                    let geometry = TerminalGeometry(measuredRows: rows, columns: cols)
                    let configuredGeometry = session.currentTerminalGeometry
                    if !session.hasMeasuredTerminalGeometry,
                       geometry != configuredGeometry,
                       macInitialGeometryFitAttempts < 3 {
                        macInitialGeometryFitAttempts += 1
                        if terminalHostModel.fitMacWindowToTerminalGrid(
                            columns: configuredGeometry.columns,
                            rows: configuredGeometry.rows
                        ) {
                            // Wait for SwiftTerm to measure the resized canvas.
                            // The PTY remains on its configured fallback until
                            // renderer and window agree on the opening grid.
                            return
                        }
                    }
                    #endif
                    // SwiftTerm reports a new grid from inside UIKit's layout pass. The session keeps
                    // it; no view state is written there (W10).
                    session.updateTerminalGeometry(rows: rows, columns: cols)
                },
                onBell: { [profile = profile] in
                    guard profile.bellEnabled else { return }
                    terminalAudioManager.playBell()
                    if profile.visualBell {
                        withAnimation(.easeInOut(duration: 0.1)) { showVisualBell = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(.easeInOut(duration: 0.1)) { showVisualBell = false }
                        }
                    }
                }
            )
            .onGeometryChange(for: CGSize.self) { $0.size } action: { terminalCanvasSize = $0 }
            .background(Color.clear)
            .overlay(Color.white.opacity(showVisualBell ? 0.3 : 0).allowsHitTesting(false))
            .padding(.horizontal, terminalCanvasHorizontalPadding)
            .padding(.vertical, terminalCanvasPadding)
        }
        .clipShape(RoundedRectangle(cornerRadius: terminalCanvasCornerRadius, style: .continuous))
        .contentShape(.rect)
        #if !os(macOS)
        // Files and photos dropped from another app go up to the host, and their paths there are
        // typed (W14). SwiftUI's own drop target, so nothing UIKit is built here (rule 64). A Mac
        // pane takes its drop in the workspace, which knows a local shell from an SSH one.
        .onDrop(of: TerminalRemoteDrops.acceptedTypes + [TerminalTabTransfer.typeIdentifier],
                isTargeted: nil) { providers in
            // A terminal tab dragged here (W15) moves into this window; it is never a file to
            // upload, and where nothing takes tabs the drop is refused.
            if TerminalTabTransfer.isCarried(by: providers) {
                guard let terminalTabDrop else { return false }
                TerminalTabTransfer.load(from: providers, terminalTabDrop)
                return true
            }
            return TerminalRemoteDrops.shared.receive(providers, on: session)
        }
        #endif
        .onTapGesture {
            if terminalCanOwnFocus {
                terminalHostModel.focus()
            }
        }
        .onAppear {
            if terminalCanOwnFocus {
                terminalHostModel.focus()
            } else {
                terminalHostModel.stopFocusMaintenance()
            }
        }
        // Error detection for the AI explainer, once output has come to rest. Not per chunk of
        // output: this whole view was rebuilt for each one (W10).
        .onChange(of: session.outputSettledNonce) { _, _ in
            // Not while turned off in Settings, nor in a terminal paused from the card.
            if aiAssistant.isAvailable, settingsManager.errorSuggestions, !session.errorSuggestionsPaused {
                errorCheckTask?.cancel()
                errorCheckTask = Task { @MainActor in
                    let lines = terminalHostModel.getVisibleText(lastNLines: 10)
                    if detectErrorInTerminalOutput(lines) {
                        await aiAssistant.explainError(
                            terminalContext: lines,
                            host: session.server.host,
                            username: session.server.username
                        )
                        if aiAssistant.lastError != nil {
                            withAnimation { showingErrorCard = true }
                        }
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if find.isPresented {
                TerminalFindBar(controller: find)
                    .padding(.top, 14)
                    .padding(.horizontal, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear { configureFind() }
        .onChange(of: ObjectIdentifier(session)) { _, _ in configureFind() }
        // A bar that goes with its view would leave tmux in copy mode, with nothing to close it.
        .onDisappear { if find.isPresented { find.close() } }
        #if !os(macOS)
        .background { findKeyboardShortcut }
        #endif
        .overlay(alignment: .bottom) {
            if showingErrorCard, let errorInfo = aiAssistant.lastError {
                AIErrorCard(
                    error: errorInfo,
                    onRunFix: { fix in
                        session.sendCommand(fix)
                    },
                    onDismiss: {
                        withAnimation { showingErrorCard = false }
                    },
                    onPause: {
                        session.errorSuggestionsPaused = true
                        errorCheckTask?.cancel()
                        withAnimation { showingErrorCard = false }
                    },
                    onTurnOff: {
                        settingsManager.errorSuggestions = false
                        settingsManager.saveSettings()
                        errorCheckTask?.cancel()
                        withAnimation { showingErrorCard = false }
                    }
                )
                // Clear of tmux's status line, the bottom row of a terminal in tmux.
                .padding(.bottom, session.survivesClose ? 34 : 14)
                .padding(.horizontal, 14)
            }
        }
        // A drop's upload and what went wrong with it, in the corner, clear of tmux's status line.
        .overlay(alignment: .bottomTrailing) {
            TerminalRemoteDropStatusView(sessionID: session.id)
                .padding(.bottom, session.survivesClose ? 34 : 14)
                .padding(.horizontal, 14)
        }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 6) {
                ForEach(notificationManager.active) { notification in
                    NotificationBanner(notification: notification) {
                        notificationManager.dismiss(notification.id)
                    }
                }
            }
            .padding(14)
            .animation(.spring(), value: notificationManager.active.count)
        }
        .onAppear {
            aiAssistant.checkAvailability()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var swiftTermTheme: SwiftTermTheme {
        var theme = windowTheme.swiftTermTheme
        theme.fontSize = terminalHostModel.resolvedFontSize(defaultSize: defaultFontSize)
        return theme
    }

    /// The theme's size, or this window's, at the system's text size unless Settings says not to
    /// (`GlassSystemTextSize`). ⌘+ and ⌘− step from it, and Reset returns to it.
    private var defaultFontSize: CGFloat {
        let size = windowTheme.swiftTermTheme.fontSize
        guard settingsManager.fontFollowsSystemTextSize else { return size }
        return GlassSystemTextSize.scaled(size, for: dynamicTypeSize, within: SwiftTermHostModel.zoomRange)
    }

    private var fontActions: TerminalFontActions {
        let defaultSize = defaultFontSize
        let model = terminalHostModel
        // Under Scale (D75) the text's size is the window's: these size the window, a step at a
        // time, or back to where the text is at its font's own size. Where a window can't be sized
        // so (full screen; an iPad window made smaller) they do nothing, as a font change would show
        // nothing.
        return TerminalFontActions(
            increase: {
                if model.scaledGrid != nil {
                    model.zoomScaledWindow(by: Self.scaledZoomStep)
                } else {
                    model.adjustFontSize(by: 1, defaultSize: defaultSize)
                }
            },
            decrease: {
                if model.scaledGrid != nil {
                    model.zoomScaledWindow(by: 1 / Self.scaledZoomStep)
                } else {
                    model.adjustFontSize(by: -1, defaultSize: defaultSize)
                }
            },
            reset: {
                if model.scaledGrid != nil {
                    model.zoomScaledWindow(by: nil)
                } else {
                    model.resetFontSize()
                }
            }
        )
    }

    /// ⌘+ under Scale: about a point of text at a 10–12 point font.
    private static let scaledZoomStep: CGFloat = 1.1

    #if !os(macOS)
    private var fontSizeMenu: some View {
        Menu {
            Button("Increase Font Size", systemImage: "textformat.size.larger", action: fontActions.increase)
                .keyboardShortcut("+", modifiers: .command)
            Button("Decrease Font Size", systemImage: "textformat.size.smaller", action: fontActions.decrease)
                .keyboardShortcut("-", modifiers: .command)
            Button("Reset Font Size", systemImage: "arrow.counterclockwise", action: fontActions.reset)
                .keyboardShortcut("0", modifiers: .command)
        } label: {
            Image(systemName: "textformat.size")
        }
        // A toolbar item on Vision Pro, styled by the toolbar (W31).
        #if os(iOS)
        .buttonStyle(.borderless)
        #endif
        .disabled(!isTerminalActive)
        .accessibilityLabel("Terminal Font Size")
        .accessibilityValue("\(Int(swiftTermTheme.fontSize)) points")
        .accessibilityIdentifier("terminal-font-size")
        .help("Terminal Font Size")
    }
    #endif

    private var terminalCanOwnFocus: Bool {
        isTerminalActive
            && !find.isPresented
            && !showingTerminalSettings
            && !showingCloseConfirmation
            && !showingSnippetPicker
            && !showingAIAssistant
            && !showingRecordings
            && !showingRecordingConsent
            && session.pendingHostKeyChallenge == nil
            && !showingErrorCard
            && terminalHostModel.pendingPasteReview == nil
            && terminalHostModel.pendingExternalLink == nil
    }

    private var pendingPasteReviewBinding: Binding<SwiftTermPasteReview?> {
        Binding(
            get: { terminalHostModel.pendingPasteReview },
            set: { value in
                if value == nil {
                    terminalHostModel.resolvePendingPaste(approvedText: nil)
                }
            }
        )
    }

    private var externalLinkConfirmationBinding: Binding<Bool> {
        Binding(
            get: { terminalHostModel.pendingExternalLink != nil },
            set: { isPresented in
                if !isPresented {
                    _ = terminalHostModel.resolvePendingExternalLink(approved: false)
                }
            }
        )
    }

    private func updateTerminalFocusOwnership(competingControlPresented: Bool) {
        terminalHostModel.setFocusOwnershipAllowed(
            !competingControlPresented && terminalCanOwnFocus
        )
    }

    @ViewBuilder
    private var recordingIndicator: some View {
        if let recorder = session.recorder, recorder.isRecording {
            if recorder.capturesInput {
                Label("INPUT REC", systemImage: "keyboard.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.red, in: Capsule())
                    .accessibilityLabel("Recording terminal output and keyboard input")
            } else {
                Circle()
                    .fill(.red)
                    .frame(width: 9, height: 9)
                    .accessibilityLabel("Recording terminal output only")
            }
        }
    }

    private var terminalCanvasPadding: CGFloat {
        #if os(macOS)
        4
        #elseif os(visionOS)
        Self.visionRowsInset
        #else
        10
        #endif
    }

    /// The rows' inset at the sides: on Vision Pro the same as at top and bottom, so square rows
    /// nest evenly in the canvas corner; elsewhere twice it, as before.
    private var terminalCanvasHorizontalPadding: CGFloat {
        #if os(visionOS)
        Self.visionRowsInset
        #else
        terminalCanvasPadding * 2
        #endif
    }

    /// **A Vision Pro terminal's three shapes, nested from Apple's corner in** (owner, 2026-10-10,
    /// with an annotated capture: "the radius of the window itself, our output area, and the
    /// terminal itself"; "Larger outside, smaller inside"). The window's corner is Apple's
    /// (`GlassWindowShape.spatialWindowCornerRadius`); the canvas sits `visionCanvasEdgeInset`
    /// inside the window's edge on every side, whether or not the ornaments show, so it never
    /// moves as the window gains or loses focus; its corner is concentric with the window's; and
    /// the rows sit `visionRowsInset` inside it on every side, square, concentric with that.
    static let visionCanvasEdgeInset: CGFloat = GlassWindowShape.spatialNestedCanvasInset

    /// How far the rows sit inside the canvas, on every side. The rows are square: the terminal
    /// view itself has no corner on Vision Pro (owner, 2026-10-10: "remove that radius all
    /// together").
    static let visionRowsInset: CGFloat = 12

    /// The canvas corner: continuous, like Apple's window corner, and begun where Apple's begins
    /// along each edge so the gap round it reads even (46 − 34 / 1.528 ≈ 24). The circular rule
    /// gave 12, which the owner found "too small and still uneven".
    static var visionCanvasCornerRadius: CGFloat {
        GlassWindowShape.spatialNestedCanvasCornerRadius
    }

    /// The padding inside `GlassNativeWindowFrame` that puts the canvas `visionCanvasEdgeInset`
    /// from the window's edge: the frame insets for the ornaments it shows, this makes up the rest.
    /// Shared with every plain window's canvas (`GlassWindowShape.spatialNestedCanvasPadding`).
    static func visionCanvasPadding(showsTitle: Bool, showsControls: Bool) -> EdgeInsets {
        GlassWindowShape.spatialNestedCanvasPadding(showsTitle: showsTitle, showsControls: showsControls)
    }

    /// Whether a Vision Pro terminal shows its connection title ornament.
    private var visionShowsTitle: Bool { isTerminalActive && showsConnectionOrnament }

    private var terminalCanvasCornerRadius: CGFloat {
        #if os(macOS)
        // Square. The window already has Apple's rounded glass edge and clips to it, so a second
        // rounded rectangle inset inside it reads as an extra border rather than as the canvas.
        0
        #elseif os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone ? 0 : 18
        #else
        // Concentric with the window's corner around it, and with the square rows inside it.
        Self.visionCanvasCornerRadius
        #endif
    }

    #if os(macOS)
    private var macTerminalCanvasBackground: some View {
        TerminalCanvasBackground(
            color: windowTheme.background,
            tint: tintColor,
            opacity: effectiveWindowOpacity,
            blur: effectiveBlurBackground,
            appearance: windowTheme.resolvedAppearance
        )
    }
    #endif

    private func startRecording(capturesInput: Bool) {
        if session.recorder == nil {
            session.recorder = SessionRecorder()
        }
        session.recorder?.start(
            sessionID: session.id,
            serverName: session.server.name,
            host: session.server.host,
            width: session.currentTerminalGeometry.columns,
            height: session.currentTerminalGeometry.rows,
            capturesInput: capturesInput
        )

        guard session.recorder?.isRecording == true else {
            notificationManager.post(
                icon: "exclamationmark.triangle.fill",
                title: "Recording failed",
                message: session.recorder?.lastError,
                style: .error
            )
            return
        }
        notificationManager.post(
            icon: capturesInput ? "keyboard.fill" : "record.circle",
            title: capturesInput ? "Recording input and output" : "Recording output only",
            message: capturesInput ? "Keyboard input may contain secrets." : nil,
            style: capturesInput ? .warning : .info
        )
    }

    @ViewBuilder
    private var terminalDisplayBackground: some View {
        // Opacity is deliberately separate from the window's blur layer.
        // Zero leaves the terminal canvas completely unpainted.
        let bg = windowTheme.canvasBackgroundColor

        Rectangle()
            .fill(bg.color)
            .opacity(effectiveWindowOpacity)
    }

    // MARK: - The window's settings (W20, W22)

    /// Settings ▸ This Window edits the window's settings, read live from whatever holds them; nil
    /// when this terminal is in no window that keeps any, and This Window is then not offered.
    private var windowSettingsBinding: Binding<GlassWindowOverrides>? {
        #if os(macOS)
        guard let macWindow else { return nil }
        return Binding(get: { macWindow.windowSettings }, set: { macWindow.setWindowSettings($0) })
        #else
        guard let workgroupID else { return nil }
        let manager = sessionManager
        return Binding(get: { manager.workgroup(for: workgroupID)?.windowSettings ?? GlassWindowOverrides() },
                       set: { manager.setWindowSettings($0, forWorkgroup: workgroupID) })
        #endif
    }

    /// Whether this terminal keeps its rows and columns and scales its text to the window (D75).
    /// On a Mac, only once the window has been fitted to Settings' initial size, so that is the
    /// grid a terminal opened under Scale keeps.
    private var wantsScaling: Bool {
        guard TerminalResizeBehavior.isOffered, profile.whenResized == .scale else { return false }
        #if os(macOS)
        return session.hasMeasuredTerminalGeometry
        #else
        return true
        #endif
    }

    /// The shape the window keeps under Scale: the kept grid's at the terminal's font. Not while a
    /// Mac window is split, where each pane scales into its own part.
    private var windowShapeAspect: Double? {
        #if os(macOS)
        guard !showsMacPaneChrome else { return nil }
        #endif
        return terminalHostModel.scaledGrid?.aspect
    }

    /// The window's bar's Scale Text, which sets This Window's When Resized; nil where this
    /// terminal is in no window that keeps settings.
    private var scalesBinding: Binding<Bool>? {
        guard TerminalResizeBehavior.isOffered, let windowSettingsBinding else { return nil }
        return Binding(
            get: { profile.whenResized == .scale },
            set: { scales in
                windowSettingsBinding.wrappedValue[TerminalWindowSettings.whenResized] =
                    (scales ? TerminalResizeBehavior.scale : .changeGrid).rawValue
            })
    }

    /// What this terminal draws and behaves with: its window's settings over the terminal
    /// settings (`\.glassWindowOverrides`, set at the window's root).
    private var profile: TerminalWindowProfile {
        TerminalWindowProfile.resolved(windowSettings, settings: settingsManager)
    }

    /// The window's theme, with its font, else the settings'.
    private var windowTheme: TerminalTheme { profile.theme }

    private var look: TerminalLook { profile.look }

    private var tintColor: Color? { look.tintColor }

    private var effectiveWindowOpacity: Double { look.opacity }

    private var effectiveBlurBackground: Double { look.blur }

    private var resolvedMaterial: Material { look.material }

    private func duplicateSession() {
        Task {
            do {
                let launch = try await sessionManager.duplicateAuthorizedSession(
                    from: session,
                    settingsManager: settingsManager,
                    initialTerminalPresentation: { pendingSession in
                        presentDuplicatedTerminal(pendingSession)
                    }
                )
                if launch.session.state == .connected {
                    if !launch.session.didRequestInitialTerminalPresentation {
                        presentDuplicatedTerminal(launch.session)
                    }
                } else if let challenge = launch.session.pendingHostKeyChallenge {
                    if interactiveHostKeyTrustIsAllowed {
                        // The new window owns the exact trust prompt and reconnect
                        // lifecycle for its per-connection challenge.
                        presentDuplicatedTerminal(launch.session)
                    } else {
                        notificationManager.post(
                            icon: "lock.shield",
                            title: "Duplicate Blocked",
                            message: strictHostKeyFailureMessage(for: challenge),
                            style: .error
                        )
                        launch.session.pendingHostKeyChallenge = nil
                        sessionManager.closeSession(launch.session)
                    }
                } else if case .error(let message) = launch.session.state {
                    guard !launch.session.didRequestInitialTerminalPresentation else { return }
                    notificationManager.post(
                        icon: "exclamationmark.triangle",
                        title: "Duplicate Failed",
                        message: message,
                        style: .error
                    )
                    sessionManager.closeSession(launch.session)
                }
            } catch {
                notificationManager.post(
                    icon: "exclamationmark.triangle",
                    title: "Duplicate Failed",
                    message: error.localizedDescription,
                    style: .error
                )
            }
        }
    }

    private func presentDuplicatedTerminal(_ duplicatedSession: TerminalSession) {
        #if os(visionOS)
        // A new window with this one's look (W20), as Move Tab to New Window keeps it.
        let workgroupID = sessionManager.createWorkgroup(
            name: duplicatedSession.server.name,
            colorTag: duplicatedSession.server.colorTag,
            windowSettings: windowSettings
        )
        guard sessionManager.appendSession(duplicatedSession, toWorkgroup: workgroupID) else {
            sessionManager.discardWorkgroupIfEmpty(workgroupID)
            sessionManager.closeSession(duplicatedSession)
            notificationManager.post(
                icon: "exclamationmark.triangle",
                title: "Duplicate Failed",
                message: "The duplicate terminal could not be added to a workgroup.",
                style: .error
            )
            return
        }
        openWindow(id: "terminal", value: workgroupID)
        #elseif os(iOS)
        let existingWorkgroupID = iOSRouter.terminalWorkgroupID
        let workgroupID = existingWorkgroupID ?? sessionManager.createWorkgroup(
            name: duplicatedSession.server.name,
            colorTag: duplicatedSession.server.colorTag,
            windowSettings: windowSettings
        )
        guard sessionManager.appendSession(duplicatedSession, toWorkgroup: workgroupID) else {
            if existingWorkgroupID == nil {
                sessionManager.discardWorkgroupIfEmpty(workgroupID)
            }
            sessionManager.closeSession(duplicatedSession)
            notificationManager.post(
                icon: "exclamationmark.triangle",
                title: "Duplicate Failed",
                message: "The duplicate terminal could not be added to a workgroup.",
                style: .error
            )
            return
        }
        iOSRouter.showTerminal(workgroupID: workgroupID)
        #else
        var request = MacLiveSessionWorkspaceRouter.launchRequest(
            for: duplicatedSession,
            sessionManager: sessionManager
        )
        // A new window with this one's look (W20), as Move Tab to New Window keeps it.
        request.windowSettings = windowSettings
        openWindow(id: "workspace", value: request)
        #endif
    }

    private var hostTrustBinding: Binding<Bool> {
        Binding(
            get: { interactiveHostKeyTrustIsAllowed && session.pendingHostKeyChallenge != nil },
            set: { isPresented in
                if !isPresented {
                    if interactiveHostKeyTrustIsAllowed {
                        session.pendingHostKeyChallenge = nil
                    } else {
                        rejectPendingHostKeyChallengeInStrictMode()
                    }
                }
            }
        )
    }

    private var interactiveHostKeyTrustIsAllowed: Bool {
        settingsManager.hostKeyVerificationMode == HostKeyVerificationMode.ask.rawValue
    }

    private func strictHostKeyFailureMessage(for challenge: HostKeyTrustChallenge) -> String {
        let reason = challenge.reason == .changed
            ? "the presented key does not match the saved key"
            : "the presented key has not been saved"
        return "Strict host-key verification blocked the connection to \(challenge.host):\(challenge.port) because \(reason). No trust decision was recorded."
    }

    private func rejectPendingHostKeyChallengeInStrictMode() {
        guard !interactiveHostKeyTrustIsAllowed,
              let challenge = session.pendingHostKeyChallenge else { return }
        session.pendingHostKeyChallenge = nil
        notificationManager.post(
            icon: "lock.shield",
            title: "Host Key Rejected",
            message: strictHostKeyFailureMessage(for: challenge),
            style: .error
        )
    }

    private func trustAndReconnect(_ challenge: HostKeyTrustChallenge) {
        guard interactiveHostKeyTrustIsAllowed else {
            rejectPendingHostKeyChallengeInStrictMode()
            return
        }
        // The trust decision now includes a catalog write. The error handling below is unchanged:
        // it still posts the same notification, one turn of the run loop later.
        Task { @MainActor in
        do {
            try await sessionManager.trustHostKey(challenge, for: session)
            session.pendingHostKeyChallenge = nil
            reconnectSession()
        } catch {
            notificationManager.post(
                icon: "exclamationmark.triangle",
                title: "Trust Failed",
                message: error.localizedDescription,
                style: .error
            )
        }
        }
    }

    private func closeTerminalSession() {
        if ownsSessionLifecycle {
            sessionManager.closeSession(session)
            dismiss()
        } else if let onSessionRequestedClose {
            onSessionRequestedClose()
        } else {
            sessionManager.closeSession(session)
        }
    }

    private func closeTerminalAfterCleanExit() {
        if ownsSessionLifecycle {
            closeTerminalSession()
        } else if let onSessionEndedCleanly {
            onSessionEndedCleanly()
        } else {
            closeTerminalSession()
        }
    }

    private func reconnectSession() {
        session.cancelReconnect()
        Task {
            do {
                try await sessionManager.reconnect(session, settingsManager: settingsManager)
            } catch {
                notificationManager.post(
                    icon: "exclamationmark.triangle",
                    title: "Reconnect Failed",
                    message: error.localizedDescription,
                    style: .error
                )
            }
        }
    }

    private func openTerminalSettings() {
        showingTerminalSettings = true
    }

    private var footerNewTerminalButton: some View {
        Button {
            openNewTerminalFromFooter()
        } label: {
            Image(systemName: "plus")
        }
        #if os(iOS)
        .buttonStyle(.borderless)
        #endif
        .accessibilityIdentifier("terminal-footer-new-tab")
        .accessibilityLabel(newTerminalAccessibilityLabel)
        .help(newTerminalAccessibilityLabel)
    }

    private func openNewTerminalFromFooter() {
        if let onNewTerminalTab {
            onNewTerminalTab()
            return
        }
        TerminalNewTerminalRoute.platformDefault.perform(
            openConnections: { showConnections() },
            openMacTab: {
                #if os(macOS)
                openWindow(
                    id: "workspace",
                    value: MacWorkspaceLaunchRequest(startsEmpty: true)
                )
                #endif
            }
        )
    }

    private func showConnections() {
        #if os(iOS)
        iOSRouter.showConnections()
        #else
        openWindow.openConnections()
        #endif
    }


    private var newTerminalAccessibilityLabel: String {
        onNewTerminalTab == nil
            ? TerminalNewTerminalRoute.platformDefault.accessibilityLabel
            : "New Terminal Tab"
    }

    private var showsFooterWorkspaceNavigationActions: Bool {
        #if os(iOS)
        // The native workgroup toolbar owns Connections and New Tab on iPhone
        // and iPad. Standalone terminal windows retain their footer routes.
        ownsSessionLifecycle
        #else
        true
        #endif
    }

    private var showsFooterNewTerminalAction: Bool {
        #if os(macOS)
        // macOS tab creation belongs to the native workspace shell so the
        // title bar exposes exactly one New Terminal Tab action.
        false
        #else
        showsFooterWorkspaceNavigationActions
        #endif
    }

    // MARK: - Bottom Status

    #if os(macOS)
    @ToolbarContentBuilder
    private var macTerminalToolbar: some ToolbarContent {
        if isTerminalActive {
            ToolbarItemGroup(placement: .primaryAction) {
                bottomStatusBarContents(compact: true)
            }
            .glassKeepVisibleWhenCompact()
        }
    }
    #endif

    private var bottomStatusBar: some View {
        #if os(iOS)
        iOSKeyboardToolsMenu
            .padding(.horizontal, 12)
        #elseif os(macOS)
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                bottomStatusBarContents(compact: false)
            }
            HStack(spacing: 6) {
                bottomStatusBarContents(compact: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        #else
        // Vision Pro: the items themselves, with no stack, spacing or padding of their own. They
        // are Apple's toolbar ornament (`GlassNativeWindowFrame`), which sizes and spaces them and
        // draws the capsule, so the bar is the size of every other window's (W31).
        bottomStatusBarContents(compact: false)
        #endif
    }

    #if os(iOS)
    /// The terminal theme's own light or dark, so controls drawn on its colour read; nil for an
    /// automatic theme, which follows the system.
    private var themeColorScheme: ColorScheme? {
        windowTheme.resolvedAppearance.colorScheme
    }

    /// The keyboard's accessory is up, with its own Tools: the terminal's would be a second.
    /// The accessory says so itself; the keyboard's frame is the fallback.
    private var keyboardToolsShown: Bool {
        softwareKeyboardVisible || terminalHostModel.keyboardAccessoryShown
    }

    /// An iPhone on its side: compact height.
    private var isPhoneLandscape: Bool {
        verticalSizeClass == .compact && UIDevice.current.userInterfaceIdiom == .phone
    }

    private var iOSKeyboardToolsMenu: some View {
        Menu {
                bottomStatusBarContents(compact: true, inMenu: true)
            } label: {
                Label("Tools", systemImage: "wrench.and.screwdriver")
                    .font(.body)
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("terminal-keyboard-tools")
    }

    private func updateKeyboardTools() {
        terminalHostModel.setKeyboardTools(
            iOSKeyboardToolsMenu
            .frame(width: 100, height: 44)
            .environment(settingsManager)
            .environment(sessionManager)
        )
    }
    #endif

    @ViewBuilder
    private func bottomStatusBarContents(compact: Bool, inMenu: Bool = false) -> some View {
        #if os(visionOS)
        if let visionPresentation {
            VisionTerminalPresentationPicker(selection: visionPresentation)
        }
        #endif

            if showsFooterWorkspaceNavigationActions {
                Button {
                    showConnections()
                } label: {
                    Image(systemName: "server.rack")
                }
                // iPhone and iPad only: on Vision Pro these are toolbar items, and the toolbar
                // styles its own buttons (W31).
#if os(iOS)
                .buttonStyle(.borderless)
#endif
                .accessibilityLabel("Connections")
                .help("Connections")
            }

            if aiAssistant.isAvailable {
                Button {
                    Task {
                        aiAssistantDirectory = await session.workingDirectory(reported: terminalHostModel.currentDirectory)
                        showingAIAssistant = true
                    }
                } label: {
                    toolLabel("AI Assistant", image: "sparkles", inMenu: inMenu)
                }
#if os(iOS)
                .buttonStyle(.borderless)
#endif
                .accessibilityLabel("AI Assistant")
                .help("AI Assistant")
            }

            // Files left this toolbar when it became a peer row on the host detail: it is a
            // separate tool, reached from the machine, not a control of one terminal session.
            // The command palette still opens it per saved connection (`connection.sftp.*`).
            //
            // "Open Folder Here" is not that tool returning. Files browses *a machine*; this opens
            // the directory **this shell is standing in**, which is a property of the session and
            // of nothing else. The remote shell reports it over OSC 7 — the same value the AI
            // assistant already uses — so the local and remote halves of the idea behave the same:
            // Finder for a local shell, SFTP for a remote one, both arriving where the user is.
            // In tmux the reported directory is stale, so the button is always there and the
            // directory is asked of tmux when it is pressed.
            if canOpenWorkingFolder {
                Button {
                    withWorkingFolder(openFolderHere)
                } label: {
                    Image(systemName: "folder")
                }
                // Pinch and hold (right-click on a Mac): the same folder in the editor instead.
                .contextMenu { workingFolderActions }
                .accessibilityLabel("Open Folder Here")
                .accessibilityIdentifier("terminal-open-folder-here")
                .help(session.survivesClose ? "Open this shell's folder over SFTP" : "Open \(reportedFolder ?? "") over SFTP")
            }


            #if os(visionOS)
            Button {
                Task {
                    if isImmersiveFocusActive {
                        await dismissImmersiveSpace()
                        isImmersiveFocusActive = false
                    } else {
                        let result = await openImmersiveSpace(id: "focus-environment")
                        isImmersiveFocusActive = (result == .opened)
                    }
                }
            } label: {
                Image(systemName: isImmersiveFocusActive ? "moon.fill" : "moon")
            }
            .accessibilityLabel(isImmersiveFocusActive ? "Exit Focus Mode" : "Focus Mode")
            .help(isImmersiveFocusActive ? "Exit Focus Mode" : "Focus Mode")
            #elseif os(macOS)
            Button {
                toggleMacFocusMode()
            } label: {
                Image(systemName: isMacFullScreen ? "moon.fill" : "moon")
            }
            .accessibilityLabel(isMacFullScreen ? "Exit Focus Mode" : "Focus Mode")
            .help(isMacFullScreen ? "Exit Focus Mode" : "Focus Mode")
            #endif

            recordingIndicator

            #if !os(macOS)
            if inMenu {
                Menu("Font Size", systemImage: "textformat.size") {
                    Button("Increase", action: fontActions.increase)
                        .keyboardShortcut("+", modifiers: .command)
                    Button("Decrease", action: fontActions.decrease)
                        .keyboardShortcut("-", modifiers: .command)
                    Button("Reset", action: fontActions.reset)
                        .keyboardShortcut("0", modifiers: .command)
                }
                .disabled(!isTerminalActive)
            } else {
            fontSizeMenu
            }
            #endif

            if let scalesBinding {
                TerminalScaleToggle(scales: scalesBinding, inMenu: inMenu)
                    .disabled(!isTerminalActive)
            }

            if showsFooterNewTerminalAction {
                #if !os(macOS)
                if let onOpenTerminal {
                    // Held: servers ▸ their terminals, opened in this window (2026-10-15).
                    TerminalNewTabMenu(pickServer: { openNewTerminalFromFooter() }, open: onOpenTerminal) {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("terminal-footer-new-tab")
                    .accessibilityLabel(newTerminalAccessibilityLabel)
                    .help("New Terminal Tab. Hold for a server's running terminals.")
                } else {
                    footerNewTerminalButton
                }
                #else
                footerNewTerminalButton
                #endif
            }

            Menu {
                Button {
                    configureFind()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if find.isPresented { find.close() } else { find.present() }
                    }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }

                Button {
                    session.clearScreen()
                } label: {
                    Label("Clear", systemImage: "trash")
                }

                if canOpenWorkingFolder, openFolderInEditor != nil {
                    Button {
                        if let openFolderInEditor { withWorkingFolder(openFolderInEditor) }
                    } label: {
                        Label("Open Folder in Editor", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }

                #if DEBUG
                #if !os(iOS)
                Button {
                    let context = HTMLPreviewContext(
                        sessionID: session.id,
                        url: "http://localhost:8080"
                    )
                    openWindow(id: "html-preview", value: context)
                } label: {
                    Label("HTML Preview", systemImage: "safari")
                }
                #endif
                #endif

                Button {
                    showingSnippetPicker = true
                } label: {
                    Label("Snippets", systemImage: "text.page")
                }
                .disabled(session.state != .connected || settingsManager.snippets.isEmpty)

                Divider()

                if session.recorder?.isRecording == true {
                    Button {
                        let recording = session.recorder?.stop()
                        if recording?.isComplete == true {
                            notificationManager.post(icon: "stop.circle", title: "Recording saved", style: .info)
                        } else {
                            notificationManager.post(
                                icon: "exclamationmark.triangle.fill",
                                title: "Recording was not saved",
                                message: session.recorder?.lastError,
                                style: .error
                            )
                        }
                    } label: {
                        Label("Stop Recording", systemImage: "stop.circle.fill")
                    }
                } else {
                    Button {
                        showingRecordingConsent = true
                    } label: {
                        Label("Start Recording…", systemImage: "record.circle")
                    }
                    .disabled(session.state != .connected)
                }

                Button {
                    showingRecordings = true
                } label: {
                    Label("Recordings", systemImage: "list.bullet.rectangle")
                }

                Divider()

                Button {
                    duplicateSession()
                } label: {
                    Label("Duplicate Session", systemImage: "doc.on.doc")
                }

                #if os(visionOS) || os(iOS)
                // W26: a window with one terminal has no tab, and so no tab menu to move it from.
                // The tab's own moves, for this terminal, as one row (**New Window** is inside it):
                // a second row would push Settings below this menu's fold.
                if let tabMoving, let workgroupID {
                    TerminalTabMoveActions(workgroupID: workgroupID, canMoveToNewWindow: tabMoving.canMoveToNewWindow,
                                           asOneRow: true,
                                           moveToNewWindow: { tabMoving.moveToNewWindow(session) },
                                           move: { tabMoving.move(session, $0) })
                }
                #endif

                Button {
                    reconnectSession()
                } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                }
                .disabled(session.state == .connecting || session.state == .reconnecting)

                if session.state == .reconnecting {
                    Button(role: .destructive) {
                        session.cancelReconnect()
                    } label: {
                        Label("Cancel Reconnect", systemImage: "stop.circle")
                    }
                } else {
                    Button(role: .destructive) {
                        if settingsManager.confirmBeforeClosing && session.closeStopsWork {
                            showingCloseConfirmation = true
                        } else {
                            closeTerminalSession()
                        }
                    } label: {
                        // In tmux the session goes on running: this leaves it, it does not end it.
                        Label(session.survivesClose ? "Detach" : "Disconnect",
                              systemImage: session.survivesClose ? "eject" : "xmark.circle")
                    }
                    .disabled(session.state == .disconnected)
                }

                Divider()

                Button {
                    openTerminalSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            } label: {
                toolLabel("Session", image: "gearshape", inMenu: inMenu)
            }
            .menuOrder(.fixed)
#if os(iOS)
            .menuStyle(.button)
            .buttonStyle(.borderless)
#endif
            .help("Tools")
            .accessibilityLabel("Tools menu")
    }

    @ViewBuilder
    private func toolLabel(_ title: String, image: String, inMenu: Bool) -> some View {
        if inMenu { Label(title, systemImage: image) }
        else { Image(systemName: image) }
    }
    
    #if !os(macOS)
    /// ⌘F on an iPad's or Vision Pro's hardware keyboard, beside the tools menu's Search: the Mac's
    /// is in its menu bar. Only the terminal in front answers it. Not drawn, not reachable by touch.
    @ViewBuilder
    private var findKeyboardShortcut: some View {
        if isTerminalActive {
            Button("Find") {
                configureFind()
                withAnimation(.easeInOut(duration: 0.2)) { find.present() }
            }
            .keyboardShortcut("f", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
    #endif

    private var snippetPicker: some View {
        NavigationStack {
            List(settingsManager.snippets) { snippet in
                Button {
                    session.sendCommand(snippet.command)
                    settingsManager.useSnippet(snippet.id)
                    showingSnippetPicker = false
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snippet.name).font(.headline)
                        Text(snippet.command)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        if !snippet.description.isEmpty {
                            Text(snippet.description)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .navigationTitle("Snippets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingSnippetPicker = false }
                }
            }
        }
    }

    private var terminalSettingsModal: some View {
        TerminalSettingsSheet(session: session, windowSettings: windowSettingsBinding) {
            showingTerminalSettings = false
        }
    }
}

/// **Terminal Settings**, from a terminal's tools menu ▸ Settings: the window's own settings
/// (**This Window**, W20, W22), the settings every terminal shares (**All Terminals**) and, for an
/// SSH session, its port forwards. A Mac's local pane opens the same sheet without Port Forwarding
/// (W20); the app's Settings stay on ⌘,.
struct TerminalSettingsSheet: View {
    /// The SSH session it was opened from; nil for a Mac's local shell, which has no forwards.
    let session: TerminalSession?
    /// The window's own settings, when the terminal is in a window that keeps them.
    let windowSettings: Binding<GlassWindowOverrides>?
    let done: () -> Void

    @Environment(SettingsManager.self) private var settingsManager
    /// Each opening starts on This Window when the terminal's window keeps settings, else on All
    /// Terminals.
    @State private var tab: TerminalSettingsModalTab

    init(session: TerminalSession?, windowSettings: Binding<GlassWindowOverrides>?, done: @escaping () -> Void) {
        self.session = session
        self.windowSettings = windowSettings
        self.done = done
        _tab = State(initialValue: Self.firstTab(hasWindowSettings: windowSettings != nil))
    }

    static func firstTab(hasWindowSettings: Bool) -> TerminalSettingsModalTab {
        hasWindowSettings ? .overrides : .terminal
    }

    var body: some View {
        // Laid out as every window's Settings sheet is (W27): title, Done, one size.
        GlassSettingsSheet("Terminal Settings", doneIdentifier: "terminal-settings-done", done: done) {
            Group {
            #if os(iOS)
            List {
                if UIDevice.current.userInterfaceIdiom == .pad, let windowSettings {
                    NavigationLink("This Window") {
                        TerminalOverridesSettingsView(settings: windowSettings)
                            .environment(settingsManager)
                            .navigationTitle("This Window")
                    }
                }
                NavigationLink("All Terminals") {
                    TerminalSettingsView()
                        .environment(settingsManager)
                        .navigationTitle("All Terminals")
                }
                if let session {
                    NavigationLink("Port Forwarding") {
                        TerminalPortForwardingSettingsView(session: session)
                            .navigationTitle("Port Forwarding")
                    }
                }
            }
            #else
            GlassSettingsSections(
                selection: $tab,
                options: TerminalSettingsModalTab.offered(hasSession: session != nil,
                                                          hasWindowSettings: windowSettings != nil),
                title: { $0.title },
                pickerIdentifier: "terminal-settings-section-picker"
            ) { tab in
                Group {
                    switch tab {
                    case .terminal:
                        TerminalSettingsView()
                            .environment(settingsManager)
                    case .overrides:
                        if let windowSettings {
                            TerminalOverridesSettingsView(settings: windowSettings)
                                .environment(settingsManager)
                        }
                    case .portForwarding:
                        if let session {
                            TerminalPortForwardingSettingsView(session: session)
                        }
                    }
                }
            }
            #endif
            }
        }
    }
}

/// The sections of a terminal's Settings, the window's own first. Named for what they change: the
/// owner, on the Vision Pro, changed transparency and tint on the first section, then called
/// "Terminal", saw every window change, and found no window-level control (2026-10-10).
enum TerminalSettingsModalTab: String, CaseIterable, Hashable {
    case overrides
    case terminal
    case portForwarding

    var title: String {
        switch self {
        case .overrides: "This Window"
        case .terminal: "All Terminals"
        case .portForwarding: "Port Forwarding"
        }
    }

    /// The sections a terminal's Settings shows (W20): This Window when its window keeps settings,
    /// Port Forwarding for an SSH session — never for a Mac's local shell.
    static func offered(hasSession: Bool, hasWindowSettings: Bool) -> [Self] {
        allCases.filter { tab in
            switch tab {
            case .terminal: true
            case .overrides: hasWindowSettings
            case .portForwarding: hasSession
            }
        }
    }
}

struct TerminalPortForwardingSettingsView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Bindable var session: TerminalSession
    @State private var showingAddForward = false

    private var portForwards: [PortForward] {
        sessionManager.portForwardManager.forwards(for: session.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Port Forwards")
                    .font(.headline)
                Spacer()
                Button {
                    showingAddForward = true
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if portForwards.isEmpty {
                ContentUnavailableView {
                    Label("No Port Forwards", systemImage: "arrow.forward.square")
                } description: {
                    Text("Add a local, remote, or dynamic forward for this session.")
                }
            } else {
                List {
                    ForEach(portForwards) { forward in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(forward.type.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(forward.displayString)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                if let errorMessage = forward.errorMessage {
                                    Text(errorMessage)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }

                            Spacer()

                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { forward.isActive },
                                    set: { newValue in
                                        setForwardActive(forward.id, isActive: newValue)
                                    }
                                )
                            )
                            .labelsHidden()
                            .disabled(forward.status == .starting || forward.status == .stopping)

                            Button(role: .destructive) {
                                removeForward(forward.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .sheet(isPresented: $showingAddForward) {
            AddSessionPortForwardView { forward, socks5Username, socks5Password in
                if forward.type == .dynamic,
                   let socks5Username,
                   let socks5Password {
                    sessionManager.portForwardManager.addForward(
                        forward,
                        to: session.id,
                        socks5Username: socks5Username,
                        socks5Password: socks5Password
                    )
                } else {
                    sessionManager.portForwardManager.addForward(forward, to: session.id)
                }
            }
        }
    }

    private func setForwardActive(_ id: UUID, isActive: Bool) {
        guard let forward = portForwards.first(where: { $0.id == id }),
              forward.isActive != isActive else {
            return
        }
        sessionManager.portForwardManager.toggleForward(
            forward,
            in: session.id,
            session: session
        )
    }

    private func removeForward(_ id: UUID) {
        guard let forward = portForwards.first(where: { $0.id == id }) else { return }
        sessionManager.portForwardManager.removeForward(forward, from: session.id)
    }
}

struct AddSessionPortForwardView: View {
    let onAdd: (PortForward, String?, String?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var forwardType: PortForward.ForwardType = .local
    @State private var localPort = ""
    @State private var remoteHost = "localhost"
    @State private var remotePort = ""
    @State private var socks5Username = ""
    @State private var socks5Password = ""
    @FocusState private var isLocalPortFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Forward Type") {
                    Picker("Type", selection: $forwardType) {
                        Text("Local").tag(PortForward.ForwardType.local)
                        Text("Remote").tag(PortForward.ForwardType.remote)
                        Text("Dynamic (SOCKS)").tag(PortForward.ForwardType.dynamic)
                    }
                }

                Section("Configuration") {
                    TextField("Local Port", text: $localPort)
                        .terminalNumericInput()
                        .focused($isLocalPortFocused)

                    if forwardType != .dynamic {
                        TextField("Remote Host", text: $remoteHost)
                            .terminalTextInputDefaults()

                        TextField("Remote Port", text: $remotePort)
                            .terminalNumericInput()
                    }
                }

                if forwardType == .dynamic {
                    Section("SOCKS5 Authentication") {
                        TextField("Username", text: $socks5Username)
                            .terminalTextInputDefaults()
                        SecureField("Password", text: $socks5Password)

                        Text("Required for every local SOCKS5 client. These credentials remain only in app memory for this session and are never saved with the forward.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if forwardType == .remote {
                    Section("Remote Bind Safety") {
                        Text("Remote listeners are limited to localhost, 127.0.0.1, or ::1 so the tunnel cannot expose a local service to the server's network.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Add Port Forward")
            .onAppear { isLocalPortFocused = true }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let local = Int(localPort) else { return }
                        let remote = Int(remotePort) ?? 0
                        let forward = PortForward(
                            type: forwardType,
                            localPort: local,
                            remoteHost: forwardType == .dynamic ? "localhost" : remoteHost,
                            remotePort: forwardType == .dynamic ? 0 : remote
                        )
                        onAdd(
                            forward,
                            forwardType == .dynamic ? socks5Username : nil,
                            forwardType == .dynamic ? socks5Password : nil
                        )
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        guard let local = Int(localPort), local > 0 && local <= 65535 else { return false }
        if forwardType == .dynamic {
            return PortForwardManager.socks5Credentials(
                username: socks5Username,
                password: socks5Password
            ) != nil
        }
        guard !remoteHost.isEmpty else { return false }
        guard let remote = Int(remotePort), remote > 0 && remote <= 65535 else { return false }
        if forwardType == .remote {
            let normalizedHost = remoteHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard ["localhost", "127.0.0.1", "::1"].contains(normalizedHost) else { return false }
        }
        return true
    }
}

// MARK: - Session State Notifications

extension TerminalWindowView {
    func handleSessionStateNotification(from oldState: SessionState, to newState: SessionState) {
        switch newState {
        case .connected where oldState == .reconnecting:
            notificationManager.post(icon: "checkmark.circle.fill", title: "Reconnected", style: .success)
        case .error(let message):
            notificationManager.post(icon: "exclamationmark.triangle.fill", title: "Connection Error", message: message, style: .error)
        case .disconnected where oldState == .connected:
            notificationManager.post(icon: "xmark.circle", title: "Disconnected", style: .warning)
        default:
            break
        }
    }

    var recordingsListSheet: some View {
        NavigationStack {
            List {
                if recordings.isEmpty {
                    ContentUnavailableView("No Recordings", systemImage: "waveform", description: Text("Session recordings will appear here."))
                } else {
                    ForEach(recordings) { recording in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(recording.serverName)
                                    .font(.headline)
                                if !recording.isComplete {
                                    Label("Interrupted", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Color.orange.opacity(0.15), in: Capsule())
                                        .accessibilityLabel("Interrupted recording")
                                }
                                Spacer()
                                Text("\(recording.eventCount) events")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Text(recording.host)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(recording.startTime, format: .dateTime.month().day().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }

                            if let endTime = recording.endTime {
                                let duration = endTime.timeIntervalSince(recording.startTime)
                                Text("Duration: \(Int(duration / 60))m \(Int(duration.truncatingRemainder(dividingBy: 60)))s")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                recordingPendingDeletion = recording
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .onAppear {
                recordings = SessionRecorder.loadRecordings()
            }
            .navigationTitle("Recordings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingRecordings = false }
                }
            }
        }
        .alert(
            "Delete Recording?",
            isPresented: recordingDeletionBinding,
            presenting: recordingPendingDeletion
        ) { recording in
            Button("Delete", role: .destructive) {
                do {
                    try SessionRecorder.deleteRecording(recording)
                    recordings = SessionRecorder.loadRecordings()
                } catch {
                    recordingDeletionError = error.localizedDescription
                }
                recordingPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                recordingPendingDeletion = nil
            }
        } message: { recording in
            Text("Permanently delete the recording of \(recording.serverName)? This cannot be undone.")
        }
        .alert(
            "Recording Deletion Failed",
            isPresented: Binding(
                get: { recordingDeletionError != nil },
                set: { if !$0 { recordingDeletionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { recordingDeletionError = nil }
        } message: {
            Text(recordingDeletionError ?? "The recording could not be deleted.")
        }
        .frame(width: 520, height: 440)
    }

    private var recordingDeletionBinding: Binding<Bool> {
        Binding(
            get: { recordingPendingDeletion != nil },
            set: { if !$0 { recordingPendingDeletion = nil } }
        )
    }
}

// MARK: - Glass Window Background

/// Composites blur independently behind the terminal canvas's theme-color
/// opacity. Window chrome uses its own standard platform material, so a zero
/// blur amount makes only the typing surface completely transparent.
struct GlassWindowBackground: ViewModifier {
    let interactive: Bool
    let material: Material
    let blurAmount: Double
    let appearance: TerminalThemeAppearance

    func body(content: Content) -> some View {
        content.background {
            if blurAmount > 0 {
                #if os(macOS)
                MacTerminalVisualEffect(amount: blurAmount, appearance: appearance)
                #else
                appearanceMatchedMaterial
                #endif
            }
        }
    }

    #if !os(macOS)
    private var appearanceMatchedMaterial: some View {
        GlassCanvasBackdrop(
            material: material,
            blurAmount: blurAmount,
            interactive: interactive,
            colorScheme: canvasColorScheme
        )
    }

    private var canvasColorScheme: ColorScheme? {
        switch appearance {
        case .automatic: nil
        case .light: .light
        case .dark: .dark
        }
    }
    #endif
}

extension TerminalThemeAppearance {
    /// The theme's own light or dark, so controls drawn on its colour read; nil for an automatic
    /// theme, which follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .automatic: nil
        }
    }
}

#if os(macOS)
/// Reports the hosting window without reapplying window policy or installing a
/// second close observer; the scene-level reader continues to own those jobs.
struct MacTerminalWindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window { onWindow(window) }
        }
    }
}

/// Shared local/SSH terminal canvas composition. Chrome deliberately lives
/// outside this view and therefore never inherits these adjustable alpha values.
struct TerminalCanvasBackground: View {
    let color: CodableColor
    let tint: Color?
    let opacity: Double
    let blur: Double
    let appearance: TerminalThemeAppearance

    var body: some View {
        let clampedOpacity = min(1, max(0, opacity.isFinite ? opacity : 0))
        ZStack {
            if blur > 0 {
                MacTerminalVisualEffect(amount: blur, appearance: appearance)
            }
            Color(red: color.red, green: color.green, blue: color.blue)
                .opacity(clampedOpacity)
            if let tint {
                tint.opacity(TerminalCanvasTint.strength(canvasOpacity: clampedOpacity))
            }
        }
    }
}

/// Uses AppKit's behind-window compositor without changing the opacity of
/// terminal glyphs, the cursor, or any foreground chrome.
struct MacTerminalVisualEffect: NSViewRepresentable {
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let amount: Double
    var material: NSVisualEffectView.Material = .underWindowBackground
    var state: NSVisualEffectView.State = .followsWindowActiveState
    var appearance: TerminalThemeAppearance = .automatic

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(frame: .zero)
        view.blendingMode = .behindWindow
        view.material = material
        view.state = state
        view.alphaValue = clampedAmount
        view.appearance = resolvedNSAppearance
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.state = state
        nsView.alphaValue = clampedAmount
        nsView.appearance = resolvedNSAppearance
    }

    private var clampedAmount: Double {
        Self.clampedAmount(amount)
    }

    static func clampedAmount(_ amount: Double) -> Double {
        min(1, max(0, amount.isFinite ? amount : 0))
    }

    private var resolvedNSAppearance: NSAppearance? {
        guard let name = Self.resolvedAppearanceName(
            for: appearance,
            increaseContrast: colorSchemeContrast == .increased
        ) else { return nil }
        return NSAppearance(named: name)
    }

    static func resolvedAppearanceName(
        for appearance: TerminalThemeAppearance,
        increaseContrast: Bool
    ) -> NSAppearance.Name? {
        switch (appearance, increaseContrast) {
        case (.automatic, _):
            nil
        case (.light, false):
            .aqua
        case (.light, true):
            .accessibilityHighContrastAqua
        case (.dark, false):
            .darkAqua
        case (.dark, true):
            .accessibilityHighContrastDarkAqua
        }
    }
}
#endif

enum TerminalGlassTint {
    static func color(for value: String) -> Color? {
        if value == "None" || value.isEmpty { return nil }
        switch value {
        case "Blue": return .blue
        case "Purple": return .purple
        case "Green": return .green
        default: return Color(hex: value)
        }
    }
}

// MARK: - Glass Tint Picker

struct GlassTintPicker: View {
    @Binding var value: String

    private static let presets: [(String, Color)] = [
        ("None", .clear),
        ("#007AFF", .blue),
        ("#AF52DE", .purple),
        ("#34C759", .green),
        ("#FF9500", .orange),
        ("#FF2D55", .pink),
        ("#5AC8FA", .cyan),
        ("#FFD60A", .yellow),
    ]

    private var colorBinding: Binding<Color> {
        Binding(
            get: {
                if value == "None" || value.isEmpty { return .blue }
                return Color(hex: value) ?? .blue
            },
            set: { newColor in
                value = newColor.hexString
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                // Its name, and on This Window the ↺ back to All Terminals' tint.
                GlassSettingTitle("Glass Tint")
                Spacer()
                if value != "None" && !value.isEmpty {
                    Button("Clear") { value = "None" }
                        .font(.caption)
                }
            }

            HStack(spacing: 8) {
                ForEach(Self.presets, id: \.0) { hex, color in
                    Button {
                        value = hex
                    } label: {
                        if hex == "None" {
                            Circle()
                                .strokeBorder(.secondary, lineWidth: 1.5)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    Image(systemName: "xmark")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                        } else {
                            Circle()
                                .fill(color)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    if value == hex {
                                        Image(systemName: "checkmark")
                                            .font(.caption2.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(hex == "None" ? "No tint" : hex)
                }

                Divider().frame(height: 24)

                ColorPicker("", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("Custom tint color")
            }
        }
    }
}

// MARK: - Color Hex Helpers

extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let int = UInt64(h, radix: 16) else { return nil }
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    var hexString: String {
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int(round(r * 255))
        let gi = Int(round(g * 255))
        let bi = Int(round(b * 255))
        return String(format: "#%02X%02X%02X", ri, gi, bi)
        #elseif canImport(AppKit)
        let nsColor = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int(round(r * 255))
        let gi = Int(round(g * 255))
        let bi = Int(round(b * 255))
        return String(format: "#%02X%02X%02X", ri, gi, bi)
        #else
        return "#007AFF"
        #endif
    }
}

#Preview {
    let session = TerminalSession(server: ServerConfiguration(
        name: "Development Server",
        host: "dev.example.com",
        username: "developer"
    ))

    return TerminalWindowView(session: session)
        .environment(SessionManager())
        .environment(SettingsManager())
}

/// Shared canvas geometry for the Mac terminal surfaces (session canvas and local pane).
enum TerminalCanvasMetrics {
    /// The rounded canvas's corner radius when it shows its Mac pane chrome.
    static let macCornerRadius: CGFloat = 18
    /// Retired 2026-09-12. The canvas used to float inside a 3 pt margin of window glass with its
    /// own 18 pt corners; against Apple's own rounded glass edge that read as a second, redundant
    /// border. The canvas now fills the content area and the window's edge is the only edge.
}
