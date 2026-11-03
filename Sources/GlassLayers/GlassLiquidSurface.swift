#if os(macOS) || os(iOS)
import SwiftUI

/// A floating surface of Apple's Liquid Glass rather than a frost: the Mac's orb dock (the owner, 2026-11-02,
/// beside Control Center in its Clear look: "let's make the dock background use a liquid texture like Apple's",
/// "Like this!"). A frost is a blur under a wash, with no edge and nothing bent, so on an even wallpaper it was
/// "as flat as flat is". Glass, Material and Opacity still mean what they mean on a window: how much glass,
/// which glass, and the theme's paint (`glass-is-the-point`).
public struct GlassLiquidLook: Equatable, Sendable {
    /// Apple's two glasses.
    public enum Kind: Equatable, Sendable {
        /// Control Center's: what lies behind it, bent at its edges and barely frosted.
        case clear
        /// The frostier one, as Apple's Tinted look is.
        case regular

        public var glass: Glass { self == .clear ? .clear : .regular }
    }

    /// Clear for Light, Medium and Heavy; Regular for Max.
    public var kind: Kind
    /// How much of the glass shows: Glass. None leaves what lies on it floating on the desktop.
    public var strength: Double
    /// How much what the glass sees is darkened (lightened in light mode) under it, as Apple dims behind
    /// Clear glass so what lies on it can be read: more for a heavier Material, none for Light or Max.
    public var dim: Double
    /// The theme's colour under the glass, which the glass takes on: Opacity.
    public var paint: Double

    /// Heavy's dimming, the app's default: about Control Center's.
    public static let heavyDim = 0.24

    public init(_ state: GlassLayerState) {
        kind = state.material == .thick ? .regular : .clear
        strength = state.frost
        let dim: Double = switch state.material {
        case .ultraThin, .thick: 0
        case .thin: Self.heavyDim / 2
        case .regular: Self.heavyDim
        }
        self.dim = dim * state.frost
        paint = state.effectiveOpacity
    }

    /// No glass and no paint: nothing is drawn.
    public var isEmpty: Bool { strength == 0 && paint == 0 }
}

public extension EnvironmentValues {
    /// Which glass what floats on a `GlassLiquidSurface` is made of: the orb dock's drops follow its Material.
    @Entry var glassLiquidKind: GlassLiquidLook.Kind = .clear
}

/// `GlassLiquidLook` drawn: the theme's paint, the dimming, then the glass over them, which takes on both. Not
/// hit-testable; the content over it owns input.
public struct GlassLiquidSurface: View {
    private let look: GlassLiquidLook
    private let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    public init(_ look: GlassLiquidLook, cornerRadius: CGFloat) {
        self.look = look
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if look.paint > 0 {
                shape.fill(Color.glassThemeBackground).opacity(look.paint)
            }
            if look.strength > 0 {
                if look.dim > 0 {
                    shape.fill(colorScheme == .dark ? Color.black : Color.white).opacity(look.dim)
                }
                Color.clear
                    .glassEffect(look.kind.glass, in: shape)
                    .opacity(look.strength)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
