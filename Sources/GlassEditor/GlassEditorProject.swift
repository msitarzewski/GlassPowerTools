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

    public init(id: UUID = UUID(), hostID: HostID? = nil, path: String,
                displayName: String? = nil, openedAt: Date = Date()) {
        self.id = id
        self.hostID = hostID
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

    public init(name: String, path: String, isDirectory: Bool) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
    }

    /// Reads this folder's contents once. Idempotent: a folder already read is left alone, so
    /// expanding, collapsing and expanding again does not re-scan.
    public func loadChildrenIfNeeded(using reader: GlassEditorDirectoryReader) {
        guard isDirectory, children == nil else { return }
        do {
            children = try reader.contents(ofDirectory: path)
        } catch {
            children = []
            loadError = error.localizedDescription
        }
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

/// Where a project's directory listings come from. One protocol so the tree does not know whether
/// it is reading a disk or an SSH connection — and so the tree can be tested without either.
@MainActor
public protocol GlassEditorDirectoryReader {
    func contents(ofDirectory path: String) throws -> [GlassEditorProjectNode]
}

/// This device's file system.
@MainActor
public struct GlassEditorLocalDirectoryReader: GlassEditorDirectoryReader {
    /// Entries a project view has no business showing by default. Not a general "hidden files"
    /// rule — `.env` and `.gitignore` are the sort of file people open all day — just the ones
    /// that are machinery.
    public static let skipped: Set<String> = [".git", ".build", ".DS_Store", "node_modules",
                                              ".swiftpm", "DerivedData"]

    public init() {}

    public func contents(ofDirectory path: String) throws -> [GlassEditorProjectNode] {
        // **A child's path is its parent's path plus its name — built here, not read back.**
        //
        // `contentsOfDirectory` answers in whatever spelling the platform prefers: ask it about
        // `/var/folders/…/T/thing` and it returns `/private/var/folders/…/T/thing/README.md`. Both
        // are the same file and neither is wrong, but a tree whose children do not share their
        // parent's prefix cannot answer "which folder is this file in?", and the answer to that is
        // where a new file goes. So the parent's own spelling is carried down the tree.
        let base = GlassEditorProject.normalized(path)
        let url = URL(filePath: base, directoryHint: .isDirectory)
        let entries = try FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        return entries
            .filter { !Self.skipped.contains($0.lastPathComponent) }
            .map { entry in
                let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return GlassEditorProjectNode(name: entry.lastPathComponent,
                                              path: base + "/" + entry.lastPathComponent,
                                              isDirectory: isDirectory)
            }
            // Folders first, then by name, case-insensitively — the order every file browser on
            // this platform uses, and the one a user's eye is already trained on.
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }
}
