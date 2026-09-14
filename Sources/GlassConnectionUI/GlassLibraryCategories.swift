import SwiftUI
import GlassConnectionKit

/// Common sections with app-owned category rows. This lets existing native
/// shells preserve their navigation/focus handlers and specialized sections.
public struct GlassLibraryCategories<ID: Hashable & Sendable, Category: View>: View {
    private let projection: GlassLibraryProjection<ID>
    private let category: (GlassLibraryScope, String, Int) -> Category

    public init(projection: GlassLibraryProjection<ID>,
                @ViewBuilder category: @escaping (GlassLibraryScope, String, Int) -> Category) {
        self.projection = projection
        self.category = category
    }

    public var body: some View {
        Section("Library") {
            category(.allConnections, "All Connections", projection.itemCount(in: .allConnections))
            category(.favorites, "Favorites", projection.itemCount(in: .favorites))
            category(.recent, "Recent", projection.itemCount(in: .recent))
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
