//
//  TerminalTypeAheadChips.swift
//  Glass Power Tools — GlassTerminal
//
//  Type-ahead (D102, 2026-11-06) where there is no grey text: iPhone, iPad and Vision Pro. Up to three commands
//  offered for the line being typed; a tap types the rest of one. Typing on glass is slow, so these matter most here.
//  `tasks/2026-11/2026-11-06_type-ahead.md`.
//
//  Never over the terminal's text: drawn there first, they covered the line being typed whenever the screen was
//  full. The owner's choice (2026-11-06), Apple's own places for suggestions: on iPhone and iPad a row above the
//  keyboard's bar, like QuickType, standing for as long as the keyboard is up (`TerminalTypeAheadChipRow`), so the
//  terminal is one row shorter while typing rather than changing size with each line; on Vision Pro an ornament
//  under the window's toolbar, for the terminal in front (`TerminalWindowView`).
//

#if !os(macOS)
import SwiftUI
import GlassTerminalEmulator

/// The commands offered for the line now, side by side, scrolling where they don't all fit.
struct TerminalTypeAheadChips: View {
    @ObservedObject var model: SwiftTermHostModel

    /// The widest a chip grows; a longer command loses its start, which is what was typed already, and keeps the
    /// end that tells it from the others.
    private static let widest: CGFloat = 280

    var body: some View {
        // Each at its own width: three ordinary commands are wider than a phone, and cut to fit they read
        // "git st…h list" (2026-11-06, drawn at a phone's width).
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.typeAheadChoices, id: \.self) { command in
                    Button {
                        model.takeTypeAheadChoice(command)
                    } label: {
                        TerminalTypeAheadChipWidth(widest: Self.widest) {
                            Text(command)
                                .font(.system(.footnote, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    #if os(visionOS)
                    .glassBackgroundEffect(in: .capsule)
                    .hoverEffect()
                    #else
                    .glassEffect(.regular.interactive(), in: .capsule)
                    #endif
                    .accessibilityLabel(command)
                    .accessibilityHint("Types the rest of this command")
                }
            }
            .padding(.horizontal, 8)
        }
        .scrollClipDisabled()
        .animation(.easeOut(duration: 0.15), value: model.typeAheadChoices)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggested commands")
    }
}

#if os(iOS)
/// iPhone and iPad: the chips' row, directly above the keyboard's bar, for as long as the keyboard is up and
/// type-ahead is on; empty while nothing is offered, so the terminal above it keeps one size while typing.
struct TerminalTypeAheadChipRow: View {
    @ObservedObject var model: SwiftTermHostModel
    static let height: CGFloat = 40

    var body: some View {
        if model.offersTypeAheadChips, model.keyboardAccessoryShown {
            TerminalTypeAheadChips(model: model)
                .frame(height: Self.height)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif

/// A chip's text at its own width up to `widest`, then shortened. In a sideways scroll view nothing offers a width,
/// so a text's frame alone would clip it rather than shorten it.
private struct TerminalTypeAheadChipWidth: Layout {
    let widest: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let text = subviews.first else { return .zero }
        let width = min(text.sizeThatFits(.unspecified).width, proposal.width ?? .infinity, widest)
        return text.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}
#endif
