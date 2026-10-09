#if os(macOS)
import AppKit
import GlassConnectionUI
import GlassShell
import Observation
import os
import GlassTerminalEmulator
import SwiftUI
import GlassLayers

struct MacWorkspaceSceneRoot: View {
    private let request: MacWorkspaceLaunchRequest?
    /// A window SwiftUI opens with no value — one whose saved value it couldn't read back — keeps
    /// one request for its life. Made in `init`, each run of it was a new window id, so a new
    /// controller that no window showed, and each wrote a window record and an empty tab (W7b).
    @State private var requestWithoutValue = MacWorkspaceLaunchRequest(startsEmpty: true)

    init(request: MacWorkspaceLaunchRequest?) {
        self.request = request
    }

    var body: some View {
        MacWorkspaceView(request: request ?? requestWithoutValue)
    }
}

struct MacWorkspaceView: View {
    @State private var windowController: MacWorkspaceWindowController
    @State private var columnVisibility: NavigationSplitViewVisibility
    @State private var secureKeyboardEntry = MacSecureKeyboardEntry.shared
    @State private var terminalWindow: NSWindow?
    /// Puts a reopened window back where it was, and keeps its place in its record (W12).
    @State private var placementTracker = MacWorkspaceWindowPlacementTracker()
    @State private var workgroupEditorContext: WorkgroupEditorContext?
    @State private var workspaceSaveError: String?
    @State private var isConfirmingTabClose = false
    /// The tab being renamed in the sidebar, and the name as typed (2026-10-07).
    @State private var renamingTabID: UUID?
    @State private var renameText = ""
    @FocusState private var renameFieldFocused: Bool
    @State private var pendingWindowClose = false
    /// A tab from another window is being dragged over this one.
    @State private var tabDropTargeted = false
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
        // SwiftUI runs this again for a window it already shows, and `@State` keeps only the first
        // controller; a second one made here lived on beside it as a twin (2026-10-08). The
        // registry hands back the window's own, and makes one only for a window that has none.
        let controller = MacWorkspacePreviewRegistry.shared.windowController(for: request)
        let scope = controller.tabs.first?.workgroupID?.uuidString.lowercased() ?? "terminal"
        let key = UserDefaultsKeys.macWorkspaceSidebarVisibility + "." + scope
        sidebarPreferenceKey = key
        let savedVisibility = UserDefaults.standard.object(forKey: key) as? Bool
        _windowController = State(initialValue: controller)
        _columnVisibility = State(
            initialValue: (savedVisibility ?? controller.tabs.contains { $0.workgroupID != nil }) ? .all : .detailOnly
        )
    }

    /// The sidebar's tabs. Its own property, so the window's body stays within what the type
    /// checker can solve.
    private var tabList: some View {
        List(selection: sidebarSelection) {
            ForEach(windowController.tabs, id: \.workspaceID) { controller in
                tabRow(controller)
            }
            .onInsert(of: [MacWorkspaceTabDrag.type]) { index, providers in
                MacWorkspaceTabDrag.load(from: providers) { drags in
                    windowController.acceptDroppedTabs(drags, at: index)
                }
            }
        }
        // The list's own menu and primary action: double-click (or Return) renames in place, as
        // Finder's sidebar does, without a tap gesture holding every single click back. The menu
        // gets the selection when the row right-clicked is in it, else that row alone.
        .contextMenu(forSelectionType: UUID.self) { ids in
            tabMenu(for: ids)
        } primaryAction: { ids in
            if ids.count == 1, let controller = ids.first.flatMap(tab(_:)) { beginRename(controller) }
        }
    }

    private func tab(_ id: UUID) -> MacWorkspaceController? {
        windowController.tabs.first { $0.workspaceID == id }
    }

    /// One tab: rename, as before. Several, ⌘- or ⇧-clicked (W8, owner, 2026-10-08): move them
    /// to a new window together, or close them. Rename is for one tab only.
    @ViewBuilder
    private func tabMenu(for ids: Set<UUID>) -> some View {
        let chosen = windowController.tabs.filter { ids.contains($0.workspaceID) }
        if chosen.count == 1, let controller = chosen.first {
            Button("Rename Tab…", systemImage: "pencil") { beginRename(controller) }
                .labelStyle(.titleAndIcon)
            if controller.tabLabel != nil {
                Button("Use Automatic Name", systemImage: "arrow.uturn.backward") {
                    windowController.renameTab(controller.workspaceID, to: nil)
                }
                .labelStyle(.titleAndIcon)
            }
        } else if chosen.count > 1 {
            let chosenIDs = Set(chosen.map(\.workspaceID))
            Button(MacMoveWorkspaceTabsAction.title(count: chosen.count), systemImage: "macwindow.badge.plus") {
                moveTabsToNewWindow(chosenIDs)
            }
            .labelStyle(.titleAndIcon)
            .disabled(!windowController.canTransferTabs(chosenIDs))
            Button("Close \(chosen.count) Tabs", systemImage: "xmark") { requestCloseTabs(chosenIDs) }
                .labelStyle(.titleAndIcon)
        }
    }

    @ViewBuilder
    private func tabRow(_ controller: MacWorkspaceController) -> some View {
        let tabIdentity = controller.windowIdentity(
            servers: sessionManager.serverManager.servers
        )
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    if renamingTabID == controller.workspaceID {
                        // Return saves, Escape cancels, leaving the field saves; blank is
                        // the automatic name again.
                        TextField("Tab Name", text: $renameText, prompt: Text(tabIdentity.title))
                            .textFieldStyle(.plain)
                            .focused($renameFieldFocused)
                            .onAppear { renameFieldFocused = true }
                            .onSubmit { commitRename() }
                            .onExitCommand { renamingTabID = nil }
                            .onChange(of: renameFieldFocused) { _, focused in
                                if !focused { commitRename() }
                            }
                            .accessibilityIdentifier("mac-workspace-tab-rename")
                    } else {
                        Text(tabIdentity.title)
                            .lineLimit(1)
                    }
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
            .frame(maxWidth: .infinity, alignment: .leading)
            // While a terminal in the tab is printing, a wave moves under the row.
            .background {
                if controller.isProducingOutput {
                    MacTerminalActivityWave(color: controller.workgroupColor?.color ?? .accentColor)
                        .padding(.horizontal, -6)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: controller.isProducingOutput)
        .tag(controller.workspaceID)
        .accessibilityLabel(tabIdentity.title)
        .accessibilityValue(tabIdentity.subtitle ?? "")
        .accessibilityIdentifier(
            "mac-workspace-tab-\(controller.workspaceID.uuidString.lowercased())"
        )
        // Drag a tab to another terminal window to move it there, running, or within this
        // sidebar to reorder (2026-10-08). The list's own drag, not a gesture on the row: a
        // gesture made every click wait, and selecting a tab took several.
        .itemProvider {
            MacWorkspaceTabDrag(windowID: windowController.windowID,
                                workspaceID: controller.workspaceID).itemProvider()
        }
    }

    var body: some View {
        let selected = windowController.selectedTab
        let identity = selected.windowIdentity(
            servers: sessionManager.serverManager.servers
        )

        NavigationSplitView(columnVisibility: $columnVisibility) {
            tabList
                .listStyle(.sidebar)
                // A wider ceiling than 360: the sidebar carries a title and a monospaced subtitle
                // per tab, and a user with long session names could not widen past truncation.
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 520)
                // No autosave name of our own: SwiftUI autosaves the split view itself, and a
                // second name assigned from outside restored layouts SwiftUI had not asked for
                // (2026-10-08). One owner per split view.
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
            // A tab dragged from another window can land anywhere on this one, sidebar open or
            // not; it joins at the end. Panes take only Finder's files, so they pass it on.
            .onDrop(of: [MacWorkspaceTabDrag.type], isTargeted: $tabDropTargeted) { providers in
                MacWorkspaceTabDrag.load(from: providers) { drags in
                    windowController.acceptDroppedTabs(drags, at: windowController.tabs.count)
                }
                return true
            }
            .overlay {
                if tabDropTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .padding(4)
                        .allowsHitTesting(false)
                }
            }
            // Editable: clicking the window title renames the tab, as the sidebar does.
            .navigationTitle(Binding(
                get: { showingOverview && !overviewControlsVisible ? "" : identity.title },
                set: { name in
                    guard !(showingOverview && !overviewControlsVisible), name != identity.title else { return }
                    windowController.renameTab(selected.workspaceID, to: name)
                }))
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
            // On screen now: save what the window opened with, if it is new. Its controller's
            // init writes nothing, since SwiftUI makes ones it never shows (W7b).
            windowController.windowDidOpen()
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
            for tab in tabs { startLocalPanes(of: tab) }
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
        // Its last tab was dragged into another window: this one is done.
        .onChange(of: windowController.closesAfterLastTabLeft) { _, closes in
            guard closes else { return }
            pendingWindowClose = true
            terminalWindow?.close()
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
                    // Once per window: back where it was if reopened from its record. Here, on the
                    // main queue after SwiftUI's update, never from inside one.
                    placementTracker.track(window, controller: windowController)
                    window.title = showingOverview && !overviewControlsVisible ? "" : identity.title
                    window.subtitle = showingOverview && !overviewControlsVisible ? "" : identity.subtitle ?? ""
                    if pendingWindowClose {
                        DispatchQueue.main.async { window.close() }
                    }
                },
                onClose: {
                    placementTracker.stop()
                    MacWorkspacePreviewRegistry.shared.remove(windowController.windowID)
                    windowController.closeAllSessions(sessionManager: sessionManager)
                    for tab in windowController.tabs {
                        secureKeyboardEntry.disable(for: tab.workspaceID)
                    }
                },
                shouldConfirmClose: { quitting in
                    guard settingsManager.confirmBeforeClosing else { return nil }
                    return quitting ? windowController.quitConfirmationMessage : windowController.closeConfirmationMessage
                },
                opensSidebarInitially: !showingOverview && columnVisibility == .all,
                overviewPresented: showingOverview
            )
        }
        // A two-finger pinch in shows every terminal (W9). The monitor keeps every pinch in this
        // window from the terminals, so none is ever zoomed by one.
        .background {
            MacTerminalExposePinchMonitor { outcome in
                if outcome == .pinchedIn { MacTerminalExpose.shared.show(exposeContext) }
            }
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
                                 detail: "View all terminal tabs", shortcut: "⌥⌘G") { showOverview(carousel: false) },
            MacCommandCenterEntry(id: "workspace.carousel", title: "Terminal Carousel",
                                 detail: "Browse overlapping terminal previews", shortcut: "⌥⇧⌘G") { showOverview(carousel: true) },
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
        .focusedSceneValue(\.macMoveWorkspaceTabsAction, moveTabsAction)
        // ⌘W, while a terminal workspace is focused, closes the tab rather than the window with
        // every tab in it — the behaviour the menu item used to carry, now registered with the
        // shell's close router rather than declared as a second ⌘W that took the key off Close.
        .glassCloseCommandTarget(priority: .workspace) {
            guard let window = NSApp.keyWindow, window.attachedSheet == nil,
                  window.sheetParent == nil else { return }
            requestCloseSelectedTab()
        }
        .sheet(item: $workgroupEditorContext) { context in
            // Saving under a workgroup's name offers to replace it: how a window rebuilds the
            // workgroup it was arranged as (W4b).
            WorkgroupEditorView(context: context, servers: sessionManager.serverManager.servers,
                                existing: settingsManager.layoutPresets) { preset in
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


    /// What Show All Terminals draws with, from this window.
    private var exposeContext: MacTerminalExpose.Context {
        MacTerminalExpose.Context(sessionManager: sessionManager, settingsManager: settingsManager,
                                  openWindow: openWindow)
    }

    @ToolbarContentBuilder
    private func workspaceToolbar(selected: MacWorkspaceController) -> some ToolbarContent {
            ToolbarItem(id: "terminal-overview") {
                Button("Terminal Overview", systemImage: "square.grid.2x2", action: openOverview)
                    .help("Show all terminal tabs as a grid or carousel")
                    .accessibilityIdentifier("mac-workspace-overview")
            }
            .glassKeepVisibleWhenCompact()
            // Every terminal window and its tabs, not just this one's (W9). ⇧⌘\ is the Window
            // menu item's, not this button's.
            ToolbarItem(id: "show-all-terminals") {
                Button("Show All Terminals", systemImage: "rectangle.3.group") {
                    MacTerminalExpose.shared.toggle(exposeContext)
                }
                .help("Show All Terminals")
                .accessibilityIdentifier("mac-workspace-show-all-terminals")
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
                        Button(MacMoveWorkspaceTabsAction.title(count: windowController.selectedTabIDs.count),
                               systemImage: "macwindow.badge.plus") {
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
            // A capture is a new preset; it replaces one only when saved under its name and the
            // editor's Replace is chosen.
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

    /// Several tabs at once (W8): ⌘-click and ⇧-click are the list's own. The window controller
    /// picks the tab shown from what the list reports, so a plain click still shows its tab.
    private var sidebarSelection: Binding<Set<UUID>> {
        Binding(
            get: { windowController.selectedTabIDs },
            set: { windowController.updateSelection($0) }
        )
    }

    /// The menu bar's Move Tab to New Window, for the selected tabs.
    private var moveTabsAction: MacMoveWorkspaceTabsAction {
        MacMoveWorkspaceTabsAction(
            count: windowController.selectedTabIDs.count,
            isEnabled: windowController.canTransferSelectedTab,
            moveSelectedTabToNewWindow
        )
    }

    private func beginRename(_ tab: MacWorkspaceController) {
        renameText = tab.tabLabel ?? ""
        renamingTabID = tab.workspaceID
        renameFieldFocused = true
    }

    private func commitRename() {
        guard let id = renamingTabID else { return }
        renamingTabID = nil
        windowController.renameTab(id, to: renameText)
    }

    /// "+" and ⌘T: a tab with a shell on this Mac, started at once (2026-10-08).
    private func addTab() {
        if let tab = windowController.addTab() { startLocalPanes(of: tab) }
    }

    /// Starts a tab's local shells now, not when its view first draws: a pane started only by
    /// its view waited on SwiftUI, and could be left with no shell at all.
    private func startLocalPanes(of tab: MacWorkspaceController) {
        tab.startLocalPanes(sessionManager: sessionManager, settingsManager: settingsManager) {
            closeTab(tab.workspaceID)
        }
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
        // And the tmux session belongs to the pane that made it: the new tab gets its own.
        intent.localTmuxSession = nil
        intent.sshTmuxSession = nil
        if let tab = windowController.addTab(
            MacWorkspaceTabRequest(startsEmpty: false, initialPaneIntent: intent)
        ) {
            startLocalPanes(of: tab)
        }
    }

    private func closeTab(_ workspaceID: UUID) {
        closeTabs([workspaceID])
    }

    private func closeTabs(_ ids: Set<UUID>) {
        let closesWindow = windowController.removeTabs(ids, sessionManager: sessionManager)
        for id in ids { secureKeyboardEntry.disable(for: id) }
        if closesWindow {
            pendingWindowClose = true
            terminalWindow?.close()
        }
    }

    /// ⌘W: the tab shown, even with several selected.
    private func requestCloseSelectedTab() {
        requestCloseTabs([windowController.selectedTabID])
    }

    /// Closes tabs as closing one does (W8): asks first when any would stop something (D44), and
    /// a terminal kept in tmux detaches and keeps running.
    private func requestCloseTabs(_ ids: Set<UUID>) {
        guard !isConfirmingTabClose else { return }
        let count = windowController.tabs.filter { ids.contains($0.workspaceID) }.count
        guard count > 0 else { return }
        guard let warning = windowController.closeWarning(forTabs: ids) else {
            closeTabs(ids)
            return
        }
        guard let window = terminalWindow, window.attachedSheet == nil else { return }
        isConfirmingTabClose = true
        let alert = NSAlert()
        alert.messageText = count == 1 ? "Close Terminal Tab?" : "Close \(count) Terminal Tabs?"
        alert.informativeText = warning + " The saved Workgroup will not be changed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: count == 1 ? "Close Tab" : "Close \(count) Tabs")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            isConfirmingTabClose = false
            if response == .alertFirstButtonReturn {
                closeTabs(ids)
            }
        }
    }

    private func moveSelectedTabToNewWindow() {
        moveTabsToNewWindow(windowController.selectedTabIDs)
    }

    /// One new window holding these tabs, in sidebar order, still running. When they were every
    /// tab, this window closes once they have gone (`closesAfterLastTabLeft`).
    private func moveTabsToNewWindow(_ ids: Set<UUID>) {
        guard let request = windowController.transferTabs(ids) else { return }
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
            // Edit ▸ Find, Find Next and Find Previous belong to the shell (`GlassShellFindCommands`);
            // here they go to the focused pane's find bar.
            .focusedSceneValue(\.glassFindItem, GlassFindItemAction(
                isEnabled: controller.focusedPaneID != nil,
                find: { controller.requestFind(.show) },
                findNext: { controller.requestFind(.next) },
                findPrevious: { controller.requestFind(.previous) }
            ))
            .sheet(isPresented: sshPickerPresented) { sshPicker }
            .sheet(item: $credentialPrompt) { prompt in
                ConnectionPasswordPromptSheet(server: prompt.server, savesPassword: true) { password in
                    guard let current = sessionManager.server(for: prompt.server.id),
                          controller.state.root?.pane(id: prompt.paneID) != nil else {
                        return "This connection or terminal pane is no longer available."
                    }
                    do {
                        try await sessionManager.serverManager.tryPassword(password, for: current)
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
                                // Files dropped from Finder type their paths, as Terminal.app does;
                                // so does a screenshot's floating thumbnail, a file promise.
                                .onDrop(of: SFTPIncomingDrop.acceptedTypes, isTargeted: nil) { providers in
                                    receiveDrop(providers, on: pane.id)
                                }
                                .frame(width: frame.width, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)
                        }
                    }

                    ForEach(layout.handles) { handle in
                        splitHandle(handle, globalOrigin: globalOrigin)
                    }
                }
            }
        } else if let failure = controller.restorationFailure {
            MacWorkspaceUnrestoredTab(reason: failure, close: onCloseEmptyTab)
        } else {
            MacWorkspaceEmptyTab(
                theme: settingsManager.currentTheme,
                tint: TerminalGlassTint.color(for: settingsManager.glassTint),
                opacity: settingsManager.windowOpacity,
                blur: settingsManager.blurBackground,
                startLocal: { controller.addPane(intent: .local, axis: .horizontal) },
                startSSH: { controller.requestSSHPane(axis: .horizontal) }
            )
        }
    }

    /// Reads a drop the way the Files browser does — a file promise first, as AppKit offers it —
    /// and types the paths. A file that already exists types its own path; a promised file or bare
    /// image data is written to the drop inbox first (`TerminalDroppedPaths.inbox`).
    private func receiveDrop(_ providers: [NSItemProvider], on paneID: UUID) -> Bool {
        guard let drop = SFTPIncomingDrop(providers: providers) else { return false }
        Task { @MainActor in
            do {
                let staging = try SFTPDropStaging(keepingFilesIn: TerminalDroppedPaths.inbox())
                let received = try await drop.materialize(into: staging)
                _ = dropFiles(received.urls, on: paneID)
            } catch {
                Self.dropLogger.error("A drop on a terminal could not be read: \(error.localizedDescription, privacy: .public)")
            }
        }
        return true
    }

    private static let dropLogger = Logger(subsystem: "sh.glas", category: "terminal-drop")

    /// Types the dropped files' paths into the pane's terminal, and makes it the focused pane.
    private func dropFiles(_ urls: [URL], on paneID: UUID) -> Bool {
        guard let text = TerminalDroppedPaths.text(for: urls) else { return false }
        let model = controller.localRuntimesByPaneID[paneID]?.model ?? controller.session(for: paneID)?.terminalHostModel
        guard let model else { return false }
        controller.focus(paneID)
        model.insertDroppedText(text)
        return true
    }

    /// A local pane is done: its shell ended, or it was closed — in tmux, detached (D47).
    private func closeLocalPane(_ paneID: UUID) {
        guard !controller.isClosed else { return }
        let closesWorkspace = controller.state.root?.panes.count == 1
        controller.removePane(paneID, sessionManager: sessionManager)
        if closesWorkspace {
            onCloseEmptyTab()
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
                    tmuxSession: pane.intent.localTmuxSession,
                    isFocused: isFocused,
                    showsPaneChrome: showsPaneChrome,
                    findRequest: findRequest(for: pane.id),
                    claimStartupCommand: { controller.claimStartupCommand(for: pane.id) },
                    onFocus: { controller.focus(pane.id) },
                    onDisconnect: { closeLocalPane(pane.id) },
                    onProcessStatusChange: { controller.updateLocalProcessStatus($0, for: pane.id) },
                    onContextChange: { controller.updatePaneContext(title: $0, directory: $1, for: pane.id) },
                    hostModel: runtime.model,
                    processState: runtime.processState
                )
            } else if !controller.isClosed, pane.intent.localTmuxSession != nil {
                // Refused: another tab here already shows this tmux session (`claimShown`).
                ContentUnavailableView {
                    Label("Already Open", systemImage: "rectangle.on.rectangle")
                } description: {
                    Text("This terminal's tmux session is open in another tab. Close this pane and use that tab.")
                } actions: {
                    Button("Close Pane") { closeLocalPane(pane.id) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.regularMaterial, in: .rect(cornerRadius: showsPaneChrome ? 18 : 0))
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
                    externalFindRequest: findRequest(for: pane.id),
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
                    },
                    onTerminalContextChange: { controller.updatePaneContext(title: $0, directory: $1, for: pane.id) }
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
                if settingsManager.confirmBeforeClosing && controller.focusedPaneCloseStopsWork {
                    showingPaneCloseConfirmation = true
                } else {
                    controller.removeFocusedPane(sessionManager: sessionManager)
                }
            },
            focusNextPane: { controller.focusNextPane() },
            toggleSecureKeyboardEntry: {
                secureKeyboardEntry.toggle(for: controller.workspaceID)
            }
        )
    }

    private func findRequest(for paneID: UUID) -> TerminalFindRequest {
        controller.findTargetPaneID == paneID ? controller.findRequest : .none
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

/// The chooser an otherwise-empty tab shows. It sits on the terminal theme's canvas, so it takes
/// the theme's light or dark: in the system's, a dark theme under Light appearance drew its text
/// and buttons black on black, and the tab looked blank (2026-10-08).
struct MacWorkspaceEmptyTab: View {
    let theme: TerminalTheme
    var tint: Color? = nil
    var opacity: Double = 1
    var blur: Double = 0
    let startLocal: () -> Void
    let startSSH: () -> Void
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        ContentUnavailableView {
            Label("New Terminal", systemImage: "apple.terminal")
        } description: {
            Text("Choose how to start this terminal tab.")
        } actions: {
            Button("Local Terminal", systemImage: "apple.terminal", action: startLocal)
            Button("SSH Connection", systemImage: "network", action: startSSH)
        }
        .environment(\.colorScheme, theme.resolvedAppearance.colorScheme ?? systemColorScheme)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            TerminalCanvasBackground(
                color: theme.background,
                tint: tint,
                opacity: opacity,
                blur: blur,
                appearance: theme.resolvedAppearance
            )
        }
    }
}

/// A tab whose saved layout couldn't be read (W7b). The record is kept exactly as it was, so
/// nothing here can add a pane over it; closing the tab is how it is discarded.
struct MacWorkspaceUnrestoredTab: View {
    let reason: String
    let close: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't Restore This Tab", systemImage: "exclamationmark.triangle")
        } description: {
            Text("\(reason) It has been kept as it was. Close the tab to discard it.")
        } actions: {
            Button("Close Tab", action: close)
                .accessibilityIdentifier("mac-workspace-close-unrestored-tab")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
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
