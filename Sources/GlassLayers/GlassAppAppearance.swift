//
//  GlassAppAppearance.swift
//  Glass Power Tools — GlassLayers
//
//  The app's own Light or Dark, or the system's: Settings ▸ Appearance (the owner, 2026-10-13,
//  on the command palette following the Mac's appearance rather than his: "TIL we don't allow the
//  user to choose (in Appearance) Light, Dark, System. Then it should follow that.").
//
//  On the Mac it is the application's appearance, so every window, sheet, menu and panel follows
//  it — AppKit's own panels too, like the command palette. On iPhone and iPad it is each window's
//  interface style, including windows opened later. Not on Vision Pro, where the system's glass
//  has no light and dark of its own to choose (D63). A choice for this device, not synced.
//

import Foundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

public enum GlassAppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    public static let key = "com.glasspowertools.appearance"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// What this device chose; System until a choice is made.
    public static func stored(in defaults: UserDefaults = GlassUITestRun.settingsDefaults) -> GlassAppAppearance {
        defaults.string(forKey: key).flatMap(Self.init(rawValue:)) ?? .system
    }

    /// Applies the stored choice now and, off the Mac, to every window that appears later. Once,
    /// as the app starts, before its windows are shown.
    @MainActor
    public static func install() {
        stored().apply()
        #if os(iOS)
        guard windowObserver == nil else { return }
        windowObserver = NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeVisibleNotification, object: nil, queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                (notification.object as? UIWindow)?.overrideUserInterfaceStyle = stored().interfaceStyle
            }
        }
        #endif
    }

    /// Applies this choice to the app as it is now.
    @MainActor
    public func apply() {
        #if os(macOS)
        NSApplication.shared.appearance = appearance
        #elseif os(iOS)
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { window.overrideUserInterfaceStyle = interfaceStyle }
        }
        #endif
    }

    #if os(macOS)
    /// The application appearance it stands for; nil follows the system.
    public var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
    #elseif os(iOS)
    @MainActor private static var windowObserver: (any NSObjectProtocol)?

    public var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
    #endif
}
