import Testing
import GlassLayers
import GlassShell
@testable import GlassDatabase

/// Settings ▸ Databases: the page existed and nothing presented it (help audit, 2026-09-27).
@Suite("Database settings page")
@MainActor
struct DatabaseSettingsPageTests {
    @Test("the capability offers its settings to the shell's Settings")
    func registersAPage() {
        let capability = GlassDatabaseCapability(runtime: GlassDatabaseRuntime(layers: GlassLayerStore.forTest()))
        #expect(capability.settingsPages.map(\.title) == ["Databases"])
    }
}
