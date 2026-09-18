//
//  GlassOpenFolderAsProject.swift
//  Glass Power Tools — GlassTerminal
//
//  "Open in Editor" on a folder in the Files browser.
//
//  The terminal does not import the editor and must not learn to: it owns SSH, SFTP and the trust
//  prompt, and the editor owns documents and projects. So what crosses is one closure, supplied by
//  the composition root — the only place that knows about both — carrying the two facts the editor
//  needs: which server's connection this folder was found through, and its absolute path.
//
//  The same shape as `GlassEditorRuntime.remoteReader` in the other direction, and for the same
//  reason.
//

import SwiftUI

/// Opens a folder on the machine behind `serverID` as an editor project.
public typealias GlassOpenFolderAsProject = @MainActor (_ serverID: UUID, _ path: String) -> Void

/// Opens one file on the machine behind `serverID` in the editor.
///
/// A file rather than a folder, and a tab rather than a sheet: **Edit** in the Files browser used
/// to raise a second editor of its own, which had no tabs, no project tree, no gutter and its own
/// vocabulary for "this file changed underneath you". There is one editor now.
public typealias GlassOpenFileInEditor = @MainActor (_ serverID: UUID, _ path: String) -> Void

private struct GlassOpenFolderAsProjectKey: EnvironmentKey {
    static let defaultValue: GlassOpenFolderAsProject? = nil
}

private struct GlassOpenFileInEditorKey: EnvironmentKey {
    static let defaultValue: GlassOpenFileInEditor? = nil
}

public extension EnvironmentValues {
    /// Nil when nothing can open a project — the menu item is then not offered at all, rather than
    /// offered and inert.
    var glassOpenFolderAsProject: GlassOpenFolderAsProject? {
        get { self[GlassOpenFolderAsProjectKey.self] }
        set { self[GlassOpenFolderAsProjectKey.self] = newValue }
    }

    /// Nil when no editor can take a file — then **Edit** is not offered rather than offered and
    /// inert.
    var glassOpenFileInEditor: GlassOpenFileInEditor? {
        get { self[GlassOpenFileInEditorKey.self] }
        set { self[GlassOpenFileInEditorKey.self] = newValue }
    }
}
