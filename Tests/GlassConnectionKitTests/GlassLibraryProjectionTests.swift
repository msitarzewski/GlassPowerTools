import Foundation
import Testing
@testable import GlassConnectionKit

struct GlassLibraryProjectionTests {
    private func item(_ id: Int, _ name: String, tags: [String] = [], favorite: Bool = false,
                      last: TimeInterval? = nil, added: TimeInterval = 0,
                      terms: [String] = []) -> GlassLibraryItem<Int> {
        .init(id: id, name: name, searchTerms: terms, tags: tags, isFavorite: favorite,
              lastConnected: last.map(Date.init(timeIntervalSince1970:)),
              dateAdded: Date(timeIntervalSince1970: added))
    }

    @Test func duplicateIDsKeepAuthoritativeFirstRecord() {
        let projection = GlassLibraryProjection(items: [item(1, "first"), item(1, "second", favorite: true)])
        #expect(projection.items.map(\.name) == ["first"])
        #expect(projection.favoriteIDs.isEmpty)
    }

    @Test func existingAllAndCollectionOrderingPoliciesRemainExplicit() {
        let items = [item(1, "Zulu", tags: ["Ops"]), item(2, "Alpha", tags: ["Ops"])]
        let ssh = GlassLibraryProjection(items: items, order: .source)
        let db = GlassLibraryProjection(items: items, order: .alphabetical)
        #expect(ssh.items(in: .allConnections).map(\.id) == [1, 2])
        #expect(db.items(in: .allConnections).map(\.id) == [2, 1])
        #expect(ssh.items(in: .collection("ops")).map(\.id) == [1, 2])
        #expect(db.items(in: .collection("ops")).map(\.id) == [2, 1])
    }

    @Test func collectionsFoldCaseDiacriticsWidthAndDuplicateTags() {
        let projection = GlassLibraryProjection(items: [
            item(1, "One", tags: [" Café ", "cafe", "ＣＡＦＥ", " "]),
            item(2, "Two", tags: ["CAFE"])
        ])
        #expect(projection.collections.count == 1)
        #expect(projection.collections.first?.id == "cafe")
        #expect(projection.collections.first?.itemIDs == [1, 2])
        #expect(projection.itemCount(in: .collection("cafe")) == 2)
    }

    @Test func recentsUseLastConnectionAndFavoritesFallBackToCreation() {
        let projection = GlassLibraryProjection(items: [
            item(1, "Old", favorite: true, last: 10, added: 500),
            item(2, "New", favorite: true, added: 30),
            item(3, "Recent", last: 20)
        ])
        #expect(projection.favoriteIDs == [2, 1])
        #expect(projection.recentIDs == [3, 1])
    }

    @Test func recentLimitIsBoundedAndNeverAddsUnconnectedHosts() {
        let records = (0..<15).map { item($0, "Host \($0)", last: Double($0)) } + [item(20, "Never")]
        #expect(GlassLibraryProjection(items: records).recentIDs.count == 10)
        #expect(GlassLibraryProjection(items: records, recentLimit: -1).recentIDs.isEmpty)
        #expect(GlassLibraryProjection(items: records, recentLimit: 1).recentIDs == [14])
    }

    @Test func searchUsesAppTermsAndDoesNotChangeUnfilteredCounts() {
        let projection = GlassLibraryProjection(items: [
            item(1, "Production", tags: ["Operations"], terms: ["PostgreSQL", "reporting"]),
            item(2, "Development")
        ])
        #expect(projection.items(in: .allConnections, searchQuery: " POSTGRES ").map(\.id) == [1])
        #expect(projection.items(in: .allConnections, searchQuery: "reporting").map(\.id) == [1])
        #expect(projection.itemCount(in: .allConnections) == 2)
    }

    @Test func filteringAndDeletionNeverSelectADifferentHost() {
        let projection = GlassLibraryProjection(items: [item(1, "One"), item(2, "Two", favorite: true)])
        #expect(projection.resolvedSelection(1, in: .allConnections) == 1)
        #expect(projection.resolvedSelection(1, in: .favorites) == nil)
        #expect(projection.resolvedSelection(1, in: .allConnections, searchQuery: "Two") == nil)
        #expect(projection.resolvedSelection(9, in: .allConnections) == nil)
        #expect(projection.resolvedSelection(nil, in: .allConnections) == nil)
        #expect(projection.items(in: .collection("removed")).isEmpty)
    }
}
