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
    /// A panel whose `sectionTitle` is this sits **inside** the Library section, after All,
    /// Favorites and Recent, rather than heading a section of its own. Active is the case: it is
    /// a way of looking at the connections, not a different kind of thing.
    public static let librarySectionTitle = "Library"

    /// Stable across launches: it is the selection value and the accessibility identifier.
    public let id: String
    /// The sidebar section this panel heads, e.g. "Workgroups". Panels sharing a title share a
    /// section, in the order given.
    public let sectionTitle: String
    public let title: String
    public let symbolName: String
    private let countProvider: () -> Int?
    private let resultsBuilder: () -> AnyView
    private let detailBuilder: () -> AnyView
    private let selectionToken: (() -> AnyHashable?)?
    private let selectionClear: (() -> Void)?

    /// - Parameters:
    ///   - selection: what the panel has selected, as something comparable. **Not a `Bool`**: see
    ///     `selectedItem`.
    ///   - clearSelection: how to put it back to nothing, called when the detail is popped.
    public init(id: String, sectionTitle: String, title: String, symbolName: String,
                count: @autoclosure @escaping () -> Int? = nil,
                selection: (() -> AnyHashable?)? = nil,
                clearSelection: (() -> Void)? = nil,
                @ViewBuilder results: @escaping () -> some View,
                @ViewBuilder detail: @escaping () -> some View) {
        self.id = id
        self.sectionTitle = sectionTitle
        self.title = title
        self.symbolName = symbolName
        self.countProvider = count
        self.selectionToken = selection
        self.selectionClear = clearSelection
        let results = results
        let detail = detail
        resultsBuilder = { AnyView(results()) }
        detailBuilder = { AnyView(detail()) }
    }

    /// Shown trailing in the sidebar row like a category's count. Nil shows nothing rather than a
    /// zero, because "no count" and "none" are different statements.
    ///
    /// **Asked every time it is drawn, not stored.** A panel a capability rebuilds each time the
    /// library's body runs got a fresh count for free; a *standalone* panel is registered once and
    /// kept, so its count was whatever the list held at launch — Projects said 5 with four in it
    /// after one was removed (reported 2026-09-18). Read inside a view body this registers the
    /// dependency on the contributor's `@Observable` list, exactly as `selectedItem` does, so
    /// removing a project redraws the row that counts them.
    public var count: Int? { countProvider() }

    /// What the panel has selected, if anything — the value a compact stack watches to know when
    /// to push the detail.
    ///
    /// **A compact stack cannot see a panel's selection.** The library pushes its own detail when
    /// `selection` changes, but a panel owns its selection privately — so on an iPhone, choosing a
    /// row in a panel set a selection nobody pushed for and the detail was simply unreachable.
    /// Every panel had it: SSH Keys could be listed and never opened, and a project could not be
    /// opened at all, which is most of "the editor doesn't work on the phone".
    ///
    /// **It reports the item, not a yes/no.** As a `Bool` it went true on the first selection and
    /// stayed true: going back left the panel's selection set, so choosing a *different* row
    /// changed nothing the stack was watching and the tap did nothing at all — reported
    /// 2026-09-18 as *"it just absorbed the click"*, and reproduced in
    /// `EditorOnIPhoneUITests.testAProjectThatRefusesToOpenDoesNotBlockTheNextOne`.
    ///
    /// Read inside a view body, so the panel's own `@Observable` model registers the dependency.
    public var selectedItem: AnyHashable? { selectionToken?() }

    /// Puts the panel back to nothing selected — called when its detail is popped, so choosing the
    /// **same** row again is a change again.
    public func clearSelection() { selectionClear?() }

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
