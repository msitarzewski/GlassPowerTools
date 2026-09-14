import SwiftUI

/// Forces a control's label to render in a given style, where a `Menu` would otherwise repaint it.
///
/// **Why this exists.** `Menu` does not inherit `foregroundStyle` from its surroundings the way a
/// `Button` does: `.menuStyle(.borderlessButton)` supplies its own label colour, so a chevron
/// inside it renders in the default label colour no matter what the enclosing view sets — and
/// setting the colour on the label content directly does not win either, because the style is
/// applied after it. On a filled accent capsule that means a black glyph beside a white one.
///
/// A `ButtonStyle` is the one hook that is *not* overridden: with `.menuStyle(.button)` the menu
/// renders through the button style, and `configuration.label` is ours to style. Every filled
/// control in the family can use this rather than each discovering the same behaviour separately.
///
/// Deliberately only colour and press feedback — the shape and background stay with the caller, so
/// a split control can keep one capsule spanning two halves.
public struct GlassOnFilledLabelStyle: ButtonStyle {
    private let foreground: AnyShapeStyle

    /// - Parameter foreground: what the label renders in. Defaults to white, the convention for a
    ///   glyph on a filled accent shape; pass another style for a differently filled control.
    public init(foreground: some ShapeStyle = .white) {
        self.foreground = AnyShapeStyle(foreground)
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .opacity(configuration.isPressed ? 0.65 : 1)
            .contentShape(Rectangle())
    }
}

public extension View {
    /// Renders a `Menu`'s label through a button style so its colour is the caller's to set.
    ///
    /// Pairs `.menuStyle(.button)` with ``GlassOnFilledLabelStyle``; use it wherever a menu sits on
    /// a filled accent shape.
    func glassMenuOnFilled(foreground: some ShapeStyle = .white) -> some View {
        menuStyle(.button)
            .buttonStyle(GlassOnFilledLabelStyle(foreground: foreground))
    }
}
