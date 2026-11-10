//
//  TerminalConnectionNotice.swift
//  GlassTerminal
//
//  A terminal without its connection says so in the window itself (the owner, 2026-11-10: "a
//  disconnected terminal shows a red text under the name in the tab, but the window itself still
//  shows what looks like a connected window … Dim the window, add a close or reconnect UI to the
//  center of the window"). Its text dims, and a panel in the middle says what happened, with
//  Reconnect and Close Terminal; while auto-reconnect works, its progress and Cancel Reconnect. The
//  database's window (`DatabaseWorkspaceView.connectionRecoveryOverlay`) and the remote desktop's
//  (`DesktopSessionView.connectionStatus`) already did this for theirs.
//

import SwiftUI

/// What the panel over a terminal without its connection says, or nil while the terminal is live
/// or on its way to its first connection.
struct TerminalConnectionNotice: Equatable {
    enum Kind: Equatable {
        /// Auto-reconnect, or a Reconnect, is on its way: a spinner.
        case reconnecting
        /// Lost, failed or ended: Reconnect.
        case down
    }

    var kind: Kind
    var title: String
    var message: String?
    /// Auto-reconnect is at work, and Cancel Reconnect stops it. A Reconnect someone chose has
    /// nothing to cancel it with; Close Terminal still closes.
    var offersCancelReconnect: Bool

    /// How much of the terminal's text shows under the panel: dim, still readable, so the last of
    /// its output can be read, scrolled and copied.
    static let dimmedTextOpacity = 0.35

    /// - Parameters:
    ///   - hasConnected: it has been connected. Down before that and never failed, it is waiting for
    ///     its first connection (an iPhone's tab not yet shown) and says nothing; that first
    ///     connection shows where it always has.
    ///   - hasFailed: a connection of its has failed, so connecting again is a retry, shown here.
    ///   - shellEnded: an `exit` on a connection that stood: its window closes it.
    ///   - autoReconnectAttempt: auto-reconnect's try now (0 before its first), nil when it isn't at work.
    static func make(state: SessionState, hasConnected: Bool, hasFailed: Bool, shellEnded: Bool,
                     userDisconnected: Bool, autoReconnectAttempt: Int?,
                     maxAttempts: Int = TerminalSession.autoReconnectAttempts,
                     serverName: String) -> TerminalConnectionNotice? {
        if shellEnded || state == .connected { return nil }
        if let attempt = autoReconnectAttempt {
            return TerminalConnectionNotice(
                kind: .reconnecting, title: "Reconnecting…",
                message: attempt > 0 ? "Attempt \(attempt) of \(maxAttempts) to reach \(serverName)." : nil,
                offersCancelReconnect: true)
        }
        guard hasConnected || hasFailed else { return nil }
        switch state {
        case .connected:
            return nil
        case .connecting, .reconnecting:
            return TerminalConnectionNotice(kind: .reconnecting,
                                            title: hasConnected ? "Reconnecting…" : "Connecting…",
                                            message: nil, offersCancelReconnect: false)
        case .disconnected:
            if userDisconnected {
                return TerminalConnectionNotice(kind: .down, title: "Disconnected", message: nil,
                                                offersCancelReconnect: false)
            }
            return TerminalConnectionNotice(kind: .down, title: "Connection Lost",
                                            message: "The connection to \(serverName) ended.",
                                            offersCancelReconnect: false)
        case .error(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return TerminalConnectionNotice(kind: .down, title: hasConnected ? "Connection Lost" : "Couldn't Connect",
                                            message: trimmed.isEmpty ? nil : trimmed, offersCancelReconnect: false)
        }
    }
}

extension TerminalSession {
    /// What its window says over its text, now (`TerminalConnectionNotice`).
    var connectionNotice: TerminalConnectionNotice? {
        TerminalConnectionNotice.make(state: state, hasConnected: hasConnected, hasFailed: hasFailedToConnect,
                                      shellEnded: shellEnded, userDisconnected: userInitiatedDisconnect,
                                      autoReconnectAttempt: isAutoReconnecting ? reconnectAttemptCount : nil,
                                      serverName: server.name)
    }
}

/// The panel in the middle of a terminal without its connection.
struct TerminalConnectionNoticePanel: View {
    let notice: TerminalConnectionNotice
    /// The terminal theme's own light or dark; nil for a theme that follows the system.
    let terminalColorScheme: ColorScheme?
    let reconnect: () -> Void
    let cancelReconnect: () -> Void
    let close: () -> Void
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        panel
            #if !os(visionOS)
            // The terminal's light or dark, as the panel stands on its colour: the system's light material over a
            // dark terminal came out mid grey on the Mac, its grey words lost in it (2026-11-10, the macOS VM).
            // Vision Pro's glass is the system's own.
            .environment(\.colorScheme, terminalColorScheme ?? systemColorScheme)
            #endif
    }

    private var panel: some View {
        VStack(spacing: 14) {
            Group {
                switch notice.kind {
                case .reconnecting:
                    ProgressView()
                        .controlSize(.large)
                case .down:
                    Image(systemName: "bolt.horizontal.circle")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 40)

            VStack(spacing: 6) {
                Text(notice.title)
                    .font(.title2.bold())
                    .accessibilityIdentifier("terminal-connection-title")
                if let message = notice.message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        // Not selectable: on iPhone a selectable Text is drawn by UIKit, and under the panel's
                        // fade-in it drew nothing (2026-11-10, the simulator). The same words are in the
                        // terminal's own text, to copy from there.
                        .accessibilityIdentifier("terminal-connection-message")
                }
            }

            HStack(spacing: 10) {
                Button("Close Terminal", action: close)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("terminal-connection-close")
                switch notice.kind {
                case .down:
                    Button(action: reconnect) {
                        Label("Reconnect", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("terminal-connection-reconnect")
                case .reconnecting where notice.offersCancelReconnect:
                    Button("Cancel Reconnect", action: cancelReconnect)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("terminal-connection-cancel")
                case .reconnecting:
                    EmptyView()
                }
            }
            #if !os(visionOS)
            .controlSize(.large)
            #endif
            .padding(.top, 4)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: 420)
        #if os(visionOS)
        .glassBackgroundEffect(in: .rect(cornerRadius: 28, style: .continuous))
        #else
        .background(.regularMaterial, in: .rect(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 28, y: 10)
        #endif
        .padding(20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("terminal-connection-panel")
    }
}
