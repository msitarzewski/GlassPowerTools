//
//  MacTerminalOverviewCarousel.swift
//  Glass Power Tools — GlassTerminal
//
//  The window's overview as a row that flows past the tab in front, as an album view did (the owner,
//  2026-11-02: "i really wanted the carousel to work like the old album view in itunes, but we never got
//  there", then, asked whether to build it: "i dare you 😂 sick live animations, agent like expose?"). The
//  first carousel (removed by D96 the same day) showed three cards turned 12°; this one shows the row: the tab
//  in front flat and large, the rest turned steeply toward it and stacked close on either side, each with its
//  reflection, flowing with a trackpad, a drag, the arrow keys or new output.
//
//  Its tiles are Show All Windows' (`MacTerminalExposeTabTile`): the live picture, the coding agent's mark,
//  the wave while it prints. Every position is a function of how far a tab is from the one in front, in tabs
//  and fractional while it moves, so a tab travels through the middle rather than jumping to its place.
//

#if os(macOS)
import AppKit
import QuartzCore
import SwiftUI
import GlassShell

/// How the window's overview lays out its tabs: Show All Windows' grid, or the carousel. This Mac's choice,
/// kept for every window.
enum MacTerminalOverviewStyle: String, CaseIterable {
    case grid, carousel

    static let key = "com.glasspowertools.terminal.overviewStyle"

    var title: String {
        switch self {
        case .grid: "Grid"
        case .carousel: "Carousel"
        }
    }

    var symbolName: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .carousel: "rectangle.stack"
        }
    }
}

/// Where a tab stands in the carousel, by `d`: how far it is from the tab in front, in tabs. Apart from
/// drawing it, so it is tested.
struct MacTerminalCarouselGeometry: Equatable {
    /// The tile in front.
    let tile: CGSize
    /// How far a tab beside the front turns toward it. None with Reduce Motion: the row slides.
    var turn: Double = 64

    /// Tabs drawn either side of the one in front.
    static let reach = 8

    /// As large as the row's band allows: the front is read, not glanced at (the owner, 2026-11-02: "do we need to
    /// make the focused one larger?"; it had held 0.56 of the band, leaving it a third of his window). Room is kept
    /// for the neighbours' outer edges, drawn taller than the front, and for the top of the reflection; the rest of
    /// the reflection fades out behind the name. No wider than leaves the first neighbour either side in sight.
    init(in band: CGSize, turn: Double = 64) {
        let width = max(160, min(band.width * 0.46, band.height / Self.bandPerTile * 1.6))
        tile = CGSize(width: width, height: width / 1.6)
        self.turn = turn
    }

    /// The band's height for each point of the tile's: the tile, the neighbours' outer edges past it above and below,
    /// and the reflection's brightest part.
    static let bandPerTile: CGFloat = 1.38

    /// Where the middle of the row stands, from the band's top: below the neighbours' outer edges, the row and its
    /// reflection centred in what is left.
    func rowCenter(inBand height: CGFloat) -> CGFloat {
        let above = (outerEdgeHeight - tile.height) / 2
        let used = outerEdgeHeight + tile.height * 0.3
        return above + tile.height / 2 + max(0, (height - used) / 2)
    }

    /// How tall a neighbour's outer edge is drawn: taller than the front, as it comes toward you.
    var outerEdgeHeight: CGFloat {
        let radians = turn * .pi / 180
        let half = tile.width / 2 * scale(1)
        let toward = half * CGFloat(sin(radians)) + depth(1)
        return tile.height * scale(1) / (1 - toward / eye)
    }

    init(tile: CGSize, turn: Double = 64) {
        self.tile = tile
        self.turn = turn
    }

    /// From the middle of the tab in front to the middle of the first beside it: far enough that its inner edge
    /// stands just clear of the front's. Tucked under the front (0.62 of a tile), the neighbours showed through a
    /// glass terminal as dark bands down its edges (the owner's screenshot, 2026-11-02).
    var gap: CGFloat { tile.width / 2 + innerHalf + tile.width * 0.03 }
    /// Between the tabs further out, stacked close.
    var pitch: CGFloat { tile.width * 0.17 }
    /// Points of a drag or a swipe for one tab.
    var perTab: CGFloat { tile.width * 0.30 }
    /// How far the eye stands from the row: the perspective.
    var eye: CGFloat { tile.width * 1.9 }
    /// How far a tab turned beside the front reaches toward it, as seen: its inner edge, turned away from you
    /// and so drawn smaller, by the same perspective `MacTerminalCarouselPlacement` draws with.
    var innerHalf: CGFloat { seenHalf(edgeComingForward: false) }
    /// How far it reaches away from the front: its outer edge, turned toward you and drawn larger.
    var outerHalf: CGFloat { seenHalf(edgeComingForward: true) }

    private func seenHalf(edgeComingForward: Bool) -> CGFloat {
        let radians = turn * .pi / 180
        let half = tile.width / 2 * scale(1)
        let toward = (edgeComingForward ? 1 : -1) * half * CGFloat(sin(radians)) + depth(1)
        return half * CGFloat(cos(radians)) / (1 - toward / eye)
    }

    private func near(_ d: Double) -> Double { min(abs(d), 1) }

    /// Across: the first tab either side opens the gap, the rest follow it closely.
    func x(_ d: Double) -> CGFloat {
        abs(d) <= 1 ? CGFloat(d) * gap : CGFloat(d.sign == .minus ? -1 : 1) * (gap + CGFloat(abs(d) - 1) * pitch)
    }

    /// Turned to face the middle, as an album view turns them: a tab's outer edge comes toward you and its inner
    /// edge goes back (the owner, 2026-11-02, beside Apple's: "should the rear windows be angled like this vs out?";
    /// they had faced out, inner edge forward). Negative on the right, by the transform's own turn.
    func angle(_ d: Double) -> Double { -max(-1, min(1, d)) * turn }

    func scale(_ d: Double) -> CGFloat { 1 - 0.08 * CGFloat(near(d)) }

    /// Set back from the front, so the stacks recede.
    func depth(_ d: Double) -> CGFloat { -CGFloat(near(d)) * tile.width * 0.22 }

    /// Which tab a click lands on, `x` points from the middle of the row: the front within its own width; past
    /// it, the nearest tab whose uncovered strip is there, as each tab covers those further out up to its outer edge.
    func tab(at x: CGFloat, front: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let reach = abs(x)
        let away: Int
        if reach <= tile.width / 2 {
            away = 0
        } else if reach <= gap + outerHalf {
            away = 1
        } else {
            away = 1 + Int(((reach - gap - outerHalf) / pitch).rounded(.up))
        }
        return max(0, min(count - 1, front + (x < 0 ? -away : away)))
    }

    /// The tab a swipe or a drag settles on: the nearest whole tab, inside the row.
    static func settled(_ flow: Double, count: Int) -> Int {
        max(0, min(count - 1, Int(flow.rounded())))
    }
}

/// A tab's place in the row: across, turned toward the front, set back, in perspective. Animated by `d`
/// itself, so a tab moving several places passes through each on the way.
struct MacTerminalCarouselPlacement: GeometryEffect {
    var d: Double
    let geometry: MacTerminalCarouselGeometry

    var animatableData: Double {
        get { d }
        set { d = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let scale = geometry.scale(d)
        var transform = CATransform3DMakeTranslation(-size.width / 2, -size.height / 2, 0)
        transform = CATransform3DConcat(transform, CATransform3DMakeScale(scale, scale, 1))
        transform = CATransform3DConcat(transform, CATransform3DMakeRotation(geometry.angle(d) * .pi / 180, 0, 1, 0))
        transform = CATransform3DConcat(transform, CATransform3DMakeTranslation(0, 0, geometry.depth(d)))
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / geometry.eye
        transform = CATransform3DConcat(transform, perspective)
        transform = CATransform3DConcat(transform, CATransform3DMakeTranslation(size.width / 2 + geometry.x(d), size.height / 2, 0))
        return ProjectionTransform(transform)
    }
}

/// The carousel: this window's tabs, as Show All Windows draws them, in a row that flows.
struct MacTerminalCarousel: View {
    let tiles: [MacTerminalExposeTile]
    let tabs: [UUID: MacWorkspaceController]
    @Binding var selection: MacTerminalExposeItemID?
    let blurred: Bool
    let activate: (UUID) -> Void
    /// Where the row stands: the tab in front, fractional while it moves.
    @State private var flow: Double = 0
    @State private var dragStart: Double?
    @State private var settling: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var front: Int { MacTerminalCarouselGeometry.settled(flow, count: tiles.count) }

    /// Below the row: the front's name and where it is.
    static let captionRoom: CGFloat = 62

    private var spring: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.86)
    }

    var body: some View {
        GeometryReader { proxy in
            let band = CGSize(width: proxy.size.width, height: max(proxy.size.height - Self.captionRoom, 1))
            let geometry = MacTerminalCarouselGeometry(in: band,
                                                       turn: reduceMotion ? 0 : 64)
            ZStack {
                ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                    let d = Double(index) - flow
                    if abs(d) <= Double(MacTerminalCarouselGeometry.reach) + 1, case .tab(let id) = tile.id, let tab = tabs[id] {
                        item(tile, tab: tab, d: d, geometry: geometry)
                            .modifier(MacTerminalCarouselPlacement(d: d, geometry: geometry))
                            .zIndex(-abs(d))
                    }
                }
            }
            .frame(width: proxy.size.width, height: geometry.tile.height)
            .position(x: proxy.size.width / 2, y: geometry.rowCenter(inBand: band.height))
            .overlay(alignment: .bottom) { caption }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(.rect)
            .gesture(drag(geometry))
            .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                choose(at: tap.location.x - proxy.size.width / 2, geometry: geometry)
            })
            .background {
                MacTerminalCarouselScrollMonitor { scroll in moveRow(by: scroll, geometry: geometry) }
            }
        }
        .onAppear { flow = Double(index(of: selection) ?? 0) }
        // Typing narrows the row: where it stands is the selection's place in what is left.
        .onChange(of: tiles.map(\.id)) { _, _ in
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { flow = Double(index(of: selection) ?? 0) }
        }
        // The arrows, new output, a click on a tab beside the front: the row flows to it.
        .onChange(of: selection) { _, selection in
            guard let index = index(of: selection), index != front else { return }
            withAnimation(spring) { flow = Double(index) }
        }
        .onChange(of: front) { _, front in
            guard tiles.indices.contains(front), selection != tiles[front].id else { return }
            selection = tiles[front].id
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Carousel")
        .accessibilityValue(tiles.indices.contains(front) ? tiles[front].title : "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(1)
            case .decrement: step(-1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("terminal-overview-carousel")
    }

    /// A tab: Show All Windows' tile, and below it its reflection on the floor, fading.
    private func item(_ tile: MacTerminalExposeTile, tab: MacWorkspaceController, d: Double,
                      geometry: MacTerminalCarouselGeometry) -> some View {
        MacTerminalExposeTabTile(tab: tab, tile: tile, selected: false, hovering: false,
                                 alwaysVisible: true, blurred: blurred)
            .frame(width: geometry.tile.width, height: geometry.tile.height)
            .overlay(alignment: .bottom) {
                if abs(d) <= 4 {
                    MacWorkspacePreview(controller: tab, alwaysVisible: true)
                        .blur(radius: blurred ? GlassShowAllWindows.previewBlurRadius : 0)
                        .frame(width: geometry.tile.width, height: geometry.tile.height)
                        .scaleEffect(x: 1, y: -1)
                        .mask {
                            LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.08), .clear],
                                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.5))
                        }
                        .offset(y: geometry.tile.height + 3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tile.title)
            .accessibilityValue(tile.location ?? "")
            .accessibilityIdentifier("terminal-overview-tab-\(tab.workspaceID.uuidString.lowercased())")
    }

    /// The tab in front's name and where it is, under the row, as an album's title was.
    @ViewBuilder
    private var caption: some View {
        if tiles.indices.contains(front) {
            let tile = tiles[front]
            VStack(spacing: 3) {
                Text(tile.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                if let location = tile.location {
                    Text(location)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(tile.repository == nil ? .head : .tail)
                }
            }
            .frame(maxWidth: 520)
            .padding(.bottom, 6)
            .id(tile.id)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.18), value: tile.id)
            .allowsHitTesting(false)
        }
    }

    private func index(of id: MacTerminalExposeItemID?) -> Int? {
        id.flatMap { id in tiles.firstIndex { $0.id == id } }
    }

    private func step(_ by: Int) {
        guard !tiles.isEmpty else { return }
        selection = tiles[max(0, min(tiles.count - 1, front + by))].id
    }

    /// The front opens; one beside it comes to the front.
    private func choose(at x: CGFloat, geometry: MacTerminalCarouselGeometry) {
        let index = geometry.tab(at: x, front: front, count: tiles.count)
        guard tiles.indices.contains(index) else { return }
        if index == front, Double(index) == flow, case .tab(let id) = tiles[index].id {
            activate(id)
        } else {
            selection = tiles[index].id
            withAnimation(spring) { flow = Double(index) }
        }
    }

    /// Dragged with the mouse: the row follows the pointer, then settles where it was flung.
    private func drag(_ geometry: MacTerminalCarouselGeometry) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { drag in
                let start = dragStart ?? flow
                if dragStart == nil { dragStart = start }
                flow = rubberBanded(start - Double(drag.translation.width / geometry.perTab))
            }
            .onEnded { drag in
                let start = dragStart ?? flow
                dragStart = nil
                let flung = start - Double(drag.predictedEndTranslation.width / geometry.perTab)
                let target = MacTerminalCarouselGeometry.settled(flung, count: tiles.count)
                withAnimation(spring) { flow = Double(target) }
            }
    }

    /// A swipe on a trackpad moves the row with the fingers, momentum and all, and settles when it stops; a
    /// mouse's wheel steps a tab a notch.
    private func moveRow(by scroll: MacTerminalCarouselScroll, geometry: MacTerminalCarouselGeometry) {
        guard !tiles.isEmpty else { return }
        settling?.cancel()
        if scroll.precise {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { flow = rubberBanded(flow - Double(scroll.delta / geometry.perTab)) }
            settling = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return }
                withAnimation(spring) { flow = Double(MacTerminalCarouselGeometry.settled(flow, count: tiles.count)) }
            }
        } else if scroll.delta != 0 {
            step(scroll.delta > 0 ? -1 : 1)
        }
    }

    /// Past either end the row gives a little, then springs back.
    private func rubberBanded(_ value: Double) -> Double {
        let last = Double(max(tiles.count - 1, 0))
        if value < 0 { return -0.35 * (1 - 1 / (1 - value)) }
        if value > last { return last + 0.35 * (1 - 1 / (1 + value - last)) }
        return value
    }
}

/// A scroll over the carousel: along the row, in points; precise from a trackpad or a Magic Mouse.
struct MacTerminalCarouselScroll {
    let delta: CGFloat
    let precise: Bool
}

/// Hears the scroll wheel and trackpad over this window while the carousel shows, and keeps them from the
/// terminals hidden under it.
private struct MacTerminalCarouselScrollMonitor: NSViewRepresentable {
    let scrolled: (MacTerminalCarouselScroll) -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView() }
    func updateNSView(_ view: MonitorView, context: Context) { view.scrolled = scrolled }
    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stop() }

    final class MonitorView: NSView {
        var scrolled: ((MacTerminalCarouselScroll) -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                // Along the row: a sideways swipe, or a wheel or an up-and-down swipe when that is all there is.
                let across = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
                self.scrolled?(MacTerminalCarouselScroll(delta: across, precise: event.hasPreciseScrollingDeltas))
                return nil
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
#endif
