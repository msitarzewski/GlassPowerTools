import Foundation
import GlassConnectionKit
import GlasSecretStore
import Darwin

public enum DesktopAuthentication: String, Codable, CaseIterable, Sendable {
    case networkLevel
    case tls
}

/// Wire protocol of a saved desktop. Documents written before this field existed decode as RDP.
public enum DesktopProtocol: String, Codable, CaseIterable, Sendable {
    case rdp
    /// VNC/RFB, including Apple Screen Sharing on macOS hosts.
    case vnc

    public var defaultPort: UInt16 { self == .rdp ? 3389 : 5900 }
    public var displayName: String { self == .rdp ? "Remote Desktop (RDP)" : "Screen Sharing (VNC)" }
}

public struct DesktopConnection: Identifiable, Codable, Equatable, Sendable {
    public var id: EndpointID
    public var hostID: HostID?
    public var name: String
    public var host: String
    public var port: UInt16
    public var username: String
    public var domain: String
    public var credentialID: CredentialID
    public var mobility: SecretMobilityPolicy
    public var authentication: DesktopAuthentication
    public var tags: [String]
    public var isFavorite: Bool
    public var createdAt: Date
    public var lastConnectedAt: Date?
    public var desktop: DesktopSize
    public var clipboardEnabled: Bool
    public var audioEnabled: Bool
    public var certificateSHA256: String?
    public var `protocol`: DesktopProtocol

    /// Password-only VNC servers have no account; the shared credential store still needs one.
    public static let passwordOnlyAccount = "vnc-password"

    public init(id: EndpointID = EndpointID(), name: String = "", host: String = "", port: UInt16 = 3389,
                username: String = "", domain: String = "", credentialID: CredentialID = CredentialID(),
                protocol: DesktopProtocol = .rdp) {
        self.id = id
        self.protocol = `protocol`
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.domain = domain
        self.credentialID = credentialID
        self.mobility = .deviceOnly
        self.authentication = .networkLevel
        self.tags = []
        self.isFavorite = false
        self.createdAt = Date()
        self.desktop = .standard
        self.clipboardEnabled = false
        self.audioEnabled = false
    }

    public var address: String { host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)" }

    /// The account name stored with the credential; VNC desktops without a user name use a fixed placeholder.
    public var credentialAccountName: String {
        `protocol` == .vnc && username.isEmpty ? Self.passwordOnlyAccount : username
    }

    private enum CodingKeys: String, CodingKey {
        case id, hostID, name, host, port, username, domain, credentialID, mobility, authentication, tags, isFavorite
        case createdAt, lastConnectedAt, desktop, clipboardEnabled, audioEnabled, certificateSHA256
        case `protocol`
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(EndpointID.self, forKey: .id)
        hostID = try values.decodeIfPresent(HostID.self, forKey: .hostID)
        name = try values.decode(String.self, forKey: .name)
        host = try values.decode(String.self, forKey: .host)
        port = try values.decode(UInt16.self, forKey: .port)
        username = try values.decode(String.self, forKey: .username)
        domain = try values.decode(String.self, forKey: .domain)
        credentialID = try values.decode(CredentialID.self, forKey: .credentialID)
        mobility = try values.decode(SecretMobilityPolicy.self, forKey: .mobility)
        authentication = try values.decode(DesktopAuthentication.self, forKey: .authentication)
        tags = try values.decode([String].self, forKey: .tags)
        isFavorite = try values.decode(Bool.self, forKey: .isFavorite)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        lastConnectedAt = try values.decodeIfPresent(Date.self, forKey: .lastConnectedAt)
        desktop = try values.decode(DesktopSize.self, forKey: .desktop)
        clipboardEnabled = try values.decode(Bool.self, forKey: .clipboardEnabled)
        audioEnabled = try values.decode(Bool.self, forKey: .audioEnabled)
        certificateSHA256 = try values.decodeIfPresent(String.self, forKey: .certificateSHA256)
        `protocol` = try values.decodeIfPresent(DesktopProtocol.self, forKey: .protocol) ?? .rdp
    }

    public func validated() throws -> Self {
        var value = self
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        value.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        value.domain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.host.hasPrefix("["), value.host.hasSuffix("]") {
            value.host.removeFirst(); value.host.removeLast()
        }
        guard !value.name.isEmpty, value.name.count <= 256,
              !value.name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { throw DesktopError.invalidName }
        guard !value.host.isEmpty, value.host.count <= 255,
              !value.host.contains(where: { $0.isWhitespace || $0 == "/" || $0 == "\\" || $0 == "@" }),
              !value.host.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { throw DesktopError.invalidHost }
        if value.host.contains(":") {
            let parts = value.host.split(separator: "%", omittingEmptySubsequences: false)
            guard parts.count <= 2 else { throw DesktopError.invalidHost }
            if parts.count == 2 {
                guard !parts[1].isEmpty, parts[1].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "_.-".contains($0)) })
                else { throw DesktopError.invalidHost }
            }
            var address = in6_addr()
            guard String(parts[0]).withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else {
                throw DesktopError.invalidHost
            }
        } else if value.host.contains(where: { "[]%?#".contains($0) }) { throw DesktopError.invalidHost }
        guard port > 0 else { throw DesktopError.invalidPort }
        if value.protocol == .vnc {
            // RFB has no domains, TLS certificates or client-chosen initial sizes; keep the record canonical.
            value.domain = ""
            value.authentication = .networkLevel
            value.certificateSHA256 = nil
            value.audioEnabled = false
            guard value.username.utf8.count <= 63 else { throw DesktopError.invalidAccount }
        }
        guard value.username.count <= 255, value.domain.count <= 255,
              !value.username.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !value.domain.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { throw DesktopError.invalidAccount }
        guard createdAt.timeIntervalSinceReferenceDate.isFinite,
              lastConnectedAt.map({ $0.timeIntervalSinceReferenceDate.isFinite }) ?? true
        else { throw DesktopError.invalidDocument }
        try desktop.validate()
        let cleanedTags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard cleanedTags.count <= 64, cleanedTags.allSatisfy({ $0.count <= 64 }) else { throw DesktopError.invalidTags }
        var seen = Set<String>()
        value.tags = cleanedTags.filter { seen.insert($0.lowercased()).inserted }
        if let pin = value.certificateSHA256 {
            let normalized = pin.replacingOccurrences(of: ":", with: "").lowercased()
            guard normalized.count == 64, normalized.allSatisfy({ $0.isHexDigit && $0.isASCII }) else {
                throw DesktopError.invalidCertificate
            }
            value.certificateSHA256 = normalized
        }
        return value
    }
}

public enum DesktopError: Error, LocalizedError, Equatable, Sendable {
    case invalidName, invalidHost, invalidPort, invalidAccount, invalidTags, invalidCertificate
    case invalidDesktop, invalidDocument, unsupportedVersion(Int), duplicateConnection, missingConnection
    case storageTooLarge, invalidDestination, connectionChanged

    public var errorDescription: String? {
        switch self {
        case .invalidName: "Enter a connection name of 1–256 characters."
        case .invalidHost: "Enter a hostname or IP address, without a URL scheme or account name."
        case .invalidPort: "Enter a port from 1 to 65535."
        case .invalidAccount: "The account or domain is invalid or too long."
        case .invalidTags: "Use up to 64 collections, each no longer than 64 characters."
        case .invalidCertificate: "The certificate fingerprint must be a SHA-256 fingerprint."
        case .invalidDesktop: "Choose a desktop from 200 to 8192 pixels per side, with an even width and at most 16 million pixels."
        case .invalidDocument: "The saved connections file is invalid. It has been left unchanged."
        case .unsupportedVersion(let version): "Connection file version \(version) is not supported. It has been left unchanged."
        case .duplicateConnection: "The connections file contains duplicate identities."
        case .missingConnection: "This saved connection no longer exists."
        case .storageTooLarge: "The connections file exceeds the supported size."
        case .invalidDestination: "This Glass connection link is invalid."
        case .connectionChanged: "This connection changed while it was being edited. Reopen it and try again."
        }
    }
}
