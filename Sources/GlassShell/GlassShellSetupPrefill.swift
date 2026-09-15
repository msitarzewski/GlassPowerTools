//
//  GlassShellSetupPrefill.swift
//  Glass Power Tools — GlassShell
//
//  Opening the host sheet with a machine already filled in, for importing from another tool.
//
//  The shape follows what glassDT did with `.rdp` files and is worth keeping deliberately: a parsed
//  file is **a draft to review, never a saved connection**. Passwords are not imported, and a file
//  can say things the app cannot honour exactly (a resolution it has to fit, an audio mode it does
//  not have), so the user has to see the result before it becomes a machine in their library.
//  Importing straight to saved would hide both of those.
//
//  This rides on `.addHost` rather than adding a mode of its own, because "a new machine with one
//  service on it" is exactly what `.addHost` already means — and it means the import inherits the
//  host record and service link for free, which is D27.
//

import Foundation
import GlassConnectionKit

/// A machine parsed from somewhere else, ready for the user to look over and save.
public struct GlassShellSetupPrefill: Identifiable, Sendable {
    /// New per import, so presenting the same file twice re-opens the sheet.
    public let id = UUID()
    public let kind: HostServiceKind
    public let hostName: String
    public let address: String
    /// The capability's own encoded record. Opaque here; `setupDraft(importing:)` decodes it.
    public let configuration: Data
    /// What the source file asked for that this app will not do, in the user's words. Shown in the
    /// sheet, where the decision is, rather than in an alert that precedes it.
    public let notices: [String]

    public init(kind: HostServiceKind, hostName: String, address: String,
                configuration: Data, notices: [String] = []) {
        self.kind = kind
        self.hostName = hostName
        self.address = address
        self.configuration = configuration
        self.notices = notices
    }
}
