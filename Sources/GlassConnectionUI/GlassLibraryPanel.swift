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
    private let selectionCheck: (() -> Bool)?

    public init(id: String, sectionTitle: String, title: String, symbolName: String,
                count: Int? = nil,
                hasSelection: (() -> Bool)? = nil,
                @ViewBuilder results: @escaping () -> some View,
                @ViewBuilder detail: @escaping () -> some View) {
        self.id = id
        self.sectionTitle = sectionTitle
        self.title = title
        self.symbolName = symbolName
        self.count = count
        self.selectionCheck = hasSelection
        let results = results
        let detail = detail
        resultsBuilder = { AnyView(results()) }
        detailBuilder = { AnyView(detail()) }
    }

    /// Whether the panel has something selected, and therefore a detail worth showing.
    ///
    /// **A compact stack cannot see a panel's selection.** The library pushes its own detail when
    /// `selection` changes, but a panel owns its selection privately — so on an iPhone, choosing a
    /// row in a panel set a selection nobody pushed for and the detail was simply unreachable.
    /// Every panel had it: SSH Keys could be listed and never opened, and a project could not be
    /// opened at all, which is most of "the editor doesn't work on the phone".
    ///
    /// Read inside a view body, so the panel's own `@Observable` model registers the dependency
    /// and the push happens when the selection actually changes. A panel that does not supply the
    /// check keeps the old behaviour rather than pushing an empty detail.
    public var hasSelection: Bool { selectionCheck?() ?? false }

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
