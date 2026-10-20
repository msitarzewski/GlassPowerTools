//
//  GlassLibraryEmptyState.swift
//  Glass Power Tools — GlassConnectionKit
//
//  What an empty list of hosts says. Every scope said "No Connections — Add a saved host to begin.",
//  so an empty Favorites or Recent told someone with four saved hosts to add one (seen on the iPhone
//  Duo's tour, 2026-10-18). An empty list now says what the scope holds and how something gets
//  there; only an empty library asks for a first host.
//

import Foundation

public struct GlassLibraryEmptyState: Equatable, Sendable {
    public let title: String
    public let systemImage: String
    public let message: String

    public init(title: String, systemImage: String, message: String) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
    }

    /// The empty state for a scope with nothing in it.
    /// - Parameter libraryIsEmpty: the library holds no host at all, in any scope.
    public static func of(_ scope: GlassLibraryScope, libraryIsEmpty: Bool) -> GlassLibraryEmptyState {
        if libraryIsEmpty {
            return GlassLibraryEmptyState(title: "No Connections", systemImage: "server.rack",
                                          message: "Add a saved host to begin.")
        }
        switch scope {
        case .allConnections:
            return GlassLibraryEmptyState(title: "No Connections", systemImage: "server.rack",
                                          message: "Add a saved host to begin.")
        case .favorites:
            return GlassLibraryEmptyState(title: "No Favorites", systemImage: "star",
                                          message: "Choose Add Favorite on a host to keep it here.")
        case .recent:
            return GlassLibraryEmptyState(title: "Nothing Recent", systemImage: "clock",
                                          message: "Hosts you connect to appear here.")
        case .collection:
            return GlassLibraryEmptyState(title: "No Hosts in This Collection", systemImage: "folder",
                                          message: "Edit a host and add it under Also known as & Collections.")
        }
    }
}
