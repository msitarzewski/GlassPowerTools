//
//  GlassEditorSecurityScope.swift
//  Glass Power Tools — GlassEditor
//
//  Asking for, and giving back, access to a file or folder the user picked.
//
//  A folder chosen from Files on an iPad or a headset arrives **security-scoped**: nothing in it
//  can be read until access is asked for, and it stops being readable the moment access is given
//  back. The Projects panel gave it back straight away while the tree was still loading, so the
//  folder opened empty. A project holds its access for as long as it is open now, and this is the
//  seam that lets a test count the asking and the giving back, which no real URL in a test run
//  ever needs.
//

import Foundation

@MainActor
public struct GlassEditorSecurityScope {
    /// True when access was granted and has to be given back; false for a URL that needs none.
    public var start: (URL) -> Bool
    public var stop: (URL) -> Void

    public init(start: @escaping (URL) -> Bool, stop: @escaping (URL) -> Void) {
        self.start = start
        self.stop = stop
    }

    /// The system's own calls.
    public static let system = GlassEditorSecurityScope(
        start: { $0.startAccessingSecurityScopedResource() },
        stop: { $0.stopAccessingSecurityScopedResource() }
    )

    /// Runs `body` with access held, and gives it back afterwards whatever happened.
    func withAccess<Result>(to url: URL, _ body: (_ scoped: Bool) -> Result) -> Result {
        let scoped = start(url)
        defer { if scoped { stop(url) } }
        return body(scoped)
    }

    /// Whether this is a folder on this device, asked with the access a picked folder needs.
    func isFolder(_ url: URL) -> Bool {
        withAccess(to: url) { _ in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path(percentEncoded: false),
                                                  isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }
}
