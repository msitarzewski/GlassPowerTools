//
//  VisionTerminalWorkgroupView.swift
//  glas.sh
//
//  Platform terminal tabs backed by SessionManager workgroups.
//

import SwiftUI
import GlassShell
#if os(visionOS)
import GlassTerminalEmulator
import UIKit

typealias VisionTerminalPresentation = LayoutPreset.OpeningView

/// Matches the Mac overview's status precedence without changing shared
/// connection-state colors used by the iPhone/iPad connection UI.
enum VisionTerminalStatus {
    static func color(for state: SessionState) -> Color {
        switch state {
        case .connected: .green
        case .connecting, .reconnecting: .orange
        case .error: .red
        case .disconnected: .secondary
        }
    }
}

@Observable
final class VisionTerminalPresentationState {
    var mode: VisionTerminalPresentation = .tabs
}

private struct VisionTerminalPresentationKey: EnvironmentKey {
    static let defaultValue: Binding<VisionTerminalPresentation>? = nil
}

extension EnvironmentValues {
    var visionTerminalPresentation: Binding<VisionTerminalPresentation>? {
        get { self[VisionTerminalPresentationKey.self] }
        set { self[VisionTerminalPresentationKey.self] = newValue }
    }
}

struct VisionTerminalPresentationPicker: View {
    @Binding var selection: VisionTerminalPresentation
    var body: some View {
        Picker("Terminal View", selection: $selection) {
            ForEach(VisionTerminalPresentation.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 290)
        .accessibilityIdentifier("vision-terminal-presentation")
    }
}

/// Bounded, in-memory viewport images only. This view neither owns a renderer
/// nor feeds input, and its timer is cancelled when the card leaves the layout.
private struct VisionTerminalPreview: View {
    let session: TerminalSession
    @Environment(SettingsManager.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @State private var image: UIImage?

    private var previewMaterial: Material {
        switch settings.sessionOverride(for: session.id)?.glassFrost ?? settings.glassFrost {
        case "thin": .thinMaterial
        case "regular": .regularMaterial
        case "thick": .thickMaterial
        default: .ultraThinMaterial
        }
    }

    var body: some View {
        let override = settings.sessionOverride(for: session.id)
        let appearance = TerminalGlassAppearance.resolved(
            globalOpacity: settings.windowOpacity,
            globalBlur: settings.blurBackground,
            sessionOverride: override
        )
        ZStack {
            settings.currentTheme.canvasBackgroundColor.color.opacity(appearance.opacity)
            if let tint = TerminalGlassTint.color(for: override?.glassTint ?? settings.glassTint) {
                tint.opacity(0.12 * appearance.opacity)
            }
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView("Preparing preview")
            }
        }
        .modifier(GlassWindowBackground(
            interactive: false, material: previewMaterial,
            blurAmount: appearance.blur, appearance: settings.currentTheme.resolvedAppearance
        ))
        .clipShape(.rect(cornerRadius: 12))
        .allowsHitTesting(false)
        .task(id: session.id) {
            while !Task.isCancelled {
                if scenePhase == .active {
                    image = session.terminalHostModel.previewImage(maxPixelWidth: 800)
                }
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
            }
        }
    }
}
#endif
#if os(iOS)
import UIKit
#endif

#if os(visionOS) || os(iOS)
struct VisionTerminalWorkgroupView: View {
    let workgroupID: UUID

    @Environment(SessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    #if os(iOS)
    @Environment(IOSAppRouter.self) private var iOSRouter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    /// The ⚡: the way to every live connection. Optional because a view rendered outside the
    /// composed app has no runtime.
    @Environment(GlassTerminalRuntime.self) private var runtime: GlassTerminalRuntime?

    @State private var selectedSessionID: UUID?
    @State private var showingSavedHostPicker = false
    @State private var openingServerID: UUID?
    @State private var connectionFailureMessage: String?
    @State private var didCloseWorkgroup = false
    /// The terminal being renamed, and the name typed (W11): as a Mac tab's Rename Tab….
    @State private var renamingSession: TerminalSession?
    @State private var renameText = ""
    #if os(visionOS)
    @State var spatialPresentation = VisionTerminalPresentationState()
    @FocusState private var overviewFocused: Bool

    private var presentation: VisionTerminalPresentation {
        get { spatialPresentation.mode }
        nonmutating set { spatialPresentation.mode = newValue }
    }

    private var presentationBinding: Binding<VisionTerminalPresentation> {
        Binding(get: { spatialPresentation.mode }, set: { spatialPresentation.mode = $0 })
    }
    #endif

    var body: some View {
        Group {
            if let workgroup = sessionManager.workgroup(for: workgroupID) {
                let sessions = liveSessions(in: workgroup)
                if sessions.isEmpty {
                    missingWorkgroupContent
                } else {
                    terminalTabs(workgroup: workgroup, sessions: sessions)
                }
            } else {
                missingWorkgroupContent
            }
        }
        .sheet(isPresented: $showingSavedHostPicker) {
            savedHostPicker
        }
        .alert("Unable to Open Terminal", isPresented: connectionFailureBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(connectionFailureMessage ?? "The saved host could not be opened.")
        }
        .alert("Rename Tab", isPresented: renamingBinding) {
            TextField("Tab Name", text: $renameText)
            Button("Rename") { renamingSession?.rename(to: renameText) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Leave it blank to use the automatic name. In tmux, every device shows the name.")
        }
        .onAppear {
            sessionManager.serverManager.loadServersIfNeeded()
            synchronizeSelection()
            connectShownSlot()
        }
        .onChange(of: liveSelectedSessionID) { _, newSelection in
            if selectedSessionID != newSelection {
                selectedSessionID = newSelection
            }
        }
        .onChange(of: selectedSessionID) { _, newSelection in
            guard let newSelection else { return }
            sessionManager.selectSession(newSelection, inWorkgroup: workgroupID)
            connectShownSlot()
        }
        .focusedSceneValue(
            \.platformNewTerminalAction,
            PlatformNewTerminalAction(title: "New Terminal Tab") {
                showingSavedHostPicker = true
            }
        )
    }

    private var liveSelectedSessionID: UUID? {
        sessionManager.workgroup(for: workgroupID)?.selectedSessionID
    }

    // MARK: Names (W11, 2026-10-09)
    //
    // Every label here — the tab ornament, the tab bar, the grid and carousel cards, the iPhone's
    // switcher — is `TerminalWorkgroupOpening.label`, so a name kept on a session shows on all of
    // them: the headset's ornament, grid and carousel each read the server's name for itself.

    /// Under the name: in a repository its name and branch, then the machine.
    private func machineLine(of session: TerminalSession) -> String {
        let machine = "\(session.server.username)@\(session.server.host)"
        return session.repositoryLine.map { "\($0) · \(machine)" } ?? machine
    }

    private var renamingBinding: Binding<Bool> {
        Binding(get: { renamingSession != nil }, set: { if !$0 { renamingSession = nil } })
    }

    private func beginRename(_ session: TerminalSession) {
        renameText = session.givenName ?? ""
        renamingSession = session
    }

    /// The Mac's tab menu, for one terminal: Rename Tab…, and Use Automatic Name once named.
    @ViewBuilder
    private func renameActions(for session: TerminalSession) -> some View {
        Button("Rename Tab…", systemImage: "pencil") { beginRename(session) }
        if session.givenName != nil {
            Button("Use Automatic Name", systemImage: "arrow.uturn.backward") { session.rename(to: nil) }
        }
    }

    private var connectionFailureBinding: Binding<Bool> {
        Binding(
            get: { connectionFailureMessage != nil },
            set: { isPresented in
                if !isPresented {
                    connectionFailureMessage = nil
                }
            }
        )
    }

    private var savedHostPicker: some View {
        NavigationStack {
            Group {
                if sessionManager.serverManager.servers.isEmpty {
                    ContentUnavailableView {
                        Label("No Saved Hosts", systemImage: "server.rack")
                    } description: {
                        Text("Add a server in Connections before opening another terminal tab.")
                    } actions: {
                        Button("Open Connections", systemImage: "sidebar.left") {
                            showingSavedHostPicker = false
                            showConnections()
                        }
                    }
                } else {
                    List(sessionManager.serverManager.servers) { server in
                        Button {
                            openSavedHost(server)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(server.colorTag.color)
                                    .accessibilityHidden(true)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(server.name)
                                        .fontWeight(.semibold)
                                    Text("\(server.username)@\(server.host):\(server.port)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if openingServerID == server.id {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                            .contentShape(Rectangle())
                            .frame(minHeight: 60)
                        }
                        .buttonStyle(.plain)
                        .disabled(openingServerID != nil)
                        .accessibilityLabel("Open \(server.name) in this workgroup")
                    }
                }
            }
            .navigationTitle("New Terminal Tab")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingSavedHostPicker = false
                    }
                }
            }
        }
        .alert("Unable to Open Terminal", isPresented: connectionFailureBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(connectionFailureMessage ?? "The saved host could not be opened.")
        }
    }

    private var missingWorkgroupContent: some View {
        ContentUnavailableView {
            Label("Terminal Workgroup Closed", systemImage: "rectangle.stack.badge.minus")
        } description: {
            Text("This terminal window no longer has any live sessions.")
        } actions: {
            Button("Open Connections", systemImage: "sidebar.left") {
                showConnections()
            }
        }
    }

    @ViewBuilder
    private func terminalTabs(
        workgroup: TerminalWorkgroup,
        sessions: [TerminalSession]
    ) -> some View {
        #if os(visionOS)
        spatialTerminalTabs(workgroup: workgroup, sessions: sessions)
            .accessibilityIdentifier("terminal-workgroup-tabs")
        #else
        if usesCompactPhoneNavigation {
            NavigationStack {
                compactTerminalTabs(workgroup: workgroup, sessions: sessions)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(.visible, for: .navigationBar)
                    .toolbar(.hidden, for: .tabBar)
                    .toolbar {
                        terminalNavigationToolbar(
                            sessions: sessions,
                            includesSessionSwitcher: true
                        )
                    }
                    // The way out of this session and into any other. On a phone the terminal
                    // swaps the library root, so leaving it is `showConnections()`.
                    .glassActiveConnectionsToolbar(show: runtime?.showActiveConnections,
                                                   dismissCurrent: { iOSRouter.showConnections() })
                    .accessibilityIdentifier("terminal-workgroup-tabs")
            }
        } else {
            NavigationStack {
                adaptiveTerminalTabs(workgroup: workgroup, sessions: sessions)
                    .navigationBarTitleDisplayMode(.inline)
                    .defaultAdaptableTabBarPlacement(.tabBar)
                    .toolbar {
                        terminalNavigationToolbar(
                            sessions: sessions,
                            includesSessionSwitcher: false
                        )
                    }
                    .toolbarBackground(.automatic, for: .tabBar)
                    .glassActiveConnectionsToolbar(show: runtime?.showActiveConnections,
                                                   dismissCurrent: { iOSRouter.showConnections() })
                    .accessibilityIdentifier("terminal-workgroup-tabs")
            }
        }
        #endif
    }

    #if os(visionOS)
    private func spatialTerminalTabs(
        workgroup: TerminalWorkgroup,
        sessions: [TerminalSession]
    ) -> some View {
        ZStack {
            // Do not remove the native tab/ornament host during a presentation
            // change. Its selection is also useful for navigating the overview.
            TabView(selection: $selectedSessionID) {
                ForEach(sessions) { session in
                    Tab(value: Optional(session.id)) { Color.clear } label: {
                        Label(TerminalWorkgroupOpening.label(session, on: .tabOrnament), systemImage: "terminal")
                            .foregroundStyle(VisionTerminalStatus.color(for: session.state))
                            .accessibilityValue(session.state.displayName)
                    }
                    .contextMenu { renameActions(for: session) }
                }
            }
            .toolbarVisibility(presentation == .tabs && sessions.count > 1 ? .visible : .hidden, for: .tabBar)
            ForEach(sessions) { session in
                let active = presentation == .tabs && selectedSessionID == session.id
                TerminalWindowView(
                    session: session,
                    ownsSessionLifecycle: false,
                    showsConnectionOrnament: true,
                    isTerminalActive: active,
                    onNewTerminalTab: { showingSavedHostPicker = true },
                    onSessionRequestedClose: { closeSessionTab(session) }
                )
                .environment(\.visionTerminalPresentation, sessions.count > 1 ? presentationBinding : nil)
                .opacity(active ? 1 : 0)
                .allowsHitTesting(active)
                .accessibilityHidden(!active)
            }
            spatialOverview(sessions: sessions)
                // Each card owns its terminal's canvas and frost. A second,
                // shared glass panel would obscure passthrough between cards
                // and compound their per-terminal transparency settings.
                .allowsHitTesting(presentation != .tabs)
                .accessibilityHidden(presentation == .tabs)
                .ornament(visibility: presentation == .tabs || sessions.count < 2 ? .hidden : .visible,
                          attachmentAnchor: .scene(.bottom)) {
                    HStack(spacing: 16) {
                        VisionTerminalPresentationPicker(selection: presentationBinding)
                        Button("Previous", systemImage: "chevron.left") {
                            moveOverviewSelection(-1, sessions: sessions)
                        }
                        .labelStyle(.iconOnly)
                        Button("Next", systemImage: "chevron.right") {
                            moveOverviewSelection(1, sessions: sessions)
                        }
                        .labelStyle(.iconOnly)
                        Button("Open Terminal", systemImage: "arrow.up.forward") {
                            presentation = .tabs
                        }
                    }
                    .padding(12)
                    .glassBackgroundEffect(in: .capsule)
                }
        }
        .onChange(of: sessions.count, initial: true) { _, count in
            if count < 2 { presentation = .tabs }
        }
        .onChange(of: presentation) { _, mode in
            guard sessions.count > 1 || mode == .tabs else {
                presentation = .tabs
                return
            }
            if mode != .tabs {
                Task { @MainActor in
                    await Task.yield()
                    overviewFocused = true
                }
            } else {
                overviewFocused = false
            }
        }
    }

    private func spatialOverview(sessions: [TerminalSession]) -> some View {
        GeometryReader { geometry in
            Group {
                if presentation == .grid {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 24)], spacing: 24) {
                            ForEach(sessions) { session in
                                overviewCard(session, on: .grid)
                            }
                        }
                        .padding(28)
                    }
                } else if presentation == .carousel {
                    let selectedIndex = sessions.firstIndex { $0.id == selectedSessionID } ?? 0
                    let width = min(720, geometry.size.width * 0.64,
                                    max(200, (geometry.size.height - 120) * 1.6))
                    ZStack {
                        ForEach(Array(sessions.enumerated()).filter { abs($0.offset - selectedIndex) <= 1 }, id: \.element.id) { index, session in
                            let distance = index - selectedIndex
                            overviewCard(session, on: .carousel)
                                .frame(width: width)
                                .scaleEffect(distance == 0 ? 1 : 0.82)
                                .rotation3DEffect(.degrees(Double(distance) * -18), axis: (x: 0, y: 1, z: 0))
                                .offset(x: CGFloat(distance) * width * 0.7)
                                .zIndex(distance == 0 ? 1 : 0)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .animation(.easeInOut(duration: 0.2), value: selectedSessionID)
                }
            }
        }
        .focusable(presentation != .tabs)
        .focused($overviewFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .return, .space, .escape]) { event in
            switch event.key {
            case .leftArrow, .upArrow: moveOverviewSelection(-1, sessions: sessions)
            case .rightArrow, .downArrow: moveOverviewSelection(1, sessions: sessions)
            default: presentation = .tabs
            }
            return .handled
        }
        .accessibilityIdentifier("vision-terminal-overview")
    }

    private func overviewCard(_ session: TerminalSession, on surface: TerminalWorkgroupOpening.LabelSurface) -> some View {
        Button {
            selectedSessionID = session.id
            presentation = .tabs
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                VisionTerminalPreview(session: session)
                    .aspectRatio(1.6, contentMode: .fit)
                Text(TerminalWorkgroupOpening.label(session, on: surface))
                    .font(.headline)
                    .foregroundStyle(VisionTerminalStatus.color(for: session.state))
                    .opacity(selectedSessionID == session.id ? 1 : 0.65)
                    .lineLimit(1)
            }
            .padding(10)
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(selectedSessionID == session.id ? Color.accentColor : .clear,
                                  lineWidth: 3)
            }
            .contentShape(.interaction, RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        // A terminal preview is a large interaction target, not a glass button.
        // The system highlight fills it with an oversized gaze capsule.
        .hoverEffectDisabled()
        .focusEffectDisabled()
        .contextMenu { renameActions(for: session) }
        .accessibilityLabel("Open \(TerminalWorkgroupOpening.label(session, on: surface)) terminal")
        .accessibilityValue(session.state.displayName)
    }

    private func moveOverviewSelection(_ delta: Int, sessions: [TerminalSession]) {
        guard !sessions.isEmpty else { return }
        let index = sessions.firstIndex { $0.id == selectedSessionID } ?? 0
        selectedSessionID = sessions[min(sessions.count - 1, max(0, index + delta))].id
    }
    #endif

    private func adaptiveTerminalTabs(
        workgroup: TerminalWorkgroup,
        sessions: [TerminalSession]
    ) -> some View {
        TabView(selection: $selectedSessionID) {
            TabSection(workgroup.name) {
                ForEach(sessions) { session in
                    terminalTab(session: session, workgroup: workgroup)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    #if os(iOS)
    private func compactTerminalTabs(
        workgroup: TerminalWorkgroup,
        sessions: [TerminalSession]
    ) -> some View {
        ZStack {
            // A slot that has never connected has nothing to keep on screen: its terminal is
            // made when it is shown (W4b). Connected ones stay, hidden, as before.
            ForEach(sessions.filter { $0.id == (selectedSessionID ?? workgroup.selectedSessionID) || $0.state != .disconnected }) { session in
                let active = (selectedSessionID ?? workgroup.selectedSessionID) == session.id
                TerminalWindowView(
                    session: session,
                    ownsSessionLifecycle: false,
                    showsConnectionOrnament: false,
                    isTerminalActive: active,
                    onNewTerminalTab: { showingSavedHostPicker = true },
                    onSessionRequestedClose: { closeSessionTab(session) }
                )
                .opacity(active ? 1 : 0)
                .allowsHitTesting(active)
                .accessibilityHidden(!active)
                .accessibilityIdentifier("terminal-workgroup-session-\(session.id.uuidString)")
            }
        }
    }
    #endif

    private func terminalTab(
        session: TerminalSession,
        workgroup: TerminalWorkgroup
    ) -> some TabContent<UUID?> {
        Tab(value: Optional(session.id)) {
            TerminalWindowView(
                session: session,
                ownsSessionLifecycle: false,
                showsConnectionOrnament: false,
                isTerminalActive: selectedSessionID == session.id,
                onNewTerminalTab: {
                    showingSavedHostPicker = true
                },
                onSessionRequestedClose: {
                    closeSessionTab(session)
                }
            )
            .accessibilityIdentifier("terminal-workgroup-session-\(session.id.uuidString)")
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(TerminalWorkgroupOpening.label(session, on: .tabBar))
                        .lineLimit(1)
                    Text(machineLine(of: session))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } icon: {
                Image(systemName: "circle.fill")
                    .foregroundStyle(workgroup.colorTag.color)
            }
        }
        .contextMenu { renameActions(for: session) }
    }

    #if os(iOS)
    /// Every iPhone, in every orientation. A Pro Max on its side reports a regular width, and
    /// the iPad layout's tab bar then put a session pill under the terminal and rebuilt the
    /// screen on every rotation (2026-10-04, landscape on a Pro Max).
    private var usesCompactPhoneNavigation: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    @ToolbarContentBuilder
    private func terminalNavigationToolbar(
        sessions: [TerminalSession],
        includesSessionSwitcher: Bool
    ) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showConnections()
            } label: {
                // **A back arrow, not a sidebar toggle.** There is no sidebar here: the terminal
                // takes the whole screen and this control goes *back* to the library, which is
                // what a chevron says and what `sidebar.left` promised it would not do
                // (reported 2026-09-19). The session keeps running either way.
                Label("Connections", systemImage: "chevron.backward")
            }
            .accessibilityIdentifier("terminal-workgroup-connections")
        }

        if includesSessionSwitcher {
            ToolbarItem(placement: .principal) {
                compactSessionSwitcher(sessions: sessions)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingSavedHostPicker = true
            } label: {
                Label("New Terminal Tab", systemImage: "plus")
            }
            .accessibilityIdentifier("terminal-workgroup-new-tab")
        }
    }

    /// Each slot by the workgroup's label for it, else "Terminal N · server", with a filled dot
    /// once it is connected (W4b): choosing one connects it.
    private func compactSessionSwitcher(sessions: [TerminalSession]) -> some View {
        Menu {
            Picker("Session", selection: $selectedSessionID) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { position, session in
                    Label(TerminalWorkgroupOpening.slotTitle(session, position: position),
                          systemImage: session.state == .connected ? "circle.fill" : "circle")
                        .accessibilityValue(session.state == .connected ? "Connected" : "Not connected")
                        .tag(Optional(session.id))
                }
            }
            // The terminal on screen, as a Mac tab's menu names it (W11).
            if let shown = sessions.first(where: { $0.id == selectedSessionID }) ?? sessions.first {
                Divider()
                renameActions(for: shown)
            }
        } label: {
            HStack(spacing: 5) {
                Text(selectedSessionName(in: sessions))
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.caption)
            }
            .lineLimit(1)
        }
        .accessibilityLabel("Terminal Sessions")
        .accessibilityValue(selectedSessionName(in: sessions))
        .accessibilityIdentifier("terminal-workgroup-session-switcher")
    }

    private func selectedSessionName(in sessions: [TerminalSession]) -> String {
        let position = sessions.firstIndex(where: { $0.id == selectedSessionID }) ?? 0
        guard sessions.indices.contains(position) else { return "Session" }
        return TerminalWorkgroupOpening.slotTitle(sessions[position], position: position)
    }
    #endif

    /// iPhone: the slot on screen connects if it needs to, and the hidden ones wait to be shown
    /// (W4b). iPad and Vision Pro keep every terminal connected for their previews.
    private func connectShownSlot() {
        #if os(iOS)
        guard usesCompactPhoneNavigation else { return }
        Task { @MainActor in
            do {
                try await TerminalWorkgroupOpening.connectShownSlot(in: workgroupID, sessionManager: sessionManager,
                                                                    settingsManager: settingsManager)
            } catch {
                connectionFailureMessage = error.localizedDescription
            }
        }
        #endif
    }

    private func liveSessions(in workgroup: TerminalWorkgroup) -> [TerminalSession] {
        sessionManager.sessions(inWorkgroup: workgroup.id)
    }

    private func synchronizeSelection() {
        guard sessionManager.workgroup(for: workgroupID) != nil else {
            selectedSessionID = nil
            return
        }
        selectedSessionID = sessionManager.selectedSession(inWorkgroup: workgroupID)?.id
    }

    private func openSavedHost(_ server: ServerConfiguration) {
        guard openingServerID == nil else { return }
        openingServerID = server.id

        Task { @MainActor in
            defer { openingServerID = nil }
            do {
                let launch = try await sessionManager.createAuthorizedSessionByServerID(
                    server.id,
                    settingsManager: settingsManager,
                    initialTerminalPresentation: { pendingSession in
                        guard sessionManager.appendSession(
                            pendingSession,
                            toWorkgroup: workgroupID
                        ) else { return }
                        selectedSessionID = pendingSession.id
                        showingSavedHostPicker = false
                    }
                )
                let session = launch.session
                guard session.state == .connected || session.pendingHostKeyChallenge != nil else {
                    if case .error(let message) = session.state {
                        connectionFailureMessage = message
                    } else {
                        connectionFailureMessage = "\(server.name) did not establish a terminal session."
                    }
                    sessionManager.closeSession(session)
                    return
                }
                if session.didRequestInitialTerminalPresentation {
                    return
                }
                guard sessionManager.appendSession(session, toWorkgroup: workgroupID) else {
                    sessionManager.closeSession(session)
                    connectionFailureMessage = "\(server.name) could not be added to this workgroup."
                    return
                }
                selectedSessionID = session.id
                showingSavedHostPicker = false
            } catch {
                connectionFailureMessage = error.localizedDescription
            }
        }
    }

    private func closeSessionTab(_ session: TerminalSession) {
        let closesLastSession = sessionManager.workgroup(for: workgroupID)?.sessionIDs == [session.id]
        guard sessionManager.closeSession(session.id, inWorkgroup: workgroupID) else {
            return
        }
        if closesLastSession {
            closeWorkgroupOnce()
            #if os(visionOS)
            dismiss()
            #else
            iOSRouter.showConnections()
            #endif
        } else {
            synchronizeSelection()
        }
    }

    private func showConnections() {
        #if os(visionOS)
        openWindow(id: "main")
        dismiss()
        #else
        iOSRouter.showConnections()
        #endif
    }

    private func closeWorkgroupOnce() {
        guard !didCloseWorkgroup else { return }
        didCloseWorkgroup = true
        sessionManager.closeWorkgroup(workgroupID)
    }
}
#endif
