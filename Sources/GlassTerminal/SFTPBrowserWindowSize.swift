//
//  SFTPBrowserWindowSize.swift
//  Glass Power Tools — GlassTerminal
//
//  The Files window's size on Vision Pro: the person's, kept (the owner, 2026-11-05, after the window was made wider so
//  names show: "it should also remember the user's preference for sizing. It opens a little too wide now"). A Files
//  window opens at the size the last one was left at, on this device; until one has been, at `standard`.
//

import CoreGraphics
import Foundation
import GlassLayers
import GlassShell

enum SFTPBrowserWindowSize {
    /// The first size: wide enough for every column of a row beside a name of `SFTPFileRowLayout.nameMinimum` (a list
    /// 940 points wide), and little more. 1100 was "a little too wide"; 700 cut every name to "…".
    static let standard = CGSize(width: 960, height: 500)

    static let key = "com.glasspowertools.files.windowSize"

    /// The size a Files window opens at: the last one a Files window was left at, else `standard`.
    static func opening(in defaults: UserDefaults = GlassUITestRun.settingsDefaults) -> CGSize {
        #if DEBUG
        // `--demo-files-window-size 780x620`: kept as if a Files window had been left at that size, so the simulator
        // shows the next one opening there (it can't resize a window).
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "--demo-files-window-size"), arguments.indices.contains(flag + 1),
           let size = GlassConnectionsWindowSize.stored(arguments[flag + 1]) {
            keep(size, in: defaults)
        }
        #endif
        return GlassConnectionsWindowSize.stored(defaults.string(forKey: key) ?? "") ?? standard
    }

    /// Keeps a Files window's size as it is now, for the next one. Nothing for a size that can't be a window's (zero,
    /// as a window is laid out before it has one).
    static func keep(_ size: CGSize, in defaults: UserDefaults = GlassUITestRun.settingsDefaults) {
        let text = GlassConnectionsWindowSize.stored(size)
        guard !text.isEmpty, defaults.string(forKey: key) != text else { return }
        defaults.set(text, forKey: key)
    }
}
