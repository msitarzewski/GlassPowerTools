//
//  GlassSidebarToggle.swift
//  Glass Power Tools — GlassConnectionUI
//
//  Show and hide a split view's sidebar, where the system draws no control for it.
//
//  On Vision Pro a `NavigationSplitView` in these windows shows no sidebar toggle of its own: the
//  editor's file list had none, only an empty bar where it would be (the owner, 2026-10-10:
//  "There's no hide the sidebar in the files list when an editor is open"), with a project open and
//  nothing removing the system's item (W32, seen in the visionOS 27 simulator). The database had
//  placed its own since glassdb, at the leading edge of the detail column's bar, and on an iPad.
//  This is that button, shared, so both windows have the same one in the same place.
//
//  **On Vision Pro since W33** the four windows of columns have no split view at all: the toggle
//  leads the content column's header (`GlassSpatialColumnHeader`), with ⌃⌘S, and the sidebar
//  slides out and back (`GlassSpatialSplitView`). The iPad's database keeps it in its bar.
//
//  **Not on a Mac.** There the system's own item is the family standard (D24): a placed button
//  drops into the overflow menu with its title and leaves with a collapsed column.
//

import SwiftUI

public struct GlassSidebarToggle: View {
    @Binding private var columnVisibility: NavigationSplitViewVisibility

    public init(columnVisibility: Binding<NavigationSplitViewVisibility>) {
        _columnVisibility = columnVisibility
    }

    private var isHidden: Bool { columnVisibility == .detailOnly }

    public var body: some View {
        Button {
            withAnimation {
                columnVisibility = isHidden ? .automatic : .detailOnly
            }
        } label: {
            Label("Toggle Sidebar", systemImage: isHidden ? "sidebar.left" : "sidebar.leading")
        }
        .help(isHidden ? "Show the sidebar" : "Hide the sidebar")
        .accessibilityIdentifier("sidebar-toggle")
    }
}
