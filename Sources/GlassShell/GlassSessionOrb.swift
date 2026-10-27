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
import GlassConnectionKit
import GlassConnectionUI
import GlassLayers

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
    public static var iconSize: CGFloat { GlassOrbRingLayout.iconSize }

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

    public init(title: String, symbolName: String, pulses: Bool = false, tabs: [GlassSessionOrbTab] = [],
                showsButton: Bool = true, showsSingleTab: Bool = false, dockID: String? = nil,
                endpointIDs: [EndpointID] = [], kind: HostServiceKind? = nil,
                picture: @escaping @MainActor () -> Image?) {
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
        tabs.count >= (showsSingleTab ? 1 : 2) ? Array(tabs.prefix(GlassOrbRingLayout.maximumTabs)) : []
    }

    /// The ring with the machine's services after the tabs, as many as fit. Asked only while the
    /// orb is drawn: it reads every open session, and a window's own body must not (every window
    /// would draw again whenever any session changed).
    func ring(services: [GlassSessionOrbTab]) -> [GlassSessionOrbTab] {
        Array((ringTabs + services).prefix(GlassOrbRingLayout.maximumTabs))
    }
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
    /// The window at its own size: not its orb, and not still growing back from one. What holds a
    /// window to a shape (a desktop's, W38) waits for this before holding it again.
    public let isWindow: Bool
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
    /// Growing back from the orb, until visionOS has had a moment to give the window its size.
    @State private var growing = false
    /// The window as it looked as it shrank, for a window with no picture of its own (a database,
    /// a document): out of sight it cannot draw itself again.
    @State private var lastLook: Image?
    @State private var sizer = GlassWindowSizer()
    /// The orb has a ring: tabs, or the machine's services. Settled as the window shrinks, the
    /// services being read only then.
    @State private var ringed = false
    /// Gathering into a drop on the way to the dock (the owner, 2026-10-25: "a liquid 'Water
    /// drop' effect when they go to the dock").
    @State private var departing = false
    @AppStorage(GlassOrbDock.settingKey, store: GlassUITestRun.settingsDefaults) private var inDock = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    func body(content: Content) -> some View {
        let isOrb = keptSize != nil
        let orbSize = GlassSessionOrbSize.window(ringed: ringed)
        GlassConnectionsWindowLayout(library: keptSize, orb: orbSize, orbContent: orbSize) {
            content
                // First in the window's bottom bar, in every kind of session window.
                .toolbar {
                    if face.showsButton {
                        ToolbarItem(placement: .bottomOrnament) { GlassSessionOrbButton() }
                    }
                }
                .environment(\.glassSessionOrb, GlassSessionOrbControl(shrink: shrink, isOrb: isOrb,
                                                                       isWindow: !isOrb && !growing))
                .environment(\.glassWindowOutOfSight, isOrb || departing)
                // Its ornaments go with it, as the library's do (`VisionTabOutOfSight`).
                .toolbarVisibility(isOrb || departing ? .hidden : .automatic, for: .bottomOrnament, .tabBar)
                .animation(.easeInOut(duration: 0.2)) { $0.opacity(isOrb ? 0 : 1) }
                .modifier(GlassOrbDropDeparture(departing: departing))
                .allowsHitTesting(!isOrb && !departing)
                .accessibilityHidden(isOrb)
            if isOrb {
                GlassSessionOrbView(face: faceWithLook, grow: grow)
            }
        }
        .background { GlassWindowSizerView(sizer: sizer).accessibilityHidden(true) }
        // Back from the dock, by its orb or any other way (Active, All Windows, the library): out
        // of the dock, at the size it had there. Reopened by a launch as its orb, as it was left:
        // its orb at once. Otherwise open, as it appears.
        .task(id: face.dockID) {
            guard let id = face.dockID else { return }
            let orbs = GlassOrbDockModel.shared
            if let size = orbs.windowAppeared(id) {
                sizer.resize(to: size, event: "session-from-dock")
                return
            }
            let reopened = orbs.takeOpeningAsOrb(id)
            if reopened.opens {
                standAsOrb(growingBackTo: reopened.size)
            } else if keptSize == nil {
                orbs.noLongerStands(id)
            }
        }
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

    /// The face, with the window's last look where the session has no picture of its own.
    private var faceWithLook: GlassSessionOrbFace {
        var withLook = face
        let own = face.picture, look = lastLook
        withLook.picture = { own() ?? look }
        return withLook
    }

    private func shrink() {
        guard keptSize == nil else { return }
        // Into the dock (D88): visionOS carries no window anywhere, so the window closes into its
        // orb there, its sessions kept, and comes back above the dock at this size.
        // Only a window whose session the app lists: the dock draws an orb from that, and a window
        // closed with nothing to draw would be out of reach (the demo desktop's, on throwaway
        // storage, is not listed).
        if inDock, let id = face.dockID, GlassShowAllWindows.openSessions?().contains(where: { $0.id == id }) == true {
            guard !departing else { return }
            let size = sizer.windowSize
            departing = true
            // The drop lands in the dock as the window finishes gathering into it, then the window
            // goes.
            Task { @MainActor in
                try? await Task.sleep(for: GlassOrbDrop.landing)
                GlassOrbDockModel.shared.dock(id, size: size)
                GlassOrbDockView.logger.info("docking \(id, privacy: .public)")
                GlassOrbDockModel.shared.open(with: openWindow)
                try? await Task.sleep(for: GlassOrbDrop.departure - GlassOrbDrop.landing)
                dismissWindow()
            }
            return
        }
        standAsOrb()
    }

    /// The window becomes its orb where it is, growing back to `size`, or to its size now; kept for
    /// the next launch, which reopens it as its orb.
    private func standAsOrb(growingBackTo size: CGSize? = nil) {
        guard keptSize == nil else { return }
        // Taken while the window is still in sight: a database's tables, a document's text.
        lastLook = face.picture() == nil ? sizer.picture() : nil
        let kept = GlassConnectionsWindowSize.returning(to: size ?? sizer.windowSize)
        keptSize = kept
        if let id = face.dockID { GlassOrbDockModel.shared.stands(id, growingBackTo: kept) }
        ringed = !face.ring(services: GlassSessionOrbServices.dots(for: face)).isEmpty
        sizer.resize(to: GlassSessionOrbSize.window(ringed: ringed), event: "session-orb", freeform: true)
    }

    private func grow() {
        guard let size = keptSize else { return }
        keptSize = nil
        if let id = face.dockID { GlassOrbDockModel.shared.noLongerStands(id) }
        growing = true
        sizer.resize(to: size, event: "session-window") { growing = false }
    }
}

#if DEBUG
enum GlassSessionOrbDemo {
    static var shrinksOnOpen: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--ui-testing") && arguments.contains("--demo-session-orb")
    }

    /// `--demo-orb-names`: every name drawn as it is for a look, to check where each sits — the
    /// simulator cannot be looked at. `--demo-orb-name <title>`: only that tab's, as one look opens
    /// one, to check what it is drawn over.
    static func showsName(_ title: String) -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-testing") else { return false }
        if arguments.contains("--demo-orb-names") { return true }
        guard let flag = arguments.firstIndex(of: "--demo-orb-name"), arguments.indices.contains(flag + 1) else { return false }
        return arguments[flag + 1] == title
    }
}
#endif

/// The orb: the session's live picture inside a glass sphere, pulsing while its session is busy and
/// the window asked for it; growing a little when looked at or pinched (the owner, 2026-10-15: "Make
/// the orb shaped more like an orb, and have it grow slightly when interacted with"). With two or
/// more tabs, they sit evenly on a ring around it; looking at one shows its picture in the orb and its
/// name beyond it, never over the orb ("it should grow away from the orb"), and a pinch on one grows
/// the window back on that tab.
struct GlassSessionOrbView: View {
    let face: GlassSessionOrbFace
    /// A dot opens into its icon and name while it is looked at, as Apple's tab bar does (the owner,
    /// 2026-10-25: "on mouse over the tab icon simply expands to show the icon and the name"): in the
    /// dock, where a name beside its dot would lie over the next orb, and one under the orb could not
    /// be read from the dot ("foveated rendering … reading the top tab's name under the orb is
    /// impossible"). Only the icon is looked at; the name opens toward the trailing side.
    var expandsDots = false
    let grow: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.layoutDirection) private var layoutDirection
    @Namespace private var looks

    /// What looking at the orb, or at a tab's dot, shows. Only the orb and the dots set their group
    /// going; what they show follows (`.followsGroup`). Left to the default, every tab's picture —
    /// each inside the orb — set its own group going when the orb was looked at, and every tab's name
    /// showed at once (the owner, on the headset: "all of them at once is a lot").
    private var orbLook: HoverEffectGroup { HoverEffectGroup(id: "orb", in: looks) }
    private func look(_ tab: GlassSessionOrbTab) -> HoverEffectGroup { HoverEffectGroup(id: "tab-" + tab.id, in: looks) }
    private var shownByOrb: HoverEffectGroup { orbLook.behavior(.followsGroup) }

    /// Nil, so a look alone shows a name — except in the screenshots' demo.
    private static func namesOverride(_ title: String) -> HoverEffectPhaseOverride? {
        #if DEBUG
        GlassSessionOrbDemo.showsName(title) ? .active : nil
        #else
        nil
        #endif
    }
    private func shown(by tab: GlassSessionOrbTab) -> HoverEffectGroup { look(tab).behavior(.followsGroup) }

    var body: some View {
        let tabs = face.ring(services: GlassSessionOrbServices.dots(for: face))
        GlassOrbRingLayout(count: tabs.count, namesFromDots: expandsDots) {
            orb(tabs)
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                if expandsDots {
                    openingDot(tab)
                        .offset(z: GlassOrbRingLayout.lift(of: index, count: tabs.count))
                } else {
                    dot(tab)
                }
            }
            // A name is somewhere to look as well as something shown: looked at, it keeps its group
            // going, so it stays while it is read. It vanished as the eyes moved to it from its dot
            // (the owner, on the headset: "The labels disappear when you try to read them because
            // the dot lose focus"). A pinch on it does what a pinch on its dot does.
            ForEach(tabs) { tab in
                if expandsDots {
                    // The dot carries its name; the layout keeps a place for one.
                    Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
                } else {
                    Button {
                        choose(tab)
                    } label: {
                        GlassOrbName(title: tab.title)
                            .hoverEffect(GlassOrbRevealEffect().hoverEffectPhaseOverride(Self.namesOverride(tab.title)), in: shown(by: tab))
                    }
                    .buttonStyle(GlassSessionOrbPressStyle())
                    .contentShape(.hoverEffect, .capsule)
                    .hoverEffectGroup(look(tab))
                    .accessibilityHidden(true)
                }
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
                    // Only a picture: a symbol in its place showed over the session's own, several
                    // at once, a database's and a desktop's (the owner, on the headset: "the icons in
                    // the middle seem to overlap").
                    ForEach(tabs) { tab in
                        if let image = tab.picture() {
                            picture(image, symbolName: tab.symbolName)
                                .clipShape(.circle)
                                .hoverEffect(GlassOrbRevealEffect(), in: shown(by: tab))
                        }
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

    /// A tab comes to the front as the window grows back on it; a service opens on its own.
    private func choose(_ tab: GlassSessionOrbTab) {
        tab.select()
        if tab.growsWindow { grow() }
    }

    private func dot(_ tab: GlassSessionOrbTab) -> some View {
        Button {
            choose(tab)
        } label: {
            dotIcon(tab)
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

    /// A dot that opens into its icon and name while looked at: the icon on a circle of its own, as
    /// a window's dots are, and behind it the name's capsule running to the trailing side, out of
    /// sight until the icon is looked at (the owner, 2026-10-25: "the natural state remain the
    /// circle, only expand on attention"). Only the icon is somewhere to look or pinch, so an open
    /// name never takes a look from what it passes over. Laid out at the dot's size.
    ///
    /// The capsule is the dot's own, opened by its own look. Put in a layer of its own in front of
    /// every dot (0.4.528), with nowhere to look on it, it showed on the headset only as a stub, with
    /// the dot's icon still behind its copy (the owner, 2026-10-26: "only show a stub and you can still
    /// see the original icon behind"). A neighbour no longer covers an open name because whatever lies
    /// on the leading side stands a little in front of what lies on the trailing side, where names
    /// open (`GlassOrbRingLayout.lift`, and the dock's row).
    ///
    /// In front of the orb, so an open name crossing it stays over it ("they need to remain on
    /// top!"): drawn after the orb, it was still under the sphere's glass, and an effect the system
    /// draws cannot bring anything forward.
    private func openingDot(_ tab: GlassSessionOrbTab) -> some View {
        let side = GlassOrbRingLayout.dotDiameter
        let rightToLeft = layoutDirection == .rightToLeft
        let name = Text(tab.title)
            .font(.footnote.weight(.medium))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: GlassOrbRingLayout.nameWidth, alignment: .leading)
            .padding(.leading, side + 4)
            .padding(.trailing, 16)
            .fixedSize()
            .frame(height: side)
        return Button {
            choose(tab)
        } label: {
            ZStack(alignment: .leading) {
                name.hidden()
                    .glassBackgroundEffect(in: .capsule)
                    .hoverEffect(GlassOrbOpenEffect(rightToLeft: rightToLeft).hoverEffectPhaseOverride(Self.namesOverride(tab.title)),
                                 in: shown(by: tab))
                name
                    .hoverEffect(GlassOrbRevealEffect().hoverEffectPhaseOverride(Self.namesOverride(tab.title)), in: shown(by: tab))
                dotIcon(tab)
                    .frame(width: side, height: side)
                    .glassBackgroundEffect(in: .circle)
                    .hoverEffect(GlassOrbGrowEffect(), in: shown(by: tab))
            }
            .contentShape(.hoverEffect, GlassOrbLeadingCircle(rightToLeft: rightToLeft))
            .contentShape(.interaction, GlassOrbLeadingCircle(rightToLeft: rightToLeft))
            .hoverEffect(.highlight)
        }
        .buttonStyle(GlassSessionOrbPressStyle())
        .hoverEffectGroup(look(tab))
        .frame(width: side, height: side, alignment: .leading)
        .accessibilityLabel("Open \(tab.title)")
        .accessibilityIdentifier("session-orb-tab-\(tab.id)")
    }

    @ViewBuilder
    private func dotIcon(_ tab: GlassSessionOrbTab) -> some View {
        if let icon = tab.icon {
            icon
        } else {
            Image(systemName: tab.symbolName)
                .font(.system(size: GlassOrbRingLayout.iconSize, weight: .semibold))
                .foregroundStyle(tab.tint)
        }
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

/// A name on glass, shown while what it names is looked at: as wide as its words, up to the width
/// `GlassOrbRingLayout` gives it, then shortened in the middle.
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
            .contentShape(.capsule)
            .accessibilityHidden(true)
    }
}

/// A name's capsule opening out of its dot, as Apple's tab bar opens: squeezed into the icon's circle
/// and clear until the icon is looked at, then stretched to its whole width. Stretched rather than
/// cut: visionOS cut the glass to the clip's square, so a dot at rest was round on one side and
/// square on the other (on the headset and in the simulator, 2026-10-25). Drawn by the system, out
/// of the app's process.
struct GlassOrbOpenEffect: CustomHoverEffect {
    let rightToLeft: Bool

    func body(content: Content) -> some CustomHoverEffect {
        content.hoverEffect { effect, isActive, proxy in
            effect.opacity(isActive ? 1 : 0)
                .scaleEffect(x: isActive ? 1 : proxy.size.height / max(proxy.size.width, 1), y: 1,
                             anchor: rightToLeft ? .trailing : .leading)
        }
    }
}

/// The circle at a capsule's icon end: all of an opening dot that can be looked at or pinched.
struct GlassOrbLeadingCircle: Shape {
    let rightToLeft: Bool

    func path(in rect: CGRect) -> Path {
        let side = rect.height
        return Path(ellipseIn: CGRect(x: rightToLeft ? rect.maxX - side : rect.minX, y: rect.minY, width: side, height: side))
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
    /// Each tab's name opening from its dot's leading edge, rather than beside the dot away from the orb.
    var namesFromDots = false
    static let maximumTabs = 12
    /// Large enough to read the agent's mark in it at a glance (the owner, 2026-10-21: "increase the
    /// size of the icons in orb view"); it was 30, its symbol 12.
    static let dotDiameter: CGFloat = 48
    /// A dot's symbol, or its icon's side.
    static let iconSize: CGFloat = 24
    /// Between the orb's rim and a dot's (the owner: "move the dots away from the orb a few more pixels").
    static let gap: CGFloat = 22
    static let nameWidth: CGFloat = 150
    /// How far a dot that opens into its name stands in front of the orb.
    static let openingLift: CGFloat = 12
    static var ringRadius: CGFloat { GlassConnectionsOrb.diameter / 2 + gap + dotDiameter / 2 }

    /// How far an opening dot stands in front of the orb: `openingLift`, and up to `liftSpan` more
    /// the further it lies to the leading side, so an open name lies over the dots it crosses on
    /// its way to the trailing side instead of under them (the owner, 2026-10-26: "I was looking at
    /// the one on the left and the one to the right opened"). Depth, not drawing order: dots stood
    /// in front of the orb are each their own layer, and `zIndex` did not order them (the
    /// simulator, 2026-10-26). The same in a right-to-left language: the layout is mirrored.
    static func lift(of index: Int, count: Int) -> CGFloat {
        let across = cos(-Double.pi / 2 + 2 * Double.pi * Double(index) / Double(max(count, 1)))
        return openingLift + liftSpan * CGFloat(1 - across) / 2
    }
    /// From the trailing-most dot to the leading-most: about 3 mm, unseen except where they overlap.
    static let liftSpan: CGFloat = 4

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
            if namesFromDots {
                Self.place(subviews[1 + count + index], at: CGPoint(x: dot.x - Self.dotDiameter / 2, y: dot.y),
                           anchor: .leading, widest: .infinity)
                continue
            }
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
            Self.place(subviews[1 + count + index], at: point, anchor: anchor, widest: Self.nameWidth)
        }
        Self.place(subviews[subviews.count - 1], at: CGPoint(x: center.x, y: center.y + outer + 10), anchor: .top,
                   widest: Self.nameWidth + 40)
    }

    /// A name at its own width, never wider than `widest`. Offered the widest width, a name drew
    /// its capsule centred in all of it, so a short one sat well away from its dot on either side
    /// (the owner, on the headset, 2026-10-15: "the small names still don't align correctly around
    /// the orb").
    private static func place(_ name: LayoutSubview, at point: CGPoint, anchor: UnitPoint, widest: CGFloat) {
        let ideal = name.sizeThatFits(.unspecified)
        name.place(at: point, anchor: anchor, proposal: ProposedViewSize(width: min(ideal.width, widest), height: ideal.height))
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
