//
//  TestLayers.swift
//  Glass Power Tools — tests
//
//  A layer store of a test's own. `GlassLayerStore.forTest()` keeps its state in the process's standard
//  domain — shared by every test in the run, and by every run — and, finding none there, migrates
//  from the App Group and from glas.sh's, glassdb's and glassDT's own preferences: the owner's, read
//  by the tests (2026-10-24). The same copy of this file lives in each test target that needs one.
//

import Foundation
import GlassLayers

extension GlassLayerStore {
    /// Its own defaults suite, removed when the process exits (`TestDefaults`), and nothing to
    /// migrate from.
    @MainActor static func forTest() -> GlassLayerStore {
        GlassLayerStore(defaults: UserDefaults.forTest(suiteName: "GlassLayers.\(UUID().uuidString)")!, legacyDefaults: [])
    }
}
