//
//  GlassSettingsSheet.swift
//  Glass Power Tools — GlassConnectionUI
//
//  The sheet a window's gear opens — Terminal, Editor, Database and Desktop Settings — laid out
//  one way (W27). Before, the editor's had Done top-right under a leading title and the other
//  three Done top-left under a centred one, and the desktop's added a button of its own; the
//  owner asked for one layout. So: the title, **Done** in the system's confirmation placement
//  (top-trailing on Vision Pro and iPad, the sheet's bottom bar on the Mac), and one size per
//  platform. Anything else a sheet offers belongs on its pages.
//

import SwiftUI

/// A window's Settings sheet: `content` (usually `GlassSettingsSections`) under `title`, with Done.
public struct GlassSettingsSheet<Content: View>: View {
    private let title: String
    private let doneIdentifier: String
    private let done: () -> Void
    private let content: Content

    /// - Parameters:
    ///   - doneIdentifier: the Done button's accessibility identifier, for UI tests.
    ///   - done: dismisses the sheet; the presenter owns whether it is shown.
    public init(_ title: String, doneIdentifier: String, done: @escaping () -> Void,
                @ViewBuilder content: () -> Content) {
        self.title = title
        self.doneIdentifier = doneIdentifier
        self.done = done
        self.content = content()
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: done)
                            .accessibilityIdentifier(doneIdentifier)
                    }
                }
        }
        #if os(iOS)
        .presentationDetents([.large])
        #else
        .frame(width: Self.size.width, height: Self.size.height)
        #endif
    }

    /// Every window's Settings sheet, on the platforms that size their own sheets.
    ///
    /// **Vision Pro:** large enough that a This Window page's main sections — the window's
    /// Appearance and the capability's first section after it — are in view without scrolling
    /// (measured in the visionOS simulator, W27): the terminal's Appearance and Theme, the
    /// database's Appearance, Query and Editor, the desktop's Appearance and Background Removal.
    /// At 760 × 560 the terminal's glass section alone filled it. Form rows there are about 88
    /// points tall, so each one costs more height than on the Mac.
    static var size: CGSize {
        #if os(visionOS)
        CGSize(width: 820, height: 860)
        #else
        CGSize(width: 760, height: 560)
        #endif
    }
}
