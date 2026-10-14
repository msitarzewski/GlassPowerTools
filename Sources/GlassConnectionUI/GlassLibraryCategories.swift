import SwiftUI
import GlassConnectionKit

/// Common sections with app-owned category rows. This lets existing native
/// shells preserve their navigation/focus handlers and specialized sections.
public struct GlassLibraryCategories<ID: Hashable & Sendable, Category: View, Extras: View>: View {
    private let projection: GlassLibraryProjection<ID>
    private let favoriteExtraCount: Int
    private let category: (GlassLibraryScope, String, Int) -> Category
    private let extras: () -> Extras

    /// - Parameter extras: rows that belong in the Library section after the three categories —
    ///   Active, which is another way of looking at the connections rather than a section of
    ///   its own.
    ///   - favoriteExtraCount: favourites that are not machines, counted with them (2026-10-13).
    public init(projection: GlassLibraryProjection<ID>, favoriteExtraCount: Int = 0,
                @ViewBuilder category: @escaping (GlassLibraryScope, String, Int) -> Category,
                @ViewBuilder extras: @escaping () -> Extras = { EmptyView() }) {
        self.projection = projection
        self.favoriteExtraCount = favoriteExtraCount
        self.category = category
        self.extras = extras
    }

    public var body: some View {
        Section("Library") {
            category(.allConnections, "All Connections", projection.itemCount(in: .allConnections))
            category(.favorites, "Favorites", projection.itemCount(in: .favorites) + favoriteExtraCount)
            category(.recent, "Recent", projection.itemCount(in: .recent))
            extras()
        }
        if !projection.collections.isEmpty {
            Section("Collections") {
                ForEach(projection.collections) { collection in
                    category(.collection(collection.id), collection.name, collection.count)
                }
            }
        }
    }
}
