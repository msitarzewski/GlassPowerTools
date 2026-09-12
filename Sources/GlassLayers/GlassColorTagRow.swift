import SwiftUI

/// A colour tag row for a menu `Picker`. `Label(_:systemImage:).foregroundStyle(_:)` loses its
/// tint inside a macOS menu — every dot renders grey — so the swatch is drawn as a shape with an
/// explicit palette rendering mode, which the menu honours.
public struct GlassColorTagRow: View {
    public let title: String
    public let color: Color?

    public init(title: String, color: Color?) {
        self.title = title
        self.color = color
    }

    public var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: color == nil ? "circle.dotted" : "circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(color ?? .secondary)
        }
    }
}
