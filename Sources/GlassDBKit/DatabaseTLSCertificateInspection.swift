//
//  DatabaseTLSCertificateInspection.swift
//  Glass Power Tools — GlassDBKit
//
//  Reads a user-supplied trust root well enough for a person to decide whether to trust it,
//  and rejects a file that is not one before it can be saved against a service.
//
//  It lives in the engine because the engine owns NIOSSL: `GlassDatabase` does not depend on
//  swift-nio-ssl (`Package.swift:130-140`) and adding that edge to show a fingerprint would put
//  certificate parsing in two modules.
//

import CryptoKit
import Foundation
import NIOSSL

/// What can be said about supplied certificate material without contacting anything.
public struct DatabaseTLSCertificateInspection: Sendable, Hashable {
    /// One entry per certificate found, in file order. The first is the one a single-certificate
    /// CA file contains; a chain file contains several and every one becomes a trust root.
    public let certificates: [Certificate]

    public struct Certificate: Sendable, Hashable {
        /// SHA-256 over the DER encoding, uppercase hex in colon-separated pairs — what
        /// `openssl x509 -fingerprint -sha256` prints, so a user can compare the two strings
        /// character for character. Deliberately **not** the `SHA256:<base64>` form the terminal
        /// shows for SSH host keys: that is OpenSSH's presentation, and this is compared against
        /// OpenSSL's.
        public let fingerprintSHA256: String
        public let notValidBefore: Date
        public let notValidAfter: Date

        public func isExpired(asOf now: Date = Date()) -> Bool { now > notValidAfter }
        public func isNotYetValid(asOf now: Date = Date()) -> Bool { now < notValidBefore }
    }

    public var count: Int { certificates.count }

    /// True when every certificate in the file is outside its validity window in the same
    /// direction; a chain with one expired intermediate is still reported per certificate.
    public func expiredCertificates(asOf now: Date = Date()) -> [Certificate] {
        certificates.filter { $0.isExpired(asOf: now) || $0.isNotYetValid(asOf: now) }
    }
}

extension DatabaseTLSCertificate {
    /// Parses this material and describes it. Throws `DatabaseError.invalidTLSCertificate` for
    /// anything that is not a certificate — the same error the connect path throws, so a file
    /// that fails here could never have connected either.
    public func inspect() throws -> DatabaseTLSCertificateInspection {
        let parsed: [NIOSSLCertificate]
        do {
            switch format {
            case .pem:
                parsed = try NIOSSLCertificate.fromPEMBytes(Array(bytes))
            case .der:
                parsed = [try NIOSSLCertificate(bytes: Array(bytes), format: .der)]
            }
        } catch {
            throw DatabaseError.invalidTLSCertificate(error.localizedDescription)
        }
        guard !parsed.isEmpty else {
            throw DatabaseError.invalidTLSCertificate("No certificates were found in the supplied data.")
        }
        return DatabaseTLSCertificateInspection(
            certificates: try parsed.map { certificate in
                let der: [UInt8]
                do { der = try certificate.toDERBytes() } catch {
                    throw DatabaseError.invalidTLSCertificate(error.localizedDescription)
                }
                return .init(
                    fingerprintSHA256: Self.hexFingerprint(ofDER: der),
                    notValidBefore: Date(timeIntervalSince1970: TimeInterval(certificate.notValidBefore)),
                    notValidAfter: Date(timeIntervalSince1970: TimeInterval(certificate.notValidAfter))
                )
            }
        )
    }

    static func hexFingerprint(ofDER der: [UInt8]) -> String {
        SHA256.hash(data: der)
            .map { String(format: "%02X", $0) }
            .joined(separator: ":")
    }
}
