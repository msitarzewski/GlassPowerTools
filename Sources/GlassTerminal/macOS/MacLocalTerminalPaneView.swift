#if os(macOS)
#if os(macOS)
import AppKit
import GlassTerminalEmulator
import SwiftUI
import GlassEditorCore
import GlassLayers
import GlassShell

struct MacLocalTerminalPaneView: View {
    let runtime: SwiftTermLocalProcessRuntime
    let recorder: SessionRecorder
    let workspaceID: UUID
    var shellOverride: String? = nil
    var directoryOverride: String? = nil
    /// D47: the tmux session this pane runs in, or nil for a plain shell.
    var tmuxSession: String? = nil
    let isFocused: Bool
    let showsPaneChrome: Bool
    /// Find, Find Next and Find Previous from the menu bar, for this pane.
    let findRequest: TerminalFindRequest
    let claimStartupCommand: () -> TerminalStartupCommandTicket?
    let onFocus: () -> Void
    let onDisconnect: () -> Void
    let onProcessStatusChange: (String?) -> Void
    /// The shell's title and directory, as they change — they name the tab (2026-10-07).
    var onContextChange: (_ title: String?, _ directory: String?) -> Void = { _, _ in }

    @Environment(SettingsManager.self) private var settingsManager
    /// Present whenever this pane is inside the app's workspace scene. Used only to answer the
    /// shell when it asked for this local shell by name (D8); nil in previews and tests.
    @Environment(GlassTerminalRuntime.self) private var terminalRuntime: GlassTerminalRuntime?
    @Environment(\.openWindow) private var openWindow
    /// The terminal window this pane is in, whose settings Settings ▸ This Window edits (W20, W22).
    @Environment(MacWorkspaceWindowController.self) private var terminalWindow: MacWorkspaceWindowController?
    /// That window's settings, which this pane draws and behaves with.
    @Environment(\.glassWindowOverrides) private var windowSettings
    @ObservedObject var hostModel: SwiftTermHostModel
    @ObservedObject var processState: SwiftTermLocalProcessState
    @State private var aiAssistant = AIAssistant()
    @State private var localSessionID = UUID()
    @State private var find = TerminalFindController()
    /// A link to a 3D model, opened in 3D here (D78).
    @State private var modelLinks = TerminalModelLinkOpener()
    @State private var showingAIAssistant = false
    @State private var aiAssistantDirectory: String?
    /// Why Open Folder Here did not open a folder, while that is shown.
    @State private var folderProblem: MacLocalShellFolder.Problem?
    @State private var showingSnippets = false
    @State private var showingRecordings = false
    @State private var showingRecordingConsent = false
    @State private var showingTerminalSettings = false
    @State private var showingDisconnectConfirmation = false
    @State private var recordingError: String?
    @State private var terminalColumns = 120
    @State private var terminalRows = 40
    @State private var localTerminalWindow: NSWindow?
    /// One outcome per pane: `reportLocalShell` answers the oldest waiting request, so a second
    /// call from the same pane would steal another request's answer.
    @State private var didReportLocalShell = false
    @State private var isLocalFullScreen = false
    @State private var showVisualBell = false
    /// The terminal's own area, for Scale's window shape (D75).
    @State private var terminalCanvasSize = CGSize.zero
    /// The terminal has measured its grid, so Scale keeps a real one, not the 120 × 40 it starts at.
    @State private var hasMeasuredGrid = false

    var body: some View {
        VStack(spacing: 0) {
            SwiftTermLocalProcessHostView(
                runtime: runtime,
                configuration: localConfiguration,
                theme: terminalTheme,
                runtimeSettings: runtimeSettings,
                onOutputData: { recorder.recordOutput($0) },
                onInputData: { recorder.recordInput($0) },
                onResize: { columns, rows in
                    terminalColumns = max(20, columns)
                    terminalRows = max(8, rows)
                    hasMeasuredGrid = true
                    recorder.recordResize(width: columns, height: rows)
                },
                onBell: { [profile = profile] in
                    guard profile.bellEnabled else { return }
                    NSSound.beep()
                    if profile.visualBell {
                        withAnimation(.easeInOut(duration: 0.1)) { showVisualBell = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(.easeInOut(duration: 0.1)) { showVisualBell = false }
                        }
                    }
                },
                onProcessReady: {
                    reportLocalShellOnce(.connected)
                    guard let ticket = claimStartupCommand() else { return }
                    _ = processState.sendCommand(ticket.command)
                },
                onProcessTerminated: { exitCode in
                    if recorder.isRecording { _ = recorder.stop() }
                    MacSecureKeyboardEntry.shared.disable(for: workspaceID)
                    if MacLocalTerminalExitPolicy.shouldClose(exitCode: exitCode, tmuxSession: tmuxSession,
                                                              sessionRuns: MacLocalTerminalExitPolicy.localSessionRuns) {
                        onDisconnect()
                    }
                }
            )
            .onGeometryChange(for: CGSize.self) { $0.size } action: { terminalCanvasSize = $0 }
            .terminalTextLook(profile.lookStyle, theme: profile.theme)
            .overlay(Color.white.opacity(showVisualBell ? 0.3 : 0).allowsHitTesting(false))
            .overlay(alignment: .bottom) { if isDetachedFromTmux { detachedBanner } }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                // The window's settings over the terminal settings, as its SSH panes draw (W20, W22).
                let resolved = profile
                ZStack {
                    TerminalCanvasBackground(
                        color: resolved.theme.background,
                        tint: resolved.look.tintColor,
                        opacity: resolved.look.opacity,
                        blur: resolved.look.blur,
                        appearance: resolved.theme.resolvedAppearance
                    )
                    // What the window shows behind its text (D84).
                    TerminalBackdropView(style: resolved.lookStyle, theme: resolved.theme,
                                         activity: hostModel.outputActivity)
                }
            }
            // A framed canvas: the background is clipped to the session canvas's corner radius
            // and floats inside a margin of window glass (top stays flush under the toolbar).
            // No inset and no corner of its own: the window's glass edge is the only edge.
            .overlay {
                if let launchError = processState.launchError {
                    ContentUnavailableView(
                        "Local Shell Failed",
                        systemImage: "exclamationmark.triangle",
                        description: Text(launchError)
                    )
                    .background(.regularMaterial)
                }
            }
            .overlay(alignment: .top) {
                if find.isPresented {
                    TerminalFindBar(controller: find)
                        .padding(.top, 10)
                        .padding(.horizontal, 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            // A bar that goes with its pane would leave tmux in copy mode, with nothing to close it.
            .onDisappear { if find.isPresented { find.close() } }
        }
        .clipShape(.rect(cornerRadius: showsPaneChrome ? 18 : 0, style: .continuous))
        .overlay {
            if showsPaneChrome {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isFocused ? Color.accentColor : .clear, lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        // The shell is told the truth about the shell it asked for: the process started, or it
        // did not. Opening a window is neither, so neither is reported here (D8).
        .onAppear { if let error = processState.launchError { reportLocalShellOnce(.failed(error)) } }
        .onChange(of: processState.launchError) { _, error in
            if let error { reportLocalShellOnce(.failed(error)) }
        }
        .background {
            MacTerminalWindowAccessor { window in
                if localTerminalWindow !== window {
                    localTerminalWindow = window
                    isLocalFullScreen = window.styleMask.contains(.fullScreen)
                }
            }
        }
        .simultaneousGesture(TapGesture().onEnded {
            onFocus()
            processState.focus()
        })
        .focusedValue(\.terminalFontActions, isFocused ? fontActions : nil)
        // Scale Text (D75), as a terminal on another machine has it: the window's When Resized.
        // This view never had it, so a local tab ignored the bar's Scale Text (2026-10-20).
        .modifier(TerminalScaling(model: hostModel, scales: wantsScaling, holdsWindow: isFocused,
                                  aspect: windowShapeAspect, canvas: terminalCanvasSize))
        .toolbar {
            if isFocused {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Connections", systemImage: "server.rack") {
                        openWindow(id: "main")
                    }
                    .labelStyle(.iconOnly)
                    .help("Connections")

                    if aiAssistant.isAvailable {
                        Button("AI Assistant", systemImage: "sparkles") {
                            presentAIAssistant()
                        }
                        .labelStyle(.iconOnly)
                        .disabled(!processState.isRunning)
                        .help("AI Assistant")
                    }

                    // Click: Finder. The arrow beside it: Finder or the Editor (2026-10-20, the owner:
                    // "a regular drop down like … new terminal"), as + has New Terminal's others.
                    Menu {
                        workingFolderActions
                    } label: {
                        Label("Open Folder Here", systemImage: "folder")
                    } primaryAction: {
                        openFolderHere()
                    }
                    .labelStyle(.iconOnly)
                    .disabled(!canOpenFolder)
                    .help("Open the shell’s working directory in Finder")
                    .accessibilityIdentifier("terminal-open-folder-here")

                    Button(
                        isLocalFullScreen ? "Exit Focus Mode" : "Focus Mode",
                        systemImage: isLocalFullScreen ? "moon.fill" : "moon"
                    ) {
                        processState.toggleFullScreen()
                    }
                    .labelStyle(.iconOnly)
                    .help(isLocalFullScreen ? "Exit Focus Mode" : "Focus Mode")

                    if let scalesBinding {
                        TerminalScaleToggle(scales: scalesBinding)
                    }

                    localRecordingIndicator
                    localToolsMenu
                }
                .glassKeepVisibleWhenCompact()
            }
        }
        .onAppear {
            aiAssistant.checkAvailability()
            hostModel.pasteRewrite = TerminalWrappedPaste.rewrite(settings: settingsManager)
            hostModel.setFocusOwnershipAllowed(isFocused)
            if isFocused { processState.focus() }
        }
        .onChange(of: localProcessStatusText, initial: true) { _, status in
            onProcessStatusChange(status)
        }
        .onChange(of: [processState.terminalTitle, processState.currentDirectory], initial: true) { _, context in
            onContextChange(context[0], context[1])
        }
        .onDisappear {
            hostModel.setFocusOwnershipAllowed(false)
        }
        .onChange(of: isFocused) { _, focused in
            hostModel.setFocusOwnershipAllowed(focused)
            if focused { processState.focus() }
        }
        .onChange(of: findRequest) { _, request in
            guard request.nonce > 0 else { return }
            configureFind()
            withAnimation(.easeInOut(duration: 0.2)) { find.perform(request.command) }
        }
        // The bar holds the keyboard while it is open; closing it gives the shell back.
        .onChange(of: find.isPresented) { _, showing in
            if showing {
                hostModel.setFocusOwnershipAllowed(false)
            } else {
                restoreTerminalFocus()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) {
            updateLocalFullScreenState(from: $0, isFullScreen: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) {
            updateLocalFullScreenState(from: $0, isFullScreen: false)
        }
        .sheet(isPresented: $showingAIAssistant, onDismiss: restoreTerminalFocus) {
            AIAssistantView(
                aiAssistant: aiAssistant,
                host: "localhost",
                username: NSUserName(),
                // Not `processState.currentDirectory`: in tmux that is the client's folder.
                currentDirectory: aiAssistantDirectory,
                onRunCommand: { _ = processState.sendCommand($0) }
            )
        }
        .sheet(isPresented: $showingSnippets, onDismiss: restoreTerminalFocus) {
            localSnippetsSheet
        }
        .sheet(isPresented: $showingRecordings, onDismiss: restoreTerminalFocus) {
            MacLocalRecordingHistoryView {
                showingRecordings = false
            }
        }
        .sheet(isPresented: $showingTerminalSettings, onDismiss: restoreTerminalFocus) {
            TerminalSettingsSheet(session: nil, windowSettings: windowSettingsBinding) {
                showingTerminalSettings = false
            }
        }
        .confirmationDialog(
            "Start Local Terminal Recording",
            isPresented: $showingRecordingConsent,
            titleVisibility: .visible
        ) {
            Button("Record Output Only") { startRecording(capturesInput: false) }
            Button("Record Output and Keyboard Input", role: .destructive) {
                startRecording(capturesInput: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Output-only is the safest default. Keyboard input may include passwords, tokens, and other secrets.")
        }
        .confirmationDialog(
            "Disconnect Local Terminal?",
            isPresented: $showingDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive, action: disconnectLocalTerminal)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The local shell process will end and this terminal pane will close.")
        }
        .alert("Recording Failed", isPresented: recordingErrorPresented) {
            Button("OK", role: .cancel) { recordingError = nil }
        } message: {
            Text(recordingError ?? "The local terminal recording could not be changed.")
        }
        .alert(folderProblem?.title ?? "", isPresented: folderProblemPresented, presenting: folderProblem) { _ in
            Button("OK", role: .cancel) { folderProblem = nil }
        } message: { problem in
            Text(problem.message)
        }
        .sheet(item: pendingPasteBinding) { request in
            TerminalPasteReviewSheet(
                request: request,
                onCancel: { hostModel.resolvePendingPaste(approvedText: nil) },
                onPaste: { hostModel.resolvePendingPaste(approvedText: $0) }
            )
        }
        .alert(
            "Open External Link?",
            isPresented: externalLinkConfirmationBinding,
            presenting: hostModel.pendingExternalLink
        ) { request in
            Button(GlassModelFile.isModelLink(request.url) ? "Open in 3D" : "Open") {
                if let url = hostModel.resolvePendingExternalLink(approved: true) {
                    if GlassModelFile.isModelLink(url) {
                        modelLinks.open(url)
                    } else {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                _ = hostModel.resolvePendingExternalLink(approved: false)
            }
        } message: { request in
            let authority = request.port.map { "\(request.normalizedHost):\($0)" }
                ?? request.normalizedHost
            Text("A local terminal link wants to open this address.\n\nHost: \(authority)\n\nExact URL:\n\(request.exactURL)")
        }
        .modifier(TerminalModelLinkPresentation(opener: modelLinks))
    }

    private var localProcessStatusText: String? {
        if processState.isRunning { return nil }
        if processState.launchError != nil { return "Failed" }
        if isDetachedFromTmux { return "Detached" }
        if let exitCode = processState.exitCode { return "Exited \(exitCode)" }
        return "Starting"
    }

    /// The pane's tmux client has gone and the pane stayed: its session runs on (the exit policy
    /// closes a pane whose session ended), so the pane offers to attach to it again.
    private var isDetachedFromTmux: Bool {
        tmuxSession != nil && !processState.isRunning && processState.launchError == nil && processState.exitCode != nil
    }

    private var detachedBanner: some View {
        HStack(spacing: 12) {
            Label("Detached. This session is still running in tmux.", systemImage: "pause.circle")
            Button("Reattach") { restartLocalTerminal() }
                .accessibilityIdentifier("terminal-reattach")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var localRecordingIndicator: some View {
        if recorder.isRecording {
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

    private var localToolsMenu: some View {
        Menu {
            Button("Connections", systemImage: "server.rack") {
                openWindow(id: "main")
            }
            if aiAssistant.isAvailable {
                Button("AI Assistant", systemImage: "sparkles") {
                    presentAIAssistant()
                }
                .disabled(!processState.isRunning)
            }
            Button("Open Folder Here", systemImage: "folder") {
                openFolderHere()
            }
            .disabled(!canOpenFolder)
            Button(
                isLocalFullScreen ? "Exit Focus Mode" : "Focus Mode",
                systemImage: isLocalFullScreen ? "moon.fill" : "moon"
            ) {
                processState.toggleFullScreen()
            }
            if let scalesBinding {
                TerminalScaleToggle(scales: scalesBinding, inMenu: true)
            }

            Divider()

            Button("Search", systemImage: "magnifyingglass") { presentSearch() }
            Button("Clear", systemImage: "trash") {
                processState.clearDisplay()
                restoreTerminalFocus()
            }
            #if DEBUG
            Button("HTML Preview", systemImage: "safari") {
                openWindow(
                    id: "html-preview",
                    value: HTMLPreviewContext(
                        sessionID: localSessionID,
                        url: "http://localhost:8080"
                    )
                )
            }
            #endif
            Button("Snippets", systemImage: "text.page") { presentSnippets() }
                .disabled(!processState.isRunning || settingsManager.snippets.isEmpty)

            Divider()

            if recorder.isRecording {
                Button("Stop Recording", systemImage: "stop.circle.fill") { stopRecording() }
            } else {
                Button("Start Recording…", systemImage: "record.circle") {
                    showingRecordingConsent = true
                }
                .disabled(!processState.isRunning)
            }
            Button("Recordings", systemImage: "list.bullet.rectangle") {
                presentRecordings()
            }

            Divider()

            Button("New Local Terminal Window", systemImage: "macwindow.badge.plus") {
                openWindowInThisFolder()
            }

            if !processState.isRunning {
                Button(tmuxSession == nil ? "Restart" : "Reattach", systemImage: "arrow.clockwise") {
                    restartLocalTerminal()
                }
            }

            // In tmux this detaches: the session keeps running, and Active lists it (D47). Nothing
            // stops, so nothing to confirm — as for an SSH terminal kept in tmux (D44).
            Button(
                processState.isRunning ? (tmuxSession == nil ? "Disconnect" : "Detach") : "Close Pane",
                systemImage: "xmark.circle",
                role: tmuxSession == nil ? .destructive : nil
            ) {
                if settingsManager.confirmBeforeClosing && processState.isRunning && tmuxSession == nil {
                    showingDisconnectConfirmation = true
                } else {
                    disconnectLocalTerminal()
                }
            }

            Divider()

            // Terminal Settings, as an SSH terminal's gear opens them (W20); the app's Settings
            // window stays on ⌘, and in the app menu.
            Button("Settings", systemImage: "gearshape") { presentTerminalSettings() }
                .accessibilityIdentifier("local-terminal-settings")
        } label: {
            Image(systemName: "gearshape")
        }
        .menuOrder(.fixed)
        .help("Local Terminal Tools")
        .accessibilityLabel("Local terminal tools menu")
    }

    private var localSnippetsSheet: some View {
        NavigationStack {
            List(settingsManager.snippets) { snippet in
                Button {
                    if processState.sendCommand(snippet.command) {
                        settingsManager.useSnippet(snippet.id)
                        showingSnippets = false
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snippet.name)
                        Text(snippet.command)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Run Snippet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingSnippets = false }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private func presentSearch() {
        configureFind()
        withAnimation(.easeInOut(duration: 0.2)) { find.present() }
    }

    /// Where this pane's finds search: tmux's history when the pane runs in this Mac's tmux,
    /// otherwise the shell's own buffer.
    private func configureFind() {
        let session = tmuxSession
        // The terminal's own history, where it keeps one in tmux (`TmuxControlClient`, D83).
        find.configure(model: hostModel) {
            hostModel.keepsHistoryUnderTmux ? nil : MacLocalTmux.findTarget(session: session)
        }
    }

    private func presentAIAssistant() {
        hostModel.setFocusOwnershipAllowed(false)
        aiAssistantDirectory = nil
        showingAIAssistant = true
        // Arrives a moment later; unknown stays unknown rather than becoming the client's folder.
        Task { aiAssistantDirectory = await resolveShellFolder().path }
    }

    /// Where the shell is. In tmux the process here is the tmux client, which stays where it
    /// started, so only tmux is asked (`MacLocalShellFolder`).
    private func resolveShellFolder() async -> MacLocalShellFolder {
        await MacLocalShellFolder.resolve(
            tmuxSession: tmuxSession,
            shellIsRunning: processState.isRunning,
            processDirectory: { runtime.currentWorkingDirectory }
        )
    }

    /// New Local Terminal Window: a window whose terminal starts in the folder this shell is in
    /// (W37), asked as `resolveShellFolder` asks it.
    private func openWindowInThisFolder() {
        let shell = MacLocalTerminalStart.Source(
            tmuxSession: tmuxSession,
            shellIsRunning: processState.isRunning,
            processDirectory: { [runtime] in runtime.currentWorkingDirectory }
        )
        Task {
            let folder = await MacLocalTerminalStart.folder(for: .window, from: shell)
            openWindow(id: "workspace", value: MacLocalTerminalStart.windowRequest(in: folder))
        }
    }

    private var canOpenFolder: Bool {
        MacLocalShellFolder.isAvailable(tmuxSession: tmuxSession, shellIsRunning: processState.isRunning)
    }

    private func presentSnippets() {
        hostModel.setFocusOwnershipAllowed(false)
        showingSnippets = true
    }

    private func presentRecordings() {
        hostModel.setFocusOwnershipAllowed(false)
        showingRecordings = true
    }

    /// Terminal Settings, as an SSH terminal's gear opens it (W20): This Window, which sets this
    /// window's own settings, and All Terminals. No Port Forwarding: a local shell has no
    /// connection to forward.
    private func presentTerminalSettings() {
        hostModel.setFocusOwnershipAllowed(false)
        showingTerminalSettings = true
    }

    /// The window's settings, for This Window; nil outside a terminal window (previews).
    private var windowSettingsBinding: Binding<GlassWindowOverrides>? {
        guard let terminalWindow else { return nil }
        return Binding(get: { terminalWindow.windowSettings }, set: { terminalWindow.setWindowSettings($0) })
    }

    /// What this pane draws and behaves with: its window's settings over the terminal settings.
    private var profile: TerminalWindowProfile {
        TerminalWindowProfile.resolved(windowSettings, settings: settingsManager)
    }

    /// Answers the shell's waiting request, at most once for this pane. Does nothing when the
    /// shell asked for nothing — the toolbar's Local Terminal button and a pane split from inside
    /// the workspace both arrive here with no request outstanding.
    private func reportLocalShellOnce(_ outcome: GlassCapabilityOutcome) {
        guard !didReportLocalShell else { return }
        didReportLocalShell = true
        terminalRuntime?.reportLocalShell(outcome)
    }

    private func disconnectLocalTerminal() {
        if recorder.isRecording { _ = recorder.stop() }
        processState.terminate()
        onDisconnect()
    }

    private func restartLocalTerminal() {
        localSessionID = UUID()
        if !processState.restart(localConfiguration) {
            recordingError = processState.launchError ?? "The local shell could not be restarted."
        }
        restoreTerminalFocus()
    }

    private func updateLocalFullScreenState(
        from notification: Notification,
        isFullScreen: Bool
    ) {
        guard let window = notification.object as? NSWindow,
              window === localTerminalWindow else { return }
        isLocalFullScreen = isFullScreen
    }

    private func restoreTerminalFocus() {
        hostModel.setFocusOwnershipAllowed(true)
        if isFocused { processState.focus() }
    }

    /// The shell's folder in Finder, or a message saying why not — never Home in its place.
    private func openFolderHere() {
        Task {
            let folder = await resolveShellFolder()
            folderProblem = MacLocalShellFolder.open(folder) { NSWorkspace.shared.open($0) }
        }
    }

    /// The editor's way in for this shell's folder; nil where no editor is wired in.
    private var openFolderInEditor: (@MainActor (String) -> Void)? {
        guard let open = terminalRuntime?.openWorkingFolderInEditor else { return nil }
        return { open(nil, $0) }
    }

    /// The folder button's menu.
    @ViewBuilder
    private var workingFolderActions: some View {
        Button("Open in Finder", systemImage: "folder") { openFolderHere() }
        if let openFolderInEditor {
            Button("Open in Editor", systemImage: "chevron.left.forwardslash.chevron.right") {
                Task {
                    // The folder as Open Folder Here finds it, and its problems said the same way.
                    let folder = await resolveShellFolder()
                    folderProblem = MacLocalShellFolder.open(folder) { url in
                        openFolderInEditor(url.path(percentEncoded: false))
                        return true
                    }
                }
            }
        }
    }

    private var folderProblemPresented: Binding<Bool> {
        Binding(
            get: { folderProblem != nil },
            set: { if !$0 { folderProblem = nil } }
        )
    }

    private func startRecording(capturesInput: Bool) {
        recorder.start(
            sessionID: localSessionID,
            serverName: "Local Terminal",
            host: "localhost",
            width: terminalColumns,
            height: terminalRows,
            capturesInput: capturesInput
        )
        if !recorder.isRecording {
            recordingError = recorder.lastError ?? "The local terminal recording did not start."
        }
        restoreTerminalFocus()
    }

    private func stopRecording() {
        let recording = recorder.stop()
        if recording?.isComplete != true {
            recordingError = recorder.lastError ?? "The local terminal recording was not finalized."
        }
        restoreTerminalFocus()
    }

    private var recordingErrorPresented: Binding<Bool> {
        Binding(
            get: { recordingError != nil },
            set: { if !$0 { recordingError = nil } }
        )
    }

    private var localConfiguration: SwiftTermLocalProcessConfiguration {
        MacLocalTerminalConfiguration.resolve(
            shell: shellOverride ?? settingsManager.localShell,
            directory: directoryOverride ?? settingsManager.localWorkingDirectory,
            tmuxSession: tmuxSession
        )
    }

    private var runtimeSettings: SwiftTermRuntimeSettings {
        profile.runtimeSettings
    }

    private var terminalTheme: SwiftTermTheme {
        var theme = profile.theme.swiftTermTheme
        theme.fontSize = hostModel.resolvedFontSize(defaultSize: theme.fontSize)
        return theme
    }

    /// Under Scale (D75) the text's size is the window's, so these size the window, as on a
    /// terminal on another machine.
    private var fontActions: TerminalFontActions {
        let defaultSize = profile.theme.swiftTermTheme.fontSize
        let model = hostModel
        return TerminalFontActions(
            increase: {
                if model.scaledGrid != nil { model.zoomScaledWindow(by: TerminalScaling.zoomStep) }
                else { model.adjustFontSize(by: 1, defaultSize: defaultSize) }
            },
            decrease: {
                if model.scaledGrid != nil { model.zoomScaledWindow(by: 1 / TerminalScaling.zoomStep) }
                else { model.adjustFontSize(by: -1, defaultSize: defaultSize) }
            },
            reset: {
                if model.scaledGrid != nil { model.zoomScaledWindow(by: nil) } else { model.resetFontSize() }
            }
        )
    }

    /// Whether this terminal keeps its rows and columns and scales its text to the window (D75),
    /// once it has measured them.
    private var wantsScaling: Bool {
        TerminalResizeBehavior.isOffered && profile.whenResized == .scale && hasMeasuredGrid
    }

    /// The shape the window keeps under Scale; none while the window is split, where each pane
    /// scales into its own part.
    private var windowShapeAspect: Double? {
        showsPaneChrome ? nil : hostModel.scaledGrid?.aspect
    }

    /// The bar's Scale Text, which sets This Window's When Resized; nil outside a terminal window.
    private var scalesBinding: Binding<Bool>? {
        guard TerminalResizeBehavior.isOffered, let windowSettingsBinding else { return nil }
        return Binding(
            get: { profile.whenResized == .scale },
            set: { scales in
                windowSettingsBinding.wrappedValue[TerminalWindowSettings.whenResized] =
                    (scales ? TerminalResizeBehavior.scale : .changeGrid).rawValue
            })
    }

    private var pendingPasteBinding: Binding<SwiftTermPasteReview?> {
        Binding(
            get: { hostModel.pendingPasteReview },
            set: { if $0 == nil { hostModel.resolvePendingPaste(approvedText: nil) } }
        )
    }

    private var externalLinkConfirmationBinding: Binding<Bool> {
        Binding(
            get: { hostModel.pendingExternalLink != nil },
            set: { if !$0 { _ = hostModel.resolvePendingExternalLink(approved: false) } }
        )
    }
}

enum MacLocalTerminalConfiguration {
    /// - Parameter tmuxSession: D47 — run in this tmux session (attach, or create it) instead of
    ///   a bare shell. Without tmux on the Mac the pane falls back to the shell.
    static func resolve(shell: String?, directory: String?, tmuxSession: String? = nil,
                        tmux: String? = nil) -> SwiftTermLocalProcessConfiguration {
        let requestedShell = expandedPath(shell)
        let loginShell = getpwuid(getuid()).flatMap { entry in
            entry.pointee.pw_shell.map { String(cString: $0) }
        }
        let fallbackShell = expandedPath(loginShell)
            ?? expandedPath(ProcessInfo.processInfo.environment["SHELL"])
            ?? "/bin/zsh"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let currentDirectory = expandedPath(directory) ?? home
        let processEnvironment = environment(from: ProcessInfo.processInfo.environment)
        // A folder gone by the time the process starts — deleted since this pane opened there
        // (W37: a new terminal opens where the one in front was), or on a volume since unmounted —
        // starts it at Home rather than leaving a pane that cannot start, or a tmux session it
        // cannot reattach to. tmux does the same for a session's `-c`.
        // The server's tmux, as everything else asks it: a pane attaching with this Mac's own tmux
        // under a test's stand-in joined, or made, sessions on the owner's server (2026-10-12).
        let server = MacLocalTmux.server
        let named = tmux != nil
        if let tmuxSession, let tmux = tmux ?? server.executablePath() {
            let launch = tmuxLaunch(shell: shell, directory: directory)
            // A pane reattaching after a restart would start the server itself, in the app's
            // coalition: launchd starts it first (`MacTmuxService`). Not for a tmux the caller
            // names, which is not the server's.
            if !named { server.ensureRunning(tmux, launch.environmentVariables) }
            // A control-mode client where this Mac's tmux can have one (D83); a tmux a caller names —
            // a test's — attaches the ordinary way.
            let control = !named && MacLocalTmux.supportsControlMode(tmux)
            return SwiftTermLocalProcessConfiguration(
                executable: tmux,
                arguments: MacLocalTmux.arguments(session: tmuxSession, directory: launch.directory, control: control)
                    + launch.command,
                environment: launch.environment,
                currentDirectory: launch.directory,
                fallbackDirectory: home,
                tmuxControl: control
            )
        }
        return SwiftTermLocalProcessConfiguration(
            executable: requestedShell ?? fallbackShell,
            arguments: ["-l"],
            environment: processEnvironment,
            currentDirectory: currentDirectory,
            fallbackDirectory: home
        )
    }

    /// What a pane's tmux session starts with (D47): the pane's folder, and the environment below.
    /// tmux runs the login shell itself; a shell someone chose is the session's command, which tmux
    /// uses only when it creates the session — so the claim that creates it passes the same.
    static func tmuxLaunch(shell: String?, directory: String?) -> MacLocalTmux.Launch {
        MacLocalTmux.Launch(
            directory: expandedPath(directory) ?? FileManager.default.homeDirectoryForCurrentUser.path,
            command: expandedPath(shell).map { [$0, "-l"] } ?? [],
            environment: environment(from: ProcessInfo.processInfo.environment)
        )
    }

    /// The environment a local terminal starts with: the Mac's own, as Terminal.app passes it —
    /// SSH_AUTH_SOCK for the ssh agent, TMPDIR for the private temporary folder, and the rest —
    /// with this terminal's identity in place of whatever terminal or debugger launched the app.
    /// SwiftTerm's default passed only TERM, COLORTERM, LANG, LOGNAME, USER and HOME (2026-10-07).
    static func environment(from inherited: [String: String],
                            version: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
        -> [String] {
        var environment = inherited.filter { name, _ in
            !inheritedTerminalNames.contains(name) && !inheritedPrefixes.contains { name.hasPrefix($0) }
        }
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "GlassPowerTools"
        environment["TERM_PROGRAM_VERSION"] = version ?? "0"
        if environment["LANG"] == nil, environment["LC_ALL"] == nil {
            environment["LANG"] = "en_US.UTF-8"
        }
        return environment.filter { !$0.key.isEmpty && !$0.key.contains("=") }
            .map { "\($0.key)=\($0.value)" }.sorted()
    }

    /// Another terminal's identity, when the app was started from one: it would describe that
    /// terminal, not this one. TMUX in particular would make tmux refuse to start a local session.
    private static let inheritedTerminalNames: Set<String> = [
        "TERM", "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "TERM_SESSION_ID", "COLORTERM", "TERMINFO",
        "TMUX", "TMUX_PANE", "STY", "WINDOWID", "WT_SESSION", "INSIDE_EMACS",
        "LC_TERMINAL", "LC_TERMINAL_VERSION", "XPC_SERVICE_NAME", "NSUnbufferedIO",
    ]

    /// Loader and debugger settings Xcode gives the app, and other terminals' own variables.
    private static let inheritedPrefixes = [
        "DYLD_", "__XPC_", "OS_ACTIVITY_", "MTL_", "CA_DEBUG", "Malloc",
        "ITERM_", "KITTY_", "WEZTERM_", "GHOSTTY_", "ALACRITTY_", "VSCODE_", "ZELLIJ",
    ]

    /// A path as given: a typed setting's stray spaces trimmed and a leading `~` expanded. A
    /// folder whose name begins or ends with a space is still that folder, as a terminal reports
    /// it (W37), so an absolute path that names a folder as written is kept exactly; only one that
    /// names nothing as written is trimmed, which costs a look at the disk only then.
    static func expandedPath(_ value: String?,
                             isFolder: (String) -> Bool = MacLocalShellFolder.Lookups.folderExists) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed != value, value.hasPrefix("/"), isFolder(value) { return value }
        return trimmed.hasPrefix("~") ? (trimmed as NSString).expandingTildeInPath : trimmed
    }
}

enum MacLocalTerminalExitPolicy {
    static func shouldClose(exitCode: Int32?) -> Bool {
        // `exit` inherits the last command's status (for example a failed SSH
        // tunnel). A normally exited shell is finished even when it returns 1.
        guard let exitCode else { return false }
        return (0..<128).contains(exitCode)
    }

    /// A pane kept in tmux closes only once its session has ended. Its tmux client also exits
    /// normally when it is detached — Take Over from another device, `tmux detach` — while the
    /// session runs on, and closing the pane then dropped the tab and the record of which session
    /// it showed (2026-10-08). Unknown keeps the pane: a pane can be closed again, a lost one
    /// cannot be found.
    static func shouldClose(exitCode: Int32?, tmuxSession: String?, sessionRuns: (String) -> Bool?) -> Bool {
        guard shouldClose(exitCode: exitCode) else { return false }
        guard let tmuxSession else { return true }
        return sessionRuns(tmuxSession) == false
    }

    /// Whether this Mac's tmux runs `name`; nil when tmux cannot be asked or its answer read.
    static func localSessionRuns(_ name: String) -> Bool? {
        guard let tmux = MacLocalTmux.server.executablePath(),
              let sessions = MacLocalTmux.listing(tmux: tmux) else { return nil }
        return sessions.contains { $0.name == name }
    }
}

private struct MacLocalRecordingHistoryView: View {
    let onDone: () -> Void

    @State private var recordings: [SessionRecording] = []
    @State private var pendingDeletion: SessionRecording?
    @State private var deletionError: String?

    var body: some View {
        NavigationStack {
            List {
                if recordings.isEmpty {
                    ContentUnavailableView(
                        "No Recordings",
                        systemImage: "waveform",
                        description: Text("Local and SSH terminal recordings will appear here.")
                    )
                } else {
                    ForEach(recordings) { recording in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recording.serverName)
                                    .font(.headline)
                                Text(recording.host)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                Text(recording.startTime, format: .dateTime.month().day().hour().minute())
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("\(recording.eventCount) events")
                                    .font(.caption.monospacedDigit())
                                if let endTime = recording.endTime {
                                    let duration = endTime.timeIntervalSince(recording.startTime)
                                    Text("Duration: \(Int(duration / 60))m \(Int(duration.truncatingRemainder(dividingBy: 60)))s")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                }
                                if !recording.isComplete {
                                    Label("Interrupted", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                pendingDeletion = recording
                            }
                            .labelStyle(.iconOnly)
                        }
                    }
                }
            }
            .navigationTitle("Recording History")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
            .onAppear { recordings = SessionRecorder.loadRecordings() }
        }
        .confirmationDialog(
            "Delete Recording?",
            isPresented: deletionPresented,
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { recording in
            Button("Delete", role: .destructive) { delete(recording) }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { recording in
            Text("Permanently delete the recording of \(recording.serverName)? This cannot be undone.")
        }
        .alert("Recording Deletion Failed", isPresented: deletionErrorPresented) {
            Button("OK", role: .cancel) { deletionError = nil }
        } message: {
            Text(deletionError ?? "The recording could not be deleted.")
        }
        .frame(minWidth: 560, minHeight: 440)
    }

    private func delete(_ recording: SessionRecording) {
        do {
            try SessionRecorder.deleteRecording(recording)
            recordings = SessionRecorder.loadRecordings()
        } catch {
            deletionError = error.localizedDescription
        }
        pendingDeletion = nil
    }

    private var deletionPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private var deletionErrorPresented: Binding<Bool> {
        Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )
    }
}

#endif

#endif
