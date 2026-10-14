//
//  DesktopServiceDraft.swift
//  Glass Power Tools — GlassDesktop
//
//  The desktop's side of the shell's one-and-done setup sheet. Holds everything needed to create
//  or update one desktop service, and nothing the host owns: no address, ever — the shell passes
//  it in at commit.
//
//  Shaped after `Sources/GlassDatabase/DatabaseServiceDraft.swift`: the same touched-field and
//  attempted-save reveal, and the same rule that a service is created complete, configuration and
//  credential together.
//
//  The protocol picker is the thing that makes this capability serve two: RDP and VNC/Screen
//  Sharing are one service kind with a field, exactly as glassDT modelled them, so the shell's
//  catalog needs no fourth `HostServiceKind` and nothing here is a schema change.
//

import SwiftUI
import GlassShell
import GlassConnectionKit
import GlasSecretStore

@MainActor @Observable
final class DesktopServiceDraft: GlassServiceDraft {
    enum Field: String, Hashable, Sendable {
        case name, username, password, port, domain, desktopWidth, desktopHeight
    }

    /// The order issues are reported and focus is moved in.
    static let orderedFields: [Field] = [.name, .username, .password, .port, .domain,
                                         .desktopWidth, .desktopHeight]

    let kind: HostServiceKind = .rdp

    /// The saved desktop being edited; nil for a new one.
    let editing: DesktopConnection?
    private let app: DesktopAppModel

    // MARK: Required

    /// Spelled out rather than borrowing the keyword: the @Observable macro cannot generate
    /// storage for a backtick-escaped property name. The saved record keeps the keyword spelling,
    /// because that one is a Codable key and renaming it would orphan every stored desktop.
    var desktopProtocol: DesktopProtocol
    var username: String
    var password = ""

    // MARK: Advanced

    /// Optional: the shell derives a default from the host when it is left blank.
    var name: String
    /// Empty means "follow the protocol", which is what a user almost always wants.
    var portText: String
    var domain: String
    var authentication: DesktopAuthentication
    var desktopWidthText: String
    var desktopHeightText: String
    var clipboardEnabled: Bool
    var audioEnabled: Bool
    var graphicsMode: DesktopGraphicsMode
    var mobility: SecretMobilityPolicy

    // MARK: Reveal

    private var touched: Set<Field> = []
    private var attemptedSave = false
    var focusRequest: Field?

    init(app: DesktopAppModel) {
        self.app = app
        editing = nil
        desktopProtocol = .rdp
        username = ""
        name = ""
        portText = ""
        domain = ""
        authentication = .networkLevel
        desktopWidthText = String(DesktopSize.standard.width)
        desktopHeightText = String(DesktopSize.standard.height)
        clipboardEnabled = false
        audioEnabled = false
        graphicsMode = .automatic
        // D18: this project's credentials synchronize by default. glassDT defaulted a desktop to
        // `.deviceOnly`; following it here would have silently contradicted the decision that
        // Stage 3.5 made precisely so the third credential kind would arrive settled.
        mobility = .iCloudKeychain
    }

    init(editing connection: DesktopConnection, app: DesktopAppModel) {
        self.app = app
        editing = connection
        desktopProtocol = connection.protocol
        username = connection.username
        name = connection.name
        portText = String(connection.port)
        domain = connection.domain
        authentication = connection.authentication
        desktopWidthText = String(connection.desktop.width)
        desktopHeightText = String(connection.desktop.height)
        clipboardEnabled = connection.clipboardEnabled
        audioEnabled = connection.audioEnabled
        graphicsMode = connection.graphicsMode
        mobility = connection.mobility
    }

    // MARK: Naming

    func serviceDisplayName(hostName: String) -> String {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        return hostName
    }

    /// The port actually committed: what was typed, or the protocol's own default.
    var resolvedPort: UInt16 {
        let typed = portText.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty { return desktopProtocol.defaultPort }
        return UInt16(typed) ?? desktopProtocol.defaultPort
    }

    /// Moving the picker moves an untouched port with it, the way glassDT's editor did, so the
    /// common case needs no typing and a deliberate port is never overwritten.
    func protocolDidChange() {
        guard !touched.contains(.port) else { return }
        portText = ""
    }

    /// RDP-only fields are hidden rather than disabled for VNC: a domain or an NLA choice has no
    /// meaning in RFB, and showing dead controls is what the parity checklist warns against.
    var showsRDPOnlyFields: Bool { desktopProtocol == .rdp }

    /// A Screen Sharing session with a Mac user name: a Mac is answered in its own revision and
    /// encrypted after sign-in (e7463ce). A password alone, or a server that is not a Mac, protects
    /// the password at sign-in and nothing after it.
    var vncSignsInWithMacAccount: Bool {
        desktopProtocol == .vnc && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Validation

    func validate(address: String) -> [GlassSetupIssue] {
        var issues: [GlassSetupIssue] = []
        let typedPort = portText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typedPort.isEmpty, UInt16(typedPort).map({ $0 == 0 }) ?? true {
            issues.append(GlassSetupIssue(field: Field.port.rawValue,
                                          message: "Enter a port between 1 and 65535, or leave it blank for \(desktopProtocol.defaultPort)."))
        }
        // RDP needs an account; a VNC server may be password-only, which is why the record has a
        // placeholder account name for exactly that case.
        if desktopProtocol == .rdp, username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(GlassSetupIssue(field: Field.username.rawValue,
                                          message: "Enter the account to sign in with."))
        }
        if desktopProtocol == .vnc, username.utf8.count > 63 {
            issues.append(GlassSetupIssue(field: Field.username.rawValue,
                                          message: "A Screen Sharing user name can be at most 63 characters."))
        }
        if editing == nil, password.isEmpty {
            issues.append(GlassSetupIssue(field: Field.password.rawValue,
                                          message: "Enter the password for this desktop."))
        }
        if let size = typedDesktopSize() {
            do { try size.validate() } catch {
                issues.append(GlassSetupIssue(field: Field.desktopWidth.rawValue,
                                              message: "Enter a size between 200 and 8192, with an even width."))
            }
        } else {
            issues.append(GlassSetupIssue(field: Field.desktopWidth.rawValue,
                                          message: "Enter a desktop size in pixels."))
        }
        // The address belongs to the host, so this validates only that it can be committed.
        if address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(GlassSetupIssue(field: Field.name.rawValue,
                                          message: "This machine needs an address before a desktop can be added."))
        }
        return issues
    }

    private func typedDesktopSize() -> DesktopSize? {
        guard let width = Int(desktopWidthText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let height = Int(desktopHeightText.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return DesktopSize(width: width, height: height)
    }

    /// Issues keyed by field, for the row views. Mirrors `DatabaseServiceDraft.issues`.
    func issues(address: String) -> [Field: String] {
        var byField: [Field: String] = [:]
        for issue in validate(address: address) {
            guard let field = Field(rawValue: issue.field) else { continue }
            byField[field] = issue.message
        }
        return byField
    }

    /// The message to show for a field, or nil while it is still unrevealed. A message appears
    /// once the user has touched the field or tried to save — never the moment the sheet opens.
    func message(for field: Field, in issues: [Field: String]) -> String? {
        guard shouldReveal(field) else { return nil }
        return issues[field]
    }

    // MARK: The sheet's rows

    func requiredFields() -> AnyView { AnyView(DesktopRequiredFields(draft: self)) }
    func advancedFields() -> AnyView { AnyView(DesktopAdvancedFields(draft: self)) }

    func focusFirstIssue(_ issues: [GlassSetupIssue]) {
        attemptedSave = true
        guard let first = issues.first,
              let field = Field(rawValue: first.field) else { return }
        focusRequest = field
    }

    func shouldReveal(_ field: Field) -> Bool { attemptedSave || touched.contains(field) }
    func markTouched(_ field: Field) { touched.insert(field) }

    // MARK: Commit

    func commit(endpointID: EndpointID, host: HostProfile, address: String) async throws {
        var connection = editing ?? DesktopConnection(id: endpointID, protocol: desktopProtocol)
        connection.id = endpointID
        connection.hostID = host.id
        connection.protocol = desktopProtocol
        connection.name = serviceDisplayName(hostName: host.displayName)
        connection.host = address
        connection.port = resolvedPort
        connection.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        // Written through as typed. `DesktopConnection.validated()` owns what a VNC record may
        // hold — it clears the domain, the authentication mode, the pin and audio for RFB
        // (`DesktopConnection.swift:131-137`) — and re-stating that rule here would give the
        // invariant two owners that could disagree. The fields are hidden for VNC so a user
        // cannot type into them anyway; the record is what guarantees it.
        connection.domain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        connection.authentication = authentication
        connection.desktop = typedDesktopSize() ?? .standard
        connection.clipboardEnabled = clipboardEnabled
        connection.audioEnabled = audioEnabled
        connection.graphicsMode = graphicsMode
        connection.mobility = mobility
        try await app.save(connection, password: password.isEmpty ? nil : password)
    }

    func rollback(endpointID: EndpointID) async {
        guard editing == nil, let created = app.connections.first(where: { $0.id == endpointID }) else { return }
        await app.delete(created)
    }
}
