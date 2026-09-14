import Foundation

/// Platform-neutral color. `GlassEditorCore` cannot import SwiftUI/AppKit/UIKit,
/// so themes resolve to this and `GlassEditorUI` converts at render time.
/// Components are linear-independent sRGB in 0...1.
public struct ResolvedColor: Sendable, Hashable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
        self.alpha = min(max(alpha, 0), 1)
    }

    // MARK: WCAG math

    /// WCAG 2.x relative luminance of the sRGB components.
    public var relativeLuminance: Double {
        func channel(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG contrast ratio between two colors, in 1...21.
    public static func contrastRatio(_ a: ResolvedColor, _ b: ResolvedColor) -> Double {
        let la = a.relativeLuminance
        let lb = b.relativeLuminance
        let lighter = max(la, lb)
        let darker = min(la, lb)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// The result of alpha-compositing `self` over `background`
    /// (both treated as opaque output).
    public func composited(over background: ResolvedColor) -> ResolvedColor {
        let a = alpha
        return ResolvedColor(
            red: red * a + background.red * (1 - a),
            green: green * a + background.green * (1 - a),
            blue: blue * a + background.blue * (1 - a),
            alpha: 1.0
        )
    }

    public static let black = ResolvedColor(red: 0, green: 0, blue: 0)
    public static let white = ResolvedColor(red: 1, green: 1, blue: 1)
    public static let clear = ResolvedColor(red: 0, green: 0, blue: 0, alpha: 0)
}
