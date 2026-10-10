//
//  DatabaseIOSRouter.swift
//  Glass Power Tools — GlassDatabase
//
//  Moved from `../glassdb/glassdb/glassdbApp.swift:133-153`. glassdb kept this in its app
//  entry point; the merged product's app entry belongs to the shell, so the router moves in
//  with the capability that uses it. `IOSAppRoot` did not come with it: its job — hosting the
//  library and the deep-link handler — is the shell's now.
//

#if os(iOS)
import SwiftUI

/// Routes iPhone database work inside the primary scene while leaving iPad's `openWindow` path
/// available for native multiwindow workspaces.
@MainActor
@Observable
final class DatabaseIOSRouter {
    var workspaceRequest: DatabaseWorkspaceWindowRequest?

    func showWorkspace(_ request: DatabaseWorkspaceWindowRequest) {
        workspaceRequest = request
    }

    func showConnections() {
        workspaceRequest = nil
    }
}
#endif
