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
import os
#if canImport(UIKit)
import UIKit
#endif

public enum GlassWindowPresentation {
    /// True where a second window is possible: macOS, visionOS, iPadOS — and an unfolded iPhone Duo.
    ///
    /// A capability that opens windows must ask this and present in place when the answer is no —
    /// a full-screen cover over the library, which is what a window is on a phone anyway.
    ///
    /// **`supportsMultipleScenes`, and on a phone a regular-width scene too** (2026-10-12, B-F44).
    /// `supportsMultipleScenes` also answers no for an iPad with multiwindow switched off. Measured
    /// that day: an iPhone 17 Pro Max (iOS 26.5) and an iPhone 18 Pro (27.0) answer no, so every
    /// ordinary iPhone presents in place as before; an iPad answers yes; and an **iPhone Duo**
    /// (iOS 27.1 simulator) answers yes with a phone idiom — **folded as well as unfolded**. Folded,
    /// on the 466-point outer display, a scene request does not fail: a new full-screen window covers
    /// the library and the library drops to the background, reachable only from the app switcher.
    /// Apple keeps side-by-side windows for the inner display. So a phone opens windows only when the
    /// active scene is regular width — the Duo unfolded — and presents in place otherwise, a 50/50
    /// Split View half included. (An idiom check alone refused the unfolded Duo; the system's answer
    /// alone sent the folded one into the switcher.) The unfolded half is unverified: Xcode 27.2
    /// beta's Device Hub has no fold controls, which came with the 27.1 branch. Each distinct answer
    /// is logged once (category `windows`).
    ///
    /// **Ask it where you need it; never store the answer.** Stored as a property's default it is
    /// read during app construction, before any scene has connected — and at that moment
    /// `UIDevice.current.userInterfaceIdiom` is `.unspecified`, which is not `.phone`, so an
    /// iPhone answers *yes*. That cost an afternoon on 2026-09-21: the editor kept a snapshot of
    /// this and went on discarding a workspace on every dismissal (rule 55). The width changes with
    /// the hinge, which is one more reason.
    public static var canOpenWindows: Bool {
        #if canImport(UIKit) && !os(visionOS)
        let multipleScenes = UIApplication.shared.supportsMultipleScenes
        let idiom = UIDevice.current.userInterfaceIdiom
        let width = activeSceneWidth
        report(multipleScenes: multipleScenes, idiom: idiom, width: width)
        guard multipleScenes else { return false }
        return idiom != .phone || width == .regular
        #else
        true
        #endif
    }

    #if canImport(UIKit) && !os(visionOS)
    /// The horizontal size class of the scene in front, or unspecified when none is.
    private static var activeSceneWidth: UIUserInterfaceSizeClass {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .traitCollection.horizontalSizeClass ?? .unspecified
    }
    #endif

    #if canImport(UIKit) && !os(visionOS)
    private static let reported = OSAllocatedUnfairLock(initialState: Set<String>())

    private static func report(multipleScenes: Bool, idiom: UIUserInterfaceIdiom, width: UIUserInterfaceSizeClass) {
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let line = "multipleScenes=\(multipleScenes) idiom=\(idiom.rawValue) width=\(width.rawValue) model=\(model)"
        guard reported.withLock({ $0.insert(line).inserted }) else { return }
        Logger(subsystem: "com.glasspowertools", category: "windows")
            .notice("Window support: \(line, privacy: .public)")
    }
    #endif
}
