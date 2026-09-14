import SwiftUI
import GlassConnectionKit

/// Native shell for the shared categories. Apps with specialized destinations
/// can compose GlassLibraryNavigation/ConnectionRow/Detail into their existing
/// shells incrementally, preserving workgroup/discovery routing.
public struct GlassConnectionLibrary<ID: Hashable & Sendable, Row: View, Detail: View>: View {
    private let items: [GlassLibraryItem<ID>]
    private let order: GlassLibraryOrder
    @Binding private var selection: ID?
    @Binding private var scope: GlassLibraryScope
    @Binding private var searchText: String
    private let columnAutosaveName: String?
    private let onActivate: (ID) -> Void
    private let row: (GlassLibraryItem<ID>) -> Row
    private let detail: (ID?) -> Detail
    private var toolbarActions: () -> AnyView = { AnyView(EmptyView()) }
    private var sidebarActions: () -> AnyView = { AnyView(EmptyView()) }
    private var presentationAnchor: () -> AnyView = { AnyView(EmptyView()) }
    /// Surfaces that are not lists of hosts — Workgroups, Network — in sidebar order.
    private var panels: [GlassLibraryPanel] = []
    /// Which panel is open, or nil while the library is showing hosts. Held here rather than
    /// beside `scope` so the two cannot disagree about what is on screen.
    @State private var openPanelID: String?
    @State private var compactPath: [CompactDestination] = []
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init(items: [GlassLibraryItem<ID>], selection: Binding<ID?>,
                scope: Binding<GlassLibraryScope>, searchText: Binding<String>,
                order: GlassLibraryOrder = .source, columnAutosaveName: String? = nil,
                onActivate: @escaping (ID) -> Void,
                @ViewBuilder row: @escaping (GlassLibraryItem<ID>) -> Row,
                @ViewBuilder detail: @escaping (ID?) -> Detail) {
        self.items = items
        _selection = selection
        _scope = scope
        _searchText = searchText
        self.order = order
        self.columnAutosaveName = columnAutosaveName
        self.onActivate = onActivate
        self.row = row
        self.detail = detail
    }

    /// Inject app-owned actions at the native navigation roots. Applying an
    /// outer toolbar to this adaptive shell does not reach compact stacks.
    public init<Actions: View>(items: [GlassLibraryItem<ID>], selection: Binding<ID?>,
                scope: Binding<GlassLibraryScope>, searchText: Binding<String>,
                order: GlassLibraryOrder = .source, columnAutosaveName: String? = nil,
                onActivate: @escaping (ID) -> Void,
                @ViewBuilder row: @escaping (GlassLibraryItem<ID>) -> Row,
                @ViewBuilder detail: @escaping (ID?) -> Detail,
                @ViewBuilder toolbarActions: @escaping () -> Actions) {
        self.init(items: items, selection: selection, scope: scope, searchText: searchText,
                  order: order, columnAutosaveName: columnAutosaveName,
                  onActivate: onActivate, row: row, detail: detail)
        self.toolbarActions = { AnyView(toolbarActions()) }
    }

    /// Places app-owned native presentations on exactly one visible navigation
    /// root. Retained compact destinations and inactive vision tabs do not present.
    public init<Actions: View, Anchor: View>(items: [GlassLibraryItem<ID>], selection: Binding<ID?>,
                scope: Binding<GlassLibraryScope>, searchText: Binding<String>,
                order: GlassLibraryOrder = .source, columnAutosaveName: String? = nil,
                onActivate: @escaping (ID) -> Void,
                @ViewBuilder row: @escaping (GlassLibraryItem<ID>) -> Row,
                @ViewBuilder detail: @escaping (ID?) -> Detail,
                @ViewBuilder toolbarActions: @escaping () -> Actions,
                @ViewBuilder presentationAnchor: @escaping () -> Anchor) {
        self.init(items: items, selection: selection, scope: scope, searchText: searchText,
                  order: order, columnAutosaveName: columnAutosaveName,
                  onActivate: onActivate, row: row, detail: detail, toolbarActions: toolbarActions)
        self.presentationAnchor = { AnyView(presentationAnchor()) }
    }

    /// App-owned actions for the sidebar column's own toolbar region. On the Mac and a regular
    /// iPad this is the area beside the sidebar toggle, ahead of it; the library's creation
    /// action belongs here so it sits with the library rather than with the selected item.
    /// Compact iPhone stacks and the vision tab bar have no sidebar region; place those
    /// actions in `toolbarActions` there.
    /// Contributed surfaces that live in the same sidebar as Collections.
    ///
    /// glas.sh's `libraryNavigation` listed `Section("Workgroups")` and `Section("Network")` after
    /// the shared categories, and its results and detail switched on the selected mode. This is
    /// that, contributed instead of hard-coded, so the shell never learns a capability's surfaces
    /// by name.
    public func libraryPanels(_ panels: [GlassLibraryPanel]) -> Self {
        var copy = self
        copy.panels = panels
        return copy
    }

    /// The panels grouped into the sections the sidebar draws, preserving the given order.
    private var panelSections: [(title: String, panels: [GlassLibraryPanel])] {
        var order: [String] = []
        var grouped: [String: [GlassLibraryPanel]] = [:]
        for panel in panels {
            if grouped[panel.sectionTitle] == nil { order.append(panel.sectionTitle) }
            grouped[panel.sectionTitle, default: []].append(panel)
        }
        return order.map { ($0, grouped[$0] ?? []) }
    }

    private var openPanel: GlassLibraryPanel? {
        guard let openPanelID else { return nil }
        return panels.first { $0.id == openPanelID }
    }

    /// The sidebar sections for contributed panels, and the selection behaviour that makes
    /// choosing one close the host list rather than leaving both apparently selected.
    @ViewBuilder private var panelSidebarSections: some View {
        ForEach(panelSections, id: \.title) { section in
            Section(section.title) {
                ForEach(section.panels) { panel in
                    HStack {
                        Label(panel.title, systemImage: panel.symbolName)
                        Spacer()
                        if let count = panel.count {
                            Text(count, format: .number).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .glassGazeHighlight()
                    .onTapGesture {
                        openPanelID = panel.id
                        #if os(iOS)
                        // A compact stack shows the sidebar as its root; without the push the tap
                        // changes state and nothing moves.
                        if horizontalSizeClass == .compact { compactPath = [.results] }
                        #endif
                    }
                    .accessibilityAddTraits(openPanelID == panel.id ? .isSelected : [])
                    .accessibilityIdentifier("glass-library-panel-\(panel.id)")
                }
            }
        }
    }

    public func sidebarActions<Actions: View>(@ViewBuilder _ actions: @escaping () -> Actions) -> Self {
        var copy = self
        copy.sidebarActions = { AnyView(actions()) }
        return copy
    }

    /// The library's primary actions.
    ///
    /// **On visionOS these belong to an ornament, not to the window.** `.toolbar(placement:
    /// .primaryAction)` renders them inside the window's own navigation bar, which on the headset
    /// is three small circles crowded into the top-right corner of the content — the single loudest
    /// signal that an app was ported rather than designed for the platform. An ornament floats the
    /// same controls just below the window at a comfortable size, which is Apple's pattern and what
    /// a visionOS user reaches for. The actions are identical on every platform; only where they
    /// live differs, so a Mac user still recognises the app.
    private func withLibraryToolbar<Content: View>(_ content: Content, active: Bool = true) -> some View {
        #if os(visionOS)
        content
            .ornament(visibility: active ? .visible : .hidden,
                      attachmentAnchor: .scene(.bottom),
                      contentAlignment: .center) {
                HStack(spacing: GlassSpatialMetrics.ornamentSpacing) {
                    toolbarActions()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.large)
                .padding(.horizontal, GlassSpatialMetrics.ornamentPadding)
                .padding(.vertical, GlassSpatialMetrics.ornamentPadding * 0.6)
                .glassBackgroundEffect(in: .capsule)
            }
            .background { if active { presentationAnchor() } }
        #else
        content.toolbar {
            ToolbarItem(id: "glass.library.actions", placement: .primaryAction) { toolbarActions() }
        }.background { if active { presentationAnchor() } }
        #endif
    }

    private var projection: GlassLibraryProjection<ID> { .init(items: items, order: order) }
    private var visibleItems: [GlassLibraryItem<ID>] { projection.items(in: scope, searchQuery: searchText) }

    public var body: some View {
        platformNavigation
            .onChange(of: visibleItems.map(\.id)) { _, _ in reconcileSelection() }
            #if os(iOS)
            .onChange(of: horizontalSizeClass) { _, sizeClass in
                if sizeClass == .compact, selection != nil {
                    compactPath = [.results, .detail]
                } else if sizeClass == .compact, compactPath.last == .detail {
                    compactPath.removeLast()
                }
            }
            #endif
            .onChange(of: selection) { _, value in
                #if os(iOS)
                if horizontalSizeClass == .compact {
                    if value != nil, compactPath.last != .detail {
                        if compactPath.isEmpty { compactPath.append(.results) }
                        compactPath.append(.detail)
                    } else if value == nil, compactPath.last == .detail {
                        compactPath.removeLast()
                    }
                }
                #endif
            }
    }

    @ViewBuilder private var platformNavigation: some View {
        #if os(visionOS)
        visionNavigation
        #elseif os(iOS)
        if horizontalSizeClass == .compact { compactNavigation } else { regularNavigation }
        #else
        regularNavigation
        #endif
    }

    private var regularNavigation: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            GlassLibraryNavigation(projection: projection, scope: $scope,
                                   onSelect: { openPanelID = nil }) { panelSidebarSections }
                .navigationSplitViewColumnWidth(min: GlassLibraryColumnLayout.navigationMinimum,
                                                 ideal: GlassLibraryColumnLayout.navigationIdeal,
                                                 max: GlassLibraryColumnLayout.navigationMaximum)
                // **AppKit's own sidebar toggle on macOS, left alone — the family standard.**
                //
                // glassdb's `databaseSidebarChrome()` removes it on every platform *except* macOS
                // (`glassdb/Constants.swift:267-273`), and glas.sh never removed it. Left alone it
                // sits at the sidebar's trailing edge, stays out of the overflow menu, and moves
                // with the column. A replacement button does none of that: it is an ordinary
                // toolbar item, so it drops into the overflow with its title once the toolbar
                // fills, and it disappears with the sidebar region when the column collapses.
                #if !os(macOS)
                .toolbar(removing: .sidebarToggle)
                #endif
        } content: {
            Group {
                // A panel owns both columns while it is open, the way `libraryResults` switched on
                // `selectedMode` in glas.sh. The host list is not filtered away — it is simply not
                // what the library is showing.
                if let openPanel { openPanel.results() } else { results }
            }
            .navigationSplitViewColumnWidth(min: GlassLibraryColumnLayout.resultsMinimum,
                                             ideal: GlassLibraryColumnLayout.resultsIdeal,
                                             max: GlassLibraryColumnLayout.resultsMaximum)
            .glassLibraryColumnAutosave(columnAutosaveName)
            // The app's own actions lead the content region, past the divider — the placement
            // glassdb gives Add Connection (`ConnectionManagerView.swift:327-330`).
            .toolbar {
                ToolbarItem(id: "glass.library.sidebar-actions", placement: .navigation) {
                    sidebarActions()
                }
            }
        } detail: {
            if let openPanel {
                withLibraryToolbar(openPanel.detail())
            } else {
                withLibraryToolbar(detail(selection))
            }
        }
    }

    private var compactNavigation: some View {
        NavigationStack(path: $compactPath) {
            withLibraryToolbar(
                GlassLibraryNavigation(projection: projection, scope: $scope,
                                       onSelect: {
                                           openPanelID = nil
                                           compactPath = [.results]
                                       }) { panelSidebarSections },
                active: compactPath.isEmpty && selection == nil)
            .navigationDestination(for: CompactDestination.self) { destination in
                switch destination {
                // On a compact stack a panel replaces both pushes: its results are the push from
                // the sidebar, its detail the push from there.
                case .results:
                    if let openPanel {
                        withLibraryToolbar(openPanel.results(), active: compactPath.last == .results)
                    } else {
                        withLibraryToolbar(results, active: compactPath.last == .results && selection == nil)
                    }
                case .detail:
                    if let openPanel {
                        withLibraryToolbar(openPanel.detail(), active: compactPath.last == .detail)
                    } else {
                        withLibraryToolbar(detail(selection), active: compactPath.last == .detail && selection != nil)
                    }
                }
            }
        }
        .onChange(of: compactPath) { _, path in
            if path.last != .detail { selection = nil }
        }
    }

    private var results: some View {
        GlassLibraryResults(items: visibleItems, title: projection.title(for: scope),
                            selection: $selection, searchText: $searchText,
                            onActivate: onActivate, row: row)
    }

    #if os(visionOS)
    private var visionNavigation: some View {
        TabView(selection: visionTabSelection) {
            ForEach(VisionCategory.allCases) { category in
                Group {
                    if category == .collections {
                        NavigationSplitView {
                            List(projection.collections) { collection in
                                Button(collection.name) { scope = .collection(collection.id) }
                                    .buttonStyle(.plain)
                            }
                            .navigationTitle("Collections")
                        } content: {
                            results.navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 460)
                        } detail: { withLibraryToolbar(detail(selection), active: activeTab == .category(category)) }
                    } else {
                        NavigationSplitView {
                            // Wide enough to carry a full-size row. The sidebar was previously left
                            // at the system default and the row's contents were shrunk to fit it,
                            // which is backwards: on a platform aimed with the eyes the column
                            // gives way, not the target.
                            results.navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 460)
                        } detail: { withLibraryToolbar(detail(selection), active: activeTab == .category(category)) }
                    }
                }
                .tabItem { Label(category.title, systemImage: category.symbol) }
                .tag(VisionTab.category(category))
            }
            // A contributed panel is a tab here rather than a sidebar section: visionOS already
            // draws the tab bar as an ornament beside the window, which is the platform's own
            // answer to the same question glas.sh answered with a sidebar section on the Mac.
            ForEach(panels) { panel in
                NavigationSplitView {
                    panel.results().navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 460)
                } detail: {
                    withLibraryToolbar(panel.detail(), active: activeTab == .panel(panel.id))
                }
                .tabItem { Label(panel.title, systemImage: panel.symbolName) }
                .tag(VisionTab.panel(panel.id))
            }
        }
    }

    private var activeTab: VisionTab {
        if let openPanelID, panels.contains(where: { $0.id == openPanelID }) { return .panel(openPanelID) }
        return .category(VisionCategory(scope))
    }

    private var visionTabSelection: Binding<VisionTab> {
        Binding(get: { activeTab }, set: { tab in
            switch tab {
            case .panel(let id):
                openPanelID = id
            case .category(let category):
                openPanelID = nil
                switch category {
                case .all: scope = .allConnections
                case .favorites: scope = .favorites
                case .recent: scope = .recent
                case .collections:
                    if case .collection = scope {} else { scope = .collection("") }
                }
            }
        })
    }

    #endif

    private func reconcileSelection() {
        selection = projection.resolvedSelection(selection, in: scope, searchQuery: searchText)
        #if os(iOS)
        // A compact stack shows the detail only while its path ends in `.detail`. Reloading the
        // items behind a presented sheet (saving a host, adding a service) rebuilds the list and
        // can pop that path, leaving the user at the root with a host still selected once the
        // sheet dismisses. Re-push the detail for a selection that survived the reload.
        if horizontalSizeClass == .compact, selection != nil, compactPath.last != .detail {
            if compactPath.isEmpty { compactPath.append(.results) }
            compactPath.append(.detail)
        }
        #endif
    }
}

private enum CompactDestination: Hashable { case results, detail }

#if os(visionOS)
/// What the spatial tab bar is showing: one of the library's own categories, or a contributed panel.
private enum VisionTab: Hashable {
    case category(VisionCategory)
    case panel(String)
}
#endif

#if os(visionOS)
private enum VisionCategory: String, CaseIterable, Identifiable {
    case all, favorites, recent, collections
    var id: Self { self }
    init(_ scope: GlassLibraryScope) {
        switch scope {
        case .allConnections: self = .all
        case .favorites: self = .favorites
        case .recent: self = .recent
        case .collection: self = .collections
        }
    }
    var title: String {
        switch self { case .all: "All"; case .favorites: "Favorites"; case .recent: "Recent"; case .collections: "Collections" }
    }
    var symbol: String {
        switch self { case .all: "server.rack"; case .favorites: "star"; case .recent: "clock"; case .collections: "folder" }
    }
}
#endif
