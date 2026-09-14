import SwiftUI
import GlassConnectionKit

/// A library surface that is not a list of hosts.
///
/// glas.sh had this before the merge and it was the right shape: `ConnectionLibraryMode` carried
/// `workgroups` and `network` beside `library`, `favorites`, `recent` and `collections`, and
/// `libraryResults`/`libraryDetail` switched on it. Workgroups is **fleet-wide** — it spans every
/// machine rather than belonging to one — so it belongs in the same sidebar as Collections, not
/// behind a separate window. Moving it to its own window was the drift.
///
/// A panel is contributed rather than special-cased, so the shell does not learn the name of every
/// capability's surface. Its `results` and `detail` are two views, not one, because they occupy two
/// columns: whatever state they share belongs to a model the contributor owns, exactly as
/// `ConnectionManagerView` owned `selectedWorkgroupSelection` for both halves in glas.sh.
public struct GlassLibraryPanel: Identifiable {
    /// Stable across launches: it is the selection value and the accessibility identifier.
    public let id: String
    /// The sidebar section this panel heads, e.g. "Workgroups". Panels sharing a title share a
    /// section, in the order given.
    public let sectionTitle: String
    public let title: String
    public let symbolName: String
    /// Shown trailing in the sidebar row like a category's count. Nil shows nothing rather than a
    /// zero, because "no count" and "none" are different statements.
    public let count: Int?
    private let resultsBuilder: () -> AnyView
    private let detailBuilder: () -> AnyView

    public init(id: String, sectionTitle: String, title: String, symbolName: String,
                count: Int? = nil,
                @ViewBuilder results: @escaping () -> some View,
                @ViewBuilder detail: @escaping () -> some View) {
        self.id = id
        self.sectionTitle = sectionTitle
        self.title = title
        self.symbolName = symbolName
        self.count = count
        let results = results
        let detail = detail
        resultsBuilder = { AnyView(results()) }
        detailBuilder = { AnyView(detail()) }
    }

    public func results() -> AnyView { resultsBuilder() }
    public func detail() -> AnyView { detailBuilder() }
}

/// What the library is showing: its own host scopes, or a contributed panel.
///
/// One value rather than two pieces of state, so "a panel is open" and "which scope is selected"
/// cannot disagree — the bug that two independent selections always eventually produce.
public enum GlassLibrarySelection: Hashable, Sendable {
    case scope(GlassLibraryScope)
    case panel(String)

    public var panelID: String? {
        if case .panel(let id) = self { return id }
        return nil
    }

    public var scope: GlassLibraryScope? {
        if case .scope(let value) = self { return value }
        return nil
    }
}
