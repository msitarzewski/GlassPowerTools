//
//  GlassSessionOrb.swift
//  Glass Power Tools — GlassShell
//
//  A session window shrunk into an orb, on Vision Pro (the owner, 2026-10-15: "I'd also like a
//  persistent system level session/service icon that shrinks a window into a small preview. When
//  activity is enabled, the preview/orb should pulse"). His choices: an orb whose face is a tiny
//  live picture of the session ("with a live view of the activity"); the pulse switched by the
//  window's Auto-focus on activity; the control first in the bottom bar; every kind of session
//  window — terminal, desktop, database, editor.
//
//  As the Connections window becomes its own orb (W39, `glassConnectionsIdleShrink`): no second
//  window. The session window keeps its content, out of sight and out of reach, laid out at the
//  size it had, and asks visionOS for the orb's size; a pinch on the orb grows it back. Its
//  ornaments go with it.
//

#if os(visionOS)
import SwiftUI
import UIKit
import GlassConnectionUI

/// A tab of a window shown as its orb: a dot on the ring around it (the owner, 2026-10-15: "redraw
/// the tabs around the orb evenly distributed with a preview in the orb on hover").
public struct GlassSessionOrbTab: Identifiable {
    public let id: String
    public var title: String
    public var symbolName: String
    /// The dot's glyph colour: the tab's state, as its tab label shows it.
    public var tint: Color
    public var picture: @MainActor () -> Image?
    /// Brings the tab to the front, as the window grows back on it.
    public var select: @MainActor () -> Void

    public init(id: String, title: String, symbolName: String, tint: Color,
                picture: @escaping @MainActor () -> Image?, select: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.tint = tint
        self.picture = picture
        self.select = select
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

    public init(title: String, symbolName: String, pulses: Bool = false, tabs: [GlassSessionOrbTab] = [],
                showsButton: Bool = true, picture: @escaping @MainActor () -> Image?) {
        self.title = title
        self.symbolName = symbolName
        self.pulses = pulses
        self.tabs = tabs
        self.showsButton = showsButton
        self.picture = picture
    }

    /// A ring when there are tabs to put on one: as many as fit around the orb, in order.
    var ringTabs: [GlassSessionOrbTab] { tabs.count >= 2 ? Array(tabs.prefix(GlassOrbRingLayout.maximumTabs)) : [] }
}

/// The window's size as its orb: the Connections orb's alone, larger with a ring of tabs, whose names
/// need room beyond it.
enum GlassSessionOrbSize {
    static func window(ringed: Bool) -> CGSize {
        ringed ? CGSize(width: 560, height: 380) : GlassConnectionsWindowSize.orb
    }
}

public extension View {
    /// Leaves this out while the window is its orb: the terminal's tab ornament, whose tabs the orb's
    /// ring shows instead.
    func glassHiddenWhileOrb() -> some View {
        modifier(GlassHiddenWhileOrb())
    }
}

private struct GlassHiddenWhileOrb: ViewModifier {
    @Environment(\.glassSessionOrb) private var orb

    func body(content: Content) -> some View {
        if orb?.isOrb != true { content }
    }
}

/// The window's orb as its bar sees it: how to become one, and whether it is one.
public struct GlassSessionOrbControl {
    public let shrink: @MainActor () -> Void
    public let isOrb: Bool
}

public extension EnvironmentValues {
    /// Set by `glassSessionOrb` for everything in the window; nil in a window that has no orb.
    @Entry var glassSessionOrb: GlassSessionOrbControl? = nil
}

public extension View {
    /// Lets this session window become its orb. Attach to the window's whole content: what it wraps
    /// is what goes out of sight while the window is its orb. The window's bar shows
    /// `GlassSessionOrbButton` first.
    func glassSessionOrb(_ face: GlassSessionOrbFace) -> some View {
        modifier(GlassSessionOrbModifier(face: face))
    }
}

/// "Shrink to Orb", first in a session window's bottom bar; nothing in a window without an orb.
public struct GlassSessionOrbButton: View {
    @Environment(\.glassSessionOrb) private var orb

    public init() {}

    public var body: some View {
        if let orb, !orb.isOrb {
            Button("Shrink to Orb", systemImage: "arrow.down.right.and.arrow.up.left") { orb.shrink() }
                .help("Shrink this window to an orb. Pinch the orb to bring it back.")
                .accessibilityIdentifier("session-orb-shrink")
        }
    }
}

private struct GlassSessionOrbModifier: ViewModifier {
    let face: GlassSessionOrbFace
    /// The window's size while it is its orb, to grow back to; nil while it is the window.
    @State private var keptSize: CGSize?
    @State private var sizer = GlassWindowSizer()

    func body(content: Content) -> some View {
        let isOrb = keptSize != nil
        let orbSize = GlassSessionOrbSize.window(ringed: !face.ringTabs.isEmpty)
        GlassConnectionsWindowLayout(library: keptSize, orb: orbSize, orbContent: orbSize) {
            content
                // First in the window's bottom bar, in every kind of session window.
                .toolbar {
                    if face.showsButton {
                        ToolbarItem(placement: .bottomOrnament) { GlassSessionOrbButton() }
                    }
                }
                .environment(\.glassSessionOrb, GlassSessionOrbControl(shrink: shrink, isOrb: isOrb))
                .environment(\.glassWindowOutOfSight, isOrb)
                // Its ornaments go with it, as the library's do (`VisionTabOutOfSight`).
                .toolbarVisibility(isOrb ? .hidden : .automatic, for: .bottomOrnament, .tabBar)
                .animation(.easeInOut(duration: 0.2)) { $0.opacity(isOrb ? 0 : 1) }
                .allowsHitTesting(!isOrb)
                .accessibilityHidden(isOrb)
            if isOrb {
                GlassSessionOrbView(face: face, grow: grow)
            }
        }
        .background { GlassWindowSizerView(sizer: sizer).accessibilityHidden(true) }
        #if DEBUG
        // Screenshots only: `--demo-session-orb` in a `--ui-testing` run shrinks the window into its
        // orb a few seconds after it opens, so the orb can be captured from outside (rule 11).
        .task {
            guard GlassSessionOrbDemo.shrinksOnOpen else { return }
            try? await Task.sleep(for: .seconds(4))
            shrink()
        }
        #endif
    }

    private func shrink() {
        guard keptSize == nil else { return }
        keptSize = GlassConnectionsWindowSize.returning(to: sizer.windowSize)
        sizer.resize(to: GlassSessionOrbSize.window(ringed: !face.ringTabs.isEmpty), event: "session-orb", freeform: true)
    }

    private func grow() {
        guard let size = keptSize else { return }
        keptSize = nil
        sizer.resize(to: size, event: "session-window")
    }
}

#if DEBUG
enum GlassSessionOrbDemo {
    static var shrinksOnOpen: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--ui-testing") && arguments.contains("--demo-session-orb")
    }

    /// `--demo-orb-names`: every name drawn as it is for a look, to check where each sits — the
    /// simulator cannot be looked at.
    static var showsNames: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--ui-testing") && arguments.contains("--demo-orb-names")
    }
}
#endif

/// The orb: the session's live picture inside a glass sphere, pulsing while its session is busy and
/// the window asked for it; growing a little when looked at or pinched (the owner, 2026-10-15: "Make
/// the orb shaped more like an orb, and have it grow slightly when interacted with"). With two or
/// more tabs, they sit evenly on a ring around it; looking at one shows its picture in the orb and its
/// name beyond it, never over the orb ("it should grow away from the orb"), and a pinch on one grows
/// the window back on that tab.
private struct GlassSessionOrbView: View {
    let face: GlassSessionOrbFace
    let grow: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var looks

    /// What looking at the orb, or at a tab's dot, shows. Only the orb and the dots set their group
    /// going; what they show follows (`.followsGroup`). Left to the default, every tab's picture —
    /// each inside the orb — set its own group going when the orb was looked at, and every tab's name
    /// showed at once (the owner, on the headset: "all of them at once is a lot").
    private var orbLook: HoverEffectGroup { HoverEffectGroup(id: "orb", in: looks) }
    private func look(_ tab: GlassSessionOrbTab) -> HoverEffectGroup { HoverEffectGroup(id: "tab-" + tab.id, in: looks) }
    private var shownByOrb: HoverEffectGroup { orbLook.behavior(.followsGroup) }

    /// Nil, so a look alone shows a name — except in the screenshots' demo.
    private static var namesOverride: HoverEffectPhaseOverride? {
        #if DEBUG
        GlassSessionOrbDemo.showsNames ? .active : nil
        #else
        nil
        #endif
    }
    private func shown(by tab: GlassSessionOrbTab) -> HoverEffectGroup { look(tab).behavior(.followsGroup) }

    var body: some View {
        let tabs = face.ringTabs
        GlassOrbRingLayout(count: tabs.count) {
            orb(tabs)
            ForEach(tabs) { tab in dot(tab) }
            // A name is somewhere to look as well as something shown: looked at, it keeps its group
            // going, so it stays while it is read. It vanished as the eyes moved to it from its dot
            // (the owner, on the headset: "The labels disappear when you try to read them because
            // the dot lose focus"). A pinch on it does what a pinch on its dot does.
            ForEach(tabs) { tab in
                Button {
                    tab.select()
                    grow()
                } label: {
                    GlassOrbName(title: tab.title)
                        .hoverEffect(GlassOrbRevealEffect().hoverEffectPhaseOverride(Self.namesOverride), in: shown(by: tab))
                }
                .buttonStyle(GlassSessionOrbPressStyle())
                .contentShape(.hoverEffect, .capsule)
                .hoverEffectGroup(look(tab))
                .accessibilityHidden(true)
            }
            Button(action: grow) {
                GlassOrbName(title: face.title, prominent: true)
                    .hoverEffect(GlassOrbRevealEffect(), in: shownByOrb)
            }
            .buttonStyle(GlassSessionOrbPressStyle())
            .contentShape(.hoverEffect, .capsule)
            .hoverEffectGroup(orbLook)
            .accessibilityHidden(true)
        }
    }

    private func orb(_ tabs: [GlassSessionOrbTab]) -> some View {
        Button(action: grow) {
            TimelineView(.animation(minimumInterval: 1, paused: scenePhase != .active)) { _ in
                ZStack {
                    picture(face.picture(), symbolName: face.symbolName)
                        .clipShape(.circle)
                    // A tab's own picture, shown while its dot is looked at: the system shows it,
                    // as it is never told where a person looks. Each cut to the circle before its
                    // effect: drawn by the system on its own, it is not inside the orb's clip.
                    ForEach(tabs) { tab in
                        picture(tab.picture(), symbolName: tab.symbolName)
                            .clipShape(.circle)
                            .hoverEffect(GlassOrbRevealEffect(), in: shown(by: tab))
                    }
                }
            }
            .frame(width: GlassConnectionsOrb.diameter, height: GlassConnectionsOrb.diameter)
            .overlay { GlassOrbSphereShading(diameter: GlassConnectionsOrb.diameter) }
            .clipShape(.circle)
            .glassBackgroundEffect(in: .circle)
            .overlay { if face.pulses { GlassSessionOrbPulse() } }
            .contentShape(.hoverEffect, .circle)
            .hoverEffect(.highlight)
            .hoverEffect(GlassOrbGrowEffect())
        }
        .buttonStyle(GlassSessionOrbPressStyle())
        .hoverEffectGroup(orbLook)
        .accessibilityActivationPoint(.center)
        .accessibilityLabel(face.title)
        .accessibilityHint("Brings the window back")
        .accessibilityIdentifier("session-orb")
    }

    private func dot(_ tab: GlassSessionOrbTab) -> some View {
        Button {
            tab.select()
            grow()
        } label: {
            Image(systemName: tab.symbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tab.tint)
                .frame(width: GlassOrbRingLayout.dotDiameter, height: GlassOrbRingLayout.dotDiameter)
                .glassBackgroundEffect(in: .circle)
                .contentShape(.hoverEffect, .circle)
                .hoverEffect(.highlight)
                .hoverEffect(GlassOrbGrowEffect())
        }
        .buttonStyle(GlassSessionOrbPressStyle())
        .hoverEffectGroup(look(tab))
        .accessibilityLabel("Open \(tab.title)")
        .accessibilityIdentifier("session-orb-tab-\(tab.id)")
    }

    @ViewBuilder
    private func picture(_ image: Image?, symbolName: String) -> some View {
        if let image {
            image.resizable().aspectRatio(contentMode: .fill)
                .frame(width: GlassConnectionsOrb.diameter, height: GlassConnectionsOrb.diameter)
        } else {
            Image(systemName: symbolName)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .frame(width: GlassConnectionsOrb.diameter, height: GlassConnectionsOrb.diameter)
        }
    }
}

/// A sphere's light on the orb's face: brighter toward the upper left, falling away to the rim, with
/// a small highlight and a rim catching the light, over the picture seen through the glass.
private struct GlassOrbSphereShading: View {
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

/// A name on glass, shown while what it names is looked at.
private struct GlassOrbName: View {
    let title: String
    var prominent = false

    var body: some View {
        Text(title)
            .font(prominent ? .callout.weight(.medium) : .footnote.weight(.medium))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, prominent ? 14 : 10)
            .padding(.vertical, prominent ? 7 : 5)
            .glassBackgroundEffect(in: .capsule)
            .fixedSize()
            .frame(maxWidth: GlassOrbRingLayout.nameWidth)
            .contentShape(.capsule)
            .accessibilityHidden(true)
    }
}

/// Pinched, the orb and a tab's dot grow a little, as they do when looked at.
private struct GlassSessionOrbPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.06 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// The orb in the middle; its tabs' dots evenly around it from the top; each tab's name beyond its
/// dot, anchored on the side toward the orb so it grows away from it; the orb's own name below it,
/// or below the ring.
struct GlassOrbRingLayout: Layout {
    let count: Int
    static let maximumTabs = 12
    static let dotDiameter: CGFloat = 30
    /// Between the orb's rim and a dot's (the owner: "move the dots away from the orb a few more pixels").
    static let gap: CGFloat = 22
    static let nameWidth: CGFloat = 150
    static var ringRadius: CGFloat { GlassConnectionsOrb.diameter / 2 + gap + dotDiameter / 2 }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: GlassSessionOrbSize.window(ringed: count > 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let radius = Self.ringRadius
        let outer = count > 0 ? radius + Self.dotDiameter / 2 : GlassConnectionsOrb.diameter / 2
        // Room below for the orb's name: the whole group sits a little high.
        let center = CGPoint(x: bounds.midX, y: bounds.midY - 14)
        subviews[0].place(at: center, anchor: .center, proposal: .unspecified)
        for index in 0..<count {
            let angle = -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(count)
            let (dx, dy) = (CGFloat(cos(angle)), CGFloat(sin(angle)))
            subviews[1 + index].place(at: CGPoint(x: center.x + radius * dx, y: center.y + radius * dy),
                                      anchor: .center,
                                      proposal: ProposedViewSize(width: Self.dotDiameter, height: Self.dotDiameter))
            // The name beside its own dot, growing away from the orb: on either side, level with
            // the dot and leading away from it; at the top and bottom, centred above or below it.
            // It was anchored by the angle's fraction of its own size, which drew a long name
            // well off its dot (the owner: "the titles are aligned incorrectly to the dots").
            let dot = CGPoint(x: center.x + radius * dx, y: center.y + radius * dy)
            let clearance = Self.dotDiameter / 2 + 8
            let point: CGPoint
            let anchor: UnitPoint
            if abs(dx) >= 0.35 {
                point = CGPoint(x: dot.x + (dx > 0 ? clearance : -clearance), y: dot.y)
                anchor = dx > 0 ? .leading : .trailing
            } else {
                point = CGPoint(x: dot.x, y: dot.y + (dy > 0 ? clearance : -clearance))
                anchor = dy > 0 ? .top : .bottom
            }
            subviews[1 + count + index].place(at: point, anchor: anchor,
                                              proposal: ProposedViewSize(width: Self.nameWidth, height: nil))
        }
        subviews[subviews.count - 1].place(at: CGPoint(x: center.x, y: center.y + outer + 10), anchor: .top,
                                           proposal: ProposedViewSize(width: Self.nameWidth + 40, height: nil))
    }
}

/// A ring going out from the orb's rim, again and again, while its session is busy.
private struct GlassSessionOrbPulse: View {
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
#endif
