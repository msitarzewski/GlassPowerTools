//
//  GlassPathHeader.swift
//  Glass Power Tools — GlassConnectionUI
//
//  Where you are, at the top of a file browser: the folder's name, and the path that leads to it.
//
//  `SFTPBrowserView` used to put the whole path in `.navigationTitle`, which reads as a string of
//  text rather than a place — and the editor's file list had no header at all. Both are file
//  browsers over the same kind of thing, so they share one header rather than growing two.
//
//  The shape, reported 2026-09-18:
//
//  - **The current folder's name, large.** `sensor`, not `/home/ann/projects/sensor`.
//  - **The path that leads to it beneath**, across the whole width, smaller and secondary, without
//    the current folder repeated — `/home/ann/projects`.
//  - **Truncated from the front** when it will not fit: `…/ann/projects`. The end of a path is
//    the part that locates you; the beginning is the part you can infer.
//

import SwiftUI

/// A path split into the two facts a header shows. Separate from the view so the splitting is
/// testable without rendering anything, and so both browsers agree about what a path means.
public struct GlassPathLocation: Equatable, Sendable {
    /// The folder itself. `/` for the root, which has no name of its own.
    public let name: String
    /// What leads to it, without the folder repeated. Empty at the root.
    public let parent: String

    /// `~` for the user's home directory, because a header is not the place to read someone's
    /// user name back to them — nor, on a simulator, a container UUID.
    ///
    /// Lives here rather than in the editor, which had the only copy: the Files browser wants the
    /// same spelling, and the copy dropped one character too many (`~F/Documents`, photographed
    /// 2026-09-18) because it kept the last character of home instead of the separator after it.
    public static func abbreviatingHome(_ path: String, home: String = NSHomeDirectory()) -> String {
        guard !home.isEmpty, path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    public init(path: String, separator: Character = "/") {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        // A trailing separator is the same folder written differently — `/home/ann/` names
        // `ann`, not an unnamed folder inside it.
        var body = trimmed
        while body.count > 1, body.last == separator { body.removeLast() }

        guard body != String(separator), !body.isEmpty else {
            self.name = String(separator)
            self.parent = ""
            return
        }

        guard let index = body.lastIndex(of: separator) else {
            // A relative path with one component: the name is all there is.
            self.name = body
            self.parent = ""
            return
        }
        self.name = String(body[body.index(after: index)...])
        let lead = String(body[body.startIndex..<index])
        // The root's children hang off `/`, which is a parent worth showing.
        self.parent = lead.isEmpty ? String(separator) : lead
    }
}

/// The header itself. Used through `glassPathHeader(_:)` rather than placed by hand, so both
/// browsers get the same navigation title with it.
public struct GlassPathHeader: View {
    private let location: GlassPathLocation

    public init(location: GlassPathLocation) {
        self.location = location
    }

    public init(path: String) {
        self.init(location: GlassPathLocation(path: path))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(location.name)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                // A name is short and its middle is the part nobody needs; only a very long one
                // ever truncates at all.
                .truncationMode(.middle)
            if !location.parent.isEmpty {
                Text(location.parent)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        // One thing to a screen reader — "sensor, in /home/ann/projects" — rather than two
        // unrelated labels, one of which is a path read character by character.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(location.parent.isEmpty
                            ? location.name
                            : "\(location.name), in \(location.parent)")
        .accessibilityIdentifier("glass-path-header")
    }
}

private struct GlassPathHeaderModifier: ViewModifier {
    let location: GlassPathLocation

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    GlassPathHeader(location: location)
                    Divider()
                }
                // The same surface the editor's status bar sits on. A pinned header with no
                // surface has the list scrolling through it.
                .background(.bar)
            }
            // **On a Mac only.** A window needs a title, and the folder's name is a better one
            // than the whole path was. On a phone and in the headset the navigation bar sits
            // directly above this header, so a title there is the same word twice, half an inch
            // apart — photographed on the first run of this change.
            #if os(macOS)
            .navigationTitle(location.name)
            #endif
    }
}

public extension View {
    /// Puts the shared "where you are" header above this view and titles it with the folder.
    func glassPathHeader(_ path: String) -> some View {
        modifier(GlassPathHeaderModifier(location: GlassPathLocation(path: path)))
    }

    /// The same, for a caller that has already worked out how to spell the path — the editor
    /// abbreviates a home directory to `~` before it gets here.
    func glassPathHeader(location: GlassPathLocation) -> some View {
        modifier(GlassPathHeaderModifier(location: location))
    }
}
