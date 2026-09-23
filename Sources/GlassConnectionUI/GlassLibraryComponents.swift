import SwiftUI
import GlassConnectionKit
#if os(macOS)
import AppKit
#endif

/// Matches the accepted Connections dimensions in both existing apps.
public enum GlassLibraryColumnLayout {
    public static let navigationMinimum: CGFloat = 240
    public static let navigationIdeal: CGFloat = 340
    public static let navigationMaximum: CGFloat = 480
    public static let resultsMinimum: CGFloat = 320
    public static let resultsIdeal: CGFloat = 510
    public static let resultsMaximum: CGFloat = 760
}

/// The shared Library/Collections section. Apps can append Workgroups, Network,
/// or other specialized sections without duplicating the common categories.
public struct GlassLibraryNavigation<ID: Hashable & Sendable, Extras: View, LibraryExtras: View>: View {
    private let projection: GlassLibraryProjection<ID>
    @Binding private var scope: GlassLibraryScope
    /// The Library-section panel that is open, if one is — it is the highlighted row then, not
    /// the scope (2026-09-22: *"Active doesn't stay highlighted when clicked"*: the panel rows
    /// carried no tag, so the list went on showing All Connections while Active was open).
    @Binding private var openPanelID: String?
    private let onOpenPanel: (String) -> Void
    private let favoriteSymbol: String
    private let onSelect: () -> Void
    private let extras: () -> Extras
    private let libraryExtras: () -> LibraryExtras

    /// - Parameters:
    ///   - extras: sections after the library's own.
    ///   - libraryExtras: rows inside the Library section, after All, Favorites and Recent.
    public init(projection: GlassLibraryProjection<ID>, scope: Binding<GlassLibraryScope>,
                openPanelID: Binding<String?> = .constant(nil),
                onOpenPanel: @escaping (String) -> Void = { _ in },
                favoriteSymbol: String = "star", onSelect: @escaping () -> Void = {},
                @ViewBuilder extras: @escaping () -> Extras,
                @ViewBuilder libraryExtras: @escaping () -> LibraryExtras = { EmptyView() }) {
        _openPanelID = openPanelID
        self.onOpenPanel = onOpenPanel
        self.projection = projection
        _scope = scope
        self.favoriteSymbol = favoriteSymbol
        self.onSelect = onSelect
        self.extras = extras
        self.libraryExtras = libraryExtras
    }

    /// The sidebar is a native `List` selection: AppKit and UIKit draw the platform's own
    /// selection (the inset capsule on macOS 26), so this list matches every other sidebar in the
    /// family instead of painting a row background of its own (project rule 15).
    private var selection: Binding<GlassLibrarySidebarSelection?> {
        Binding(get: { GlassLibrarySidebarSelection.current(scope: scope, openPanelID: openPanelID) },
                set: { value in
            switch GlassLibrarySidebarSelection.change(choosing: value, scope: scope, openPanelID: openPanelID) {
            case nil: return
            case .scope(let chosen)?:
                scope = chosen
                onSelect()
            case .panel(let id)?:
                onOpenPanel(id)
            }
        })
    }

    public var body: some View {
        List(selection: selection) {
            GlassLibraryCategories(projection: projection, category: { value, title, _ in
                category(value, title: title, symbol: symbol(for: value)).tag(GlassLibrarySidebarSelection.scope(value))
            }, extras: libraryExtras)
            extras()
        }
        .listStyle(.sidebar)
        .navigationTitle("Connections")
    }

    private func symbol(for value: GlassLibraryScope) -> String {
        switch value {
        case .allConnections: "server.rack"
        case .favorites: favoriteSymbol
        case .recent: "clock"
        case .collection: "folder"
        }
    }

    private func category(_ value: GlassLibraryScope, title: String, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(projection.itemCount(in: value), format: .number)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        // A plain tap still has to select on a compact stack, where the list is the root and
        // selection alone does not drive navigation.
        .onTapGesture {
            if scope != value { scope = value }
            onSelect()
        }
        .accessibilityAddTraits(scope == value && openPanelID == nil ? .isSelected : [])
        .accessibilityIdentifier("glass-library-scope-\(value.id)")
    }
}

/// What the sidebar list highlights: a scope, or the open panel. One selection type for both,
/// so the native list draws the highlight on whichever row is actually showing.
enum GlassLibrarySidebarSelection: Hashable {
    case scope(GlassLibraryScope)
    case panel(String)

    /// The row to highlight: the open panel, else the scope.
    static func current(scope: GlassLibraryScope, openPanelID: String?) -> Self {
        openPanelID.map { .panel($0) } ?? .scope(scope)
    }

    enum Change: Equatable {
        case scope(GlassLibraryScope)
        case panel(String)
    }

    /// What choosing `value` changes, or nil when it is what is already showing. Choosing the
    /// current scope while a panel is open is a change: it closes the panel.
    static func change(choosing value: Self?, scope: GlassLibraryScope, openPanelID: String?) -> Change? {
        switch value {
        case nil: nil
        case .scope(let chosen)?: chosen == scope && openPanelID == nil ? nil : .scope(chosen)
        case .panel(let id)?: openPanelID == id ? nil : .panel(id)
        }
    }
}

public extension GlassLibraryNavigation where Extras == EmptyView, LibraryExtras == EmptyView {
    init(projection: GlassLibraryProjection<ID>, scope: Binding<GlassLibraryScope>,
         favoriteSymbol: String = "star", onSelect: @escaping () -> Void = {}) {
        self.init(projection: projection, scope: scope, favoriteSymbol: favoriteSymbol,
                  onSelect: onSelect, extras: { EmptyView() }, libraryExtras: { EmptyView() })
    }
}

/// A shared connection row; domain/status icons remain an app-provided accessory.
///
/// The row carries no "last connected" text: the service icons in the accessory already say what
/// a host offers, and a relative date beside them was noise (removed family-wide 2026-09-11).
/// A detail panel is where a connection's history belongs. `subtitle` is optional for the same
/// reason — a row whose accessory names the services does not need to repeat them.
public struct GlassLibraryConnectionRow<Accessory: View, Badges: View>: View {
    private let name: String
    private let subtitle: String?
    private let isFavorite: Bool
    private let favoriteSymbol: String
    private let color: Color?
    private let badges: () -> Badges
    private let accessory: () -> Accessory
    private let nameAccessibilityIdentifier: String?

    /// - Parameter badges: small marks that belong to the machine rather than to the action —
    ///   its service kinds, for instance. They sit **under the name, tight to the leading edge**,
    ///   where they read as a property of the row. Carried in the trailing accessory they competed
    ///   with the control next to them and pushed the name into truncating first.
    public init(name: String, subtitle: String? = nil, isFavorite: Bool = false,
                favoriteSymbol: String = "star.fill", color: Color? = nil,
                nameAccessibilityIdentifier: String? = nil,
                @ViewBuilder badges: @escaping () -> Badges,
                @ViewBuilder accessory: @escaping () -> Accessory) {
        self.name = name
        self.subtitle = subtitle
        self.isFavorite = isFavorite
        self.favoriteSymbol = favoriteSymbol
        self.color = color
        self.badges = badges
        self.accessory = accessory
        self.nameAccessibilityIdentifier = nameAccessibilityIdentifier
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let color {
                Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name).font(GlassSpatialMetrics.rowTitleFont).lineLimit(1)
                        .accessibilityIdentifier(nameAccessibilityIdentifier ?? "glass-library-connection-name")
                    if isFavorite {
                        Image(systemName: favoriteSymbol).font(GlassSpatialMetrics.rowSubtitleFont)
                            .foregroundStyle(.yellow).accessibilityLabel("Favorite")
                    }
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(GlassSpatialMetrics.rowSubtitleFont).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                }
                // Tight to the name: the same leading edge, and only the gap the glyphs need.
                badges()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory()
        }
        .padding(.vertical, GlassSpatialMetrics.isSpatial ? 10 : 4)
        // A floor, so the row is never shorter than the control inside it. A host with no badges
        // yet — the device's own, before its built-in services are known — measured 24pt against a
        // 51pt neighbour, and a bordered-prominent Connect button does not fit in 24pt: it was
        // drawn clipped at the separator. The floor costs nothing on a row that is already taller.
        .frame(minHeight: GlassSpatialMetrics.isSpatial ? 56 : 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

public extension GlassLibraryConnectionRow where Badges == EmptyView {
    /// A row with a trailing accessory and no badges — the shape every consumer used before
    /// service kinds moved under the name.
    init(name: String, subtitle: String? = nil, isFavorite: Bool = false,
         favoriteSymbol: String = "star.fill", color: Color? = nil,
         nameAccessibilityIdentifier: String? = nil,
         @ViewBuilder accessory: @escaping () -> Accessory) {
        self.init(name: name, subtitle: subtitle, isFavorite: isFavorite,
                  favoriteSymbol: favoriteSymbol, color: color,
                  nameAccessibilityIdentifier: nameAccessibilityIdentifier,
                  badges: { EmptyView() }, accessory: accessory)
    }
}

public extension GlassLibraryConnectionRow where Accessory == EmptyView, Badges == EmptyView {
    init(name: String, subtitle: String? = nil, isFavorite: Bool = false,
         favoriteSymbol: String = "star.fill", color: Color? = nil) {
        self.init(name: name, subtitle: subtitle, isFavorite: isFavorite,
                  favoriteSymbol: favoriteSymbol, color: color,
                  badges: { EmptyView() }, accessory: { EmptyView() })
    }
}

/// Preserves the existing grouped details and separate native action footer.
/// The app owns every field and action, including credentials and authorization.
public struct GlassLibraryDetail<Content: View, Actions: View>: View {
    private let title: String
    private let content: () -> Content
    private let actions: () -> Actions
    private let hasSuppliedForm: Bool

    public init(title: String, @ViewBuilder content: @escaping () -> Content,
                @ViewBuilder actions: @escaping () -> Actions) {
        self.title = title
        self.content = content
        self.actions = actions
        hasSuppliedForm = false
    }

    /// Allows an adopting app to retain its existing Form-specific accessibility
    /// and platform modifiers while sharing the surrounding presentation.
    public init(title: String, @ViewBuilder form: @escaping () -> Content,
                @ViewBuilder actions: @escaping () -> Actions) {
        self.title = title
        content = form
        self.actions = actions
        hasSuppliedForm = true
    }

    public var body: some View {
        VStack(spacing: 0) {
            Group {
                // `.scrollContentBackground(.hidden)` for the same reason as the results list: the
                // window's glass is the surface. A grouped form still draws its own row groups, so
                // the content stays legible — it is the page behind them that becomes glass.
                if hasSuppliedForm {
                    content().scrollContentBackground(.hidden)
                } else {
                    Form { content() }.formStyle(.grouped).scrollContentBackground(.hidden)
                }
            }
            Divider()
            // The bar spans the panel and paints its material across the full width. Sizing the
            // material to the buttons let the window's layered theme show through at both ends
            // (observed on macOS, 2026-09-11). Actions sit trailing, the way the family's sheets
            // place Cancel and their primary action, so both bars read as one pattern.
            actions()
                .padding(.horizontal, GlassSpatialMetrics.isSpatial ? 28 : 20)
                .padding(.vertical, GlassSpatialMetrics.isSpatial ? 18 : 12)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .glassActionBarSurface()
        }
        .navigationTitle(title)
    }
}

public extension View {
    /// Per-app namespace preserves independent user divider positions.
    @ViewBuilder func glassLibraryColumnAutosave(_ name: String?) -> some View {
        #if os(macOS)
        if let name { background(GlassLibrarySplitViewAutosave(name: name)) } else { self }
        #else
        self
        #endif
    }
}

#if os(macOS)
private struct GlassLibrarySplitViewAutosave: NSViewRepresentable {
    let name: String
    func makeNSView(context: Context) -> AttachmentView {
        let view = AttachmentView(frame: .zero)
        view.autosaveName = name
        view.applyAutosaveName()
        return view
    }
    func updateNSView(_ nsView: AttachmentView, context: Context) {
        nsView.autosaveName = name
        nsView.applyAutosaveName()
    }
    final class AttachmentView: NSView {
        var autosaveName = ""
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); applyAutosaveName() }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); applyAutosaveName() }
        func applyAutosaveName() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                var candidate = superview
                while let view = candidate {
                    if let split = view as? NSSplitView {
                        if split.autosaveName != autosaveName { split.autosaveName = autosaveName }
                        return
                    }
                    candidate = view.superview
                }
            }
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
#endif
