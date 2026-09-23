import Testing
import GlassConnectionKit
@testable import GlassConnectionUI

/// The sidebar highlights the row that is showing: the open panel, else the scope
/// (2026-09-22: *"Active doesn't stay highlighted when clicked"*).
@Suite("The sidebar highlights the open panel")
struct GlassLibrarySidebarSelectionTests {
    @Test("With a panel open the panel is the current row; otherwise the scope is")
    func currentRow() {
        #expect(GlassLibrarySidebarSelection.current(scope: .allConnections, openPanelID: nil) == .scope(.allConnections))
        #expect(GlassLibrarySidebarSelection.current(scope: .allConnections, openPanelID: "active") == .panel("active"))
    }

    @Test("Choosing a row changes only what is not already showing")
    func changes() {
        typealias S = GlassLibrarySidebarSelection
        #expect(S.change(choosing: .scope(.allConnections), scope: .allConnections, openPanelID: nil) == nil,
                "the scope already showing is not a change")
        #expect(S.change(choosing: .scope(.allConnections), scope: .allConnections, openPanelID: "active") == .scope(.allConnections),
                "the current scope while a panel is open is a change: it closes the panel")
        #expect(S.change(choosing: .scope(.favorites), scope: .allConnections, openPanelID: nil) == .scope(.favorites))
        #expect(S.change(choosing: .panel("active"), scope: .allConnections, openPanelID: nil) == .panel("active"))
        #expect(S.change(choosing: .panel("active"), scope: .allConnections, openPanelID: "active") == nil,
                "the panel already open is not a change")
        #expect(S.change(choosing: .panel("keys"), scope: .allConnections, openPanelID: "active") == .panel("keys"))
        #expect(S.change(choosing: nil, scope: .allConnections, openPanelID: "active") == nil,
                "the list clearing its selection changes nothing; the rows own what is showing")
    }
}
