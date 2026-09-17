#if os(macOS)
import AppKit
import GlassConnectionUI
import GlassShell
import Observation
import GlassTerminalEmulator
import SwiftUI
import GlassLayers

struct MacWorkspaceSceneRoot: View {
    private let request: MacWorkspaceLaunchRequest

    init(request: MacWorkspaceLaunchRequest?) {
        self.request = request ?? MacWorkspaceLaunchRequest(startsEmpty: true)
    }

    var body: some View {
        MacWorkspaceView(request: request)
    }
}

struct MacWorkspaceView: View {
    @State private var windowController: MacWorkspaceWindowController
    @State private var columnVisibility: NavigationSplitViewVisibility
    @State private var secureKeyboardEntry = MacSecureKeyboardEntry.shared
    @State private var terminalWindow: NSWindow?
    @State private var workgroupEditorContext: WorkgroupEditorContext?
    @State private var workspaceSaveError: String?
    @State private var isConfirmingTabClose = false
    @State private var pendingWindowClose = false
    @State private var showingOverview = false
    @State private var overviewCarousel = false
    @State private var followsActivity = false
    @State private var appliedOpeningPreferences = false
    @State private var overviewControlsVisible = true
    @State private var gridCardWidth: Double?
    @State private var sidebarBeforeOverview: NavigationSplitViewVisibility?
    private let sidebarPreferenceKey: String

    @Environment(SessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.openWindow) private var openWindow

    init(request: MacWorkspaceLaunchRequest) {
        let controller = MacWorkspaceWindowController(request: request)
        let scope = controller.tabs.first?.workgroupID?.uuidString.lowercased() ?? "terminal"
        let key = UserDefaultsKeys.macWorkspaceSidebarVisibility + "." + scope
        sidebarPreferenceKey = key
        let savedVisibility = UserDefaults.standard.object(forKey: key) as? Bool
        _windowController = State(initialValue: controller)
        _columnVisibility = State(
            initialValue: (savedVisibility ?? controller.tabs.contains { $0.workgroupID != nil }) ? .all : .detailOnly
        )
    }

    var body: some View {
        let selected = windowController.selectedTab
        let identity = selected.windowIdentity(
            servers: sessionManager.serverManager.servers
        )

        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: sidebarSelection) {
            ForEach(windowController.tabs, id: \.workspaceID) { controller in
                let tabIdentity = controller.windowIdentity(
                    servers: sessionManager.serverManager.servers
                )
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tabIdentity.title)
                                .lineLimit(1)
                            if let subtitle = tabIdentity.subtitle {
                                Text(subtitle)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(
                                        controller.focusedSessionState().flatMap { state in
                                            state == .connected ? nil : state.color
                                        } ?? Color.secondary
                                    )
                                    .lineLimit(1)
                            }
                        }
                    } icon: {
                        Image(systemName: "apple.terminal")
                            .foregroundStyle(controller.workgroupColor?.color ?? .secondary)
                    }
                .tag(controller.workspaceID)
                .accessibilityLabel(tabIdentity.title)
                .accessibilityValue(tabIdentity.subtitle ?? "")
                .accessibilityIdentifier(
                    "mac-workspace-tab-\(controller.workspaceID.uuidString.lowercased())"
                )
            }
            }
                .listStyle(.sidebar)
                // A wider ceiling than 360: the sidebar carries a title and a monospaced subtitle
                // per tab, and a user with long session names could not widen past truncation.
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 520)
                // Remember where the user put the divider. AppKit persists this per autosave name,
                // and the terminal window had none — every new window reverted to the ideal width.
                // Its own namespace, so it does not share a position with the library.
                .glassLibraryColumnAutosave("com.glasspowertools.terminal.columns")
                // **AppKit's own sidebar toggle, left alone — the family standard.**
                //
                // glassdb's `databaseSidebarChrome()` removes it on every platform *except* macOS
                // (`glassdb/Constants.swift:267-273`), and glas.sh never removed it at all. Left
                // alone, AppKit puts it at the sidebar's trailing edge, keeps it out of the
                // overflow menu, and moves it with the column.
                //
                // Owning it is what kept regressing. A placed button is an ordinary toolbar item:
                // it overflows when the toolbar is crowded and renders with its title, and if it
                // sits in this column's region it disappears when the column collapses. Neither is
                // fixable by choosing a different placement, which is what several attempts here
                // tried. The sidebar column contributes no toolbar content of its own now.
        } detail: {
            MacWorkspaceTabContent(
                controller: selected,
                allowsTerminalFocus: !showingOverview,
                onNewTab: addTab,
                onCloseEmptyTab: { closeTab(selected.workspaceID) }
            )
            .id(selected.workspaceID)
            .navigationTitle(showingOverview && !overviewControlsVisible ? "" : identity.title)
            .navigationSubtitle(showingOverview && !overviewControlsVisible ? "" : identity.subtitle ?? "")
            // New Tab leads the content region, immediately after the sidebar — the placement
            // glassdb gives Add Connection (`ConnectionManagerView.swift:327-330`).
            .toolbar {
                ToolbarItem(id: "new-terminal-tab", placement: .navigation) {
                    Button("New Terminal Tab", systemImage: "plus", action: addTab)
                        .help("New Terminal Tab")
                        .disabled(!windowController.canAddTab)
                        .accessibilityIdentifier("mac-workspace-new-tab")
                }
                .glassKeepVisibleWhenCompact()
            }
            .toolbar { workspaceToolbar(selected: selected) }
            .toolbar(showingOverview && !overviewControlsVisible ? .hidden : .visible, for: .windowToolbar)
        }
        .task {
            SharedDefaults.migrateIfNeeded()
            sessionManager.preloadPersistentStateIfNeeded()
            settingsManager.loadPersistentStateIfNeeded()
            if !appliedOpeningPreferences {
                appliedOpeningPreferences = true
                if let preset = currentWorkgroupPreset {
                    followsActivity = preset.autoFocusOnActivity
                    gridCardWidth = preset.gridCardWidth
                    if preset.openingView != .tabs {
                        overviewCarousel = preset.openingView == .carousel
                        openOverview()
                    }
                }
            }
            let tabs = windowController.tabs
            for tab in tabs {
                tab.startLocalPanes(sessionManager: sessionManager, settingsManager: settingsManager) {
                    closeTab(tab.workspaceID)
                }
            }
            // Each SSH connection progresses independently, even in unvisited tabs.
            let connections = tabs.flatMap { tab in
                (tab.state.root?.panes ?? []).filter { $0.intent.kind == .ssh }.map { pane in
                    Task { @MainActor in
                        await tab.prepareSSHPaneIfNeeded(
                            pane, sessionManager: sessionManager, settingsManager: settingsManager
                        )
                    }
                }
            }
            for connection in connections { await connection.value }
        }
        .onChange(of: followsActivity) { _, enabled in
            guard var preset = currentWorkgroupPreset,
                  preset.autoFocusOnActivity != enabled else { return }
            preset.autoFocusOnActivity = enabled
            settingsManager.upsertLayoutPreset(preset)
        }
        .onChange(of: columnVisibility) { _, visibility in
            guard !showingOverview, sidebarBeforeOverview == nil,
                  visibility == .all || visibility == .detailOnly else { return }
            UserDefaults.standard.set(visibility == .all, forKey: sidebarPreferenceKey)
        }
        .onChange(of: windowController.selectedTab.workgroupID) { _, _ in
            followsActivity = currentWorkgroupPreset?.autoFocusOnActivity ?? false
            gridCardWidth = currentWorkgroupPreset?.gridCardWidth
        }
        .onChange(of: gridCardWidth) { _, width in
            guard var preset = currentWorkgroupPreset, preset.gridCardWidth != width else { return }
            preset.gridCardWidth = width
            settingsManager.upsertLayoutPreset(preset)
        }
        .onChange(of: overviewControlsVisible) { _, visible in
            terminalWindow?.toolbar?.isVisible = !showingOverview || visible
            terminalWindow?.titleVisibility = showingOverview && !visible ? .hidden : .visible
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                terminalWindow?.standardWindowButton(button)?.isHidden = showingOverview && !visible
            }
        }
        .accessibilityIdentifier("mac-workspace-tabs")
        .frame(minWidth: 720, minHeight: 460)
        .containerBackground(.clear, for: .window)
        .background {
            MacTerminalWindowReader(
                tabbingIdentifier: "sh.glas.workspace.\(windowController.windowID.uuidString)",
                onWindow: { window in
                    terminalWindow = window
                    MacWorkspacePreviewRegistry.shared.register(windowController, window: window)
                    window.title = showingOverview && !overviewControlsVisible ? "" : identity.title
                    window.subtitle = showingOverview && !overviewControlsVisible ? "" : identity.subtitle ?? ""
                    if pendingWindowClose {
                        DispatchQueue.main.async { window.close() }
                    }
                },
                onClose: {
                    MacWorkspacePreviewRegistry.shared.remove(windowController.windowID)
                    windowController.closeAllSessions(sessionManager: sessionManager)
                    for tab in windowController.tabs {
                        secureKeyboardEntry.disable(for: tab.workspaceID)
                    }
                },
                shouldConfirmClose: {
                    settingsManager.confirmBeforeClosing && !windowController.isEmpty
                },
                opensSidebarInitially: !showingOverview && columnVisibility == .all,
                overviewPresented: showingOverview
            )
        }
        // ⌘N, while a terminal workspace is focused, means a new terminal window. The shell owns
        // the one File ▸ New item and each window says what it makes (`GlassShellFileCommands`).
        .focusedSceneValue(\.glassNewItem, GlassNewItemAction(title: "New Terminal Window") {
            openWindow(id: "workspace", value: MacWorkspaceLaunchRequest())
        })
        .focusedSceneValue(
            \.macNewWorkspaceTabAction,
            MacNewWorkspaceTabAction(
                isEnabled: windowController.canAddTab,
                currentConnectionName: repeatableConnectionName,
                addTab,
                repeatingCurrentConnection: addTabRepeatingCurrentConnection
            )
        )
        .focusedSceneValue(\.macCommandCenterEntries, [
            MacCommandCenterEntry(id: "workspace.overview", title: "Terminal Overview",
                                 detail: "Browse tabs in a live grid or carousel") { openOverview() },
            MacCommandCenterEntry(id: "workspace.grid", title: "Terminal Grid",
                                 detail: "View all terminal tabs", shortcut: "⌘G") { showOverview(carousel: false) },
            MacCommandCenterEntry(id: "workspace.carousel", title: "Terminal Carousel",
                                 detail: "Browse overlapping terminal previews", shortcut: "⌥⌘G") { showOverview(carousel: true) },
            MacCommandCenterEntry(id: "workspace.activity", title: followsActivity ? "Disable Auto-focus on Activity" : "Enable Auto-focus on Activity",
                                 detail: "Follow new output in Grid or Carousel") { followsActivity.toggle() }
        ] + windowController.tabs.enumerated().map { index, tab in
            MacCommandCenterEntry(id: "workspace.tab.\(index + 1)",
                title: tab.windowIdentity(servers: sessionManager.serverManager.servers).title,
                detail: "Switch terminal workspace", shortcut: index < 9 ? "⌘\(index + 1)" : "") {
                    windowController.select(tab.workspaceID)
                    if showingOverview { closeOverview() }
                }
        })
        .focusedSceneValue(
            \.macCloseWorkspaceTabAction,
            MacCloseWorkspaceTabAction { requestCloseSelectedTab() }
        )
        .sheet(item: $workgroupEditorContext) { context in
            WorkgroupEditorView(context: context, servers: sessionManager.serverManager.servers) { preset in
                settingsManager.addLayoutPreset(preset)
            }
        }
        .allowsHitTesting(!showingOverview)
        .accessibilityHidden(showingOverview)
        .opacity(showingOverview ? 0 : 1)
        .overlay {
            if showingOverview {
                MacTerminalOverview(controller: windowController,
                                    servers: sessionManager.serverManager.servers,
                                    carousel: $overviewCarousel,
                                    followsActivity: $followsActivity,
                                    controlsVisible: $overviewControlsVisible,
                                    preferredCardWidth: $gridCardWidth,
                                    activate: { id in
                    windowController.select(id)
                    closeOverview()
                }, dismiss: closeOverview)
                .background {
                    MacTerminalVisualEffect(amount: 1, material: .underWindowBackground)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .alert("Workspace Could Not Be Saved", isPresented: Binding(
            get: { workspaceSaveError != nil },
            set: { if !$0 { workspaceSaveError = nil } }
        )) {
            Button("OK", role: .cancel) { workspaceSaveError = nil }
        } message: {
            Text(workspaceSaveError ?? "")
        }
    }

    private var currentWorkgroupPreset: LayoutPreset? {
        settingsManager.layoutPresets.first { $0.id == windowController.selectedTab.workgroupID }
    }

    private func showOverview(carousel: Bool) {
        overviewCarousel = carousel
        openOverview()
    }

    private func openOverview() {
        if !showingOverview { sidebarBeforeOverview = columnVisibility }
        columnVisibility = .detailOnly
        overviewControlsVisible = true
        for tab in windowController.tabs {
            for pane in tab.state.root?.panes ?? [] {
                tab.previewModel(for: pane.id)?.setFocusOwnershipAllowed(false)
            }
        }
        showingOverview = true
    }

    private func restoreTerminalFocus() {
        let tab = windowController.selectedTab
        if let paneID = tab.focusedPaneID {
            tab.previewModel(for: paneID)?.setFocusOwnershipAllowed(true)
        }
    }

    private func closeOverview() {
        overviewControlsVisible = true
        showingOverview = false
        if let sidebarBeforeOverview { columnVisibility = sidebarBeforeOverview }
        sidebarBeforeOverview = nil
        Task { @MainActor in
            await Task.yield()
            restoreTerminalFocus()
        }
    }


    @ToolbarContentBuilder
    private func workspaceToolbar(selected: MacWorkspaceController) -> some ToolbarContent {
            ToolbarItem(id: "terminal-overview") {
                Button("Terminal Overview", systemImage: "square.grid.2x2", action: openOverview)
                    .help("Show all terminal tabs as a grid or carousel")
                    .accessibilityIdentifier("mac-workspace-overview")
            }
            .glassKeepVisibleWhenCompact()
            ToolbarItem(id: "save-workspace") {
                Button("Save Workspace as Workgroup…", systemImage: "rectangle.stack.badge.plus") {
                    saveWorkspace()
                }
                .disabled(windowController.isEmpty)
                .help("Save this window’s tabs and split layout as a Workgroup")
                .accessibilityIdentifier("mac-workspace-save-workgroup")
            }
            .glassOverflowFirstWhenCompact()

            if windowController.canTransferSelectedTab {
                ToolbarItem(id: MacTerminalToolbarItemID.tabActions) {
                    Menu("Tab Actions", systemImage: "ellipsis.circle") {
                        Button("Move Tab to New Window", systemImage: "macwindow.badge.plus") {
                            moveSelectedTabToNewWindow()
                        }
                    }
                    .help("Tab Actions")
                }
                .glassOverflowFirstWhenCompact()
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button("New Local Pane", systemImage: "rectangle.split.2x1") {
                    selected.addPane(intent: .local, axis: .horizontal)
                }
                .disabled(!selected.canAddPane)
                .accessibilityIdentifier("mac-workspace-new-local-pane")

                // The library is where a machine is chosen, everywhere in the app. This used to
                // open a picker of its own, which meant two different answers to "which host?" —
                // one of them without the library's search, scopes, favourites or services.
                Button("Connections", systemImage: "network") {
                    openWindow(id: "main")
                }
                .accessibilityIdentifier("mac-workspace-connect-host")

                Button(
                    "Secure Keyboard Entry",
                    systemImage: secureKeyboardEntry.isEnabled(for: selected.workspaceID)
                        ? "lock.fill"
                        : "lock.open"
                ) {
                    secureKeyboardEntry.toggle(for: selected.workspaceID)
                }
                .disabled(selected.focusedPaneID == nil)
                .accessibilityIdentifier("mac-workspace-secure-keyboard-entry")
            }
            .glassOverflowFirstWhenCompact()
    }

    private func saveWorkspace() {
        do {
            let defaults = MacLocalTerminalConfiguration.resolve(
                shell: settingsManager.localShell,
                directory: settingsManager.localWorkingDirectory
            )
            let preset = try windowController.capturePreset(
                name: windowController.selectedTab.workgroupName ?? "Workgroup",
                servers: sessionManager.serverManager.servers,
                defaultLocalShell: defaults.executable,
                defaultLocalDirectory: defaults.currentDirectory ?? NSHomeDirectory(),
                sourcePresets: settingsManager.layoutPresets
            )
            // A capture is a new preset; saving does not overwrite its source.
            workgroupEditorContext = WorkgroupEditorContext(
                original: nil,
                name: preset.name,
                colorTag: preset.colorTag,
                sessionIntents: preset.sessionIntents,
                workspaceLayout: preset.workspaceLayout
            )
        } catch {
            workspaceSaveError = error.localizedDescription
        }
    }

    private var sidebarSelection: Binding<UUID?> {
        Binding(
            get: { windowController.selectedTabID },
            set: { if let id = $0 { windowController.select(id) } }
        )
    }

    private func addTab() {
        windowController.addTab()
    }

    /// What ⇧⌘T repeats: the intent the focused tab's focused pane is running.
    ///
    /// The *intent*, not the session — a pane intent already carries everything a tab needs to
    /// start the same thing again (the saved server for SSH, the shell and directory for local),
    /// and starting from it is what makes the new tab ask nothing. An empty tab has no intent,
    /// so there is nothing to repeat and the command is offered as disabled rather than guessing.
    private var repeatableIntent: MacWorkspacePaneIntent? {
        windowController.selectedTab.focusedPane?.intent
    }

    /// The machine the focused tab is on, for the menu item's title.
    private var repeatableConnectionName: String? {
        guard let intent = repeatableIntent else { return nil }
        switch intent.kind {
        case .local:
            return intent.label ?? "This Mac"
        case .ssh:
            guard let serverID = intent.serverID,
                  let server = sessionManager.serverManager.servers.first(where: { $0.id == serverID })
            else { return nil }
            return intent.label ?? server.name
        }
    }

    private func addTabRepeatingCurrentConnection() {
        guard var intent = repeatableIntent else { return }
        // Cleared deliberately: the index identifies a pane inside a *restored workgroup layout*,
        // and this tab is a new one the user asked for, not a restoration of that slot.
        intent.sourceSessionIndex = nil
        windowController.addTab(
            MacWorkspaceTabRequest(startsEmpty: false, initialPaneIntent: intent)
        )
    }

    private func closeTab(_ workspaceID: UUID) {
        let closesWindow = windowController.removeTab(
            workspaceID,
            sessionManager: sessionManager
        )
        secureKeyboardEntry.disable(for: workspaceID)
        if closesWindow {
            pendingWindowClose = true
            terminalWindow?.close()
        }
    }

    private func requestCloseSelectedTab() {
        guard !isConfirmingTabClose else { return }
        let tab = windowController.selectedTab
        guard let warning = tab.closeWarning else {
            closeTab(tab.workspaceID)
            return
        }
        guard let window = terminalWindow, window.attachedSheet == nil else { return }
        isConfirmingTabClose = true
        let alert = NSAlert()
        alert.messageText = "Close Terminal Tab?"
        alert.informativeText = warning + " The saved Workgroup will not be changed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Close Tab")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            isConfirmingTabClose = false
            if response == .alertFirstButtonReturn {
                closeTab(tab.workspaceID)
            }
        }
    }

    private func moveSelectedTabToNewWindow() {
        guard let request = windowController.transferSelectedTab() else { return }
        openWindow(id: "workspace", value: request)
    }
}

private struct WorkspaceCredentialPrompt: Identifiable {
    var id: UUID { paneID }
    let paneID: UUID
    let server: ServerConfiguration
}

private struct MacWorkspaceTabContent: View {
    private let controller: MacWorkspaceController
    private let allowsTerminalFocus: Bool
    @State private var secureKeyboardEntry = MacSecureKeyboardEntry.shared
    @State private var persistentStateReady = false
    @State private var showingPaneCloseConfirmation = false
    @State private var credentialPrompt: WorkspaceCredentialPrompt?

    @Environment(SessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.openWindow) private var openWindow

    private let onNewTab: () -> Void
    private let onCloseEmptyTab: () -> Void

    init(
        controller: MacWorkspaceController,
        allowsTerminalFocus: Bool,
        onNewTab: @escaping () -> Void,
        onCloseEmptyTab: @escaping () -> Void
    ) {
        self.controller = controller
        self.allowsTerminalFocus = allowsTerminalFocus
        self.onNewTab = onNewTab
        self.onCloseEmptyTab = onCloseEmptyTab
    }

    var body: some View {
        workspaceContent
            .frame(minHeight: 460)
            .focusedSceneValue(\.macWorkspaceActions, focusedActions)
            .sheet(isPresented: sshPickerPresented) { sshPicker }
            .sheet(item: $credentialPrompt) { prompt in
                ConnectionPasswordPromptSheet(server: prompt.server, savesPassword: true) { password in
                    guard let current = sessionManager.server(for: prompt.server.id),
                          controller.state.root?.pane(id: prompt.paneID) != nil else {
                        return "This connection or terminal pane is no longer available."
                    }
                    do {
                        try await sessionManager.serverManager.updateServerOrThrow(current, password: password)
                        controller.retryPane(prompt.paneID)
                        return nil
                    } catch {
                        return "The password could not be saved. \(error.localizedDescription)"
                    }
                }
            }
            .alert(
                "Secure Keyboard Entry",
                isPresented: secureKeyboardErrorPresented
            ) {
                Button("OK", role: .cancel) { secureKeyboardEntry.clearError() }
            } message: {
                Text(secureKeyboardEntry.lastError ?? "Secure Keyboard Entry could not be changed.")
            }
            .confirmationDialog(
                "Close Terminal Pane?",
                isPresented: $showingPaneCloseConfirmation,
                titleVisibility: .visible
            ) {
                Button("Close Pane", role: .destructive) {
                    controller.removeFocusedPane(sessionManager: sessionManager)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The terminal process or SSH session in this pane will be disconnected.")
            }
            .onAppear {
                SharedDefaults.migrateIfNeeded()
                sessionManager.preloadPersistentStateIfNeeded()
                settingsManager.loadPersistentStateIfNeeded()
                persistentStateReady = true
            }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        if let root = controller.state.root {
            GeometryReader { proxy in
                let bounds = CGRect(origin: .zero, size: proxy.size)
                let showsPaneChrome = root.panes.count > 1
                let layoutBounds = showsPaneChrome ? bounds.insetBy(dx: 8, dy: 8) : bounds
                let layout = MacWorkspaceLayout(root: root, in: layoutBounds)
                let globalOrigin = proxy.frame(in: .global).origin

                ZStack(alignment: .topLeading) {
                    ForEach(root.panes) { pane in
                        if let frame = layout.paneFrames[pane.id] {
                            paneView(pane, showsPaneChrome: showsPaneChrome)
                                .id(pane.id)
                                .frame(width: frame.width, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)
                        }
                    }

                    ForEach(layout.handles) { handle in
                        splitHandle(handle, globalOrigin: globalOrigin)
                    }
                }
            }
        } else {
            ContentUnavailableView {
                Label("New Terminal", systemImage: "apple.terminal")
            } description: {
                Text("Choose how to start this terminal tab.")
            } actions: {
                Button("Local Terminal", systemImage: "apple.terminal") {
                    controller.addPane(intent: .local, axis: .horizontal)
                }
                Button("SSH Connection", systemImage: "network") {
                    controller.requestSSHPane(axis: .horizontal)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                TerminalCanvasBackground(
                    color: settingsManager.currentTheme.background,
                    tint: TerminalGlassTint.color(for: settingsManager.glassTint),
                    opacity: settingsManager.windowOpacity,
                    blur: settingsManager.blurBackground,
                    appearance: settingsManager.currentTheme.resolvedAppearance
                )
            }
        }
    }

    @ViewBuilder
    private func paneView(_ pane: MacWorkspacePane, showsPaneChrome: Bool) -> some View {
        let isFocused = allowsTerminalFocus && controller.focusedPaneID == pane.id
        switch pane.intent.kind {
        case .local:
            if let runtime = controller.localRuntime(for: pane.id),
               let recorder = controller.recorder(for: pane.id) {
                MacLocalTerminalPaneView(
                    runtime: runtime,
                    recorder: recorder,
                    workspaceID: controller.workspaceID,
                    shellOverride: pane.intent.localShell,
                    directoryOverride: pane.intent.localDirectory,
                    isFocused: isFocused,
                    showsPaneChrome: showsPaneChrome,
                    findRequestNonce: findNonce(for: pane.id),
                    claimStartupCommand: { controller.claimStartupCommand(for: pane.id) },
                    onFocus: { controller.focus(pane.id) },
                    onDisconnect: {
                        guard !controller.isClosed else { return }
                        let closesWorkspace = controller.state.root?.panes.count == 1
                        controller.removePane(pane.id, sessionManager: sessionManager)
                        if closesWorkspace {
                            onCloseEmptyTab()
                        }
                    },
                    onProcessStatusChange: { controller.updateLocalProcessStatus($0, for: pane.id) },
                    hostModel: runtime.model,
                    processState: runtime.processState
                )
            }
        case .ssh:
            if !persistentStateReady {
                ProgressView("Loading saved hosts…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.regularMaterial, in: .rect(cornerRadius: 18))
            } else if let session = controller.session(for: pane.id) {
                TerminalWindowView(
                    session: session,
                    ownsSessionLifecycle: false,
                    isTerminalActive: isFocused,
                    showsMacPaneChrome: showsPaneChrome,
                    externalSearchRequestNonce: findNonce(for: pane.id),
                    onNewTerminalTab: onNewTab,
                    onSessionRequestedClose: {
                        guard !controller.isClosed else { return }
                        controller.disconnectSSHPane(
                            pane.id,
                            sessionManager: sessionManager
                        )
                    },
                    onSessionEndedCleanly: {
                        guard !controller.isClosed else { return }
                        let closesWorkspace = controller.completeCleanSSHExit(
                            pane.id,
                            sessionManager: sessionManager
                        )
                        if closesWorkspace {
                            onCloseEmptyTab()
                        }
                    }
                )
                .overlay {
                    if showsPaneChrome {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isFocused ? Color.accentColor : .clear, lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { controller.focus(pane.id) })
            } else {
                sshPlaceholder(for: pane)
                    .task(id: controller.error(for: pane.id)) {
                        await controller.prepareSSHPaneIfNeeded(
                            pane,
                            sessionManager: sessionManager,
                            settingsManager: settingsManager
                        )
                    }
            }
        }
    }

    private func sshPlaceholder(for pane: MacWorkspacePane) -> some View {
        Group {
            if controller.isLoading(pane.id) {
                ProgressView("Connecting…")
            } else if let error = controller.error(for: pane.id) {
                ContentUnavailableView {
                    Label("Connection Failed", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    if let failure = controller.pendingCredentialErrorsByPaneID[pane.id],
                       case .missingPassword(let server, _) = failure {
                        Button("Enter Password…") {
                            credentialPrompt = WorkspaceCredentialPrompt(paneID: pane.id, server: server)
                        }
                    }
                    Button("Retry") { controller.retryPane(pane.id) }
                    Button("Connections") { openWindow(id: "main") }
                    Button("Close Pane", role: .destructive) {
                        controller.removePane(pane.id, sessionManager: sessionManager)
                    }
                }
            } else {
                ProgressView("Preparing SSH session…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: .rect(cornerRadius: 18))
        .contentShape(Rectangle())
        .onTapGesture { controller.focus(pane.id) }
    }

    private func splitHandle(
        _ handle: MacWorkspaceLayout.Handle,
        globalOrigin: CGPoint
    ) -> some View {
        let hitWidth = handle.axis == .horizontal ? max(14, handle.frame.width) : handle.frame.width
        let hitHeight = handle.axis == .vertical ? max(14, handle.frame.height) : handle.frame.height
        return Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .overlay {
                Capsule()
                    .fill(.secondary.opacity(0.45))
                    .frame(
                        width: handle.axis == .horizontal ? 2 : 30,
                        height: handle.axis == .horizontal ? 30 : 2
                    )
            }
            .frame(width: hitWidth, height: hitHeight)
            .position(x: handle.frame.midX, y: handle.frame.midY)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        let point = CGPoint(
                            x: value.location.x - globalOrigin.x,
                            y: value.location.y - globalOrigin.y
                        )
                        let rawFraction: Double
                        switch handle.axis {
                        case .horizontal:
                            rawFraction = Double(
                                (point.x - handle.container.minX)
                                    / max(1, handle.container.width)
                            )
                        case .vertical:
                            rawFraction = Double(
                                (point.y - handle.container.minY)
                                    / max(1, handle.container.height)
                            )
                        }
                        controller.updateSplitFraction(handle.id, fraction: rawFraction)
                    }
            )
            .onHover { hovering in
                if hovering {
                    (handle.axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .accessibilityLabel(handle.axis == .horizontal ? "Vertical split divider" : "Horizontal split divider")
            .accessibilityValue("\(Int(handle.fraction * 100)) percent")
            .accessibilityAdjustableAction { direction in
                let delta = direction == .increment ? 0.05 : -0.05
                controller.updateSplitFraction(handle.id, fraction: handle.fraction + delta)
            }
    }

    private var focusedActions: MacWorkspaceFocusedActions {
        MacWorkspaceFocusedActions(
            workspaceID: controller.workspaceID,
            canAddPane: controller.canAddPane,
            hasFocusedPane: controller.focusedPaneID != nil,
            secureKeyboardEntryEnabled: secureKeyboardEntry.isEnabled(for: controller.workspaceID),
            addLocalPane: { controller.addPane(intent: .local, axis: $0) },
            requestSSHPane: { controller.requestSSHPane(axis: $0) },
            closeFocusedPane: {
                if settingsManager.confirmBeforeClosing {
                    showingPaneCloseConfirmation = true
                } else {
                    controller.removeFocusedPane(sessionManager: sessionManager)
                }
            },
            focusNextPane: { controller.focusNextPane() },
            findInFocusedPane: { controller.requestFindInFocusedPane() },
            toggleSecureKeyboardEntry: {
                secureKeyboardEntry.toggle(for: controller.workspaceID)
            }
        )
    }

    private func findNonce(for paneID: UUID) -> UInt64 {
        controller.findTargetPaneID == paneID ? controller.findRequestNonce : 0
    }

    private var sshPickerPresented: Binding<Bool> {
        Binding(
            get: { controller.pendingSSHAxis != nil },
            set: { if !$0 { controller.cancelSSHPaneRequest() } }
        )
    }

    private var sshPicker: some View {
        NavigationStack {
            Group {
                if sessionManager.serverManager.servers.isEmpty {
                    ContentUnavailableView(
                        "No Saved Hosts",
                        systemImage: "server.rack",
                        description: Text("Add a host in Connections, then return here to open it in a pane.")
                    )
                } else {
                    List(sessionManager.serverManager.servers) { server in
                        Button {
                            controller.addSSHPane(serverID: server.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(server.name)
                                Text("\(server.username)@\(server.host):\(server.port)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Connect Saved Host")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { controller.cancelSSHPaneRequest() }
                }
                ToolbarItem {
                    Button("Open Connections") {
                        controller.cancelSSHPaneRequest()
                        openWindow(id: "main")
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private var secureKeyboardErrorPresented: Binding<Bool> {
        Binding(
            get: { secureKeyboardEntry.lastError != nil },
            set: { if !$0 { secureKeyboardEntry.clearError() } }
        )
    }
}

struct MacWorkspaceLayout {
    struct Handle: Identifiable {
        let id: UUID
        let axis: MacWorkspaceSplitAxis
        let fraction: Double
        let frame: CGRect
        let container: CGRect
    }

    private(set) var paneFrames: [UUID: CGRect] = [:]
    private(set) var handles: [Handle] = []

    init(root: MacWorkspaceNode, in bounds: CGRect) {
        place(root, in: bounds)
    }

    private mutating func place(_ node: MacWorkspaceNode, in rect: CGRect) {
        switch node {
        case .pane(let pane):
            paneFrames[pane.id] = rect
        case .split(let split):
            let gap: CGFloat = 8
            let fraction = CGFloat(min(0.9, max(0.1, split.fraction)))
            switch split.axis {
            case .horizontal:
                let usable = max(0, rect.width - gap)
                let firstWidth = usable * fraction
                let first = CGRect(x: rect.minX, y: rect.minY, width: firstWidth, height: rect.height)
                let handle = CGRect(x: first.maxX, y: rect.minY, width: gap, height: rect.height)
                let second = CGRect(x: handle.maxX, y: rect.minY, width: usable - firstWidth, height: rect.height)
                handles.append(Handle(id: split.id, axis: split.axis, fraction: split.fraction, frame: handle, container: rect))
                place(split.first, in: first)
                place(split.second, in: second)
            case .vertical:
                let usable = max(0, rect.height - gap)
                let firstHeight = usable * fraction
                let first = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: firstHeight)
                let handle = CGRect(x: rect.minX, y: first.maxY, width: rect.width, height: gap)
                let second = CGRect(x: rect.minX, y: handle.maxY, width: rect.width, height: usable - firstHeight)
                handles.append(Handle(id: split.id, axis: split.axis, fraction: split.fraction, frame: handle, container: rect))
                place(split.first, in: first)
                place(split.second, in: second)
            }
        }
    }
}

#endif
