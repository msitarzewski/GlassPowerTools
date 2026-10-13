//
//  glas_shApp.swift
//  glas.sh
//
//  Created by Michael Sitarzewski on 9/10/25.
//

import SwiftUI
import GlassLayers
import GlassShell
import GlassConnectionKit
import os
#if os(macOS)
import AppKit

@MainActor
public final class MacTerminalAppDelegate: NSObject, NSApplicationDelegate {
    public override init() {
        super.init()
        // D54: AppKit replays saved window state before any delegate is asked, under SwiftUI's own
        // delegate; this preference makes it skip that state at launch. The app's records reopen
        // its windows (2026-10-09: a leftover state kept restoring empty terminal windows).
        UserDefaults.standard.register(defaults: [Self.ignoresSavedWindowStateKey: true])
    }

    /// AppKit's preference to skip saved window state at launch.
    static let ignoresSavedWindowStateKey = "ApplePersistenceIgnoreState"

    var sessionManager: SessionManager?
    var settingsManager: SettingsManager?
    private var terminationInProgress = false

    // MARK: Live library updates (D19)
    //
    // macOS allows one application delegate and the terminal already owns it, so the shell's
    // receiver is called from here rather than taking a second one. The three methods below are
    // the whole of it; the reconciling happens in `GlassShellModel`.

    public func applicationDidFinishLaunching(_ notification: Notification) {
        GlassRemoteChangeReceiver.register()
    }

    /// What answers the app's Finder services (`NSServices`), set by the composition root before
    /// launch finishes (D72).
    public static var servicesProvider: AnyObject?
    /// The Dock icon's menu, built by the composition root each time it opens (D72).
    public static var dockMenu: (@MainActor () -> NSMenu?)?

    public func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        Self.dockMenu?()
    }

    /// What is opened with the app — the Finder's Open With, a drop on the Dock icon, an `ssh://`
    /// link — taken here rather than by a scene's `onOpenURL` (D72; the owner, 2026-10-13: "Open with
    /// opens a new connections window along with the desired file"). SwiftUI delivers a URL to a
    /// scene by opening one of its windows when none is open, so every Open With brought up a
    /// Connections window too. Set by the composition root.
    public static var openURLs: (@MainActor ([URL]) -> Void)?

    public func application(_ application: NSApplication, open urls: [URL]) {
        Self.openURLs?(urls)
    }

    /// Settings ▸ Appearance's Light, Dark or System, before any window is shown; and the Finder
    /// services, ready for a service that launched the app.
    public func applicationWillFinishLaunching(_ notification: Notification) {
        GlassAppAppearance.install()
        if let provider = Self.servicesProvider {
            NSApp.servicesProvider = provider
            NSUpdateDynamicServices()
        }
    }

    // MARK: Window restoration (D54)
    //
    // The app reopens its windows from its own records, which know each terminal window's tabs.
    // AppKit's saved window state is neither written nor replayed: an hour with it turned on left
    // a saved state that AppKit then restored at every launch, as empty terminal windows beside
    // the app's own (2026-10-09).
    public func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
    public func application(_ app: NSApplication, shouldSaveSecureApplicationState coder: NSCoder) -> Bool { false }
    public func application(_ app: NSApplication, shouldRestoreSecureApplicationState coder: NSCoder) -> Bool { false }

    public func application(_ application: NSApplication,
                            didReceiveRemoteNotification userInfo: [String: Any]) {
        GlassRemoteChangeReceiver.handleRemoteNotification(userInfo)
    }

    public func application(_ application: NSApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        GlassRemoteChangeReceiver.registrationFailed(error)
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationInProgress else { return .terminateLater }
        let windows = MacTerminalWindowReader.Coordinator.active.allObjects
        let sessions = sessionManager?.sessions ?? []
        let windowMessage = windows.lazy.compactMap(\.quitConfirmationMessage).first
        let needsConfirmation = windowMessage != nil
            || (settingsManager?.confirmBeforeClosing == true && sessions.contains(where: \.closeStopsWork))
        if needsConfirmation {
            let alert = NSAlert()
            alert.messageText = "Quit \(GlassProduct.displayName)?"
            alert.informativeText = windowMessage ?? (sessions.contains(where: \.survivesClose)
                ? "Terminals that aren't kept in tmux will be disconnected. Those in tmux keep running, and Active lists them."
                : "Running terminal sessions will be disconnected.")
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        }
        terminationInProgress = true
        // Before the windows let go of their terminals: where each window is, and which hold
        // terminals in tmux, to open again at the next launch (D47, W12). The list is kept current
        // while the app runs, for a crash. A window closed by hand drops out of it; the windows
        // closing for this quit do not.
        MacWindowsToReopen.shared.prepareForQuit()
        // Keep the windows and their saved layouts intact for restoration while
        // finalizing recordings and stopping their local and remote processes.
        for window in windows { window.finishSessions() }
        sessionManager?.closeAllSessions()
        Task { @MainActor in
            for session in sessions { await session.awaitLifecycleCleanup() }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
#endif

@MainActor
struct PlatformNewTerminalAction {
    let title: String
    private let action: () -> Void

    init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    func callAsFunction() {
        action()
    }
}

private struct PlatformNewTerminalActionKey: FocusedValueKey {
    typealias Value = PlatformNewTerminalAction
}

extension FocusedValues {
    var platformNewTerminalAction: PlatformNewTerminalAction? {
        get { self[PlatformNewTerminalActionKey.self] }
        set { self[PlatformNewTerminalActionKey.self] = newValue }
    }
}

struct PlatformTerminalCommands: Commands {
    @FocusedValue(\.platformNewTerminalAction) private var newTerminalAction

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(newTerminalAction?.title ?? "New Terminal") {
                newTerminalAction?()
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(newTerminalAction == nil)
        }
    }
}


#if os(iOS)
@MainActor
@Observable
final class IOSAppRouter {
    var terminalWorkgroupID: UUID?
    private(set) var mostRecentTerminalWorkgroupID: UUID?
    var showsTailscale = false
    var sftpContext: SFTPBrowserContext?

    func showTerminal(workgroupID: UUID) {
        sftpContext = nil
        mostRecentTerminalWorkgroupID = workgroupID
        terminalWorkgroupID = workgroupID
        // W15: the workgroup on screen is shown again after a relaunch.
        TerminalWorkgroupsToReopen.shared.noteShown(workgroupID)
    }

    func showConnections() {
        sftpContext = nil
        TerminalWorkgroupsToReopen.shared.noteShown(nil, replacing: terminalWorkgroupID)
        terminalWorkgroupID = nil
    }

    func liveWorkgroups(in sessionManager: SessionManager) -> [TerminalWorkgroup] {
        sessionManager.workgroups.filter { workgroup in
            workgroup.sessionIDs.contains { sessionManager.session(for: $0) != nil }
        }
    }

    func resumableWorkgroupID(in sessionManager: SessionManager) -> UUID? {
        let liveWorkgroups = liveWorkgroups(in: sessionManager)
        if let mostRecentTerminalWorkgroupID,
           liveWorkgroups.contains(where: { $0.id == mostRecentTerminalWorkgroupID }) {
            return mostRecentTerminalWorkgroupID
        }
        return liveWorkgroups.last?.id
    }

    @discardableResult
    func resumeTerminal(
        workgroupID: UUID,
        in sessionManager: SessionManager
    ) -> Bool {
        guard liveWorkgroups(in: sessionManager).contains(where: { $0.id == workgroupID }) else {
            return false
        }
        showTerminal(workgroupID: workgroupID)
        return true
    }

    @discardableResult
    func resumeMostRecentTerminal(in sessionManager: SessionManager) -> Bool {
        guard let workgroupID = resumableWorkgroupID(in: sessionManager) else {
            return false
        }
        showTerminal(workgroupID: workgroupID)
        return true
    }

    func showSFTP(sessionID: UUID) {
        sftpContext = SFTPBrowserContext(sessionID: sessionID)
    }
}

#endif

struct MainBootstrapView<Content: View>: View {
    let content: Content
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    @State private var didBootstrap = false
    #if DEBUG
    @State private var uiTestCredentialCleanupComplete = false
    #endif

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
        #if DEBUG
        .overlay(alignment: .topLeading) {
            if uiTestCredentialCleanupComplete {
                Text("UI test credential cleanup complete")
                    .font(.caption2)
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("ui-test-credential-cleanup-complete")
            }
        }
        #endif
        .task {
            guard !didBootstrap else { return }
            didBootstrap = true
            loadPersistentState()
            #if DEBUG
            await purgeUITestCredentialsIfRequested()
            #endif
        }
        // NOTE: We intentionally do NOT close sessions on scenePhase == .background.
        // On visionOS, closing the Connections window (or glancing away) backgrounds
        // this scene — which would kill every live terminal and orphan its window into
        // "Session not found". Sessions are ephemeral and the OS tears down sockets on
        // actual app termination; TerminalSession.deinit cancels outstanding tasks.
    }

    private func loadPersistentState() {
        SharedDefaults.migrateIfNeeded()
        sessionManager.preloadPersistentStateIfNeeded()
        settingsManager.loadPersistentStateIfNeeded()
    }

    #if DEBUG
    private func purgeUITestCredentialsIfRequested() async {
        guard ProcessInfo.processInfo.environment[
            "GLAS_UI_TEST_CREDENTIAL_CLEANUP"
        ] == "1" else { return }
        do {
            try await sessionManager.serverManager.purgeConnectionLibraryUITestFixtures()
            uiTestCredentialCleanupComplete = true
        } catch {
            Logger.keychain.error(
                "UI test credential cleanup failed: \(error.localizedDescription)"
            )
        }
    }
    #endif

}


struct SFTPBrowserNotFoundView: View {
    let context: SFTPBrowserContext?
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.fill.badge.questionmark")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text("SFTP browser unavailable")
                .font(.title3)
                .fontWeight(.semibold)

            Text("This SFTP window's source session is no longer active.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            Button("Close Window") {
                if let context {
                    dismissWindow(id: "sftp", value: context)
                } else {
                    dismissWindow(id: "sftp")
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }
}

#if DEBUG
struct HTMLPreviewNotFoundView: View {
    let context: HTMLPreviewContext?
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text("Preview unavailable")
                .font(.title3)
                .fontWeight(.semibold)

            Text("This preview window's source session is no longer active.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)

            Button("Close Window") {
                if let context {
                    dismissWindow(id: "html-preview", value: context)
                } else {
                    dismissWindow(id: "html-preview")
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }
}
#endif
