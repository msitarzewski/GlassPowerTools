import Testing
import SwiftUI
@testable import GlassConnectionUI

@Suite("A library panel's count")
struct GlassLibraryPanelCountTests {
    @MainActor
    final class List {
        var items: [String]
        init(_ items: [String]) { self.items = items }
    }

    @MainActor
    private func panel(counting list: List) -> GlassLibraryPanel {
        GlassLibraryPanel(id: "test", sectionTitle: "Projects", title: "Projects",
                          symbolName: "folder",
                          count: list.items.isEmpty ? nil : list.items.count,
                          results: { EmptyView() },
                          detail: { EmptyView() })
    }

    @Test @MainActor func followsTheListRatherThanFreezingAtRegistration() {
        // Reported 2026-09-18: a project was removed, the list showed four, and the sidebar went
        // on saying 5. A standalone panel is registered once and kept, so a stored count is the
        // count at launch forever.
        let list = List(["a", "b", "c", "d", "e"])
        let panel = panel(counting: list)
        #expect(panel.count == 5)

        list.items.removeLast()
        #expect(panel.count == 4, "the count was stored at registration instead of asked for")
    }

    @Test @MainActor func showsNothingRatherThanAZeroWhenTheListEmpties() {
        let list = List(["only"])
        let panel = panel(counting: list)
        #expect(panel.count == 1)
        list.items.removeAll()
        #expect(panel.count == nil, "\"no count\" and \"none\" are different statements")
    }
}

@Suite("A library panel's selection")
struct GlassLibraryPanelSelectionTests {
    @MainActor
    final class Model {
        var selection: String?
        init(_ selection: String? = nil) { self.selection = selection }
    }

    @MainActor
    private func panel(_ model: Model) -> GlassLibraryPanel {
        GlassLibraryPanel(id: "test", sectionTitle: "Projects", title: "Projects",
                          symbolName: "folder",
                          selection: { model.selection },
                          clearSelection: { model.selection = nil },
                          results: { EmptyView() },
                          detail: { EmptyView() })
    }

    @Test @MainActor func choosingADifferentRowIsAChangeTheStackCanSee() {
        // Reported 2026-09-19: a project refused to open, and *"I tried to open another project
        // and it just absorbed the click."* As a Bool this went true on the first selection and
        // stayed true, so no later selection changed anything the compact stack was watching.
        let model = Model()
        let panel = panel(model)
        #expect(panel.selectedItem == nil)

        model.selection = "first"
        let first = panel.selectedItem
        #expect(first == AnyHashable("first"))

        model.selection = "second"
        #expect(panel.selectedItem != first, "the second choice has to look different from the first")
    }

    @Test @MainActor func goingBackClearsItSoTheSameRowCanBeChosenAgain() {
        let model = Model("only")
        let panel = panel(model)
        #expect(panel.selectedItem != nil)

        panel.clearSelection()
        #expect(panel.selectedItem == nil, "popping the detail puts the panel back to nothing")

        model.selection = "only"
        #expect(panel.selectedItem == AnyHashable("only"),
                "so choosing the same project again is a change again")
    }

    @Test @MainActor func aPanelThatContributesNothingIsSilentRatherThanSelected() {
        let panel = GlassLibraryPanel(id: "plain", sectionTitle: "Keys", title: "Keys",
                                      symbolName: "key",
                                      results: { EmptyView() }, detail: { EmptyView() })
        #expect(panel.selectedItem == nil)
        panel.clearSelection()
    }
}
