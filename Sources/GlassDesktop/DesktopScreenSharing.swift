//
//  DesktopScreenSharing.swift
//  Glass Power Tools — GlassDesktop
//
//  Open in Screen Sharing: a VNC desktop handed to Apple's own Screen Sharing app on the Mac.
//
//  glassDT offered it on a VNC connection's detail (`DesktopLibraryView.swift:274,310`); the merge
//  deleted that view and nothing replaced the button (found comparing the two, 2026-09-27). It is a
//  tool row on the host's detail now, beside the terminal's Files — the same idea: a separate app,
//  reached from the machine.
//
//  **Only the endpoint travels.** `vnc://host:port`, never a user or a password: Screen Sharing asks
//  for its own, from its own Keychain, and a credential in a URL would reach whatever handles it.
//

import Foundation
#if os(macOS)
import AppKit
#endif

enum DesktopScreenSharing {
    static let bundleIdentifier = "com.apple.ScreenSharing"

    /// The link Screen Sharing opens, or nil for a desktop that is not VNC or has no usable host.
    static func url(for connection: DesktopConnection) -> URL? {
        guard connection.protocol == .vnc else { return nil }
        let host = connection.host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "vnc"
        // An IPv6 literal goes in brackets, or the colons read as a port.
        components.host = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        components.port = Int(connection.port)
        return components.url
    }

    #if os(macOS)
    /// Opens `connection` in Screen Sharing — that app explicitly, not whatever claims `vnc:`.
    @MainActor
    static func open(_ connection: DesktopConnection, failure: @escaping @MainActor (String) -> Void) {
        guard let url = url(for: connection) else {
            failure("This desktop has no address Screen Sharing can open. Edit the service to add one.")
            return
        }
        let workspace = NSWorkspace.shared
        guard let application = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            workspace.open(url)
            return
        }
        workspace.open([url], withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error else { return }
            Task { @MainActor in failure("Screen Sharing could not be opened: \(error.localizedDescription)") }
        }
    }
    #endif
}
