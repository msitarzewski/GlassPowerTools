//
//  TerminalWindowOverview.swift
//  Glass Power Tools — GlassTerminal
//
//  A terminal window's overview on iPhone, iPad and Vision Pro (D99; the owner, 2026-11-03: "both seem to be
//  missing coverflow and the new expose"): its tabs as a grid, drawn as All Windows draws its cards, or as the
//  carousel — in real depth on Vision Pro, his choice. The Mac's is `MacTerminalOverview` (D96, D97); both stand on
//  the shell's layout, navigation and carousel row.
//
//  Chosen from the window's Terminal View menu: on iPhone and iPad a button in its top bar (his choice), on Vision
//  Pro the control it already had. A tab chosen opens in the window; Esc, or a tap beside the tiles, goes back.
//

#if os(iOS) || os(visionOS)
import SwiftUI
import GlassShell
import GlassLayers

/// The overview of one window's tabs.
struct TerminalWindowOverview<TileMenu: View>: View {
    let title: String
    let sessions: [TerminalSession]
    @Binding var selection: UUID?
    let style: TerminalOverviewStyle
    /// What the window paints behind its terminal (iPhone and iPad), so a tile looks as the tab does.
    var backdrop: Color?
    /// Opens a tab in the window.
    let open: (UUID) -> Void
    /// Back to the tab in front.
    let close: () -> Void
    /// Vision Pro: a tile drags onto another window or another tile, and takes a tab dropped on it (W15).
    var moving: TerminalOverviewMoving?
    /// A tile's menu, as its tab's.
    @ViewBuilder let menu: (TerminalSession) -> TileMenu

    @State private var filter = ""
    @State private var area: CGSize = .zero
    #if os(visionOS)
    @Environment(SettingsManager.self) private var settings
    /// The window's settings (W20, W22): a tile looks like the terminal it shows.
    @Environment(\.glassWindowOverrides) private var windowSettings
    #endif
    @State private var dropTarget: UUID?
    @FocusState private var focused: Bool

    static var hint: String { "Arrows to move · Return to open · Esc to go back" }

    private var items: [GlassOverviewItem] {
        GlassOverviewItem.filtered(sessions.map(Self.item(of:)), by: filter)
    }

    /// A tab as its tile names and shows it.
    static func item(of session: TerminalSession) -> GlassOverviewItem {
        GlassOverviewItem(
            id: session.id,
            title: TerminalWorkgroupOpening.label(session, on: .grid),
            detail: detail(of: session),
            detailTruncation: .tail,
            identifier: "terminal-overview-tab-\(session.id.uuidString.lowercased())",
            picture: { [weak session] in session.flatMap(GlassTerminalCapability.preview(of:)) },
            mark: { [weak session] in session.flatMap(GlassTerminalCapability.agent(of:))?.markImage })
    }

    /// Where a tab is, as its sidebar row says it: its repository and branch, its machine, in tmux, and its state
    /// while not connected.
    static func detail(of session: TerminalSession) -> String {
        let machine = "\(session.server.username)@\(session.server.host)"
        var line = session.repositoryLine.map { "\($0) · \(machine)" } ?? machine
        if session.survivesClose { line += " · in tmux" }
        if session.state != .connected { line += " — \(session.state.displayName)" }
        return line
    }

    var body: some View {
        let items = self.items
        VStack(spacing: 12) {
            GlassOverviewFindField(text: $filter, matches: items.count)
            GeometryReader { proxy in
                Group {
                    if items.isEmpty {
                        ContentUnavailableView(filter.isEmpty ? "No Terminals" : "No Matches",
                                               systemImage: filter.isEmpty ? "rectangle.3.group" : "magnifyingglass",
                                               description: Text(filter.isEmpty ? "This window has no terminals."
                                                                 : "No terminal's name or folder contains “\(filter)”."))
                    } else if style == .carousel {
                        carousel(items)
                    } else {
                        GlassOverviewGrid(title: title, items: items, selection: selection, size: proxy.size) { item, _ in
                            tile(item)
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .onGeometryChange(for: CGSize.self, of: \.size) { area = $0 }
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 12, trailing: 16))
        .background { backdropLayer }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .return, .escape]) { press in
            handle(press.key, items: items) ? .handled : .ignored
        }
        // A selection typing hid moves to a tile shown; the tab in front is selected to begin with.
        .onChange(of: items.map(\.id), initial: true) { _, ids in
            if let selection, ids.contains(selection) { return }
            selection = ids.first
        }
        .onAppear { focused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Terminal Overview")
        .accessibilityIdentifier("terminal-overview")
    }

    /// Behind the tiles. On iPhone and iPad the terminal under them, blurred and dimmed, as the Mac's overview
    /// stands over its window; a tap there goes back. On Vision Pro the window's own glass is enough.
    @ViewBuilder
    private var backdropLayer: some View {
        #if os(iOS)
        ZStack {
            Rectangle().fill(.regularMaterial)
            Color.black.opacity(0.22)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: close)
        .accessibilityHidden(true)
        #else
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture(perform: close)
            .accessibilityHidden(true)
        #endif
    }

    private func carousel(_ items: [GlassOverviewItem]) -> some View {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return GlassCarouselRow(items: items.map(\.carouselItem), selection: $selection, activate: open) { item, _ in
            if let item = byID[item.id] {
                GlassOverviewTile(item: item, selected: false, backdrop: backdrop, captioned: false)
                    .background { tileBacking }
                    .contextMenu { if let session = session(item.id) { menu(session) } }
            }
        } reflection: { item, _ in
            if let item = byID[item.id] {
                GlassOverviewTile(item: item, selected: false, backdrop: backdrop, captioned: false, live: false)
                    .background { tileBacking }
            }
        }
        .accessibilityIdentifier("terminal-overview-carousel")
    }

    /// A grid tile: tapped, it opens its tab; held, its tab's menu; on Vision Pro it drags and takes a drop.
    @ViewBuilder
    private func tile(_ item: GlassOverviewItem) -> some View {
        let tile = GlassOverviewTile(item: item, selected: selection == item.id, backdrop: backdrop)
            .background { tileBacking }
            .overlay {
                // Where a dragged tab would land.
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(dropTarget == item.id ? 0.22 : 0))
                    .allowsHitTesting(false)
            }
            .onTapGesture { open(item.id) }
            #if os(visionOS)
            // Lit in the tile's own shape: the system's own fills a large target with an oversized capsule.
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 10, style: .continuous))
            .hoverEffect()
            #endif
            .contextMenu { if let session = session(item.id) { menu(session) } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.title)
            .accessibilityValue([item.detail, selection == item.id ? "Selected" : nil].compactMap { $0 }.joined(separator: ", "))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open(item.id) }
            .accessibilityIdentifier(item.identifier)
        if let moving, let index = sessions.firstIndex(where: { $0.id == item.id }) {
            tile
                .draggable(TerminalTabTransfer(workgroupID: moving.workgroupID, sessionID: item.id))
                .dropDestination(for: TerminalTabTransfer.self) { tabs, _ in
                    moving.accept(tabs, index)
                } isTargeted: { targeted in
                    if targeted {
                        dropTarget = item.id
                    } else if dropTarget == item.id {
                        dropTarget = nil
                    }
                }
        } else {
            tile
        }
    }

    /// Behind a tile on Vision Pro: its terminal's own canvas, at the window's opacity, tint and frost, as the
    /// window draws it, so a tile reads in the window and out of it in the carousel's depth. Apple's glass alone
    /// behind a tile barely showed over the window's (the visionOS simulator, 2026-11-03). Nothing on iPhone and
    /// iPad, where the window's page is the tile's `backdrop`.
    @ViewBuilder
    private var tileBacking: some View {
        #if os(visionOS)
        let profile = TerminalWindowProfile.resolved(windowSettings, settings: settings)
        let look = profile.look
        ZStack {
            profile.theme.canvasBackgroundColor.color.opacity(look.opacity)
            if let tint = look.tintColor {
                tint.opacity(TerminalCanvasTint.strength(canvasOpacity: look.opacity))
            }
        }
        .modifier(GlassWindowBackground(interactive: false, material: look.material,
                                        blurAmount: look.blur, appearance: profile.theme.resolvedAppearance))
        .clipShape(.rect(cornerRadius: 10, style: .continuous))
        #else
        EmptyView()
        #endif
    }

    private func session(_ id: UUID) -> TerminalSession? {
        sessions.first { $0.id == id }
    }

    // MARK: Keys

    /// With a keyboard, as the Mac's overview: the arrows move, Return opens, Esc goes back.
    private func handle(_ key: KeyEquivalent, items: [GlassOverviewItem]) -> Bool {
        switch key {
        case .escape:
            close()
        case .return:
            if let selection, items.contains(where: { $0.id == selection }) { open(selection) }
        case .leftArrow where style == .carousel: step(-1, items)
        case .rightArrow where style == .carousel: step(1, items)
        case .upArrow where style == .carousel, .downArrow where style == .carousel: break
        case .leftArrow: navigate(.left, items)
        case .rightArrow: navigate(.right, items)
        case .upArrow: navigate(.up, items)
        case .downArrow: navigate(.down, items)
        default: return false
        }
        return true
    }

    private func step(_ by: Int, _ items: [GlassOverviewItem]) {
        guard !items.isEmpty else { return }
        let index = selection.flatMap { id in items.firstIndex { $0.id == id } } ?? 0
        selection = items[max(0, min(items.count - 1, index + by))].id
    }

    private func navigate(_ direction: GlassAllWindowsNavigation.Direction, _ items: [GlassOverviewItem]) {
        let frames = GlassOverviewGrid<EmptyView>.frames(count: items.count, in: area)
        selection = GlassAllWindowsNavigation.moved(selection, direction,
                                                   in: zip(items, frames).map { (id: $0.id, frame: $1) })
    }
}

/// How the overview's tiles move tabs on Vision Pro: dragged out to another window, or dropped here.
struct TerminalOverviewMoving {
    let workgroupID: UUID
    /// Tabs dropped on the tile at an index; true when any moved.
    let accept: ([TerminalTabTransfer], Int) -> Bool
}

/// The window's Terminal View on iPhone and iPad, in its top bar (D99; his choice): Tabs, Grid, Carousel, as Vision
/// Pro's lists them.
struct TerminalViewMenu: View {
    @Binding var choice: TerminalViewChoice

    var body: some View {
        Menu {
            Picker("Terminal View", selection: $choice) {
                ForEach(TerminalViewChoice.allCases, id: \.self) { choice in
                    Label(choice.title, systemImage: choice.symbolName).tag(choice)
                }
            }
        } label: {
            Label("Terminal View", systemImage: choice.symbolName)
        }
        .accessibilityValue(choice.title)
        .accessibilityIdentifier("terminal-view-menu")
    }
}
#endif
