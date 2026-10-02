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
    public override init() { super.init() }
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
        let needsConfirmation = windows.contains { $0.requiresCloseConfirmation }
            || (settingsManager?.confirmBeforeClosing == true && sessions.contains(where: \.closeStopsWork))
        if needsConfirmation {
            let alert = NSAlert()
            alert.messageText = "Quit \(GlassProduct.displayName)?"
            alert.informativeText = sessions.contains(where: \.survivesClose)
                ? "Terminals that aren't kept in tmux will be disconnected. Those in tmux keep running, and Active lists them."
                : "Running terminal sessions will be disconnected."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        }
        terminationInProgress = true
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
    var showsWorkgroups = false
    var showsTailscale = false
    var sftpContext: SFTPBrowserContext?

    func showTerminal(workgroupID: UUID) {
        sftpContext = nil
        mostRecentTerminalWorkgroupID = workgroupID
        terminalWorkgroupID = workgroupID
    }

    func showConnections() {
        sftpContext = nil
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


/// Slowly spinning terminal icon shown when Connections is closed as the last window.
/// Tapping it restores the full Connections window and dismisses this proxy.
struct MinimizedConnectionsView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Button {
            openWindow(id: "main")
            dismissWindow(id: "minimized")
        } label: {
            Image(systemName: "terminal")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .symbolEffect(.rotate, options: .repeat(.continuous))
                .padding(28)
                .background(.regularMaterial, in: .circle)
        }
        .buttonStyle(.plain)
        .terminalHoverHighlight()
        .help("Open Connections")
        .accessibilityLabel("Open Connections")
    }
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
