//
//  GlassEditorProject.swift
//  Glass Power Tools — GlassEditor
//
//  A project is a folder **on a machine**, and the machine is a host record.
//
//  This is the whole idea, and it is why a project is not simply a `URL`. The user's question was:
//  *"I'm on my Mac in the Editor, move to Vision Pro where juliet is an SSH connection — make the
//  association between the two somehow?"* The association already exists. `~/Software/thing` on
//  juliet is the same project whether you reach it through the file system because you are
//  sitting at juliet, or over SFTP because you are in a headset across the room. What changes is
//  the transport, not the project.
//
//  So a project is `(hostID, path)`. The host id is the catalog's, which means a project travels
//  between devices for free — the same D19 sync that carries machines carries these — and each
//  device decides for itself how to reach it:
//
//  - the host **is this machine** → the local file system
//  - anything else → SFTP over that host's terminal service
//
//  `GlassMachineIdentity` is what answers "is this machine", and it answers it with the SSH host
//  key rather than a hostname or an address, because a name can be anything and a key cannot.
//

import Foundation
import GlassConnectionKit

/// A folder opened as a project, on a named machine.
public struct GlassEditorProject: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    /// The machine the folder lives on, as the catalog knows it. Nil means *this device* for a
    /// project that was opened before any machine was involved — a plain local folder.
    public var hostID: HostID?
    /// Absolute path on that machine. A path, not a `URL`: a remote root has no file URL, and
    /// storing one would make the local case look privileged when it is just the common case.
    public var path: String
    /// What the user called it; defaults to the folder's own name.
    public var displayName: String
    public var openedAt: Date
    /// What this project says about the text, where it disagrees with the app's defaults. Nil is
    /// the ordinary case: it follows Settings ▸ Editor and changes when that does
    /// (`GlassEditorTextOverrides`). Travels with the record, so a project reads the same on the
    /// phone.
    public var textOverrides: GlassEditorTextOverrides?

    public init(id: UUID = UUID(), hostID: HostID? = nil, path: String,
                displayName: String? = nil, openedAt: Date = Date(),
                textOverrides: GlassEditorTextOverrides? = nil) {
        self.id = id
        self.hostID = hostID
        self.textOverrides = textOverrides
        // No trailing slash, ever. `URL.path` on a directory keeps one, and a root spelled
        // "/work/thing/" is not a prefix of "/work/thing/main.swift" by any string comparison —
        // which is how "is this file in this project?" gets the wrong answer.
        self.path = Self.normalized(path)
        self.displayName = displayName ?? (Self.normalized(path) as NSString).lastPathComponent
        self.openedAt = openedAt
    }

    public static func normalized(_ path: String) -> String {
        guard path.count > 1, path.hasSuffix("/") else { return path }
        return String(path.reversed().drop { $0 == "/" }.reversed())
    }

    /// A project rooted at a local folder on this device.
    public static func local(_ url: URL, hostID: HostID? = nil) -> GlassEditorProject {
        GlassEditorProject(hostID: hostID, path: url.standardizedFileURL.path(percentEncoded: false))
    }

    /// The root as a file URL — only meaningful on the device the folder is actually on.
    public var localURL: URL { URL(filePath: path, directoryHint: .isDirectory) }
}

/// How a project's files are being reached on *this* device, which is what the badge says.
public enum GlassEditorProjectReach: Sendable, Hashable {
    /// The folder is on this machine; the file system is the transport.
    case thisMachine
    /// The folder is on another machine, reached over that host's terminal service.
    case overSSH(host: String)
    /// The machine is known but has no way in from here — no terminal service on the record.
    case unreachable(host: String)

    public var badge: String {
        switch self {
        case .thisMachine: "On this Mac"
        case .overSSH(let host): "Over SSH · \(host)"
        case .unreachable(let host): "\(host) — no terminal service"
        }
    }

    public var symbolName: String {
        switch self {
        case .thisMachine: "internaldrive"
        case .overSSH: "network"
        case .unreachable: "exclamationmark.triangle"
        }
    }
}

// MARK: - The tree

/// One entry in a project's tree. Folders are loaded on demand: a project root can be a checkout
/// with a hundred thousand files in it, and reading all of them to draw a sidebar is how an editor
/// earns a beachball on open.
@MainActor @Observable
public final class GlassEditorProjectNode: Identifiable {
    public let id = UUID()
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public private(set) var children: [GlassEditorProjectNode]?
    public private(set) var loadError: String?
    /// A read is in flight. On a disk this is over before a frame draws; over SSH it is a folder
    /// listing crossing a network, and the tree says so rather than looking empty.
    public private(set) var isLoading = false

    public init(name: String, path: String, isDirectory: Bool) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
    }

    /// Reads this folder's contents once. Idempotent: a folder already read is left alone, so
    /// expanding, collapsing and expanding again does not re-scan, and a read already in flight is
    /// not started twice — over a network the second one would be a second round trip for an
    /// answer already on its way.
    public func loadChildrenIfNeeded(using access: any GlassEditorFileAccess) async {
        guard isDirectory, children == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            children = try await access.contents(ofDirectory: path)
        } catch {
            children = []
            loadError = error.localizedDescription
        }
    }

    /// The same read, for a caller that cannot await — a SwiftUI `Binding`'s setter, which is what
    /// a disclosure triangle is. The view observes `children` and `isLoading`, so it redraws when
    /// the answer lands.
    public func beginLoadingChildrenIfNeeded(using access: any GlassEditorFileAccess) {
        Task { await loadChildrenIfNeeded(using: access) }
    }

    /// What `OutlineGroup` asks for: nil for a leaf, so it draws no disclosure triangle, and the
    /// children once a folder has been read. A folder that has not been expanded yet reports an
    /// empty array rather than nil, so the triangle is there to expand.
    public var loadedChildren: [GlassEditorProjectNode]? {
        guard isDirectory else { return nil }
        return children ?? []
    }

    /// Forgets what was read, so the next expansion sees the folder as it is now.
    public func invalidate() {
        children = nil
        loadError = nil
    }
}

/// One entry as a listing found it, before it is a node. The two file accesses differ in how they
/// *get* this list and in nothing else, so everything that happens to it afterwards — the
/// machinery folders nobody wants to see, the path rule, the sort order — is written once below.
public struct GlassEditorDirectoryEntry: Sendable, Hashable {
    public var name: String
    public var isDirectory: Bool

    public init(name: String, isDirectory: Bool) {
        self.name = name
        self.isDirectory = isDirectory
    }
}

@MainActor
public extension GlassEditorProject {
    /// Entries a project view has no business showing by default. Not a general "hidden files"
    /// rule — `.env` and `.gitignore` are the sort of file people open all day — just the ones
    /// that are machinery.
    static let skippedNames: Set<String> = [".git", ".build", ".DS_Store", "node_modules",
                                            ".swiftpm", "DerivedData"]

    /// Turns a listing into the tree's nodes.
    ///
    /// **A child's path is its parent's path plus its name — built here, not read back.**
    /// `contentsOfDirectory` answers in whatever spelling the platform prefers: ask it about
    /// `/var/folders/…/T/thing` and it returns `/private/var/folders/…/T/thing/README.md`. Both
    /// are the same file and neither is wrong, but a tree whose children do not share their
    /// parent's prefix cannot answer "which folder is this file in?", and the answer to that is
    /// where a new file goes. An SFTP server is free to answer in its own spelling too, so the
    /// rule belongs to the editor, not to the file system.
    static func nodes(in parentPath: String,
                      from entries: [GlassEditorDirectoryEntry]) -> [GlassEditorProjectNode] {
        let base = normalized(parentPath)
        return entries
            .filter { !skippedNames.contains($0.name) }
            .map {
                GlassEditorProjectNode(name: $0.name,
                                       path: base + "/" + $0.name,
                                       isDirectory: $0.isDirectory)
            }
            // Folders first, then by name, case-insensitively — the order every file browser on
            // this platform uses, and the one a user's eye is already trained on.
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }
}
