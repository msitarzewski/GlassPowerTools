//
//  GlassUITestRun.swift
//  Glass Power Tools — GlassLayers
//
//  One answer to "is a UI test driving this run, and where do its settings go?", for every
//  store that keeps settings in a `UserDefaults` suite.
//
//  The catalog and the terminal's servers were isolated under `--ui-testing <uuid>`; the terminal's
//  settings and themes (`SettingsManager`) and Appearance (`GlassLayerStore`, made in the app's
//  `init`) were not — they used `UserDefaults.standard`, the person's own store, so a UI run on the
//  Mac could change their real themes, opacity and glass (found by W35, 2026-10-11).
//

import Foundation

public enum GlassUITestRun {
    /// The per-run defaults suite while a UI test drives the app (`--ui-testing <uuid>`, Debug
    /// only), else nil. Every caller gets the same suite for the same run, named after the App
    /// Group so it is recognisably this app's: `<group>.uitests.<uuid>`.
    public nonisolated static var defaults: UserDefaults? {
        identifier.flatMap { UserDefaults(suiteName: suiteName(for: $0)) }
    }

    /// The run's identifier while a UI test drives the app (`--ui-testing <uuid>`, Debug only),
    /// for a store that keeps files rather than settings to keep them apart too.
    public nonisolated static var identifier: UUID? {
        #if DEBUG || GLASS_STRESS_HARNESS
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--ui-testing"),
              arguments.indices.contains(index + 1) else { return nil }
        return UUID(uuidString: arguments[index + 1])
        #else
        return nil
        #endif
    }

    /// Where settings go: the run's own suite while a UI test drives the app, the person's own
    /// store (`UserDefaults.standard`) otherwise. In a Release build it is always the latter.
    public nonisolated static var settingsDefaults: UserDefaults { defaults ?? .standard }

    /// The suite's name for a run's identifier.
    public nonisolated static func suiteName(for identifier: UUID) -> String {
        "\(GlassAppIdentity.appGroup).uitests.\(identifier.uuidString)"
    }
}
