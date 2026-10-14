//
//  GlassFavoriteSections.swift
//  Glass Power Tools — GlassShell
//
//  Favorites' sections after its machines (the owner, 2026-10-13: "Favorites should be machines OR
//  services OR projects OR Workgroups OR SFTP (at the current folder depth)"; laid out in sections by
//  kind, his choice). A service is the shell's to name and connect; a project, a workgroup and a
//  folder are described by the composition root, which holds the editor and the terminal
//  (`GlassShellModel.describeFavorite`). A favourite whose thing is gone, or has not reached this
//  device yet, is simply not listed — its star stays, so it shows again when the thing does.
//

import SwiftUI
import GlassConnectionKit
import GlassConnectionUI

/// How Favorites shows and opens one of its non-machine favourites.
public struct GlassFavoriteDescription {
    /// More than Open, in the row's menu: a folder's terminal there, for one.
    public struct Action: Identifiable {
        public let title: String
        public let symbolName: String
        public let perform: @MainActor () -> Void
        public var id: String { title }

        public init(title: String, symbolName: String, perform: @escaping @MainActor () -> Void) {
            self.title = title
            self.symbolName = symbolName
            self.perform = perform
        }
    }

    public var title: String
    /// What it is and where: "Database on alpha", "/srv/app on bravo", "3 terminals".
    public var subtitle: String
    public var symbol: GlassServiceSymbol
    /// What opening it is called: Connect for a service, Open otherwise.
    public var openTitle: String
    public var open: @MainActor () -> Void
    public var actions: [Action]

    public init(title: String, subtitle: String, symbol: GlassServiceSymbol, openTitle: String = "Open",
                open: @escaping @MainActor () -> Void, actions: [Action] = []) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.openTitle = openTitle
        self.open = open
        self.actions = actions
    }
}

/// One listed favourite.
public struct GlassFavoriteRowContent: Identifiable {
    public let item: GlassFavorite
    public let description: GlassFavoriteDescription
    public var id: String { item.key }
}

public extension GlassShellModel {
    /// How Favorites shows `item`, or nil when what it names is not on this device.
    func favoriteDescription(_ item: GlassFavorite) -> GlassFavoriteDescription? {
        guard case .service(let endpoint) = item else { return describeFavorite?(item) }
        guard let host = host(owningEndpoint: endpoint),
              let service = host.services.first(where: { $0.endpointID == endpoint }) else { return nil }
        let kindName = GlassServicePresentation.displayName(for: service.kind)
        // A service called only by its kind — "Terminal" — is named by its machine instead.
        let namedByKind = service.displayName.isEmpty || service.displayName == kindName
        return GlassFavoriteDescription(
            title: namedByKind ? host.displayName : service.displayName,
            subtitle: namedByKind ? kindName : "\(kindName) on \(host.displayName)",
            symbol: GlassServicePresentation.symbol(for: service.kind),
            openTitle: "Connect",
            open: { [weak self] in self?.connect(hostID: host.id, endpointID: endpoint) })
    }

    /// Favorites' non-machine rows that match `search` (by name or by what and where), in section order.
    func favoriteRows(matching search: String) -> [GlassFavoriteRowContent] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return favoriteItems.compactMap { item in
            guard let description = favoriteDescription(item) else { return nil }
            guard query.isEmpty || description.title.localizedCaseInsensitiveContains(query)
                    || description.subtitle.localizedCaseInsensitiveContains(query) else { return nil }
            return GlassFavoriteRowContent(item: item, description: description)
        }
    }

    /// What the library list draws under Favorites' machines.
    var favoriteSections: GlassLibraryExtraSections {
        GlassLibraryExtraSections(
            count: { [weak self] in self?.favoriteRows(matching: $0).count ?? 0 },
            content: { [weak self] search in
                guard let self else { return AnyView(EmptyView()) }
                return AnyView(GlassFavoriteSectionsList(model: self, search: search))
            })
    }
}

/// The sections, one per kind that has a favourite.
struct GlassFavoriteSectionsList: View {
    let model: GlassShellModel
    let search: String

    var body: some View {
        let rows = model.favoriteRows(matching: search)
        ForEach(GlassFavorite.Kind.allCases, id: \.self) { kind in
            let inKind = rows.filter { $0.item.kind == kind }
            if !inKind.isEmpty {
                Section(kind.sectionTitle) {
                    ForEach(inKind) { row in GlassFavoriteRow(model: model, row: row) }
                }
            }
        }
    }
}

/// A favourite: a click or tap opens it, as a Finder sidebar favourite does; its menu has the rest.
struct GlassFavoriteRow: View {
    let model: GlassShellModel
    let row: GlassFavoriteRowContent

    var body: some View {
        let description = row.description
        Button { description.open() } label: {
            GlassLibraryConnectionRow(name: description.title, isFavorite: true,
                                      nameAccessibilityIdentifier: "favorite-row-\(description.title)") {
                Label {
                    Text(description.subtitle).lineLimit(1).truncationMode(.middle)
                } icon: {
                    GlassServiceIcon(description.symbol)
                }
                .labelStyle(.titleAndIcon)
                .font(GlassSpatialMetrics.rowSubtitleFont)
                .foregroundStyle(.secondary)
            } accessory: {
                EmptyView()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassSpatialListRow()
        .contextMenu {
            Button(description.openTitle, systemImage: "play.fill") { description.open() }
            ForEach(description.actions) { action in
                Button(action.title, systemImage: action.symbolName) { action.perform() }
            }
            Divider()
            Button("Remove Favorite", systemImage: "star.slash") { model.setFavorite(row.item, false) }
        }
        .labelStyle(.titleAndIcon)
        .accessibilityHint("\(description.openTitle)s \(description.title)")
    }
}

/// What a capability's own surfaces ask of Favorites — a project's or a workgroup's star, Files'
/// Add This Folder to Favorites (2026-10-13). The shell owns the list; a capability only asks.
public struct GlassFavoritesAccess {
    public let isFavorite: @MainActor (GlassFavorite) -> Bool
    public let setFavorite: @MainActor (GlassFavorite, Bool) -> Void

    public init(isFavorite: @escaping @MainActor (GlassFavorite) -> Bool,
                setFavorite: @escaping @MainActor (GlassFavorite, Bool) -> Void) {
        self.isFavorite = isFavorite
        self.setFavorite = setFavorite
    }

    @MainActor public func toggle(_ item: GlassFavorite) { setFavorite(item, !isFavorite(item)) }
}

public extension GlassShellModel {
    var favoritesAccess: GlassFavoritesAccess {
        GlassFavoritesAccess(isFavorite: { [weak self] in self?.isFavorite($0) ?? false },
                             setFavorite: { [weak self] item, value in self?.setFavorite(item, value) })
    }
}

public extension EnvironmentValues {
    /// Favorites, for a view whose window the capability builds — Files (2026-10-13).
    @Entry var glassFavorites: GlassFavoritesAccess? = nil
}
