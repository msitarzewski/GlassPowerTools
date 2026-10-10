//
//  GlassConnectionsOrb.swift
//  Glass Power Tools — GlassShell
//
//  The headset's Connections window, shrunk to an orb (W29). It stands in for the window in two
//  cases: Connections idle while other windows are open (`glassConnectionsIdleShrink`, which
//  pushes the orb in the window's place), and Connections closed as the app's last window
//  (`GlassWindowRecoveryManager`, which parks it here). Either way a pinch brings the window back.
//
//  It was glas.sh's spinner: a terminal symbol rotating without end in a material circle, which
//  moved in the corner of the eye all day. Now it is still — the app's own icon in Apple's
//  glass — and only answers being looked at, the way every control on the headset does: the system
//  grows and lights it and shows "Connections" beneath it. The app is never told it was looked at
//  (visionOS keeps where a person looks private), so looking shows and a pinch restores.
//

import SwiftUI

#if os(visionOS)
/// The orb's window. Plain, so the orb's own glass circle is the only thing drawn, and sized to
/// its content: a pushed window otherwise opens at the size of the window it replaces.
public struct GlassConnectionsOrbScene: Scene {
    private let model: GlassShellModel
    private let recovery: GlassWindowRecoveryManager

    public init(model: GlassShellModel, recovery: GlassWindowRecoveryManager) {
        self.model = model
        self.recovery = recovery
    }

    public var body: some Scene {
        // The literal, not `GlassConnectionsOrb.windowID`: GlassWindowShapeTests reads each plain
        // scene's `id:` from the source and records this one as "minimized".
        Window("", id: "minimized") {
            GlassConnectionsOrb(model: model, recovery: recovery)
                .trackWindowPresence(key: GlassConnectionsOrb.windowID, recovery: recovery)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultSize(width: GlassConnectionsOrb.windowSide, height: GlassConnectionsOrb.windowSide)
        .restorationBehavior(.disabled)
    }
}

/// The orb: the app's icon in a glass circle, with the library's Active count when there is one.
public struct GlassConnectionsOrb: View {
    /// The orb's scene. "minimized" since glas.sh; the recovery manager parks Connections by it.
    public static let windowID = "minimized"
    static let diameter: CGFloat = 112
    /// Room for the circle grown on a look, and the name shown beneath it.
    static let windowSide: CGFloat = 184

    private let model: GlassShellModel
    private let recovery: GlassWindowRecoveryManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.scenePhase) private var scenePhase

    public init(model: GlassShellModel, recovery: GlassWindowRecoveryManager) {
        self.model = model
        self.recovery = recovery
    }

    /// The library's own number — the Active row's — so the orb never disagrees with the window
    /// it stands for. Nothing until the library has loaded, as the row says nothing then either.
    private var activeCount: Int { model.isLoaded ? model.activeSessionCount() : 0 }

    public var body: some View {
        let count = activeCount
        Button(action: restore) {
            // Room under the icon for its count's badge before the name.
            VStack(spacing: 10 + GlassConnectionsOrbFace.badgeDrop) {
                GlassConnectionsOrbFace(count: count)
                    .frame(width: Self.diameter, height: Self.diameter)
                    .glassBackgroundEffect(in: .circle)
                    .contentShape(.hoverEffect, .circle)
                    // Looked at, it lights as every control does, and grows a little.
                    .hoverEffect(.highlight)
                    .hoverEffect(GlassOrbGrowEffect().hoverEffectPhaseOverride(Self.lookedAtOverride))
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
        // Its own style: a plain button would light its whole frame on a look, a square over
        // the circle.
        .buttonStyle(GlassOrbButtonStyle())
        .frame(width: Self.windowSide, height: Self.windowSide)
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

    /// Back to the full window. Pushed aside for idle, the window is still there behind the orb:
    /// dismissing the orb brings it back at its size and place, as it was. Parked because it was
    /// closed, there is no window behind it, so a new one opens.
    private func restore() {
        if recovery.isConnectionsPushedAside {
            dismissWindow()
        } else {
            openWindow.openConnections()
            dismissWindow(id: Self.windowID)
        }
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
private struct GlassOrbGrowEffect: CustomHoverEffect {
    func body(content: Content) -> some CustomHoverEffect {
        content.hoverEffect { effect, isActive, _ in
            effect.scaleEffect(isActive ? 1.08 : 1)
        }
    }
}

/// Fades the name in while the orb is looked at.
private struct GlassOrbRevealEffect: CustomHoverEffect {
    func body(content: Content) -> some CustomHoverEffect {
        content.hoverEffect { effect, isActive, _ in
            effect.opacity(isActive ? 1 : 0)
        }
    }
}

/// The app's icon, and at its foot the Active count when there is one.
private struct GlassConnectionsOrbFace: View {
    let count: Int

    var body: some View {
        // The app's own icon, its three layers flattened (`GlassPowerToolsOrb` in the app's
        // assets), round as visionOS draws app icons. The owner (2026-10-10): "use the Glass Power
        // Tools icon instead of the generic terminal one for the floater."
        Image("GlassPowerToolsOrb")
            .resizable()
            .scaledToFill()
            .clipShape(.circle)
            .overlay(alignment: .bottom) {
                if count > 0 {
                    // The Active row's own symbol and number: what the window would say.
                    Label {
                        Text(count, format: .number)
                    } icon: {
                        Image(systemName: "bolt.fill")
                    }
                    .labelStyle(GlassOrbCountLabelStyle())
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassBackgroundEffect(in: .capsule)
                    // A badge on the icon's rim, as the system badges an app.
                    .offset(y: Self.badgeDrop)
                    .transition(.opacity)
                }
            }
            .accessibilityHidden(true)
    }

    /// How far the count's badge hangs below the icon.
    static let badgeDrop: CGFloat = 12
}

/// Pressed, the orb gives a little; looked at, its own hover effects answer.
private struct GlassOrbButtonStyle: ButtonStyle {
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
