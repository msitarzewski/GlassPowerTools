//
//  SSHWakeWatcher.swift
//  Glass Power Tools — GlassTerminal
//
//  After the Mac wakes, or the app comes back to the foreground on iPhone, iPad and Vision Pro,
//  every SSH connection is asked to answer at once (2026-10-12, B-X25). One that died while the
//  device slept — a laptop lid closed, a phone in a pocket — used to look alive: a terminal took
//  typing and showed nothing, and a project or a tunnel stalled, until TCP gave up minutes later.
//  Now it is shown lost within seconds, with the Reconnect every surface already has, and a
//  terminal in tmux reattaches to what was running.
//

import Foundation
import GlassSSHTransport
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@MainActor
final class SSHWakeWatcher {
    // Written once, in `init`; read once, in `deinit`.
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    init() {
        #if os(macOS)
        let center = NSWorkspace.shared.notificationCenter
        let name = NSWorkspace.didWakeNotification
        #elseif canImport(UIKit)
        let center = NotificationCenter.default
        let name = UIApplication.willEnterForegroundNotification
        #endif
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
            Task { await SSHLiveTransports.shared.checkAllAlive() }
        })
    }

    deinit {
        #if os(macOS)
        let center = NSWorkspace.shared.notificationCenter
        #else
        let center = NotificationCenter.default
        #endif
        for observer in observers { center.removeObserver(observer) }
    }
}
