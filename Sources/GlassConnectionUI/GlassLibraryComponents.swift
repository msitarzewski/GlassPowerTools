import SwiftUI
import GlassConnectionKit

/// Matches the accepted Connections dimensions in both existing apps.
public enum GlassLibraryColumnLayout {
    public static let navigationMinimum: CGFloat = 240
    public static let navigationIdeal: CGFloat = 340
    public static let navigationMaximum: CGFloat = 480
    /// At an accessibility text size (`glassNavigationColumnWidth()`).
    public static let accessibilityNavigationMinimum: CGFloat = 360
    public static let accessibilityNavigationIdeal: CGFloat = 480
    public static let accessibilityNavigationMaximum: CGFloat = 600
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
    /// Favorites that are not machines, counted with them in the Favorites row.
    private let favoriteExtraCount: Int
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
                favoriteExtraCount: Int = 0,
                favoriteSymbol: String = "star", onSelect: @escaping () -> Void = {},
                @ViewBuilder extras: @escaping () -> Extras,
                @ViewBuilder libraryExtras: @escaping () -> LibraryExtras = { EmptyView() }) {
        _openPanelID = openPanelID
        self.onOpenPanel = onOpenPanel
        self.favoriteExtraCount = favoriteExtraCount
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
            GlassLibraryCategories(projection: projection, favoriteExtraCount: favoriteExtraCount,
                                   category: { value, title, count in
                category(value, title: title, symbol: symbol(for: value), count: count)
                    .tag(GlassLibrarySidebarSelection.scope(value))
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

    private func category(_ value: GlassLibraryScope, title: String, symbol: String, count: Int) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(count, format: .number)
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

    /// The second line's height: a service icon's (`GlassServiceIcon`, 17 pt at body size) or a
    /// line of subtitle text, whichever is taller, whatever the line holds — or nothing at all.
    @ScaledMetric(relativeTo: .body) private var serviceIconSide: CGFloat = 17
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var secondLineMinimum: CGFloat {
        max(serviceIconSide, GlassSpatialMetrics.rowSubtitleLineHeight(dynamicTypeSize))
    }

    public var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name).font(GlassSpatialMetrics.rowTitleFont).lineLimit(1)
                        .accessibilityIdentifier(nameAccessibilityIdentifier ?? "glass-library-connection-name")
                    // **After the name, on its line** — where the favourite star already sits.
                    // In front of the name it pushed a workgroup's name right of where every
                    // other list puts a name, and centred on the row it fell between the two lines
                    // (2026-10-07: "items should remain in consistent position between views").
                    if let color {
                        Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
                    }
                    if isFavorite {
                        Image(systemName: favoriteSymbol).font(GlassSpatialMetrics.rowSubtitleFont)
                            .foregroundStyle(.yellow).accessibilityLabel("Favorite")
                    }
                }
                // **One height for the second line in every list**, so rows do not change height
                // and names do not move when the column switches from Connections to Workgroups,
                // Keys or Projects: service icons are taller than a line of caption text, and a row
                // with neither keeps the space. The hidden text measures a subtitle line at the
                // current size, so this follows Dynamic Type and the headset's larger fonts.
                //
                // A plain minimum height. The first version measured with a hidden text and a
                // zero-width spacer in a ZStack; the headset then crashed twice inside SwiftUI's
                // stack layout, with no frame of ours on the stack (2026-10-07), so the row keeps
                // its layout to the plain stacks it had before.
                VStack(alignment: .leading, spacing: 2) {
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(GlassSpatialMetrics.rowSubtitleFont).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    // Tight to the name: the same leading edge, and only the gap the glyphs need.
                    badges()
                }
                .frame(minHeight: secondLineMinimum, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory()
        }
        // The list's own row insets are the padding on the headset; 10 pt more here, and 8 more
        // from the spatial row metrics, made rows twice the height of Safari's (2026-09-28).
        .padding(.vertical, GlassSpatialMetrics.isSpatial ? 2 : 4)
        // A floor, so the row is never shorter than the control inside it. A host with no badges
        // yet — the device's own, before its built-in services are known — measured 24pt against a
        // 51pt neighbour, and a bordered-prominent Connect button does not fit in 24pt: it was
        // drawn clipped at the separator. The floor costs nothing on a row that is already taller.
        .frame(minHeight: GlassSpatialMetrics.isSpatial ? 44 : 36)
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
        // The navigation title, and on an iPad or an unfolded iPhone Duo a large title on the list
        // column's line instead of the system's in the toolbar row (2026-10-12).
        .glassDetailColumnTitle(title)
        // On the headset the column's own header, where the navigation bar's title was (W33).
        .glassSpatialColumn(title)
    }
}
