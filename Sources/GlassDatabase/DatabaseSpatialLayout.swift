//
//  DatabaseSpatialLayout.swift
//  Glass Power Tools — GlassDatabase
//
//  W28 (owner, 2026-10-10, on the Vision Pro): "I'd also like to rebuild all window appearances to
//  match the new terminal. So screen sharing, database, etc."
//
//  **Why the database window can't simply be cleared.** A terminal window is plain and draws
//  Apple's glass itself, as strong as its Glass, so at 0 it is completely clear (D59). The database
//  window is plain too, but its `NavigationSplitView` draws system glass behind every column —
//  whole-window glass and a darker sidebar — and nothing public turns that off on visionOS 27
//  (W28's simulator trace: `glassBackgroundEffect(displayMode: .never)`, toolbar backgrounds and
//  visibility, every split view style and a `TabView` around it all leave it; the column
//  controllers SwiftUI makes ask UIKit for glass, and rule 62 keeps us from reaching into them).
//
//  **The option this file switches on.** Without the split view, on the headset only: the schema
//  list and the workspace side by side on the window's own glass (`GlassSpatialWindowGlass`), the
//  workspace as the canvas Opacity paints, in the corner nested in Apple's, and the window's title,
//  way back, sidebar button and ⚡ in a title ornament, as a terminal's are. At Glass 0 and Opacity 0
//  the window is completely clear but for its content and controls.
//
//  What it gives up beside the system split view: the sidebar's own animated collapse and the
//  column layout the system adapts to the window's width (the list keeps a fixed width; the sidebar
//  button still shows and hides it); the sidebar's navigation bar, so its title, Refresh, Mutation
//  Log and filter are drawn in the list's own header instead of the system's; the detail's
//  navigation bar, so the controls that lived there — Run, the assistant — join the bottom
//  toolbar; and the sidebar and content landmarks the system gives VoiceOver's rotor for a split
//  view's columns. Mac, iPad and iPhone are untouched.
//

import SwiftUI

extension EnvironmentValues {
    /// The schema list draws its own title, Refresh, Mutation Log and filter, because there is no
    /// navigation bar to hold them: a Vision Pro database window without the split view.
    @Entry var databaseSchemaInlineChrome = false
}

#if os(visionOS)
enum DatabaseSpatialLayout {
    /// **The switch.** `false`: the system split view, as before (Glass can't clear it).
    /// `true`: no split view on the headset, the window's own glass, and Glass 0 completely clear.
    static let ownGlass = false

    /// Whether this run draws the window without the split view. `--demo-database-own-glass`
    /// turns it on in a debug run, for comparing the two in screenshots (`App/GlassDemoMode.swift`).
    static let drawsItsOwnGlass: Bool = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo-database-own-glass") { return true }
        #endif
        return ownGlass
    }()

    /// The schema list's width beside the workspace: the split view's sidebar width on the headset.
    static let sidebarWidth: CGFloat = 320
}
#endif
