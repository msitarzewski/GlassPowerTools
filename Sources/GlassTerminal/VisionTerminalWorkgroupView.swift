//
//  VisionTerminalWorkgroupView.swift
//  glas.sh
//
//  Platform terminal tabs backed by SessionManager workgroups.
//

import SwiftUI
import GlassShell
import GlassLayers
// Every platform this view is built for: Watch Log File reads a terminal's folder (2026-10-15).
import GlassTerminalEmulator
#if os(visionOS)
import GlassConnectionUI
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

/// Whether a terminal in a window printed something in the last moment, for its orb's pulse
/// (2026-10-15), as a Mac tab tells it (`MacWorkspaceController.isProducingOutput`).
@MainActor @Observable
final class TerminalWindowActivity {
    private(set) var isBusy = false
    /// The terminal that printed last, for Auto-focus on activity in the grid and carousel.
    private(set) var lastSessionID: UUID?
    @ObservationIgnored private var quiet: Task<Void, Never>?

    func note(_ sessionID: UUID) {
        if !isBusy { isBusy = true }
        if lastSessionID != sessionID { lastSessionID = sessionID }
        quiet?.cancel()
        quiet = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1_200))
            guard !Task.isCancelled else { return }
            self?.isBusy = false
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

    /// Whether a terminal window shows its sidebar (2026-10-21), for the toggle in its bar; nil in a
    /// window of one terminal, which has none.
    @Entry var visionTerminalSidebar: Binding<Bool>? = nil
}

/// The window's layout — tabs, grid, carousel — as one control, as the editor's preview is (the
/// owner, 2026-10-15: "I'd like the tabs/grid/carousel selector to be a toggle like we have for the
/// markdown preview in the text editor"). Its glyph is the layout the window is in — an eye says
/// show or hide, and nothing here is hidden — a pinch moves to the next, and a pinch held lists the
/// three. It was a 290-point segmented picker in the bar.
struct VisionTerminalPresentationPicker: View {
    @Binding var selection: VisionTerminalPresentation
    /// The window's orb, the fourth way to see it (the owner, 2026-10-15: "is the orb view just one
    /// more option for the view menu in terminal mode?").
    @Environment(\.glassSessionOrb) private var orb
    var body: some View {
        Menu {
            ForEach(VisionTerminalPresentation.allCases, id: \.self) { mode in
                Toggle(isOn: Binding(get: { selection == mode }, set: { if $0 { selection = mode } })) {
                    Label(mode.title, systemImage: mode.symbolName)
                }
            }
            if let orb, !orb.isOrb {
                Button("Orb", systemImage: "circle.circle") { orb.shrink() }
                    .accessibilityIdentifier("vision-terminal-presentation-orb")
            }
        } label: {
            Label("Terminal View", systemImage: orb.map { $0.isOrb ? selection.symbolName : "circle.circle" } ?? selection.symbolName)
        } primaryAction: {
            // The orb, first (the owner, 2026-10-21: "make Orb the default option in the Tabs menu so
            // a click gets orb view"); with none to become, the next layout, as before.
            if let orb, !orb.isOrb { orb.shrink() } else { selection = selection.next }
        }
        .help(orb.map { _ in "\(selection.title). Pinch to shrink to an orb; hold to choose a view." }
              ?? "\(selection.title). Pinch for \(selection.next.title); hold to choose.")
        .accessibilityValue(selection.title)
        .accessibilityIdentifier("vision-terminal-presentation")
    }
}

extension LayoutPreset.OpeningView {
    /// The layout's glyph: a window with its tab strip, a grid of cards, a stack of cards.
    var symbolName: String {
        switch self {
        case .tabs: "rectangle.topthird.inset.filled"
        case .grid: "square.grid.2x2"
        case .carousel: "rectangle.stack"
        }
    }

    /// The layout a pinch moves to: tabs, grid, carousel, and round again.
    var next: Self {
        switch self {
        case .tabs: .grid
        case .grid: .carousel
        case .carousel: .tabs
        }
    }
}

/// Bounded, in-memory viewport images only. This view neither owns a renderer
/// nor feeds input, and its timer is cancelled when the card leaves the layout.
private struct VisionTerminalPreview: View {
    let session: TerminalSession
    @Environment(SettingsManager.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    /// The window's settings (W20, W22): a card looks like the terminal it shows.
    @Environment(\.glassWindowOverrides) private var windowSettings
    @State private var image: UIImage?

    var body: some View {
        let profile = TerminalWindowProfile.resolved(windowSettings, settings: settings)
        let look = profile.look
        ZStack {
            profile.theme.canvasBackgroundColor.color.opacity(look.opacity)
            if let tint = look.tintColor {
                tint.opacity(TerminalCanvasTint.strength(canvasOpacity: look.opacity))
            }
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView("Preparing preview")
            }
        }
        .modifier(GlassWindowBackground(
            interactive: false, material: look.material,
            blurAmount: look.blur, appearance: profile.theme.resolvedAppearance
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

/// A terminal window's sidebar beside its terminals, from the second terminal on (the owner,
/// 2026-10-21), laid out as the headset's database, editor, Files and Connections lay theirs
/// (`GlassSpatialSplitView`, W33): Apple's split view draws glass behind every column that nothing
/// clears, and a Glass window is completely clear at Glass 0. The sidebar has Apple's glass of its
/// own, as the system's sidebar column does; the terminal beside it keeps the window's.
///
/// The window widens by the sidebar as its second terminal arrives and narrows as the last but one
/// leaves (`glassAdditiveSidebar`), as a Mac window does, and as its toggle in the window's bar shows
/// and hides it (the owner, 2026-10-21: "We need a sidebar/tabs toggle in the bottom ornaments").
/// The grid, the carousel and the orb hide it and keep the window's size, as the Mac's overview does.
private struct VisionTerminalSidebarLayout<Sidebar: View, Detail: View>: View {
    /// Two or more terminals: the window has the sidebar's room.
    let hasTabs: Bool
    /// The window's toggle leaves it shown.
    let wanted: Bool
    /// The tabs layout, not the grid or the carousel.
    let showsTabs: Bool
    @ViewBuilder let sidebar: Sidebar
    @ViewBuilder let detail: Detail

    @Environment(\.glassSessionOrb) private var orb
    @State private var visibility = NavigationSplitViewVisibility.detailOnly

    var body: some View {
        let shown = hasTabs && wanted && showsTabs && orb?.isOrb != true
        // The sidebar in its own glass, apart from the terminal, which keeps the window's (the owner's
        // choice, 2026-10-21: "Ours, in its own glass").
        GlassSpatialSplitView(visibility: $visibility, showsToggle: false, sidebarHasGlass: true) {
            sidebar
        } content: {
            detail
        }
        .onChange(of: shown, initial: true) { _, shown in
            withAnimation(.easeInOut(duration: 0.25)) { visibility = shown ? .all : .detailOnly }
        }
        // Its room, given and taken back as the second terminal comes and goes and as its toggle
        // shows and hides it.
        .glassAdditiveSidebar(isOpen: hasTabs && wanted, width: GlassSpatialColumns.sidebarIdealWidth)
    }
}

/// One terminal in the window's sidebar, as a Mac tab's row (`MacWorkspaceView.tabRow`): its name,
/// and under it where it is — its repository and branch, its machine, in tmux — in its state's
/// colour while not connected; its agent's mark in the agent's colour, pulsing while it prints.
private struct VisionTerminalSidebarRow: View {
    let session: TerminalSession
    /// The mark's colour with no agent's own: the window's tint, else its workgroup's.
    let color: Color

    var body: some View {
        let name = TerminalWorkgroupOpening.label(session, on: .tabBar)
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .lineLimit(1)
                Text(whereItIs)
                    .font(.caption)
                    .foregroundStyle(session.state == .connected ? Color.secondary : VisionTerminalStatus.color(for: session.state))
                    .lineLimit(1)
            }
        } icon: {
            TerminalSessionMark(session: session, color: color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
        .accessibilityValue(whereItIs)
    }

    private var whereItIs: String {
        let machine = "\(session.server.username)@\(session.server.host)"
        var line = session.repositoryLine.map { "\($0) · \(machine)" } ?? machine
        if session.survivesClose { line += " · in tmux" }
        if session.state != .connected { line += " — \(session.state.displayName)" }
        return line
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
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// iPad: **Move Tab to New Window** opens another window; an iPhone has one.
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
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
    /// Set once this view has left a workgroup that emptied, so it leaves once.
    @State private var didLeaveEmptiedWorkgroup = false
    #if os(visionOS)
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State var spatialPresentation = VisionTerminalPresentationState()
    /// Output in this window's terminals, for its orb's pulse.
    @State private var activity = TerminalWindowActivity()
    @FocusState private var overviewFocused: Bool
    /// The grid card a dragged tab is over (W15).
    @State private var dropTargetSessionID: UUID?
    /// Whether the window shows its sidebar, as its bar's toggle leaves it.
    @State private var showsSidebar = true

    private var presentation: VisionTerminalPresentation {
        get { spatialPresentation.mode }
        nonmutating set { spatialPresentation.mode = newValue }
    }

    private var presentationBinding: Binding<VisionTerminalPresentation> {
        Binding(get: { spatialPresentation.mode }, set: { spatialPresentation.mode = $0 })
    }

    #if DEBUG
    /// Screenshots only (`GlassTerminalRuntime.requestDemoTabs`): workgroups whose window opens in
    /// the grid.
    static var demoOpensGrid: Set<UUID> = []
    #endif
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
            #if DEBUG && os(visionOS)
            if Self.demoOpensGrid.remove(workgroupID) != nil { presentation = .grid }
            #endif
        }
        // A link held on a path (2026-10-15): Open in Editor, Show in Files and Watch Log File for
        // each terminal here, again as terminals come and go.
        .task(id: sessionManager.workgroup(for: workgroupID)?.sessionIDs ?? []) {
            for session in sessionManager.sessions(inWorkgroup: workgroupID) {
                TerminalPathActions.install(on: session) { [weak session] path in
                    if let session { watchFile(path, printedBy: session) }
                }
                #if os(visionOS)
                // Its output, for the orb's pulse.
                let id = session.id
                session.terminalHostModel.onOutputActivity = { [weak activity] in activity?.note(id) }
                #endif
            }
        }
        #if os(visionOS)
        // Auto-focus on activity: in the grid and carousel, the terminal printing comes forward.
        .onChange(of: activity.lastSessionID) { _, printing in
            guard let printing, followsActivity, presentation != .tabs, selectedSessionID != printing else { return }
            selectedSessionID = printing
        }
        #endif
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
        // W15: a workgroup whose last tab moved to another window, or that Active closed, is
        // gone: its window closes, as a Mac window does when its last tab leaves; an iPhone or
        // iPad goes back to the library.
        .onChange(of: sessionManager.workgroup(for: workgroupID) == nil) { wasGone, isGone in
            if !wasGone, isGone { leaveEmptiedWorkgroup() }
        }
        .focusedSceneValue(
            \.platformNewTerminalAction,
            PlatformNewTerminalAction(title: "New Terminal Tab") {
                showingSavedHostPicker = true
            }
        )
        // W20, W22: this window's own settings, for every terminal, card and sheet in it — and for
        // its glass (`GlassLayeredWindow`). A terminal moved in takes them, since it is drawn here
        // now. The workgroup's id is where This Window writes them.
        .glassWindowOverrides(sessionManager.workgroup(for: workgroupID)?.windowSettings ?? GlassWindowOverrides())
        .environment(\.terminalWorkgroupID, workgroupID)
        #if os(visionOS)
        // The window's glass, once, behind every terminal, card and message in it: the window is
        // plain, and this is as much of Apple's glass as its Blur asks for (2026-10-10). The same
        // glass every plain Glass window draws (`GlassSpatialWindowGlass`, W28).
        .glassSpatialWindowGlass(strength: windowLook.windowGlass(reduceTransparency: reduceTransparency))
        // Shrinks into an orb with the terminal in front live on its face (2026-10-15).
        .glassSessionOrb(orbFace)
        #endif
    }

    #if os(visionOS)
    /// Auto-focus on activity (the owner, 2026-10-15): the window's own, in This Window, else the
    /// saved Workgroup's it was opened from, else off.
    private var followsActivity: Bool {
        sessionManager.workgroup(for: workgroupID)?.windowSettings[TerminalWindowSettings.autoFocusOnActivity]
            ?? settingsManager.layoutPresets.first { $0.id == workgroupID }?.autoFocusOnActivity
            ?? false
    }

    /// This window as its orb: the terminal in front, live; pulsing while a terminal here prints, when
    /// the window has Auto-focus on activity (the owner's choice of switch).
    private var orbFace: GlassSessionOrbFace {
        let workgroup = sessionManager.workgroup(for: workgroupID)
        let title = workgroup.map { GlassTerminalCapability.title(of: $0, live: liveSessions(in: $0)) } ?? "Terminal"
        let sessionManager = sessionManager, workgroupID = workgroupID
        // The terminal in front, or the one printing where the window follows activity (the owner:
        // "front tab, or whichever is active").
        let shown = (followsActivity ? activity.lastSessionID : nil) ?? selectedSessionID
        let tabs = workgroup.map { liveSessions(in: $0) } ?? []
        let markColor = windowLook.tintColor ?? workgroup?.colorTag.color ?? .secondary
        return GlassSessionOrbFace(
            title: title, symbolName: "terminal", pulses: followsActivity && activity.isBusy,
            // With two or more terminals the view menu offers the orb; alone, the bar's button does.
            tabs: tabs.map { session in
                GlassSessionOrbTab(
                    id: session.id.uuidString,
                    title: TerminalWorkgroupOpening.label(session, on: .tabOrnament),
                    symbolName: "terminal",
                    tint: VisionTerminalStatus.color(for: session.state),
                    // Its agent, in its colour and pulsing while it works, as its sidebar row shows it.
                    icon: AnyView(TerminalSessionMark(session: session, color: markColor, size: GlassSessionOrbTab.iconSize)),
                    picture: { [weak session] in
                        session?.terminalHostModel.previewImage(maxPixelWidth: 400).map(Image.init(uiImage:))
                    },
                    select: { _ = sessionManager.selectSession(session.id, inWorkgroup: workgroupID) })
            },
            showsButton: tabs.count < 2
        ) {
            let front = shown.flatMap { sessionManager.session(for: $0) } ?? sessionManager.selectedSession(inWorkgroup: workgroupID)
            return front?.terminalHostModel.previewImage(maxPixelWidth: 400).map(Image.init(uiImage:))
        }
    }
    #endif

    #if os(visionOS)
    /// The canvas look of this window: its own settings over the terminal settings.
    private var windowLook: TerminalLook {
        TerminalLook.resolved(sessionManager.workgroup(for: workgroupID)?.windowSettings ?? GlassWindowOverrides(),
                              settings: settingsManager)
    }
    #endif

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

    /// A tab's menu, as the Mac's names it.
    @ViewBuilder
    private func tabActions(for session: TerminalSession) -> some View {
        renameActions(for: session)
        TerminalTabMoveActions(workgroupID: workgroupID, canMoveToNewWindow: canMoveToNewWindow,
                               moveToNewWindow: { moveToNewWindow(session) },
                               move: { destination in move(session, to: destination) })
    }

    // MARK: Moving tabs (W15, 2026-10-09)
    //
    // The owner, on the Vision Pro: "We also have no way to move tabs from one window to another."
    // A tab's menu moves it — its terminal still running, the same session — to a new window or
    // into another open one, whose name the menu shows as Active does. On Vision Pro a grid card
    // also drags onto another terminal window. A window whose last tab leaves closes.
    //
    // W26 (2026-10-10): "we still don't have a way to combine two independent terminal windows
    // there's no tab to drag between". A window with one terminal shows no tab bar, so the same
    // moves are in the terminal's tools menu, and on Vision Pro its title drags as a card does.

    /// A new window for a tab that leaves others behind; on iPhone there is only the one window.
    private var canMoveToNewWindow: Bool {
        guard TerminalTabMoves.canMoveToNewWindow(from: workgroupID, in: sessionManager) else { return false }
        #if os(visionOS)
        return true
        #else
        return supportsMultipleWindows && runtime != nil
        #endif
    }

    /// The same moves, for a terminal's tools menu and its title (W26): a window with one terminal
    /// has no tab bar to hold them. Handed down rather than rebuilt in the terminal, since opening,
    /// bringing forward and closing windows is this view's.
    private var tabMoving: TerminalTabMoving {
        TerminalTabMoving(canMoveToNewWindow: canMoveToNewWindow,
                          moveToNewWindow: { moveToNewWindow($0) },
                          move: { move($0, to: $1) })
    }

    private func moveToNewWindow(_ session: TerminalSession) {
        guard let created = TerminalTabMoves.moveToNewWorkgroup(session.id, in: sessionManager) else { return }
        #if os(visionOS)
        openWindow(id: "terminal", value: created)
        #else
        // A new library window, which shows the workgroup as it appears.
        runtime?.requestWindow(showing: created)
        openWindow(id: "main")
        #endif
        afterMovingOut()
    }

    private func move(_ session: TerminalSession, to destination: UUID) {
        guard case .moved(let sourceClosed) = TerminalTabMoves.move(session.id, to: destination, at: nil,
                                                                    in: sessionManager) else { return }
        #if os(visionOS)
        // Brings the window it went to forward.
        openWindow(id: "terminal", value: destination)
        #else
        // The last tab gone, the screen follows it rather than going back to the library.
        if sourceClosed { iOSRouter.showTerminal(workgroupID: destination) }
        #endif
        afterMovingOut()
    }

    private func afterMovingOut() {
        if sessionManager.workgroup(for: workgroupID) == nil {
            leaveEmptiedWorkgroup()
        } else {
            synchronizeSelection()
        }
    }

    /// This workgroup is gone: on Vision Pro its window closes; on iPhone and iPad, a window still
    /// showing it goes back to the library.
    private func leaveEmptiedWorkgroup() {
        guard !didLeaveEmptiedWorkgroup else { return }
        didLeaveEmptiedWorkgroup = true
        #if os(visionOS)
        dismiss()
        #else
        if iOSRouter.terminalWorkgroupID == workgroupID { iOSRouter.showConnections() }
        #endif
    }

    #if os(visionOS)
    /// Tabs dragged here: from another window they move in at `index` (nil: after the last) and
    /// are selected; from this one, one takes the place it is dropped on.
    @discardableResult
    private func acceptDroppedTabs(_ tabs: [TerminalTabTransfer], at index: Int?) -> Bool {
        var moved = false
        var position = index
        for tab in tabs {
            switch TerminalTabMoves.move(tab.sessionID, to: workgroupID, at: position, in: sessionManager) {
            case .refused:
                continue
            case .reordered:
                moved = true
            case .moved:
                moved = true
                position = position.map { $0 + 1 }
            }
        }
        if moved { synchronizeSelection() }
        return moved
    }
    #endif

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
            // A container of its own, or its name is every view's inside it: the sidebar's rows lost
            // theirs (2026-10-21), as the iPhone's controls had.
            .accessibilityElement(children: .contain)
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
                    // A container of its own, or the name is every control's inside it, and a
                    // test finds none of them by theirs (2026-10-21, the Duo's laptop bar).
                    .accessibilityElement(children: .contain)
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
                    // A container of its own, or the name is every control's inside it, and a
                    // test finds none of them by theirs (2026-10-21, the Duo's laptop bar).
                    .accessibilityElement(children: .contain)
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
        // The window's tabs are its sidebar, as a Mac window's are, once it holds two terminals (the
        // owner, 2026-10-21). They were Apple's tab bar, which Apple keeps for an app's sections:
        // a column of identical terminal symbols at the window's side until looked at, one short
        // line each, covering the terminal while open. A sidebar row says where each is, shows its
        // agent at work, and drags.
        VisionTerminalSidebarLayout(hasTabs: sessions.count > 1, wanted: showsSidebar, showsTabs: presentation == .tabs) {
            terminalSidebar(workgroup: workgroup, sessions: sessions)
        } detail: {
            spatialTerminals(sessions: sessions)
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

    /// The sidebar: each terminal as a Mac tab's row. A pinch shows it; a pinch held offers its
    /// menu, and moving the hand drags it — onto another terminal window to move it there, onto
    /// another row here to take that place, or into empty space for a window of its own.
    private func terminalSidebar(workgroup: TerminalWorkgroup, sessions: [TerminalSession]) -> some View {
        List(selection: $selectedSessionID) {
            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                VisionTerminalSidebarRow(session: session, color: windowLook.tintColor ?? workgroup.colorTag.color)
                    .glassSpatialListRow()
                    .contextMenu { tabActions(for: session) }
                    .onDrag {
                        TerminalTabDrag.itemProvider(TerminalTabTransfer(workgroupID: workgroupID, sessionID: session.id))
                    }
                    .dropDestination(for: TerminalTabTransfer.self) { tabs, _ in
                        acceptDroppedTabs(tabs, at: index)
                    }
                    .accessibilityIdentifier("vision-terminal-sidebar-row-\(session.id.uuidString)")
            }
        }
        .glassSpatialList()
        // A tab from another window let go below the rows joins after the last.
        .dropDestination(for: TerminalTabTransfer.self) { tabs, _ in
            acceptDroppedTabs(tabs, at: nil)
        }
        .accessibilityIdentifier("vision-terminal-sidebar")
        // The window's name, its Workgroup's or its machine's, in the header every Glass window's
        // sidebar has.
        .glassSpatialColumn(workgroup.name)
    }

    /// Every terminal in the window, the one shown in front, and the grid and carousel over them.
    private func spatialTerminals(sessions: [TerminalSession]) -> some View {
        ZStack {
            ForEach(sessions) { session in
                let active = presentation == .tabs && selectedSessionID == session.id
                TerminalWindowView(
                    session: session,
                    ownsSessionLifecycle: false,
                    showsConnectionOrnament: true,
                    isTerminalActive: active,
                    onNewTerminalTab: { showingSavedHostPicker = true },
                    onOpenTerminal: { openSavedHost($0, tmux: $1) },
                    onSessionRequestedClose: { closeSessionTab(session) }
                )
                .environment(\.visionTerminalPresentation, sessions.count > 1 ? presentationBinding : nil)
                .environment(\.visionTerminalSidebar, sessions.count > 1 ? $showsSidebar : nil)
                // A grid card or a terminal's title from another window, dropped on the terminal: it
                // joins this window. This window's own title let go over it changes nothing (W26).
                .environment(\.terminalTabDrop, { tabs in
                    _ = acceptDroppedTabs(TerminalTabMoves.arriving(tabs, at: workgroupID, in: sessionManager), at: nil)
                })
                // W26: its tools menu and its title move it, with one terminal in the window or many.
                .environment(\.terminalTabMoving, tabMoving)
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
                // The grid's and the carousel's controls: Apple's toolbar ornament, as a terminal's
                // are (W31), and in the same place. Never both: in the grid and the carousel no
                // terminal is in front, so none contributes its own.
                .toolbar {
                    if presentation != .tabs && sessions.count > 1 {
                        ToolbarItemGroup(placement: .bottomOrnament) {
                            VisionTerminalPresentationPicker(selection: presentationBinding)
                            // Icons only, as the toolbar draws a label by default.
                            Button("Previous", systemImage: "chevron.left") {
                                moveOverviewSelection(-1, sessions: sessions)
                            }
                            Button("Next", systemImage: "chevron.right") {
                                moveOverviewSelection(1, sessions: sessions)
                            }
                            Button("Open Terminal", systemImage: "arrow.up.forward") {
                                presentation = .tabs
                            }
                            .labelStyle(.titleAndIcon)
                        }
                    }
                }
        }
    }

    private func spatialOverview(sessions: [TerminalSession]) -> some View {
        GeometryReader { geometry in
            Group {
                if presentation == .grid {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 24)], spacing: 24) {
                            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                                draggableCard(session, at: index)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
            // A tab from another window dropped anywhere but on a card joins after the last.
            .dropDestination(for: TerminalTabTransfer.self) { tabs, _ in
                acceptDroppedTabs(tabs, at: nil)
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
            // Where a dragged tab would land.
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.accentColor.opacity(dropTargetSessionID == session.id ? 0.22 : 0))
            }
            .contentShape(.interaction, RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        // A terminal preview is a large interaction target, not a glass button.
        // The system highlight fills it with an oversized gaze capsule.
        .hoverEffectDisabled()
        .focusEffectDisabled()
        .contextMenu { tabActions(for: session) }
        .accessibilityLabel("Open \(TerminalWorkgroupOpening.label(session, on: surface)) terminal")
        .accessibilityValue(session.state.displayName)
    }

    /// A grid card that drags (W15; the owner: "maybe we do that with grid view? drag and drop"):
    /// onto another terminal window to move the tab there, still running, or onto another card
    /// here to take its place. The card itself takes a dropped tab at its own place.
    private func draggableCard(_ session: TerminalSession, at index: Int) -> some View {
        overviewCard(session, on: .grid)
            .draggable(TerminalTabTransfer(workgroupID: workgroupID, sessionID: session.id))
            .dropDestination(for: TerminalTabTransfer.self) { tabs, _ in
                acceptDroppedTabs(tabs, at: index)
            } isTargeted: { targeted in
                if targeted {
                    dropTargetSessionID = session.id
                } else if dropTargetSessionID == session.id {
                    dropTargetSessionID = nil
                }
            }
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
                    onOpenTerminal: { openSavedHost($0, tmux: $1) },
                    onSessionRequestedClose: { closeSessionTab(session) }
                )
                .opacity(active ? 1 : 0)
                .allowsHitTesting(active)
                .accessibilityHidden(!active)
                .accessibilityElement(children: .contain)
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
                onOpenTerminal: { openSavedHost($0, tmux: $1) },
                onSessionRequestedClose: {
                    closeSessionTab(session)
                }
            )
            // iPad (W26): a tab's own menu is drawn only in the sidebar, so Tools moves it too.
            .environment(\.terminalTabMoving, tabMoving)
            // A container of its own, so the controls inside keep their names (2026-10-21).
            .accessibilityElement(children: .contain)
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
        .contextMenu { tabActions(for: session) }
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
            // A tap is the picker; held, servers ▸ their terminals, opened here (2026-10-15).
            TerminalNewTabMenu(pickServer: { showingSavedHostPicker = true },
                               open: { openSavedHost($0, tmux: $1) }) {
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
            // The terminal on screen, as a Mac tab's menu names it (W11), and where it can move (W15).
            if let shown = sessions.first(where: { $0.id == selectedSessionID }) ?? sessions.first {
                Divider()
                tabActions(for: shown)
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
        // **In the terminal's own light or dark** (the owner, 2026-10-15: "theres no way to switch
        // tabs on iphone"). The title sits over the terminal, not over a bar, and in light mode its
        // text was drawn black on a dark theme's black: the switcher was there and could not be
        // seen. A theme that follows the system leaves it to the system.
        .environment(\.colorScheme, themeColorScheme ?? systemColorScheme)
        .accessibilityLabel("Terminal Sessions")
        .accessibilityValue(selectedSessionName(in: sessions))
        .accessibilityIdentifier("terminal-workgroup-session-switcher")
    }

    /// This window's terminal theme's light or dark; nil for a theme that follows the system.
    private var themeColorScheme: ColorScheme? {
        TerminalWindowProfile.resolved(sessionManager.workgroup(for: workgroupID)?.windowSettings ?? GlassWindowOverrides(),
                                       settings: settingsManager).theme.resolvedAppearance.colorScheme
    }

    private func selectedSessionName(in sessions: [TerminalSession]) -> String {
        let position = sessions.firstIndex(where: { $0.id == selectedSessionID }) ?? 0
        guard sessions.indices.contains(position) else { return "Session" }
        return TerminalWorkgroupOpening.slotTitle(sessions[position], position: position)
    }
    #endif

    /// iPhone and iPad: the slot on screen connects if it needs to, and the hidden ones wait to be
    /// shown (W4b). An iPad makes slots only for a workgroup it reopens at launch (W15); one it
    /// opens otherwise has no slots, and this does nothing. Vision Pro keeps every terminal
    /// connected for its previews.
    private func connectShownSlot() {
        #if os(iOS)
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

    /// `tmux`: attached to a session already running there, from the + menu (2026-10-15).
    /// `startupCommand` and `configure`: a terminal made for something, as Watch Log File's is.
    private func openSavedHost(_ server: ServerConfiguration, tmux: TerminalTmuxAttachment? = nil,
                               startupCommand: String? = nil,
                               configure: (@MainActor (TerminalSession) -> Void)? = nil) {
        guard openingServerID == nil else { return }
        openingServerID = server.id

        Task { @MainActor in
            defer { openingServerID = nil }
            do {
                let launch = try await sessionManager.createAuthorizedSessionByServerID(
                    server.id,
                    settingsManager: settingsManager,
                    startupCommand: startupCommand,
                    tmux: tmux,
                    configure: configure,
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

    /// Watch Log File, held on a path a terminal here printed (2026-10-15, as the Mac's of
    /// 2026-10-14): a tab of this window on the same host, following the file (`tail -F`) in a
    /// plain shell, named after it.
    private func watchFile(_ path: String, printedBy session: TerminalSession) {
        Task { @MainActor in
            var directory: String?
            if TerminalWatchFile.isRelative(path) {
                directory = TerminalRepository.path(
                    fromReported: await session.workingDirectory(reported: session.terminalHostModel.currentDirectory))
            }
            guard let command = TerminalWatchFile.command(for: path, in: directory) else { return }
            let label = TerminalWatchFile.tabLabel(for: path)
            openSavedHost(session.server, startupCommand: command) { watching in
                watching.withoutTmux = true
                watching.workgroupLabel = label
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
            leaveEmptiedWorkgroup()
            #else
            iOSRouter.showConnections()
            #endif
        } else {
            synchronizeSelection()
        }
    }

    private func showConnections() {
        #if os(visionOS)
        openWindow.openConnections()
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

/// A tab's **Move Tab to New Window** and **Move Tab To** (W15), in its menu and, for the terminal
/// on screen, in the terminal's tools menu (W26). A view of its own, so the other windows' names it
/// shows are read here: read by the terminal window itself, a name changing in any window would
/// redraw every terminal window.
struct TerminalTabMoveActions: View {
    let workgroupID: UUID
    let canMoveToNewWindow: Bool
    /// The tools menu's form (W26): one **Move Tab To** row holding **New Window** as well, with no
    /// divider of its own. That menu shows 640 points in a terminal window of the default size and
    /// already filled about 595 of them in a Release build (651 in Debug, with HTML Preview); two
    /// rows and a divider put its last item, Settings, out of sight below the fold (measured in the
    /// visionOS simulator, 2026-10-10).
    var asOneRow = false
    let moveToNewWindow: () -> Void
    let move: (UUID) -> Void
    @Environment(SessionManager.self) private var sessionManager

    /// The other workgroups a tab can go to: on Vision Pro those with a window open, elsewhere
    /// every one with live terminals (iPhone and iPad show one at a time; Active lists the rest).
    private var destinations: [TerminalTabMoves.Destination] {
        #if os(visionOS)
        TerminalTabMoves.destinations(from: workgroupID, among: TerminalWorkgroupsToReopen.shared.openWindowIDs,
                                      in: sessionManager)
        #else
        TerminalTabMoves.destinations(from: workgroupID, among: nil, in: sessionManager)
        #endif
    }

    var body: some View {
        let destinations = self.destinations
        if asOneRow {
            if canMoveToNewWindow || !destinations.isEmpty {
                Menu("Move Tab To", systemImage: "rectangle.portrait.and.arrow.right") {
                    if canMoveToNewWindow {
                        Button("New Window", systemImage: "macwindow.badge.plus", action: moveToNewWindow)
                    }
                    if canMoveToNewWindow && !destinations.isEmpty {
                        Divider()
                    }
                    ForEach(destinations) { destination in
                        Button(destination.title) { move(destination.id) }
                    }
                }
            }
        } else {
            separateRows(destinations)
        }
    }

    @ViewBuilder
    private func separateRows(_ destinations: [TerminalTabMoves.Destination]) -> some View {
        if canMoveToNewWindow || !destinations.isEmpty {
            Divider()
        }
        if canMoveToNewWindow {
            Button("Move Tab to New Window", systemImage: "macwindow.badge.plus", action: moveToNewWindow)
        }
        if !destinations.isEmpty {
            Menu("Move Tab To", systemImage: "rectangle.portrait.and.arrow.right") {
                ForEach(destinations) { destination in
                    Button(destination.title) { move(destination.id) }
                }
            }
        }
    }
}
#endif
