import Foundation
import Testing
@testable import GlassTerminal

/// Legacy SSH algorithms need a confirmation per connection, which a Workgroup cannot give. Every
/// platform now refuses a Workgroup that includes such a connection; only the Mac used to.
@MainActor
@Suite("Workgroups and legacy algorithms")
struct LegacyAlgorithmWorkgroupTests {
    @Test("a Workgroup with a legacy-algorithm connection needs that connection's own consent")
    func legacyConnectionIsRefused() {
        var legacy = ServerConfiguration(name: "Old switch", host: "192.0.2.20", username: "ann")
        legacy.allowLegacyAlgorithms = true
        let modern = ServerConfiguration(name: "alpha", host: "192.0.2.10", username: "ann")

        #expect(TerminalConnectFlow.workgroupNeedsLegacyConsent(
            LayoutPreset(name: "Mixed", serverIDs: [modern.id, legacy.id]), servers: [modern, legacy]))
        #expect(!TerminalConnectFlow.workgroupNeedsLegacyConsent(
            LayoutPreset(name: "Modern", serverIDs: [modern.id]), servers: [modern, legacy]))
    }
}
