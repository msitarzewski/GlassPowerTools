//
//  GlassDetailColumnTitle.swift
//  Glass Power Tools — GlassConnectionUI
//
//  A detail column's title on the line of the list column's (2026-10-12). On an iPad or an
//  unfolded iPhone Duo the library is two columns: the list's title is the system's large title
//  ("All Connections"), and iOS 27 puts a detail column's title in the toolbar row instead, a row
//  higher, so selecting a machine moved its name out of line with the list. The owner chose the
//  large-title line for every two-column screen: the detail's title is drawn there, as a header
//  VoiceOver reads as one, and the system is given no title to put in the toolbar row —
//  `.toolbar(removing: .title)` left it there on iOS 27.1. So this modifier is the column's
//  navigation title too: the title itself everywhere else (compact width, the Mac, the headset,
//  which has its own column header, `glassSpatialColumn`).
//

import SwiftUI

public enum GlassDetailColumnTitleMetrics {
    /// The space above the title that sets it on the list column's large-title line: measured on
    /// the iPhone Duo simulator (iOS 27.1), cap tops level to a pixel.
    public static let top: CGFloat = 4
    /// Where iOS 27 drew the detail column's own title from the column's leading edge.
    public static let leading: CGFloat = 20
    /// How much lower the list's first row begins than a grouped form's under its title: added to
    /// the column's scrolling content so the first rows of both columns start on one line
    /// (measured on the Duo: "This iPhone" and "Services" were 35 pixels apart).
    public static let contentTop: CGFloat = 12
}

public extension View {
    /// This detail column's title: on an iPad or an unfolded iPhone Duo a large title on the list
    /// column's line, in place of the system's in the toolbar row; elsewhere its navigation title.
    @ViewBuilder
    func glassDetailColumnTitle(_ title: String,
                                leading: CGFloat = GlassDetailColumnTitleMetrics.leading) -> some View {
        #if os(iOS)
        modifier(GlassDetailColumnTitleModifier(title: title, leading: leading))
        #else
        navigationTitle(title)
        #endif
    }
}

#if os(iOS)
private struct GlassDetailColumnTitleModifier: ViewModifier {
    let title: String
    let leading: CGFloat
    @Environment(\.horizontalSizeClass) private var widthClass

    func body(content: Content) -> some View {
        if widthClass == .regular {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.largeTitle.bold())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, GlassDetailColumnTitleMetrics.top)
                    .padding(.horizontal, leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                content
                    .contentMargins(.top, GlassDetailColumnTitleMetrics.contentTop, for: .scrollContent)
            }
            .navigationTitle("")
        } else {
            content.navigationTitle(title)
        }
    }
}
#endif
