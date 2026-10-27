//
//  GlassConnectionsOrb.swift
//  Glass Power Tools — GlassShell
//
//  The headset's Connections window, shrunk to an orb (W29). Since W39 the orb is not a window of
//  its own: the Connections window becomes it, made orb-sized, with the library kept out of sight
//  inside (`glassConnectionsIdleShrink`). It stands in for the library in two cases: idle while
//  other windows are open, and closed as the app's last window (`GlassWindowRecoveryManager`
//  opens Connections again as its orb). Either way a pinch brings the library back.
//
//  It was glas.sh's spinner: a terminal symbol rotating without end in a material circle, which
//  moved in the corner of the eye all day. Now it is still — the app's own icon in Apple's
//  glass — and only answers being looked at, the way every control on the headset does: the system
//  grows and lights it and shows "Connections" beneath it. The app is never told it was looked at
//  (visionOS keeps where a person looks private), so looking shows and a pinch restores.
//

import SwiftUI

#if os(visionOS)
/// The orb: the app's icon in a glass circle, with the library's Active count when there is one.
/// No panel behind it: the window it stands in draws none while it is the orb, so the icon and
/// its glass circle are all there is, as when the orb was a plain window of its own.
public struct GlassConnectionsOrb: View {
    static let diameter: CGFloat = 112
    /// Room for the circle grown on a look, and the name shown beneath it.
    static var windowSide: CGFloat { GlassConnectionsWindowSize.orbSide }

    private let model: GlassShellModel
    /// Larger in the dock, where it leads the others (the owner, 2026-10-26: "bring the connections
    /// orb to more prominence").
    private let scale: CGFloat
    private let restore: () -> Void
    /// What a pinch and hold offers, in the dock.
    private var menu: AnyView?
    @Environment(\.scenePhase) private var scenePhase

    /// - Parameter restore: grows the window back into the library.
    init(model: GlassShellModel, scale: CGFloat = 1, restore: @escaping () -> Void) {
        self.model = model
        self.scale = scale
        self.restore = restore
    }

    /// - Parameter menu: offered on a pinch and hold; a pinch still restores.
    init<Items: View>(model: GlassShellModel, scale: CGFloat = 1, restore: @escaping () -> Void,
                      @ViewBuilder menu: () -> Items) {
        self.init(model: model, scale: scale, restore: restore)
        self.menu = AnyView(menu())
    }

    /// The library's own number — the Active row's — so the orb never disagrees with the window
    /// it stands for. Nothing until the library has loaded, as the row says nothing then either.
    private var activeCount: Int { model.isLoaded ? model.activeSessionCount() : 0 }

    public var body: some View {
        let count = activeCount
        orb(count)
            // Activated in its middle, on the icon. Left to SwiftUI, the point moved down to the name
            // when the badge came out of the icon (42071ef); the name is invisible until the orb is
            // looked at, and the UI test's tap there reached the terminal behind the orb instead (W34).
            .accessibilityActivationPoint(.center)
            .frame(width: Self.windowSide * scale, height: Self.windowSide * scale)
            .animation(.smooth, value: count)
            .help("Open Connections")
            .accessibilityLabel(count > 0 ? "Open Connections, \(count) active" : "Open Connections")
            // What runs on the machines, asked the way the library asks as it appears: at most once
            // in `runningSessionsMaxAge`, and not before the library has loaded. Nothing more polls.
            .task { await model.refreshRunningSessionsIfDue() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await model.refreshRunningSessionsIfDue() }
            }
    }

    /// A pinch restores the library. With a menu, a pinch and hold opens it (the owner, 2026-10-27:
    /// "No menu on the connections icon with pinch and hold"): a `.contextMenu` on the button never
    /// opened in the dock, on the headset or in the simulator, scrolling or not; a menu whose pinch is
    /// its primary action does, as a toolbar button's does.
    @ViewBuilder
    private func orb(_ count: Int) -> some View {
        if let menu {
            Menu { menu } label: { face(count) } primaryAction: { restore() }
                .menuIndicator(.hidden)
                .buttonStyle(GlassOrbButtonStyle())
        } else {
            // Its own style: a plain button would light its whole frame on a look, a square over
            // the circle.
            Button(action: restore) { face(count) }
                .buttonStyle(GlassOrbButtonStyle())
        }
    }

    private func face(_ count: Int) -> some View {
        // Room under the icon for the count's badge before the name.
        VStack(spacing: 10 + GlassConnectionsOrbBadge.drop) {
            GlassConnectionsOrbFace()
                .frame(width: Self.diameter * scale, height: Self.diameter * scale)
                .glassBackgroundEffect(in: .circle)
                .contentShape(.hoverEffect, .circle)
                // Looked at, it lights as every control does, and grows a little.
                .hoverEffect(.highlight)
                .hoverEffect(GlassOrbGrowEffect().hoverEffectPhaseOverride(Self.lookedAtOverride))
                // Over the icon, after its hover effects, so the highlight's circle never clips it.
                .overlay(alignment: .bottom) {
                    if count > 0 {
                        GlassConnectionsOrbBadge(count: count)
                            .alignmentGuide(.bottom) { $0[.bottom] - GlassConnectionsOrbBadge.drop }
                            .transition(.opacity)
                    }
                }
            Text("Connections")
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .glassBackgroundEffect(in: .capsule)
                // Shown only while the orb is looked at: the name, where the eyes already are.
                .hoverEffect(GlassOrbRevealEffect().hoverEffectPhaseOverride(Self.lookedAtOverride))
        }
        // Looking at either part lights both.
        .hoverEffectGroup()
    }

    #if DEBUG
    /// Screenshots only (`--demo-open orb-looked-at`): the simulator cannot be looked at, so the
    /// demo has the system draw the orb as it draws it for a look.
    @MainActor public static var demoShowsLookedAt = false
    #endif

    /// Nil, so the system alone decides when the orb is looked at — except in that demo.
    @MainActor private static var lookedAtOverride: HoverEffectPhaseOverride? {
        #if DEBUG
        demoShowsLookedAt ? .active : nil
        #else
        nil
        #endif
    }
}

/// Grows the orb a little while it is looked at. Drawn by the system, out of the app's process.
struct GlassOrbGrowEffect: CustomHoverEffect {
    func body(content: Content) -> some CustomHoverEffect {
        content.hoverEffect { effect, isActive, _ in
            effect.scaleEffect(isActive ? 1.08 : 1)
        }
    }
}

/// Fades the name in while the orb is looked at.
struct GlassOrbRevealEffect: CustomHoverEffect {
    func body(content: Content) -> some CustomHoverEffect {
        content.hoverEffect { effect, isActive, _ in
            effect.opacity(isActive ? 1 : 0)
        }
    }
}

/// The app's icon: its three visionOS layers flattened (`GlassPowerToolsOrb` in the app's assets),
/// round as visionOS draws app icons. The owner (2026-10-10): "use the Glass Power Tools icon
/// instead of the generic terminal one for the floater."
private struct GlassConnectionsOrbFace: View {
    var body: some View {
        Image("GlassPowerToolsOrb")
            .resizable()
            .scaledToFill()
            .clipShape(.circle)
            .accessibilityHidden(true)
    }
}

/// The library's Active count on the orb's rim, as the system badges an app: its own glass, drawn
/// over the icon rather than inside it. Inside, the look highlight (clipped to the circle) cut it
/// in half (owner, on the headset: "the count is kind of off").
private struct GlassConnectionsOrbBadge: View {
    let count: Int

    var body: some View {
        // The Active row's own symbol and number: what the window would say.
        Label {
            Text(count, format: .number)
        } icon: {
            Image(systemName: "bolt.fill")
        }
        .labelStyle(GlassOrbCountLabelStyle())
        .font(.subheadline.weight(.semibold).monospacedDigit())
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassBackgroundEffect(in: .capsule)
        .accessibilityHidden(true)
    }

    /// How far the badge hangs below the icon's rim: half its height, so it straddles the rim.
    static let drop: CGFloat = 14
}

/// Pressed, the orb gives a little; looked at, its own hover effects answer.
struct GlassOrbButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

private struct GlassOrbCountLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

#endif
