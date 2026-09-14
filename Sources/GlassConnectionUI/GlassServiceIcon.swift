import SwiftUI

/// How a service kind is drawn. Most kinds are SF Symbols; the database is Heroicons'
/// `circle-stack`, which the family prefers to any of the SF cylinder/drive symbols.
public enum GlassServiceSymbol: Sendable, Hashable {
    case system(String)
    case circleStack
}

/// Draws a `GlassServiceSymbol` at text size, tinted by the current foreground style.
/// Callers own the accessibility label and identifier, as they did with a bare `Image`.
public struct GlassServiceIcon: View {
    private let symbol: GlassServiceSymbol
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 17

    public init(_ symbol: GlassServiceSymbol) { self.symbol = symbol }

    public var body: some View {
        switch symbol {
        case .system(let name):
            Image(systemName: name)
        case .circleStack:
            HeroiconCircleStack()
                .stroke(style: StrokeStyle(lineWidth: HeroiconCircleStack.strokeWidth * side / 24,
                                           lineCap: .round, lineJoin: .round))
                .frame(width: side, height: side)
        }
    }
}

/// Heroicons v2 `optimized/24/outline/circle-stack.svg`, from Tailwind Labs, MIT licensed.
/// The original file and its licence are vendored at `Vendor/heroicons/`; the commands below are
/// that file's single `d` attribute translated one-for-one into `Path`, keeping its 24×24
/// viewport, 1.5 stroke width and round caps and joins. Do not "simplify" it: it should stay
/// comparable to upstream.
///
///     M20.25 6.375c0 2.278-3.694 4.125-8.25 4.125S3.75 8.653 3.75 6.375m16.5 0c0-2.278-3.694
///     -4.125-8.25-4.125S3.75 4.097 3.75 6.375m16.5 0v11.25c0 2.278-3.694 4.125-8.25 4.125s-8.25
///     -1.847-8.25-4.125V6.375m16.5 0v3.75m-16.5-3.75v3.75m16.5 0v3.75C20.25 16.153 16.556 18 12
///     18s-8.25-1.847-8.25-4.125v-3.75m16.5 0c0 2.278-3.694 4.125-8.25 4.125s-8.25-1.847-8.25-4.125
public struct HeroiconCircleStack: Shape {
    public static let strokeWidth: CGFloat = 1.5

    public init() {}

    public func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / 24
        let originX = rect.minX + (rect.width - side) / 2
        let originY = rect.minY + (rect.height - side) / 2
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: originX + x * scale, y: originY + y * scale)
        }

        var path = Path()
        // The top disc, drawn as its lower then upper arc.
        path.move(to: point(20.25, 6.375))
        path.addCurve(to: point(12, 10.5), control1: point(20.25, 8.653), control2: point(16.556, 10.5))
        path.addCurve(to: point(3.75, 6.375), control1: point(7.444, 10.5), control2: point(3.75, 8.653))
        path.move(to: point(20.25, 6.375))
        path.addCurve(to: point(12, 2.25), control1: point(20.25, 4.097), control2: point(16.556, 2.25))
        path.addCurve(to: point(3.75, 6.375), control1: point(7.444, 2.25), control2: point(3.75, 4.097))
        // The body: both sides and the closing arc at the bottom.
        path.move(to: point(20.25, 6.375))
        path.addLine(to: point(20.25, 17.625))
        path.addCurve(to: point(12, 21.75), control1: point(20.25, 19.903), control2: point(16.556, 21.75))
        path.addCurve(to: point(3.75, 17.625), control1: point(7.444, 21.75), control2: point(3.75, 19.903))
        path.addLine(to: point(3.75, 6.375))
        // The two discs stacked inside it.
        path.move(to: point(20.25, 6.375))
        path.addLine(to: point(20.25, 10.125))
        path.move(to: point(3.75, 6.375))
        path.addLine(to: point(3.75, 10.125))
        path.move(to: point(20.25, 10.125))
        path.addLine(to: point(20.25, 13.875))
        path.addCurve(to: point(12, 18), control1: point(20.25, 16.153), control2: point(16.556, 18))
        path.addCurve(to: point(3.75, 13.875), control1: point(7.444, 18), control2: point(3.75, 16.153))
        path.addLine(to: point(3.75, 10.125))
        path.move(to: point(20.25, 10.125))
        path.addCurve(to: point(12, 14.25), control1: point(20.25, 12.403), control2: point(16.556, 14.25))
        path.addCurve(to: point(3.75, 10.125), control1: point(7.444, 14.25), control2: point(3.75, 12.403))
        return path
    }
}
