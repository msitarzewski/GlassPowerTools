import SwiftUI

/// Explicit labels remain visible even on platforms that hide Slider labels.
public struct GlassSpatialDisplayControls: View {
    @Binding private var curvature: Double
    @Binding private var tilt: Double
    @Binding private var angle: Double
    public init(curvature: Binding<Double>, tilt: Binding<Double>, angle: Binding<Double>) {
        _curvature = curvature; _tilt = tilt; _angle = angle
    }
    public var body: some View {
        Section("Display Shape") {
            row("Curvature", value: $curvature, range: 0...120, identifier: "display.curvature")
            row("Tilt", value: $tilt, range: -60...60, identifier: "display.tilt")
            row("Horizontal Angle", value: $angle, range: -60...60, identifier: "display.angle")
            Text("0° curvature is flat. Increase it to bring the sides toward you. Adjust tilt and angle while sitting comfortably; these choices stay fixed until you change them.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func row(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, identifier: String) -> some View {
        let bounded = Binding(get: { GlassSpatialGeometry.bounded(value.wrappedValue, in: range) }, set: { value.wrappedValue = GlassSpatialGeometry.bounded($0, in: range) })
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(bounded.wrappedValue.rounded()))°").monospacedDigit().foregroundStyle(.secondary)
                Stepper(title, value: bounded, in: range, step: 1)
                    .labelsHidden().fixedSize()
                    .accessibilityLabel(title)
                    .accessibilityIdentifier(identifier + ".stepper")
            }
            Slider(value: bounded, in: range, step: 1) { Text(title) }
                .accessibilityLabel(title)
                .accessibilityValue("\(Int(bounded.wrappedValue.rounded())) degrees")
                .accessibilityIdentifier(identifier)
        }
    }
}
