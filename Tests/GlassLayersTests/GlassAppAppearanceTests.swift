//
//  GlassAppAppearanceTests.swift
//  Glass Power Tools — GlassLayersTests
//
//  Settings ▸ Appearance's Light, Dark and System (the owner, 2026-10-13: "TIL we don't allow the
//  user to choose (in Appearance) Light, Dark, System. Then it should follow that.").
//

import Foundation
import Testing
#if os(macOS)
import AppKit
#endif
@testable import GlassLayers

@Suite("The app's Light, Dark or System")
struct GlassAppAppearanceTests {
    @Test func aDeviceWithoutAChoiceFollowsTheSystem() throws {
        let defaults = try #require(UserDefaults.forTest(suiteName: "app-appearance-\(UUID().uuidString)"))
        #expect(GlassAppAppearance.stored(in: defaults) == .system)
        defaults.set("dark", forKey: GlassAppAppearance.key)
        #expect(GlassAppAppearance.stored(in: defaults) == .dark)
        defaults.set("sepia", forKey: GlassAppAppearance.key)
        #expect(GlassAppAppearance.stored(in: defaults) == .system)
    }

    #if os(macOS)
    /// The application's appearance, so AppKit's own panels follow it too — the command palette
    /// was drawn in the Mac's appearance whatever the app looked like.
    @Test @MainActor func theChoiceIsTheApplicationsAppearance() {
        let before = NSApplication.shared.appearance
        defer { NSApplication.shared.appearance = before }
        GlassAppAppearance.dark.apply()
        #expect(NSApplication.shared.appearance?.name == .darkAqua)
        GlassAppAppearance.light.apply()
        #expect(NSApplication.shared.appearance?.name == .aqua)
        GlassAppAppearance.system.apply()
        #expect(NSApplication.shared.appearance == nil)
    }
    #endif

    /// The palette reads the windows' layers outside SwiftUI's environment; reading must change
    /// nothing, or opening it could migrate or stamp a person's appearance.
    @Test @MainActor func theStoredLayersAreReadWithoutWritingAnything() throws {
        let defaults = try #require(UserDefaults.forTest(suiteName: "layers-read-\(UUID().uuidString)"))
        #expect(GlassLayerStore.storedState(in: defaults) == .default)
        #expect(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("glass.layers") }.isEmpty)

        let store = GlassLayerStore(defaults: defaults, legacyDefaults: [])
        store.state = GlassLayerState(opacity: 0.4, frost: 0.6, material: .thin)
        #expect(GlassLayerStore.storedState(in: defaults) == GlassLayerState(opacity: 0.4, frost: 0.6, material: .thin))
    }
}
