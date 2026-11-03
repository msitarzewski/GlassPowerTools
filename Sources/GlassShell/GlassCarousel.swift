//
//  GlassCarousel.swift
//  Glass Power Tools — GlassShell
//
//  A row that flows past the item in front, as an album view did: the item in front flat and large, the rest
//  turned steeply toward it and stacked close on either side, each with its reflection, flowing with a swipe, a
//  drag, the arrow keys or new output. Built for the Mac's Terminal Overview (D97, `MacTerminalCarousel`) and moved
//  here so iPhone, iPad and Vision Pro draw the same row (D99; the owner, 2026-11-03: "both seem to be missing
//  coverflow"). On Vision Pro the row stands in real depth (his choice): the items beside the front are turned and
//  set back in space rather than drawn in perspective on the window.
//
//  Every position is a function of how far an item is from the one in front, in items and fractional while it
//  moves, so an item travels through the middle rather than jumping to its place.
//

import SwiftUI
import QuartzCore

/// Where an item stands in the carousel, by `d`: how far it is from the item in front, in items. Apart from
/// drawing it, so it is tested.
public struct GlassCarouselGeometry: Equatable {
    /// The tile in front.
    public let tile: CGSize
    /// How far an item beside the front turns toward it. None with Reduce Motion: the row slides.
    public var turn: Double = 64

    /// Items drawn either side of the one in front.
    public static let reach = 8

    /// As large as the row's band allows: the front is read, not glanced at (the owner, 2026-11-02: "do we need to
    /// make the focused one larger?"; it had held 0.56 of the band, leaving it a third of his window). Room is kept
    /// for the neighbours' outer edges, drawn taller than the front, and for the top of the reflection; the rest of
    /// the reflection fades out behind the name. No wider than leaves the first neighbour either side in sight.
    public init(in band: CGSize, turn: Double = 64, share: CGFloat = 0.46) {
        let width = max(160, min(band.width * share, band.height / Self.bandPerTile * 1.6))
        tile = CGSize(width: width, height: width / 1.6)
        self.turn = turn
    }

    public init(tile: CGSize, turn: Double = 64) {
        self.tile = tile
        self.turn = turn
    }

    /// The band's height for each point of the tile's: the tile, the neighbours' outer edges past it above and below,
    /// and the reflection's brightest part.
    public static let bandPerTile: CGFloat = 1.38

    /// Where the middle of the row stands, from the band's top: below the neighbours' outer edges, the row and its
    /// reflection centred in what is left.
    public func rowCenter(inBand height: CGFloat) -> CGFloat {
        let above = (outerEdgeHeight - tile.height) / 2
        let used = outerEdgeHeight + tile.height * 0.3
        return above + tile.height / 2 + max(0, (height - used) / 2)
    }

    /// How tall a neighbour's outer edge is drawn: taller than the front, as it comes toward you.
    public var outerEdgeHeight: CGFloat {
        let radians = turn * .pi / 180
        let half = tile.width / 2 * scale(1)
        let toward = half * CGFloat(sin(radians)) + depth(1)
        return tile.height * scale(1) / (1 - toward / eye)
    }

    /// From the middle of the item in front to the middle of the first beside it: far enough that its inner edge
    /// stands just clear of the front's. Tucked under the front (0.62 of a tile), the neighbours showed through a
    /// glass terminal as dark bands down its edges (the owner's screenshot, 2026-11-02).
    public var gap: CGFloat { tile.width / 2 + innerHalf + tile.width * 0.03 }
    /// Between the items further out, stacked close.
    public var pitch: CGFloat { tile.width * 0.17 }
    /// Points of a drag or a swipe for one item.
    public var perTab: CGFloat { tile.width * 0.30 }
    /// How far the eye stands from the row: the perspective.
    public var eye: CGFloat { tile.width * 1.9 }
    /// How far an item turned beside the front reaches toward it, as seen: its inner edge, turned away from you
    /// and so drawn smaller, by the same perspective `GlassCarouselPlacement` draws with.
    public var innerHalf: CGFloat { seenHalf(edgeComingForward: false) }
    /// How far it reaches away from the front: its outer edge, turned toward you and drawn larger.
    public var outerHalf: CGFloat { seenHalf(edgeComingForward: true) }

    private func seenHalf(edgeComingForward: Bool) -> CGFloat {
        let radians = turn * .pi / 180
        let half = tile.width / 2 * scale(1)
        let toward = (edgeComingForward ? 1 : -1) * half * CGFloat(sin(radians)) + depth(1)
        return half * CGFloat(cos(radians)) / (1 - toward / eye)
    }

    private func near(_ d: Double) -> Double { min(abs(d), 1) }

    /// Across: the first item either side opens the gap, the rest follow it closely.
    public func x(_ d: Double) -> CGFloat {
        abs(d) <= 1 ? CGFloat(d) * gap : CGFloat(d.sign == .minus ? -1 : 1) * (gap + CGFloat(abs(d) - 1) * pitch)
    }

    /// Turned to face the middle, as an album view turns them: an item's outer edge comes toward you and its inner
    /// edge goes back (the owner, 2026-11-02, beside Apple's: "should the rear windows be angled like this vs out?";
    /// they had faced out, inner edge forward). Negative on the right, by the transform's own turn.
    public func angle(_ d: Double) -> Double { -max(-1, min(1, d)) * turn }

    public func scale(_ d: Double) -> CGFloat { 1 - 0.08 * CGFloat(near(d)) }

    /// Set back from the front, so the stacks recede.
    public func depth(_ d: Double) -> CGFloat { -CGFloat(near(d)) * tile.width * 0.22 }

    /// Which item a click lands on, `x` points from the middle of the row: the front within its own width; past
    /// it, the nearest item whose uncovered strip is there, as each item covers those further out up to its outer
    /// edge.
    public func tab(at x: CGFloat, front: Int, count: Int) -> Int {
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

    /// The item a swipe or a drag settles on: the nearest whole item, inside the row.
    public static func settled(_ flow: Double, count: Int) -> Int {
        max(0, min(count - 1, Int(flow.rounded())))
    }

    // MARK: Real depth (Vision Pro, D99)

    /// An item's pose in space on Vision Pro: turned about its upright middle, set across, and moved toward the
    /// person, in points. The front stands out of the window, nearest, as an album's front cover is; the rest stand
    /// on the window's plane, each turned about its middle, its outer edge coming toward you without passing the
    /// front and its inner edge going back behind the plane, where visionOS still draws it (seen in the visionOS 27
    /// simulator, 2026-11-03: the turned tiles' inner halves, text and all).
    public struct DepthPose: Equatable {
        public let angle: Double
        public let x: CGFloat
        public let z: CGFloat
        public let scale: CGFloat
    }

    /// How far the front stands out of the window: as far as a turned neighbour's outer edge reaches toward you,
    /// plus a little, so the front is never behind one. Lifted twice that, to keep every inner edge in front of the
    /// plane as well, perspective drew the front over 60% of the window (the simulator, 2026-11-03).
    public var frontLift: CGFloat {
        let half = tile.width / 2 * scale(1)
        return half * CGFloat(sin(turn * .pi / 180)) + tile.width * 0.04
    }

    /// The pose for `d`: the front at `frontLift`, coming down to the window's plane by the first item either side;
    /// further out they stay there, stacked.
    public func depthPose(_ d: Double) -> DepthPose {
        DepthPose(angle: angle(d), x: x(d), z: frontLift * CGFloat(1 - near(d)), scale: scale(d))
    }
}

/// An item's place in the row: across, turned toward the front, set back, in perspective. Animated by `d` itself,
/// so an item moving several places passes through each on the way.
public struct GlassCarouselPlacement: GeometryEffect {
    public var d: Double
    public let geometry: GlassCarouselGeometry

    public init(d: Double, geometry: GlassCarouselGeometry) {
        self.d = d
        self.geometry = geometry
    }

    public var animatableData: Double {
        get { d }
        set { d = newValue }
    }

    public func effectValue(size: CGSize) -> ProjectionTransform {
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

#if os(visionOS)
/// An item's place in the row in real depth (D99): its pose (`GlassCarouselGeometry.depthPose`) as space draws it,
/// turned and moved toward the person rather than projected onto the window. Animated by `d`, as the flat row is.
struct GlassCarouselDepthPlacement: ViewModifier, Animatable {
    var d: Double
    let geometry: GlassCarouselGeometry

    nonisolated var animatableData: Double {
        get { d }
        set { d = newValue }
    }

    func body(content: Content) -> some View {
        let pose = geometry.depthPose(d)
        content
            .scaleEffect(pose.scale)
            // The row's own turn is the Mac's (negative on the right); space turns the other way about y.
            .rotation3DEffect(.degrees(-pose.angle), axis: (x: 0, y: 1, z: 0))
            .offset(x: pose.x)
            .offset(z: pose.z)
    }
}
#endif

/// One item of the row: what it is called and where, for the caption under the row and for VoiceOver.
public struct GlassCarouselItem<ID: Hashable>: Identifiable {
    public let id: ID
    public let title: String
    public let detail: String?
    /// How the detail loses what doesn't fit: `repo · branch · folder` its end, a folder path its start.
    public let detailTruncation: Text.TruncationMode
    /// For UI tests.
    public let identifier: String

    public init(id: ID, title: String, detail: String?, detailTruncation: Text.TruncationMode = .head,
                identifier: String) {
        self.id = id
        self.title = title
        self.detail = detail
        self.detailTruncation = detailTruncation
        self.identifier = identifier
    }
}

/// A scroll over the carousel: along the row, in points; precise from a trackpad or a Magic Mouse.
public struct GlassCarouselScroll {
    public let delta: CGFloat
    public let precise: Bool

    public init(delta: CGFloat, precise: Bool) {
        self.delta = delta
        self.precise = precise
    }
}

/// The carousel: items in a row that flows. The caller draws each tile and its reflection; the row places them,
/// moves with a drag (a finger, a pinch, the mouse), a tap or click, the arrows (through `selection`), and on the
/// Mac a trackpad (`scrollMonitor`). Choosing the item in front opens it (`activate`); one beside it comes forward.
public struct GlassCarouselRow<ID: Hashable, Tile: View, Reflection: View>: View {
    let items: [GlassCarouselItem<ID>]
    @Binding var selection: ID?
    let activate: (ID) -> Void
    let tile: (GlassCarouselItem<ID>, CGSize) -> Tile
    let reflection: (GlassCarouselItem<ID>, CGSize) -> Reflection
    /// The Mac's trackpad and wheel: given the row's handler, a view that hears them.
    let scrollMonitor: ((@escaping (GlassCarouselScroll) -> Void) -> AnyView)?

    /// Where the row stands: the item in front, fractional while it moves.
    @State private var flow: Double = 0
    @State private var dragStart: Double?
    @State private var settling: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(items: [GlassCarouselItem<ID>], selection: Binding<ID?>, activate: @escaping (ID) -> Void,
                scrollMonitor: ((@escaping (GlassCarouselScroll) -> Void) -> AnyView)? = nil,
                @ViewBuilder tile: @escaping (GlassCarouselItem<ID>, CGSize) -> Tile,
                @ViewBuilder reflection: @escaping (GlassCarouselItem<ID>, CGSize) -> Reflection) {
        self.items = items
        _selection = selection
        self.activate = activate
        self.scrollMonitor = scrollMonitor
        self.tile = tile
        self.reflection = reflection
    }

    private var front: Int { GlassCarouselGeometry.settled(flow, count: items.count) }

    /// Below the row: the front's name and where it is.
    public static var captionRoom: CGFloat { 62 }

    private var spring: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.86)
    }

    /// How much of the row's width the front takes: in space a little less, as the front stands out toward you and
    /// is seen larger for it.
    private static var share: CGFloat {
        #if os(visionOS)
        0.4
        #else
        0.46
        #endif
    }

    /// The turn: the Mac's in perspective; in space a little less, as each degree there reaches toward you.
    private var turn: Double {
        guard !reduceMotion else { return 0 }
        #if os(visionOS)
        return 50
        #else
        return 64
        #endif
    }

    public var body: some View {
        GeometryReader { proxy in
            let band = CGSize(width: proxy.size.width, height: max(proxy.size.height - Self.captionRoom, 1))
            let geometry = GlassCarouselGeometry(in: band, turn: turn, share: Self.share)
            ZStack {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let d = Double(index) - flow
                    if abs(d) <= Double(GlassCarouselGeometry.reach) + 1 {
                        placed(entry(item, d: d, geometry: geometry), d: d, geometry: geometry)
                            .zIndex(-abs(d))
                            #if os(visionOS)
                            // In space the eyes say which item is meant: each takes its own pinch.
                            .onTapGesture { choose(index) }
                            #endif
                    }
                }
            }
            .frame(width: proxy.size.width, height: geometry.tile.height)
            .position(x: proxy.size.width / 2, y: geometry.rowCenter(inBand: band.height))
            .overlay(alignment: .bottom) { caption }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(.rect)
            .gesture(drag(geometry))
            #if !os(visionOS)
            .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                choose(geometry.tab(at: tap.location.x - proxy.size.width / 2, front: front, count: items.count))
            })
            #endif
            .background {
                if let scrollMonitor {
                    scrollMonitor { scroll in moveRow(by: scroll, geometry: geometry) }
                }
            }
        }
        .onAppear { flow = Double(index(of: selection) ?? 0) }
        // Typing narrows the row: where it stands is the selection's place in what is left.
        .onChange(of: items.map(\.id)) { _, _ in
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { flow = Double(index(of: selection) ?? 0) }
        }
        // The arrows, new output, a tap on an item beside the front: the row flows to it.
        .onChange(of: selection) { _, selection in
            guard let index = index(of: selection), index != front else { return }
            withAnimation(spring) { flow = Double(index) }
        }
        .onChange(of: front) { _, front in
            guard items.indices.contains(front), selection != items[front].id else { return }
            selection = items[front].id
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Carousel")
        .accessibilityValue(items.indices.contains(front) ? items[front].title : "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(1)
            case .decrement: step(-1)
            @unknown default: break
            }
        }
    }

    @ViewBuilder
    private func placed<V: View>(_ view: V, d: Double, geometry: GlassCarouselGeometry) -> some View {
        #if os(visionOS)
        view.modifier(GlassCarouselDepthPlacement(d: d, geometry: geometry))
        #else
        view.modifier(GlassCarouselPlacement(d: d, geometry: geometry))
        #endif
    }

    /// An item: its tile, and below it its reflection on the floor, fading.
    private func entry(_ item: GlassCarouselItem<ID>, d: Double, geometry: GlassCarouselGeometry) -> some View {
        tile(item, geometry.tile)
            .frame(width: geometry.tile.width, height: geometry.tile.height)
            .overlay(alignment: .bottom) {
                if abs(d) <= 4 {
                    reflection(item, geometry.tile)
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
            .accessibilityLabel(item.title)
            .accessibilityValue(item.detail ?? "")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(item.identifier)
    }

    /// The item in front's name and where it is, under the row, as an album's title was.
    @ViewBuilder
    private var caption: some View {
        if items.indices.contains(front) {
            let item = items[front]
            VStack(spacing: 3) {
                Text(item.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                if let detail = item.detail {
                    Text(detail)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(item.detailTruncation)
                }
            }
            .frame(maxWidth: 520)
            .padding(.bottom, 6)
            .id(item.id)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.18), value: item.id)
            .allowsHitTesting(false)
        }
    }

    private func index(of id: ID?) -> Int? {
        id.flatMap { id in items.firstIndex { $0.id == id } }
    }

    private func step(_ by: Int) {
        guard !items.isEmpty else { return }
        selection = items[max(0, min(items.count - 1, front + by))].id
    }

    /// The front opens; one beside it comes to the front.
    private func choose(_ index: Int) {
        guard items.indices.contains(index) else { return }
        if index == front, Double(index) == flow {
            activate(items[index].id)
        } else {
            selection = items[index].id
            withAnimation(spring) { flow = Double(index) }
        }
    }

    /// Dragged: the row follows the finger, the pinch or the pointer, then settles where it was flung.
    private func drag(_ geometry: GlassCarouselGeometry) -> some Gesture {
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
                let target = GlassCarouselGeometry.settled(flung, count: items.count)
                withAnimation(spring) { flow = Double(target) }
            }
    }

    /// A swipe on a trackpad moves the row with the fingers, momentum and all, and settles when it stops; a
    /// mouse's wheel steps an item a notch.
    private func moveRow(by scroll: GlassCarouselScroll, geometry: GlassCarouselGeometry) {
        guard !items.isEmpty else { return }
        settling?.cancel()
        if scroll.precise {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { flow = rubberBanded(flow - Double(scroll.delta / geometry.perTab)) }
            settling = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return }
                withAnimation(spring) { flow = Double(GlassCarouselGeometry.settled(flow, count: items.count)) }
            }
        } else if scroll.delta != 0 {
            step(scroll.delta > 0 ? -1 : 1)
        }
    }

    /// Past either end the row gives a little, then springs back.
    private func rubberBanded(_ value: Double) -> Double {
        let last = Double(max(items.count - 1, 0))
        if value < 0 { return -0.35 * (1 - 1 / (1 - value)) }
        if value > last { return last + 0.35 * (1 - 1 / (1 + value - last)) }
        return value
    }
}
