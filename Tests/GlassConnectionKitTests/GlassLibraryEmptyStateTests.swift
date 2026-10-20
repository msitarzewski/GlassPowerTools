import Testing
@testable import GlassConnectionKit

/// 2026-10-18, the iPhone Duo tour: Favorites and Recent, empty, said "No Connections — Add a saved
/// host to begin." beside four saved hosts. Only an empty library asks for a first host; an empty
/// scope says what it holds and how something gets there.
struct GlassLibraryEmptyStateTests {
    @Test("An empty library asks for a first host, whatever the scope")
    func emptyLibrary() {
        for scope: GlassLibraryScope in [.allConnections, .favorites, .recent, .collection("x")] {
            #expect(GlassLibraryEmptyState.of(scope, libraryIsEmpty: true).message == "Add a saved host to begin.")
        }
    }

    @Test("With hosts saved, an empty scope says what it holds, never to add a host")
    func emptyScopeWithHosts() {
        let favorites = GlassLibraryEmptyState.of(.favorites, libraryIsEmpty: false)
        #expect(favorites.title == "No Favorites")
        #expect(favorites.message.contains("Add Favorite"))
        let recent = GlassLibraryEmptyState.of(.recent, libraryIsEmpty: false)
        #expect(recent.title == "Nothing Recent")
        let collection = GlassLibraryEmptyState.of(.collection("x"), libraryIsEmpty: false)
        #expect(collection.message.contains("Collections"))
        for state in [favorites, recent, collection] {
            #expect(state.title != "No Connections")
            #expect(!state.message.contains("Add a saved host"))
        }
    }
}
