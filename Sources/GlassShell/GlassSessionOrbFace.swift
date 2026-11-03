//
//  GlassSessionOrbFace.swift
//  Glass Power Tools — GlassShell
//
//  What a session window shows as its orb, and the button that makes it one: shared by Vision Pro,
//  where a window shrinks into its orb where it is or into the dock (D74, D88), and the Mac, where a
//  window goes into the dock (D95). Each platform draws the orb itself (`GlassSessionOrb.swift`,
//  `GlassMacOrbDock.swift`); what it shows, the sphere's light and pulse, and the dock's rows are the
//  same.
//

#if os(visionOS) || os(macOS)
import SwiftUI
import GlassConnectionKit

/// The orb's sizes on each platform: a point on the headset is larger than one on a Mac's screen.
enum GlassOrbMetrics {
    #if os(visionOS)
    static let orbDiameter: CGFloat = 112
    /// A dot's symbol, or its icon's side.
    static let iconSize: CGFloat = 24
    /// How far the orb stands above its cell's middle, leaving room for its name below.
    static let orbRaise: CGFloat = 14
    /// How far an orb falls as it lands in the dock.
    static let fall: CGFloat = 70
    static let shrinkHelp = "Shrink this window to an orb. Pinch the orb to bring it back."
    #else
    static let orbDiameter: CGFloat = 56
    static let iconSize: CGFloat = 14
    /// None: the Mac names an orb above the dock, so it stands on its cell's middle (D95).
    static let orbRaise: CGFloat = 0
    static let fall: CGFloat = 36
    static let shrinkHelp = "Put this window in the orb dock. Click its orb to bring it back."
    #endif
    /// Tabs on one ring, past which the rest are left off.
    static let maximumTabs = 12
}

/// A tab of a window shown as its orb: a dot on the ring around it (the owner, 2026-10-15: "redraw
/// the tabs around the orb evenly distributed with a preview in the orb on hover").
public struct GlassSessionOrbTab: Identifiable {
    public let id: String
    public var title: String
    public var symbolName: String
    /// The dot's glyph colour: the tab's state, as its tab label shows it.
    public var tint: Color
    /// What the dot shows in place of `symbolName`, drawn by the session's own kind: a terminal's
    /// coding agent in its colour, pulsing while it works, as its tab in the sidebar shows it
    /// (2026-10-21).
    public var icon: AnyView?
    public var picture: @MainActor () -> Image?
    /// Brings the tab to the front, as the window grows back on it.
    public var select: @MainActor () -> Void
    /// A pinch grows the window back as well as selecting: a tab. A machine's service on the ring
    /// (D88) comes forward on its own and leaves the orb as it is.
    public var growsWindow: Bool

    /// The side an `icon` is drawn at, in its dot.
    public static var iconSize: CGFloat { GlassOrbMetrics.iconSize }

    public init(id: String, title: String, symbolName: String, tint: Color, icon: AnyView? = nil,
                growsWindow: Bool = true,
                picture: @escaping @MainActor () -> Image?, select: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.tint = tint
        self.icon = icon
        self.growsWindow = growsWindow
        self.picture = picture
        self.select = select
    }
}

/// A machine's other services on an orb's ring (D88; the owner, 2026-10-25: "add Editor, Database,
/// and Desktop to the orb so it's more of a machine nav than just tabs for a Terminal window").
/// Set by the composition root, which knows the library; nil where nothing can supply them.
@MainActor
public enum GlassSessionOrbServices {
    /// The services of the machine `endpointIDs` are on, other than `own` kind, then what was opened
    /// from the window `from` (an editor, from a terminal's folder button), as dots.
    public static var dots: ((_ endpointIDs: [EndpointID], _ own: HostServiceKind?, _ from: String?) -> [GlassSessionOrbTab])?

    static func dots(for face: GlassSessionOrbFace) -> [GlassSessionOrbTab] {
        guard !face.endpointIDs.isEmpty || face.dockID != nil else { return [] }
        return dots?(face.endpointIDs, face.kind, face.dockID) ?? []
    }
}

/// What a session window shows as its orb.
public struct GlassSessionOrbFace {
    /// The window's name, shown beneath the orb while it is looked at.
    public var title: String
    /// The kind's symbol, where there is no picture.
    public var symbolName: String
    /// The session's picture now, taken again every second while the orb is on screen.
    public var picture: @MainActor () -> Image?
    /// Pulsing: activity in the session, where the window's Auto-focus on activity is on.
    public var pulses: Bool
    /// The window's tabs, on a ring around the orb when there are two or more.
    public var tabs: [GlassSessionOrbTab]
    /// Whether the window's bar shows Shrink to Orb. A terminal window with a view menu offers the
    /// orb there instead (the owner, 2026-10-15: "is the orb view just one more option for the view
    /// menu in terminal mode?").
    public var showsButton: Bool
    /// A single tab is on the ring too: a machine's orb in the dock, whose one editor is not the
    /// orb itself, as a window's one tab is.
    public var showsSingleTab: Bool
    /// The window's open session (`GlassOpenSession.id`), by which it waits in the dock (D88); nil
    /// for a window that shrinks where it is whatever the setting says.
    public var dockID: String?
    /// The machines the window's sessions are on, whose other services join the ring (D88).
    public var endpointIDs: [EndpointID]
    /// The window's own kind of service, left off the ring: its tabs are already there.
    public var kind: HostServiceKind?
    /// What the window paints behind its picture, for a picture that has none of its own: a Mac
    /// terminal's is its text alone, which its window draws over its theme (D95). Nil where the
    /// picture stands on its own.
    public var backdrop: Color?

    public init(title: String, symbolName: String, pulses: Bool = false, tabs: [GlassSessionOrbTab] = [],
                showsButton: Bool = true, showsSingleTab: Bool = false, dockID: String? = nil,
                endpointIDs: [EndpointID] = [], kind: HostServiceKind? = nil, backdrop: Color? = nil,
                picture: @escaping @MainActor () -> Image?) {
        self.backdrop = backdrop
        self.title = title
        self.symbolName = symbolName
        self.pulses = pulses
        self.tabs = tabs
        self.showsButton = showsButton
        self.showsSingleTab = showsSingleTab
        self.dockID = dockID
        self.endpointIDs = endpointIDs
        self.kind = kind
        self.picture = picture
    }

    /// A ring when there are tabs to put on one: as many as fit around the orb, in order.
    var ringTabs: [GlassSessionOrbTab] {
        tabs.count >= (showsSingleTab ? 1 : 2) ? Array(tabs.prefix(GlassOrbMetrics.maximumTabs)) : []
    }

    /// The ring with the machine's services after the tabs, as many as fit. Asked only while the
    /// orb is drawn: it reads every open session, and a window's own body must not (every window
    /// would draw again whenever any session changed).
    func ring(services: [GlassSessionOrbTab]) -> [GlassSessionOrbTab] {
        Array((ringTabs + services).prefix(GlassOrbMetrics.maximumTabs))
    }
}

/// The window's orb as its bar sees it: how to become one, and whether it is one.
public struct GlassSessionOrbControl {
    public let shrink: @MainActor () -> Void
    public let isOrb: Bool
    /// The window at its own size: not its orb, and not still growing back from one. What holds a
    /// window to a shape (a desktop's, W38) waits for this before holding it again.
    public let isWindow: Bool
}

public extension EnvironmentValues {
    /// Set by `glassSessionOrb` for everything in the window; nil in a window that has no orb.
    @Entry var glassSessionOrb: GlassSessionOrbControl? = nil
}

/// "Shrink to Orb": first in a session window's bottom bar on Vision Pro, beside Show All Windows in its
/// toolbar on the Mac (D95); nothing in a window without an orb.
public struct GlassSessionOrbButton: View {
    /// The orb's glyph wherever a window becomes one: this button, and the Orb in a Vision Pro terminal's
    /// view menu (the owner, 2026-11-02: "Take a look at the vision pro 'circle' icon (puts the window
    /// in the dock). That should be the standard here, not the two arrows."). The two arrows are
    /// Active's Take Over.
    public static let symbolName = "circle.circle"

    @Environment(\.glassSessionOrb) private var orb

    public init() {}

    public var body: some View {
        if let orb, !orb.isOrb {
            Button("Shrink to Orb", systemImage: Self.symbolName) { orb.shrink() }
                .help(GlassOrbMetrics.shrinkHelp)
                .accessibilityIdentifier("session-orb-shrink")
        }
    }
}

/// A sphere's light on the orb's face: brighter toward the upper left, falling away to the rim, with
/// a small highlight and a rim catching the light, over the picture seen through the glass.
struct GlassOrbSphereShading: View {
    let diameter: CGFloat

    var body: some View {
        ZStack {
            RadialGradient(colors: [.white.opacity(0.32), .white.opacity(0)],
                           center: UnitPoint(x: 0.32, y: 0.26), startRadius: 0, endRadius: diameter * 0.55)
            RadialGradient(colors: [.clear, .clear, .black.opacity(0.38)],
                           center: .center, startRadius: 0, endRadius: diameter * 0.52)
            Ellipse()
                .fill(.white.opacity(0.55))
                .frame(width: diameter * 0.26, height: diameter * 0.14)
                .rotationEffect(.degrees(-30))
                .blur(radius: 5)
                .offset(x: -diameter * 0.18, y: -diameter * 0.24)
            Circle()
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.08), .white.opacity(0.3)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
        }
        .frame(width: diameter, height: diameter)
        // Cut to the sphere here: the orb's own clip did not hold its corners in on the headset (the
        // gradients' square showed around the orb in the visionOS 27.2 simulator).
        .compositingGroup()
        .clipShape(.circle)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}


/// A ring going out from the orb's rim, again and again, while its session is busy.
struct GlassSessionOrbPulse: View {
    var body: some View {
        Circle()
            .strokeBorder(.white.opacity(0.75), lineWidth: 3)
            .phaseAnimator([0.0, 1.0]) { ring, phase in
                ring.scaleEffect(1 + 0.22 * phase).opacity(1 - phase)
            } animation: { phase in
                phase == 1 ? .easeOut(duration: 1.3) : .linear(duration: 0)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: The dock's rows

/// Where the dock is scrolled to: its offset, the height it shows, and its content's height.
struct GlassOrbDockRoom: Equatable {
    var offset: CGFloat = 0
    var shown: CGFloat = 0
    var content: CGFloat = 0

    /// What lies above what is shown, and below it.
    var above: CGFloat { offset }
    var below: CGFloat { content - offset - shown }
}

/// The orbs in rows that wrap, as `GlassOrbFlow` lays them out.
struct GlassOrbFlowLayout: Layout {
    var gapAfterFirst: CGFloat
    /// The rows are laid out at least this wide, past what is shown, which then shows what fits: a Mac dock growing to
    /// a width it has been given (`GlassMacOrbDockView`). Laid out at each width along the way, its orbs wrapped into
    /// a column while it grew, Connections standing in the middle and the next orb out of sight below (the VM,
    /// 2026-11-02, filmed at 60 fps).
    var widthAtLeast: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let used = GlassOrbFlow.size(of: frames(subviews, width: max(width, widthAtLeast)))
        return CGSize(width: width.isFinite ? width : used.width, height: used.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(subviews, width: max(bounds.width, widthAtLeast))) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
        GlassOrbFlow.frames(of: subviews.map { $0.sizeThatFits(.unspecified) }, width: width, gapAfterFirst: gapAfterFirst)
    }
}
#endif
