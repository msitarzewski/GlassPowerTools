import SwiftUI
import GlassConnectionKit

/// Common results interaction: inspect selection, activate on Return or Mac
/// double-click, and retain native searchable List behavior. Rows own app menus.
public struct GlassLibraryResults<ID: Hashable & Sendable, Row: View>: View {
    private let items: [GlassLibraryItem<ID>]
    private let title: String
    @Binding private var selection: ID?
    @Binding private var searchText: String
    @FocusState private var searchFocused: Bool
    private let onActivate: (ID) -> Void
    private let row: (GlassLibraryItem<ID>) -> Row

    /// Supply already scoped/filtered items from GlassLibraryProjection.
    public init(items: [GlassLibraryItem<ID>], title: String, selection: Binding<ID?>,
                searchText: Binding<String>, onActivate: @escaping (ID) -> Void,
                @ViewBuilder row: @escaping (GlassLibraryItem<ID>) -> Row) {
        self.items = items
        self.title = title
        _selection = selection
        _searchText = searchText
        self.onActivate = onActivate
        self.row = row
    }

    public var body: some View {
        List(selection: $selection) {
            if items.isEmpty {
                // An empty state is the one thing a first-time user is guaranteed to see. On the
                // headset a `ContentUnavailableView` at its default scale is a small card adrift in
                // a large pane, so it is given the row's own breathing room rather than being left
                // to size itself for a Mac list.
                Group {
                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView("No Connections", systemImage: "server.rack",
                                               description: Text("Add a saved host to begin."))
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(items) { item in
                    // Spatial rows are taller and respond to gaze; on every other platform both
                    // modifiers are no-ops and the Mac's own row metrics are untouched.
                    row(item).tag(item.id)
                        .glassSpatialRowMetrics()
                        .contentShape(Rectangle())
                        .glassGazeHighlight()
                        .onTapGesture { selection = item.id }
                        #if os(macOS)
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            selection = item.id
                            onActivate(item.id)
                        })
                        #endif
                }
            }
        }
        .navigationTitle(title)
        // The list does not paint a surface of its own: the window's layered glass is the surface,
        // and the list sits on it. This is what makes the results column match the sidebar instead
        // of being an opaque white panel beside it — and it is why the opacity and frost settings
        // reach this column at all. Painting here was also what produced the seam at the column
        // divider, since an opaque child over a translucent window leaves every pixel it misses
        // showing the desktop.
        .scrollContentBackground(.hidden)
        .searchable(text: $searchText, prompt: "Search connections...")
        .searchFocused($searchFocused)
        .onKeyPress(.return, phases: .down) { press in
            guard press.modifiers.isEmpty, !searchFocused, let selection,
                  items.contains(where: { $0.id == selection }) else { return .ignored }
            onActivate(selection)
            return .handled
        }
    }

}
