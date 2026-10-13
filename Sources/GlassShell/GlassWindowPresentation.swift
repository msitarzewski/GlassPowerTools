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
    /// True where a second window is possible: macOS, visionOS, iPadOS — and an iPhone that says so.
    ///
    /// A capability that opens windows must ask this and present in place when the answer is no —
    /// a full-screen cover over the library, which is what a window is on a phone anyway.
    ///
    /// **The system's answer, `supportsMultipleScenes`, and nothing else** (2026-10-12, B-F44). It
    /// also answers no for an iPad with multiwindow switched off. Until today an idiom check stood
    /// beside it, so that every iPhone was excluded twice over. Measured that day, it never decided
    /// anything: an iPhone 17 Pro Max on iOS 26.5 and an iPhone 18 Pro on iOS 27.0 both report
    /// `supportsMultipleScenes == false` (and an iPad reports true). The one phone it would decide
    /// is the iPhone Duo, whose inner display runs Split View — and there the clause would have
    /// refused a second window the system says it can open. No simulator runtime here could run a
    /// Duo, so its answer is logged the first time it is asked (category `windows`); if a Duo says
    /// yes and a window still does not open, that line is the evidence and the idiom clause comes
    /// back for it.
    ///
    /// **Ask it where you need it; never store the answer.** Stored as a property's default it is
    /// read during app construction, before any scene has connected — and at that moment
    /// `UIDevice.current.userInterfaceIdiom` is `.unspecified`, which is not `.phone`, so an
    /// iPhone answers *yes*. That cost an afternoon on 2026-09-21: the editor kept a snapshot of
    /// this and went on discarding a workspace on every dismissal (rule 55).
    public static var canOpenWindows: Bool {
        #if canImport(UIKit) && !os(visionOS)
        let multipleScenes = UIApplication.shared.supportsMultipleScenes
        report(multipleScenes: multipleScenes, idiom: UIDevice.current.userInterfaceIdiom)
        return multipleScenes
        #else
        true
        #endif
    }

    #if canImport(UIKit) && !os(visionOS)
    private static let reported = OSAllocatedUnfairLock(initialState: Set<String>())

    private static func report(multipleScenes: Bool, idiom: UIUserInterfaceIdiom) {
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let line = "multipleScenes=\(multipleScenes) idiom=\(idiom.rawValue) model=\(model)"
        guard reported.withLock({ $0.insert(line).inserted }) else { return }
        Logger(subsystem: "com.glasspowertools", category: "windows")
            .notice("Window support: \(line, privacy: .public)")
    }
    #endif
}
