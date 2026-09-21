//
//  GlassWindowPresentation.swift
//  Glass Power Tools — GlassShell
//
//  Whether this device can put a surface in a window of its own.
//
//  **`openWindow` does nothing on an iPhone, silently.** There is one scene, so a capability that
//  answers a connect request by opening a window answers it by doing nothing at all — no window, no
//  error, no log line. The editor's Projects panel had this defect and the desktop's session had
//  it too; both were reported as "nothing happens", which is exactly what it looks like.
//
//  A runtime check rather than `#if os(iOS)`, because the difference is an iPhone against an iPad
//  and both compile as `os(iOS)`.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public enum GlassWindowPresentation {
    /// True where a second window is possible: macOS, visionOS, iPadOS. False on iPhone.
    ///
    /// A capability that opens windows must ask this and present in place when the answer is no —
    /// a full-screen cover over the library, which is what a window is on a phone anyway.
    /// Both signals, because they fail in opposite directions and neither alone is enough.
    ///
    /// `supportsMultipleScenes` is the precise question and also answers no for an iPad with
    /// multiwindow switched off. The idiom check is the blunt one, and is the half already proven
    /// in production: the database has routed iPhone work in-scene on it since before the merge.
    /// Requiring both means an iPhone is excluded by either, which is the direction to be wrong in
    /// — presenting in place where a window was possible is a cosmetic difference, and opening a
    /// window where none is possible is the user tapping and nothing happening.
    /// **Ask it where you need it; never store the answer.** Stored as a property's default it is
    /// read during app construction, before any scene has connected — and at that moment
    /// `UIDevice.current.userInterfaceIdiom` is `.unspecified`, which is not `.phone`, so an
    /// iPhone answers *yes*. That cost an afternoon on 2026-09-21: the editor kept a snapshot of
    /// this and went on discarding a workspace on every dismissal (rule 55).
    public static var canOpenWindows: Bool {
        #if canImport(UIKit) && !os(visionOS)
        UIApplication.shared.supportsMultipleScenes
            && UIDevice.current.userInterfaceIdiom != .phone
        #else
        true
        #endif
    }
}
