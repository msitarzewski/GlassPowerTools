import SwiftUI

/// A continuous percentage setting with the Glass family's aligned value column.
public struct GlassSettingSlider: View {
    private let title: String
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let detents: [Double]
    private let leadingAccessibilityLabel: String
    private let trailingAccessibilityLabel: String
    private let accessibilityIdentifier: String?

    /// `range` defaults to a 0...1 percentage. `detents` are values the slider settles on exactly
    /// when a drag lands near them, so a setting like 100% can be reached without pixel-hunting.
    public init(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double> = 0...1,
        detents: [Double] = [],
        leadingAccessibilityLabel: String,
        trailingAccessibilityLabel: String,
        accessibilityIdentifier: String? = nil
    ) {
        self.title = title
        _value = value
        self.range = range
        self.detents = detents
        self.leadingAccessibilityLabel = leadingAccessibilityLabel
        self.trailingAccessibilityLabel = trailingAccessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    public var body: some View {
        LabeledContent {
            HStack(spacing: 12) {
                if let accessibilityIdentifier {
                    slider.accessibilityIdentifier(accessibilityIdentifier)
                } else {
                    slider
                }
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: 44, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: 280)
        } label: {
            // The name, and on a This Window page the way back beside it (`GlassSettingTitle`).
            GlassSettingTitle(title)
        }
    }

    private var slider: some View {
        // A step draws ticks on Mac. Keep a continuous track and round
        // writes to whole percentages without adding those visual marks.
        Slider(
            value: Binding(
                get: { value },
                set: { value = snapped(($0 * 100).rounded() / 100) }
            ),
            in: range
        )
        .frame(minWidth: 190)
        .accessibilityLabel(title)
        .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
        .accessibilityHint("\(leadingAccessibilityLabel) to \(trailingAccessibilityLabel)")
    }

    private func snapped(_ candidate: Double) -> Double {
        Snapping(range: range, detents: detents).snapped(candidate)
    }

    /// Settling rule, kept separate from the view so it can be tested directly.
    struct Snapping {
        let range: ClosedRange<Double>
        let detents: [Double]

        /// Settles on a detent when the value lands within one and a half percentage points of it.
        func snapped(_ candidate: Double) -> Double {
            guard let detent = detents.first(where: { abs($0 - candidate) < 0.015 }) else { return candidate }
            return min(max(range.lowerBound, detent), range.upperBound)
        }
    }
}
