//
//  GlassWindowRestoration.swift
//  Glass Power Tools — GlassShell
//
//  Windows come back where they were. The owner, 2026-10-09, after an update reopened every
//  terminal window at the default place: "we need to remember window positions. Apple has an
//  API for this, right?" It does: macOS's own window restoration, which brings Safari and Finder
//  back on the same displays and Spaces, at the same size and place, and which SwiftUI uses for
//  a window group's windows, value and all.
//
//  The system setting "Close windows when quitting an application" — on by default — turns it
//  off for every app. An app's own `NSQuitAlwaysKeepsWindows` overrides that for the app alone,
//  which is how apps with their own "reopen windows" setting do it. This app chooses it once, and
//  Settings ▸ General can turn it off again. Windows that make no sense to restore (databases,
//  desktops, the editor, Files) already decline it in their scenes.
//

#if os(macOS)
import Foundation

public enum GlassWindowRestoration {
    /// AppKit's key: whether windows are kept when the app quits, and restored when it opens.
    public static let key = "NSQuitAlwaysKeepsWindows"

    /// At launch: restoration on, the first time, unless this app's own setting already says
    /// otherwise. Only the app's own domain is read, so the system-wide choice is never mistaken
    /// for the user's choice here.
    public static func adoptDefault(_ defaults: UserDefaults = .standard,
                                    domain: String? = Bundle.main.bundleIdentifier) {
        guard let domain, defaults.persistentDomain(forName: domain)?[key] == nil else { return }
        defaults.set(true, forKey: key)
    }
}
#endif
