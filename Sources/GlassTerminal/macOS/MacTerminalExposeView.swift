//
//  MacTerminalExposeView.swift
//  Glass Power Tools — GlassTerminal
//
//  What Show All Windows draws (`MacTerminalExpose`): the dimmed, blurred backdrop, a group per
//  terminal window with a live tile per tab, the "Not in a window" group of tmux sessions no tab
//  shows, and a group per other kind of window — Databases, Desktops, Editor (2026-10-13). Tiles
//  are `MacWorkspacePreview`s and sessions' own snapshots — images, never live surfaces.
//

#if os(macOS)
import AppKit
import SwiftUI
import GlassLayers
import GlassShell

struct MacTerminalExposeView: View {
    let expose: MacTerminalExpose
    let insets: EdgeInsets
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Settings ▸ Appearance ▸ Show All Windows ▸ Blur previews (GlassShowAllWindows.blursPreviewsKey).
    @AppStorage(GlassShowAllWindows.blursPreviewsKey, store: GlassUITestRun.settingsDefaults) private var blursPreviews = false
    @State private var appeared = false
    @State private var hovered: MacTerminalExposeItemID?
    @State private var dropTarget: UUID?
    /// The space the groups are laid out in, kept for the arrow keys.
    @State private var area: CGSize = .zero
    @FocusState private var focused: Bool

    private var windows: [MacWorkspacePreviewRegistry.ShownWindow] { expose.registry.shownWindows }

    /// Read in the body, so titles, tabs and windows follow the app while it is open.
    private var groups: [MacTerminalExposeGroup] {
        let windowGroups = MacTerminalExposeModel.groups(windows: windows.map(\.controller),
                                                         servers: sessionManager.serverManager.servers)
        let unshown = MacTerminalExposeModel.notInAWindowGroup(expose.unshownSessions).map { [$0] } ?? []
        let others = MacTerminalExposeModel.otherGroups(expose.otherSessions)
        return MacTerminalExposeModel.filtered(windowGroups + unshown + others, by: expose.filter)
    }

    var body: some View {
        let groups = self.groups
        let visible = appeared && !expose.isClosing
        ZStack {
            MacTerminalExposeBackdrop { expose.close() }
            VStack(spacing: 14) {
                MacTerminalExposeHeader(filter: expose.filter,
                                        matches: groups.reduce(0) { $0 + $1.tiles.count })
                GeometryReader { proxy in
                    arrangement(groups, in: proxy.size)
                }
                .onGeometryChange(for: CGSize.self, of: \.size) { area = $0 }
            }
            .padding(EdgeInsets(top: insets.top + 24, leading: insets.leading + 32,
                                bottom: insets.bottom + 28, trailing: insets.trailing + 32))
            // Mission Control's zoom: the groups settle into place as the screen dims.
            .scaleEffect(visible || reduceMotion ? 1 : 1.06)
            .opacity(visible ? 1 : 0)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: [.down, .repeat]) { press in
            handle(press, groups: groups) ? .handled : .ignored
        }
        .background {
            MacTerminalExposePinchMonitor { outcome in
                if outcome == .pinchedOut { expose.close() }
            }
        }
        // From the start too: a selection the filter or a closed window hid moves to a tile shown.
        .onChange(of: groups.flatMap { $0.tiles.map(\.id) }, initial: true) { _, ids in
            let kept = MacTerminalExposeModel.selection(expose.selection, shown: ids)
            if kept != expose.selection { expose.selection = kept }
        }
        .onAppear {
            focused = true
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.28, bounce: 0.1)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(GlassShowAllWindows.title)
        .accessibilityIdentifier("terminal-expose")
    }

    // MARK: Arrangement

    @ViewBuilder
    private func arrangement(_ groups: [MacTerminalExposeGroup], in size: CGSize) -> some View {
        let layout = MacTerminalExposeLayout(tileCounts: groups.map(\.tiles.count), in: size)
        if groups.isEmpty {
            MacTerminalExposeEmpty(filter: expose.filter)
                .frame(width: size.width, height: size.height)
        } else if layout.scrolls {
            ScrollView {
                canvas(groups, layout)
                    .frame(width: layout.contentSize.width, height: layout.contentSize.height)
            }
            .scrollIndicators(.automatic)
        } else {
            canvas(groups, layout)
        }
    }

    private func canvas(_ groups: [MacTerminalExposeGroup], _ layout: MacTerminalExposeLayout) -> some View {
        let tabs = Dictionary(windows.flatMap(\.controller.tabs).map { ($0.workspaceID, $0) },
                              uniquingKeysWith: { first, _ in first })
        let sessions = Dictionary(expose.otherSessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ZStack(alignment: .topLeading) {
            ForEach(Array(zip(groups, layout.groups)), id: \.0.id) { group, frames in
                groupView(group, frames: frames, tileSize: layout.tileSize, tabs: tabs, sessions: sessions,
                          scrolls: layout.scrolls)
                    .frame(width: frames.frame.width, height: frames.frame.height)
                    .position(x: frames.frame.midX, y: frames.frame.midY)
            }
        }
    }

    private func groupView(_ group: MacTerminalExposeGroup, frames: MacTerminalExposeLayout.Group,
                           tileSize: CGSize, tabs: [UUID: MacWorkspaceController],
                           sessions: [String: GlassOpenSession], scrolls: Bool) -> some View {
        let windowID: UUID? = if case .window(let id) = group.id { id } else { nil }
        let origin = frames.frame.origin
        let targeted = windowID != nil && dropTarget == windowID
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(targeted ? Color.accentColor : Color.white.opacity(0.14), lineWidth: targeted ? 3 : 1)
                }
                .contentShape(.rect(cornerRadius: 18))
                // The group itself is the window: clicking it goes back to the tab it shows.
                .onTapGesture {
                    if let windowID, let window = windows.first(where: { $0.controller.windowID == windowID }) {
                        expose.choose(.tab(window.controller.selectedTabID))
                    }
                }
            Label(group.title, systemImage: Self.symbol(for: group))
                .font(.headline)
                .lineLimit(1)
                .foregroundStyle(.primary)
                .frame(width: frames.titleFrame.width, height: frames.titleFrame.height, alignment: .leading)
                .offset(x: frames.titleFrame.minX - origin.x, y: frames.titleFrame.minY - origin.y)
                .allowsHitTesting(false)
            ForEach(Array(zip(group.tiles, frames.tileFrames)), id: \.0.id) { tile, frame in
                tileView(tile, tab: tabID(tile.id).flatMap { tabs[$0] }, windowID: windowID,
                         session: sessionID(tile.id).flatMap { sessions[$0] },
                         size: tileSize, alwaysVisible: !scrolls)
                    .position(x: frame.midX - origin.x, y: frame.midY - origin.y)
            }
        }
        .onDrop(of: [MacWorkspaceTabDrag.type], isTargeted: Binding(
            get: { targeted },
            set: { dropTarget = $0 ? windowID : (dropTarget == windowID ? nil : dropTarget) }
        )) { providers in
            guard let windowID else { return false }
            MacWorkspaceTabDrag.load(from: providers) { drags in expose.drop(drags, onto: windowID) }
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(group.title)
    }

    /// A terminal window's group, the tmux sessions no window shows, or a kind of window by the
    /// symbol its sessions carry.
    private static func symbol(for group: MacTerminalExposeGroup) -> String {
        switch group.id {
        case .window: "macwindow"
        case .notInAWindow: "rectangle.dashed"
        case .kind: group.tiles.first?.symbolName ?? "macwindow"
        }
    }

    @ViewBuilder
    private func tileView(_ tile: MacTerminalExposeTile, tab: MacWorkspaceController?, windowID: UUID?,
                          session: GlassOpenSession?, size: CGSize, alwaysVisible: Bool) -> some View {
        let selected = expose.selection == tile.id
        let hovering = hovered == tile.id
        Group {
            if let tab, let windowID {
                MacTerminalExposeTabTile(tab: tab, tile: tile, selected: selected, hovering: hovering,
                                         alwaysVisible: alwaysVisible, blurred: blursPreviews)
                    .onDrag { MacWorkspaceTabDrag(windowID: windowID, workspaceID: tab.workspaceID).itemProvider() }
            } else if case .session = tile.id {
                MacTerminalExposeWindowTile(tile: tile, session: session, selected: selected, hovering: hovering,
                                            blurred: blursPreviews)
            } else {
                MacTerminalExposeSessionTile(tile: tile, selected: selected) { expose.choose(tile.id) }
            }
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(hovering && !reduceMotion ? 1.03 : 1)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { inside in
            if inside { hovered = tile.id } else if hovered == tile.id { hovered = nil }
        }
        .onTapGesture { expose.choose(tile.id) }
        .help([tile.title, tile.location ?? tile.detail].compactMap { $0 }.joined(separator: " — "))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.title)
        .accessibilityValue([tile.location ?? tile.detail, selected ? "Selected" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { expose.choose(tile.id) }
        .accessibilityIdentifier(identifier(tile.id))
    }

    private func tabID(_ id: MacTerminalExposeItemID) -> UUID? {
        if case .tab(let workspaceID) = id { workspaceID } else { nil }
    }

    private func sessionID(_ id: MacTerminalExposeItemID) -> String? {
        if case .session(let sessionID) = id { sessionID } else { nil }
    }

    private func identifier(_ id: MacTerminalExposeItemID) -> String {
        switch id {
        case .tab(let workspaceID): "terminal-expose-tab-\(workspaceID.uuidString.lowercased())"
        case .tmux(let name): "terminal-expose-tmux-\(name)"
        case .session(let id): "expose-session-\(id)"
        }
    }

    // MARK: Keys

    /// Arrows move, Return opens, Escape closes, Delete and typing edit the filter. Anything with
    /// ⌘ or ⌃ is left for the menu bar, so ⇧⌘\ closes it again.
    private func handle(_ press: KeyPress, groups: [MacTerminalExposeGroup]) -> Bool {
        guard press.modifiers.isDisjoint(with: [.command, .control]) else { return false }
        switch press.key {
        case .escape:
            expose.close()
        case .return:
            if let selection = expose.selection, groups.contains(where: { $0.tiles.contains { $0.id == selection } }) {
                expose.choose(selection)
            }
        case .leftArrow: navigate(.left, groups)
        case .rightArrow: navigate(.right, groups)
        case .upArrow: navigate(.up, groups)
        case .downArrow: navigate(.down, groups)
        case .delete, .deleteForward:
            if !expose.filter.isEmpty { expose.filter.removeLast() }
        default:
            let typed = press.characters.filter { character in
                character.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
                    && !(0xF700...0xF8FF).contains(character.unicodeScalars.first?.value ?? 0)
            }
            guard !typed.isEmpty else { return false }
            expose.filter += typed
        }
        return true
    }

    private func navigate(_ direction: MacTerminalExposeNavigation.Direction, _ groups: [MacTerminalExposeGroup]) {
        let layout = MacTerminalExposeLayout(tileCounts: groups.map(\.tiles.count), in: area)
        let items = zip(groups, layout.groups).flatMap { group, frames in
            zip(group.tiles, frames.tileFrames).map { (id: $0.id, frame: $1) }
        }
        expose.selection = MacTerminalExposeNavigation.moved(expose.selection, direction, in: items)
    }
}

/// A tab, live: its panes as images, the activity wave while it prints, and its name and folder
/// on hover or when selected.
private struct MacTerminalExposeTabTile: View {
    let tab: MacWorkspaceController
    let tile: MacTerminalExposeTile
    let selected: Bool
    let hovering: Bool
    let alwaysVisible: Bool
    let blurred: Bool

    var body: some View {
        MacWorkspacePreview(controller: tab, alwaysVisible: alwaysVisible)
            // The picture only, never its name: Blur previews (GlassShowAllWindows.blursPreviewsKey).
            .blur(radius: blurred ? GlassShowAllWindows.previewBlurRadius : 0)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .bottom) {
                if tile.isBusy {
                    MacTerminalActivityShimmer(color: tab.workgroupColor?.color ?? .accentColor)
                        .frame(height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: tile.isBusy)
            // The agent the tab is running, in the middle of its picture.
            .overlay { if let agent = tile.agent { MacTerminalExposeAgentMark(agent: agent) } }
            .overlay(alignment: .bottom) {
                if selected || hovering {
                    // `repo · branch · folder` loses its end, where the least is said; a folder
                    // path its start, keeping the folder itself (W11).
                    MacTerminalExposeCaption(title: tile.title, detail: tile.location,
                                             detailTruncation: tile.repository == nil ? .head : .tail)
                        .padding(8)
                        .transition(.opacity)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? Color.accentColor : Color.white.opacity(0.16), lineWidth: selected ? 3 : 1)
            }
            .shadow(color: .black.opacity(0.35), radius: hovering ? 14 : 8, y: 4)
            .contentShape(.rect(cornerRadius: 10))
    }
}

/// Another kind of window — a desktop, a database, an editor: its picture where its session can
/// draw one (a desktop's screen), else its symbol, name and state. Choosing it brings the window
/// forward (`GlassOpenSession.activate`).
private struct MacTerminalExposeWindowTile: View {
    let tile: MacTerminalExposeTile
    let session: GlassOpenSession?
    let selected: Bool
    let hovering: Bool
    let blurred: Bool

    var body: some View {
        let picture = session?.snapshot?()
        ZStack {
            if let picture {
                picture.resizable().aspectRatio(contentMode: .fit)
                    .blur(radius: blurred ? GlassShowAllWindows.previewBlurRadius : 0)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: tile.symbolName ?? "macwindow")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                    Text(tile.title)
                        .font(.headline)
                        .lineLimit(1)
                    if let detail = tile.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .bottom) {
            if picture != nil, selected || hovering {
                MacTerminalExposeCaption(title: tile.title, detail: tile.detail)
                    .padding(8)
                    .transition(.opacity)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Color.accentColor : Color.white.opacity(0.16), lineWidth: selected ? 3 : 1)
        }
        .shadow(color: .black.opacity(0.35), radius: hovering ? 14 : 8, y: 4)
        .contentShape(.rect(cornerRadius: 10))
    }
}

/// A tmux session on this Mac that no tab shows: what it is, and Reopen.
private struct MacTerminalExposeSessionTile: View {
    let tile: MacTerminalExposeTile
    let selected: Bool
    let reopen: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if let logo = tile.agent?.logo {
                Image(nsImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Running \(tile.agent?.displayName ?? "")")
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
            }
            Text(tile.title)
                .font(.headline)
                .lineLimit(1)
            if let detail = tile.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            Button("Reopen", action: reopen)
                .controlSize(.small)
                .help("Open this session in a terminal window")
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(selected ? Color.accentColor : Color.white.opacity(0.16), lineWidth: selected ? 3 : 1)
        }
        .contentShape(.rect(cornerRadius: 10))
    }
}

/// Which AI agent a tile's terminal is running (the owner, 2026-10-14: "put a monochrome logo in
/// the center of the window in expose mode"): the agent's mark, one colour, sized to the tile, on a
/// soft disc so it reads over any picture, sharp or blurred.
private struct MacTerminalExposeAgentMark: View {
    let agent: TerminalAgent

    var body: some View {
        GeometryReader { geometry in
            let side = min(max(min(geometry.size.width, geometry.size.height) * 0.3, 28), 88)
            ZStack {
                Circle()
                    .fill(.black.opacity(0.42))
                    .frame(width: side * 1.6, height: side * 1.6)
                    .blur(radius: side * 0.18)
                if let logo = agent.logo {
                    Image(nsImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: side, height: side)
                        .foregroundStyle(.white.opacity(0.92))
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Running \(agent.displayName)")
    }
}

private struct MacTerminalExposeCaption: View {
    let title: String
    let detail: String?
    var detailTruncation: Text.TruncationMode = .head

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
            if let detail {
                // Legible over whatever the tile shows (the owner, 2026-10-13: "TIL that there's
                // actually a second line. Let's make sure that's legible"): secondary grey on a thin
                // material let the terminal's text behind show through it.
                Text(detail)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.primary.opacity(0.78))
                    .lineLimit(1)
                    .truncationMode(detailTruncation)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// What typing has narrowed to, and how to drive it.
private struct MacTerminalExposeHeader: View {
    let filter: String
    let matches: Int

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                if filter.isEmpty {
                    Text("Type to find a terminal by name or folder")
                        .foregroundStyle(.secondary)
                } else {
                    Text(filter)
                    Text(matches == 1 ? "1 terminal" : "\(matches) terminals")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.title3)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            Text("Arrows to move · Return to open · drag a terminal onto another window to move it · Esc to close")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MacTerminalExposeEmpty: View {
    let filter: String

    var body: some View {
        ContentUnavailableView {
            Label(filter.isEmpty ? "No Terminal Windows" : "No Matches", systemImage: "rectangle.3.group")
        } description: {
            Text(filter.isEmpty ? "Open a terminal to see it here." : "No terminal's name or folder contains “\(filter)”.")
        }
    }
}

/// Mission Control's backdrop: what is behind, blurred by the system material and dimmed. A click
/// on it closes the overlay. Reduce Transparency turns the material solid, which AppKit does.
private struct MacTerminalExposeBackdrop: View {
    let close: () -> Void

    var body: some View {
        ZStack {
            MacTerminalExposeBlur()
            Color.black.opacity(0.22)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: close)
        .accessibilityHidden(true)
    }
}

private struct MacTerminalExposeBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
#endif
