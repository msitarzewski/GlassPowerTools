//
//  GlassPowerToolsApp.swift
//  Glass Power Tools
//
//  Minimal entry point that proves the app target links the shell modules.
//  The Stage 1 integration pass replaces the scene bodies.
//

import SwiftUI
import GlassShell
import GlassLayers

@main
struct GlassPowerToolsApp: App {
    var body: some Scene {
        WindowGroup("Connections", id: "main") {
            Text("Glass Power Tools")
                .accessibilityIdentifier("glasspowertools-main-placeholder")
                .padding()
        }
        #if os(macOS)
        Settings {
            EmptyView()
        }
        #endif
    }
}
