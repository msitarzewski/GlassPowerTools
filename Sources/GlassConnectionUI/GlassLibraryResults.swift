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
    /// The library's own actions, offered on a right-click, long-press or pinch-and-hold in the
    /// empty part of the list. Rows carry their own menu; this is the one place that had none, and
    /// "add a machine" is the thing you want when you are looking at the list rather than at a row.
    private let backgroundActions: () -> AnyView
    /// Pull to refresh. The library already knows how to pull, merge and publish — this is the
    /// user asking it to, instead of waiting for a launch or a push that may never arrive.
    private let onRefresh: (() async -> Void)?
    /// Sections after the machines — Favorites' services, projects, workgroups and folders
    /// (2026-10-13). With any, the machines get a section of their own above them.
    private let extraSections: GlassLibraryExtraSections?
    /// What the list says with nothing in it: the scope's own words (`GlassLibraryEmptyState`).
    private let emptyState: GlassLibraryEmptyState

    /// Supply already scoped/filtered items from GlassLibraryProjection.
    public init(items: [GlassLibraryItem<ID>], title: String, selection: Binding<ID?>,
                searchText: Binding<String>, onActivate: @escaping (ID) -> Void,
                @ViewBuilder row: @escaping (GlassLibraryItem<ID>) -> Row,
                backgroundActions: @escaping () -> AnyView = { AnyView(EmptyView()) },
                onRefresh: (() async -> Void)? = nil,
                extraSections: GlassLibraryExtraSections? = nil,
                emptyState: GlassLibraryEmptyState = .of(.allConnections, libraryIsEmpty: true)) {
        self.emptyState = emptyState
        self.items = items
        self.title = title
        _selection = selection
        _searchText = searchText
        self.onActivate = onActivate
        self.row = row
        self.backgroundActions = backgroundActions
        self.onRefresh = onRefresh
        self.extraSections = extraSections
    }

    private var extraCount: Int { extraSections?.count(searchText) ?? 0 }

    public var body: some View {
        List(selection: $selection) {
            if items.isEmpty && extraCount == 0 {
                // An empty state is the one thing a first-time user is guaranteed to see. On the
                // headset a `ContentUnavailableView` at its default scale is a small card adrift in
                // a large pane, so it is given the row's own breathing room rather than being left
                // to size itself for a Mac list.
                Group {
                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView(emptyState.title, systemImage: emptyState.systemImage,
                                               description: Text(emptyState.message))
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if extraCount > 0, let extraSections {
                if !items.isEmpty {
                    Section(extraSections.itemsTitle) { rows }
                }
                extraSections.content(searchText)
            } else {
                rows
            }
        }
        // The first row must not open underneath the toolbar. Two causes, both cheap to rule out:
        // the column's scroll view starts flush with the window top under a transparent title bar,
        // and a restored scroll offset can leave the list mid-scroll on open. The anchor pins the
        // list to its top on appearance; the margin keeps the first row clear of the toolbar's
        // edge rather than tucked against it (reported 2026-09-16: "opening the new window covers
        // the local placeholder and I have to scroll to see it fully").
        // A menu for the list itself. `forSelectionType` hands back an empty set when the click
        // landed on the background rather than on a row, which is exactly the case that had no
        // menu — a row already offers Connect, Edit, Favorite and Delete through its own
        // `.contextMenu`, and those keep answering for clicks on a row.
        .contextMenu(forSelectionType: ID.self) { targets in
            if targets.isEmpty { backgroundActions() }
        }
        // Touch and gaze pull the list down to sync; the Mac has no such gesture, and
        // `refreshable` is simply inert there rather than needing an `#if`.
        .refreshable { await onRefresh?() }
        // Safari's bookmark list on the headset: see `glassSpatialList()`.
        .glassSpatialList()
        .defaultScrollAnchor(.top)
        #if os(macOS)
        .contentMargins(.top, 10, for: .scrollContent)
        #endif
        // On the headset the column's header holds the title and the search field instead
        // (`GlassConnectionLibrary.visionSidebar`, W33): there is no navigation bar there for
        // either to appear in.
        #if !os(visionOS)
        .navigationTitle(title)
        #endif
        // The list does not paint a surface of its own: the window's layered glass is the surface,
        // and the list sits on it. This is what makes the results column match the sidebar instead
        // of being an opaque white panel beside it — and it is why the opacity and frost settings
        // reach this column at all. Painting here was also what produced the seam at the column
        // divider, since an opaque child over a translucent window leaves every pixel it misses
        // showing the desktop.
        .scrollContentBackground(.hidden)
        #if !os(visionOS)
        .searchable(text: $searchText, prompt: "Search connections...")
        .searchFocused($searchFocused)
        #endif
        .onKeyPress(.return, phases: .down) { press in
            guard press.modifiers.isEmpty, !searchFocused, let selection,
                  items.contains(where: { $0.id == selection }) else { return .ignored }
            onActivate(selection)
            return .handled
        }
    }

    @ViewBuilder private var rows: some View {
        ForEach(items) { item in
            // **One shape per row, the list's own.** On the headset these rows also carried
            // spatial padding and a hover effect of their own, so gaze lit a rectangle
            // inside the list's row inside nothing — "a nested CSS cluster that eye
            // tracking reveals layer by layer" (2026-09-28). The list's row is the target.
            row(item).tag(item.id)
                .contentShape(Rectangle())
                .glassSpatialListRow()
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

/// Sections a library list shows after its machines (2026-10-13): Favorites' services, projects,
/// workgroups and folders, which the shell draws because only it can name and open them.
public struct GlassLibraryExtraSections {
    /// What the machines' own section is called when there are other sections under it.
    public let itemsTitle: String
    /// How many rows match the search, the empty string included — the sidebar's count.
    public let count: (String) -> Int
    /// The sections, filtered by the search.
    public let content: (String) -> AnyView

    public init(itemsTitle: String = "Machines", count: @escaping (String) -> Int,
                content: @escaping (String) -> AnyView) {
        self.itemsTitle = itemsTitle
        self.count = count
        self.content = content
    }
}
