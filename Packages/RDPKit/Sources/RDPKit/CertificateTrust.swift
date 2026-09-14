import Foundation

/// The certificate must be authorized before any CredSSP or RDP credentials are sent.
/// A pin is scoped to one endpoint and is checked even when the certificate has system trust.
public enum RDPServerCertificatePolicy: Equatable, Sendable {
    case systemTrust
    case pinned(RDPServerCertificateTrustKey)

    public func accepts(_ certificate: RDPServerCertificateInfo, host: String, port: UInt16) -> Bool {
        switch self {
        case .systemTrust:
            return certificate.trusted
        case let .pinned(pin):
            guard pin.host == host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  pin.port == port,
                  let expected = Self.digest(pin.sha256),
                  let received = Self.digest(certificate.sha256)
            else { return false }
            return expected == received
        }
    }

    private static func digest(_ text: String?) -> String? {
        guard let text else { return nil }
        let value = text.replacingOccurrences(of: ":", with: "").lowercased()
        guard value.count == 64, value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            return nil
        }
        return value
    }
}

public struct RDPServerCertificateTrustKey: Equatable, Hashable, Sendable {
    public var host: String
    public var port: UInt16
    public var sha256: String

    public init?(host: String, port: UInt16, sha256: String?) {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedHost.isEmpty == false else {
            return nil
        }

        guard let sha256 else {
            return nil
        }
        let normalizedSHA256 = sha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedSHA256.isEmpty == false else {
            return nil
        }

        self.host = normalizedHost
        self.port = port
        self.sha256 = normalizedSHA256
    }

    public var storageIdentifier: String {
        [
            host,
            String(port),
            sha256,
        ].joined(separator: "\u{1f}")
    }
}
