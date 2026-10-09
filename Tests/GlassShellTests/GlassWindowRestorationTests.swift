#if os(macOS)
import Foundation
import Testing
@testable import GlassShell

/// Windows come back where they were (2026-10-09): the app turns macOS's window restoration on
/// for itself once, and leaves alone a choice made in its own settings.
@Suite("Window restoration")
struct GlassWindowRestorationTests {
    @Test("restoration is chosen once for this app, and a choice made here is kept")
    func adoptingTheDefault() throws {
        let suite = "GlassWindowRestorationTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        GlassWindowRestoration.adoptDefault(defaults, domain: suite)
        #expect(defaults.persistentDomain(forName: suite)?[GlassWindowRestoration.key] as? Bool == true,
                "chosen in the app's own domain, which overrides the system-wide setting for this app")

        defaults.set(false, forKey: GlassWindowRestoration.key)
        GlassWindowRestoration.adoptDefault(defaults, domain: suite)
        #expect(defaults.bool(forKey: GlassWindowRestoration.key) == false, "turned off in Settings: stays off")
    }
}
#endif
